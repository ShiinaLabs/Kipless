import XCTest
@testable import Kipless

final class SessionRingProgressTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    func testAFreshSessionHasAFullRing() {
        XCTAssertEqual(progress(for: .hour1, at: start), 1)
    }

    func testHalfWayThroughTheRingIsHalfFull() {
        XCTAssertEqual(
            progress(for: .hour1, at: start.addingTimeInterval(1800)),
            0.5,
            accuracy: 0.0001
        )
    }

    func testAnExpiredSessionHasAnEmptyRing() {
        XCTAssertEqual(progress(for: .hour1, at: start.addingTimeInterval(3600)), 0)
    }

    func testATimeBeforeTheStartIsClampedToAFullRing() {
        XCTAssertEqual(progress(for: .hour1, at: start.addingTimeInterval(-60)), 1)
    }

    func testALongJumpPastTheDeadlineIsClampedToAnEmptyRing() {
        // What a Mac waking from a long sleep finds.
        XCTAssertEqual(progress(for: .minutes15, at: start.addingTimeInterval(6 * 3600)), 0)
    }

    func testAnIndefiniteOrIdleSessionReadsAsAFullRing() {
        XCTAssertEqual(
            SessionRingProgress.progress(
                session: WakeSession(mode: .display, startedAt: start, duration: .indefinite),
                at: start.addingTimeInterval(48 * 3600)
            ),
            1
        )
        XCTAssertEqual(SessionRingProgress.progress(session: nil, at: start), 1)
    }

    func testRemainingSecondsCountsDownToTheDeadline() {
        XCTAssertEqual(remaining(at: start), 3600)

        // Rounded up, so the countdown reads the full remaining second.
        XCTAssertEqual(remaining(at: start.addingTimeInterval(59.5)), 3541)

        XCTAssertEqual(remaining(at: start.addingTimeInterval(3600)), 0)
        XCTAssertEqual(remaining(at: start.addingTimeInterval(7200)), 0)
    }

    func testAnIndefiniteOrIdleSessionHasNoRemainingSeconds() {
        XCTAssertNil(
            SessionRingProgress.remainingSeconds(
                session: WakeSession(mode: .display, startedAt: start, duration: .indefinite),
                at: start
            )
        )
        XCTAssertNil(SessionRingProgress.remainingSeconds(session: nil, at: start))
    }

    private func progress(for duration: WakeDuration, at date: Date) -> Double {
        SessionRingProgress.progress(
            session: WakeSession(mode: .system, startedAt: start, duration: duration),
            at: date
        )
    }

    private func remaining(at date: Date) -> Int? {
        SessionRingProgress.remainingSeconds(
            session: WakeSession(mode: .system, startedAt: start, duration: .hour1),
            at: date
        )
    }
}

@MainActor
final class SessionPresentationClockTests: XCTestCase {
    func testTheClockRunsOnlyWhenThereIsSomethingToDraw() {
        let clock = makeClock()

        clock.update(isVisible: true, expiresAt: deadline)
        XCTAssertTrue(clock.isTicking)

        clock.update(isVisible: true, expiresAt: nil)
        XCTAssertFalse(clock.isTicking, "a Session with no deadline has nothing to count down")

        clock.update(isVisible: false, expiresAt: deadline)
        XCTAssertFalse(clock.isTicking, "a closed popover must not refresh anything")
        XCTAssertFalse(clock.isVisible)
    }

    func testStartingTheClockRefreshesWhatItDrawsFor() {
        let face = ClockFace()
        let clock = makeClock(face: face)

        // The popover may have been closed for an hour. The first frame after
        // it reopens has to be drawn for now, not for then.
        face.now = face.now.addingTimeInterval(3600)
        clock.update(isVisible: true, expiresAt: face.now.addingTimeInterval(60))

        XCTAssertEqual(clock.now, face.now)
    }

    func testAStoppedClockDoesNotRefresh() {
        let face = ClockFace()
        let clock = makeClock(face: face)
        clock.update(isVisible: false, expiresAt: deadline)
        let before = clock.now

        face.now = face.now.addingTimeInterval(3600)
        clock.update(isVisible: false, expiresAt: deadline)

        XCTAssertEqual(clock.now, before)
    }

    func testTheClockAsksItsCadenceHowLongToWait() async {
        let cadence = RecordingCadence(result: .seconds(3600))
        let face = ClockFace()
        let clock = SessionPresentationClock(
            cadence: { cadence.record(remainingSeconds: $0) },
            dateProvider: { face.now }
        )

        clock.update(isVisible: true, expiresAt: face.now.addingTimeInterval(1800))
        await waitUntil("the clock asks its cadence") { !cadence.requestedSeconds.isEmpty }

        XCTAssertEqual(cadence.requestedSeconds.first, 1800)

        clock.update(isVisible: false, expiresAt: nil)
    }

