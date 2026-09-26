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
/// range would erase the one fact that matters. That fact leads the row's
/// line in words ("Out of range · 12 days") since prd §945, which deleted the
/// range bar drawn under an idle row.
///
/// FLAT BY LAW like its neighbor — a plain VStack, no generic `Widget`/`Row`
/// mount (the render-depth lesson).
struct WalletLiquidityCard: View {
    let book: UniswapLiquidity.Book

    var body: some View {
        if !book.positions.isEmpty {
            // The group's name is the room's `DSGroupHeader` (prd §945), and
            // the second headline ("1 of 2 positions idle") is each row's own
            // first word now.
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                ForEach(sorted, id: \.key) { position in
                    positionRow(position)
                }
            }
            .padding(.bottom, DS.Space.s4)
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

    /// One position (2026-08-01, the Cash App pass): the pair's real token
    /// marks, the pair, the mechanism demoted to a subline, and the OUTCOME as
    /// a pill on the trailing edge.
    ///
    /// The outcome pill is the whole ruling. "Is it working" is the question
    /// this card exists to answer, and a range bar makes the reader derive it
    /// from geometry — so the answer became a word: **Earning +$59** in the
    /// money green (the fees finally wear the colour of money arriving), or
    /// **Idle 3d** in attention.
    ///
    /// And the range bar now appears ONLY on an idle row, where it explains
    /// something the pill can't — your range gone cold with the price sitting
    /// outside it, which is *why* it's idle. On an earning row it's deleted:
    /// being in range is what "Earning" MEANS, and drawing it a second time is
    /// the tally instinct wearing geometry.
    /// **ONE ROW, THE WALLET LIST'S ANATOMY (prd §945).** The pair, one line
    /// — what the position is doing first ("Out of range · 12 days",
    /// "Earning $193", "In range"), then the fee tier and chain — and one
    /// figure. The range bar under an idle row and the stamp under the
    /// figure are gone: the line says it in words.
    private func positionRow(_ position: UniswapLiquidity.Position) -> some View {
        WalletRow(mark: .pair(position.token0Symbol, position.token1Symbol),
                  title: "\(position.token0Symbol)/\(position.token1Symbol)",
                  subtitle: Self.line(position)) {
            if let value = position.valueUSD, value > 0 {
                WalletRowValue(value: WalletValue.money(value))
            }
        }
    }

    private static func state(_ position: UniswapLiquidity.Position) -> String {
        if position.inRange {
            if let fees = position.uncollectedFeeUSD, fees > 0.01 {
                return String(localized: "Earning \(WalletValue.money(fees))")
            }
            return String(localized: "In range")
        }
        if let days = UniswapLiquidity.daysOutOfRange(
            address: position.address, network: position.network,
            version: position.version, tokenId: position.tokenId) {
            return days == 1 ? String(localized: "Out of range · 1 day")
                             : String(localized: "Out of range · \(days) days")
        }
        return String(localized: "Out of range")
    }

    private static func line(_ position: UniswapLiquidity.Position) -> String {
        var parts: [String] = [state(position)]
        if position.feeTier != Self.dynamicFeeFlag {
            parts.append(feeTierLabel(position.feeTier))
        }
        if let chain = WalletIngest.displayName(forNetwork: position.network) {
            parts.append(chain)
        }
        return parts.joined(separator: " · ")
    }

    /// V4's `0x800000` sentinel in the fee field — "this pool's hook sets the
    /// fee per swap", not a rate of 838.86%.
    private static let dynamicFeeFlag = 0x800000

    private static func feeTierLabel(_ hundredthsOfBip: Int) -> String {
        String(format: "%.2f%%", Double(hundredthsOfBip) / 10_000)
    }
}
