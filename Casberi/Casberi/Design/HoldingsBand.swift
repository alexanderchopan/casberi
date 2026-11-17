import SwiftUI

/// **HOME'S MAP IS A BAND (prd §1843).** On the phone's Home the holdings
/// map is one row: each holding a tile as wide as its share, wearing its
/// mark and no figure, filled by its day as the map's tiles are (§1837).
/// The balance over it says how much; the band says what of. It is a
/// picture and one door (the caller's button): a tile is too narrow to be a
/// target of its own.
struct HoldingsBand: View {
    struct Cell: Identifiable, Equatable {
        let id: String
        let usd: Double
    }

    /// Biggest first, the tail already folded into Other (`cells(_:)`).
    let cells: [Cell]
    /// Each holding's day move, by `HoldingMoves.key`.
    let moves: [String: Double]
    /// SimpleFIN picked (prd §1702): a currency is that bank's cash.
    var pickIsBank = false

    static let height: CGFloat = 52
    static let gap: CGFloat = 3
    /// A tile never narrower than its mark and its air.
    static let minWidth: CGFloat = 44

    /// The top five and the rest as one Other, the map's own fold (§939).
    static func cells(_ worth: [String: Double]) -> [Cell] {
        let sorted = worth.filter { $0.value > 0 }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
        let rest = sorted.dropFirst(5).reduce(0) { $0 + $1.value }
        return sorted.prefix(5).map { Cell(id: $0.key, usd: $0.value) }
            + (rest > 0 ? [Cell(id: HoldingsTreemapLayout.otherID, usd: rest)] : [])
    }

    /// Each tile's width: its share of the row, never under `minWidth`; the
    /// tiles above the floor share what the floored ones leave.
    static func widths(_ cells: [Cell], in total: CGFloat) -> [CGFloat] {
        let room = total - gap * CGFloat(max(0, cells.count - 1))
        guard room > 0, !cells.isEmpty else { return [] }
        var floored = Set<Int>()
        var widths = [CGFloat](repeating: minWidth, count: cells.count)
        for _ in cells.indices {
            let free = room - CGFloat(floored.count) * minWidth
            let worth = cells.indices.filter { !floored.contains($0) }.reduce(0) { $0 + cells[$1].usd }
            var changed = false
            for i in cells.indices where !floored.contains(i) {
                let width = worth > 0 ? free * CGFloat(cells[i].usd / worth) : free / CGFloat(cells.count - floored.count)
                if width < minWidth {
                    floored.insert(i)
                    changed = true
                } else {
                    widths[i] = width
                }
            }
            if !changed { break }
        }
        for i in floored { widths[i] = minWidth }
        return widths
    }

    private func move(_ id: String) -> Double? {
        id == HoldingsTreemapLayout.otherID ? nil : moves[HoldingMoves.key(id)]
    }

    var body: some View {
        GeometryReader { geo in
            let widths = Self.widths(cells, in: geo.size.width)
            // The row's strength is its biggest drawn move (§1081's rule).
            let widest = cells.compactMap { move($0.id) }.map(abs).max() ?? 0
            HStack(spacing: Self.gap) {
                ForEach(Array(cells.enumerated()), id: \.element.id) { index, cell in
                    mark(cell.id)
                        .frame(width: index < widths.count ? widths[index] : Self.minWidth, height: Self.height)
                        .background(HoldingsTreemap.dayFill(move: move(cell.id), widest: widest),
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
        .frame(height: Self.height)
        .accessibilityHidden(true)
    }

    /// The tile's mark, as the map's tile wears it.
    @ViewBuilder
    private func mark(_ id: String) -> some View {
        let size = DS.Mark.badge + 4
        if id == HoldingsTreemapLayout.otherID {
            Image(systemName: "ellipsis")
                .dsGlyph(.body, weight: .semibold)
                .foregroundStyle(DS.textSecondary)
        } else if let app = WalletPortfolio.appCell(id) {
            // An app's tile wears its Apps row's mark (prd §1698).
            if let bank = SimpleFINShape.connID(fromHolder: app.address) {
                BankMark(connID: bank, size: size)
            } else {
                BridgeIcon(name: FeedScreen.venueMark(app), size: size)
            }
        } else if pickIsBank, Locale.commonISOCurrencyCodes.contains(id) {
            PickBankMark(currency: id, size: size)
        } else {
            AssetMark(name: id, size: size)
        }
    }
}
