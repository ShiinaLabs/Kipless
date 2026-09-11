import Foundation
import ServiceManagement

/// Wraps `SMAppService.mainApp` so the Settings view does not have to deal with
/// registration errors, approval states or status re-reads.
@Observable
@MainActor
final class LaunchAtLoginService {
    private let service = SMAppService.mainApp

    private(set) var status: SMAppService.Status
    private(set) var errorMessage: String?

    init() {
        status = service.status
    }

    /// Whether the toggle should read as on. A registration that macOS is still
    /// waiting for the user to approve has been registered, so it counts.
    var isEnabled: Bool {
        status == .enabled || status == .requiresApproval
    }

    /// macOS is holding the registration until the user allows it in
    /// System Settings › General › Login Items.
    var requiresApproval: Bool { status == .requiresApproval }

    func refresh() {
        status = service.status
    }

    func setEnabled(_ enabled: Bool) {
        errorMessage = nil
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
    }
}
