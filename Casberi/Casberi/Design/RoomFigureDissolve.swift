import SwiftUI

/// THE SLOT DISSOLVE (2026-08-27, prd §501) — a scope's lead drawing fades in
/// where it used to appear already there.
///
/// **Why this is not the ruling it looks like it reverses.** §495 made a scope
/// pick INSTANT and stated the reason: animating a swap between two slots of
/// different natural height moves everything below the bar and settles it
/// back. That reason is about LAYOUT, and this modifier touches none — it
/// animates `opacity` and nothing else, on a view that is laid out at its
/// final size on the first frame. Nothing above, below or beside it can move
/// as a result, so the pick stays exactly as instant as it was; only the
/// picture arrives rather than being suddenly present.
///
/// **A fade-IN, deliberately, not a crossfade.** A crossfade needs the
/// outgoing view held in the hierarchy while it fades, which is a removal
/// transition, which IS layout — the exact thing above.
///
/// **Keyed rather than appear-only**, because the two rooms compose their
/// slots differently: Vibenet's `scopeVisual` is one `Group` that persists
/// across picks (so `onAppear` fires once, ever), while a room that emits a
/// different view per scope remounts. Keying on the scope covers both, and
/// costs the remounting case nothing — the fade simply happens on appear and
/// on change, and only one of the two can be true at a time.
///
/// Reduce Motion renders the final frame immediately, per `ChartEntrance`'s
/// own rule. It reads the environment itself rather than taking the flag as a
/// parameter (`MicroMotion`'s side of that split): this modifier sequences
/// nothing, so no caller holds a beat it has to stay in step with.
private struct RoomFigureDissolve<K: Equatable>: ViewModifier {
    let key: K
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .onAppear { arrive() }
            .onChange(of: key) { _, _ in
                guard !reduceMotion else { return }
                // The zero has to RENDER before the fade, or SwiftUI coalesces
                // both writes into one frame and there is no transition to
                // watch — the same runloop turn `VibenetRoomCard`'s count-up
                // takes for the same reason.
                shown = false
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 8_000_000)
                    withAnimation(.easeOut(duration: RoomFigureMotion.dissolve)) { shown = true }
                }
            }
    }

    private func arrive() {
        guard !reduceMotion else { shown = true; return }
        withAnimation(.easeOut(duration: RoomFigureMotion.dissolve)) { shown = true }
    }
}

enum RoomFigureMotion {
    /// How long a scope's drawing takes to arrive. Shorter than
    /// `ChartEntrance.wipe` on purpose: this is the FRAME arriving, and the
    /// drawing's own entrance plays inside it — a slow fade would hold the
    /// wipe hostage behind it and read as the room being sluggish.
    static let dissolve: Double = 0.18
}

extension View {
    /// The scope's lead drawing arrives rather than simply being there.
    /// Opacity only — see `RoomFigureDissolve` for why nothing else may move.
    func roomFigureDissolve<K: Equatable>(_ key: K) -> some View {
        modifier(RoomFigureDissolve(key: key))
    }
}
