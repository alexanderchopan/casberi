import SwiftUI

/// A pill chip — the app's smallest interactive unit. Lived in `Shell/Composer.swift`
/// until prd §715 moved it here, where people look for a template: ten
/// capsule buttons across `Screens/` were drawn by hand beside it.
struct Chip: View {
    /// `neutral` is a word you can tap, `tint` is one the app is nudging you
    /// toward, and `primary` is THE verb of the block it sits in — filled,
    /// white on tint (2026-08-28).
    ///
    /// The third rung exists because there was no small primary in the system
    /// and `NameAddressPrompt` had hand-rolled one: `Text` in a
    /// `Capsule().fill(DS.tint)` with its own padding, which is the shape this
    /// type is. `VerbCapsule` was not it — that is the store's closed verb set
    /// (Connect / Pair / Fix / Open / Soon) and takes a `CapsuleVerb`, not a
    /// sentence. Deliberately still the chip's own size: a primary chip is a
    /// chip, and the moment it grows its own metrics it is a button wearing a
    /// chip's name.
    enum Style { case tint, neutral, primary }
    let text: String
    var style: Style = .neutral
    var glyph: String? = nil
    /// `false` for a chip that is a word and not a control (a note's tags, a
    /// permission list): no pointer hover lighting up something inert (§715).
    var interactive = true

    var body: some View {
        HStack(spacing: DS.Space.s1) {
            if let glyph {
                Image(systemName: glyph).dsGlyph(12, weight: .regular)
                    .accessibilityHidden(true)
            }
            // A chip is a capsule — its label never breaks across lines
            // (2026-07-21: a squeezed row wrapped "Try with your key" into
            // "Try with / your key" inside a 28pt capsule).
            Text(text).dsText(.label12).lineLimit(1)
        }
        .foregroundStyle(ink)
        .padding(.horizontal, DS.Space.s3)
        .frame(minHeight: 28)
        .fixedSize(horizontal: true, vertical: false)
        .background(wash, in: Capsule(style: .continuous))
        // DRAWN 28, TARGETED 44 — but only for a chip that IS a control. A
        // non-interactive chip is a word inside someone else's layout (a
        // note's tags, a permission list) and a 44pt floor there would push
        // that layout apart for a target nothing can hit; size 0 is a no-op.
        .dsTapTarget(Capsule(style: .continuous), size: interactive ? DS.Hit.min : 0)
        // Folded in HERE rather than at each call site, the same reasoning
        // `dsListCardRow` states: every Chip is the label of a Button, so a
        // screen that reaches for one gets Mac hover with no separate
        // decision. No tooltip — a chip is a word.
        .dsHover()
        .hoverEffectDisabled(!interactive)
    }

    private var ink: Color {
        switch style {
        case .tint:    return DS.tint
        case .neutral: return DS.textPrimary
        case .primary: return .white
        }
    }

    private var wash: Color {
        switch style {
        case .tint:    return DS.tintDim
        case .neutral: return DS.gray100
        case .primary: return DS.tint
        }
    }
}
