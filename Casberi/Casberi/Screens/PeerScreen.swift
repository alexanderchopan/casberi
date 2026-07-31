import SwiftUI
import SwiftData

/// Peer, connected — your fiat↔crypto trades, as they settle (prd §113).
/// Peer is non-custodial: every trade settles onchain into the person's OWN
/// wallet, so there is no account, no key, no OAuth — the seat rides the
/// watched wallets the way Strava rides Apple Health, and connecting is one
/// switch. What the seat adds over the bare wallet feed is the WHY: "Bought
/// 25 USDC with Venmo on Peer" instead of an unexplained transfer. Read-only
/// by design and by ruling: nothing here ever starts a trade, and Peer's
/// zero-knowledge design keeps the Venmo/PayPal side private — the chain
/// (and so this screen) never sees it.
struct PeerScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @State private var syncing = false
    @State private var lastResult: String?

    private var hasWallets: Bool { !WalletStore.shared.addresses.isEmpty }
    private var walletCount: Int { WalletStore.shared.addresses.count }

    var body: some View {
        List {
            BridgeSetupHeader(name: "Peer", connected: hasWallets)
            connectSection.listRowSeparator(.hidden)
            if hasWallets {
                ChipLiveNote(name: "Peer", verb: "for your fills.")
                    .listRowSeparator(.hidden)
            }
            footerSection.listRowSeparator(.hidden)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .bridgeSetupWash(name: "Peer")
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .dsScreenTitle("Peer")
        .onAppear {
            // Watching is consent (prd §207): keep the catalog seat honest the
            // moment this screen appears, and refresh fills if a wallet's watched.
            store.reconcileWalletSeats()
            if hasWallets { Task { await sync() } }
        }
    }

    // MARK: - Connect (automatic — no switch, prd §207)

    /// No toggle: Peer settles into your own wallet, so watching a wallet IS
    /// the consent to read its fills. With wallets watched, the row states the
    /// fact and doors to the wallet manager (where you add or remove them);
    /// with none, it's the invitation to watch one — the add-a-wallet entry
    /// this catalog tile exists to be.
    private var connectSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                if hasWallets {
                    DSSlabDoor(title: String(localized: "Watching \(walletCount) wallet\(walletCount == 1 ? "" : "s")"),
                               detail: String(localized: "Manage")) {
                        HomeRoute.shared.pushBridge(.wallet)
                    }
                } else {
                    DSSlabDoor(title: "Watch a wallet") {
                        HomeRoute.shared.pushBridge(.wallet)
                    }
                }
                DSSlabNote(text: hasWallets
                    ? "On automatically — Peer reads the wallets you watch. Read-only, never trades."
                    : "Peer settles into your own wallet, so watching a wallet is all it takes. Read-only, never trades.")
            }
        }
        .dsSlabSection()
    }

    private var footerSection: some View {
        Section {
            Text("Fills are read from Base's public chain by \(DS.device) — no Peer account, no key.\n\nPeer's zero-knowledge design keeps your Venmo or PayPal side private; the chain never shows it, so neither does Casberi. Read-only: nothing here ever starts a trade.")
                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                .listRowBackground(Color.clear)
        }
    }

    // MARK: - Actions

    /// Refresh fills for the watched wallets. The catalog seat is kept honest
    /// by `store.reconcileWalletSeats()` (on appear + every foreground), not
    /// here — this only lands new fills and reports reach.
    private func sync() async {
        guard hasWallets, !syncing else { return }
        syncing = true
        defer { syncing = false }
        let added = await PeerBridge.syncNow(context: modelContext)
        if let added {
            lastResult = added > 0 ? String(localized: "\(added) new")
                                   : String(localized: "Up to date")
        } else {
            lastResult = String(localized: "Couldn't reach Base — check your connection.")
        }
    }
}
