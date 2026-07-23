import SwiftUI
import SwiftData

/// The name-only bridges — connect by a public name alone (no password, no
/// token, nothing stored but the name), so their screens are the same shape.
/// Two families ride this one enum: the people bridges (Bluesky, Farcaster,
/// Pinterest), and the feed-follow bridges (Substack, Reddit, YouTube,
/// Podcasts), whose per-bridge words and URL rules live in `FeedFollowKind`.
/// This enum carries the words that differ, the way TokenBridge does for the
/// paste-a-token screens; the feed cases delegate to their kind.
enum HandleBridge: String {
    case bluesky   = "Bluesky"
    case farcaster = "Farcaster"
    case pinterest = "Pinterest"
    case substack  = "Substack"
    case reddit    = "Reddit"
    case youtube   = "YouTube"
    case podcasts  = "Podcasts"

    /// The feed-follow kind behind the four feed cases, nil for the people
    /// bridges — the join that lets each switch below fall through to one place.
    var feedKind: FeedFollowKind? { FeedFollowKind(rawValue: rawValue) }

    /// BridgeStore id, and the connected-strip route.
    var bridgeID: String {
        switch self {
        case .bluesky:   "bsky"
        case .farcaster: "fc"
        case .pinterest: "pinterest"
        default:         feedKind?.bridgeID ?? ""
        }
    }

    /// What the person types — Bluesky says handle, Farcaster says username.
    var nameNoun: String {
        switch self {
        case .bluesky:   "handle"
        case .farcaster, .pinterest: "username"
        default:         feedKind?.nameNoun ?? "name"
        }
    }

    var placeholder: String {
        switch self {
        case .bluesky:   "you"
        case .farcaster, .pinterest: "yourname"
        default:         feedKind?.placeholder ?? ""
        }
    }

    /// The fixed part of the name, shown around the field so the person
    /// types only what's theirs.
    var fieldPrefix: String? {
        switch self {
        case .farcaster: "farcaster.xyz/"
        case .pinterest: "pinterest.com/"
        default:         nil
        }
    }

    var fieldSuffix: String? {
        switch self {
        case .bluesky:   ".bsky.social"
        default:         nil
        }
    }

    /// Every bridge here but Pinterest watches a LIST — a small following feed,
    /// not just one mirror. Pinterest stays single (its feed is per-user).
    var supportsMultiple: Bool { self != .pinterest }

    /// The bridges whose field doubles as a finder: Bluesky/Farcaster people
    /// search, and Podcasts show search. Pinterest and the templated feeds
    /// (Substack/Reddit/YouTube) have no such surface — you type the name.
    var supportsSearch: Bool {
        self == .bluesky || self == .farcaster || self == .podcasts
    }

    func search(_ query: String) async -> [UserSearch.Hit] {
        switch self {
        case .bluesky:   await UserSearch.bluesky(query)
        case .farcaster: await UserSearch.farcaster(query)
        case .podcasts:  await FeedFetch.searchPodcasts(query)
        default:         []
        }
    }

    /// A tapped search hit connects like a typed name — plus, for Farcaster,
    /// the fid the search carried, or for Podcasts, the feed the search found.
    func add(hit: UserSearch.Hit) {
        switch self {
        case .bluesky:
            BlueskyStore.shared.add(hit.handle)
        case .farcaster:
            if let fid = hit.fid {
                FarcasterStore.shared.add(hit.handle, fid: fid)
            } else {
                FarcasterStore.shared.add(hit.handle)
            }
        case .podcasts:
            FeedFollowStore.podcasts.add(
                FeedFollowEntry(input: hit.displayName, feedURL: hit.feedURL ?? "", title: hit.displayName))
        default:
            break
        }
    }

    /// The connected accounts, for the list the multi-account screen shows.
    var names: [String] {
        switch self {
        case .bluesky:   return BlueskyStore.shared.handles
        case .farcaster: return FarcasterStore.shared.usernames
        case .pinterest:
            let u = PinterestStore.shared.username
            return u.isEmpty ? [] : [u]
        default:         return feedKind?.store.inputs ?? []
        }
    }

    /// The list row's short form — Bluesky's ".bsky.social" comes off; a feed
    /// follow shows its learned title (the publication's real name).
    func shortName(_ name: String) -> String {
        switch self {
        case .bluesky:
            name.hasSuffix(".bsky.social") ? String(name.dropLast(".bsky.social".count)) : name
        case .farcaster, .pinterest:
            name
        default:
            feedKind?.store.display(for: name) ?? name
        }
    }

