import XCTest
@testable import Kipless

final class SleepOverrideSystemStateTests: XCTestCase {
    func testParsesSleepDisabledZero() {
        XCTAssertEqual(
            SleepOverrideStateParser.parse("System-wide power settings:\n SleepDisabled 0\n"),
            .disabled
        )
    }

    func testParsesSleepDisabledOne() {
        XCTAssertEqual(
            SleepOverrideStateParser.parse("System-wide power settings:\n SleepDisabled 1\n"),
            .enabled
        )
    }

    func testMalformedOutputIsUnknown() {
        XCTAssertEqual(SleepOverrideStateParser.parse("SleepDisabled yes"), .unknown)
        XCTAssertEqual(SleepOverrideStateParser.parse(""), .unknown)
    }

    func testConflictingValuesAreUnknown() {
        XCTAssertEqual(
            SleepOverrideStateParser.parse("SleepDisabled 0\nSleepDisabled 1"),
            .unknown
        )
    }
}
