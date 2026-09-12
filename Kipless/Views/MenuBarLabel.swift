import SwiftUI

/// The menu bar glyph, plus the countdown when the user asks for one.
///
/// Plain template symbols, so they follow the menu bar's own light/dark
/// rendering without any custom assets. Awake is a filled bolt, inactive is the
/// same bolt struck through — the two read differently even at menu bar size.
struct MenuBarLabel: View {
    @Environment(WakeSessionManager.self) private var manager
    @AppStorage(MenuBarCountdownPreference.storageKey)
    private var showsCountdown = MenuBarCountdownPreference.defaultValue

    /// The countdown's own clock, driven by the text's cadence rather than by a
    /// fixed beat: see `MenuBarCountdown`.
    @State private var countdown = SessionPresentationClock(cadence: MenuBarCountdown.cadence)

    /// What the menu bar is showing, held rather than derived.
    ///
    /// A derived value would be drawn from the clock's last reading, which can
    /// be hours old the first time a Session is started after a long idle
    /// stretch. Holding it means the label shows nothing for the single frame
    /// before the clock has a reading, instead of showing a wrong countdown.
    @State private var countdownText: String?

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: manager.isActive ? "bolt.fill" : "bolt.slash")
                .accessibilityLabel(
                    manager.isActive
                        ? String(localized: LocalizedStringResource.menuStatusActive)
                        : String(localized: LocalizedStringResource.menuStatusInactive)
                )

            if let countdownText {
                countdownLabel(countdownText)
            }
        }
        .onChange(of: countdownKey, initial: true) { _, _ in
            countdown.update(isVisible: true, expiresAt: countdownDeadline)
            refreshCountdownText()
        }
        .onChange(of: countdown.now) { _, _ in
            refreshCountdownText()
        }
    }

    /// Everything that decides whether there is a countdown and which one.
    ///
    /// The Session's identity is in here rather than its deadline because an
    /// indefinite Session has no deadline: keyed on the deadline alone, going
    /// from idle straight to an indefinite Session would look like no change,
    /// and the label would never be told to draw anything.
    private struct CountdownKey: Equatable {
        let sessionID: UUID?
        let isEnabled: Bool
    }

    private var countdownKey: CountdownKey {
        CountdownKey(sessionID: manager.session?.id, isEnabled: showsCountdown)
    }

    /// The deadline the label counts down to, or `nil` when it shows no
    /// countdown at all — which is also what stops the clock.
    private var countdownDeadline: Date? {
        guard showsCountdown, manager.isActive else { return nil }

        return manager.session?.expiresAt
    }

    /// The countdown itself, or the mark that stands in for one with no
    /// deadline to count down to.
    @ViewBuilder
    private func countdownLabel(_ text: String) -> some View {
        if text == MenuBarCountdown.indefinite {
            // The glyph already says the Session is running, and reading
            // "infinity" out after it adds nothing.
            Text(text)
                .monospacedDigit()
                .accessibilityHidden(true)
        } else {
            Text(text)
                .monospacedDigit()
                .accessibilityLabel(spokenCountdown)
        }
    }

    private func refreshCountdownText() {
        guard showsCountdown, let session = manager.session else {
            countdownText = nil
            return
        }

        guard let expiresAt = session.expiresAt else {
            // An indefinite Session has nothing to count down to, so the glyph
            // stands alone with the mark the popover uses for it.
            countdownText = MenuBarCountdown.indefinite
            return
        }

        countdownText = MenuBarCountdown.text(
            remainingSeconds: SessionRingProgress.remainingSeconds(
                until: expiresAt,
                at: countdown.now
            )
        )
    }

    /// The countdown read out plainly. "29m" is a menu bar abbreviation, not
    /// something to say aloud, and the copy for saying it plainly already
    /// exists and is translated.
    private var spokenCountdown: String {
        guard let expiresAt = manager.session?.expiresAt else {
            return MenuBarCountdown.indefinite
        }

        return SessionCountdown.text(
            forRemainingSeconds: SessionRingProgress.remainingSeconds(
                until: expiresAt,
                at: countdown.now
            )
        )
    }
}
