import Foundation
import Observation

/// The single source of truth for whether Kipless is keeping the Mac awake.
///
/// The popover observes this object and derives everything it shows from it. It
/// never keeps its own copy of the current mode, the remaining time or an
/// "is awake" flag, so there is nothing that can disagree with the real session.
@MainActor
@Observable
final class WakeSessionManager {
    /// The one session manager for the running app. `WakeSessionManager` is
    /// deliberately the only state source, and this makes that structural.
    static let shared = WakeSessionManager()

    /// The running session, or `nil` when Kipless is inactive.
    private(set) var session: WakeSession?

    /// Message for the last failed start, cleared on the next successful one.
    private(set) var errorMessage: String?

    /// Set when a Closed Lid start failed because the privileged helper still
    /// needs its Login Items approval. The Popover turns this into a dialog:
    /// the failure needs an answer, not another line of status.
    private(set) var lidApprovalIsRequired = false

    /// Re-stamped on every tick purely so views observing `remainingSeconds`
    /// re-render. It is never used to decide when a session ends.
    private(set) var now: Date

    /// How long quitting waits for a Closed Lid transition to unwind.
    static let defaultTerminationTimeout: Duration = .seconds(3)

    private let assertions: SleepAsserting
    private let lidSleepOverride: LidSleepOverrideClient
    private let dateProvider: () -> Date
    private let terminationTimeout: Duration
    private var ticker: Task<Void, Never>?
    private var transitionTask: Task<Void, Never>?
    private var transitionID = 0
    private var pendingTransitionID: Int?

    init(
        assertions: SleepAsserting = SleepAssertionManager(),
        lidSleepOverride: LidSleepOverrideClient = PrivilegedHelperClient(),
        dateProvider: @escaping () -> Date = Date.init,
        terminationTimeout: Duration = WakeSessionManager.defaultTerminationTimeout
    ) {
        self.assertions = assertions
        self.lidSleepOverride = lidSleepOverride
        self.dateProvider = dateProvider
        self.terminationTimeout = terminationTimeout
        self.now = dateProvider()
    }

    var isActive: Bool { session != nil }

    /// True while the Closed Lid backend is acquiring or releasing its lease.
    /// A transition is kept separate from `isActive` so the UI cannot start a
    /// second Session while the previous helper operation is still unwinding.
    private(set) var isTransitioning = false

    /// Seconds left in the session, or `nil` when it runs until stopped.
    ///
    /// Always derived from the absolute deadline and the current time, so it
    /// stays correct across a stalled run loop or a Mac that slept.
    var remainingSeconds: Int? {
        guard let expiresAt = session?.expiresAt else { return nil }
        return max(0, Int(expiresAt.timeIntervalSince(now).rounded(.up)))
    }

    // MARK: - Session lifecycle

    /// Starts a session, replacing any session already running.
    ///
    /// If the power assertion cannot be created the session does not start, so
    /// the UI can never claim to be keeping the Mac awake when it is not.
    func start(mode: WakeMode, duration: WakeDuration) {
        guard !isTransitioning else { return }

        stop()

        // Stopping an active Closed Lid session has an asynchronous cleanup
        // phase. Do not overlap a new acquire with that release.
        guard !isTransitioning else { return }

        if mode == .closedLid {
            startClosedLidSession(duration: duration)
            return
        }

        do {
            try assertions.acquire(for: mode)
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        session = WakeSession(mode: mode, startedAt: dateProvider(), duration: duration)
        errorMessage = nil
        startTicking()
    }

    /// Ends the session and releases the assertion. Safe to call when inactive.
    func stop() {
        transitionID &+= 1
        stopTicking()

        let wasClosedLid = session?.mode == .closedLid
        session = nil
        assertions.release()

        if wasClosedLid {
            beginLidSleepOverrideRelease()
        } else if pendingTransitionID == nil {
            isTransitioning = false
        }
    }

    /// Waits for any Closed Lid acquire/release operation before allowing the
    /// app to terminate. Normal cleanup still goes through `stop()` so this is
    /// also safe when no Session is running.
    func prepareForTermination(completion: @escaping @MainActor () -> Void) {
        stop()

        Task { @MainActor [weak self] in
            await self?.waitForTransitionBeforeTermination()
            completion()
        }
    }

    /// Waits for the Closed Lid transition to unwind, but never longer than
    /// `terminationTimeout`.
    ///
    /// The cap matters: this runs while AppKit is holding up termination, so
    /// waiting forever means the app cannot be quit at all — it sits in the
    /// event loop, unresponsive, until the system kills it.
    private func waitForTransitionBeforeTermination() async {
        let deadline = ContinuousClock.now.advanced(by: terminationTimeout)

        while transitionTask != nil, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    func dismissError() {
        errorMessage = nil
    }

    /// Called once the approval dialog has been shown, so it is asked once per
    /// failed attempt rather than on every redraw.
    func acknowledgeLidApprovalRequest() {
        lidApprovalIsRequired = false
    }

    // MARK: - Expiry

    /// Ticks once a second. This only refreshes the derived UI state — the
    /// deadline check reads the real clock, so the tick rate can never make a
    /// session run long or short.
    private func startTicking() {
        stopTicking()
        now = dateProvider()

        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                self.tick()
            }
        }
    }

