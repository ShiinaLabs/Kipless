import SwiftUI

/// v1.0 has exactly one setting.
struct SettingsView: View {
    @State private var launchAtLogin = LaunchAtLoginService()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Launch at Login", isOn: Binding(
                get: { launchAtLogin.isEnabled },
                set: { launchAtLogin.setEnabled($0) }
            ))

            if launchAtLogin.requiresApproval {
                Text("Allow Kipless in System Settings › General › Login Items to finish turning this on.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let message = launchAtLogin.errorMessage {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(width: 380, alignment: .leading)
        .onAppear { launchAtLogin.refresh() }
    }
}
