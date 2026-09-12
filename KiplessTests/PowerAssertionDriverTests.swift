import IOKit.pwr_mgt
import XCTest
@testable import Kipless

final class PowerAssertionDriverTests: XCTestCase {
    func testSharedDriverMapsSystemAndDisplayModesToExpectedIOKitTypes() {
        XCTAssertEqual(
            PowerAssertionDriver.assertionType(for: .system) as String,
            kIOPMAssertionTypePreventUserIdleSystemSleep as String
        )
        XCTAssertEqual(
            PowerAssertionDriver.assertionType(for: .display) as String,
            kIOPMAssertionTypePreventUserIdleDisplaySleep as String
        )
    }

    func testWakeModesUseTheSharedPowerAssertionModes() {
        XCTAssertEqual(WakeMode.system.powerAssertionMode, .system)
        XCTAssertEqual(WakeMode.display.powerAssertionMode, .display)
        XCTAssertEqual(WakeMode.closedLid.powerAssertionMode, .system)
    }

    func testAssertionCreationErrorDoesNotRepeatTheModeTitle() {
        let error = SleepAssertionError.creationFailed(mode: .system, code: kIOReturnError)
        let description = error.errorDescription ?? ""

        XCTAssertTrue(description.hasPrefix("Could not keep your Mac awake"))
        XCTAssertFalse(description.contains(WakeMode.system.title.lowercased()))
    }
}
