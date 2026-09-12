import XCTest
@testable import Kipless

/// Destructive local tests for the real root helper. They are opt-in because
/// they temporarily change the Mac's SleepDisabled power policy.
final class LidAwakeIntegrationTests: XCTestCase {
    func testDisabledBaselineRoundTrip() async throws {
        try requireOptIn()
        let client = try makeClient()
        let baseline = try await client.getSleepOverrideState()
        guard baseline == .disabled else {
            client.invalidate()
            throw XCTSkip("Run this case with SleepDisabled 0")
        }

        do {
            try await client.enableSleepOverride()
            let enabledState = try await client.getSleepOverrideState()
            XCTAssertEqual(enabledState, .enabled)
            try await client.disableSleepOverride()
            let disabledState = try await client.getSleepOverrideState()
            XCTAssertEqual(disabledState, .disabled)
        } catch {
            try? await client.disableSleepOverride()
            client.invalidate()
            throw error
        }
        client.invalidate()
    }

    func testEnabledBaselineIsPreserved() async throws {
        try requireOptIn()
        let client = try makeClient()
        let baseline = try await client.getSleepOverrideState()
        guard baseline == .enabled else {
            client.invalidate()
            throw XCTSkip("Run this case with SleepDisabled 1")
        }

        do {
            try await client.enableSleepOverride()
            try await client.disableSleepOverride()
            let finalState = try await client.getSleepOverrideState()
            XCTAssertEqual(finalState, .enabled)
        } catch {
            client.invalidate()
            throw error
        }
        client.invalidate()
    }

    func testRepeatedAcquireAndReleaseRestoresBaseline() async throws {
        try requireOptIn()
        let client = try makeClient()
        let baseline = try await client.getSleepOverrideState()
        try requireKnown(baseline)

        do {
            try await client.enableSleepOverride()
            try await client.enableSleepOverride()
            try await client.disableSleepOverride()
            try await client.disableSleepOverride()
            let finalState = try await client.getSleepOverrideState()
            XCTAssertEqual(finalState, baseline)
        } catch {
            try? await client.disableSleepOverride()
            client.invalidate()
            throw error
        }
        client.invalidate()
    }

    func testConnectionInvalidationRestoresBaseline() async throws {
        try requireOptIn()
        let client = try makeClient()
        let baseline = try await client.getSleepOverrideState()
        try requireKnown(baseline)

        do {
            try await client.enableSleepOverride()
            client.invalidate()

            let observer = try makeClient()
            defer { observer.invalidate() }
            let restored = try await waitForState(baseline, using: observer)
            XCTAssertEqual(restored, baseline)
        } catch {
            client.invalidate()
            throw error
        }
    }

    private func requireOptIn() throws {
        guard ProcessInfo.processInfo.environment["KIPLESS_RUN_LID_AWAKE_INTEGRATION"] == "1" else {
            throw XCTSkip("Set KIPLESS_RUN_LID_AWAKE_INTEGRATION=1 to modify SleepDisabled")
        }
    }

    private func requireKnown(_ state: SleepOverrideSystemState) throws {
        guard state != .unknown else {
            throw IntegrationTestError.unknownState
        }
    }

    private func makeClient() throws -> PrivilegedHelperClient {
        let client = PrivilegedHelperClient()
        try client.connect()
        return client
    }

    private func waitForState(
        _ expected: SleepOverrideSystemState,
        using client: PrivilegedHelperClient
    ) async throws -> SleepOverrideSystemState {
        for _ in 0..<25 {
            let state = try await client.getSleepOverrideState()
            if state == expected { return state }
            try await Task.sleep(for: .milliseconds(200))
        }
        throw IntegrationTestError.stateDidNotRestore(expected: expected)
    }
}

private enum IntegrationTestError: LocalizedError {
    case unknownState
    case stateDidNotRestore(expected: SleepOverrideSystemState)

    var errorDescription: String? {
        switch self {
        case .unknownState:
            "The helper returned an unknown SleepDisabled state"
        case let .stateDidNotRestore(expected):
            "SleepDisabled did not restore to \(expected)"
        }
    }
}
