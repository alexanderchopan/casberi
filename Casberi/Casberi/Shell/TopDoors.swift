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
    /// Bumped by Home's pull-to-refresh — the avatar does one full spin
    /// while the refresh runs (2026-07-10): it's the person's own face
    /// doing the work. 0 everywhere else (Feed never spins).
    var refreshSpin: Int = 0
    /// The zoom transition's anchor (2026-07-10): Settings inflates out of
    /// the avatar like a bubble — the destination's navigationTransition
    /// points back at this source. Optional so a caller without the
    /// transition still renders plain doors.
    var zoomNS: Namespace.ID? = nil
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
                if let zoomNS {
                    AvatarDoor()
                        .modifier(DoorBounce(trigger: avatarBounce))
                        .modifier(DoorSpin(trigger: refreshSpin))
                        .matchedTransitionSource(id: "settingsDoor", in: zoomNS)
                } else {
                    AvatarDoor()
                        .modifier(DoorBounce(trigger: avatarBounce))
                        .modifier(DoorSpin(trigger: refreshSpin))
                }
            }
            .accessibilityLabel("Settings")
        }
    }
}

/// One full turn per refresh — additive, so back-to-back pulls keep
/// spinning forward instead of unwinding.
private struct DoorSpin: ViewModifier {
    let trigger: Int
    @State private var angle: Double = 0

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(angle))
            .onChange(of: trigger) {
                withAnimation(.spring(response: 0.8, dampingFraction: 0.8)) {
                    angle += 360
                }
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
/// Sized up alongside the Apps door (2026-07-09): the two doors are the only
/// way to Settings/Apps, so they earn presence in the bar, not a whisper.
struct AvatarDoor: View {
    var body: some View {
        if let avatar = ProfileStore.shared.avatar {
            Image(uiImage: avatar)
                .resizable().scaledToFill()
                .frame(width: 32, height: 32)
                .clipShape(Circle())
        } else {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 26))
                .foregroundStyle(DS.textSecondary)
        }
    }
}

/// The Apps door — a grid glyph, bigger now so the store is findable
/// (report 2026-07-09: the thin glyph was easy to miss). When a bridge needs
/// reconnecting it goes UNMISTAKABLE: the glyph fills, turns the attention
/// color, and pulses — a real breakage signal, never a standing one (the
/// re-ruling 2026-07-07 that killed the tab badge still holds: this is a nav
/// button, not a tab, and it only lights on actual breakage).
struct AppsDoor: View {
    @Environment(BridgeStore.self) private var bridges

    private var needsAttention: Bool { bridges.attentionCount > 0 }

    var body: some View {
        Image(systemName: needsAttention ? "square.grid.2x2.fill" : "square.grid.2x2")
            .font(.system(size: 21, weight: .semibold))
            .foregroundStyle(needsAttention ? DS.attention : DS.tint)
            .symbolEffect(.pulse, options: .repeating, isActive: needsAttention)
    }
}
