import SwiftUI

/// **MARKETS' BOX IS THE SECTORS' DAY (prd §1391, user: "each tile is how
/// much up or down that sector is … it should just be how the sector did";
/// of the ten-tile box: "it looks weird b/c we have two sizes of buttons").**
/// Every other Wallet page's box is a figure (the balance, the map, the
/// checkup); Markets' was a menu. Now it says one thing: how the eight packs
/// did today — "Today · 6 sectors up, 2 down", then the packs four across,
/// each its category glyph, its name and the mean day move of its traded
/// companies, washed and edged by that move as Holdings' tiles are (§1389).
/// A press lists the pack below, as the tile did; the picked pack wears the
/// pick ink (§1385). A pack with no quote yet draws the plain fill and no move (§83).
struct MarketsSectorsBox: View {
    let packs: [TokensScope]
    let picked: TokensScope
    let pick: (TokensScope) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The mean day move of a pack's traded companies, as a fraction; nil
    /// until one of them has a quote.
    static func move(of pack: [CompanyPacks.Company], quotes: CompanyQuotes) -> Double? {
        let changes = pack.compactMap { quotes.quote($0.listing)?.change }
        guard !changes.isEmpty else { return nil }
        return changes.reduce(0, +) / Double(changes.count)
    }

    var body: some View {
        let quotes = CompanyQuotes.shared
        let moves = packs.map { ($0, Self.move(of: $0.pack, quotes: quotes)) }
        let up = moves.filter { ($0.1 ?? 0) > 0 && !TokenChartStyle.isFlat($0.1 ?? 0) }.count
        let down = moves.filter { ($0.1 ?? 0) < 0 && !TokenChartStyle.isFlat($0.1 ?? 0) }.count
        let read = moves.contains { $0.1 != nil }
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                Text("Today").dsText(.heading20).foregroundStyle(DS.textPrimary)
                if read {
                    Text("\(up) sectors up, \(down) down")
                        .dsText(.body17).foregroundStyle(DS.textSecondary)
                        .contentTransition(.numericText())
                }
            }
            .padding(.horizontal, DS.Space.s1)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.s2), count: 4),
                      spacing: DS.Space.s2) {
                ForEach(moves, id: \.0.id) { scope, move in
                    cell(scope, move: move)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(reduceMotion ? nil : DS.Motion.standard, value: read)
    }

    private func cell(_ scope: TokensScope, move: Double?) -> some View {
        let lit = scope == picked
        let flat = move.map(TokenChartStyle.isFlat) ?? true
        let hue: Color? = (move.map { $0 > 0 } ?? false) ? DS.confirm : (move.map { $0 < 0 } ?? false) ? DS.destructive : nil
        let ink: Color = lit ? .white : flat ? DS.textTertiary : (move ?? 0) > 0 ? DS.confirmInk : DS.destructiveInk
        return Button {
            DSHaptic.selection()
            pick(scope)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: scope.glyph)
                    .dsGlyph(.body, weight: .regular)
                    .foregroundStyle(lit ? Color.white : DS.brandInk)
                Text(verbatim: scope.label)
                    .dsText(.label12)
                    .foregroundStyle(lit ? Color.white : DS.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let move {
                    Text(TokenChartStyle.changeText(move))
                        .dsText(.label12)
                        .monospacedDigit()
                        .foregroundStyle(ink)
                        .contentTransition(.numericText())
                }
            }
            .padding(.vertical, DS.Space.s2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Unpainted, as Holdings' map is (prd §1389): a wash and an edge.
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(lit ? DS.pickInk : (flat ? DS.fillFaint : (hue ?? DS.fillFaint).opacity(0.14))))
            .overlay {
                if !lit, !flat, let hue {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(hue.opacity(0.6), lineWidth: 1.5)
                }
            }
            .contentShape(Rectangle())
            .animation(DS.Motion.standard, value: lit)
        }
        .buttonStyle(PressSpring())
        .accessibilityLabel(move.map { Text("\(scope.label), \(TokenChartStyle.changeText($0)) today") }
                            ?? Text(verbatim: scope.label))
        .accessibilityAddTraits(lit ? .isSelected : [])
    }
}
