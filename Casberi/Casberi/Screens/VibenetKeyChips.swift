import SwiftUI

/// **THE KEY FILTER STRIP, ONCE (prd §715).** The tray's strip and the account
/// detail's strip were verbatim twins — `filterChip` and `keyChip` — which is
/// the drift §480 gave both surfaces one row grammar to end, one component up.
///
/// A chip strip rather than headings, because a heading you scroll past costs
/// a screenful and a chip you tap costs nothing when you don't. "All" leads
/// and is the rest state, so a surface always opens showing every key its
/// count line counted.
///
/// **Not `DSSectionSwitcher`**, deliberately: that selects with tint, and blue
/// in this room means urgency (a key about to lapse). Which slice you are
/// looking at is not urgent, so the SELECTED chip is a neutral fill — which is
/// `Chip`'s own selection since prd §746, when this strip's hand-drawn capsule
/// became the one choice template it had been the model for.
///
/// The gate is the caller's: the tray draws it for any census, the detail only
/// where there is something to choose between.
struct VibenetKeyFilterStrip: View {
    /// The census, forwarded — never a second derivation, or a card would say
    /// 4 and the list it opens show 3.
    let census: [VibenetPolicyCount]
    @Binding var filter: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Space.s2) {
                chip(label: String(localized: "All"), count: nil, value: nil)
                ForEach(Array(census.enumerated()), id: \.offset) { _, entry in
                    chip(label: entry.label, count: entry.count, value: entry.label)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func chip(label: String, count: Int?, value: String?) -> some View {
        let on = filter == value
        return Button {
            DSHaptic.selection()
            withAnimation(reduceMotion ? nil : DS.Motion.standard) { filter = value }
        } label: {
            Chip(text: label, count: count, selected: on)
        }
        .buttonStyle(PressSpring())
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }
}

/// **ONE KEY'S PERMISSIONS, ONCE (prd §715), AS FACTS (prd §746).** Drawn by
/// `VibenetKeySheet` and by the account detail's key row, byte for byte, so a
/// key reads the same on the row and on its own sheet.
///
/// A permission is a FACT about the key, never a control, so it is a
/// `DSStamp` — a word, not a capsule. The three claims keep three treatments
/// in the only vocabulary a stamp has: ADMIN carries a mark (scope 0 is every
/// capability there is, including reserved ones this build cannot name, so it
/// must not read as one more permission among five); the unknown tail is the
/// quiet weight with no mark; a named permission is the plain word. The
/// inverted admin fill and the outlined tail are gone with the capsules.
struct VibenetScopeChips: View {
    let scope: VibenetScope

    var body: some View {
        let labels = scope.grantedPlainLabels
        let isAdmin = scope.isAdmin
        FlowLayout(spacing: 6) {
            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                let isUnknownTail = index == labels.count - 1 && scope.unknownCount > 0
                DSStamp(word: label,
                        weight: isAdmin ? .good : .quiet,
                        glyph: isAdmin ? "key.fill" : (isUnknownTail ? "questionmark.circle" : nil))
            }
        }
    }
}
