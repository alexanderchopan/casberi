import SwiftUI

/// **ONE TOKEN ROW, HOME'S AND MOVE'S (prd §1859, §1917).** The token's mark
/// in the rows' lead column; its name over where it is, in grey; its dollars
/// trailing, over a second grey line (the day on Home). Home's holdings draw
/// it, and so does every token list in Move (`MoveTokenGrid`), so a token you
/// pick to move is the row you know from Home (user, 2026-11-20: "the home
/// screen is very very good … i still feel like things are confusing or hard
/// when i am in move").
struct TokenRowLabel: View {
    let symbol: String
    var line: String?
    var lineInk: Color = DS.textSecondary
    var figure: String?
    var figureInk: Color = DS.textPrimary
    var under: String?
    var underInk: Color = DS.textSecondary
    /// A pick in a Move list: its name in the pick's ink.
    var picked = false
    /// **ON THE RECEIPT'S GRID (prd §1932):** in Move's lists the mark
    /// stands in the receipt's label column, the symbol and its network on
    /// one line where the chips start, the figure trailing, at the
    /// receipt's one pitch.
    var grid = false

    var body: some View {
        if grid { gridBody } else { stackBody }
    }

    private var gridBody: some View {
        HStack(alignment: .center, spacing: 0) {
            AssetMark(name: symbol, size: DS.Mark.row)
                .frame(width: MoveReceipt.labelWidth, alignment: .leading)
                .accessibilityHidden(true)
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                Text(verbatim: symbol).dsText(.heading17).foregroundStyle(picked ? DS.pickInk : DS.textPrimary)
                if let line, !line.isEmpty {
                    Text(verbatim: line).dsText(.body17).foregroundStyle(lineInk)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .layoutPriority(1)
            Spacer(minLength: DS.Space.s2)
            if let figure {
                Text(verbatim: figure).dsText(.price17).monospacedDigit().foregroundStyle(figureInk).lineLimit(1)
            }
        }
        .frame(minHeight: MoveReceipt.lineHeight + MoveReceipt.gap)
        .contentShape(Rectangle())
    }

    private var stackBody: some View {
        HStack(alignment: .center, spacing: DSRoomChassis.headGap) {
            AssetMark(name: symbol, size: DS.Mark.row)
                .frame(width: DSRoomChassis.headGlyph)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: symbol).dsText(.body17).foregroundStyle(picked ? DS.pickInk : DS.textPrimary).lineLimit(1)
                if let line, !line.isEmpty {
                    Text(verbatim: line).dsText(.subhead12).foregroundStyle(lineInk).lineLimit(1)
                }
            }
            Spacer(minLength: DS.Space.s2)
            VStack(alignment: .trailing, spacing: 2) {
                if let figure {
                    Text(verbatim: figure).dsText(.price17).monospacedDigit().foregroundStyle(figureInk).lineLimit(1)
                }
                if let under {
                    Text(verbatim: under).dsText(.subhead12).monospacedDigit().foregroundStyle(underInk).lineLimit(1)
                }
            }
        }
        .frame(minHeight: DSFeed.headHeight)
        .contentShape(Rectangle())
    }
}
