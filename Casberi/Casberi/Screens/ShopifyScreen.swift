import SwiftUI
import SwiftData

/// Shopify, connected — stores' new drops in Casberi. The person manages WHICH
/// stores are followed (paste a store's web address, swipe to remove) and sees
/// what's landed. New products, restocks, and sale prices arrive as things on
/// every visit and app foreground — no account, no server, read-only. Tapping
/// a product opens the store's own page; nothing here checks out or pays.
struct ShopifyScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @Bindable private var shopify = ShopifyStore.shared
    @State private var newStore = ""
    @State private var syncing = false
    @State private var lastResult: BridgeProof?
    /// Whether `lastResult` is a failure — see `PrivacyPoolsScreen` (audit,
    /// 2026-07-31): hardcoding `false` painted "Couldn't reach your stores" in
    /// confirm green with the count-up animation.
    @FocusState private var fieldFocused: Bool


    /// The page's one presentation (`AccountPage.sheet`).
    @State private var sheet: AccountPageSheet?
    /// This week's products per store, for the roster's subline and its
    /// active/quiet split. Keyed on the shop's DISPLAY NAME, which is what
    /// `ShopifyIngest` stamps as the thing's `authorHandle`.
    @State private var weekly: [String: (week: Int, new: Bool)] = [:]

    var body: some View {
        AccountPage(
            name: "Shopify", seatID: "shopify", source: "Shopify",
            state: AccountPageState.of(name: "Shopify", seatID: "shopify",
                                       connected: shopify.connected, store: store),
            mode: .noAccount,
            rows: rows,
            query: newStore,
            onRemoveRow: unfollow,
            teardown: { ShopifyStore.shared.shops = [] },
            sheet: $sheet,
            act: { addBlock },
            more: { EmptyView() },
            keySheet: { EmptyView() }
        )
        .onAppear {
            countWeek()
            // Opening the page doesn't connect — the person pastes a store to
            // follow it. Only refresh if something's already followed.
            if shopify.connected { Task { await sync() } }
        }
        .onChange(of: shopify.shops) { _, _ in countWeek() }
    }

    // MARK: - The roster

    /// One row per followed store. A shop is a publication you follow, and
    /// what a row says about it is how many products it dropped this week —
    /// the same grammar every other seat's roster wears, in place of the
    /// square-marked "Following N" list with its own Remove.
    private var rows: [AccountPageShape.Row] {
        shopify.shops.map { shop in
            let counted = weekly[shop.displayName.lowercased()] ?? (week: 0, new: false)
            return AccountPageShape.Row(
                id: shop.id.uuidString,
                title: shop.displayName,
                subline: AccountPageShape.subline(nouns: String(localized: "products"),
                                                  weekCount: counted.week),
                weekCount: counted.week, hasNew: counted.new,
                isYou: false, avatarURL: nil)
        }
    }

    private func unfollow(_ id: String) {
        guard let i = shopify.shops.firstIndex(where: { $0.id.uuidString == id }) else { return }
        shopify.remove(at: IndexSet(integer: i))
        countWeek()
    }

    /// This week's products per store, keyed on the shop's display name —
    /// what `ShopifyIngest` stamps as a product's `authorHandle`.
    private func countWeek() {
        weekly = AccountWeek.counts(source: "Shopify", seatID: "shopify",
                                    context: modelContext) { $0.authorHandle }
    }


    // MARK: - Following

    // MARK: - Add

    /// The omnibox leads (prd §186) — following a store is this screen's
    /// primary act, not an errand below a list.
    @ViewBuilder private var addBlock: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
        DSSlabField(placeholder: String(localized: "Store web address"),
                    text: $newStore, actionLabel: String(localized: "Follow"),
                    keyboard: .URL, focus: $fieldFocused, action: addStore)
        BridgeSyncStatusRows(syncing: syncing,
                             syncingLine: String(localized: "Reading the store…"),
                             proof: lastResult)
        DSSlabNote(text: "New drops, restocks, and sale prices land in your feed.", plain: true)
        }
    }


    // MARK: - Actions

    /// Follows the pasted store, and SAYS what happened either way. A silent
    /// `guard … else { return }` left a rejected address sitting in the field
    /// with no message, no haptic and no state change, so nothing on screen
    /// separated "that isn't a store" from "you didn't tap" (audit,
    /// 2026-07-31). A duplicate isn't an error — it's the thing you wanted,
    /// already done — so it says so without the red and the shake.
    private func addStore() {
        switch shopify.add(newStore) {
        case .added:
            newStore = ""
            fieldFocused = false
            lastResult = nil
            DSHaptic.success()
            Task { await sync() }
        case .duplicate:
            newStore = ""
            fieldFocused = false
            lastResult = .says(String(localized: "Already following that store."))
            DSHaptic.selection()
        case .unreadable:
            lastResult = .failed(String(localized: "That isn't a store web address — paste one like allbirds.com."))
        }
    }

    /// Fetch + land; the bridge's status line carries the proof.
    private func sync() async {
        guard shopify.connected, !syncing else { return }
        syncing = true
        let added = await ShopifyIngest.refresh(context: modelContext)
        syncing = false
        guard let added else {
            // nil = every followed store refused or was unreachable — the
            // honest "won't share" line, not a silent empty.
            lastResult = .failed(String(localized: "Couldn't reach your stores — check the address, or the store isn't Shopify / blocks reads."))
            return
        }
        lastResult = .landed(added)
        let proof = added > 0
            ? String(localized: "\(added) drops in")
            : String(localized: "Synced just now")
        store.registerConnected(id: "shopify", name: "Shopify", proof: proof,
                                can: ["Reads the newest products from the stores you follow.",
                                      "Read-only — never checks out or pays."])
    }
}
