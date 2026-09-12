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

final class SessionRingMotionTests: XCTestCase {
    func testASteadyTickTakesTheShortestStep() {
        // One second of a thirty-minute Session: the ring barely moves, and the
        // move has to finish well before the next tick sets off another one.
        XCTAssertEqual(SessionRingMotion.duration(forDelta: 1.0 / 1800.0), 0.15)
        XCTAssertLessThan(SessionRingMotion.duration(forDelta: 0.01), 1)
    }

    func testACatchUpGrowsWithWhatWasMissed() {
        XCTAssertEqual(SessionRingMotion.duration(forDelta: 0.05), 0.25)
        XCTAssertEqual(SessionRingMotion.duration(forDelta: 0.2), 0.35)
    }

    func testACatchUpIsBoundedHoweverLongThePopoverWasClosed() {
        XCTAssertLessThanOrEqual(SessionRingMotion.maximumCatchUpDuration, 0.5)
        XCTAssertEqual(
            SessionRingMotion.duration(forDelta: 0.9),
            SessionRingMotion.maximumCatchUpDuration
        )
    }

    func testReduceMotionPlacesTheRingInsteadOfMovingIt() {
        XCTAssertNil(SessionRingMotion.animation(reduceMotion: true, delta: 0.5))
        XCTAssertNotNil(SessionRingMotion.animation(reduceMotion: false, delta: 0.5))
    }
}

@MainActor
final class SessionPresentationClockTests: XCTestCase {
    func testTheClockRunsOnlyWhenThereIsSomethingToShow() {
        let clock = makeClock()

        clock.update(isVisible: true, isCountingDown: true)
        XCTAssertTrue(clock.isTicking)

        clock.update(isVisible: true, isCountingDown: false)
        XCTAssertFalse(clock.isTicking, "an indefinite Session has nothing to count down")

        clock.update(isVisible: false, isCountingDown: true)
        XCTAssertFalse(clock.isTicking, "a closed popover must not refresh anything")
        XCTAssertFalse(clock.isVisible)
    }

    func testTheTrailIsToldWhatTheWindowIsDoing() {
        let clock = makeClock()

        clock.update(isVisible: false, isCountingDown: false)
        XCTAssertFalse(clock.isVisible)

        clock.update(isVisible: true, isCountingDown: true)
        XCTAssertTrue(clock.isVisible)
    }

    func testStartingTheClockRefreshesWhatItDrawsFor() {
        let face = ClockFace()
        let clock = makeClock(face: face)

        // The popover may have been closed for an hour. The first frame after
        // it reopens has to be drawn for now, not for then.
        face.now = face.now.addingTimeInterval(3600)
        clock.update(isVisible: true, isCountingDown: true)

        XCTAssertEqual(clock.now, face.now)
    }

    func testAStoppedClockDoesNotRefresh() {
        let face = ClockFace()
        let clock = makeClock(face: face)
        clock.update(isVisible: false, isCountingDown: true)
        let before = clock.now

        face.now = face.now.addingTimeInterval(3600)
        clock.update(isVisible: false, isCountingDown: true)

        XCTAssertEqual(clock.now, before)
    }

    func testTheClockAdvancesWhileItRuns() async {
        let face = ClockFace()
        let clock = SessionPresentationClock(
            dateProvider: { face.now },
            interval: .milliseconds(1)
        )

        clock.update(isVisible: true, isCountingDown: true)
        face.now = face.now.addingTimeInterval(5)

        let deadline = Date().addingTimeInterval(2)
        while clock.now != face.now, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }

        XCTAssertEqual(clock.now, face.now)

        clock.update(isVisible: false, isCountingDown: false)
    }

    private func makeClock(face: ClockFace = ClockFace()) -> SessionPresentationClock {
        SessionPresentationClock(dateProvider: { face.now }, interval: .seconds(3600))
    }

    /// A clock the cases move by hand.
    private final class ClockFace {
        var now = Date(timeIntervalSince1970: 1_700_000_000)
    }
}
