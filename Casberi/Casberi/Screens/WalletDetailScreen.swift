import SwiftUI
import SwiftData

/// One watched wallet's own screen (2026-07-20) — the collapse: approvals,
/// gas, Aave, and Safe used to each earn a top-level `Section` on
/// `WalletScreen`, repeating every watched wallet's face+label once per
/// feature. Here they're scoped to the ONE wallet this screen is about,
/// reached by tapping its row in Watching. Self-sufficient — does its own
/// fetch on appear rather than threading state down from `WalletScreen`,
/// the same shape `ThingSheetView`'s prepare/queue cards already follow.
struct WalletDetailScreen: View {
    @Bindable private var wallet = WalletStore.shared
    let addressID: WalletStore.WatchedAddress.ID
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @State private var renameDraft = ""
    @State private var renaming = false
    @State private var holdings: WalletIngest.HoldingsGroup?
    @State private var gasUSD: Double?
    @State private var positions: [WalletDeFi.Position] = []
    @State private var pendingCount: Int?
    @State private var delegation: WalletSafety.Delegation?

    private var addr: WalletStore.WatchedAddress? {
        wallet.addresses.first { $0.id == addressID }
    }

    var body: some View {
        List {
            if let addr {
                headerSection(addr)
                if let holdings { holdingsMap(holdings) }
                if !positions.isEmpty { defiSection }
                safetySection(addr)
                removeSection(addr)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .navigationTitle(addr.map { $0.label.isEmpty ? $0.short : $0.label } ?? "Wallet")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { load() }
        .alert("Name this wallet",
               isPresented: $renaming) {
            TextField("Name (e.g. Main, Cold)", text: $renameDraft)
            Button("Save") { saveRename() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A blank name shows the address instead.")
        }
    }

    private func load() {
        guard let addr else { return }
        Task {
            // `resolved` may come back empty (a Solana-only watch, say) —
            // every read below already guards an empty address list on its
            // own (returns [] / nil rather than mis-firing), so no extra
            // branching is needed here.
            let resolved = await WalletIngest.resolvedAddresses([addr.address])
                .filter { ENS.isHexAddress($0) }
            async let totals = WalletIngest.topHoldingsByWallet()
            async let gas = WalletGas.totalUSD(address: addr.address)
            async let defi = WalletDeFi.positions(addresses: resolved)
            async let safe = SafeBridge.pendingCounts(addresses: resolved)
            async let currentDelegs = WalletSafety.currentDelegations(addresses: resolved)
            holdings = await totals.first { $0.address?.lowercased() == addr.address.lowercased() }
            gasUSD = await gas
            positions = await defi
            pendingCount = (await safe)[addr.address.lowercased()]
            delegation = (await currentDelegs).first
        }
    }

    private func saveRename() {
        guard let addr else { return }
        wallet.rename(addr.id, to: renameDraft)
        DSHaptic.success()
    }

    // MARK: - Header

    private func rowSamples(_ addr: WalletStore.WatchedAddress) -> [WalletStore.ValueSample]? {
        let s = wallet.valueSamples(forAddress: addr.address)
        guard s.count >= 2 else { return nil }
        return s
    }

    /// Value + gas in one line — the fact no explorer states this way (they
    /// show a single tx's fee, never a running sum), honestly scoped ("since
    /// you started watching", never a fabricated lifetime figure).
    private func subline(_ addr: WalletStore.WatchedAddress) -> String? {
        var parts: [String] = []
        if let holdings {
            parts.append(holdings.tokenCount == 1
                ? "\(TokenStats.compact(holdings.totalUSD)) across 1 token"
                : "\(TokenStats.compact(holdings.totalUSD)) across \(holdings.tokenCount) tokens")
        } else if !addr.label.isEmpty {
            parts.append(addr.short)
        }
        if let gasUSD { parts.append("\(TokenStats.compact(gasUSD)) gas") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func headerSection(_ addr: WalletStore.WatchedAddress) -> some View {
        Section {
            HStack(spacing: DS.Space.s3) {
                WalletFace(address: addr.address, size: 36)
                Button {
                    DSHaptic.tap()
                    renameDraft = addr.label
                    renaming = true
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(addr.label.isEmpty ? addr.short : addr.label)
                            .dsText(.body17).foregroundStyle(DS.textPrimary)
                            .lineLimit(1)
                        if let subline = subline(addr) {
                            Text(subline).dsText(.subhead13).foregroundStyle(DS.textSecondary)
                                .monospacedDigit()
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
                if let samples = rowSamples(addr) {
                    let closes = samples.map(\.usd)
                    let first = closes.first ?? 0
                    let last = closes.last ?? 0
                    let change = first > 0 ? (last - first) / first : 0
                    VStack(alignment: .trailing, spacing: 4) {
                        TokenChartPlot(chart: TokenChart(closes: closes, price: last, change: change),
                                       accent: TokenChartStyle.accent(change: change, scheme: scheme),
                                       height: 22, pulses: false)
                            .frame(width: 40)
                            .accessibilityHidden(true)
                        TokenDeltaPill(change: change,
                                       label: samples.first!.at.formatted(.dateTime.month(.abbreviated).day()),
                                       compact: true)
                    }
                }
            }
            .dsListCardRow()
        }
    }

    // MARK: - Holdings treemap (this wallet only)

    private func holdingsMap(_ group: WalletIngest.HoldingsGroup) -> some View {
        let doc = WalletIngest.groupDocument(group).joined(separator: "\n")
        return GenRender(id: "root", els: GenParser.parse(prefix: doc[...], isComplete: true))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets())
    }

    // MARK: - DeFi (this wallet only)

    private var defiSection: some View {
        Section {
            ForEach(Array(positions.enumerated()), id: \.offset) { _, p in
                HStack(spacing: DS.Space.s3) {
                    Text(WalletIngest.displayName(forNetwork: p.network) ?? p.network)
                        .dsText(.body17).foregroundStyle(DS.textPrimary)
                    Spacer()
                    if let hf = p.healthFactor {
                        Text(String(format: "%.2f", hf))
                            .dsText(.body17)
                            .foregroundStyle(hf < 1.5 ? DS.destructive : DS.textPrimary)
                            .monospacedDigit()
                    }
                }
                .dsListCardRow()
            }
        } header: {
            Text("DeFi positions").dsText(.label12)
                .foregroundStyle(DS.textSecondary)
        } footer: {
            Text("Aave collateral, debt, and health factor — read live from the chain. Below 1.5 is worth watching; below 1.0 risks liquidation.")
                .dsText(.callout15).foregroundStyle(DS.textSecondary)
        }
    }

    // MARK: - Safety (approvals + delegation + Safe queue, this wallet only)

    private func safetySection(_ addr: WalletStore.WatchedAddress) -> some View {
        Section {
            if WalletApprovals.canServe(addr.address) {
                Button {
                    DSHaptic.selection()
                    if let url = URL(string: WalletApprovals.revokeURL(address: addr.address)) {
                        openURL(url)
                    }
                } label: {
                    HStack(spacing: DS.Space.s3) {
                        Text("Approvals").dsText(.body17).foregroundStyle(DS.textPrimary)
                        Spacer()
                        Text("Revoke.cash").dsText(.subhead13).foregroundStyle(DS.textSecondary)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(DS.textTertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .dsListCardRow()
            }
            if let delegation {
                HStack(spacing: DS.Space.s3) {
                    Text("Delegates on \(WalletIngest.displayName(forNetwork: delegation.network) ?? delegation.network)")
                        .dsText(.body17).foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    Text(WalletIngest.knownLabel(for: delegation.delegate) ?? WalletStore.shortAddress(delegation.delegate))
                        .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                }
                .dsListCardRow()
            }
            if let pendingCount, pendingCount > 0 {
                HStack(spacing: DS.Space.s3) {
                    Text("Safe queue").dsText(.body17).foregroundStyle(DS.textPrimary)
                    Spacer()
                    Text(pendingCount == 1 ? "1 pending" : "\(pendingCount) pending")
                        .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                }
                .dsListCardRow()
            }
        } header: {
            Text("Safety").dsText(.label12)
                .foregroundStyle(DS.textSecondary)
        } footer: {
            Text("What this wallet has allowed contracts to spend, whether it delegates (EIP-7702), and any Safe signatures still needed. Revoking and signing both happen elsewhere — never in Casberi.")
                .dsText(.callout15).foregroundStyle(DS.textSecondary)
        }
    }

    // MARK: - Remove

    private func removeSection(_ addr: WalletStore.WatchedAddress) -> some View {
        Section {
            Button(role: .destructive) {
                if let i = wallet.addresses.firstIndex(where: { $0.id == addr.id }) {
                    wallet.remove(at: IndexSet(integer: i))
                }
                dismiss()
            } label: {
                Text("Stop watching this wallet")
                    .frame(maxWidth: .infinity)
            }
            .dsListCardRow()
        }
    }
}
