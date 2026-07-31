import SwiftUI
import SwiftData

/// Privacy Pools (0xBow), connected — your deposits and their screening
/// status (prd §162). Depositing happens from the person's own wallet on
/// 0xBow's app, so there is no account, no key, no OAuth — the seat rides
/// the watched wallets the way Peer does, and connecting is one switch.
/// What the seat adds: each deposit lands as a thing, and the moment the
/// screening clears it to withdraw privately (or declines it), that lands
/// too — the flip people otherwise poll a website for. Read-only by design
/// and by ruling: nothing here deposits, withdraws, proves, or signs, and
/// the withdrawal side is unlinkable by design, so Casberi never sees it.
struct PrivacyPoolsScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @State private var syncing = false
    @State private var lastResult: String?

    private var hasWallets: Bool { !WalletStore.shared.addresses.isEmpty }
    private var walletCount: Int { WalletStore.shared.addresses.count }

    var body: some View {
        List {
            BridgeSetupHeader(name: "0xBow Privacy Pools", connected: hasWallets)
            connectSection.listRowSeparator(.hidden)
            if hasWallets {
                ChipLiveNote(name: "0xBow Privacy Pools",
                            verb: "for your deposits and their screening status.")
                    .listRowSeparator(.hidden)
            }
            footerSection.listRowSeparator(.hidden)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .bridgeSetupWash(name: "0xBow Privacy Pools")
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .dsScreenTitle("0xBow Privacy Pools")
        .onAppear {
            // Watching is consent (prd §207): keep the catalog seat honest on
            // appear, and refresh deposits if a wallet's watched.
            store.reconcileWalletSeats()
            if hasWallets { Task { await sync() } }
        }
    }

    // MARK: - Connect (automatic — no switch, prd §207)

    /// No toggle: deposits come from your own wallet, so watching a wallet IS
    /// the consent to read them and poll their screening status. With wallets
    /// watched, the row states the fact and doors to the wallet manager; with
    /// none, it's the invitation to watch one.
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
                BridgeSyncStatusRows(syncing: syncing,
                                     syncingLine: String(localized: "Reading your deposits…"),
                                     result: lastResult, resultIsError: false)
                DSSlabNote(text: hasWallets
                    ? String(localized: "On automatically — tells you the moment screening clears a deposit.")
                    : String(localized: "Deposits are read off the wallets you watch. Read-only."))
            }
        }
        .dsSlabSection()
    }

    private var footerSection: some View {
        Section {
            Text("Deposits are read from Ethereum's public chain and each deposit's review status from 0xBow's public API by \(DS.device) — no account, no key.\n\nWithdrawals are private by design: the chain can't link them to your deposit, so Casberi never sees or shows that side. Read-only: nothing here deposits, withdraws, or moves funds.")
                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                .listRowBackground(Color.clear)
        }
    }

    // MARK: - Actions

    /// Refresh deposits + status for the watched wallets. The catalog seat is
    /// kept honest by `store.reconcileWalletSeats()`, not here.
    private func sync() async {
        guard hasWallets, !syncing else { return }
        syncing = true
        defer { syncing = false }
        let added = await PrivacyPoolsBridge.syncNow(context: modelContext)
        if let added {
            lastResult = added > 0 ? String(localized: "\(added) new")
                                   : String(localized: "Up to date")
        } else {
            lastResult = String(localized: "Couldn't reach the chain — check your connection.")
        }
    }
}
