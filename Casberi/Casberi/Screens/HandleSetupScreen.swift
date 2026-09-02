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
    case nostr     = "Nostr"
    case pinterest = "Pinterest"
    case substack  = "Substack"
    case reddit    = "Reddit"
    case youtube   = "YouTube"
    case podcasts  = "Podcasts"
    case telegram  = "Telegram"

    /// Does this seat ALSO import an export you exported yourself?
    ///
    /// Telegram is the only one, and it is why this screen carries an import
    /// section at all (prd §456): following public channels and importing your
    /// own archive are two doors onto one product, so they belong on one seat
    /// rather than as two catalog tiles for the same app.
    var importsArchive: Bool { self == .telegram }

    /// The feed-follow kind behind the five feed cases, nil for the people
    /// bridges — the join that lets each switch below fall through to one place.
    var feedKind: FeedFollowKind? { FeedFollowKind(rawValue: rawValue) }

    /// BridgeStore id, and the connected-strip route.
    var bridgeID: String {
        switch self {
        case .bluesky:   "bsky"
        case .farcaster: "fc"
        case .nostr:     "nostr"
        case .pinterest: "pinterest"
        default:         feedKind?.bridgeID ?? ""
        }
    }

    /// What the person types — Bluesky says handle, Farcaster says username.
    var nameNoun: String {
        switch self {
        case .bluesky:   "handle"
        case .farcaster, .pinterest: "username"
        case .nostr:     "npub"
        default:         feedKind?.nameNoun ?? "name"
        }
    }

    var placeholder: String {
        switch self {
        case .bluesky:   "you"
        case .farcaster, .pinterest: "yourname"
        case .nostr:     "npub1… or name@domain"
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
        case .nostr:
            return NostrStore.shared.accounts.map { $0.pubkeyHex.isEmpty ? $0.input : $0.pubkeyHex }
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
        case .nostr:
            SocialThread.shortHandle(name)
        case .farcaster, .pinterest:
            name
        default:
            feedKind?.store.display(for: name) ?? name
        }
    }

    /// What a followed feed's row should say when the feed itself has stopped
    /// answering (2026-08-05) — nil for the people bridges, which fetch an API
    /// rather than a feed, and nil for a feed with nothing to report.
    ///
    /// Keyed on the RESOLVED feed URL, so a follow that never got past
    /// resolution (a YouTube handle whose channel page never answered, a
    /// podcast search that found no show) reports nothing here — it has never
    /// fetched a feed to have a health record for. That case reads as an
    /// unchanging list rather than a failing feed, which is honest: nothing
    /// about the feed is known.
    func feedTrouble(_ name: String) -> String? {
        guard let kind = feedKind,
              let entry = kind.store.entries.first(where: {
                  $0.input.caseInsensitiveCompare(name) == .orderedSame
              }),
              !entry.feedURL.isEmpty
        else { return nil }
        return FeedFreshness.trouble(for: entry.feedURL)
    }

    func addName(_ raw: String) {
        switch self {
        case .bluesky:   BlueskyStore.shared.add(raw)
        case .farcaster: FarcasterStore.shared.add(raw)
        case .nostr:     NostrStore.shared.add(raw)
        case .pinterest: PinterestStore.shared.username = PinterestStore.normalize(raw)
        default:         feedKind?.store.add(FeedFollowEntry(input: raw))
        }
    }

    /// Unfollowing takes their posts with it (user ruling, 2026-08-02: "if
    /// you unfollow something it shouldn't show in your corpus", prd §286).
    /// This used to only edit the store's own list, so an account or feed you
    /// removed went on filling the feed forever with no way to clear it short
    /// of Delete everything.
    ///
    /// The identity is resolved BEFORE the store mutates — Nostr's rows are
    /// keyed on the resolved pubkey hex while `remove` accepts either that or
    /// what was typed, so reading it afterwards would find nothing to match.
    @MainActor
    func removeName(_ name: String, context: ModelContext) {
        // `rawValue` IS the source name on every case here.
        let source = rawValue
        var handle = name
        var remainingTopics: [String] = []

        switch self {
        case .bluesky:
            remainingTopics = BlueskyStore.shared.feeds.map(\.name)
            BlueskyStore.shared.remove(name)
        case .farcaster:
            remainingTopics = FarcasterStore.shared.channels.map(\.name)
            FarcasterStore.shared.remove(name)
        case .nostr:
            handle = NostrStore.shared.accounts.first {
                $0.input == name || $0.pubkeyHex == name
            }?.pubkeyHex ?? name
            remainingTopics = NostrStore.shared.hashtags.map(\.tag)
            NostrStore.shared.remove(name)
        case .pinterest:
            handle = PinterestStore.shared.username
            PinterestStore.shared.username = ""
        default:
            // A feed item carries the FEED'S name in `authorHandle`, not the
            // URL that was typed — resolve the display name while the entry
            // still exists.
            handle = feedKind?.store.display(for: name) ?? name
            feedKind?.store.remove(input: name)
        }

        SocialTopics.pruneAuthor(source: source, handle: handle,
                                 remainingTopics: remainingTopics, context: context)
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
        case .nostr:     "notes"
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
        case .nostr:
            "Paste an npub, a raw hex pubkey, or a name@domain identifier — notes are public on the open protocol, so there's no password to give and nothing to search (Nostr has no directory)."
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
        case .nostr:     "Notes"
        case .pinterest: "Pins"
        default:         feedKind?.recentHeader ?? "Recent"
        }
    }

    /// The connect screen's one sentence (prd §315). Replaced `footerLine`,
    /// which carried the same facts at the bottom of the screen in the tier
    /// `DesignTokens` reserves for timestamps. Each says the mode's
    /// consequence, then the payoff, then — only where it would otherwise
    /// read as a bug — the one thing that can never arrive.
    var setupIntro: String {
        switch self {
        case .bluesky:
            String(localized: "Name someone and their posts arrive, straight from Bluesky's public API. What they like needs a sign-in, which is coming later.")
        case .farcaster:
            String(localized: "Name someone and their casts arrive, from the Farcaster team's own public node. Channels and mentions of you can be followed too.")
        case .nostr:
            String(localized: "Name someone and their notes arrive from whichever public relays this \(DS.device) can reach. Nothing here can ever post.")
        case .pinterest:
            String(localized: "Name someone and their public pins arrive. A secret board never appears in Pinterest's own feed, so it can never appear here.")
        default:
            feedKind?.setupIntro ?? ""
        }
    }

    var canLine: String {
        switch self {
        case .bluesky:   "Reads public posts — accounts, feeds, mentions."
        case .farcaster: "Reads public casts — accounts, channels, likes."
        case .nostr:     "Reads public notes — accounts, hashtags, reactions."
        case .pinterest: "Reads your public pins."
        default:         feedKind?.canLine ?? ""
        }
    }

    /// The social bridges (Bluesky, Farcaster, Nostr) whose account rows
    /// carry a face, a bio, and watch toggles — the rich shared row. Others
    /// show the plain name row.
    var isRichSocial: Bool {
        switch self {
        case .bluesky, .farcaster, .nostr: true
        default: false
        }
    }

    /// The watched accounts as the shared row renders them — read straight
    /// off each @Observable store, so a toggle or a landed profile updates
    /// the rows with nothing to snapshot.
    @MainActor
    var socialAccounts: [SocialAccount] {
        switch self {
        case .bluesky:   BlueskyStore.shared.socialAccounts
        case .farcaster: FarcasterStore.shared.socialAccounts
        case .nostr:     NostrStore.shared.socialAccounts
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
            case .recasts:  FarcasterStore.shared.setRecasts(on, for: name)
            case .mentions: FarcasterStore.shared.setMentions(on, for: name)
            case .mine:     FarcasterStore.shared.setMine(on, for: name)
            }
        case .nostr:
            switch kind {
            case .likes:    NostrStore.shared.setLikes(on, for: name)
            case .mentions: NostrStore.shared.setMentions(on, for: name)
            case .recasts:  break   // NIP-18 reposts aren't read yet
            case .mine:     break   // no inbound reads on Nostr yet
            }
        case .bluesky:
            switch kind {
            case .recasts:  BlueskyStore.shared.setRecasts(on, for: name)
            case .mentions: BlueskyStore.shared.setMentions(on, for: name)
            case .mine:     BlueskyStore.shared.setMine(on, for: name)
            case .likes:    break   // getActorLikes is auth-only — no keyless read
            }
        default: break
        }
    }

    /// The line under the watched-accounts list, explaining its toggles.
    ///
    /// Rewritten 2026-08-07 (prd §331). It used to end "and likes bring your
    /// posts back", which described the ONE thing a like did — resurface the
    /// post — and that only fired when the liker was already an account you
    /// watch, so for almost every like it promised something that never
    /// happened. It never said you would see WHO, because until §330 you
    /// couldn't. Now it names the three reads plainly, in the order they
    /// matter.
    var watchFooter: String? {
        switch self {
        case .farcaster, .bluesky:
            "Mine — this account is yours: who liked your posts, who replied, and who started following."
        case .nostr:     nil
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
        case .nostr:     NostrStore.shared.connected
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
        case .nostr:
            if name.isEmpty { NostrStore.shared.removeAll() } else { NostrStore.shared.add(name) }
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
        case .nostr:     NostrStore.normalize(raw)
        case .pinterest: PinterestStore.normalize(raw)
        default:         feedKind?.normalize(raw) ?? raw
        }
    }

    @MainActor
    func refresh(context: ModelContext) async -> Int? {
        switch self {
        case .bluesky:   return await BlueskyIngest.refresh(context: context)
        case .farcaster: return await FarcasterIngest.refresh(context: context)
        case .nostr:     return await NostrIngest.refresh(context: context)
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
    // This window's filter and stack (per-window since `SceneState`).
    @Environment(FeedFilter.self) private var filter
    @Environment(HomeRoute.self) private var route
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

    /// The followed list as an OPML file, for the four feed bridges. nil for
    /// the people bridges (there is no feed to hand anyone) and until a follow
    /// resolves — see `refreshExportURL`.
    @State private var exportURL: URL?
    // The import half (Telegram only — see `HandleBridge.importsArchive`).
    @State private var importing = false
    @State private var importResult: String?
    @State private var importIsError = false
    @State private var importHeld = 0
    @State private var importStaleness: String?

    var body: some View {
        List {
            BridgeSetupHeader(name: bridge.rawValue,
                              mode: .noAccount, intro: bridge.setupIntro,
                              connected: bridge.isConnected, flipTrigger: connectFlip)
            // The way back to your things (§460).
            if bridge.isConnected {
                RoomDoor(name: bridge.rawValue, source: bridge.rawValue)
                    .listRowSeparator(.hidden)
            }
            omniSection.listRowSeparator(.hidden)
            if bridge.isRichSocial {
                rosterSection
            } else if bridge.supportsMultiple, !accountNames.isEmpty {
                accountsSection.listRowSeparator(.hidden)
            }
            // Starter packs (item 4, 2026-07-27) — Bluesky's own curated-list
            // discovery, the honest fix to `FollowImportSheet`'s problem: a
            // real follow graph runs to thousands, too many to picker through
            // one checkbox at a time. Its own child view owns its `.sheet`
            // (not chained onto this screen's body) — a SECOND `.sheet`
            // modifier stacked on the same view is exactly what broke
            // `FeedScreen`'s first tap once (see its `FeedSheetRoute` doc
            // comment); isolating it in a subview sidesteps that class
            // entirely rather than re-risking it here.
            if bridge == .bluesky {
                StarterPacksDoor(onImport: { _ in Task { await sync() } })
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            } else if bridge == .farcaster {
                // Farcaster's own pack (2026-08-08) — a pinned list, not a
                // browse endpoint (Farcaster's client API has none keyless;
                // see `FarcasterStarterPack`'s doc comment), so this door
                // opens straight to a face grid instead of a search field.
                FarcasterPackDoor(onImport: { _ in Task { await sync() } })
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            if bridge.importsArchive {
                archiveSection.listRowSeparator(.hidden)
                ImportUpkeepSection(source: bridge.rawValue, held: importHeld,
                                    staleness: importStaleness) { _ in rereadImport() }
                    .listRowSeparator(.hidden)
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
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .bridgeSetupWash(name: bridge.rawValue)
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .dsScreenTitle(bridge.rawValue)
        // The list changing is the cheap trigger; a finished sync is the other
        // one, since that is when an entry's feed URL actually resolves (a
        // follow added seconds ago has a name and no address yet).
        .onChange(of: accountNames) { _, _ in refreshExportURL() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.folder]) { result in
            guard case .success(let url) = result else { return }
            Task { await runImport(url) }
        }
        .onAppear {
            accountNames = bridge.names
            refreshExportURL()
            if bridge.importsArchive { rereadImport() }
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
                filter.source = bridge.rawValue
                filter.tag = "All"
                // This screen can be RAISED as the connect sheet (prd §219),
                // and `path` is the stack behind it — so close the sheet too,
                // or the feed we just navigated to sits under a form that's
                // still on top of it.
                route.closeConnectForm()
                route.path = []
                DSHaptic.tap()
            } label: {
                HStack(spacing: DS.Space.s2) {
                    Image(systemName: "list.bullet")
                    Text("See in feed")
                    Spacer()
                    Image(systemName: "arrow.right")
                        .dsGlyph(13)
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
                    BridgeIcon(name: bridge.rawValue, size: DS.Face.row, circular: true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(bridge.shortName(name)).dsText(.body17)
                            .foregroundStyle(DS.textPrimary)
                            .lineLimit(1)
                        // A followed feed that has stopped answering says so —
                        // the RSS ledger's own line (2026-08-05). Silent
                        // otherwise, so the row keeps its plain shape; there
                        // is no subline to demote here, unlike RSS's URL.
                        if let trouble = bridge.feedTrouble(name) {
                            Text(trouble)
                                .dsText(.label12).foregroundStyle(DS.attention)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        bridge.removeName(name, context: modelContext)
                        accountNames = bridge.names
                        DSHaptic.tap()
                    } label: { Label("Remove", systemImage: "minus.circle") }
                }
                // A swipe has no Mac-mouse equivalent — right-click mirrors it
                // (Mac polish, 2026-07-28).
                .contextMenu {
                    Button(role: .destructive) {
                        bridge.removeName(name, context: modelContext)
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
                RemoteThumb(urlString: avatar, size: DS.Face.shelf, fallback: bridge.rawValue, circular: true)
            } else {
                BridgeIcon(name: bridge.rawValue, size: DS.Face.shelf, circular: true)
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
            .frame(minHeight: 28, alignment: .top)
        }
        .frame(width: 74)
        .contentShape(Rectangle())
        .onTapGesture {
            DSHaptic.tap()
            openProfile = SocialProfile(source: bridge.rawValue, handle: account.key,
                                        displayName: account.title, bio: nil,
                                        avatarURL: account.avatarURL)
        }
        .dsTapCard()
        .contextMenu {
            Button(role: .destructive) {
                bridge.removeName(account.key, context: modelContext)
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
                        .dsGlyph(16)
                        .foregroundStyle(DS.textTertiary)
                }
            Text("Watch").dsText(.label12).foregroundStyle(DS.textTertiary)
                .frame(minHeight: 28, alignment: .top)
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
                        // Unfollowing takes the channel's casts with it —
                        // leaving them made the feed unfixable short of
                        // Delete everything (prd §286).
                        SocialTopics.pruneTopic(
                            source: "Farcaster", channel: channel.name,
                            watchedHandles: FarcasterStore.shared.usernames,
                            context: modelContext)
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
                        // Keyed on the feed's NAME, not its uri — `landFeed`
                        // stores `channel: feed.name` (prd §286).
                        SocialTopics.pruneTopic(
                            source: "Bluesky", channel: feed.name,
                            watchedHandles: BlueskyStore.shared.handles,
                            context: modelContext)
                        DSHaptic.tap()
                    }
                }
            } header: {
                Text("Topics").dsText(.label12).foregroundStyle(DS.textTertiary)
            }
            .listRowSeparator(.hidden)
        }
        if bridge == .nostr, !NostrStore.shared.hashtags.isEmpty {
            Section {
                ForEach(NostrStore.shared.hashtags) { hashtag in
                    topicRow(imageURL: nil, title: "#\(hashtag.tag)",
                            kind: String(localized: "Hashtag")) {
                        NostrStore.shared.removeHashtag(hashtag.tag)
                        // Nostr keys `authorHandle` on the pubkey hex, so the
                        // watched set is the resolved keys (prd §286).
                        SocialTopics.pruneTopic(
                            source: "Nostr", channel: hashtag.tag,
                            watchedHandles: NostrStore.shared.accounts.map(\.pubkeyHex),
                            context: modelContext)
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
                BridgeIcon(name: bridge.rawValue, size: DS.Mark.list, circular: false)
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
        // A swipe has no Mac-mouse equivalent — right-click mirrors it
        // (Mac polish, 2026-07-28).
        .contextMenu {
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
        // The slab, its hits, its status, and the screen's ONE sentence (prd
        // §190). The section header ("Add a username") went with the
        // furniture: the field's own placeholder already says what to type,
        // and the slab's verb says what happens.
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                DSSlabField(placeholder: fieldPlaceholder, text: $query,
                            actionLabel: omniButtonLabel, action: omniSubmit)
                ForEach(omniHits) { hit in
                    BridgeSearchResultRow(
                        imageURL: hit.imageURL, fallbackIcon: bridge.rawValue,
                        title: hit.title, subtitle: omniSubtitle(hit),
                        action: { pick(hit) })
                }
                BridgeSyncStatusRows(syncing: syncing,
                                     syncingLine: omniSyncingLine,
                                     result: result, resultIsError: resultIsError)
                DSSlabNote(text: omniNote)
                exportLink
            }
        }
        .dsSlabSection()
    }

    /// The off-ramp (2026-08-06).
    ///
    /// These four follows are RSS underneath — every one resolves to a feed
    /// URL — but OPML lived on the RSS screen alone, so a list of forty
    /// YouTube channels collected over a year could not leave. §309 made
    /// reversibility the standard for the import rooms; a follow list is the
    /// same promise.
    ///
    /// Export only, deliberately, where RSS has both. An OPML file's outlines
    /// are feed URLs, and this screen's grammar is a NAME (`@handle`, `r/sub`,
    /// a show to search) that the app resolves — importing raw feed URLs here
    /// would put entries in the store that no name explains, which is exactly
    /// the state `YouTubeFollowRepair` exists to clean up. Feed URLs already
    /// have a front door: the RSS screen imports them.
    ///
    /// Secondary, not a second slab — this screen's one verb is following.
    @ViewBuilder private var exportLink: some View {
        if let exportURL {
            ShareLink(item: exportURL) {
                Text("Export as OPML")
                    .dsText(.subhead13).foregroundStyle(DS.tint)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded { DSHaptic.tap() })
        }
    }

    /// Kept fresh as the list changes — an export offered stale (missing a
    /// channel followed seconds ago) is a small honesty gap on a screen whose
    /// whole pitch is that nothing sits between you and the feed. nil until at
    /// least one follow has RESOLVED: an unresolved entry is left out of the
    /// file (see `OPMLImport.export`), so a list of only those has nothing to
    /// write and offers no link rather than an empty document.
    // MARK: - The archive half (Telegram only, prd §456)

    /// Following channels is live and ongoing; importing your export is a
    /// one-time act on a file. Both are Telegram, so both live on this seat —
    /// the import sits BELOW the follow field because a channel needs nothing
    /// but a name, while the export needs you to go and generate one first.
    @ViewBuilder private var archiveSection: some View {
        Section {
            ImportArchiveSection(
                source: bridge.rawValue,
                // Telegram Desktop exports from inside the app itself — there
                // is no web page to send anyone to, so this screen names no
                // door (the Snapchat/TikTok shape).
                doorTitle: nil,
                steps: [
                    String(localized: "Open Telegram Desktop on a computer"),
                    String(localized: "Settings → Advanced → Export Telegram data"),
                    String(localized: "Choose JSON as the format, then export"),
                    String(localized: "Bring the unzipped folder here")
                ],
                pickTitle: String(localized: "Choose folder"),
                alreadyImported: importHeld > 0,
                showsMessagesToggle: true
            ) { importing = true }
            BridgeSyncStatusRows(result: importResult, resultIsError: importIsError)
        }
        .dsSlabSection()
    }

    private func rereadImport() {
        importHeld = ImportRemoval.count(source: bridge.rawValue, context: modelContext)
        importStaleness = ImportRemoval.stalenessLine(source: bridge.rawValue,
                                                      context: modelContext)
    }

    private func runImport(_ url: URL) async {
        // The scoped grant is the SCREEN's, held across the whole read — the
        // importer awaits inside it, which is safe for the reason
        // `ImportCommit` records: `defer` fires on return, not on suspend.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let summary = await TelegramImport.run(folder: url, context: modelContext)
        if summary.failed {
            importIsError = true
            importResult = summary.reason ?? String(localized: "Couldn't read that folder — is it the unzipped export?")
            return
        }
        importIsError = false
        DSHaptic.success()
        importResult = summary.landedLine
        rereadImport()
        store.registerConnected(id: bridge.bridgeID, name: bridge.rawValue,
                                proof: summary.landedLine, can: [bridge.canLine])
    }

    private func refreshExportURL() {
        guard let kind = bridge.feedKind else { exportURL = nil; return }
        let resolved = kind.store.entries.filter { !$0.feedURL.isEmpty }
        guard !resolved.isEmpty else { exportURL = nil; return }
        let data = OPMLImport.export(resolved, listName: "Casberi \(kind.source)")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("casberi-\(kind.bridgeID).opml")
        guard (try? data.write(to: url, options: .atomic)) != nil else { exportURL = nil; return }
        exportURL = url
    }

    /// The field's own words. `BridgeFieldRow`'s fixed affixes are gone with
    /// it (prd §190) — a slab holds one input, and "farcaster.xyz/" wrapped
    /// around a field was a third shape inside the second one. The affix
    /// becomes part of the placeholder, which reads the same and draws less.
    private var fieldPlaceholder: String {
        if bridge == .farcaster { return String(localized: "@name, or /channel") }
        if bridge == .bluesky { return String(localized: "Handle, or search a feed") }
        if bridge == .nostr { return String(localized: "npub, hex, name@domain, or #hashtag") }
        if let prefix = bridge.fieldPrefix { return prefix + bridge.placeholder }
        if let suffix = bridge.fieldSuffix { return bridge.placeholder + suffix }
        return bridge.placeholder
    }

    /// The one sentence — the shortest true version of what the three
    /// footers said. Everything longer moved to the catalog page the person
    /// arrived from, which already carries this bridge's full promise.
    private var omniNote: String {
        switch bridge {
        case .bluesky, .farcaster, .nostr:
            return String(localized: "Public posts only — no password, ever.")
        case .pinterest:
            return String(localized: "Public pins only — no password, ever.")
        default:
            return String(localized: "Read-only — new \(bridge.noun) land in your feed.")
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
        if bridge == .nostr, query.hasPrefix("#") { return [] }
        return hits.map(OmniHit.person) + feedHits.map(OmniHit.feed)
    }

    /// The slab's verb, in sentence case like every other field slab's.
    ///
    /// §190 made these verbs CONSISTENT and this one was the odd sentence-case
    /// label out; 2026-08-22 made them consistent the other way, because §190
    /// rules on slab SHAPE and never on case, while build-brief §8 is the law
    /// and has no ALL-CAPS anything. `allcaps-audit.py` holds all of them
    /// there now — including this property, which no call site can speak for
    /// since the verb is composed here across four branches.
    private var omniButtonLabel: String {
        if bridge == .farcaster, query.hasPrefix("/") { return "Follow" }
        if bridge == .nostr, query.hasPrefix("#") { return "Follow" }
        if bridge.supportsMultiple { return "Add" }
        return bridge.currentName.isEmpty ? "Connect" : "Update"
    }

    private var omniSyncingLine: String {
        if bridge == .farcaster, query.hasPrefix("/") {
            return String(localized: "Finding the channel…")
        }
        if bridge == .nostr, query.hasPrefix("#") {
            return String(localized: "Following the hashtag…")
        }
        return String(localized: "Fetching \(bridge.noun)…")
    }

    private func omniSubmit() {
        if bridge == .farcaster, query.hasPrefix("/") {
            followChannel()
        } else if bridge == .nostr, query.hasPrefix("#") {
            followHashtag()
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

    /// A leading "#" follows a Nostr hashtag instead of watching a person —
    /// no resolve step needed (unlike a Farcaster channel name, a hashtag is
    /// just itself), so this only ever normalizes and adds.
    private func followHashtag() {
        let raw = query.hasPrefix("#") ? String(query.dropFirst()) : query
        let tag = NostrStore.normalizeHashtag(raw)
        guard !tag.isEmpty else { return }
        NostrIngest.followHashtag(tag)
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
        // A sync is where a follow's feed URL resolves, and the export is
        // built from resolved URLs — so the link appears (or grows) here, not
        // at the moment the name was typed.
        refreshExportURL()
        if resyncQueued {
            resyncQueued = false
            await sync()
            return
        }
        guard let added else {
            // nil is "nothing was reachable", and for the four feed-follow
            // bridges that is usually not a spelling mistake. A follow whose
            // feed URL is already stored has PROVED its name: for YouTube the
            // channel page answered and named its own id, for the others the
            // URL is a template over what was typed. So when nothing reached
            // and something is resolved, the host refused us — YouTube
            // answers a throttled client a plain 404 or 500 (measured, see
            // `FeedFollowIngest.fetchAndParse`) — and the follow is saved,
            // will be retried on the next pass, and will fill in. Blaming the
            // spelling there sends somebody to delete a follow that works.
            //
            // A channels-only Farcaster connection has no username to blame
            // either — nil there is the node not answering.
            if let kind = bridge.feedKind,
               kind.store.entries.contains(where: { !$0.feedURL.isEmpty }) {
                result = String(localized: "Saved — \(bridge.rawValue) didn't answer just now. It'll fill in on the next refresh.")
            } else if bridge == .farcaster, accountNames.isEmpty {
                result = String(localized: "Couldn't reach Farcaster — try again.")
            } else {
                result = String(localized: "Couldn't find that \(bridge.nameNoun) — check the spelling.")
            }
            resultIsError = true
            return
        }
        resultIsError = false
        result = added > 0 ? String(localized: "\(added) \(bridge.noun) in") : String(localized: "Up to date")
        let proof = added > 0
            ? String(localized: "\(added) \(bridge.noun) in")
            : String(localized: "Synced just now")
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
