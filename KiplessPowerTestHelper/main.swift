import Foundation
import Darwin
import IOKit.pwr_mgt

private enum HelperFailure: Error, CustomStringConvertible {
    case usage
    case assertion(mode: String, code: IOReturn)

    var description: String {
        switch self {
        case .usage:
            "Usage: KiplessPowerTestHelper system|display|hold-system|hold-display|replace-system-display|replace-display-system"
        case let .assertion(mode, code):
            "Could not create the \(mode) assertion (IOKit error \(code))."
        }
    }
}

private func emit(_ message: String) {
    let data = Data((message + "\n").utf8)
    FileHandle.standardOutput.write(data)
}

private func assertionType(for mode: String) -> CFString? {
    switch mode {
    case "system":
        kIOPMAssertionTypePreventUserIdleSystemSleep as CFString
    case "display":
        kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString
    default:
        nil
    }
}

private func acquire(mode: String) throws -> IOPMAssertionID {
    guard let type = assertionType(for: mode) else { throw HelperFailure.usage }

    var id: IOPMAssertionID = 0
    let reason = "Kipless is keeping your Mac awake." as CFString
    let result = IOPMAssertionCreateWithName(
        type,
        IOPMAssertionLevel(kIOPMAssertionLevelOn),
        reason,
        &id
    )

    guard result == kIOReturnSuccess else {
        throw HelperFailure.assertion(mode: mode, code: result)
    }
    return id
}

private func release(_ id: IOPMAssertionID, mode: String) {
    IOPMAssertionRelease(id)
    emit("KIPLESS_ASSERTION_RELEASED \(mode)")
}

private func hold(_ id: IOPMAssertionID, mode: String) -> Never {
    signal(SIGTERM, SIG_IGN)
    let signalSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
    signalSource.setEventHandler {
        release(id, mode: mode)
        exit(EXIT_SUCCESS)
    }
    signalSource.resume()
    dispatchMain()
}

private func hold(for mode: String) throws {
    let id = try acquire(mode: mode)
    emit("KIPLESS_ASSERTION_READY \(mode)")
    hold(id, mode: mode)
}

private func runOnce(for mode: String) throws {
    let id = try acquire(mode: mode)
    emit("KIPLESS_ASSERTION_READY \(mode)")
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 1))
    release(id, mode: mode)
}

private func replace(first: String, second: String) throws {
    let firstID = try acquire(mode: first)
    emit("KIPLESS_ASSERTION_READY \(first)")
    release(firstID, mode: first)

    let secondID = try acquire(mode: second)
    emit("KIPLESS_ASSERTION_READY \(second)")
    hold(secondID, mode: second)
}

let command = CommandLine.arguments.dropFirst().first

do {
    switch command {
    case "system":
        try runOnce(for: "system")
    case "display":
        try runOnce(for: "display")
    case "hold-system":
        try hold(for: "system")
    case "hold-display":
        try hold(for: "display")
    case "replace-system-display":
        try replace(first: "system", second: "display")
    case "replace-display-system":
        try replace(first: "display", second: "system")
    default:
        throw HelperFailure.usage
    }
} catch {
    FileHandle.standardError.write(Data(("KiplessPowerTestHelper: \(error)\n").utf8))
    exit(EXIT_FAILURE)
}
