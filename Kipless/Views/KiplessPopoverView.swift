import AppKit
import SwiftUI

enum KiplessTheme {
    static var accentNSColor: NSColor { .controlAccentColor }
    static var accentColor: Color { Color(nsColor: accentNSColor) }
}

enum KiplessSettingsOpener {
    static var windowTitle: String {
        String(localized: LocalizedStringResource.settingsWindowTitle)
    }

    @MainActor
    static func open() {
        KiplessSettingsWindowController.shared.show()
    }
}

enum KiplessDonationOpener {
    private static let url = URL(string: "https://shiinalabs.com/donate/")!

    @MainActor
    static func open() {
        NSWorkspace.shared.open(url)
    }
}

@MainActor
enum KiplessLoginItemsOpener {
    typealias LaunchSystemSettings = @Sendable (
        @escaping @Sendable (NSRunningApplication?) -> Void
    ) -> Void
    typealias OpenURL = @Sendable (URL) -> Bool
    typealias Activate = @Sendable (NSRunningApplication) -> Void

    private static let systemSettingsURL = URL(
        fileURLWithPath: "/System/Applications/System Settings.app"
    )
    private static let loginItemsURL = URL(
        string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
    )!

    static func openLoginItems() {
        let systemSettingsURL = Self.systemSettingsURL

        openLoginItems(
            launchSystemSettings: { completion in
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                NSWorkspace.shared.openApplication(
                    at: systemSettingsURL,
                    configuration: configuration
                ) { app, _ in
                    DispatchQueue.main.async {
                        completion(app)
                    }
                }
            },
            openURL: { NSWorkspace.shared.open($0) },
            activate: { app in
                app.activate(options: [.activateAllWindows])
            }
        )
    }

    static func openLoginItems(
        launchSystemSettings: @escaping LaunchSystemSettings,
        openURL: @escaping OpenURL,
        activate: @escaping Activate
    ) {
        let loginItemsURL = Self.loginItemsURL

        launchSystemSettings { app in
            _ = openURL(loginItemsURL)
            if let app {
                activate(app)
            }
        }
    }
}

/// The dialog for a Closed Lid start that is waiting on the privileged
/// helper's Login Items approval.
///
/// It is a dialog rather than a row in the Popover because this failure needs
/// an answer — the user either goes and approves the helper, or they do not.
@MainActor
enum ClosedLidApprovalAlert {
    typealias RunAlert = @MainActor (String, String, String, String) -> Bool
    typealias OpenLoginItems = @MainActor () -> Void

    static func present() {
        present(runAlert: runAlert, openLoginItems: KiplessLoginItemsOpener.openLoginItems)
    }

    /// `runAlert` receives the title, message, accept and dismiss titles, and
    /// reports whether the user chose to open Login Items.
    static func present(
        runAlert: @escaping RunAlert,
        openLoginItems: @escaping OpenLoginItems
    ) {
        let title = String(localized: LocalizedStringResource.permissionClosedLidApprovalTitle)
        let message = String(localized: LocalizedStringResource.permissionClosedLidApprovalMessage)
        let accept = String(localized: LocalizedStringResource.permissionClosedLidApprovalOpenSettings)
        let dismiss = String(localized: LocalizedStringResource.permissionClosedLidApprovalDismiss)

        guard runAlert(title, message, accept, dismiss) else { return }
        openLoginItems()
    }

    private static func runAlert(
        title: String,
        message: String,
        accept: String,
        dismiss: String
    ) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: accept)
        alert.addButton(withTitle: dismiss)

        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }
}

fileprivate enum KiplessMotion {
    static func sessionState(reduceMotion: Bool) -> Animation {
        .easeInOut(duration: reduceMotion ? 0.18 : 0.2)
    }

    static func presentation(reduceMotion: Bool) -> Animation {
        .easeInOut(duration: reduceMotion ? 0.18 : 0.26)
    }
}

private struct WakeControlPanel: View {
    let presentation: WakeControlPresentation
    let timeText: String
    let ringProgress: Double
    let isActive: Bool
    let isActionDisabled: Bool
    let isTrailAnimating: Bool
    let accent: Color
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            switch presentation.layout {
            case .timed:
                TimedControlView(
                    timeText: timeText,
                    ringProgress: ringProgress,
                    isActive: isActive,
                    isActionDisabled: isActionDisabled,
                    accent: accent,
                    action: action
                )
                .transition(presentationTransition)
            case .indefinite:
                IndefiniteControlView(
                    isActive: isActive,
                    isActionDisabled: isActionDisabled,
                    isTrailAnimating: isTrailAnimating,
                    accent: accent,
                    action: action
                )
                .transition(presentationTransition)
            }
        }
        .frame(width: KiplessLayout.timerDiameter, height: KiplessLayout.timerDiameter)
        .animation(
            KiplessMotion.presentation(reduceMotion: reduceMotion),
            value: presentation.layout
        )
    }

    private var presentationTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }

        return .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 1.04)),
            removal: .opacity.combined(with: .scale(scale: 0.96))
        )
    }
}

