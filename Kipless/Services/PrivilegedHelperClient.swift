import Foundation
import ServiceManagement

enum PrivilegedHelperClientError: LocalizedError, Sendable {
    case helperApprovalRequired
    case helperUnavailable(String)
    case helperNotResponding
    case remoteFailure(String)
    case unknownState(Int)

    var message: String {
        switch self {
        case .helperApprovalRequired:
            String(localized: LocalizedStringResource.permissionClosedLidApprovalMessage)
        case .helperNotResponding:
            "The privileged helper did not respond, so Closed Lid could not start"
        case let .helperUnavailable(message), let .remoteFailure(message): message
        case let .unknownState(code): "Helper returned an unknown SleepDisabled state (\(code))"
        }
    }

    /// Whether the failure is the user's to resolve by approving the helper.
    /// The Popover answers this with a dialog instead of a status row.
    var requiresUserApproval: Bool {
        if case .helperApprovalRequired = self { return true }
        return false
    }

    var errorDescription: String? { message }
}

/// The narrow privileged capability used only by the Closed Lid wake mode.
/// Keeping this interface separate from the UI makes the helper lease a
/// Session backend rather than an independently toggled setting.
protocol LidSleepOverrideClient: AnyObject, Sendable {
    func acquireLidSleepOverride() async throws
    func releaseLidSleepOverride() async throws
    func helperApprovalIsRequired() -> Bool
    func invalidate()
}

/// Client-side facade for the constrained privileged helper.
///
/// The injected initializer is used by unit tests. The production initializer
/// registers the bundled LaunchDaemon through SMAppService and connects to its
/// fixed Mach service; it never accepts arbitrary commands or arguments.
final class PrivilegedHelperClient: @unchecked Sendable {
    private static let daemonPlistName = "com.kaoru.kipless.lidsleep.plist"
    private static let machServiceName = "com.kaoru.kipless.lidsleep"

    private let lock = NSLock()
    private var connection: NSXPCConnection?
    private var remoteObject: KiplessSleepHelperProtocol?
    private let injectedRemote: KiplessSleepHelperProtocol?
    /// How long a helper request may stay unanswered. launchd accepts a Mach
    /// message for a daemon it then refuses to run, and such a request is never
    /// answered and never fails on its own, so waiting has to end somewhere.
    ///
    /// A working helper answers in milliseconds, so this is only ever paid on a
    /// broken one — and the Popover is unresponsive while it is paid.
    static let defaultRequestTimeout: Duration = .seconds(3)

    private let statusProvider: @Sendable () -> SMAppService.Status
    private let requestTimeout: Duration
    private let repairRegistration: @Sendable () async -> Void
    private var hasAttemptedRegistrationRepair = false
    private var pendingRequestFailures: [UUID: @Sendable (PrivilegedHelperClientError) -> Void] = [:]

    init(
        requestTimeout: Duration = PrivilegedHelperClient.defaultRequestTimeout,
        repairRegistration: @escaping @Sendable () async -> Void =
            PrivilegedHelperClient.rebuildRegistration
    ) {
        injectedRemote = nil
        self.requestTimeout = requestTimeout
        self.repairRegistration = repairRegistration
        statusProvider = {
            SMAppService.daemon(plistName: Self.daemonPlistName).status
        }
    }

    init(
        remote: KiplessSleepHelperProtocol,
        requestTimeout: Duration = PrivilegedHelperClient.defaultRequestTimeout,
        repairRegistration: @escaping @Sendable () async -> Void =
            PrivilegedHelperClient.rebuildRegistration
    ) {
        injectedRemote = remote
        remoteObject = remote
        self.requestTimeout = requestTimeout
        self.repairRegistration = repairRegistration
        statusProvider = { .enabled }
    }

    init(
        statusProvider: @escaping @Sendable () -> SMAppService.Status,
        requestTimeout: Duration = PrivilegedHelperClient.defaultRequestTimeout,
        repairRegistration: @escaping @Sendable () async -> Void =
            PrivilegedHelperClient.rebuildRegistration
    ) {
        injectedRemote = nil
        self.requestTimeout = requestTimeout
        self.repairRegistration = repairRegistration
        self.statusProvider = statusProvider
    }

    /// Drops the daemon registration and registers it again, so the system
    /// recomputes the requirement it enforces when launching the helper.
    static func rebuildRegistration() async {
        let service = SMAppService.daemon(plistName: daemonPlistName)
        try? await service.unregister()
        try? await service.register()
    }

    func connect() throws {
        _ = try remoteForRequest()
    }