    func addName(_ raw: String) {
        switch self {
        case .bluesky:   BlueskyStore.shared.add(raw)
        case .farcaster: FarcasterStore.shared.add(raw)
        case .pinterest: PinterestStore.shared.username = PinterestStore.normalize(raw)
        default:         feedKind?.store.add(FeedFollowEntry(input: raw))
        }
    }

    func removeName(_ name: String) {
        switch self {
        case .bluesky:   BlueskyStore.shared.remove(name)
        case .farcaster: FarcasterStore.shared.remove(name)
        case .pinterest: PinterestStore.shared.username = ""
        default:         feedKind?.store.remove(input: name)
        }
    }

    /// What the field shows for an existing connection — for the single
    /// bridge (Pinterest), the connected name; for the multi bridges the
    /// field is a fresh "add another", so it starts empty.
    var displayName: String {
        switch self {
        case .pinterest: return PinterestStore.shared.username
        default:         return ""
        }
    }

    /// What lands, for proof lines: "3 posts in".
    var noun: String {
        switch self {
        case .bluesky:   "posts"
        case .farcaster: "casts"
        case .pinterest: "pins"
        default:         feedKind?.noun ?? "things"
        }
    }

    var fieldFooter: String {
        switch self {
        case .bluesky:
            "Type a few letters to find someone, or the full handle — posts are public, so there's no password to give."
        case .farcaster:
            "Type a few letters to find someone, or the exact username — casts are public on the open protocol, so there's no password to give."
        case .pinterest:
            "Just the username — your public pins arrive through Pinterest's own feed, so there's no password to give."
        default:
            feedKind?.fieldFooter ?? ""
        }
    }

    var recentHeader: String {
        switch self {
        case .bluesky:   "Posts"
        case .farcaster: "Casts"
        case .pinterest: "Pins"
        default:         feedKind?.recentHeader ?? "Recent"
        }
    }

    var footerLine: String {
        switch self {
        case .bluesky:
            "Read-only, public data only. Likes arrive with sign-in, later."
        case .farcaster:
            "Read-only, public data only — served by the Farcaster team's own public node."
        case .pinterest:
            "Read-only, public boards only — secret boards never appear in the public feed."
        default:
            feedKind?.footerLine ?? ""
        }
    }

    var canLine: String {
        switch self {
        case .bluesky:   "Reads public posts — accounts, feeds, mentions."
        case .farcaster: "Reads public casts — accounts, channels, likes."
        case .pinterest: "Reads your public pins."
        default:         feedKind?.canLine ?? ""
        }
    }

    /// The social bridges (Bluesky, Farcaster) whose account rows carry a
    /// face, a bio, and watch toggles — the rich shared row. Others show the
    /// plain name row.
    var isRichSocial: Bool {
        switch self {
        case .bluesky, .farcaster: true
        default: false
        }
    }

    /// The watched accounts as the shared row renders them — read straight
    /// off each @Observable store, so a toggle or a landed profile updates
    /// the rows with nothing to snapshot.
    var socialAccounts: [SocialAccount] {
        switch self {
        case .bluesky:   BlueskyStore.shared.socialAccounts
        case .farcaster: FarcasterStore.shared.socialAccounts
        default:         []
        }
    }

    /// Flip a per-account watch toggle. A bridge ignores a kind it doesn't
    /// offer (Bluesky has no keyless likes), so the call is always safe.
    func setWatch(_ kind: SocialWatch.Kind, _ on: Bool, for name: String) {
        switch self {
        case .farcaster:
            switch kind {
            case .likes:    FarcasterStore.shared.setLikes(on, for: name)
            case .mentions: FarcasterStore.shared.setMentions(on, for: name)
            }
        case .bluesky:
            if kind == .mentions { BlueskyStore.shared.setMentions(on, for: name) }
        default: break
        }
    }

    /// The line under the watched-accounts list, explaining its toggles.
    var watchFooter: String? {
        switch self {
        case .farcaster: "Likes — also saves the casts an account has liked. Mentions — also saves casts that name them."
        case .bluesky:   "Mentions — also saves posts that name them, replies and quotes included."
        default:         nil
        }
    }

