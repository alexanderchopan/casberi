import SwiftUI

// Split out of `AgentBar.swift` when the bar was deleted (prd §697,
// 2026-09-11). This modifier is the composer's RISE — it has nothing to do
// with the agent beyond having been written beside it, and `Composer`'s own
// note is the authority on why the match sits where it does.

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

