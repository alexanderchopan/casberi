import SwiftUI

/// Uniswap V3 liquidity — the wallet room's third live-state card (2026-07-30),
/// beside `WalletLendingCard`. A SIBLING card, not a third row folded into
/// Lending's own: prd §212's reasoning ("Aave and Morpho were never two
/// subjects, they're two providers of one") cuts the other way here — lending
/// asks "is it safe" (collateral/debt/health factor), a Uniswap position asks
/// "is it working" (in range and earning, or silently idle). Different
/// subjects earn different cards; the same subject wearing two providers
/// doesn't.
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
                // on its own `tokenId` — real, stable on-chain identity, not
                // an array offset.
                ForEach(book.positions, id: \.tokenId) { position in
                    positionRow(position)
                }
            }
            .padding(DS.Space.s4)
            .dsWidgetSurface(fillOpacity: WalletCardStyle.fill)
        }
    }

    @ViewBuilder
    private func positionRow(_ position: UniswapLiquidity.Position) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            WalletRow(mark: .monogram("UN", tint: position.inRange ? DS.tint : DS.attention),
                     title: "\(position.token0Symbol)/\(position.token1Symbol)",
                     subtitle: Self.line(position)) {
                if let fees = position.uncollectedFeeUSD, fees > 0.01 {
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

    /// "In range · Base" / "Out of range for 6 days · Base" — status, then
    /// where it lives, then how long, the `WalletLendingCard.line` shape.
    private static func line(_ position: UniswapLiquidity.Position) -> String {
        var parts: [String] = []
        if position.inRange {
            parts.append(String(localized: "In range"))
        } else {
            let since = UniswapLiquidity.timeOutOfRange(address: position.address,
                                                         network: position.network,
                                                         tokenId: position.tokenId)
            parts.append(since ?? String(localized: "Out of range"))
        }
        if let chain = WalletIngest.displayName(forNetwork: position.network) {
            parts.append(chain)
        }
        return parts.joined(separator: " · ")
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
