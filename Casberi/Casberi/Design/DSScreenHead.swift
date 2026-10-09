import SwiftUI

/// A screen's name, in its content (prd §767).
///
/// The system's large title stood at the top edge at 34pt, beside a back
/// chevron. The name sits in the rows' column and scrolls away with them
/// (§767) — and since prd §915 it takes its OWN rung, `heading34`: at
/// `heading24` the screen's name, its sections, its switcher and "Since you
/// left" were four jobs on one rung, so nothing on the Accounts screen
/// outranked anything else. One scale now: the screen at 34, a section at
/// 24, a switcher's words at 17.
///
/// **A room wears one too, since prd §930.** Until then no room had a title:
/// the dock's lit tile named the category under your thumb. With the strip
/// folded into the rooms tray, nothing on the screen said which room you were
/// in, so every room names itself here, first in its list, the way a pushed
/// screen does.
struct DSScreenHead: View {
    let title: Text
    /// A category's name is pink (prd §1129, user: "i meant for ONLY the
    /// category to be in pink"); a pushed screen's stays primary.
    var ink: Color = DS.textPrimary

    var body: some View {
        title
            .dsText(.heading34)
            .foregroundStyle(ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// **A CATEGORY'S TITLE ROW (prd §1129, §1133).** Its name in pink, and
/// once something in it is picked, the pick after a dot in the primary ink:
/// "Wallet · Coinbase", "You · Settings". A label that presses nothing (§1133:
/// the face says where, the tiles say what), on one line at one height
/// picked or not, so nothing under it moves; a long pair shrinks to fit.
/// Every room draws it first in its list, and You's three screens (Apps,
/// Addresses, Settings) draw it in place of their own heads.
struct DSRoomTitleRow: View {
    let title: String
    var pick: String? = nil
    @Environment(\.sizeCategory) private var sizeCategory

    var body: some View {
        DSScreenHead(title: label, ink: DS.brandInk)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            // ONE HEIGHT, whatever the name (prd §1136f, user: "the box should
            // never move down!"): a long pair shrinks to fit, and the row used
            // to shrink with it, so the box and the tiles under it moved with
            // the length of your name. The row is the rung's full line, always.
            .frame(height: Self.height, alignment: .leading)
            .accessibilityLabel(Text(verbatim: pick.map { "\(title), \($0)" } ?? title))
    }

    /// The rung's line at its full size, scaled for Dynamic Type as the
    /// words are.
    static var height: CGFloat {
        let style = DSTextStyle.heading34
        return UIFontMetrics(forTextStyle: style.relative)
            .scaledValue(for: style.lineHeight * style.platformSize / style.size)
    }

    private var label: Text {
        guard let pick else { return Text(verbatim: title) }
        return Text(verbatim: title)
            + Text(verbatim: " · ").foregroundStyle(DS.textTertiary)
            + Text(verbatim: pick).foregroundStyle(DS.textPrimary)
    }
}

/// **THE TWO POLES' TITLE (prd §1203 item 5, user: "i think if it is a gray
/// label someone will want to tap it tho").** On the Feed and the Wallet the
/// title names both pages, in the swipe's order: the one you stand on in the
/// category pink, the other in the tertiary ink and pressable, the way
/// "For you · Following" reads. A narrow exception to §752: the third way to
/// make the move the swipe and the tray already make, never the only one.
/// One height with `DSRoomTitleRow`, so nothing under it moves.
struct DSPoleTitleRow: View {
    /// Whether the Wallet is the page standing.
    let walletStands: Bool
    /// The other pole, pressed.
    let onOther: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s3) {
            word(String(localized: "Feed"), standing: !walletStands)
            word(String(localized: "Wallet"), standing: walletStands)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .frame(maxWidth: .infinity, minHeight: DSRoomTitleRow.height,
               maxHeight: DSRoomTitleRow.height, alignment: .leading)
        .animation(DS.Motion.standard, value: walletStands)
    }

    @ViewBuilder
    private func word(_ name: String, standing: Bool) -> some View {
        if standing {
            DSScreenHead(title: Text(verbatim: name), ink: DS.brandInk)
                .fixedSize()
        } else {
            Button(action: onOther) {
                DSScreenHead(title: Text(verbatim: name), ink: DS.textTertiary)
                    .fixedSize()
                    .contentShape(Rectangle())
            }
            .buttonStyle(RowPress())
            .accessibilityHint(Text("Shows this page"))
        }
    }
}