    /// Whether anything is connected — drives the "connected" chrome. For the
    /// multi bridges, the first watched account stands in.
    var currentName: String { names.first ?? "" }

    /// Connected at all — for Farcaster a followed CHANNEL, and for Bluesky a
    /// followed FEED (2026-07-16), still counts with no account at all: it
    /// syncs, it can disconnect. Everywhere else the account list is the whole
    /// story.
    var isConnected: Bool {
        switch self {
        case .farcaster: FarcasterStore.shared.connected
        case .bluesky:   BlueskyStore.shared.connected
        default:         !names.isEmpty
        }
    }

    /// Teardown only (the single Pinterest path + Disconnect): an empty name
    /// clears the connection. Multi-account adds go through `addName`.
    func setName(_ name: String) {
        switch self {
        case .bluesky:
            if name.isEmpty { BlueskyStore.shared.removeAll() } else { BlueskyStore.shared.add(name) }
        case .farcaster:
            if name.isEmpty { FarcasterStore.shared.removeAll() } else { FarcasterStore.shared.add(name) }
        case .pinterest:
            PinterestStore.shared.username = name
        default:
            guard let feedKind else { break }
            if name.isEmpty { feedKind.store.removeAll() }
            else { feedKind.store.add(FeedFollowEntry(input: name)) }
        }
    }

    func normalize(_ raw: String) -> String {
        switch self {
        case .bluesky:   BlueskyStore.normalize(raw)
        case .farcaster: FarcasterStore.normalize(raw)
        case .pinterest: PinterestStore.normalize(raw)
        default:         feedKind?.normalize(raw) ?? raw
        }
    }

    @MainActor
    func refresh(context: ModelContext) async -> Int? {
        switch self {
        case .bluesky:   return await BlueskyIngest.refresh(context: context)
        case .farcaster: return await FarcasterIngest.refresh(context: context)
        case .pinterest: return await PinterestIngest.refresh(context: context)
        default:
            guard let feedKind else { return nil }
            return await FeedFollowIngest.refresh(feedKind, context: context)
        }
    }
}

/// One screen for every handle-only bridge: state the way in plainly (a
/// public name, nothing else), then show it working.
///
/// REBUILT 2026-07-23 (prd §184) — the manager pattern the wallet screen
/// proved (prd §182) generalized to every watch-list bridge, with one split
/// the wallet didn't need: a face is a PERSON, so watched Farcaster/Bluesky
/// accounts ride a roster shelf exactly like watched addresses do (faces,
/// unbounded, one trailing "+" since there's no cap to draw); channels and
/// feeds are TOPICS, not people, so they stay a square-marked ledger below.
/// One omnibox both adds and searches — a leading "/" follows a topic on
/// Farcaster, plain text searches people (and, on Bluesky, feeds too). Every
/// per-account action (Likes/Mentions, watch-their-wallet, who-they-follow)
/// moved off the row and onto `SocialProfileCard`, reached by tapping a face —
/// the same card a post's byline already opens. The "what landed" preview is
/// gone; the feed already shows that, and a manager manages (prd §182's own
/// ruling, carried here).
struct HandleSetupScreen: View {
    let bridge: HandleBridge

    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    /// The one omnibox — finds a person (and, on Bluesky, a feed) as you
    /// type; on Farcaster a leading "/" follows a channel instead. Doubles as
    /// the single/multi bridges' plain add field.
    @State private var query = ""
    @State private var syncing = false
    @State private var result: String?
    @State private var resultIsError = false
    /// Bumped once when this screen first turns a connection live — the header
    /// icon coin-flips to acknowledge the handshake.
    @State private var connectFlip = 0
    /// Shown after a first connect, once: a one-tap way to the board where the
    /// new card just landed. Cleared on tap.
    @State private var showHomeHint = false

    /// The watched accounts (multi bridges) — a local snapshot refreshed on
    /// each add/remove, since the screen doesn't observe the store directly.
    @State private var accountNames: [String] = []

    /// Bluesky feed search results, riding the same omnibox as people —
    /// merged with `hits` for display (a feed has no typeable name, so the
    /// search IS the entry gesture, 2026-07-16).
    @State private var feedHits: [BlueskyStore.Feed] = []
    /// A chip toggled (or channel followed) while a sync is in flight —
    /// the finished sync runs once more instead of silently dropping it.
    @State private var resyncQueued = false

