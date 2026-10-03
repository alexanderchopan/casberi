import SwiftUI

/// **THE WALLET'S HOLDINGS, AS APPLE WOULD DRAW THEM (prd §939).**
///
/// The circle pack (§917) scaled the MARK with the share, so a 97% holding
/// was a 200pt coin (user, 2026-09-26: *"the icons look silly blown up that
/// large"*), and the unit treemap it replaced sized tiles by square root, so
/// 97% and 1% looked nearly equal. This one:
///
/// - **True area.** A tile's area is its share of the total, laid out
///   squarified (Bruls, Huizing & van Wijk) so tiles stay close to square.
/// - **The mark is proportional, and capped (prd §957).** A tile carries the
///   token's mark and its share; no name, because the list under the crown
///   names every token (user: *"we don't need token name either"*). The mark
///   is `markRatio` of the tile's shorter side, between `markFloor` and
///   `markCap`: a fixed 22pt read as a speck in a 94% tile (user: *"it just
///   looks weird to have this banker icon so small in the largest square"*),
///   and §917's uncapped mark was a 200pt coin.
/// - **The tail folds.** Anything under `foldShare`, and anything the layout
///   would draw narrower than a tap, joins one "Other" tile that shows its
///   share only; that tile is never narrower than `minSide`.
/// - **Grey, blue when pressed.** Every tile is the same neutral fill; a
///   press lights one in the tint, quiets the rest, and the number above
///   reads that token's value. A second press on a lit tile opens the token.
enum HoldingsTreemapLayout {
    struct Tile: Equatable {
        let id: String
        let share: Double
        let rect: CGRect
    }

    static let foldShare: Double = 0.03
    static let otherID = "@other"

    /// Shares (summing to 1) → tiles in `rect`, after folding the tail.
    static func layout(_ shares: [(id: String, share: Double)], in rect: CGRect,
                       gap: CGFloat, minSide: CGFloat) -> [Tile] {
        guard rect.width > 0, rect.height > 0 else { return [] }
        var kept = shares.filter { $0.id != otherID && $0.share >= foldShare }
            .sorted { $0.share > $1.share }
        var other = 1 - kept.reduce(0) { $0 + $1.share }
        // A tile's LABEL is its true share; only the drawn area of "Other"
        // may be raised to the tap floor, so the label never follows it.
        func labelled(_ tiles: [Tile]) -> [Tile] {
            let truth = Dictionary(uniqueKeysWithValues: kept.map { ($0.id, $0.share) })
            return tiles.map { Tile(id: $0.id, share: truth[$0.id] ?? other, rect: $0.rect) }
        }
        // Fold until every drawn tile clears the tap floor.
        for _ in 0..<8 {
            let tiles = squarify(withOther(kept, other: other, rect: rect, minSide: minSide),
                                 in: rect, gap: gap)
            let tooSmall = tiles.filter { $0.id != otherID && min($0.rect.width, $0.rect.height) < minSide }
            guard !tooSmall.isEmpty else { return labelled(tiles) }
            let drop = Set(tooSmall.map(\.id))
            other += kept.filter { drop.contains($0.id) }.reduce(0) { $0 + $1.share }
            kept.removeAll { drop.contains($0.id) }
        }
        return labelled(squarify(withOther(kept, other: other, rect: rect, minSide: minSide), in: rect, gap: gap))
    }

    /// The kept tiles plus "Other", Other's area raised to the tap floor when
    /// its true share would draw a sliver (the one place a size is not exact;
    /// its label still says its true share).
    private static func withOther(_ kept: [(id: String, share: Double)], other: Double,
                                  rect: CGRect, minSide: CGFloat) -> [(id: String, share: Double)] {
        guard other > 0.0005 else { return kept }
        let floor = Double((minSide * rect.height) / (rect.width * rect.height))
        let drawn = max(other, min(floor, 0.25))
        let scale = (1 - drawn) / max(0.0001, 1 - other)
        return kept.map { ($0.id, $0.share * scale) } + [(otherID, drawn)]
    }

