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
///
/// **ON `AccountPage` SINCE §639 (2026-09-06).** It was a connect screen —
/// header, room door, one slab — and stayed one after connecting, which is
/// the complaint that opened §639: *"these others that are already connected
/// still look like connect pages."* The page now opens on the mark, the name
/// and what the seat is doing; the wallet door is the act slot, because
/// watching another wallet is the only thing there is to add here.
struct PrivacyPoolsScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    // This window's stack (per-window since `SceneState`).
    @Environment(HomeRoute.self) private var route
    @State private var syncing = false
    @State private var lastResult: BridgeProof?
    /// Whether `lastResult` is a failure. Hardcoding `false` at the call site
    /// painted "Couldn't reach the chain" in confirm green with the count-up
    /// animation — the fake-status class §83 bans, in the component whose own
    /// doc-comment prohibits it (audit, 2026-07-31).

    private var hasWallets: Bool { !WalletStore.shared.addresses.isEmpty }
    private var walletCount: Int { WalletStore.shared.addresses.count }

    /// The page's one presentation (`AccountPage.sheet`).
    @State private var sheet: AccountPageSheet?

    var body: some View {
        AccountPage(
            name: "0xBow Privacy Pools", seatID: "privacypools", source: "Privacy Pools",
            state: AccountPageState.of(name: "0xBow Privacy Pools", seatID: "privacypools",
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
                             syncingLine: String(localized: "Reading your deposits…"),
                             proof: lastResult)
        DSSlabNote(text: hasWallets
            ? String(localized: "On automatically — tells you the moment screening clears a deposit.")
            : String(localized: "Deposits are read off the wallets you watch."),
            plain: true)
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
            lastResult = .landed(added)
        } else {
            lastResult = .failed(String(localized: "Couldn't reach the chain — check your connection."))
        }
    }
}
