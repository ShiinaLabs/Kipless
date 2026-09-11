import SwiftUI

/// The menu bar glyph.
///
/// Plain template symbols, so they follow the menu bar's own light/dark
/// rendering without any custom assets. Awake is a filled bolt, inactive is the
/// same bolt struck through — the two read differently even at menu bar size.
struct MenuBarLabel: View {
    let isActive: Bool

    var body: some View {
        Image(systemName: isActive ? "bolt.fill" : "bolt.slash")
            .accessibilityLabel(
                isActive
                    ? String(localized: KiplessStrings.menuStatusActive)
                    : String(localized: KiplessStrings.menuStatusInactive)
            )
    }
}
