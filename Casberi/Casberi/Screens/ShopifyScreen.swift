import SwiftUI
import SwiftData

/// The Shopify products already in the corpus — newest first. A @Query so the
/// list grows live as a sync lands products.
private let shopifyRecentDescriptor: FetchDescriptor<Thing> = {
    var d = FetchDescriptor<Thing>(
        predicate: #Predicate { $0.source == "Shopify" },
        sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
    )
    d.fetchLimit = 12
    return d
}()

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
    @State private var lastResult: String?
    @FocusState private var fieldFocused: Bool

    @Query(shopifyRecentDescriptor) private var recent: [Thing]

    var body: some View {
        List {
            BridgeSetupHeader(name: "Shopify")
            if !shopify.shops.isEmpty { followingSection.listRowSeparator(.hidden) }
            addSection.listRowSeparator(.hidden)
            if !recent.isEmpty {
                RecentThingsSection(header: "New drops", things: recent, titleLines: 1)
                    .listRowSeparator(.hidden)
            }
            if !shopify.shops.isEmpty {
                BridgeDisconnectSection(
                    bridgeID: "shopify", name: "Shopify",
                    teardown: {
                        ShopifyStore.shared.shops = []
                    }
                ).listRowSeparator(.hidden)
            }
            footerSection.listRowSeparator(.hidden)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .bridgeSetupWash(name: "Shopify")
        .dsPageBackground()
        .navigationTitle("Shopify")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { EditButton().tint(DS.textPrimary) }
        }
        .onAppear {
            // Opening the screen doesn't connect — the person pastes a store to
            // follow it. Only refresh if something's already followed.
            if shopify.connected { Task { await sync() } }
        }
    }

    // MARK: - Following

    private var followingSection: some View {
        Section {
            ForEach(shopify.shops) { shop in
                VStack(alignment: .leading, spacing: 2) {
                    Text(shop.displayName)
                        .dsText(.body17).foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    Text(shop.host)
                        .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                }
                .dsListCardRow()
            }
            .onDelete { shopify.remove(at: $0) }
        } header: {
            HStack {
                Text("Following").dsText(.label12)
                    .foregroundStyle(DS.textTertiary)
                Spacer()
                if syncing {
                    ProgressView().controlSize(.small)
                } else if let lastResult {
                    Text(lastResult).dsText(.label12).foregroundStyle(DS.textTertiary)
                }
            }
        }
    }

    // MARK: - Add

    private var addSection: some View {
        Section {
            BridgeFieldRow(placeholder: "Store web address", text: $newStore,
                           buttonLabel: "Follow", keyboard: .URL,
                           focus: $fieldFocused, action: addStore)
        } header: {
            Text("Follow a store").dsText(.label12)
                .foregroundStyle(DS.textTertiary)
        } footer: {
            Text("Paste a Shopify store's web address — its newest products land in your feed as things. Sale prices and restocks land too.")
                .dsText(.callout15).foregroundStyle(DS.textTertiary)
        }
    }

    private var footerSection: some View {
        Section {
            Text("Fetched directly by this iPhone through each store's public catalog — no account, no ranking. Read-only: nothing here checks out or pays. Some big stores block automated reads; those it can't follow, it says so.")
                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                .listRowBackground(Color.clear)
        }
    }

    // MARK: - Actions

    private func addStore() {
        guard shopify.add(newStore) else { return }
        newStore = ""
        fieldFocused = false
        DSHaptic.success()
        Task { await sync() }
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
            lastResult = String(localized: "Couldn't reach your stores — check the address, or the store isn't Shopify / blocks reads.")
            return
        }
        lastResult = added > 0 ? String(localized: "\(added) new") : String(localized: "Up to date")
        let proof = added > 0 ? "\(added) drops in" : "Synced just now"
        store.registerConnected(id: "shopify", name: "Shopify", proof: proof,
                                can: ["Reads the newest products from the stores you follow.",
                                      "Read-only — never checks out or pays."])
    }
}
