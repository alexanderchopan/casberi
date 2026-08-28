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
/// opening line, posts read as author-led cards with media at width,
/// Bookmarks reads as a reading list; Music and Tokens carry a lede block; the
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
            // `rowBudget` MUST be here (PERF 2026-08-21). It is the swipe's
            // transient fetch bound, and it changes by being CLEARED — so if
            // this comparison could not see it, the room would keep its
            // 150-row query for the life of the mount and "Show older" would
            // stop at the bound with nothing on screen able to say why.
            && a.rowBudget == b.rowBudget
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
    /// A TRANSIENT bound on the room's own query, for the length of a swipe
    /// (PERF 2026-08-21, prd §434 ruling 2) — nil at rest, which is every state
    /// but that one.
    ///
    /// THE COST IT REMOVES. §265 made a room change a remount, so the incoming
    /// room's `@Query` materialises from zero on every swipe — and a source
    /// room's query is deliberately UNBOUNDED (see the `else` branch of `init`
    /// and its 2026-08-14 note: the room heads must see the full span, so a
    /// permanent `fetchLimit` was written there and taken back out). A bulk
    /// import puts thousands of rows under one source, so that materialisation
    /// — the 2026-08-06 profile's dominant main-thread cost, `swift_conformsTo`
    /// / `Hasher.combine` / retain-release, SwiftData making models — lands in
    /// the frames the slide animation is trying to draw. It grows with every
    /// import, which is why this arrived as "the app is STARTING to lag".
    ///
    /// WHY IT IS NOT THE 2026-08-14 RULING REVERSED. That ruling refuses a
    /// PERMANENT bound because a room head computed over a truncated slice is a
    /// claim about the whole room that isn't true — "your loudest year" over
    /// the newest 150 posts. Nothing here is computed over the slice: the head
    /// task declines outright while this is set (see `.task(id: headKey)`), so
    /// the room draws no head for a few hundred milliseconds and then draws the
    /// real one, over everything. Deferred, never truncated.
    ///
    /// WHAT IT BOUNDS is only what RENDERS, and the room windows at
    /// `windowRowTarget` (30) rows anyway — so at 150 the first paint is
    /// pixel-identical to the unbounded one, with four more windows of headroom
    /// than a person can open inside the transition.
    let rowBudget: Int?

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
    /// Read by `isQuiet` (prd §378): under increased contrast the feed's rows
    /// never recede — that setting exists to refuse exactly this.
    @Environment(\.colorSchemeContrast) private var contrast
    /// For the Today header's day line (prd §385) — `DayBrief.Whisper
    /// .detailText` paints the wallet move in its direction's accent, and
    /// the accent is scheme-keyed (§83's flat-move rule lives in there too).
    @Environment(\.colorScheme) private var colorScheme
    // This window's stack and detail pane (per-window since `SceneState`).
    @Environment(HomeRoute.self) private var route
    @Environment(PadDetailSelection.self) private var detail

    init(source: String, isActive: Bool, nearActive: Bool = true, rowBudget: Int? = nil) {
        self.source = source
        self.rowBudget = rowBudget
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
            d.propertiesToFetch = Self.lightColumns
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
            d.fetchLimit = min(Self.allRoomFetchLimit, rowBudget ?? .max)
            _things = Query(d)
        } else if Pinboard.isPinnedRoom(source) {
            // The pinned room is the one room that is not a source, so it is
            // the one room whose rows are not selected by `source` and not
            // sorted by `capturedAt`.
            //
            // The sort is the point: every other room orders by when the thing
            // HAPPENED, and this one orders by when YOU acted. A pin you made
            // this morning on a two-year-old screenshot belongs at the top —
            // that is what makes this a list you built rather than another
            // slice of the same river. See `Thing.pinnedAt`.
            //
            // Unbounded deliberately, unlike the All room above: this list is
            // as long as you made it by hand, so there is no corpus-scale
            // growth to bound and a ceiling here could hide a row you pinned
            // on purpose — the one place in the app where that would be
            // unambiguously wrong. `rowBudget` is ignored here for the same
            // reason: there is no corpus-scale materialisation to defer.
            _things = Query(filter: #Predicate<Thing> { $0.pinnedAt != nil },
                            sort: \Thing.pinnedAt, order: .reverse)
        } else {
            // A SOURCE room, bounded and light-columned the same way (2026-08-14).
            //
            // This branch had neither, which made it strictly the worse half of
            // the 2026-08-06 measurement above: the All room was fixed and the
            // rooms most able to hurt were left alone. A source room is the one
            // place a single query can be enormous — a bulk import lands
            // thousands of rows under ONE source in one afternoon (§307 raised
            // the X caps to 10,000 posts + 5,000 likes, and §309 did the same
            // for Instagram, TikTok and Snapchat) — so opening that room
            // materialised every row as a real model object on the main actor,
            // WITH its heavy inline text (`content`/`enrichedText`/`postText`),
            // which the All room had stopped doing months earlier.
            //
            // `windowed` bounds what RENDERS and never bounded what is FETCHED,
            // so the cost landed before a single row was drawn — the reason
            // this reads as "the room takes a moment to open" rather than as a
            // scrolling problem, and the reason it grew with the imports.
            //
            // COLUMNS ONLY — deliberately NOT `fetchLimit` (2026-08-14).
            //
            // A row bound was written here and then taken back out, because a
            // source room's derivations are not the All room's. `sourceHead`
            // composes from `visible`, so `XRoomSource.compose(things: visible)`
            // would chart the newest 1,200 posts and present them as the whole
            // archive — and §375 built that card specifically to draw the FULL
            // span with silent years at zero, on the grounds that the gap is
            // the reading. "Your loudest year" computed over a truncated slice
            // is the §83 fake status, in the room whose entire promise is that
            // it holds your history. Same exposure for the topic treemap's
            // "N of M" subtitle and every leaderboard.
            //
            // The 2026-08-06 All-room bound came with a user ruling that its
            // derivations may describe the recent window rather than all-time.
            // No such ruling covers a source room, so the bound is a question
            // to ask, not a default to assume — and the columns alone are the
            // half that needs no ruling, since it changes what each row COSTS
            // and never what any derivation SEES.
            //
            // A TRANSIENT bound is a different question from the permanent one
            // refused above, and this is where it lands (PERF 2026-08-21). See
            // `rowBudget`: it is set only for the length of a swipe, and the
            // head chain declines to compute while it is set — so nothing here
            // ever describes a truncated room, which is the entire objection
            // the paragraph above raises. Deferred, never truncated.
            var d = FetchDescriptor<Thing>(predicate: #Predicate<Thing> { $0.source == source },
                                           sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
            d.propertiesToFetch = Self.lightColumns
            if let rowBudget { d.fetchLimit = rowBudget }
            _things = Query(d)
        }
    }

    /// The columns a room's derivations actually read.
    ///
    /// Shared by the All room and every source room since 2026-08-14 — one
    /// list, because two copies drift and the symptom of drift here is a
    /// per-row fault storm that looks like a slow room rather than like a
    /// missing column. The heavy inline text (`content`/`enrichedText`/
    /// `postText`) is deliberately absent: the derivations that run per save
    /// (bundling, day-grouping, the themes treemap, the room heads) read only
    /// light columns, and the few visible rows that DO show prose fault it on
    /// appearance — a cheap local read, once, not per re-fetch. The
    /// `.externalStorage` columns (audio/image/embedding) are already lazy.
    private static let lightColumns: [PartialKeyPath<Thing>] = [
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
        // `FeedInsight.leaderboard` reads this for EVERY row of a Snapchat
        // room ("Who you snap with"), and Snapchat is a bulk-import room, so
        // omitting one `Int?` would trade a cheap column for thousands of
        // faults — the §260 mistake above in a different coat. Added
        // 2026-08-14 with the source-room columns.
        \.messageCount,
    ]

    // KNOWN AND DELIBERATE: `content` stays OUT, and it is the one omission
    // that costs something rather than saving it. `FeedInsight` reads it per
    // row for three leaderboards — Steam hours, the `r/` subreddit, and the
    // host a link came from — so those rooms now fault once per row where the
    // old unpredicated fetch had it loaded. It is left out because `content`
    // is the heavy column for the rooms this change is FOR: a note's whole
    // body, a chat's transcript, a screenshot's OCR. The three rooms that pay
    // are feed bridges holding tens to hundreds of rows; the rooms that gain
    // are bulk imports holding thousands.
    //
    // UNMEASURED, and stated as such: the 26.6%-of-main-thread figure behind
    // the All room's own columns came from `scripts/main-thread-profile.sh` on
    // a 6,000-row corpus, and no equivalent profile has been run for a source
    // room. If a Reddit or Steam room ever reads as slow to open, this comment
    // is the first place to look and `content` is the first thing to try.

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
        /// One Hegotá movement, opened for its FRAME BREAKDOWN (prd §500).
        ///
        /// Routed here for `market`'s two reasons at once: the seat lands no
        /// `Thing` so it cannot ride `.thing`, and its card lives inside this
        /// List's rows — a `.sheet` there resolves to the same presenting
        /// controller as this one and half-opens before closing again.
        /// Carries the OWNING address beside the move: in the All scope
        /// nothing else can say which of your addresses a transaction was.
        case hegotaMove(HegotaMove, String)
        /// One FRAME of a frame transaction — the chain's defining object, and
        /// until §503 the one thing in this room that could not be opened.
        /// Carries the whole move and an index rather than the frame alone, so
        /// the sheet can draw the step in its sequence; a step out of its order
        /// is a step without its meaning.
        case hegotaFrame(HegotaMove, Int)
        /// One watched Hegotá address, opened from the Accounts list — routed
        /// here for `hegotaMove`'s two reasons: no `Thing` to ride, and a card
        /// inside this List cannot present its own sheet.
        case hegotaAccount(HegotaAccount)
        /// One UTXO, the spend that created it, and which of that spend's
        /// outputs are still unspent.
        case hegotaCoin(HegotaCoin, [HegotaCoin], Set<UInt64>)
        /// The NFT picker (prd §387). Routed here rather than presented by the
        /// shelf card, which lives inside this List's rows — a `.sheet` on a row
        /// resolves to the same presenting controller as this one and the picker
        /// would rise part way and close again (ruling 2026-07-28). Carries only
        /// value types, so no `Thing` and no liveness question.
        case nftPicks(address: String, label: String)
        /// Your years with one person, opened from the room's own board
        /// (2026-08-18, prd §396). Routed here for the standing reason every
        /// case above it is: the board lives inside this List's rows, and a
        /// `.sheet` on a row resolves to the same presenting controller as
        /// this one — the half-open-then-close bug (ruling 2026-07-28).
        /// Carries a handle and a source, so no `Thing` and no liveness
        /// question.
        case person(source: String, handle: String)
        /// The vibenet key tray (2026-08-25, prd §468) — which keys are in
        /// which permission category, opened from the keys card. Routed here
        /// for the standing reason every case above it is: the card lives
        /// inside this List's rows, and a `.sheet` on a row resolves to the
        /// same presenting controller as this one — the half-open-then-close
        /// bug (ruling 2026-07-28).
        ///
        /// Carries the ACCOUNT ITEMS by value rather than reading the room at
        /// present time, the `deposits`/`locks` ruling: a composed read can
        /// land under an open tray, and a tray that re-read mid-presentation
        /// would renumber itself while being looked at. Value types
        /// throughout, so no `Thing` and no liveness question.
        case vibenetKeys([VibenetAccountItem], newKeyIDs: Set<String>)
        /// One key's own sheet (prd §478) — the scoped vibenet account's key
        /// rows present rather than expand in place. Actor + the account it
        /// acts for + the room-wide shared-key facts, all value types
        /// captured at tap time, the `vibenetKeys` reasoning exactly.
        case vibenetKey(VibenetActor, VibenetAccountItem, [VibenetSharedKey])

        var id: String {
            switch self {
            case .thing(let t): "thing:\(t.id.uuidString)"
            case .token(let r): "token:\(r.id)"
            case .allocation: "allocation"
            case .worthALook: "worthALook"
            case .deposits: "deposits"
            case .locks: "locks"
            case .market(let p): "market:\(p.id)"
            case .hegotaMove(let m, _): "hegotaMove:\(m.id)"
            case .hegotaFrame(let m, let i): "hegotaFrame:\(m.id)#\(i)"
            case .hegotaAccount(let a): "hegotaAccount:\(a.address)"
            case .hegotaCoin(let c, _, _): "hegotaCoin:\(c.index)"
            case .nftPicks(let address, _): "nftPicks:\(address)"
            case .person(let source, let handle): "person:\(source):\(handle)"
            case .vibenetKeys: "vibenetKeys"
            case .vibenetKey(let actor, let item, _):
                "vibenetKey:\(VibenetKeySeenDiff.keyID(address: item.address, actorId: actor.actorId))"
            }
        }
    }
    @State private var feedSheet: FeedSheetRoute?

    /// Scope the vibenet room to one account — the Accounts card's row tap
    /// and the linked spine's node tap (prd §476), the same write
    /// `VibenetScopeRail` makes.
    ///
    /// A stored closure rather than an inline one at the call site, for the
    /// reason `roomHead`'s own note records: `listBody`'s List is one
    /// expression and closure literals in it have already tipped the
    /// type-checker's budget once.
    private var vibenetScoper: (String) -> Void {
        { address in
            // EMPTY MEANS ALL (prd §482 amendment). The folded chip strip
            // signals "unscoped" by passing "", because its callback is a
            // plain `(String) -> Void` shared with the rail it replaced —
            // mapping it to nil HERE rather than widening the signature keeps
            // every other caller unchanged, and an empty string reaching
            // `vibenetScope` would scope the room to an account that cannot
            // exist and quietly empty it.
            withAnimation(DS.Motion.standard) {
                chrome.vibenetScope = address.isEmpty ? nil : address
            }
        }
    }


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

    /// One publisher (or one writer), when the reading room has been narrowed
    /// to them from its own board (2026-08-23, prd §455).
    ///
    /// `@State`, so it dies with the room — `MainSurface` gives its single
    /// `FeedScreen` an `.id(filter.source)`, and that is the RIGHT lifetime
    /// here for the reason `x402Lane` has it: this is how you are looking at
    /// one room right now, not a setting you configured. It is deliberately
    /// NOT the shell-held shape §356 gave the wallet scope, because that scope
    /// spans a whole category of rooms and a publisher exists in exactly one.
    ///
    /// Carries the FIELD as well as the label. The board decides at runtime
    /// which of the two it ranked (see `FeedInsight.Leaderboard.Scope`), so
    /// the tap records what was on screen when it happened rather than letting
    /// the filter guess later.
    struct ReadingScope: Equatable {
        let label: String
        let scope: FeedInsight.Leaderboard.Scope
        /// For the head's memo key, which is a string.
        var key: String { "\(scope.rawValue):\(label)" }
    }
    @State private var readingScope: ReadingScope?

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
    /// The wallet this room is scoped to (prd §128, widened by §356) — nil is
    /// "All". Scopes the balance lede, holdings treemap, NFT strip and the
    /// rows to one watched wallet.
    ///
    /// **A window onto `ShellChrome.walletScope`, not `@State`, and that is
    /// the whole of §356.** It used to be `@State` here, which made it a
    /// property of ONE room: `MainSurface` gives its single `FeedScreen` an
    /// `.id(filter.source)`, so moving to Peer destroys this screen and every
    /// bit of its state — which is why the scope silently evaporated on a room
    /// change and why no wallet room but the balance room could be narrowed at
    /// all. Held on the shell, one scope now spans the whole category.
    private var selectedWallet: String? {
        get { chrome.walletScope }
        nonmutating set { chrome.walletScope = newValue }
    }
    /// The Wallet feed's live reads (2026-07-20) — Aave positions and the
    /// warnings rolled up from them plus Safe/poisoning/delegation. Never a
    /// landed thing: re-read each time this feed comes forward or its scope
    /// changes, exactly as the manage screen used to hold it.
    @State private var walletLive = WalletLiveState()
    /// Whether the scoped wallet holds any NFT collection at all (prd §387) —
    /// what decides between the shelf's invitation line and nothing. Owned by
    /// the room, filled by `loadWalletLive`; see there for why not by the card.
    @State private var nftHasCollections = false
    /// A card the risk strip asked to be walked to (prd §417), consumed and
    /// cleared by `listCore`.
    ///
    /// Routed through state rather than by threading the `ScrollViewProxy` down
    /// into `walletRiskSection`: the proxy lives at `feedList` and the strip is
    /// five call layers below it, so passing it would mean a signature change
    /// on `shapedSections` and every room's builder — for one tap in one room.
    @State private var cardScrollTarget: String?
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
        /// The cover (prd §389c) — picked from `days` and lifted out of
        /// `groups`, so it is stored as an id and resolved against the first
        /// day at render (never held as a `Thing` across renders: this class
        /// outlives a heal's delete, and the id is the same shape `FeedRow`
        /// stores for the same reason).
        var lede: UUID?
        var imageOnly: Set<UUID> = []
        var wideArt: Set<UUID> = []
        var coarse: Set<String> = []
        /// A coarse group's own subject, by label (prd §379).
        var subjects: [String: String] = [:]
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
    /// One scroll-past per mount (prd §385, 2026-08-14): on appear the list
    /// settles just below the Themes card, so the map lives ABOVE THE FOLD —
    /// revealed by scrolling up past the top, the way Mail hides search.
    /// Every source switch re-mounts this screen (`.id(filter.source)` in
    /// `MainSurface`), which resets this and re-hides the map — the stronger
    /// form of the digest-collapse behaviour it replaced (the one thing the
    /// user kept from that design: "i like that it collapses when you
    /// navigate away and come back").
    @State private var foldSettled = false
    /// The zero-height row just below the Themes card that `foldSettled`'s
    /// scroll targets. `scrollTo` on an id that never rendered is a no-op,
    /// which is the whole guard: non-All rooms, a filtered All, and an empty
    /// corpus render no anchor and so never scroll.
    private static let themesFoldAnchor = "feed.themesFold"
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

    /// Is this room's content divided by AUTHOR — the one question the social
    /// face rail asks (prd §362), answered by the room-shaping taxonomy that
    /// already owns it rather than by a second list of source names kept in step
    /// with `Shape` by hand. Internal because `SocialScopeRail` lives in the
    /// shell and must decide whether to draw before any feed exists; `Shape`
    /// itself stays private, since nothing outside this file has business
    /// knowing the other twenty-two cases.
    static func isSocialRoom(_ source: String) -> Bool {
        // ASKED OF `SocialRoom`, NOT OF `Shape` (2026-08-26, prd §489). The
        // rail and the accounts behind it must answer for the same set or the
        // rail draws faces the room cannot filter to — which is exactly what a
        // `Shape`-only answer would have produced the moment Nostr joined
        // `.social` while `SocialRoomSource.accounts` still had two cases.
        // One registry, two readers.
        SocialRoom.hasRoster(source)
    }

    /// The shape a source takes when its chip is in force.
    private enum Shape {
        case all, photos, wallet, ledger, calendar, gmail, chat, social, reminders, bookmarks, notes, you, music, media, tokens, bitrefill, oneclaw, snapchat, files, instagram, tiktok, x, x402, appStoreConnect, cursor, cardPointers, walletbeat, l2beat, telegram, vibenet, plain

        /// Rooms whose lead is a GRID of pictures, and which therefore earn the
        /// wide content cap on a regular-width window (2026-08-17).
        ///
        /// Membership is "does this room draw a picture wall", not "does this
        /// room contain images" — `social` and `x` hold plenty of photos but
        /// lead with post cards whose words are the content, and widening those
        /// would stretch a paragraph past the reading measure to no benefit.
        /// The mixed rooms (Files, Snapchat, Instagram) are in because the grid
        /// is what sets their width; `x` stays out because its picture half is
        /// a minority of a room that is overwhelmingly writing.
        var widensForPictures: Bool {
            switch self {
            case .photos, .media, .files, .snapchat, .instagram: return true
            default: return false
            }
        }
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
            // The WALLET-RIDING money rooms (prd §485, 2026-08-26). Both had NO case
            // here, so they fell to `.plain` and drew the band's generic
            // sentence row — in rooms whose every row is a transfer, with the
            // amount and the direction already stamped on it
            // (`transferAmount`/`transferDirection`, since prd §369 and §397)
            // and `BandRow.moneyColumn` already built to read exactly that
            // pair. So the figure sat inside an 80-character sentence, and a
            // column of moves scanned as a column of prose where the wallet
            // room beside them has scanned as a ledger since §158.
            //
            // `.ledger` rather than `.wallet`: that shape carries the wallet
            // room's whole apparatus — its section switcher, its crown, its
            // tiles, its warnings — and these rooms have a head of their own.
            // What they share with it is one row anatomy and one flag.
            //
            // A non-transfer row in these rooms is unaffected by construction:
            // Privacy Pools' proof-required ALERT carries no
            // `transferDirection`, so `moneyAmount` returns nil and it keeps
            // its full sentence. The flag is opt-in per ROW, not per room.
            //
            // GNOSIS PAY IS DELIBERATELY NOT HERE, and the reason is data, not
            // taste: its title states the spend in FIAT ("Spent EUR 42.80 with
            // Gnosis Pay") while its `transferAmount` is the TOKEN amount
            // ("42.80 EURe") — two spellings of one figure — so `titleText`'s
            // strip can never match and the row would print the amount twice,
            // in two units. Its honest column is the fiat one, which means
            // teaching the money column to prefer `priceValue`/`priceCurrency`
            // for a real ISO currency; that changes what §374's mask reads
            // (the trailing SYMBOL of `transferAmount`) and belongs in its own
            // pass rather than riding this one.
            //
            // The LITERALS, like `case "Cursor"` and `case "Instagram"` below
            // — `demo-selftest.py`'s check F reads this switch to prove every
            // shape has a seeded source, and it resolves only three
            // indirections by name.
            case "Railgun", "Privacy Pools": self = .ledger
            case "Calendar", "Cal.com", "Calendly": self = .calendar
            case "Gmail", "iCloud Mail": self = .gmail
            case "ChatGPT", "Claude", "Gemini": self = .chat
            // Posts read as posts in their own room (2026-07-13) — split from
            // .chat: a saved conversation is a snippet row, a post is a card.
            // NOSTR JOINED 2026-08-26 (prd §489) — two years of this room
            // being a room for two of the three networks that land into it.
            // It had no case here at all, so its rows fell to `.plain`'s
            // generic band: no faces above the room, no post cards, no thread
            // folding, no person filter. All of it was already built and
            // already knew about Nostr — `PostCard.author` branches on its hex
            // pubkey to shorten it for display, `SocialThreadCard` does the
            // same, `SocialThread.replies` reads its threads, and
            // `NostrStore.socialAccounts` was drawn on the setup screen. One
            // switch statement never learned the name.
            case "Farcaster", "Bluesky", "Nostr": self = .social
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
            // Instagram, 2026-08-18 (prd §395) — the LAST photo app in this
            // app still drawing as text, and the one where it cost most. It
            // had no case here at all, so it fell to `.plain`: a `BandRow` per
            // row, a 26pt leader square and `titleLine`'s 80-character clamp,
            // in a room whose own importer has written 480pt thumbnails since
            // §310 explicitly because "Instagram is a photo app, and its room
            // was a wall of text". The pixels were stored and never drawn at
            // any size worth looking at — the §283 Files failure and the §313 X
            // failure, both again, in the room they were both compared to.
            //
            // Its OWN case rather than joining `.x`: that room's grid holds
            // your own wordless posts alone, and this one has to hold saves
            // that arrived with no picture at all until `InstagramCaptions`
            // fetched one. Sharing the case would also hand this room X's head.
            // The LITERAL, like `case "X"` and `case "Snapchat"` beside it —
            // `demo-selftest.py`'s check F reads this switch to prove every
            // shape has a seeded source, and it resolves exactly three
            // indirections by name (x402, App Store Connect, the media
            // predicate). A fourth would make this room's shape unverifiable
            // rather than verified, which is the worse half of both options.
            case "Instagram":           self = .instagram
            // TikTok, 2026-08-26 (prd §489) — the SECOND room with no case
            // here, found by auditing the other seven rather than by a report,
            // because nobody had opened it lately. A room of saved videos drew
            // one `BandRow` per row: a 26pt leader square and `titleLine`'s
            // 80-character clamp over what is, before `TikTokImport.fetchFaces`
            // has run, the raw share URL. The cover art the face pass fetches
            // was stored on `previewImageURL` and drawn at no size at all.
            //
            // Its own case rather than joining `.instagram`: that room's rows
            // carry `postText` and read as post cards, and TikTok's carry none
            // (its caption lands on `enrichedText`, retrieval-only) — see
            // `SocialRoom.rowKind` for why that makes a post card dishonest
            // here and a reading row correct.
            // The LITERAL, like `case "Instagram"` above it —
            // `demo-selftest.py`'s check F reads this switch to prove every
            // shape has a seeded source, and it resolves only three
            // indirections by name.
            case "TikTok":              self = .tiktok
            case "X":                   self = .x
            // Telegram, 2026-08-23 (prd §456) — the first room holding BOTH a
            // live drip and an import under one source, so it has the widest
            // row mix in the app: a followed channel's broadcast posts (words,
            // usually a picture), your Saved Messages (mostly bare links), and
            // whole conversations as `.chat` rows.
            //
            // Its own case rather than `.social`: that one is Farcaster and
            // Bluesky, whose roster head reads accounts out of `BlueskyStore`
            // for anything that isn't Farcaster — the same objection that kept
            // X out. And rather than `.chat`: a channel post is not a message,
            // and a room of broadcast posts drawn as chat bubbles is the §313
            // failure wearing the other coat.
            case "Telegram":            self = .telegram
            // R4.2 (2026-08-23) — had NO case, so it fell to `.plain` and
            // drew one identical glyph per row with the account's address
            // truncated at the END of an 80-char title. Two accounts'
            // events were indistinguishable at a glance, in a room whose
            // whole subject is which account something happened to. Its
            // own case rather than `.wallet`: that room's rows are money
            // and its head is a balance, and a key authorization is
            // neither.
            // The LITERAL, not `VibenetIdentity.source`: `demo-selftest.py`'s
            // check F reads this switch to prove every shape has a seeded
            // source, and it resolves exactly three indirections by name.
            // A fourth makes this room's shape UNVERIFIABLE rather than
            // verified — the comment above `case "Instagram"` says so, and
            // this case failed that check on its first run for exactly
            // that reason.
            case "Base Vibenet":        self = .vibenet
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
            // CardPointers, 2026-08-26 (prd §487) — the x402 finding again,
            // six rooms later and with the same three symptoms. It had no case
            // here, so `.plain` drew a `BandRow` per offer: one glyph, the
            // `Card · Merchant` title, and a trailing timestamp that is
            // `capturedAt` — which the ingest stamps `.now`, so every row in
            // the room shared one time under one "Today" header. The two facts
            // that make an offer an offer were on the row's own model and on
            // no screen: the terms on `summary` (which `BandRow` never reads)
            // and the deadline on `dueAt` (which only the head drew, for one
            // offer). Its own case rather than `.reminders`, whose band is a
            // one-line fact — an offer is three.
            //
            // The LITERAL, like `case "Cursor"` above it — `demo-selftest.py`'s
            // check F reads this switch to prove every shape has a seeded
            // source, and it resolves only three indirections by name.
            case "CardPointers":        self = .cardPointers
            // The LITERAL, for the same reason as the line above.
            case "Walletbeat":          self = .walletbeat
            // The LITERAL, for the same reason as `case "Walletbeat"` above —
            // `demo-selftest.py`'s check F reads this switch by name.
            case "L2BEAT":              self = .l2beat
            case "Reminders", "Todoist": self = .reminders
            // This case was written 2026-07-13 for a "Safari" bridge that
            // never shipped — Safari and Chrome exports merged into ONE
            // "Bookmarks" offer on 2026-07-28 (prd §224), and the shape below
            // was never rewired to the source that actually landed. Found
            // 2026-08-10: the case had gone fully dead (no bridge ever
            // stamped `source: "Safari"`) while `BookmarksImport.land` had
            // been stamping `.link` things as "Bookmarks" since it shipped,
            // silently falling to `.plain`'s generic band row — exactly the
            // saved-link reading list this shape (`ReadingRow`/`ReadingLede`)
            // was built for, wearing no Safari branding of its own.
            case "Bookmarks":           self = .bookmarks
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
        case .social, .x, .instagram, .tiktok: .init(dx: 0, dy: 12, scale: 0.98, step: 0.035)
        default:        .init(dx: 0, dy: 8, scale: 1, step: 0.028)
        }
    }

    // MARK: - Derivations

    /// The corpus MINUS the search-only sources — Contacts land as things for
    /// lookup and the answer path, but never as feed rows or a source chip
    /// (ruling 2026-07-12): hundreds of names would bury the day's captures.
    /// One rule (`Corpus.surfaced`), shared with Home's synthesis.
    ///
    /// The pinned room is the one exception, and it is the same exception its
    /// `@Query` already makes: its rows are selected by YOUR act, not by a
    /// source, so the corpus-shaped rules don't apply to it. A contact you
    /// pinned is a contact you asked to keep in front of you — dropping it here
    /// would make the verb silently fail on exactly the rows the search-only
    /// rule exists to keep OUT of a river you didn't build.
    private var feedThings: [Thing] {
        Pinboard.isPinnedRoom(source) ? things : Corpus.surfaced(things)
    }

    private func liveVisible() -> [Thing] {
        feedThings.filter { thing in
            // The pinned room's membership is decided entirely by the `@Query`
            // above (`pinnedAt != nil`), so there is no source to match against
            // — and matching one is how this room shipped EMPTY (2026-08-10):
            // "Pinned" is not a source any thing carries, so `thing.source ==
            // source` was false for every row the query had just correctly
            // handed over, and the room drew its own "nothing pinned" line over
            // a list that wasn't.
            (source == "All" || Pinboard.isPinnedRoom(source) || thing.source == source)
                // A bulk import (Instagram, Snapchat) keeps its own room but
                // stays OUT of All — thousands of things dated across years
                // would bury the day's real captures. All sees its receipt
                // only; the chip opens the room that holds the rest.
                && (source != "All" || Corpus.showsInAll(thing))
                && (filter.tag == "All" || thing.tags.contains(filter.tag))
                && walletScopeAllows(thing)
                && vibenetScopeAllows(thing)
                && personScopeAllows(thing)
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
    /// The wallet apps the person said they use, for the Walletbeat room's
    /// incident rows (prd §422). Derived from the room's own rows rather than
    /// fetched — §419's decision to make the watch a `Thing` is what makes that
    /// possible, and it means the marker can never disagree with the watch rows
    /// sitting directly above it in the same feed.
    ///
    /// Scoped to that room by construction: the only caller is `shapedRow`'s
    /// `.walletbeat` case, so this walk costs nothing in any other room. Its
    /// bound is that room's own size — 32 wallets and a dozen incidents — so
    /// the per-row recomputation is a few hundred string compares, not the
    /// corpus-wide walk this file's perf history warns about.
    private var walletbeatWatchedIDs: Set<String> {
        Set(visible.live.compactMap { WalletbeatWatch.walletID(from: $0) })
    }

    /// The chains the person said they use, for the L2BEAT room's milestone rows
    /// (prd §428). Derived from the room's own rows rather than fetched — making
    /// the watch a `Thing` is what makes that possible, and it means the marker
    /// can never disagree with the watch rows sitting above it in the same feed.
    ///
    /// Scoped to that room by construction: the only caller is `shapedRow`'s
    /// `.l2beat` case, so this walk costs nothing in any other room.
    private var l2beatWatchedIDs: Set<String> {
        Set(visible.live.compactMap { L2beatWatch.chainID(from: $0) })
    }

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
        // Never `things.count` here (PERF 2026-08-11) — see `corpusRevision`.
        // Before the snapshot exists there is nothing on screen to animate
        // against anyway, so 0 is the honest starting value.
        return debouncedAllSnapshot?.count ?? 0
    }

    /// How many things exist, WITHOUT materialising one — the All room's
    /// change signal (2026-08-11). It replaces `things.count`, which was a
    /// trap in two directions at once.
    ///
    /// COST. `@Query` fetches in its GETTER — the 6,000-row main-thread
    /// profile puts the CoreData fetch under `FeedScreen.things.getter`
    /// (`scripts/output/profile-ios-cold-6k.txt`), not under any update hook —
    /// so every `.count` materialised up to `allRoomFetchLimit` real `Thing`
    /// objects on the main actor. The body reads that key on EVERY evaluation,
    /// and a cold foreground fires one per bridge save, ~30 of them. Which is
    /// the exact cost the debounce below exists to avoid: reading `.count` to
    /// decide whether to debounce paid the price the debounce was saving.
    ///
    /// CORRECTNESS, and this half is the more serious one. `things` is bounded
    /// at `allRoomFetchLimit` (1,200). On any corpus LARGER than that its
    /// count is pinned at exactly 1,200 and can never change again — so
    /// `.task(id: things.count)` never restarted, `debouncedAllSnapshot` was
    /// populated once and never refreshed, and the All room stopped showing
    /// new arrivals for the life of the mount. It was masked by `MainSurface`
    /// carrying `.id(filter.source)`: leaving the room and coming back builds
    /// a new screen, which paints correctly, so it reads as "the feed only
    /// updates when I switch chips" rather than as a frozen list. Introduced
    /// with the fetch bound on 2026-08-06 and invisible to every check here,
    /// since the bound is only reachable on a corpus that large.
    ///
    /// `fetchCount` is a SQL `COUNT` over the whole store: no ceiling, so it
    /// tracks arrivals at any corpus size, and no model instantiation, so it
    /// costs a fraction of the read it replaces.
    ///
    /// It shares `things.count`'s one blind spot deliberately: an in-place
    /// heal that changes no row COUNT doesn't repaint until the next arrival —
    /// the same acceptable lag for a cosmetic fixup that the `.task(id:)`
    /// below already documents.
    /// Two terms since 2026-08-12 — see `Corpus.Revision`. The second one
    /// closes the gap this property's own doc used to concede: an in-place
    /// heal that changes no row count now repaints instead of waiting for the
    /// next arrival.
    ///
    /// The room guard lives HERE rather than at the `.task(id:)` below, so a
    /// per-source room doesn't even run the `COUNT` — its own predicated
    /// query already coordinates it, and it has no snapshot to refresh.
    ///
    /// That stays true now source rooms are BOUNDED too (2026-08-14): the
    /// bound caps how many rows the query returns, not whether SwiftData
    /// re-runs it on save, so the array still tracks arrivals. What the bound
    /// does break is anything keyed on that array's `.count`, which pins at
    /// the limit — `listRevision` above is the one such reader and says so.
    private var corpusRevision: Corpus.Revision {
        guard source == "All", filter.tag == "All" else { return .idle }
        return Corpus.revision(in: modelContext)
    }

    // MARK: - The room's head, memoised

    /// The registry answers a room's head is chosen from (PERF 2026-08-21,
    /// prd §434 ruling 1).
    ///
    /// None of these holds a `Thing` — `FeedInsight`'s four are plain value
    /// types over counts and labels, and `SourceHead`'s cases carry room models
    /// whose own contract is that they hand back a value and let the VIEW do
    /// the lookup (see the `sourceHead` render below, which says so). That is
    /// what makes this cacheable at all: a cache of model references would be
    /// the SwiftData liveness class this file documents at length, arriving by
    /// the one route none of its six corollaries covers.
    private struct RoomHeads {
        let sourceHead: SourceHead?
        let topicMap: FeedInsight.TopicMap?
        let leaderboard: FeedInsight.Leaderboard?
        let distribution: FeedInsight.Distribution?
        let mosaic: FeedInsight.Mosaic?
        /// Whether the feeds behind a reading room are still answering
        /// (2026-08-23, prd §455). Cached HERE rather than in a task of its
        /// own because it has exactly this lifecycle — recompute when the
        /// room, the pull or the room's contents move — and because
        /// `FeedFreshness` is not `@Observable`, so a body read would never
        /// refresh itself and would copy its whole record dictionary once per
        /// followed feed per body pass.
        var feedHealth: FeedRoomHealth.Standing? = nil
    }

    /// The last head computed for each room, kept ACROSS the mount.
    ///
    /// This is the half that makes a swipe cheap, and it exists because §265's
    /// discrete transition is a remount: `MainSurface` carries
    /// `.id(filter.source)`, so every swipe destroys this screen and builds a
    /// new one, and anything held in `@State` is gone. The head chain was
    /// therefore recomputed from zero on EVERY entry to EVERY room, over the
    /// room's whole contents, on the main actor, inside the frames the slide
    /// animation needs — which is the reported "lag swiping between screens".
    ///
    /// Static, not `@State`, for exactly that reason. `AgentOpenCache` is the
    /// same shape for the same reason one screen over.
    ///
    /// Bounded by the number of rooms, which is bounded by the catalog, and
    /// each entry is a handful of labels and counts — so there is no eviction
    /// policy here on purpose, because there is nothing to evict.
    ///
    /// KEYED BY `headIdentity`, NOT BY SOURCE. Keying by source alone would
    /// hand back a head computed under a DIFFERENT scope — leave a wallet-scoped
    /// room, come back unscoped, and the card describes rows that are not on
    /// screen. It self-corrects a frame later, which makes it worse rather than
    /// better: a card that is briefly wrong and then right is a card nobody can
    /// trust, and §83 is not a rule about how long a claim is false for. A miss
    /// draws no head, which is the honest answer while one is being computed.
    @MainActor private static var headMemo: [String: RoomHeads] = [:]

    /// What this room's head draws from right now. Seeded from `headMemo` and
    /// refreshed by the task below, so a room you have already visited paints
    /// its head immediately and a room you have not shows none until the first
    /// computation lands — the same nothing a head that DECLINES draws.
    @State private var heads: RoomHeads?

    /// What the head is memoised AGAINST — everything that can change what it
    /// says, and nothing that can't.
    ///
    /// `Corpus.revision(in:source:)` is the content term and is two indexed
    /// reads rather than a materialisation (see its own doc). The scopes are in
    /// here because the head describes `visible`, and `visible` is narrowed by
    /// the wallet rail, the person rail and the tag filter — a head that
    /// survived a scope change would be a card describing rows that are no
    /// longer on screen, which is the §83 disagreement this file already
    /// forbids one level up in `shapedSections`.
    private var headIdentity: String {
        let revision = source == "All"
            ? Corpus.revision(in: modelContext)
            : Corpus.revision(in: modelContext, source: source)
        return [source, filter.tag, selectedWallet ?? "", chrome.personScope ?? "",
                // The vibenet rail scopes the CARD (2026-08-23), so it
                // belongs in the memo key for the reason this property's
                // own doc gives: a head that survived a scope change is a
                // card describing rows that are no longer on screen.
                // Omitted at first, and the symptom was exactly that —
                // the face lit and the card kept listing every account.
                chrome.vibenetScope ?? "",
                x402Lane ?? "", readingScope?.key ?? "",
                // Bridge state is the one input a corpus revision cannot see —
                // `sourceHead` reads a Stripe balance, PostHog readings, an ASC
                // standing, none of which is a `Thing`. A pull is when somebody
                // is explicitly asking for new numbers, so it re-keys here.
                // Residual, stated: a BACKGROUND sweep that updates bridge state
                // and lands no row leaves the head reading until the next
                // arrival. Acceptable because a sweep that changes a reading
                // almost always lands the row that changed it, and because the
                // alternative is recomputing the whole chain on a timer.
                String(chrome.refreshPulse),
                // **THE ONE SEAT THAT BREAKS THE RESIDUAL ABOVE.** That note
                // is right about every other bridge: a sweep that changes a
                // reading almost always lands the row that changed it, so the
                // corpus revision moves and the head recomputes. Ethrex Hegotá
                // lands NO row, ever — its whole room is live state — so its
                // revision is frozen at zero and this key never changed. The
                // head was therefore computed ONCE, while the sweep had not yet
                // returned, memoised as nil, and never recomputed: a black
                // room, permanently, with every other fix in place. Reported
                // from a device three times before this was found, because
                // nothing static can see a memo that never invalidates.
                HegotaRoomSource.identity,
                String(revision.count), String(revision.signal)]
            .joined(separator: "|")
    }

    /// The task's id — the identity above PLUS whether we are allowed to
    /// compute yet. Two spellings because they answer two different questions,
    /// and collapsing them breaks one of them whichever way you collapse.
    ///
    /// `headIdentity` says WHAT the head would describe, so it is what the memo
    /// is stored under: the swipe's transient bound changes nothing about the
    /// answer, so a room re-entered mid-swipe must still hit its cached head —
    /// which is the entire point of a cache that survives the remount.
    ///
    /// The task id must additionally move when the BUDGET lifts, and that half
    /// is a bug this pass wrote and then caught by re-reading its own diff: the
    /// task declines while `rowBudget` is set, and the revision inside the
    /// identity counts the WHOLE room, unaffected by the query's transient
    /// `fetchLimit`. So without this term the id is byte-identical before and
    /// after the bound lifts, the task never re-fires, and the head is not
    /// deferred but DROPPED — nil until some unrelated change moves the count.
    private var headKey: String {
        headIdentity + (rowBudget == nil ? "|full" : "|bounded")
    }

    /// The room's own narrowing, as ONE rule — the lane strip scopes everything
    /// below it, head included (2026-08-06). Shared by `shapedSections` (which
    /// narrows the ROWS) and the head computation (which must describe exactly
    /// those rows), because two spellings of one scope is how a head ends up
    /// describing a marketplace the reader just filtered away.
    /// `narrowingToPublisher` is the one asymmetry, and it exists because the
    /// reading board is the CONTROL as well as the reading (2026-08-23, prd
    /// §455): the rows narrow to one publisher, and the board must keep every
    /// publisher on it or there is no way back — the venue switcher's rule
    /// (§357), which shows every venue while the room shows one. Passed false
    /// by `recomputeHeads` when it computes that one card and by nothing else,
    /// so every other head still describes exactly the rows on screen.
    private func roomScoped(_ rows: [Thing], narrowingToPublisher: Bool = true) -> [Thing] {
        var out = shape == .x402 ? x402Scoped(rows) : rows
        if narrowingToPublisher, let scope = readingScope {
            // `.live` before a stored property is read (corollary 4) —
            // `rows` may be the debounced All snapshot.
            out = out.live.filter {
                scope.scope.value(of: $0)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) == scope.label
            }
        }
        return out
    }

    /// Compute this room's head, off the body.
    ///
    /// ALL FIVE UNCONDITIONALLY, where the body short-circuits — and that costs
    /// nothing, which is why the gates could be left where they belong. Each
    /// registry switches on `source` and returns nil immediately for a source it
    /// doesn't serve, and the registries deliberately don't intersect (see the
    /// heatmap's own note in `shapedSections`), so for any given room at most
    /// one of these does real work. Keeping the gates in ONE place — the body,
    /// where `liveStream` and `anniversary` live because they hold `Thing`s and
    /// can never be cached — is worth far more than a short-circuit that saves
    /// four switch statements.
    @MainActor
    private func recomputeHeads() {
        // `.live` at the read, inside the task: `visible` is re-read here rather
        // than captured by the body, and nothing suspends between this line and
        // the computation below, so every model is valid for the whole of it
        // (liveness corollary 6 — the one the audit's check 6 exists for, and
        // the reason a PERF change that moves a fetch is always also a liveness
        // change).
        let rows = roomScoped(visible.live)
        // THE BOARD ALONE IS COMPUTED OVER THE WHOLE ROOM (2026-08-23), when
        // the room has been narrowed FROM that board — see `roomScoped`. A
        // board recomputed over one publisher's rows is a single bar naming
        // the choice you already made, with nothing to switch to and no way to
        // clear it. Identical to `rows` whenever nothing is scoped, which is
        // every other room and most of this one's life.
        let boardRows = readingScope == nil
            ? rows
            : roomScoped(visible.live, narrowingToPublisher: false)
        let computed = RoomHeads(
            sourceHead: sourceHead(rows),
            topicMap: FeedInsight.topicMap(source: source, things: rows),
            leaderboard: FeedInsight.leaderboard(source: source, things: boardRows),
            distribution: FeedInsight.distribution(source: source, things: rows),
            mosaic: FeedInsight.mosaic(source: source, things: rows),
            // Reads the follow stores and `FeedFreshness`, never `rows` — the
            // whole point is a feed that has stopped producing rows, so a
            // verdict derived from the room's contents could not see it.
            feedHealth: FeedRoomHealthSource.standing(for: source))
        Self.headMemo[headIdentity] = computed
        heads = computed
        SwipeClock.mark("heads", detail: "rows=\(rows.count)")
    }

    /// Is this room one the wallet scope may narrow (prd §356) — every seat in
    /// the Wallet category, which is what the face rail is offered on.
    ///
    /// **The gate is the room, never the scope's own nil-ness**, and that
    /// distinction became load-bearing the moment §356 moved the scope onto
    /// the shell: a scope set in the balance room now outlives the room, so an
    /// ungated filter would reach Social and Work — where every row's
    /// `walletAddress` is nil, so `scopeMatches` answers false for all of them
    /// and the room renders EMPTY with nothing on screen able to explain why.
    private var roomTakesWalletScope: Bool {
        BridgeCatalog.category(forSource: source) == CategoryFold.walletCategory
    }

    /// The per-wallet scope (prd §128, widened to the whole Wallet category by
    /// §356) — everything passes in "All"; when scoped, only rows belonging to
    /// that watched wallet. Matched through `WalletStore.scopeMatches`
    /// (2026-07-20): things are stamped with the RESOLVED hex while the scope
    /// is the WATCHED spelling, so a raw compare empties an ENS/SNS-watched
    /// wallet's scoped feed entirely.
    private func walletScopeAllows(_ thing: Thing) -> Bool {
        guard roomTakesWalletScope, let scope = selectedWallet else { return true }
        return wallet.scopeMatches(thing.walletAddress, scope: scope)
    }

    /// The per-person scope (prd §362, 2026-08-11) — the social rail's own
    /// filter, the exact counterpart of `walletScopeAllows` above, and gated the
    /// same way for the same reason: on the ROOM, never on the scope's nil-ness.
    /// The scope is cleared on every source change (`MainSurface`), so this gate
    /// is belt-and-braces rather than the primary defence — but it is the one
    /// that holds if a room is entered before that clear lands, and an ungated
    /// compare against `authorHandle` would empty every non-social room, where
    /// that field is nil on essentially every row.
    private func personScopeAllows(_ thing: Thing) -> Bool {
        guard SocialRoom.hasRoster(source), let scope = chrome.personScope else { return true }
        return thing.authorHandle == scope
    }

    /// The vibenet room's account scope (2026-08-23) — the same shape as
    /// the two above, gated on the ROOM rather than the scope's nil-ness
    /// for the same reason: every vibenet event stamps its account on
    /// `authorHandle`, and an ungated compare would empty every other
    /// room where that field means something else entirely. Case-
    /// insensitive because a watched address may be stored in any case
    /// while the landed row carries the lowercased form the log gave.
    private func vibenetScopeAllows(_ thing: Thing) -> Bool {
        guard shape == .vibenet, let scope = chrome.vibenetScope else { return true }
        guard let handle = thing.authorHandle else { return false }
        return handle.caseInsensitiveCompare(scope) == .orderedSame
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
        // Wrapped rather than passed by reference: `bundledRowCount` grew a
        // defaulted `nextEventID`, and Swift does not apply default arguments
        // when converting a function to a value.
        return dayGroups(recent)
            + coarsenIfSparse(dayGroups(older), rows: { bundledRowCount($0) })
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
    /// Asks the REAL fold decision (`foldBuckets` + `fold`) rather than
    /// mirroring it. It used to mirror — a hand-copy of "a source with
    /// `bundleThreshold`+ bundleable things collapses to one row" — and §255
    /// is the record of what that costs: the gate measured THINGS while the
    /// feed drew ROWS, so the tail-coarsening it guards never once fired.
    /// Two folds (a bundle and a strip, with different eligibility) is exactly
    /// where a second copy would go quietly wrong again, so there is only one.
    ///
    /// `nextEventID` defaults to nil, and that is CORRECT rather than lazy for
    /// this caller: the clock carve-out below only ever spares a FUTURE event,
    /// which by construction cannot sit in the coarsened tail this gate is
    /// deciding about.
    private func bundledRowCount(_ dayThings: [Thing], nextEventID: UUID? = nil) -> Int {
        let (bySource, eligible) = foldBuckets(dayThings, nextEventID: nextEventID)
        var folded: Set<String> = []
        for (source, members) in bySource
        where FeedFold.decide(members, faceSources: BandRow.faceSources) != nil {
            folded.insert(source)
        }
        var rows = 0
        var seen: Set<String> = []
        for t in dayThings {
            if folded.contains(t.source), eligible.contains(ObjectIdentifier(t)) {
                if seen.insert(t.source).inserted { rows += 1 }
            } else {
                rows += 1
            }
        }
        return rows
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

    /// What each COARSE group was mostly about (prd §379) — the tail stops
    /// being a list of month names and becomes an index.
    ///
    /// §218 made the tail short and §254 made it quiet, and neither made it
    /// BROWSABLE: "March", "April", "May" are three identical headers, so
    /// finding last spring still means scrolling into it and reading rows.
    ///
    /// The rule is `XRoom.subject` CALLED, never re-implemented — §375's own
    /// recurrence floor (two mentions or a tenth of the group, whichever is
    /// larger), already compiled whole and mutation-proven by
    /// `x-selftest.sh`. It is the same question that ruling asked of a year,
    /// asked of a month.
    ///
    /// Terms come from `ocrTopics` ONLY. Tags were considered and declined:
    /// most of them are FACETS (`Post`, `Liked`, `Watchlist`, `Memory` — §308),
    /// so a month would report its structure as its subject, which is the
    /// §83 fake status wearing a label. `ocrTopics` is the deterministic
    /// extraction (§313), so every subject drawn here is a term that literally
    /// appears in the things beneath it.
    ///
    /// Nil is the NORMAL answer and the header is built for it: a month of
    /// wallet transactions and calendar events carries no topic terms at all,
    /// and inventing one for it would be worse than saying nothing.
    private func coarseSubjects(_ groups: [(String, [Thing])],
                                coarse: Set<String>) -> [String: String] {
        var out: [String: String] = [:]
        for (label, rows) in groups where coarse.contains(label) {
            var terms: [String: Int] = [:]
            var counted = 0
            // `.isLive` before any stored read — a derived array, read in the
            // same graph update a heal's delete can land in (CLAUDE.md).
            for t in rows where t.isLive {
                counted += 1
                for term in t.ocrTopics { terms[term, default: 0] += 1 }
            }
            if let subject = XRoom.subject(terms, posts: counted) { out[label] = subject }
        }
        return out
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
        /// The ambient tier (prd §378) — a row that arrived on its own rather
        /// than one you made or one that concerns you. STORED at construction,
        /// exactly like `id` and `date` and for the same reason: the render
        /// loop must be able to ask "does this recede?" without a
        /// stored-property read on a model a heal may since have deleted.
        let ambient: Bool
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
            /// A run folded into its MEMBERS rather than into a sentence about
            /// them (prd §377): screenshots and file images as their pictures,
            /// posts as their authors' faces, songs as their covers. Same
            /// one-row compression as `.bundle`, drawn side by side instead of
            /// as an overlapped fan.
            case strip(source: String, word: String, count: Int, newest: Date, tiles: [StripTile])
        }
        static func single(_ t: Thing) -> FeedRow {
            FeedRow(id: t.id.uuidString, date: t.capturedAt, kind: .single(KeyedThing(t)),
                    ambient: FeedFold.tier(t) == .arrived)
        }
        static func bundle(source: String, word: String, count: Int,
                           newest: Date, art: [String], ambient: Bool) -> FeedRow {
            FeedRow(id: "bundle-\(source)-\(newest.timeIntervalSince1970)", date: newest,
                    kind: .bundle(source: source, word: word, count: count,
                                  newest: newest, art: art),
                    ambient: ambient)
        }
        static func strip(source: String, word: String, count: Int,
                          newest: Date, tiles: [StripTile], ambient: Bool) -> FeedRow {
            FeedRow(id: "strip-\(source)-\(newest.timeIntervalSince1970)", date: newest,
                    kind: .strip(source: source, word: word, count: count,
                                 newest: newest, tiles: tiles),
                    ambient: ambient)
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

    /// `bundleThreshold`+ foldable things from one source in one day collapse
    /// into ONE row at the position of their newest member — a `StripRow` when
    /// the members can be drawn as themselves, a `BundleRow` otherwise (see
    /// `fold`). Order is untouched either way — compression, not ranking.
    /// Takes the already-computed day groups so the caller derives `dayGroups`
    /// (→`visible`→`feedThings`) ONCE per render and reuses it for the day
    /// totals too, instead of rebuilding the whole chain here a second time.
    ///
    /// `excluding` is the cover (prd §389c) — removed BEFORE the fold buckets
    /// are built, not filtered out of the finished rows, so a source whose run
    /// the cover was part of counts and draws its remaining members honestly
    /// (three mails minus the cover is two mails, which is under
    /// `bundleThreshold` and correctly stops folding at all). Filtering after
    /// the fact would have left "iCloud Mail · 3 emails" beside a cover that is
    /// one of those three.
    private func bundle(_ days: [(String, [Thing])],
                        nextEventID: UUID? = nil,
                        excluding cover: UUID? = nil) -> [(String, [FeedRow])] {
        days.map { label, allDayThings in
            let dayThings = cover.map { id in allDayThings.filter { $0.id != id } }
                ?? allDayThings
            // Grouped ONCE per day (perf, 2026-07-28): the old version
            // re-filtered the whole day for every bundled source it found
            // (O(day size²) — a heavy sync day with several bundled sources
            // multiplied its own count against itself). Same membership,
            // built with one pass instead of one pass per source.
            let (bySource, eligible) = foldBuckets(dayThings, nextEventID: nextEventID)
            var folded: [String: FeedFold.Decision] = [:]
            for (source, members) in bySource {
                if let decision = FeedFold.decide(members, faceSources: BandRow.faceSources) {
                    folded[source] = decision
                }
            }
            var rows: [FeedRow] = []
            var seen: Set<String> = []
            for t in dayThings {
                guard let decision = folded[t.source],
                      eligible.contains(ObjectIdentifier(t)) else {
                    rows.append(.single(t)); continue
                }
                guard seen.insert(t.source).inserted else { continue }
                let members = bySource[t.source] ?? []
                let kinds = Set(members.map(\.kind))
                let word = kinds.count == 1
                    ? kinds.first!.typeTagPlural.lowercased() : "things"
                // A fold recedes only if EVERY member would — one transaction
                // or one clock inside a mixed run keeps the whole row at full
                // weight, since the row is the only thing standing in for it.
                let ambient = FeedFold.ambient(members)
                switch decision {
                case .strip(let choices):
                    // A choice names its member by INDEX — the seam that keeps
                    // `FeedFold` free of SwiftData and therefore harnessable
                    // (§379). The models are still live here: this runs while
                    // building the row value, the same moment `FeedRow.single`
                    // captures its id.
                    let tiles = choices.map {
                        StripTile(members[$0.index], remote: $0.remote, circular: $0.circular)
                    }
                    rows.append(.strip(source: t.source, word: word,
                                       count: members.count, newest: t.capturedAt,
                                       tiles: tiles, ambient: ambient))
                case .bundle(let art):
                    rows.append(.bundle(source: t.source, word: word,
                                        count: members.count, newest: t.capturedAt,
                                        art: art, ambient: ambient))
                }
            }
            return (label, rows)
        }
    }

    /// The things in a day that are ELIGIBLE to fold, bucketed by source, plus
    /// their identities so the row loop can ask "was this one folded?" in
    /// constant time (the O(day²) trap the 2026-07-28 perf pass fixed once
    /// already — a `contains(where:)` per thing would put it straight back).
    ///
    /// Two things are held out, for opposite reasons:
    ///
    /// - Anything neither `bundleable` nor a strip candidate. A screenshot is
    ///   the case worth naming: it is deliberately still NOT `bundleable`, so
    ///   it can never collapse into "Photos · 4 screenshots" — a sentence that
    ///   hides the only thing a screenshot has. It folds only into a strip,
    ///   where its picture survives.
    /// - Anything carrying a CLOCK (prd §377). §35 ruled that perishables show
    ///   their countdown "everywhere … not just in their source's shape", and
    ///   nothing enforced it: a day with three calendar events folded the
    ///   next-up row away, and a live row can't be floated to the top of its
    ///   day (2026-07-21) once it has stopped existing as a row. Its siblings
    ///   still fold; the row with the clock stands out of the fold.
    private func foldBuckets(_ dayThings: [Thing], nextEventID: UUID?)
        -> (bySource: [String: [Thing]], eligible: Set<ObjectIdentifier>) {
        var bySource: [String: [Thing]] = [:]
        var eligible: Set<ObjectIdentifier> = []
        for t in dayThings {
            guard FeedFold.bundleable(t)
                    || FeedFold.stripCandidate(t, faceSources: BandRow.faceSources)
            else { continue }
            guard !FeedFold.carriesAClock(t, nextEventID: nextEventID,
                                          isLive: isLive(t)) else { continue }
            bySource[t.source, default: []].append(t)
            eligible.insert(ObjectIdentifier(t))
        }
        return (bySource, eligible)
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

    /// Past this, the newest thing is not news and gets no cover (prd §389).
    /// A hero is a claim about recency and nothing else, so it needs a clock
    /// to be true — open the app after a quiet week and the top row is a week
    /// old, which is exactly when a cover would be lying by implication.
    private static let ledeMaxAge: TimeInterval = 24 * 3600

    /// A cover over a two-row feed IS the feed. Same minority discipline
    /// `wideArtIDs` states as its own floor, for the same reason.
    private static let ledeMinRows = 3

    /// The THING that draws as the feed's cover (prd §389c, 2026-08-16) — the
    /// newest one in the newest day, full stop, whether or not it would
    /// otherwise have folded. It is lifted OUT of the rows below (see
    /// `bundle(_:nextEventID:excluding:)`), so it appears exactly once; when
    /// the next thing lands it takes the cover and this one drops back into its
    /// own row, or into its source's fold.
    ///
    /// **Chosen over THINGS, before bundling — not over rows, after it.** The
    /// §389b version read the bundled rows and stepped over folds to find the
    /// newest thing that had arrived on its own, and its own doc admitted the
    /// consequence: "the cover may not be the newest thing on screen, since a
    /// fold above it can be newer." Reported as exactly that within the day — an
    /// eight-hour-old voice note leading over a newer email, because mail had
    /// folded and voice can never fold (`FeedFold.bundleable` excludes voice,
    /// screenshots and anything from You, so the §389b candidate pool was
    /// biased toward precisely the rows that never fold, and a stale one could
    /// hold the top of the feed for a full `ledeMaxAge`). The feed's standing
    /// law is that volume compresses and NEVER reorders (§35); the cover was
    /// the one place that reordered, so the fix is to make it unable to.
    ///
    /// Three ways it declines, each because the card would say something
    /// untrue:
    ///
    /// - The newest thing is older than `ledeMaxAge`. A cover is a claim about
    ///   recency and nothing else. NOTE this is asked when the derivation memo
    ///   is rebuilt rather than per render, so a session left open for a day
    ///   keeps its cover until the next arrival — deliberate: the cover and the
    ///   fold that excludes it MUST be decided together, and a per-render pick
    ///   could name a thing that is still inside `memo.groups`' fold, drawing
    ///   it twice.
    /// - The feed is shorter than `ledeMinRows` — counted in THINGS here as a
    ///   cheap upper bound, and re-asked in ROWS by the caller once the fold
    ///   has run (the real floor; see `bundledSections`).
    /// - The newest thing `standsAlone` — a consent card, a token pulse, a post
    ///   card are full anatomies sized for their own reasons, and wrapping one
    ///   in a cover is two rhythm-breakers stacked (for `ApprovalCard` it would
    ///   bury the verbs). NOTE it declines rather than reaching PAST it: a
    ///   stands-alone row keeps its own position at the top of the rows, so
    ///   covering something older would put a newer row underneath an older
    ///   card — the very thing this rewrite exists to make impossible.
    ///
    /// Scoped to the FIRST group: a cover is the top of the feed, and reaching
    /// into yesterday for one would be ranking, not position.
    ///
    /// Counted rather than flattened, deliberately: `flatMap` would allocate
    /// the whole thing list to read one group, on the screen with this app's
    /// worst measured perf history (`derivationKey`'s own
    /// 6.3-seconds-across-44-renders note).
    private func ledeThingID(in days: [(String, [Thing])]) -> UUID? {
        let count = days.reduce(0) { $0 + $1.1.count }
        guard count >= Self.ledeMinRows, let head = days.first?.1 else { return nil }
        for thing in head {
            // `.isLive` before any stored read — a derived array read during the
            // same graph update a heal's delete can land in (the dead-Thing
            // rule). A dead row is skipped, not fatal: the next one may be fine.
            guard thing.isLive else { continue }
            // Newest-first, so the first one past the age bound means every
            // later one is too.
            guard Date.now.timeIntervalSince(thing.capturedAt) <= Self.ledeMaxAge
            else { return nil }
            return standsAlone(thing) ? nil : thing.id
        }
        return nil
    }

    /// The away window lifted into its own section (prd §389) — "Since you
    /// left", then the day grain underneath it.
    ///
    /// The All feed has carried this boundary since 2026-07-09, as an inline
    /// capsule (`newSinceDivider`) sitting wherever it happened to fall inside
    /// a day. That says the same true thing in the weakest available position:
    /// a caption between two rows, competing with the day header above it.
    /// Promoting it to sectioning makes the FIRST thing the feed says be what
    /// you actually came to find out.
    ///
    /// Returns the groups unchanged (and `moment: false`) whenever the split
    /// would be degenerate — no away window, nothing new, or EVERYTHING new —
    /// which is `boundaryID`'s own rule: a divider at the very top or the very
    /// bottom marks nothing.
    ///
    /// Order carries the partition: groups are newest-first and so are the rows
    /// inside them, so the fresh side is a prefix and one pass splits it. A
    /// FOLD spanning the boundary lands whole on the fresh side, since a bundle
    /// dates itself by its newest member — the same place the inline divider
    /// has always put it, so nothing moves that wasn't already there.
    private func momentSplit(_ groups: [(String, [FeedRow])])
        -> (groups: [(String, [FeedRow])], moment: Bool) {
        guard let since = newSince,
              let first = groups.first?.1.first, first.date > since
        else { return (groups, false) }
        var fresh: [FeedRow] = []
        var rest: [(String, [FeedRow])] = []
        for (label, rows) in groups {
            let new = rows.prefix { $0.date > since }
            let old = rows.dropFirst(new.count)
            fresh.append(contentsOf: new)
            guard !old.isEmpty else { continue }
            // A day the boundary cut through keeps its rows under a name that
            // says so. Only the CUT day is renamed — an untouched Today (the
            // boundary fell yesterday) is still just Today.
            let cut = !new.isEmpty && label == String(localized: "Today")
            rest.append((cut ? String(localized: "Earlier today") : label, Array(old)))
        }
        guard !fresh.isEmpty, !rest.isEmpty else { return (groups, false) }
        return ([(Self.momentLabel, fresh)] + rest, true)
    }

    /// The away section's name. A constant so the header's whisper gate and
    /// the seam can both ask for it by identity rather than re-localizing a
    /// literal and hoping the two strings match.
    private static var momentLabel: String { String(localized: "Since you left") }

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
            // §483 — the wallet room publishes which readings it HAS, and the
            // shell-mounted toggle consumes them. `initial: true` because a
            // room that never changes after mount (a wallet whose live state
            // was already loaded) would otherwise publish nothing and draw no
            // control at all.
            .onChange(of: walletSectionPublication, initial: true) { _, now in
                chrome.walletSections = now.sections
                chrome.walletSectionAttention = now.attention
            }
            // Cleared on the way OUT, not merely overwritten on the way in.
            // Every room writes this, so a stale non-empty list would leave the
            // toggle drawn over whichever room you moved to — and because the
            // list is also the control's own gate, clearing it is what makes
            // "the toggle cannot appear over a Vibenet room" true by
            // construction rather than by a source test in two files.
            .onDisappear {
                guard shape == .wallet else { return }
                chrome.walletSections = []
                chrome.walletSectionAttention = []
            }
            // §482 — the same contract for the vibenet room. `initial: true`
            // for the same reason: a room whose read had already landed before
            // mount would otherwise publish nothing and draw no control.
            .onChange(of: vibenetSectionPublication, initial: true) { _, now in
                chrome.vibenetSections = now.sections
                chrome.vibenetSectionAttention = now.attention
            }
            .onDisappear {
                guard shape == .vibenet else { return }
                chrome.vibenetSections = []
                chrome.vibenetSectionAttention = []
            }
    }

    /// Every token the treemap maps, as rows (prd §483).
    ///
    /// **The half this scope never had.** The room has drawn a holdings BOARD
    /// since §158 and never a list, because the board was the only holdings
    /// object in a room of cards and had to answer everything. Under §483 each
    /// scope is one drawing and one list, and this is the list — the board
    /// keeps the shape of the thing, these say what is in it.
    ///
    /// It reads the SAME `portfolio.positions` the treemap does rather than
    /// re-deriving, so a cell and its row can never disagree about a number,
    /// and it costs no read: the portfolio is already in hand for the crown.
    ///
    /// **`UnitTreemap` caps at six cells**, so on a wallet holding more than
    /// that the board has always been a partial answer with nothing saying so.
    /// The list is where the rest live, which is the other reason it belongs
    /// here rather than behind a door.
    @ViewBuilder
    private var walletTokenListSection: some View {
        if let portfolio, !portfolio.isEmpty {
            Section {
                ForEach(portfolio.positions) { position in
                    Button {
                        // The cell's own door, at row scale — a token's chart
                        // when it is watched, the quick sheet when it is only
                        // held (the 2026-07-14 split, unchanged).
                        if let route = position.route,
                           let r = TokenQuickRoute.from(sentinel: "@token:\(route):\(position.symbol)") {
                            if let thing = r.watchedThing(in: modelContext) {
                                openThing(thing)
                            } else {
                                feedSheet = .token(r.withHolders(position.holders))
                            }
                        }
                    } label: {
                        HStack(spacing: DS.Space.s3) {
                            TokenIcon(symbol: position.symbol, size: DS.Face.list)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(position.symbol)
                                    .dsText(.body17).foregroundStyle(DS.textPrimary)
                                    .lineLimit(1)
                                // Whose it is, only where that is a real
                                // question — one watched wallet has no split to
                                // report and the line would be noise (§212's
                                // own guard, one level down).
                                if position.holders.count > 1 {
                                    Text(position.holders.prefix(2)
                                            .map(\.label).joined(separator: " · "))
                                        .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer(minLength: DS.Space.s2)
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(WalletValue.money(position.usd))
                                    .dsText(.body17).foregroundStyle(DS.textPrimary)
                                    .monospacedDigit()
                                // Its share of everything — the one fact the
                                // board states that a bare amount does not, and
                                // the reason someone opens this scope at all.
                                if portfolio.totalUSD > 0 {
                                    // Whole percents: a holdings share is read
                                    // to compare, not to reconcile, and "56%"
                                    // beside "55.7%" is precision nobody asked
                                    // for on a figure that moves hourly.
                                    Text("\(Int((position.usd / portfolio.totalUSD * 100).rounded()))%")
                                        .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                                        .monospacedDigit()
                                }
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RowPress())
                    .dsHover()
                    .listRowInsets(EdgeInsets(top: DS.Space.s2, leading: DS.Space.s4,
                                              bottom: DS.Space.s2, trailing: DS.Space.s4))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
        }
    }

    /// The one drawing this scope leads with, above the toggle (prd §483).
    ///
    /// **The rule, in the user's own words: "above the toggles is always a
    /// visual of some kind and then a list below it".** Home's visual is the
    /// sparkline, drawn by the crown itself, so this returns nothing there —
    /// the slot is already filled rather than empty.
    ///
    /// Two scopes have no drawing yet and say so by drawing nothing rather than
    /// by inventing one: `nfts`, whose grid IS its picture and belongs with its
    /// rows, and `permissions`, whose exposure card is one object carrying both
    /// halves. Splitting those is worth doing deliberately, not as a side
    /// effect of a layout pass.
    @ViewBuilder
    private func walletScopeVisualSection(_ section: WalletSection) -> some View {
        switch section {
        // Home's drawing is the sparkline, which the crown draws itself — so
        // this slot is already filled there rather than empty.
        case .home:        EmptyView()
        case .activity:    walletFlowSection
        case .holdings:    holdingsBlockSection
        case .positions:   walletCompositionSection
        // **THE RANKED BARS LEAD, NOT "Worth a look"** (prd §483, 2026-08-26).
        // The warnings row is a ROW — one line with a chevron — so in a 210pt
        // slot it drew a sentence and 180pt of nothing, while the one drawing
        // this scope has sat below it in the list. They swap: the bars head
        // the scope, the row keeps its place at the top of the list where a
        // door belongs.
        case .risk:        walletRiskSection
        case .nfts:        walletNFTSection
        case .permissions: walletPermissionsSection
        }
    }

    /// What the crown gives back when it stops drawing the line.
    ///
    /// **THE TOGGLE MUST NOT MOVE BETWEEN SCOPES** (user ruling, prd §483: *"when
    /// toggling between home activity etc, the bar SHOULD NOT MOVE"*). A control
    /// that jumps as you use it is one you stop aiming at — and it jumped by
    /// construction, because Home's crown carries a 96pt chart plus its range
    /// chips while every other scope's crown carries neither.
    ///
    /// So the non-Home crowns reserve exactly what Home's chart and chips
    /// occupy, and the scope's own drawing sits in that reserved space. The
    /// number is spelled here rather than measured, because measuring it would
    /// mean the bar settles a frame LATE — which is the same jump, arriving
    /// slower.
    private static var walletVisualSlot: CGFloat { DSRoomChassis.visualSlot }

    /// How many moves Home shows. Three, matching Wallet's own crown rows:
    /// enough to say what just happened, few enough that the scope stays one
    /// drawing and one short list rather than becoming the stream twice.
    private static let vibenetHomeRows = 3

    /// The wallet scope rail — the Address Book door, "All", and a face per
    /// watched wallet — drawn in the room's own content directly under the
    /// sparkline (prd §483, 2026-08-26, user: *"i now think these avatars and
    /// address book should go BELOW the sparkline"*, and *"the toggles need to
    /// go immediately below them"*).
    ///
    /// **It was pinned in `MainSurface.roomControls` until this.** That is what
    /// made the room four strips of chips deep before any content — source
    /// chips, venue rail, this, then the scope toggle — and pushed the crown to
    /// about 45% down the screen. Both this and the toggle come down; the crown
    /// and its chart are what the room opens with.
    ///
    /// **Derived from the FULL watch list, never from the scoped room.** The
    /// trap, paid for in Vibenet the same afternoon: derive the items from the
    /// scoped room and picking a face collapses the strip to one item, the
    /// `shows(…)` gate then hides it, and the control deletes itself the moment
    /// it is used — with no way back to the other wallets.
    // MARK: - Hegotá's three room sections

    @ViewBuilder private var hegotaVisualSection: some View {
        if let head = HegotaRoomSource.compose() {
            Section {
                HegotaRoomFigure(head: head,
                                 accounts: HegotaRoomSource.accounts(),
                                 scoped: chrome.hegotaScope,
                                 section: HegotaSection.resolve(chrome.hegotaSection,
                                                                present: chrome.hegotaSections))
                    // **The chassis inset, NOT full bleed.** `DSRoomSlot` adds
                    // its own `contentInset` (12pt) and nothing else, so a
                    // full-bleed row put every figure at 12pt while the toggle
                    // bar below it sits at 20 — the drawing was wider than the
                    // control that scopes it, which is the one thing Wallet's
                    // room never does. Matching the switcher's inset lands the
                    // figure INSIDE the bar, the way Wallet's chart sits inside
                    // its own.
                    .listRowInsets(EdgeInsets(top: 0, leading: DSRoomChassis.inset,
                                              bottom: 0, trailing: DSRoomChassis.inset))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
    }

    /// FULL BLEED (`leading: 0`), Wallet's own inset for this rail: it scrolls
    /// horizontally, so an inset would stop the faces reaching the edge.
    @ViewBuilder private var hegotaRailSection: some View {
        if HegotaScopeRail.shows(source: source,
                                 watched: HegotaRoomSource.accounts().count) {
            Section {
                FaceScopeRail(
                    items: HegotaScopeRail.items(HegotaRoomSource.accounts().map(\.address)),
                    scope: chrome.hegotaScope,
                    compact: false,
                    matches: HegotaScopeRail.matches,
                    onPick: { picked in
                        withAnimation(DS.Motion.standard) {
                            chrome.hegotaScope = (picked?.isEmpty ?? true) ? nil : picked
                        }
                    })
                    .listRowInsets(EdgeInsets(top: 0, leading: 0,
                                              bottom: DSRoomChassis.switcherGap,
                                              trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
    }

    @ViewBuilder private var hegotaSwitcherSection: some View {
        if HegotaSection.shows(present: chrome.hegotaSections) {
            Section {
                DSSectionSwitcher(
                    sections: chrome.hegotaSections,
                    active: HegotaSection.resolve(chrome.hegotaSection,
                                                  present: chrome.hegotaSections),
                    attention: HegotaSection.attention()) { picked in
                        chrome.hegotaSection = picked
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: DSRoomChassis.inset,
                                              bottom: DSRoomChassis.contentGap,
                                              trailing: DSRoomChassis.inset))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
    }

    @ViewBuilder
    private var walletScopeRailSection: some View {
        if WalletScopeRail.shows(source: source, watched: wallet.addresses.count) {
            Section {
                FaceScopeRail(
                    items: WalletScopeRail.items(wallet.addresses),
                    scope: chrome.walletScope,
                    // Never folded now: `compact` existed for a pinned strip
                    // that had to yield height to the content scrolling under
                    // it. In the content there is nothing to yield to.
                    compact: false,
                    // **NAMES ARE BACK (prd §483 — amends §450).** That ruling
                    // dropped the rail's captions on the strength of the crown
                    // card naming the pick one row down. Two things since have
                    // taken that away: the caption itself is gone (it read
                    // "Across your accounts", which the lit "All" already said),
                    // and the face stopped carrying identity at all — it is one
                    // uniform person mark now, tinted only weakly. Five
                    // identical glyphs with nothing under them is not a roster.
                    //
                    // Which is the trade §483 made deliberately, not a
                    // regression: identity moved from a colour you had to learn
                    // to a WORD you can read. The caption is where it lives now,
                    // so it has to be drawn.
                    namesInRoom: false,
                    matches: WalletScopeRail.matches,
                    onPick: { picked in
                        withAnimation(DS.Motion.standard) { chrome.walletScope = picked }
                    },
                    // No re-tap verb: there is no "deeper" a watched address
                    // goes that the room you are already in does not show.
                    onReTap: nil,
                    // ONE slot, not two (prd §466) — watching another wallet
                    // and seeing the roster are the same screen, so an ADD slot
                    // would point at the book door beside it.
                    addTitle: nil,
                    onAdd: nil,
                    bookTitle: String(localized: "Address Book"),
                    onOpenBook: { route.push(.addressBook) })
                    // `DSRoomChassis`, which Vibenet reads too — see that
                    // type for why these gaps stopped being two hand-tuned
                    // stacks.
                    .listRowInsets(EdgeInsets(top: 0, leading: 0,
                                              bottom: DSRoomChassis.switcherGap,
                                              trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
    }

    /// The composition strip, lifted OUT of the crown card and into the
    /// `Positions` scope (prd §483, 2026-08-26).
    ///
    /// It sat in the crown until the toggle moved below the sparkline: with the
    /// control under the chart, anything else still in that card would sit
    /// between the sparkline and the toggle the user asked to put directly
    /// beneath it. And it belongs here anyway — it is the SUMMARY of exactly
    /// what this scope holds, which is the room's own rule that a scope leads
    /// with the drawing that summarizes its own rows.
    ///
    /// §240's "inside the balance card rather than a card of its own" is the
    /// ruling this amends: that reasoning was that "what's it worth" is one
    /// glance and this is the rest of that glance's answer. Still true — the
    /// crown is one tap away in every scope, and the figure it summarizes is
    /// still directly above it on the Positions scope itself.
    @ViewBuilder
    private var walletCompositionSection: some View {
        let composition = walletComposition
        if !composition.isEmpty {
                            WalletCompositionStrip(
                    composition: composition,
                    onOpenDeposits: { feedSheet = .deposits(composition) },
                    // Owed gets no door on purpose — the Lending card below
                    // already states health per protocol.
                    onOpenLocks: { feedSheet = .locks(composition) })
                    // BARE ON THE PAGE (user ruling, prd §483: *"we don't do
                    // cards"*). A scope's lead drawing sits in the visual slot
                    // exactly as the sparkline, the treemap and the flow band
                    // do — a tinted plate under one of four otherwise
                    // identical slots reads as that scope being a different
                    // kind of thing, which it is not.
                    .padding(.bottom, DS.Space.s3)
        }
    }

    /// The Worth-a-look strip, lifted out of the crown card into the `Risk`
    /// scope for the same reason (prd §483) — and it is what that scope is
    /// FOR, so it heads it rather than trailing the leverage axis.
    @ViewBuilder
    private var walletWarningsSection: some View {
        let warnings = walletLive.warnings
        if !warnings.isEmpty {
            Section {
                WalletWarningsStrip(warnings: warnings) { feedSheet = .worthALook }
                    // Bare, for `walletCompositionSection`'s reason.
                    .padding(.bottom, DS.Space.s3)
                    .listRowInsets(WalletCardStyle.rowInsets)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
    }

    /// The scope toggle, drawn in the room's own content directly under the
    /// crown and its chart (prd §483).
    ///
    /// Still reads `chrome.walletSections` rather than deriving presence here:
    /// the publication is one value computed once per pass, and re-deriving it
    /// at the draw site is how the strip and the sections it scopes come to
    /// disagree about which scopes exist.
    @ViewBuilder
    private func walletSectionSwitcherSection(_ active: WalletSection) -> some View {
        if WalletSection.shows(present: chrome.walletSections) {
            // **PINNING WAS TRIED HERE AND DOES NOT WORK AS A HEADER**
            // (prd §495, 2026-08-27).
            //
            // The strip scrolls away with the crown — measured, entirely off
            // screen — so the control that scopes the room cannot be reached
            // from inside the room it scopes. `.plain` pins section headers,
            // so `Section { EmptyView() } header: { switcher }` looked like
            // the fix that costs no height at rest and therefore does not
            // re-open §483 (which ruled this control OUT of `roomControls`,
            // where pinning it makes a fourth row of chips and pushes the
            // crown to 45% down the screen).
            //
            // It does not pin: a header only stays while its own section has
            // ROWS on screen, and this section has none, so the header leaves
            // with them. Verified on the device, not reasoned about.
            //
            // Pinning properly means making the switcher the header of the
            // section that carries the SCOPE'S CONTENT — which differs per
            // scope across a dozen section builders — so it is a real
            // refactor and its own ruling, not a line here. What ships
            // instead is §495's return-to-head on a scope change, which
            // removes the JUMP (the reported defect) without pretending to
            // fix the reachability.
            Section {
                DSSectionSwitcher(
                    sections: chrome.walletSections,
                    active: active,
                    attention: chrome.walletSectionAttention) { picked in
                        // Instant, for the reason vibenet's own pick states
                        // at length (prd §495): animating a swap between two
                        // slots of different natural height moves everything
                        // below the bar and settles it back.
                        chrome.walletSection = picked
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: DSRoomChassis.inset,
                                              bottom: DSRoomChassis.contentGap,
                                              trailing: DSRoomChassis.inset))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
    }

    /// What this room publishes to the shell for §483's toggle — the scopes
    /// that have something, and which of them want you.
    ///
    /// One value rather than two so a single `onChange` carries both; they are
    /// read from the same live state on the same pass and must never be
    /// published a frame apart, or the strip draws a dot on a scope it has
    /// already stopped listing.
    private var walletSectionPublication: WalletSectionPublication {
        guard shape == .wallet else { return .init(sections: [], attention: []) }
        // **EVERY FLAG IS THE SECTION'S OWN RENDER GATE, SPELLED THE SAME WAY.**
        // Reported from the device as "we can't do this", with a screenshot of
        // the Risk chip selected over an empty page. `risk` was flagged on
        // `walletRiskEntries != nil` while `walletRiskSection` draws on
        // `if let entries` AND needs them to be non-empty to draw anything —
        // so a non-nil empty strip offered a chip that opened nothing.
        //
        // The class matters more than the instance: presence and rendering are
        // two expressions of one question, in two files, and when they drift
        // the result is a control that leads somewhere blank — §83's dead
        // control wearing a scope's clothes. `positions` had the same shape
        // (it duplicated `hasLendingCard`'s two terms rather than reading it),
        // so it now reads the gates themselves. If a section's gate changes,
        // this must change with it — `wallet-section-selftest.sh` guards that
        // both spellings stay identical.
        let sections = WalletSection.present(
            holdings: !blockStream.els.isEmpty,
            positions: hasLendingCard
                || !walletLive.uniswap.isEmpty
                || !walletLive.hyperliquid.positions.isEmpty,
            nfts: nftShelfEntry != nil,
            risk: !(walletRiskEntries ?? []).isEmpty,
            // NOT `!exposure.isEmpty` any more (prd §490): the scope now draws
            // for a wallet with no token grant at all but a Safe module or a
            // 7702 delegate acting on it. Spelled as the section's OWN gate so
            // the two cannot drift — the failure that gave §483 its rule was a
            // chip that opened a blank page.
            permissions: !WalletPermissionsSource.holders(exposure: walletLive.exposure,
                                                          acting: walletLive.acting).isEmpty)
        // **`warnings`, not "does Risk exist".** A wallet with a 3.0 health
        // factor HAS a risk reading and is in no trouble at all, so lighting
        // the dot on presence would be the §83 overclaim that got "Needs
        // attention" retired on 2026-07-23 — "we don't know if it needs
        // attention, do we?". `walletLive.warnings` is the set the room already
        // computes for the Worth-a-look strip: something really is wrong.
        //
        // `.permissions` deliberately takes NO dot yet. The honest test is an
        // UNLIMITED allowance against a token you actually hold, which
        // `WalletApprovalExposure` can answer — but choosing the threshold is a
        // ruling, not a chassis change, and a dot that fires on every approval
        // ever granted would train you to ignore the one that matters.
        let attention: Set<WalletSection> =
            walletLive.warnings.isEmpty || !sections.contains(.risk) ? [] : [.risk]
        return .init(sections: sections, attention: attention)
    }

    struct WalletSectionPublication: Equatable {
        var sections: [WalletSection]
        var attention: Set<WalletSection>
    }

    /// What the vibenet room publishes to the shell for §482's toggle — the
    /// scopes that have something, and which of them want you.
    ///
    /// Guarded on `shape` for the same reason Wallet's is: this computed
    /// property is read by a room that may not be vibenet, and an unguarded
    /// version would publish a vibenet strip over whatever room is on screen.
    private var vibenetSectionPublication: VibenetSectionPublication {
        guard shape == .vibenet, let room = VibenetRoomSource.card() else {
            return .init(sections: [], attention: [])
        }
        // `hasEvents` is asked of the ROWS rather than of the room, because
        // "Recent" is the only scope whose content is not the card's: an
        // account watched today has a full roster and no events at all, and a
        // chip opening an empty day list is the dead control §83 bans.
        let sections = VibenetSection.present(room, hasEvents: !visible.live.isEmpty)
        // The dots are `VibenetAttention`'s ranking, one layer down — the same
        // set that used to draw the strip. **Not presence**: a room HAS keys
        // and HAS accounts at all times, so lighting on presence would be the
        // §83 overclaim that retired "Needs attention" (the wallet room's own
        // `warnings`-not-presence rule, arrived at independently). A key only
        // lights Keys inside its urgency window, and an account only lights
        // Accounts when it is locked, unlocking or unread.
        return .init(sections: sections, attention: VibenetSection.attention(room))
    }

    /// Whether the vibenet room is currently drawing its event rows — true for
    /// every other room, so this reads as a plain pass-through everywhere it is
    /// not vibenet. One derivation, so the footer and the rows can never
    /// disagree about whether there is a list to be at the bottom of.
    private var vibenetShowsRows: Bool {
        guard shape == .vibenet else { return true }
        let scopes = vibenetSectionPublication.sections
        return !VibenetSection.shows(present: scopes)
            || VibenetSection.resolve(chrome.vibenetSection, present: scopes) == .activity
    }

    /// Which of the Privacy Pools room's three readings have anything to show
    /// (prd §486).
    ///
    /// **EVERY FLAG IS THE SCOPE'S OWN RENDER GATE, SPELLED THE SAME WAY** —
    /// §483's lesson, learned there from a Risk chip that opened an empty page.
    /// `shielded` is exactly the test `PrivacyPoolsRoomCard.shieldedHasContent`
    /// makes, and `review` exactly the one `reviewHasContent` makes; the card
    /// draws the untagged deposits as a legend row of their own, which is why
    /// a room with no state tags at all still earns that scope.
    ///
    /// Derived here rather than published to the shell like Wallet's and
    /// Vibenet's, because the CARD draws this strip: there is no shell-mounted
    /// control to feed, so a published list would be state nothing reads.
    private func privacyPoolsSections(_ room: PrivacyPoolsRoom) -> [PrivacyPoolsSection] {
        PrivacyPoolsSection.present(shielded: !room.holdings.isEmpty,
                                    review: !room.segments.isEmpty || room.untagged > 0)
    }

    /// Whether the Privacy Pools room's rows draw — `vibenetShowsRows`'s shape,
    /// and true for every other room the `.ledger` shape serves.
    ///
    /// Railgun shares that shape and has no scopes, so it must never be gated
    /// by one; the source test is what keeps this room's control from reaching
    /// into its neighbour's room. Recomposing the room here is the same read
    /// the head above already makes on this pass — `PrivacyPoolsRoomSource`
    /// composes from `visible` and touches nothing else — and deriving it is
    /// what keeps the gate and the strip from describing different rooms.
    private func privacyPoolsShowsRows(_ visible: [Thing]) -> Bool {
        guard source == PrivacyPoolsRoomSource.source,
              let room = PrivacyPoolsRoomSource.compose(things: visible) else { return true }
        let scopes = privacyPoolsSections(room)
        return !PrivacyPoolsSection.shows(present: scopes)
            || PrivacyPoolsSection.resolve(chrome.privacyPoolsSection, present: scopes) == .activity
    }

    struct VibenetSectionPublication: Equatable {
        var sections: [VibenetSection]
        var attention: Set<VibenetSection>
    }

    /// A source room's COMPOSE action — "New event", "New email", "New task" —
    /// and the only survivor of the header capsule this replaced (prd §359,
    /// 2026-08-11, user: "remove that header capsule", answering their own
    /// "should we get rid of all these and user just go to the app catalogue to
    /// manage?").
    ///
    /// **Why the capsule went.** It carried the source's NAME, its status, and a
    /// Manage door, and by this date all three were said better elsewhere. The
    /// name was the third naming of the same room on one screen (the category
    /// chip, the switcher's mark, then this); status has its own home in the
    /// strip, where a broken seat lights the category chip's dashed attention
    /// ring (§351) whether or not you are standing in that room; and managing a
    /// source is the app catalogue's whole job, reachable from the fixed
    /// catalogue door at the head of the strip on every screen. A capsule that
    /// repeats two things and duplicates a third is chrome.
    ///
    /// **Why compose did NOT go with it.** It is a different verb: Manage opens
    /// something inside this app, compose LEAVES for another one — a genuinely
    /// other place the catalogue is not a door to (the 2026-07-14 ruling that
    /// made it a distinct control beside the capsule rather than folded into
    /// it). Read-only sources never had one, so most rooms simply have no row
    /// here at all now.
    ///
    /// The "+" add-another hint went with the capsule and is NOT rehomed: it
    /// opened the same setup screen the catalogue opens, and in the one room
    /// where adding is a frequent verb the wallet face rail already carries it
    /// (§357).
    private func sourceComposeRow(_ action: SourceAction) -> some View {
        HStack(spacing: DS.Space.s2) {
            Button {
                DSHaptic.selection()
                if case .openURL(let url) = action.run { openExternal(url) }
            } label: {
                HStack(spacing: DS.Space.s1) {
                    Image(systemName: "plus").dsGlyph(13)
                        .accessibilityHidden(true)
                    Text(LocalizedStringKey(action.label))
                        .dsText(.subhead13).fontWeight(.medium)
                }
                .foregroundStyle(DS.tint)
                .padding(.horizontal, DS.Space.s3)
                .frame(minHeight: 30)
                .background(DS.surfaceSheet, in: Capsule(style: .continuous))
                .contentShape(Capsule())
            }
            .buttonStyle(PressSpring())
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Space.s4)
        // The capsule's own generous top gap (2026-07-14: s3 read as still
        // touching the chip row), kept — this row sits in the same place under
        // the same strip.
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

    /// What each `FeedSheetRoute` presents.
    ///
    /// Extracted from the `.sheet(item:)` closure for `roomHead`'s reason
    /// (below): the switch is one expression over a dozen cases, and adding a
    /// single argument to one of its calls put it over the type-checker's
    /// budget. Behaviour is unchanged — this is still the ONE presentation
    /// this screen makes (see `FeedSheetRoute`'s doc for why five separate
    /// `.sheet` modifiers made the first tap self-dismiss).
    @ViewBuilder
    private func sheetContent(_ route: FeedSheetRoute) -> some View {
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
            // The two walk doors (prd §449). Each is handed over ONLY
            // when its card is really on screen — the sheet falls back to
            // enumerating that group itself otherwise, so a pill can
            // never point at a card this room isn't drawing (§83's dead
            // control, and the same nil-able shape
            // `WalletCompositionStrip` keeps for Deposited and Locked).
            //
            // Dismiss and scroll are set TOGETHER on purpose: `scrollTo`
            // animates over ~0.3s and the sheet's dismissal over ~0.35s,
            // so the card is already centred as the sheet clears — the
            // room moving to meet you rather than a jump you arrive to.
            WalletWorthALookTray(
                warnings: walletLive.warnings,
                flagged: walletLive.flagged,
                activeApprovals: walletLive.activeApprovals,
                exposure: walletLive.exposure,
                onWalkToApprovals: walletLive.exposure.isEmpty ? nil : {
                    feedSheet = nil
                    cardScrollTarget = Self.approvalsAnchor
                },
                onWalkToLending: hasLendingCard ? {
                    feedSheet = nil
                    cardScrollTarget = Self.lendingAnchor
                } : nil)
        case .deposits(let composition):
            WalletDepositsTray(composition: composition)
        case .locks(let composition):
            WalletLocksTray(composition: composition)
        case .market(let preview):
            PredictionPreviewSheet(preview: preview)
        case .hegotaMove(let move, let owner):
            HegotaMoveSheet(move: move, owner: owner,
                            watched: HegotaRoomSource.accounts().map(\.address)) { index in
                // Frame-to-frame through the ONE sheet: replacing the route
                // swaps the tray's content in place, so the frame rises where
                // the move was rather than as a second sheet over it.
                feedSheet = .hegotaFrame(move, index)
            }
        case .hegotaFrame(let move, let index):
            HegotaFrameSheet(move: move, index: index,
                             watched: HegotaRoomSource.accounts().map(\.address))
        case .hegotaAccount(let account):
            HegotaAccountSheet(account: account) { section in
                // The sheet's facts are doors: scope the room to this account
                // and open the list the fact names.
                chrome.hegotaScope = account.address
                chrome.hegotaSection = section
                feedSheet = nil
            }
        case .hegotaCoin(let coin, let all, let unspent):
            HegotaCoinSheet(coin: coin, all: all, unspent: unspent)
        case .nftPicks(let address, let label):
            WalletNFTPickerSheet(wallet: address, label: label)
        case .person(let source, let handle):
            NavigationStack {
                PersonRoomScreen(profile: SocialProfile(
                    source: source, handle: handle,
                    displayName: nil, bio: nil, avatarURL: nil))
            }
        case .vibenetKeys(let items, let newKeyIDs):
            // A tapped key SCOPES THE ROOM to its account (prd §470),
            // which is the follow-up the tray previously dead-ended on.
            //
            // DISMISS FIRST, THEN SCOPE — the order matters and is the
            // same one `RoomDoor` spells out for its own pop-then-ask
            // move: `vibenetScope` re-composes the room BEHIND this
            // sheet, and asking for that while the sheet is still up
            // means the change lands under a covered screen. Setting
            // `feedSheet = nil` here is the whole dismissal, since this
            // screen owns the presentation.
            //
            // No animation on the scope write, deliberately: the room is
            // behind a dismissing sheet, so an animation animates
            // something nobody can see and lands mid-transition.
            VibenetKeyTraySheet(items: items,
                                onPick: { address in
                                    feedSheet = nil
                                    chrome.vibenetScope = address
                                },
                                // The same new-key set the room card read and
                                // spent, so a key marked "New" on the card's
                                // own detail is marked here too (prd §479).
                                newKeyIDs: newKeyIDs)
        case .vibenetKey(let actor, let item, let shared):
            VibenetKeySheet(actor: actor, item: item, sharedKeys: shared)
        }
    }

    /// Everything the room draws ABOVE its rows — the source chrome, the
    /// per-source heroes and heads, the ledes.
    ///
    /// Extracted for `populatedRoom`'s reason (see below), and it took three
    /// passes to find the real boundary: pulling out the day sections did not
    /// help, pulling out the whole content chain did not help, because the
    /// cost was never in one branch — `listBody`'s List is ONE expression and
    /// the solver closes it whole. Splitting it at its two natural halves,
    /// head and body, is what brought it back under budget.
    @ViewBuilder
    private var roomHead: some View {
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
            // The source header CAPSULE is gone (user ruling 2026-08-11,
            // §359) — managing a source happens in the app catalogue.
            // What survives is COMPOSE, and only because it is a different
            // verb: "New event" / "New task" leaves for another app, which
            // the catalogue is not a door to. See `sourceComposeRow`.
            if let bridge = activeSourceBridge,
               let action = SourceActions.action(forSource: bridge.name),
               case .openURL = action.run {
                sourceComposeRow(action)
            }
            // GitHub's source feed leads with its contribution graph (moved
            // off Home, 2026-07-18). Gated on the source STRING, not the
            // BridgeStore seat — the graph belongs to GitHub's token
            // (`GitHubGraphStore` self-fetches with it), so it rides the
            // GitHub feed whenever it's the filter; the hero self-checks for
            // a landed year and takes no room otherwise.
            // …and stands DOWN whenever the "needs you" head has something
            // to say (prd §401). Two leads is not a richer room, it is a
            // room with no lead: the heatmap answers "how much did I write
            // this year" and the head answers "what is waiting on you",
            // and only one of those is why you opened it. The heatmap
            // remains the lead on the quiet days, which is most of them,
            // and is why it was not simply deleted.
            if source == "GitHub", sourceHeadIsAbsent { githubGraphHero }
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
        // A NON-EMPTY debounced snapshot already proves the room has
        // content, so the query is never touched in the case that matters
        // (PERF 2026-08-11): `things` materialises its whole bounded fetch
        // in the getter, and this line ran on every body evaluation.
        //
        // Deliberately one-directional — a non-empty snapshot short-
        // circuits, an empty or absent one still asks `hasSurfaced`. The
        // snapshot is narrowed by the tag and wallet/person scopes and
        // `things` is not, so treating an EMPTY snapshot as an empty room
        // would put "Let's fill this feed" over a room that is merely
        // filtered. Same answer as before, in every case; the expensive
        // read just stops happening whenever there is anything to draw.
    }

    /// The room's own content: the empty state, the filtered-empty state, or
    /// the day sections. Extracted from `feedList` for `populatedRoom`'s
    /// reason (see just below) — pulling one branch out was not enough, since
    /// the cost is the whole chain rather than any one arm of it.
    @ViewBuilder
    private var roomBody: some View {
        let roomHasContent = (debouncedAllSnapshot.map { !$0.isEmpty } ?? false)
            || Corpus.hasSurfaced(things)
        if !roomHasContent && !LiveRoomSources.has(source) {
            Group { emptyState }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
        } else if source == HegotaIdentity.source, let head = HegotaRoomSource.compose() {
            // **A ROOM WITH LIVE CONTENT AND NO ROWS.** Without this branch the
            // `if/else if` above falls through BOTH arms and renders nothing at
            // all — a black screen, which is how the Hegotá room reached a
            // device four times.
            //
            // The gap is structural rather than an oversight: `LiveRoomSources`
            // exists so a room with live content skips the corpus-shaped empty
            // state, and until now its only members were Kalshi and Polymarket,
            // whose `predictionBook` draws from a separate path — so for them
            // the room is never really empty and the missing arm never showed.
            // Hegotá lands no `Thing` EVER, so its rows are always zero and its
            // entire content is this head.
            // **THREE SECTIONS, exactly as Wallet emits them** — figure, rail,
            // switcher — rather than one card holding all three. They are not
            // children of a card in this app; the rail is FULL BLEED so it can
            // scroll edge to edge, and the switcher takes the room's own inset.
            // Nested inside a card they inherited the card's padding instead,
            // which is what put this room's rails out of line with Wallet's.
            // The room publishes what it HAS, so the switcher never offers a
            // chip that opens nothing — derived from the composed room rather
            // than the watch list (the face rail's own rule).
            let _ = { chrome.hegotaSections = HegotaRoomSource.sections() }()
            hegotaVisualSection
            hegotaRailSection
            hegotaSwitcherSection
            Group {
                HegotaRoomList(head: head,
                               accounts: HegotaRoomSource.accounts(),
                               scoped: chrome.hegotaScope,
                               section: HegotaSection.resolve(chrome.hegotaSection,
                                                              present: chrome.hegotaSections)) { move, owner in
                    feedSheet = .hegotaMove(move, owner)
                } onOpenAccount: { account in
                    feedSheet = .hegotaAccount(account)
                } onOpenCoin: { coin, all, unspent in
                    feedSheet = .hegotaCoin(coin, all, unspent)
                }
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: DSRoomChassis.inset,
                                      bottom: DS.Space.s4, trailing: DSRoomChassis.inset))
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
                populatedRoom(visible)
            }
        }
    }

    /// The day sections of a room that has rows, plus its closing line.
    ///
    /// **EXTRACTED FROM `feedList` BECAUSE THE COMPILER ASKED (2026-08-25).**
    /// `feedList`'s `if/else` chain had been sitting at the edge of what the
    /// type-checker will solve, and it went over on a change that touched
    /// none of it: adding ONE stored property to `FeedScreen` produced
    /// "unable to type-check this expression in reasonable time" pointed six
    /// hundred lines away, deterministically, on three separate members
    /// tried. Measured against this tree — reverting the unrelated member
    /// builds, keeping it does not, whatever the member is. So the budget,
    /// not the member, was the defect, and this is the fix the error message
    /// names: pull a branch out into its own function so the solver has a
    /// smaller expression to close. Nothing about what is drawn changes.
    ///
    /// Takes `visible` rather than re-deriving it — that array is the
    /// Feed-freeze rule's one filter pass per render, and a second call here
    /// would be a second walk of the corpus on every body evaluation.
    @ViewBuilder
    private func populatedRoom(_ visible: [Thing]) -> some View {
                let nextID = nextEventID(visible)
                // The Themes treemap, ABOVE THE FOLD of the unfiltered All
                // room (prd §385) — called HERE, before `shapedSections`,
                // and not inside its `.all` branch where it lived from
                // 2026-07-18 to 2026-08-14: the shape chain draws its
                // heroes (a live stream above all) before the branch
                // runs, and the fold-settle scroll hides EVERYTHING above
                // `themesFoldAnchor` — a live hero must stay below the
                // anchor or going live would hide it. The condition is
                // the `.all` branch's own gate restated (kind-filtered
                // All and the pinned room take other branches, and
                // neither draws the map).
                // The themes lede LEFT the All feed (user ruling
                // 2026-08-14, prd §386a: "we could put the treemap of
                // themes here [the overview] and get rid of it on the all
                // page, i don't think it really works there") — hours
                // after §385 moved it above the fold, which is the
                // fastest a ruling here has ever been reversed by its own
                // author watching it. The treemap's one home is now the
                // Today overview's "What you're into" module, where it
                // sits beside the other aggregates instead of ahead of
                // the chronology it was interrupting.
                // `themesLedeSection` and the §385 fold machinery stay
                // compiled but unreached (dormant-not-deleted).
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
                // **A SCOPE WITH NO ROWS MUST NOT CLAIM TO BE CAUGHT UP
                // (prd §482).** "That's everything from Base Vibenet · 4
                // events" under a census of keys is a claim about a list that
                // is not on screen — the §83 fake status, and it shipped for
                // the length of one build because the footer's own gate knew
                // about rooms and not about scopes. Vibenet draws its rows in
                // `.recent` alone, so the line belongs there alone; Wallet
                // sidesteps the same problem by opting out of the footer
                // entirely one clause up.
                if shape != .reminders && shape != .wallet
                    && vibenetShowsRows
                    // The same gate for the Privacy Pools room's own scopes
                    // (prd §486), and for the same reason: "you're all caught
                    // up" under a Shielded card with no stream on screen is the
                    // §83 fake status the clause above it was added to end.
                    && privacyPoolsShowsRows(visible)
                    && !hidesPastEvents(visible) && !memo.windowHasMore {
                    caughtUpFooter(visible)
                }
    }

    /// reaches the All feed) only on an explicit Follow.
    @ViewBuilder private var predictionBook: some View {
        if LiveRoomSources.isPredictionVenue(source) {
            PredictionRoomBook(source: source) { feedSheet = .market($0) }
        }
    }

    // The folded-category venue switcher and the wallet face rail used to be
    // two `.safeAreaInset(edge: .top)` bars declared here. Both moved to
    // `MainSurface.roomControls` on 2026-08-11 (prd §357) — this screen carries
    // `.id(filter.source)` under a move transition, so chrome pinned to it was
    // destroyed and rebuilt on every move it made. See that property for the
    // three things that silently cost.

    private var feedList: some View {
        // ONE extra container on the launch path's deepest tree (see the 8MB
        // main-stack history before "improving" this) — accepted for §385:
        // the fold-settle scroll needs a `ScrollViewProxy` enclosing the
        // List, and this is the shallowest place one can live. Mac already
        // nests a second reader OUTSIDE for the keyboard walk; nested
        // readers are fine, `scrollTo` resolves inward.
        ScrollViewReader { proxy in
            listCore(proxy)
        }
    }

    private func listCore(_ proxy: ScrollViewProxy) -> some View {
        listBody(proxy)
            // The risk strip's walk-to-card (prd §417). Animated, unlike the
            // themes fold's settle above: that one is the room's resting
            // position and this is a MOVE somebody asked for, so it has to be
            // followable — landing instantly two screens down reads as the room
            // having jumped rather than as an answer to the tap. Reduce Motion
            // is honoured by `scrollTo`'s own transaction, which SwiftUI
            // disables under the setting.
            //
            // `.center`, not `.top`: the card is the answer, so it lands in the
            // middle of the screen with the strip that sent you still visible
            // above it — the connection is the point.
            .onChange(of: cardScrollTarget) { _, target in
                guard let target else { return }
                withAnimation(DS.Motion.standard) {
                    proxy.scrollTo(target, anchor: .center)
                }
                // Cleared so tapping the SAME dot twice moves twice — an
                // unchanged binding would fire `onChange` once and then look
                // broken on every later tap.
                cardScrollTarget = nil
            }
            // **A SCOPE CHANGE RETURNS TO THE TOP** (prd §495, user: *"when
            // you click any of the button on the toggle bar the bar jumps. we
            // need it fixed in place"*).
            //
            // The strip is not pinned in either room — Wallet draws it as a
            // `List` section and vibenet inside its room card — so it scrolls
            // away with the crown, and measured on the device it goes ENTIRELY
            // off screen. What reads as a jump is the half-scrolled case: the
            // scope changes, the content below is a different height, the
            // scroll view clamps to the new extent, and everything shifts
            // under the finger that just tapped.
            //
            // Returning to the top removes the shift by removing the offset
            // there is to clamp — and it is the honest behaviour anyway, since
            // a preserved scroll position into DIFFERENT content is not the
            // place you were, it is a number that survived.
            //
            // **NOT the whole fix, and the difference is worth stating:** the
            // strip still scrolls away once you are reading, so it cannot be
            // tapped without scrolling back up. Pinning it into
            // `MainSurface.roomControls` — where `categorySwitcher` and
            // `socialScopeRail` already sit pinned — is the structural answer,
            // and it SUPERSEDES §357's placement for these two rooms rather
            // than extending it, so it wants its own ruling rather than a
            // quiet diff.
            .onChange(of: chrome.walletSection) { _, _ in returnToRoomTop(proxy) }
            .onChange(of: chrome.vibenetSection) { _, _ in returnToRoomTop(proxy) }
            // **AND ON AN ACCOUNT PICK** (prd §495, user: *"clicking on an
            // account in vibenet fucks up the screen… it makes the silhouette
            // and toggle bar jump to the top"*).
            //
            // Same defect as the scope chips and the same fix: narrowing the
            // room to one account replaces its whole content, the list's
            // extent changes under a scroll offset that no longer means
            // anything, and the scroll view clamps — which throws the rail and
            // the strip up the screen. The SCOPE chips were hooked here and
            // the FACE rail was not, because the first report named the chips.
            .onChange(of: chrome.walletScope) { _, _ in returnToRoomTop(proxy) }
            .onChange(of: chrome.vibenetScope) { _, _ in returnToRoomTop(proxy) }
    }

    /// The id the room's head carries, so a scope change can return to it.
    private static let roomTopAnchor = "roomTop"

    /// Scroll the room back to its own head, with the standard motion so it
    /// reads as the room resetting rather than as a jump of its own — which
    /// is the thing this exists to remove.
    private func returnToRoomTop(_ proxy: ScrollViewProxy) {
        withAnimation(DS.Motion.standard) {
            proxy.scrollTo(Self.roomTopAnchor, anchor: .top)
        }
    }

    private func listBody(_ proxy: ScrollViewProxy) -> some View {
        List {
            roomHead
                .id(Self.roomTopAnchor)
            roomBody

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
        // Width buys COLUMNS in a picture room and LINE LENGTH everywhere else
        // (2026-08-17). The 700pt reading cap is right for prose and wrong for
        // a grid: a Mac window at 1120 drew the same three-across grid it draws
        // at 700 and spent the rest on margin, so the one room type that can
        // actually use a big window was the one room type that didn't.
        //
        // Only the rooms whose lead is a GRID widen. A mixed room (Files,
        // Snapchat, Instagram, X) qualifies because its grid half is what sets
        // its width; its prose rows still wrap inside the same column, which is
        // the trade — a slightly long band row against a picture wall that
        // actually fills the window. Everything else keeps `.reading`, and no
        // paragraph in this app gets wider.
        .dsAdaptiveContentWidth(shape.widensForPictures ? .wide : .reading)
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
        // Keyed on `corpusRevision`, not `things.count` (2026-08-11) — see its
        // doc: the old key both materialised the query on every body pass and,
        // past the fetch bound, stopped changing at all.
        // `.idle` for every other room — the body's first line is a guard that
        // returns for them, and keying it on `things.count` there read a
        // source-filtered query that, unlike the All room's, carries no
        // `fetchLimit` at all: a bulk-imported room is thousands of rows,
        // materialised to key a task that does nothing.
        .task(id: corpusRevision) {
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
        // THE HEAD IS COMPUTED HERE, NOT IN THE BODY (PERF 2026-08-21).
        //
        // It used to be derived inline in `shapedSections`, which means once per
        // body evaluation, over the room's whole contents. A swipe is a remount
        // (§265's `.id(filter.source)`), so every room change paid that from
        // zero, several times, on the main actor, in the frames the slide
        // animation needed — the reported "lag swiping between screens".
        //
        // Seeded from the memo FIRST so a room you have visited paints its head
        // immediately: the recompute below then either agrees with it or
        // corrects it within the same frame batch, and a room you have never
        // visited simply has no head until it lands, which is the same nothing
        // a head that declines already draws.
        .task(id: headKey) {
            if heads == nil {
                heads = Self.headMemo[headIdentity]
                SwipeClock.mark("mount", detail: heads == nil ? "memo=miss" : "memo=hit")
            }
            // NEVER over a truncated room. `rowBudget` is the swipe's transient
            // bound (see `MainSurface.swipeRowBudget`) — a head composed from
            // the newest 150 rows and presented as the room's own reading is
            // the §83 fake status this file's 2026-08-14 note refuses a
            // permanent `fetchLimit` over. The budget clears within a few
            // hundred ms and `headKey` moves with it, so the real computation
            // follows on its own.
            guard rowBudget == nil else { return }
            recomputeHeads()
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
        // The swipe trace's closing bracket — the room's list is on screen, so
        // the materialisation its first content build needed has been paid.
        .onAppear { SwipeClock.finish() }
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
                || !wallet.addresses.contains(where: {
                    WalletWatch.sameAddress($0.address, sel)
                }) {
                selectedWallet = nil
            }
            if isActive { streamBlock(); loadWalletLive() }
        }
        // Scoping to a wallet (or back to All) re-paints the treemap/NFT strip
        // AND re-reads the live tiles for that scope; the rows and balance
        // re-derive from state.
        .onChange(of: chrome.walletScope) {
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
        // …asked for by the shell's face rail now (prd §362), which is where the
        // faces live since they became a filter. It hands the request down
        // rather than pushing itself, because THIS screen owns the destination:
        // routing it through `RootShell` instead would have presented
        // `SocialProfileCard` — the quick-glance tray — where the roster has
        // always pushed the fuller `PersonRoomScreen`, a silent downgrade of the
        // one door this change had to keep intact.
        .onChange(of: chrome.personRequest) { _, person in
            guard let person else { return }
            openPerson = person
            chrome.personRequest = nil
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
            sheetContent(route)
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
        let visible = roomScoped(allVisible)
        if shape == .x402 { x402LaneStrip }
        // ABOVE THE HEAD, deliberately (2026-08-23, prd §455). This is not a
        // reading about the room, it is a statement about whether the room is
        // COMPLETE — and every reading below it (a board ranking publishers, a
        // count of stories, a year grid) is computed over rows that a dead feed
        // stopped contributing to weeks ago. A correction printed under those
        // claims is a correction printed after the claim.
        feedHealthNote
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
        // ONE DISPATCH (2026-08-26, prd §489). This was a
        // `source == "Farcaster" ? … : BlueskyStore…` ternary, which is not a
        // lookup but a coin flip with two faces: any third network reaching it
        // would have been handed Bluesky's watched accounts. See
        // `SocialRoomSource.accounts(for:)`, which `MainSurface` now reads too,
        // so the rail above the room and the roster inside it can never name
        // two different sets of people.
        let rosterAccounts: [SocialAccount] = liveStream == nil
            ? SocialRoomSource.accounts(for: source)
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
        // Derived ONCE and shared with the grid below — the memories room asks
        // this set twice (which picture leads, and which rows are tiles) and
        // walking `visible` per question is the shape the 2026-07-13 feed
        // freeze was made of. Empty for every other room, so it costs nothing
        // there.
        let memoryTiles = shape == .snapchat ? visible.live.filter(Self.isMemoryTile) : []
        // THE ANNIVERSARY — a real thing from this exact day in an earlier year.
        //
        // It sits ABOVE `sourceHead` since 2026-08-17 (prd §398), which is a
        // promotion, and the reason is the one `OnThisDayHero`'s own doc has
        // always given: it is worth more than any STANDING fact the room can
        // state, and it is nil on nearly every day, so it takes the head rarely
        // rather than owning it. Until that pass nothing above it could claim
        // these rooms, so the rank was untested; the journal head landing the
        // same day is what made the order a real question, and a card about how
        // many years you have kept a journal must not cover what you wrote on
        // this date in one of them.
        //
        // SCOPED, and the scope is the whole safety of the promotion: this is
        // non-nil only for the memories room and the two journals, and neither
        // has an ALARM head. Widen it to a room whose head is a dispute
        // deadline or a Safe awaiting your signature and a nostalgia card would
        // cover something time-critical — so a new source belongs here only
        // after that question is asked about its head.
        let anniversary: OnThisDay.Echo? = liveStream == nil
            ? journalAnniversary(shape: shape, memoryTiles: memoryTiles, visible: visible)
            : nil
        // READ, NOT COMPUTED (PERF 2026-08-21). The five registry answers below
        // come from `heads`, filled by this screen's own `.task(id: headKey)`;
        // the GATES stay here, unchanged, because `liveStream` and `anniversary`
        // hold `Thing`s and so can never be cached — and because one place for
        // the ranking is the whole reason these were gathered into a chain of
        // re-stated conditions rather than five independent lets (2026-08-04).
        // A nil `heads` is a head that has not been computed yet and draws
        // exactly what a head that DECLINED draws.
        let sourceHead = liveStream == nil && anniversary == nil ? heads?.sourceHead : nil
        // (The All feed's cross-source "thread" head lived here for one day and
        // was DELETED, prd §333. It ranked a shared WORD as a subject, so its
        // headline read "Wallet" over a Files row, an x402 blurb containing
        // "wallet flow", and two of the person's own commit messages about
        // building the Apple Wallet bridge. That is the deterministic
        // co-occurrence card §36c already removed once for manufacturing
        // connections — see `HomeInsightStore`, whose doc says a real version
        // "would be a fresh build, not a revival of this." The All feed leads
        // with the themes treemap again, which claims only what it measures.)
        // The OCR/text treemap (2026-07-30) — what the screenshots are ABOUT,
        // and since 2026-07-31 what an Instagram export's own captions and
        // comments are about. When there's too little text to say anything it
        // returns nil and the next card down takes the head.
        let topicMap = liveStream == nil && sourceHead == nil && anniversary == nil && rosterAccounts.isEmpty
            ? heads?.topicMap : nil
        let leaderboard = liveStream == nil && sourceHead == nil && anniversary == nil && topicMap == nil && rosterAccounts.isEmpty
            ? heads?.leaderboard : nil
        let distribution = liveStream == nil && sourceHead == nil && anniversary == nil && topicMap == nil
            && leaderboard == nil && rosterAccounts.isEmpty
            ? heads?.distribution : nil
        let mosaic = liveStream == nil && sourceHead == nil && anniversary == nil && topicMap == nil
            && leaderboard == nil && distribution == nil && rosterAccounts.isEmpty
            ? heads?.mosaic : nil
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
                case .cardPointers(let room):
                    // No callback since §487: the head stopped naming a single
                    // offer, so it has nothing to open — every offer is its own
                    // row a scroll below, and each of those is its own door.
                    CardPointersRoomCard(room: room)
                case .walletbeat(let room):
                    WalletbeatRoomCard(room: room) { ref in
                        // The card names a real row's `sourceRef`, so this lands
                        // exactly — the card itself holds no `Thing` (corollary 5)
                        // and the lookup happens here, against the live corpus.
                        openBySourceRef(ref, in: visible)
                    } onBrowse: {
                        // Pushed, not raised: this is navigation to a place, not a
                        // connect act (§219 — Connect raises, Open pushes). Straight to
                        // the directory, never via the connect screen: §234's ruling is
                        // that a browse is mounted by the room, and routing through the
                        // setup screen made reading the list a trip into the catalog
                        // plus a second tap (prd §421).
                        route.path.append(.walletbeatDirectory)
                    }
                case .l2beat(let room):
                    L2beatRoomCard(room: room) { ref in
                        openBySourceRef(ref, in: visible)
                    } onBrowse: {
                        // Pushed, not raised (§219 — Connect raises, Open pushes), and
                        // straight to the directory rather than via the connect screen
                        // (§234 — a browse is mounted by the room).
                        route.path.append(.l2beatDirectory)
                    }
                case .github(let room):
                    GitHubRoomCard(room: room) { ref in
                        // The card names a real row, so this lands exactly —
                        // no "newest matching" hop is needed or wanted.
                        openNewest(source: GitHubRoomSource.source, in: visible) { thing in
                            thing.sourceRef == ref
                        }
                    }
                case .radicle(let room):
                    RadicleRoomCard(room: room) { rid, id, kind in
                        // This head reads STATE, so the item it names may have
                        // no landed row at all — an issue opened before you
                        // started watching is in the store's open list and was
                        // never landed as news. So the landing is the row when
                        // one exists, and nothing when it doesn't, rather than
                        // a guess at a neighbouring row.
                        let ref = "radicle:\(kind.rawValue):\(rid):\(id):opened"
                        openNewest(source: RadicleRoomSource.source, in: visible) { thing in
                            thing.sourceRef == ref
                        }
                    }
                case .peer(let room):
                    PeerRoomCard(room: room) { rail in
                        // A rail owns many fills, so the honest landing is its
                        // most recent one, matched on the funding rail §311
                        // stamps on `authorHandle` (the Cursor repo rule).
                        openNewest(source: PeerRoomSource.source, in: visible) { thing in
                            thing.authorHandle == rail.name
                        }
                    }
                case .vibenet(let room):
                    // The same card the setup screen draws. `onRemove` AND
                    // `onRename` are deliberately inert here (their default
                    // no-op): unwatching and naming are both setup acts,
                    // and a destructive or state-changing verb reached from
                    // a feed row it would silently re-compose behind is the
                    // wrong place for either — the setup screen still
                    // carries them. `onOpen` is left NIL here (2026-08-24,
                    // corrected — see `VibenetRoomCard`'s own header doc):
                    // Wallet's own unscoped room has no per-wallet door
                    // anywhere, only scoping, so a feed-room roster tap
                    // must only scope too, never open a sheet. Scoping
                    // itself is `VibenetScopeRail`'s alone (prd §469): the
                    // card's `onScope` closure was deleted after being found
                    // unreached — this call site passed a real closure into
                    // a prop nothing called — and the rail above the card
                    // already scopes every account with the toggle rule
                    // (tap the scoped account again to return to "All").
                    //
                    // `onOpenKeys` routes through THIS screen's single
                    // `.sheet` (prd §468) rather than being presented by the
                    // card: the card is inside this List's rows, and a
                    // `.sheet` there resolves to the same presenting
                    // controller — the half-open-then-close bug. It carries
                    // the ROOM's items, which are already scoped by the rail,
                    // so a tray opened from a scoped room lists that
                    // account's keys and a tray opened from All lists
                    // everyone's — the same "click all you see all" rule the
                    // cards above it follow.
                    // WHICH READING IS ON SCREEN (prd §482). Resolved rather
                    // than read raw: a scope remembered from a room whose
                    // last key has since been revoked falls back to Holdings
                    // instead of rendering an empty page claiming to be a
                    // section — `WalletSection.resolve`'s rule, one room over.
                    VibenetRoomCard(room: room, onRemove: { _ in },
                                    onOpenKeys: { newKeyIDs in
                                        feedSheet = .vibenetKeys(room.items, newKeyIDs: newKeyIDs)
                                    },
                                    onOpenKey: { actor, item, shared in
                                        feedSheet = .vibenetKey(actor, item, shared)
                                    },
                                    onScope: vibenetScoper,
                                    // WHICH READING IS ON SCREEN (prd §482).
                                    // Resolved rather than read raw: a scope
                                    // remembered from a room whose last key has
                                    // since been revoked falls back to Holdings
                                    // instead of rendering an empty page that
                                    // claims to be a section.
                                    section: VibenetSection.resolve(
                                        chrome.vibenetSection,
                                        present: vibenetSectionPublication.sections),
                                    // The strip is drawn by the CARD now, under
                                    // the crown (prd §482 amendment). Its inputs
                                    // are handed down rather than read from the
                                    // shell there, so `VibenetScreen` — which has
                                    // no scope state — draws no strip for free.
                                    scopes: vibenetSectionPublication.sections,
                                    scopeAttention: vibenetSectionPublication.attention,
                                    onPickScope: { picked in
                                        // **THE SWAP IS NOT ANIMATED** (prd
                                        // §495, user: *"it lands in place, but
                                        // jumps"* — which is the whole
                                        // diagnosis).
                                        //
                                        // §495's template fix made every
                                        // scope's drawing START at the same y,
                                        // so the bar lands where it belongs.
                                        // What was left is the TRANSITION:
                                        // each scope produces its own
                                        // `DSRoomSlot`, so SwiftUI replaces
                                        // one view with another rather than
                                        // updating one in place, and under
                                        // `withAnimation` it interpolates that
                                        // replacement — two drawings of
                                        // different natural heights briefly
                                        // sharing the box, which moves the
                                        // rail and the strip below and settles
                                        // them back. A jump that no settled
                                        // screenshot can see, which is exactly
                                        // why four rounds of measuring stills
                                        // reported "it does not move".
                                        //
                                        // The SELECTION still animates — that
                                        // is `DSSectionSwitcher`'s own
                                        // `matchedGeometryEffect`, and §-
                                        // 2026-07-14's ruling that selection is
                                        // an object travelling rather than two
                                        // states blinking is untouched. It is
                                        // only the CONTENT swap that is
                                        // instant, which is also the honest
                                        // reading: two scopes are two answers,
                                        // not one answer moving.
                                        chrome.vibenetSection = picked
                                    },
                                    // The face rail's two halves, now the
                                    // crown's (prd §482 amendment).
                                    scopedAddress: chrome.vibenetScope,
                                    onOpenBook: { route.push(.vibenetAddressBook) })
                case .altana(let card):
                    AltanaRoomCard(card: card) {
                        // The door is Altana's own explorer — the only place a
                        // key can actually be revoked (§112: we read and
                        // state, they act). Opened directly rather than
                        // landing on a row, because the account page is the
                        // whole subject and no single row is.
                        if let url = URL(string: AltanaKeystore.explorerURL(address: card.address)) {
                            openExternal(url)
                        }
                    } onPickKey: { row in
                        // Matched on the KEY ID, the last segment of every ref
                        // `AltanaKeystore.ref` builds. A SHARED credential is
                        // one token signing for several accounts (§408a), so it
                        // has several rows — the newest wins, which is
                        // `openNewest`'s own rule and the honest answer when
                        // one credential has more than one registration.
                        let tail = ":" + row.id.lowercased()
                        openNewest(source: AltanaKeystore.source, in: visible) { thing in
                            thing.sourceRef?.hasSuffix(tail) ?? false
                        }
                    }
                case .privacyPools(let room):
                    // Computed once and read three times: presence decides the
                    // strip, the dot and the row gate, and three separate reads
                    // are three chances for them to describe different rooms.
                    let poolScopes = privacyPoolsSections(room)
                    PrivacyPoolsRoomCard(
                        room: room,
                        onOpen: { slice in
                            // Matched on the DEPOSIT ref as well as the tag: an
                            // alert row about a cleared deposit carries no state
                            // tag, but a future one might, and landing on the
                            // announcement instead of the deposit it announces
                            // is the wrong row by one hop.
                            //
                            // The UNKNOWN slice is the same match with the test
                            // inverted — a deposit wearing none of the bridge's
                            // state tags (prd §486). It is a real door rather
                            // than a label for the same reason every other
                            // legend row is one: these are deposits you can go
                            // and look at, and the one thing this card cannot
                            // say about them is on the row itself.
                            openNewest(source: PrivacyPoolsRoomSource.source, in: visible) { thing in
                                guard thing.sourceRef?.hasPrefix(PrivacyPoolsRoom.depositPrefix) ?? false
                                else { return false }
                                switch slice {
                                case .state(let state): return thing.tags.contains(state.rawValue)
                                case .unknown: return PrivacyPoolsRoom.state(tags: thing.tags) == nil
                                }
                            }
                        },
                        // WHICH READING IS ON SCREEN (prd §486). Resolved
                        // rather than read raw: a scope remembered from a room
                        // whose last deposit has since been reclaimed falls
                        // back to Activity instead of rendering an empty page
                        // claiming to be a section — `WalletSection.resolve`'s
                        // rule, two rooms over.
                        section: PrivacyPoolsSection.resolve(
                            chrome.privacyPoolsSection, present: poolScopes),
                        scopes: poolScopes,
                        scopeAttention: PrivacyPoolsSection.attention(
                            needsProof: room.needsYou != nil,
                            declined: room.needsReclaim != nil,
                            present: poolScopes),
                        onPickScope: { picked in
                            withAnimation(DS.Motion.standard) {
                                chrome.privacyPoolsSection = picked
                            }
                        })
                case .gnosisPay(let room):
                    GnosisPayRoomCard(room: room) { currency in
                        openNewest(source: GnosisPayRoomSource.source, in: visible) { thing in
                            thing.priceCurrency == currency.code
                        }
                    }
                case .railgun(let room):
                    RailgunRoomCard(room: room) { token in
                        // A token owns many moves, so the honest landing is
                        // its most recent one, matched on the same
                        // `priceCurrency` field the room groups by (the
                        // Gnosis Pay currency rule, one field over).
                        openNewest(source: RailgunRoomSource.source, in: visible) { thing in
                            thing.priceCurrency == token.symbol
                        }
                    }
                case .safe(let room):
                    // `fallbackRef` is what the card opens when nothing is
                    // pending and only a module warning stands — without it
                    // that card announced a door and had none (2026-08-17).
                    SafeRoomCard(room: room,
                                 fallbackRef: SafeRoomSource.fallbackRef(things: visible)) { ref in
                        // Unlike its siblings, a Safe entry OWNS a single row
                        // — the tracking snapshot is keyed by the pending
                        // thing's own `sourceRef` — so this is a direct
                        // lookup, not a newest-of-many match.
                        openBySourceRef(ref, in: visible)
                    }
                case .x(let room):
                    XRoomCard(room: room) { year in
                        openYear(year, in: visible)
                    }
                case .journal(let room, let name):
                    JournalRoomCard(room: room, source: name) { year in
                        openJournalYear(year, source: name, in: visible)
                    }
                case .agent(let room, let name):
                    AgentRoomCard(room: room, source: name) { month in
                        openAgentMonth(month, source: name, in: visible)
                    } onOpenLongest: { longest in
                        // A single conversation, so it lands directly. Falls
                        // back to its month rather than doing nothing when the
                        // row carries no ref — a dead lead is P4.
                        if let ref = longest.ref {
                            openBySourceRef(ref, in: visible)
                        } else {
                            openAgentMonth(room.busiest, source: name, in: visible)
                        }
                    }
                case .instagram(let room):
                    InstagramRoomCard(room: room) { account in
                        // An account owns many kept posts, so the card names
                        // its newest as the landing (the Cursor repo rule).
                        // Matched on `authorHandle` and on the ACT, or a tap on
                        // a saves board could open a like from the same person.
                        let tag = room.act == .saved ? "Saved" : "Liked"
                        openNewest(source: InstagramRoomSource.source, in: visible) { thing in
                            thing.authorHandle == account.handle && thing.tags.contains(tag)
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
            insightSection {
                // THE BOARD IS A DOOR, in the one room that can open one
                // (2026-08-18, prd §396). "Who you reply to" names people you
                // have talked to for a decade and, until this pass, tapping
                // one did nothing — while the corpus behind it could answer
                // "when, and how often" better than X can. Passed only for X:
                // every other board here ranks subreddits, artists,
                // publications and books, and a person room over an artist
                // name would open an empty screen.
                //
                // A READING ROOM'S BOARD NARROWS ITS OWN ROOM instead
                // (2026-08-23, prd §455) — see `FeedInsight.Leaderboard.Scope`
                // for why the board carries the field it ranked and
                // `roomScoped` for why this one card is not narrowed with the
                // rows. Two destinations, never both: X's board opens a person
                // and a reading board scopes, so `scope` being non-nil is the
                // whole test and no room can accidentally get both.
                LeaderboardHero(board: scopedBoard(leaderboard),
                                onPick: leaderboardPick(leaderboard),
                                selected: readingScope?.label)
            }
        } else if let distribution {
            insightSection { DistributionHero(dist: distribution) }
        } else if let mosaic {
            insightSection { ImageMosaicHero(mosaic: mosaic) }
        } else if let heatmapLabel {
            calendarHeatmapSection(visible, label: heatmapLabel)
        } else if !rosterAccounts.isEmpty {
            // NOTHING is drawn here any more (prd §362, 2026-08-11), and the
            // branch survives on purpose — `rosterAccounts` is now a
            // SUPPRESSION term, not a card.
            //
            // The faces moved out of the room and onto the shell, as the pinned
            // `FaceScopeRail` the wallets already wore. What they leave behind is
            // an empty head slot, and the branch is what keeps it empty: delete
            // it and the chain falls through to `FeedHeatmap`'s "Casting
            // activity" density grid, which is precisely the card §219 removed
            // when the roster was built ("a density grid says nothing a face with
            // a ring doesn't already say better"). The faces still say it — one
            // tier up, permanently — so the grid has no more claim on this room
            // than it had yesterday, and a room that answers a ruling by growing
            // a card back is the opposite of the simplification this was.
            EmptyView()
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
        case .telegram:
            // The mixed room's fourth instance, and the widest: a followed
            // channel's wordless pictures lead as a grid, while its captioned
            // posts, your Saved Messages and whole imported conversations all
            // read as rows beneath them.
            let tiles = visible.live.filter(Self.isTelegramPhotoTile)
            let rest = visible.live.filter { !Self.isTelegramPhotoTile($0) }
            if !tiles.isEmpty { photoGridSection(tiles) }
            let telegramDays = chronoGroups(rest)
            groupedSections(telegramDays, nextEventID: nextEventID,
                            boundary: boundaryThingID(in: telegramDays))
        case .x:
            // The mixed room's third instance (2026-08-13, prd §375), and the
            // one that had to wait for the importer: until a wordless picture
            // post landed as a PICTURE rather than as the t.co shortlink
            // standing in for it, this room had no tiles to draw — every
            // photograph in it was a row whose words were a shortened URL.
            //
            // Same honesty rule as Snapchat's and Files': a tile promises a
            // picture, so only a post with pixels and nothing to say becomes
            // one. A photograph with a caption stays a post card, because the
            // caption is the post — extracting its picture into a grid would
            // separate the two halves of one thing.
            let photoTiles = visible.live.filter(Self.isXPhotoTile)
            let rest = visible.live.filter { !Self.isXPhotoTile($0) }
            if !photoTiles.isEmpty { photoGridSection(photoTiles) }
            // A THREAD READS AS A THREAD (2026-08-18, prd §396). The archive
            // has named a self-reply's parent since §308, and until this pass
            // the only place that fact reached was `enrichedText` — retrieval
            // text, drawn by nothing — so a twelve-post thread was one
            // findable argument and twelve unreadable rows. Same fold the
            // social rooms have used since 2026-07-27, on the same field.
            //
            // Instagram deliberately does NOT fold below: only X's archive
            // names a parent post, which is §309's standing split between what
            // generalises across the import rooms and what is one export's own
            // fact.
            let (roomThings, threadReplies) = foldThreadReplies(rest)
            let days = chronoGroups(roomThings)
            groupedSections(days, nextEventID: nextEventID,
                            boundary: boundaryThingID(in: days), replies: threadReplies)
        case .instagram:
            // The mixed room's fourth instance (2026-08-18, prd §395), on
            // Snapchat's, Files' and X's terms: what has pixels AND nothing to
            // say leads as a grid, everything else reads as rows.
            let photoTiles = visible.live.filter(Self.isInstagramPhotoTile)
            let rest = visible.live.filter { !Self.isInstagramPhotoTile($0) }
            if !photoTiles.isEmpty { photoGridSection(photoTiles) }
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
            // The stream's rows, gathered ONCE at the top of the case
            // (2026-08-18): the newest few now LEAD the room from inside the
            // balance card (`walletTodayCard`) and the rest read below, so
            // both halves have to be cut from one list — computed twice, a
            // row would show up in both.
            let upcoming = walletUpcoming(visible)
            // Promoted rows leave the stream, or the same deadline would be
            // read twice on one screen — once as what's coming and once as
            // whenever it happened to land.
            let promoted = Set(upcoming.map(\.id))
            let all = visible.live.filter { !promoted.contains($0.id) }
            // WHICH READING IS ON SCREEN (prd §483). Resolved rather than read
            // raw: a scope remembered from a wallet that has since closed its
            // last position falls back to the feed instead of rendering an
            // empty page that claims to be a section.
            let section = WalletSection.resolve(
                chrome.walletSection, present: walletSectionPublication.sections)
            // The crown's own newest-few (§208, added 2026-08-18) exist for one
            // reason: "the room's transactions used to begin after ten standing
            // cards, so on a busy wallet the one thing a wallet app gets opened
            // for was two screens down." In `.activity` they are no longer two
            // screens down — they are the next thing on the page — so leading
            // with three of them and then repeating them below is §208's own
            // "never say one thing twice", committed by the fix for it.
            //
            // Every other scope KEEPS them, and that is the half worth stating:
            // standing in Holdings or Permissions, the transactions are not on
            // screen at all, and three of them in the crown is the only place
            // that room still says what just happened.
            // HOME'S LIST IS THE LAST FEW MOVES (prd §483). Every scope is one
            // drawing and one list; Home's list is these three rows, so they
            // draw here and nowhere else. In `.activity` the full stream is
            // directly below and repeating three of it at the top is §208's own
            // "never say one thing twice"; in every other scope the room is
            // answering a different question entirely.
            let latest = section == .home
                ? Array(all.prefix(Self.walletTodayRows))
                : []

            // The hero, and the only block with no header of its own: a title
            // above the first thing on a screen is noise (see
            // `walletGroupHeader` for the whole ruling).
            // ONE SLOT, SHARED. The crown IS Home's drawing, so it lives in
            // the same fixed box every other scope's drawing does — otherwise
            // Home is a crown plus an empty slot and the bar sits a third of a
            // screen lower there than anywhere else.
            // NOT EMITTED off Home — see the visual slot's own note below for
            // why collapsing it to `maxHeight: 0` was not enough: an empty
            // `Section` still takes list spacing, so a zero-height box is not a
            // absent one, and the count of sections above the bar has to match
            // on every scope for the bar to land in the same place.
            if section == .home {
                // The same one template as every scope below and as every
                // vibenet scope (prd §495). Home is a bare view now too, so
                // the Section and its row modifiers are written once here
                // rather than inside the builder.
                Section {
                    // `reservesHeadline: false` — the crown IS this scope's
                    // headline (`price48`), so it stands IN the row rather
                    // than under it, which is what puts its first pixel level
                    // with every other scope's headline.
                    DSRoomSlot(headline: nil, reservesHeadline: false) {
                        walletTilesSection(visible, streamTotal: all.count, drawsChart: true)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(WalletCardStyle.rowInsets)
                }
            }
            // THE TOGGLE SITS BELOW THE SPARKLINE, IN THE CONTENT (user ruling,
            // 2026-08-26: *"we need to have those toggles be below the
            // sparkline"*, and *"we cannot have four rows of chips"*).
            //
            // It mounted in `MainSurface.roomControls` for one build, which put
            // it FOURTH in a stack of pinned strips — source chips, venue rail,
            // face rail, then this — and pushed the crown to about 45% down the
            // screen. Moving it into the scroll is the fix for both complaints
            // at once, and it makes the structure honest rather than merely
            // shorter: **the crown and its chart belong to no scope.** They are
            // the room's identity, so they sit ABOVE the control that scopes
            // everything else, and §482's "crown and holdings are one reading"
            // now holds by construction instead of by ordering things carefully.
            //
            // KNOWN, and the next thing to fix rather than something to pretend
            // is solved: a control inside the scroll scrolls away, which is
            // §357's own complaint one level down — a scope control you cannot
            // reach while deep in the rows it scopes. The answer is a pinned
            // `Section` header (those stick in a plain `List` for free), not a
            // return to `safeAreaInset`.
            // ONE DRAWING PER SCOPE, ABOVE THE CONTROL (prd §483). Home's is
            // the sparkline, which the crown draws itself; every other scope's
            // steps into the same slot, so the room always opens on a figure
            // and the toggle always sits between that figure and its list.
            // **THE BAR MUST LAND IN THE SAME PLACE ON EVERY SCOPE** (user
            // ruling, prd §483: *"this bar of avatars and toggles below it
            // should be in a fixed position on each page, it should not
            // move"*). The only way that is true is if everything ABOVE it is
            // one height — so the visual slot is fixed rather than fitted, and
            // each scope's drawing sits in it top-aligned.
            //
            // A `maxHeight` as well as a `minHeight`, which is the half that
            // makes it a promise: without it the flow band's own card (a header,
            // three lines of reading and a 138pt band) ran to roughly three
            // times the sparkline's height and pushed the bar a third of a
            // screen down.
            // **NOT EMITTED AT ALL ON HOME** — the counterpart of the crown's
            // own gate above, and the actual reason the bar kept moving.
            //
            // Both were emitted always and collapsed with `maxHeight: 0`, which
            // collapses the VIEW and not the SECTION: a `List` still gives an
            // empty section its own spacing. So Home drew ONE MORE SECTION than
            // every other scope — its crown plus an empty visual — and the bar
            // sat that spacing higher there. Two zero-height boxes, each
            // invisible, and the difference between them was the bug.
            if section != .home {
                // **ONE TEMPLATE, AND WALLET IS IN IT NOW** (prd §495, user:
                // "Wallet and Vibenet should use same template" → "one
                // template" → "we need to finish the other half").
                //
                // The seven scope builders used to be List SECTIONS, each
                // carrying its own `Section { … }` and its own row modifiers —
                // which is what stopped Wallet reaching `DSRoomSlot` on the
                // first attempt, because wrapping a Section in a plain view
                // collapses it and drops its hidden separator (a HAIRLINE, §8
                // bans them). They are bare views now, the Section is here and
                // written once, and the box is the same `DSRoomSlot` every
                // vibenet scope draws into.
                //
                // `headline: nil`: Wallet's figures name themselves today. The
                // ROW is still reserved, which is what makes each drawing
                // start at the same y and what clears the settings gear.
                Section {
                    // `reservesHeadline: false`, like Home above (prd §495).
                    //
                    // **The rule is: reserve the row only when the CHASSIS
                    // draws the headline.** Vibenet's figures pass theirs to
                    // `scopeFigure`, so the chassis owns that line and must
                    // keep room for it. Wallet's figures name themselves
                    // INSIDE their own drawing, so reserving a row above them
                    // both leaves a blank band and — the part that was
                    // visible — steals 42pt from drawings sized for the whole
                    // slot: the holdings treemap and the NFT quad were both
                    // clipped along their bottom edge, since the quad derives
                    // its cell size from `visualSlot` directly.
                    DSRoomSlot(headline: nil, reservesHeadline: false) {
                        walletScopeVisualSection(section)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(WalletCardStyle.rowInsets)
                }
            }
            walletScopeRailSection
            walletSectionSwitcherSection(section)
            // THE FOUR `walletGroupHeader` GROUPS BECOME SCOPES (prd §483).
            // Renamed to short nouns and split twice — NFTs out of "What you
            // hold", and "What it's doing" into Positions and Risk — so the
            // mapping from card to scope is IDENTITY: every section below is
            // the one that shipped, moved and not redrawn.
            //
            // The headers themselves are gone rather than kept inside their
            // scopes, because the chip now says the same words in the same
            // place; two of them would be §208's rule broken by the very pass
            // that cites it. They come back the day a scope holds two unlike
            // kinds of thing.
            switch section {
            case .home:
                // Home's LIST — below the toggle like every other scope's, not
                // inside the crown card where §208 put it. Drawn there it sat
                // BETWEEN the sparkline and the control, which is the one place
                // the ruling says nothing may go.
                if !latest.isEmpty {
                    Section {
                        // BARE ON THE PAGE, NO CARD (user ruling, prd §483:
                        // *"we need to put the transactions that are showing
                        // outside of a card, remember we are going to the
                        // restrained design?"*). §391's rule, one room over:
                        // text sections lose their box and separate by air and
                        // heading weight; only DRAWINGS keep a surface, because
                        // `DS.ink(magnitude:)` and the chart fills are
                        // calibrated against one.
                        walletTodayCard(latest, streamTotal: all.count)
                            .listRowInsets(EdgeInsets(top: 0, leading: DS.Space.s4,
                                                      bottom: 0, trailing: DS.Space.s4))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
            case .activity:
                // **WHAT ALREADY HAPPENED, AND ONLY THAT** (user ruling, prd
                // §483: *"on activity below the toggle bar, this is
                // transactions or whatever, so it should be things that already
                // happened, not things in the future"*).
                //
                // The forward-dated rows led this scope for one build, on the
                // reasoning that a timeline has two directions. True of a
                // timeline and false of this one: the stream reads backwards
                // from today and is grouped Today / Yesterday / earlier, so a
                // block of things that have not happened sat above a list whose
                // every heading is a past day.
                //
                // PARKED rather than rehomed — `walletUpcoming` still computes
                // and its rows still leave the stream, so nothing is duplicated
                // and nothing is lost; they simply draw nowhere until a scope
                // earns them. Risk is the likely home (a deadline is a hazard
                // with a clock) but that is a ruling, not a default.
                walletStreamSections(walletStreamRows(all), nextEventID: nextEventID)
                walletSeeAllSection(total: all.count)
            case .holdings:
                walletTokenListSection
            case .positions:
                walletDeFiSection
                walletLiquiditySection
                walletPerpsSection
            case .nfts:
                // The QUAD is the drawing above; these are the collections
                // behind it, named (prd §483, user: *"below the toggle bar is
                // those four in a list w/ collection name and so on"*).
                walletNFTListSection
            case .risk:
                // The bars moved up into the slot, so the list is the door
                // they were covering — see `walletScopeVisualSection`.
                walletWarningsSection
                // **§417's OVERVIEW→DETAIL PAIR, restored.** `WalletRiskStrip`
                // is documented as the overview of exactly these cards ("the
                // cards below state each position in its own protocol's
                // units, and this is the one view that puts them in an
                // order"), and its dot walk sets `cardScrollTarget` to one of
                // their anchors. Heading the scope with the strip split the
                // pair across two scopes, which broke that walk silently — it
                // scrolled to an anchor that was not on screen — and left
                // this list empty on any wallet with nothing to warn about,
                // which is most of them.
                //
                // They draw in BOTH scopes, and that is not "saying one thing
                // twice": the two are never on screen together, and they
                // answer different questions — in Positions they are the
                // detail behind where the money is, here they are the detail
                // behind what is close to closing.
                walletDeFiSection
                walletPerpsSection
            case .permissions:
                walletApprovalsSection
            }
        case .ledger:
            // THE ROWS ARE A SCOPE IN ONE OF THE TWO ROOMS THIS SHAPE SERVES
            // (prd §486) — Privacy Pools' Activity. Railgun shares the row
            // anatomy and has no scopes at all, and `privacyPoolsShowsRows`
            // answers true for it by construction rather than by a second
            // source test here.
            //
            // Days, and the memoized grouping every other source room uses:
            // these are real events at real block times, so a chronological
            // grouping is honest.
            if privacyPoolsShowsRows(visible) {
                let days = chronoDays(visible)
                groupedSections(days, nextEventID: nextEventID,
                                boundary: boundaryThingID(in: days))
            }
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
        case .vibenet:
            // THE EVENTS ARE A SCOPE NOW (prd §482) — "Recent", and the only
            // one of vibenet's four that is rows rather than cards. Drawn when
            // that scope is picked, or when the strip is not shown at all
            // (`present` returned fewer than two, so there is no control and
            // the room is one scroll again).
            //
            // Days, like most rooms: unlike x402 (where every row shares
            // one sync timestamp) these are real events at real block
            // times, so a chronological grouping is honest here.
            // **HOME'S LIST IS THE LAST FEW MOVES; ACTIVITY'S IS THE STREAM**
            // (prd §482 amendment, Wallet's §483 rule: every scope is one
            // drawing and one list). Home drew a chart and then nothing —
            // half a scope — because the rows were gated to Activity alone.
            //
            // Home takes three, UNGROUPED: day headings over three rows are
            // headings over one row each, and the reading here is "the last
            // few things", not "what happened on Monday". Activity keeps the
            // full stream in days, and the three are NOT repeated at its top —
            // §208's own "never say one thing twice", which is the same call
            // Wallet made for its own crown rows.
            let vScope = VibenetSection.resolve(chrome.vibenetSection,
                                                present: vibenetSectionPublication.sections)
            let vScoped = VibenetSection.shows(present: vibenetSectionPublication.sections)
            if vScoped && vScope == .home {
                let latest = Array(visible.live.prefix(Self.vibenetHomeRows))
                if !latest.isEmpty {
                    groupedSections([(String(localized: "Latest"), latest)],
                                    nextEventID: nextEventID)
                }
            } else if vibenetShowsRows {
                let days = chronoGroups(visible)
                groupedSections(days, nextEventID: nextEventID, boundary: boundaryThingID(in: days))
            }
        case .x402:
            // Lanes, not days — see `x402Lanes`. No `boundary:`, deliberately:
            // the new-since divider is a chronological mark, and in a room
            // where every row shares one timestamp it would land arbitrarily.
            groupedSections(x402Lanes(visible), nextEventID: nextEventID)
        case .cardPointers:
            // Deadlines, not days — see `cardPointersGroups`. No `boundary:`,
            // for x402's reason one room over: every offer carries the
            // `capturedAt` of the sync that first saw it, so a new-since
            // divider in this room marks nothing.
            groupedSections(cardPointersGroups(visible), nextEventID: nextEventID)
        case .walletbeat:
            // Your watched wallets lead as standing report cards, then the news
            // below in days. A rating is not an event and must not be filed under
            // the day it happened to be read; an incident is, and is.
            let watches = visible.live.filter { WalletbeatWatch.isWatchRef($0.sourceRef) }
            let rest = visible.live.filter { !WalletbeatWatch.isWatchRef($0.sourceRef) }
            if !watches.isEmpty {
                groupedSections([(String(localized: "Your wallets"), watches)], nextEventID: nextEventID)
            }
            let days = chronoGroups(rest)
            groupedSections(days, nextEventID: nextEventID, boundary: boundaryThingID(in: days))
        case .l2beat:
            // Your watched chains lead as standing assessments, then the timeline
            // below in days. An assessment is not an event and must not be filed
            // under the day it happened to be read; a milestone is, and is.
            let watches = visible.live.filter { L2beatWatch.isChainRef($0.sourceRef) }
            let rest = visible.live.filter { !L2beatWatch.isChainRef($0.sourceRef) }
            if !watches.isEmpty {
                groupedSections([(String(localized: "Your chains"), watches)], nextEventID: nextEventID)
            }
            let days = chronoGroups(rest)
            groupedSections(days, nextEventID: nextEventID, boundary: boundaryThingID(in: days))
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
        case .bookmarks:
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
            if Pinboard.isPinnedRoom(source) {
                // ONE group, in the `@Query`'s own order — which is pin order,
                // newest pin first. Every other room here day-groups on
                // `capturedAt`, and doing that to this one would sort your list
                // by the corpus's clock instead of yours: a pin you made this
                // morning on a two-year-old screenshot would land under a 2024
                // header, below things you pinned weeks ago. That is exactly
                // the failure `Thing.pinnedAt` is a DATE rather than a Bool to
                // avoid, and it would arrive by the back door.
                daySection(Pinboard.room, visible, nextEventID: nextEventID)
            } else if filter.tag != "All" && shape == .all {
                daySection(filterLabel, visible, nextEventID: nextEventID)
            } else if shape == .all {
                // The Themes treemap no longer renders here — it moved ABOVE
                // the shape chain entirely (prd §385, see the call site in
                // `feedList`): it must precede every hero this switch's
                // preamble draws, or the fold-settle scroll would hide a live
                // hero above the fold along with the map.
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
                    SocialRoom.foldsThreads(source) ? foldThreadReplies(visible) : (visible, [:])
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

    #if DEBUG
    /// The All room's census — see the call site in `bundledSections` for why
    /// it is emitted from the render rather than mirrored in `ProbeHooks`.
    ///
    /// Takes no `Thing` by design (`hasCover` is a Bool, not the cover): this
    /// is called from inside a body evaluation, and the liveness rules above
    /// mean a census has no business holding a model to count it. Every input
    /// is already a value type by the time it arrives.
    ///
    /// De-duplicated on the composed text because this runs on every body pass:
    /// a census that repeats forty times a launch buries the one line that
    /// changed, and `verify.sh` greps for presence, not for the last write.
    private func logAllFeedCensus(groups: [(String, [FeedRow])],
                                  hasCover: Bool,
                                  boundary: String?,
                                  moment: Bool,
                                  imageOnly: Set<UUID>,
                                  wideArt: Set<UUID>,
                                  coarse: Set<String>,
                                  subjects: [String: String],
                                  more: Bool,
                                  dayLine: DayBrief.Whisper?,
                                  tailDays: Int,
                                  tailDrawn: Int) -> Void {
        var single = 0, strip = 0, bundle = 0
        var stripTiles = 0, bundleArt = 0, ambient = 0
        for (_, rows) in groups {
            for row in rows {
                if row.ambient { ambient += 1 }
                switch row.kind {
                case .single: single += 1
                case .strip(_, _, _, _, let tiles): strip += 1; stripTiles += tiles.count
                case .bundle(_, _, _, _, let art): bundle += 1; bundleArt += art.count
                }
            }
        }
        // Each line is one FEATURE of this room, named the way `verify.sh`'s
        // required list names it. Counts, never contents: a census that printed
        // titles would be a corpus dump, and the question here is only ever
        // "can this room draw this at all on the demo".
        let lines = [
            "days=\(groups.count) rows=\(single + strip + bundle)",
            "cover=\(hasCover ? 1 : 0)",
            "single=\(single) strip=\(strip) bundle=\(bundle)",
            "stripTiles=\(stripTiles) bundleArt=\(bundleArt)",
            "imageOnly=\(imageOnly.count) wideArt=\(wideArt.count)",
            "coarse=\(coarse.count) subjects=\(subjects.count)",
            "newSince=\(boundary == nil ? 0 : 1) moment=\(moment ? 1 : 0)",
            "window=\(more ? "open" : "whole")",
            "dayLine=\(dayLine == nil ? 0 : 1)",
            "ambient=\(ambient)",
            // Both terms of `coarsenIfSparse`'s ratio, plus its verdict. The
            // gate needs `tailDays >= 6` AND `tailDrawn / tailDays < 1.5`, so
            // printing the average alone would hide which half is failing.
            "tailDays=\(tailDays) tailDrawn=\(tailDrawn)",
            "tailAvg=\(tailDays == 0 ? "n/a" : String(format: "%.2f", Double(tailDrawn) / Double(tailDays)))"
                + " coarsens=\(tailDays >= 6 && Double(tailDrawn) / Double(max(tailDays, 1)) < 1.5 ? 1 : 0)",
        ]
        let composed = lines.joined(separator: ";")
        guard Self.lastAllFeedCensus != composed else { return }
        Self.lastAllFeedCensus = composed
        for line in lines { NSLog("[Casberi] allFeed| %@", line) }
        // The terminator `verify.sh` waits on — without it the reader cannot
        // tell "the census finished" from "the census never ran", which for a
        // room that legitimately draws zero bundles is the whole question.
        NSLog("[Casberi] allFeed| census complete")
    }
    @MainActor private static var lastAllFeedCensus = ""
    #endif

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
            // The cover is chosen over THINGS and before the fold (prd §389c),
            // which is the whole of the fix: chosen after it, the newest thing
            // could be inside a fold and the card would lead with something
            // older than a row beneath it.
            memo.lede = ledeThingID(in: memo.days)
            // `nextEventID` rides in so the clock carve-out (prd §377) can
            // spare the next-up row. Both it and the live set can change
            // WITHOUT `visible` changing, and this memo keys on the snapshot's
            // revision (see `derivationKey`), so a newly-live row can stay
            // folded until the next write. That is a delay, never a
            // regression: before this carve-out existed those rows folded
            // unconditionally, so the stale case is exactly the old behaviour.
            memo.groups = perfAccum("bundle") {
                bundle(memo.days, nextEventID: nextEventID, excluding: memo.lede)
            }
            // `ledeMinRows` is a floor in ROWS, and rows are only known after
            // the fold — which needs the cover's identity first, so the two
            // cannot both be decided in one pass. Asked here, where the answer
            // exists: four RSS items are four THINGS and one bundled row, and a
            // cover over a lone "RSS · 3 articles" is the whole feed being a
            // cover, which is what that floor exists to prevent. Re-bundling
            // costs nothing precisely because it only ever happens on a feed
            // this small.
            if memo.lede != nil,
               memo.groups.reduce(1, { $0 + $1.1.count }) < Self.ledeMinRows {
                memo.lede = nil
                memo.groups = bundle(memo.days, nextEventID: nextEventID)
            }
            memo.imageOnly = perfAccum("imageOnlyIDs") { imageOnlyIDs(memo.days) }
            memo.wideArt = perfAccum("wideArtIDs") { wideArtIDs(memo.groups) }
            memo.coarse = perfAccum("coarseLabels") { coarseLabels(in: memo.days) }
            memo.subjects = perfAccum("coarseSubjects") {
                coarseSubjects(memo.days, coarse: memo.coarse)
            }
        }
        // The away window becomes sectioning (prd §389) — OUTSIDE the memo
        // above, deliberately: `newSince` freezes when the page lands and so
        // changes without `visible` changing, which the memo key (the
        // snapshot's revision) cannot see. It is a partition of arrays already
        // built, so recomputing it per render costs a walk and no derivation.
        let allGroups = memo.groups
        let split = momentSplit(allGroups)
        // Windowed (prd §264). `boundary` and `lede` read the FULL set so
        // neither moves depending on whether the window is open.
        let window = windowed(split.groups)
        let _ = { memo.windowHasMore = window.more }()
        let groups = window.shown
        // Suppressed under a moment split: the section header IS the boundary
        // there, and two seams for one fact is worse than either alone.
        let boundary = split.moment ? nil : boundaryID(in: split.groups)
        // The cover is already OUT of `memo.groups` (prd §389c), so it is
        // resolved from the day it came from rather than searched for among the
        // rows. `.isLive` before the id read: `memo.days` is held across
        // renders, so a heal's delete can land under it — and the first day is
        // the only one that can hold the cover, so the scan is bounded by a day
        // rather than by the corpus.
        let ledeThing = memo.lede.flatMap { id in
            memo.days.first?.1.first { $0.isLive && $0.id == id }
        }
        let firstLabel = groups.first?.0
        let imageOnly = memo.imageOnly
        let wideArt = memo.wideArt
        let coarse = memo.coarse
        let subjects = memo.subjects
        // The day header speaks (prd §385, 2026-08-14): the Today header
        // carries the day's own sentence — `DayBrief`'s whisper, the ONE
        // implementation of "what today was" (the capsule, the kept pill and
        // now this header all read it, so no two can disagree). Deliberately
        // NOT in the memo above: the whisper depends on the away window and
        // the wallet's day move, both of which change without the corpus
        // changing, and it is a filter-plus-scan over an already-bounded
        // array — cheap enough to stay time-fresh. Nil composes to no line
        // (honesty law: a day with nothing to say says nothing).
        let dayLine = DayBrief.whisper(things: visible)
        #if DEBUG
        // `-allFeedProbe YES` — the All room's own census (2026-08-17), and the
        // only demo-parity check that can see this room AT ALL.
        //
        // Every other demo coverage step reaches a SOURCE room: `verify.sh`'s
        // room-head step probes ten of them by name, its sheet-anatomy step
        // opens one record at a time, and `demo-selftest.py`'s check F
        // explicitly exempts this one (`SHAPE_NO_SOURCE = {"all"}`). But All is
        // the ONLY room that runs `bundledSections`, so the cover (§389c),
        // folding into strips and bundles (§377), the image-only and wide-art
        // treatments, the coarse tail and its subjects (§379) and the away
        // split (§389) exist NOWHERE ELSE — none of them has ever been checked
        // against the demo corpus, and All is the room the demo opens on. It is
        // the first screen a first-time opener sees, and it was the last one
        // with no parity check.
        //
        // Emitted from HERE rather than mirrored in `ProbeHooks`, for
        // `MainSurface`'s `categoryFold|` reason (2026-08-11): a probe that
        // recomputes an answer can only ever prove its own copy of the rule.
        // That is the documented weakness of `-roomInsightProbe`, whose own
        // header says the order "lives in `FeedScreen.shapedSections` — this
        // mirrors it, so a change there means a change here." This derives
        // nothing: every value below is one this render is about to draw with,
        // read at the one moment they all exist together.
        //
        // One NSLog per line (the `-todayProbe` truncation lesson).
        if UserDefaults.standard.bool(forKey: "allFeedProbe") {
            // THE TAIL'S OWN ARITHMETIC (2026-08-17). `coarse` measured 0 and
            // — unlike every other feature here — no amount of seeding can
            // change that on its own: `coarsenIfSparse` fires only when the
            // older-than-7-days section averages under 1.5 DRAWN rows per day,
            // and drawn is post-fold, not row count. So the question "how far
            // off is the demo" has a number, and guessing at it would mean
            // restructuring 56 days of dates on a theory. Reported as the two
            // terms of the ratio plus the gate's own verdict, because an
            // average alone cannot say whether the fix is fewer rows or more
            // folding — which are different changes to the demo.
            let tailCutoff = Self.groupingCalendar.date(
                byAdding: .day, value: -7,
                to: Self.groupingCalendar.startOfDay(for: .now))
            let tail = tailCutoff.map { cut in
                visible.filter { $0.isLive && $0.capturedAt < cut }
            } ?? []
            let tailDayGroups = dayGroups(tail)
            let tailDrawn = tailDayGroups.reduce(0) { $0 + bundledRowCount($1.1) }
            // `memo.groups`, NOT `groups` — measured 2026-08-17 on the demo and
            // the difference is the whole check: `groups` is `windowed(...)`'s
            // SHOWN slice (prd §264), so the first census over a 467-row demo
            // read `days=1 rows=3` while `wideArt` — taken from `memo`, i.e.
            // the full set — read 12 in the same breath. Two units in one
            // census, and the smaller one is the one `verify.sh` tests for
            // zero, so a healthy room would have reported missing features
            // forever. The question here is what the room CAN draw, which is a
            // property of the whole composed feed; whether the window is open
            // is reported separately, as its own fact.
            logAllFeedCensus(groups: memo.groups, hasCover: ledeThing != nil, boundary: boundary,
                             moment: split.moment, imageOnly: imageOnly, wideArt: wideArt,
                             coarse: coarse, subjects: subjects, more: window.more,
                             dayLine: dayLine,
                             tailDays: tailDayGroups.count, tailDrawn: tailDrawn)
        }
        #endif
        return Group {
        ForEach(groups, id: \.0) { label, rows in
            // The cover draws above the FIRST group's run and is already absent
            // from every group's rows (prd §389c) — so the run positions below
            // see the true row list with no filtering, and the card's top
            // shoulder lands on the real first row.
            //
            // The first group is named rather than indexed: `momentSplit` can
            // rename or insert a leading group ("Since you left"), and the
            // labels are the `ForEach` identity, so they are the one thing that
            // is unique here by construction.
            let cover = label == firstLabel ? ledeThing : nil
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
                if let cover, cover.isLive { ledeListRow(cover) }
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
                            // The day's promoted anchor NEVER recedes (§378
                            // amendment, found by auditing §254 × §378): every
                            // promotable row is ambient by construction —
                            // `artRidesBesideIdentity` admits only social/RSS
                            // — so without this exemption the one row §254
                            // chose as the day's landmark was the one row
                            // guaranteed quiet. A dimmed landmark is a
                            // contradiction in terms, and it stays exempt
                            // below the read boundary too: landmarks are for
                            // wayfinding, which already-read territory needs
                            // MORE of, not less.
                            let anchor = wideArt.contains(thing.id)
                            shapedListRow(thing, index: i, nextEventID: nextEventID,
                                          position: positions[i],
                                          imageOnly: imageOnly.contains(thing.id),
                                          wideArt: anchor)
                                .opacity(!anchor && isQuiet(row) ? Self.quietRow : 1)
                        }
                    case .bundle(let source, let word, let count, let newest, let art):
                        bundleListRow(source: source, word: word, count: count,
                                      newest: newest, art: art, index: i, position: positions[i])
                            .opacity(isQuiet(row) ? Self.quietRow : 1)
                    case .strip(let source, let word, let count, let newest, let tiles):
                        stripListRow(source: source, word: word, count: count,
                                     newest: newest, tiles: tiles, index: i,
                                     position: positions[i])
                            .opacity(isQuiet(row) ? Self.quietRow : 1)
                    }
                }
                // The moment closes (prd §389). `newSinceDivider` said the
                // same thing from ABOVE the boundary, where it had to name the
                // date to be understood; from below, under a section already
                // named "Since you left", the only fact left to state is that
                // this is where you can stop.
                if split.moment && label == Self.momentLabel { caughtUpSeam }
            } header: {
                // No count (prd §218, 2026-07-25). §213 retired volume as news
                // in the brief ("people do not care how many things landed"),
                // and the widget's own tally went the same day; this header was
                // the last surface still counting. "Monday, Jun 15 · 1" was the
                // clearest case against it — a number that can only ever say
                // "one", under a header already carrying the date.
                VStack(alignment: .leading, spacing: 1) {
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
                    // What the group was mostly about (prd §379) — coarse
                    // groups only, and only when a term actually recurs, so
                    // the recent days keep their bare date and nothing is
                    // invented for a month with no topic terms in it.
                    if let subject = subjects[label] {
                        Text(String(localized: "mostly \(subject)"))
                            .dsText(.subhead13)
                            .foregroundStyle(DS.textTertiary)
                            .lineLimit(1)
                    }
                    // Today's own line (prd §385) — the §379 subject line's
                    // shape, on the one day it never covers (Today is never
                    // coarse, so at most one of these two renders). The
                    // whisper capsule shows this same sentence once a day and
                    // then clears; this is its standing home, on the divider
                    // the day already owns.
                    //
                    // Under a moment split (prd §389) the sentence follows the
                    // TOP group, which is then "Since you left" and the day's
                    // remainder is "Earlier today" — without this the whisper
                    // would simply vanish on exactly the opens the split fires
                    // on. Deliberately not "the first group": open the app
                    // after a quiet week and that is a Saturday from August,
                    // and today's sentence does not belong on it.
                    if label == (split.moment ? Self.momentLabel : String(localized: "Today")),
                       let whisper = dayLine {
                        whisper.detailText(scheme: colorScheme)
                            .dsText(.subhead13)
                            .lineLimit(1)
                    } else if label == Self.momentLabel {
                        // No count here, by §218's own ruling on this header —
                        // and the fact worth carrying is not how many landed
                        // but when you were last here, which is what makes
                        // "since you left" a measurable claim rather than a
                        // mood.
                        Text(String(localized: "Last here \(sinceLabel)"))
                            .dsText(.subhead13)
                            .foregroundStyle(DS.textTertiary)
                            .lineLimit(1)
                    }
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
    /// How far a receding row steps back (prd §378). One step, and only one:
    /// a row is quiet or it isn't, never quieter for two reasons at once
    /// (see `isQuiet`). Opacity rather than the `done` treatment's colour step
    /// because this must recede a row WHOLE — its picture and its brand mark
    /// included — and colour reaches only text; it is also one modifier with
    /// no layout change, so nothing shifts as the boundary moves.
    private static let quietRow = 0.68

    /// Whether a row steps back on a skim — ambient, or already read.
    ///
    /// The two reasons are OR'd into ONE step deliberately. They answer the
    /// same practical question ("can I skip this?") and multiplying them would
    /// double-dim an ambient row below the boundary into unreadability, which
    /// is how a legibility change becomes a legibility bug. Above the divider
    /// the tiers do the sorting; below it everything recedes together, which
    /// is honest — you have read it.
    ///
    /// Never applied under increased contrast: dimming is exactly what that
    /// setting exists to refuse, and the feed's structure must not be the one
    /// thing it costs you.
    private func isQuiet(_ row: FeedRow) -> Bool {
        guard contrast != .increased else { return false }
        if row.ambient { return true }
        guard let newSince else { return false }
        return row.date <= newSince
    }

    /// The end of what's new (prd §389) — the moment section's own floor,
    /// under a split. Words only, no drawn rule (the no-hairlines law), and
    /// deliberately not a capsule: `newSinceDivider` is a marker BETWEEN two
    /// rows and needs a fill to read as a seam, while this one closes a
    /// section and reads as the quiet line it is (`caughtUpFooter`'s
    /// treatment, which does the same job for the whole feed).
    private var caughtUpSeam: some View {
        Text("You're caught up — everything below, you've seen")
            .dsText(.subhead13)
            .foregroundStyle(DS.textTertiary)
            .frame(maxWidth: .infinity)
            .padding(.top, DS.Space.s4)
            .padding(.bottom, DS.Space.s2)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

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
    /// Who posted here since you last opened this room — the social rail's
    /// attention ring, handed UP to the shell (prd §362).
    ///
    /// It is computed here and not in `MainSurface` because both of its inputs
    /// are the feed's: `newSince` is this room's own frozen last-visit stamp,
    /// and `visible` is the room's boundary-filtered rows. The shell's own
    /// corpus query deliberately does not fetch `authorHandle`, so asking it
    /// there would fault the heavy columns back in on every body pass — the exact
    /// cost that query's `propertiesToFetch` exists to avoid.
    ///
    /// Written on LANDING only, alongside the crown pour and for the same
    /// reason: it is a fact about arriving in a room, and recomputing it as rows
    /// stream in would dissolve the rings one by one while you watched.
    private func publishFreshHandles() {
        guard SocialRoom.hasRoster(source), let since = newSince else {
            chrome.freshHandles = []
            return
        }
        chrome.freshHandles = Set(visible.compactMap {
            $0.capturedAt > since ? $0.authorHandle : nil
        })
    }

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
        publishFreshHandles()
        // Every landing writes the crown pour's hue (prd §159): the scoped
        // wallet's face tint when you're standing inside one, else nil —
        // Casberi's own blue. Written unconditionally, not just by the Wallet
        // page, so arriving on ANY page resets a scoped tint the wallet page
        // left behind; no leave() bookkeeping to race the pager's ordering.
        chrome.pourHue = roomTakesWalletScope ? selectedWallet.map(WalletFace.tint) : nil
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

    /// The cover in the list (prd §389). ONE gesture, opening the same sheet
    /// the row would have — a cover is a bigger read of one thing, not a
    /// second kind of destination.
    ///
    /// It carries no `runBackground`: the card paints its own surface (it is
    /// the one object here that is a card rather than a row on a card), so the
    /// run underneath it starts clean at the row below. That is also why the
    /// Mac walk's selection is passed INTO the card rather than washed behind
    /// it — a `selectionWash` under an opaque card is a selection you cannot
    /// see.
    ///
    /// `.id` is load-bearing on Mac: `walkRowIDs` publishes this row's id from
    /// `memo.groups`, which still holds the promoted row, so without an id here
    /// ↓ onto the cover would scroll to nothing and highlight nothing — the
    /// exact dead-walk failure `walkRowIDs`' own doc warns about.
    private func ledeListRow(_ thing: Thing) -> some View {
        Button {
            openThing(thing)
        } label: {
            FeedLedeCard(thing: thing,
                         selected: DS.isMac
                            && chrome.walkSelected == thing.id.uuidString)
                .modifier(RowEntrance(index: 0, wave: shapeWave, style: entranceStyle))
                .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        .dsHover()
        .macHoverLift()
        .id(thing.id.uuidString)
        .listRowBackground(Color.clear)
        // A wider gap below than above: the cover is its own object, and the
        // day's run begins under it rather than continuing from it.
        .listRowInsets(.init(top: DS.Space.s2,
                             leading: DS.Space.s4 + DS.Space.s3,
                             bottom: DS.Space.s4,
                             trailing: DS.Space.s4 + DS.Space.s3))
        .listRowSeparator(.hidden)
    }

    /// A bundle in the list: same card treatment as a thing row; the tap
    /// opens the source's own shape (where volume is designed to live) —
    /// no swipes, nothing here is a single thing to pin or open.
    private func bundleListRow(source: String, word: String, count: Int,
                               newest: Date, art: [String] = [], index: Int,
                               position: RunPosition = .only) -> some View {
        let skin = rowSkin(forSource: source)
        return BundleRow(source: source, count: count, word: word, newest: newest, art: art)
            .environment(\.colorScheme, skin?.ink ?? colorScheme)
            .modifier(RowEntrance(index: index, wave: shapeWave, style: entranceStyle))
            .contentShape(Rectangle())
            .onTapGesture {
                DSHaptic.selection()
                withAnimation(DS.Motion.standard) { filter.source = source }
            }
            .dsTapCard()
            // A bundle is an ordinary row, never a designed card, so it goes
            // bare on the ink like every list row (lists are air) — UNLESS the
            // room mixes sources, where the card IS the source's colour and a
            // bundle is the row most worth colouring: it stands for the whole
            // of that source's day.
            .listRowBackground(runBackground(position, bare: true, skin: skin))
            // Feed rhythm (2026-07-13): back to s2 — the s3 airy read made
            // every gap the same size, so days never clustered. Rows sit
            // tight within their day; the day header carries the big gap.
            .listRowInsets(.init(top: DS.Space.s2,
                                 leading: DS.Space.s4 + DS.Space.s3,
                                 bottom: DS.Space.s2,
                                 trailing: DS.Space.s4 + DS.Space.s3))
            .listRowSeparator(.hidden)
    }

    /// A strip in the list — the same row contract as a bundle, drawn as its
    /// members (prd §377).
    ///
    /// ONE gesture, opening the source's own room, exactly like `bundleListRow`
    /// — the tiles are a picture of what folded, never controls. Two rules say
    /// so and they agree: a feed row is a read with one gesture (2026-07-16),
    /// and §35's bundle contract already sends volume to "that source's chip,
    /// whose shape is where volume is designed to live" — which for screenshots
    /// IS the photo grid. Per-tile taps were considered and held: a second
    /// target on a row is also the shape that made five sibling `.sheet`
    /// modifiers self-dismiss (2026-07-28), and it is not a change worth
    /// making unseen.
    private func stripListRow(source: String, word: String, count: Int,
                              newest: Date, tiles: [StripTile], index: Int,
                              position: RunPosition = .only) -> some View {
        let skin = rowSkin(forSource: source)
        return StripRow(source: source, count: count, word: word, newest: newest, tiles: tiles)
            .environment(\.colorScheme, skin?.ink ?? colorScheme)
            .modifier(RowEntrance(index: index, wave: shapeWave, style: entranceStyle))
            .contentShape(Rectangle())
            .onTapGesture {
                DSHaptic.selection()
                withAnimation(DS.Motion.standard) { filter.source = source }
            }
            .dsTapCard()
            .listRowBackground(runBackground(position, bare: true, skin: skin))
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
    /// ABOVE THE FOLD since 2026-08-14 (prd §385, user: "i'm not sure it
    /// needs to be a treemap … i like the idea of 1 and 3"): the map is an
    /// all-time reading that almost never changes, so as a standing head it
    /// answered "what does my corpus contain" on a surface whose question is
    /// "what's different since I last looked". It no longer claims the head
    /// at all — the list opens settled at `themesFoldAnchor` just below it
    /// (see `foldSettled`), and the map is revealed by scrolling up past the
    /// top, the way Mail hides search. The digest-collapse machinery this
    /// replaces (2026-07-20's seen-digest + the collapsed one-line row) is
    /// deleted, not demoted: hidden-by-geometry does the same job with no
    /// stored state, and re-hides on every re-mount for free.
    ///
    /// Deliberately NOT gated on `heroShown` anymore: the no-stacking rule
    /// (2026-08-07) was about two cross-source overviews competing for the
    /// resting open, and above the fold this one isn't present at rest —
    /// seeing it under a thread head costs an explicit scroll-up, which is a
    /// request for more, not a stack.
    @ViewBuilder
    private func themesLedeSection(_ visible: [Thing], proxy: ScrollViewProxy) -> some View {
        // Memoized since 2026-07-31 (see `themesData`), so it no longer walks
        // the corpus on every launch-window body pass.
        let themes = themesData(visible)
        if let doc = themes.doc {
            let rendered = doc.joined(separator: "\n")
            let els = perfAccum("themesParse") { GenParser.parse(prefix: rendered[...], isComplete: true) }
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
                // The fold anchor — the line the list opens settled at, so
                // everything above it (the card) sits above the fold. Zero
                // height on purpose, and `defaultMinListRowHeight` is forced
                // down PER-ROW because a List otherwise gives any row its
                // ~44pt minimum, which would render as a mystery gap between
                // the revealed card and the Today header.
                //
                // The settle rides the ANCHOR'S OWN `onAppear`, not the
                // List's: it fires exactly when this row materialises, so the
                // `scrollTo` can never race the List's first layout (a
                // List-level `onAppear` can run before lazy rows register,
                // and a `scrollTo` no target has heard of is a silent no-op
                // that would leave the map sitting visibly at the top). It
                // also self-gates for free — no themes card, no anchor, no
                // scroll. Unanimated on purpose: this is the room's resting
                // position, not a motion.
                Color.clear
                    .frame(height: 0)
                    .id(Self.themesFoldAnchor)
                    .environment(\.defaultMinListRowHeight, 0)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
                    .onAppear {
                        guard !foldSettled else { return }
                        foldSettled = true
                        proxy.scrollTo(Self.themesFoldAnchor, anchor: .top)
                    }
            }
        }
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
    /// A feed that has stopped answering, said in the room (2026-08-23, prd
    /// §455). Draws nothing at all when every feed is fine, which is the
    /// common case — see `FeedRoomHealth`.
    ///
    /// A DOOR, not a label. The one useful response is to look at the followed
    /// list and re-add or remove the feed, and that list lives on the bridge's
    /// own screen; a line stating a problem with no way to act on it is the
    /// half-control the honesty law is about. Its destination comes from
    /// `FeedRoomHealthSource`, so a room whose screen we cannot name draws no
    /// note rather than a chevron that goes nowhere.
    @ViewBuilder
    private var feedHealthNote: some View {
        if let standing = heads?.feedHealth,
           let destination = FeedRoomHealthSource.destination(for: source) {
            Section {
                Button {
                    DSHaptic.selection()
                    route.pushBridge(destination)
                } label: {
                    HStack(spacing: DS.Space.s2) {
                        Text(standing.line)
                            .dsText(.subhead13)
                            .foregroundStyle(DS.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.right")
                            .dsText(.label11)
                            .foregroundStyle(DS.textTertiary)
                    }
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.vertical, DS.Space.s2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .dsHover()
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
            }
        }
    }

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
        .buttonStyle(PressSpring())
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

    /// The CardPointers room grouped by DEADLINE rather than by day (prd §487)
    /// — the `x402Lanes` shape, for a sharper version of the same reason.
    ///
    /// A day is not merely the wrong axis here, it is a constant: every offer
    /// lands with `capturedAt: .now`, so day-grouping produced ONE "Today"
    /// header over the entire room and an order that was the sync's, not
    /// anybody's. Meanwhile the room's own head announced "4 offers expire this
    /// week" over a list sorted by nothing of the kind — the head and the rows
    /// describing two different books.
    ///
    /// Three groups, and each one is a fact the rows cannot state for
    /// themselves:
    ///
    ///  • **Coming up** — dated offers, soonest first. This is the room's
    ///    subject and the only thing in it that gets worse while you do
    ///    nothing.
    ///  • **No end date** — active, and CardPointers gave us no expiry. Named
    ///    rather than hidden: a room leading with "4 expire this week" over a
    ///    book where nine more have no date at all is quietly wrong about its
    ///    own completeness. This header is what let the head drop its footnote
    ///    (§208 — the fact now sits on the rows it is about).
    ///  • **Not active** — redeemed, expired, or deliberately snoozed. Before
    ///    §487 these were indistinguishable from live dateless offers, because
    ///    `heal` cleared the date and stamped nothing, so spent coupons sat in
    ///    the list looking available.
    ///
    /// **A past-dated ACTIVE offer leads "Coming up" rather than getting a
    /// group of its own.** Their `active` status is the authority on whether an
    /// offer is over and a date we parsed is not (the ruling `CardPointers.room`
    /// already makes), so while they still call it live we still list it as
    /// something to act on — and the row's own subtitle reads "3 days ago", so
    /// nothing is claimed that is not true. It is a transient state in any
    /// case: the next sync flips the status and the row moves.
    private func cardPointersGroups(_ visible: [Thing]) -> [(String, [Thing])] {
        let now = Date.now
        var ahead: [(Thing, Date)] = []
        var dateless: [Thing] = []
        var notActive: [Thing] = []
        // Live at the BOUNDARY, before any stored property is read (corollary
        // 4) — `visible` may be a debounced snapshot.
        for thing in visible.live {
            if thing.mark == .done {
                notActive.append(thing)
            } else if let due = thing.dueAt {
                ahead.append((thing, due))
            } else {
                dateless.append(thing)
            }
        }
        // Total orders throughout: `capturedAt` is one shared instant in this
        // room, so it can break no tie, and a list that reshuffles between
        // opens over identical data reads as broken (§324).
        let dated = ahead
            .sorted { $0.1 == $1.1 ? $0.0.title < $1.0.title : $0.1 < $1.1 }
            .map(\.0)
        var out: [(String, [Thing])] = []
        if !dated.isEmpty { out.append((String(localized: "Coming up"), dated)) }
        if !dateless.isEmpty {
            out.append((String(localized: "No end date"),
                        dateless.sorted { $0.title < $1.title }))
        }
        if !notActive.isEmpty {
            out.append((String(localized: "Not active"),
                        notActive.sorted { $0.title < $1.title }))
        }
        return out
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
        // Walletbeat (prd §419) — the only head here whose subject is not the
        // person's own data at all, but somebody else's review of the software
        // they use. It reads stored ratings beside the landed rows.
        case walletbeat(WalletbeatRoom)
        // L2BEAT (prd §428) — Walletbeat's twin one layer down: somebody else's
        // review of the RAILS the person's money sits on, rather than of their
        // own data. It reads stored assessments beside the landed rows.
        case l2beat(L2beatRoom)
        // CardPointers (prd §420) — the offers on your cards, led by the one
        // that runs out soonest. The only head here whose subject is a
        // DEADLINE somebody else set.
        case cardPointers(CardPointers.Room)
        // The two CODE rooms (prd §401). GitHub had led with the contributions
        // heatmap since it shipped — a decorative card answering "how much did
        // I write", in the slot the rows that actually need you were competing
        // for. Radicle shipped headless on purpose (§400 refused the
        // `/activity` span strip), and this is the head that entry pointed at.
        case github(GitHubRoom)
        case radicle(RadicleRoom)
        // Ethrex Hegotá deliberately has NO case here (prd §500). Its room is
        // four sections of its own — figure, rail, switcher, list — which is
        // what Wallet does, and what keeps its rails on the ROOM's insets
        // rather than a card's.
        // The WALLET-RIDING seats that own a source room (2026-08-10, prd
        // §349). Aave/Morpho/Hyperliquid/Aerodrome/Uniswap still land under
        // `source: "Wallet"` and have no room of their own to head; their
        // readings are the Wallet room's balance card, DeFi tiles and
        // composition strip, which is where they belong.
        case peer(PeerRoom)
        // Altana's keystore (2026-08-18, prd §403) — the only wallet-riding
        // room whose subject is not money at all: which credentials can sign
        // in this account's name, and when each of them stops.
        case altana(AltanaRoom.Card)
        // R4.1 (2026-08-23) — the room had NO head at all: `Base Vibenet`
        // appeared nowhere in this file, so the one card this feature has
        // was drawn only on the setup screen, which you visit once.
        case vibenet(VibenetRoom)
        case privacyPools(PrivacyPoolsRoom)
        case gnosisPay(GnosisPayRoom)
        // A fourth wallet-riding seat (2026-08-11) — grouped by TOKEN rather
        // than by rail, since Railgun has no funding platform to rank.
        case railgun(RailgunRoom)
        // Safe (2026-08-11) — the fifth, and the one that earned its own
        // source rather than joining the fold at "Wallet" (`SafeBridge`'s
        // top-of-file doc, amendment (8)). Ranked by "your turn" rather than
        // a proportion — a Safe has no lead-token/lead-rail shape.
        case safe(SafeRoom)
        // X (2026-08-13, prd §375) — the first head over an IMPORT rather than
        // a live bridge, and the first that displaces a card the room already
        // drew (`FeedInsight.topicMap`). It declines under `XRoom`'s floors so
        // a shallow archive keeps the treemap; see that type's own note for
        // why the year rows carry each year's subject.
        case x(XRoom)
        // Instagram (2026-08-18, prd §389) — the second head over an import,
        // and the second that displaces a card the room already drew. It
        // carries `FeedInsight.leaderboard`'s board forward whole, which is
        // §349's rule rather than a courtesy; see `InstagramRoom`'s type note.
        case instagram(InstagramRoom)
        // The two journal rooms (2026-08-17, prd §398) — the first head serving
        // MORE THAN ONE source, and the only place in this enum where that is
        // right: Day One and Apple Journal hold the same object under two app
        // names, compose through one `JournalRoomSource`, and draw one card
        // that differs by a kicker and a hue. It carries its source so the card
        // can say which journal it is without storing a `Thing`.
        case journal(JournalRoom, source: String)
        // The four AGENT rooms (2026-08-23, prd §457) — the second head to
        // serve more than one source, and right here for the journal reason:
        // ChatGPT, Claude, Gemini and Claude Code hold the same object under
        // four product names, compose through one `AgentRoomSource`, and draw
        // one card that differs only by a hue. It carries its source so the
        // card can pick that hue without storing a `Thing`.
        case agent(AgentRoom, source: String)
    }

    /// Which rooms may lead with an anniversary, and what it reaches into.
    ///
    /// Two shapes, because the ROOMS are two shapes. The memories room asks only
    /// its picture tiles — a photograph is what it has, and an echo naming a
    /// saved chat there would open a wall of text where a tile was promised.
    /// The journal rooms ask their entries, which is every row they have.
    ///
    /// The import receipt is excluded for the reason every aggregate over these
    /// rooms excludes it (`Corpus.isImportReceipt`): "3 years ago today" over
    /// our own note about a sync is the app reminiscing about itself.
    private func journalAnniversary(shape: Shape, memoryTiles: [Thing],
                                    visible: [Thing]) -> OnThisDay.Echo? {
        if shape == .snapchat { return OnThisDay.find(in: memoryTiles) }
        guard JournalRoomSource.sources.contains(source) else { return nil }
        return OnThisDay.find(in: visible.live.filter {
            $0.kind == .note && !Corpus.isImportReceipt($0)
        })
    }

    /// True when this room draws no `SourceHead`, so a card that would
    /// otherwise be a SECOND lead can stand down (prd §401).
    ///
    /// Deliberately re-composes rather than caching: `sourceHead` is already
    /// evaluated once per body pass for the head itself, both sides are pure
    /// over the same array, and a cached flag is one more thing that can
    /// disagree with what actually drew.
    private var sourceHeadIsAbsent: Bool {
        sourceHead(liveVisible()) == nil
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
        case WalletbeatRoomSource.source:
            return WalletbeatRoomSource.compose(things: visible).map { .walletbeat($0) }
        case L2beatRoomSource.source:
            return L2beatRoomSource.compose(things: visible).map { .l2beat($0) }
        case CardPointersRoomSource.source:
            return CardPointersRoomSource.compose(things: visible).map { .cardPointers($0) }
        case GitHubRoomSource.source:
            return GitHubRoomSource.compose(things: visible).map { .github($0) }
        // Reads no rows at all — its subject is bridge STATE, since no landed
        // row can say a patch is still unresolved. See `RadicleRoomSource`.
        case RadicleRoomSource.source:
            return RadicleRoomSource.compose(things: visible).map { .radicle($0) }
        // Reads no rows at all — this seat lands none. Its subject is chain
        // state read live (`HegotaLiveState`), so there is nothing in `visible`
        // for it to replay — and no head CARD either: its room is four sections
        // of its own, Wallet's shape.
        // Composed from the SNAPSHOT the sweep wrote, not from `visible` — the
        // keys are chain state, not rows, and re-reading them on every draw
        // would spend an `eth_call` per scroll (`AltanaState`).
        case AltanaKeystore.source:
            // Scoped by the face rail, exactly as the wallet crown and the
            // vibenet card are (prd §488). Altana is in the Wallet CATEGORY,
            // so `WalletScopeRail` has drawn your wallet faces above this room
            // since §356 — and until now the card ignored the pick entirely,
            // so ringing a face changed the rows beneath and left the head
            // describing every account. A scope control the head does not obey
            // is the dead control §83 bans.
            return AltanaRoom.card(scope: selectedWallet).map { .altana($0) }
        // Composed from the SNAPSHOT the sweep wrote, exactly like Altana
        // above and for the same reason: this room's subject is chain
        // state, and composing it live would spend an `eth_call` per
        // scroll. See `VibenetState`.
        case VibenetIdentity.source:
            // Scoped by the face rail, exactly as the wallet crown is
            // (2026-08-23): pick one and the card describes that account
            // alone; pick All and it describes them all.
            return VibenetRoomSource.card()
                .map { $0.scoped(to: chrome.vibenetScope) }
                .map { .vibenet($0) }
        case PeerRoomSource.source:
            return PeerRoomSource.compose(things: visible).map { .peer($0) }
        case PrivacyPoolsRoomSource.source:
            return PrivacyPoolsRoomSource.compose(things: visible).map { .privacyPools($0) }
        case GnosisPayRoomSource.source:
            return GnosisPayRoomSource.compose(things: visible).map { .gnosisPay($0) }
        case RailgunRoomSource.source:
            return RailgunRoomSource.compose(things: visible).map { .railgun($0) }
        case SafeRoomSource.source:
            return SafeRoomSource.compose(things: visible).map { .safe($0) }
        case XRoomSource.source:
            return XRoomSource.compose(things: visible).map { .x($0) }
        case InstagramRoomSource.source:
            return InstagramRoomSource.compose(things: visible).map { .instagram($0) }
        case let name where JournalRoomSource.sources.contains(name):
            return JournalRoomSource.compose(things: visible).map { .journal($0, source: name) }
        case let name where AgentRoomSource.sources.contains(name):
            // `rivals` is a SEPARATE store read (see `AgentRoomSource.compose`'s
            // doc) — `visible` here is this room's own rows and can never hold
            // another seat's, which is exactly the shape `things=14` on a
            // 14-row room proved on the probe's first real run.
            return AgentRoomSource.compose(
                source: name, things: visible,
                rivals: AgentRoomSource.rivals(besides: name, context: modelContext))
                .map { .agent($0, source: name) }
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

    /// Open a year's loudest post (2026-08-13, prd §375). A year owns hundreds
    /// of rows, so like every other head that ranks a group this hands back a
    /// value and the lookup lands here.
    ///
    /// Two landings, and the fallback is the point: an archive vintage that
    /// recorded no `favorite_count` has no loudest post to name, and a card
    /// whose tap did nothing would be a dead control (P4). So a year with no
    /// counts opens its NEWEST post instead — still that year, still a real
    /// row, and never a claim about reach we don't have.
    private func openYear(_ year: XRoom.Year, in visible: [Thing]) {
        if let ref = year.loudestRef {
            openBySourceRef(ref, in: visible)
            return
        }
        let calendar = Calendar.current
        openNewest(source: XRoomSource.source, in: visible) { thing in
            thing.kind == .note
                && calendar.component(.year, from: thing.capturedAt) == year.year
        }
    }

    /// Open a journal year's last entry (2026-08-17, prd §398). A year owns
    /// hundreds of entries, so like every other head that ranks a group this
    /// hands back a value and the lookup lands here.
    ///
    /// The fallback is `openYear`'s and exists for the same reason — a card
    /// whose tap did nothing would be a dead control (P4) — but the PRIMARY
    /// landing differs, and deliberately: an X year opens its most-liked post
    /// because an archive records popularity, and a journal records none at
    /// all, so the honest answer is simply the last thing written that year.
    private func openJournalYear(_ year: JournalRoom.Year, source name: String,
                                 in visible: [Thing]) {
        if let ref = year.newestRef {
            openBySourceRef(ref, in: visible)
            return
        }
        let calendar = Calendar.current
        openNewest(source: name, in: visible) { thing in
            thing.kind == .note
                && calendar.component(.year, from: thing.capturedAt) == year.year
        }
    }

    /// A tapped MONTH opens that month's last conversation (2026-08-23, prd
    /// §457) — `openJournalYear` one unit down, and for its reason: an agent
    /// room records no popularity of any kind, so there is nothing to rank a
    /// month's conversations by and the honest landing is simply the last one.
    ///
    /// The fallback re-derives the month from `capturedAt` against the SAME
    /// packing `AgentRoomSource` used, or a tap would land in a neighbouring
    /// month — which looks like the card pointing at the wrong bar.
    private func openAgentMonth(_ month: AgentRoom.Month, source name: String,
                                in visible: [Thing]) {
        if let ref = month.newestRef {
            openBySourceRef(ref, in: visible)
            return
        }
        let calendar = Calendar.current
        openNewest(source: name, in: visible) { thing in
            guard thing.kind == .chat else { return false }
            let parts = calendar.dateComponents([.year, .month], from: thing.capturedAt)
            return (parts.year ?? 0) * 12 + ((parts.month ?? 1) - 1) == month.month
        }
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
    /// What a tapped bar does, or nil for a board with nowhere to go
    /// (2026-08-23, prd §455).
    ///
    /// One place, so the two destinations can never both apply to one room:
    /// X's board opens a person room, a scoped board narrows this one, and a
    /// board with neither keeps the plain untappable row `LeaderboardHero`
    /// has always drawn for it.
    private func leaderboardPick(
        _ board: FeedInsight.Leaderboard) -> ((FeedInsight.LeaderRow) -> Void)? {
        if source == XPersonSource.source {
            return { row in
                feedSheet = .person(source: XPersonSource.source, handle: row.label)
            }
        }
        guard let scope = board.scope else { return nil }
        return { row in
            // Tapping the row you are already scoped to CLEARS it. The board
            // is the only control this scope has, so it has to be able to
            // undo itself — a narrowing with no way out is the dead end §83
            // forbids, and a separate "clear" chip for a state most readers
            // will never enter is chrome on every other visit.
            withAnimation(DS.Motion.standard) {
                readingScope = readingScope?.label == row.label
                    ? nil
                    : ReadingScope(label: row.label, scope: scope)
            }
        }
    }

    /// The board as the switcher says it: unchanged, except that a narrowed
    /// room replaces the subtitle's tally with what is actually on screen and
    /// how to leave.
    ///
    /// The tally is the right subtitle for a READING and the wrong one for a
    /// narrowed room — it counts every story while the rows below show one
    /// publisher's, which is the two-surfaces-disagreeing failure this file
    /// already forbids one level up. Replaced rather than appended: the count
    /// is recoverable by tapping back to all, and a subtitle carrying both is
    /// a sentence nobody finishes.
    private func scopedBoard(_ board: FeedInsight.Leaderboard) -> FeedInsight.Leaderboard {
        guard let scope = readingScope else { return board }
        return FeedInsight.Leaderboard(
            title: board.title,
            subtitle: String(localized: "Showing \(scope.label) · tap again for all"),
            rows: board.rows,
            scope: board.scope)
    }

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

    /// How many transactions lead the room from inside the balance card
    /// (2026-08-18, user ruling — the answer to "the transactions are at the
    /// end"). THREE, and the number is the whole design: it is what fits above
    /// the fold under a shortened chart, and the moment it grows it stops
    /// being a glance and becomes the stream a second time.
    ///
    /// The two rejected fixes are worth recording, because both were drawn
    /// before this one won. FOLDING the standing cards (Liquidity, Perps, a
    /// changeless Approvals into one "Positions" card) buys the same height
    /// and costs a room the user likes: "don't collapse the rest of the
    /// stuff." MOVING the whole stream up front-loads a room that may hold
    /// hundreds of rows, and re-litigates the load-bearing hero → ink →
    /// treemap adjacency below. A three-row card costs ~140pt, hides nothing
    /// (every row it takes is still one tap away, and the rest of the stream
    /// still reads below), and leaves every card in the room exactly where it
    /// was.
    private static let walletTodayRows = 3

    /// The wallet room's two cards are TRANSLUCENT (prd §160): they sit on the
    /// crown pour, and an opaque surface would punch a hole in the one
    /// atmospheric move the shell makes. One constant so the balance card and
    /// the holdings card can never drift apart.
    // ONE source (2026-08-22). This was its own `0.82`, a second copy of
    // `WalletCardStyle.fill` sitting in a different file — which is how a
    // room ends up at two opacities, the exact drift that type's own doc
    // was written to prevent.
    private static let walletCardFill = WalletCardStyle.fill

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
    /// - Parameters:
    ///   - latest: the newest stream rows, led from inside this card
    ///     (`walletTodayCard`). Named apart from the balance's own `total`
    ///     below, which is money — these two numbers count different things
    ///     and a shadowed name here would be a silent wrong figure.
    ///   - streamTotal: how many rows the stream holds in all, for the card's
    ///     own door.
    @ViewBuilder
    private func walletTilesSection(_ visible: [Thing],
                                    latest: [Thing] = [],
                                    streamTotal: Int = 0,
                                    // **THE SPARKLINE IS HOME'S VISUAL, not the
                                    // room's furniture (prd §483, user ruling:
                                    // "above the toggles is always a visual of
                                    // some kind and then a list below it").**
                                    // Every scope owns one drawing and one
                                    // list; Home's drawing happens to be the
                                    // line. In every other scope the line steps
                                    // aside for that scope's own figure, so the
                                    // room never stacks two large drawings.
                                    drawsChart: Bool = true) -> some View {
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
        // `latest` joins the gate for the same reason `composition` did: a
        // wallet with no priced holdings, no line and no warning still has
        // transactions, and without this the one card that shows them would
        // never render at all.
        if chart != nil || total != nil || !warnings.isEmpty || !composition.isEmpty
            || !latest.isEmpty {
                            // ONE card (prd §212, 2026-07-25) — the balance, the per-wallet
                // split, and the security read. Three parcels of equal weight
                // until this pass, and they were never three subjects: "what's
                // it worth", "whose is it", "is it okay" are the questions of a
                // single glance at a single number.
                //
                // **The MONEY half now wears the bright card** (2026-08-15) and
                // the rest of that card stays ink, which splits §212's single
                // parcel in two. The reason is the one this pass keeps
                // arriving at: colour is information, so it may only cover the
                // rows it is true of. "What's it worth" is the reading this
                // room exists for and is the app's most natural home for the
                // Messages register — one hero number over one list is what
                // §212 built. "Is it okay" is a WARNING, and a saturated card
                // under "this grant reaches $4,120" dresses it as a
                // celebration; §83's honesty rule forbids exactly that kind of
                // true-sounding surface. So the split is not two subjects
                // after all — it is one subject and one caution about it, and
                // they were never the same glance.
                //
                // The two still read as one system: same corner radius, same
                // insets, stacked with the section's own spacing, so this is
                // one card that changed weight partway down rather than the
                // six parcels §212 collapsed.
                // ONE list row still, and that outer stack is what keeps it
                // one: two siblings under a `Section` are two rows, each
                // taking the List's own background and insets, which would
                // undo both the card geometry and the entrance below.
                VStack(alignment: .leading, spacing: DS.Space.s3) {
                // Guarded as a whole for the same reason the caution block
                // below is: the section renders whenever ANY of its four
                // inputs exist, so a wallet whose money is entirely in
                // protocols (§240's own case — no priced holdings, no line)
                // would otherwise paint a bright card with nothing in it.
                if chart != nil || total != nil {
                VStack(alignment: .leading, spacing: DS.Space.s3) {
                    do {
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
                        // SCOPED, THIS LINE IS THE WALLET'S NAME (prd §450).
                        // The rail above stopped captioning its faces on the
                        // strength of this slot existing — so when it is set,
                        // it outranks both of the descriptive captions below,
                        // and the chevron stays away for the reason it always
                        // did (`hasBreakdown` is false while scoped: there is
                        // no split behind a single wallet to open).
                        //
                        // A single-wallet install has no rail at all
                        // (`WalletScopeRail.shows` wants > 1 watched) and no
                        // scope, so it keeps "Balance" exactly as before.
                        let scoped = selectedWallet.map {
                            WalletScopeRail.caption(for: $0, in: wallet.addresses)
                        }
                        WalletBalanceHeadline(
                            total: total,
                            chart: chart,
                            marks: drawsChart
                                ? walletMarks(dates: windowed.map(\.at), things: visible)
                                : [],
                            // ALWAYS "accounts", never "wallets" (user ruling,
                            // prd §483, 2026-08-26). This forked on whether any
                            // holder was an EXCHANGE — "accounts" when one was,
                            // "wallets" when they were all self-custodied — a
                            // distinction the person reading it never asked for
                            // and which made the same line change wording on
                            // them when they connected a venue. "Accounts" is
                            // true of both, and it is the noun the rail
                            // directly below now uses for the same faces.
                            // **THE CAPTION NAMES THE SCOPE, OR SAYS NOTHING**
                            // (user, prd §483: *"should we get rid of this
                            // since user is on 'All'? is it redundant?"* — yes).
                            // Scoped, this is the wallet's own name and is the
                            // only place it appears (§450). Unscoped it read
                            // "Across your accounts", which is precisely what
                            // the lit "All" on the rail below already says —
                            // and a bare figure is what Apple Card and Stocks
                            // both show. Dropping it also buys back a row
                            // toward getting three transactions above the fold.
                            //
                            // "Balance" survives for the single-wallet install,
                            // which has no rail at all (`WalletScopeRail.shows`
                            // wants > 1) and so has nothing else naming it.
                            caption: scoped?.name
                                ?? (hasBreakdown ? "" : String(localized: "Balance")),
                            captionAddress: selectedWallet,
                            captionDetail: scoped?.detail,
                            // An empty caption must take NO height, or dropping
                            // the word leaves its row behind — a 20pt gap under
                            // the venue rail with nothing in it.
                            hidesEmptyCaption: true,
                            // No mover line and a shorter chart — see the
                            // parameters' own docs (prd §483).
                            mover: nil,
                            drawsChart: drawsChart,
                            drawsReading: drawsChart,
                            chartHeight: 96,
                            ranges: ranges,
                            range: active,
                            onPickRange: { r in
                                balanceRange = r
                                r.remember()
                            },
                            onOpen: nil,
                            // FALSE again (2026-08-16): the hero has no
                            // coloured ground to sit on, so the line takes
                            // back its own direction accent — the whole
                            // reason `onColor` whitened it was that red on
                            // saturated blue measured ~1.35:1, and there is
                            // no blue now. The flag survives for any future
                            // caller that does paint a ground.
                            onColor: false,
                            onOpenMark: { id in
                                feedSheet = visible.first { $0.id == id }.map(FeedSheetRoute.thing)
                            })
                    }
                    // Whose the number is (prd §212) — only unscoped and only
                    // with more than one wallet carrying a real line, exactly
                    // the guard the retired "Each wallet" card kept. A tap
                    // scopes the whole feed, the move the switcher bar makes.
                    // THE VALUE PILLS ARE GONE (user ruling, prd §483,
                    // 2026-08-26: *"drop the value pills"*). They named each
                    // wallet's own total under the crown — and once the scope
                    // rail moved out of the pinned chrome and into the content
                    // directly below, the room drew the same wallets twice, in
                    // two adjacent rows of faces. That is the "we cannot have
                    // four rows of chips" complaint reappearing one level down.
                    //
                    // The rail is the row that survives because it is the
                    // INTERACTIVE one: it scopes, it carries the book door, and
                    // the figure each pill used to state is the crown directly
                    // above it once a face is picked. What is genuinely lost is
                    // every wallet's total AT A GLANCE, without picking — say so
                    // rather than pretend the move was free. §212's "whose the
                    // number is" question is now answered by the rail's lit
                    // face rather than by a row of figures.
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // NO HORIZONTAL PADDING (2026-08-22). It carried s4, which put
                // the hero's figure 36pt from the screen edge — the line every
                // CARD's text sits on, because a card adds its own s4 inside
                // the row's own s4. But this hero has no card, and the room's
                // other chrome-less text — the group headers below — sits at
                // 18. Two bare elements on two different margins is the kind of
                // misalignment you see before you can name it. The number now
                // leads on the same line as the headings that follow it, which
                // is where a bare hero sits in Stocks and in Apple Card.
                .padding(.vertical, DS.Space.s2)
                // NO GROUND AT ALL (2026-08-16, the Apple redraw — retiring
                // the `DS.tint` card this carried for a day). Apple has never
                // shipped a balance inside a coloured card: Apple Card's sits
                // on a plain surface, Stocks' quote on black. The figure, the
                // move and the chart ARE the hero; a container around them was
                // the app claiming emphasis the content already had. It also
                // ends the two-blues problem by deletion — the only blue left
                // in the room is chrome — and it restores something the card
                // structurally prevented: on a DOWN day this hero is red, top
                // to bottom, because every colour on it now comes from the
                // data rather than from the surface.
                }

                // WHAT JUST HAPPENED, directly under the number it moved
                // (2026-08-18, user ruling). The room's transactions used to
                // begin after ten standing cards, so on a busy wallet the one
                // thing a wallet app gets opened for was two screens down. This
                // is the whole fix, and deliberately the SMALLEST one that
                // works: three rows, nothing else folded, every card below
                // exactly where it was.
                //
                // ABOVE the caution block on purpose. That block's own ordering
                // note (below) is about the hero and the TREEMAP reading as one
                // blue mass with no ink between them — still true, and now
                // doubly satisfied, since this card is ink too. What it is not
                // is a reason to seat a security warning between the balance
                // and the transactions that moved it: this card and the hero
                // are one glance ("it moved — here's what moved"), and the
                // caution answers a different question.
                if !latest.isEmpty {
                    walletTodayCard(latest, streamTotal: streamTotal)
                }

                // …and the caution presses back in ink. ORDERING IS
                // LOAD-BEARING (2026-08-15, wallet cohesion pass): this ink
                // card sits BETWEEN the bright hero above and the holdings
                // treemap below, and that is not incidental — the hero is the
                // room's one bright object, the treemap is a large blue-ish
                // figure, and without ink between them the two read as one
                // oversized blue mass. A future reshuffle that puts the
                // treemap directly under the hero should re-litigate that
                // adjacency, not inherit it. GUARDED as a whole,
                // which it never had to be while it shared the balance's card:
                // an unguarded empty stack used to cost nothing, and now it
                // would draw a surface with nothing on it for every wallet
                // that holds no protocol position and has no warning — which
                // is most of them.
                }
                // Each piece arrives on its own clock — the balance reads off
                // already-recorded samples (instant) while warnings/holdings/
                // lending wait on live reads (2026-07-20: "balance shows then
                // the others pop in but looks unintentional"). The card is one
                // entrance now that the three ride inside it; the pieces still
                // appear as they land, they just no longer each stage a
                // separate surface into the room.
                .modifier(RowEntrance(index: 0, wave: shapeWave, style: entranceStyle))
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

    // MARK: - The wallet room's section headers

    /// A named block of the wallet room (2026-08-20, user ruling: *"should
    /// there be section headers between things"*).
    ///
    /// The room stacks up to nine live-state cards before the stream, and its
    /// arc — what you hold, what it's doing, who can reach it, what's ahead —
    /// existed only in the `.wallet` case's own comments. On screen it read as
    /// nine slabs of equal weight with no landmarks: no orientation, no sense
    /// of how much was left, which is what "it seems like a long feed" is
    /// describing. These are the landmarks.
    ///
    /// **The card labels STAY.** A header names the block; a card's own
    /// `WalletSectionLabel` distinguishes it from its SIBLINGS inside that
    /// block — "Lending", "Liquidity" and "Perps" all sit under "What it's
    /// doing" and are indistinguishable without their names. The one label
    /// that goes is `walletComingUpSection`'s, which said exactly what its
    /// header now says (§208: never say one thing twice).
    ///
    /// **The grammar is the stream's own day header**, verbatim — `heading22`
    /// in primary ink at the same insets. That is deliberate on two counts:
    /// this room already had a group-header tier and it was the day names, so
    /// "What you hold" and "Today" are peers because they ARE peers (both are
    /// top-level blocks of one room); and a second, smaller tier would mean
    /// inventing a rung the ramp doesn't carry between `heading22` and
    /// `label12`, for one screen.
    ///
    /// **Never rendered over nothing.** Every card here self-gates, so a
    /// header emitted unconditionally would promise content on the wallets
    /// that have least of it — a "What it's doing" over a wallet with no
    /// positions is worse than no header at all, because a header is a claim
    /// that something follows. Hence the hoisted predicates below: each one
    /// asks the same question its cards ask, so the header and the block can
    /// never disagree.
    ///
    /// The hero (balance + flow) deliberately gets NO header — a title above
    /// the first thing on a screen is noise, and the room's own name is the
    /// chip you tapped to get here.
    private func walletGroupHeader(_ title: String) -> some View {
        Section {
            Text(title)
                .dsText(.heading22)
                .foregroundStyle(DS.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
                // Index 0 so the header LEADS its block's stagger rather than
                // popping in ahead of it — every other row in this room wears
                // this entrance, and a header that didn't would be the one
                // thing on screen that arrives without the wave.
                .modifier(RowEntrance(index: 0, wave: shapeWave, style: entranceStyle))
                .padding(.leading, DS.Space.s4)
                // s8 above, s1 below (2026-08-22). At s6/s1 the header sat
                // 24 from the card it left and 14 from the card it names —
                // near enough to even that it read as floating between the
                // two rather than belonging to the one below. The gap above
                // has to beat the gap below by enough to be seen doing it;
                // 32 against 14 is that. (Below is s1 plus the next card's
                // own s3, which is why this is not simply doubled.)
                .padding(.top, DS.Space.s8)
                .padding(.bottom, DS.Space.s1)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
    }

    /// The picked-NFT shelf's wallet, or nil when the shelf draws nothing.
    ///
    /// Hoisted out of `walletNFTSection` (2026-08-20) so the "What you hold"
    /// header can ask whether that block has a second card without restating
    /// the gate — two copies of this condition is how a header starts
    /// appearing over an absent shelf.
    private var nftShelfEntry: WalletStore.WatchedAddress? {
        guard let entry = nftShelfWallet else { return nil }
        // Gated on state the ROOM owns (`nftHasCollections`, filled by
        // `loadWalletLive`), never on state the card would have to be alive to
        // fetch — see that function for the pruning trap this avoids.
        guard DemoMode.isActive || nftHasCollections
                || WalletNFTStore.shared.hasPicks(wallet: entry.address)
        else { return nil }
        return entry
    }

    /// Every leveraged position on one axis, or nil when there are fewer than
    /// two to compare. Hoisted for `nftShelfEntry`'s reason.
    private var walletRiskEntries: [WalletRiskScale.Entry]? {
        WalletRiskScaleSource.strip(aave: walletLive.positions,
                                    morpho: walletLive.morpho,
                                    hyperliquid: walletLive.hyperliquid)
    }

    // MARK: - Walking from the risk axis to a card (prd §417)

    /// Scroll anchors for the two cards the risk strip's dots can reach.
    /// Spelled once here and attached with `.id(…)` below, so the tap and the
    /// target can't drift apart.
    private static let lendingAnchor = "wallet.card.lending"
    private static let perpsAnchor = "wallet.card.perps"
    /// Reached from the Worth-a-look sheet's approvals walk row (prd §449),
    /// not from the risk axis — approvals aren't a leveraged position and have
    /// no dot. Spelled here beside its siblings so all three anchors and their
    /// `.id(…)` sites stay in one place.
    private static let approvalsAnchor = "wallet.card.approvals"

    /// Which card states the position behind a dot, from the entry id
    /// `WalletRiskScaleSource` stamped.
    ///
    /// **Matched on the id's namespace, never on the label** — a label is
    /// localized display text ("Morpho · wstETH/USDC"), so keying on it would
    /// send a Spanish device nowhere. nil is a deliberate, safe outcome: a
    /// protocol that joins the axis without a card here scrolls nowhere rather
    /// than scrolling to the wrong card.
    private static func riskCardAnchor(for id: String) -> String? {
        if id.hasPrefix("aave:") || id.hasPrefix("morpho:") { return lendingAnchor }
        if id.hasPrefix("hl:") { return perpsAnchor }
        return nil
    }

    /// The holdings card's tail — the book's shape on the left, the door to
    /// the whole allocation on the right, in ONE tertiary row (2026-08-22,
    /// prd §447).
    ///
    /// **This is what a four-line block reduced to.** §417 promoted the
    /// concentration sentence to a `heading22` lead above the map, on the
    /// reasoning that Lending and Approvals lead with their reading; that was
    /// right for those cards and wrong here, because the §417 group headers
    /// landed a 22pt "What you hold" in the same pass — so the card opened
    /// with two stacked 22pt lines, and the map under them opened with its own
    /// eyebrow repeating the header word for word. Three voices before the
    /// drawing. The reading is not deleted, it is demoted to where its sibling
    /// already lived.
    ///
    /// **What survives is exactly the pair the treemap cannot draw**, which is
    /// the test every cut here was made against: `UnitTreemap` is rank-ordered
    /// rather than area-proportional, so it cannot state a share; and stables
    /// are scattered across its cells by symbol, so it cannot group them. Both
    /// halves are composed by `WalletPortfolio.shapeLine`, never assembled
    /// here — a sentence built in a view would be a second definition of
    /// concentration, and the two would drift.
    ///
    /// Guarded as a WHOLE rather than per-child: both halves self-gate (a
    /// single-position book has no shape, a single wallet has no door), so an
    /// unguarded row would take a spacing slot in the card's stack and draw
    /// nothing in it.
    @ViewBuilder
    private var holdingsTail: some View {
        if let portfolio, !portfolio.isEmpty,
           portfolio.shapeLine != nil || portfolio.walletCount > 1 {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                if let shape = portfolio.shapeLine {
                    Text(shape)
                        .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                Spacer(minLength: 0)
                WalletAllocationDoor(
                    portfolio: portfolio,
                    onOpen: portfolio.walletCount > 1 && selectedWallet == nil
                        ? { feedSheet = .allocation } : nil)
            }
            .padding(.horizontal, DS.Space.s4)
            // s2 from the stack + s1 here = s3 of air under the drawing. A
            // caption sits closer to its figure than two cards sit to each
            // other, and at the bare s2 the row read as a seventh cell.
            .padding(.top, DS.Space.s1)
        }
    }

    /// Does the "What you hold" block have anything in it — the treemap, the
    /// NFT shelf, or both.
    private var walletHoldsSomething: Bool {
        !blockStream.els.isEmpty || nftShelfEntry != nil
    }

    /// Does the "What it's doing" block have anything in it.
    ///
    /// The risk strip is derived FROM the three books below it, so it can
    /// never be the only thing here — it is named anyway rather than inferred,
    /// because "the strip implies a book" is a cross-file fact that would fail
    /// silently the day either side changes.
    private var walletDoingSomething: Bool {
        walletRiskEntries != nil
            || !walletLive.positions.isEmpty
            || !walletLive.morpho.isEmpty
            || !walletLive.uniswap.isEmpty
            || !walletLive.hyperliquid.positions.isEmpty
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
                            WalletFlowBand(band: band, windowLabel: balanceRange.flowLabel,
                               spineAddress: spineWalletAddress)
                    .modifier(RowEntrance(index: 1, wave: shapeWave, style: entranceStyle))
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

    /// Whose NFT shelf this room draws (2026-08-15, prd §387) — the scoped
    /// wallet, or the sole watched one.
    ///
    /// nil when several wallets are merged, and the shelf then draws nothing:
    /// a pick is made PER WALLET, so a merged shelf would have to say whose
    /// each piece is, and this room already declines to speak for merged
    /// wallets rather than invent an attribution (`spineWalletAddress`, same
    /// reasoning applied to a portrait). The wallet switcher is pinned above
    /// the room, so narrowing to one is a tap away.
    private var nftShelfWallet: WalletStore.WatchedAddress? {
        let watched = wallet.addresses
        if let selectedWallet {
            return watched.first { WalletWatch.sameAddress($0.address, selectedWallet) }
        }
        // **UNSCOPED FALLS BACK TO THE FIRST WALLET WITH PICKS, not to nil**
        // (2026-08-26, prd §483). The old `count == 1` rule predates the NFTs
        // SCOPE existing: it was written when this card sat inside one long
        // room, where showing one wallet's art unscoped would have been a
        // silent claim about all of them. As a scope it is worse than
        // conservative, it is broken — anybody watching two wallets got a
        // chip that could never appear, however many collections they had
        // picked, with no way to find out why short of unwatching a wallet.
        //
        // The pick book is what makes the fallback honest: a wallet only
        // qualifies here because its owner named collections FOR it, so the
        // shelf is answering a question that was actually asked. Watch order,
        // never "the one with the most" — a shelf that reshuffles when an
        // airdrop lands reads as broken (§292's total-order rule).
        if watched.count == 1 { return watched.first }
        // The demo has no pick book by ruling (§387 — a picker there teaches a
        // decision that evaporates), so the pick test below would always fail
        // and the scope could never appear in the one place it MUST (the demo
        // is the north star, and a scope invisible there is a feature nobody
        // sees).
        if DemoMode.isActive { return watched.first }
        return watched.first { WalletNFTStore.shared.hasPicks(wallet: $0.address) }
    }

    /// The collections behind the quad, one row each (prd §483, 2026-08-26).
    ///
    /// A separate section rather than a `layout` branch inside one call so the
    /// room's own rule holds: ONE drawing in the slot, ONE list below, and the
    /// slot is height-clipped while the list is not. Both read the same
    /// cached pick fetch, so the pair costs one network read, not two.
    ///
    /// **No price on these rows**, which is the whole reason they can say what
    /// they say: §387 refused a floor and §481 refused it again, on the same
    /// ground — a floor is a bid on the thinnest book in this app, it moves
    /// without you, and printing one puts a number people believe (§83)
    /// beside art somebody keeps for reasons that are not the number. The
    /// shelf stores no value anywhere, so there is nothing here to round.
    @ViewBuilder
    private var walletNFTListSection: some View {
        if let entry = nftShelfEntry {
            Section {
                WalletNFTCollectionRows(
                    wallet: entry.address,
                    onEdit: { feedSheet = .nftPicks(address: entry.address,
                                                    label: entry.label.isEmpty ? entry.short : entry.label) })
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(WalletCardStyle.rowInsets)
            }
        }
    }

    /// The picked-NFT shelf. Renders nothing at all for a wallet with no picks
    /// and no collections to pick — which is most wallets, and is why this is
    /// the one wallet card that can be completely absent without meaning a
    /// read failed.
    @ViewBuilder
    private var walletNFTSection: some View {
        // The gate itself lives in `nftShelfEntry` (2026-08-20) — the "What
        // you hold" header asks the same question, and one copy is what keeps
        // the header and this card from ever disagreeing.
        if let entry = nftShelfEntry {
                            WalletNFTShelfCard(
                    wallet: entry.address,
                    label: entry.label.isEmpty ? entry.short : entry.label,
                    onEdit: { feedSheet = .nftPicks(address: entry.address,
                                                    label: entry.label.isEmpty ? entry.short : entry.label) })
                    .modifier(RowEntrance(index: 2, wave: shapeWave, style: entranceStyle))
        }
    }

    /// Every leveraged position on one axis (2026-08-01, `WalletRiskStrip`),
    /// directly ABOVE the lending card it summarises — the cards below state
    /// each position in its own protocol's units, and this is the one view
    /// that puts them in an order. Declines under two positions, where the
    /// cards already say it better.
    @ViewBuilder
    private var walletRiskSection: some View {
        if let entries = walletRiskEntries {
                            WalletRiskStrip(entries: entries, onPick: { entry in
                    // Overview → detail (prd §417). The strip ranks every
                    // leveraged position on one axis; the card below states the
                    // one you picked in its own protocol's units. The target is
                    // derived from the entry's OWN id prefix, which
                    // `WalletRiskScaleSource` already builds — so a new
                    // protocol joining the axis lands on `nil` and simply
                    // doesn't scroll, rather than scrolling somewhere wrong.
                    cardScrollTarget = Self.riskCardAnchor(for: entry.id)
                })
                    .modifier(RowEntrance(index: 2, wave: shapeWave, style: entranceStyle))
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
    /// WHO CAN ACT FOR YOU — the `Permissions` scope's lead (prd §490).
    ///
    /// The scope had NO drawing at all until this: it opened straight onto the
    /// approvals list, which is the shape §247 named as the gap ("a room that
    /// leads with a list of its own rows"). The reading it leads with now is
    /// one the list structurally cannot make — a Safe module and an EIP-7702
    /// delegate have no dollar amount, so they can never be ranked into a card
    /// built on `min(allowance, balance) × price`, and they are the most
    /// dangerous things in this scope.
    ///
    /// Declines when there is genuinely nothing, which on most wallets is most
    /// of the time — no grants and nothing acting is the healthy state, and a
    /// card announcing it would be a permanent fixture saying "fine".
    @ViewBuilder
    private var walletPermissionsSection: some View {
        let holders = WalletPermissionsSource.holders(exposure: walletLive.exposure,
                                                      acting: walletLive.acting)
        if !holders.isEmpty {
                            WalletPermissionsCard(holders: holders)
                    .modifier(RowEntrance(index: 1, wave: shapeWave, style: entranceStyle))
                    .padding(.bottom, DS.Space.s3)
        }
    }

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
                .id(Self.approvalsAnchor)
                .modifier(RowEntrance(index: 2, wave: shapeWave, style: entranceStyle))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(WalletCardStyle.rowInsets)
            }
        }
    }

    /// Lending — Aave and Morpho for the wallets in scope, in ONE card as two
    /// rows (prd §212, 2026-07-25). They were two full cards until this pass;
    /// they were never two subjects, just two providers of one. The treemap
    /// says what you HOLD, this says what you OWE — which is why it earns a
    /// seat here rather than staying two taps down. Nothing renders without a
    /// position on either.
    /// Whether `walletDeFiSection` will draw — the gate spelled once so the
    /// Worth-a-look sheet's walk door and the card it points at can't disagree
    /// (prd §449).
    private var hasLendingCard: Bool {
        !walletLive.positions.isEmpty || !walletLive.morpho.isEmpty
    }

    @ViewBuilder
    private var walletDeFiSection: some View {
        if hasLendingCard {
            Section {
                WalletLendingCard(aave: walletLive.positions, morpho: walletLive.morpho)
                    // The risk strip's Aave and Morpho dots land here (§417).
                    .id(Self.lendingAnchor)
                    // Same reveal the balance card and holdings treemap wear —
                    // lending is usually the last of the live reads to land, so
                    // it gets the deepest stagger.
                    .modifier(RowEntrance(index: 2, wave: shapeWave, style: entranceStyle))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(WalletCardStyle.rowInsets)
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
                    .listRowInsets(WalletCardStyle.rowInsets)
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
                    // The risk strip's perp dots land here (§417).
                    .id(Self.perpsAnchor)
                    .modifier(RowEntrance(index: 4, wave: shapeWave, style: entranceStyle))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(WalletCardStyle.rowInsets)
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
                    // No label of its own since 2026-08-20: the group header
                    // directly above says "Coming up", and this card is the
                    // only thing under it (§208 — never say one thing twice).
                    // Every other card here keeps its label, because every
                    // other card has siblings to be told apart from.
                    //
                    // The rail says what the rows can't: whether these are
                    // bunched or spread (prd §417). Dates are read here, while
                    // the models are known live, and handed on as plain values
                    // — `WalletRunwayRail` never holds a `Thing` (the build-188
                    // leaf rule).
                    WalletRunwayRail(dates: upcoming.compactMap { $0.isLive ? $0.dueAt : nil })
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
                .padding(WalletCardStyle.pad)
                .dsWidgetSurface(fillOpacity: Self.walletCardFill)
                .modifier(RowEntrance(index: 5, wave: shapeWave, style: entranceStyle))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(WalletCardStyle.rowInsets)
            }
        }
    }

    /// "Closes Thursday" / "In 3 weeks" — when the deadline lands, in the
    /// grain that's actually useful at that distance. Guarded internally
    /// because it takes a raw `Thing` from a call site that may re-evaluate
    /// (corollary 4's rule for shared helpers).
    ///
    /// Forwards to `FeedLedeFace.dueLine` (prd §389 amendment) so the cover's
    /// countdown and this one are the same formatting — they sit on the same
    /// screen, often about the same thing, and two copies is where a countdown
    /// quietly starts disagreeing with itself depending on where you read it.
    private static func dueLine(_ thing: Thing) -> String? {
        guard thing.isLive, let due = thing.dueAt else { return nil }
        return FeedLedeFace.dueLine(due)
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

    /// The newest few transactions, drawn INSIDE the balance card
    /// (2026-08-18, user ruling: "the real answer is the user will want to see
    /// them above the fold").
    ///
    /// **Not a second row anatomy.** These are `BandRow`s with the money
    /// column, byte-identical to what the stream below draws, because §212's
    /// law for this room is one row shape and a compact variant here would be
    /// the second. So a row reads the same whether you meet it up top or two
    /// screens down, and the fold's rows and this card's can never disagree
    /// about how a transfer looks.
    ///
    /// **The door is the section label's count-link, not a centred see-all
    /// row.** `WalletRowChevron`'s own note records that this room once
    /// carried six grammars for "there's more" and that exactly two survived
    /// the §212 pass — a chevron on a row, and a count-link on a section
    /// label. This is the second one, at its documented shape.
    ///
    /// **Every row it takes, the stream gives up** (see the `.wallet` case's
    /// `led` set), so nothing is said twice and nothing is hidden: the rest of
    /// the stream still reads below, and the full history is one tap away.
    @ViewBuilder
    private func walletTodayCard(_ rows: [Thing], streamTotal: Int) -> some View {
        // Only when there IS more behind it — a wallet whose whole history is
        // these three rows would otherwise get a door onto what it can already
        // see (the honesty rule's dead-control clause).
        let hasMore = streamTotal > rows.count
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            WalletSectionLabel(
                title: walletLatestLabel(rows),
                // NO COUNTER (user ruling, prd §483: *"we can just say see all
                // activity or see activity. we dont need a counter"*). The
                // number was a second fact competing with the verb, and it is
                // the one that changes every sync.
                trailingTitle: hasMore ? String(localized: "See activity") : nil,
                onTapTrailing: hasMore
                    ? { route.pushBridge(.walletHistory(scope: selectedWallet)) }
                    : nil)
            ForEach(Array(rows.keyed.enumerated()), id: \.element.id) { i, item in
                // `live` INSIDE the closure, before any read (corollary 3):
                // this re-evaluates against the array it already holds when a
                // heal's delete lands.
                if let thing = item.live {
                    Button {
                        openThing(thing)
                    } label: {
                        BandRow(thing: thing, moneyColumn: true, rippleIndex: i)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(RowPress())
                    .dsHover()
                    .macHoverLift()
                }
            }
        }
        // **NO SURFACE (user ruling, prd §483: *"we need to put the
        // transactions that are showing outside of a card, remember we are
        // going to the restrained design?"*).** The rows sit bare on the page
        // and separate by air and heading weight, which is the direction's own
        // rule: text sections lose their box, DRAWINGS keep one. The sparkline
        // directly above still has its ground because `TokenChartPlot`'s fill
        // is calibrated against it; three rows of type need nothing.
        //
        // Only the horizontal inset survives, so the rows land on the same
        // 18pt margin the crown's figure and the toggle already sit on — a
        // card's own padding was what put them 36pt in.
        .padding(.vertical, DS.Space.s2)
    }

    /// What to call the card above — and the reason it is a function rather
    /// than the literal "Today" the mock carried.
    ///
    /// A day word is only honest while every row it covers falls on that day.
    /// A wallet that last moved in March would wear "Today" over three
    /// five-month-old transfers — §83's fake status, in the largest claim on
    /// the card. So the day label is used when the rows agree on a day (the
    /// ordinary case on an active wallet, where it reads exactly as asked),
    /// and the room's own neutral word otherwise. Each row carries its own
    /// timestamp either way, so nothing is lost by the fallback.
    private func walletLatestLabel(_ rows: [Thing]) -> String {
        let days = Set(rows.live.map { Self.groupingCalendar.startOfDay(for: $0.capturedAt) })
        if days.count == 1, let day = days.first { return dayLabel(day) }
        // **"Recent", not "Activity" (prd §483).** This fallback read "Activity"
        // until the scope strip took that word for a chip — and this card only
        // draws in the scopes where that chip is NOT selected, so the room said
        // "Activity" in a card 300pt below an "Activity" chip that was greyed
        // out. Two different things wearing one word, with the deselected one
        // implying the card belonged to a scope you were not in.
        return String(localized: "Recent")
    }

    private func walletStreamRows(_ things: [Thing]) -> [FeedRow] {
        var rows: [FeedRow] = []
        var run: [Thing] = []
        func flush() {
            guard !run.isEmpty else { return }
            if run.count >= Self.walletFoldMin, let newest = run.first {
                // Never ambient: these are transactions, which `tier` files as
                // concerning you by definition. Stated rather than derived
                // because this fold is the Wallet ROOM's, where §378's weight
                // axis does not run at all — the flag exists so the payload is
                // honest if it ever does.
                rows.append(.bundle(source: "Wallet",
                                    word: String(localized: "transfers"),
                                    count: run.count, newest: newest.capturedAt, art: [],
                                    ambient: false))
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
        ForEach(Array(groups.enumerated()), id: \.element.0) { groupIndex, group in
            let (label, dayRows) = group
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
                    case .strip(_, let word, let count, let newest, _):
                        // Drawn like `.bundle` above, and for that case's own
                        // reason rather than by copying it: the generic
                        // `stripListRow` opens the source filter, and this room
                        // IS the Wallet source, so that tap would be a control
                        // that does nothing. The door is the history screen.
                        // The tiles are dropped with it — a strip earns its
                        // picture row by having pictures, and a run of
                        // transactions has none to show.
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
                // The FIRST day heading sits directly under the scope
                // switcher, which already carries its own bottom inset — the
                // macro pad belongs BETWEEN days, not above the first one, and
                // spending it there opened a ~45pt dead band on Activity that
                // Home (whose lead section is a small header) never had.
                .padding(.top, groupIndex == 0 ? DS.Space.s1 : DS.Space.s6)
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


    /// The wallet leads with holdings — real, from Alchemy (WalletIngest),
    /// one treemap per watched address, same doc Home and the Wallet screen
    /// render (ruling 2026-07-09: the old mock demo-only block never showed a
    /// real user anything real).
    @ViewBuilder
    private var holdingsBlockSection: some View {
        if !blockStream.els.isEmpty {
                            VStack(alignment: .leading, spacing: DS.Space.s2) {
                    // THE DRAWING LEADS (2026-08-22, prd §447) — nothing above
                    // the map at all. §417 put the concentration sentence here
                    // at `heading22` on Lending's and Approvals' anatomy, and
                    // the same pass put a 22pt "What you hold" header directly
                    // above this card: two display lines stacked, then the
                    // map's own eyebrow saying the header's words again. The
                    // reading moved down to `holdingsTail`, beside the stables
                    // line it always belonged with; the header is the card's
                    // title and always was.
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
                    // The map says WHAT you hold; this one row says the two
                    // things it is structurally unable to say, and opens the
                    // rest. Three separate text objects until 2026-08-22 — see
                    // **THE TAIL LINE IS GONE** (user ruling, prd §483:
                    // *"get rid of the words"*). It carried a concentration
                    // sentence ("ETH 62% · 28% stables") and an "All 3 ›" door.
                    //
                    // Both were answers to a question the board alone could not
                    // settle — WHICH tokens, in what share — and the token list
                    // directly below the toggle now answers it properly, with
                    // every holding, its amount and its own percentage. The
                    // door in particular pointed at a tray showing less than
                    // the list it would have covered.
                }
                // The holdings CARD (prd §160) — title, map, and the
                // concentration line become one parcel. GenTagMap already
                // self-pads horizontally by s4, which becomes this card's
                // inner gutter; only the bottom needs closing, since the map
                // pads its own top.
                .padding(.bottom, DS.Space.s3)
                // **NO CARD** (user ruling, prd §483: *"your treemap is in a
                // card, we don't do cards"*). The room's drawings sit bare on
                // the page — the sparkline does, the flow diagram does, and a
                // surface under this one made it the only boxed figure left.
                //
                // **It IMPROVES the magnitude ramp rather than costing it**,
                // which is the opposite of what I assumed: `DS.ink`'s dark floor
                // is #131316 and the card was #111113 — two points apart, so the
                // quietest cell was very nearly invisible ON the card. Against
                // the #000 page it is nineteen points clear. The ramp is
                // untouched, and the user's "Darker" pick from 2026-08-10
                // stands.
                // The SECTION's own arrival, not the cells' — GenTagMap
                // already stages its cells once mounted; this is what
                // stops the whole treemap from hard-popping in the moment
                // the holdings read lands (2026-07-20, wallet streaming fix).
                .modifier(RowEntrance(index: 1, wave: shapeWave, style: entranceStyle))
                // The card needs the page gutter the bare map didn't (it used
                // to bleed to the screen edge and self-pad its cells).
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

    /// A connected-folder file whose heal has landed pixels — the mixed
    /// Files room's grid membership (2026-08-02), `isMemoryTile`'s shape with
    /// one addition: the extension check makes the picture claim explicit
    /// rather than inferring it from `previewImageData`, which is the heal's
    /// implementation detail and not this test's contract. Guarded internally
    /// for the same corollary-4 reason as above.
    ///
    /// `drawsAsPicture`, not `isImageRef`, since 2026-08-17 — a VIDEO's poster
    /// frame is pixels and tiles here too. The comment above used to say only
    /// images ever carry `previewImageData` under Files; that stopped being
    /// true the day the poster heal landed, which is exactly why the claim was
    /// written as an explicit test instead of a `previewImageData != nil`.
    private static func isFileImageTile(_ thing: Thing) -> Bool {
        thing.isLive && thing.source == "Files" && thing.kind == .file
            && thing.previewImageData != nil
            && FilesIngest.drawsAsPicture(thing.sourceRef)
    }

    /// A wordless picture in an Instagram export (2026-08-18, prd §389) — the
    /// mixed room's grid membership, `isXPhotoTile`'s shape one product over
    /// and for its exact reasons.
    ///
    /// Your own posts, reels and stories ONLY. A saved post's cover is a
    /// picture too, and it is deliberately not a tile: a save is somebody
    /// else's post that you kept for what it SAID as much as what it showed,
    /// and the caption `InstagramCaptions` fetches is the words the room exists
    /// to make searchable — extracting the picture into a grid would file the
    /// two halves of one thing in two places. It rides its own post card
    /// instead, cover and all.
    ///
    /// The test is the pixels plus the tag the importer stamps, never the
    /// title: that title is the localized word "Photo", and matching on it
    /// would empty this grid on every device that isn't in English. Guarded
    /// internally for the same corollary-4 reason as its three siblings.
    private static func isInstagramPhotoTile(_ thing: Thing) -> Bool {
        thing.isLive && thing.source == InstagramImport.source && thing.kind == .note
            && thing.previewImageData != nil
            && thing.tags.contains("Photo")
    }

    /// A wordless picture OR video post in an X archive (2026-08-13, prd §375;
    /// widened 2026-08-18, prd §396) — the mixed X room's grid membership,
    /// `isMemoryTile`'s shape one source over.
    ///
    /// THE TEST IS `postText == nil`, not the tag, and that changed with the
    /// videos. A wordless post is exactly one the importer gave no `postText`
    /// (`landTweets` writes it only from a non-empty body), which is a fact
    /// about the row rather than a word about the medium — so one test covers
    /// both tags and neither tag has to mean two things. It is never the
    /// title: that title is the localized word "Photo" or "Video", and
    /// matching on it would empty this grid on every device not in English.
    ///
    /// `Video` rides captioned posts too (see `landTweets`), which is exactly
    /// why the tag can no longer be the membership test: a video with a
    /// caption is a post card, and its caption is the post.
    ///
    /// Guarded internally for the same corollary-4 reason as its three
    /// siblings.
    private static func isXPhotoTile(_ thing: Thing) -> Bool {
        thing.isLive && thing.source == XRoomSource.source && thing.kind == .note
            && thing.previewImageData != nil
            && thing.postText == nil
            && (thing.tags.contains("Photo") || thing.tags.contains("Video"))
    }

    /// A wordless picture from a followed CHANNEL (2026-08-23, prd §456).
    ///
    /// Live rows only: an imported conversation or a saved message never
    /// becomes a tile, whatever it carries. The same honesty rule the three
    /// mixed rooms before it settled — a tile promises a picture, so a post
    /// with a caption stays a post card, because the caption is the post.
    private static func isTelegramPhotoTile(_ thing: Thing) -> Bool {
        thing.isLive && thing.source == TelegramChannel.source
            && Corpus.arrivedLive(thing)
            && thing.previewImageData != nil
            && (thing.postText ?? "").isEmpty
    }

    /// A tile whose picture is one FRAME of a video, so the grid can mark it.
    ///
    /// The mark is not decoration and its absence was a small lie: a poster
    /// frame is a still, and a still drawn with nothing to say otherwise reads
    /// as a photograph. `VideoMark`'s own doc settled the shape (cornered, no
    /// centred play button, no hits taken) — this is the test that decides
    /// which tiles wear it, in the two rooms that can hold one.
    private static func isVideoTile(_ thing: Thing) -> Bool {
        guard thing.isLive else { return false }
        if thing.source == XRoomSource.source { return thing.tags.contains("Video") }
        return FilesIngest.isVideoRef(thing.sourceRef)
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
        // An X picture post has no caption BY DEFINITION — that is the whole
        // test that made it a tile — and its title is the placeholder word the
        // importer gave it. Printing that under every cell would be a grid of
        // identical labels saying nothing.
        if thing.source == XRoomSource.source { return nil }
        // An Instagram picture post is a tile precisely BECAUSE it has no
        // caption; its title is the placeholder word the importer gave it, and
        // printing that under every cell is a grid of identical labels.
        if thing.source == InstagramImport.source { return nil }
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
                                              caption: Self.tileCaption(thing),
                                              video: Self.isVideoTile(thing))
                                }
                                // A photograph LIFTS under the finger (prd
                                // §384) where every control tile dips — a
                                // picture is picked up, not pushed. Was
                                // `DSTileButtonStyle` (2026-07-10).
                                .buttonStyle(PressLift())
                                .dsHover()
                                // …and BLOOMS under a cursor (2026-08-17). The
                                // vocabulary's media treatment, on the app's
                                // largest field of pictures: a photograph is
                                // the one row whose content you read by
                                // looking, so the cursor answers it by making
                                // it bigger rather than by lifting a card.
                                // Never paired with `macHoverLift` — one
                                // motion treatment per element.
                                .macHoverBloom()
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
                        .dsGlyph(11)
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
                                .dsGlyph(12)
                                .foregroundStyle(DS.textTertiary)
                        }
                        .padding(.vertical, DS.Space.s1)
                        .contentShape(Rectangle())
                        .onTapGesture { withAnimation(DS.Motion.standard) { staleExpanded = true } }
                        .dsTapCard()
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
        // A POST CARD NEVER MERGES, IN ANY OF THE SEVEN ROOMS THAT DRAW ONE
        // (2026-08-26, prd §489) — and the answer is DERIVED from the same
        // `rowKind` that picks the anatomy, never spelled beside it.
        //
        // That derivation is the fix. §396a happened because `shapedRow` and
        // this function answered "is this a post" in two places and drifted; it
        // was then repaired for X alone, and Instagram and Telegram went on
        // drawing post cards squeezed into a merged run of bare rows — a card
        // by anatomy with no card under it — in rooms nobody had reported.
        // Two more instances of one bug, in a registry the two new cases never
        // joined. There is now nothing to join: if `rowKind` says card, this
        // says card.
        if SocialRoom.drawsPosts(thing.source) {
            return SocialRoomSource.standsAlone(thing)
        }
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
    /// `shadowed: false` for a source-skinned row. §61's mechanic is that a
    /// RUN casts one silhouette because its middle rows are gapless and their
    /// shadows fall on an identical fill — a skinned row is always `.only`, so
    /// every row in the feed would cast its own, which is both forty offscreen
    /// blurs per screenful on the app's hottest scroll and a lift the colour
    /// has already done: a card that differs from the page in HUE does not
    /// need to differ from it in height as well.
    private func dayCardBackground(_ position: RunPosition,
                                   fill: Color = DS.surfaceSheet,
                                   shadowed: Bool = true) -> some View {
        let r = DS.Radius.card
        let top = position == .first || position == .only
        let bottom = position == .last || position == .only
        return UnevenRoundedRectangle(topLeadingRadius: top ? r : 0,
                                      bottomLeadingRadius: bottom ? r : 0,
                                      bottomTrailingRadius: bottom ? r : 0,
                                      topTrailingRadius: top ? r : 0,
                                      style: .continuous)
            .fill(fill)
            .padding(.horizontal, DS.Space.s4)
            .padding(.top, top ? DS.Space.s1 : 0)
            .padding(.bottom, bottom ? DS.Space.s1 : 0)
            .shadow(color: shadowed ? DS.cardShadow : .clear,
                    radius: shadowed ? 18 : 0, x: 0, y: shadowed ? 6 : 0)
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
    /// The row's card fill when the room mixes sources — nil everywhere else,
    /// and that nil is the ruling rather than an optimization (2026-08-15,
    /// user: "what if each row was a colored card from it's source").
    ///
    /// **Colour here says WHICH SOURCE, so it may only appear where the answer
    /// varies.** In the All room a screenful of hues tells you at a glance what
    /// your day was made of. Inside a source room every row would be the same
    /// hue — a permanent colour that says nothing, which is §297's own argument
    /// for draining the crown pour in exactly that room, and §8's colour law
    /// (identity, state, or nothing) reaching the row surface.
    ///
    /// Guards liveness FIRST, `standsAlone`'s reason verbatim: this is read in
    /// the argument list of the row builder, so it runs before `shapedRow`'s
    /// own guard, and `thing.source` is a stored property that fault-resolves
    /// against the store (corollary 3, build 176).
    /// NIL like its sibling below — see that function's note for the ruling.
    /// Kept (rather than deleted with its call sites) for the same
    /// dormant-not-deleted reason, and because its one historical lesson is
    /// worth the lines: when the rows DID wear colour, the first cut skinned
    /// only `shapedListRow` and missed this path entirely — the bundle and
    /// strip rows are most of what the All room actually draws, and a
    /// feature keyed off "a row" has to reach every row BUILDER, of which
    /// this screen has three.
    private func rowSkin(forSource source: String) -> DS.RowSkin? { nil }

    /// NIL, ALWAYS, AND ON PURPOSE (2026-08-15, the user's final ruling of
    /// the colour night: "i now feel like they all looked better solid
    /// black, including the all feed"). The row-colour experiment ran its
    /// full arc in one evening — raw brand fills, a solved uniform register,
    /// a 14% wash — and every strength was worse than the black it replaced,
    /// which is the 2026-07-22 "lists are air" ruling re-earned with three
    /// builds of evidence instead of taste. Rows are content on ink;
    /// provenance is the source name (`legibleInk`) and the icon; the app's
    /// colour budget is spent on ONE bright object per screen (the wallet
    /// hero, the brief's lede card) and on selection.
    ///
    /// The machinery stays (`DS.rowSkin`, the `skin:` plumbing through
    /// `runBackground`) — dormant-not-deleted, because the full arc is
    /// recorded in `computeRowSkin`'s own doc and deleting the plumbing would
    /// orphan that record. DO NOT re-enable without reading it: three
    /// strengths were built, shipped and rejected the same night.
    private func rowSkin(_ thing: Thing) -> DS.RowSkin? { nil }

    /// Rooms that hold more than one source. "All" is the one that always
    /// does; Pinboard is selected by `pinnedAt` rather than by source, so it
    /// mixes too. A folded category (Markets) resolves to a real seat before
    /// it reaches here, so it is correctly NOT in this set.
    private var roomMixesSources: Bool {
        source == "All" || source == Pinboard.room
    }

    @ViewBuilder
    private func runBackground(_ position: RunPosition, bare: Bool,
                               selected: Bool = false,
                               skin: DS.RowSkin? = nil) -> some View {
        if selected {
            selectionWash(position, bare: bare)
        } else if let skin {
            // A COLOURED ROW IS ALWAYS ITS OWN CARD — the run position is
            // deliberately ignored rather than threaded through. A run's whole
            // mechanic is that middle rows go square and GAPLESS so one
            // silhouette casts one shadow (§61), which is only true while every
            // row in it shares a fill; with a hue per source, a merged run
            // renders as butted stripes of different colours and the shadow
            // falls across the seam. Forcing `.only` here keeps that geometry
            // in the one function that owns it, instead of making five call
            // sites pass a breaker predicate they have no reason to know about.
            dayCardBackground(.only, fill: skin.fill, shadowed: false)
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
        let skin = rowSkin(thing)
        return Button {
            openThing(thing)
        } label: {
            AnyView(shapedRow(thing, nextEventID: nextEventID, index: index,
                              imageOnly: imageOnly, wideArt: wideArt,
                              replies: replies))
                .modifier(RowEntrance(index: index, wave: shapeWave, style: entranceStyle))
                .contentShape(Rectangle())
                // THE INK FOLLOWS ITS CARD. Every text token in this app is a
                // `Color.adaptive` resolved against the trait, so overriding
                // the scheme for the subtree re-points the WHOLE ramp —
                // primary, secondary, tertiary, glyphs — in one line, instead
                // of teaching a dozen row anatomies about a foreground colour
                // they have never taken. Nil (the neutral fills) keeps the
                // page's own ramp; see `DS.RowSkin.ink`.
                .environment(\.colorScheme, skin?.ink ?? colorScheme)
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
                                                && chrome.walkSelected == thing.id.uuidString,
                                             skin: skin))
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
                // PIN (2026-08-10). This menu's own doc calls itself READS
                // ONLY, and a pin is a write, so the exception is stated
                // rather than assumed: that rule exists to keep a one-slip yes
                // off anything irreversible or outward-facing ("Approve/Deny
                // are consent"). A pin reaches no network, tells no service,
                // and its undo is the identical gesture on the identical row.
                // It is also the only verb here the person performs ON their
                // own corpus, so the long-press — the row's whole verb surface
                // since the swipe was measured unreachable — is the only place
                // it can live for a row.
                Button {
                    let pinned = Pinboard.toggle(thing)
                    chrome.pinPulse += 1
                    DSHaptic.tap()
                    chrome.flash(pinned ? String(localized: "Pinned")
                                        : String(localized: "Unpinned"))
                } label: {
                    Label(Pinboard.isPinned(thing) ? "Unpin" : "Pin",
                          systemImage: Pinboard.isPinned(thing) ? "pin.slash" : "pin")
                }
                ThingShareLink(thing: thing) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            } preview: {
                // What the band could not fit (prd §412a) — the full title, the
                // picture at a size worth looking at, the opening words. Until
                // this landed the menu had no `preview:` at all, so the system
                // lifted a snapshot of the 44pt row: a bigger copy of what your
                // finger was already on. `RowPeek` is one stored property, so
                // building it per visible row is free; its body — which is what
                // touches `content` and `previewImageData` — runs only when a
                // press actually raises it.
                RowPeek(thing: thing)
            }
    }

    /// One row in any of the seven post rooms (2026-08-26, prd §489).
    ///
    /// The anatomy is `SocialRoom.rowKind`'s answer and nothing else — this
    /// function has no rules of its own, and that is the contract. Adding a
    /// branch here re-opens the drift the table closed: the rule belongs in
    /// `SocialRoom`, where a harness can reach it and where `standsAlone` reads
    /// the same answer.
    ///
    /// `thing` is already liveness-guarded by `shapedRow`, which is the only
    /// caller.
    @ViewBuilder
    private func socialRow(_ thing: Thing, replies: [String: [Thing]],
                           index: Int, nextEventID: UUID?,
                           imageOnly: Bool, wideArt: Bool) -> some View {
        let kids = replies[thing.id.uuidString] ?? []
        switch SocialRoomSource.rowKind(thing, hasReplies: !kids.isEmpty) {
        case .band:
            BandRow(thing: thing,
                    emphasized: thing.id == nextEventID,
                    live: false,
                    imageOnly: imageOnly,
                    wideArt: wideArt)
        case .excerpt(let lines):
            ExcerptRow(thing: thing, lines: lines)
        case .reading:
            ReadingRow(thing: thing)
        case .post(let whole):
            PostCard(thing: thing, whole: whole)
        case .thread(let whole):
            SocialThreadCard(head: thing, replies: kids, whole: whole)
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
            // A CardPointers offer is three facts, not one (prd §487): who it
            // is with, what it gives, and when it runs out. `BandRow` could
            // draw one of them — the title — and did, while the terms sat on
            // `summary` (which it never reads) and the deadline on `dueAt`
            // (which only the head drew, for a single offer). `WalletRow` is
            // the app's three-slot anatomy and already the shape the wallet's
            // own "Coming up" deadlines wear, which is what these rows are.
            //
            // The mark is the CARD's initials, and that is what paid for
            // deleting the head's card-by-card tally: the grouping it counted
            // is legible down the left edge of the room instead. Never
            // `AssetMark` — this app bundles no card artwork, and matching
            // "Amex Gold" against a token brand would put somebody else's logo
            // on their credit card.
            //
            // Bare, with no tap of its own: `shapedListRow` already wraps every
            // row in the single Button that opens the sheet, and a second one
            // here would be a button inside a button.
            case .cardPointers:
                WalletRow(mark: CardPointers.initials(card: thing.authorHandle).isEmpty
                            ? .kind(thing.kind)
                            : .monogram(CardPointers.initials(card: thing.authorHandle),
                                        tint: DS.textSecondary),
                          title: CardPointers.merchant(title: thing.title,
                                                       card: thing.authorHandle),
                          // Their words for what the offer gives, never a
                          // number we made (§420's no-total refusal, on the row
                          // this time).
                          subtitle: thing.summary) {
                    if let due = thing.dueAt {
                        Text(FeedLedeFace.dueLine(due))
                            .dsText(.subhead13)
                            .foregroundStyle(FeedLedeFace.isOverdue(due)
                                             ? DS.attention : DS.textTertiary)
                    }
                }
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
            // The same ledger reading for the wallet-riding money rooms
            // (prd §485, 2026-08-26) — one flag, one anatomy. See `Shape.init`.
            case .ledger: BandRow(thing: thing, moneyColumn: true, rippleIndex: index)
            case .notes:  ExcerptRow(thing: thing, lines: 3)
            case .chat:   ExcerptRow(thing: thing, lines: 2)
            // THE SEVEN POST ROOMS, ONE BRANCH (2026-08-26, prd §489).
            //
            // This was five hand-rolled branches — `.social`, `.x`,
            // `.telegram`, `.instagram`, and `.plain` standing in for TikTok
            // and Nostr because neither had a case at all — each re-spelling
            // the same four decisions in its own dialect. The rules moved to
            // `SocialRoom.rowKind`, which is Foundation-only and therefore the
            // first time any of them can be compiled and mutation-proved by a
            // harness; nothing inside this file could ever be reached by one.
            //
            // Every row's own reasoning travelled with it — a follower is a
            // person, a comment is not a post, an archive draws its words
            // whole — and is now written once in `SocialRoom` beside the source
            // it governs, rather than four times in four places that agreed
            // only by accident.
            case .social, .x, .telegram, .instagram, .tiktok:
                socialRow(thing, replies: replies, index: index,
                          nextEventID: nextEventID,
                          imageOnly: imageOnly, wideArt: wideArt)
            case .vibenet:
                // Face-led (R4.2): the room's subject is WHICH ACCOUNT
                // something happened to, and `.plain`'s band drew one
                // identical glyph for every account.
                VibenetEventRow(thing: thing)
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
            case .walletbeat:
                // Three shapes in one room: a watched wallet is a standing report
                // card, an incident and a revision are dated news, and our own note
                // about the sync keeps its plain band the way every other room does.
                if Corpus.isImportReceipt(thing) {
                    BandRow(thing: thing,
                            emphasized: thing.id == nextEventID,
                            live: false,
                            imageOnly: imageOnly,
                            wideArt: wideArt)
                } else if WalletbeatWatch.isWatchRef(thing.sourceRef) {
                    WalletbeatWalletRow(thing: thing)
                } else {
                    WalletbeatNewsRow(thing: thing,
                                      watchedWallets: walletbeatWatchedIDs)
                }
            case .l2beat:
                // Three shapes in one room: a watched chain is a standing assessment,
                // a milestone and a revision are dated news, and our own note about
                // the sync keeps its plain band the way every other room does.
                if Corpus.isImportReceipt(thing) {
                    BandRow(thing: thing,
                            emphasized: thing.id == nextEventID,
                            live: false,
                            imageOnly: imageOnly,
                            wideArt: wideArt)
                } else if L2beatWatch.isChainRef(thing.sourceRef) {
                    L2beatChainRow(thing: thing)
                } else {
                    L2beatNewsRow(thing: thing, watchedChains: l2beatWatchedIDs)
                }
            case .bookmarks: ReadingRow(thing: thing)
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
                    // The source badge (2026-08-09): a CROSS-SOURCE room asks
                    // for it, a single-source room doesn't — there the room
                    // itself already says the source and a badge would
                    // double-tell it. `.all` is this same `default` arm's
                    // OTHER tenant (a single-source room with no shape case of
                    // its own, e.g. Instagram/TikTok, falls here too as
                    // `.plain`), which is why the test is on the room and not
                    // on the row.
                    //
                    // The pinned room is the second cross-source room and was
                    // missing from this test (user ruling 2026-08-11: "pinned
                    // rows definitely need a source badge"). It renders as
                    // `.plain` — "Pinned" is not a source, so `Shape` has
                    // nothing to match and every row lands in this arm — so it
                    // read as a single-source room to the one line that
                    // decides this, and a pinned note sat next to a pinned
                    // import row with nothing on either saying where it came
                    // from. It is in fact the room where the badge matters
                    // MOST: All is at least chronological, so a row's
                    // neighbours date it, while this list is ordered by when
                    // you pinned and its rows can come from anywhere.
                    BandRow(thing: thing,
                            emphasized: thing.id == nextEventID,
                            live: isLive(thing),
                            imageOnly: imageOnly,
                            wideArt: wideArt,
                            sourceBadge: shape == .all || Pinboard.isPinnedRoom(source))
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
                            .dsGlyph(12)
                    }
                    .foregroundStyle(DS.tint)
                    .padding(.horizontal, DS.Space.s4)
                    .frame(minHeight: 36)
                    .background(DS.tintDim, in: Capsule(style: .continuous))
                }
                .buttonStyle(PressSpring())
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
                        .dsGlyph(12)
                }
                .foregroundStyle(DS.tint)
                .padding(.horizontal, DS.Space.s4)
                .frame(minHeight: 36)
                .background(DS.tintDim, in: Capsule(style: .continuous))
            }
            .buttonStyle(PressSpring())
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
                BridgeIcon(name: source, size: DS.Mark.tile)
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
                    .frame(minHeight: 32)
                    .background(DS.tintDim, in: Capsule(style: .continuous))
            }
            .buttonStyle(PressSpring())
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
                let added = await RSSIngest.refresh(context: modelContext,
                                                    waitForInFlight: true)
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
                    .dsGlyph(12)
                Text(label)
                    .dsText(.subhead13).fontWeight(.medium)
            }
            .foregroundStyle(DS.tint)
            .padding(.horizontal, DS.Space.s3)
            .padding(.vertical, DS.Space.s2)
            .background(DS.tint.opacity(0.12), in: Capsule(style: .continuous))
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(PressSpring())
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
        // The pinned room is normally unreachable while empty — its chip only
        // exists once something is pinned — but the shell renders whatever
        // `filter.source` names whether or not it has a chip, so unpinning the
        // last thing while standing here lands exactly on this line. It says what
        // the verb is rather than that the room is empty, because unlike every
        // other room nothing will ever arrive here on its own.
        if Pinboard.isPinnedRoom(source) {
            return String(localized: "Nothing pinned. Press and hold anything to pin it.")
        }
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
        // A DAY OF POSTS SAYS POSTS, in every room that draws one, and only
        // when EVERY row in the group is one (2026-08-26, prd §489).
        //
        // X's rule (§396a) generalised, and a deliberate change to the three
        // live rooms, which said "posts" unconditionally: a day holding twelve
        // casts and one shared article was calling the article a thirteenth
        // post. It now falls through to the generic noun, which is vaguer and
        // true. The test is the same `rowKind` the rows themselves drew from,
        // so the header can never disagree with what is under it.
        if SocialRoom.drawsPosts(source), SocialRoomSource.groupIsPosts(rows) {
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
        // stops fetching at `allRoomFetchLimit`; the copy says which stop this is.
        //
        // The door this offers stays real: a source room carries its own
        // predicated query and (2026-08-14) still no row bound, so opening one
        // genuinely does reach further back than the All room can.
        Text(reachedFetchCeiling
             ? "Showing your most recent \(rows.count) — open a source to go further back"
             : source == "All"
             ? "That's everything · \(rows.count == 1 ? "1 thing" : "\(rows.count) things")"
             // "from Pinned" would name a source that doesn't exist. This room
             // is the one place the sentence is about something you did.
             : Pinboard.isPinnedRoom(source)
             ? "That's everything you've pinned · \(countLabel(rows))"
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

    /// How many rows a room's `@Query` will materialise, ever. See the long
    /// note in `init` for the measurement that produced it: unbounded, that
    /// query was 26.6% of the main thread on a 6,000-row corpus, because
    /// SwiftData instantiates every row as a real model object on the main
    /// actor. ~40 "Show older" taps of headroom, and constant thereafter no
    /// matter how large the corpus grows.
    ///
    /// Still the ALL room's alone: source rooms took the light columns on
    /// 2026-08-14 and deliberately not this bound, and the pinned room takes
    /// neither. See `init` for both reasons.
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
    ///
    /// Still All-room only: it is the only bounded room. Source rooms got the
    /// light columns on 2026-08-14 but deliberately no row bound — see `init`.
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
        case .showInFiles:
            Task {
                do { try await HandOff.showInFiles(thing) }
                catch { chrome.flash(error.localizedDescription, tone: .failure) }
            }
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
        chrome.refreshHue = roomTakesWalletScope
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
        if LiveRoomSources.isPredictionVenue(source) { await KalshiWatch.invalidateCache() }
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
        // Whether this wallet has anything to PICK (prd §387).
        //
        // Read HERE rather than inside the shelf card, and that placement is
        // the whole fix: the card draws nothing until it knows, so a card that
        // asked for itself produced an empty row, `List` pruned the row, and
        // the `.task` that would have answered never ran — the invitation could
        // never appear on any wallet. Gating a section on state the section
        // itself has to be alive to fetch is a chicken-and-egg; the owner of
        // the section owns the question.
        //
        // Costs no request: served from the same cached read the wallet refresh
        // already made for the NFT spam allowlist.
        if let entry = nftShelfWallet {
            Task { @MainActor in
                let any = !(await WalletNFTShelf.collections(for: entry.address)).isEmpty
                guard scope == selectedWallet else { return }
                if nftHasCollections != any { nftHasCollections = any }
            }
        } else if nftHasCollections {
            nftHasCollections = false
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
