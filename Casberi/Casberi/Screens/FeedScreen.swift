import SwiftUI
import SwiftData
import Translation

/// Feed — the record paints (M3), and it is ENTIRELY a feed (re-ruling
/// 2026-07-04): source chips, machine presence, then rows. A kind filter
/// (`FeedFilter.tag`) can still be in force — the agent sets it when an ask
/// names a kind — but it wears no chip of its own (2026-08-01): the day
/// header names it and any source chip tap clears it.
///
/// SHAPED FEEDS (docs/handoff-shaped-feeds.md): when one source is in force
/// the feed takes that source's native shape — Photos becomes a grid, Zerion
/// leads with the holdings treemap, Calendar reads as an agenda, Gmail
/// surfaces what's waiting, Reminders groups by state, chats earn takeaway
/// cards. Deepened 2026-07-13: notes lead with their text, chats with their
/// opening line, posts read as author-led cards with media at width, Safari
/// reads as a reading list; Music and Tokens carry a lede block; the
/// new-since divider is per-source; each feed closes with a caught-up line.
/// "All" renders kind-aware rows; only `.approval` breaks row rhythm
/// (the consent card). Day groups, pins, swipes, the sheet, and write-confirm
/// all survive inside shapes.
/// Compared by its three PLAIN inputs, so a parent re-render alone cannot
/// rebuild the feed (2026-08-06).
///
/// `MainSurface` re-creates this view on every one of its own body
/// evaluations, and SwiftUI then compares the two structs to decide whether to
/// re-run this body. That comparison could never say "equal": the stored
/// `@Query` descriptor and the `@Environment` actions wrap closures and key
/// paths, which compare by nothing. So every MainSurface render — and it
/// renders on every corpus change, holding an unfiltered `@Query` of its own —
/// re-ran the whole feed body.
///
/// MEASURED on a 6,000-row corpus. `Self._printChanges()` put `@self changed`
/// at 24 of 53 invalidations in one launch (40 of 79 in another), the single
/// largest cause. With `.equatable()`, interleaved A/B runs against one
/// drained corpus: **15 body builds → 2**, reproducible, launch unchanged.
///
/// What it did NOT do, stated so nobody reads more into it: in that steady
/// state the 13 removed builds were cheap ones, and the ~600ms main-actor
/// stall per foreground was IDENTICAL in both arms — so this is less work,
/// not a demonstrated cure for the "laggy after 271" report. The remaining
/// stall is somewhere else again.
///
/// The three `let`s below ARE the entire contract with the parent — every
/// other input arrives through a property wrapper (`@Query`, `@State`,
/// `@Environment`, `@Observable` environment objects), each of which
/// invalidates this view through its own dependency rather than the parent's
/// comparison. So equality on the three is sound: state changes, query
/// re-fires and observation all still redraw exactly as before; only the
/// parent-churn path is cut.
///
/// If a stored property the body READS is ever added here, it MUST join this
/// comparison — otherwise the feed renders it once and never updates it again,
/// which is the one way this optimization can lie.
extension FeedScreen: Equatable {
    static func == (a: FeedScreen, b: FeedScreen) -> Bool {
        a.source == b.source && a.isActive == b.isActive && a.nearActive == b.nearActive
    }
}

struct FeedScreen: View {
    /// The source this feed IS (2026-07-16, the pager): each page owns one
    /// source for its whole life instead of the whole screen re-reading the
    /// shared filter. `FeedFilter.source` is still the truth for WHICH
    /// page is up — it's the pager's selection — but a page's own shape,
    /// query, and boundary are this.
    let source: String
    /// Whether this page is the one in front. A pager keeps its neighbours
    /// MOUNTED, so `onAppear` stopped meaning "the person is looking at this"
    /// — every per-visit effect (the boundary freeze, the entrance wave, the
    /// synthesis stream, chrome minimizing) gates on this
    /// instead, or a page swiped PAST would burn its arrival unseen and stamp
    /// its own "New since" line away.
    let isActive: Bool

    /// Whether this page is the active one OR an immediate neighbour of it
    /// (PERF 2026-07-30). `TabView(.page)` EAGERLY builds every page in its
    /// `ForEach` and rebuilds ALL of them on every render pass — measured on a
    /// cold launch as ~10 full feed-tree builds per pass, 6+ passes in the
    /// first second, which is what made the first open crawl and the chip strip
    /// unswipeable while it settled (the `launchPerf` body-tick stream). An
    /// off-screen page the person hasn't reached builds nothing heavy until it
    /// becomes active or a neighbour (so a one-swipe-away page is ready and the
    /// swipe stays instant); once built it LATCHES (`everBuilt`) so a revisit
    /// never pays again. Passed by `MainSurface`, which knows the chip order.
    let nearActive: Bool

    /// Latches true the first time this page is active/near, so a page already
    /// assembled once stays assembled — the built set only ever grows, spread
    /// across the person's own swipes instead of all at once on launch.
    @State private var everBuilt = false

    /// Source-scoped since 2026-07-21 (perf audit): the pager keeps every
    /// neighbor page MOUNTED (doc above), so an unfiltered `@Query` here used
    /// to mean N+1 live full-corpus queries (one per source chip, plus
    /// MainSurface's own) — a write to ANY thing, anywhere, re-materialized
    /// and re-filtered the whole corpus on every one of them. Each page now
    /// only ever observes its own source's rows; only the "All" page still
    /// queries everything, because it genuinely shows everything.
    @Query private var things: [Thing]
    @Environment(ShellChrome.self) private var chrome
    @Environment(BridgeStore.self) private var bridges
    @Environment(\.modelContext) private var modelContext
    // This window's stack and detail pane (per-window since `SceneState`).
    @Environment(HomeRoute.self) private var route
    @Environment(PadDetailSelection.self) private var detail

