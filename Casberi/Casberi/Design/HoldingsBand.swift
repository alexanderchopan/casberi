import SwiftUI

/// **THE PLATE ENDS IN THE MAP (prd §1856, over §1851's Holdings row).** On
/// the phone's Home the holdings map is the plate's foot: one row of square
/// tiles run edge to edge, the plate's corners cutting the outer two. Each
/// tile is as wide as its share and says its token's name over its dollars,
/// no mark (user: "the tokens inside the balance bar don't work as circle
/// icons bc they compete w/ the app icons"), filled by its day as the map's
/// tiles are (§1837). Three tokens at most, and a fourth tile only when it is
/// Other (user: "only show top 3 or 4 if 4 is 'other'"). The whole foot is
/// Holdings' door, as the row it replaces was.
struct HoldingsBand: View {
    struct Cell: Identifiable, Equatable {
        let id: String
        let usd: Double
    }

    /// Biggest first, the rest already folded into Other (`cells(_:named:)`).
    let cells: [Cell]
    /// Each holding's day move, by `HoldingMoves.key`.
    let moves: [String: Double]
    /// Hide balances: a tile says its share, never its dollars.
    var masked = false

    static let height: CGFloat = 56
    static let gap: CGFloat = 2
    /// A tile never narrower than its name.
    static let minWidth: CGFloat = 64
    /// As many tokens as the foot names; the rest is Other.
    static let named = 3

    /// The three biggest tokens `isToken` admits, then Other: everything
    /// else, places and apps included, so the tiles' widths add up to the
    /// balance. No Other when nothing is left.
    static func cells(_ worth: [String: Double], isToken: (String) -> Bool) -> [Cell] {
        let held = worth.filter { $0.value > 0 }
        let tokens = held.filter { isToken($0.key) }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(named).map { Cell(id: $0.key, usd: $0.value) }
        let shown = Set(tokens.map(\.id))
        let rest = held.filter { !shown.contains($0.key) }.reduce(0) { $0 + $1.value }
        // A cent of dust is not a tile.
        return tokens + (rest >= 0.01 ? [Cell(id: HoldingsTreemapLayout.otherID, usd: rest)] : [])
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
            let total = cells.reduce(0) { $0 + $1.usd }
            HStack(spacing: Self.gap) {
                ForEach(Array(cells.enumerated()), id: \.element.id) { index, cell in
                    tile(cell, total: total)
                        .frame(width: index < widths.count ? widths[index] : Self.minWidth,
                               height: Self.height, alignment: .leading)
                        // Square, named: a bare `.background(style)` takes
                        // the container's shape, which inside a Button in
                        // a List is a capsule (seen on iOS 27).
                        .background(HoldingsTreemap.dayFill(move: move(cell.id), widest: widest), in: Rectangle())
                }
            }
        }
        .frame(height: Self.height)
        .accessibilityElement(children: .combine)
    }

    /// The name over the dollars (the share under Hide balances).
    private func tile(_ cell: Cell, total: Double) -> some View {
        let other = cell.id == HoldingsTreemapLayout.otherID
        let figure = masked
            ? "\(Int((total > 0 ? cell.usd / total * 100 : 0).rounded()))%"
            : WalletValue.money(cell.usd)
        return VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: other ? String(localized: "Other") : cell.id)
                .dsText(.fact15)
                .fontWeight(.semibold)
                .foregroundStyle(DS.textPrimary)
            Text(verbatim: figure)
                .dsText(.label12)
                .monospacedDigit()
                .foregroundStyle(DS.textSecondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.leading, DS.Space.s3)
        .padding(.trailing, DS.Space.s1)
    }
}
