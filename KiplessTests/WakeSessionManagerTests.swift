import XCTest
@testable import Kipless

@MainActor
final class WakeSessionManagerTests: XCTestCase {
    private var clock = TestClock()
    private var assertions = MockSleepAssertionManager()
    private var sleeper = GatedDeadlineSleeper()
    private var manager: WakeSessionManager!

    override func setUp() async throws {
        try await super.setUp()
        clock = TestClock()
        assertions = MockSleepAssertionManager()
        sleeper = GatedDeadlineSleeper()
        manager = makeManager()
    }

    /// A manager whose clock and deadline waits the test moves by hand, so no
    /// case here waits on real time.
    private func makeManager(
        lidSleepOverride: LidSleepOverrideClient = PrivilegedHelperClient(),
        terminationTimeout: Duration = WakeSessionManager.defaultTerminationTimeout
    ) -> WakeSessionManager {
        let sleeper = self.sleeper

        return WakeSessionManager(
            assertions: assertions,
            lidSleepOverride: lidSleepOverride,
            dateProvider: { [clock] in clock.now },
            terminationTimeout: terminationTimeout,
            sleeper: { duration in await sleeper.sleep(for: duration) }
        )
    }

    // MARK: - Starting

    func testStartsInactive() {
        XCTAssertFalse(manager.isActive)
        XCTAssertNil(manager.session)
        XCTAssertNil(remainingSeconds)
        XCTAssertEqual(assertions.releaseCount, 0)
    }

    func testStartAcquiresAssertionAndActivates() {
        manager.start(mode: .system, duration: .minutes30)

        XCTAssertTrue(manager.isActive)
        XCTAssertEqual(manager.session?.mode, .system)
        XCTAssertEqual(assertions.acquiredModes, [.system])
        XCTAssertTrue(assertions.isHolding)
        XCTAssertNil(manager.errorMessage)
    }

    func testStartStopsThePreviousSessionFirst() {
        manager.start(mode: .system, duration: .minutes30)
        manager.start(mode: .display, duration: .hour1)

        // Every start begins by clearing whatever was held, so the sequence has
        // a release in front of it too — the point is that no acquire is ever
        // followed by another acquire without a release in between.
        XCTAssertEqual(
            assertions.events,
            [.release, .acquire(.system), .release, .acquire(.display)]
        )
        XCTAssertEqual(assertions.maxHeldCount, 1)
        XCTAssertEqual(manager.session?.mode, .display)
    }

    func testSwitchingBetweenModesKeepsOneAssertion() {
        manager.start(mode: .system, duration: .indefinite)
        manager.start(mode: .display, duration: .indefinite)

        XCTAssertTrue(assertions.isHolding)
        XCTAssertEqual(assertions.maxHeldCount, 1)
        XCTAssertEqual(manager.session?.mode, .display)
    }

    func testSwitchingFromDisplayToSystemKeepsOneAssertion() {
        manager.start(mode: .display, duration: .indefinite)
        manager.start(mode: .system, duration: .indefinite)

        XCTAssertEqual(manager.session?.mode, .system)
        XCTAssertEqual(assertions.maxHeldCount, 1)
        XCTAssertEqual(assertions.events, [
            .release, .acquire(.display), .release, .acquire(.system)
        ])
    }

    func testFailedReplacementLeavesTheManagerInactiveAndReleasesTheOldAssertion() {
        manager.start(mode: .system, duration: .indefinite)
        assertions.errorToThrow = SleepAssertionError.creationFailed(mode: .display, code: -1)

        manager.start(mode: .display, duration: .indefinite)

        XCTAssertFalse(manager.isActive)
        XCTAssertNil(manager.session)
        XCTAssertFalse(assertions.isHolding)
        XCTAssertEqual(assertions.maxHeldCount, 1)
    }

    // MARK: - Stopping

    func testStopReleasesAssertionAndDeactivates() {
        manager.start(mode: .display, duration: .hour2)
        manager.stop()

        XCTAssertFalse(manager.isActive)
        XCTAssertNil(manager.session)
        XCTAssertFalse(assertions.isHolding)
    }

    func testStopWhenInactiveIsHarmless() {
        manager.stop()
        manager.stop()

        XCTAssertFalse(manager.isActive)
        XCTAssertEqual(assertions.acquiredModes, [])
    }

