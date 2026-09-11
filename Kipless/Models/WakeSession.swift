import Foundation

/// One wake session.
///
/// Kipless never runs more than one at a time, and the session's existence *is*
/// the app's active state — there is no separate `isActive` flag to fall out of
/// sync with it.
struct WakeSession: Equatable, Sendable {
    let mode: WakeMode
    let startedAt: Date

    /// Absolute deadline, or `nil` when the session runs until stopped.
    ///
    /// Deadlines are absolute rather than a countdown so that a stalled app, a
    /// paused run loop or a Mac that slept through the interval cannot make the
    /// session outlive the time the user asked for.
    let expiresAt: Date?

    init(mode: WakeMode, startedAt: Date, duration: WakeDuration) {
        self.mode = mode
        self.startedAt = startedAt
        self.expiresAt = duration.seconds.map(startedAt.addingTimeInterval)
    }
}
