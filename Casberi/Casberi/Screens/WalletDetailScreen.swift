import SwiftUI
import SwiftData

/// One watched wallet's own screen — its CONNECTION, not its contents
/// (2026-07-20, second pass; user: "the manage screen should only be about
/// connecting wallets and disconnecting them"). The first pass moved the
/// per-wallet reads here from `WalletScreen`'s top level; this pass moves the
/// reads out of the manage stack entirely — the holdings treemap, the value
/// sparkline, and the gas line all belonged to the feed's tiles and treemap,
/// and showing them here made two of everything. What's left is what only
/// this screen can do: rename, the safety facts (approvals door, delegation,
/// Safe queue — the rows the Worth-a-look tray's doors land on), and remove.
/// Self-sufficient — does its own fetch on appear rather than threading state
/// down, the same shape `ThingSheetView`'s prepare/queue cards follow.
struct WalletDetailScreen: View {
    @Bindable private var wallet = WalletStore.shared
    let addressID: WalletStore.WatchedAddress.ID
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @State private var renameDraft = ""
    @State private var renaming = false
    @State private var pendingCount: Int?
    @State private var delegation: WalletSafety.Delegation?

    private var addr: WalletStore.WatchedAddress? {
        wallet.addresses.first { $0.id == addressID }
    }

    var body: some View {
        List {
            if let addr {
                headerSection(addr)
                safetySection(addr)
                removeSection(addr)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftTopEdge()
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
            async let safe = SafeBridge.pendingCounts(addresses: resolved)
            async let currentDelegs = WalletSafety.currentDelegations(addresses: resolved)
            pendingCount = (await safe)[addr.address.lowercased()]
            delegation = (await currentDelegs).first
        }
    }

    private func saveRename() {
        guard let addr else { return }
        wallet.rename(addr.id, to: renameDraft)
        DSHaptic.success()
    }

    // MARK: - Header (identity + rename — the reads live on the feed)

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
                        // The address, always — identity, not a read. The
                        // value/gas subline and the sparkline moved to the
                        // feed's Balance tile with the rest of the reads.
                        if !addr.label.isEmpty {
                            Text(addr.short).dsText(.subhead13)
                                .foregroundStyle(DS.textSecondary)
                                .monospacedDigit()
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .dsListCardRow()
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
