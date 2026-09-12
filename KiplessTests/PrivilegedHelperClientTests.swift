import XCTest
@testable import Kipless

final class PrivilegedHelperClientTests: XCTestCase {
    func testEnabledStateCodeMapsToEnabledState() async throws {
        let remote = FakeSleepHelperRemote(stateCode: SleepOverrideSystemState.enabled.rawValue)
        let client = PrivilegedHelperClient(remote: remote)

        let state = try await client.getSleepOverrideState()
        XCTAssertEqual(state, .enabled)
    }

    func testDisabledStateCodeMapsToDisabledState() async throws {
        let remote = FakeSleepHelperRemote(stateCode: SleepOverrideSystemState.disabled.rawValue)
        let client = PrivilegedHelperClient(remote: remote)

        let state = try await client.getSleepOverrideState()
        XCTAssertEqual(state, .disabled)
    }

    func testUnknownStateCodeFailsClosed() async {
        let remote = FakeSleepHelperRemote(stateCode: SleepOverrideSystemState.unknown.rawValue)
        let client = PrivilegedHelperClient(remote: remote)

        do {
            _ = try await client.getSleepOverrideState()
            XCTFail("Unknown helper state must not be treated as disabled")
        } catch {
            XCTAssertTrue(error is PrivilegedHelperClientError)
        }
    }

    func testRemoteOperationFailureIsPropagated() async {
        let remote = FakeSleepHelperRemote(operationSuccess: false, message: "not approved")
        let client = PrivilegedHelperClient(remote: remote)

        do {
            try await client.enableSleepOverride()
            XCTFail("The client must reject an unsuccessful helper operation")
        } catch let error as PrivilegedHelperClientError {
            XCTAssertEqual(error.message, "not approved")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private final class FakeSleepHelperRemote: NSObject, KiplessSleepHelperProtocol {
    let stateCode: Int
    let operationSuccess: Bool
    let message: String?

    init(
        stateCode: Int = SleepOverrideSystemState.disabled.rawValue,
        operationSuccess: Bool = true,
        message: String? = nil
    ) {
        self.stateCode = stateCode
        self.operationSuccess = operationSuccess
        self.message = message
    }

    func getState(withReply reply: @escaping (Int, String?) -> Void) {
        reply(stateCode, message)
    }

    func acquireSleepOverride(withReply reply: @escaping (Bool, String?) -> Void) {
        reply(operationSuccess, message)
    }

    func releaseSleepOverride(withReply reply: @escaping (Bool, String?) -> Void) {
        reply(operationSuccess, message)
    }
}