    func testRepeatedStartStopLeavesNothingHeld() {
        for _ in 0..<5 {
            manager.start(mode: .system, duration: .minutes15)
            manager.stop()
        }

        XCTAssertFalse(manager.isActive)
        XCTAssertFalse(assertions.isHolding)
        XCTAssertEqual(assertions.acquiredModes.count, 5)
        XCTAssertEqual(assertions.maxHeldCount, 1, "two assertions must never be held at once")
    }

    // MARK: - Failure

    func testFailedAcquisitionDoesNotActivateTheSession() {
        assertions.errorToThrow = SleepAssertionError.creationFailed(mode: .system, code: -1)

        manager.start(mode: .system, duration: .minutes30)

        XCTAssertFalse(manager.isActive)
        XCTAssertNil(manager.session)
        XCTAssertNotNil(manager.errorMessage)
        XCTAssertNil(remainingSeconds)
    }

    func testClosedLidApprovalFailureAsksForApprovalInsteadOfStarting() async {
        let helper = FakeLidSleepOverrideClient(
            error: PrivilegedHelperClientError.helperApprovalRequired,
            approvalRequired: true
        )
        manager = makeManager(lidSleepOverride: helper)

        manager.start(mode: .closedLid, duration: .hour1)
        for _ in 0..<10 where manager.isTransitioning {
            await Task.yield()
        }

        XCTAssertFalse(manager.isActive)
        // Approving the helper is the user's call, so it is asked with a
        // dialog; the panel's status row is left to actual failures.
        XCTAssertNil(manager.errorMessage)
        XCTAssertTrue(manager.lidApprovalIsRequired)

        manager.acknowledgeLidApprovalRequest()
        XCTAssertFalse(manager.lidApprovalIsRequired)
    }

    func testTerminationDoesNotWaitForeverForTheClosedLidRelease() async {
        let helper = NeverReleasingLidSleepOverrideClient()
        manager = makeManager(
            lidSleepOverride: helper,
            terminationTimeout: .milliseconds(50)
        )

        manager.start(mode: .closedLid, duration: .hour1)
        for _ in 0..<10 where manager.isTransitioning {
            await Task.yield()
        }
        XCTAssertTrue(manager.isActive)

        // The helper accepts the release and never answers. Quitting must still
        // be allowed to proceed, otherwise the app is stuck in AppKit's modal
        // terminate wait and cannot be quit.
        let finished = expectation(description: "termination is allowed to proceed")
        manager.prepareForTermination { finished.fulfill() }

        await fulfillment(of: [finished], timeout: 1)
    }

    func testClosedLidHelperTimeoutLeavesNoStuckTransition() async {
        let helper = FakeLidSleepOverrideClient(
            error: PrivilegedHelperClientError.helperNotResponding
        )
        manager = makeManager(lidSleepOverride: helper)

        manager.start(mode: .closedLid, duration: .hour1)
        for _ in 0..<10 where manager.isTransitioning {
            await Task.yield()
        }

        XCTAssertFalse(manager.isActive)
        // A stalled helper must not leave the UI in the transitional state,
        // where Start stays disabled and the countdown never moves.
        XCTAssertFalse(manager.isTransitioning)
        XCTAssertNotNil(manager.errorMessage)
        XCTAssertFalse(manager.lidApprovalIsRequired)
    }

    func testSuccessfulStartClearsAPreviousError() {
        assertions.errorToThrow = SleepAssertionError.creationFailed(mode: .system, code: -1)
        manager.start(mode: .system, duration: .minutes30)
        XCTAssertNotNil(manager.errorMessage)

        assertions.errorToThrow = nil
        manager.start(mode: .system, duration: .minutes30)

        XCTAssertTrue(manager.isActive)
        XCTAssertNil(manager.errorMessage)
    }

    // MARK: - Time

    func testRemainingTimeIsDerivedFromTheDeadline() {
        manager.start(mode: .system, duration: .minutes30)

        XCTAssertEqual(remainingSeconds, 30 * 60)

        // The value must come from the clock, not from decrementing a counter.
        clock.advance(by: 12 * 60)

        XCTAssertEqual(remainingSeconds, 18 * 60)
    }

    func testIndefiniteSessionHasNoDeadline() async {
        manager.start(mode: .display, duration: .indefinite)

        XCTAssertNil(manager.session?.expiresAt)
        XCTAssertNil(remainingSeconds)

        clock.advance(by: 48 * 3600)
        await settle()

        XCTAssertTrue(manager.isActive, "an indefinite session runs until stopped")
        XCTAssertTrue(assertions.isHolding)
    }