    /// Squarified layout of shares that sum to 1, largest first.
    static func squarify(_ items: [(id: String, share: Double)], in rect: CGRect, gap: CGFloat) -> [Tile] {
        let total = items.reduce(0) { $0 + $1.share }
        guard total > 0 else { return [] }
        let area = Double(rect.width * rect.height)
        var queue = items.map { (id: $0.id, share: $0.share, area: $0.share / total * area) }
        var free = rect
        var out: [Tile] = []
        while !queue.isEmpty {
            let side = Double(min(free.width, free.height))
            var row: [(id: String, share: Double, area: Double)] = [queue.removeFirst()]
            while let next = queue.first,
                  worst(row + [next], side: side) <= worst(row, side: side) {
                row.append(queue.removeFirst())
            }
            let rowArea = row.reduce(0) { $0 + $1.area }
            let horizontal = free.width >= free.height   // lay the row as a column on the left
            let thickness = CGFloat(rowArea / side)
            var offset: CGFloat = 0
            for cell in row {
                let length = CGFloat(cell.area / rowArea) * CGFloat(side)
                let r = horizontal
                    ? CGRect(x: free.minX, y: free.minY + offset, width: thickness, height: length)
                    : CGRect(x: free.minX + offset, y: free.minY, width: length, height: thickness)
                out.append(Tile(id: cell.id, share: cell.share, rect: r))
                offset += length
            }
            free = horizontal
                ? CGRect(x: free.minX + thickness, y: free.minY, width: free.width - thickness, height: free.height)
                : CGRect(x: free.minX, y: free.minY + thickness, width: free.width, height: free.height - thickness)
        }
        // Gaps: inset every tile by half the gap, except along the outer edge.
        return out.map { t in
            var r = t.rect
            let h = gap / 2
            if r.minX > rect.minX + 0.5 { r.origin.x += h; r.size.width -= h }
            if r.maxX < rect.maxX - 0.5 { r.size.width -= h }
            if r.minY > rect.minY + 0.5 { r.origin.y += h; r.size.height -= h }
            if r.maxY < rect.maxY - 0.5 { r.size.height -= h }
            return Tile(id: t.id, share: t.share, rect: r)
        }
    }

    private static func worst(_ row: [(id: String, share: Double, area: Double)], side: Double) -> Double {
        let s = row.reduce(0) { $0 + $1.area }
        guard s > 0, side > 0 else { return .infinity }
        let maxA = row.map(\.area).max() ?? 0
        let minA = row.map(\.area).min() ?? 0
        return max((side * side * maxA) / (s * s), (s * s) / (side * side * minA))
    }

    static let markRatio: CGFloat = 0.3
    static let markFloor: CGFloat = 16
    static let markCap: CGFloat = 56

    /// The mark's side for a tile: the same fraction of every tile.
    static func markSize(for rect: CGRect) -> CGFloat {
        min(markCap, max(markFloor, (min(rect.width, rect.height) * markRatio).rounded()))
    }

    /// "97%" — whole percents, "<1%" never (a folded share is Other's).
    static func percent(_ share: Double) -> String {
        "\(max(1, Int((share * 100).rounded())))%"
    }
}

extension EnvironmentValues {
    /// Each holding's day move by upper-cased symbol (`HoldingMoves`, prd
    /// §1090). Empty everywhere but the Wallet's Holdings box, where a fresh
    /// read turns the grey blocks into the day's heat map.
    @Entry var holdingsDayMoves: [String: Double] = [:]
}

struct HoldingsTreemap: View {
    struct Holding: Equatable {
        let id: String
        let usd: Double
        let route: String?
        /// What a pressed tile reads instead of dollars — a devnet token's own
        /// quantity (prd §949), because test money has no dollar value to state.
        var display: String? = nil
    }

