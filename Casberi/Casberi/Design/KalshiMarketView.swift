import SwiftUI

/// A watched Kalshi market's sheet read (2026-07-11) — the probability-market
/// sibling of TokenChartView, in the same doses (a live headline number, a
/// delta pill, honest about what's live vs settled) but without a scrub
/// chart: Kalshi's public candlestick data is too thin for most game
/// markets to draw a real curve, and prd 51's rule stands — a fallback
/// stops pretending. The settled case (a game that's finished) says so
/// instead of showing a stale live probability.
struct KalshiMarketView<Fallback: View>: View {
    let series: String
    let event: String
    @ViewBuilder let fallback: () -> Fallback

    private enum Phase { case loading, ready, dead }
    @State private var market: KalshiMarket?
    @State private var phase: Phase = .loading
    @Environment(\.colorScheme) private var scheme

    private var delta: Double {
        guard let market, let previous = market.previousProbability else { return 0 }
        return market.probability - previous
    }
    private var accent: Color { TokenChartStyle.accent(change: delta, scheme: scheme) }

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

    private func loaded(_ market: KalshiMarket) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            HStack(spacing: DS.Space.s2) {
                Text("\(Int((market.probability * 100).rounded()))%")
                    .dsText(.heading22).foregroundStyle(DS.textPrimary)
                    .monospacedDigit()
                if market.status == "active" {
                    TokenDeltaPill(change: delta, label: "vs last")
                } else {
                    Text(market.status.capitalized)
                        .dsText(.label12).foregroundStyle(DS.textTertiary)
                }
                Spacer(minLength: DS.Space.s2)
            }
            if !market.subtitle.isEmpty {
                Text("Odds \(market.subtitle) wins")
                    .dsText(.callout15).foregroundStyle(DS.textSecondary)
            }
            if let closeTime = market.closeTime {
                Text(market.status == "active"
                     ? "Closes \(closeTime.formatted(.relative(presentation: .named)))"
                     : "A Kalshi prediction market — public odds, not a bet placed here.")
                    .dsText(.subhead13).foregroundStyle(DS.textTertiary)
            }
        }
    }

    private func load() async {
        guard let fetched = await KalshiMarket.fetch(series: series, event: event) else {
            phase = .dead
            return
        }
        market = fetched
        phase = .ready
    }
}
