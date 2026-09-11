import SwiftUI

enum SettingsCopy {
    static var launchAtLoginDescription: String {
        String(localized: KiplessStrings.settingsLaunchAtLoginDescription)
    }

    static var aboutDescription: String {
        String(localized: KiplessStrings.settingsAboutDescription)
    }
}

/// A compact, single-column settings window for the small v1 surface area.
struct SettingsView: View {
    @State private var launchAtLogin = LaunchAtLoginService()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(KiplessStrings.settingsTitle)
                .font(.system(size: 24, weight: .semibold, design: .rounded))

            Text(KiplessStrings.appName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            settingsSection(String(localized: KiplessStrings.settingsGeneralSection)) {
                generalSection
            }

            settingsSection(String(localized: KiplessStrings.settingsAboutSection)) {
                aboutSection
            }
        }
        .padding(28)
        .frame(width: 520, height: 330, alignment: .topLeading)
        .tint(KiplessTheme.accentColor)
        .onAppear { launchAtLogin.refresh() }
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(KiplessStrings.settingsLaunchAtLoginTitle)
                        .font(.system(size: 13, weight: .medium))

                    Text(SettingsCopy.launchAtLoginDescription)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                Toggle(
                    String(localized: KiplessStrings.settingsLaunchAtLoginTitle),
                    isOn: Binding(
                        get: { launchAtLogin.isEnabled },
                        set: { launchAtLogin.setEnabled($0) }
                    )
                )
                .labelsHidden()
                .controlSize(.small)
            }

            if launchAtLogin.requiresApproval {
                inlineMessage(
                    String(localized: KiplessStrings.settingsLaunchAtLoginApproval),
                    systemImage: "info.circle"
                )
            }

            if let message = launchAtLogin.errorMessage {
                inlineMessage(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var aboutSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(SettingsCopy.aboutDescription)
                    .font(.system(size: 12, weight: .medium))

                Text(KiplessStrings.settingsPrivacyDescription)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 3) {
                Text(String(localized: KiplessStrings.settingsVersion(versionText)))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)

                Text(KiplessStrings.settingsLicense)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            content()
        }
        .padding(.top, 22)
    }

    private func inlineMessage(_ message: String, systemImage: String) -> some View {
        Label {
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
    }

    private var versionText: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }
}
