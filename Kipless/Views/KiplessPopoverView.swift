import AppKit
import SwiftUI

/// The whole UI: what Kipless is doing, and the one control that changes it.
struct KiplessPopoverView: View {
    @Environment(WakeSessionManager.self) private var manager

    @State private var mode: WakeMode = .system
    @State private var duration: WakeDuration = .minutes30

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Kipless")
                .font(.headline)
                .padding(.bottom, 12)

            if manager.isActive {
                activeSection
            } else {
                inactiveSection
            }

            if let message = manager.errorMessage {
                errorRow(message)
            }

            Divider()
                .padding(.vertical, 12)

            footer
        }
        .padding(14)
        .frame(width: 272)
    }

    // MARK: - Active

    private var activeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusRow(active: true, text: "Active")

            VStack(alignment: .leading, spacing: 2) {
                Text(manager.session?.mode.activeDescription ?? "")
                    .font(.system(size: 15, weight: .semibold))
                Text(remainingText)
                    .font(.system(size: 13))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Button("Stop") { manager.stop() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
        }
    }

    private var remainingText: String {
        guard let seconds = manager.remainingSeconds else { return "Until stopped" }
        return SessionCountdown.text(forRemainingSeconds: seconds)
    }

    // MARK: - Inactive

    private var inactiveSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            statusRow(active: false, text: "Inactive")

            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("Mode")
                Picker("Mode", selection: $mode) {
                    ForEach(WakeMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("Duration")
                Picker("Duration", selection: $duration) {
                    ForEach(WakeDuration.allCases) { duration in
                        Text(duration.title).tag(duration)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            Button("Start") {
                manager.start(mode: mode, duration: duration)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Pieces

    private func statusRow(active: Bool, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: active ? "circle.fill" : "circle")
                .font(.system(size: 8))
                .foregroundStyle(active ? Color.accentColor : Color.secondary)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(active ? Color.primary : Color.secondary)
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
    }

    private func errorRow(_ message: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 11))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 12)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            SettingsLink {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Settings")

            Spacer(minLength: 0)

            Button("Quit Kipless") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .keyboardShortcut("q")
            .help("Quit Kipless and release the wake session")
        }
    }
}
