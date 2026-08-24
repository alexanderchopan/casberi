import SwiftUI
import SwiftData

/// Railgun, connected — what you shield and what comes back (prd §268).
/// Shielding happens from the person's own wallet in Railgun's own app, so
/// there is no account, no key, no OAuth — the seat rides the watched wallets
/// the way Peer and Privacy Pools do, and there is no switch to throw.
///
/// This screen exists to carry Railgun's CEILINGS, which are unusual enough
/// that the catalog summary alone shouldn't be their only home: nothing inside
/// the pool is read, an unshield never names its sender, and native ETH isn't
/// attributable. Every one of those is the product working rather than a gap,
/// and the footer says so in those words.
struct RailgunScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    // This window's stack (per-window since `SceneState`).
    @Environment(HomeRoute.self) private var route
    @State private var syncing = false
    @State private var lastResult: String?
    /// Whether `lastResult` is a failure — never hardcoded false, or a
    /// "couldn't reach the chain" line paints in confirm green with the
    /// count-up animation, which is the fake status §83 bans.
    @State private var lastResultIsError = false

    private var hasWallets: Bool { !WalletStore.shared.addresses.isEmpty }
    private var walletCount: Int { WalletStore.shared.addresses.count }

    var body: some View {
        List {
            BridgeSetupHeader(
                name: "Railgun",
                mode: .watchedWallets,
                intro: "No account here — it reads the wallets you already watch, so shields and unshields land in your feed. What happens inside the pool is never read: your private balance stays private, which is the point of using Railgun.",
                connected: hasWallets)
            if hasWallets {
                RoomDoor(name: "Railgun", source: "Railgun")
                    .listRowSeparator(.hidden)
            }
            connectSection.listRowSeparator(.hidden)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .bridgeSetupWash(name: "Railgun")
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .dsScreenTitle("Railgun")
        .onAppear {
            // Watching is consent (prd §207): keep the catalog seat honest on
            // appear, and refresh if a wallet's watched.
            store.reconcileWalletSeats()
            if hasWallets { Task { await sync() } }
        }
    }

    // MARK: - Connect (automatic — no switch, prd §207)

    /// No toggle: shields come from your own wallet, so watching a wallet IS
    /// the consent to read them. With wallets watched, the row states the fact
    /// and doors to the wallet manager; with none, it's the invitation.
    private var connectSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                if hasWallets {
                    DSSlabDoor(title: String(localized: "Watching \(walletCount) wallet"),
                               detail: String(localized: "Manage")) {
                        route.pushBridge(.wallet)
                    }
                } else {
                    DSSlabDoor(title: "Watch a wallet") {
                        route.pushBridge(.wallet)
                    }
                }
                BridgeSyncStatusRows(syncing: syncing,
                                     syncingLine: String(localized: "Reading the pool's doors…"),
                                     result: lastResult, resultIsError: lastResultIsError)
                DSSlabNote(text: hasWallets
                    ? String(localized: "On automatically — both doors land as they happen.")
                    : String(localized: "Read off the wallets you watch."))
            }
        }
        .dsSlabSection()
    }


    // MARK: - Actions

    /// Refresh both doors for the watched wallets. The catalog seat is kept
    /// honest by `store.reconcileWalletSeats()`, not here.
    private func sync() async {
        guard hasWallets, !syncing else { return }
        syncing = true
        defer { syncing = false }
        let added = await RailgunBridge.syncNow(context: modelContext)
        if let added {
            lastResult = added > 0 ? String(localized: "\(added) new")
                                   : String(localized: "Up to date")
            lastResultIsError = false
        } else {
            lastResult = String(localized: "Couldn't reach the chain — check your connection.")
            lastResultIsError = true
        }
    }
}
