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
            // Tightened 2026-08-01 (user: "it's pretty large right now"):
            // s3 → s2 between rows and s4 → s3 around the card. Each position
            // already carries two lines plus a range bar, so the air between
            // them was doing the work of a separator nothing here needs.
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                WalletSectionLabel(title: String(localized: "Liquidity"))
                // THE READING (2026-08-20, prd §417). This card jumped from an
                // 11pt label straight to rows, so "is it working" — the
                // question its own doc says it exists to answer — had to be
                // derived by reading every pill. Lending and Approvals have led
                // with a spoken `heading22` since they shipped; this is that
                // anatomy finished. The rows are unchanged: the reading says
                // the verdict, the pills say which position.
                Text(reading.text)
                    .dsText(.heading22)
                    .foregroundStyle(reading.idle ? DS.attention : DS.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                // `Position` is a plain value type (never a `Thing`), keyed
                // on its own on-chain identity. The key spans VERSION and
                // network too: V3 and V4 mint tokenIds from separate
                // counters, so #8472 exists in both and a bare tokenId key
                // would collide (the reused-id ForEach trap).
                ForEach(sorted, id: \.key) { position in
                    positionRow(position)
                }
            }
            .padding(DS.Space.s3)
            .dsWidgetSurface(fillOpacity: WalletCardStyle.fill)
        }
    }

    /// The card's spoken verdict (prd §417) — idle first, because an idle
    /// position is the only thing here anyone can act on.
    ///
    /// **Never sums fees across positions**: two positions can earn in
    /// different tokens, and a combined "+$59" would be adding what the rows
    /// deliberately keep apart. So the reading counts POSITIONS, which is a
    /// unit that always converts, and leaves the money to the pills.
    private var reading: (text: String, idle: Bool) {
        let total = book.positions.count
        let idle = book.positions.filter { !$0.inRange }.count
        switch idle {
        case 0:
            return (total == 1
                    ? String(localized: "Your position is earning")
                    : String(localized: "All \(total) positions are earning"), false)
        case total:
            return (total == 1
                    ? String(localized: "Your position is idle")
                    : String(localized: "All \(total) positions are idle"), true)
        default:
            return (String(localized: "\(idle) of \(total) positions idle"), true)
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
    @ViewBuilder
    private func positionRow(_ position: UniswapLiquidity.Position) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            WalletRow(mark: .pair(position.token0Symbol, position.token1Symbol),
                     title: "\(position.token0Symbol)/\(position.token1Symbol)",
                     subtitle: Self.line(position)) {
                VStack(alignment: .trailing, spacing: 3) {
                    if let value = position.valueUSD, value > 0 {
                        Text(WalletValue.money(value))
                            .dsText(.price16).foregroundStyle(DS.textPrimary)
                            .monospacedDigit().lineLimit(1)
                    }
                    outcomePill(position)
                }
            }
            if !position.inRange {
                UniswapRangeBar(tickLower: position.tickLower, tickUpper: position.tickUpper,
                                currentTick: position.currentTick, inRange: position.inRange)
                    .padding(.leading, 42)   // aligns under the title, past the 34pt mark
            }
        }
    }

    /// "Earning +$59" / "In range" / "Idle 3d" — what the position is DOING,
    /// in one word plus its number.
    ///
    /// A position in range with no fees yet says "In range" quietly rather
    /// than "Earning +$0": zero earned is not a green moment, and claiming one
    /// would be the fake-status rule in miniature.
    @ViewBuilder
    private func outcomePill(_ position: UniswapLiquidity.Position) -> some View {
        if position.inRange, let fees = position.uncollectedFeeUSD, fees > 0.01 {
            pill(String(localized: "Earning +\(WalletValue.money(fees))"), tone: DS.confirm)
        } else if position.inRange {
            pill(String(localized: "In range"), tone: DS.textSecondary)
        } else if let days = UniswapLiquidity.daysOutOfRange(
                    address: position.address, network: position.network,
                    version: position.version, tokenId: position.tokenId) {
            pill(String(localized: "Idle \(days)d"), tone: DS.attention)
        } else {
            pill(String(localized: "Idle"), tone: DS.attention)
        }
    }

    private func pill(_ text: String, tone: Color) -> some View {
        Text(text)
            .dsText(.label12).fontWeight(.bold)
            .foregroundStyle(tone)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tone.opacity(0.16), in: Capsule())
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
        // The STATUS moved to the outcome pill (2026-08-01) and is deliberately
        // not repeated here — it led this line for a year, and saying "In
        // range" twice on one row is the thing the pill was introduced to stop.
        // What's left is pure mechanism: the rate it earns at, where it lives,
        // which version.
        //
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
        return String(localized: "\(WalletValue.money(fees)) fees")
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
///
/// **It draws itself** (2026-08-03, prd §297): the range segment expands from
/// its own centre, then the price dot lands on the tick it's actually at. The
/// order is the reading's own logic — the range is the thing you chose, the
/// price is the thing that happened to it — and it's why the dot doesn't slide
/// along the bar: sliding would imply a path the price took, which this bar has
/// no data for. It lands where it is and nowhere else.
struct UniswapRangeBar: View {
    let tickLower: Int
    let tickUpper: Int
    let currentTick: Int
    let inRange: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var opened = false
    @State private var dotLanded = false

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
                    // Opens from its own middle — the range grew outward from
                    // the price it was set around.
                    .scaleEffect(x: opened ? 1 : 0, anchor: .center)
                Circle().fill(tint)
                    .frame(width: 8, height: 8)
                    .offset(x: min(max(markX - 4, 0), width - 8))
                    .scaleEffect(dotLanded ? 1 : 0)
            }
            .frame(height: 8, alignment: .leading)
        }
        .frame(height: 8)
        .accessibilityHidden(true)
        .onAppear(perform: enter)
    }

    private func enter() {
        guard !opened else { return }
        guard !reduceMotion else { opened = true; dotLanded = true; return }
        withAnimation(.easeOut(duration: 0.45).delay(ChartEntrance.lead)) { opened = true }
        withAnimation(ChartEntrance.land(after: ChartEntrance.lead + 0.35)) { dotLanded = true }
    }
}
