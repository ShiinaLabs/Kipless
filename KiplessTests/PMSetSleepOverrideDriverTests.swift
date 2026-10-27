import XCTest
@testable import Kipless

final class PMSetSleepOverrideDriverTests: XCTestCase {
    func testEnableUsesOnlyFixedEnableAndVerificationOperations() throws {
        let runner = RecordingPMSetRunner(outputs: [
            .enable: [""],
            .readState: ["System-wide power settings:\n SleepDisabled 1\n"]
        ])
        let driver = PMSetSleepOverrideDriver(runner: runner)

        try driver.enable()

        XCTAssertEqual(runner.operations, [.enable, .readState])
    }

    func testDisableUsesOnlyFixedDisableAndVerificationOperations() throws {
        let runner = RecordingPMSetRunner(outputs: [
            .disable: [""],
            .readState: ["System-wide power settings:\n SleepDisabled 0\n"]
        ])
        let driver = PMSetSleepOverrideDriver(runner: runner)

        try driver.disable()

        XCTAssertEqual(runner.operations, [.disable, .readState])
    }

    func testReadStateReturnsParsedState() throws {
        let runner = RecordingPMSetRunner(outputs: [
            .readState: ["System-wide power settings:\n SleepDisabled 1\n"]
        ])
        let driver = PMSetSleepOverrideDriver(runner: runner)

        XCTAssertEqual(try driver.readState(), true)
        XCTAssertEqual(runner.operations, [.readState])
    }

    func testReadStateTreatsMissingSleepDisabledAsNotDisabledInValidOutput() throws {
        let runner = RecordingPMSetRunner(outputs: [
            .readState: [
                "System-wide power settings:\n DestroyFVKeyOnStandby\t\t0\n VACTDisabled\t\t0\n"
            ]
        ])
        let driver = PMSetSleepOverrideDriver(runner: runner)

        XCTAssertFalse(try driver.readState())
        XCTAssertEqual(runner.operations, [.readState])
    }

    func testControllerAcquiresAndReleasesWhenSleepDisabledIsOmittedAtBaseline() throws {
        let normalOutput =
            "System-wide power settings:\n DestroyFVKeyOnStandby\t\t0\n VACTDisabled\t\t0\n"
        let enabledOutput = "System-wide power settings:\n SleepDisabled 1\n"
        let runner = RecordingPMSetRunner(outputs: [
            .readState: [normalOutput, enabledOutput, enabledOutput, normalOutput, normalOutput],
            .enable: [""],
            .disable: [""]
        ])
        let driver = PMSetSleepOverrideDriver(runner: runner)
        let controller = SleepOverrideController(driver: driver)

        try controller.acquireOverride()
        XCTAssertTrue(controller.hasLease)
        XCTAssertEqual(
            controller.ownership,
            SleepOverrideOwnership(baselineWasDisabled: false, modifiedByKipless: true)
        )

        try controller.releaseOverride()

        XCTAssertFalse(controller.hasLease)
        XCTAssertEqual(
            runner.operations,
            [.readState, .enable, .readState, .readState, .disable, .readState, .readState]
        )
    }

    func testUnknownVerificationStateFailsTheWrite() {
        let runner = RecordingPMSetRunner(outputs: [
            .enable: [""],
            .readState: ["SleepDisabled maybe"]
        ])
        let driver = PMSetSleepOverrideDriver(runner: runner)

        XCTAssertThrowsError(try driver.enable())
    }

    func testWrongVerificationStateFailsTheWrite() {
        let runner = RecordingPMSetRunner(outputs: [
            .enable: [""],
            .readState: ["System-wide power settings:\n SleepDisabled 0\n"]
        ])
        let driver = PMSetSleepOverrideDriver(runner: runner)

        XCTAssertThrowsError(try driver.enable())
    }
}

private final class RecordingPMSetRunner: PMSetCommandRunning {
    private var outputs: [FixedPMSetOperation: [String]]
    private(set) var operations: [FixedPMSetOperation] = []

    init(outputs: [FixedPMSetOperation: [String]]) {
        self.outputs = outputs
    }

    func run(_ operation: FixedPMSetOperation) throws -> String {
        operations.append(operation)
        guard var values = outputs[operation], !values.isEmpty else {
            return ""
        }
        let output = values.removeFirst()
        outputs[operation] = values
        return output
    }
}