private struct TimedControlView: View {
    let timeText: String
    let ringProgress: Double
    let isActive: Bool
    let isActionDisabled: Bool
    let accent: Color
    let action: () -> Void

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.1), lineWidth: 6)

            if ringProgress > 0 {
                // No animation of its own: the ring is moved by whatever
                // transaction the popover sets `ringProgress` in, which is what
                // keeps a steady tick short and a catch-up bounded.
                Circle()
                    .trim(from: 0, to: ringProgress)
                    .stroke(accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }

            VStack(spacing: 8) {
                Text(timeText)
                    .font(.system(size: 24, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .kerning(-1.2)

                SessionActionButton(
                    isActive: isActive,
                    isDisabled: isActionDisabled,
                    action: action
                )
            }
        }
        .frame(width: KiplessLayout.timerDiameter, height: KiplessLayout.timerDiameter)
    }
}

private struct IndefiniteParticleTrail: View {
    let accent: Color
    let isActive: Bool

    /// The trail is the one thing in the popover that animates on its own, so
    /// it is the one thing that has to be told to stop when the popover is
    /// closed. Without this the timeline keeps driving a Canvas at 30 fps
    /// inside a window nobody can see.
    let isAnimating: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if isActive {
                if reduceMotion {
                    Capsule()
                        .fill(accent.opacity(0.05))
                        .frame(width: 104, height: 16)
                        .blur(radius: 8)
                } else {
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isAnimating)) { timeline in
                        Canvas { context, size in
                            let horizontalInset: CGFloat = 4
                            let verticalInset: CGFloat = 10
                            let trailWidth = size.width * 0.62
                            let usableWidth = max(trailWidth - (horizontalInset * 2), 0)
                            let usableHeight = max(size.height - (verticalInset * 2), 0)
                            let verticalOffset = IndefiniteControlLayout.compact.particleVerticalOffset

                            for particle in IndefiniteParticleMotion.particles(
                                at: timeline.date.timeIntervalSinceReferenceDate
                            ) {
                                let thickness = CGFloat(particle.thickness)
                                let length = thickness * 3.0
                                let center = CGPoint(
                                    x: horizontalInset + CGFloat(particle.progress) * usableWidth,
                                    y: verticalInset + verticalOffset
                                        + CGFloat(particle.verticalPosition) * usableHeight
                                )
                                let rect = CGRect(
                                    x: center.x - (length / 2),
                                    y: center.y - (thickness / 2),
                                    width: length,
                                    height: thickness
                                )

                                context.fill(
                                    Path(roundedRect: rect, cornerRadius: thickness / 2),
                                    with: .color(accent.opacity(particle.opacity))
                                )
                            }
                        }
                    }
                }
            }
        }
        .frame(width: KiplessLayout.timerDiameter, height: IndefiniteControlLayout.compact.symbolAreaHeight)
        .allowsHitTesting(false)
    }
}

private struct IndefiniteControlView: View {
    let isActive: Bool
    let isActionDisabled: Bool
    let isTrailAnimating: Bool
    let accent: Color
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let layout = IndefiniteControlLayout.compact

        VStack(spacing: layout.verticalSpacing) {
            ZStack {
                IndefiniteParticleTrail(
                    accent: accent,
                    isActive: isActive,
                    isAnimating: isTrailAnimating
                )

                Text("∞")
                    .font(.system(size: layout.infinityFontSize, weight: .light, design: .rounded))
                    .foregroundStyle(isActive ? accent : .primary)
                    .kerning(-3)
            }
            .frame(width: KiplessLayout.timerDiameter, height: layout.symbolAreaHeight)

            switch layout.actionPlacement {
            case .inline:
                HStack(spacing: layout.statusActionSpacing) {
                    Text(
                        String(
                            localized: isActive
                                ? LocalizedStringResource.sessionIndefiniteActive
                                : LocalizedStringResource.sessionIndefiniteIdle
                        )
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .id(isActive)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .opacity.combined(with: .scale(scale: 0.96))
                    )

                    SessionActionButton(
                        isActive: isActive,
                        isDisabled: isActionDisabled,
                        action: action
                    )
                }
            }
        }
        .frame(width: KiplessLayout.timerDiameter, height: KiplessLayout.timerDiameter)
        .animation(
            KiplessMotion.sessionState(reduceMotion: reduceMotion),
            value: isActive
        )
    }
}

