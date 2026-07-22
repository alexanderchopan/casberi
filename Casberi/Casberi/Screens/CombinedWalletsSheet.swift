import SwiftUI
import Charts

/// The "Across your wallets" full read (2026-07-15) — the combined section's
/// headline opens into this. The Casberi frame, not Zapper's: one number
/// decomposed into your history, never a single terminal figure. The hero is
/// the combined net-worth line (state-colored, up/down); beneath it each
/// wallet's own line draws in its face's color, so a move you see up top can be
/// read back to the wallet that drove it. Read on this iPhone, watch-only —
/// the footer says so (prd §77).
struct CombinedWalletsSheet: View {
    let total: Double
    let combined: [WalletStore.ValueSample]
    let wallets: [WalletStore.WatchedAddress]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    /// Per-wallet lines with ≥2 points, each paired with its face tint.
    private struct Line: Identifiable {
        let id: WalletStore.WatchedAddress.ID
        let address: String
        let label: String
        let closes: [Double]
        let since: Date
        let tint: Color
    }

    /// The combined move attributed by token — top 3 symbols by USD swing over
    /// the sampled window (2026-07-15). Empty until enough per-token snapshots
    /// exist (forward-only, like the line).
    private var movers: [(symbol: String, delta: Double)] {
        Array(WalletStore.shared.combinedHoldingsDeltas().prefix(3))
    }

