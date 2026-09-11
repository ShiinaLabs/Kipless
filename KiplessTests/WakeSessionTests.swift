import XCTest
@testable import Kipless

final class WakeSessionTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    func testTimedSessionGetsAnAbsoluteDeadline() {
        let session = WakeSession(mode: .system, startedAt: start, duration: .minutes15)

        XCTAssertEqual(session.expiresAt, start.addingTimeInterval(15 * 60))
    }

    func testPresetDurations() {
        XCTAssertEqual(WakeDuration.minutes15.seconds, 900)
        XCTAssertEqual(WakeDuration.minutes30.seconds, 1800)
        XCTAssertEqual(WakeDuration.hour1.seconds, 3600)
        XCTAssertEqual(WakeDuration.hour2.seconds, 7200)
        XCTAssertNil(WakeDuration.indefinite.seconds)
    }

    func testIndefiniteSessionHasNoDeadline() {
        let session = WakeSession(mode: .display, startedAt: start, duration: .indefinite)

        XCTAssertNil(session.expiresAt)
    }

    func testEveryDurationIsOfferedExactlyOnce() {
        XCTAssertEqual(
            WakeDuration.allCases,
            [.minutes15, .minutes30, .hour1, .hour2, .indefinite]
        )
        XCTAssertEqual(WakeMode.allCases, [.system, .display])
    }
}
