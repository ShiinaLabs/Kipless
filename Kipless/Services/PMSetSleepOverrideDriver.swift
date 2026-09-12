import Foundation

enum FixedPMSetOperation: Hashable, Sendable {
    case readState
    case enable
    case disable

    var arguments: [String] {
        switch self {
        case .readState:
            ["-g"]
        case .enable:
            ["-a", "disablesleep", "1"]
        case .disable:
            ["-a", "disablesleep", "0"]
        }
    }
}

protocol PMSetCommandRunning: AnyObject {
    func run(_ operation: FixedPMSetOperation) throws -> String
}

protocol SleepOverrideDriving: AnyObject {
    func readState() throws -> Bool
    func enable() throws
    func disable() throws
}

enum PMSetSleepOverrideDriverError: LocalizedError, Equatable {
    case commandFailed(operation: FixedPMSetOperation, status: Int32, message: String)
    case unknownState(operation: FixedPMSetOperation, output: String)
    case verificationFailed(operation: FixedPMSetOperation, actual: SleepOverrideSystemState)

    var errorDescription: String? {
        switch self {
        case let .commandFailed(operation, status, message):
            "pmset \(operation) failed with status \(status): \(message)"
        case let .unknownState(operation, output):
            "pmset \(operation) returned an unknown SleepDisabled state: \(output)"
        case let .verificationFailed(operation, actual):
            "pmset \(operation) could not verify the expected SleepDisabled state; got \(actual)"
        }
    }
}

final class PMSetSleepOverrideDriver: SleepOverrideDriving {
    private let runner: PMSetCommandRunning

    init(runner: PMSetCommandRunning = ProcessPMSetCommandRunner()) {
        self.runner = runner
    }

    func readState() throws -> Bool {
        let output = try runner.run(.readState)
        switch SleepOverrideStateParser.parse(output) {
        case .disabled:
            return false
        case .enabled:
            return true
        case .unknown:
            throw PMSetSleepOverrideDriverError.unknownState(
                operation: .readState,
                output: output
            )
        }
    }

    func enable() throws {
        try set(.enable, expected: .enabled)
    }

    func disable() throws {
        try set(.disable, expected: .disabled)
    }

    private func set(
        _ operation: FixedPMSetOperation,
        expected: SleepOverrideSystemState
    ) throws {
        _ = try runner.run(operation)
        let output = try runner.run(.readState)
        let actual = SleepOverrideStateParser.parse(output)
        guard actual == expected else {
            if actual == .unknown {
                throw PMSetSleepOverrideDriverError.unknownState(
                    operation: .readState,
                    output: output
                )
            }
            throw PMSetSleepOverrideDriverError.verificationFailed(
                operation: operation,
                actual: actual
            )
        }
    }
}

private final class ProcessPMSetCommandRunner: PMSetCommandRunning {
    func run(_ operation: FixedPMSetOperation) throws -> String {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = operation.arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            throw PMSetSleepOverrideDriverError.commandFailed(
                operation: operation,
                status: -1,
                message: error.localizedDescription
            )
        }

        process.waitUntilExit()
        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: output, encoding: .utf8) ?? ""
        let stderr = String(data: errorOutput, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw PMSetSleepOverrideDriverError.commandFailed(
                operation: operation,
                status: process.terminationStatus,
                message: stderr.isEmpty ? stdout : stderr
            )
        }
        return stdout
    }
}
