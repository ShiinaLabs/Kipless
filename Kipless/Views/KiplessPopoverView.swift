import AppKit
import SwiftUI

enum KiplessTheme {
    static var accentNSColor: NSColor { .controlAccentColor }
    static var accentColor: Color { Color(nsColor: accentNSColor) }
}

enum KiplessSettingsOpener {
    static let windowTitle = "Kipless Settings"

    @MainActor
    static func open() {
        KiplessSettingsWindowController.shared.show()
    }
}

@MainActor
private final class KiplessSettingsWindowController: NSWindowController {
    static let shared = KiplessSettingsWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 330),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        window.title = KiplessSettingsOpener.windowTitle
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: SettingsView())
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard let window else { return }

        NSApp.activate(ignoringOtherApps: true)
        if !window.isVisible {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
    }
}

/// The whole UI: what Kipless is doing, and the one control that changes it.
struct KiplessPopoverView: View {
    @Environment(WakeSessionManager.self) private var manager

    @State private var mode: WakeMode = .system
    @State private var duration: WakeDuration = .minutes30

    private var quietAccent: Color { KiplessTheme.accentColor }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let message = manager.errorMessage {
                errorRow(message)
            }

            HStack(spacing: 0) {
                timerPanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                optionsPanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(height: 180)

            Divider()
            footer
                .frame(height: 36)
        }
        .frame(width: 360)
    }

    // MARK: - Quiet Ring

    private var timerPanel: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.1), lineWidth: 6)

            if ringProgress > 0 {
                Circle()
                    .trim(from: 0, to: 0.985 * ringProgress)
                    .stroke(quietAccent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }

            VStack(spacing: 8) {
                Text(timeText)
                    .font(.system(size: 24, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .kerning(-1.2)

                Button(action: toggleSession) {
                    Image(systemName: manager.isActive ? "stop.fill" : "play.fill")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 30, height: 30)
                        .background(Color.primary.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel(manager.isActive ? "Stop session" : "Start session")
                .help(manager.isActive ? "Stop session" : "Start session")
            }
        }
        .frame(width: 138, height: 138)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Session time remaining")
    }

    private var optionsPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(WakeMode.allCases.enumerated()), id: \.element.id) { index, candidate in
                    if index > 0 {
                        Divider()
                            .padding(.leading, 23)
                    }

                    modeOption(candidate)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                Text("Duration")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Picker("Duration", selection: $duration) {
                    ForEach(WakeDuration.allCases) { duration in
                        Text(duration.title).tag(duration)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .controlSize(.small)
                .disabled(manager.isActive)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func modeOption(_ candidate: WakeMode) -> some View {
        Button {
            mode = candidate
        } label: {
            HStack(alignment: .top, spacing: 8) {
                modeIndicator(isSelected: mode == candidate)

                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.title)
                        .font(.system(size: 11, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)

                    Text(candidate.subtitle)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(manager.isActive)
        .opacity(manager.isActive ? 0.46 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(candidate.title)
        .accessibilityValue(candidate.subtitle)
        .accessibilityAddTraits(mode == candidate ? .isSelected : [])
    }

    private func modeIndicator(isSelected: Bool) -> some View {
        ZStack {
            Circle()
                .stroke(
                    isSelected ? quietAccent : Color.secondary.opacity(0.58),
                    lineWidth: 1.5
                )

            if isSelected {
                Circle()
                    .fill(quietAccent)
                    .frame(width: 6, height: 6)
            }
        }
        .frame(width: 15, height: 15)
        .padding(.top, 1)
    }

    // MARK: - Pieces

    private var timeText: String {
        guard let seconds = manager.remainingSeconds else {
            return manager.isActive ? "∞" : durationText
        }

        let minutes = seconds / 60
        let remainder = seconds % 60
        return "\(minutes):\(String(format: "%02d", remainder))"
    }

    private var durationText: String {
        guard let seconds = duration.seconds else { return "∞" }

        let minutes = Int(seconds) / 60
        return "\(minutes):00"
    }

    private var ringProgress: Double {
        guard let session = manager.session, let expiresAt = session.expiresAt else { return 1 }

        let total = max(expiresAt.timeIntervalSince(session.startedAt), 1)
        let remaining = Double(manager.remainingSeconds ?? 0)
        return min(max(remaining / total, 0), 1)
    }

    private func toggleSession() {
        if manager.isActive {
            manager.stop()
        } else {
            manager.start(mode: mode, duration: duration)
        }
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
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.secondary.opacity(0.72))
                    .frame(width: 7, height: 7)
                    .padding(3)
                    .background(Color.secondary.opacity(0.12), in: Circle())

                Text("Kipless")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button {
                KiplessSettingsOpener.open()
            } label: {
                Text("Settings")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Settings")

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Quit Kipless")
            .help("Quit Kipless and release the wake session")
        }
        .padding(.horizontal, 18)
    }
}
