import SwiftUI
import SwiftData

/// The wallet's connection plumbing — chains and Disconnect (prd §182,
/// 2026-07-22). Pushed from the manager's one "Connection" row rather than
/// living inline, which is the amendment to §139's "manage is one page, no
/// doors": that ruling killed doors to READS — the per-wallet detail screen's
/// safety facts already lived better as Worth-a-look tray rows. This door
/// isn't a read. It's set-once configuration nobody wants staring at them
/// every time they open the wallet manager to watch a new address, and moving
/// it here is what let the manager stop looking like a settings page.
struct WalletConnectionScreen: View {
    @Bindable private var chainStore = WalletChainStore.shared
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDisconnect = false
    /// Re-syncs after a chain toggle — the manager screen's own `sync()` isn't
    /// reachable from here, and a toggle that visibly does nothing until the
    /// next foreground would read as broken.
    @State private var syncing = false

    var body: some View {
        List {
            Section {
                ForEach(WalletChainStore.selectable, id: \.id) { chain in
                    Button {
                        toggleChain(chain.id)
                    } label: {
                        HStack(spacing: DS.Space.s3) {
                            Text(chain.name)
                                .dsText(.body17).foregroundStyle(DS.textPrimary)
                            Spacer()
                            if chainStore.isSelected(chain.id) {
                                Image(systemName: "checkmark")
                                    .dsText(.body17).foregroundStyle(DS.tint)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .dsListCardRow()
                }
                // Bitcoin is watched and has been since 2026-07-27, and this
                // screen was the only place that could say so and didn't —
                // reported as "bitcoin doesn't show as an address for the
                // wallet to watch" (prd §512a). It is STATED, never a toggle:
                // `BitcoinBridge` rides neither Alchemy nor Zerion, so it has
                // no `WalletChainStore` id to switch, and it reads only when a
                // Bitcoin address is actually watched — a switch would govern
                // nothing for everyone who watches none, which is the dead
                // control §83 bans. Not a `Button`, so there is no tap to
                // disappoint; the trailing words carry the condition.
                HStack(spacing: DS.Space.s3) {
                    Text("Bitcoin")
                        .dsText(.body17).foregroundStyle(DS.textPrimary)
                    Spacer()
                    Text("When you watch one")
                        .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                }
                .dsListCardRow()
            } header: {
                Text("Chains").dsText(.label12).foregroundStyle(DS.textSecondary)
            } footer: {
                Text("A Bitcoin address is read too, from its own public API.")
                    .dsText(.callout15).foregroundStyle(DS.textSecondary)
            }
            Section {
                Button(role: .destructive) { confirmDisconnect = true } label: {
                    Text("Disconnect Wallet")
                        .dsText(.body17)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .dsListCardRow()
                .confirmationDialog("Disconnect Wallet?", isPresented: $confirmDisconnect,
                                    titleVisibility: .visible) {
                    Button("Keep its things") { disconnectWallet(purge: false) }
                    Button("Remove its things too", role: .destructive) { disconnectWallet(purge: true) }
                    Button("Cancel", role: .cancel) {}
                }
            } footer: {
                Text("Read-only — watching can never trade or move funds. Activity is public, read across chains directly on \(DS.device).")
                    .dsText(.subhead13).foregroundStyle(DS.textSecondary)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .navigationTitle("Connection")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func toggleChain(_ id: String) {
        DSHaptic.tap()
        chainStore.toggle(id)
        guard !syncing else { return }
        syncing = true
        Task {
            _ = await WalletIngest.refresh(context: modelContext)
            syncing = false
        }
    }

    private func disconnectWallet(purge: Bool) {
        if purge {
            let all = (try? modelContext.fetch(FetchDescriptor<Thing>())) ?? []
            let doomed = all.filter { $0.source == "Wallet" }
            SpotlightIndex.remove(ids: doomed.map(\.id))
            for thing in doomed { modelContext.delete(thing) }
            modelContext.saveHonestly()
        }
        WalletStore.shared.addresses = []
        store.remove("wallet")
        DSHaptic.tap()
        dismiss()
    }
}
