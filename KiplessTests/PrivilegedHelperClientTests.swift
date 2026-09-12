import ServiceManagement
import XCTest
@testable import Kipless

final class PrivilegedHelperClientTests: XCTestCase {
    func testRequiresApprovalIsReportedBeforeConnectingToHelper() {
        let client = PrivilegedHelperClient(statusProvider: { .requiresApproval })

        do {
            try client.connect()
            XCTFail("A helper that needs approval must not be treated as connected")
        } catch let error as PrivilegedHelperClientError {
            XCTAssertEqual(
                error.message,
                "In System Settings › General › Login Items, turn on Kipless in the background apps list to use Closed Lid mode."
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testHelperApprovalStatusCanBeRefreshed() {
        let client = PrivilegedHelperClient(statusProvider: { .requiresApproval })

        XCTAssertTrue(client.helperApprovalIsRequired())
    }

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

    func testADaemonThatNeverAnswersRebuildsTheRegistrationOnce() async {
        let remote = PendingSleepHelperRemote()
        let repairs = RegistrationRepairRecorder()
        let client = PrivilegedHelperClient(
            remote: remote,
            requestTimeout: .milliseconds(50),
            repairRegistration: {
                await repairs.repair()
            }
        )
        // A registered helper that never answers is one the system will not
        // launch: rebuild the registration and ask the user to approve it.
        do {
            try await client.acquireLidSleepOverride()
            XCTFail("A helper that never answers must not report success")
        } catch let error as PrivilegedHelperClientError {
            guard case .helperApprovalRequired = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let repairsAfterFirst = await repairs.count
        XCTAssertEqual(repairsAfterFirst, 1)

        // One rebuild per run is enough: a second attempt must not keep
        // dropping the registration the user may already have approved.
        do {
            try await client.acquireLidSleepOverride()
            XCTFail("A helper that never answers must not report success")
        } catch {
            // expected
        }
        let repairsAfterSecond = await repairs.count
        XCTAssertEqual(repairsAfterSecond, 1)

        remote.acquireReply?(true, nil)
    }

    func testOtherHelperFailuresDoNotRebuildTheRegistration() async {
        let remote = FakeSleepHelperRemote(operationSuccess: false, message: "helper refused")
        let repairs = RegistrationRepairRecorder()
        let client = PrivilegedHelperClient(
            remote: remote,
            repairRegistration: { await repairs.repair() }
        )

        do {
            try await client.acquireLidSleepOverride()
            XCTFail("A refused operation must not report success")
        } catch {
            // expected
        }
        let repairCount = await repairs.count
        XCTAssertEqual(repairCount, 0)
    }

    func testARequestThatIsNeverAnsweredFailsInsteadOfHanging() async {
        let remote = PendingSleepHelperRemote()
        let client = PrivilegedHelperClient(remote: remote, requestTimeout: .milliseconds(50))

        do {
            try await client.enableSleepOverride()
            XCTFail("A helper that never answers must not report success")
        } catch let error as PrivilegedHelperClientError {
            guard case .helperNotResponding = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        // A reply that arrives after the timeout must not complete the request
        // a second time.
        remote.acquireReply?(true, nil)
    }

    func testInvalidatingClientFinishesAnInFlightOperation() async {
        let remote = PendingSleepHelperRemote()
        let client = PrivilegedHelperClient(remote: remote)
        let finished = expectation(description: "the pending request finishes")

        let operation = Task {
            do {
                try await client.enableSleepOverride()
                XCTFail("An invalidated helper request must not succeed")
            } catch {
                finished.fulfill()
            }
        }

        while remote.acquireReply == nil {
            await Task.yield()
        }

        client.invalidate()
        await fulfillment(of: [finished], timeout: 0.5)

        // Keep the test self-cleaning against the pre-fix implementation,
        // whose continuation is only released if the fake eventually replies.
        remote.acquireReply?(false, "connection invalidated")
        await operation.value
    }

    func testStatusLookupDoesNotRunWhileClientLockIsHeld() {
        let clientBox = ClientBox()
        clientBox.client = PrivilegedHelperClient(statusProvider: {
            // This models a synchronous connection lifecycle callback that
            // re-enters the client while permission state is changing.
            clientBox.client.invalidate()
            return .requiresApproval
        })
        let finished = expectation(description: "status lookup returns")

        DispatchQueue.global().async {
            do {
                try clientBox.client.connect()
            } catch {
                finished.fulfill()
            }
        }

        wait(for: [finished], timeout: 0.5)
    }
}

private final class ClientBox: @unchecked Sendable {
    var client: PrivilegedHelperClient!
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

private final class PendingSleepHelperRemote: NSObject, KiplessSleepHelperProtocol {
    var acquireReply: ((Bool, String?) -> Void)?

    func getState(withReply reply: @escaping (Int, String?) -> Void) {
        reply(SleepOverrideSystemState.disabled.rawValue, nil)
    }

    func acquireSleepOverride(withReply reply: @escaping (Bool, String?) -> Void) {
        acquireReply = reply
    }

    func releaseSleepOverride(withReply reply: @escaping (Bool, String?) -> Void) {
        reply(true, nil)
    }
}

/// Records registration rebuilds.
private actor RegistrationRepairRecorder {
    private(set) var count = 0

    func repair() async {
        count += 1
    }
}
