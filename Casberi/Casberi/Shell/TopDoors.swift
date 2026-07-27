import SwiftUI

/// The avatar door — the Settings entry. Lived alone in the top-right
/// toolbar corner until 2026-07-20, when it joined the catalogue door as a
/// second FIXED leading chip in `SourceChips` (Stories-style: your own face
/// leads the strip, same as the catalogue door already did) — the vacated
/// nav bar is hidden entirely (`MainSurface`), so this is the only way to
/// Settings now. Kept as its own small view (not folded directly into
/// `SourceChips`) so `AvatarDoor`/`DoorSpin`/`DoorBounce` stay one shared
/// definition regardless of where the door lives.
struct AvatarChip: View {
    var onSettings: () -> Void
    /// Bumped by pull-to-refresh — the avatar does one full spin while the
    /// refresh runs: it's the person's own face doing the work.
    var refreshSpin: Int = 0
    /// The zoom transition anchor — Settings grows out of the avatar. Shared
    /// with `SourceChips`'s own `zoomNS` (the catalogue door's "appsDoor"
    /// transition lives in the same namespace under a different id).
    var zoomNS: Namespace.ID? = nil
    /// Taps bounce the door (Telegram grammar, same as the tab icons).
    @State private var avatarBounce = 0
    /// Last time the door actually opened — see `openSettings()` below.
    @State private var lastOpen: TimeInterval = 0

    var body: some View {
        Button {
            // A real action again (2026-07-26), not a no-op: whichever
            // recognizer wins the press, the door opens. Same shape as
            // `SourceChips.catalogueChip`, which this door sits beside.
            open()
        } label: {
            ZStack {
                Circle().fill(DS.gray100)
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
            .frame(width: 46, height: 46)
            // The door is the circle. This one was never as bad as the
            // catalogue's — its `Circle().fill` renders across the whole
            // 46pt, so the region was already whole — but stating it means
            // the two doors beside each other can't drift on what a press
            // has to hit.
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Settings")
        // See `SourceChips.catalogueChip`'s comment: a plain Button here
        // competes with the paged feed TabView's pan recognizer for the
        // first touch (Apple forums thread 725366) and can need several
        // taps to win. `highPriorityGesture` wins immediately — kept as the
        // belt beside the Button's own braces above.
        .highPriorityGesture(TapGesture().onEnded { open() })
    }

    /// One entry point for the door's two possible tap deliveries, coalesced
    /// so the fallback can never double-bounce or double-push.
    private func open() {
        let now = Date().timeIntervalSinceReferenceDate
        guard now - lastOpen > 0.4 else { return }
        lastOpen = now
        avatarBounce += 1
        onSettings()
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
