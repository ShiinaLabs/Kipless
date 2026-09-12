import Foundation
import ServiceManagement

enum PrivilegedHelperClientError: LocalizedError, Sendable {
    case helperUnavailable(String)
    case remoteFailure(String)
    case unknownState(Int)

    var message: String {
        switch self {
        case let .helperUnavailable(message), let .remoteFailure(message): message
        case let .unknownState(code): "Helper returned an unknown SleepDisabled state (\(code))"
        }
    }

    var errorDescription: String? { message }
}

/// The narrow privileged capability used only by the Closed Lid wake mode.
/// Keeping this interface separate from the UI makes the helper lease a
/// Session backend rather than an independently toggled setting.
protocol LidSleepOverrideClient: AnyObject, Sendable {
    func acquireLidSleepOverride() async throws
    func releaseLidSleepOverride() async throws
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

    init() {
        injectedRemote = nil
    }

    init(remote: KiplessSleepHelperProtocol) {
        injectedRemote = remote
        remoteObject = remote
    }

    func connect() throws {
        _ = try remoteForRequest()
    }

    func getSleepOverrideState() async throws -> SleepOverrideSystemState {
        let remote = try remoteForRequest()

        return try await withCheckedThrowingContinuation { continuation in
            let completion = OnceCompletion(continuation)
            let requestRemote = remoteProxy(fallback: remote) { error in
                completion.fail(.remoteFailure(error.localizedDescription))
            }
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
    }

    private func performOperation(
        _ invoke: @escaping (
            KiplessSleepHelperProtocol,
            @escaping (Bool, String?) -> Void
        ) -> Void
    ) async throws {
        let remote = try remoteForRequest()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let completion = OnceCompletion(continuation)
            let requestRemote = remoteProxy(fallback: remote) { error in
                completion.fail(.remoteFailure(error.localizedDescription))
            }
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
        defer { lock.unlock() }

        if let remoteObject { return remoteObject }
        if let injectedRemote { return injectedRemote }

        do {
            let service = SMAppService.daemon(plistName: Self.daemonPlistName)
            switch service.status {
            case .enabled:
                break
            case .notRegistered, .requiresApproval, .notFound:
                try service.register()
            @unknown default:
                try service.register()
            }

            let connection = NSXPCConnection(
                machServiceName: Self.machServiceName,
                options: .privileged
            )
            connection.remoteObjectInterface = NSXPCInterface(
                with: KiplessSleepHelperProtocol.self
            )
            connection.invalidationHandler = { [weak self] in
                self?.clearConnectionIfNeeded()
            }
            connection.resume()

            let proxy = connection.remoteObjectProxyWithErrorHandler { [weak self] _ in
                self?.clearConnectionIfNeeded()
            }

            guard let remote = proxy as? KiplessSleepHelperProtocol else {
                connection.invalidate()
                throw PrivilegedHelperClientError.helperUnavailable(
                    "The privileged helper does not expose the expected interface"
                )
            }

            self.connection = connection
            self.remoteObject = remote
            return remote
        } catch let error as PrivilegedHelperClientError {
            throw error
        } catch {
            throw PrivilegedHelperClientError.helperUnavailable(error.localizedDescription)
        }
    }

    private func clearConnectionIfNeeded() {
        lock.lock()
        connection = nil
        remoteObject = injectedRemote
        lock.unlock()
    }

    private func remoteProxy(
        fallback: KiplessSleepHelperProtocol,
        errorHandler: @escaping (Error) -> Void
    ) -> KiplessSleepHelperProtocol {
        lock.lock()
        defer { lock.unlock() }

        guard injectedRemote == nil, let connection else { return fallback }
        return connection.remoteObjectProxyWithErrorHandler(errorHandler)
            as! KiplessSleepHelperProtocol
    }
}

extension PrivilegedHelperClient: LidSleepOverrideClient {
    func acquireLidSleepOverride() async throws {
        try await enableSleepOverride()
    }

    func releaseLidSleepOverride() async throws {
        try await disableSleepOverride()
    }
}

private final class OnceCompletion<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var didComplete = false
    private let continuation: CheckedContinuation<Value, Error>

    init(_ continuation: CheckedContinuation<Value, Error>) {
        self.continuation = continuation
    }

    func succeed(_ value: Value) {
        lock.lock()
        guard !didComplete else {
            lock.unlock()
            return
        }
        didComplete = true
        lock.unlock()
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
        continuation.resume(throwing: error)
    }
}
