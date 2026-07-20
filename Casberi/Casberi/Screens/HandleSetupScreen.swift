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
        default:         feedKind!.bridgeID
        }
    }

    /// What the person types — Bluesky says handle, Farcaster says username.
    var nameNoun: String {
        switch self {
        case .bluesky:   "handle"
        case .farcaster, .pinterest: "username"
        default:         feedKind!.nameNoun
        }
    }

    var placeholder: String {
        switch self {
        case .bluesky:   "you"
        case .farcaster, .pinterest: "yourname"
        default:         feedKind!.placeholder
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
        default:         return feedKind!.store.inputs
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
            feedKind!.store.display(for: name)
        }
    }

    func addName(_ raw: String) {
        switch self {
        case .bluesky:   BlueskyStore.shared.add(raw)
        case .farcaster: FarcasterStore.shared.add(raw)
        case .pinterest: PinterestStore.shared.username = PinterestStore.normalize(raw)
        default:         feedKind!.store.add(FeedFollowEntry(input: raw))
        }
    }

    func removeName(_ name: String) {
        switch self {
        case .bluesky:   BlueskyStore.shared.remove(name)
        case .farcaster: FarcasterStore.shared.remove(name)
        case .pinterest: PinterestStore.shared.username = ""
        default:         feedKind!.store.remove(input: name)
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
        default:         feedKind!.noun
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
            feedKind!.fieldFooter
        }
    }

    var recentHeader: String {
        switch self {
        case .bluesky:   "Posts"
        case .farcaster: "Casts"
        case .pinterest: "Pins"
        default:         feedKind!.recentHeader
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
            feedKind!.footerLine
        }
    }

    var canLine: String {
        switch self {
        case .bluesky:   "Reads public posts — accounts, feeds, mentions."
        case .farcaster: "Reads public casts — accounts, channels, likes."
        case .pinterest: "Reads your public pins."
        default:         feedKind!.canLine
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
            if name.isEmpty { feedKind!.store.removeAll() }
            else { feedKind!.store.add(FeedFollowEntry(input: name)) }
        }
    }

    func normalize(_ raw: String) -> String {
        switch self {
        case .bluesky:   BlueskyStore.normalize(raw)
        case .farcaster: FarcasterStore.normalize(raw)
        case .pinterest: PinterestStore.normalize(raw)
        default:         feedKind!.normalize(raw)
        }
    }

    @MainActor
    func refresh(context: ModelContext) async -> Int? {
        switch self {
        case .bluesky:   await BlueskyIngest.refresh(context: context)
        case .farcaster: await FarcasterIngest.refresh(context: context)
        case .pinterest: await PinterestIngest.refresh(context: context)
        default:         await FeedFollowIngest.refresh(feedKind!, context: context)
        }
    }
}

/// One screen for every handle-only bridge: state the way in plainly (a
/// public name, nothing else), then show it working.
struct HandleSetupScreen: View {
    let bridge: HandleBridge

    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @Environment(ShellChrome.self) private var chrome
    @State private var nameField = ""
    @State private var syncing = false
    @State private var result: String?
    @State private var resultIsError = false
    /// Bumped once when this screen first turns a connection live — the header
    /// icon coin-flips to acknowledge the handshake.
    @State private var connectFlip = 0
    /// Shown after a first connect, once: a one-tap way to the board where the
    /// new card just landed. Cleared on tap.
    @State private var showHomeHint = false

    /// This bridge's things — cached per appearance and after each sync, rather
    /// than re-fetched twice on every body pass. The source is per-bridge, so
    /// this is the cache path rather than a static @Query.
    @State private var recent: [Thing] = []
    /// The source's true thing count (not the capped preview) — names the
    /// recent section's header honestly.
    @State private var recentTotal = 0

    /// The watched accounts (multi bridges) — a local snapshot refreshed on
    /// each add/remove, since the screen doesn't observe the store directly.
    @State private var accountNames: [String] = []

