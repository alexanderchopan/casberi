import SwiftUI
import SwiftData

/// The wallet's connection plumbing — which chains are read (prd §182,
/// 2026-07-22). Pushed from the account page's one "Connection" row rather
/// than living inline, which is the amendment to §139's "manage is one page,
/// no doors": that ruling killed doors to READS — the per-wallet detail
/// screen's safety facts already lived better as Worth-a-look tray rows. This
/// door isn't a read. It's set-once configuration nobody wants staring at them
/// every time they open the wallet page to watch a new address, and moving it
/// here is what let that page stop looking like a settings page.
///
/// **ON THE ACCOUNT PAGE'S GRAMMAR SINCE §639c (2026-09-06)** — plain rows on
/// the page's own ground, a `subhead13` tertiary caption, the same ink top.
/// It is one tap below a catalogue page and was the last thing in that journey
/// still drawn as `insetGrouped` cards with `label12` headers, which is the
/// settings-page look the ruling above says this door exists to avoid.
///
/// **AND ITS DISCONNECT IS GONE, which is a fix rather than a trim.** §639b
/// gave `AccountPage` an exits section, so the Wallet page one level up grew a
/// Disconnect it never had — with the same verb, the same dialog and the same
/// keep-or-purge choice `BridgeDisconnectSection` has always drawn. Two
/// controls for one consequence is §190's split, where neither reads as the
/// real one, and the copy that has to go is the one on the page you reach by
/// tapping "Connection" to pick chains. What stays is this page's own fact:
/// the read is public and happens on the device.
struct WalletConnectionScreen: View {
    @Bindable private var chainStore = WalletChainStore.shared
    @Environment(\.modelContext) private var modelContext
    /// Re-syncs after a chain toggle — the account page's own `sync()` isn't
    /// reachable from here, and a toggle that visibly does nothing until the
    /// next foreground would read as broken.
    @State private var syncing = false

    var body: some View {
        List {
            Text("Chains")
                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                .padding(.top, DS.Space.s3)
                .plainAccountRow()
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
                                .dsGlyph(17).foregroundStyle(DS.tint)
                        }
                    }
                    .frame(minHeight: AccountFactRow.height)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .plainAccountRow()
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
            .frame(minHeight: AccountFactRow.height)
            .plainAccountRow()
            Text("A Bitcoin address is read too, from its own public API.")
                .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, DS.Space.s2)
                .plainAccountRow()
            // The promise, and the only thing left on this page that is not a
            // chain — the Disconnect that used to sit under it belongs to the
            // account page's exits (see this file's doc).
            Text("Read-only — watching can never trade or move funds. Activity is public, read across chains directly on \(DS.device).")
                .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, DS.Space.s3)
                .padding(.bottom, ShellMetrics.bottomInset)
                .plainAccountRow()
        }
        .listStyle(.plain)
        .listSectionSpacing(.compact)
        .scrollContentBackground(.hidden)
        .bridgeSetupWash(name: "Wallet")
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
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
}
