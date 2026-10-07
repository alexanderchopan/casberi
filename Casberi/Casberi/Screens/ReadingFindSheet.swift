import SwiftUI
import SwiftData

/// READING'S FOLLOW (prd §1085), Markets' Add carried over: a tray with the
/// field at the bottom on glass, where the thumb is (prd §752).
///
/// Before you type: the sites you keep saving from and follow nothing at
/// (`ReadingRoom.suggestions`) — two saves or more in sixty days. Typing an
/// address offers that site. Following adds it to RSS, which finds the
/// site's feed on its next read (`FeedDiscovery`); a site that publishes none
/// is said so and left unfollowed. Its Search half is deleted (prd §1171):
/// the tray's search finds what you read, through Find.
///
/// Optional environment only: on Mac Catalyst a sheet's content is evaluated
/// where the presenter's `.environment` has not reached (prd §872).
struct ReadingFindSheet: View {
    /// After a follow landed and the tray closed (prd §1119): Apps takes the
    /// person to Reading's Subscriptions.
    var onTracked: (() -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(ShellChrome.self) private var chrome: ShellChrome?
    @Environment(BridgeStore.self) private var store: BridgeStore?

    @State private var query = ""
    @State private var suggestions: [ReadingRoom.Suggestion] = []
    @State private var followed: Set<String> = []
    @State private var following: String? = nil
    @State private var recents: [String] = []
    @FocusState private var fieldFocused: Bool

    private static let recentsKey = "reading.find.recents"

    var body: some View {
        DSTray(title: Following.Room.reading.verb,
               height: 640, detents: [.large]) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if trimmed.isEmpty { before } else { results }
                }
                .padding(.bottom, 96)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) { field }
        }
        .task { load() }
        .onAppear {
            fieldFocused = true
            #if DEBUG
            // `-readingQuery "<text>"` fills the field (prd §1085): a
            // simctl-booted simulator draws no keyboard to type with.
            if let q = UserDefaults.standard.string(forKey: "readingQuery") { query = q }
            // `-readingFollowNow YES` presses Follow on the typed site (prd
            // §1119): the whole first follow, headless, from Apps to the room.
            if UserDefaults.standard.bool(forKey: "readingFollowNow"),
               let site = ReadingRoom.site(in: query) {
                Task { await follow(site) }
            }
            #endif
        }
    }

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    // MARK: - The field

    private var field: some View {
        DSTraySearchField(placeholder: String(localized: "A site's address"),
                          text: $query, focus: $fieldFocused,
                          keyboard: .URL,
                          onSubmit: { remember(query) })
    }

    // MARK: - Before you type

    @ViewBuilder private var before: some View {
        if !suggestions.isEmpty {
            DSTrayHead(String(localized: "Sites you save from"))
            ForEach(suggestions, id: \.host) { s in
                siteRow(s.host, line: String(localized: "You saved \(s.count) lately"))
            }
        }
        if !recents.isEmpty {
            DSTrayHead(String(localized: "Recent"))
            ForEach(recents, id: \.self) { recent in
                Button {
                    query = recent
                } label: {
                    HStack(spacing: DS.Space.s3) {
                        Image(systemName: "clock.arrow.circlepath")
                            .dsGlyph(.subhead).foregroundStyle(DS.textTertiary)
                            .frame(width: DS.Face.rowCircle)
                        Text(verbatim: recent).dsText(.body17).foregroundStyle(DS.textPrimary)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowPress())
                .padding(.horizontal, DS.Space.s4)
            }
        }
        if suggestions.isEmpty && recents.isEmpty {
            footnote
        }
    }

    private var footnote: some View {
        DSFootnote(Text("Type a site's address to follow it. Sites you save from twice show here."))
            .padding(.horizontal, DS.Space.s4)
            .padding(.top, DS.Space.s4)
    }

    // MARK: - As you type

    @ViewBuilder private var results: some View {
        if let site = ReadingRoom.site(in: trimmed) {
            DSTrayHead(String(localized: "Follow"))
            siteRow(site, line: String(localized: "Its feed lands in Reading"))
        }
        if ReadingRoom.site(in: trimmed) == nil {
            footnote
        }
    }

    // MARK: - Rows

    private func siteRow(_ host: String, line: String) -> some View {
        let on = ReadingRoom.covered(host, by: followed)
        let busy = following == host
        return HStack(spacing: DS.Space.s3) {
            WatchFace(url: nil, lettered: host)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: host).dsText(.body17).foregroundStyle(DS.textPrimary).lineLimit(1)
                Text(verbatim: on ? String(localized: "Following") : line)
                    .dsText(.subhead12).foregroundStyle(DS.textTertiary).lineLimit(1)
            }
            Spacer(minLength: DS.Space.s2)
            if busy {
                DSSpinner(size: .small).frame(minWidth: 44, minHeight: 44)
            } else {
                Button {
                    Task { await follow(host) }
                } label: {
                    Image(systemName: on ? "checkmark" : "plus")
                        .dsGlyph(.title, weight: .regular)
                        .foregroundStyle(on ? DS.textTertiary : DS.tint)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressSpring())
                .disabled(on)
                .accessibilityLabel(Text(on ? String(localized: "Following \(host)")
                                            : String(localized: "Follow \(host)")))
            }
        }
        .frame(minHeight: 64)
        .padding(.horizontal, DS.Space.s4)
    }

    // MARK: - Following

    /// Adds the site to RSS, reads it once so the feed is found now, and says
    /// so either way: a site that publishes no feed is taken back out. A
    /// Substack goes to Substack's own list, so one publication is never
    /// followed twice through two apps (prd §1118). Following closes the tray
    /// onto the Subscriptions list it joined.
    private func follow(_ host: String) async {
        guard !DemoMode.isActive else {
            chrome?.flash(String(localized: "Following works once you leave the demo."))
            return
        }
        if host.hasSuffix(".substack.com") {
            await followSubstack(host)
            return
        }
        let rss = RSSStore.shared
        let address = "https://\(host)"
        guard rss.add(address, title: host) else { return }
        remember(host)
        following = host
        _ = await RSSIngest.refresh(context: modelContext, waitForInFlight: true)
        following = nil
        let normalized = rss.normalized(address) ?? address
        if FeedFreshness.noFeedFound(at: normalized),
           let index = rss.feeds.firstIndex(where: { $0.url.lowercased() == normalized.lowercased() }) {
            rss.remove(at: IndexSet(integer: index))
            chrome?.flash(String(localized: "\(host) doesn't publish a feed"), tone: .failure)
            return
        }
        followed.insert(host)
        chrome?.flash(String(localized: "Following \(host)"), tone: .success)
        store?.registerConnected(id: "rss", name: "RSS",
                                 proof: String(localized: "Synced just now"),
                                 can: ["Reads the feeds you follow."])
        landOnSubscriptions()
    }

    /// A Substack, through Substack's own list (`HandleBridge.substack`, the
    /// seat's page's add and sync).
    private func followSubstack(_ host: String) async {
        let bridge = HandleBridge.substack
        let input = FeedURL.substackInput(host)
        guard !FeedFollowStore.substack.inputs.contains(where: { $0.caseInsensitiveCompare(input) == .orderedSame })
        else { landOnSubscriptions(); return }
        remember(host)
        following = host
        bridge.addName(input)
        let added = await bridge.refresh(context: modelContext)
        following = nil
        guard added != nil else {
            FeedFollowStore.substack.remove(input: input)
            chrome?.flash(String(localized: "Couldn't reach \(host)"), tone: .failure)
            return
        }
        followed.insert(host)
        chrome?.flash(String(localized: "Following \(host)"), tone: .success)
        store?.registerConnected(id: bridge.bridgeID, name: bridge.rawValue,
                                 proof: String(localized: "Synced just now"), can: [bridge.canLine])
        landOnSubscriptions()
    }

    /// The tray closes onto the list the follow joined.
    private func landOnSubscriptions() {
        chrome?.readingScope = .subscriptions
        dismiss()
        onTracked?()
    }

    // MARK: - Reading

    private func load() {
        recents = UserDefaults.standard.data(forKey: Self.recentsKey)
            .flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
        let members = RoomAccounts.roomSources(RoomAccounts.readingRoom)
        var d = FetchDescriptor<Thing>(predicate: #Predicate<Thing> { members.contains($0.source) },
                                       sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        d.fetchLimit = 1_500
        let room = ((try? modelContext.fetch(d)) ?? []).filter(\.isLive)
        // What you already follow: every RSS feed's site, and the sites the
        // room's feed rows come from (Substack's publications among them).
        var hosts = Set(RSSStore.shared.feeds.compactMap { ReadingRoom.host(of: $0.url) })
        for thing in room where thing.source == "RSS" || thing.source == "Substack" {
            if let h = Self.link(of: thing).flatMap(ReadingRoom.host(of:)) { hosts.insert(h) }
        }
        followed = hosts
        // Saves: a link kept in a saving app, never a feed's own rows.
        let saves = room.filter { ReadingRoom.saveSources.contains($0.source) }
            .compactMap { thing in Self.link(of: thing).map { ReadingRoom.Save(url: $0, at: thing.capturedAt) } }
        suggestions = ReadingRoom.suggestions(saves: saves, followed: hosts, now: .now)
    }

    /// A row's link: its page, else its content when that is an address.
    private static func link(of thing: Thing) -> String? {
        if let page = thing.externalLink, !page.isEmpty { return page }
        let content = thing.content.trimmingCharacters(in: .whitespacesAndNewlines)
        return content.hasPrefix("http") ? content : nil
    }

    private func remember(_ raw: String) {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        recents = Array(([q] + recents.filter { $0.caseInsensitiveCompare(q) != .orderedSame }).prefix(5))
        if let data = try? JSONEncoder().encode(recents) {
            DefaultsWrite.set(data, forKey: Self.recentsKey)
        }
    }
}
