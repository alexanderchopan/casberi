import SwiftUI

/// The agent's bar (docs/agent-brief.md, ruling 6) — replaces the FAB.
/// Floating-layer glass, rides every screen (hosted in `RootShell`'s own
/// ZStack, not `MainSurface`'s, so pushed rooms — Apps, Settings, a bridge
/// setup form — never slide over it the way they used to slide over the
/// FAB). Tap raises the agent full screen.
///
/// The berry mark breathes (the same idiom `Composer.swift`'s in-flight
/// "Thinking…" state already uses) while some kept ask changed and the agent
/// hasn't been raised yet this launch — ruling 6: no number badges, ever.
///
/// Morphs into the risen surface (2026-07-20) — `morphNS` is the SAME
/// namespace `RootShell` gives `Composer`'s `glassNamespace`, and `"agentMorph"`
/// the same id both sides key on, so the bar's own frame is what the risen
/// sheet visibly grows out of (`matchedGeometryEffect`, not `glassEffectID` —
/// the risen surface is plain ink, never glass, per design law §8 "Liquid
/// Glass on the floating layer only... never on content panels"; only the
/// SHAPE morphs, the glass itself stays the bar's alone and fades out as the
/// sheet's opaque background fades in). `RootShell` hides this view entirely
/// once risen (`if !composerOpen`) so exactly one side of the pair exists at
/// a time — matchedGeometryEffect needs that alternation to interpolate.
struct AgentBar: View {
    var hasUnseenSignal: Bool
    var morphNS: Namespace.ID?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.s3) {
                Text("Ask your things…")
                    .dsText(.body17)
                    .foregroundStyle(DS.textTertiary)
                Spacer(minLength: 0)
                if hasUnseenSignal {
                    CasberiMark(size: 20).breathing()
                } else {
                    CasberiMark(size: 20)
                }
            }
            .padding(.horizontal, DS.Space.s4)
            .padding(.vertical, DS.Space.s3)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .dsGlass(cornerRadius: DS.Radius.pill)
        .modifier(MorphMatch(ns: morphNS))
    }
}

/// Applies `matchedGeometryEffect` only when a real namespace was given —
/// `RootShell` always supplies one, but keeps this optional so a future
/// preview/embedding of `AgentBar` without a namespace doesn't crash on a
/// force-unwrap. Shared with `Composer` (not file-private) — both sides of
/// the morph key the exact same id/namespace pairing, so one modifier
/// keeps them from drifting apart.
struct MorphMatch: ViewModifier {
    let ns: Namespace.ID?
    func body(content: Content) -> some View {
        if let ns {
            content.matchedGeometryEffect(id: "agentMorph", in: ns)
        } else {
            content
        }
    }
}