    /// People matching what's typed so far — the field doubles as a finder
    /// on the bridges with public search. Cleared on add and on emptying.
    @State private var hits: [UserSearch.Hit] = []

    /// The face tapped on the roster — opens the same profile card a post's
    /// byline does, carrying every per-account action.
    @State private var openProfile: SocialProfile?

    var body: some View {
        List {
            BridgeSetupHeader(name: bridge.rawValue,
                              connected: bridge.isConnected, flipTrigger: connectFlip)
            omniSection.listRowSeparator(.hidden)
            if bridge.isRichSocial {
                rosterSection
            } else if bridge.supportsMultiple, !accountNames.isEmpty {
                accountsSection.listRowSeparator(.hidden)
            }
            topicsSection
            if showHomeHint {
                seeInFeedSection.listRowSeparator(.hidden)
            }
            if bridge.isConnected {
                BridgeDisconnectSection(
                    bridgeID: bridge.bridgeID, name: bridge.rawValue,
                    teardown: {
                        bridge.setName("")
                        accountNames = []
                    }
                ).listRowSeparator(.hidden)
            }
            footerSection.listRowSeparator(.hidden)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .bridgeSetupWash(name: bridge.rawValue)
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .navigationTitle(bridge.rawValue)
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            accountNames = bridge.names
            query = bridge.displayName
            if bridge.isConnected {
                Task { await sync() }
            }
        }
        // The debounced omnibox search — people, and on Bluesky feeds too;
        // already-watched accounts stay out of the results, they're in the
        // roster above. A leading "/" on Farcaster is a channel name, not a
        // search, so it skips both.
        .task(id: query) {
            let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if bridge == .farcaster, q.hasPrefix("/") {
                hits = []
                return
            }
            async let peopleResult: [UserSearch.Hit]? = debouncedSearch(q, fetch: {
                guard bridge.supportsSearch else { return [] }
                let watched = Set(bridge.names)
                return await bridge.search(q)
                    .filter { !watched.contains(bridge.normalize($0.handle)) }
            })
            async let feedResult: [BlueskyStore.Feed]? = debouncedSearch(q, fetch: {
                guard bridge == .bluesky else { return [] }
                return await BlueskyIngest.searchFeeds(q)
            })
            if let p = await peopleResult { hits = p }
            if let f = await feedResult { feedHits = f }
        }
        .sheet(item: $openProfile) { p in
            SocialProfileCard(profile: p)
        }
    }

