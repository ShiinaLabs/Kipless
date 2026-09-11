import Foundation
import IOKit.pwr_mgt

/// Holds a power assertion for a given mode.
///
/// A protocol so `WakeSessionManager` never has to know about IOKit, and so the
/// session logic can be tested without touching real power management.
@MainActor
protocol SleepAsserting: AnyObject {
    func acquire(for mode: WakeMode) throws
    func release()
}

enum SleepAssertionError: LocalizedError, Sendable {
    case creationFailed(mode: WakeMode, code: IOReturn)

    var errorDescription: String? {
        switch self {
        case let .creationFailed(mode, code):
            String(localized: KiplessStrings.assertionCreationError(mode: mode.title.lowercased(), code: code))
        }
    }
}

/// Owns the one power assertion Kipless holds.
///
/// Acquisition and release are paired by construction: `acquire(for:)` releases
/// whatever it was already holding before creating a new assertion, and
/// `release()` is a no-op when nothing is held. That makes it impossible for a
/// leak to build up across a series of sessions, and impossible for a restart
/// to end up holding two assertions at once.
@MainActor
final class SleepAssertionManager: SleepAsserting {
    private var assertionID: IOPMAssertionID = 0

    /// Shown in `pmset -g assertions`, so make it say what is going on.
    private static let reason = "Kipless is keeping your Mac awake." as CFString

    /// Whether an assertion is currently held. Exposed for tests and diagnostics.
    var isHolding: Bool { assertionID != 0 }

    func acquire(for mode: WakeMode) throws {
        release()

        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            Self.assertionType(for: mode),
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            Self.reason,
            &id
        )

        guard result == kIOReturnSuccess else {
            throw SleepAssertionError.creationFailed(mode: mode, code: result)
        }
        assertionID = id
    }

    func release() {
        guard assertionID != 0 else { return }
        let id = assertionID
        // Clear the stored ID first: if the release call were ever to trap or
        // re-enter, the assertion must not look like it is still held.
        assertionID = 0
        IOPMAssertionRelease(id)
    }

    private static func assertionType(for mode: WakeMode) -> CFString {
        switch mode {
        case .system: kIOPMAssertionTypePreventUserIdleSystemSleep as CFString
        case .display: kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString
        }
    }
}
