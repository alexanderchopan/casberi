import SwiftUI

/// **THE KEY FILTER STRIP, ONCE (prd §715).** The tray's strip and the account
/// detail's strip were verbatim twins — `filterChip` and `keyChip` — which is
/// the drift §480 gave both surfaces one row grammar to end, one component up.
///
/// A capsule strip rather than headings, because a heading you scroll past
/// costs a screenful and a chip you tap costs nothing when you don't. "All"
/// leads and is the rest state, so a surface always opens showing every key
/// its count line counted.
///
/// **Not `DSSectionSwitcher`**, deliberately: that selects with tint, and blue
/// in this room means urgency (a key about to lapse). Which slice you are
/// looking at is not urgent, so the SELECTED chip is a neutral fill —
/// `fillStrong`/`fillFaint`, the source strip's own selected grammar.
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
            HStack(spacing: 5) {
                Text(label)
                    .dsText(.label12).fontWeight(.semibold)
                if let count {
                    Text("\(count)")
                        .dsText(.label12)
                        .monospacedDigit()
                        .opacity(0.7)
                }
            }
            .foregroundStyle(on ? DS.textPrimary : DS.textSecondary)
            .padding(.horizontal, DS.Space.s3)
            .padding(.vertical, 6)
            .background(Capsule(style: .continuous).fill(on ? DS.fillStrong : DS.fillFaint))
            .contentShape(Capsule())
        }
        .buttonStyle(PressSpring())
        .dsHover()
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }
}

/// **ONE KEY'S PERMISSIONS, AS CHIPS (§463), ONCE (prd §715).** Drawn by
/// `VibenetKeySheet` and by the account detail's key row, byte for byte, so a
/// key reads the same on the row and on its own sheet — which two copies can
/// only promise until one of them is edited.
///
/// Three claims, three treatments. ADMIN inverts: scope 0 is every capability
/// there is, including reserved ones this build cannot name, so it must not
/// read as one more permission among five. The unknown tail is OUTLINED — a
/// visibly different claim from a named permission, never an invented name in
/// the same fill.
struct VibenetScopeChips: View {
    let scope: VibenetScope

    private static let mark = DS.brandHue(for: "Base Vibenet") ?? Color.fixed("#0052ff")

    var body: some View {
        let labels = scope.grantedPlainLabels
        let isAdmin = scope.isAdmin
        FlowLayout(spacing: 6) {
            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                let isUnknownTail = index == labels.count - 1 && scope.unknownCount > 0
                Text(label)
                    .dsText(.label11)
                    .fontWeight(isAdmin ? .semibold : .regular)
                    .foregroundStyle(isAdmin ? DS.page
                                     : (isUnknownTail ? DS.textTertiary : DS.textPrimary))
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background {
                        if isAdmin {
                            Capsule().fill(DS.textPrimary)
                        } else if isUnknownTail {
                            Capsule().strokeBorder(DS.textTertiary, lineWidth: 1)
                        } else {
                            Capsule().fill(Self.mark.opacity(0.12))
                        }
                    }
            }
        }
    }
}
