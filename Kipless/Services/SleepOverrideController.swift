import Foundation

enum SleepOverrideControllerError: LocalizedError {
    case stateReadFailed(String)
    case enableFailed(String)
    case disableFailed(String)
    case verificationFailed(expected: SleepOverrideSystemState, actual: SleepOverrideSystemState)

    var errorDescription: String? {
        switch self {
        case let .stateReadFailed(message):
            "Could not read SleepDisabled: \(message)"
        case let .enableFailed(message):
            "Could not enable closed-lid sleep override: \(message)"
        case let .disableFailed(message):
            "Could not restore closed-lid sleep override: \(message)"
        case let .verificationFailed(expected, actual):
            "SleepDisabled verification failed; expected \(expected), got \(actual)"
        }
    }
}

final class SleepOverrideController {
    private let driver: SleepOverrideDriving

    private(set) var ownership: SleepOverrideOwnership?

    var hasLease: Bool { ownership != nil }

    init(driver: SleepOverrideDriving) {
        self.driver = driver
    }

    func currentState() throws -> SleepOverrideSystemState {
        do {
            return try driver.readState() ? .enabled : .disabled
        } catch {
            throw SleepOverrideControllerError.stateReadFailed(error.localizedDescription)
        }
    }

    func acquireOverride() throws {
        guard ownership == nil else { return }

        let baselineWasDisabled: Bool
        do {
            baselineWasDisabled = try driver.readState()
        } catch {
            throw SleepOverrideControllerError.stateReadFailed(error.localizedDescription)
        }

        if baselineWasDisabled {
            ownership = SleepOverrideOwnership(
                baselineWasDisabled: true,
                modifiedByKipless: false
            )
            return
        }

        do {
            try driver.enable()
            let stateAfterEnable: SleepOverrideSystemState =
                (try driver.readState()) ? .enabled : .disabled
            guard stateAfterEnable == .enabled else {
                throw SleepOverrideControllerError.verificationFailed(
                    expected: .enabled,
                    actual: stateAfterEnable
                )
            }
            ownership = SleepOverrideOwnership(
                baselineWasDisabled: false,
                modifiedByKipless: true
            )
        } catch let error as SleepOverrideControllerError {
            restoreDisabledBaselineAfterFailedAcquire()
            throw error
        } catch {
            restoreDisabledBaselineAfterFailedAcquire()
            throw SleepOverrideControllerError.enableFailed(error.localizedDescription)
        }
    }

    func releaseOverride() throws {
        guard let ownership else { return }

        guard ownership.modifiedByKipless else {
            self.ownership = nil
            return
        }

        do {
            try driver.disable()
            let stateAfterDisable: SleepOverrideSystemState =
                (try driver.readState()) ? .enabled : .disabled
            guard stateAfterDisable == .disabled else {
                throw SleepOverrideControllerError.verificationFailed(
                    expected: .disabled,
                    actual: stateAfterDisable
                )
            }
            self.ownership = nil
        } catch let error as SleepOverrideControllerError {
            throw SleepOverrideControllerError.disableFailed(error.localizedDescription)
        } catch {
            throw SleepOverrideControllerError.disableFailed(error.localizedDescription)
        }
    }

    private func restoreDisabledBaselineAfterFailedAcquire() {
        try? driver.disable()
        ownership = nil
    }
}