    // MARK: - Expiry

    func testATimedSessionParksOneWaitOnItsWholeDeadline() async {
        manager.start(mode: .system, duration: .minutes30)
        await waitUntil("the deadline wait is parked") { self.sleeper.waits.count == 1 }

        // One wait for the whole interval rather than a tick per second. This is
        // the difference between a Session that costs nothing in the background
        // and one that wakes the app up 86,400 times a day.
        XCTAssertEqual(sleeper.requestedSeconds, [30 * 60])
    }

    func testAnIndefiniteSessionParksNoWaitAtAll() async {
        manager.start(mode: .display, duration: .indefinite)
        await settle()

        XCTAssertEqual(sleeper.waits.count, 0)
    }

    func testStoppingCancelsTheParkedWait() async {
        manager.start(mode: .system, duration: .minutes30)
        await waitUntil("the deadline wait is parked") { self.sleeper.waits.count == 1 }

        manager.stop()
        await waitUntil("the parked wait is released") { self.sleeper.parkedCount == 0 }

        clock.advance(by: 60 * 60)
        sleeper.elapseEveryWait()
        await settle()

        XCTAssertEqual(sleeper.waits.count, 1, "a stopped Session must not park another wait")
        XCTAssertFalse(manager.isActive)
        XCTAssertFalse(assertions.isHolding)
    }

    func testTheDeadlineEndsTheSessionAndReleasesTheAssertion() async {
        manager.start(mode: .system, duration: .minutes15)
        await waitUntil("the deadline wait is parked") { self.sleeper.waits.count == 1 }

        clock.advance(by: 15 * 60)
        sleeper.elapseWait(at: 0)
        await waitUntil("the session ends at its deadline") { !self.manager.isActive }

        XCTAssertNil(manager.session)
        XCTAssertFalse(assertions.isHolding, "expiry must release the assertion")
    }

    func testWakingEarlyWaitsAgainForExactlyWhatIsLeft() async {
        manager.start(mode: .system, duration: .minutes30)
        await waitUntil("the deadline wait is parked") { self.sleeper.waits.count == 1 }

        // A wait that returns before the deadline — a timer firing early, or a
        // clock that moved — must not be mistaken for the deadline arriving.
        clock.advance(by: 60)
        sleeper.elapseWait(at: 0)
        await waitUntil("the session parks a second wait") { self.sleeper.waits.count == 2 }

        XCTAssertEqual(sleeper.requestedSeconds, [30 * 60, 29 * 60])
        XCTAssertTrue(manager.isActive)
    }

    func testASessionThatExpiredWhileTheMacSleptEndsOnWake() async {
        manager.start(mode: .system, duration: .hour1)
        await waitUntil("the deadline wait is parked") { self.sleeper.waits.count == 1 }

        // The wait is still parked, because nothing about the Mac sleeping makes
        // a timer fire. Re-reading the deadline on wake is what ends it.
        clock.advance(by: 3 * 3600)
        XCTAssertTrue(manager.isActive)

        manager.systemDidWake()
        await waitUntil("the session ends once the Mac is back") { !self.manager.isActive }

        XCTAssertFalse(assertions.isHolding)
    }

    func testAWakeBeforeTheDeadlineLeavesTheSessionRunning() async {
        manager.start(mode: .system, duration: .hour1)
        await waitUntil("the deadline wait is parked") { self.sleeper.waits.count == 1 }

        clock.advance(by: 10 * 60)
        manager.systemDidWake()
        await waitUntil("the session parks a fresh wait") { self.sleeper.waits.count == 2 }

        XCTAssertEqual(sleeper.requestedSeconds, [3600, 50 * 60])
        XCTAssertTrue(manager.isActive)
    }

    func testWakingWhileInactiveParksNothing() async {
        manager.systemDidWake()
        await settle()

        XCTAssertEqual(sleeper.waits.count, 0)
    }

    func testAReplacedSessionIsNotEndedByTheDeadlineItLeftBehind() async {
        manager.start(mode: .system, duration: .minutes15)
        await waitUntil("the first deadline wait is parked") { self.sleeper.waits.count == 1 }

        clock.advance(by: 15 * 60)
        manager.start(mode: .display, duration: .hour2)
        await waitUntil("the replacement parks its own wait") { self.sleeper.waits.count == 2 }

        // The first Session's wait is let go after its deadline has already
        // passed. It must not take down the Session that replaced it.
        sleeper.elapseEveryWait()
        await settle()

        XCTAssertEqual(manager.session?.mode, .display)
        XCTAssertTrue(assertions.isHolding)
        XCTAssertEqual(assertions.maxHeldCount, 1)
    }

