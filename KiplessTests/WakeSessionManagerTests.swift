import XCTest
@testable import Kipless

@MainActor
final class WakeSessionManagerTests: XCTestCase {
    private var clock = TestClock()
    private var assertions = MockSleepAssertionManager()
    private var manager: WakeSessionManager!

    override func setUp() {
        super.setUp()
        clock = TestClock()
        assertions = MockSleepAssertionManager()
        manager = WakeSessionManager(
            assertions: assertions,
            dateProvider: { [clock] in clock.now }
        )
    }

    // MARK: - Starting

    func testStartsInactive() {
        XCTAssertFalse(manager.isActive)
        XCTAssertNil(manager.session)
        XCTAssertNil(manager.remainingSeconds)
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
        XCTAssertNil(manager.remainingSeconds)
    }

    func testClosedLidApprovalFailureAsksForApprovalInsteadOfStarting() async {
        let helper = FakeLidSleepOverrideClient(
            error: PrivilegedHelperClientError.helperApprovalRequired,
            approvalRequired: true
        )
        manager = WakeSessionManager(
            assertions: assertions,
            lidSleepOverride: helper,
            dateProvider: { [clock] in clock.now }
        )

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
        manager = WakeSessionManager(
            assertions: assertions,
            lidSleepOverride: helper,
            dateProvider: { [clock] in clock.now },
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
        manager = WakeSessionManager(
            assertions: assertions,
            lidSleepOverride: helper,
            dateProvider: { [clock] in clock.now }
        )

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
        XCTAssertEqual(manager.remainingSeconds, 30 * 60)

        // The value must come from the clock, not from decrementing a counter.
        clock.advance(by: 12 * 60)
        manager.tickForTesting()

        XCTAssertEqual(manager.remainingSeconds, 18 * 60)
    }

    func testTimedSessionExpiresOnItsDeadline() {
        manager.start(mode: .system, duration: .minutes15)

        clock.advance(by: 14 * 60 + 59)
        manager.tickForTesting()
        XCTAssertTrue(manager.isActive, "must still be running one second before the deadline")

        clock.advance(by: 1)
        manager.tickForTesting()

        XCTAssertFalse(manager.isActive)
        XCTAssertFalse(assertions.isHolding, "expiry must release the assertion")
    }

    func testExpiryDoesNotDependOnTickFrequency() {
        manager.start(mode: .system, duration: .minutes15)

        // Sleep past the deadline in one jump, as a Mac waking from sleep would.
        clock.advance(by: 6 * 3600)
        manager.tickForTesting()

        XCTAssertFalse(manager.isActive)
        XCTAssertFalse(assertions.isHolding)
    }

    func testIndefiniteSessionHasNoDeadline() {
        manager.start(mode: .display, duration: .indefinite)

        XCTAssertNil(manager.session?.expiresAt)
        XCTAssertNil(manager.remainingSeconds)

        clock.advance(by: 48 * 3600)
        manager.tickForTesting()

        XCTAssertTrue(manager.isActive, "an indefinite session runs until stopped")
        XCTAssertTrue(assertions.isHolding)
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
