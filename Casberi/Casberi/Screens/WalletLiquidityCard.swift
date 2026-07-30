import SwiftUI

/// Uniswap liquidity — the wallet room's third live-state card (2026-07-30),
/// beside `WalletLendingCard`. A SIBLING card, not a third row folded into
/// Lending's own: prd §212's reasoning ("Aave and Morpho were never two
/// subjects, they're two providers of one") cuts the other way here — lending
/// asks "is it safe" (collateral/debt/health factor), a Uniswap position asks
/// "is it working" (in range and earning, or silently idle). Different
/// subjects earn different cards; the same subject wearing two providers
/// doesn't.
///
/// V3 and V4 positions MERGE into this one list (user ruling 2026-07-30) —
/// and that's §212's rule applied rather than broken: two protocol versions
/// of the same product are two providers of one subject, exactly like Aave
/// and Morpho. The version survives only as a quiet `v3`/`v4` at the tail of
/// the subline, because two positions on the same pair in different versions
/// really are different positions.
///
/// One row per position, never collapsed the way Aave sums collateral/debt —
/// each position is its own pair and its own range, and summing away the
/// range would erase the one fact that matters. Beneath each row, a small
/// self-scaling range bar (`UniswapRangeBar`) — the module the design-law
/// doctrine asks for (a visualization, not a tally), and the one thing no
/// Uniswap UI volunteers without you going and looking for it.
///
/// FLAT BY LAW like its neighbor — a plain VStack, no generic `Widget`/`Row`
/// mount (the render-depth lesson).
struct WalletLiquidityCard: View {
    let book: UniswapLiquidity.Book

    var body: some View {
        if !book.positions.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                WalletSectionLabel(title: String(localized: "Liquidity"))
                // `Position` is a plain value type (never a `Thing`), keyed
                // on its own on-chain identity. The key spans VERSION and
                // network too: V3 and V4 mint tokenIds from separate
                // counters, so #8472 exists in both and a bare tokenId key
                // would collide (the reused-id ForEach trap).
                ForEach(sorted, id: \.key) { position in
                    positionRow(position)
                }
            }
            .padding(DS.Space.s4)
            .dsWidgetSurface(fillOpacity: WalletCardStyle.fill)
        }
    }

    /// Out-of-range first (the rows that need attention lead), then by size —
    /// the same "worst first" instinct the Lending card's health factor has.
    private var sorted: [UniswapLiquidity.Position] {
        book.positions.sorted {
            if $0.inRange != $1.inRange { return !$0.inRange }
            return ($0.valueUSD ?? 0) > ($1.valueUSD ?? 0)
        }
    }

    @ViewBuilder
    private func positionRow(_ position: UniswapLiquidity.Position) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            WalletRow(mark: .monogram("UN", tint: position.inRange ? DS.tint : DS.attention),
                     title: "\(position.token0Symbol)/\(position.token1Symbol)",
                     subtitle: Self.line(position)) {
                // The money leads on the trailing edge (the Lending card's
                // own ranking), with fees as its caption when there are any —
                // "what's it worth" beats "what fee tier is it" every time,
                // and the fee tier already rides the subline.
                if let value = position.valueUSD, value > 0 {
                    WalletRowValue(value: TokenStats.compact(value),
                                   caption: Self.feesCaption(position))
                } else if let fees = position.uncollectedFeeUSD, fees > 0.01 {
                    WalletRowValue(value: TokenStats.compact(fees), caption: String(localized: "fees"))
                } else {
                    WalletRowValue(value: Self.feeTierLabel(position.feeTier), caption: nil)
                }
            }
            UniswapRangeBar(tickLower: position.tickLower, tickUpper: position.tickUpper,
                            currentTick: position.currentTick, inRange: position.inRange)
                .padding(.leading, 42)   // aligns under the row's title, past the 34pt mark
        }
    }

    /// "In range · 0.30% · Base · v4" — status, the fee tier it earns at,
    /// where it lives, and only then the protocol version, the
    /// `WalletLendingCard.line` shape. The version rides LAST and quietly
    /// because it's the least interesting thing about a position (user
    /// ruling 2026-07-30: merge the rows) — but it isn't dropped, since two
    /// positions on the same pair in different versions are genuinely
    /// different positions.
    private static func line(_ position: UniswapLiquidity.Position) -> String {
        var parts: [String] = []
        if position.inRange {
            parts.append(String(localized: "In range"))
        } else {
            let since = UniswapLiquidity.timeOutOfRange(address: position.address,
                                                         network: position.network,
                                                         version: position.version,
                                                         tokenId: position.tokenId)
            parts.append(since ?? String(localized: "Out of range"))
        }
        // A V4 dynamic-fee pool carries a flag, not a rate — printing 838.86%
        // would be a fake number, so it says nothing instead.
        if position.feeTier != Self.dynamicFeeFlag {
            parts.append(feeTierLabel(position.feeTier))
        }
        if let chain = WalletIngest.displayName(forNetwork: position.network) {
            parts.append(chain)
        }
        parts.append("v\(position.version)")
        return parts.joined(separator: " · ")
    }

    /// V4's `0x800000` sentinel in the fee field — "this pool's hook sets the
    /// fee per swap", not a rate of 838.86%.
    private static let dynamicFeeFlag = 0x800000

    /// "$47 in fees" as the value's caption — nil when there's nothing
    /// uncollected, so a fresh position doesn't wear a "$0 fees" label.
    private static func feesCaption(_ position: UniswapLiquidity.Position) -> String? {
        guard let fees = position.uncollectedFeeUSD, fees > 0.01 else { return nil }
        return String(localized: "\(TokenStats.compact(fees)) fees")
    }

    private static func feeTierLabel(_ hundredthsOfBip: Int) -> String {
        String(format: "%.2f%%", Double(hundredthsOfBip) / 10_000)
    }
}

/// A self-scaling range bar — `[lower ——●—— upper]`. The display domain
/// always stretches to cover BOTH the position's range and the current
/// price, whichever is wider, so a position drifted far out of range still
/// shows a meaningful (not vanishingly thin) range segment, the way a
/// sparkline autoscales rather than plotting against a fixed axis.
struct UniswapRangeBar: View {
    let tickLower: Int
    let tickUpper: Int
    let currentTick: Int
    let inRange: Bool

    private var domain: (low: Double, high: Double) {
        let low = Double(min(tickLower, currentTick))
        let high = Double(max(tickUpper, currentTick))
        let span = max(high - low, 1)
        let pad = span / 8
        return (low - pad, high + pad)
    }

    private func fraction(_ tick: Int) -> CGFloat {
        let (low, high) = domain
        let span = max(high - low, 1)
        return CGFloat(min(max((Double(tick) - low) / span, 0), 1))
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let lowX = fraction(tickLower) * width
            let highX = fraction(tickUpper) * width
            let markX = fraction(currentTick) * width
            let tint = inRange ? DS.tint : DS.attention
            ZStack(alignment: .leading) {
                Capsule().fill(DS.textTertiary.opacity(0.18))
                    .frame(height: 4)
                Capsule().fill(tint.opacity(0.35))
                    .frame(width: max(highX - lowX, 3), height: 4)
                    .offset(x: lowX)
                Circle().fill(tint)
                    .frame(width: 8, height: 8)
                    .offset(x: min(max(markX - 4, 0), width - 8))
            }
            .frame(height: 8, alignment: .leading)
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}
