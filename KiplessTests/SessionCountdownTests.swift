import XCTest
@testable import Kipless

final class SessionCountdownTests: XCTestCase {
    func testMinutes() {
        XCTAssertEqual(SessionCountdown.text(forRemainingSeconds: 60), "1 min remaining")
        XCTAssertEqual(SessionCountdown.text(forRemainingSeconds: 42 * 60), "42 min remaining")
        XCTAssertEqual(SessionCountdown.text(forRemainingSeconds: 59 * 60 + 59), "59 min remaining")
    }

    func testHours() {
        XCTAssertEqual(SessionCountdown.text(forRemainingSeconds: 3600), "1 hr remaining")
        XCTAssertEqual(SessionCountdown.text(forRemainingSeconds: 2 * 3600), "2 hr remaining")
        XCTAssertEqual(SessionCountdown.text(forRemainingSeconds: 3600 + 60), "1 hr 1 min remaining")
        XCTAssertEqual(SessionCountdown.text(forRemainingSeconds: 2 * 3600 + 5 * 60), "2 hr 5 min remaining")
    }

    func testUnderAMinute() {
        XCTAssertEqual(SessionCountdown.text(forRemainingSeconds: 59), "Less than a minute remaining")
        XCTAssertEqual(SessionCountdown.text(forRemainingSeconds: 1), "Less than a minute remaining")
        XCTAssertEqual(SessionCountdown.text(forRemainingSeconds: 0), "Less than a minute remaining")
    }

    func testNegativeIsClampedRatherThanRendered() {
        XCTAssertEqual(SessionCountdown.text(forRemainingSeconds: -5), "Less than a minute remaining")
    }
}
