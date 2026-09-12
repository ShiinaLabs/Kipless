import XCTest
@testable import Kipless

final class PMSetSleepOverrideDriverTests: XCTestCase {
    func testEnableUsesOnlyFixedEnableAndVerificationOperations() throws {
        let runner = RecordingPMSetRunner(outputs: [
            .enable: [""],
            .readState: ["SleepDisabled 1"]
        ])
        let driver = PMSetSleepOverrideDriver(runner: runner)

        try driver.enable()

        XCTAssertEqual(runner.operations, [.enable, .readState])
    }

    func testDisableUsesOnlyFixedDisableAndVerificationOperations() throws {
        let runner = RecordingPMSetRunner(outputs: [
            .disable: [""],
            .readState: ["SleepDisabled 0"]
        ])
        let driver = PMSetSleepOverrideDriver(runner: runner)

        try driver.disable()

        XCTAssertEqual(runner.operations, [.disable, .readState])
    }

    func testReadStateReturnsParsedState() throws {
        let runner = RecordingPMSetRunner(outputs: [
            .readState: ["SleepDisabled 1"]
        ])
        let driver = PMSetSleepOverrideDriver(runner: runner)

        XCTAssertEqual(try driver.readState(), true)
        XCTAssertEqual(runner.operations, [.readState])
    }

    func testUnknownVerificationStateFailsTheWrite() {
        let runner = RecordingPMSetRunner(outputs: [
            .enable: [""],
            .readState: ["SleepDisabled maybe"]
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
