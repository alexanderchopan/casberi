import SwiftUI

/// The shell's two doors — the avatar (→ Settings) and the grid (→ Apps) —
/// worn by EVERY tab root (ruling 2026-07-06: not just Home; with two tabs,
/// Feed had no way to reach either without bouncing through Home). One shared
/// component so the doors can't drift apart. The grid carries the attention
/// dot when a bridge needs reconnecting — a nav button, not a tab, so the
/// no-tab-indicator rule holds. Pushed screens keep their back button.
struct TopDoors: ToolbarContent {
    var onSettings: () -> Void
    var onApps: () -> Void

    var body: some ToolbarContent {
        // Both doors sit together on the right — they are one cluster of
        // management controls, and the left edge stays clear for titles and
        // the Home cover text.
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button(action: onApps) { AppsDoor() }
                .accessibilityLabel("Apps")
                .tint(DS.tint)
            Button(action: onSettings) { AvatarDoor() }
                .accessibilityLabel("Settings")
        }
    }
}

/// The avatar (or a person glyph before one's set) — the Settings entry.
struct AvatarDoor: View {
    var body: some View {
        if let avatar = ProfileStore.shared.avatar {
            Image(uiImage: avatar)
                .resizable().scaledToFill()
                .frame(width: 28, height: 28)
                .clipShape(Circle())
        } else {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 22))
                .foregroundStyle(DS.textSecondary)
        }
    }
}

/// The Apps door — a grid glyph that PULSES when a bridge needs
/// reconnecting (re-ruling 2026-07-07: the dot died; the button itself
/// breathes — the only place Apps earns a signal outside its own page).
struct AppsDoor: View {
    @Environment(BridgeStore.self) private var bridges

    var body: some View {
        Image(systemName: "square.grid.2x2")
            .symbolEffect(.pulse, options: .repeating,
                          isActive: bridges.attentionCount > 0)
    }
}