private struct SessionActionButton: View {
    let isActive: Bool
    let isDisabled: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            ZStack {
                if isActive {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 10, weight: .bold))
                        .transition(iconTransition)
                } else {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10, weight: .bold))
                        .transition(iconTransition)
                }
            }
            .frame(width: 30, height: 30)
            .background(Color.primary.opacity(0.06), in: Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.52 : 1)
        .animation(
            KiplessMotion.sessionState(reduceMotion: reduceMotion),
            value: isActive
        )
        .accessibilityLabel(
            String(
                localized: isActive
                    ? LocalizedStringResource.sessionActionStop
                    : LocalizedStringResource.sessionActionStart
            )
        )
        .help(
            String(
                localized: isActive
                    ? LocalizedStringResource.sessionActionStop
                    : LocalizedStringResource.sessionActionStart
            )
        )
    }

    private var iconTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .opacity.combined(with: .scale(scale: 0.75))
    }
}

@MainActor
private final class KiplessSettingsWindowController: NSWindowController {
    static let shared = KiplessSettingsWindowController()

    private init() {
        // Tall enough for every card, so nothing sits below the fold. Only a
        // short screen can force scrolling, and that case keeps its indicator.
        let height = SettingsWindowSizing.height(
            visibleScreenHeight: NSScreen.main?.visibleFrame.height ?? 900
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: SettingsWindowSizing.width, height: height),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        window.title = KiplessSettingsOpener.windowTitle
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: SettingsView())
        // A scroll container has no intrinsic height, so assigning it as the
        // content view controller collapses the window; size it explicitly.
        window.setContentSize(NSSize(width: SettingsWindowSizing.width, height: height))
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var mode: WakeMode = .system
    @State private var duration: WakeDuration = .minutes30

    /// The countdown's own clock. It runs only while this popover is on screen
    /// and there is something to count down to, so a Session that keeps the Mac
    /// awake in the background costs the UI nothing.
    @State private var presentation = SessionPresentationClock()

    /// Where the ring is drawn, which is allowed to lag the truth so that
    /// reopening the popover catches up rather than jumping.
    @State private var displayedProgress: Double = 1

    /// Which Session `displayedProgress` belongs to, so a position left over
    /// from the last one can never be inherited by the next.
    @State private var displayedSessionID: UUID?

    private var quietAccent: Color { KiplessTheme.accentColor }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let message = manager.errorMessage {
                errorRow(message)
            }

            HStack(spacing: 0) {
                sessionControlPanel
                    .frame(width: KiplessLayout.sessionPanelWidth, height: KiplessLayout.sessionPanelHeight)

                optionsPanel
                    .frame(width: KiplessLayout.optionsPanelWidth, height: KiplessLayout.sessionPanelHeight)
            }
            .frame(width: KiplessLayout.popoverWidth)
            .frame(height: KiplessLayout.sessionPanelHeight)

