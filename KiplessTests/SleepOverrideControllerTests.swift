import XCTest
@testable import Kipless

final class SleepOverrideControllerTests: XCTestCase {
    func testAcquireFromDisabledBaselineEnablesAndReleaseRestoresIt() throws {
        let driver = RecordingSleepOverrideDriver(state: false)
        let controller = SleepOverrideController(driver: driver)

        try controller.acquireOverride()
        XCTAssertEqual(
            driver.operations,
            [.read, .enable, .read]
        )
        XCTAssertEqual(
            controller.ownership,
            SleepOverrideOwnership(baselineWasDisabled: false, modifiedByKipless: true)
        )

        try controller.releaseOverride()
        XCTAssertEqual(driver.operations, [.read, .enable, .read, .disable, .read])
        XCTAssertFalse(controller.hasLease)
        XCTAssertFalse(driver.state)
    }

    func testAcquireFromEnabledBaselineDoesNotChangeSystemState() throws {
        let driver = RecordingSleepOverrideDriver(state: true)
        let controller = SleepOverrideController(driver: driver)

        try controller.acquireOverride()
        try controller.releaseOverride()

        XCTAssertEqual(driver.operations, [.read])
        XCTAssertNil(controller.ownership)
        XCTAssertFalse(controller.hasLease)
        XCTAssertTrue(driver.state)
    }

    func testRepeatedAcquireAndReleaseAreIdempotent() throws {
        let driver = RecordingSleepOverrideDriver(state: false)
        let controller = SleepOverrideController(driver: driver)

        try controller.acquireOverride()
        try controller.acquireOverride()
        try controller.releaseOverride()
        try controller.releaseOverride()

        XCTAssertEqual(driver.operations, [.read, .enable, .read, .disable, .read])
        XCTAssertFalse(controller.hasLease)
    }

    func testEnableFailureDoesNotCreateLease() {
        let driver = RecordingSleepOverrideDriver(state: false)
        driver.enableError = TestDriverError.failed
        let controller = SleepOverrideController(driver: driver)

        XCTAssertThrowsError(try controller.acquireOverride())
        XCTAssertFalse(controller.hasLease)
        XCTAssertNil(controller.ownership)
    }

    func testWrongPostEnableStateDoesNotCreateLease() {
        let driver = RecordingSleepOverrideDriver(state: false)
        driver.stateAfterEnable = false
        let controller = SleepOverrideController(driver: driver)

        XCTAssertThrowsError(try controller.acquireOverride())
        XCTAssertFalse(controller.hasLease)
        XCTAssertNil(controller.ownership)
    }

    func testFailedReleaseKeepsLeaseForRetry() throws {
        let driver = RecordingSleepOverrideDriver(state: false)
        let controller = SleepOverrideController(driver: driver)
        try controller.acquireOverride()
        driver.disableError = TestDriverError.failed

        XCTAssertThrowsError(try controller.releaseOverride())
        XCTAssertTrue(controller.hasLease)

        driver.disableError = nil
        try controller.releaseOverride()
        XCTAssertFalse(controller.hasLease)
    }
}

private enum DriverOperation: Equatable {
    case read
    case enable
    case disable
}

private enum TestDriverError: Error {
    case failed
}

private final class RecordingSleepOverrideDriver: SleepOverrideDriving {
    var state: Bool
    var stateAfterEnable: Bool?
    var enableError: Error?
    var disableError: Error?
    private(set) var operations: [DriverOperation] = []

    init(state: Bool) {
        self.state = state
    }

    func readState() throws -> Bool {
        operations.append(.read)
        return state
    }

    func enable() throws {
        operations.append(.enable)
        if let enableError { throw enableError }
        state = stateAfterEnable ?? true
    }

    func disable() throws {
        operations.append(.disable)
        if let disableError { throw disableError }
        state = false
    }
}