    func getSleepOverrideState() async throws -> SleepOverrideSystemState {
        let remote = try remoteForRequest()

        return try await withCheckedThrowingContinuation { continuation in
            let requestID = UUID()
            let completion = OnceCompletion(continuation) { [weak self] in
                self?.removePendingRequest(requestID)
            }
            registerPendingRequest(requestID) { error in
                completion.fail(error)
            }
            scheduleRequestTimeout(requestID)

            guard let requestRemote = remoteProxy(
                fallback: remote,
                errorHandler: { error in
                    completion.fail(.remoteFailure(error.localizedDescription))
                }
            ) else { return }
            requestRemote.getState { stateCode, message in
                if let message {
                    completion.fail(.remoteFailure(message))
                    return
                }

                guard let state = SleepOverrideSystemState(rawValue: stateCode), state != .unknown else {
                    completion.fail(.unknownState(stateCode))
                    return
                }
                completion.succeed(state)
            }
        }
    }

    func enableSleepOverride() async throws {
        try await performOperation { remote, reply in
            remote.acquireSleepOverride(withReply: reply)
        }
    }

    func disableSleepOverride() async throws {
        try await performOperation { remote, reply in
            remote.releaseSleepOverride(withReply: reply)
        }
    }

    func invalidate() {
        lock.lock()
        let connection = self.connection
        self.connection = nil
        self.remoteObject = injectedRemote
        lock.unlock()

        connection?.invalidate()
        failPendingRequests(
            with: .remoteFailure("The privileged helper connection was invalidated")
        )
    }

    func helperApprovalIsRequired() -> Bool {
        statusProvider() == .requiresApproval
    }

    /// A helper that is registered but never answers is one the system refuses
    /// to launch — its recorded launch requirement can go stale, for example
    /// after the app bundle is replaced. Rebuilding the registration is the only
    /// way out, and the rebuilt one needs the user's approval, so this reports
    /// whether the caller should ask for it.
    private func repairRegistrationIfNeeded(
        after error: PrivilegedHelperClientError
    ) async -> Bool {
        guard case .helperNotResponding = error else { return false }
        guard statusProvider() == .enabled else { return false }
        guard claimRegistrationRepair() else { return false }

        invalidate()
        await repairRegistration()
        return true
    }