            Divider()
            footer
                .frame(height: KiplessLayout.footerHeight)
        }
        .frame(width: KiplessLayout.popoverWidth)
        .background(visibilityProbe)
        .onChange(of: manager.session?.id) { _, _ in
            updatePresentationClock()
            syncDisplayedProgress()
        }
        .onChange(of: presentation.now) { _, _ in
            syncDisplayedProgress()
        }
        .onChange(of: manager.lidApprovalIsRequired) { _, isRequired in
            guard isRequired else { return }

            manager.acknowledgeLidApprovalRequest()
            // Running a modal alert inside SwiftUI's update pass would nest
            // run loops underneath it, so hand it to the next main-actor turn.
            Task { @MainActor in ClosedLidApprovalAlert.present() }
        }
    }

    // MARK: - Session control

    private var sessionControlPanel: some View {
        WakeControlPanel(
            presentation: WakeControlPresentation(duration: duration, isActive: manager.isActive),
            timeText: timeText,
            ringProgress: displayedProgress,
            isActive: manager.isActive,
            isActionDisabled: manager.isTransitioning,
            isTrailAnimating: presentation.isVisible,
            accent: quietAccent,
            action: toggleSession
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(sessionControlAccessibilityLabel)
    }

    private var sessionControlAccessibilityLabel: String {
        if duration == .indefinite {
            return String(
                localized: manager.isActive
                    ? LocalizedStringResource.sessionIndefiniteActive
                    : LocalizedStringResource.sessionIndefiniteIdle
            )
        }

        return String(localized: LocalizedStringResource.sessionTimeRemaining)
    }

    private var optionsPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(LocalizedStringResource.sessionModeExplanation)
                .font(.system(size: 8.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            // Keep every semantic item in one vertical flow. SwiftUI divides
            // the available space between these spacers evenly, so shorter or
            // longer localized copy changes the gap size without creating a
            // single oversized blank area.
            Spacer(minLength: 0)

            ForEach(Array(WakeMode.allCases.enumerated()), id: \.element.id) { index, candidate in
                modeOption(candidate)
                    .overlay(alignment: .top) {
                        if index > 0 {
                            Divider()
                                .padding(.leading, 23)
                        }
                    }

                if index < WakeMode.allCases.count - 1 {
                    Spacer(minLength: 0)
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 5) {
                Text(LocalizedStringResource.sessionDurationTitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                Picker(String(localized: LocalizedStringResource.sessionDurationTitle), selection: $duration) {
                    ForEach(WakeDuration.allCases) { duration in
                        Text(duration.title).tag(duration)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .controlSize(.small)
                .frame(width: KiplessLayout.durationPickerWidth, alignment: .leading)
                .layoutPriority(1)
                .disabled(manager.isActive || manager.isTransitioning)
            }
            .frame(height: KiplessLayout.durationRowHeight)
            .opacity(manager.isActive || manager.isTransitioning ? 0.46 : 1)
            .animation(
                .easeInOut(duration: 0.2),
                value: manager.isActive || manager.isTransitioning
            )
        }
        .padding(.horizontal, KiplessLayout.optionsHorizontalPadding)
        .padding(.vertical, KiplessLayout.optionsVerticalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
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
            .padding(.vertical, KiplessLayout.modeOptionVerticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(manager.isActive || manager.isTransitioning)
        .opacity(manager.isActive || manager.isTransitioning ? 0.46 : 1)
        .animation(
            .easeInOut(duration: 0.2),
            value: manager.isActive || manager.isTransitioning
        )
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
        guard let seconds = SessionRingProgress.remainingSeconds(
            session: manager.session,
            at: presentation.now
        ) else {
            return durationText
        }

        let minutes = seconds / 60
        let remainder = seconds % 60
        return "\(minutes):\(String(format: "%02d", remainder))"
    }

    /// A zero-sized view whose only job is to say whether the popover's window
    /// is on screen, which is what decides if anything is worth refreshing.
    private var visibilityProbe: some View {
        WindowVisibilityProbe { isVisible in
            presentation.update(
                isVisible: isVisible,
                expiresAt: manager.session?.expiresAt
            )
        }
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    private func updatePresentationClock() {
        presentation.update(
            isVisible: presentation.isVisible,
            expiresAt: manager.session?.expiresAt
        )
    }

    /// Moves the ring to where the Session actually is.
    ///
    /// A Session that has just started is placed outright: there is no previous
    /// position for it to travel from, and the last Session's progress must not
    /// be inherited. Within one Session the ring interpolates instead, which is
    /// what makes reopening the popover glide to the real value after a while
    /// rather than jumping to it.
    private func syncDisplayedProgress() {
        let sessionID = manager.session?.id
        let target = SessionRingProgress.progress(
            session: manager.session,
            at: presentation.now
        )

        guard let sessionID, sessionID == displayedSessionID else {
            displayedSessionID = sessionID
            setDisplayedProgress(target, animated: sessionID == nil)
            return
        }

        setDisplayedProgress(target, animated: true)
    }

    private func setDisplayedProgress(_ target: Double, animated: Bool) {
        guard abs(target - displayedProgress) > 0.0001 else { return }

        guard animated,
              let animation = SessionRingMotion.animation(
                  reduceMotion: reduceMotion,
                  delta: target - displayedProgress
              )
        else {
            displayedProgress = target
            return
        }

        withAnimation(animation) {
            displayedProgress = target
        }
    }

    private var durationText: String {
        guard let seconds = duration.seconds else { return "∞" }

        let minutes = Int(seconds) / 60
        return "\(minutes):00"
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

                Text(LocalizedStringResource.appName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            Button {
                KiplessDonationOpener.open()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 8, weight: .semibold))
                    Text(LocalizedStringResource.supportActionDonate)
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundStyle(Color(red: 0.46, green: 0.31, blue: 0.70))
                .frame(height: 20)
                .padding(.horizontal, 7)
                .background(
                    Color(red: 0.46, green: 0.31, blue: 0.70).opacity(0.13),
                    in: Capsule()
                )
                .overlay {
                    Capsule()
                        .stroke(
                            Color(red: 0.46, green: 0.31, blue: 0.70).opacity(0.30),
                            lineWidth: 0.75
                        )
                }
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help(String(localized: LocalizedStringResource.supportActionDonate))

            Spacer(minLength: 0)

            Button {
                KiplessSettingsOpener.open()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel(String(localized: LocalizedStringResource.settingsActionOpen))
            .help(String(localized: LocalizedStringResource.settingsActionOpen))

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel(String(localized: LocalizedStringResource.appActionQuit))
            .help(String(localized: LocalizedStringResource.appActionQuitHelp))
        }
        .padding(.horizontal, 18)
    }
}
