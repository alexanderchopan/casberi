import SwiftUI

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
                               accent: TokenChartStyle.accent(up: change >= 0, scheme: scheme),
                               height: 150, pulses: false)
                TokenDeltaPill(change: change,
                               label: "since \(combined.first!.at.formatted(.dateTime.month(.abbreviated).day()))")
            } else {
                Text("A combined line begins once every wallet has a sample — sampled as you use Casberi, never back-filled.")
                    .dsText(.callout15).foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
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
