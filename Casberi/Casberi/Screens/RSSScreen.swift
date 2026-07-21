import SwiftUI
import SwiftData

/// The RSS things already in the corpus — newest first. A @Query so the list
/// updates live as sync lands posts, and the fetch runs once per store change
/// rather than twice on every body pass.
private let rssRecentDescriptor: FetchDescriptor<Thing> = {
    var d = FetchDescriptor<Thing>(
        predicate: #Predicate { $0.source == "RSS" },
        sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
    )
    d.fetchLimit = 12
    return d
}()

/// RSS, connected — feeds' home in Casberi. The person manages WHICH feeds
/// are followed (paste a site or feed URL, swipe to remove) and sees what's
/// landed. New posts arrive as link things on every visit and app foreground
/// — no account, no server, no algorithm in between.
struct RSSScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @Bindable private var rss = RSSStore.shared
    @State private var newFeed = ""
    @State private var syncing = false
    @State private var lastResult: String?
    @FocusState private var fieldFocused: Bool

    @Query(rssRecentDescriptor) private var recent: [Thing]

    var body: some View {
        List {
            BridgeSetupHeader(name: "RSS", connected: !rss.feeds.isEmpty)
            if !rss.feeds.isEmpty { followingSection.listRowSeparator(.hidden) }
            addSection.listRowSeparator(.hidden)
            if recent.isEmpty {
                // Only before the first feed: once one is followed, a ghost
                // captioned "when you follow a feed" would contradict the
                // Following list above it (honesty rule; review 2026-07-16).
                if rss.feeds.isEmpty {
                    GhostPreviewSection(name: "RSS",
                                        replaceLine: "Your real posts replace this when you follow a feed.")
                        .listRowSeparator(.hidden)
                }
            } else {
                RecentThingsSection(header: "Recent", things: recent, titleLines: 1)
                    .listRowSeparator(.hidden)
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
        .dsSoftTopEdge()
        .navigationTitle("RSS")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            // Edit only exists once there's a following list to edit — every
            // other section here is gated the same way.
            if !rss.feeds.isEmpty {
                ToolbarItem(placement: .topBarTrailing) { EditButton().tint(DS.textPrimary) }
            }
        }
        .onAppear {
            // Every visit refreshes — feeds are cheap to poll.
            Task { await sync() }
        }
    }

    // MARK: - Following

    private var followingSection: some View {
        Section {
            ForEach(rss.feeds) { feed in
                VStack(alignment: .leading, spacing: 2) {
                    Text(feed.displayName)
                        .dsText(.body17).foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    Text(feed.url)
                        .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                }
                .dsListCardRow()
            }
            .onDelete { rss.remove(at: $0) }
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
            BridgeFieldRow(placeholder: "Site or feed URL", text: $newFeed,
                           buttonLabel: "Follow", keyboard: .URL,
                           focus: $fieldFocused, action: addFeed)
        } header: {
            Text("Add a feed").dsText(.label12)
                .foregroundStyle(DS.textTertiary)
        } footer: {
            // The mechanic only — the promise lives in the header, the privacy
            // line in the footer; each block says its one thing (2026-07-16).
            Text("A site's own address works too — Casberi finds its feed.")
                .dsText(.callout15).foregroundStyle(DS.textTertiary)
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
        DSHaptic.success()
        Task { await sync() }
    }

    /// Fetch + land; the bridge's status line carries the proof.
    private func sync() async {
        guard !rss.feeds.isEmpty, !syncing else { return }
        syncing = true
        let added = await RSSIngest.refresh(context: modelContext)
        syncing = false
        guard let added else {
            lastResult = String(localized: "Couldn't reach your feeds — check your connection.")
            return
        }
        lastResult = added > 0 ? String(localized: "\(added) new") : String(localized: "Up to date")
        let proof = added > 0 ? "\(added) posts in" : "Synced just now"
        store.registerConnected(id: "rss", name: "RSS", proof: proof,
                                can: ["Reads the feeds you follow."])
    }
}
