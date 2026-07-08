import SwiftUI
import SwiftData

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

    /// The RSS things already in the corpus — newest first.
    private var recent: [Thing] {
        recentBridgeThings(source: "RSS", context: modelContext)
    }

    var body: some View {
        List {
            if !rss.feeds.isEmpty { followingSection }
            addSection
            if !recent.isEmpty {
                RecentThingsSection(header: "RECENT", things: recent, titleLines: 1)
            }
            footerSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .dsPageBackground()
        .navigationTitle("RSS")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { EditButton().tint(DS.textPrimary) }
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
                .listRowBackground(DS.surfaceSheet)
            }
            .onDelete { rss.remove(at: $0) }
        } header: {
            HStack {
                Text("FOLLOWING").dsText(.label12).kerning(0.7)
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
            Text("ADD A FEED").dsText(.label12).kerning(0.7)
                .foregroundStyle(DS.textTertiary)
        } footer: {
            Text("Paste a site's feed URL — new posts land in your feed as links.")
                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
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
            lastResult = "Couldn't reach your feeds — check your connection."
            return
        }
        lastResult = added > 0 ? "\(added) new" : "Up to date"
        let proof = added > 0 ? "\(added) posts in" : "Synced just now"
        store.registerConnected(id: "rss", name: "RSS", proof: proof,
                                can: ["Reads the feeds you follow."])
    }
}