    init(source: String, isActive: Bool, nearActive: Bool = true) {
        self.source = source
        self.isActive = isActive
        self.nearActive = nearActive
        if source == "All" {
            // The All feed's @Query is unfiltered, so it re-fetches on EVERY
            // context save from any bridge — and a cold-launch foreground fires
            // a burst of them as ~every connected network bridge's sync returns
            // over several seconds (PERF 2026-07-30, user: "frozen ~5s, snappy
            // in airplane mode" — the burst is network-driven). Without
            // `propertiesToFetch` each of those re-fetches re-materialized the
            // WHOLE corpus WITH its heavy inline text (`content`/`enrichedText`/
            // `postText`) on the main thread — the exact cost MainSurface's own
            // query fixed the same way. The derivations that run per save
            // (bundling, day-grouping, the themes treemap) read only light
            // columns, so the heavy text is pure overhead here; the few visible
            // rows that DO show `content`/`postText` fault it on appearance
            // (a cheap local read, once, not per re-fetch). The `.externalStorage`
            // columns (audio/image/embedding) are already lazy and omitted.
            var d = FetchDescriptor<Thing>(sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
            d.propertiesToFetch = [
                \.id, \.kind, \.title, \.source, \.createdAt, \.capturedAt, \.mark,
                \.tags, \.provenance, \.sourceRef, \.previewImageURL, \.walletAddress,
                \.counterpartyAddress, \.transferDirection, \.transferAmount, \.transferVenue,
                \.transferCounterparty, \.securityFlag, \.spoofedSymbol, \.authorHandle,
                \.authorAvatarURL, \.summary, \.dueAt, \.ocrAt, \.ocrTopics, \.topicsAt,
                \.watchPriceUsd, \.starCount, \.repoLanguage, \.priceValue, \.priceCurrency,
                \.socialContext, \.channelName, \.likeCount, \.repostCount, \.replyCount,
                \.quote, \.parent, \.imageURLs, \.postAuthor, \.externalLink, \.wikilinks,
                \.marketResolvedYes,
                // The row's context menu reads these per row now (prd §260), so
                // they belong in the pre-fetch with everything else it reads —
                // otherwise storing the detection would just trade a detector
                // pass for a per-row fault, which is the same mistake wearing a
                // cheaper coat.
                \.detectedTel, \.detectedPlace, \.detectedMailto,
            ]
            // BOUNDED (2026-08-06). `propertiesToFetch` above made each row
            // cheap; it never bounded HOW MANY, so this query materialised the
            // whole corpus — every row, as a real `Thing` object, on the main
            // actor, every time the body read it.
            //
            // MEASURED with `scripts/main-thread-profile.sh` on a 6,000-row
            // corpus, cold launch: `FeedScreen.things.getter` was 26.6% of the
            // main thread (and `MainSurface.things.getter` another 25.0%). The
            // self time underneath is `swift_conformsToProtocol`,
            // `MetadataCacheKey::operator==`, `Hasher.combine` and
            // retain/release — SwiftData instantiating models, not any code of
            // ours. Our own functions measured ~0% self time. That is the
            // "laggy after 271" report: it scales with corpus size, which is
            // why it arrived with the bulk-import rooms.
            //
            // Three read sites made it unavoidable per body evaluation, which
            // is why the limit lives HERE and not at any one of them:
            // `Corpus.hasSurfaced(things)` in `feedList`, `.task(id:
            // things.count)`, and `liveVisible()`.
            //
            // The number: the feed WINDOWS at `windowRowTarget` (30) rows and
            // grows by that much per "Show older", so this is ~40 taps of
            // headroom — far past anyone's scrolling — while bounding the cost
            // at a constant no matter how large the corpus grows. The room's
            // own derivations (themes, day groups, the insight heroes) now
            // describe the recent window rather than all-time, which is the
            // ruling this was built under (user, 2026-08-06) and is what
            // `HomeInsightStore` already did with its own 600-row fetch.
            //
            // HONESTY (§83): a bound the person can reach must never render as
            // "you're all caught up". `reachedFetchCeiling` below says so
            // plainly at the edge instead.
            d.fetchLimit = Self.allRoomFetchLimit
            _things = Query(d)
        } else {
            _things = Query(filter: #Predicate<Thing> { $0.source == source },
                            sort: \Thing.capturedAt, order: .reverse)
        }
    }

    /// Only `tag` is read from here now — a kind filter is a cross-page state
    /// (it arrives from Home's kind bar and applies to the All room).
    /// Per-WINDOW since `SceneState`: `RootShell` owns it and injects it.
    @Environment(FeedFilter.self) private var filter
    /// The one sheet this screen can have open at a time (2026-07-24, fixing
    /// prd §196's "opens and dismisses itself on first try"). Five separate
    /// `.sheet` modifiers stacked on one view — thing/token/combined
    /// wallets/allocation/Worth-a-look — fought each other for the
    /// presentation controller: SwiftUI only reliably drives one
    /// `.sheet(item:)` + one `.sheet(isPresented:)` per view, and past that
    /// the first tap's controller got torn down mid-present by a sibling's
    /// state settling, so it flashed open and closed; the second tap then
    /// worked because the machinery had quieted. One enum route behind one
    /// `.sheet(item:)` removes the contention entirely.
    private enum FeedSheetRoute: Identifiable {
        case thing(Thing)
        case token(TokenQuickRoute)
        case allocation
        case worthALook
        /// The two composition doors (prd §240, 2026-07-31). Both carry the
        /// composition VALUE rather than reading `walletLive` at present time:
        /// the books can land again under an open tray, and a tray that
        /// re-reads mid-presentation would renumber itself while being looked
        /// at. Value-typed all the way down, so no `Thing` and no liveness
        /// question here.
        case deposits(WalletComposition)
        case locks(WalletComposition)
        /// A market from the live book, previewed BEFORE it's followed
        /// (prd §234) — so it has no `Thing` yet and can't ride `.thing`.
        /// Routed here rather than presented by the browse section itself
        /// because that section lives inside this List's rows, and a `.sheet`
        /// on a row resolves to the same presenting controller as this one —
        /// the half-open-then-close bug (ruling 2026-07-28).
        case market(PredictionPreview)

        var id: String {
            switch self {
            case .thing(let t): "thing:\(t.id.uuidString)"
            case .token(let r): "token:\(r.id)"
            case .allocation: "allocation"
            case .worthALook: "worthALook"
            case .deposits: "deposits"
            case .locks: "locks"
            case .market(let p): "market:\(p.id)"
            }
        }
    }
    @State private var feedSheet: FeedSheetRoute?
    /// The x402 room's selected lane, or nil for all of it (2026-08-06).
    ///
    /// `@State`, so it resets when you leave the room — the same lifetime
    /// `PredictionBrowseSection.bookView` has, and correct for a VIEW filter:
    /// it is how you are looking right now, not a setting you configured.
    /// Which is also what keeps §269 intact — that ruling killed a chip which
    /// APPEARED as a consequence of agent state, not a control you operate.
    /// This strip is always there, always shows every lane, and nothing but a
    /// tap can change it.
    @State private var x402Lane: String?
    @State private var confirming: (Verb, Thing)?
    /// Translate verb, swipe-triggered — same system sheet as ThingSheetView's.
    @State private var showTranslate = false
    @State private var translateText = ""
    @State private var staleExpanded = false
    /// The Calendar room hides what's already happened (user, 2026-07-27) —
    /// this is the disclosure that brings it back. Collapsed by default; see
    /// `calendarSections`.
    @State private var pastEventsExpanded = false
    @State private var blockStream = GenStream()
    // GitHub's contribution graph rides the TOP of its own source feed (moved
    // off Home, 2026-07-18): the green-squares year is a GitHub thing, so it
    // belongs where GitHub lives. Self-fetching @Observable store, same one the
    // graph always used; the hero only paints once a real year with
    // contributions has landed (an empty grid is a skeleton, not content).
    @State private var githubGraph = GitHubGraphStore.shared
    @Bindable private var wallet = WalletStore.shared
    /// The wallet the Wallet feed is scoped to (prd §128) — nil is "All", the
    /// combined view. Set by the switcher chip strip at the top of the wallet
    /// feed; scopes the balance lede, holdings treemap, NFT strip, and the
    /// transaction rows to one watched wallet. Only meaningful on the Wallet
    /// page (each FeedScreen owns one source); nil everywhere else.
    @State private var selectedWallet: String?
    /// The Wallet feed's live reads (2026-07-20) — Aave positions and the
    /// warnings rolled up from them plus Safe/poisoning/delegation. Never a
    /// landed thing: re-read each time this feed comes forward or its scope
    /// changes, exactly as the manage screen used to hold it.
    @State private var walletLive = WalletLiveState()
    /// The combined portfolio behind the treemap (2026-07-21, prd §155) — one
    /// derivation the balance headline, the concentration line, and the
    /// allocation tray all read, so nothing on this screen can disagree with
    /// the map it's standing under. Lands with the treemap doc, from the same
    /// read.
    @State private var portfolio: WalletPortfolio?
    /// The full allocation tray — every position and which wallets hold it.
    /// Routed through `feedSheet` (`.allocation`) now, not its own bool.
    /// The balance line's window (prd §155). Narrowed to what the record can
    /// actually answer each render; the choice persists across launches.
    @State private var balanceRange: WalletRange = .watched
    /// The wallet switcher's selection fill — ONE capsule that slides from
    /// the old chip to the new (the source chips' own ruling, 2026-07-14:
    /// "selection is an object traveling, not two states blinking").
    @Namespace private var walletSwitcherNS
    /// Bumped when this page lands — rows replay their shape's
    /// entrance (each shape arrives its own way, ruling 2026-07-07).
    /// Memo for the feed's two expensive derivations (PERF 2026-07-31).
    /// Measured on a cold launch: the All page's body evaluates ~18 times while
    /// the corpus and the bridge sweep settle, and each pass re-ran the day
    /// grouping and the bundling over the SAME visible set — pure waste, and
    /// the cost scales with corpus size. These are pure functions of `visible`,
    /// so they're computed once per real change and reused otherwise.
    ///
    /// A plain class, deliberately NOT `@Observable`: writing to it during a
    /// body evaluation is memoization, not state, and must never itself
    /// schedule another render.
    ///
    /// Liveness (the 176/177/188 crash class): a cache hit means the key is
    /// unchanged, and the key covers every id in `visible` — so a delete (which
    /// removes an id, `visible` being `.live`-filtered upstream) always misses
    /// the cache and recomputes. The rows are `KeyedThing` and every reader is
    /// already guarded, so a hit can only ever serve models that were live when
    /// derived.
    @MainActor private final class DerivationMemo {
        var key: Int?
        var days: [(String, [Thing])] = []
        var groups: [(String, [FeedRow])] = []
        var imageOnly: Set<UUID> = []
        var wideArt: Set<UUID> = []
        var coarse: Set<String> = []
        /// Set while the sections render; read by `feedList` a few lines later
        /// to decide whether "that's everything" is still true. Same
        /// write-during-body / read-later shape `groups` already has, and safe
        /// for the same reason: the sections are evaluated before the footer.
        var windowHasMore = false
    }
    @State private var memo = DerivationMemo()

    /// Same memo, for the themes treemap's own corpus walk (`projectClusters`
    /// → `themesDocument` → `GenParser.parse`), which ran on every one of those
    /// same ~18 passes.
    @MainActor private final class ThemesMemo {
        var key: Int?
        var clusters: [HomeComposition.Cluster] = []
        var doc: [String]?
    }
    @State private var themesMemo = ThemesMemo()

    /// The themes lede's corpus walk, computed once per real change. Kept as a
    /// function (not inline in the `@ViewBuilder`) because a memo needs a
    /// statement body, which a ViewBuilder won't take.
    /// Takes the render's own `visible` (PERF 2026-07-31). It used to read
    /// `self.visible` twice — and for the All room every read is a `.live`
    /// filter over the WHOLE corpus, so the render paid for three passes where
    /// one would do. The caller already holds the array; passing it makes that
    /// obvious rather than incidental.
    private func themesData(_ visible: [Thing]) -> (clusters: [HomeComposition.Cluster], doc: [String]?) {
        let key = derivationKey(visible)
        if themesMemo.key != key {
            themesMemo.key = key
            themesMemo.clusters = perfAccum("projectClusters") {
                HomeComposition.projectClusters(things: visible)
            }
            themesMemo.doc = perfAccum("themesDocument") {
                HomeComposition.themesDocument(clusters: themesMemo.clusters)
            }
        }
        return (themesMemo.clusters, themesMemo.doc)
    }

    /// Cheap identity for a derivation input — count + every id and capture
    /// date, which is what the grouping and bundling actually key on. O(n)
    /// hashing is ~1% of the grouping it saves. An in-place cosmetic heal (a
    /// backfilled thumbnail) doesn't change this and so won't repaint until the
    /// next structural change — the same tradeoff `debouncedAllSnapshot`
    /// already documents and accepts.
    private func derivationKey(_ things: [Thing]) -> Int {
        var h = Hasher()
        h.combine(things.count)
        h.combine(filter.tag)
        h.combine(source)
        // The All room keys on the SNAPSHOT's revision, not on a walk of its
        // contents (PERF 2026-07-31, measured on a 4,000-thing corpus: the All
        // page's `feedList` cost 6.3 SECONDS of main-thread time across 44
        // launch-window renders — 143ms each, against 2ms on the demo corpus).
        // Almost all of it was HERE. The loop below reads two PERSISTED
        // properties per element, so the cache key cost about what the grouping
        // it caches costs, and it ran two or three times per render — a memo
        // that pays for itself twice over is not a memo. It is also what made
        // the pager stick: a 143ms main-thread block lands right where the
        // page's release animation should run, so the swipe rests between two
        // pages until the thread frees.
        //
        // O(1) and still safe on the crash class: `things` here is `visible`,
        // which is `.live`-filtered at the boundary, so a DELETE always shows
        // up in `things.count` above and misses the cache. An INSERT can only
        // reach the All room through `debouncedAllSnapshot`, and every write to
        // it bumps `allRevision`. Same standing tradeoff the debounce itself
        // documents: an in-place heal that changes neither count nor revision
        // (including a `capturedAt` edit that would re-day-group a row) waits
        // for the next structural change to repaint.
        if source == "All", filter.tag == "All" {
            h.combine(allSnapshotKey)
            return h.finalize()
        }
        // Every other room reads its own source-filtered `@Query` directly, so
        // it is only re-emitted by ITS source's own saves and there is no
        // snapshot to count revisions of. The walk stays exact there.
        for t in things {
            h.combine(t.id)
            h.combine(t.capturedAt)
        }
        return h.finalize()
    }

    /// The All snapshot's CONTENT signature, computed once each time the
    /// snapshot is written — the All room's O(1) derivation identity at render
    /// time. See `derivationKey`.
    ///
    /// A plain revision counter was the first cut and measurably worse: the
    /// debounce republishes on every count-changing emission, so the counter
    /// moved even when the resulting array was identical, and the grouping and
    /// bundling recomputed three times a launch instead of once (+420ms at
    /// 4,000 things). This is the same walk the old per-render key did — just
    /// paid on the three writes instead of on all forty-four renders.
    @State private var allSnapshotKey = 0

    /// Identity of a snapshot's contents: what the grouping and bundling
    /// actually key on. Mirrors `derivationKey`'s non-All walk deliberately —
    /// if one ever learns about a new field, so must the other.
    private func snapshotSignature(_ things: [Thing]) -> Int {
        var h = Hasher()
        h.combine(things.count)
        for t in things {
            h.combine(t.id)
            h.combine(t.capturedAt)
        }
        return h.finalize()
    }

    @State private var shapeWave = 0
    /// Latches on the FIRST landing so the row entrance plays once, not on
    /// every swipe back to this page (2026-07-30 swipe-smoothness — see
    /// `land()`).
    @State private var hasLanded = false
    /// The last time the person left THIS feed ("feed.lastSeen" is All's
    /// original key, so nothing migrates), no per-thing read state. The
    /// boundary freezes when the page lands and holds for the whole visit
    /// (ruling 2026-07-09: the divider never moves while you look at it — a
    /// bounce out and back must not erase it), and stamps when the page is
    /// left. The old per-source dictionary + visited SET are gone with the
    /// pager (2026-07-16): one screen used to serve every room, so it had to
    /// remember which rooms it had been; a page IS its room and can only ever
    /// stamp its own key. That also retires the 2026-07-13 bug those guards
    /// existed for (the shared filter reading "Pinned" while this screen went
    /// away, stamping a junk key) — this page never sees another room's name.
    @State private var newSince: Date?
    @State private var visitFrozen = false
    /// A tapped Themes cell (2026-07-18, the All feed's own treemap) — the
    /// same project detail door Home's map already opened.
    @State private var openProject: ProjectRoute?
    @State private var openPerson: SocialProfile?
    /// Themes stays expanded for the rest of THIS session once tapped open
    /// (2026-07-20) — session-only by design; a fresh mount re-checks the
    /// digest and may collapse again.
    @State private var themesExpanded = false
    private static let themesSeenDigestKey = "feed.themesSeenDigest"
    struct ProjectRoute: Identifiable, Hashable {
        let name: String
        var id: String { name }
    }
    @Namespace private var zoomNS
    /// prd 43h: Reduce Motion is law — the hand-rolled moves (row entrances)
    /// fall back to plain state changes under it.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Opening a URL is an ACTION here — a button tap, a swipe verb — and never
    /// something the body renders. It used to arrive as
    /// `@Environment(\.openURL)`, which is a stored property, and
    /// `OpenURLAction` wraps a closure, so it can never compare equal: every
    /// recomputation of the environment counted as a change to this view and
    /// re-ran the whole feed body.
    ///
    /// MEASURED 2026-08-06 on a 6,000-row corpus, via `Self._printChanges()`:
    /// 18 of 53 FeedScreen invalidations in one launch named `_openURL`, and
    /// each one is a ~260ms `feedList` rebuild on the main actor — a third of
    /// the rebuild storm, bought by a value the view never draws. Nothing above
    /// this view overrides `openURL` (the one override in the tree wraps
    /// `ThingSheetView` inside the composer), so this is the same call the
    /// environment action would have made.
    ///
    /// It is NOT the whole rebuild story and should not be read as the fix:
    /// the dominant trigger is `@self` — MainSurface re-creating this view —
    /// which this does nothing about. A/B measured rebuilds ~49 → ~43.
    private func openExternal(_ url: URL) {
        UIApplication.shared.open(url)
    }

    /// The shape a source takes when its chip is in force.
    private enum Shape {
        case all, photos, wallet, calendar, gmail, chat, social, reminders, safari, notes, you, music, media, tokens, bitrefill, oneclaw, snapchat, files, x, x402, appStoreConnect, cursor, plain
        init(source: String) {
            switch source {
            case "All":                 self = .all
            case "Photos":              self = .photos
            // Snapchat is the first MIXED room (2026-07-31): memories are
            // pictures and saved chats are conversations, so it can't be
            // `.photos` (that would hide the chats) or `.chat` (that would
            // list the pictures as dated rows, which is exactly what the
            // export already is and what this app exists to beat). It gets
            // its own shape: the memories that have their pixels back as a
            // grid, everything else as rows beneath.
            case "Snapchat":            self = .snapchat
            // The second mixed room (2026-08-02): a connected folder holds
            // images beside PDFs and text files, and `FilesIngest.heal` gives
            // the images real thumbnails + OCR — which `.plain` then rendered
            // as filename rows, pixels stored but never drawn (a user pointing
            // the folder card at a screenshots folder saw a wall of text).
            // Same split as Snapchat: healed images as a grid, the rest as
            // rows.
            case "Files":               self = .files
            // App Store Connect, 2026-08-06 — its own shape for ONE row type:
            // a customer review is somebody else's words about your work, and
            // `.plain` drew it as an 80-character title with the text stored
            // and never rendered (the §313 X finding, one room over). Verdicts
            // and builds keep the band — they are one-line facts, and giving
            // them a card would spend the room's emphasis on the rows that
            // need it least.
            case ASCShape.source:       self = .appStoreConnect
            case "Wallet":              self = .wallet
            case "Calendar", "Cal.com", "Calendly": self = .calendar
            case "Gmail", "iCloud Mail": self = .gmail
            case "ChatGPT", "Claude", "Gemini": self = .chat
            // Posts read as posts in their own room (2026-07-13) — split from
            // .chat: a saved conversation is a snippet row, a post is a card.
            case "Farcaster", "Bluesky": self = .social
            // X, 2026-08-06 — the same ruling as the line above, arriving two
            // years of somebody's writing late. The room had NO case here at
            // all, so it fell to `.plain` and drew a `BandRow` per row: an
            // icon, `titleLine`'s 80-character clamp, a timestamp. In a room
            // whose entire content is sentences written to be read. The words
            // were in the store the whole time and on no screen — a post's on
            // `content`, a liked post's on `enrichedText`, which is
            // retrieval-only by the 2026-07-15 ruling.
            //
            // Its OWN case rather than joining `.social`, because `.social`
            // means something different by a `.link`: there it is an article a
            // post shared (`ReadingRow`), here it is a post somebody else
            // wrote and you liked — a post, and it reads as one. Sharing the
            // case would also hand X's room the Farcaster/Bluesky roster head,
            // which reads its accounts out of `BlueskyStore` for anything that
            // isn't Farcaster.
            case "X":                   self = .x
            // Circle x402, 2026-08-06 — the same defect as the line above, one
            // day later. It had no case here, so `.plain` drew twenty-two
            // BandRows wearing one glyph and ONE TIMESTAMP (every seller lands
            // on the walk that first sees it), while what a call costs sat on
            // `summary`, visible only inside the sheet. Its own case rather
            // than joining any existing one: no other room's row leads with a
            // price, and none of them has a trailing slot that must NOT be a
            // time.
            case X402Ingest.source:     self = .x402
            // Its own case rather than joining `.chat` (2026-08-08, prd §340).
            // A Cursor row is a REPORT — an outcome, a repository and a
            // paragraph the agent wrote about what it did — where a chat row
            // is an excerpt of a conversation; and `.plain`, which this fell
            // to before, drew the outcome and the report away entirely.
            case "Cursor":              self = .cursor
            case "Reminders", "Todoist": self = .reminders
            case "Safari":              self = .safari
            // Obsidian joins the notes room — the vault is notes (prd §59).
            // Files LEFT this group on 2026-08-02 (see `.files` above): the
            // excerpt row it shared here draws title + text + time and no
            // image at all, so a connected folder of screenshots rendered as
            // pure text while its thumbnails sat in the store undrawn.
            case "Notes", "Day One", "Apple Journal", "Obsidian": self = .notes
            case "You", "Voice":        self = .you
            case "Apple Music", "Spotify": self = .music
            // The media room (prd §219, 2026-07-25): art at the medium's own
            // proportions instead of the All feed's 26pt square. Music is NOT
            // here — `MusicRow` has led with the cover since 2026-07-11 and is
            // already this shape by another name.
            //
            // PODCASTS STAYS HERE, decided 2026-08-06 rather than allowed to
            // happen. A per-episode `<itunes:image>` now fills
            // `previewImageURL`, so overnight every episode row carries art
            // where it carried none, and the three precedents for splitting a
            // room off (Snapchat §247, Files §283, X §313) all look like this
            // one from a distance. They are not: each of those was a room whose
            // pixels were STORED AND NEVER DRAWN, or whose rows were the wrong
            // anatomy for what they held. This room was built for art from the
            // day it shipped — `MediaShape.art(for:)` has declared Podcasts
            // `.cover` since §219, and `MediaRow` has drawn `previewImageURL`
            // at 48×48 with the brand glyph standing in on the same 48×48 box.
            // So the geometry does not move: row height, leading box, byline,
            // trailing time are all unchanged, and what changes is the CONTENT
            // of a box the room already reserved. That is a fill, not a
            // re-shape, and a new `Shape` case would be a second mechanism
            // saying what this one already says.
            //
            // Two knock-ons, both already handled where they live, and both
            // reasons NOT to build a mixed grid here: `FeedInsight.mosaic`
            // dedupes tiles by URL, so a show that stamps one cover on every
            // episode can never fill the 4-tile shelf and the head correctly
            // declines it (and the "Latest episodes" leaderboard outranks the
            // mosaic anyway); and `MediaShape.freshness` saturation now reaches
            // podcast art, which is §219's own decay arriving as designed
            // rather than a new behaviour.
            case _ where MediaShape.isMediaFeed(source): self = .media
            case "Tokens":              self = .tokens
            case "Bitrefill":           self = .bitrefill
            case "1Claw":               self = .oneclaw
            default:                    self = .plain
            }
        }
    }
    private var shape: Shape { Shape(source: source) }


    /// How this shape's rows arrive: the agenda slides in from the leading
    /// edge like a day filling, photos scale in like the grid, transactions
    /// rise like entries posting, everything else lifts gently.
    private var entranceStyle: RowEntrance.Style {
        switch shape {
        case .calendar: .init(dx: -28, dy: 0, scale: 1, step: 0.045)
        case .wallet, .tokens: .init(dx: 0, dy: 16, scale: 1, step: 0.04)
        case .photos:   .init(dx: 0, dy: 0, scale: 0.92, step: 0.03)
        case .music:    .init(dx: 0, dy: 10, scale: 1, step: 0.035)
        // Frames settle in like the music room's covers — a touch of scale so
        // the art reads as arriving, not sliding.
        case .media:    .init(dx: 0, dy: 10, scale: 0.97, step: 0.035)
        case .social, .x: .init(dx: 0, dy: 12, scale: 0.98, step: 0.035)
        default:        .init(dx: 0, dy: 8, scale: 1, step: 0.028)
        }
    }

    // MARK: - Derivations

    /// The corpus MINUS the search-only sources — Contacts land as things for
    /// lookup and the answer path, but never as feed rows or a source chip
    /// (ruling 2026-07-12): hundreds of names would bury the day's captures.
    /// One rule (`Corpus.surfaced`), shared with Home's synthesis.
    private var feedThings: [Thing] { Corpus.surfaced(things) }

    private func liveVisible() -> [Thing] {
        feedThings.filter { thing in
            (source == "All" || thing.source == source)
                // A bulk import (Instagram, Snapchat) keeps its own room but
                // stays OUT of All — thousands of things dated across years
                // would bury the day's real captures. All sees its receipt
                // only; the chip opens the room that holds the rest.
                && (source != "All" || Corpus.showsInAll(thing))
                && (filter.tag == "All" || thing.tags.contains(filter.tag))
                && walletScopeAllows(thing)
        }
    }

    /// Debounced snapshot for the unfiltered All room only (perf, 2026-07-28).
    /// A foreground refresh fires ~30 independent bridge saves (`BridgeRefresh`),
    /// each re-firing every `@Query` whose predicate could match — every
    /// per-source page is shielded from an unrelated bridge's save by its own
    /// `source ==` predicate (2026-07-21 perf audit, see `things`' doc above),
    /// but the All room's `@Query` is unfiltered by design (it genuinely shows
    /// everything), so it alone re-runs the WHOLE render chain — bundling,
    /// day-grouping, the corpus treemap — once per save instead of once per
    /// pull. Every downstream reader already re-filters `.isLive` before
    /// touching a stored property (`daySection`'s COROLLARY 2 guard), so a
    /// snapshot that's briefly behind the live corpus is safe: a thing deleted
    /// in the gap just doesn't repaint until the next settle, same as it
    /// wouldn't mid-transaction today. The FIRST population is instant (no
    /// debounce) so opening the All room never shows a blank beat.
    ///
    /// CORRECTION (2026-07-28, builds 176 + 177): "every downstream reader
    /// already re-filters" was NOT true, and holding raw `Thing` refs in
    /// `@State` on the promise that someone else guards is how both crashes
    /// happened. `visible` filters `.live` itself now — see below.
    @State private var debouncedAllSnapshot: [Thing]?
    private var visible: [Thing] {
        // Non-All rooms read their own source-filtered @Query directly — that
        // array is SwiftData-coordinated (its elements are live), so no
        // snapshot and no `.live` pass.
        guard source == "All", filter.tag == "All" else { return liveVisible() }
        // All room. `.live` HERE, at the boundary — not left to "every
        // downstream reader", which is what the note above used to claim and
        // what builds 176 and 177 both disproved (2026-07-28). The snapshot
        // holds raw model refs and is DELIBERATELY behind the live corpus, so
        // for the whole debounce window after any delete it hands out refs
        // that are already tombstoned; 176 trapped on the ForEach path, 177 on
        // `HomeComposition.projectClusters` reading `thing.tags`. Filtering
        // once here makes the claim true for every reader.
        //
        // PERF (2026-07-29): compute `liveVisible()` ONLY when the snapshot
        // isn't populated yet (the first cold paint). The old form bound
        // `let live = liveVisible()` unconditionally and threw it away on
        // every steady-state body eval — a full `Corpus.surfaced` + filter
        // pass over the whole corpus, wasted, and this body re-evaluates on
        // every one of the hundreds of context merges a cold CloudKit import
        // fires. Snapshot present → ONE `.live` pass; absent → one live compute.
        if let snap = debouncedAllSnapshot { return snap.live }
        return liveVisible().live
    }

    /// The value the feed List animates its insertions against. For the All
    /// room this is the DEBOUNCED snapshot's count, not the raw `@Query` count
    /// (PERF 2026-07-29): a cold CloudKit import merges hundreds of records in
    /// a burst on first launch, each bumping `things.count`, and keying the
    /// list's `.animation` on the raw count re-ran a full List insertion
    /// animation on every merge while the main thread was already saturated —
    /// the "slow-motion" first load. The debounced snapshot changes at most
    /// once per 250ms, so the list settles into place instead of thrashing.
    private var listRevision: Int {
        guard source == "All", filter.tag == "All" else { return things.count }
        return debouncedAllSnapshot?.count ?? things.count
    }

    /// The Wallet feed's per-wallet scope (prd §128) — everything passes in
    /// "All" (selectedWallet nil, and it's never set off the Wallet page); when
    /// scoped, only transactions from that watched wallet. Matched through
    /// `WalletStore.scopeMatches` (2026-07-20): things are stamped with the
    /// RESOLVED hex while the scope is the WATCHED spelling, so the old raw
    /// compare emptied an ENS/SNS-watched wallet's scoped feed entirely.
    private func walletScopeAllows(_ thing: Thing) -> Bool {
        guard let scope = selectedWallet else { return true }
        return wallet.scopeMatches(thing.walletAddress, scope: scope)
    }
    private var filterLabel: String {
        let tagLabel = filter.tag == "All" ? nil
            : (ThingKind.from(typeTag: filter.tag)?.typeTagPlural ?? filter.tag)
        return [source == "All" ? nil : source, tagLabel]
            .compactMap { $0 }.joined(separator: " · ")
    }

    /// The connected bridge the feed is currently filtered to, if any. A source
    /// header appears only for a real, live seat — a plain source (Photos,
    /// Voice, Safari) owns no control panel, so it gets no door. Paused seats
    /// aren't "connected", so they don't either.
    private var activeSourceBridge: BridgeApp? {
        guard source != "All" else { return nil }
        // Through the catalog, not against the source: a source name is not
        // always its seat's name ("Privacy Pools" against the "0xBow Privacy
        // Pools" seat), and a bare `==` meant that room silently owned no
        // seat — so it got no header and no door to its own control panel.
        let seat = BridgeCatalog.offer(forSource: source)?.name ?? source
        return bridges.bridges.first { $0.name == seat && $0.status != .paused }
    }

    /// Day groups, newest day first ("Today", "Yesterday", then dated). A feed
    /// is history — it reads from today back. A reminder/event lands with
    /// `capturedAt` set to when it's DUE, so a future-dated thing sorts newest
    /// by raw time and would LEAD the feed — a Wednesday sitting above Today
    /// (user, 2026-07-19). What's still ahead lives on Home's "Coming up" lane,
    /// not here, so future days are dropped from the walk; the feed starts on
    /// Today. (Timed things still to come LATER today stay under Today — the
    /// day, not the clock, is what leads.)
    private func dayGroups(_ visible: [Thing]) -> [(String, [Thing])] {
        let today = Self.groupingCalendar.startOfDay(for: .now)
        var order: [String] = []
        var groups: [String: [Thing]] = [:]
        for thing in visible
        where Self.groupingCalendar.startOfDay(for: thing.capturedAt) <= today {
            let label = dayLabel(thing.capturedAt)
            if groups[label] == nil { order.append(label) }
            groups[label, default: []].append(thing)
        }
        return order.map { ($0, groups[$0] ?? []) }
    }

    /// Day groups, but COARSENED to week/month grain when the source lands
    /// sparsely (ruling 2026-07-21, the day-cards sequel): a source that
    /// drops one thing most days would otherwise become a ladder of one-row
    /// day cards under big headers — exactly the confetti day-cards killed,
    /// re-expressed as headers. When the trailing history averages under
    /// ~1.5 things a day (and there's enough of it to judge), the same rows
    /// regroup as "This week / Last week / <month>" instead. A dense feed
    /// (social bursts, an RSS sync) stays day-grained untouched — this is a
    /// no-op above the threshold, so every chronological source can route
    /// through it safely.
    private func chronoGroups(_ visible: [Thing]) -> [(String, [Thing])] {
        coarsenIfSparse(dayGroups(visible))
    }

    /// Day grain for the last week, coarsened grain behind it (prd §218).
    ///
    /// `coarsenIfSparse` judges a feed as a WHOLE and is all-or-nothing, which
    /// is right for one source's room. The All feed is different: it spans the
    /// entire corpus, so its head is dense (dozens a day) while its tail is
    /// always thin — and the whole-feed average, dragged up by the head, meant
    /// All was the ONE chronological feed that never coarsened at all. Scroll
    /// back far enough and it became the ladder of one-row day cards the
    /// 2026-07-21 ruling killed for every other source.
    ///
    /// So the split is by recency, not by average: the last 7 days always keep
    /// their own day cards (that's the part you're actually reading), and
    /// everything older goes through the existing sparseness gate — which
    /// leaves a genuinely dense older stretch day-grained, exactly as before.
    ///
    /// The gate is asked in ROWS here, not things (prd §255) — this is the one
    /// feed that bundles, so it's the one feed where the two numbers differ,
    /// and counting things is what kept the fold from ever happening.
    private func recentDaysThenCoarseTail(_ visible: [Thing]) -> [(String, [Thing])] {
        let cal = Self.groupingCalendar
        guard let cutoff = cal.date(byAdding: .day, value: -7,
                                    to: cal.startOfDay(for: .now))
        else { return dayGroups(visible) }
        let recent = visible.filter { $0.capturedAt >= cutoff }
        let older = visible.filter { $0.capturedAt < cutoff }
        return dayGroups(recent) + coarsenIfSparse(dayGroups(older), rows: bundledRowCount)
    }

    /// The sparseness gate + regroup, shared by the plain day path and the
    /// agent path (which builds its own day groups first).
    ///
    /// `rows` answers how many ROWS a day will actually DRAW, which is not
    /// always how many things it holds (prd §255, 2026-07-31). In a source's
    /// own room the two are the same number and the default is right. The All
    /// feed BUNDLES after grouping, so a day whose seven wallet transactions
    /// collapse into one row was scoring seven here — and this gate, whose
    /// entire job is to prevent a ladder of one-row day cards, therefore never
    /// once fired on the one feed that actually had one. Measured on a real
    /// corpus: single-row days marching back 487 days, every header full
    /// weight, while the gate read the tail as "dense" and left it alone.
    ///
    /// The old comment here claimed the average "matches what the feed
    /// actually renders". That was the bug, stated as a fact.
    private func coarsenIfSparse(_ days: [(String, [Thing])],
                                 rows: ([Thing]) -> Int = { $0.count }) -> [(String, [Thing])] {
        let drawn = days.reduce(0) { $0 + rows($1.1) }
        guard days.count >= 6,
              Double(drawn) / Double(days.count) < 1.5 else { return days }
        return coarseGroups(days.flatMap { $0.1 })
    }

    /// How many rows a day's things draw once `bundle` has run over them.
    ///
    /// Mirrors `bundle`'s own rule — a source with `bundleThreshold`+
    /// bundleable things in the day collapses to ONE row, everything else draws
    /// itself — without building the rows, because the gate runs BEFORE
    /// bundling and only needs the count. One pass per day, no allocation
    /// beyond a small per-source tally.
    private func bundledRowCount(_ dayThings: [Thing]) -> Int {
        var bySource: [String: Int] = [:]
        var loose = 0
        for t in dayThings {
            if bundleable(t) { bySource[t.source, default: 0] += 1 } else { loose += 1 }
        }
        return loose + bySource.values.reduce(0) {
            $0 + ($1 >= Self.bundleThreshold ? 1 : $1)
        }
    }

    /// Regroup already-ordered (newest-first) things by week, then month —
    /// "This week", "Last week", then month names for the tail (a week grain
    /// that ran all the way down would ladder into "3 weeks ago, 4 weeks
    /// ago"; months are how sparse history actually reads back).
    private func coarseGroups(_ things: [Thing]) -> [(String, [Thing])] {
        var order: [String] = []
        var groups: [String: [Thing]] = [:]
        for t in things {
            let label = coarseLabel(t.capturedAt)
            if groups[label] == nil { order.append(label) }
            groups[label, default: []].append(t)
        }
        return order.map { ($0, groups[$0] ?? []) }
    }

    /// Which of these groups came from the COARSE regroup above rather than the
    /// day grain — the folded tail (prd §254, 2026-07-31), whose headers weigh
    /// one step less than a day's.
    ///
    /// Asked of `coarseLabel` ITSELF rather than pattern-matched off the
    /// string: a group is coarse exactly when its label is what `coarseLabel`
    /// would name its own members. That keeps it correct in every language (no
    /// English words here), and — the reason it isn't the simpler "is this not
    /// a `dayLabel`?" — it leaves the MUSIC room's session groups ("This
    /// morning", "Mon evening") alone, which are a different grain, not a
    /// coarser one.
    private func coarseLabels(in groups: [(String, [Thing])]) -> Set<String> {
        Set(groups.compactMap { label, rows -> String? in
            // `.isLive` before `capturedAt`: a derived array, read during the
            // same graph update a heal's delete can land in (the dead-Thing
            // rule, CLAUDE.md).
            guard let first = rows.first(where: \.isLive) else { return nil }
            return label == coarseLabel(first.capturedAt) ? label : nil
        })
    }

    private func coarseLabel(_ date: Date) -> String {
        let cal = Self.groupingCalendar
        if cal.isDate(date, equalTo: .now, toGranularity: .weekOfYear) {
            return String(localized: "This week")
        }
        if let lastWeek = cal.date(byAdding: .weekOfYear, value: -1, to: .now),
           cal.isDate(date, equalTo: lastWeek, toGranularity: .weekOfYear) {
            return String(localized: "Last week")
        }
        if cal.isDate(date, equalTo: .now, toGranularity: .year) {
            return date.formatted(.dateTime.month(.wide))
        }
        return date.formatted(.dateTime.month(.wide).year())
    }

    /// Music lands in SITTINGS, not calendar days (ruling 2026-07-21) — the
    /// day header answers "when" but the real unit of listening is the
    /// session. Consecutive plays less than 45 min apart cluster into one
    /// group, labelled by its start ("This morning", "Yesterday evening",
    /// "Mon evening"). A single session that straddles the whole day still
    /// reads as one card; two listens hours apart split honestly.
    private func sessionGroups(_ visible: [Thing]) -> [(String, [Thing])] {
        let sorted = visible.sorted { $0.capturedAt > $1.capturedAt }
        guard let first = sorted.first else { return [] }
        let gap: TimeInterval = 45 * 60
        var sessions: [[Thing]] = []
        var current: [Thing] = [first]
        for t in sorted.dropFirst() {
            if let last = current.last,
               last.capturedAt.timeIntervalSince(t.capturedAt) <= gap {
                current.append(t)
            } else {
                sessions.append(current)
                current = [t]
            }
        }
        sessions.append(current)
        let labelled = sessions.map { (sessionLabel($0.first!.capturedAt), $0) }
        // groupedSections keys its ForEach on the label, so two sittings that
        // share one ("this morning" twice, >45 min apart) would collide into
        // one SwiftUI id. Append the start clock ONLY to a colliding label, so
        // the common single-session case stays clean.
        var counts: [String: Int] = [:]
        for (label, _) in labelled { counts[label, default: 0] += 1 }
        return labelled.map { label, rows in
            guard (counts[label] ?? 0) > 1 else { return (label, rows) }
            let time = rows.first!.capturedAt.formatted(date: .omitted, time: .shortened)
            return ("\(label) · \(time)", rows)
        }
    }

    private func sessionLabel(_ date: Date) -> String {
        let cal = Self.groupingCalendar
        let part: String
        switch cal.component(.hour, from: date) {
        case 5..<12:  part = String(localized: "morning")
        case 12..<17: part = String(localized: "afternoon")
        case 17..<22: part = String(localized: "evening")
        default:      part = String(localized: "late night")
        }
        if cal.isDateInToday(date) {
            return String(localized: "This \(part)")
        }
        if cal.isDateInYesterday(date) {
            return String(localized: "Yesterday \(part)")
        }
        return "\(date.formatted(.dateTime.weekday(.abbreviated))) \(part)"
    }

    // MARK: - Bundling (ruling 2026-07-09: volume compresses, never reorders)

    /// A feed row in the All shape: a thing, or one row standing in for a
    /// source's bulk arrivals that day.
    /// `id` and `date` are STORED, captured at construction — never computed
    /// off the wrapped `Thing` on demand (2026-07-24 crash fix). As an enum
    /// whose `id` read `t.id.uuidString` lazily, `ForEach`'s identity diffing
    /// (`ForEachChild.updateValue()`) reached into the SwiftData model every
    /// graph update; when a launch-time dedupe (`SyncReconcile`) or a CloudKit
    /// merge deleted that `Thing` mid-render, the read trapped inside SwiftData
    /// (`_assertionFailure`) — the field crash reported as "crashes on open
    /// after an update, never on a fresh install," since only an updated
    /// install has synced duplicates to delete. Capturing the id/date as plain
    /// value types at construction (below, while the `Thing` is still valid)
    /// keeps the diffing path off the model entirely; the model is only touched
    /// in the row body, which renders exclusively from the post-delete `@Query`
    /// snapshot that already excludes the deleted row.
    private struct FeedRow: Identifiable {
        let id: String
        let date: Date
        let kind: Kind
        enum Kind {
            /// `KeyedThing`, not a raw `Thing` — so every read of the model
            /// goes through `.thing`/`.live` and the liveness audit's check 3
            /// can SEE it. Build 176 trapped right here, in a row body that
            /// bound its `Thing` straight out of this payload: correct by the
            /// rules as written, invisible to the lint that enforces them.
            case single(KeyedThing)
            /// `art`: up to three member preview-image URLs, newest first — the
            /// bundle's own pictures (2026-07-21), so "Shopify · 100 products"
            /// can show what actually arrived instead of one brand glyph.
            case bundle(source: String, word: String, count: Int, newest: Date, art: [String])
        }
        static func single(_ t: Thing) -> FeedRow {
            FeedRow(id: t.id.uuidString, date: t.capturedAt, kind: .single(KeyedThing(t)))
        }
        static func bundle(source: String, word: String, count: Int,
                           newest: Date, art: [String]) -> FeedRow {
            FeedRow(id: "bundle-\(source)-\(newest.timeIntervalSince1970)", date: newest,
                    kind: .bundle(source: source, word: word, count: count,
                                  newest: newest, art: art))
        }
    }

    /// `Screens/ThingRowKeying.swift`'s `KeyedThing` — this screen used to
    /// carry a PRIVATE copy of it, which shadowed the shared type here and let
    /// the two drift: the copy never gained `live`, the corollary-3 guard, and
    /// its doc still claimed row bodies "only ever render the post-delete
    /// `@Query` snapshot" (the assumption build 176 disproved). One type now.
    private func keyed(_ things: [Thing]) -> [KeyedThing] { things.keyed }

    /// Consecutive self-replies fold into one thread (item 6 of the
    /// 2026-07-27 social enrichment pass) — a person's own reply chain reads
    /// top-to-bottom as one card in their room, instead of N separate rows a
    /// chronological feed would otherwise interleave with everything else.
    /// Pure over whatever `[Thing]` the caller hands it; called only for
    /// `shape == .social`, so the mixed All feed is never touched.
    ///
    /// `heads` is `things` with every swallowed reply removed — safe to feed
    /// straight into the existing day-grouped `ForEach` pipeline (same array
    /// shape, just fewer rows). `byHeadID` maps a head's `id.uuidString` to
    /// its ordered replies (oldest first, the order a thread was written
    /// in) — plain `[Thing]`, re-wrapped into a `KeyedThing` only at the
    /// point `SocialThreadCard` renders them, since these ride a side
    /// dictionary rather than a `ForEach`'s own diffed array.
    private func foldThreadReplies(_ things: [Thing]) -> (heads: [Thing], byHeadID: [String: [Thing]]) {
        var bySourceRef: [String: Thing] = [:]
        for t in things {
            if let ref = t.sourceRef { bySourceRef[ref] = t }
        }
        var childrenOfRoot: [String: [Thing]] = [:]
        var swallowed: Set<UUID> = []
        for t in things {
            guard let handle = t.authorHandle, !handle.isEmpty,
                  let parentRef = t.parent?.ref,
                  let parent = bySourceRef[parentRef],
                  parent.authorHandle == handle
            else { continue }
            // Walk to the chain's ROOT so a three-deep thread groups under
            // its first post rather than nesting a thread of threads. Capped
            // defensively — a real reply chain is never this deep, but
            // nothing here guarantees the data can't cycle.
            var root = parent
            var hops = 0
            while hops < 32,
                  let grandparentRef = root.parent?.ref,
                  let grandparent = bySourceRef[grandparentRef],
                  grandparent.authorHandle == handle {
                root = grandparent
                hops += 1
            }
            childrenOfRoot[root.id.uuidString, default: []].append(t)
            swallowed.insert(t.id)
        }
        guard !swallowed.isEmpty else { return (things, [:]) }
        let heads = things.filter { !swallowed.contains($0.id) }
        var byHeadID: [String: [Thing]] = [:]
        for (rootID, kids) in childrenOfRoot {
            byHeadID[rootID] = kids.sorted { $0.capturedAt < $1.capturedAt }
        }
        return (heads, byHeadID)
    }

    /// Machine bulk bundles; human captures never do. A screenshot, a voice
    /// note, or anything typed/pasted is one deliberate act each — an RSS
    /// sync or a wallet backfill is one act producing many rows.
    /// A screenshot Vision read and found NO words in — `ocrAt` set (the read
    /// happened) with nothing to show for it. Distinct from "not read yet",
    /// which still wears the placeholder and is about to be retitled.
    private func isWordless(_ t: Thing) -> Bool {
        if t.kind == .screenshot { return t.ocrAt != nil && t.content.isEmpty }
        // A folder-picked image reads the same way (2026-07-27) — OCR ran,
        // found nothing, and the picture already carries the row; gated on
        // `previewImageData` too so a not-yet-thumbnailed image (still
        // showing its byte size as `content`, `ocrAt` untouched) never
        // qualifies before there's actually a picture to show.
        if t.kind == .file, t.source == "Files" {
            return t.ocrAt != nil && t.content.isEmpty && t.previewImageData != nil
        }
        return false
    }

    /// Which rows render as a picture with no title (prd §218) — the wordless
    /// screenshots (and, since 2026-07-27, wordless Files images) of each
    /// day, but ONLY while they're a MINORITY of that day.
    ///
    /// The gate is the whole design. One wordless shot among five rows is a
    /// picture worth looking at; a day that's mostly wordless shots would
    /// become a column of 58pt tiles — which is the Photos grid, a shape that
    /// already exists behind its own chip. Past half a day, they fall back to
    /// the ordinary band and keep the honest filename as the title.
    private func imageOnlyIDs(_ days: [(String, [Thing])]) -> Set<UUID> {
        var ids: Set<UUID> = []
        for (_, dayThings) in days {
            let wordless = dayThings.filter(isWordless)
            guard wordless.count * 2 < dayThings.count else { continue }
            ids.formUnion(wordless.map(\.id))
        }
        return ids
    }

    /// The ONE row per day whose own picture reads at size (prd §254,
    /// 2026-07-31) — the newest post or article that actually carries art.
    ///
    /// §218 gave a wordless screenshot the room its missing words would have
    /// had; this is the same argument for a row that HAS words: the picture is
    /// the part you can't get from the title, and at 26pt a day of them is a
    /// column of specks. One per day, so the feed gains an anchor without
    /// becoming a gallery — the same minority discipline `imageOnlyIDs` uses,
    /// stated as a count instead of a ratio.
    ///
    /// Read off the BUNDLED groups, not the raw days: a row that collapsed
    /// into a bundle never renders as a band, so choosing from the day would
    /// silently promote a row nobody can see (RSS is bundleable, and RSS is
    /// one of the three sources that qualify).
    ///
    /// Withheld under 3 rows — on a two-row day the promoted picture is half
    /// the day, which is a gallery, not an anchor.
    private func wideArtIDs(_ groups: [(String, [FeedRow])]) -> Set<UUID> {
        var ids: Set<UUID> = []
        for (_, rows) in groups where rows.count >= 3 {
            for row in rows {
                // `.live` before any stored read (corollary 3, build 176).
                guard case .single(let item) = row.kind, let thing = item.live
                else { continue }
                if BandRow.artRidesBesideIdentity(thing) {
                    ids.insert(thing.id)
                    break
                }
            }
        }
        return ids
    }

    private func bundleable(_ t: Thing) -> Bool {
        t.kind != .screenshot && t.kind != .voice && t.kind != .approval
            && t.source != "You" && t.source != "Voice"
            // REVERSED 2026-08-09 (user: following 140 Farcaster accounts
            // made "deliberate reads" the wrong call at that follow count —
            // the 2026-07-12 ruling above held for a handful of watched
            // accounts, not a feed wide enough to flood All on its own).
            // Bluesky/Farcaster now bundle the same as any other source:
            // 3+ same-day posts collapse into one row, still fully readable
            // one tap away in the source's own `.social` room, which never
            // bundles (`bundle(_:)` runs only in the day-grouped All path).
            // Same reasoning for watched tokens: each row wears its own
            // sparkline (TokenPulse) — collapsing 3+ into "Tokens · N things"
            // silently drops every one of them.
            && t.source != "Tokens"
            // And Bitrefill orders: each wears the product's own artwork and a
            // "name · $value" title (prd §103). They're deliberate purchases,
            // low volume — not machine bulk — so a gift-card spree stays
            // legible row by row instead of "Bitrefill · N things".
            && t.source != "Bitrefill"
            // And 1Claw grants: policies are typically created together, so
            // they share a created_at day — bundled, the grant table the
            // bridge exists to show collapses into "1Claw · N links".
            && t.source != "1Claw"
    }

    /// How many bundleable things from one source in one day collapse into a
    /// single BundleRow (lowered from 4, 2026-07-12 — smaller same-source runs
    /// were the real All-feed clutter). Named since 2026-07-31 because
    /// `bundledRowCount` has to predict this exact rule to gate the coarsening,
    /// and two copies of a literal 3 is how that prediction goes quietly wrong.
    static let bundleThreshold = 3

    /// `bundleThreshold`+ bundleable things from one source in one day collapse
    /// into a BundleRow at the position of their newest member.
    /// Order is untouched otherwise — compression, not ranking.
    /// Takes the already-computed day groups so the caller derives `dayGroups`
    /// (→`visible`→`feedThings`) ONCE per render and reuses it for the day
    /// totals too, instead of rebuilding the whole chain here a second time.
    private func bundle(_ days: [(String, [Thing])]) -> [(String, [FeedRow])] {
        days.map { label, dayThings in
            // Grouped ONCE per day (perf, 2026-07-28): the old version
            // re-filtered the whole day for every bundled source it found
            // (O(day size²) — a heavy sync day with several bundled sources
            // multiplied its own count against itself). Same membership,
            // built with one pass instead of one pass per source.
            var bySource: [String: [Thing]] = [:]
            for t in dayThings where bundleable(t) { bySource[t.source, default: []].append(t) }
            let bundledSources = Set(bySource.filter { $0.value.count >= Self.bundleThreshold }.keys)
            var rows: [FeedRow] = []
            var seen: Set<String> = []
            for t in dayThings {
                if bundleable(t), bundledSources.contains(t.source) {
                    guard !seen.contains(t.source) else { continue }
                    seen.insert(t.source)
                    let members = bySource[t.source] ?? []
                    let kinds = Set(members.map(\.kind))
                    let word = kinds.count == 1
                        ? kinds.first!.typeTagPlural.lowercased() : "things"
                    // The bundle's own pictures — the first three members
                    // that actually carry art, in feed order (newest first,
                    // since dayThings is).
                    let art = members.compactMap { m -> String? in
                        guard let a = m.previewImageURL, !a.isEmpty else { return nil }
                        return a
                    }.prefix(3)
                    rows.append(.bundle(source: t.source, word: word,
                                        count: members.count, newest: t.capturedAt,
                                        art: Array(art)))
                } else {
                    rows.append(.single(t))
                }
            }
            return (label, rows)
        }
    }

    /// The first row at-or-past the last-visit boundary — the "new since"
    /// divider renders above it. Nil when nothing is new (no divider at the
    /// very top) or everything is (no divider at the very bottom).
    ///
    /// Takes the already-bundled groups so the caller computes them ONCE per
    /// render and shares them — as a bare computed property this rebuilt the
    /// whole bundle chain, and it was read once per row (the Feed-freeze
    /// O(rows × corpus) blowup, perf pass 2026-07-13).
    private func boundaryID(in groups: [(String, [FeedRow])]) -> String? {
        guard let newSince else { return nil }
        let all = groups.flatMap(\.1)
        guard let first = all.first, first.date > newSince else { return nil }
        return all.first(where: { $0.date <= newSince })?.id
    }

    // MARK: - Body

    var body: some View {
        // Build the heavy feed tree only for the pages that need it (PERF
        // 2026-07-30 — see `nearActive`). An unreached off-screen page renders
        // a clear placeholder; the shell (`MainSurface`) paints the themed page
        // field + crown pour BEHIND the pager, so a not-yet-built page shows
        // that field, not a hole. `everBuilt` latches so a page assembled once
        // never drops back to the placeholder on a later pass.
        //
        // The keyboard walk is Mac-only, and so is everything that carries it
        // (`ShellChrome.canWalk`). The `#if` keeps the `ScrollViewReader`
        // container, the modifier's closure box and its four observers off the
        // phone entirely rather than gating them at run time — this is the
        // root of the app's deepest view tree, the one the 8MB main-stack
        // history is about, and neither iPhone nor iPad gains anything here.
        #if targetEnvironment(macCatalyst)
        return ScrollViewReader { proxy in
            page
                .modifier(KeyboardWalk(isActive: isActive, chrome: chrome,
                                       proxy: proxy, ids: walkRowIDs,
                                       open: openRowID))
        }
        .onChange(of: isActive || nearActive, initial: true) { _, want in
            if want && !everBuilt { everBuilt = true }
        }
        #else
        return page
            .onChange(of: isActive || nearActive, initial: true) { _, want in
                if want && !everBuilt { everBuilt = true }
            }
        #endif
    }

    @ViewBuilder private var page: some View {
        if isActive || nearActive || everBuilt {
            builtBody
        } else {
            Color.clear
        }
    }

    /// What ↑/↓ walk: the rows this feed ACTUALLY RENDERED, in the order it
    /// rendered them. Mac only — nothing else compiles this.
    ///
    /// The first cut published `visible`, the room's chronology, on the theory
    /// that day-grouping a newest-first array leaves the sequence untouched.
    /// True of the grouping, false of the All room — which is the room this
    /// feature is most for. `bundledSections` collapses any day's three-or-more
    /// same-source things into ONE bundle row and drops the members from the
    /// tree entirely, so walking `visible` there steps onto dozens of ids with
    /// no view: `scrollTo` finds nothing, no highlight paints, and ↓ looks dead
    /// for a run of presses on exactly the days with the most in them.
    ///
    /// So it reads `memo.groups` — the bundled row list the `ForEach` itself
    /// walks, which `boundaryID(in:)` already treats as the feed's canonical
    /// order for the same reason. Reading a memo written during body evaluation
    /// is safe here precisely because nothing reads this DURING body:
    /// `KeyboardWalk` publishes from `.onChange`, which runs after the update
    /// that filled it. Rooms that don't bundle leave the memo empty and fall
    /// back to `visible`, which for them genuinely is the render order.
    ///
    /// A BUNDLE row is skipped: it summarizes things rather than being one, so
    /// it has nothing to open in the pane. The walk steps over it.
    ///
    /// Two shapes regroup rather than bundle — Reminders splits by mark (Doing
    /// / To do / Done), Gmail lifts two "Waiting on you" rows to the top while
    /// leaving them in their day. Every row there does render, so nothing is
    /// unreachable; the walk visits them in corpus order and the list scrolls
    /// to each. Stated rather than hidden: the alternative is a second copy of
    /// every shape branch, drifting from the first the day either changes.
    ///
    /// Row ids (`String`) — the same value `FeedRow.id` and every `ForEach` key
    /// in this feed use, so the scroll target and the list's own identity are
    /// one thing rather than two kept in step by hand. Ids and never models: a
    /// `[Thing]` handed to the shell's long-lived `chrome` is the 2026-07-24
    /// crash class by construction.
    ///
    /// `isActive` guards for PERF as much as correctness — `body` evaluates for
    /// all three mounted pager pages, including the one the 2026-07-30 pass
    /// deliberately leaves unbuilt, and `visible` is the derivation that pass
    /// exists to avoid paying for off-screen.
    private var walkRowIDs: [String] {
        guard isActive else { return [] }
        guard memo.groups.isEmpty else {
            return memo.groups.flatMap(\.1).compactMap { row in
                if case .single = row.kind { return row.id }
                return nil
            }
        }
        return visible.map { $0.id.uuidString }
    }

    /// Open a walked row. Resolves against the live corpus at the moment of the
    /// keypress rather than holding a model — see `walkRowIDs`.
    private func openRowID(_ rowID: String) {
        guard let thing = visible.live.first(where: { $0.id.uuidString == rowID })
        else { return }
        openThing(thing)
    }

    /// The single surface owns the NavigationStack, the chip header, and the
    /// shared doors now (MainSurface) — this is just the feed's body, hosted
    /// inside that one stack. Its own inner push (a bridge control panel) stays
    /// here; Apps/Settings moved up to the shell.
    private var builtBody: some View {
        #if DEBUG
        let _ = LaunchPerf.buildTick(source)
        #endif
        return perfAccum("feedList[\(source)]") { feedList }
            // Re-tapping the active chip pops this surface's own pushed
            // screens and sheets back to root (the old per-tab pop habit).
            .onChange(of: chrome.popHome) {
                feedSheet = nil
                route.path = []
                confirming = nil
            }
    }

    /// The capsule's leading mark — a status glyph for every source, except
    /// Wallet with exactly one watched: that reads as its ENS face instead
    /// (avatar, or the deterministic identicon while none resolved), the
    /// same identity the multi-wallet switcher bar already wears above this
    /// capsule when there's more than one. "Connected" stops being a color
    /// and becomes a face — the wallet you're watching is a person, and this
    /// is the one spot the single-wallet feed says whose. Two-plus wallets
    /// keep the plain status glyph here (the switcher bar carries identity
    /// then), since the capsule still speaks for the WHOLE source, not one
    /// wallet in particular.
    @ViewBuilder
    private func sourceStatusMark(_ bridge: BridgeApp) -> some View {
        if bridge.name == "Wallet", wallet.addresses.count == 1, let only = wallet.addresses.first {
            WalletFace(address: only.address, size: 16, circular: true)
                .accessibilityLabel(Text("\(bridge.status.spoken). \(wallet.displayName(for: only))"))
        } else {
            // A glyph, not a bare dot: the three states were one shape
            // in three hues (2026-07-21). Sized to the old 6pt dot's
            // footprint so the header's rhythm is unchanged.
            Image(systemName: bridge.status.glyph)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(bridge.status == .connected ? DS.confirm
                                                             : bridge.status.color)
                .frame(width: 8, height: 8)
                .accessibilityLabel(Text(bridge.status.spoken))
        }
    }

    /// A slim, tappable strip above a single source's shaped feed: the app, its
    /// live status. Tapping opens the app's control panel through the router —
    /// the dedicated screen when the bridge has one (Tokens' watchlist,
    /// Wallet's addresses), the generic detail page otherwise. It rides
    /// `HomeRoute.pushBridge` — the same channel a Wallet row already
    /// uses. (2026-07-11:
    /// this hardcoded `.detail`, so Tokens' Feed header opened a page with
    /// no way to watch a second token.)
    ///
    /// A slim capsule now, not a card (2026-07-14, user: the full-width block
    /// read as a settings panel dropped into the feed). Picked from three
    /// on-sim mocks — this one echoes the Dynamic-Island-style pill already
    /// riding the top of the screen instead of introducing a new rectangular
    /// shape, and it hugs its own content instead of stretching edge to edge.
    /// The per-row brand icon is gone too (it doubled the same icon in the
    /// source chip right above) — a status dot carries connection health
    /// instead.
    private func sourceHeader(_ bridge: BridgeApp, showAddHint: Bool,
                              headerCompose: SourceAction? = nil) -> some View {
        HStack(spacing: DS.Space.s2) {
        Button {
            DSHaptic.selection()
            route.pushBridge(BridgeRouter.destination(forID: bridge.id))
        } label: {
            HStack(spacing: DS.Space.s2) {
                sourceStatusMark(bridge)
                HStack(spacing: 4) {
                    Text(bridge.name).fontWeight(.semibold).foregroundStyle(DS.textPrimary)
                    Text(bridge.statusLine)
                        .foregroundStyle(bridge.status == .connected ? DS.textSecondary : bridge.status.color)
                }
                .dsText(.subhead13)
                .lineLimit(1)
                // A watch/follow source advertises "there's more in here" — the
                // add-another action folds into this one capsule (which already
                // opens the same setup screen) rather than a second stacked row
                // (user, 2026-07-12). Compose sources keep their own row instead
                // — that action leaves for another app, a genuinely other place.
                // A 1×12 rule stood here until 2026-07-30 — the ONLY hairline
                // left in the app, against a law that takes no exceptions
                // ("No hairlines — zero exceptions"). Air separates the status
                // words from the control instead, which is what every other
                // grouping in this app already uses.
                Group {
                if showAddHint {
                    Image(systemName: "plus")
                        .accessibilityHidden(true)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DS.tint)
                } else {
                    // Names the destination (2026-07-15, user: the quiet
                    // chevron read as pure status, not a control — this
                    // capsule already says "connected", so tapping it felt
                    // unclear). "Manage" not "Settings": that word is
                    // already claimed by the global Settings screen, and
                    // these panels are add/remove/disconnect surfaces, not
                    // toggle panes.
                    Text("Manage")
                        .dsText(.subhead13).fontWeight(.medium)
                        .foregroundStyle(DS.tint)
                }
                }
                .padding(.leading, DS.Space.s1)
            }
            .padding(.horizontal, DS.Space.s3)
            .padding(.vertical, DS.Space.s2)
            .background(DS.surfaceSheet, in: Capsule(style: .continuous))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        // Compose folds into this row as a trailing pill — "New event" /
        // "New email" / "New task" — instead of a full-width bar below (user
        // ruling 2026-07-14). It leaves for another app, so it stays a
        // distinct control from the capsule; same neutral surface, tint on
        // the label alone.
        if let headerCompose {
            Spacer(minLength: DS.Space.s2)
            Button {
                DSHaptic.selection()
                if case .openURL(let url) = headerCompose.run { openExternal(url) }
            } label: {
                HStack(spacing: DS.Space.s1) {
                    Image(systemName: "plus").font(.system(size: 13, weight: .semibold))
                        .accessibilityHidden(true)
                    Text(LocalizedStringKey(headerCompose.label))
                        .dsText(.subhead13).fontWeight(.medium)
                }
                .foregroundStyle(DS.tint)
                .padding(.horizontal, DS.Space.s3)
                .frame(height: 30)
                .background(DS.surfaceSheet, in: Capsule(style: .continuous))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        }
        .padding(.horizontal, DS.Space.s4)
        // A generous gap above the capsule (2026-07-14, user: s3/12pt read as
        // still touching the chip row) — the chips are the strip, the capsule
        // is clearly its own thing below it.
        .padding(.top, DS.Space.s8)
        .padding(.bottom, DS.Space.s2)
    }

    /// The GitHub source feed's lede — "Your year in code · N contributions"
    /// and the green-squares grid, drawn on device and cached in
    /// `GitHubGraphStore` (the same store, and reusing `ContributionGraph`, that
    /// the retired Home tile used). Paints only for a real year with
    /// contributions (an empty grid is a skeleton, not content); the fetch that
    /// seeds that year runs from the List's own `.task` (see feedList), not
    /// here — a conditionally-empty view's `.task` wouldn't fire.
    @ViewBuilder private var githubGraphHero: some View {
        if let year = githubGraph.year, year.total > 0 {
            CalendarHeatmapHero(title: "Your year in code",
                                subtitle: "\(year.total.formatted()) contributions",
                                year: year)
        }
    }

    /// The prediction-market rooms lead with the live BOOK (prd §234) — the
    /// `githubGraphHero` shape (a source room's own non-corpus content, gated
    /// on the source string), but load-bearing rather than decorative: Kalshi
    /// and Polymarket have no sync, so without this the room of a freshly
    /// connected exchange is empty and there is nowhere to find a market to
    /// follow. Browsing here never writes — a market becomes a Thing (and so
    /// reaches the All feed) only on an explicit Follow.
    @ViewBuilder private var predictionBook: some View {
        if LiveRoomSources.has(source) {
            PredictionRoomBook(source: source) { feedSheet = .market($0) }
        }
    }

    private var feedList: some View {
        List {
            Group {
                // The source chips moved to the shell's fixed header
                // (MainSurface / SourceChips) — the app is one surface now.
                // The kind-clear "× Links" chip that used to sit here is GONE
                // (user, 2026-08-01: "i do not want to see the x chips those
                // are supposed to be internal only"). A kind filter still
                // exists — the agent sets it when an ask names a kind ("show
                // my links") — it just never asks the person to manage it: the
                // day-section header already names it (`filterLabel`), and any
                // source chip tap clears it, INCLUDING a re-tap of the source
                // already showing, which is the one-gesture way out that the
                // chip used to be (see `MainSurface.go(to:)`).
                // The door back to the app: when the feed wears one connected
                // source's shape, its header opens that app's control panel
                // (Pause/Remove/ask/Reconnect) — the reverse of the detail's
                // "All in Feed". It lives inside this always-present group so it
                // inserts reliably on mount (a standalone conditional row won't).
                if let bridge = activeSourceBridge {
                    let action = SourceActions.action(forSource: bridge.name)
                    // Both actions fold into the header row now (user ruling
                    // 2026-07-14: the full-width compose bar read as an empty
                    // stretch). Expand (add-another) is a "+" hint inside the
                    // capsule — same setup screen the capsule already opens.
                    // Compose is a trailing labeled pill — it leaves for another
                    // app, a genuinely other place, so it stays a distinct
                    // control beside the capsule, not folded into it. Read-only
                    // sources get neither.
                    let composeAction: SourceAction? = {
                        if let action, case .openURL = action.run { return action }
                        return nil
                    }()
                    let showsAddHint: Bool = {
                        if let action, case .route = action.run { return true }
                        return false
                    }()
                    sourceHeader(bridge, showAddHint: showsAddHint,
                                 headerCompose: composeAction)
                }
                // GitHub's source feed leads with its contribution graph (moved
                // off Home, 2026-07-18). Gated on the source STRING, not the
                // BridgeStore seat — the graph belongs to GitHub's token
                // (`GitHubGraphStore` self-fetches with it), so it rides the
                // GitHub feed whenever it's the filter; the hero self-checks for
                // a landed year and takes no room otherwise.
                if source == "GitHub" { githubGraphHero }
                predictionBook
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets())

            // A live-room source paints its book above, so the corpus being
            // empty is NOT an empty room — "Let's fill this feed" over a
            // full market book would be nonsense (prd §234).
            // `hasSurfaced` short-circuits — no full `Corpus.surfaced` alloc
            // just to test emptiness (PERF 2026-07-29), and it was allocated
            // twice here per body eval.
            let roomHasContent = Corpus.hasSurfaced(things)
            if !roomHasContent && !LiveRoomSources.has(source) {
                Group { emptyState }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
            } else if roomHasContent {
                // Derived ONCE per render and threaded into everything below
                // — the day groups, ledes, and per-row hint/next-event ids
                // all share this one filter pass instead of each re-deriving
                // it from `feedThings` (the Feed-freeze rule, perf pass
                // 2026-07-13, extended to `visible` itself).
                let visible = self.visible
                if visible.isEmpty {
                    Group { filteredEmptyState }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets())
                } else {
                    let nextID = nextEventID(visible)
                    // A pin is a HOME pin only (ruling 2026-07-10): the Feed's
                    // own Pinned section doubled what Home already shows and
                    // cluttered the record — pinned things now ride the feed in
                    // their natural chronological place. The holdings module
                    // lives on Home too (same-day amendment) — in Feed it shows
                    // only in the Wallet chip's own shape, never leading All.
                    shapedSections(visible, nextEventID: nextID)
                    // No closing line in the Reminders shape: its state groups
                    // deliberately render a subset (Done shows same-day only), so
                    // a `visible`-count claim would disagree with the rows above.
                    // Wallet joined it (2026-07-20) for the same reason — it
                    // previews five and hands off to the history page, so
                    // "that's everything · 131 transactions" under five rows was
                    // a flat lie. Its own "See all transactions · 131" row is
                    // the honest close. Calendar joined them conditionally
                    // (2026-07-27): with past events collapsed the room shows
                    // a subset too, and its disclosure row ("Show 12 past
                    // events") is that subset's honest close — expanded, the
                    // room is whole again and the line comes back.
                    // "That's everything" is a CLAIM, so it waits until the
                    // room really is whole (prd §264). While a window is open
                    // the `olderRow` is what sits at the bottom instead.
                    if shape != .reminders && shape != .wallet
                        && !hidesPastEvents(visible) && !memo.windowHasMore {
                        caughtUpFooter(visible)
                    }
                }
            }

            // Room for the floating bar.
            Color.clear.frame(height: ShellMetrics.bottomInset - 40)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        // ONE pull, both outcomes. This List carried TWO `.refreshable` until
        // 2026-07-16 — SwiftUI keeps the outermost, so the real bridge sync
        // never ran on a pull; only the 600ms pulse stub did.
        .refreshable { await performPull() }
        // Mac's ⌘R (2026-07-28): a trackpad overscroll gesture is the only
        // trigger `.refreshable` gives Catalyst, and it isn't reliably
        // discoverable with a mouse — this runs the identical pull, just
        // triggered from the menu bar instead of a gesture.
        .onChange(of: chrome.refreshRequest) { _, _ in
            guard isActive else { return }
            Task { await performPull() }
        }
        .animation(DS.Motion.standard, value: listRevision)   // new things rise in (debounced for All)
        .scrollContentBackground(.hidden)
        .dsAdaptiveContentWidth()
        // Seed/refresh the contribution year from a RELIABLE always-present spot
        // (the conditionally-empty hero's own `.task` doesn't fire until a year
        // lands — chicken-and-egg). `source` is fixed per feed instance, so this
        // runs once when the GitHub feed appears; `refreshIfStale` self-guards.
        .task { if source == "GitHub" { await githubGraph.refreshIfStale() } }
        // Drives `debouncedAllSnapshot` (see its doc above) — `.task(id:)`
        // cancels and restarts on every `@Query` emission, so only the LAST
        // save in a refresh burst survives its sleep and actually publishes;
        // every emission in between is superseded before its sleep completes.
        // `things.count` alone (not a full signature) is a deliberate choice:
        // a pure in-place heal patch (a decoded title, a backfilled icon)
        // doesn't change count and so won't repaint instantly here — an
        // acceptable lag for a cosmetic fixup, and it repaints on the very
        // next count-changing emission regardless.
        .task(id: things.count) {
            guard source == "All", filter.tag == "All" else { return }
            guard debouncedAllSnapshot != nil else {
                let first = liveVisible()              // first paint: no delay
                allSnapshotKey = snapshotSignature(first)
                debouncedAllSnapshot = first
                return
            }
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch { return }   // superseded by a newer emission
            guard !Task.isCancelled else { return }
            let next = liveVisible()
            allSnapshotKey = snapshotSignature(next)
            debouncedAllSnapshot = next
        }
        // The page coat moved UP to the shell (prd §159, 2026-07-21): the crown
        // pour lives in MainSurface's background so it can run behind the chip
        // strip, and painting the opaque themed coat again HERE would slide
        // black between that field and the content — the exact hard seam the
        // first, page-level cut of the pour produced (§158's version, retired
        // the same day). Only a chosen background PHOTO still renders
        // per-screen: it's the person's own atmosphere, covers the pour on
        // purpose, and DSPageBackground's scrim is part of its treatment.
        .background {
            if ThemeStore.shared.backgroundPhoto != nil { DSPageBackground() }
        }
        .environment(\.defaultMinListHeaderHeight, 0)
        .scrollIndicators(.hidden)
        .minimizesChrome(chrome, active: isActive)
        // The pull's WIND-UP feed (2026-08-04): raw top overscroll, which
        // `minimizesChrome`'s observer deliberately filters out (`new > 60`),
        // so this is its own geometry read. The avatar door rotates with it —
        // tension before the release spin. Sub-point jitter is dropped, and
        // Reduce Motion never writes, so the door stays still there.
        .onScrollGeometryChange(for: CGFloat.self) { geo in
            max(0, -(geo.contentOffset.y + geo.contentInsets.top))
        } action: { _, new in
            guard isActive, !reduceMotion else { return }
            let clamped = min(new, 140)
            guard abs(chrome.pullTension - clamped) > 0.5 else { return }
            chrome.pullTension = clamped
        }
        .safeAreaInset(edge: .top, spacing: 0) { walletSwitcherBar }
        .dsSoftScrollEdges()
        // Arrival is `isActive`, not `onAppear` (2026-07-16, the pager): a
        // mounted neighbour appears without ever being looked at, so landing
        // effects hang off the front page changing, and leaving stamps the
        // boundary on the way out.
        .onAppear {
            #if DEBUG
            // `-feedSource Zerion` lands on that chip for screenshots. From
            // the front page only — three mounted pages would each write it.
            if isActive, let src = UserDefaults.standard.string(forKey: "feedSource") {
                filter.source = src
            }
            #endif
            if isActive { land() }
        }
        .onDisappear { if visitFrozen { leave() } }
        .onChange(of: isActive) { _, now in
            if now { land() } else { leave() }
        }
        // Adding/removing a watched wallet re-fetches the Wallet chip's
        // holdings block — only on the page in force; a background Wallet
        // page has no reason to re-hit Alchemy.
        .onChange(of: wallet.addresses) {
            // A scope whose wallet dropped (or the list fell back to one)
            // returns to All rather than stranding the feed on a gone wallet.
            if let sel = selectedWallet,
               wallet.addresses.count <= 1
                || !wallet.addresses.contains(where: { walletSameAddress($0.address, sel) }) {
                selectedWallet = nil
            }
            if isActive { streamBlock(); loadWalletLive() }
        }
        // Scoping to a wallet (or back to All) re-paints the treemap/NFT strip
        // AND re-reads the live tiles for that scope; the rows and balance
        // re-derive from state.
        .onChange(of: selectedWallet) {
            if isActive {
                streamBlock(); loadWalletLive()
                // A scope switch retints the crown mid-flight with the
                // switcher capsule (prd §159).
                chrome.pourHue = selectedWallet.map(WalletFace.tint)
            }
        }
        .navigationDestination(item: $openProject) { route in
            ProjectDetailScreen(projectName: route.name)
                .navigationTransition(.zoom(sourceID: route.name, in: zoomNS))
        }
        // The social roster's own door (item 2, 2026-07-27) — a face pushes
        // the person room, not the quick-glance tray `SocialProfileCard`
        // still serves everywhere else.
        .navigationDestination(item: $openPerson) { profile in
            PersonRoomScreen(profile: profile)
        }
        // A raised sheet owns the keyboard (Mac, 2026-07-31 — see
        // `ShellChrome.canWalk`). It matters most where the detail pane
        // ISN'T: a Mac window narrower than `PadLayout.minWidthForPane` opens
        // every row as one of these, and the walk staying live underneath
        // would keep ↑/↓/Return off the sheet that's actually in front.
        .onChange(of: feedSheet != nil) { _, open in
            guard isActive else { return }
            chrome.walkSheetOpen = open
        }
        // One `.sheet(item:)` for every sheet this screen presents — see
        // `FeedSheetRoute`'s doc comment for why five separate `.sheet`
        // modifiers here caused the first tap to silently self-dismiss.
        .sheet(item: $feedSheet) { route in
            switch route {
            case .thing(let thing):
                // Zoom transition DROPPED for thing opens (2026-07-30, prd
                // ruling 232): a beta tester on build 225 hit a deterministic crash
                // opening any photo ("every photo, instantly, every time")
                // that never reproduced for the dev or on the simulator —
                // headless open, the real tile-tap zoom, and the sheet content
                // path were all verified clean. That profile — universal for
                // one device, invisible everywhere else — is an OS/device-
                // specific `.navigationTransition(.zoom)` fault, the one
                // fragile system API in an otherwise clean path. The zoom is
                // decorative; the standard sheet present is the safe fallback.
                // The matching `matchedTransitionSource` sources were removed
                // with it. Restore only once a symbolicated stack proves a
                // different cause.
                ThingSheetView(thing: thing)
            case .token(let route):
                TokenQuickSheet(route: route)
            case .allocation:
                if let portfolio {
                    WalletAllocationTray(portfolio: portfolio)
                }
            case .worthALook:
                WalletWorthALookTray(
                    warnings: walletLive.warnings,
                    flagged: walletLive.flagged,
                    activeApprovals: walletLive.activeApprovals)
            case .deposits(let composition):
                WalletDepositsTray(composition: composition)
            case .locks(let composition):
                WalletLocksTray(composition: composition)
            case .market(let preview):
                PredictionPreviewSheet(preview: preview)
            }
        }
        #if !targetEnvironment(macCatalyst)
        .translationPresentation(isPresented: $showTranslate, text: translateText)
        #endif
        .confirmationDialog(
            // Guard the held `Thing` with `isLive` (2026-07-24 crash class):
            // a background heal can delete this exact thing while the dialog
            // sits open, and reading `$0.1.title` on a dead model traps. If it
            // dies, the presentation binding flips false and the dialog leaves.
            confirming.map { $0.1.isLive ? "\($0.0.label): \($0.1.title)?" : "" } ?? "",
            isPresented: Binding(get: { confirming?.1.isLive == true },
                                 set: { if !$0 { confirming = nil } }),
            titleVisibility: .visible
        ) {
            if let (verb, thing) = confirming, thing.isLive {
                Button(verb.label) { if thing.isLive { perform(verb, on: thing) }; confirming = nil }
                Button("Cancel", role: .cancel) { confirming = nil }
            }
        }
    }

    // MARK: - Shaped sections (one source in force = its native shape)

    /// Takes the render's one `visible` derivation (and the hint/next-event
    /// ids computed alongside it) and threads them into every shape branch —
    /// none of the branches below re-derive `visible` themselves.
    @ViewBuilder
    private func shapedSections(_ allVisible: [Thing], nextEventID: UUID?) -> some View {
        // THE LANE STRIP SCOPES EVERYTHING BELOW IT, head included (2026-08-06).
        // Narrowed here, once, rather than at each reader: a head still
        // describing the whole marketplace over rows you just filtered would be
        // two surfaces disagreeing on screen.
        //
        // A chip reaches ANY lane a seller sells into, which is the capability
        // the shelves structurally cannot offer — they file each seller under
        // one primary lane, so Prediction markets and Creative have no shelf at
        // all despite having real members, and were unreachable by any means.
        let visible = shape == .x402 ? x402Scoped(allVisible) : allVisible
        if shape == .x402 { x402LaneStrip }
        // The new-since divider rides every chronological shape now
        // (2026-07-13) — each source's feed keeps its own last-visit stamp.
        // Photos (a grid), Calendar (future-first) and Reminders (state
        // groups) aren't chronological top-to-bottom, so no line there.
        //
        // A per-source feed overview leads the rows — derived from THIS feed's
        // own things (the same `visible`), above whatever shape they take below.
        // Each source qualifies for at most one: a habit heatmap, a ranked-bars
        // leaderboard, a distribution bar, or a thumbnail mosaic. All render only
        // when the real data is there (guards live in FeedHeatmap / FeedInsight).
        // Derived once and reused: `heroShown` lets a shape's own recap lede
        // (music's "today", Gmail's "waiting") yield so a feed never stacks two
        // overview cards — the lede's records still ride the rows below.
        //
        // Live outranks every aggregate (§164's one exception, cashed in by
        // prd §219): a stream that is ON RIGHT NOW takes the head at frame
        // size. `thing.isLive` here is the SwiftData liveness guard (COROLLARY
        // 2 — the hero holds this reference across renders and a heal pass can
        // delete under it); `isLive(_:)` is the Twitch broadcast set. Both,
        // in that order.
        let liveStream = visible.first { $0.isLive && isLive($0) }
        // The social room's own head (item 5, 2026-07-27) — faces, ringed on
        // fresh activity, beat `FeedHeatmap`'s pre-existing "Casting
        // activity"/"Posting activity" density grid for Farcaster/Bluesky
        // (corrected 2026-07-27: the grid was winning this exact priority
        // chain silently, so the roster built for item 5 had never actually
        // rendered — a density grid says nothing a face with a ring doesn't
        // already say better).
        let rosterAccounts: [SocialAccount] = liveStream == nil && shape == .social
            ? (source == "Farcaster" ? FarcasterStore.shared.socialAccounts : BlueskyStore.shared.socialAccounts)
            : []
        // THE PER-SOURCE HEADS — the rooms whose lede can only come from that
        // room's own model, because the registries below are pure over `Thing`
        // and these facts aren't in the corpus: Cloudflare's certificate dates,
        // Stripe's balance, PostHog's metric readings all live in bridge state.
        //
        // Gathered into ONE term rather than one `let` per card (2026-08-04).
        // Each gate below re-states every predecessor by hand, so three
        // separate lets would mean editing five gates to add a card and
        // silently mis-ranking it if you missed one. They can never compete
        // with each other — each claims exactly one source — so one term is
        // also the honest shape.
        //
        // These sit directly under the live exception because nothing else can
        // claim these rooms: no registry below names any of the three, so the
        // chain would fall through to a blank head. Cloudflare's is also the
        // one card here that renders on an EMPTY room, which is the whole
        // reason it exists — see `CloudflareRunway`.
        let sourceHead = liveStream == nil ? sourceHead(visible) : nil
        // (The All feed's cross-source "thread" head lived here for one day and
        // was DELETED, prd §333. It ranked a shared WORD as a subject, so its
        // headline read "Wallet" over a Files row, an x402 blurb containing
        // "wallet flow", and two of the person's own commit messages about
        // building the Apple Wallet bridge. That is the deterministic
        // co-occurrence card §36c already removed once for manufacturing
        // connections — see `HomeInsightStore`, whose doc says a real version
        // "would be a fresh build, not a revival of this." The All feed leads
        // with the themes treemap again, which claims only what it measures.)
        // The anniversary, when it's a PICTURE (2026-07-31). Scoped to the
        // memories room on purpose: everywhere else `OnThisDay` rides inside
        // the heatmap card, where a title represents the thing perfectly, and
        // widening this to every source would silently re-rank rooms nobody
        // has looked at yet. Here the thing is a photograph from this exact
        // day years ago, which is worth more than any standing fact the room
        // can state — and it's nil on nearly every day, so it takes the head
        // rarely rather than owning it.
        // Derived ONCE and shared with the grid below — the memories room asks
        // this set twice (which picture leads, and which rows are tiles) and
        // walking `visible` per question is the shape the 2026-07-13 feed
        // freeze was made of. Empty for every other room, so it costs nothing
        // there.
        let memoryTiles = shape == .snapchat ? visible.live.filter(Self.isMemoryTile) : []
        let anniversary: OnThisDay.Echo? = liveStream == nil && shape == .snapchat
            ? OnThisDay.find(in: memoryTiles) : nil
        // The OCR/text treemap (2026-07-30) — what the screenshots are ABOUT,
        // and since 2026-07-31 what an Instagram export's own captions and
        // comments are about. When there's too little text to say anything it
        // returns nil and the next card down takes the head.
        let topicMap = liveStream == nil && sourceHead == nil && anniversary == nil && rosterAccounts.isEmpty
            ? FeedInsight.topicMap(source: source, things: visible) : nil
        let leaderboard = liveStream == nil && sourceHead == nil && anniversary == nil && topicMap == nil && rosterAccounts.isEmpty
            ? FeedInsight.leaderboard(source: source, things: visible) : nil
        let distribution = liveStream == nil && sourceHead == nil && anniversary == nil && topicMap == nil
            && leaderboard == nil && rosterAccounts.isEmpty
            ? FeedInsight.distribution(source: source, things: visible) : nil
        let mosaic = liveStream == nil && sourceHead == nil && anniversary == nil && topicMap == nil
            && leaderboard == nil && distribution == nil && rosterAccounts.isEmpty
            ? FeedInsight.mosaic(source: source, things: visible) : nil
        // The heatmap sits LAST (moved 2026-07-31), not third. It answers
        // WHEN, which is the weakest thing a room can lead with — every card
        // above it names a WHO or a WHAT — and its label comes from a static
        // registry, so it can never decline the slot the way the derived cards
        // do. Third, it silently owned every room it was registered for; the
        // §219 social-roster bug was exactly that, caught late. Nothing
        // changes for any source that shipped before this: no source in the
        // registry qualifies for a leaderboard, distribution or mosaic (the
        // sets don't intersect), so each still draws the one card it always
        // drew. Instagram and Snapchat are the first sources with two facts
        // to choose between, and for them the grid is the graceful fallback —
        // the role it already plays for Photos under the treemap.
        let heatmapLabel = liveStream == nil && rosterAccounts.isEmpty && anniversary == nil
            && topicMap == nil && leaderboard == nil && distribution == nil && mosaic == nil
            && sourceHead == nil
            ? FeedHeatmap.label(for: source) : nil
        let heroShown = liveStream != nil || anniversary != nil || topicMap != nil
            || heatmapLabel != nil || leaderboard != nil || sourceHead != nil
            || distribution != nil || mosaic != nil || !rosterAccounts.isEmpty
        if let liveStream {
            insightSection { LiveStreamHero(thing: liveStream) { openThing(liveStream) } }
        } else if let sourceHead {
            // Each card holds no `Thing` — it hands back its own value and the
            // lookup happens HERE, against the live corpus, in the view that
            // owns the sheet.
            insightSection {
                switch sourceHead {
                case .runway(let runway):
                    CloudflareRunwayCard(runway: runway) { item in
                        openBySourceRef(item.id, in: visible)
                    }
                case .stripe(let room):
                    StripeRoomCard(room: room) { item in
                        openBySourceRef(item.id, in: visible)
                    }
                case .posthog(let room):
                    PostHogRoomCard(room: room) { event in
                        openBySourceRef(PostHogWatch.metricRef(event), in: visible)
                    }
                case .appleWallet(let room):
                    // Opens by MERCHANT rather than by `sourceRef`: the card
                    // ranks a merchant across many charges, so there is no one
                    // row it names — the honest tap is "show me this merchant",
                    // which is the tag filter the room already supports.
                    AppleWalletRoomCard(room: room) { merchant in
                        openMerchant(merchant, in: visible)
                    }
                case .x402(let room):
                    X402RoomCard(room: room) { slug in
                        openBySourceRef("x402:\(slug)", in: visible)
                    }
                case .appStoreConnect(let room):
                    AppStoreConnectRoomCard(room: room) { app in
                        openNewest(source: ASCShape.source, in: visible) { thing in
                            // The card ranks an APP, which owns many rows, so
                            // it can't name a `sourceRef` — the honest landing
                            // is that app's most recent row, matched on the
                            // link every one of its rows carries (the Apple
                            // Wallet merchant rule).
                            thing.content.contains("/apps/\(app.id)")
                        }
                    }
                case .cursor(let room):
                    CursorRoomCard(room: room) { repo in
                        // The card ranks a REPOSITORY, which owns many rows, so
                        // it can't name a `sourceRef` — the honest landing is
                        // that repo's most recent run, matched on the stored
                        // `authorHandle` (the App Store Connect app rule, one
                        // field over).
                        openNewest(source: CursorRoomSource.source, in: visible) { thing in
                            thing.authorHandle == repo.name
                        }
                    }
                }
            }
        } else if let anniversary {
            insightSection {
                OnThisDayHero(echo: anniversary) { feedSheet = .thing(anniversary.thing) }
            }
        } else if let topicMap {
            insightSection { TopicMapHero(map: topicMap) }
        } else if let leaderboard {
            insightSection { LeaderboardHero(board: leaderboard) }
        } else if let distribution {
            insightSection { DistributionHero(dist: distribution) }
        } else if let mosaic {
            insightSection { ImageMosaicHero(mosaic: mosaic) }
        } else if let heatmapLabel {
            calendarHeatmapSection(visible, label: heatmapLabel)
        } else if !rosterAccounts.isEmpty {
            // Fresh = a post landed after this room's own last-visit stamp
            // (`newSince`, the same one the new-since divider rides).
            let freshHandles: Set<String> = newSince.map { since in
                Set(visible.compactMap { $0.capturedAt > since ? $0.authorHandle : nil })
            } ?? []
            // Richer roster (2026-08-08): who's actually been active in this
            // room, not insertion order — a watched account with nothing
            // landed shouldn't outrank one leading the feed. Purely derived
            // from `visible` (the room's own things, already boundary-
            // filtered live), no new field/request/store — the same
            // discipline `FeedInsight`'s other readings follow.
            let postCounts: [String: Int] = visible.reduce(into: [:]) { counts, thing in
                guard let handle = thing.authorHandle, !handle.isEmpty else { return }
                counts[handle, default: 0] += 1
            }
            // Stable sort (Swift's `sorted` guarantee): ties keep the
            // account list's own order rather than reshuffling on every
            // re-render over equal counts.
            let rankedAccounts = rosterAccounts.sorted { a, b in
                let ca = postCounts[a.key] ?? 0, cb = postCounts[b.key] ?? 0
                if ca != cb { return ca > cb }
                let fa = freshHandles.contains(a.key), fb = freshHandles.contains(b.key)
                return fa && !fb
            }
            insightSection {
                SocialRosterHero(source: source, accounts: rankedAccounts,
                                  freshHandles: freshHandles) { account in
                    DSHaptic.tap()
                    openPerson = SocialProfile(source: source, handle: account.key,
                                               displayName: account.title, bio: nil,
                                               avatarURL: account.avatarURL)
                }
            }
        }
        switch shape {
        case .photos:
            photoGridSection(visible)
        case .snapchat:
            // The memories whose pictures actually came back lead as a grid;
            // everything else — saved chats, videos (never fetched, see
            // `SnapchatImport`), and memories whose 7-day download window
            // closed before anyone pressed Get pictures — reads as rows.
            // The split is the honest one: a tile promises a picture, so a
            // row with no pixels stays a dated entry rather than a grey well
            // pretending to be a photograph.
            let rest = visible.live.filter { !Self.isMemoryTile($0) }
            if !memoryTiles.isEmpty { photoGridSection(memoryTiles) }
            let days = chronoGroups(rest)
            groupedSections(days, nextEventID: nextEventID, boundary: boundaryThingID(in: days))
        case .files:
            // The Snapchat split for a connected folder (2026-08-02): images
            // whose heal has landed a thumbnail lead as a grid, everything
            // else — PDFs, text files, and images the throttled heal (40
            // thumbnails a pass) hasn't reached yet — reads as rows until it
            // has pixels to show. Same honesty rule as above: a tile promises
            // a picture.
            let imageTiles = visible.live.filter(Self.isFileImageTile)
            let rest = visible.live.filter { !Self.isFileImageTile($0) }
            if !imageTiles.isEmpty { photoGridSection(imageTiles) }
            let days = chronoGroups(rest)
            groupedSections(days, nextEventID: nextEventID, boundary: boundaryThingID(in: days))
        case .wallet:
            // The reads first, then the stream (2026-07-20, the surface split):
            // balance + warnings side by side, the holdings treemap, DeFi, and
            // only then the transactions — capped, with a door to all of them.
            // Everything above the rows is live state, never a landed thing.
            // (The wallet switcher isn't here: it PINS over the stream via
            // safeAreaInset — a scoping control has to stay reachable when
            // you're deep in the transactions it scopes.)
            walletTilesSection(visible)
            // Answers the question the balance card's own delta pill raises,
            // before the map changes the subject to composition (2026-08-01).
            walletFlowSection
            holdingsBlockSection
            walletRiskSection
            walletDeFiSection
            walletLiquiditySection
            walletPerpsSection
            // Last of the state cards: everything above is what your money is
            // doing, this is who else can reach it (prd §292).
            walletApprovalsSection
            // What's still AHEAD, before the history (2026-07-31). The stream
            // below reads backwards from today; these rows are dated forwards,
            // and nothing else in the app shows them any more — see
            // `walletUpcoming` for why they were effectively invisible.
            let upcoming = walletUpcoming(visible)
            walletComingUpSection(upcoming)
            // Promoted rows leave the stream, or the same deadline would be
            // read twice on one screen — once as what's coming and once as
            // whenever it happened to land.
            let promoted = Set(upcoming.map(\.id))
            let all = visible.live.filter { !promoted.contains($0.id) }
            let preview = walletStreamRows(all)
            walletStreamSections(preview, nextEventID: nextEventID)
            walletSeeAllSection(total: all.count)
        case .calendar:
            calendarSections(visible, nextEventID: nextEventID)
        case .gmail:
            if !heroShown { waitingSection(visible, nextEventID: nextEventID) }
            let days = chronoGroups(visible)
            groupedSections(days, nextEventID: nextEventID, boundary: boundaryThingID(in: days))
        case .reminders:
            reminderSections(visible, nextEventID: nextEventID)
        case .music:
            if !heroShown { listeningLedeSection(visible) }
            // Sessions, not days (2026-07-21) — a listening sitting is music's
            // real unit; boundary rides the same capturedAt-keyed helper.
            let days = sessionGroups(visible)
            groupedSections(days, nextEventID: nextEventID, boundary: boundaryThingID(in: days))
        case .x402:
            // Lanes, not days — see `x402Lanes`. No `boundary:`, deliberately:
            // the new-since divider is a chronological mark, and in a room
            // where every row shares one timestamp it would land arbitrarily.
            groupedSections(x402Lanes(visible), nextEventID: nextEventID)
        case .cursor:
            // Repositories, not days — see `cursorRepos`. Keeps `boundary:`,
            // unlike x402: these rows carry the run's REAL start, so they span
            // real time and the new-since divider means something.
            let repos = cursorRepos(visible)
            groupedSections(repos, nextEventID: nextEventID,
                            boundary: boundaryThingID(in: repos))
        case .tokens:
            watchlistLedeSection(visible)
            watchlistSection(visible, nextEventID: nextEventID)
        case .safari:
            // A reading list is doors, not reads (2026-07-21) — its lede owns
            // the return-trip guilt: how much is piling up, and the oldest
            // thing still waiting. Rows below stay chronological (coarsened
            // when saves are sparse, like any door source).
            if !heroShown { readingLedeSection(visible) }
            let days = chronoGroups(visible)
            groupedSections(days, nextEventID: nextEventID, boundary: boundaryThingID(in: days))
        case .bitrefill:
            bitrefillLedeSection(visible)
            let days = chronoGroups(visible)
            groupedSections(days, nextEventID: nextEventID, boundary: boundaryThingID(in: days))
        case .oneclaw:
            oneclawLedeSection(visible)
            let days = chronoGroups(visible)
            groupedSections(days, nextEventID: nextEventID, boundary: boundaryThingID(in: days))
        default:
            if filter.tag != "All" && shape == .all {
                daySection(filterLabel, visible, nextEventID: nextEventID)
            } else if shape == .all {
                // The Themes treemap leads the unfiltered All room (2026-07-18,
                // moved off Home) — a cross-source overview, so it only makes
                // sense over the WHOLE corpus, not a kind-filtered slice (the
                // `if` branch above).
                //
                // Yields to the cross-source THREAD head when one fired
                // (2026-08-07): both are cross-source overviews and the design
                // forbids stacking two (`heroShown`). The thread is the
                // specific, timely lead; the themes map is the standing one —
                // so the thread wins the slot, and the map returns on every day
                // no thread forms. (Also closes a latent double-stack: a live
                // stream landing in the All feed already set `heroShown`.)
                if !heroShown { themesLedeSection(visible) }
                // All is where volume floods — bundles + the new-since
                // divider live here. A single source's shape IS that source;
                // bundling there would collapse the whole screen into one row.
                bundledSections(visible, nextEventID: nextEventID)
                corpusFloorSection(visible)
            } else {
                // Threads fold BEFORE day-grouping (item 6, 2026-07-27): a
                // person's own consecutive replies collapse into one card in
                // their room, so `roomThings` (fewer rows than `visible`)
                // feeds the existing day/ForEach pipeline unchanged, and
                // `threadReplies` rides beside it for `shapedRow` to render
                // inline. Scoped to `.social` — every other shape's `visible`
                // passes through untouched.
                let (roomThings, threadReplies): ([Thing], [String: [Thing]]) =
                    shape == .social ? foldThreadReplies(visible) : (visible, [:])
                // Live-first in a source's own room (2026-07-21): a stream
                // that's on RIGHT NOW is the one row whose relevance isn't
                // chronological, so it leads its group. No-op for sources
                // with no live set.
                let days = chronoDays(roomThings)
                groupedSections(days, nextEventID: nextEventID, boundary: boundaryThingID(in: days),
                                replies: threadReplies)
            }
        }
    }

    /// A SOURCE room's day grouping, memoized (PERF 2026-08-01, prd §263).
    ///
    /// The All room's grouping has been memoized since §258; every OTHER room
    /// recomputed `chronoGroups` from scratch on each body evaluation, and every
    /// mounted page re-evaluates whenever `filter.source` changes — i.e. on
    /// every swipe. Measured with `sample` (the only instrument here that sees
    /// row-closure work at all): `chronoGroups` 165 samples + `dayGroups` 124
    /// on a 4,000-row corpus.
    ///
    /// This was tried once before and recorded as "neutral", which was a
    /// measurement artifact: it was judged with a `perfAccum` timer wrapped
    /// around a view-building property, and SwiftUI evaluates the `ForEach`
    /// content closure AFTER that property returns, so the timer could not see
    /// the work either way. Same change, real instrument, different answer.
    ///
    /// Shares `DerivationMemo` with `bundledSections` safely: a given
    /// `FeedScreen` has a fixed `source` and takes one branch or the other
    /// consistently, and `filter.tag` — the one input that moves it between
    /// them — is part of the key.
    private func chronoDays(_ roomThings: [Thing]) -> [(String, [Thing])] {
        let key = derivationKey(roomThings)
        if memo.key != key {
            memo.key = key
            memo.days = liveFirst(chronoGroups(roomThings))
            memo.groups = []        // this path renders things, not bundled rows
        }
        return memo.days
    }

    /// The first thing at-or-past the last-visit boundary in a shaped feed's
    /// day groups — the Thing twin of `boundaryID(in:)` (which speaks FeedRow,
    /// All's bundled currency). Same freeze semantics: computed ONCE per
    /// render by the caller and passed down, never re-derived per row.
    private func boundaryThingID(in groups: [(String, [Thing])]) -> UUID? {
        guard let newSince else { return nil }
        let all = groups.flatMap(\.1)
        guard let first = all.first, first.capturedAt > newSince else { return nil }
        return all.first(where: { $0.capturedAt <= newSince })?.id
    }

    /// Music's lede: today's listening, covers lapped, count honest (the
    /// distinct songs that landed today — recently-played dedupes per song).
    @ViewBuilder
    private func listeningLedeSection(_ visible: [Thing]) -> some View {
        let today = visible.filter { Self.groupingCalendar.isDateInToday($0.capturedAt) }
        if !today.isEmpty {
            ledeSection(ListeningLede(
                covers: today.compactMap(\.previewImageURL).filter { !$0.isEmpty },
                count: today.count))
        }
    }

    /// Tokens' lede: the watchlist's 24h at a glance — from the SAME cached
    /// pulses the rows wear, so the summary can never disagree with the rows.
    /// Two watched tokens minimum: one token's row already says everything.
    @ViewBuilder
    private func watchlistLedeSection(_ visible: [Thing]) -> some View {
        let pulses = visible.compactMap { TokenPulse.shared.pulse(for: $0) }
        if pulses.count >= 2 {
            // Flat (exactly 0) is neither up nor down — "2 up" for two
            // stablecoins would claim a gain that didn't happen (honesty).
            ledeSection(WatchlistLede(
                up: pulses.filter { $0.change24h > 0 }.count,
                down: pulses.filter { $0.change24h < 0 }.count))
        }
    }

    /// Bitrefill's lede: the account at a glance — the balance its API last
    /// reported, and how many orders landed this month (from the same rows
    /// below, so the two can't disagree). Connected-only: a disconnected
    /// seat must not wear yesterday's balance as if it were current.
    @ViewBuilder
    private func bitrefillLedeSection(_ visible: [Thing]) -> some View {
        if TokenBridge.bitrefill.connected, let balance = BitrefillBalance.formatted {
            let month = visible.filter {
                BitrefillFetch.isOrderRef($0.sourceRef)
                    && Self.groupingCalendar.isDate($0.capturedAt, equalTo: .now,
                                                    toGranularity: .month)
            }.count
            ledeSection(BitrefillLede(balance: balance, monthCount: month))
        }
    }

    /// 1Claw's lede: the key's reach at a glance — the vault count its API
    /// last reported, and how many grants landed as rows below (counted from
    /// the same rows, so the two can't disagree). Connected-only: a
    /// disconnected seat must not wear yesterday's reach as if it were
    /// current.
    @ViewBuilder
    private func oneclawLedeSection(_ visible: [Thing]) -> some View {
        if TokenBridge.oneclaw.connected, let vaults = OneClawAccess.formatted {
            let grants = visible.filter { OneClawFetch.isGrantRef($0.sourceRef) }.count
            ledeSection(OneClawLede(vaults: vaults, grantCount: grants))
        }
    }

    /// The watchlist's OWN order, not chronology (2026-07-15) — day headers
    /// answer "when did I watch this", a question that stops mattering once
    /// there's more than a couple of tokens; what you actually want is what
    /// MOVED, or the order you dragged it into (TokenWatchOrder — the same
    /// shared choice the settings screen and Home's tile read). One flat
    /// section, no day breaks; the "new since" divider drops with it — it's
    /// a chronological-feed idea, and this list may no longer read top to
    /// bottom by time.
    @ViewBuilder
    private func watchlistSection(_ visible: [Thing], nextEventID: UUID?) -> some View {
        let ordered = TokenWatchOrder.shared.apply(
            visible, sourceRef: \.sourceRef,
            change24h: { TokenPulse.shared.pulse(for: $0)?.change24h })
        // One flat run: pulsed tokens wear the fat TokenRow and stand alone
        // (standsAlone), so merging only ever joins the still-unpulsed rows.
        let positions = cardRunPositions(count: ordered.count,
                                         isBreaker: { standsAlone(ordered[$0]) })
        Section {
            ForEach(Array(keyed(ordered).enumerated()), id: \.element.id) { i, item in
                // Corollary 3 (build 176) — see `ThingRowKeying`.
                if let thing = item.live {
                    shapedListRow(thing, index: i, nextEventID: nextEventID,
                                  position: positions[i])
                }
            }
        }
    }

    /// A shape's one glanceable block, wearing the same card surface as the
    /// rows below it — a lede is part of the feed, not a foreign panel.
    private func ledeSection(_ content: some View) -> some View {
        Section {
            content
                .listRowBackground(
                    RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                        .fill(DS.surfaceSheet)
                        .padding(.horizontal, DS.Space.s4)
                        .padding(.vertical, DS.Space.s1)
                        .shadow(color: DS.cardShadow, radius: 18, x: 0, y: 6)
                )
                .listRowInsets(.init(top: DS.Space.s2,
                                     leading: DS.Space.s4 + DS.Space.s3,
                                     bottom: DS.Space.s2,
                                     trailing: DS.Space.s4 + DS.Space.s3))
                .listRowSeparator(.hidden)
        }
    }

    private func bundledSections(_ visible: [Thing], nextEventID: UUID?) -> some View {
        // Derive ONCE per render, then share — the day bundles, each day's true
        // total, and the new-since boundary. Read inside the row/header loops
        // (as `newBoundaryID` and `dayGroups.first(where:)` were) they rebuilt
        // the whole chain per row/section — the Feed freeze (perf pass
        // 2026-07-13).
        // Memoized (PERF 2026-07-31 — see `DerivationMemo`): recomputed only
        // when `visible` actually changed, not on all ~18 launch-window body
        // passes over the same set.
        let key = derivationKey(visible)
        if memo.key != key {
            memo.key = key
            memo.days = perfAccum("dayGrouping") { recentDaysThenCoarseTail(visible) }
            memo.groups = perfAccum("bundle") { bundle(memo.days) }
            memo.imageOnly = perfAccum("imageOnlyIDs") { imageOnlyIDs(memo.days) }
            memo.wideArt = perfAccum("wideArtIDs") { wideArtIDs(memo.groups) }
            memo.coarse = perfAccum("coarseLabels") { coarseLabels(in: memo.days) }
        }
        // Windowed (prd §264). `boundary` reads the FULL set so the new-since
        // divider lands on the same row whether or not the window is open.
        let allGroups = memo.groups
        let window = windowed(allGroups)
        let _ = { memo.windowHasMore = window.more }()
        let groups = window.shown
        let boundary = boundaryID(in: allGroups)
        let imageOnly = memo.imageOnly
        let wideArt = memo.wideArt
        let coarse = memo.coarse
        return Group {
        ForEach(groups, id: \.0) { label, rows in
            // Bundles merge into the day card like any row-shaped thing —
            // only a single that stands alone (consent, token) breaks the run.
            let positions = cardRunPositions(
                count: rows.count,
                isBreaker: { i in
                    if case .single(let item) = rows[i].kind,
                       let thing = item.live { return standsAlone(thing) }
                    return false
                },
                isBoundary: { rows[$0].id == boundary })
            Section {
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                    if row.id == boundary { newSinceDivider }
                    switch row.kind {
                    case .single(let item):
                        // `live` before ANY read (corollary 3, build 176 —
                        // see `ThingRowKeying`): this closure is re-evaluated
                        // against the array it already holds when a heal's
                        // delete lands, and `imageOnly.contains(thing.id)`
                        // below is an argument, evaluated here, ahead of any
                        // guard inside the builder.
                        if let thing = item.live {
                            shapedListRow(thing, index: i, nextEventID: nextEventID,
                                          position: positions[i],
                                          imageOnly: imageOnly.contains(thing.id),
                                          wideArt: wideArt.contains(thing.id))
                        }
                    case .bundle(let source, let word, let count, let newest, let art):
                        bundleListRow(source: source, word: word, count: count,
                                      newest: newest, art: art, index: i, position: positions[i])
                    }
                }
            } header: {
                // No count (prd §218, 2026-07-25). §213 retired volume as news
                // in the brief ("people do not care how many things landed"),
                // and the widget's own tally went the same day; this header was
                // the last surface still counting. "Monday, Jun 15 · 1" was the
                // clearest case against it — a number that can only ever say
                // "one", under a header already carrying the date.
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                    Text(label)
                        .dsText(.heading22)
                        // The tail cools (prd §254, 2026-07-31). §218 already
                        // folds everything past a week into week/month groups;
                        // the type never followed, so a month from last spring
                        // shouted in the same 22pt bold as Today. One weight
                        // step down — size and weight are the only hierarchy
                        // this app has (no kerning, no caps, design law), and
                        // dropping a SIZE step instead would land the header at
                        // 18pt, which is the row titles beneath it.
                        .fontWeight(coarse.contains(label) ? .semibold : .bold)
                        .foregroundStyle(DS.textPrimary)
                }
                .textCase(nil)
                .padding(.leading, DS.Space.s4)
                .padding(.vertical, DS.Space.s1)
            }
        }
        if window.more { olderRow }
        }
    }

    /// The floor (prd §218, 2026-07-25) — one quiet line at the very bottom of
    /// the All feed naming when the corpus starts.
    ///
    /// Delight that is a FACT, not a compliment: it's the real date of the
    /// oldest thing kept, it can't fire wrongly, and it can't fire twice. It
    /// also does a structural job — a scroll with no visible end teaches you
    /// never to reach one, and the newly coarsened tail finally has a bottom
    /// worth walking to. Deliberately NOT a count of anything (§213).
    ///
    /// Withheld on a corpus too young to have a history: "this is where it
    /// starts · today" is a fact nobody needs, and a floor under three rows
    /// reads as an empty-state apology.
    @ViewBuilder
    private func corpusFloorSection(_ visible: [Thing]) -> some View {
        // `.isLive` before reading `capturedAt`: this walks a DERIVED array to
        // its oldest member, and a reconciliation or CloudKit delete can land
        // in the same graph update (CLAUDE.md, the dead-Thing rule).
        let live = visible.filter(\.isLive)
        if live.count >= 8, let oldest = live.last?.capturedAt,
           Date.now.timeIntervalSince(oldest) > 7 * 86_400 {
            Section {
                Text("This is where it starts · \(oldest.formatted(.dateTime.month(.abbreviated).day()))")
                    .dsText(.subhead13)
                    .foregroundStyle(DS.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.Space.s6)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .accessibilityLabel("The oldest thing you kept is from \(oldest.formatted(.dateTime.month(.wide).day().year()))")
            }
        }
    }

    /// The boundary line — words only, no drawn rule (the no-hairlines law).
    /// Everything above it arrived since you last left this screen.
    private var newSinceDivider: some View {
        // A quiet capsule, not tint-colored prose (which reads as a tappable
        // link). The fill gives the boundary its line without drawing one.
        Text(newSinceText)
            .dsText(.label12)
            .foregroundStyle(DS.textSecondary)
            .padding(.horizontal, DS.Space.s3)
            .padding(.vertical, DS.Space.s1)
            .background(DS.fillFaint, in: Capsule(style: .continuous))
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Space.s1)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    /// The seam's words (2026-07-21): "what's new" differs by source, so the
    /// divider names it concretely instead of a bare "New since Friday". Most
    /// feeds get a count ("New since Friday · 4"); a Wallet feed — whose rows
    /// are SCANNED, not read — names the flow instead ("2 in, 1 out since
    /// Friday"), the question a wallet actually answers. Counts run over the
    /// frozen `visible` (things newer than the last-visit stamp); the divider
    /// renders once per boundary, so this reads `visible` a single time.
    private var newSinceText: String {
        guard let newSince else { return "" }
        let fresh = visible.filter { $0.capturedAt > newSince }
        if shape == .wallet {
            let inN = fresh.filter { $0.transferDirection == "received" }.count
            let outN = fresh.filter { $0.transferDirection == "sent" }.count
            if inN > 0 || outN > 0 {
                var parts: [String] = []
                if inN > 0 { parts.append(String(localized: "\(inN) in")) }
                if outN > 0 { parts.append(String(localized: "\(outN) out")) }
                return String(localized: "\(parts.joined(separator: ", ")) since \(sinceLabel)")
            }
        }
        return fresh.isEmpty
            ? String(localized: "New since \(sinceLabel)")
            : String(localized: "New since \(sinceLabel) · \(fresh.count)")
    }

    private var sinceLabel: String {
        guard let newSince else { return "" }
        if Calendar.current.isDateInToday(newSince) {
            return newSince.formatted(date: .omitted, time: .shortened)
        }
        if Calendar.current.isDateInYesterday(newSince) { return "yesterday" }
        return newSince.formatted(.dateTime.weekday(.wide))
    }

    /// Per-source last-visit stamps. All keeps its original "feed.lastSeen"
    /// key — an update never resets anyone's divider.
    private func lastSeenKey(for source: String) -> String {
        source == "All" ? "feed.lastSeen" : "feed.lastSeen.\(source)"
    }

    private func lastSeen(for source: String) -> Date? {
        let stamp = UserDefaults.standard.double(forKey: lastSeenKey(for: source))
        return stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
    }

    private func stampSeen(_ source: String) {
        UserDefaults.standard.set(Date.now.timeIntervalSince1970,
                                  forKey: lastSeenKey(for: source))
    }

    /// This page came to the front: freeze its boundary for the visit, replay
    /// the shape's entrance, stream its synthesis block. Every one of these is
    /// an ARRIVAL — spending them on a mounted-but-unseen neighbour would hand
    /// the person a page whose moment already happened.
    private func land() {
        freezeBoundary()
        // Replay the shape's entrance ONLY the first time this page is landed
        // (2026-07-30, user: swiping between screens had a tiny lag; "just
        // appear on revisit"). Re-animating every row on every swipe-in was
        // both the extra motion and a per-frame main-actor cost on each visit —
        // now the rows animate in the first time the page is seen and simply
        // ARE there on return. Pull-to-refresh still replays deliberately
        // (`refreshFeed` bumps `shapeWave` itself), and a page never yet built
        // still gets its first-appearance entrance from `RowEntrance.onAppear`.
        if !hasLanded {
            hasLanded = true
            shapeWave += 1
        }
        streamBlock()
        loadWalletLive()
        // Every landing writes the crown pour's hue (prd §159): the scoped
        // wallet's face tint when you're standing inside one, else nil —
        // Casberi's own blue. Written unconditionally, not just by the Wallet
        // page, so arriving on ANY page resets a scoped tint the wallet page
        // left behind; no leave() bookkeeping to race the pager's ordering.
        chrome.pourHue = source == "Wallet" ? selectedWallet.map(WalletFace.tint) : nil
        // And how much of it this room gets (prd §297, 2026-08-03) — the rule
        // and its reasoning live together on `ShellChrome`. Written
        // unconditionally beside the hue for the same reason: arriving on any
        // page settles the crown, with no leave() bookkeeping to race the
        // pager.
        chrome.pourDose = ShellChrome.pourDose(for: source)
    }

    /// The person left this page — stamp what they saw, so the next visit's
    /// "New since" line is honest, and let the boundary freeze afresh then.
    private func leave() {
        stampSeen(source)
        visitFrozen = false
    }

    /// The boundary freezes on arrival and holds for the whole visit — a
    /// bounce out to another page and back can't move the line (ruling
    /// 2026-07-09). All tracks `AppVisit.away` instead of a per-page stamp
    /// (2026-07-20) — the same "since you left the app" window the agent's
    /// own "While I was away?" chip already names; there's no single page
    /// for the whole corpus to have left.
    private func freezeBoundary() {
        guard !visitFrozen else { return }
        visitFrozen = true
        newSince = source == "All" ? AppVisit.away?.lowerBound : lastSeen(for: source)
    }

    /// A bundle in the list: same card treatment as a thing row; the tap
    /// opens the source's own shape (where volume is designed to live) —
    /// no swipes, nothing here is a single thing to pin or open.
    private func bundleListRow(source: String, word: String, count: Int,
                               newest: Date, art: [String] = [], index: Int,
                               position: RunPosition = .only) -> some View {
        BundleRow(source: source, count: count, word: word, newest: newest, art: art)
            .modifier(RowEntrance(index: index, wave: shapeWave, style: entranceStyle))
            .contentShape(Rectangle())
            .onTapGesture {
                DSHaptic.selection()
                withAnimation(DS.Motion.standard) { filter.source = source }
            }
            // A bundle is an ordinary row, never a designed card, so it goes
            // bare on the ink like every list row (lists are air).
            .listRowBackground(runBackground(position, bare: true))
            // Feed rhythm (2026-07-13): back to s2 — the s3 airy read made
            // every gap the same size, so days never clustered. Rows sit
            // tight within their day; the day header carries the big gap.
            .listRowInsets(.init(top: DS.Space.s2,
                                 leading: DS.Space.s4 + DS.Space.s3,
                                 bottom: DS.Space.s2,
                                 trailing: DS.Space.s4 + DS.Space.s3))
            .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private func groupedSections(_ groups: [(String, [Thing])],
                                 nextEventID: UUID?,
                                 boundary: UUID? = nil,
                                 replies: [String: [Thing]] = [:]) -> some View {
        // Computed once for the whole feed rather than per section: every
        // shaped room routes its groups through here, so the folded tail's
        // lighter header (prd §254) reaches all of them from one place.
        let coarse = coarseLabels(in: groups)
        // Windowed (prd §264) — `coarse` and `boundary` are computed against
        // the FULL set above, so a label or a divider does not change meaning
        // when the window opens.
        let window = windowed(groups)
        let _ = { memo.windowHasMore = window.more }()
        ForEach(window.shown, id: \.0) { label, rows in
            daySection(label, rows, nextEventID: nextEventID, boundary: boundary,
                       replies: replies, coarse: coarse.contains(label))
        }
        if window.more { olderRow }
    }

    /// The cross-source Themes treemap (2026-07-18: moved off Home — "should
    /// it go on all?" — a cross-source overview belongs on the cross-source
    /// feed, the same split that already sent the Wallet treemap to the
    /// Wallet feed). Synchronous, off the SAME `visible` the rows below draw
    /// from (no separate query, so the two can't disagree) — no GenStream
    /// needed, unlike the wallet block, which waits on a real network fetch.
    ///
    /// Collapses to one line once you've already seen these exact clusters
    /// (2026-07-20) — a digest of cluster name+count compared against a
    /// locally-stamped "last seen" digest (its own key, NOT `KeptAskStore`,
    /// which is scoped to kept ASKS specifically). Tapping expands the full
    /// treemap for the rest of this session and marks the digest seen.
    @ViewBuilder
    private func themesLedeSection(_ visible: [Thing]) -> some View {
        // Computed once and shared with the collapsed row below (2026-07-21) —
        // this used to run `projectClusters` a second time over the same
        // `visible` set just to build the collapsed summary. Memoized since
        // 2026-07-31 (see `themesData`), so it no longer walks the corpus on
        // every launch-window body pass.
        let themes = themesData(visible)
        if let doc = themes.doc {
            let clusters = themes.clusters
            let digest = doc.joined(separator: "\n")
            let unchanged = digest == UserDefaults.standard.string(forKey: Self.themesSeenDigestKey)
            if themesExpanded || !unchanged {
                let els = perfAccum("themesParse") { GenParser.parse(prefix: digest[...], isComplete: true) }
                Section {
                    GenRender(id: "root", els: els)
                        // The Themes CARD (2026-07-21, the §160 ruling carried
                        // to the All room): every other feed-head read — the
                        // wallet's two parcels, the heatmaps, the leaderboards,
                        // the mosaics — wears the widget surface; this was the
                        // last one floating bare on the page. Same recipe as
                        // the holdings card: GenTagMap self-pads horizontally,
                        // so only the bottom needs closing.
                        .padding(.bottom, DS.Space.s3)
                        .dsWidgetSurface(fillOpacity: Self.walletCardFill)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        // The card needs the page gutter the bare map didn't.
                        .listRowInsets(EdgeInsets(top: DS.Space.s2, leading: DS.Space.s4,
                                                  bottom: 0, trailing: DS.Space.s4))
                        .environment(\.genProjectTap) { name in
                            openProject = ProjectRoute(name: name)
                        }
                        .onAppear {
                            // Pin expanded for the rest of this mount too —
                            // without this, stamping the digest here would
                            // make the NEXT body re-eval (any unrelated
                            // state change, still the same visit) read
                            // `unchanged` true and collapse out from under
                            // someone mid-visit.
                            themesExpanded = true
                            UserDefaults.standard.set(digest, forKey: Self.themesSeenDigestKey)
                        }
                }
            } else {
                Section {
                    Button {
                        DSHaptic.selection()
                        withAnimation(DS.Motion.standard) { themesExpanded = true }
                    } label: {
                        themesCollapsedRow(clusters)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
        }
    }

    /// The collapsed Themes row — eyebrow + a one-line cluster-count summary,
    /// same voice as `daySection`'s header (name in heading weight, the
    /// count in tertiary).
    private func themesCollapsedRow(_ clusters: [HomeComposition.Cluster]) -> some View {
        let names = clusters.prefix(6).map(\.name).joined(separator: ", ")
        return HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
            Text("Themes").dsText(.heading17).foregroundStyle(DS.textPrimary)
            Text(names).dsText(.subhead13).foregroundStyle(DS.textTertiary)
                .lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 0)
            Image(systemName: "chevron.down")
                .accessibilityHidden(true)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DS.textTertiary)
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.vertical, DS.Space.s3)
    }

    /// A room whose head comes from that room's OWN model rather than from a
    /// registry over `[Thing]` (2026-08-04, prd §298).
    ///
    /// `FeedInsight` is pure over the corpus by contract — it can only count
    /// and group stored fields. These three rooms lead with facts that are not
    /// in the corpus at all: a certificate's expiry, a Stripe balance, a
    /// PostHog reading, each held in bridge state. So they get a head each,
    /// and they share one slot in the chain because they can never compete —
    /// every case names exactly one source.
    /// The lane strip — `PredictionBrowseSection.viewChip` reused verbatim in
    /// look and behaviour, because that is the app's existing answer to "scope
    /// this room by one of a known set of categories" and a second visual
    /// language for the same job would be the drift the design system exists to
    /// prevent.
    ///
    /// Every lane is always listed, in the catalog's own order, whether or not
    /// anyone sells into it today — a strip whose contents shift under you is a
    /// status readout, not a control. A lane with nothing in it still answers
    /// honestly when tapped (the empty room says so), which is a truthful
    /// answer rather than a missing button.
    @ViewBuilder
    private var x402LaneStrip: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Space.s2) {
                    laneChip(nil, label: String(localized: "All"))
                    ForEach(X402Category.allCases) { lane in
                        laneChip(lane.display, label: lane.display)
                    }
                }
                .padding(.horizontal, DS.Space.s4)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets())
        }
    }

    private func laneChip(_ value: String?, label: String) -> some View {
        let isOn = x402Lane == value
        return Button {
            DSHaptic.selection()
            withAnimation(DS.Motion.standard) { x402Lane = value }
        } label: {
            Text(label)
                .dsText(.subhead13).fontWeight(.semibold)
                .foregroundStyle(isOn ? .white : DS.textSecondary)
                .padding(.horizontal, DS.Space.s3).padding(.vertical, 7)
                .background(Capsule().fill(isOn ? DS.tint : DS.fillFaint))
        }
        .buttonStyle(.plain)
    }

    /// The room narrowed to the selected lane. A seller qualifies if it sells
    /// into that lane AT ALL — the row's `tags` carry every lane it serves, not
    /// just the primary one its shelf files it under.
    private func x402Scoped(_ visible: [Thing]) -> [Thing] {
        guard let lane = x402Lane else { return visible }
        return visible.live.filter { thing in
            thing.tags.contains { $0.caseInsensitiveCompare(lane) == .orderedSame }
        }
    }

    /// LANES, NOT DAYS (2026-08-06) — the x402 room's real unit.
    ///
    /// Every seller here lands on the walk that first sees it, so the whole room
    /// shares one timestamp: day-grouping produces a single section called
    /// "Today" holding twenty-two rows, which is a grouping that does no work
    /// and a divider that says nothing. `.music` made exactly this move for the
    /// same reason (a listening sitting is its real unit, not a calendar day).
    ///
    /// Two orderings, and both replace something arbitrary:
    ///
    ///  • **Lanes by how many sellers they hold**, so the shelf you scroll into
    ///    first is the one with something on it.
    ///  • **Sellers within a lane by SERVICE COUNT**, matching the head's own
    ///    ranking — so scrolling the room reads as descending a leaderboard
    ///    instead of wandering a pile. Before this the order was insertion
    ///    order, which is to say no order at all.
    ///
    /// A seller whose reading isn't stored yet (a fresh install syncs the rows
    /// but not `X402State`) ranks 0 and falls back to its own arrival rather
    /// than being dropped — the room still draws, just unranked, which is the
    /// honest outcome when we haven't walked on this device yet.
    private func x402Lanes(_ visible: [Thing]) -> [(String, [Thing])] {
        let services = Dictionary(X402State.sellers.map { ($0.slug, $0.services) },
                                  uniquingKeysWith: { first, _ in first })
        func rank(_ thing: Thing) -> Int {
            guard let ref = thing.sourceRef, ref.hasPrefix("x402:") else { return 0 }
            return services[String(ref.dropFirst("x402:".count))] ?? 0
        }
        var lanes: [String: [Thing]] = [:]
        // Live at the BOUNDARY, before any stored property is read (corollary 4)
        // — `visible` may be a debounced snapshot.
        for thing in visible.live {
            // The room's own marker names no lane; the first real tag wins. A
            // row with no lane at all (a seller whose category this build can't
            // map — quirk 2) gets a shelf rather than vanishing, which is the
            // same refusal the ingest makes when it lands them.
            let lane = thing.tags.first { $0.caseInsensitiveCompare("x402") != .orderedSame }
                ?? String(localized: "Everything else")
            lanes[lane, default: []].append(thing)
        }
        return lanes
            .map { label, rows in
                (label, rows.sorted { (rank($0), $0.capturedAt) > (rank($1), $1.capturedAt) })
            }
            .sorted { ($0.1.count, $1.0) > ($1.1.count, $0.0) }
    }

    /// The Cursor room grouped by REPOSITORY rather than by day (2026-08-08,
    /// prd §340) — the `x402Lanes` shape, for the same reason.
    ///
    /// A day is the wrong axis for agent runs. You launch several against one
    /// repository in an afternoon and then nothing for a week, so day-grouping
    /// produces one enormous "Today" and a scatter of singletons, and the
    /// question a person actually arrives with — *what has been happening on
    /// this project* — is the one the screen refuses to answer.
    ///
    /// Within a repository, FAILURES LEAD (then newest first). That inverts the
    /// chronology deliberately and for the same reason the room head ranks them
    /// first: a failed run is the one that still needs you, and burying it under
    /// three successes because they happened later is the room hiding its own
    /// news. Repositories themselves are ordered by run count, with the name as
    /// a tiebreak so the ordering is TOTAL — a room that reshuffles between
    /// opens over identical data reads as broken.
    private func cursorRepos(_ visible: [Thing]) -> [(String, [Thing])] {
        var repos: [String: [Thing]] = [:]
        // Live at the BOUNDARY, before any stored property is read (corollary
        // 4) — `visible` may be a debounced snapshot.
        for thing in visible.live {
            // The repo is stored on `authorHandle` at landing. A row that
            // predates that, or a run whose source carried no usable
            // repository, gets a shelf rather than vanishing — the same
            // refusal the x402 room makes, and the §307 rule that a row we
            // can't file is never silently dropped.
            let repo = thing.authorHandle?.trimmingCharacters(in: .whitespacesAndNewlines)
            let label = (repo?.isEmpty == false ? repo! : String(localized: "Somewhere else"))
            repos[label, default: []].append(thing)
        }
        return repos
            .map { label, rows in
                (label, rows.sorted {
                    let a = CursorAgentStatus.failed(tags: $0.tags)
                    let b = CursorAgentStatus.failed(tags: $1.tags)
                    if a != b { return a }
                    return $0.capturedAt > $1.capturedAt
                })
            }
            .sorted { ($0.1.count, $1.0) > ($1.1.count, $0.0) }
    }

    private enum SourceHead {
        case runway(CloudflareRunway)
        case stripe(StripeRoom)
        case posthog(PostHogRoom)
        case appleWallet(AppleWalletRoom.Card)
        case x402(X402Room)
        case appStoreConnect(ASCRoom)
        case cursor(CursorRoom)
    }

    /// Resolve this room's own head, or nil. One `switch` so adding a fourth
    /// per-source head is one case here rather than an edit to five gates.
    private func sourceHead(_ visible: [Thing]) -> SourceHead? {
        switch source {
        case "Cloudflare":
            return CloudflareRunwaySource.compose(things: visible).map { .runway($0) }
        case "Stripe":
            return StripeRoomSource.compose(things: visible).map { .stripe($0) }
        case "PostHog":
            return PostHogRoomSource.compose(things: visible).map { .posthog($0) }
        case AppleWalletBridge.sourceName:
            return AppleWalletRoomSource.compose(things: visible).map { .appleWallet($0) }
        case X402Ingest.source:
            return X402RoomSource.compose(things: visible, lane: x402Lane).map { .x402($0) }
        // The one head here that reads no rows at all — its subject is STATE,
        // and replaying the feed for it would let this card and the connect
        // screen disagree about the same corpus. See `ASCRoomSource.compose`.
        case ASCShape.source:
            return ASCRoomSource.compose(things: visible).map { .appStoreConnect($0) }
        case CursorRoomSource.source:
            return CursorRoomSource.compose(things: visible).map { .cursor($0) }
        default:
            return nil
        }
    }

    /// Open a merchant's newest charge. The Apple Wallet head ranks a merchant
    /// across many rows, so it can't name a `sourceRef` — the honest landing is
    /// the most recent charge from that merchant, matched on the stored
    /// counterparty rather than by parsing the title back apart.
    private func openMerchant(_ merchant: String, in visible: [Thing]) {
        let match = visible.live
            .filter { $0.source == AppleWalletBridge.sourceName
                      && $0.transferCounterparty == merchant }
            .max { $0.capturedAt < $1.capturedAt }
        if let match { openThing(match) }
    }

    /// Open the row a head card named, by its `sourceRef`. The cards hold no
    /// `Thing` (corollary 5), so every one of them hands back a value and the
    /// lookup lands here, against the live corpus.
    private func openBySourceRef(_ ref: String, in visible: [Thing]) {
        guard let match = visible.first(where: { $0.isLive && $0.sourceRef == ref })
        else { return }
        openThing(match)
    }

    /// Open a thing by its `id.uuidString`, resolved against the live feed — the
    /// head-card contract for a head whose members carry ids rather than
    /// `sourceRef`s (the cross-source thread; not every thing has a unique ref).
    /// Liveness inside the filter, before any stored read (corollary 3).
    private func openByID(_ id: String, in visible: [Thing]) {
        guard let match = visible.first(where: { $0.isLive && $0.id.uuidString == id })
        else { return }
        openThing(match)
    }

    /// Open the newest row of a source that a predicate accepts — `openMerchant`
    /// generalised, for a head that ranks something owning MANY rows and so
    /// cannot name a single `sourceRef`. Liveness is checked inside the filter,
    /// before any stored property is read (corollary 3).
    private func openNewest(source: String, in visible: [Thing],
                            where matches: (Thing) -> Bool) {
        let match = visible
            .filter { $0.isLive && $0.source == source && matches($0) }
            .max { $0.capturedAt < $1.capturedAt }
        if let match { openThing(match) }
    }

    /// The list-row chrome every insight hero mounts in (clear background, no
    /// separator, edge-to-edge — the card owns its own padding).
    @ViewBuilder
    private func insightSection<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        Section {
            content()
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
        }
    }

    /// A source's own consistency heatmap (2026-07-18) — the same green-squares
    /// grid the GitHub feed leads with, here derived from the feed's own things:
    /// each thing's `capturedAt` bucketed into the trailing year. Synchronous,
    /// off the SAME `visible` the rows draw from (no separate query). Renders
    /// only once a few days are lit, so a near-empty grid can't read as a
    /// loading skeleton.
    @ViewBuilder
    private func calendarHeatmapSection(_ visible: [Thing], label: FeedHeatmap.Label) -> some View {
        // What the grid counts, which is not always the whole room (2026-07-31):
        // a label may name one kind ("your memory year" must mean memories, not
        // the chats sitting beside them), and the import receipt is never a day
        // the person did something. The anniversary reads the SAME set, so the
        // card can't reach back to something its own grid doesn't chart.
        let counted = FeedHeatmap.counted(visible, label: label)
        let year = ContributionYear.from(dates: counted.map(\.capturedAt), columns: label.columns)
        if year.activeDays >= 4 {
            let echo = OnThisDay.find(in: counted)
            Section {
                CalendarHeatmapHero(title: label.title,
                                    subtitle: FeedHeatmap.subtitle(label, total: year.total),
                                    year: year, minColumns: label.columns,
                                    onThisDay: echo,
                                    onTapOnThisDay: { feedSheet = echo.map { .thing($0.thing) } })
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
            }
        }
    }

    /// The portfolio's own value-history line (2026-07-18), leading the
    /// treemap — real samples off `WalletStore.combinedValueSamples()`
    /// (recorded on every real holdings fetch since a wallet was watched, not
    /// synthesized). Empty (no section) until two aligned samples exist.
    /// How many transactions the feed previews before handing off to the
    /// history page (2026-07-20). Five is the count that still reads as "here's
    /// what's new" rather than a log — the reads above it are the point of this
    /// screen, and an unbounded stream buried all four of them.
    private static let walletPreviewRows = 5

    /// The wallet room's two cards are TRANSLUCENT (prd §160): they sit on the
    /// crown pour, and an opaque surface would punch a hole in the one
    /// atmospheric move the shell makes. One constant so the balance card and
    /// the holdings card can never drift apart.
    private static let walletCardFill = 0.82

    /// The balance CARD, then Worth a look as a quiet line beneath it — the two
    /// questions a wallet screen answers at a glance ("what's it worth", "is it
    /// okay").
    ///
    /// The card is prd §160 (2026-07-21, user: "i like both boxed"), amending
    /// §146/§151's page-set headline: the room's crown is already a parade of
    /// rounded shapes (source chips, wallet switcher pills, sync capsule), so
    /// the argument that a free-set number reads as "the room's voice" lost to
    /// the argument that a boxed one is easier to SCAN — parcels beat strata
    /// when the eye is looking for sections. The number keeps every ounce of
    /// its weight (price48, the pour behind it, the delta and mover with it);
    /// it just gets an edge. Translucent so the crown pour still travels under
    /// it rather than being punched out.
    ///
    /// Rendered FLAT (§gotchas' eager-head law): a plain VStack of two shallow
    /// pieces, no generic widget path. Either can be absent — no balance until
    /// two value samples exist, no warnings line when there's nothing wrong —
    /// and with both absent the section renders nothing at all rather than an
    /// empty row (the same honesty floor every section here keeps).
    @ViewBuilder
    private func walletTilesSection(_ visible: [Thing]) -> some View {
        // Scoped to the selected wallet's own value line, else the combined
        // portfolio line (prd §128). Both start honest — nil until two aligned
        // samples exist (TokenChart.from guards ≥2) — but the NUMBER no longer
        // waits on them (prd §155): the live total leads, the line joins.
        let samples = selectedWallet.map { wallet.valueSamples(forAddress: $0) }
            ?? wallet.combinedValueSamples()
        let ranges = WalletRange.offered(for: samples)
        let active = ranges.contains(balanceRange) ? balanceRange
            : WalletRange.remembered(offered: ranges)
        let windowed = active.clip(samples)
        let chart = TokenChart.from(samples: windowed)
        let total = portfolio.map(\.totalUSD).flatMap { $0 > 0 ? $0 : nil }
        let warnings = walletLive.warnings
        let chips = walletFaceChipEntries
        // Gathered ONCE — the gate below and the strip inside both read it,
        // and a computed property would re-walk every book on each body pass.
        let composition = walletComposition
        // The composition earns the card on its own (prd §240): a wallet whose
        // money is entirely in protocols — everything supplied to Aave, or a
        // Hyperliquid account with an empty EVM wallet — has no priced
        // holdings and no warnings, so without this the one surface that
        // states its money would never render at all.
        if chart != nil || total != nil || !warnings.isEmpty || !composition.isEmpty {
            Section {
                // ONE card (prd §212, 2026-07-25) — the balance, the per-wallet
                // split, and the security read. Three parcels of equal weight
                // until this pass, and they were never three subjects: "what's
                // it worth", "whose is it", "is it okay" are the questions of a
                // single glance at a single number.
                VStack(alignment: .leading, spacing: DS.Space.s3) {
                    if chart != nil || total != nil {
                        // The headline is a READ, not a door (prd §208,
                        // 2026-07-25): the multi-wallet "All" view used to open
                        // a separate "Across your wallets" sheet, but that sheet
                        // re-showed this very number and line before getting to
                        // its only unique content — the per-wallet split — which
                        // now lives in this same card as face chips. No door, no
                        // chevron; the number just states itself.
                        // "Wallets" only when that's all it is (2026-07-31).
                        // This number merges connected exchange balances and
                        // staked-validator ETH (§163), and a caption naming
                        // wallets over a total that isn't only wallets is the
                        // honesty rule's own failure mode — a true-sounding
                        // phrase that isn't describing what it counts.
                        // "Accounts" is the word that covers both without
                        // claiming the app knows what to call each one.
                        // `chips`, gathered once at the top of this section —
                        // it walks the portfolio's holders, so re-deriving it
                        // here would do that twice per body pass.
                        let hasBreakdown = !chips.isEmpty && selectedWallet == nil
                        let hasVenue = chips.contains { $0.venueLabel != nil }
                        WalletBalanceHeadline(
                            total: total,
                            chart: chart,
                            marks: walletMarks(dates: windowed.map(\.at), things: visible),
                            caption: hasBreakdown
                                ? (hasVenue ? String(localized: "Across your accounts")
                                            : String(localized: "Across your wallets"))
                                : String(localized: "Balance"),
                            mover: moverLine(),
                            ranges: ranges,
                            range: active,
                            onPickRange: { r in
                                balanceRange = r
                                r.remember()
                            },
                            onOpen: nil,
                            onOpenMark: { id in
                                feedSheet = visible.first { $0.id == id }.map(FeedSheetRoute.thing)
                            })
                    }
                    // Whose the number is (prd §212) — only unscoped and only
                    // with more than one wallet carrying a real line, exactly
                    // the guard the retired "Each wallet" card kept. A tap
                    // scopes the whole feed, the move the switcher bar makes.
                    if !chips.isEmpty, selectedWallet == nil {
                        WalletFaceChips(entries: chips) { address in
                            withAnimation(DS.Motion.standard) { selectedWallet = address }
                        }
                    }
                    // What the crown doesn't count (prd §240) — every protocol
                    // position the app already reads sits outside that number,
                    // and for Hyperliquid and Aerodrome this is their only
                    // seat on the screen. Inside this card rather than a card
                    // of its own: "what's it worth" is one glance (§212), and
                    // this is the rest of that glance's answer. Guarded at the
                    // call site like every other strip in this card, so an
                    // empty one can't take a spacing slot in the stack.
                    if !composition.isEmpty {
                        WalletCompositionStrip(
                            composition: composition,
                            onOpenDeposits: { feedSheet = .deposits(composition) },
                            // Owed gets no door on purpose — the Lending card
                            // below already states health per protocol.
                            onOpenLocks: { feedSheet = .locks(composition) })
                    }
                    if !warnings.isEmpty {
                        WalletWarningsStrip(warnings: warnings) { feedSheet = .worthALook }
                    }
                }
                // The card (prd §160, kept). Padded and surfaced HERE, not
                // inside the headline view, so `WalletBalanceHeadline` still
                // renders bare wherever else it's used.
                .padding(DS.Space.s4)
                .dsWidgetSurface(fillOpacity: Self.walletCardFill)
                // Each piece arrives on its own clock — the balance reads off
                // already-recorded samples (instant) while warnings/holdings/
                // lending wait on live reads (2026-07-20: "balance shows then
                // the others pop in but looks unintentional"). The card is one
                // entrance now that the three ride inside it; the pieces still
                // appear as they land, they just no longer each stage a
                // separate surface into the room.
                .modifier(RowEntrance(index: 0, wave: shapeWave, style: entranceStyle))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: DS.Space.s2, leading: DS.Space.s4,
                                          bottom: 0, trailing: DS.Space.s4))
            }
        }
    }

    /// The transactions that landed inside the drawn window, placed against it
    /// (prd §155, 2026-07-21). A balance line conflates two different stories —
    /// prices moved, and money moved in or out — and the app holds both halves;
    /// this is the one that ties them together, so a step in the line can be
    /// read back to the send that caused it.
    ///
    /// Only things that fall BETWEEN the first and last sample are marked:
    /// a transaction from before the record began has no place on the line, and
    /// inventing one at the left edge would claim it caused a move the line
    /// never saw. Capped at the most recent ten — beyond that the punctuation
    /// becomes a second series and the line stops being readable.
    private func walletMarks(dates: [Date], things: [Thing]) -> [TokenChartMark] {
        guard dates.count >= 2, let first = dates.first, let last = dates.last else { return [] }
        return things
            .filter { $0.kind == .transaction && $0.capturedAt >= first && $0.capturedAt <= last }
            .prefix(10)
            .compactMap { thing in
                guard let i = dates.lastIndex(where: { $0 <= thing.capturedAt }) else { return nil }
                let next = min(i + 1, dates.count - 1)
                let span = dates[next].timeIntervalSince(dates[i])
                let t = span > 0 ? thing.capturedAt.timeIntervalSince(dates[i]) / span : 0
                return TokenChartMark(id: thing.id, x: Double(i) + min(max(t, 0), 1),
                                      label: thing.title)
            }
    }

    /// "Mostly ETH · +$310" — the top attributed mover, in the scope the feed
    /// is standing in (prd §155). The delta pill says the line moved; this says
    /// what moved it, off the same per-token snapshots. nil whenever the record
    /// can't attribute honestly yet — most of all on a young history, where no
    /// snapshot pair exists to difference. (This line is now the only "what
    /// moved" surface; the combined sheet that carried a fuller table retired
    /// with prd §208.)
    private func moverLine() -> String? {
        guard let top = wallet.holdingsDeltas(forAddress: selectedWallet).first else { return nil }
        let sign = top.delta >= 0 ? "+" : "−"
        return String(localized: "Mostly \(top.symbol) · \(sign)\(TokenStats.compact(abs(top.delta)))")
    }

    /// What's in protocols, for the balance card's composition strip (prd
    /// §240). Pure arithmetic over books `loadWalletLive` already fetched —
    /// no network of its own, and it follows the feed's wallet scope for free
    /// because `WalletWatch.liveState` reads every book at that same scope.
    private var walletComposition: WalletComposition {
        WalletComposition.from(aave: walletLive.positions,
                               morpho: walletLive.morpho,
                               uniswap: walletLive.uniswap,
                               hyperliquid: walletLive.hyperliquid,
                               aerodrome: walletLive.aerodrome,
                               etherfiCash: walletLive.etherfiCash,
                               etherfiUnstake: walletLive.etherfiUnstake)
    }

    /// The per-wallet split as chip entries (prd §212, 2026-07-25) — value
    /// types keyed by address, so the ForEach behind them never reads a live
    /// `@Model` (the crash class the CLAUDE.md ForEach rule guards).
    ///
    /// It rode a card of its own from §208 until this pass: face, name, total,
    /// an 80pt sparkline and a delta pill per wallet. Same source, same guard
    /// (≥2 aligned samples, >1 wallet watched) — the sparkline and the name
    /// drop out, because at 80pt the line was decoration and tapping a chip
    /// scopes the feed to that wallet, where the line is drawn full-width as
    /// the room's own headline.
    ///
    /// VENUES JOIN THEM (2026-07-31). The number these sit under is
    /// `portfolio.totalUSD`, which has merged connected exchange balances and
    /// staked-validator ETH since §163 — so a strip built only from watched
    /// wallets decomposed a fraction of it without saying so, and worst
    /// exactly where it mattered most: someone whose main holding is on an
    /// exchange is the case that ruling exists for. A venue contributes a chip
    /// with no delta, since the value line is recorded per watched wallet and
    /// a venue has no history to difference (see `WalletFaceChips.Entry`).
    ///
    /// The wallet chips still read their own recorded lines rather than the
    /// portfolio's per-wallet figures — that's unchanged, and it's why the
    /// chips have never claimed to SUM to the number above them. They answer
    /// "whose", not "how it adds up".
    private var walletFaceChipEntries: [WalletFaceChips.Entry] {
        let venues = walletVenueChipEntries
        // One wallet and no venue means there is nothing to decompose. One
        // wallet WITH a venue still splits into two places, so the strip earns
        // its keep — the old bare `> 1` guard would have hidden exactly the
        // Coinbase-plus-one-wallet case this pass is about.
        guard wallet.addresses.count > 1 || !venues.isEmpty else { return [] }
        let wallets: [WalletFaceChips.Entry] = wallet.addresses.compactMap { addr in
            let samples = wallet.valueSamples(forAddress: addr.address)
            guard samples.count >= 2, let first = samples.first?.usd,
                  let last = samples.last?.usd else { return nil }
            return WalletFaceChips.Entry(id: addr.address, value: last,
                                         change: first > 0 ? (last - first) / first : 0)
        }
        // Still nothing to split if the wallets have no lines yet and there's
        // no venue beside them — one lone chip under a number says nothing the
        // number didn't.
        guard wallets.count + venues.count > 1 else { return [] }
        return wallets + venues
    }

    /// The exchange/validator half of the strip, biggest first — floored so a
    /// few cents left on an exchange doesn't earn a chip beside real wallets.
    private var walletVenueChipEntries: [WalletFaceChips.Entry] {
        // Scoped to ONE wallet, the question is that wallet's, and a venue
        // isn't part of the answer — the same reason `WalletIngest` only
        // merges venues into the combined read.
        guard selectedWallet == nil, let portfolio else { return [] }
        return portfolio.venueTotals
            .filter { $0.usd >= WalletIngest.holdingFloor }
            .map { WalletFaceChips.Entry(id: $0.address, value: $0.usd,
                                         change: nil, venueLabel: $0.label) }
    }

    /// Where the money moved (2026-08-01, `WalletFlowBand`) — inflows, the
    /// wallet, outflows, sized by what each was worth when it moved.
    ///
    /// Sits directly under the balance card ON PURPOSE, ahead of the treemap:
    /// the crown number's own delta pill and sparkline raise the question
    /// ("it moved — where to?") and this is the answer, so putting the
    /// composition map between cause and effect would separate them for no
    /// gain. It follows the balance card's own window, so the two can never
    /// describe different periods on one screen.
    ///
    /// Nothing renders without a band worth drawing — `WalletFlow.band`
    /// declines on an unpriceable or single-lane window.
    @ViewBuilder
    private var walletFlowSection: some View {
        if let band = WalletFlowSource.band(from: visible, since: flowWindowStart) {
            Section {
                WalletFlowBand(band: band, windowLabel: balanceRange.flowLabel,
                               spineAddress: spineWalletAddress)
                    .modifier(RowEntrance(index: 1, wave: shapeWave, style: entranceStyle))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: DS.Space.s2, leading: DS.Space.s4,
                                              bottom: 0, trailing: DS.Space.s4))
            }
        }
    }

    /// The cutoff the flow band reads back to — nil for `.watched`, which
    /// means the whole record.
    private var flowWindowStart: Date? {
        balanceRange.span.map { Date.now.addingTimeInterval(-$0) }
    }

    /// Whose face rides the flow band's spine: the scoped wallet, or the sole
    /// watched one. nil when several wallets are merged — the band is then
    /// about all of them, and a face belonging to one would claim the flows
    /// were that wallet's (the honesty rule, applied to a portrait).
    private var spineWalletAddress: String? {
        if let selectedWallet { return selectedWallet }
        let watched = wallet.addresses
        return watched.count == 1 ? watched.first?.address : nil
    }

    /// Every leveraged position on one axis (2026-08-01, `WalletRiskStrip`),
    /// directly ABOVE the lending card it summarises — the cards below state
    /// each position in its own protocol's units, and this is the one view
    /// that puts them in an order. Declines under two positions, where the
    /// cards already say it better.
    @ViewBuilder
    private var walletRiskSection: some View {
        if let entries = WalletRiskScaleSource.strip(aave: walletLive.positions,
                                                     morpho: walletLive.morpho,
                                                     hyperliquid: walletLive.hyperliquid) {
            Section {
                WalletRiskStrip(entries: entries)
                    .modifier(RowEntrance(index: 2, wave: shapeWave, style: entranceStyle))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: DS.Space.s2, leading: DS.Space.s4,
                                              bottom: 0, trailing: DS.Space.s4))
            }
        }
    }

    /// Approvals — what someone else can still move (2026-08-03, prd §292).
    ///
    /// Sits with the risk reads rather than the holdings ones, because that's
    /// what it is: every card above says what your money is doing, and this
    /// says who else can reach it. Nothing renders without a live grant, which
    /// on most wallets is most of the time.
    ///
    /// The tap resolves the grant back to its `Thing` HERE rather than in the
    /// card, and re-checks `isLive` at the moment of the tap: a foreground
    /// heal can delete an approval row between the card being built and the
    /// finger landing (corollary 4's stale-array window, one layer up).
    @ViewBuilder
    private var walletApprovalsSection: some View {
        if !walletLive.exposure.isEmpty {
            Section {
                WalletApprovalExposureCard(exposure: walletLive.exposure) { grant in
                    guard let thing = walletLive.activeApprovals
                        .first(where: { $0.isLive && $0.id == grant.thingID })
                    else { return }
                    feedSheet = .thing(thing)
                }
                .modifier(RowEntrance(index: 2, wave: shapeWave, style: entranceStyle))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: DS.Space.s2, leading: DS.Space.s4,
                                          bottom: 0, trailing: DS.Space.s4))
            }
        }
    }

    /// Lending — Aave and Morpho for the wallets in scope, in ONE card as two
    /// rows (prd §212, 2026-07-25). They were two full cards until this pass;
    /// they were never two subjects, just two providers of one. The treemap
    /// says what you HOLD, this says what you OWE — which is why it earns a
    /// seat here rather than staying two taps down. Nothing renders without a
    /// position on either.
    @ViewBuilder
    private var walletDeFiSection: some View {
        if !walletLive.positions.isEmpty || !walletLive.morpho.isEmpty {
            Section {
                WalletLendingCard(aave: walletLive.positions, morpho: walletLive.morpho)
                    // Same reveal the balance card and holdings treemap wear —
                    // lending is usually the last of the live reads to land, so
                    // it gets the deepest stagger.
                    .modifier(RowEntrance(index: 2, wave: shapeWave, style: entranceStyle))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: DS.Space.s2, leading: DS.Space.s4,
                                              bottom: 0, trailing: DS.Space.s4))
            }
        }
    }

    /// Liquidity — Uniswap V3 positions for the wallets in scope (2026-07-30),
    /// a SIBLING to `walletDeFiSection`, not a third row inside it: lending
    /// asks "is it safe", a liquidity position asks "is it working" — a
    /// different subject earns a different card (see `WalletLiquidityCard`'s
    /// own doc comment). Nothing renders without a position.
    @ViewBuilder
    private var walletLiquiditySection: some View {
        if !walletLive.uniswap.isEmpty {
            Section {
                WalletLiquidityCard(book: walletLive.uniswap)
                    .modifier(RowEntrance(index: 3, wave: shapeWave, style: entranceStyle))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: DS.Space.s2, leading: DS.Space.s4,
                                              bottom: 0, trailing: DS.Space.s4))
            }
        }
    }

    /// Perps — Hyperliquid's open positions for the wallets in scope
    /// (2026-07-31). A SIBLING to lending and liquidity for the reason
    /// `WalletPerpsCard`'s own doc gives at length: a perp is not lending, so
    /// filing it under a card headed "Lending" would make the label wrong to
    /// buy one fewer surface. Nothing renders without a position.
    @ViewBuilder
    private var walletPerpsSection: some View {
        if !walletLive.hyperliquid.positions.isEmpty {
            Section {
                WalletPerpsCard(book: walletLive.hyperliquid)
                    .modifier(RowEntrance(index: 4, wave: shapeWave, style: entranceStyle))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: DS.Space.s2, leading: DS.Space.s4,
                                              bottom: 0, trailing: DS.Space.s4))
            }
        }
    }

    /// How many deadlines the room shows at once. Small on purpose: this is
    /// the head of a history feed, not an agenda.
    private static let walletUpcomingRows = 3

    /// What's still ahead in this room — the in-scope things carrying a future
    /// `dueAt`, soonest first (2026-07-31).
    ///
    /// These rows were effectively invisible, and it took two separate
    /// mechanisms to hide them. `dayGroups` DROPS future-dated things by
    /// design ("what's still ahead lives on Home's Coming up lane, not here",
    /// 2026-07-19) — but that lane retired with the Home board in §131, so
    /// what it pointed at no longer exists. And these particular rows dodge
    /// that drop only to land in a worse place: `AerodromeDeFi`,
    /// `HyperliquidDeFi` and `ENSExpiry` all stamp `capturedAt: .now` and
    /// carry the deadline on `dueAt`, reconciling the row IN PLACE as the date
    /// moves — so a vote window that first landed three weeks ago sorts three
    /// weeks down a stream ordered by arrival, far past the five-row preview,
    /// no matter how soon it closes.
    ///
    /// Which is the whole problem: a weekly vote deadline and a lock expiry
    /// are the two rows in this room where being late is the only failure
    /// mode, and they were the two least likely to be seen.
    private func walletUpcoming(_ visible: [Thing]) -> [Thing] {
        let now = Date.now
        return Array(visible.live
            .filter { ($0.dueAt ?? .distantPast) > now }
            .sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
            .prefix(Self.walletUpcomingRows))
    }

    /// "Coming up" — the room's deadlines, in its own card and its own row
    /// shape. Renders nothing when nothing is due, like every other section
    /// here (the honesty floor: no empty parcel holding a slot).
    ///
    /// A card rather than bare rows on the page, even though these ARE landed
    /// things and the room's other cards are live state. What decides it is
    /// what the reader is being asked to do: everything below is history to
    /// scroll, and this is a standing fact to act on — the same register as
    /// the cards above, and putting it on the page would make it read as the
    /// top of the stream, which is exactly the misreading that buried these
    /// rows in the first place.
    @ViewBuilder
    private func walletComingUpSection(_ upcoming: [Thing]) -> some View {
        if !upcoming.isEmpty {
            Section {
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    WalletSectionLabel(title: String(localized: "Coming up"))
                        .padding(.bottom, 2)
                    // `keyed` for identity + `live` inside the closure before
                    // any stored read (corollaries 1 and 3): this is a derived
                    // array, and a heal's delete can land in the same graph
                    // update that re-evaluates this closure.
                    ForEach(upcoming.keyed) { row in
                        if let thing = row.live {
                            Button {
                                DSHaptic.selection()
                                feedSheet = .thing(thing)
                            } label: {
                                WalletRow(mark: .kind(thing.kind),
                                          title: thing.title,
                                          subtitle: Self.dueLine(thing))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(DS.Space.s4)
                .dsWidgetSurface(fillOpacity: Self.walletCardFill)
                .modifier(RowEntrance(index: 5, wave: shapeWave, style: entranceStyle))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: DS.Space.s2, leading: DS.Space.s4,
                                          bottom: 0, trailing: DS.Space.s4))
            }
        }
    }

    /// "Closes Thursday" / "In 3 weeks" — when the deadline lands, in the
    /// grain that's actually useful at that distance. Guarded internally
    /// because it takes a raw `Thing` from a call site that may re-evaluate
    /// (corollary 4's rule for shared helpers).
    private static func dueLine(_ thing: Thing) -> String? {
        guard thing.isLive, let due = thing.dueAt else { return nil }
        return due.formatted(.relative(presentation: .named))
    }

    /// The wallet stream's preview rows, with routine transfers folded
    /// (2026-07-31).
    ///
    /// The preview is five rows over a room whose stream mixes two very
    /// different kinds of event: transfers, which a busy wallet produces by
    /// the dozen and which ask nothing of anyone, and the rare rows that carry
    /// a decision — a fresh approval, a liquidation crossing, a Privacy Pools
    /// clear. Straight chronology lets the first kind evict the second, so on
    /// an active wallet the one row worth acting on is behind "See all" and
    /// the preview is five variations of "Sent 0.1 ETH".
    ///
    /// So a RUN of consecutive routine transfers collapses into a single
    /// counted row, and the slots that frees go to whatever the run was
    /// burying. Nothing is dropped or hidden: the fold states its own count,
    /// the stream door below still totals the room unfolded, and the history
    /// screen behind it lists every row as it always did.
    ///
    /// Only a run of `walletFoldMin`+ folds — collapsing two rows into a row
    /// that says "2 transfers" saves nothing and costs the two titles.
    private static let walletFoldMin = 3

    private func walletStreamRows(_ things: [Thing]) -> [FeedRow] {
        var rows: [FeedRow] = []
        var run: [Thing] = []
        func flush() {
            guard !run.isEmpty else { return }
            if run.count >= Self.walletFoldMin, let newest = run.first {
                rows.append(.bundle(source: "Wallet",
                                    word: String(localized: "transfers"),
                                    count: run.count, newest: newest.capturedAt, art: []))
            } else {
                rows += run.map(FeedRow.single)
            }
            run = []
        }
        for thing in things {
            if Self.isRoutineTransfer(thing) {
                // A run never crosses midnight. The fold takes its date from
                // its newest member, so a run spanning three days would file
                // all of them under "Today" — a day header that lies about
                // what's under it, to save two rows. Same-day only.
                if let open = run.first,
                   !Self.groupingCalendar.isDate(open.capturedAt, inSameDayAs: thing.capturedAt) {
                    flush()
                }
                run.append(thing)
            } else {
                flush()
                rows.append(.single(thing))
            }
            // Stop once the folded list can fill the preview — a run still
            // open may yet grow, so the loop runs one flush past the cap and
            // the prefix below does the real trimming.
            if rows.count > Self.walletPreviewRows { break }
        }
        flush()
        return Array(rows.prefix(Self.walletPreviewRows))
    }

    /// A plain value transfer — the only thing this room folds.
    ///
    /// Deliberately an ALLOW-list, not "anything that isn't interesting":
    /// every other row in this room is recognized by its own `sourceRef`
    /// namespace (`wallet:approval:`, `wallet:permit2:`, `hyperliquid:*`,
    /// `aerodrome:*`) and stands alone, so a bridge added tomorrow is
    /// unfoldable by default rather than silently swept into a count. A
    /// flagged transfer (poisoning, a spoofed symbol) is never routine, and
    /// neither is anything carrying a deadline.
    private static func isRoutineTransfer(_ thing: Thing) -> Bool {
        guard thing.isLive, thing.kind == .transaction, !thing.isFlagged,
              thing.dueAt == nil, let ref = thing.sourceRef,
              ref.hasPrefix("wallet:")
        else { return false }
        return !ref.hasPrefix("wallet:approval:") && !ref.hasPrefix("wallet:permit2:")
    }

    /// The stream preview's day sections, over folded rows.
    ///
    /// A near-twin of `groupedSections`/`daySection`, and separate on purpose:
    /// those speak `[Thing]`, and a fold is not a thing. Same guards
    /// throughout — `live` re-checked inside the content closure, identity off
    /// `FeedRow`'s stored id, never the model.
    @ViewBuilder
    private func walletStreamSections(_ rows: [FeedRow], nextEventID: UUID?) -> some View {
        let groups = walletStreamDays(rows)
        // The same boundary the rest of the feed draws, over `FeedRow`'s own
        // stored dates — dropping it here would have quietly cost this room
        // its "new since" divider.
        let boundary = boundaryID(in: groups)
        ForEach(groups, id: \.0) { label, dayRows in
            // Rows in a day share ONE card silhouette (2026-07-21); a single
            // that stands alone breaks the run, and a fold — like the All
            // room's bundles — merges into it like any row-shaped thing.
            let positions = cardRunPositions(
                count: dayRows.count,
                isBreaker: { i in
                    if case .single(let item) = dayRows[i].kind,
                       let thing = item.live { return standsAlone(thing) }
                    return false
                },
                isBoundary: { dayRows[$0].id == boundary })
            Section {
                ForEach(Array(dayRows.enumerated()), id: \.element.id) { i, row in
                    if row.id == boundary { newSinceDivider }
                    switch row.kind {
                    case .single(let item):
                        // `live` INSIDE the closure, before any read
                        // (corollary 3): this re-evaluates against the array
                        // it already holds when a heal's delete lands.
                        if let thing = item.live {
                            shapedListRow(thing, index: i, nextEventID: nextEventID,
                                          position: positions[i])
                        }
                    case .bundle(_, let word, let count, let newest, _):
                        // The fold's door is the history screen, NOT
                        // `bundleListRow`'s source-filter tap: this room IS
                        // the Wallet source, so filtering to it would be a
                        // control that does nothing (the honesty rule's
                        // dead-control clause).
                        Button {
                            DSHaptic.selection()
                            route.pushBridge(.walletHistory(scope: selectedWallet))
                        } label: {
                            WalletRow(mark: .symbol("arrow.left.arrow.right", tint: DS.tint),
                                      title: String(localized: "\(count) \(word)"),
                                      subtitle: Self.foldSubline(newest))
                        }
                        .buttonStyle(.plain)
                        .modifier(RowEntrance(index: i, wave: shapeWave, style: entranceStyle))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(.init(top: DS.Space.s2,
                                             leading: DS.Space.s4 + DS.Space.s3,
                                             bottom: DS.Space.s2,
                                             trailing: DS.Space.s4 + DS.Space.s3))
                    }
                }
            } header: {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                    Text(label).dsText(.heading22).foregroundStyle(DS.textPrimary)
                }
                .textCase(nil)
                .padding(.leading, DS.Space.s4)
                .padding(.top, DS.Space.s6)
                .padding(.bottom, DS.Space.s1)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
    }

    /// "Most recent 2:14 PM" — a fold has no one title, so its subline says
    /// where in the day the run starts, which is the only thing the rows it
    /// replaced all agreed on.
    private static func foldSubline(_ newest: Date) -> String {
        String(localized: "Most recent \(newest.formatted(date: .omitted, time: .shortened))")
    }

    /// Day groups over folded rows, newest first — `dayGroups`' rule
    /// (including its "drop what's still ahead" clause, which is now genuinely
    /// true here: anything future-dated was promoted to Coming up above).
    private func walletStreamDays(_ rows: [FeedRow]) -> [(String, [FeedRow])] {
        let today = Self.groupingCalendar.startOfDay(for: .now)
        var order: [String] = []
        var groups: [String: [FeedRow]] = [:]
        for row in rows where Self.groupingCalendar.startOfDay(for: row.date) <= today {
            let label = dayLabel(row.date)
            if groups[label] == nil { order.append(label) }
            groups[label, default: []].append(row)
        }
        return order.map { ($0, groups[$0] ?? []) }
    }

    /// The stream's door — only when there's more behind it than the preview
    /// showed (no dead control when five rows is the whole history).
    @ViewBuilder
    private func walletSeeAllSection(total: Int) -> some View {
        if total > Self.walletPreviewRows {
            Section {
                WalletSeeAllRow(count: total) {
                    route.pushBridge(.walletHistory(scope: selectedWallet))
                }
                .listRowSeparator(.hidden)
                // On the page itself, not in a card — a quiet continuation
                // line, not another surface (user, 2026-07-20, twice).
                .listRowBackground(Color.clear)
            }
        }
    }

    /// The wallet switcher (prd §128) — an "All" chip then one chip per watched
    /// wallet, each wearing its `WalletFace` and, when selected, its signature
    /// tint. Scopes the whole Wallet feed (balance, treemap, NFTs, rows) to one
    /// wallet; only shown with more than one watched. Fill-only selection (no
    /// lines, per the design law). Mirrors the Wallet screen's own switcher.
    ///
    /// PINNED, not a List section (2026-07-20, prd §136's own rule applied to
    /// itself): as a section it scrolled away with the content it scopes —
    /// unreachable exactly when you're deep in the stream wondering whose
    /// transaction that was — and its glass had nothing moving behind it.
    /// As a `safeAreaInset` bar it floats under the shell's chip strip, the
    /// stream travels beneath it, and the material finally earns its blur.
    @ViewBuilder
    private var walletSwitcherBar: some View {
        if source == "Wallet", wallet.addresses.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Space.s2) {
                    walletSwitcherChip(label: "All", address: nil)
                    ForEach(wallet.addresses) { addr in
                        walletSwitcherChip(label: addr.label.isEmpty ? addr.short : addr.label,
                                           address: addr.address)
                    }
                }
                .padding(4)
                // Glass, by the law's own terms: scoping is a CONTROL, so the
                // switcher wears the floating material — one bar of glass for
                // the whole strip rather than a pane per chip.
                .dsGlass(cornerRadius: 999)
                .padding(.horizontal, DS.Space.s4)
                .padding(.vertical, DS.Space.s2)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func walletSwitcherChip(label: String, address: String?) -> some View {
        let isOn = walletChipIsOn(address)
        let tint = address.map(WalletFace.tint) ?? DS.tint
        return Button {
            DSHaptic.selection()
            withAnimation(DS.Motion.standard) { selectedWallet = address }
        } label: {
            HStack(spacing: 5) {
                if let address { WalletFace(address: address, size: 18) }
                Text(label)
                    .dsText(.subhead13)
                    .fontWeight(isOn ? .semibold : .regular)
                    .foregroundStyle(isOn ? DS.textPrimary : DS.textSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, DS.Space.s3)
            .padding(.vertical, DS.Space.s2)
            // The selection fill is ONE object that travels chip to chip on a
            // scope switch (matched geometry), tinting itself to the landing
            // wallet's own hue mid-flight — identity color doing the work.
            // Unselected chips keep their static faint fill underneath.
            .background {
                ZStack {
                    Capsule(style: .continuous).fill(DS.fillFaint)
                    if isOn {
                        Capsule(style: .continuous).fill(tint.opacity(0.18))
                            .matchedGeometryEffect(id: "walletSwitcherSelection",
                                                   in: walletSwitcherNS)
                    }
                }
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        // Chips ease at the strip's edges instead of clipping flat — the
        // source strip's own grammar (SourceChips:370), one tier down
        // (2026-08-04). Under Reduce Motion only the fade survives.
        .scrollTransition(.interactive, axis: .horizontal) { content, phase in
            content
                .scaleEffect(reduceMotion || phase.isIdentity ? 1 : 0.94)
                .opacity(phase.isIdentity ? 1 : 0.7)
        }
    }

    private func walletChipIsOn(_ address: String?) -> Bool {
        guard let address else { return selectedWallet == nil }
        guard let sel = selectedWallet else { return false }
        return walletSameAddress(sel, address)
    }

    /// Hex compares case-insensitively (EIP-55 case is a checksum), base58
    /// exactly (Solana case is identity) — the switcher's address equality.
    private func walletSameAddress(_ a: String, _ b: String) -> Bool {
        ENS.isHexAddress(a) ? a.lowercased() == b.lowercased() : a == b
    }

    /// The wallet leads with holdings — real, from Alchemy (WalletIngest),
    /// one treemap per watched address, same doc Home and the Wallet screen
    /// render (ruling 2026-07-09: the old mock demo-only block never showed a
    /// real user anything real).
    @ViewBuilder
    private var holdingsBlockSection: some View {
        if !blockStream.els.isEmpty {
            Section {
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    GenRender(id: "root", els: blockStream.els)
                        // A tapped holdings cell opens its token's chart
                        // (2026-07-14): the thing sheet when watched, the quick
                        // sheet when it's just held; a routeless native-coin
                        // cell keeps its old door — the Wallet screen (no dead
                        // controls). The Feed sets its own handler —
                        // HomeScreen's doesn't reach this surface.
                        .environment(\.genProjectTap) { name in
                            if let route = TokenQuickRoute.from(sentinel: name) {
                                if let thing = route.watchedThing(in: modelContext) {
                                    openThing(thing)
                                } else {
                                    // The combined map merges wallets, so a
                                    // cell tapped there carries the "held in"
                                    // breakdown with it (prd §155) — the fact
                                    // the per-wallet maps used to carry by
                                    // never merging in the first place.
                                    feedSheet = .token(route.withHolders(
                                        portfolio?.holders(forSymbol: route.symbol ?? "") ?? []))
                                }
                            } else if name == "@wallet" {
                                route.pushBridge(.wallet)
                            }
                        }
                    // The map says WHAT you hold; this says how much of it is
                    // one thing (prd §155) — a read that only means something
                    // about a whole portfolio.
                    if let portfolio, !portfolio.isEmpty {
                        WalletConcentrationLine(
                            portfolio: portfolio,
                            onOpen: portfolio.walletCount > 1 && selectedWallet == nil
                                ? { feedSheet = .allocation } : nil)
                            .padding(.horizontal, DS.Space.s4)
                        // And how much of it can move (2026-08-01). Concentration
                        // says the book is lopsided; this says how exposed the
                        // whole of it is — the one thing the map can't show,
                        // since stablecoins are scattered across its cells by
                        // symbol. A line, not a card: the surviving half of the
                        // cut "splits" pair (see `WalletPortfolio.stableLine`).
                        if let stable = portfolio.stableLine {
                            Text(stable)
                                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, DS.Space.s4)
                        }
                    }
                }
                // The holdings CARD (prd §160) — title, map, and the
                // concentration line become one parcel. GenTagMap already
                // self-pads horizontally by s4, which becomes this card's
                // inner gutter; only the bottom needs closing, since the map
                // pads its own top.
                .padding(.bottom, DS.Space.s3)
                .dsWidgetSurface(fillOpacity: Self.walletCardFill)
                // The SECTION's own arrival, not the cells' — GenTagMap
                // already stages its cells once mounted; this is what
                // stops the whole treemap from hard-popping in the moment
                // the holdings read lands (2026-07-20, wallet streaming fix).
                .modifier(RowEntrance(index: 1, wave: shapeWave, style: entranceStyle))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                // The card needs the page gutter the bare map didn't (it used
                // to bleed to the screen edge and self-pad its cells).
                .listRowInsets(EdgeInsets(top: DS.Space.s2, leading: DS.Space.s4,
                                          bottom: 0, trailing: DS.Space.s4))
            }
        }
    }

    /// A Snapchat memory that has its picture back — the grid's own membership
    /// test, used to split that room (2026-07-31). Guarded internally because
    /// it is a shared helper taking a raw `Thing` and every caller hands it its
    /// own derived array (COROLLARY 4, see `ThingRowKeying`).
    private static func isMemoryTile(_ thing: Thing) -> Bool {
        thing.isLive && thing.source == "Snapchat" && thing.kind == .file
            && thing.previewImageData != nil
    }

    /// A connected-folder image whose heal has landed a thumbnail — the mixed
    /// Files room's grid membership (2026-08-02), `isMemoryTile`'s shape with
    /// one addition: the extension check makes the image claim explicit
    /// (today only images ever carry `previewImageData` under Files, but that
    /// is the heal's implementation detail, not this test's contract). Guarded
    /// internally for the same corollary-4 reason as above.
    private static func isFileImageTile(_ thing: Thing) -> Bool {
        thing.isLive && thing.source == "Files" && thing.kind == .file
            && thing.previewImageData != nil
            && FilesIngest.isImageRef(thing.sourceRef)
    }

    /// What a grid tile says across its foot. A screenshot's title is the text
    /// it shows, which is the tile's whole point; a Snapchat memory's title is
    /// its date, which the day pill already carries — so that room says the
    /// PLACE the export named, or nothing at all.
    private static func tileCaption(_ thing: Thing) -> String? {
        guard thing.isLive else { return nil }
        if thing.source == "Snapchat" {
            return SnapchatImport.place(inMemoryNote: thing.content)
        }
        return thing.title
    }

    /// Photos: one continuous grid — day labels are overlay pills on the first
    /// photo of each day, never section breaks (mock P1).
    private func photoGridSection(_ visible: [Thing]) -> some View {
        Section {
            let items = visible.live
            // Day pills computed HERE, while every model is still valid, so
            // the cell closure below compares plain strings instead of
            // reaching back into `items[i - 1]` for a `capturedAt` a heal may
            // have tombstoned by the time SwiftUI re-runs it (corollary 3,
            // build 176 — see `ThingRowKeying`).
            let dayLabels = items.map { dayLabel($0.capturedAt) }
            // Hand-rolled row-chunking, NOT LazyVGrid: on iOS 26,
            // `GridItem.spacing` and even `.padding()`'s horizontal
            // component are silently ignored on a `.flexible()` column's
            // cross axis — confirmed empirically (a 60pt spacing value and
            // later an 80pt padding both only ever showed up as VERTICAL
            // gap, never horizontal, no matter which mechanism carried it).
            // `HStack`/`VStack` spacing has no such bug, so rows are built
            // by hand instead (user, 2026-07-13 — tiles were touching edge
            // to edge with no gutter at all).
            let perRow = items.count > 12 ? 3 : 2
            let rows = stride(from: 0, to: items.count, by: perRow).map {
                Array(items[$0..<min($0 + perRow, items.count)])
            }
            // The real fix for the leak was in `PhotoWell` (a `scaledToFill`
            // image reporting its own huge intrinsic size instead of
            // respecting the cell) — with that fixed, a plain HStack's normal
            // equal-flexible-child distribution is enough; no manual width
            // math needed here.
            VStack(spacing: DS.Space.s3) {
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                    HStack(spacing: DS.Space.s3) {
                        ForEach(Array(keyed(row).enumerated()), id: \.element.id) { colIndex, item in
                            // Corollary 3 (build 176) — see `ThingRowKeying`.
                            if let thing = item.live {
                                let i = rowIndex * perRow + colIndex
                                let firstOfDay = i == 0 || dayLabels[i - 1] != dayLabels[i]
                                Button {
                                    openThing(thing)
                                } label: {
                                    PhotoCell(thing: thing, dayPill: firstOfDay ? dayLabels[i] : nil,
                                              caption: Self.tileCaption(thing))
                                }
                                // The tiles press like tiles (2026-07-10) — the same
                                // settle the Settings tiles and treemap cells wear.
                                .buttonStyle(DSTileButtonStyle())
                                .dsHover()
                                // Zoom source removed with the thing-open zoom (prd 232, 2026-07-30).
                            }
                        }
                        // An incomplete last row keeps its tiles at the same
                        // width as full rows rather than stretching to fill.
                        if row.count < perRow {
                            ForEach(0..<(perRow - row.count), id: \.self) { _ in
                                Color.clear
                            }
                        }
                    }
                }
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            // The grid rides the same content gutter as every other feed row —
            // tiles no longer bleed to the screen edge (which clipped the day
            // pills), and the page background reads clearly between them so a
            // run of light screenshots stops merging into one slab.
            .listRowInsets(.init(top: DS.Space.s3, leading: DS.Space.s4,
                                 bottom: DS.Space.s3, trailing: DS.Space.s4))
        }
    }

    /// Calendar reads forward: Today and upcoming days ascending, event-time
    /// order within each day (mock C2) — and, separately, what's already
    /// happened, newest day first.
    ///
    /// Two lists, not one, since 2026-07-27 (user: "this calendar display feed
    /// with dates and different orders is awkward, can we hide past events?").
    /// The old shape concatenated them, so a single scroll ran forward then
    /// backward — Monday, Wednesday, then last Friday — and the reversal at
    /// the seam was invisible. An agenda is what's AHEAD; history is the All
    /// feed's job (a past event still sits in its own day there). So the room
    /// shows the upcoming days and keeps the past behind one disclosure at the
    /// foot, the way Reminders already keeps its stale to-dos.
    ///
    /// LIVE ONLY at the top of the derivation (COROLLARY 2, build 150): every
    /// caller below reads `capturedAt` — the split itself, the toggle's count,
    /// the day headers — and a heal pass can delete a row out from under any
    /// of them mid-update.
    private func agendaSplit(_ visible: [Thing]) -> (upcoming: [(String, [Thing])],
                                                     past: [(String, [Thing])]) {
        let cal = Self.groupingCalendar
        let today = cal.startOfDay(for: .now)
        var buckets: [Date: [Thing]] = [:]
        for thing in visible where thing.isLive {
            buckets[cal.startOfDay(for: thing.capturedAt), default: []].append(thing)
        }
        func groups(_ days: [Date]) -> [(String, [Thing])] {
            days.map { day in
                (dayLabel(day), (buckets[day] ?? []).sorted { $0.capturedAt < $1.capturedAt })
            }
        }
        return (groups(buckets.keys.filter { $0 >= today }.sorted()),
                groups(buckets.keys.filter { $0 < today }.sorted(by: >)))
    }

    /// True while the Calendar room is holding past events back — the closing
    /// "that's everything" line has to sit out then, the way it already does
    /// for Reminders and Wallet (both render a subset of `visible`). The
    /// disclosure row names the hidden count instead.
    private func hidesPastEvents(_ visible: [Thing]) -> Bool {
        guard shape == .calendar, !pastEventsExpanded else { return false }
        let today = Self.groupingCalendar.startOfDay(for: .now)
        return visible.contains {
            $0.isLive && Self.groupingCalendar.startOfDay(for: $0.capturedAt) < today
        }
    }

    /// The Calendar room: the agenda ahead, then — only when asked for — what
    /// already happened, newest first. The disclosure sits in one place
    /// whichever way it's pointing, so expanding doesn't move the control out
    /// from under the finger that tapped it.
    @ViewBuilder
    private func calendarSections(_ visible: [Thing], nextEventID: UUID?) -> some View {
        let split = agendaSplit(visible)
        let pastCount = split.past.reduce(0) { $0 + $1.1.count }
        groupedSections(split.upcoming, nextEventID: nextEventID)
        if split.upcoming.isEmpty { nothingAheadSection }
        if pastCount > 0 {
            pastEventsToggle(count: pastCount)
            if pastEventsExpanded {
                groupedSections(split.past, nextEventID: nextEventID)
            }
        }
    }

    /// An agenda with nothing on it says so, rather than leaving the room
    /// looking like a load that never finished. Not `filteredEmptyState` —
    /// nothing is filtered out and there IS a corpus here; the past sits one
    /// tap below.
    private var nothingAheadSection: some View {
        Section {
            Text("Nothing coming up.")
                .dsText(.body17)
                .foregroundStyle(DS.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, DS.Space.s4)
                .padding(.top, DS.Space.s6)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
        }
    }

    /// The past-events disclosure — a quiet inline door on the page itself,
    /// not a card (the same voice as the wallet's "See all transactions"):
    /// the agenda above is the content, this is where the record continues.
    private func pastEventsToggle(count: Int) -> some View {
        Section {
            Button {
                DSHaptic.selection()
                withAnimation(DS.Motion.standard) { pastEventsExpanded.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Text(pastEventsExpanded
                         ? String(localized: "Hide past events")
                         : (count == 1 ? String(localized: "Show 1 past event")
                                       : String(localized: "Show \(count) past events")))
                        .dsText(.callout15).fontWeight(.semibold)
                        .monospacedDigit()
                    Image(systemName: pastEventsExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .accessibilityHidden(true)
                }
                .foregroundStyle(DS.tint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Space.s1)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, DS.Space.s6)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets())
        }
    }

    /// The next upcoming event — its ROW carries the emphasis (no hero).
    /// Events only: in the All shape other kinds share the list, and only
    /// an event's capture time means "starts at".
    private func nextEventID(_ visible: [Thing]) -> UUID? {
        visible.filter { $0.isLive && $0.kind == .event && $0.capturedAt > .now }
            .min { $0.capturedAt < $1.capturedAt }?.id
    }

    /// Live right now, from the source's own current-live set (Twitch
    /// refreshes it every foreground) — never inferred from row age.
    private func isLive(_ thing: Thing) -> Bool {
        thing.source == "Twitch"
            && thing.sourceRef.map { TwitchIngest.liveRefs.contains($0) } ?? false
    }

    /// Float any live rows to the top of the NEWEST group (2026-07-21) — a
    /// stream on right now isn't a chronological row. Scoped to Twitch (the
    /// one source with a live set) and to the first group only, so history
    /// below stays in time order. A no-op everywhere else.
    private func liveFirst(_ groups: [(String, [Thing])]) -> [(String, [Thing])] {
        guard source == "Twitch", let first = groups.first,
              first.1.contains(where: isLive) else { return groups }
        let rows = first.1
        var out = groups
        out[0] = (first.0, rows.filter(isLive) + rows.filter { !isLive($0) })
        return out
    }

    /// The reading list's lede (2026-07-21) — a saved link is a DOOR, not a
    /// read, so the shape names the pile instead of pretending the rows are
    /// consumed: how many landed this month, how many are older, and the
    /// oldest one still waiting (a gentle "come back to this", never a
    /// count-shaming streak — §10). Facts only, and no "unopened" claim the
    /// model can't back (Thing tracks no read state) — "still here" is what's
    /// true. Yields to an auto hero so a shape never stacks two overviews.
    @ViewBuilder
    private func readingLedeSection(_ visible: [Thing]) -> some View {
        let cal = Self.groupingCalendar
        let thisMonth = visible.filter {
            cal.isDate($0.capturedAt, equalTo: .now, toGranularity: .month)
        }.count
        let older = visible.count - thisMonth
        // Oldest still on the list, shown only once it's genuinely aged (30d+)
        // — a fresh list has no pile to nudge about.
        let monthAgo = Date.now.addingTimeInterval(-30 * 86_400)
        let oldest = visible.filter { $0.capturedAt < monthAgo }
            .min { $0.capturedAt < $1.capturedAt }
        if visible.count >= 3 {
            ledeSection(ReadingLede(thisMonth: thisMonth, older: older, oldest: oldest))
        }
    }

    /// Gmail: what's waiting on you, capped at two (mock G1). Doing-marked
    /// only (honesty fix 2026-07-13): the old `content.contains("?")` sniff
    /// promoted any newsletter with a question mark to "waiting on you" —
    /// fake status. The section now shows only what the person marked
    /// in motion, and earns back a smarter derivation later.
    @ViewBuilder
    private func waitingSection(_ visible: [Thing], nextEventID: UUID?) -> some View {
        let waiting = visible.filter { $0.mark == .doing }.prefix(2).map { $0 }
        if !waiting.isEmpty {
            daySection("Waiting on you", waiting, nextEventID: nextEventID)
        }
    }

    // Waiting mails stay in their day groups too (unlike agent approvals,
    // which ARE removed): a mail is a record, and excluding only the first
    // two doing-marked mails (the lede's cap) would punch order-dependent
    // holes in the day history. The lede highlights; the record stays whole.

    /// Reminders: state groups — Doing, To do (stale todos collapse), Done
    /// (same-day only).
    @ViewBuilder
    private func reminderSections(_ visible: [Thing], nextEventID: UUID?) -> some View {
        let doing = visible.filter { $0.mark == .doing }
        let todos = visible.filter { $0.mark == .todo || $0.mark == .none }
        let weekAgo = Date.now.addingTimeInterval(-7 * 86_400)
        let fresh = todos.filter { $0.capturedAt > weekAgo }
        let stale = todos.filter { $0.capturedAt <= weekAgo }
        let doneToday = visible.filter {
            $0.mark == .done && Calendar.current.isDateInToday($0.capturedAt)
        }
        if !doing.isEmpty { daySection("Doing", doing, nextEventID: nextEventID) }
        if !fresh.isEmpty || !stale.isEmpty {
            // One To do card (2026-07-21): the Older toggle — or the stale
            // rows it expands into — continues the fresh rows' surface
            // instead of sitting under it as a flat band.
            let hasToggle = !stale.isEmpty && !staleExpanded
            let slots = fresh.count + (staleExpanded ? stale.count : 0) + (hasToggle ? 1 : 0)
            let positions = cardRunPositions(count: slots)
            Section {
                ForEach(Array(keyed(fresh).enumerated()), id: \.element.id) { i, item in
                    // Corollary 3 (build 176) — see `ThingRowKeying`.
                    if let thing = item.live {
                        shapedListRow(thing, index: i, nextEventID: nextEventID,
                                      position: positions[i])
                    }
                }
                if !stale.isEmpty {
                    if staleExpanded {
                        ForEach(Array(keyed(stale).enumerated()), id: \.element.id) { i, item in
                            // Corollary 3 (build 176) — see `ThingRowKeying`.
                            if let thing = item.live {
                                shapedListRow(thing, index: i, nextEventID: nextEventID,
                                              position: positions[fresh.count + i])
                            }
                        }
                    } else {
                        HStack {
                            Text("Older").dsText(.body17).foregroundStyle(DS.textSecondary)
                            Text("\(stale.count)").dsText(.subhead13).foregroundStyle(DS.textTertiary)
                            Spacer()
                            Image(systemName: "chevron.down")
                                .accessibilityHidden(true)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(DS.textTertiary)
                        }
                        .padding(.vertical, DS.Space.s1)
                        .contentShape(Rectangle())
                        .onTapGesture { withAnimation(DS.Motion.standard) { staleExpanded = true } }
                        .listRowBackground(dayCardBackground(positions[slots - 1]))
                        .listRowInsets(.init(top: DS.Space.s2,
                                             leading: DS.Space.s4 + DS.Space.s3,
                                             bottom: DS.Space.s2,
                                             trailing: DS.Space.s4 + DS.Space.s3))
                        .listRowSeparator(.hidden)
                    }
                }
            } header: {
                Text("To do").dsText(.heading17).foregroundStyle(DS.textPrimary).textCase(nil)
            }
        }
        if !doneToday.isEmpty { daySection("Done", doneToday, nextEventID: nextEventID) }
    }

    // MARK: - Row dispatch (the shape decides what a row leads with)

    /// The swipe's hand-off target, when the thing has one — shared by both
    /// swipe edges so they agree on what counts as "has a destination".
    private func openVerb(for thing: Thing) -> Verb? {
        VerbDerivation.verbs(for: thing).first {
            if case .openURL = $0.action { return true } else { return false }
        }
    }

    /// Where a row sits in its day's shared card (ruling 2026-07-21,
    /// superseding 2026-07-13's gap-only clustering): a contiguous run of
    /// row-shaped things within a day merges into ONE card — the §61
    /// section-lift mechanic brought to the plain list — while the
    /// rhythm-breakers (`standsAlone`) keep free-standing cards between
    /// runs, and the new-since seam splits a day's card in two.
    private enum RunPosition { case only, first, middle, last }

    /// Positions for a section's rows, index-based so All's FeedRow bundles
    /// and plain Thing arrays share one derivation. A run breaks at a
    /// free-standing row on either side, and at the new-since boundary
    /// (the divider renders BEFORE the boundary row, so the row above it
    /// closes its run and the boundary row opens a fresh one).
    private func cardRunPositions(count: Int,
                                  isBreaker: (Int) -> Bool = { _ in false },
                                  isBoundary: (Int) -> Bool = { _ in false }) -> [RunPosition] {
        (0..<count).map { i -> RunPosition in
            let starts = i == 0 || isBreaker(i) || isBreaker(i - 1) || isBoundary(i)
            let ends = i == count - 1 || isBreaker(i) || isBreaker(i + 1) || isBoundary(i + 1)
            switch (starts, ends) {
            case (true, true):   return .only
            case (true, false):  return .first
            case (false, true):  return .last
            case (false, false): return .middle
            }
        }
    }

    /// The anatomies that earn a free-standing card — shapedRow's
    /// rhythm-breakers. Everything else (band, check, excerpt, reading,
    /// music) merges into its day's run.
    ///
    /// `thing.modelContext == nil` is the crash guard (2026-07-24, live
    /// TestFlight crash on 125/126, upgrade-only — never a fresh install):
    /// `bundledSections`' `visible` array is captured once per render, but
    /// the delete-sync heal passes (Calendar/Reminders/Contacts/HomeKit/
    /// Bluesky/Farcaster, added §prd 121) run as `Task { @MainActor in }` —
    /// correctly serialized with the UI, but still able to land BETWEEN this
    /// render's capture and this closure's evaluation inside the `ForEach`.
    /// A `Thing` SwiftData deletes gets its `modelContext` niled out first;
    /// reading that one property is documented-safe on a deleted model, but
    /// `thing.kind`/`thing.mark` below fault-resolve against the store and
    /// crashed (`_assertionFailure` inside SwiftData, real device only — a
    /// fresh install has no synced Calendar/Reminders/etc. yet to delete).
    private func standsAlone(_ thing: Thing) -> Bool {
        guard thing.modelContext != nil else { return false }
        if thing.kind == .approval && thing.mark != .done { return true }  // consent card
        if shape == .social { return true }                                // PostCard, media at width
        if shape == .chat && thing.mark == .doing { return true }          // TakeawayCard
        if TokenPulse.shared.pulse(for: thing) != nil { return true }      // TokenRow fat anatomy
        if PredictionPulse.shared.pulse(for: thing) != nil { return true } // PredictionRow, same
        return false
    }

    /// The run-aware card surface: first/last rows carry the card's rounded
    /// shoulders and the s1 breathing edge; middle rows run square and
    /// GAPLESS, so a row's shadow falls on the adjacent same-color fill and
    /// vanishes (§61's measured mechanic) — only the run's outer silhouette
    /// casts, one lifted card instead of a stack of shadowed rows.
    private func dayCardBackground(_ position: RunPosition) -> some View {
        let r = DS.Radius.card
        let top = position == .first || position == .only
        let bottom = position == .last || position == .only
        return UnevenRoundedRectangle(topLeadingRadius: top ? r : 0,
                                      bottomLeadingRadius: bottom ? r : 0,
                                      bottomTrailingRadius: bottom ? r : 0,
                                      topTrailingRadius: top ? r : 0,
                                      style: .continuous)
            .fill(DS.surfaceSheet)
            .padding(.horizontal, DS.Space.s4)
            .padding(.top, top ? DS.Space.s1 : 0)
            .padding(.bottom, bottom ? DS.Space.s1 : 0)
            .shadow(color: DS.cardShadow, radius: 18, x: 0, y: 6)
    }

    /// Lists are AIR; parcels are for the reads (user ruling 2026-07-22,
    /// superseding the same-day "card is a group" cut). The day card failed
    /// at both extremes — one row wearing a full card was chrome around
    /// nothing, and a GitHub day's dozens made one giant slab — which means
    /// the card was never doing group-work at all: the DAY HEADER is the
    /// grouping. Apple Music is the named model: songs never sit in cards;
    /// surfaces are spent on featured content. So ordinary rows render bare
    /// on the ink, every shape, every run length. What keeps a surface: the
    /// designed-card anatomies (consent card, post, takeaway, fat token row
    /// — cards by anatomy, their surface IS this background) and the head
    /// reads (map, chart, mosaic, lede), which stay §160 parcels.
    ///
    /// `selected` is the keyboard walk's position (Mac, 2026-07-31) and is
    /// painted HERE rather than as a `.background` on the row's content,
    /// because this function already owns row-surface geometry. The first cut
    /// drew its own `RoundedRectangle` at `DS.Radius.widget` inside the row's
    /// `listRowInsets`, which put a smaller, rounder, differently-inset rect
    /// floating inside the card it was meant to be selecting — and mid-run it
    /// could not take the square shoulders a merged run demands, so the
    /// selected row visibly broke the run's silhouette. Inheriting the shape
    /// makes selection a state of the surface instead of a second surface. A
    /// FILL and never a stroke: "no hairlines — zero exceptions" makes an
    /// outline the wrong vocabulary, and `DS.tintDim` is already how this app
    /// says "this one".
    @ViewBuilder
    private func runBackground(_ position: RunPosition, bare: Bool,
                               selected: Bool = false) -> some View {
        if selected {
            selectionWash(position, bare: bare)
        } else if bare {
            Color.clear
        } else {
            dayCardBackground(position)
        }
    }

    /// The walk's position, wearing the run's own corners and insets. A bare
    /// row gets the wash alone; a card row keeps its surface with the wash over
    /// it, so a consent card or a post still reads as the card it is.
    private func selectionWash(_ position: RunPosition, bare: Bool) -> some View {
        let r = DS.Radius.card
        let top = position == .first || position == .only
        let bottom = position == .last || position == .only
        return ZStack {
            if !bare { dayCardBackground(position) }
            UnevenRoundedRectangle(topLeadingRadius: top ? r : 0,
                                   bottomLeadingRadius: bottom ? r : 0,
                                   bottomTrailingRadius: bottom ? r : 0,
                                   topTrailingRadius: top ? r : 0,
                                   style: .continuous)
                .fill(DS.tintDim)
                .padding(.horizontal, DS.Space.s4)
                .padding(.top, top ? DS.Space.s1 : 0)
                .padding(.bottom, bottom ? DS.Space.s1 : 0)
        }
    }

    /// The row inside a list section, with the standard list plumbing attached.
    private func shapedListRow(_ thing: Thing, index: Int = 0, nextEventID: UUID?,
                               position: RunPosition = .only,
                               imageOnly: Bool = false,
                               wideArt: Bool = false,
                               replies: [String: [Thing]] = [:]) -> some View {
        // AnyView: same metadata-depth insurance as GenRender (crash fix).
        // A Button since 2026-08-04 (the microanimation pass), not an
        // `onTapGesture`: the tap gesture gave no touch-down feedback, so a
        // press read as nothing until the sheet arrived. `RowPress` is the
        // dim-plus-settle a listRowBackground slab allows (its doc explains
        // why not `PressSpring`'s dip). Same single choke point, same one
        // gesture — tap opens the sheet, everything else stays long-press.
        // Zoom source removed with the thing-open zoom (prd 232, 2026-07-30).
        return Button {
            openThing(thing)
        } label: {
            AnyView(shapedRow(thing, nextEventID: nextEventID, index: index,
                              imageOnly: imageOnly, wideArt: wideArt,
                              replies: replies))
                .modifier(RowEntrance(index: index, wave: shapeWave, style: entranceStyle))
                .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
            // Mac/pointer polish (2026-07-31): the feed rendered bare rows
            // over `onTapGesture` until 2026-08-04 (now the Button above),
            // and this was the one surface a Mac cursor crossed with nothing
            // lighting up. One call, one place — every shape (`shapedRow`'s
            // dozen anatomies) inherits it.
            .dsHover()
            // …and the lift on top of the highlight (Mac delight, 2026-08-03,
            // user: "I like the rows lifting and shadow deepening"): the row
            // rises 1pt with a deepened shadow under the cursor. Same one
            // call site, so every row anatomy inherits it; compiles away off
            // Catalyst.
            .macHoverLift()
            // V3b (2026-07-07, supersedes the kind-color wash): rows are
            // NEUTRAL cards — the translucent kind wash read as murk. Color
            // moved into the tag text: the project's own stable hue.
            // `walkSelected` is only ever written on Mac, and `DS.isMac`
            // short-circuits ahead of the comparison — so no phone row ever
            // observes it (see `ShellChrome.canWalk`).
            .listRowBackground(runBackground(position, bare: !standsAlone(thing),
                                             selected: DS.isMac
                                                && chrome.walkSelected == thing.id.uuidString))
            // Feed rhythm (2026-07-13): back to s2 — the s3 airy read made
            // every gap the same size, so days never clustered. Rows sit
            // tight within their day; the day header carries the big gap.
            .listRowInsets(.init(top: DS.Space.s2,
                                 leading: DS.Space.s4 + DS.Space.s3,
                                 bottom: DS.Space.s2,
                                 trailing: DS.Space.s4 + DS.Space.s3))
            .listRowSeparator(.hidden)
            // One gesture, one meaning: TAP opens the sheet — tags and verbs
            // live there. The row's OTHER verbs ride a long-press (ruling
            // 2026-07-16, supersedes the both-edge swipe of 2026-07-15): the
            // feed pages between sources now, and a horizontal pan can only
            // belong to one thing. Measured before ruling — a `TabView(.page)`
            // pan claims 100% of horizontal drags, at every drag length, even
            // at the last page where it merely rubber-bands and the row still
            // never opens. So the swipe wasn't degraded, it was unreachable;
            // long-press is what's left, and it's what the Home board has used
            // for Open/Unpin all along (`GenRenderer.pinnedRowActions`).
            .contextMenu {
                // Derived ONCE for the whole menu. `contextMenu(menuItems:)`
                // takes a non-escaping builder, so this runs at body-build time
                // per row — and `VerbDerivation.verbs` reaches `thing.content`
                // (one of the heavy inline columns the 2026-07-30 pass
                // deliberately leaves out of the All room's `propertiesToFetch`)
                // and runs an `NSDataDetector` pass over it. Asking twice, once
                // for the open verb and once for the rest, doubled a per-row
                // fault and a per-row detector run against the exact
                // optimization that pass exists for.
                let verbs = VerbDerivation.verbs(for: thing)
                if let openVerb = verbs.first(where: {
                    if case .openURL = $0.action { return true } else { return false }
                }) {
                    Button {
                        run(openVerb, on: thing)
                    } label: {
                        Label("Open in app", systemImage: "arrow.up.right")
                    }
                }
                // The row's OTHER derived reads (2026-07-31). This menu is the
                // whole verb surface for a row — the both-edge swipe was
                // measured unreachable inside a paged TabView and retired on
                // 2026-07-16 — and it had been carrying exactly one of the
                // verbs `VerbDerivation` produces, so Translate (a read, over
                // the thing's own text) existed for every row in the corpus
                // and was reachable from none of them.
                //
                // READS ONLY, which the swipe ruling already settled and this
                // menu inherits: writes confirm in the sheet, Copy is
                // sheet-only, and Approve/Deny are consent — a consent action
                // fired from a right-click menu is precisely the kind of
                // one-slip yes S10 exists to prevent.
                if let translate = verbs.first(where: {
                    if case .translate = $0.action { return true } else { return false }
                }) {
                    Button {
                        run(translate, on: thing)
                    } label: {
                        Label(translate.label, systemImage: translate.icon)
                    }
                }
                ThingShareLink(thing: thing) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
    }

    @ViewBuilder
    private func shapedRow(_ thing: Thing, nextEventID: UUID?, index: Int = 0,
                           imageOnly: Bool = false,
                           wideArt: Bool = false,
                           replies: [String: [Thing]] = [:]) -> some View {
        // Dead-model guard first (corollary 3, build 176 — see
        // `ThingRowKeying`). This is where build 176 trapped: `thing.kind`,
        // one frame after a heal deleted the row, reached from a correctly
        // KEYED `ForEach` whose content closure SwiftUI re-ran against the
        // array it still held. Callers guard too — reads in their argument
        // lists happen before this line — but the funnel guards itself so a
        // future caller can't reintroduce the same crash. Costs no view-tree
        // depth: it is another arm of a `@ViewBuilder` chain that already
        // branches here.
        if !thing.isLive {
            EmptyView()
        // Approval is the one rhythm-breaker everywhere: the consent card.
        } else if thing.kind == .approval, thing.mark != .done {
            ApprovalCard(thing: thing,
                         onApprove: { perform(Verb(label: "Approve", icon: "checkmark.circle", action: .approve), on: thing) },
                         onDeny: { perform(Verb(label: "Deny", icon: "xmark.circle", action: .deny), on: thing) })
        } else {
            // B2b (ruling 2026-07-06): ONE row anatomy — the band — for every
            // kind and every shape. The wash carries the kind; per-kind row
            // shapes retired. One earned exception: the doing chat takeaway.
            // Reminders are the band too — read-only (ruling 2026-07-25), so
            // no check circle: a done reminder is just struck through, its
            // state grouped by section, never a control that does nothing.
            switch shape {
            case .calendar:  BandRow(thing: thing, emphasized: thing.id == nextEventID)
            case .reminders: BandRow(thing: thing)
            case .music:     MusicRow(thing: thing)
            // The medium's own proportions (prd §219) — a still arrives as a
            // still, a Steam header as a capsule, a pin as a pin. One row
            // height across all of them, so the feed keeps a single rhythm.
            case .media where MediaShape.art(for: thing.source) != nil:
                MediaRow(thing: thing,
                         art: MediaShape.art(for: thing.source) ?? .cover,
                         live: isLive(thing))
            case .chat where thing.mark == .doing:
                TakeawayCard(thing: thing)
            // Native anatomies (2026-07-13): in its own room a note leads
            // with its text, a conversation with its opening line, a post
            // with its author and media, a link with where it's from. All
            // keeps the band — these relax only inside the source's shape.
            // The wallet room reads as a ledger (prd §157): the band, with the
            // moved amount pulled out of the sentence into a right-aligned
            // figure. Same anatomy as every other row — one opt-in flag.
            case .wallet: BandRow(thing: thing, moneyColumn: true, rippleIndex: index)
            case .notes:  ExcerptRow(thing: thing, lines: 3)
            case .chat:   ExcerptRow(thing: thing, lines: 2)
            case .social:
                if thing.kind == .link {
                    // Item 1 (2026-07-27): an article a post shared lands as
                    // its own thing now — it reads like the reading list it
                    // actually is, not a post with no author of its own.
                    ReadingRow(thing: thing)
                } else if let kids = replies[thing.id.uuidString], !kids.isEmpty {
                    // Item 6 (2026-07-27): a head with folded-in self-replies
                    // reads as one thread card; everything else is a plain post.
                    SocialThreadCard(head: thing, replies: kids)
                } else {
                    PostCard(thing: thing)
                }
            // The X room (2026-08-06). A post reads as a post, and that
            // includes a LIKED one — it is somebody else's post, and
            // `XArchiveImport.fetchFaces` has stamped its author since the
            // seat shipped, which is the field `PostCard` leads with.
            //
            // Two rows here are not posts and say so by being something else:
            // the app's own import receipt (a `.note` by kind, but the one row
            // in the room nobody wrote — it keeps the plain band it wears in
            // All) and a DM conversation, which is a transcript and reads as
            // the excerpt every other chat room draws.
            case .x:
                if Corpus.isImportReceipt(thing) {
                    BandRow(thing: thing,
                            emphasized: thing.id == nextEventID,
                            live: false,
                            imageOnly: imageOnly,
                            wideArt: wideArt)
                } else if thing.kind == .chat {
                    ExcerptRow(thing: thing, lines: 2)
                } else {
                    PostCard(thing: thing)
                }
            case .x402:
                // The import receipt keeps its plain band — it is our own note
                // about the sync, not a company selling anything.
                if Corpus.isImportReceipt(thing) {
                    BandRow(thing: thing,
                            emphasized: thing.id == nextEventID,
                            live: false,
                            imageOnly: imageOnly,
                            wideArt: wideArt)
                } else {
                    // The lane's biggest seller leads it. `index` is the
                    // position within the SECTION, and since sections are lanes
                    // ranked by service count, index 0 is that lane's leader —
                    // so each shelf gets one landmark instead of reading as an
                    // undifferentiated run.
                    CircleX402Row(thing: thing, lead: index == 0)
                }
            case .appStoreConnect:
                if thing.tags.contains("Review") {
                    AppReviewRow(thing: thing)
                } else {
                    BandRow(thing: thing,
                            emphasized: thing.id == nextEventID,
                            live: false,
                            imageOnly: imageOnly,
                            wideArt: wideArt)
                }
            case .cursor:
                // Our own note about the sync keeps its plain band, the way
                // the x402 and X rooms treat theirs — it is not a run.
                if Corpus.isImportReceipt(thing) {
                    BandRow(thing: thing,
                            emphasized: thing.id == nextEventID,
                            live: false,
                            imageOnly: imageOnly,
                            wideArt: wideArt)
                } else {
                    CursorRow(thing: thing)
                }
            case .safari: ReadingRow(thing: thing)
            default:
                // Perishables show their clock everywhere (ruling 2026-07-09):
                // the next event's countdown and a stream's Live state ride
                // the row in All too, not just in their source's shape. A
                // watched token whose pulse has landed wears the fat anatomy
                // (TokenRow, prd §102) everywhere too; until it lands, the
                // plain band + timestamp — never a faked price.
                if let pulse = TokenPulse.shared.pulse(for: thing) {
                    TokenRow(thing: thing, pulse: pulse)
                } else if let odds = PredictionPulse.shared.pulse(for: thing) {
                    // A watched market wears its odds the same way — and the
                    // same rule holds: until the pulse lands, the plain band,
                    // never a faked probability.
                    PredictionRow(thing: thing, pulse: odds)
                } else {
                    // The source badge (2026-08-09): only the unscoped All
                    // room asks for it — `.all` is this same `default` arm's
                    // OTHER tenant (a single-source room with no shape case
                    // of its own, e.g. Instagram/TikTok, falls here too as
                    // `.plain`), where the room itself already says the
                    // source and a badge would double-tell it.
                    BandRow(thing: thing,
                            emphasized: thing.id == nextEventID,
                            live: isLive(thing),
                            imageOnly: imageOnly,
                            wideArt: wideArt,
                            sourceBadge: shape == .all)
                }
            }
        }
    }

    // MARK: - Pieces

    /// Empty Feed — the rain come to rest (2026-07-16, replacing the quiet
    /// line + skeleton rows: skeletons mean "loading" everywhere, so an
    /// empty state wearing them forever read as stuck, not promising). The
    /// headline speaks in the display tier (the Home cover's voice), one
    /// door opens the catalog, and the settled pile is the onboarding rain
    /// landed HERE — every tile a real offer that opens its own product
    /// page, so the pile is honest by construction. Rendered FLAT (plain
    /// stacks, no Widget/Row path) — this sits in the eager feed body,
    /// where tree depth is the launch-crash class.
    /// This room's own quiet words, or nil to use the generic invitation
    /// (prd §299). Maps the seat's SwiftUI-side status onto `RoomQuiet.Seat`,
    /// which is the only place the two vocabularies meet.
    private var quietWords: RoomQuiet.Words? {
        guard source != "All" else { return nil }
        // Through the catalog — see `activeSourceBridge`. A bare `==` resolved
        // the wallet-riding rooms to no seat at all, so `.none` won the switch
        // below and they fell back to the generic "connect an app" invitation:
        // §299's own failure, in the rooms it was written for.
        let seatName = BridgeCatalog.offer(forSource: source)?.name ?? source
        let seat = bridges.bridges.first { $0.name == seatName }
        let mapped: RoomQuiet.Seat = switch seat?.status {
        case .connected: .connected
        case .attention: .attention
        case .paused:    .paused
        case nil:        .none
        }
        return RoomQuiet.words(source: source, seat: mapped,
                               statusLine: seat?.statusLine ?? "",
                               emptyRead: TokenBridge(rawValue: source)?.emptyReadNote)
    }

    /// The empty room.
    ///
    /// A connected room says so and stops inviting you to connect it; a paused
    /// one names the state you chose; a BROKEN one says it's broken, which the
    /// generic copy hid behind a cheerful invitation (prd §299). Everything
    /// else — All, and any room with no seat — keeps the original.
    @ViewBuilder
    private var emptyState: some View {
        if let words = quietWords {
            quietState(words)
        } else {
            invitationState
        }
    }

    /// A room that is working, paused or broken — and empty. Same anatomy as
    /// the invitation below (heading, sentence, one door) so the two read as
    /// one screen in two states rather than two screens, which is the shape
    /// `CloudflareRunwayCard` settled on for the same problem.
    private func quietState(_ words: RoomQuiet.Words) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(words.headline)
                .dsText(.heading34).fontWeight(.heavy)
                .foregroundStyle(DS.textPrimary)
                .settleIn()
            Text(words.detail)
                .dsText(.body17).foregroundStyle(DS.textSecondary)
                .padding(.top, DS.Space.s2)
                .settleIn(delay: 0.05)
            if words.offersDoor {
                Button {
                    DSHaptic.selection()
                    route.present(.apps)
                } label: {
                    HStack(spacing: DS.Space.s1) {
                        Text("Open \(source)")
                            .dsText(.callout15).fontWeight(.semibold)
                        Image(systemName: "chevron.right")
                            .accessibilityHidden(true)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(DS.tint)
                    .padding(.horizontal, DS.Space.s4)
                    .frame(height: 36)
                    .background(DS.tintDim, in: Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.top, DS.Space.s4)
                .settleIn(delay: 0.1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.Space.s4)
        .padding(.top, DS.Space.s6)
    }

    private var invitationState: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Let's fill this feed.")
                .dsText(.heading34).fontWeight(.heavy)
                .foregroundStyle(DS.textPrimary)
                .settleIn()
            Text("Connect an app and things start landing on their own.")
                .dsText(.body17).foregroundStyle(DS.textSecondary)
                .padding(.top, DS.Space.s2)
                .settleIn(delay: 0.05)
            Button {
                DSHaptic.selection()
                route.present(.apps)
            } label: {
                HStack(spacing: DS.Space.s1) {
                    Text("Open the catalog")
                        .dsText(.callout15).fontWeight(.semibold)
                    Image(systemName: "chevron.right")
                        .accessibilityHidden(true)
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(DS.tint)
                .padding(.horizontal, DS.Space.s4)
                .frame(height: 36)
                .background(DS.tintDim, in: Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, DS.Space.s4)
            .settleIn(delay: 0.1)
            // The "or paste a link, share in, snap a screenshot" line is
            // DELETED (user, 2026-08-07). It was added to teach the capture
            // verbs the headline only claimed, but it teaches them to someone
            // who has nothing yet and no reason to care which door they use —
            // and it sits above the pile of real apps, which is the actual
            // answer to an empty feed. Every one of those verbs is discovered
            // in the moment it is wanted (the share sheet is the system's, the
            // composer's paste chip appears when there is something on the
            // clipboard); a screen that has to list them is padding the one
            // moment that should be shortest.
            Spacer(minLength: DS.Space.s6)
            EmptyFeedPile()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.Space.s4)
        .padding(.top, DS.Space.s6)
        // The pile rests at the FOOT of the screen (the rain lands where the
        // floor is): the row takes a fixed drop and the Spacer above hands
        // the slack to the pile. A plain minHeight, not
        // `containerRelativeFrame` — inside this List that modifier reported
        // a container shorter than the viewport and always floored (measured
        // 2026-07-16). On an oversized-type layout the Spacer collapses and
        // the row grows past the minimum instead of crowding.
        .frame(minHeight: 540, alignment: .top)
    }

    /// A filter with no matches: the filtered app's own icon, a plain line,
    /// and one way back. Never a bare "Nothing matches."
    private var filteredEmptyState: some View {
        VStack(spacing: DS.Space.s3) {
            if source != "All" {
                BridgeIcon(name: source, size: 44)
            } else if let kind = ThingKind.from(typeTag: filter.tag) {
                KindGlyph(kind: kind, size: 44)
            }
            Text(emptyLine)
                .dsText(.body17)
                .foregroundStyle(DS.textSecondary)
                .multilineTextAlignment(.center)
            Button {
                DSHaptic.selection()
                withAnimation(DS.Motion.standard) {
                    filter.source = "All"
                    filter.tag = "All"
                }
            } label: {
                Text("Show everything")
                    .dsText(.label12)
                    .foregroundStyle(DS.tint)
                    .padding(.horizontal, DS.Space.s4)
                    .frame(height: 32)
                    .background(DS.tintDim, in: Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            tryItChip
            // The empty room previews its own shape (2026-07-13) — the
            // all-feed empty state already does this with skeleton rows;
            // a shaped empty shows what ITS rows will look like: a grid
            // for Photos, rows for everything else.
            if source != "All" {
                emptyShapePreview
                    .padding(.top, DS.Space.s6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, DS.Space.s4)
        .padding(.vertical, DS.Space.s6)
    }

    /// One tap demos a source that otherwise needs a first pick to mean
    /// anything — the Wallet screen's "Peek at vitalik.eth" (prd §79),
    /// generalized to every empty room that's just a search field with
    /// nothing in it (delight pass 2026-07-21). Retires the moment anything
    /// is watched — the empty state itself stops rendering.
    @ViewBuilder private var tryItChip: some View {
        if shape == .tokens {
            tryItButton(label: "Watch ETH") {
                guard let resolved = await TokenWatch.resolve("ETH") else { return }
                TokenWatch.add(resolved, context: modelContext)
                TokenWatch.registerBridge(store: bridges, context: modelContext)
            }
        } else if source == "Stocktwits" {
            tryItButton(label: "Watch $AAPL") {
                guard let resolved = await StockWatch.resolve("AAPL") else { return }
                StockWatch.add(resolved, context: modelContext)
                StockWatch.registerBridge(store: bridges, context: modelContext)
            }
        } else if source == "RSS" {
            tryItButton(label: "Follow NASA's feed") {
                guard RSSStore.shared.add("https://www.nasa.gov/feed/") else { return }
                let added = await RSSIngest.refresh(context: modelContext)
                bridges.registerConnected(id: "rss", name: "RSS",
                    proof: (added ?? 0) > 0
                        ? String(localized: "\(added ?? 0) posts in")
                        : String(localized: "Synced just now"),
                    can: ["Reads the feeds you follow."])
            }
        }
    }

    /// One chip anatomy for every try-it — the vitalik.eth capsule's exact
    /// styling, reused instead of re-spelled per source.
    private func tryItButton(label: String, action: @escaping () async -> Void) -> some View {
        Button {
            DSHaptic.tap()
            Task { await action() }
        } label: {
            HStack(spacing: DS.Space.s1) {
                Image(systemName: "sparkles")
                    .accessibilityHidden(true)
                    .font(.system(size: 12, weight: .semibold))
                Text(label)
                    .dsText(.subhead13).fontWeight(.medium)
            }
            .foregroundStyle(DS.tint)
            .padding(.horizontal, DS.Space.s3)
            .padding(.vertical, DS.Space.s2)
            .background(DS.tint.opacity(0.12), in: Capsule(style: .continuous))
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.top, DS.Space.s2)
    }

    @ViewBuilder private var emptyShapePreview: some View {
        switch shape {
        case .photos:
            HStack(spacing: DS.Space.s3) {
                ForEach(0..<3, id: \.self) { i in
                    RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                        .fill(DS.gray100)
                        .frame(height: 90)
                        .staggerIn(index: i + 3)
                }
            }
        case .wallet:
            // A skeleton treemap mosaic — echoes the Wallet feed's real
            // holdings treemap (uneven tile sizes, not a uniform grid).
            RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous)
                .fill(DS.surfaceSheet)
                .frame(height: 160)
                .overlay {
                    HStack(spacing: DS.Space.s2) {
                        VStack(spacing: DS.Space.s2) {
                            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                                .fill(DS.gray100).frame(height: 88)
                            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                                .fill(DS.gray100)
                        }
                        VStack(spacing: DS.Space.s2) {
                            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                                .fill(DS.gray100)
                            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                                .fill(DS.gray100).frame(height: 56)
                        }
                        .frame(width: 72)
                    }
                    .padding(DS.Space.s3)
                }
                .staggerIn(index: 3)
        case .calendar:
            // A skeleton agenda band — each row a tinted strip, echoing
            // BandRow's own field-of-color shape.
            VStack(spacing: DS.Space.s2) {
                ForEach(0..<3, id: \.self) { i in
                    HStack(spacing: DS.Space.s3) {
                        Circle().fill(DS.gray100).frame(width: 24, height: 24)
                        Capsule().fill(DS.gray100).frame(height: 12)
                        Spacer(minLength: DS.Space.s2)
                        Capsule().fill(DS.gray100).frame(width: 40, height: 12)
                    }
                    .padding(.horizontal, DS.Space.s3)
                    .padding(.vertical, DS.Space.s3)
                    .background(DS.gray100.opacity(0.4),
                                in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                    .staggerIn(index: i + 3)
                }
            }
        default:
            VStack(spacing: DS.Space.s2) {
                ForEach(0..<3, id: \.self) { i in
                    GenSkeletonRow()
                        .staggerIn(index: i + 3)
                }
            }
        }
    }

    private var emptyLine: String {
        let tagLabel = ThingKind.from(typeTag: filter.tag)?.typeTagPlural ?? filter.tag
        switch (source != "All", filter.tag != "All") {
        case (true, true):   return "Nothing from \(source) under \(tagLabel) yet."
        case (true, false):  return "Nothing from \(source) yet."
        case (false, true):  return "No \(tagLabel.lowercased()) yet."
        default:             return "Nothing here yet."
        }
    }

    /// Every row opens its own thing sheet — including a wallet transaction
    /// (2026-07-24, user: "when i tap 'received' on a transaction it brings me
    /// to the wallet management screen... no reason to go there"). The old
    /// ruling (2026-07-09) sent Wallet rows to the management screen because
    /// "the generic sheet had nothing more than an explorer link to show" —
    /// long obsolete: the sheet now leads with the full transfer STAGE (the
    /// parties, the signed amount, the chain, the flag banner) and its Open
    /// disc IS that explorer link. Tapping a transaction should show the
    /// transaction, not the page for managing which wallets you watch.
    ///
    /// On iPad wide enough for two columns (2026-07-25) this fills the
    /// trailing DETAIL PANE instead of throwing a sheet over the whole
    /// screen — the row and the thing it opens stay on screen together, which
    /// is the point of the shape. `present` returns false wherever no pane
    /// exists (iPhone, an iPad mini in portrait, Slide Over), and the sheet
    /// path below is then exactly the one this app has always taken.
    private func openThing(_ thing: Thing) {
        guard !detail.present(thing) else { return }
        feedSheet = .thing(thing)
    }

    /// A day group as a native section: the day's rows share ONE sheet card
    /// (2026-07-21 — see RunPosition), rhythm-breakers stand free between
    /// runs, native scroll — no gesture fights.
    @ViewBuilder
    private func daySection(_ label: String, _ rows: [Thing],
                            nextEventID: UUID?,
                            boundary: UUID? = nil,
                            replies: [String: [Thing]] = [:],
                            // A week/month group from the folded tail rather
                            // than a day — its header weighs one step less
                            // (prd §254). Defaults false for the one caller
                            // that isn't a day at all (the kind-filtered All
                            // room, whose single header is the filter's name).
                            coarse: Bool = false) -> some View {
        // LIVE ONLY, before anything reads a stored property (build 150 crash,
        // 2026-07-25 — pull-to-refresh, symbolicated to `countLabel` inside
        // this section's own header). `rows` is a DERIVED array (the day
        // grouping) holding models by reference, and everything below touches
        // persisted properties on them: `standsAlone`/`.id` for the run
        // positions, the row bodies, and the header's `countLabel(rows)`,
        // which maps `\.kind` over every one. A refresh runs the bridge heals,
        // each of which deletes upstream-gone rows on the MAIN context — so a
        // delete lands inside the same graph update that re-evaluates this
        // section, and the first read of a tombstoned model traps in SwiftData.
        //
        // The keying rule (`ThingRowKeying`) fixed the ForEach's own identity
        // diffing; it can't help a header that reads the array directly. This
        // is the same rule's other half: guard a HELD reference with `isLive`
        // before reading through it. Filtering here covers the positions, the
        // rows, and the header at once — a row that just died drops out of the
        // day it was in, which is what the next `@Query` emission says anyway.
        let rows = rows.filter(\.isLive)
        let positions = cardRunPositions(count: rows.count,
                                         isBreaker: { standsAlone(rows[$0]) },
                                         isBoundary: { rows[$0].id == boundary })
        if !rows.isEmpty {
            Section {
                // Rows dispatch by shape (shaped feeds); the swipe stays triage —
                // reads only, writes live in the sheet (ruling), Copy sheet-only.
                ForEach(Array(keyed(rows).enumerated()), id: \.element.id) { i, item in
                    // The `rows.filter(\.isLive)` above runs when this view
                    // VALUE is made; this runs again each time the closure is
                    // re-evaluated, which is when the delete actually lands
                    // (corollary 3, build 176 — see `ThingRowKeying`).
                    if let thing = item.live {
                        if thing.id == boundary { newSinceDivider }
                        shapedListRow(thing, index: i, nextEventID: nextEventID,
                                      position: positions[i], replies: replies)
                    }
                }
            } header: {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                    Text(label)
                        .dsText(.heading22)
                        // The folded tail weighs less than today (prd §254) —
                        // see the twin in `bundledSections` for the reasoning.
                        .fontWeight(coarse ? .semibold : .bold)
                        .foregroundStyle(DS.textPrimary)
                    // In a source's own room the count speaks the source's unit —
                    // "3 events", "5 screenshots" (2026-07-13). All keeps the
                    // bare number: mixed kinds have no one unit worth naming.
                    Text(countLabel(rows)).dsText(.subhead13).foregroundStyle(DS.textTertiary)
                        .contentTransition(.numericText())
                }
                .textCase(nil)
                .padding(.leading, DS.Space.s4)
                // Days read as clusters: the gap ABOVE a day header is the
                // feed's biggest (2026-07-13), and since 2026-07-21 the day's
                // rows also share one card — the header's s6 plus the card's own
                // silhouette say "new day" without drawing a line.
                .padding(.top, DS.Space.s6)
                .padding(.bottom, DS.Space.s1)
                // The system pins whichever header currently sits at the
                // scroll position and gives IT — and only it — a material
                // backdrop for legibility over scrolling content (Mac
                // polish, 2026-07-28): the first day group reads with an
                // unwanted gray box the later ones never get, since they're
                // never the pinned one at rest. More visible under Mac
                // Catalyst than iOS; explicit clear wins over the implicit
                // material either way.
                .listRowBackground(Color.clear)
                .background(Color.clear)
            }
        }
    }

    /// The day header's count: a bare number in All, the source's own unit in
    /// a shaped feed — "3 events", "1 screenshot", "4 things" when mixed.
    /// The social room says "posts": its things are kind .chat (the ingest's
    /// container), but nobody calls a Bluesky post a chat.
    private func countLabel(_ rows: [Thing]) -> String {
        // Guarded independently of `daySection`'s own filter: the footer
        // (`caughtUpFooter`) calls this with the whole render's `visible`
        // array, which is derived the same way and carries the same hazard.
        // `\.kind` below is a persisted read — the one that trapped in 150.
        let rows = rows.filter(\.isLive)
        guard source != "All" else { return "\(rows.count)" }
        if shape == .social {
            return rows.count == 1 ? "1 post" : "\(rows.count) posts"
        }
        let kinds = Set(rows.map(\.kind))
        guard kinds.count == 1, let kind = kinds.first else {
            return rows.count == 1 ? "1 thing" : "\(rows.count) things"
        }
        let unit = rows.count == 1 ? kind.typeTag : kind.typeTagPlural
        return "\(rows.count) \(unit.lowercased())"
    }

    /// The feed closes instead of trailing off (2026-07-13): one quiet line
    /// naming what you just read to the end of. Doubles as an honest corpus
    /// count — facts only, no streaks (§10). Speaks the same unit as the day
    /// headers ("6 events", not "6 things") via the one countLabel rule.
    /// Takes the render's `visible` (the Feed-freeze rule) instead of
    /// re-deriving it.
    private func caughtUpFooter(_ rows: [Thing]) -> some View {
        // At the fetch bound this is NOT the end of the corpus, and saying
        // "that's everything" there would be the §83 fake status in the one
        // place a person is deciding whether anything older exists. The room
        // stops fetching at `allRoomFetchLimit`; the copy says which stop this
        // is. Open the source's own chip to walk past it — a per-source room
        // carries its own predicated query and no such bound.
        Text(reachedFetchCeiling
             ? "Showing your most recent \(rows.count) — open a source to go further back"
             : source == "All"
             ? "That's everything · \(rows.count == 1 ? "1 thing" : "\(rows.count) things")"
             : "That's everything from \(source) · \(countLabel(rows))")
            .dsText(.subhead13)
            .foregroundStyle(DS.textTertiary)
            .frame(maxWidth: .infinity)
            .padding(.top, DS.Space.s6)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }


    // MARK: - Windowed rows (prd §264)

    /// How many ROWS a room draws before it stops. Whole day groups only, so
    /// the real count overshoots to the end of whichever group crosses this.
    ///
    /// A room built EVERY row it held on every render, and a device profile put
    /// `feedList` at 46% of all main-thread samples with 36 hangs of up to
    /// 850ms in the first ten seconds. That cost scaled with the room, not with
    /// what anyone could see. The derivations above are unchanged and still run
    /// over the WHOLE set — the grouping, the bundling, the themes treemap and
    /// every count stay corpus-true — because the expensive thing was never the
    /// deriving (it is memoized, once per real change), it was handing a
    /// thousand rows to a `ForEach` whose content closure runs for each one.
    ///
    /// Distinct from the off-screen page trim rejected in §263: that deferred a
    /// page's rows to the body evaluation that made it ACTIVE, which moved the
    /// cost onto the moment of arrival. This never builds the rest at all until
    /// the person scrolls toward it, and then it builds a few groups.
    /// About two screenfuls. The screen holds 8-12 rows, so this is a small
    /// amount of pre-built content ahead of the viewport rather than the ten
    /// screens the first cut budgeted (user, 2026-08-01: "why not just show the
    /// last day and current day only on load" — right that it was too
    /// generous; see `windowed` for why the unit is rows and not days).
    private static let windowRowTarget = 30

    /// How many rows the All room's `@Query` will materialise, ever. See the
    /// long note in `init` for the measurement that produced it: unbounded,
    /// that query was 26.6% of the main thread on a 6,000-row corpus, because
    /// SwiftData instantiates every row as a real model object on the main
    /// actor. ~40 "Show older" taps of headroom, and constant thereafter no
    /// matter how large the corpus grows.
    static let allRoomFetchLimit = 1200

    /// True when the window has opened as far as the FETCH will go — the
    /// person has reached the bound above, not the end of their corpus.
    ///
    /// This exists so the bound can never masquerade as the end (§83). The
    /// caught-up footer is a claim about the CORPUS ("nothing older exists"),
    /// and at this edge that claim is false: there is more, we simply stopped
    /// fetching it. `windowed` reports `more: false` here for exactly the same
    /// reason it does when a room really is exhausted, so nothing downstream
    /// can tell the two apart — which is why this is asked separately.
    private var reachedFetchCeiling: Bool {
        source == "All" && filter.tag == "All"
            && windowRowBudget >= Self.allRoomFetchLimit
    }

    /// Each step opens another target's worth. Monotonic for the life of the
    /// screen: it must not collapse when a thing lands, or scrolling back would
    /// undo itself every sync.
    @State private var windowSteps = 0

    /// One more screenful per step, deliberately linear (user ruling,
    /// 2026-08-01: "most people won't be scrolling back to previous history").
    /// Geometric growth was offered and declined — it only helps the person
    /// walking a long room to its beginning, which is the rare case, and the
    /// cost of getting the common case right is what this whole change is for.
    private var windowRowBudget: Int { Self.windowRowTarget * (windowSteps + 1) }

    /// Whole groups covering the budget, plus whether any were held back.
    ///
    /// ROWS are the unit, not days, and that is the whole point: a day is not a
    /// bound on work. An import (Instagram, Snapchat, ChatGPT) lands its entire
    /// history at once and those cluster onto dates, so ONE day in that room
    /// can be thousands of rows — "draw today and yesterday" would leave the
    /// cost completely unbounded. A row budget also adapts by itself: a busy
    /// day fills the screen, a quiet week shows several days.
    ///
    /// Whole days wherever possible, because a half-drawn day would otherwise
    /// need its header to lie about what sits under it. The exception is a day
    /// that busts the budget ON ITS OWN — the import case above — which is
    /// truncated rather than allowed to unbound the room. Its header keeps
    /// stating the day's REAL total (`daySection` is handed the full day for
    /// counting), so the count stays true and "Show older" explains the gap.
    private func windowed<T>(_ groups: [(String, [T])]) -> (shown: [(String, [T])], more: Bool) {
        var shown: [(String, [T])] = []
        var rows = 0
        for group in groups {
            let remaining = windowRowBudget - rows
            if shown.isEmpty && group.1.count > windowRowBudget {
                // One day bigger than the whole budget: take a screenful of it
                // rather than the day, or this bounds nothing.
                shown.append((group.0, Array(group.1.prefix(windowRowBudget))))
                return (shown, true)
            }
            if rows > 0 && group.1.count > remaining { return (shown, true) }
            shown.append(group)
            rows += group.1.count
            if rows >= windowRowBudget { break }
        }
        return (shown, shown.count < groups.count)
    }

    /// The row that opens the next step — a TAP, deliberately, not an
    /// appearance trigger.
    ///
    /// Growing on `.onAppear` was the first cut and is a runaway: `List`
    /// realizes rows ahead of the viewport, so the row appears immediately,
    /// grows the window, re-renders, appears again. Measured — it drove
    /// `feedList` from 12% of main-thread samples to 60%, i.e. it cost far more
    /// than the windowing saved, while looking like seamless infinite scroll.
    /// A tap fires exactly once per request and cannot feed back into its own
    /// trigger.
    ///
    /// While this is on screen the room is NOT whole, so `caughtUpFooter`
    /// stands down; `memo.windowHasMore` carries that (see `feedList`).
    private var olderRow: some View {
        Button {
            DSHaptic.tap()
            withAnimation(DS.Motion.standard) { windowSteps += 1 }
        } label: {
            Text("Show older")
                .dsText(.subhead13)
                .foregroundStyle(DS.tint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Space.s4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    // MARK: - Verbs from the swipe (reads pass, writes confirm)

    private func run(_ verb: Verb, on thing: Thing) {
        if verb.isWrite {
            confirming = (verb, thing)
        } else {
            perform(verb, on: thing)
        }
    }

    private func perform(_ verb: Verb, on thing: Thing) {
        switch verb.action {
        case .openURL(let url):
            openExternal(url)
        case .addToCalendar:
            Task {
                do {
                    try await HandOff.addToCalendar(thing)
                    chrome.flash(String(localized: "Copied — paste it in Calendar"), tone: .success)
                } catch { chrome.flash(error.localizedDescription, tone: .failure) }
            }
        case .addToReminders:
            Task {
                do {
                    try await HandOff.addToReminders(thing)
                    chrome.flash(String(localized: "Copied — paste it in Reminders"), tone: .success)
                } catch { chrome.flash(error.localizedDescription, tone: .failure) }
            }
        case .copyText:
            DSPasteboard.copy(thing.content.isEmpty ? thing.title : thing.content)
            chrome.flash("Copied")
        case .markDone:
            // Rung-1 local mark only — app-owned things (a note turned to-do,
            // demo seeds). A real reminder's done-state is READ-ONLY, mirrored
            // from the Reminders app (ruling 2026-07-25), so it never offers
            // this verb; nothing here writes back to any external record.
            thing.mark = .done
            modelContext.saveHonestly()
        case .translate:
            translateText = thing.postText ?? thing.content
            showTranslate = true
        case .viewImage:
            // The full-screen viewer lives in the thing sheet, which is where
            // this row's tap already goes — the feed's own menu never offers
            // this verb (it picks out the open and translate verbs by hand), so
            // this arm exists for completeness, not as a second door.
            openThing(thing)
        case .approve:
            // An MCP client asked to save a thing (PRD §34) — the approval
            // carries the payload; the tap is what commits it. Consent → write.
            if thing.sourceRef == MCPTools.saveMarker,
               let real = Capture.thing(from: thing.content, source: thing.source) {
                modelContext.insert(real)
                thing.mark = .done
                modelContext.saveHonestly()
                SpotlightIndex.index([real])
                chrome.flash("Saved", tone: .success)
            } else {
                withAnimation(DS.Motion.standard) {
                    thing.mark = .done
                    modelContext.saveHonestly()
                }
                // Honesty: the answer is recorded on the thing. Nothing is
                // sent anywhere — no agent transport exists yet (2026-07-10;
                // the old copy claimed a gateway was told).
                chrome.flash("Approved", tone: .success)
            }
        case .deny:
            withAnimation(DS.Motion.standard) {
                thing.mark = .done
                modelContext.saveHonestly()
            }
            chrome.flash("Denied")
        }
    }


    /// Loads the real per-wallet holdings for the Wallet chip's own shape —
    /// the ONLY place holdings show in Feed (amendment 2026-07-10: the
    /// module already lives on Home; leading All with it doubled that).
    /// Everything watched shows here regardless of pin — this is the
    /// wallet's native view. Composing is synchronous elsewhere in this
    /// screen; the wallet fetch isn't, so it lands in the background and
    /// repaints.
    /// Pull-to-refresh (2026-07-12): re-polls every connected bridge for fresh
    /// things, then RECOMPOSES the feed the way a source switch does — the
    /// shaped rows re-cascade (shapeWave replays their entrance) and the
    /// synthesis block re-streams. The Feed's take on Home's pull re-compose:
    /// records paint, so the delight is the cascade, not a typewriter — which
    /// is why this returns as soon as the work is handed off (2026-07-28): the
    /// cascade IS the beat, and holding the refresh control's spinner open for
    /// an extra 450ms afterwards only made the gesture feel slow.
    /// The one pull, however it's triggered — a real gesture (`.refreshable`)
    /// or Mac's ⌘R (`chrome.refreshRequest`, see the `.onChange` above). Kept
    /// as one function so the two triggers can never drift into dealing the
    /// hue/pulse/sync sequence differently.
    private func performPull() async {
        // A pull inside one source's own feed rains in ITS hue instead
        // of the app's default berry blue — "All" keeps the default
        // (delight pass 2026-07-21). Set once; both this bump and
        // refreshFeed()'s own read the same stored hue.
        // Scoped to one wallet, the rain falls in THAT wallet's colour
        // (prd §171, 2026-07-22) — the crown already retints on a scope
        // switch (§159), so the refresh that follows should agree. Every
        // other room keeps the source's hue; "All" keeps the default berry.
        chrome.refreshHue = source == "Wallet"
            ? (selectedWallet.map(WalletFace.tint) ?? DS.washHue(for: source))
            : (source == "All" ? nil : DS.washHue(for: source))
        // BEFORE the pulse, not after (2026-08-05). The pulse is what re-fires
        // `PredictionBrowseSection`'s `.task(id:)`, i.e. it STARTS the room's
        // reload — so clearing the book cache from inside `refreshFeed()`
        // below landed after that reload had already begun its discovery walk,
        // and `KalshiWatch.Cache` correctly refuses to commit a walk a pull
        // has superseded. On a cold cache the reload therefore came back with
        // nothing and the room rendered "Couldn't reach the market book just
        // now." — on a pull that reached it fine. Worse, it was
        // self-reinforcing: the error's obvious remedy is another pull, and
        // another pull reproduced it exactly. Invalidating first makes the
        // reload a genuinely fresh read with nothing to race.
        if LiveRoomSources.has(source) { await KalshiWatch.invalidateCache() }
        chrome.refreshPulse += 1   // spins the avatar door, deals the berry rain
        await refreshFeed()
    }

    private func refreshFeed() async {
        // ONE pull, ONE shower (2026-07-28). The `.refreshable` closure above
        // already bumped `refreshPulse`; bumping it again here dealt a SECOND
        // shower a few milliseconds behind the first, over the same drop
        // identities — so the first shower's drops were re-dealt mid-fall and
        // the pour read as a stutter every time. The pulse belongs to the
        // gesture, and the gesture happens once.
        shapeWave += 1
        // The haptic lands with the gesture, not after it (user, 2026-07-28:
        // "need pull to refresh snappy"). It sat behind a deliberate 450ms
        // beat — "a short beat lets the pull read before it lands with a soft
        // thud" (2026-07-12) — which also held the refresh control's spinner
        // open for that long after the work was already handed off. The
        // cascade below IS the beat; the thud shouldn't wait for it.
        DSHaptic.success()
        // A deliberate pull re-fetches live — clear the holdings cache so the
        // Wallet feed's treemap isn't served a TTL-cached read (same contract as
        // Home's pull; the cache is for the automatic fan-out, not the gesture).
        await WalletIngest.invalidateHoldingsCache()
        // The prediction rooms' own book cache is cleared by `performPull`
        // BEFORE it bumps the pulse (see the note there) — it cannot live
        // here, because by the time this runs the pulse has already started
        // the reload this was meant to freshen.
        BridgeRefresh.refreshAllConnected(context: modelContext, store: bridges, force: true)
        streamBlock()
    }

    /// Reads the Wallet feed's live state for the current scope. Off the Wallet
    /// feed it clears rather than holding a stale read — the tiles are gone
    /// from the screen anyway, and stale state would flash on return.
    private func loadWalletLive() {
        guard source == "Wallet" else {
            if walletLive != WalletLiveState() { walletLive = WalletLiveState() }
            return
        }
        let scope = selectedWallet
        Task { @MainActor in
            let state = await WalletWatch.liveState(scopeTo: scope, context: modelContext)
            // The scope may have moved while the reads were in flight — a late
            // answer for a wallet we've since left must not paint.
            guard scope == selectedWallet else { return }
            // Animated on purpose (2026-07-20, wallet streaming fix): this
            // lands SECONDS after the balance tile (live chain reads vs a
            // local sample file), and an unanimated set hard-popped the
            // warnings/DeFi tiles into place — "looks unintentional". The
            // animation carries the LAYOUT (rows sliding to make room);
            // each tile's own RowEntrance carries its reveal.
            withAnimation(DS.Motion.standard) { walletLive = state }
        }
    }

    private func streamBlock() {
        guard source == "Wallet" else {
            if !blockStream.els.isEmpty { blockStream.paint([]) }
            if portfolio != nil { portfolio = nil }
            return
        }
        // The treemap paints as soon as holdings land, and the portfolio behind
        // it lands on the same beat — one read, both answers (prd §155), so the
        // balance number, the map, and the concentration line can never be
        // three different moments. Scoped to the selected wallet when the feed
        // is (prd §128) — the doc generator filters its groups to that address;
        // nil paints the combined map.
        let scope = selectedWallet
        Task { @MainActor in
            let read = await WalletIngest.portfolioRead(scopeTo: scope)
            // The scope may have moved while the read was in flight — a late
            // answer for a wallet we've since left must not paint (the same
            // guard `loadWalletLive` keeps).
            guard scope == selectedWallet else { return }
            if let read {
                // Same animated landing as `loadWalletLive` — the treemap is
                // the tallest late-arriving block, so ITS unanimated insert
                // was the most jarring of the pops.
                withAnimation(DS.Motion.standard) {
                    blockStream.paint(read.doc)
                    portfolio = read.portfolio
                }
            } else if !blockStream.els.isEmpty || portfolio != nil {
                withAnimation(DS.Motion.standard) {
                    blockStream.paint([])
                    portfolio = nil
                }
            }
        }
    }

    /// One calendar for the per-thing day grouping — `Calendar.current` copies
    /// the user's calendar on every access, and `dayLabel` runs once per thing
    /// inside `dayGroups`/`agendaSplit`, which the feed re-derives per paint.
    private static let groupingCalendar = Calendar.current

    private func dayLabel(_ date: Date) -> String {
        if Self.groupingCalendar.isDateInToday(date) { return String(localized: "Today") }
        if Self.groupingCalendar.isDateInYesterday(date) { return String(localized: "Yesterday") }
        // Only the agenda ever labels a day ahead (every other feed drops
        // future-dated rows in `dayGroups`), and there "Tomorrow" is how the
        // next day is actually named — a dated weekday header for it read as
        // history sitting at the top of the list.
        if Self.groupingCalendar.isDateInTomorrow(date) { return String(localized: "Tomorrow") }
        return date.formatted(.dateTime.weekday(.wide).month().day())
    }
}


/// The compact Feed treemap — 5 cells, areas "a a b c / a a d e", 140pt tall,



/// Rows arrive the way their shape moves (ruling 2026-07-07): a per-shape
/// offset/scale revealed with a small stagger, replayed when the chip
/// changes. One animation per moment — this IS the shape's moment.
struct RowEntrance: ViewModifier {
    struct Style {
        var dx: CGFloat
        var dy: CGFloat
        var scale: CGFloat
        var step: Double
    }

    let index: Int
    let wave: Int
    let style: Style
    @State private var shown = false
    /// Added 2026-08-04 (prd §299). This is the entrance EVERY feed row in the
    /// app wears, and it ignored Reduce Motion from the day it shipped —
    /// exactly the gap `SettleIn` had, found by the same audit on the same day.
    /// A person who has asked the system for less motion was getting a fully
    /// staggered offset-and-scale cascade on every scroll into a new room.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(x: shown ? 0 : style.dx, y: shown ? 0 : style.dy)
            .scaleEffect(shown ? 1 : style.scale)
            .onAppear { reveal() }
            .onChange(of: wave) {
                shown = false
                reveal()
            }
    }

    private func reveal() {
        guard !reduceMotion else { shown = true; return }
        withAnimation(DS.Motion.standard.delay(Double(min(index, 12)) * style.step)) {
            shown = true
        }
    }
}

// MARK: - Empty-feed pile (the rain come to rest)

/// The settled pile of app tiles at the foot of the empty feed — the
/// onboarding rain's third act (HowItWorksSheet rains them past, its step-1
/// strip shows them settled; here they rest where things will land). On
/// first appearance the tiles fall in and settle — gravity is an ease-IN,
/// the house rule — then the caption fades up. Every tile is a door to that
/// offer's product page in the catalog (no dead controls), routed through
/// HomeRoute.openOffer so the push survives the .apps hop.
private struct EmptyFeedPile: View {
    /// Hand-curated subset of the catalog — every name MUST resolve to a
    /// real BridgeCatalog offer (scripts/catalog-sync.sh checks this array
    /// by name, like the other decorative marquees). First six are the back
    /// row; the last six draw over them as the front row. Wallet sits LAST
    /// in the front row (2026-07-29, user: "wallet should definitely be one
    /// of them") — a flagship feature belongs fully unobstructed, not in the
    /// back row where the front row's -10pt overlap clips its bottom edge.
    /// Swapped places with YouTube, which moved back.
    static let pileApps = ["Notion", "Strava", "ChatGPT", "Photos",
                           "YouTube", "Reddit",
                           "Gmail", "GitHub", "Farcaster", "Bluesky",
                           "Claude", "Wallet"]

    /// Deterministic per-tile jitter — no randomness in a view body; the
    /// same pile settles identically every launch (and the screen sweep
    /// sees one design).
    private static let tilt:  [Double]  = [-5, 3, -2, 6, -4, 2,
                                           -6, 4, -3, 5, -2, 3]
    private static let restY: [CGFloat] = [3, -2, 4, 0, 2, -1,
                                           3, 1, -2, 2, 0, 3]

    /// How far above their rest the tiles wait — past the top of the screen
    /// from the pile's mid-page seat, so the fall crosses the headline the
    /// way the onboarding rain crosses the steps (no clip window: a clipped
    /// fall showed only its last inches, and the window's headroom read as
    /// a dead gap under the caption).
    private static let fallFrom: CGFloat = 700

    /// False = the tiles wait above the screen · true = they have landed.
    @State private var fell = false
    /// prd 43h: Reduce Motion is law — under it the pile is simply there,
    /// settled, no 700pt fall (nil animation makes the flip instant).
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // This window's stack (per-window since `SceneState`).
    @Environment(HomeRoute.self) private var route

    var body: some View {
        VStack(spacing: DS.Space.s3) {
            // "Tap any app to add it" alone read as "this pile of 12 is what
            // you get" (user, 2026-07-29) — the real catalog door sits a
            // whole screen-height above this settled pile, easy to miss once
            // your eye has landed on the tiles. Named again, right here.
            Text("Tap any app to add it")
                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                .opacity(fell ? 1 : 0)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.3).delay(1.5),
                           value: fell)
            // Two rows nestled brick-wise: the back row smaller and shifted
            // half a pitch — depth and irregularity, a pile not a grid.
            VStack(spacing: -10) {
                row(0..<6, size: 44).offset(x: 24)
                row(6..<12, size: 52)
            }
        }
        .onAppear {
            fell = true
            #if DEBUG
            // `-pileTap "<Offer name>"` — fire a tile's tap after the fall,
            // the headless check of the tile → product-page arc.
            if let name = UserDefaults.standard.string(forKey: "pileTap") {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1.5))
                    NSLog("pileTap: \(name)")
                    route.openOffer = name
                    route.present(.apps)
                }
            }
            #endif
        }
    }

    private func row(_ range: Range<Int>, size: CGFloat) -> some View {
        HStack(spacing: DS.Space.s2) {
            ForEach(range, id: \.self) { i in
                tile(Self.pileApps[i], index: i, size: size)
            }
        }
    }

    private func tile(_ name: String, index i: Int, size: CGFloat) -> some View {
        Button {
            DSHaptic.selection()
            route.openOffer = name
            route.present(.apps)
        } label: {
            BridgeIcon(name: name, size: size)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(name))
        .rotationEffect(.degrees(fell ? Self.tilt[i] : Self.tilt[i] * 0.4))
        .offset(y: fell ? Self.restY[i] : -Self.fallFrom)
        .animation(reduceMotion ? nil
                                : .easeIn(duration: 0.55).delay(0.35 + Double(i) * 0.05),
                   value: fell)
    }
}
