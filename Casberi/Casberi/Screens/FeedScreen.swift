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
            && a.hostRoom == b.hostRoom
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

    /// The merged room this screen stands inside, when it is one app's own
    /// screen shown there (prd §1050k: a testnet inside Testnets). The room
    /// names itself by it, and the account menu leads with its other apps.
    let hostRoom: String?

    /// across the person's own swipes instead of all at once on launch.
    @State private var everBuilt = false
    /// The room's own share card, raised by the door under its tiles
    /// (docs/social-spec.md section 6, item 3). Presented from the screen's
    /// root, never from the row that asks for it.
    @State var roomShare: RoomShareCard.Input?
    /// A Notes folder's card (prd §1021), from the folder's long press.
    @State var folderShare: FolderShareCard.Input?

    /// Source-scoped since 2026-07-21 (perf audit): the pager keeps every
    /// neighbor page MOUNTED (doc above), so an unfiltered `@Query` here used
    /// to mean N+1 live full-corpus queries (one per source chip, plus
    /// MainSurface's own) — a write to ANY thing, anywhere, re-materialized
    /// and re-filtered the whole corpus on every one of them. Each page now
    /// only ever observes its own source's rows; only the "All" page still
    /// queries everything, because it genuinely shows everything.
    @Query var things: [Thing]
    @Environment(ShellChrome.self) var chrome
    @Environment(BridgeStore.self) var bridges
    @Environment(\.modelContext) var modelContext
    /// Read by `isQuiet` (prd §378): under increased contrast the feed's rows
    /// never recede — that setting exists to refuse exactly this.
    @Environment(\.colorSchemeContrast) var contrast
    /// For the Today header's day line (prd §385) — `DayBrief.Whisper
    /// .detailText` paints the wallet move in its direction's accent, and
    /// the accent is scheme-keyed (§83's flat-move rule lives in there too).
    @Environment(\.colorScheme) var colorScheme
    // This window's stack and detail pane (per-window since `SceneState`).
    @Environment(HomeRoute.self) var route
    @Environment(PadDetailSelection.self) var detail
    /// The safety-net refresh's trigger (see the `.task(id: scenePhase)`
    /// below) — a signal that changes independently of `@Query`'s own
    /// health, unlike `corpusRevision`.
    @Environment(\.scenePhase) var scenePhase
    /// Compact is the phone, where a room's scope control stands IN the room
    /// (prd §959); regular keeps it on the shell's rail.
    @Environment(\.horizontalSizeClass) var roomSizeClass

    init(source: String, hostRoom: String? = nil, isActive: Bool, nearActive: Bool = true,
         rowBudget: Int? = nil) {
        self.source = source
        self.hostRoom = hostRoom
        self.rowBudget = rowBudget
        // The mark the trace was missing (PERF 2026-09-01). `mount` fires from
        // a `.task`, i.e. after the first body AND after SwiftUI has installed
        // the view — so with only `step`/`mount` the whole of "did the shell
        // even get to building the new room yet" was one opaque number. It is
        // what showed the outgoing room being re-initialised on every swipe.
        //
        // No `#if DEBUG` since 2026-09-04 (prd §600): `SwipeClock` gates itself
        // at runtime now so the trace can be read on a phone in Release, which
        // is the one configuration this symptom has never been measured in.
        // Off, this is a nil check on a static.
        SwipeClock.mark("init", detail: "src=\(source)")
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
            // The Notes room is the one room that is not a source, so it is
            // the one room whose rows are not selected by ONE `source`: what
            // you pinned, from anywhere, and the notes you wrote (`source ==
            // "You"`, narrowed to the note kind in `feedThings` — a kind
            // cannot be predicated, and your other captures are a handful).
            //
            // The ORDER is the point, and it is `Pinboard.stamp`'s, applied in
            // `feedThings`: every other room orders by when the thing
            // HAPPENED, and this one orders by when YOU acted. A pin you made
            // this morning on a two-year-old screenshot belongs at the top —
            // that is what makes this a list you built rather than another
            // slice of the same river. See `Thing.pinnedAt`. The query's own
            // sort is only a stable pre-order for that pass.
            //
            // Unbounded deliberately, unlike the All room above: this list is
            // as long as you made it by hand, so there is no corpus-scale
            // growth to bound and a ceiling here could hide a row you pinned
            // on purpose — the one place in the app where that would be
            // unambiguously wrong. `rowBudget` is ignored here for the same
            // reason: there is no corpus-scale materialisation to defer.
            _things = Query(filter: #Predicate<Thing> { $0.pinnedAt != nil || $0.source == "You" },
                            sort: \Thing.capturedAt, order: .reverse)
        } else if RoomAccounts.mergedRooms.contains(source) {
            // **A MERGED ROOM READS EVERY APP IT FOLDED IN (prd §1048, §1052).**
            // **THE WALLET CARRIES THE CARDS (prd §1048).** Its Cards tile reads
            // the card seats' spends (`WalletCards`), so the room's one query
            // takes their rows beside its own: one fetch, live like every other
            // row, never a second store a tile could disagree with. Bounded and
            // light-columned as the source rooms below are, and `lightColumns`
            // already names every field `WalletCards` reads. Home still lists
            // only the Wallet's own moves until the separate rooms fold.
            let members = RoomAccounts.roomSources(source)
            var d = FetchDescriptor<Thing>(predicate: #Predicate<Thing> { members.contains($0.source) },
                                           sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
            d.fetchLimit = min(Self.sourceRoomFetchLimit, rowBudget ?? .max)
            if Self.sourceRoomLightColumns { d.propertiesToFetch = Self.lightColumns }
            _things = Query(d)
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
            // "N of M" subtitle.
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
            // **`propertiesToFetch` IS NOT SET HERE, AND THAT IS THE FIX
            // (2026-08-31).** It was, from 2026-08-14 (c107a7de) until this
            // line — seventeen days — and it is the regression behind "the
            // room says connected and shows nothing while its rows are
            // plainly visible in All".
            //
            // The combination is the problem, not either half: a
            // `propertiesToFetch` partial fetch COMBINED WITH a `#Predicate`
            // is a long-standing SwiftData defect that can hand back a set
            // the predicate never selected — including an empty one — and it
            // behaves differently across OS versions. That is why this was
            // invisible here: the reporting device is on iOS 18.6 and this
            // project's simulator is iOS 26, so the same binary is correct on
            // one and wrong on the other.
            //
            // It also explains the exact shape of the report, which nothing
            // else did. The All room's query above sets `propertiesToFetch`
            // too and is FINE, because it carries no predicate — so the
            // asymmetry lands precisely where it was seen: rows present in
            // All, absent from their own room, with the store, the predicate
            // and `Corpus.surfaced` all provably healthy on a plain fetch
            // (a tester's Diagnostics: 22 of 22, `predicated-fetchCount`
            // agreeing). Those three green readings are what a plain fetch
            // says; this query is not a plain fetch.
            //
            // The cost is real and is accepted rather than hidden: a source
            // room materialises its rows WITH the heavy inline text again,
            // which is what c107a7de removed for bulk-import rooms. That is
            // the configuration this app shipped for months before
            // 2026-08-14, so it is known-good rather than merely untried —
            // and a room that is fast and empty is not a trade worth making.
            // If the cost has to come back, it must come back as something
            // that cannot silently drop rows.
            //
            // IT CAME BACK THAT WAY on 2026-09-05 (prd §623): the projection is
            // set again a few lines down, behind `sourceRoomLightColumns` —
            // yes on iOS 26+, where it has only ever been correct, never on
            // 18.x, where the report came from. The paragraph above stays
            // because it is still the reason the gate exists.
            // **BOUNDED SINCE 2026-09-04 (prd §600) — AND THE 2026-08-14
            // REFUSAL ABOVE IS UNTOUCHED, BECAUSE THE HEAD NO LONGER READS
            // THIS QUERY.**
            //
            // That refusal is entirely about the HEAD: `sourceHead` composed
            // from `visible`, so a bound made "your loudest year" describe the
            // newest N posts — §83 fake status in the room whose promise is
            // that it holds your history. It was never an argument that the
            // LIST must be unbounded; nothing on screen shows more than
            // `windowRowBudget` rows anyway.
            //
            // So the two are separated: this query serves the list and is
            // bounded, and `recomputeHeads` makes its own unbounded fetch of
            // the whole room (see `fullRoomRows`). The head still sees every
            // row it ever saw. What changes is that the per-body-pass read —
            // and there are several per swipe, plus one per bridge save during
            // a foreground burst — materialises 600 rows instead of a
            // bulk-import room's thousands, WITH the heavy inline text this
            // branch is obliged to carry (see the `propertiesToFetch` note
            // above). The head's full read happens ONCE per `headKey`, inside
            // a task, memoised in `headMemo` — not on every body evaluation.
            //
            // §83 is kept by `reachedFetchCeiling`, which now covers this room
            // too: at the edge the footer says "Showing your most recent N",
            // never "That's everything from <source>".
            var d = FetchDescriptor<Thing>(predicate: #Predicate<Thing> { $0.source == source },
                                           sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
            d.fetchLimit = min(Self.sourceRoomFetchLimit, rowBudget ?? .max)
            // **LIGHT COLUMNS ARE BACK, GATED BY OS (prd §623, 2026-09-05).**
            // The 2026-08-31 note above is the whole reason this is a gate
            // and not a plain assignment: `propertiesToFetch` + `#Predicate`
            // is correct on iOS 26 (this project's simulator, months of ship,
            // and c107a7de's seventeen days) and wrong on 18.6 (the field
            // report). `sourceRoomLightColumns` says yes only where it has
            // been seen correct — see its own doc for what the 18.6 runtime
            // showed on 2026-09-05 — and the COUNT-vs-`things.count` safety
            // net below this screen is the backstop for a device the gate
            // misjudges: a short room recovers into the plain fetch rather
            // than staying empty. The 18.x path is untouched: heavy, and
            // known-good.
            if Self.sourceRoomLightColumns { d.propertiesToFetch = Self.lightColumns }
            _things = Query(d)
        }
    }

    /// Whether a SOURCE room's `@Query` may project to `lightColumns`.
    ///
    /// iOS 26 and later only. The combination of `propertiesToFetch` and a
    /// `#Predicate` on a live query hands back rows the predicate never
    /// selected on iOS 18.6 (§592's field report, 2026-08-31), and is correct
    /// on iOS 26 — same binary. Both halves were finally seen on the SAME
    /// day, 2026-09-05, when an iOS 18.6 simulator runtime was installed
    /// here for the first time (docs/perf-spec.md P1's unblock step 1): see
    /// prd §623 for what each runtime showed. A deployment target of 18.0
    /// means both branches ship.
    ///
    /// DEBUG override `-sourceRoomLightColumns YES|NO` forces the projection
    /// on or off regardless of OS — it is how the 18.6 arm was driven, and
    /// it is `#if DEBUG` so the shipped binary carries no knob that can turn
    /// the defect back on.
    static var sourceRoomLightColumns: Bool {
        #if DEBUG
        // A launch argument lands as a STRING ("YES"), never a Bool — the
        // first run of the 18.6 arm read `as? Bool`, got nil, and measured
        // the OS gate twice.
        if let forced = UserDefaults.standard.string(forKey: "sourceRoomLightColumns") {
            return ["YES", "1", "true"].contains(forced)
        }
        #endif
        if #available(iOS 26.0, *) { return true }
        return false
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
    ///
    /// NOT `private` since 2026-09-01: `RootShell.fullCorpus()` — the ask
    /// path's unscoped read — takes this same list. The ask path reads a
    /// strict SUBSET of these columns, so a list of its own would be smaller
    /// and would drift, and the drift's symptom is the fault storm this
    /// doc-comment already describes. One list, one place, per the rule above.
    static let lightColumns: [PartialKeyPath<Thing>] = [
        \.id, \.kind, \.title, \.source, \.createdAt, \.capturedAt, \.mark,
        \.tags, \.provenance, \.sourceRef, \.previewImageURL, \.walletAddress,
        \.counterpartyAddress, \.transferDirection, \.transferAmount, \.transferVenue,
        \.transferCounterparty, \.securityFlag, \.spoofedSymbol, \.authorHandle,
        \.authorAvatarURL, \.summary, \.dueAt, \.endAt, \.ocrAt, \.ocrTopics, \.topicsAt,
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
        // Prefetched for the Snapchat room, a bulk import where omitting one
        // `Int?` would trade a cheap column for thousands of faults — the §260
        // mistake above in a different coat. Added 2026-08-14 with the
        // source-room columns for "Who you snap with", whose board §723
        // deleted; the column stays prefetched because it is one `Int?` and
        // the row itself reads it.
        \.messageCount,
    ]

    // KNOWN AND DELIBERATE: `content` stays OUT. It is the heavy column for
    // the rooms this change is FOR — a note's whole body, a chat's transcript,
    // a screenshot's OCR. This note used to record a cost against it: three
    // leaderboards (Steam hours, a feed's group, the host a link came
    // from) read `content` per row, so those rooms faulted once per row where
    // the old unpredicated fetch had it loaded. §723 deleted all three boards,
    // so the omission now costs nothing at all.
    //
    // UNMEASURED, and stated as such: the 26.6%-of-main-thread figure behind
    // the All room's own columns came from `scripts/main-thread-profile.sh` on
    // a 6,000-row corpus, and no equivalent profile has been run for a source
    // room. If a feed or Steam room ever reads as slow to open, this comment
    // is the first place to look and `content` is the first thing to try.

    /// Only `tag` is read from here now — a kind filter is a cross-page state
    /// (it arrives from Home's kind bar and applies to the All room).
    /// Per-WINDOW since `SceneState`: `RootShell` owns it and injects it.
    @Environment(FeedFilter.self) var filter

    @State var feedSheet: FeedSheetRoute?
    /// Whether this device holds a GitHub key — the Watch tile's gate (prd
    /// §1031), so a demo seat with no key never draws a verb that cannot
    /// act (§83). Read in a `.task`, never a body (a Keychain read, §628).
    @State var githubKeyed = false
    private var githubLandingKey: String { "\(source)|\(isActive)" }
    private func landGitHubWatch() async {
        guard source == "GitHub" else { return }
        githubKeyed = TokenBridge.github.connected
        guard isActive, chrome.connectLanding == source else { return }
        chrome.connectLanding = nil
        guard githubKeyed else { return }
        try? await Task.sleep(for: .milliseconds(700))
        guard !Task.isCancelled, feedSheet == nil else { return }
        feedSheet = .githubWatch
    }

    /// **A SERVICE DOOR LANDS HERE** (`ShellChrome.serviceDoor`): a plan's
    /// sheet in the Wallet, a list's in Day, asked for from the service's
    /// other page. Keyed on `isActive` for `landGitHubWatch`'s reason (the
    /// pager mounts neighbours). The room reads its own tile's reading first
    /// when the id is not in it yet, and a door whose destination is gone, or
    /// that outlived `serviceDoorLife`, is dropped unanswered (prd §83).
    private var serviceDoorKey: String {
        guard let door = chrome.serviceDoor else { return "" }
        return "\(source)|\(isActive)|\(door.at.timeIntervalSince1970)"
    }
    private func landServiceDoor() async {
        guard isActive, let door = chrome.serviceDoor else { return }
        guard Date.now.timeIntervalSince(door.at) < ShellChrome.serviceDoorLife else {
            chrome.serviceDoor = nil
            return
        }
        let route: FeedSheetRoute
        switch door.target {
        case .plan(let id):
            guard source == CategoryFold.walletRoom else { return }
            if !SubscriptionsReading.shared.items.contains(where: { $0.id == id }) {
                await SubscriptionsReading.shared.refresh(modelContext)
            }
            guard SubscriptionsReading.shared.items.contains(where: { $0.id == id }) else {
                chrome.serviceDoor = nil
                return
            }
            route = .subscription(id)
        case .list(let id):
            guard source == RoomAccounts.dayRoom else { return }
            if !MailSubscriptionsReading.shared.items.contains(where: { $0.id == id }) {
                MailSubscriptionsReading.shared.refresh(modelContext)
            }
            guard MailSubscriptionsReading.shared.items.contains(where: { $0.id == id }) else {
                chrome.serviceDoor = nil
                return
            }
            route = .mailSubscription(id)
        case .followed(let id, let room):
            guard source == ShellChrome.roomName(room) else { return }
            if FollowingReading.shared.item(id) == nil {
                FollowingReading.shared.refresh(room, context: modelContext)
            }
            guard FollowingReading.shared.item(id) != nil else {
                chrome.serviceDoor = nil
                return
            }
            route = .following(id, room)
        }
        // The room's card lands first, or the sheet's rise is refused. The
        // door is cleared AFTER the beat: clearing changes this task's own
        // key, which would cancel it mid-sleep.
        try? await Task.sleep(for: .milliseconds(700))
        guard !Task.isCancelled else { return }
        if feedSheet == nil { feedSheet = route }
        chrome.serviceDoor = nil
    }

    @State var confirming: (Verb, Thing)?
    /// The note a long press asked to delete, waiting on its confirmation.
    @State var deletingNote: Thing?
    /// Recently Deleted's tray (prd §985).
    @State var trashOpen = false
    /// The Notes room's folder name prompt, its field, and the folder whose
    /// Delete is being confirmed (prd §980).
    @State var folderPrompt: FolderPrompt?
    @State private var folderDraft = ""
    @State var deletingFolder: String?
    /// Translate verb, swipe-triggered — same system sheet as ThingSheetView's.
    @State var showTranslate = false
    @State var translateText = ""
    @State var blockStream = GenStream()
    @Bindable var wallet = WalletStore.shared

    /// The Wallet feed's live reads (2026-07-20) — Aave positions and the
    /// warnings rolled up from them plus Safe/poisoning/delegation. Never a
    /// landed thing: re-read each time this feed comes forward or its scope
    /// changes, exactly as the manage screen used to hold it.
    @State var walletLive = WalletLiveState()
    /// Whether the scoped wallet holds any NFT collection at all (prd §387) —
    /// what decides between the shelf's invitation line and nothing. Owned by
    /// the room, filled by `loadWalletLive`; see there for why not by the card.
    @State var nftHasCollections = false
    /// Safe transactions still in the queue, by row ref (prd §1048, step 4):
    /// read off `SafeBridge.pendingSnapshot()` in `loadWalletLive`, never in a
    /// body (§628), and read by Coming up.
    @State var walletSafePending: Set<String> = []
    /// A section the Security checkup asked to be walked to (prd §1107; the
    /// risk strip's dots, §417, until §1107 retired the strip), consumed and
    /// cleared by `listCore`.
    ///
    /// Routed through state rather than by threading the `ScrollViewProxy` down
    /// into the box: the proxy lives at `feedList` and the figure is five call
    /// layers below it, so passing it would mean a signature change on
    /// `shapedSections` and every room's builder — for one tap in one room.
    @State var cardScrollTarget: String?
    /// The combined portfolio behind the treemap (2026-07-21, prd §155) — one
    /// derivation the balance headline, the concentration line, and the
    /// allocation tray all read, so nothing on this screen can disagree with
    /// the map it's standing under. Lands with the treemap doc, from the same
    /// read.
    @State var portfolio: WalletPortfolio?
    /// Chains the person follows that the last holdings read could not reach
    /// (prd §827) — the crown states them, because a total that quietly leaves
    /// a chain out is §83's false number. Filled by `streamBlock`.
    @State var unreadableChains: [String] = []
    /// Followed chains the last pass held money on and priced nothing (prd §828).
    @State var unpricedChains: [String] = []

    /// The full allocation tray — every position and which wallets hold it.
    /// Routed through `feedSheet` (`.allocation`) now, not its own bool.
    /// The balance line's window (prd §155). Narrowed to what the record can
    /// actually answer each render; the choice persists across launches.
    @State var balanceRange: WalletRange = .watched
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
    @MainActor final class DerivationMemo {
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
        /// Set while the sections render; read by `feedList` a few lines later
        /// to decide whether "that's everything" is still true. Same
        /// write-during-body / read-later shape `groups` already has, and safe
        /// for the same reason: the sections are evaluated before the footer.
        var windowHasMore = false

        /// The two room-scoped watched-id sets (prd §626), against `key`.
        ///
        /// They are read PER ROW, and each one walked `visible.live` — so the
        /// room's whole corpus, once for every row it draws. That is O(n²) in
        /// the room's size, and it was the most expensive thing in this file.
        /// Kept here rather than recomputed because `key` is O(1) to read
        /// while `derivationKey` is O(n): memoising against the key the
        /// grouping already set is what makes the per-row read constant.
        var walletbeatWatched: Set<String> = []
        var l2beatWatched: Set<String> = []
        /// Nil until computed for the current `key`. A separate flag rather
        /// than comparing against `key` alone, because `key` is itself
        /// optional and `nil == nil` would read as a hit forever.
        var watchedKey: Int??
    }
    @State var memo = DerivationMemo()

    /// Same memo, for the themes treemap's own corpus walk (`projectClusters`
    /// → `themesDocument` → `GenParser.parse`), which ran on every one of those
    /// same ~18 passes.
    @MainActor final class ThemesMemo {
        var key: Int?
        var clusters: [HomeComposition.Cluster] = []
        var doc: [String]?
    }
    @State var themesMemo = ThemesMemo()

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
    @State var allSnapshotKey = 0

    @State var shapeWave = 0
    /// When `shapeWave` last moved — the mount, then every bump (PERF
    /// 2026-09-09, prd §661). `RowEntrance.waveAt`: a row appearing more than
    /// `RowEntrance.cascadeWindow` after this was met by scrolling, not by the
    /// room's arrival, and shows at rest instead of waiting out a stagger
    /// sized for the first screen.
    @State var shapeWaveAt = Date.timeIntervalSinceReferenceDate
    /// Latches on the FIRST landing so the row entrance plays once, not on
    /// every swipe back to this page (2026-07-30 swipe-smoothness — see
    /// `land()`).
    @State var hasLanded = false
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
    @State var newSince: Date?
    @State var visitFrozen = false
    /// The agent whose room this is, when its key is present (prd §840) —
    /// resolved in `onAppear` by `resolveRoomAgent`, never in a body.
    @State var roomAgent: AgentProvider?
    /// New was tapped in the Agents room with no agent picked and several
    /// that can answer (prd §1054).
    @State var askingWhichAgent = false
    /// New was tapped in the Day room with more than one thing to make
    /// (prd §1056).
    @State var dayMakeOpen = false
    /// Watch was tapped in the Work room with more than one seat that keeps
    /// a watch (prd §1057).
    /// The highlights you kept yourself (`Highlight`, prd §1020): notes of
    /// yours, so outside Reading's query; read when Highlights is picked
    /// (prd §1085).
    @State var keptHighlights: [Thing] = []
    /// Today's shape under Day's next thing (prd §1087). Value types only.
    @State var dayStrip: DayStrip?
    /// Day's Coming up tile (prd §1136c): every app's dated rows ahead, read
    /// in the tile's own `.task`, never in a body (§628).
    @State var dayComingUp: [Thing] = []
    /// A tapped Themes cell (2026-07-18, the All feed's own treemap) — the
    /// same project detail door Home's map already opened.
    @State var openProject: ProjectRoute?
    @State private var openPerson: SocialProfile?
    /// One scroll-past per mount (prd §385, 2026-08-14): on appear the list
    /// settles just below the Themes card, so the map lives ABOVE THE FOLD —
    /// revealed by scrolling up past the top, the way Mail hides search.
    /// Every source switch re-mounts this screen (`.id(filter.source)` in
    /// `MainSurface`), which resets this and re-hides the map — the stronger
    /// form of the digest-collapse behaviour it replaced (the one thing the
    /// user kept from that design: "i like that it collapses when you
    /// navigate away and come back").
    @State var foldSettled = false
    /// The zero-height row just below the Themes card that `foldSettled`'s
    /// scroll targets. `scrollTo` on an id that never rendered is a no-op,
    /// which is the whole guard: non-All rooms, a filtered All, and an empty
    /// corpus render no anchor and so never scroll.
    static let themesFoldAnchor = "feed.themesFold"
    struct ProjectRoute: Identifiable, Hashable {
        let name: String
        var id: String { name }
    }
    @Namespace private var zoomNS
    /// prd 43h: Reduce Motion is law — the hand-rolled moves (row entrances)
    /// fall back to plain state changes under it.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
    @State var debouncedAllSnapshot: [Thing]?
    /// The same safety net as `debouncedAllSnapshot`, for every OTHER room
    /// (2026-08-30 follow-up — the All room's fix alone left a per-source
    /// room, e.g. Vercel, still stuck: it has its own separate `@Query`, so
    /// it carries the identical FB14619787 exposure). Nil until a mismatch
    /// is actually found; see the `.task(id: scenePhase)` below and
    /// `feedThings`, the one place this is read.
    @State var sourceRoomFallbackSnapshot: [Thing]?

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

    /// The All snapshot task's key: the corpus revision AND whether the room
    /// is under the swipe's transient bound (PERF 2026-09-08) — see the task.
    private struct AllSnapshotTaskKey: Equatable {
        let revision: Corpus.Revision
        let bounded: Bool
    }

    private var allSnapshotTaskKey: AllSnapshotTaskKey {
        AllSnapshotTaskKey(revision: corpusRevision, bounded: rowBudget != nil)
    }

    /// What this room's head draws from right now. Seeded from `headMemo` and
    /// refreshed by the task below, so a room you have already visited paints
    /// its head immediately and a room you have not shows none until the first
    /// computation lands — the same nothing a head that DECLINES draws.
    @State var heads: RoomHeads?

    /// Work's and Reading's object keys, by row (prd §1079): computed off the
    /// main actor in `.task(id: objectFoldKey)`, read by `objectFolded`.
    @State var objectKeys: [UUID: String] = [:]
    /// The Subscriptions tile's pressed category, keyed on the set of
    /// subscriptions it was pressed over, so a different set clears it.
    @State var subscriptionsPick: SubscriptionsPick?
    /// The map's width, measured off the map's own row, which it is
    /// laid out in (its fold depends on it, and so does what Other holds).
    @State var subscriptionsMapWidth: CGFloat = 0
    /// Day's Subscriptions map, its pick and its measured width (prd §1117).
    @State var mailSubscriptionsPick: SubscriptionsPick?
    @State var mailSubscriptionsMapWidth: CGFloat = 0
    #if DEBUG
    /// `-marketsScope` fires once per launch, not once per page build.
    @MainActor static var marketsProbed = false
    @MainActor static var readingProbed = false
    @MainActor static var notesProbed = false
    @MainActor static var socialProbed = false
    @MainActor static var walletFollowProbed = false
    @MainActor static var subscriptionsProbed = false
    @MainActor static var mailSubscriptionProbed = false
    @MainActor static var followingProbed = false
    @MainActor static var subscriptionsCategoryProbed = false
    #endif
    /// What the Wallet last read you hold, for Markets' "You hold" line.
    @State var held: (byContract: [String: Double], bySymbol: [String: Double]) = ([:], [:])

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
                                       open: openRowID, resolve: resolveRowID))
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

    /// The single surface owns the NavigationStack, the chip header, and the
    /// shared doors now (MainSurface) — this is just the feed's body, hosted
    /// inside that one stack. Its own inner push (a bridge control panel) stays
    /// here; Apps/Settings moved up to the shell.
    private var builtBody: some View {
        #if DEBUG
        let _ = LaunchPerf.buildTick(source)
        #endif
        // Names WHICH room's body built, which `HEAVYBUILD` also does — this
        // one is on the swipe's own clock, so a build belonging to the room
        // being left is visible as such. Outside `#if DEBUG` since prd §600 —
        // see `SwipeClock.isOn`; `LaunchPerf.buildTick` above stays DEBUG
        // because it accumulates unconditionally and has no gate of its own.
        let _ = SwipeClock.mark("body", detail: "src=\(source)")
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
            // "the toggle cannot appear over another room" true by
            // construction rather than by a source test in two files.
            .onDisappear {
                guard shape == .wallet else { return }
                chrome.walletSections = []
                chrome.walletSectionAttention = []
            }
            // The two testnet rooms' half of the same contract (PERF
            // 2026-09-01), replacing writes made from inside `roomBody` — see
            // `framesSectionPublication`. `initial: true` for the reason the
            // one above gives: both rooms' live state is usually already loaded by
            // the time the room mounts, so a room that never changes afterwards
            // would publish nothing and draw no switcher at all.
            .onChange(of: framesSectionPublication, initial: true) { _, now in
                chrome.framesSections = now
            }
            .onChange(of: logosSectionPublication, initial: true) { _, now in
                chrome.logosSections = now
            }
            // Cleared on the way OUT, which the body-path writes never did:
            // every room evaluated those lines, so the list left behind was
            // whatever the last devnet visit put there. The list is also each
            // switcher's own gate, so clearing it is what makes "a devnet
            // switcher cannot appear over another room" true by construction
            // rather than by a source test in two files.
            .onDisappear {
                if source == FramesIdentity.source { chrome.framesSections = [] }
                if source == LogosRoom.source { chrome.logosSections = [] }
            }
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
    func sourceComposeRow(_ action: SourceAction) -> some View {
        // A verb, so a row (prd §746).
        DSDoorRow(icon: "plus",
                  title: Text(String(localized: String.LocalizationValue(action.label)))) {
            DSHaptic.selection()
            if case .openURL(let url) = action.run { openExternal(url) }
        }
        .padding(.horizontal, DS.Space.s4)
        // The old capsule's generous top gap (2026-07-14: s3 read as still
        // touching the chip row), kept — this row sits in the same place under
        // the same strip.
        .padding(.top, DS.Space.s8)
        .padding(.bottom, DS.Space.s2)
    }

    /// The room's own content: the empty state, the filtered-empty state, or
    /// the day sections. Extracted from `feedList` for `populatedRoom`'s
    /// reason (see just below) — pulling one branch out was not enough, since
    /// the cost is the whole chain rather than any one arm of it.
    @ViewBuilder
    private func roomBody(_ rows: [Thing]) -> some View {
        // **THE EMPTINESS TEST READS WHAT THE ROOM DRAWS (2026-09-03, prd
        // §592, user: "i clicked on activity and this is what happened" over a
        // demo Wallet room full of transactions).**
        //
        // `feedThings` prefers `sourceRoomFallbackSnapshot` — the per-source
        // safety net's rescue array, filled when the `@Query` disagrees with a
        // raw fetch on the same store — and this test asked `things`, the very
        // query the net exists BECAUSE it cannot be trusted. So the rescue
        // could land a full room in `visible` and this line still said the
        // room was empty, which drew "Nothing from <source> yet." over it.
        //
        // **The net has never once been able to rescue a room.** Both commits
        // that built it (85adc007, fee89e1e) added the fetch and neither
        // touched this line, so from the day it shipped the fallback fed the
        // ROWS while the EMPTY STATE overruled them — the exact failure it was
        // written to fix, one branch upstream of the fix.
        //
        // ONE-DIRECTIONAL, like the snapshot term beside it: a NON-EMPTY
        // fallback proves content and short-circuits, and an empty or absent
        // one still asks `hasSurfaced`.
        //
        // §592's OWN RULING IS WHAT MOVED THE ROWS TERM TO THE FRONT
        // (2026-09-08): the heading above says the test must read what the room
        // DRAWS, and `rows` is literally that array — `visible`, which
        // `feedThings` already resolves through `sourceRoomFallbackSnapshot`
        // before it ever reaches `things`. So the rescue is honoured by the
        // FIRST term now rather than by the second, and the term that reads the
        // untrusted query is last instead of third.
        //
        // **ONE READ OF THE ROOM'S ARRAY PER BODY PASS, AND THIS LINE IS WHERE
        // A SHIPPED BUILD DIED (crash report 2026-09-08, build 537).** A
        // `0x8BADF00D` process-exit watchdog — "failed to terminate gracefully
        // after 5.0s", 5.588s of application CPU at 16% — symbolicated against
        // 537's own dSYM to `FeedScreen.roomBody.getter` at exactly this
        // expression, and the frames below it are `_SwiftData_SwiftUI` →
        // `SwiftData` → `Encodable.encode(to:)` → `memmove`: the `@Query`
        // getter re-fetching AND `Codable`-snapshotting every model it returns.
        // On iOS 18.6 a source room's query carries no `propertiesToFetch`
        // (`sourceRoomLightColumns` is iOS 26+ — a predicated partial fetch
        // drops rows on 18.6, prd §623), so each of those rows is materialised
        // with its heavy inline text.
        //
        // `things` was read here even though the branch below reads the room's
        // array anyway, and each read re-materialises (the §600 measurement:
        // "asking it materialised the room every time, twice per pass"). So the
        // fix is not a cheaper test, it is ONE array: `rows` is what
        // `populatedRoom` is about to draw, and a room that has anything to
        // draw plainly has content.
        //
        // ≤ THE OLD COST IN EVERY CASE BUT ONE, and half of it in the two hot
        // ones. A room WITH rows now reads once instead of twice. A room that
        // is genuinely empty falls through to `Corpus.hasSurfaced(things)` as
        // before — and that read costs nothing precisely because the query it
        // materialises is empty. A room narrowed to empty by a tag or a scope
        // reads twice, which is what it read before.
        //
        // THE EXCEPTION, stated rather than glossed: the seats whose branches
        // below return before they ever reach the rows (Frames, Logos)
        // previously paid one short-circuiting
        // `contains` and now pay `visible`'s `Corpus.surfaced` allocation too.
        // It is free in fact and not in principle — each of those seats lands
        // no `Thing` EVER, so the array it allocates over is empty — and it is
        // written down here because a premise that stops being true is exactly
        // what this change had to go and correct one property up.
        //
        // `Corpus.hasSurfaced(rows)` rather than `!rows.isEmpty`, so the answer
        // is unchanged for the PINNED room: `feedThings` deliberately does not
        // surface-filter that one (a contact you pinned is one you asked to
        // keep in front of you), so a pinboard holding only contacts would flip
        // from the empty state to rows on a bare `isEmpty`. For every other
        // room `rows` is already surfaced, so this is true on the first element.
        //
        // `rows` is HANDED IN by `listBody` rather than bound here, so the
        // animation key beside the List reads the same array instead of
        // fetching its own (see `listRevision`).
        let roomHasContent = Corpus.hasSurfaced(rows, room: source)
            || (debouncedAllSnapshot.map { !$0.isEmpty } ?? false)
            || (sourceRoomFallbackSnapshot.map { !$0.isEmpty } ?? false)
            || Corpus.hasSurfaced(things, room: source)
        // `roomAgent != nil` joins the two liveness doors for §841's reason:
        // an agent room with no conversation yet still has a Chat tile, which
        // is the whole way to give it one. Without it the room is replaced
        // before `keepsChromeWhenEmpty` is ever consulted.
        // The Notes room is never replaced either (prd §969, §979): its New
        // tile is how an empty one stops being empty, and the generic state
        // told a first-time writer to open the catalog instead.
        if !roomHasContent && !LiveRoomSources.has(source) && !agentRoomShown
            && !Pinboard.isPinnedRoom(source) && !walletKeepsChrome {
            // An empty Home still names what stopped (prd §1162): an app
            // that broke before anything landed is the likeliest reason the
            // feed is empty at all.
            if source == "All" { reconnectSection }
            Group { emptyState }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
        } else if source == FramesIdentity.source,
                  let head = FramesRoomSource.compose(scope: chrome.framesScope) {
            // **A ROOM WITH LIVE CONTENT AND NO ROWS** — Hegotá's branch, one
            // chain over, and needed for the same reason: without it the
            // `if/else if` falls through BOTH arms and renders nothing at all.
            // This seat lands no `Thing` EVER, so its rows are always zero and
            // its entire content is this head.
            // Published from `.onChange(of: framesSectionPublication)` up in
            // `body`, NOT written here — see `framesSectionPublication` for what
            // a body that writes its own observed state costs.
            let framesScope = FramesSection.resolve(chrome.framesSection,
                                                    present: chrome.framesSections)
            // **BOX · TILES · MENU, THEN THE LIST (prd §1039).** The chrome
            // draws the crown (`FramesRoomFigure` on its `.home` arm) or the
            // scope's figure in one box, the tiles and the account menu under
            // it — nothing that scopes the room at the top of the screen
            // (§752) — and `FramesRoomList` draws the page's list: the moves
            // on Home.
            framesScopeChromeSection(framesScope, head: head)
            framesMoneyDoorsSection(framesScope)
            Group {
                FramesRoomList(head: head,
                               accounts: framesAccounts,
                               section: framesScope,
                               // **THESE ROWS WERE BUTTONS WIRED TO NOTHING**
                               // (2026-09-02). `FramesRoomList` has built every
                               // row as a `Button { onOpenMove(move) }` since
                               // the room shipped and this closure was empty —
                               // so a tap in Activity, Frames or Sponsors
                               // highlighted and did nothing, which is §83's
                               // dead control multiplied by every transaction
                               // on screen.
                               onOpenMove: { move, owner in
                                   feedSheet = .framesMove(move, owner)
                               },
                               onOpenPayer: { payer in
                                   feedSheet = .framesPayer(payer, framesShownMoves)
                               },
                               onOpenAccount: { feedSheet = .framesAccount($0) })
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            // The Wallet's row column (prd §950): a devnet list's icons centre
            // on the same line as every other room's; its day headers step
            // back to the tiles' edge themselves (`DSDayHeader`).
            .listRowInsets(EdgeInsets(top: 0, leading: DSRoomChassis.rowInset(forMark: DS.Face.list),
                                      bottom: DS.Space.s4, trailing: DS.Space.s4))
        } else if source == LogosRoom.source {
            // **THE LOGOS ROOM (prd §991)** — a devnet-family room that DOES land
            // rows. The chrome draws the box, the tiles and the account menu on
            // every page (prd §1039). Home (the chain's moves), Node and
            // Rewards then list their own rows here, with no cover: the crown
            // is the room's lead, not the newest row.
            let logosSection = LogosSection.resolve(chrome.logosSection,
                                                    present: chrome.logosSections)
            logosScopeChromeSection(logosSection)
            if logosSection == .holdings {
                logosHoldingsSection
            } else {
                let days = chronoGroups(logosRows(rows, section: logosSection))
                groupedSections(days, nextEventID: nil, boundary: boundaryThingID(in: days))
            }
        // **`|| roomAgent != nil` OR THIS CHAIN FALLS THROUGH BOTH ARMS AND
        // RENDERS A BLACK SCREEN (prd §845).** §842 added `roomAgent == nil`
        // to the first arm so an agent room would stop being replaced by the
        // generic empty state — and that is only half a move: it took the room
        // OUT of the empty arm without putting it INTO a drawing one, so a
        // connected agent with no conversation yet matched nothing here at all.
        // Reported the moment the dock fix worked: *"i press the bankr tile i
        // just see a black screen"*. `LiveRoomSources`' own doc names this
        // exact shape — it is why Frames and Logos each have an arm above
        // rather than a flag.
        } else if roomHasContent || agentRoomShown || Pinboard.isPinnedRoom(source)
                    || walletKeepsChrome {
            // Derived ONCE per render and threaded into everything below
            // — the day groups, ledes, and per-row hint/next-event ids
            // all share this one filter pass instead of each re-deriving
            // it from `feedThings` (the Feed-freeze rule, perf pass
            // 2026-07-13, extended to `visible` itself).
            // `rows`, bound once at the top of `roomBody` — NOT `self.visible`
            // again, which is a second `@Query` materialisation of the same
            // array (build 537's watchdog, see there).
            let visible = rows
            if visible.isEmpty && !keepsChromeWhenEmpty {
                Group { filteredEmptyState }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
            } else {
                populatedRoom(visible)
            }
        } else {
            // A LIVE-CONTENT ROOM WHOSE HEAD IS NIL (prd §911) — Frames with
            // nothing watched. Every arm above declined, and
            // the chain used to fall through here and draw NOTHING: the black
            // screen each of those arms' notes describes. The corpus-shaped
            // empty state is the honest floor.
            Group { emptyState }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
        }
    }

    /// **A ROOM WHOSE HEAD IS ITS OWN NAVIGATION MUST NOT BE REPLACED BY THE
    /// GENERIC EMPTY STATE (prd §538, 2026-08-31.)**
    ///
    /// Reported exactly: *"when a user is tapping on accounts in the account
    /// list, then clicks on one that has 'nothing to show' the entire
    /// navigation goes away and no way for user to continue."*
    ///
    /// `filteredEmptyState` replaces the WHOLE room — it is written for a
    /// source chip that matched nothing, where the room is its rows and the
    /// honest answer is a line plus "Show everything". In a room whose head is
    /// its navigation the room is not its rows: the tiles and the rails are how
    /// you got here and they are the only way back. Scoping to something with
    /// no activity therefore deleted the control you had just used, and the
    /// one exit left (`filter.source = "All"`) throws you out of the room
    /// altogether rather than back to where you came from. A dead end you can
    /// only leave by leaving.
    ///
    /// So a room that draws a head takes the populated path with an empty row
    /// set instead, and says "nothing here" IN the room, under its own rails —
    /// the empty state as content rather than as a replacement.
    ///
    /// Gated on the head actually COMPOSING, never on the source name alone:
    /// if there is no card to draw then the room really is its rows, and the
    /// generic state is the right answer after all. Frames already has its own
    /// arm above for the same structural reason (it lands no `Thing` ever, so
    /// its rows are always zero) — this is that reasoning applied to the rooms
    /// that land rows but can legitimately have none of them in view.
    private var keepsChromeWhenEmpty: Bool {
        // **AN AGENT ROOM'S TILES ARE HOW IT STOPS BEING EMPTY (prd §841).**
        // Without this the generic state replaces the whole room the
        // moment its last conversation is deleted, taking the Chat tile
        // with it — so the one control that could start another is gone,
        // and the room is the dead end §538 was written about.
        agentRoomShown
            // A person, repo or board picked from the control IN the room
            // (prd §959): the generic state would take that control with it,
            // and its one door leaves the room.
            || roomScopePicked
            // An app picked from a merged room's menu, the same reason
            // (prd §1065): an exchange lands no rows, only a balance, and the
            // generic state took its balance, its tiles and the menu that
            // could pick another account.
            || (selectedSeat != nil && RoomAccounts.mergedRooms.contains(source))
            // The Notes room's tiles are its navigation and its one verb
            // (prd §979, §980): an empty Pinned or Folders pick keeps them,
            // and Folders keeps its New folder row under them.
            || Pinboard.isPinnedRoom(source)
            || walletKeepsChrome
    }

    /// **THE WALLET IS NEVER REPLACED WHILE IT WATCHES AN ADDRESS** (2026-10-03,
    /// user: "if you add an address to follow that isn't detected it takes you
    /// to an empty screen that says nothing here yet, but it's not the
    /// standard wallet page, and you can't navigate out of it").
    ///
    /// An address with no activity yet lands no rows, so both empty arms of
    /// `roomBody` replaced the room — box, tiles and the account menu with
    /// them, the rail unpublished — and the scope outlived leaving the room,
    /// so coming back met the same page. §538's dead end, for an address
    /// rather than a seat. The box and its figures already say "nothing yet"
    /// in their own slots (`walletScopeIsEmpty`), so the room keeps its
    /// chrome over an empty list.
    private var walletKeepsChrome: Bool {
        source == CategoryFold.walletRoom && !wallet.addresses.isEmpty
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
                // No closing line in the Wallet (2026-07-20): it previews
                // five and hands off to the history page, so "that's
                // everything · 131 transactions" under five rows was a flat
                // lie. Its own "See all transactions · 131" row is the honest
                // close. (Reminders' state groups and Calendar's collapsed
                // past opted out for the same reason, and left with their
                // rooms, prd §1059.)
                // "That's everything" is a CLAIM, so it waits until the
                // room really is whole (prd §264). While a window is open
                // the `olderRow` is what sits at the bottom instead.
                if shape != .wallet && !memo.windowHasMore {
                    caughtUpFooter(visible)
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
            // The strip is not pinned — Wallet draws it as a `List`
            // section — so it scrolls
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
            // **AND ON AN ACCOUNT PICK** (prd §495, user: *"it makes the
            // silhouette and toggle bar jump to the top"*).
            //
            // Same defect as the scope chips and the same fix: narrowing the
            // room to one account replaces its whole content, the list's
            // extent changes under a scroll offset that no longer means
            // anything, and the scroll view clamps — which throws the rail and
            // the strip up the screen. The SCOPE chips were hooked here and
            // the FACE rail was not, because the first report named the chips.
            .onChange(of: chrome.walletScope) { _, _ in returnToRoomTop(proxy) }
    }

    /// The id the room's head carries, so a scope change can return to it.
    private static let roomTopAnchor = "roomTop"
    /// The room's title — the true top a scope change returns to.
    private static let roomTitleAnchor = "roomTitle"

    /// What the room's head says (prd §930): a source room wears its catalog
    /// name, so an aliased seat ("Privacy Pools") reads as the app you
    /// connected.
    ///
    /// Home, Notes and Markets are places in You (prd §1127, §1129): the
    /// category's name is yours, else You (`HomeScope.title`), and the You
    /// pill beside it names the place.
    var roomName: String {
        if HomeScope.contains(source) { return youPlaceName }
        return BridgeCatalog.seatName(forSource: hostRoom ?? source)
    }

    /// Scroll the room back to its own head, with the standard motion so it
    /// reads as the room resetting rather than as a jump of its own — which
    /// is the thing this exists to remove.
    private func returnToRoomTop(_ proxy: ScrollViewProxy) {
        withAnimation(DS.Motion.standard) {
            proxy.scrollTo(Self.roomTitleAnchor, anchor: .top)
        }
    }

    private func listBody(_ proxy: ScrollViewProxy) -> some View {
        // **ONE READ OF THE ROOM'S ARRAY FOR THE WHOLE SCREEN (prd §646,
        // 2026-09-08, build 537's watchdog).** Reading a `@Query` property is a
        // fetch AND a per-model `Codable` snapshot, and it is not cached between
        // reads — so each spelling of `visible` or `things` below the List was
        // its own materialisation of the same array, on every page `everBuilt`
        // has latched, on every one of the ~30 graph updates a cold-launch
        // bridge burst fires. The room's contents are ONE value now: bound here,
        // handed to the body that draws it and to the key that animates it.
        //
        // `roomHead` deliberately takes nothing — it reads neither `visible` nor
        // `things` (its heads are computed in `.task(id: headKey)` and memoised,
        // PERF 2026-08-21), which is what makes one binding enough.
        let rows = visible
        return List {
            // THE ROOM NAMES ITSELF (prd §930): its category's name in pink,
            // and what is picked in it after a dot (§1129, §1133; picked in
            // the rooms tray, never here), in the list, so it
            // scrolls with the rows and reserves nothing. NO ROOM DRAWS A
            // SLIDERS DISC (prd §1050f, amending §1033): an app's settings
            // open from its row in Apps.
            DSRoomTitleRow(title: roomName, pick: roomPick)
                #if DEBUG
                .background { notesProbeHook }
                #endif
                // THE TOP OF THE ROOM IS ITS TITLE (user: "the wallet buttons
                // still move"). A scope change scrolled to the head BELOW the
                // title, so every tile tap slid the title off and the tiles up
                // by its height; it returns here, so the tiles stand still.
                .id(Self.roomTitleAnchor)
                // The demo's pill RESERVES its band above the title (prd
                // §1005, closing §946's "found, not fixed"): the well absorbed
                // it under §919, but §930 put the title first, so the pill sat
                // on the room's name and over the well's top edge.
                .dsRoomTitleListRow()
            roomHead
                .id(Self.roomTopAnchor)
            roomBody(rows)

            // Room for the floating bar.
            Color.clear.frame(height: ShellMetrics.bottomInset - 40)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        // The wave every row lead measures a landing against (prd §901,
        // `LeadCycle`): a thing captured after this, appearing now, landed
        // while you were looking; the corpus the page opened to did not.
        .environment(\.feedWaveAt, shapeWaveAt)
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
        .animation(DS.Motion.standard, value: listRevision(rows))   // new things rise in (debounced for All)
        .scrollContentBackground(.hidden)
        // The Tokens room's tiles — Watchlist and the company packs — on the
        // phone's bottom line beside the seat, the Addresses control.
        // Markets' and Notes' own tiles ride the floating bar (prd §1136
        // item 2): under the box stand You's tiles, the same four on every
        // place in You. One modifier, so this chain stays type-checkable.
        .modifier(FeedRoomDocks(tokens: shape == .tokens, notes: Pinboard.isPinnedRoom(source),
                                tokensScope: chrome.tokensScope, notesScope: chrome.notesScope,
                                notesHold: notesHold,
                                pickTokens: { pickTokensScope($0) }, pickNotes: { pickNotesScope($0) }))
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
        // …AND on the swipe budget lifting (PERF 2026-09-08). The bound is a
        // parameter change that re-arms the query at 1,200 rows, but it
        // changes no corpus revision — so a room entered bounded (every swipe
        // into All, and since today every launch) seeded this snapshot from
        // the 150-row query and then kept it until the next save landed: the
        // head, the footer and the list all describing 150 rows over a room
        // holding 1,200. `AllSnapshotTaskKey` carries the bound, so the lift
        // re-runs the debounced branch and the snapshot follows the query.
        .task(id: allSnapshotTaskKey) {
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
        // SAFETY NET (2026-08-30, field report — a known SwiftData/CloudKit
        // bug, FB14619787): `@Query`'s live observation can permanently stop
        // firing after the corpus is restored from CloudKit on a fresh
        // install. The store genuinely has the data — a raw `fetch()` proves
        // it, and it survives even a full reinstall — but `@Query`'s own
        // `things` never picks it up, so `liveVisible()`'s default path
        // (which reads `things` via `feedThings`) inherits the same
        // blindness, and the `.task(id: corpusRevision)` above can't recover
        // either: it depends on `@Query` itself noticing something changed
        // so the body re-evaluates, which is exactly the notification this
        // bug drops.
        //
        // Keyed on `scenePhase`, not `corpusRevision` — a signal that
        // changes independently of `@Query`'s own health, so this keeps
        // firing even when everything downstream of `things` is stuck.
        // Checked once per foreground activation only (this bug's own
        // reproduction is specifically "on launch"), never a tight poll: one
        // SQL `COUNT` (`Corpus.count`, the same helper `corpusRevision`
        // uses), and a full raw fetch only on an actual mismatch — for the
        // overwhelming majority of installs, where `@Query` is healthy, this
        // is a no-op every single time.
        //
        // Compared against `things.count` CAPPED at the room's own fetch
        // limit, never the raw count directly — `things` is bounded at
        // `allRoomFetchLimit`, so on any corpus larger than that an
        // uncapped comparison would read as a permanent mismatch and run
        // the expensive fallback on every foreground, defeating the bound
        // `things` exists to enforce.
        .task(id: safetyNetKey) {
            guard source == "All", filter.tag == "All", scenePhase == .active else { return }
            // A ROOM THAT IS ALREADY DRAWING ROWS CAN WAIT (PERF 2026-09-08).
            // `things.count` below is a fetch plus a per-model snapshot of the
            // whole 1,200-row window (§646), and this task fires at mount, on
            // every foreground, and again when the launch budget lifts — i.e.
            // inside the seconds a person starts scrolling in. Sampled on the
            // 6k fixture at 194 of 1,083 main-thread samples across a launch.
            // The bug this net exists for renders as an EMPTY room, so when
            // the snapshot already holds rows the check is deferred past the
            // launch window; an empty room still checks at once. A newer key
            // cancels the sleep, which re-arms the check rather than losing it.
            if debouncedAllSnapshot.map({ !$0.isEmpty }) ?? false {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
            }
            // NEVER against a transiently bounded query — see `safetyNetKey`.
            // While the swipe budget is set, `things` holds 150 rows by our own
            // instruction, so the comparison below cannot mean what it is
            // written to mean and the mismatch is manufactured.
            guard rowBudget == nil else { return }
            let cappedRaw = min(Corpus.count(in: modelContext), Self.allRoomFetchLimit)
            guard cappedRaw != things.count else { return }
            // BOUNDED like its per-source sibling below, and here the bound is
            // not a trade but a CORRECTION: `things` is capped at
            // `allRoomFetchLimit` and `cappedRaw` is compared at that cap, so an
            // unbounded recovery re-derived this room's snapshot from a
            // different, larger set than the room is defined to hold — on the
            // largest corpora, the whole store, fully hydrated, on the main
            // actor. At the cap it reproduces exactly the array a healthy
            // `@Query` would have handed over.
            var descriptor = FetchDescriptor<Thing>(
                sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
            descriptor.fetchLimit = Self.allRoomFetchLimit
            guard let raw = try? modelContext.fetch(descriptor) else { return }
            let next = liveVisible(rawOverride: raw)
            allSnapshotKey = snapshotSignature(next)
            debouncedAllSnapshot = next
        }
        // The per-source half of the same safety net (2026-08-30 follow-up):
        // a source room (Vercel, and every other one) carries its OWN
        // `@Query`, unbounded and predicated on `source` (see the init's
        // "else" branch above) — a completely separate live-observation
        // instance from the All room's, so the fix above does not reach it.
        // Same shape: one cheap SQL `COUNT` scoped to this source, per
        // foreground activation, and only on a genuine mismatch does it run
        // a real fetch and populate `sourceRoomFallbackSnapshot`. Excludes
        // Pinboard (its `@Query` is predicated on `pinnedAt`, not `source`,
        // so a source-scoped count would compare the wrong thing) and All
        // (already covered above).
        //
        // CORRECTION (2026-08-31 field report round 3): this shipped, was
        // exercised — the Vercel room was actually visited on a build that
        // has it — and still rendered empty. Diagnostics' per-source
        // predicate-vs-in-memory breakdown (added the same round) is why:
        // on the affected device, `#Predicate<Thing> { $0.source == source }`
        // itself can disagree with a plain Swift filter over an unpredicated
        // fetch of the SAME store. That predicate is the one thing this
        // safety net trusted — both for the mismatch CHECK (`fetchCount`)
        // and for the recovery `fetch` itself — so on exactly the device
        // this exists to save, it can silently confirm "0 == 0, nothing to
        // do" while a raw fetch would show real rows, and even a caught
        // mismatch would recover into the same broken predicate. The All
        // room's own half above was never exposed to this: it re-derives
        // its snapshot from an UNPREDICATED `fetch()` filtered in Swift
        // (`liveVisible(rawOverride:)`), which is exactly why "Vercel now
        // shows in All" was already true before this per-source half did
        // anything.
        //
        // So: whenever this room's live `@Query` is rendering EMPTY — the
        // one shape every field report actually describes ("connected, no
        // feed") — this never asks the predicate at all. It runs the same
        // unpredicated, capped fetch the All room already trusts and
        // filters to `source` in Swift, the same shape Diagnostics' own
        // `bySource` count uses. The cheap predicated `fetchCount` path
        // below still covers the rarer PARTIAL-staleness case (some rows
        // showing, newer ones missing) where the predicate has already
        // demonstrated it can be trusted this session.
        .task(id: safetyNetKey) {
            guard source != "All", !Pinboard.isPinnedRoom(source), scenePhase == .active
            else { return }
            // NEVER against a transiently bounded query — see `safetyNetKey`.
            // This arm is the more expensive of the two and the one a swipe
            // reaches: with the budget set, `things` holds 150 rows, so the
            // `rawCount != things.count` test below is TRUE for every room of
            // any size, and the predicated recovery fetch runs — unbounded and,
            // since 2026-08-31, carrying the heavy inline text — on the main
            // actor, during the slide. It stays unbounded afterwards on
            // purpose: a source room's head describes the WHOLE room (the
            // init's own 2026-08-14 refusal of a permanent `fetchLimit`), so
            // the fix here is to run it at the right TIME, never to truncate it.
            guard rowBudget == nil else { return }
            #if DEBUG
            // The one reading of what the LIVE query returned (prd §623): a
            // plain fetch cannot see the predicated-projection defect, and
            // this net is the exact place it surfaces. Read by the 18.6 arm.
            NSLog("[Casberi] roomNet| source=%@ query=%d lightColumns=%@",
                  source, things.count, Self.sourceRoomLightColumns ? "on" : "off")
            #endif
            if things.isEmpty {
                // BOUNDED, and the bound is load-bearing (2026-08-31): a
                // legitimately empty source room is the COMMON case, not a
                // rare one — a quiet bridge (Polar with no disputes,
                // Cloudflare with nothing expiring) is empty by design and
                // for life. An unbounded `fetch()` here would therefore walk
                // the WHOLE corpus on every foreground of every such room,
                // which is precisely the "materialised six thousand rows to
                // draw thirty" regression this file has already paid for
                // once. Capped at the same limit the All room's own query
                // uses; a source whose rows all sit past that bound is not a
                // shape this recovery can help anyway.
                var descriptor = FetchDescriptor<Thing>(
                    sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
                descriptor.fetchLimit = Self.allRoomFetchLimit
                guard let raw = try? modelContext.fetch(descriptor) else { return }
                let members = RoomAccounts.roomSources(source)
                let scoped = raw.filter { members.contains($0.source) }
                #if DEBUG
                NSLog("[Casberi] roomNet| source=%@ query=empty plain=%d %@", source, scoped.count,
                      scoped.isEmpty ? "(empty in the store too)" : "RECOVERED: the live query dropped rows a plain fetch finds")
                #endif
                guard !scoped.isEmpty else { return }
                sourceRoomFallbackSnapshot = scoped
                return
            }
            // CAPPED AT THE ROOM'S OWN BOUND (prd §600, 2026-09-04) — the
            // correction the All room's half of this net already carries, now
            // owed here too because this room's query gained a `fetchLimit`.
            //
            // Without the cap, every source room holding more than
            // `sourceRoomFetchLimit` rows reads as a PERMANENT mismatch: the
            // raw count says ten thousand, `things.count` says six hundred by
            // our own instruction, and the unbounded recovery fetch below then
            // runs on every foreground of every bulk-import room — on the main
            // actor, carrying the heavy inline text. That is the exact
            // regression the bound was added to remove, arriving through the
            // safety net instead of through the list. It is also invisible:
            // the room renders correctly the whole time.
            // The Wallet's query carries the card seats (prd §1048), so its
            // probe counts the same sources, or every pass would read the card
            // rows as rows the query invented and swap in a Wallet-only fetch.
            // Every other room keeps the plain equality this net was built on.
            let members = RoomAccounts.roomSources(source)
            let predicate = members.count > 1
                ? #Predicate<Thing> { members.contains($0.source) }
                : #Predicate<Thing> { $0.source == source }
            let probe = FetchDescriptor<Thing>(predicate: predicate)
            guard let rawCount = try? modelContext.fetchCount(probe),
                  min(rawCount, Self.sourceRoomFetchLimit) != things.count
            else { return }
            var fetch = FetchDescriptor<Thing>(
                predicate: predicate,
                sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
            // Bounded for the same reason the comparison above is: this array
            // stands in for `things`, so it must reproduce what a healthy
            // `@Query` would have handed over — not a larger set.
            fetch.fetchLimit = Self.sourceRoomFetchLimit
            sourceRoomFallbackSnapshot = try? modelContext.fetch(fetch)
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
                chrome.roomMounts &+= 1
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
        // One row per object in Work and Reading (prd §1079): the keys read
        // the rows' links, a heavy column, so they are read once per corpus
        // revision off the main actor, never in a body.
        .task(id: objectFoldKey) { await recomputeObjectKeys() }
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
        // A row is as tall as what it draws (prd §1136j): a List gives every
        // row 44pt unless told otherwise, and it reads that HERE, on the list —
        // the app header's own setting, on its button, never reached it, so
        // each header was a 20pt label in a 44pt row. Rows that are controls
        // keep their own tap height (`DS.Hit.min`).
        .environment(\.defaultMinListRowHeight, 0)
        // Every lead in the room reads its foot from here (prd §766).
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
            resolveRoomAgent()
        }
        // A key added from Accounts must light the Chat tile without leaving
        // the room (prd §841). Accounts is PRESENTED, not pushed (§796), so
        // the feed never unmounts and `onAppear` does not fire again — add an
        // OpenAI key and the ChatGPT room kept no Chat tile until you left and
        // came back, and removing one left the tile live, which is the dead
        // control §83 bans. `registerConnected` moves `bridges`, so that is
        // the signal; `AgentKey.configured` is memoised on `TokenVault
        // .generation`, so re-asking is a dictionary hit.
        .onChange(of: bridges.bridges.count) { _, _ in resolveRoomAgent() }
        // The Agents room's menu decides whom New talks to (prd §1054).
        .onChange(of: chrome.mergedScope[source]) { _, _ in resolveRoomAgent() }
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
        // Both destinations below leave the seat's column clear
        // (`DSDock.seatClearance`). These two pushes do not run through
        // `HomeRoute.path`, so `MainSurface`'s resolver — where every other
        // pushed screen gets this line — never sees them; the seat floats over
        // them just the same, wearing the face rather than the back door.
        .navigationDestination(item: $openProject) { route in
            ProjectDetailScreen(projectName: route.name)
                .navigationTransition(.zoom(sourceID: route.name, in: zoomNS))
                .dsSeatClearance()
                .dsDemoMarkClearance()
        }
        // The social roster's own door (item 2, 2026-07-27) — a face pushes
        // the person room, not the quick-glance tray `SocialProfileCard`
        // still serves everywhere else.
        .navigationDestination(item: $openPerson) { profile in
            PersonRoomScreen(profile: profile)
                .dsSeatClearance()
                .dsDemoMarkClearance()
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
            // The phone raises the person room (prd §1132: nothing pushes);
            // the Mac keeps the push.
            #if targetEnvironment(macCatalyst)
            openPerson = person
            #else
            feedSheet = .person(source: person.source, handle: person.handle)
            #endif
            chrome.personRequest = nil
        }
        // **A PAYMENT REQUEST A LINK OPENED (prd §728c).** `initial: true`
        // because the link also switches the room: the Frames room's screen
        // mounts AFTER the request is set, so a change-only handler would
        // never see it.
        .onChange(of: chrome.framesSponsorRequest, initial: true) { _, request in
            guard let request else { return }
            feedSheet = .framesSponsor(request)
            chrome.framesSponsorRequest = nil
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
        // GITHUB'S NEXT STEP AFTER A CONNECT (prd §1030). Keyed on `isActive`
        // too: the pager mounts neighbours, and a GitHub page built beside the
        // room in front must neither spend the landing nor raise a tray
        // nobody is looking at. The beat lets the connect sheet finish closing
        // and the room's card land, or the tray's rise is refused mid-dismiss.
        // A method, not an inline closure: this chain sits at the type-checker's
        // limit, and the inline form tipped it over.
        .task(id: githubLandingKey) { await landGitHubWatch() }
        .task(id: serviceDoorKey) { await landServiceDoor() }
        .sheet(item: $roomShare) { input in
            ShareTray(room: input)
        }
        .sheet(item: $folderShare) { input in
            ShareTray(folder: input)
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
        .modifier(NoteDeleteDialog(note: $deletingNote, onDelete: deleteNote))
        .modifier(DayMakeDialog(open: $dayMakeOpen, makes: dayMakes, onPick: makeInDay))
        .modifier(WhichAgentDialog(open: $askingWhichAgent, agents: answeringAgents) { provider in
            pickAgent(provider)
            chrome.beginConversation(with: provider.agent)
            withAnimation(DS.Motion.standard) { chrome.agentScope = .new }
        })
        .modifier(NoteTrashSheet(open: $trashOpen, onRecover: recoverNote,
                                 onErase: { NoteTrash.shared.erase($0) }))
        .modifier(NoteFolderAlert(prompt: $folderPrompt, draft: $folderDraft,
                                  onSave: commitFolderPrompt))
        .modifier(NoteFolderDeleteDialog(folder: $deletingFolder, onDelete: deleteFolder))
    }

    /// Each step opens another target's worth. Monotonic for the life of the
    /// screen: it must not collapse when a thing lands, or scrolling back would
    /// undo itself every sync.
    @State var windowSteps = Self.initialWindowSteps
}

/// What New makes in the Day room (prd §1056).
private struct DayMakeDialog: ViewModifier {
    @Binding var open: Bool
    let makes: [DayMake]
    let onPick: (DayMake) -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(String(localized: "New"), isPresented: $open,
                                   titleVisibility: .hidden) {
            ForEach(makes) { make in
                Button(make.label) { onPick(make) }
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        }
    }
}

/// Which agent New talks to, when the Agents room has no pick (prd §1054).
/// A modifier for `NoteDeleteDialog`'s reason: the chain is long.
private struct WhichAgentDialog: ViewModifier {
    @Binding var open: Bool
    let agents: [AgentProvider]
    let onPick: (AgentProvider) -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(String(localized: "Start a conversation with"),
                                   isPresented: $open, titleVisibility: .visible) {
            ForEach(agents) { provider in
                Button(provider.agent) { onPick(provider) }
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        }
    }
}

/// The confirmation for a note's Delete. A MODIFIER rather than an inline
/// dialog on `FeedScreen`'s chain: the screen's presentation chain is long
/// enough already that a third dialog spelled inline risks the type-checker.
private struct NoteDeleteDialog: ViewModifier {
    @Binding var note: Thing?
    let onDelete: (Thing) -> Void

    func body(content: Content) -> some View {
        // Guarded with `isLive` (the 2026-07-24 crash class): an iCloud
        // delete from another device can remove the note while this is up.
        content.confirmationDialog(
            String(localized: "Delete this note?"),
            isPresented: Binding(get: { note?.isLive == true },
                                 set: { if !$0 { note = nil } }),
            titleVisibility: .visible
        ) {
            Button(String(localized: "Delete note"), role: .destructive) {
                if let note, note.isLive { onDelete(note) }
                note = nil
            }
            Button(String(localized: "Cancel"), role: .cancel) { note = nil }
        } message: {
            Text(String(localized: "It stays in Recently deleted for \(NoteTrashRules.keepDays) days."))
        }
    }
}

/// Recently Deleted's tray (prd §985). A MODIFIER for `NoteDeleteDialog`'s
/// reason.
private struct NoteTrashSheet: ViewModifier {
    @Binding var open: Bool
    let onRecover: (NoteTrashEntry) -> Void
    let onErase: (NoteTrashEntry) -> Void

    func body(content: Content) -> some View {
        content.sheet(isPresented: $open) {
            NoteTrashTray(onRecover: onRecover, onErase: onErase)
        }
    }
}

/// What the Notes room's folder name prompt is for (prd §980): a new folder
/// — filing the row whose menu asked, if one did — or a rename.
enum FolderPrompt {
    case make(filing: Thing?)
    case rename(String)
}

/// The folder name prompt. A MODIFIER for `NoteDeleteDialog`'s reason.
private struct NoteFolderAlert: ViewModifier {
    @Binding var prompt: FolderPrompt?
    @Binding var draft: String
    let onSave: (FolderPrompt, String) -> Void

    private var title: String {
        if case .rename = prompt { return String(localized: "Rename folder") }
        return String(localized: "New folder")
    }

    func body(content: Content) -> some View {
        content
            .alert(title, isPresented: Binding(get: { prompt != nil },
                                               set: { if !$0 { prompt = nil } })) {
                TextField(String(localized: "Name"), text: $draft)
                Button(String(localized: "Save")) {
                    if let prompt { onSave(prompt, draft) }
                    prompt = nil
                }
                Button(String(localized: "Cancel"), role: .cancel) { prompt = nil }
            }
            // The field opens on the folder's own name for a rename, empty
            // for a new one.
            .onChange(of: prompt == nil) { _, closed in
                guard !closed else { return }
                if case .rename(let name) = prompt { draft = name } else { draft = "" }
            }
    }
}

/// The confirmation for a folder's Delete: its rows stay, unfiled.
private struct NoteFolderDeleteDialog: ViewModifier {
    @Binding var folder: String?
    let onDelete: (String) -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(
            String(localized: "Delete this folder?"),
            isPresented: Binding(get: { folder != nil },
                                 set: { if !$0 { folder = nil } }),
            titleVisibility: .visible
        ) {
            Button(String(localized: "Delete folder"), role: .destructive) {
                if let folder { onDelete(folder) }
                folder = nil
            }
            Button(String(localized: "Cancel"), role: .cancel) { folder = nil }
        } message: {
            Text(String(localized: "What's in it stays in All."))
        }
    }
}
