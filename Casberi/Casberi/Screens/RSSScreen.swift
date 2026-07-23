import SwiftUI
import SwiftData

/// RSS, connected — feeds' home in Casberi. The person manages WHICH feeds
/// are followed (paste a site or feed URL, swipe to remove) and sees them as
/// one ledger. New posts arrive as link things on every visit and app
/// foreground — no account, no server, no algorithm in between.
///
/// REBUILT 2026-07-23 (prd §184) — the reference ledger for the manager
/// pattern the wallet screen proved (prd §182): identity leads, one omnibox
/// both follows and would search, the "what landed" preview drops (the feed
/// already shows that; a manager manages). RSS has no tiers or toggles, so
/// it's the plainest form the pattern takes — every publication a square
/// mark (a favicon, or the RSS glyph), its URL demoted to the subline.
struct RSSScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @Bindable private var rss = RSSStore.shared
    @State private var newFeed = ""
    @State private var syncing = false
    @State private var lastResult: String?
    @State private var resultIsError = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        List {
            BridgeSetupHeader(name: "RSS", connected: !rss.feeds.isEmpty)
            omniSection.listRowSeparator(.hidden)
            if !rss.feeds.isEmpty {
                ledgerSection.listRowSeparator(.hidden)
            }
            if !rss.feeds.isEmpty {
                BridgeDisconnectSection(
                    bridgeID: "rss", name: "RSS",
                    teardown: {
                        RSSStore.shared.feeds = []
                    }
                ).listRowSeparator(.hidden)
            }
            footerSection.listRowSeparator(.hidden)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .bridgeSetupWash(name: "RSS")
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .navigationTitle("RSS")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            // Every visit refreshes — feeds are cheap to poll.
            Task { await sync() }
        }
    }

    // MARK: - Add

    private var omniSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                DSSlabField(placeholder: String(localized: "Site or feed URL"),
                            text: $newFeed, actionLabel: String(localized: "FOLLOW"),
                            keyboard: .URL, focus: $fieldFocused, action: addFeed)
                BridgeSyncStatusRows(syncing: syncing,
                                     syncingLine: String(localized: "Reading your feeds…"),
                                     result: lastResult, resultIsError: resultIsError)
                DSSlabNote(text: "A site's own address works too — Casberi finds its feed.")
            }
        }
        .dsSlabSection()
    }

    // MARK: - The ledger

    private var ledgerSection: some View {
        Section {
            ForEach(rss.feeds) { feed in
                HStack(spacing: DS.Space.s3) {
                    // Square, not round — a publication is a topic, not a
                    // person (the mark grammar ruling, prd §184).
                    BridgeIcon(name: "RSS", size: 32, circular: false)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(feed.displayName)
                            .dsText(.body17).foregroundStyle(DS.textPrimary)
                            .lineLimit(1)
                        Text(feed.url)
                            .dsText(.label12).foregroundStyle(DS.textTertiary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .dsListCardRow()
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        if let i = rss.feeds.firstIndex(where: { $0.id == feed.id }) {
                            rss.remove(at: IndexSet(integer: i))
                        }
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                }
            }
        } header: {
            Text(rss.feeds.count == 1 ? "Following" : "Following \(rss.feeds.count)")
                .dsText(.label12).foregroundStyle(DS.textTertiary)
        }
    }

    private var footerSection: some View {
        Section {
            Text("Fetched directly by this iPhone — no account, no server, no ranking.")
                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                .listRowBackground(Color.clear)
        }
    }

    // MARK: - Actions

    private func addFeed(){
        guard rss.add(newFeed) else { return }
        newFeed = ""
        fieldFocused = false
        resultIsError = false
        DSHaptic.success()
        Task { await sync() }
    }

    /// Fetch + land; the status row carries the proof.
    private func sync() async {
        guard !rss.feeds.isEmpty, !syncing else { return }
        syncing = true
        let added = await RSSIngest.refresh(context: modelContext)
        syncing = false
        guard let added else {
            lastResult = String(localized: "Couldn't reach your feeds — check your connection.")
            resultIsError = true
            return
        }
        resultIsError = false
        lastResult = added > 0 ? String(localized: "\(added) new") : String(localized: "Up to date")
        let proof = added > 0 ? "\(added) posts in" : "Synced just now"
        store.registerConnected(id: "rss", name: "RSS", proof: proof,
                                can: ["Reads the feeds you follow."])
    }
}