    /// Farcaster's channel field (the account rows and channel list read
    /// the @Observable store directly — no snapshot to keep in step).
    @State private var channelField = ""
    @State private var channelSyncing = false
    @State private var channelError: String?
    /// Bluesky feed search results, awaiting a pick — a feed has no typeable
    /// name, so the search IS the entry gesture (2026-07-16).
    @State private var feedHits: [BlueskyStore.Feed] = []
    /// A chip toggled (or channel followed) while a sync is in flight —
    /// the finished sync runs once more instead of silently dropping it.
    @State private var resyncQueued = false

    /// The account whose follow graph the import sheet is showing, or nil
    /// (2026-07-16) — the handle doubles as the sheet's item, so opening it
    /// for a second account can't show the first one's list.
    @State private var followImport: FollowImportTarget?

    /// People matching what's typed so far — the field doubles as a finder
    /// on the bridges with public search. Cleared on add and on emptying.
    @State private var hits: [UserSearch.Hit] = []

    private func loadRecent() {
        recent = recentBridgeThings(source: bridge.rawValue, context: modelContext)
        // The TRUE total (a cheap COUNT), so the recent header names the whole
        // corpus for this source, not the 12-row preview it shows.
        let source = bridge.rawValue
        recentTotal = (try? modelContext.fetchCount(
            FetchDescriptor<Thing>(predicate: #Predicate { $0.source == source }))) ?? recent.count
    }

    var body: some View {
        List {
            BridgeSetupHeader(name: bridge.rawValue,
                              connected: bridge.isConnected, flipTrigger: connectFlip)
            nameSection.listRowSeparator(.hidden)
            if bridge.supportsMultiple, !accountNames.isEmpty {
                accountsSection.listRowSeparator(.hidden)
            }
            if bridge == .farcaster {
                channelsSection.listRowSeparator(.hidden)
            }
            if bridge == .bluesky {
                feedsSection.listRowSeparator(.hidden)
            }
            if !recent.isEmpty {
                RecentThingsSection(header: bridge.recentHeader, things: recent,
                                    total: recentTotal)
                    .listRowSeparator(.hidden)
            }
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
        .dsPageBackground()
        .navigationTitle(bridge.rawValue)
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            loadRecent()
            accountNames = bridge.names
            nameField = bridge.displayName
            if bridge.isConnected {
                Task { await sync() }
            }
        }
        // The debounced people search — already-watched accounts stay out of
        // the results; they're in the list above.
        .task(id: nameField) {
            guard bridge.supportsSearch else { return }
            let q = nameField.trimmingCharacters(in: .whitespacesAndNewlines)
            if let found = await debouncedSearch(q, fetch: {
                let watched = Set(bridge.names)
                return await bridge.search(q)
                    .filter { !watched.contains(bridge.normalize($0.handle)) }
            }) {
                hits = found
            }
        }
        .sheet(item: $followImport) { target in
            FollowImportSheet(source: target.source, handle: target.handle) { added in
                guard added > 0 else { return }
                accountNames = bridge.names
                Task { await sync() }   // their posts land now, not next foreground
            }
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
                HomeRoute.shared.push = nil
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

    /// The watched-accounts list. The rich social bridges (Bluesky,
    /// Farcaster) render `socialAccountRow` from the store's @Observable
    /// snapshot — face, display name, @handle · bio, and the watch toggles
    /// that bridge offers; every other multi bridge shows the plain name row.
    private var accountsSection: some View {
        Section {
            if bridge.isRichSocial {
                // Read straight off the @Observable store, so a toggle or a
                // landed profile re-renders with nothing to keep in step.
                ForEach(bridge.socialAccounts) { account in
                    socialAccountRow(account)
                }
            } else {
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
            }
        } header: {
            Text(accountNames.count == 1 ? "Watching" : "Watching \(accountNames.count)")
                .dsText(.label12).foregroundStyle(DS.textTertiary)
        } footer: {
            if let line = bridge.watchFooter {
                Text(LocalizedStringKey(line))
                    .dsText(.callout15).foregroundStyle(DS.textTertiary)
            }
        }
    }

    /// One watched social account: face, display name, @handle · bio, and
    /// the watch-more chips the bridge offers. Swipe to remove. Shared by
    /// Bluesky and Farcaster — the bridge answers what to show.
    private func socialAccountRow(_ account: SocialAccount) -> some View {
        HStack(alignment: .top, spacing: DS.Space.s3) {
            if let avatar = account.avatarURL {
                RemoteThumb(urlString: avatar, size: 36,
                            fallback: bridge.rawValue, circular: true)
            } else {
                BridgeIcon(name: bridge.rawValue, size: 36, circular: true)
            }
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text(account.title)
                    .dsText(.body17).foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                Text(account.subtitle)
                    .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                    .lineLimit(1)
                if !account.watches.isEmpty {
                    HStack(spacing: DS.Space.s2) {
                        ForEach(account.watches) { watch in
                            watchChip(watch, for: account.key)
                        }
                    }
                    .padding(.top, DS.Space.s1)
                }
                HStack(spacing: DS.Space.s2) {
                    // The wallet↔Farcaster join (2026-07-15): watch this
                    // account's verified onchain wallet — its holdings and
                    // activity land like any watched address. Farcaster only
                    // (Bluesky has no onchain verification); watch-only, so
                    // peeking is legitimate.
                    if bridge == .farcaster {
                        rowCapsule("wallet.pass", "Watch their wallet") {
                            watchWallet(for: account.key)
                        }
                    }
                    // Their follow graph as a picker (2026-07-16, prd 87).
                    // Both networks publish it keylessly, so on YOUR OWN
                    // watched account this is "bring in who I follow" — with
                    // no new notion of who you are, and no sign-in.
                    rowCapsule("person.2", "Who they follow") {
                        followImport = FollowImportTarget(source: bridge.rawValue,
                                                          handle: account.key)
                    }
                }
                .padding(.top, DS.Space.s1)
            }
            Spacer()
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                bridge.removeName(account.key)
                accountNames = bridge.names
                DSHaptic.tap()
            } label: { Label("Remove", systemImage: "minus.circle") }
        }
        .dsListCardRow()
        .listRowSeparator(.hidden)
    }

    /// The account row's quiet action, in chip clothes — the same capsule
    /// anatomy the watch chips wear, minus the lit state (these DO a thing
    /// rather than hold one).
    private func rowCapsule(_ icon: String, _ label: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DS.Space.s1) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                Text(LocalizedStringKey(label)).dsText(.label12)
            }
            .foregroundStyle(DS.textTertiary)
            .padding(.horizontal, DS.Space.s3)
            .frame(height: 28)
            .background(DS.gray100, in: Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// Resolves a watched Farcaster account's verified wallet and watches it —
    /// the first address not already watched, labeled with the handle. Reports
    /// the outcome honestly (no verified wallet, already watching, or watching).
    private func watchWallet(for username: String) {
        Task {
            let verified = await FarcasterIngest.verifiedEthAddresses(username: username)
            let alreadyWatched = Set(WalletStore.shared.addresses.map { $0.address.lowercased() })
            guard let address = verified.first(where: { !alreadyWatched.contains($0) }) else {
                if verified.isEmpty {
                    chrome.flash(String(localized: "No verified wallet for @\(username)."), tone: .failure)
                } else {
                    chrome.flash(String(localized: "Already watching @\(username)'s wallet."))
                }
                return
            }
            WalletStore.shared.add(address, label: "@\(username)")
            chrome.flash(String(localized: "Watching @\(username)'s wallet."), tone: .success)
        }
    }

    /// A lit-or-quiet capsule: on wears the tint, off stays gray — a switch
    /// that reads as one, in chip clothes (the tag-chip anatomy). The tap
    /// flips the bridge's setter and, when turning ON, fetches right away.
    private func watchChip(_ watch: SocialWatch, for key: String) -> some View {
        Button {
            bridge.setWatch(watch.kind, !watch.on, for: key)
            DSHaptic.tap()
            if !watch.on { Task { await sync() } }
        } label: {
            Text(LocalizedStringKey(watch.label))
                .dsText(.label12)
                .foregroundStyle(watch.on ? DS.tint : DS.textTertiary)
                .padding(.horizontal, DS.Space.s3)
                .frame(height: 28)
                .background(watch.on ? DS.tintDim : DS.gray100, in: Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// Followed channels (Farcaster only, 2026-07-14) — topic feeds beside
    /// the people. A name resolves against the channel directory; casts land
    /// the way an account's do.
    private var channelsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                BridgeFieldRow(placeholder: "design", text: $channelField,
                               buttonLabel: "Follow", prefix: "/",
                               action: followChannel)
                BridgeSyncStatusRows(syncing: channelSyncing,
                                     syncingLine: String(localized: "Finding the channel…"),
                                     result: channelError, resultIsError: true)
            }
            .dsListCardRow()
            ForEach(FarcasterStore.shared.channels) { channel in
                HStack(spacing: DS.Space.s3) {
                    if let image = channel.imageURL {
                        RemoteThumb(urlString: image, size: 28,
                                    fallback: bridge.rawValue, circular: true)
                    } else {
                        BridgeIcon(name: bridge.rawValue, size: 28, circular: true)
                    }
                    Text("/\(channel.name)").dsText(.body17)
                        .foregroundStyle(DS.textPrimary)
                    Spacer()
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        FarcasterStore.shared.removeChannel(channel.name)
                        DSHaptic.tap()
                    } label: { Label("Remove", systemImage: "minus.circle") }
                }
                .dsListCardRow()
                .listRowSeparator(.hidden)
            }
        } header: {
            Text("Channels").dsText(.label12).foregroundStyle(DS.textTertiary)
        } footer: {
            Text("A channel is a topic feed — /design, /base — followed by name, same as a person.")
                .dsText(.callout15).foregroundStyle(DS.textTertiary)
        }
    }

    /// Followed feeds (Bluesky only, 2026-07-16) — the answer to the question
    /// prd §75 deliberately held: Bluesky's channels. It has no global channel
    /// names to type, so its topical lanes are custom FEEDS, addressed by
    /// at-uri and found by search. That difference is the whole design: where
    /// Farcaster's field takes "/design" and resolves it, this one takes
    /// "science" and shows you what's there — the same finder gesture the name
    /// field above already uses for people. Once followed, a feed behaves
    /// exactly like a channel: its posts land beside the people's.
    private var feedsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                BridgeFieldRow(placeholder: "science", text: $channelField,
                               buttonLabel: "Find", action: searchFeeds)
                ForEach(feedHits) { feed in
                    BridgeSearchResultRow(
                        imageURL: feed.imageURL, fallbackIcon: bridge.rawValue,
                        title: feed.name, subtitle: String(localized: "Feed"),
                        action: { followFeed(feed) })
                }
                BridgeSyncStatusRows(syncing: channelSyncing,
                                     syncingLine: String(localized: "Finding feeds…"),
                                     result: channelError, resultIsError: true)
            }
            .dsListCardRow()
            ForEach(BlueskyStore.shared.feeds) { feed in
                HStack(spacing: DS.Space.s3) {
                    if let image = feed.imageURL {
                        RemoteThumb(urlString: image, size: 28,
                                    fallback: bridge.rawValue, circular: true)
                    } else {
                        BridgeIcon(name: bridge.rawValue, size: 28, circular: true)
                    }
                    Text(feed.name).dsText(.body17).foregroundStyle(DS.textPrimary)
                    Spacer()
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        BlueskyStore.shared.removeFeed(feed.uri)
                        DSHaptic.tap()
                    } label: { Label("Remove", systemImage: "minus.circle") }
                }
                .dsListCardRow()
                .listRowSeparator(.hidden)
            }
        } header: {
            Text("Feeds").dsText(.label12).foregroundStyle(DS.textTertiary)
        } footer: {
            Text("A feed is a topic lane someone curates — search a subject, follow one, its posts land beside the people's.")
                .dsText(.callout15).foregroundStyle(DS.textTertiary)
        }
    }

    private func searchFeeds() {
        let query = channelField.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !channelSyncing else { return }
        channelSyncing = true
        channelError = nil
        feedHits = []
        Task {
            let found = await BlueskyIngest.searchFeeds(query)
            channelSyncing = false
            feedHits = found
            if found.isEmpty {
                channelError = String(localized: "No feeds by that name.")
            }
        }
    }

    private func followFeed(_ feed: BlueskyStore.Feed) {
        BlueskyStore.shared.addFeed(feed)
        feedHits = []
        channelField = ""
        DSHaptic.tap()
        Task { await sync() }
    }

    private func followChannel() {
        let name = FarcasterStore.normalizeChannel(channelField)
        guard !name.isEmpty, !channelSyncing else { return }
        channelSyncing = true
        channelError = nil
        Task {
            if await FarcasterIngest.followChannel(name) != nil {
                channelField = ""
                channelSyncing = false
                DSHaptic.tap()
                await sync()
            } else {
                channelSyncing = false
                channelError = String(localized: "Couldn't find that channel — check the name.")
            }
        }
    }

    private var nameSection: some View {
        // Field + search hits + status in ONE list row (a VStack) — a headed
        // Section of stacked rows leaks a hairline between them that row-level
        // .listRowSeparator(.hidden) won't suppress (SwiftUI first-post-header
        // separator). Design law: no hairlines, zero exceptions.
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                BridgeFieldRow(placeholder: bridge.placeholder, text: $nameField,
                               buttonLabel: buttonLabel,
                               prefix: bridge.fieldPrefix, suffix: bridge.fieldSuffix,
                               action: connect)
                ForEach(hits) { hit in
                    BridgeSearchResultRow(
                        imageURL: hit.avatarURL, fallbackIcon: bridge.rawValue,
                        title: hit.displayName, subtitle: "@\(bridge.shortName(hit.handle))",
                        action: { pick(hit) })
                }
                BridgeSyncStatusRows(syncing: syncing,
                                     syncingLine: String(localized: "Fetching \(bridge.noun)…"),
                                     result: result, resultIsError: resultIsError,
                                     faces: proofFaces, faceFallback: bridge.rawValue)
            }
            .dsListCardRow()
        } header: {
            Text(bridge.supportsMultiple ? "Add \(anArticle) \(bridge.nameNoun)"
                                         : "Your \(bridge.nameNoun)")
                .dsText(.label12).foregroundStyle(DS.textTertiary)
        } footer: {
            Text(LocalizedStringKey(bridge.fieldFooter))
                .dsText(.callout15).foregroundStyle(DS.textTertiary)
        }
    }

    private var buttonLabel: String {
        if bridge.supportsMultiple { return "Add" }
        return bridge.currentName.isEmpty ? "Connect" : "Update"
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

    private func connect() {
        let name = bridge.normalize(nameField)
        guard !name.isEmpty else { return }
        if bridge.supportsMultiple {
            bridge.addName(name)
            accountNames = bridge.names
            nameField = ""          // the field is ready for the next one
        } else {
            bridge.setName(name)
            nameField = name
        }
        afterAdd()
    }

    /// A tapped search result connects that account — same path as typing
    /// the name exactly, minus the typing.
    private func pick(_ hit: UserSearch.Hit) {
        bridge.add(hit: hit)
        accountNames = bridge.names
        nameField = ""
        afterAdd()
    }

    private func afterAdd() {
        hits = []
        DSHaptic.tap()
        Task { await sync() }
    }

    private func sync() async {
        // A tap mid-sync (a chip, a channel follow) queues one more pass
        // instead of silently fetching nothing — the running sync took its
        // account snapshot before the toggle.
        guard !syncing else { resyncQueued = true; return }
        syncing = true
        let added = await bridge.refresh(context: modelContext)
        syncing = false
        loadRecent()
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

    /// Faces from what just landed — distinct authors, newest first, up to
    /// three — so the proof line shows who arrived, not only how many. Only
    /// the social bridges carry author avatars; the rest get an empty pile.
    private var proofFaces: [String] {
        guard bridge.isRichSocial else { return [] }
        var seen = Set<String>(), faces: [String] = []
        for t in recent {
            guard let a = t.authorAvatarURL, !a.isEmpty, seen.insert(a).inserted else { continue }
            faces.append(a)
            if faces.count == 3 { break }
        }
        return faces
    }

}