    func testStoppingAgainAfterExpiryIsHarmless() async {
        manager.start(mode: .system, duration: .minutes15)
        await waitUntil("the deadline wait is parked") { self.sleeper.waits.count == 1 }

        clock.advance(by: 15 * 60)
        sleeper.elapseWait(at: 0)
        await waitUntil("the session ends at its deadline") { !self.manager.isActive }

        manager.stop()
        await settle()

        XCTAssertEqual(assertions.maxHeldCount, 1)
        XCTAssertFalse(assertions.isHolding)
    }

    // MARK: - Test helpers

    private var remainingSeconds: Int? {
        SessionRingProgress.remainingSeconds(session: manager.session, at: clock.now)
    }

    private func waitUntil(
        _ description: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: () -> Bool
    ) async {
        for _ in 0..<1_000 {
            if condition() { return }
            await Task.yield()
        }

        XCTFail("Timed out waiting until \(description).", file: file, line: line)
    }

    private func settle() async {
        for _ in 0..<50 {
            await Task.yield()
        }
    }
}

/// Drives the manager's deadline waits by hand.
///
/// The manager parks a single wait on a Session's deadline instead of polling
/// it, so a case's job is to decide when that wait elapses — and to check that
/// the wait asked for the whole remaining interval rather than a fixed tick.
@MainActor
final class GatedDeadlineSleeper {
    /// One entry per wait the manager has parked, in the order it asked.
    final class Wait {
        fileprivate(set) var seconds: TimeInterval = 0
        fileprivate var continuation: CheckedContinuation<Void, Never>?

        fileprivate func release() {
            guard let continuation else { return }
            self.continuation = nil
            continuation.resume()
        }
    }

    private(set) var waits: [Wait] = []

    /// What each wait asked for, in order.
    var requestedSeconds: [TimeInterval] { waits.map(\.seconds) }

    /// How many waits are parked right now.
    var parkedCount: Int { waits.filter { $0.continuation != nil }.count }

    func sleep(for duration: Duration) async {
        let index = waits.count
        let wait = Wait()
        wait.seconds = Self.seconds(of: duration)
        waits.append(wait)

        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume()
                } else {
                    wait.continuation = continuation
                }
            }
        } onCancel: {
            // `Task.sleep` is what this stands in for, and it resumes when the
            // manager cancels a wait it no longer needs.
            Task { @MainActor [weak self] in
                self?.waits[index].release()
            }
        }
    }

    /// Lets the wait at `index` elapse, as its deadline arriving would.
    func elapseWait(at index: Int) {
        guard waits.indices.contains(index) else {
            XCTFail("No parked wait at index \(index).")
            return
        }

        waits[index].release()
    }

    /// Lets every wait so far elapse.
    func elapseEveryWait() {
        for wait in waits {
            wait.release()
        }
    }

    private static func seconds(of duration: Duration) -> TimeInterval {
        let components = duration.components

        return TimeInterval(components.seconds)
            + (TimeInterval(components.attoseconds) / 1e18)
    }
}

/// A clock the tests move by hand.
@MainActor
final class TestClock {
    private let origin = Date(timeIntervalSince1970: 1_700_000_000)
    private var offset: TimeInterval = 0

    var now: Date { origin.addingTimeInterval(offset) }

    func advance(by seconds: TimeInterval) {
        offset += seconds
    }
}

private final class FakeLidSleepOverrideClient: @unchecked Sendable, LidSleepOverrideClient {
    var error: Error?
    var approvalRequired: Bool

    init(error: Error? = nil, approvalRequired: Bool = false) {
        self.error = error
        self.approvalRequired = approvalRequired
    }

    func acquireLidSleepOverride() async throws {
        if let error { throw error }
    }

    func releaseLidSleepOverride() async throws {}

    func helperApprovalIsRequired() -> Bool { approvalRequired }

    func invalidate() {}
}

private final class NeverReleasingLidSleepOverrideClient: @unchecked Sendable, LidSleepOverrideClient {
    func acquireLidSleepOverride() async throws {}

    func releaseLidSleepOverride() async throws {
        // Models a helper that takes the release message and never answers.
        try? await Task.sleep(for: .seconds(3600))
    }

    func helperApprovalIsRequired() -> Bool { false }

    func invalidate() {}
}
