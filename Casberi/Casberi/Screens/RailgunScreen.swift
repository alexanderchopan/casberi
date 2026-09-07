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
///
/// **ON `AccountPage` SINCE §639 (2026-09-06).** It was a connect screen —
/// header, room door, one slab — and stayed one after connecting, which is
/// the complaint that opened §639: *"these others that are already connected
/// still look like connect pages."* The page now opens on the mark, the name
/// and what the seat is doing; the wallet door is the act slot, because
/// watching another wallet is the only thing there is to add here.
struct RailgunScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    // This window's stack (per-window since `SceneState`).
    @Environment(HomeRoute.self) private var route
    @State private var syncing = false
    @State private var lastResult: BridgeProof?
    /// Whether `lastResult` is a failure — never hardcoded false, or a
    /// "couldn't reach the chain" line paints in confirm green with the
    /// count-up animation, which is the fake status §83 bans.

    private var hasWallets: Bool { !WalletStore.shared.addresses.isEmpty }
    private var walletCount: Int { WalletStore.shared.addresses.count }

    /// The page's one presentation (`AccountPage.sheet`).
    @State private var sheet: AccountPageSheet?

    var body: some View {
        AccountPage(
            name: "Railgun", seatID: "railgun", source: "Railgun",
            state: AccountPageState.of(name: "Railgun", seatID: "railgun",
                                       connected: hasWallets, store: store),
            mode: .watchedWallets,
            // NOTHING TO TEAR DOWN, and that is the seat (prd §207). This
            // bridge holds no store of its own — it reads whatever wallets are
            // watched — so a disconnect drops the seat and leaves the wallets
            // alone, which is what somebody disconnecting THIS and not their
            // wallet means.
            teardown: {},
            sheet: $sheet,
            act: { actBlock },
            more: { EmptyView() },
            keySheet: { EmptyView() }
        )
        .onAppear {
            // Watching is consent (prd §207): keep the catalog seat honest on
            // appear, and refresh if a wallet's watched.
            store.reconcileWalletSeats()
            if hasWallets { Task { await sync() } }
        }
    }

    // MARK: - The act (automatic — no switch, prd §207)

    /// No toggle: this settles into your own wallet, so watching a wallet IS
    /// the consent to read it. The act slot carries the one thing you can add
    /// here — another wallet — and it is the wallet manager's own door rather
    /// than a second list, because a seat that reads whatever is watched must
    /// never grow a watch list of its own to disagree with (prd §207).
    ///
    /// **NO ROSTER, deliberately.** The chassis's "Watching · N" is for rows
    /// this seat owns; these are the WALLET seat's, and drawing them here
    /// would put the same list on two pages with one Remove between them.
    @ViewBuilder private var actBlock: some View {
        if hasWallets {
            DSSlabDoor(title: String(localized: "Watching \(walletCount) wallet"),
                       detail: String(localized: "Manage"),
                       systemImage: "eye") {
                route.pushBridge(.wallet)
            }
        } else {
            DSSlabDoor(title: "Watch a wallet", systemImage: "eye") {
                route.pushBridge(.wallet)
            }
        }
        BridgeSyncStatusRows(syncing: syncing,
                             syncingLine: String(localized: "Reading the pool's doors…"),
                             proof: lastResult)
        DSSlabNote(text: hasWallets
            ? String(localized: "On automatically — both doors land as they happen.")
            : String(localized: "Read off the wallets you watch."),
            plain: true)
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
            lastResult = .landed(added)
        } else {
            lastResult = .failed(String(localized: "Couldn't reach the chain — check your connection."))
        }
    }
}
