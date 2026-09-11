import Foundation
import IOKit.pwr_mgt

/// The concrete power assertions Kipless can hold.
///
/// This type is shared by the app and the integration-test helper so the
/// helper exercises the same IOKit mapping and creation path as production.
enum PowerAssertionMode: String, Sendable {
    case system
    case display
}

enum PowerAssertionDriverError: Error, Sendable {
    case creationFailed(code: IOReturn)

    var code: IOReturn {
        switch self {
        case let .creationFailed(code): code
        }
    }
}

enum PowerAssertionDriver {
    static func acquire(for mode: PowerAssertionMode) throws -> IOPMAssertionID {
        var id: IOPMAssertionID = 0
        let reason = "Kipless is keeping your Mac awake." as CFString
        let result = IOPMAssertionCreateWithName(
            assertionType(for: mode),
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &id
        )

        guard result == kIOReturnSuccess else {
            throw PowerAssertionDriverError.creationFailed(code: result)
        }
        return id
    }

    static func release(_ id: IOPMAssertionID) {
        IOPMAssertionRelease(id)
    }

    // Internal visibility lets unit tests verify the single source of truth
    // without exposing IOKit details to the rest of the app.
    static func assertionType(for mode: PowerAssertionMode) -> CFString {
        switch mode {
        case .system: kIOPMAssertionTypePreventUserIdleSystemSleep as CFString
        case .display: kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString
        }
    }
}