    /// A countdown that has reached zero has no next change to wait for. That
    /// must park the clock rather than spin it, and the Session ending is what
    /// stops it.
    func testACadenceWithNothingLeftToWaitForParksInsteadOfSpinning() async {
        let cadence = RecordingCadence(result: nil)
        let clock = SessionPresentationClock(
            cadence: { cadence.record(remainingSeconds: $0) },
            dateProvider: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        clock.update(isVisible: true, expiresAt: deadline)
        await waitUntil("the clock asks its cadence") { !cadence.requestedSeconds.isEmpty }

        await settle()
        XCTAssertEqual(
            cadence.requestedSeconds.count,
            1,
            "a cadence with nothing to wait for must not be asked over and over"
        )
        XCTAssertTrue(clock.isTicking, "the clock is parked, not gone")

        clock.update(isVisible: true, expiresAt: nil)
        XCTAssertFalse(clock.isTicking, "the Session ending is what stops it")
    }

    func testTheClockAdvancesWhileItRuns() async {
        let face = ClockFace()
        let clock = SessionPresentationClock(
            cadence: { _ in .milliseconds(1) },
            dateProvider: { face.now }
        )

        clock.update(isVisible: true, expiresAt: face.now.addingTimeInterval(3600))
        face.now = face.now.addingTimeInterval(5)

        await waitUntil("the clock picks up the new time") { clock.now == face.now }

        clock.update(isVisible: false, expiresAt: nil)
    }

    private var deadline: Date {
        Date(timeIntervalSince1970: 1_700_003_600)
    }

    private func makeClock(face: ClockFace = ClockFace()) -> SessionPresentationClock {
        SessionPresentationClock(
            cadence: { _ in .seconds(3600) },
            dateProvider: { face.now }
        )
    }

    private func waitUntil(
        _ description: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if condition() { return }
            await Task.yield()
        }

        XCTFail("Timed out waiting until \(description).", file: file, line: line)
    }

    /// Gives anything already scheduled a chance to run, so that "it did not
    /// happen again" can be asserted rather than assumed.
    private func settle() async {
        for _ in 0..<50 {
            await Task.yield()
        }
    }

    /// A clock the cases move by hand.
    private final class ClockFace {
        var now = Date(timeIntervalSince1970: 1_700_000_000)
    }

    /// Records what the clock asked its cadence for. The clock calls this from
    /// the main actor, so the lock only exists to satisfy the closure's
    /// `@Sendable` signature.
    private final class RecordingCadence: @unchecked Sendable {
        private let lock = NSLock()
        private let result: Duration?
        private var recorded: [Int] = []

        init(result: Duration?) {
            self.result = result
        }

        var requestedSeconds: [Int] {
            lock.withLock { recorded }
        }

        func record(remainingSeconds: Int) -> Duration? {
            lock.withLock { recorded.append(remainingSeconds) }

            return result
        }
    }
}

final class MenuBarCountdownTests: XCTestCase {
    func testTheCountdownIsCoarseUntilTheLastMinute() {
        XCTAssertEqual(MenuBarCountdown.text(remainingSeconds: 7200), "2h")
        XCTAssertEqual(MenuBarCountdown.text(remainingSeconds: 3660), "1h01")
        XCTAssertEqual(MenuBarCountdown.text(remainingSeconds: 3600), "1h")
        XCTAssertEqual(MenuBarCountdown.text(remainingSeconds: 1800), "30m")
        XCTAssertEqual(MenuBarCountdown.text(remainingSeconds: 61), "1m")
        XCTAssertEqual(MenuBarCountdown.text(remainingSeconds: 60), "1m")
        XCTAssertEqual(MenuBarCountdown.text(remainingSeconds: 59), "0:59")
        XCTAssertEqual(MenuBarCountdown.text(remainingSeconds: 5), "0:05")
        XCTAssertEqual(MenuBarCountdown.text(remainingSeconds: 0), "0:00")
    }

    func testANegativeRemainderIsClampedRatherThanRendered() {
        XCTAssertEqual(MenuBarCountdown.text(remainingSeconds: -5), "0:00")
    }

    func testTheNextChangeIsWaitedFor() {
        // A minute display only turns over on a minute boundary, and the exact
        // boundary is the one case where that is a second away.
        XCTAssertEqual(MenuBarCountdown.nextChangeDelay(remainingSeconds: 1810), .seconds(11))
        XCTAssertEqual(MenuBarCountdown.nextChangeDelay(remainingSeconds: 1800), .seconds(1))
        XCTAssertEqual(MenuBarCountdown.nextChangeDelay(remainingSeconds: 3600), .seconds(1))
        XCTAssertEqual(MenuBarCountdown.nextChangeDelay(remainingSeconds: 61), .seconds(2))
        XCTAssertEqual(MenuBarCountdown.nextChangeDelay(remainingSeconds: 60), .seconds(1))
        XCTAssertEqual(MenuBarCountdown.nextChangeDelay(remainingSeconds: 59), .seconds(1))
    }

    /// Once the countdown reads zero it never changes again, which is what ends
    /// the clock rather than letting it spin.
    func testAZeroCountdownIsNeverWaitedFor() {
        XCTAssertNil(MenuBarCountdown.nextChangeDelay(remainingSeconds: 0))
    }

}
