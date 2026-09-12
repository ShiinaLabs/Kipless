import AppKit
import SwiftUI

enum SettingsCopy {
    static var launchAtLoginDescription: String {
        String(localized: LocalizedStringResource.settingsLaunchAtLoginDescription)
    }

    static var aboutDescription: String {
        String(localized: LocalizedStringResource.settingsAboutDescription)
    }

    static var closedLidApprovalTitle: String {
        String(localized: LocalizedStringResource.permissionClosedLidApprovalTitle)
    }

    static var closedLidApprovalMessage: String {
        String(localized: LocalizedStringResource.permissionClosedLidApprovalMessage)
    }
}

private struct SettingsModeRow: Identifiable {
    let mode: WakeMode
    let idleSleep: SettingsModeStatus
    let displaySleep: SettingsModeStatus
    let lidSleep: SettingsModeStatus

    var id: String { mode.rawValue }
}

private enum SettingsModeStatus {
    case blocked
    case allowed

    var icon: String {
        switch self {
        case .blocked: "❌"
        case .allowed: "✅"
        }
    }

    var accessibilityLabel: LocalizedStringResource {
        switch self {
        case .blocked: LocalizedStringResource.settingsModeTableStatusBlocked
        case .allowed: LocalizedStringResource.settingsModeTableStatusAllowed
        }
    }
}

private let settingsModeColumnWidth: CGFloat = 72
private let settingsModeTitleWidth: CGFloat = 184

/// Window metrics for the Settings window.
///
/// The window is sized to the cards rather than the other way round: a fixed
/// height pushed whole cards below the fold behind an indicator-less scroll
/// view, so nothing hinted that more content existed.
enum SettingsWindowSizing {
    static let width: CGFloat = 520
    static let minimumHeight: CGFloat = 360
    static let screenMargin: CGFloat = 120

    /// Shows every card without scrolling, capped so the window still fits on
    /// a short screen.
    @MainActor
    static func height(visibleScreenHeight: CGFloat) -> CGFloat {
        let cap = max(minimumHeight, visibleScreenHeight - screenMargin)
        return min(idealContentHeight, cap)
    }

    /// The cards' natural height at `width`, measured from the content itself
    /// so adding a card grows the window instead of hiding the last one.
    @MainActor
    static var idealContentHeight: CGFloat {
        let host = NSHostingView(rootView: SettingsContentView())
        host.frame = NSRect(x: 0, y: 0, width: width, height: 0)
        host.layoutSubtreeIfNeeded()
        return host.fittingSize.height
    }
}

/// The scroll container. It only scrolls when the screen is too short for the
/// cards, and its indicator stays visible so that case is discoverable.
struct SettingsView: View {
    var body: some View {
        ScrollView(.vertical) {
            SettingsContentView()
        }
        .scrollIndicators(.visible)
        .frame(width: SettingsWindowSizing.width)
        .tint(KiplessTheme.accentColor)
    }
}

/// The cards themselves, kept out of the scroll container so their natural
/// height can be measured for window sizing.
struct SettingsContentView: View {
    @State private var launchAtLogin = LaunchAtLoginService()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(LocalizedStringResource.settingsTitle)
                .font(.system(size: 24, weight: .semibold, design: .rounded))

            Text(LocalizedStringResource.appName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            settingsSection(String(localized: LocalizedStringResource.settingsSectionGeneral)) {
                generalSection
            }

            settingsSection(String(localized: LocalizedStringResource.sessionModeClosedLidTitle)) {
                closedLidSection
            }

            settingsSection(String(localized: LocalizedStringResource.settingsSectionWakeModes)) {
                wakeModesSection
            }

            settingsSection(String(localized: LocalizedStringResource.settingsSectionAbout)) {
                aboutSection
            }
        }
        .padding(28)
        .onAppear { launchAtLogin.refresh() }
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(LocalizedStringResource.settingsLaunchAtLoginTitle)
                        .font(.system(size: 13, weight: .medium))

                    Text(SettingsCopy.launchAtLoginDescription)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                Toggle(
                    String(localized: LocalizedStringResource.settingsLaunchAtLoginTitle),
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
                    String(localized: LocalizedStringResource.settingsLaunchAtLoginApproval),
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

    private var wakeModesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: 8) {
                Text(LocalizedStringResource.settingsModeTableColumnMode)
                    .frame(width: settingsModeTitleWidth, alignment: .leading)

                Text(LocalizedStringResource.settingsModeTableColumnIdleSleep)
                    .frame(width: settingsModeColumnWidth)

                Text(LocalizedStringResource.settingsModeTableColumnDisplaySleep)
                    .frame(width: settingsModeColumnWidth)

                Text(LocalizedStringResource.settingsModeTableColumnLidSleep)
                    .frame(width: settingsModeColumnWidth)
            }
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 8)

            Divider()

            ForEach(Array(modeRows.enumerated()), id: \.element.id) { index, row in
                if index > 0 {
                    Divider()
                }

                HStack(alignment: .top, spacing: 8) {
                    Text(row.mode.title)
                        .font(.system(size: 10.5, weight: .semibold))
                        .frame(width: settingsModeTitleWidth, alignment: .leading)

                    statusCell(row.idleSleep)
                    statusCell(row.displaySleep)
                    statusCell(row.lidSleep)
                }
                .padding(.vertical, 8)
            }
        }
        .padding(14)
        .background(
            Color.primary.opacity(0.045),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }

    private var closedLidSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .background(
                        Color.primary.opacity(0.07),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(SettingsCopy.closedLidApprovalTitle)
                        .font(.system(size: 13, weight: .medium))

                    Text(SettingsCopy.closedLidApprovalMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button(LocalizedStringResource.permissionClosedLidApprovalOpenSettings) {
                KiplessLoginItemsOpener.openLoginItems()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(14)
        .background(
            Color.primary.opacity(0.045),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }

    private func statusCell(_ status: SettingsModeStatus) -> some View {
        Text(status.icon)
            .font(.system(size: 13))
            .frame(width: settingsModeColumnWidth)
            .accessibilityLabel(String(localized: status.accessibilityLabel))
    }

    private var modeRows: [SettingsModeRow] {
        return [
            SettingsModeRow(
                mode: .system,
                idleSleep: .blocked,
                displaySleep: .allowed,
                lidSleep: .allowed
            ),
            SettingsModeRow(
                mode: .display,
                idleSleep: .blocked,
                displaySleep: .blocked,
                lidSleep: .allowed
            ),
            SettingsModeRow(
                mode: .closedLid,
                idleSleep: .blocked,
                displaySleep: .allowed,
                lidSleep: .blocked
            )
        ]
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

                Text(LocalizedStringResource.settingsAboutPrivacy)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 3) {
                Text(String(localized: LocalizedStringResource.settingsAboutVersion(versionText)))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)

                Text(LocalizedStringResource.settingsAboutLicense)
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

            // Cards must all be the same width whatever they contain: a card
            // whose content has no Spacer of its own would otherwise shrink to
            // its ideal width and stand out from the rest.
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
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
