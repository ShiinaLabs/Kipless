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

    /// Re-stamped on every tick purely so views observing `remainingSeconds`
    /// re-render. It is never used to decide when a session ends.
    private(set) var now: Date

    private let assertions: SleepAsserting
    private let dateProvider: () -> Date
    private var ticker: Task<Void, Never>?

    init(
        assertions: SleepAsserting = SleepAssertionManager(),
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.assertions = assertions
        self.dateProvider = dateProvider
        self.now = dateProvider()
    }

    var isActive: Bool { session != nil }

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
        stop()

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
        stopTicking()
        assertions.release()
        session = nil
    }

    func dismissError() {
        errorMessage = nil
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