    /// Close the loop (delight 2026-07-14, repointed 2026-07-20 — the board
    /// this used to open onto is gone): the first connect ends with a
    /// one-tap way to the feed the new card just landed in — so a person
    /// sees where their connection went, instead of guessing. Every
    /// connected source always has a feed now (no more pin/hide to gate on),
    /// so this fires unconditionally on connect (see the call site below).
    private var seeInFeedSection: some View {
        Section {
            Button {
                showHomeHint = false
                FeedFilter.shared.source = bridge.rawValue
                FeedFilter.shared.tag = "All"
                HomeRoute.shared.path = []
                DSHaptic.tap()
            } label: {
                HStack(spacing: DS.Space.s2) {
                    Image(systemName: "list.bullet")
                    Text("See in Feed")
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DS.textTertiary)
                }
                .dsText(.body17).foregroundStyle(DS.tint)
                .contentShape(Rectangle())   // the whole row taps, not just the text
            }
            .buttonStyle(.plain)
            .dsListCardRow()
        }
    }

    /// The plain-name multi bridges' watched list (Substack, Reddit, YouTube,
    /// Podcasts) — the rich social bridges get a face roster instead
    /// (`rosterSection`), so this only ever renders the plain row now.
    private var accountsSection: some View {
        Section {
            ForEach(accountNames, id: \.self) { name in
                HStack(spacing: DS.Space.s3) {
                    BridgeIcon(name: bridge.rawValue, size: 28, circular: true)
                    Text(bridge.shortName(name)).dsText(.body17)
                        .foregroundStyle(DS.textPrimary)
                    Spacer()
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        bridge.removeName(name)
                        accountNames = bridge.names
                        DSHaptic.tap()
                    } label: { Label("Remove", systemImage: "minus.circle") }
                }
                .dsListCardRow()
                .listRowSeparator(.hidden)
            }
        } header: {
            Text(accountNames.count == 1 ? "Watching" : "Watching \(accountNames.count)")
                .dsText(.label12).foregroundStyle(DS.textTertiary)
        }
    }

    // MARK: - The roster (prd §184)

    /// Watched people as a shelf of faces — the wallet manager's own roster
    /// (prd §182), because a watched account is exactly the same shape as a
    /// watched address: an identity, not a topic. Unbounded (no cap to draw,
    /// unlike the wallet's five), so it scrolls, and it ends in a trailing
    /// "+" that focuses the omnibox rather than a ring of dashed empty slots.
    @ViewBuilder private var rosterSection: some View {
        if !bridge.socialAccounts.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.Space.s3) {
                        // Read straight off the @Observable store, so a
                        // landed avatar or a watch elsewhere re-renders with
                        // nothing to keep in step.
                        ForEach(bridge.socialAccounts) { account in
                            rosterFace(account)
                        }
                        addFaceSlot
                    }
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.vertical, DS.Space.s1)
                }
                Text(bridge.socialAccounts.count == 1
                     ? String(localized: "Watching 1 · tap a face for more")
                     : String(localized: "Watching \(bridge.socialAccounts.count) · tap a face for more"))
                    .dsText(.label12).foregroundStyle(DS.textTertiary)
                    .padding(.horizontal, DS.Space.s4)
            }
            .padding(.top, DS.Space.s1)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    /// One watched person's face — tap opens the same profile card a post's
    /// byline does (Likes/Mentions, watch-their-wallet, who-they-follow all
    /// live there now); long-press removes, the roster card's own gesture.
    private func rosterFace(_ account: SocialAccount) -> some View {
        VStack(spacing: 6) {
            if let avatar = account.avatarURL {
                RemoteThumb(urlString: avatar, size: 56, fallback: bridge.rawValue, circular: true)
            } else {
                BridgeIcon(name: bridge.rawValue, size: 56, circular: true)
            }
            VStack(spacing: 0) {
                Text(account.title)
                    .dsText(.label12).fontWeight(.semibold)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                Text(account.subtitle)
                    .dsText(.label12).foregroundStyle(DS.textTertiary)
                    .lineLimit(1)
            }
            .frame(height: 28, alignment: .top)
        }
        .frame(width: 74)
        .contentShape(Rectangle())
        .onTapGesture {
            DSHaptic.tap()
            openProfile = SocialProfile(source: bridge.rawValue, handle: account.key,
                                        displayName: account.title, bio: nil,
                                        avatarURL: account.avatarURL)
        }
        .contextMenu {
            Button(role: .destructive) {
                bridge.removeName(account.key)
                DSHaptic.tap()
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }

    /// A trailing "+" — no cap here, so it's an invitation rather than the
    /// wallet's literal empty slot, but the same honest door: it can't watch
    /// anyone without a name, so it focuses the omnibox.
    private var addFaceSlot: some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: DS.Radius.appIcon(56), style: .continuous)
                .strokeBorder(DS.textTertiary.opacity(0.35),
                             style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                .frame(width: 56, height: 56)
                .overlay {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(DS.textTertiary)
                }
            Text("Watch").dsText(.label12).foregroundStyle(DS.textTertiary)
                .frame(height: 28, alignment: .top)
        }
        .frame(width: 74)
    }

    // MARK: - Topics (prd §184)

    /// Channels (Farcaster) or feeds (Bluesky) — topics, not people, so they
    /// stay a square-marked ledger below the roster rather than joining it.
    @ViewBuilder private var topicsSection: some View {
        if bridge == .farcaster, !FarcasterStore.shared.channels.isEmpty {
            Section {
                ForEach(FarcasterStore.shared.channels) { channel in
                    topicRow(imageURL: channel.imageURL, title: "/\(channel.name)",
                            kind: String(localized: "Channel")) {
                        FarcasterStore.shared.removeChannel(channel.name)
                        DSHaptic.tap()
                    }
                }
            } header: {
                Text("Topics").dsText(.label12).foregroundStyle(DS.textTertiary)
            }
            .listRowSeparator(.hidden)
        }
        if bridge == .bluesky, !BlueskyStore.shared.feeds.isEmpty {
            Section {
                ForEach(BlueskyStore.shared.feeds) { feed in
                    topicRow(imageURL: feed.imageURL, title: feed.name,
                            kind: String(localized: "Feed")) {
                        BlueskyStore.shared.removeFeed(feed.uri)
                        DSHaptic.tap()
                    }
                }
            } header: {
                Text("Topics").dsText(.label12).foregroundStyle(DS.textTertiary)
            }
            .listRowSeparator(.hidden)
        }
    }

    /// One topic ledger row — a SQUARE mark (an image when there is one, else
    /// the bridge glyph), never round: the mark grammar ruling that reads a
    /// person from a topic at a glance across every ledger (prd §184).
    private func topicRow(imageURL: String?, title: String, kind: String,
                          remove: @escaping () -> Void) -> some View {
        HStack(spacing: DS.Space.s3) {
            if let imageURL, !imageURL.isEmpty {
                RemoteThumb(urlString: imageURL, size: 32, fallback: bridge.rawValue, circular: false)
            } else {
                BridgeIcon(name: bridge.rawValue, size: 32, circular: false)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).dsText(.body17).foregroundStyle(DS.textPrimary).lineLimit(1)
                Text(kind).dsText(.label12).foregroundStyle(DS.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .dsListCardRow()
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: remove) {
                Label("Remove", systemImage: "minus.circle")
            }
        }
        .listRowSeparator(.hidden)
    }

    // MARK: - The omnibox (prd §184)

    /// One field for both jobs: search-as-you-type for people (and, on
    /// Bluesky, feeds), or — on Farcaster, with a leading "/" — follow a
    /// channel by name. Replaces the old separate name/channel/feed fields.
    private var omniSection: some View {
        // Field + hits + status in ONE list row (a VStack) — a headed Section
        // of stacked rows leaks a hairline between them that row-level
        // .listRowSeparator(.hidden) won't suppress. Design law: no
        // hairlines, zero exceptions.
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                BridgeFieldRow(placeholder: bridge.placeholder, text: $query,
                               buttonLabel: omniButtonLabel,
                               prefix: bridge.fieldPrefix, suffix: bridge.fieldSuffix,
                               action: omniSubmit)
                ForEach(omniHits) { hit in
                    BridgeSearchResultRow(
                        imageURL: hit.imageURL, fallbackIcon: bridge.rawValue,
                        title: hit.title, subtitle: omniSubtitle(hit),
                        action: { pick(hit) })
                }
                BridgeSyncStatusRows(syncing: syncing,
                                     syncingLine: omniSyncingLine,
                                     result: result, resultIsError: resultIsError)
            }
            .dsListCardRow()
        } header: {
            Text(bridge.supportsMultiple ? "Add \(anArticle) \(bridge.nameNoun)"
                                         : "Your \(bridge.nameNoun)")
                .dsText(.label12).foregroundStyle(DS.textTertiary)
        } footer: {
            Text(LocalizedStringKey(omniFooter))
                .dsText(.callout15).foregroundStyle(DS.textTertiary)
        }
    }

    /// A search hit riding the omnibox — a person, or (Bluesky only) a feed,
    /// merged into one list so there's one row grammar to scan.
    private enum OmniHit: Identifiable {
        case person(UserSearch.Hit)
        case feed(BlueskyStore.Feed)
        var id: String {
            switch self {
            case .person(let h): return "p:\(h.handle)"
            case .feed(let f):   return "f:\(f.uri)"
            }
        }
        var imageURL: String? {
            switch self {
            case .person(let h): return h.avatarURL
            case .feed(let f):   return f.imageURL
            }
        }
        var title: String {
            switch self {
            case .person(let h): return h.displayName
            case .feed(let f):   return f.name
            }
        }
    }

    private func omniSubtitle(_ hit: OmniHit) -> String {
        switch hit {
        case .person(let h): return "@\(bridge.shortName(h.handle))"
        case .feed:           return String(localized: "Feed")
        }
    }

    private var omniHits: [OmniHit] {
        if bridge == .farcaster, query.hasPrefix("/") { return [] }
        return hits.map(OmniHit.person) + feedHits.map(OmniHit.feed)
    }

    private var omniButtonLabel: String {
        if bridge == .farcaster, query.hasPrefix("/") { return "Follow" }
        if bridge.supportsMultiple { return "Add" }
        return bridge.currentName.isEmpty ? "Connect" : "Update"
    }

    private var omniSyncingLine: String {
        if bridge == .farcaster, query.hasPrefix("/") {
            return String(localized: "Finding the channel…")
        }
        return String(localized: "Fetching \(bridge.noun)…")
    }

    /// The bridge's own field footer, plus one sentence naming the "/"
    /// route or the feed search — only where that route exists.
    private var omniFooter: String {
        switch bridge {
        case .farcaster:
            return bridge.fieldFooter + " A leading / follows a topic instead — /design, /base."
        case .bluesky:
            return bridge.fieldFooter + " Search also finds feeds — topic lanes someone curates."
        default:
            return bridge.fieldFooter
        }
    }

    private var anArticle: String {
        // By SOUND, not spelling — "a username" (yoo), like "a unicorn";
        // "u" in the vowel set printed "Add an username" (caught 2026-07-14).
        bridge.nameNoun.first.map { "aeio".contains($0) ? "an" : "a" } ?? "a"
    }

    private var footerSection: some View {
        Section {
            Text(LocalizedStringKey(bridge.footerLine))
                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                .listRowBackground(Color.clear)
        }
    }

    private func omniSubmit() {
        if bridge == .farcaster, query.hasPrefix("/") {
            followChannel()
        } else {
            connect()
        }
    }

    private func connect() {
        let name = bridge.normalize(query)
        guard !name.isEmpty else { return }
        if bridge.supportsMultiple {
            bridge.addName(name)
            accountNames = bridge.names
            query = ""          // the field is ready for the next one
        } else {
            bridge.setName(name)
            query = name
        }
        afterAdd()
    }

    /// A tapped search hit connects that account or follows that feed — same
    /// path as typing exactly, minus the typing.
    private func pick(_ hit: OmniHit) {
        switch hit {
        case .person(let h): pick(h)
        case .feed(let f):   followFeed(f)
        }
    }

    private func pick(_ hit: UserSearch.Hit) {
        bridge.add(hit: hit)
        accountNames = bridge.names
        query = ""
        afterAdd()
    }

    private func afterAdd() {
        hits = []
        DSHaptic.tap()
        Task { await sync() }
    }

    private func followChannel() {
        let raw = query.hasPrefix("/") ? String(query.dropFirst()) : query
        let name = FarcasterStore.normalizeChannel(raw)
        guard !name.isEmpty, !syncing else { return }
        syncing = true
        resultIsError = false
        Task {
            if await FarcasterIngest.followChannel(name) != nil {
                query = ""
                syncing = false
                DSHaptic.tap()
                await sync()
            } else {
                syncing = false
                result = String(localized: "Couldn't find that channel — check the name.")
                resultIsError = true
            }
        }
    }

    private func followFeed(_ feed: BlueskyStore.Feed) {
        BlueskyStore.shared.addFeed(feed)
        feedHits = []
        hits = []
        query = ""
        DSHaptic.tap()
        Task { await sync() }
    }

    private func sync() async {
        // A tap mid-sync (a channel follow, a feed pick) queues one more pass
        // instead of silently fetching nothing — the running sync took its
        // account snapshot before the change.
        guard !syncing else { resyncQueued = true; return }
        syncing = true
        let added = await bridge.refresh(context: modelContext)
        syncing = false
        if resyncQueued {
            resyncQueued = false
            await sync()
            return
        }
        guard let added else {
            // A channels-only Farcaster connection has no username to blame —
            // nil there is the node not answering, not a spelling.
            result = bridge == .farcaster && accountNames.isEmpty
                ? String(localized: "Couldn't reach Farcaster — try again.")
                : String(localized: "Couldn't find that \(bridge.nameNoun) — check the spelling.")
            resultIsError = true
            return
        }
        resultIsError = false
        result = added > 0 ? String(localized: "\(added) \(bridge.noun) in") : String(localized: "Up to date")
        let proof = added > 0 ? "\(added) \(bridge.noun) in" : "Synced just now"
        if store.registerConnected(id: bridge.bridgeID, name: bridge.rawValue,
                                   proof: proof, can: [bridge.canLine]) {
            // The first moment this connection goes live: the icon flips, the
            // haptic fires, and the loop-to-Home hint appears once.
            DSHaptic.success()
            withAnimation(DS.Motion.standard) {
                connectFlip += 1
                // Every connected source always has its own feed now (no
                // pin/hide to gate on) — the hint fires unconditionally.
                showHomeHint = true
            }
        }
    }
}
