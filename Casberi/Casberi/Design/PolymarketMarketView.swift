import SwiftUI

/// A watched Polymarket market's sheet read (2026-07-28) — the Kalshi sibling
/// (live headline number, honest about live vs closed), but with the real
/// scrubbable curve `KalshiMarketView` deliberately can't draw: Polymarket's
/// CLOB serves genuine price history, so this reuses `TokenChartPlot` (the
/// same plot the token/stock charts draw) rather than inventing a second
/// chart renderer. History still degrades honestly — a market too new or too
/// thin to have a real curve just shows the headline number alone, no chart
/// (prd 51: a fallback stops pretending rather than faking a line).
struct PolymarketMarketView<Fallback: View>: View {
    let conditionId: String
    @ViewBuilder let fallback: () -> Fallback

    private enum Phase { case loading, ready, dead }
    @State private var market: PolymarketBridge.Resolved?
    @State private var history: [Double] = []
    @State private var phase: Phase = .loading
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var change: Double {
        guard let first = history.first, first > 0, history.count >= 2 else { return 0 }
        return (history[history.count - 1] - first) / first
    }
    private var accent: Color { TokenChartStyle.accent(change: change, scheme: scheme) }

    var body: some View {
        Group {
            switch phase {
            case .loading:
                TokenChartSkeleton(plotHeight: 0)
            case .dead:
                fallback()
            case .ready:
                if let market { loaded(market) } else { TokenChartSkeleton(plotHeight: 0) }
            }
        }
        .task { await load() }
    }

    private func loaded(_ market: PolymarketBridge.Resolved) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            HStack(spacing: DS.Space.s2) {
                Text("\(Int((market.probability * 100).rounded()))%")
                    .dsText(.heading22).foregroundStyle(DS.textPrimary)
                    .monospacedDigit()
                if !market.closed {
                    if history.count >= 2 {
                        TokenDeltaPill(change: change, label: "this week")
                    }
                } else {
                    Text(market.yesWon == true ? "Yes" : market.yesWon == false ? "No" : "Closed")
                        .dsText(.label12).foregroundStyle(DS.textTertiary)
                }
                Spacer(minLength: DS.Space.s2)
            }
            if !market.subtitle.isEmpty {
                Text("Odds \(market.subtitle) wins")
                    .dsText(.callout15).foregroundStyle(DS.textSecondary)
            }
            if history.count >= 2 {
                TokenChartPlot(chart: TokenChart(closes: history, price: market.probability, change: change),
                              accent: accent, height: 100, pulses: !market.closed)
                    // The line draws itself (2026-08-04, prd §298). The plot
                    // never wipes itself — the reveal always lives in the
                    // caller, and this was the one caller that never added it,
                    // so a market's week arrived already drawn.
                    .chartWipe(reduceMotion: reduceMotion)
            }
            if let closeTime = market.closeTime {
                Text(!market.closed
                     ? "Closes \(closeTime.formatted(.relative(presentation: .named)))"
                     : "Public odds — not a bet placed here.")
                    .dsText(.subhead13).foregroundStyle(DS.textTertiary)
            }
        }
    }

    private func load() async {
        guard let fetched = await PolymarketBridge.fetchMarket(conditionId: conditionId) else {
            phase = .dead
            return
        }
        market = fetched
        phase = .ready
        if let tokenId = fetched.yesTokenId {
            history = await PolymarketBridge.priceHistory(yesTokenId: tokenId)
        }
    }
}
