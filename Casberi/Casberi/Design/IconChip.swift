import SwiftUI

/// One glyph (or a monogram), in a squircle — the "this row/tile carries a
/// tone" grammar that four screens each reimplemented by hand until now
/// (2026-08-10, the treemap-ink cohesion pass): `AgentPanelGrid.TileBadge`,
/// `AccountScreen`'s row badge, `AccountDetailSheet.badge`, and
/// `NotesImportScreens`' "Open Notes" chip all drew the identical shape —
/// a rounded rect, a frame, an overlay glyph — with their own copy of the
/// corner-radius math and fill logic.
///
/// Two fill styles, because both are load-bearing elsewhere and neither is
/// wrong on its own: `.solid` (opaque tone, white content — the "real app
/// icon" look `AgentPanelGrid`/`AccountDetailSheet` wear) and `.wash` (tone
/// at 16%, tone-colored content — the quieter "settings row" look
/// `AccountScreen`/`NotesImportScreens` wear).
///
/// `content` is a closure, not a fixed SF Symbol string, so a monogram
/// letter (`TileBadge`'s "no known icon" fallback) and a real glyph both fit
/// through the same shell, and a caller that needs its own
/// `.contentTransition`/`.symbolEffect` (the Theme/Privacy rows' sun↔moon,
/// lock↔cloud swap) can still attach those to the `Image` it hands in —
/// this view only owns the shape and the tone, never the glyph's own motion.
/// No bare-glyph convenience initializer on purpose: `Image`'s own
/// `.font(_:)` overload and `View`'s environment one collide under a
/// generic `where Content == Image` constraint, so every caller spells its
/// own `Image(systemName:).font(...)` — three extra words, zero magic.
///
/// Color rule unchanged (DesignTokens.swift's own law): `tone` should carry
/// identity or state. A caller with neither should pass a neutral gray, not
/// `DS.tint` as an "it has to be something" default — the same fake-identity
/// problem `TokenHue` had for an unknown token, one level up.
struct IconChip<Content: View>: View {
    enum Style { case solid, wash }

    let tone: Color
    var size: CGFloat = 34
    /// Defaults to the app-icon squircle ratio; `AgentPanelGrid`'s tiny
    /// tiles pass their own hand-tuned radius instead (the formula reads a
    /// touch soft at 16–18pt).
    var radius: CGFloat? = nil
    var style: Style = .solid
    @ViewBuilder var content: Content

    var body: some View {
        RoundedRectangle(cornerRadius: radius ?? DS.Radius.appIcon(size), style: .continuous)
            .fill(style == .solid ? tone : tone.opacity(0.16))
            .frame(width: size, height: size)
            .overlay {
                content.foregroundStyle(style == .solid ? AnyShapeStyle(.white) : AnyShapeStyle(tone))
            }
    }
}