    /// Claims the one rebuild allowed per run. Kept synchronous so the flag
    /// cannot change across a suspension point.
    private func claimRegistrationRepair() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard !hasAttemptedRegistrationRepair else { return false }
        hasAttemptedRegistrationRepair = true
        return true
    }

    private func performOperation(
        _ invoke: @escaping (
            KiplessSleepHelperProtocol,
            @escaping (Bool, String?) -> Void
        ) -> Void
    ) async throws {
        let remote = try remoteForRequest()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let requestID = UUID()
            let completion = OnceCompletion(continuation) { [weak self] in
                self?.removePendingRequest(requestID)
            }
            registerPendingRequest(requestID) { error in
                completion.fail(error)
            }
            scheduleRequestTimeout(requestID)

            guard let requestRemote = remoteProxy(
                fallback: remote,
                errorHandler: { error in
                    completion.fail(.remoteFailure(error.localizedDescription))
                }
            ) else { return }
            invoke(requestRemote) { success, message in
                guard success else {
                    completion.fail(
                        .remoteFailure(message ?? "The privileged helper rejected the operation")
                    )
                    return
                }
                completion.succeed(())
            }
        }
    }

    private func remoteForRequest() throws -> KiplessSleepHelperProtocol {
        lock.lock()
        let cachedRemote = remoteObject ?? injectedRemote
        lock.unlock()

        if let cachedRemote { return cachedRemote }

        do {
            let service = SMAppService.daemon(plistName: Self.daemonPlistName)
            switch statusProvider() {
            case .enabled:
                break
            case .requiresApproval:
                throw PrivilegedHelperClientError.helperApprovalRequired
            case .notRegistered, .notFound:
                try service.register()
            @unknown default:
                try service.register()
            }

            if statusProvider() == .requiresApproval {
                throw PrivilegedHelperClientError.helperApprovalRequired
            }

            let lifecycle = ConnectionLifecycle()
            let connection = NSXPCConnection(
                machServiceName: Self.machServiceName,
                options: .privileged
            )
            connection.remoteObjectInterface = NSXPCInterface(
                with: KiplessSleepHelperProtocol.self
            )
            let handleConnectionLoss = { [weak self, weak connection] in
                lifecycle.markInvalidated()
                self?.clearConnectionIfNeeded(connection)
            }
            connection.invalidationHandler = handleConnectionLoss
            connection.interruptionHandler = handleConnectionLoss
            connection.resume()

            guard !lifecycle.isInvalidated else {
                throw PrivilegedHelperClientError.remoteFailure(
                    "The privileged helper connection was invalidated"
                )
            }

            let proxy = connection.remoteObjectProxyWithErrorHandler { [weak self] _ in
                self?.clearConnectionIfNeeded(connection)
            }

            guard let remote = proxy as? KiplessSleepHelperProtocol else {
                connection.invalidate()
                throw PrivilegedHelperClientError.helperUnavailable(
                    "The privileged helper does not expose the expected interface"
                )
            }

            lock.lock()
            if let cachedRemote = remoteObject ?? injectedRemote {
                lock.unlock()
                connection.invalidate()
                return cachedRemote
            }
            self.connection = connection
            self.remoteObject = remote
            lock.unlock()

            guard !lifecycle.isInvalidated else {
                clearConnectionIfNeeded(connection)
                connection.invalidate()
                throw PrivilegedHelperClientError.remoteFailure(
                    "The privileged helper connection was invalidated"
                )
            }
            return remote
        } catch let error as PrivilegedHelperClientError {
            throw error
        } catch {
            throw PrivilegedHelperClientError.helperUnavailable(error.localizedDescription)
        }
    }

    private func clearConnectionIfNeeded(_ expectedConnection: NSXPCConnection? = nil) {
        lock.lock()
        guard expectedConnection == nil || connection === expectedConnection else {
            lock.unlock()
            return
        }
        connection = nil
        remoteObject = injectedRemote
        lock.unlock()

        failPendingRequests(
            with: .remoteFailure("The privileged helper connection was invalidated")
        )
    }

    private func remoteProxy(
        fallback: KiplessSleepHelperProtocol,
        errorHandler: @escaping (Error) -> Void
    ) -> KiplessSleepHelperProtocol? {
        lock.lock()
        let connection = self.connection
        let hasInjectedRemote = injectedRemote != nil
        lock.unlock()

        if hasInjectedRemote { return fallback }
        guard let connection else {
            errorHandler(
                PrivilegedHelperClientError.remoteFailure(
                    "The privileged helper connection is unavailable"
                )
            )
            return nil
        }

        return connection.remoteObjectProxyWithErrorHandler { [weak self, weak connection] error in
            errorHandler(error)
            self?.clearConnectionIfNeeded(connection)
        }
            as! KiplessSleepHelperProtocol
    }

    private func registerPendingRequest(
        _ id: UUID,
        failure: @escaping @Sendable (PrivilegedHelperClientError) -> Void
    ) {
        lock.lock()
        pendingRequestFailures[id] = failure
        lock.unlock()
    }

    private func removePendingRequest(_ id: UUID) {
        lock.lock()
        pendingRequestFailures.removeValue(forKey: id)
        lock.unlock()
    }

    private func scheduleRequestTimeout(_ id: UUID) {
        let timeout = requestTimeout

        Task { [weak self] in
            try? await Task.sleep(for: timeout)
            self?.failPendingRequestIfStillPending(id, with: .helperNotResponding)
        }
    }

    /// Only fails a request that has not finished yet, so a late timeout cannot
    /// touch a reply that already arrived.
    private func failPendingRequestIfStillPending(
        _ id: UUID,
        with error: PrivilegedHelperClientError
    ) {
        lock.lock()
        let failure = pendingRequestFailures.removeValue(forKey: id)
        lock.unlock()

        failure?(error)
    }

    private func failPendingRequests(with error: PrivilegedHelperClientError) {
        lock.lock()
        let failures = Array(pendingRequestFailures.values)
        pendingRequestFailures.removeAll()
        lock.unlock()

        failures.forEach { $0(error) }
    }
}

extension PrivilegedHelperClient: LidSleepOverrideClient {
    func acquireLidSleepOverride() async throws {
        do {
            try await enableSleepOverride()
        } catch let error as PrivilegedHelperClientError {
            if await repairRegistrationIfNeeded(after: error) {
                // The rebuilt registration is waiting for the user, which is
                // exactly what the approval dialog explains.
                throw PrivilegedHelperClientError.helperApprovalRequired
            }
            throw error
        }
    }

    func releaseLidSleepOverride() async throws {
        try await disableSleepOverride()
    }
}

private final class ConnectionLifecycle: @unchecked Sendable {
    private let lock = NSLock()
    private var invalidated = false

    var isInvalidated: Bool {
        lock.lock()
        defer { lock.unlock() }
        return invalidated
    }

    func markInvalidated() {
        lock.lock()
        invalidated = true
        lock.unlock()
    }
}

private final class OnceCompletion<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var didComplete = false
    private let continuation: CheckedContinuation<Value, Error>
    private let onComplete: @Sendable () -> Void

    init(
        _ continuation: CheckedContinuation<Value, Error>,
        onComplete: @escaping @Sendable () -> Void = {}
    ) {
        self.continuation = continuation
        self.onComplete = onComplete
    }

    func succeed(_ value: Value) {
        lock.lock()
        guard !didComplete else {
            lock.unlock()
            return
        }
        didComplete = true
        lock.unlock()
        onComplete()
        continuation.resume(returning: value)
    }

    func fail(_ error: PrivilegedHelperClientError) {
        lock.lock()
        guard !didComplete else {
            lock.unlock()
            return
        }
        didComplete = true
        lock.unlock()
        onComplete()
        continuation.resume(throwing: error)
    }
}
