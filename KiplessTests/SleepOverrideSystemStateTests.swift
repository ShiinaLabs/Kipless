import XCTest
@testable import Kipless

final class SleepOverrideSystemStateTests: XCTestCase {
    func testParsesSleepDisabledZero() {
        XCTAssertEqual(
            SleepOverrideStateParser.parse("System-wide power settings:\n SleepDisabled 0"),
            .disabled
        )
    }

    func testParsesSleepDisabledOne() {
        XCTAssertEqual(
            SleepOverrideStateParser.parse("System-wide power settings:\n SleepDisabled 1\n"),
            .enabled
        )
    }

    func testExplicitStateIgnoresUnrelatedSettingValueFormats() {
        XCTAssertEqual(
            SleepOverrideStateParser.parse(
                "System-wide power settings:\n SleepDisabled 0\n futuremode quiet\n hibernatefile /var/vm/image\n futurecount 42\nCurrently in use:\n sleep 1\n futurecurrent mode-x\n"
            ),
            .disabled
        )
        XCTAssertEqual(
            SleepOverrideStateParser.parse(
                "System-wide power settings:\n SleepDisabled 1\n futuremode quiet\n hibernatefile /var/vm/image\n futurecount 42\nCurrently in use:\n sleep 1\n futurecurrent mode-x\n"
            ),
            .enabled
        )
    }

    func testMissingSleepDisabledUsesDisabledDefaultInValidSettingsOutput() {
        XCTAssertEqual(
            SleepOverrideStateParser.parse(
                "System-wide power settings:\n DestroyFVKeyOnStandby\t\t0\n VACTDisabled\t\t0\n"
            ),
            .disabled
        )
    }

    func testIssueOutputWithCurrentlyInUseSleepSettingsAndNoSleepDisabledIsDisabled() {
        XCTAssertEqual(
            SleepOverrideStateParser.parse(
                "System-wide power settings:\nCurrently in use:\n sleep 1 (sleep prevented by powerd, Kipless, sharingd)\n"
            ),
            .disabled
        )
    }

    func testCurrentSettingsAcceptAdditionalVersionSpecificFields() {
        XCTAssertEqual(
            SleepOverrideStateParser.parse(
                "System-wide power settings:\nCurrently in use:\n sleep 1\n futuremode quiet\n futurepath /var/vm/new-image\n futurecount 7\n"
            ),
            .disabled
        )
    }

    func testSleepDisabledInCurrentlyInUseSectionIsNotSystemWideState() {
        XCTAssertEqual(
            SleepOverrideStateParser.parse(
                "System-wide power settings:\nCurrently in use:\n SleepDisabled 1\n sleep 1\n"
            ),
            .unknown
        )
    }

    func testIndentedPermissionErrorIsUnknown() {
        XCTAssertEqual(
            SleepOverrideStateParser.parse(
                "System-wide power settings:\n permission denied\n"
            ),
            .unknown
        )
        XCTAssertEqual(
            SleepOverrideStateParser.parse(
                "System-wide power settings:\nCurrently in use:\n permission denied\n"
            ),
            .unknown
        )
        XCTAssertEqual(
            SleepOverrideStateParser.parse(
                "System-wide power settings:\n futureversionkey 7\n"
            ),
            .unknown
        )
    }

    func testEmptyUnrecognizedAndIncompleteSettingsOutputIsUnknown() {
        XCTAssertEqual(SleepOverrideStateParser.parse(""), .unknown)
        XCTAssertEqual(SleepOverrideStateParser.parse("pmset output not recognized"), .unknown)
        XCTAssertEqual(SleepOverrideStateParser.parse("SleepDisabled 0"), .unknown)
        XCTAssertEqual(
            SleepOverrideStateParser.parse("System-wide power settings:\n sleep 1"),
            .unknown
        )
        XCTAssertEqual(SleepOverrideStateParser.parse("System-wide power settings:\n"), .unknown)
        XCTAssertEqual(
            SleepOverrideStateParser.parse("System-wide power settings:\nCurrently in use:\n"),
            .unknown
        )
        XCTAssertEqual(
            SleepOverrideStateParser.parse("System-wide power settings:\n not-a-setting\n"),
            .unknown
        )
    }

    func testMalformedSleepDisabledValuesAreUnknown() {
        XCTAssertEqual(
            SleepOverrideStateParser.parse("System-wide power settings:\n SleepDisabled maybe\n"),
            .unknown
        )
        XCTAssertEqual(
            SleepOverrideStateParser.parse("System-wide power settings:\n SleepDisabled 2\n"),
            .unknown
        )
        XCTAssertEqual(
            SleepOverrideStateParser.parse("System-wide power settings:\n SleepDisabled 0 extra\n"),
            .unknown
        )
    }

    func testRepeatedAndConflictingSleepDisabledValuesAreUnknown() {
        XCTAssertEqual(
            SleepOverrideStateParser.parse(
                "System-wide power settings:\n SleepDisabled 0\n SleepDisabled 0\n"
            ),
            .unknown
        )
        XCTAssertEqual(
            SleepOverrideStateParser.parse(
                "System-wide power settings:\n SleepDisabled 0\n SleepDisabled 1\n"
            ),
            .unknown
        )
    }

    func testValidAndInvalidSleepDisabledFieldsAreUnknown() {
        XCTAssertEqual(
            SleepOverrideStateParser.parse(
                "System-wide power settings:\n SleepDisabled 0\n SleepDisabled invalid\n"
            ),
            .unknown
        )
        XCTAssertEqual(
            SleepOverrideStateParser.parse(
                "System-wide power settings:\n SleepDisabled 1\n SleepDisabled 2\n"
            ),
            .unknown
        )
    }
}
