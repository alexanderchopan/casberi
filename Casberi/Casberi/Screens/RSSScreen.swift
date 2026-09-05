import SwiftUI
import SwiftData
import UniformTypeIdentifiers

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
///
/// OPML import/export added 2026-07-28 — the bulk on-ramp (and off-ramp)
/// every other reader shares this format for. Two-phase like Bookmarks
/// (parse, then pick a scope) rather than land-on-pick: an OPML export can
/// carry a hundred feeds across a dozen folders, and committing all of it
/// sight-unseen is the wrong default for a screen whose whole grammar is "no
/// algorithm in between."
struct RSSScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @Bindable private var rss = RSSStore.shared
    @State private var newFeed = ""
    @State private var syncing = false
    /// An address followed while a pass was already in flight, held so the
    /// pass that follows can read it (2026-08-16). One slot, not a queue: a
    /// second follow arriving in the same window supersedes the first, and the
    /// re-run reads EVERY feed anyway — the address is only carried so the
    /// status row can name the right one.
    @State private var pendingAdd: String?
    @State private var lastResult: BridgeProof?
    @State private var importingOPML = false
    @State private var opmlParsed: OPMLImport.Parsed?
    @State private var exportURL: URL?
    /// Tracked so a SECOND file share while this sheet is already open still
    /// lands — `HomeRoute.openSetup(forOffer:)` re-sets `connectForm` to the
    /// same `.rss` case it already held, which `sheet(item:)` treats as no
    /// change (same Hashable value, no re-present), so `.onAppear` alone
    /// never refires for it. The `.onChange` below catches that case; the
    /// `.onAppear` check stays for the first mount, where there's nothing to
    /// change FROM yet.
    @State private var pendingOPML = PendingOPMLFile.shared
    @FocusState private var fieldFocused: Bool

    var body: some View {
        BridgeSetupPage(name: "RSS") {
            BridgeSetupHeader(
                name: "RSS",
                mode: .noAccount,
                intro: "Paste a site or feed address below, and its posts arrive. No ranking, nothing skipped.",
                connected: !rss.feeds.isEmpty)
            // The way back to what arrived (§460).
            if !rss.feeds.isEmpty {
                RoomDoor(name: "RSS", source: "RSS")
                    .listRowSeparator(.hidden)
            }
            omniSection.listRowSeparator(.hidden)
            if !rss.feeds.isEmpty {
                ledgerSection.listRowSeparator(.hidden)
            }
            if !rss.feeds.isEmpty {
                BridgeDisconnectSection(
                    bridgeID: "rss", name: "RSS",
                    teardown: {
                        RSSStore.shared.removeAll()
                    }
                ).listRowSeparator(.hidden)
            }
        }
        .onAppear {
            refreshExportURL()
            // A file handed in via AirDrop/Share Sheet before this screen
            // existed to receive it (RootShell's onOpenURL raised this sheet
            // and parked the URL here) — pick it up once, same as if the
            // person had just tapped through the file picker themselves.
            if let pending = pendingOPML.url {
                pendingOPML.url = nil
                Task { await parseOPML(pending) }
            }
            // Every visit refreshes — feeds are cheap to poll.
            Task { await sync() }
        }
        .onChange(of: rss.feeds) { _, _ in refreshExportURL() }
        .onChange(of: pendingOPML.url) { _, url in
            guard let url else { return }
            pendingOPML.url = nil
            Task { await parseOPML(url) }
        }
        .fileImporter(isPresented: $importingOPML,
                      allowedContentTypes: [UTType(filenameExtension: "opml") ?? .xml, .xml]) { outcome in
            guard case .success(let url) = outcome else { return }
            Task { await parseOPML(url) }
        }
    }

    // MARK: - Add

    private var omniSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                DSSlabField(placeholder: String(localized: "Site or feed URL"),
                            text: $newFeed, actionLabel: String(localized: "Follow"),
                            keyboard: .URL, focus: $fieldFocused, action: addFeed)
                BridgeSyncStatusRows(syncing: syncing,
                                     syncingLine: String(localized: "Reading your feeds…"),
                                     proof: lastResult)
                // The note that used to sit here said "A site's own address
                // works too" beneath a field placeheld "Site or feed URL" —
                // §220's finding exactly, so it went rather than got tightened
                // (audit, 2026-07-31).
                if let opmlParsed {
                    opmlScopePicker(opmlParsed)
                } else {
                    secondaryLinks
                }
            }
        }
        .dsSlabSection()
    }

    /// Secondary, not a second slab — this screen's one verb is FOLLOW;
    /// bulk import/export from another reader is a shortcut to the same
    /// place, not a competing action, so both stay plain text links.
    private var secondaryLinks: some View {
        HStack(spacing: DS.Space.s3) {
            Spacer(minLength: 0)
            Button {
                DSHaptic.tap()
                importingOPML = true
            } label: {
                Text("Import an OPML file")
                    .dsText(.subhead13).foregroundStyle(DS.tint)
            }
            .buttonStyle(.plain)
            if !rss.feeds.isEmpty, let exportURL {
                Text("·").dsText(.subhead13).foregroundStyle(DS.textTertiary)
                ShareLink(item: exportURL) {
                    Text("Export as OPML")
                        .dsText(.subhead13).foregroundStyle(DS.tint)
                }
                .simultaneousGesture(TapGesture().onEnded { DSHaptic.tap() })
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    /// The picked file's contents, previewed before a single feed is
    /// followed (parsing never writes) — folders become scopes, mirroring
    /// `BookmarksImportScreen`'s Reading-List/All split.
    @ViewBuilder
    private func opmlScopePicker(_ parsed: OPMLImport.Parsed) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            ForEach(parsed.namedGroups, id: \.name) { group in
                DSSlabDoor(title: group.name,
                           detail: group.feeds.count == 1 ? "1 feed" : "\(group.feeds.count) feeds",
                           systemImage: "folder") {
                    importScope(group.feeds)
                }
            }
            DSSlabButton(title: parsed.namedGroups.isEmpty
                            ? "Import \(parsed.allFeeds.count) feeds"
                            : "Import all \(parsed.allFeeds.count)",
                         systemImage: "square.and.arrow.down") {
                importScope(parsed.allFeeds)
            }
            Button {
                DSHaptic.tap()
                opmlParsed = nil
            } label: {
                Text("Cancel")
                    .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - The ledger

    private var ledgerSection: some View {
        Section {
            ForEach(rss.feeds) { feed in
                HStack(spacing: DS.Space.s3) {
                    // Square, not round — a publication is a topic, not a
                    // person (the mark grammar ruling, prd §184).
                    BridgeIcon(name: "RSS", size: DS.Mark.list, circular: false)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(feed.displayName)
                            .dsText(.body17).foregroundStyle(DS.textPrimary)
                            .lineLimit(1)
                        // A feed that has stopped answering says so, in place
                        // of its own address (2026-08-05). The URL is demoted
                        // detail on this row; a publisher that has gone dark
                        // outranks it, and until now the two states — "quiet
                        // publisher" and "dead URL" — rendered as the same
                        // row that simply stopped growing. Silent unless
                        // there is something to say; see `FeedFreshness.
                        // trouble` for why the bar is three misses and three
                        // days rather than one.
                        if let trouble = FeedFreshness.trouble(for: feed.url) {
                            Text(trouble)
                                .dsText(.label12).foregroundStyle(DS.attention)
                                .lineLimit(1)
                        } else {
                            Text(feed.url)
                                .dsText(.label12).foregroundStyle(DS.textTertiary)
                                .lineLimit(1)
                        }
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
                // A swipe has no Mac-mouse equivalent — right-click mirrors it
                // (Mac polish, 2026-07-28).
                .contextMenu {
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


    // MARK: - Actions

    /// A refused follow SAYS why (2026-08-16). It used to `return` on `add`'s
    /// `false` and leave everything exactly as it was — field still full, no
    /// message, no haptic — so the two ordinary ways to be refused (a typo, and
    /// a feed already in the list, which is easy to hit since a followed site
    /// gets rewritten to its resolved feed URL and no longer matches what you
    /// pasted) both read as a dead button.
    private func addFeed(){
        let typed = newFeed
        guard rss.normalized(typed) != nil else {
            lastResult = .failed(String(localized: "That doesn't look like a web address."))
            return
        }
        guard rss.add(typed) else {
            lastResult = .failed(String(localized: "You already follow that."))
            return
        }
        let followed = rss.normalized(typed)
        newFeed = ""
        fieldFocused = false
                DSHaptic.success()
        Task { await sync(justAdded: followed) }
    }

    /// Reads a picked OPML file into a preview — never lands anything on its
    /// own. nil back from the parser (not OPML, or malformed) reports
    /// honestly instead of silently landing a truncated prefix.
    private func parseOPML(_ url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = await SecurityScopedFileReader.readData(at: url),
              let parsed = OPMLImport.parse(data: data), !parsed.allFeeds.isEmpty else {
            opmlParsed = nil
            lastResult = .failed(String(localized: "That file isn't an OPML export — pick the file your reader exported."))
            return
        }
        lastResult = nil
        opmlParsed = parsed
    }

    /// Lands the chosen scope (a folder, or everything), then syncs and
    /// upgrades the receipt from a bare count to the newest thing that
    /// actually showed up — landing on a THING, never a tally alone.
    private func importScope(_ feeds: [OPMLImport.Feed]) {
        opmlParsed = nil
        let summary = OPMLImport.land(feeds)
        guard summary.added > 0 else {
            // Not a failure — nothing was wrong with the file, you're just
            // already following all of it. See `EthValidatorScreen` for the
            // ruling that settled this across the family (2026-07-31).
            lastResult = .says(String(localized: "Already following every feed in that file."))
            return
        }
        let addedLine = "\(summary.added) feeds added\(summary.skipped > 0 ? " · \(summary.skipped) already followed" : "")"
        lastResult = .says(addedLine)
        DSHaptic.success()
        Task {
            await sync()
            // `sync()` just overwrote the status with its own per-visit
            // phrasing ("N new"/"Up to date") — the import's own receipt is
            // what belongs here, upgraded with the newest thing one of the
            // just-landed feeds actually produced, when there is one.
            lastResult = .says(addedLine)
            await describeLanding(from: feeds, addedLine: addedLine)
        }
    }

    /// Names the newest thing among the just-imported feeds instead of
    /// leaving the receipt a bare count (the module doctrine: never a tally
    /// alone). A silent no-op when nothing matches — a fresh feed's first
    /// sync can land nothing new, or land only older posts — the count line
    /// `importScope` already set stands fine on its own either way.
    @MainActor
    private func describeLanding(from feeds: [OPMLImport.Feed], addedLine: String) async {
        let names = Set(feeds.map(\.displayName))
        guard !names.isEmpty else { return }
        var descriptor = FetchDescriptor<Thing>(
            predicate: #Predicate<Thing> { $0.source == "RSS" },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 40
        guard let recent = try? modelContext.fetch(descriptor),
              let newest = recent.first(where: { names.contains($0.authorHandle ?? "") })
        else { return }
        lastResult = .says(String(localized: "\(addedLine) — newest: \(IngestSupport.titleLine(newest.title))"))
    }

    /// Fetch + land; the status row carries the proof.
    ///
    /// `justAdded` is the address the person just followed, when this sync was
    /// their doing. Two things hang off knowing that: the pass waits its turn
    /// instead of being dropped by one already in flight, and a page that
    /// turns out to publish no feed is named on the spot rather than reported
    /// as "Up to date" — which is what a site whose every path answers 200 got
    /// before, since by every other measure it is a perfectly healthy follow.
    private func sync(justAdded: String? = nil) async {
        guard !rss.feeds.isEmpty else { return }
        guard !syncing else {
            // Don't drop the person's own request — run it once this pass ends.
            if justAdded != nil { pendingAdd = justAdded }
            return
        }
        syncing = true
        let added = await RSSIngest.refresh(context: modelContext,
                                            waitForInFlight: justAdded != nil)
        syncing = false
        if let queued = pendingAdd {
            pendingAdd = nil
            await sync(justAdded: queued)
            return
        }
        guard let added else {
            lastResult = .failed(String(localized: "Couldn't reach your feeds — check your connection."))
            return
        }
        // Reported, but NOT returned on: the bridge is still connected and its
        // other feeds still landed — one address publishing nothing is a fact
        // about that address, not a failed sync.
        if let justAdded, FeedFreshness.noFeedFound(at: justAdded) {
            lastResult = .failed(String(localized: "No feed at that address — that page doesn't publish one."))
        } else {
            lastResult = .landed(added)
        }
        let proof = added > 0
            ? String(localized: "\(added) posts in")
            : String(localized: "Synced just now")
        store.registerConnected(id: "rss", name: "RSS", proof: proof,
                                can: ["Reads the feeds you follow."])
    }

    /// The other half of the bridge, kept fresh as the ledger changes — an
    /// export offered stale (missing a feed followed seconds ago) would be a
    /// small honesty gap in a screen whose whole pitch is "no server in
    /// between, nothing hidden."
    private func refreshExportURL() {
        guard !rss.feeds.isEmpty else { exportURL = nil; return }
        let data = OPMLImport.export(rss.feeds)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("casberi-feeds.opml")
        try? data.write(to: url, options: .atomic)
        exportURL = url
    }
}
