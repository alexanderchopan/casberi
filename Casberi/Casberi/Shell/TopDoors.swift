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
    /// Taps bounce their door (Telegram grammar, same as the tab icons).
    @State private var appsBounce = 0
    @State private var avatarBounce = 0

    var body: some ToolbarContent {
        // Both doors sit together on the right — they are one cluster of
        // management controls, and the left edge stays clear for titles and
        // the Home cover text.
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                appsBounce += 1
                onApps()
            } label: {
                AppsDoor().symbolEffect(.bounce, value: appsBounce)
            }
            .accessibilityLabel("Apps")
            .tint(DS.tint)
            Button {
                avatarBounce += 1
                onSettings()
            } label: {
                AvatarDoor().modifier(DoorBounce(trigger: avatarBounce))
            }
            .accessibilityLabel("Settings")
        }
    }
}

/// The tap bounce for a door that may be a PHOTO (the set avatar) — a symbol
/// effect can't move a UIImage, so the spring scale carries the same beat.
private struct DoorBounce: ViewModifier {
    let trigger: Int
    @State private var up = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(up ? 1.2 : 1)
            .onChange(of: trigger) {
                withAnimation(.spring(response: 0.18, dampingFraction: 0.45)) { up = true }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(140))
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) { up = false }
                }
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