    private var perWallet: [Line] {
        wallets.compactMap { addr in
            let samples = WalletStore.shared.valueSamples(forAddress: addr.address)
            guard samples.count >= 2, let first = samples.first else { return nil }
            return Line(id: addr.id, address: addr.address,
                        label: addr.label.isEmpty ? addr.short : addr.label,
                        closes: samples.map(\.usd), since: first.at,
                        tint: WalletFace.tint(for: addr.address))
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s6) {
                    combinedHeader
                    if !movers.isEmpty {
                        VStack(alignment: .leading, spacing: DS.Space.s3) {
                            Text("What moved").dsText(.label12)
                                .foregroundStyle(DS.textSecondary)
                            ForEach(movers, id: \.symbol) { m in
                                HStack {
                                    Text(m.symbol).dsText(.body17)
                                        .foregroundStyle(DS.textPrimary)
                                    Spacer()
                                    Text(signed(m.delta)).dsText(.body17).monospacedDigit()
                                        .foregroundStyle(m.delta >= 0 ? DS.confirm : DS.attention)
                                }
                                .dsListCardRow()
                            }
                        }
                    }
                    if !perWallet.isEmpty {
                        VStack(alignment: .leading, spacing: DS.Space.s3) {
                            Text("Each wallet").dsText(.label12)
                                .foregroundStyle(DS.textSecondary)
                            ForEach(perWallet) { line in
                                walletRow(line)
                            }
                        }
                    }
                    Text("Everything you watch, together — read on this iPhone, no account, watch-only. Only these wallets' onchain value, never a claim about your whole net worth.")
                        .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(DS.Space.s4)
            }
            .dsAdaptiveContentWidth()
            .dsPageBackground()
            .navigationTitle("Across your wallets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.tint(DS.tint)
                }
            }
        }
    }

    /// "+$310" / "−$4" — signed compact USD for a token's move.
    private func signed(_ v: Double) -> String {
        "\(v >= 0 ? "+" : "−")\(TokenStats.compact(abs(v)))"
    }

    // MARK: - Combined hero

    private var combinedHeader: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Combined value")
                    .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                Text(TokenStats.compact(total))
                    .dsText(.heading34).foregroundStyle(DS.textPrimary)
                    .monospacedDigit()
            }
            if combined.count >= 2 {
                let closes = combined.map(\.usd)
                let first = closes.first ?? 0
                let last = closes.last ?? 0
                let change = first > 0 ? (last - first) / first : 0
                TokenChartPlot(chart: TokenChart(closes: closes, price: last, change: change),
                               accent: TokenChartStyle.accent(change: change, scheme: scheme),
                               height: 150, pulses: false)
                TokenDeltaPill(change: change,
                               label: "since \(combined.first!.at.formatted(.dateTime.month(.abbreviated).day()))")
                madeOfSection(momentCount: closes.count)
            } else {
                Text("A combined line begins once every wallet has a sample — sampled as you use Casberi, never back-filled.")
                    .dsText(.callout15).foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Made of (2026-07-21, prd §155)

    /// The combined value drawn as the SUM OF ITS PARTS — one stacked band per
    /// wallet, each in its own face tint, so "the whole is these parts" is the
    /// shape of the drawing rather than an addition the reader does in their
    /// head against the small per-wallet lines below.
    ///
    /// Deliberately NOT the hero (tried as the hero first, 2026-07-21, and
    /// reverted on the screenshot): a stack has to be zero-based to stack
    /// honestly, and at real portfolio ratios — one wallet holding almost
    /// everything — that paints a full-height slab of one color in which a 3%
    /// move is invisible. The line above keeps the movement read (its own
    /// non-zero scale); this strip keeps the composition read. Two questions,
    /// two pictures, neither lying to flatter the other.
    ///
    /// Every band is forward-filled on the SAME moments the combined line uses
    /// (`WalletStore.combinedBands`), so at every x the bands sum to exactly the
    /// number in the header. Below two wallets with aligned history there's no
    /// composition to show, and nothing renders.
    @ViewBuilder
    private func madeOfSection(momentCount: Int) -> some View {
        let (moments, bands) = WalletStore.shared.combinedBands()
        if bands.count > 1, moments.count == momentCount {
            let latest = bands.map { $0.closes.last ?? 0 }
            let total = latest.reduce(0, +)
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                Text("Made of").dsText(.label12).foregroundStyle(DS.textSecondary)
                Chart {
                    ForEach(bands) { band in
                        ForEach(Array(band.closes.enumerated()), id: \.offset) { i, usd in
                            AreaMark(x: .value("t", Double(i)), y: .value("usd", usd),
                                     stacking: .standard)
                                .foregroundStyle(by: .value("Wallet", band.label))
                                .interpolationMethod(.catmullRom)
                        }
                    }
                }
                .chartForegroundStyleScale(domain: bands.map(\.label),
                                           range: bands.map {
                                               WalletFace.tint(for: $0.address).opacity(0.55)
                                           })
                // The legend below names the colors with their shares — the
                // chart's own legend would say less, in more space.
                .chartLegend(.hidden)
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 74)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                HStack(spacing: DS.Space.s4) {
                    ForEach(Array(zip(bands, latest)), id: \.0.id) { band, usd in
                        HStack(spacing: 5) {
                            Circle()
                                .fill(WalletFace.tint(for: band.address))
                                .frame(width: 7, height: 7)
                            Text(band.label)
                                .dsText(.label12).foregroundStyle(DS.textSecondary)
                                .lineLimit(1)
                            if total > 0 {
                                Text(share(usd / total))
                                    .dsText(.label12).foregroundStyle(DS.textTertiary)
                                    .monospacedDigit()
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    /// A share, honest at BOTH ends: a wallet holding a thousandth of the
    /// portfolio reads "<1%", never a rounded-away "0%" that denies it's there —
    /// and the wallet holding the rest reads ">99%", never a rounded-up "100%",
    /// which beside a "<1%" sibling would have the shares summing past the whole
    /// (caught on screen 2026-07-21). Only a true 100% — one wallet holding
    /// everything — says 100%.
    private func share(_ fraction: Double) -> String {
        let pct = fraction * 100
        if pct > 0, pct < 1 { return "<1%" }
        if pct < 100, pct.rounded() >= 100 { return ">99%" }
        return "\(Int(pct.rounded()))%"
    }

    // MARK: - Per-wallet line

    private func walletRow(_ line: Line) -> some View {
        let first = line.closes.first ?? 0
        let last = line.closes.last ?? 0
        let change = first > 0 ? (last - first) / first : 0
        return HStack(spacing: DS.Space.s3) {
            WalletFace(address: line.address, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(line.label).dsText(.body17).foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                Text(TokenStats.compact(last))
                    .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                    .monospacedDigit()
            }
            Spacer()
            // The wallet's own line in its face's color — identity carried from
            // the treemap and rows into the decomposition.
            TokenChartPlot(chart: TokenChart(closes: line.closes, price: last, change: change),
                           accent: line.tint, height: 30, pulses: false)
                .frame(width: 80)
                .accessibilityHidden(true)
            TokenDeltaPill(change: change,
                           label: "since \(line.since.formatted(.dateTime.month(.abbreviated).day()))",
                           compact: true)
        }
        .dsListCardRow()
    }
}