    let total: String
    /// Under the resting number — empty on the Wallet (§939), "assets" on a
    /// devnet, whose number is a count.
    var caption: String = ""
    let holdings: [Holding]
    /// False when the sizes are not shares at all — a devnet where nothing
    /// has a price draws every tile one size, which says "how many", and a
    /// "33%" on each would state a split nobody measured (§83, prd §1084).
    var showsShares: Bool = true
    var onOpen: ((Holding) -> Void)? = nil
    @State private var lit: String?
    /// The lit tile's share as drawn, so "Other" can state its value.
    @State private var litShare: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.holdingsDayMoves) private var dayMoves

    static let gap: CGFloat = 4
    static let minSide: CGFloat = 44

    private var sum: Double { holdings.reduce(0) { $0 + $1.usd } }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            reading
            GeometryReader { geo in
                let tiles = HoldingsTreemapLayout.layout(
                    holdings.map { (id: $0.id, share: sum > 0 ? $0.usd / sum : 0) },
                    in: CGRect(origin: .zero, size: geo.size), gap: Self.gap, minSide: Self.minSide)
                // The board's strength is its biggest DRAWN move: a holding
                // folded into "Other" shows no colour, so it cannot set the
                // scale the drawn tiles are coloured against (§1081's rule).
                let widest = tiles.compactMap { move($0.id) }.map(abs).max() ?? 0
                ZStack(alignment: .topLeading) {
                    ForEach(tiles, id: \.id) { tile in
                        tileView(tile, widest: widest)
                            .frame(width: tile.rect.width, height: tile.rect.height)
                            .offset(x: tile.rect.minX, y: tile.rect.minY)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(reduceMotion ? nil : DS.Motion.standard, value: lit)
    }

    @ViewBuilder
    private var reading: some View {
        if let lit, let holding = holdings.first(where: { $0.id == lit }) {
            DSFigureReading(number: holding.display ?? WalletValue.money(holding.usd), caption: holding.id)
        } else if lit == HoldingsTreemapLayout.otherID, showsShares {
            // With no shares (nothing priced), the folded tail has no share to
            // state either; the count stands.
            // Test money states no dollars (§949): the folded tail reads its share.
            DSFigureReading(number: holdings.contains { $0.display != nil }
                                ? HoldingsTreemapLayout.percent(litShare)
                                : WalletValue.money(litShare * sum),
                            caption: String(localized: "Other"))
        } else if let today = todayCaption {
            DSFigureReading(number: total, caption: today)
        } else {
            DSFigureReading(number: total, caption: caption)
        }
    }

    /// The day's move for a tile, when a fresh read has one.
    private func move(_ id: String) -> Double? {
        dayMoves.isEmpty || id == HoldingsTreemapLayout.otherID ? nil : dayMoves[HoldingMoves.key(id)]
    }

    /// "2 up, 1 down today", Markets' box line (§1081), when any holding
    /// moved — over every holding, as the rows under the box list them, so
    /// the count and the list agree even where a tile folded into "Other".
    private var todayCaption: String? {
        let moves = holdings.compactMap { move($0.id) }
        guard !moves.isEmpty else { return nil }
        let t = HoldingMoves.tally(moves)
        switch (t.up, t.down) {
        case (0, 0): return String(localized: "Flat today")
        case (_, 0): return String(localized: "\(t.up) up today")
        case (0, _): return String(localized: "\(t.down) down today")
        default:     return String(localized: "\(t.up) up, \(t.down) down today")
        }
    }

    /// A tile's fill: the tint when pressed; else its move's hue at its
    /// strength against the board's biggest move (Markets' rule, §1081); a
    /// flat or unread move keeps the plain fill (§83).
    private func fill(_ id: String, lit isLit: Bool, widest: Double) -> Color {
        if isLit { return DS.tint }
        guard let m = move(id), abs(m) >= 0.0005, widest > 0 else { return DS.fillFaint }
        return WatchHeatBox.fill(WatchHeat.Tile(id: id, symbol: id, change: m,
                                                strength: min(1, abs(m) / widest)))
    }

    @ViewBuilder
    private func tileView(_ tile: HoldingsTreemapLayout.Tile, widest: Double) -> some View {
        let isOther = tile.id == HoldingsTreemapLayout.otherID
        let isLit = lit == tile.id
        let small = min(tile.rect.width, tile.rect.height) < 72
        let large = tile.rect.width >= 120 && tile.rect.height >= 90
        Button {
            DSHaptic.selection()
            if isLit, !isOther, let holding = holdings.first(where: { $0.id == tile.id }) {
                onOpen?(holding)
            } else {
                lit = isLit ? nil : tile.id
                litShare = tile.share
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                if !isOther {
                    AssetMark(name: tile.id, size: HoldingsTreemapLayout.markSize(for: tile.rect))
                }
                Spacer(minLength: 0)
                if let m = move(tile.id) {
                    // The heat map's tile (prd §1090): its dollars where it
                    // has the room, and the day's move.
                    if large, let holding = holdings.first(where: { $0.id == tile.id }) {
                        Text(holding.display ?? WalletValue.money(holding.usd))
                            .dsText(.label12)
                            .monospacedDigit()
                            .foregroundStyle(isLit ? Color.white : DS.textPrimary.opacity(0.9))
                            .lineLimit(1)
                    }
                    Text(TokenChartStyle.changeText(m))
                        .dsText(large ? .stat24 : (small ? .label12 : .price17))
                        .monospacedDigit()
                        .foregroundStyle(isLit ? Color.white : DS.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                } else if showsShares {
                    Text(HoldingsTreemapLayout.percent(tile.share))
                        .dsText(large ? .stat24 : (small ? .label12 : .price17))
                        .monospacedDigit()
                        .foregroundStyle(isOther && !isLit ? DS.textSecondary : (isLit ? Color.white : DS.textPrimary))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            .padding(small ? DS.Space.s2 : DS.Space.s3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: small ? 12 : 14, style: .continuous)
                .fill(fill(tile.id, lit: isLit, widest: widest)))
            .opacity(lit != nil && !isLit ? 0.35 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressSpring())
        .accessibilityLabel(move(tile.id).map {
                Text("\(tile.id), \(HoldingsTreemapLayout.percent(tile.share)), \(TokenChartStyle.changeText($0)) today")
            } ?? (showsShares
            ? Text("\(isOther ? String(localized: "Other") : tile.id), \(HoldingsTreemapLayout.percent(tile.share))")
            : Text(isOther ? String(localized: "Other") : tile.id)))
        .accessibilityAddTraits(isLit ? .isSelected : [])
    }
}
