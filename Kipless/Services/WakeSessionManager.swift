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
#if !KIPLESS_APP_STORE
    private(set) var lidApprovalIsRequired = false
#endif

    /// How long quitting waits for a Closed Lid transition to unwind.
#if !KIPLESS_APP_STORE
    static let defaultTerminationTimeout: Duration = .seconds(3)
#endif

    /// Waits out the time left before a deadline is checked again.
    ///
    /// Injected so tests can drive expiry without waiting on a real clock. The
    /// production value sleeps exactly the interval that is left instead of
    /// polling it, so a running Session costs no wake-ups of its own.
    typealias DeadlineSleeper = @MainActor (Duration) async -> Void

    private let assertions: SleepAsserting
#if !KIPLESS_APP_STORE
    private let lidSleepOverride: LidSleepOverrideClient
#endif
    private let dateProvider: () -> Date
#if !KIPLESS_APP_STORE
    private let terminationTimeout: Duration
#endif
    private let sleeper: DeadlineSleeper
    private var expiryTask: Task<Void, Never>?
#if !KIPLESS_APP_STORE
    private var transitionTask: Task<Void, Never>?
    private var transitionID = 0
    private var pendingTransitionID: Int?
#endif

#if !KIPLESS_APP_STORE
    init(
        assertions: SleepAsserting = SleepAssertionManager(),
        lidSleepOverride: LidSleepOverrideClient = PrivilegedHelperClient(),
        dateProvider: @escaping () -> Date = Date.init,
        terminationTimeout: Duration = WakeSessionManager.defaultTerminationTimeout,
        sleeper: @escaping DeadlineSleeper = { try? await Task.sleep(for: $0) }
    ) {
        self.assertions = assertions
        self.lidSleepOverride = lidSleepOverride
        self.dateProvider = dateProvider
        self.terminationTimeout = terminationTimeout
        self.sleeper = sleeper
    }
#else
    init(
        assertions: SleepAsserting = SleepAssertionManager(),
        dateProvider: @escaping () -> Date = Date.init,
        sleeper: @escaping DeadlineSleeper = { try? await Task.sleep(for: $0) }
    ) {
        self.assertions = assertions
        self.dateProvider = dateProvider
        self.sleeper = sleeper
    }
#endif

    var isActive: Bool { session != nil }

    /// True while a distribution-specific backend is acquiring or releasing
    /// its lease. The App Store edition has no asynchronous backend, so this
    /// remains false there.
    /// A transition is kept separate from `isActive` so the UI cannot start a
    /// second Session while the previous helper operation is still unwinding.
    private(set) var isTransitioning = false

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

#if !KIPLESS_APP_STORE
        if mode == .closedLid {
            startClosedLidSession(duration: duration)
            return
        }
#endif

        do {
            try assertions.acquire(for: mode)
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        session = WakeSession(mode: mode, startedAt: dateProvider(), duration: duration)
        errorMessage = nil
        scheduleExpiry()
    }

    /// Ends the session and releases the assertion. Safe to call when inactive.
    func stop() {
#if !KIPLESS_APP_STORE
        transitionID &+= 1
        cancelExpiry()

        let wasClosedLid = session?.mode == .closedLid
        session = nil
        assertions.release()

        if wasClosedLid {
            beginLidSleepOverrideRelease()
        } else if pendingTransitionID == nil {
            isTransitioning = false
        }
#else
        cancelExpiry()
        session = nil
        assertions.release()
        isTransitioning = false
#endif
    }

    /// Waits for any Closed Lid acquire/release operation before allowing the
    /// app to terminate. Normal cleanup still goes through `stop()` so this is
    /// also safe when no Session is running.
#if !KIPLESS_APP_STORE
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
#endif

    func dismissError() {
        errorMessage = nil
    }

    /// Called once the approval dialog has been shown, so it is asked once per
    /// failed attempt rather than on every redraw.
#if !KIPLESS_APP_STORE
    func acknowledgeLidApprovalRequest() {
        lidApprovalIsRequired = false
    }
#endif

    // MARK: - Expiry

    /// Parks a wait on the Session's deadline.
    ///
    /// One wait, not a poll: nothing here measures elapsed time, so a Session
    /// that runs for an hour is woken once. What ends the Session is still the
    /// deadline compared against the real clock, so waking late — or being
    /// woken early and having to wait again — can never make a Session run
    /// long or short.
    private func scheduleExpiry() {
        cancelExpiry()

        guard let session, let expiresAt = session.expiresAt else { return }
        let identity = session.id

        expiryTask = Task { @MainActor [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                let remaining = expiresAt.timeIntervalSince(self.dateProvider())
                if remaining <= 0 { break }
                await self.sleeper(.seconds(remaining))
            }

            guard !Task.isCancelled else { return }

            // The Session this wait belongs to may have been stopped or
            // replaced while it was parked, so identity is re-checked before
            // this is allowed to end anything.
            guard self.session?.id == identity else { return }
            guard self.dateProvider() >= expiresAt else { return }

            self.stop()
        }
    }

    private func cancelExpiry() {
        expiryTask?.cancel()
        expiryTask = nil
    }

    /// Re-checks the deadline after the Mac wakes from sleep.
    ///
    /// A wait parked on a deadline is not guaranteed to elapse on schedule
    /// across a system sleep, so the deadline is re-read from the real clock as
    /// soon as the machine is back. Without this, a Session whose deadline
    /// passed while the Mac was asleep would keep its assertion until the wait
    /// eventually fired.
    func systemDidWake() {
        guard session?.expiresAt != nil else { return }

        scheduleExpiry()
    }

    // MARK: - Closed Lid backend

#if !KIPLESS_APP_STORE
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
            scheduleExpiry()
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
#endif
}
