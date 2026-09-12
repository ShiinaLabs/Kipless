import Foundation

final class SleepHelperListener: NSObject, NSXPCListenerDelegate {
    private let controller: SleepOverrideController

    init(controller: SleepOverrideController = SleepOverrideController(
        driver: PMSetSleepOverrideDriver()
    )) {
        self.controller = controller
    }

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
        let service = SleepHelperService(controller: controller)
        newConnection.exportedInterface = NSXPCInterface(with: KiplessSleepHelperProtocol.self)
        newConnection.exportedObject = service
        newConnection.invalidationHandler = { [weak service] in
            service?.releaseConnectionLease()
        }
        newConnection.resume()
        return true
    }
}

private final class SleepHelperService: NSObject, KiplessSleepHelperProtocol {
    private let controller: SleepOverrideController
    private let lock = NSLock()
    private var ownsLease = false

    init(controller: SleepOverrideController) {
        self.controller = controller
    }

    func getState(withReply reply: @escaping (Int, String?) -> Void) {
        lock.lock()
        defer { lock.unlock() }

        do {
            reply(try controller.currentState().rawValue, nil)
        } catch {
            reply(SleepOverrideSystemState.unknown.rawValue, error.localizedDescription)
        }
    }

    func acquireSleepOverride(withReply reply: @escaping (Bool, String?) -> Void) {
        lock.lock()
        defer { lock.unlock() }

        if ownsLease {
            reply(true, nil)
            return
        }

        guard !controller.hasLease else {
            reply(false, "Another Kipless client already owns the closed-lid override")
            return
        }

        do {
            try controller.acquireOverride()
            ownsLease = true
            reply(true, nil)
        } catch {
            reply(false, error.localizedDescription)
        }
    }

    func releaseSleepOverride(withReply reply: @escaping (Bool, String?) -> Void) {
        lock.lock()
        defer { lock.unlock() }

        guard ownsLease else {
            reply(true, nil)
            return
        }

        do {
            try controller.releaseOverride()
            ownsLease = false
            reply(true, nil)
        } catch {
            reply(false, error.localizedDescription)
        }
    }

    func releaseConnectionLease() {
        lock.lock()
        defer { lock.unlock() }

        guard ownsLease else { return }
        try? controller.releaseOverride()
        ownsLease = false
    }
}