    private func stopTicking() {
        ticker?.cancel()
        ticker = nil
    }

    // MARK: - Closed Lid backend

    private func startClosedLidSession(duration: WakeDuration) {
        transitionID &+= 1
        let id = transitionID
        pendingTransitionID = id
        isTransitioning = true
        errorMessage = nil
        lidApprovalIsRequired = false

        transitionTask = Task { @MainActor [weak self] in
            await self?.performClosedLidStart(duration: duration, transitionID: id)
        }
    }

    private func performClosedLidStart(
        duration: WakeDuration,
        transitionID id: Int
    ) async {
        var assertionAcquired = false
        var overrideAcquireStarted = false

        do {
            // Closed Lid includes the ordinary system-awake assertion. The
            // helper lease is acquired only after that first step succeeds.
            try assertions.acquire(for: .closedLid)
            assertionAcquired = true

            overrideAcquireStarted = true
            try await lidSleepOverride.acquireLidSleepOverride()

            // `stop()` can run while the XPC request is in flight. Roll back
            // instead of committing a Session for a request that was already
            // cancelled by the user or by app termination.
            guard !Task.isCancelled, self.transitionID == id else {
                try? await lidSleepOverride.releaseLidSleepOverride()
                assertions.release()
                finishTransition(id)
                return
            }

            session = WakeSession(
                mode: .closedLid,
                startedAt: dateProvider(),
                duration: duration
            )
            errorMessage = nil
            startTicking()
        } catch {
            // Release is intentionally attempted even when acquire returned
            // an error: an XPC reply can be lost after the helper has already
            // changed its state. The helper operation is idempotent.
            if overrideAcquireStarted {
                try? await lidSleepOverride.releaseLidSleepOverride()
            }
            if assertionAcquired { assertions.release() }

            if self.transitionID == id {
                if let helperError = error as? PrivilegedHelperClientError,
                   helperError.requiresUserApproval {
                    // Approving the helper is the user's call, so ask with a
                    // dialog and leave the panel's status row alone.
                    lidApprovalIsRequired = true
                } else {
                    errorMessage = error.localizedDescription
                }
            }
        }

        finishTransition(id)
    }

    private func beginLidSleepOverrideRelease() {
        let id = transitionID
        pendingTransitionID = id
        isTransitioning = true

        transitionTask = Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                try await lidSleepOverride.releaseLidSleepOverride()
            } catch {
                // Invalidation gives the helper a second chance to release
                // the connection-bound lease when the remote call itself
                // fails.
                lidSleepOverride.invalidate()
                errorMessage = error.localizedDescription
            }

            finishTransition(id)
        }
    }

    private func finishTransition(_ id: Int) {
        guard pendingTransitionID == id else { return }
        pendingTransitionID = nil
        transitionTask = nil
        isTransitioning = false
    }

    private func tick() {
        now = dateProvider()

        guard let expiresAt = session?.expiresAt else { return }
        if now >= expiresAt {
            stop()
        }
    }

    #if DEBUG
    /// Test seam: drives the tick without waiting on the clock.
    func tickForTesting() { tick() }
    #endif
}
