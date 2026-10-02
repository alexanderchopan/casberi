import SwiftUI
import SwiftData

// The room's head: the memoised heads, the kind tiles, the per-source heads, split out of
// FeedScreen.swift (prd §718). Nothing here changed but the file it lives
// in and, where another file reads a member, its access level.
extension FeedScreen {
    // MARK: - The room's head, memoised

    /// The registry answers a room's head is chosen from (PERF 2026-08-21,
    /// prd §434 ruling 1).
    ///
    /// None of these holds a `Thing` — `FeedInsight`'s are plain value
    /// types over counts and labels, and `SourceHead`'s cases carry room models
    /// whose own contract is that they hand back a value and let the VIEW do
    /// the lookup (see the `sourceHead` render below, which says so). That is
    /// what makes this cacheable at all: a cache of model references would be
    /// the SwiftData liveness class this file documents at length, arriving by
    /// the one route none of its six corollaries covers.
    struct RoomHeads {
        let sourceHead: SourceHead?
        let topicMap: FeedInsight.TopicMap?
        let distribution: FeedInsight.Distribution?
        /// Whether the feeds behind a reading room are still answering
        /// (2026-08-23, prd §455). Cached HERE rather than in a task of its
        /// own because it has exactly this lifecycle — recompute when the
        /// room, the pull or the room's contents move — and because
        /// `FeedFreshness` is not `@Observable`, so a body read would never
        /// refresh itself and would copy its whole record dictionary once per
        /// followed feed per body pass.
        var feedHealth: FeedRoomHealth.Standing? = nil
        /// A head that had only its sentence (prd §760). Held as the head rather
        /// than as the string so the balance mask is read when it is drawn.
        var quietHead: SourceHead? = nil
        /// The kind tiles of a kind-tile room (prd §815, §816),
        /// read over the whole room BEFORE the pick narrows it — a presence
        /// read off the narrowed list would leave only the picked kind, and
        /// the tiles would vanish the moment one was tapped. Empty draws none.
        var kindTiles: [RoomKindTile] = []
        /// Which of those tiles carry the attention dot: Safe's Queue while a
        /// transaction awaits your signature, Stripe's Disputes while one is
        /// open.
        var kindAttention: Set<RoomKindTile> = []
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
    @MainActor static var headMemo: [String: RoomHeads] = [:]

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
    var headIdentity: String {
        let revision = source == "All"
            ? Corpus.revision(in: modelContext)
            : Corpus.revision(in: modelContext, source: source)
        return [source, filter.tag, selectedWallet ?? "", chrome.personScope ?? "",
                // The GitHub rail scopes the whole feed (2026-09-11), so it
                // belongs here for this property's own stated reason.
                chrome.githubScope ?? "",
                chrome.pinterestScope ?? "",
                // Bridge state is the one input a corpus revision cannot see —
                // `sourceHead` reads a Stripe balance, PostHog readings, an ASC
                // standing, none of which is a `Thing`. A pull is when somebody
                // is explicitly asking for new numbers, so it re-keys here.
                // Residual, stated: a BACKGROUND sweep that updates bridge state
                // and lands no row leaves the head reading until the next
                // arrival. Acceptable because a sweep that changes a reading
                // almost always lands the row that changed it, and because the
                // alternative is recomputing the whole chain on a timer.
                String(chrome.roomRevision),
                // **THE SEAT THAT BREAKS THE RESIDUAL ABOVE** (prd §548). That
                // note is right about every other bridge: a sweep that changes
                // a reading almost always lands the row that changed it, so the
                // corpus revision moves and the head recomputes. The Frames
                // devnet lands NO row, ever — its whole room is live state — so
                // its revision is frozen at zero and this key would never
                // change. Without its `identity` the head composed once while
                // the demo fixture was still pouring, memoised empty, and the
                // room said "Reading the chain…" forever. Found on a simulator,
                // not by a check: nothing static can see a memo that never
                // invalidates.
                //
                // SCOPED TO ITS OWN ROOM (PERF 2026-09-01). Read
                // unconditionally this is correct and expensive in the wrong
                // place: `identity` touches the devnet's live state, an
                // `@Observable`, and this property is evaluated from EVERY
                // room's body through `headKey` — so All, X and Wallet would
                // each take an observation dependency on devnet state, and a
                // sweep tick would invalidate whichever room you were actually
                // standing in. The term is only ever load-bearing for the room
                // whose own revision cannot move.
                source == FramesIdentity.source ? FramesRoomSource.identity : "",
                // Privy's balances land no row either (prd §803c), so its
                // store's revision re-keys its head and nobody else's.
                source == PrivyHomeFeed.source ? PrivyHomeStore.identity : "",
                // **AND ITS SCOPE** (2026-09-02). The face rail scopes this
                // room's head from today, so it belongs in the memo key for
                // this property's own stated reason: a head that survived a
                // scope change is a card describing rows that are no longer on
                // screen — the face lighting while the card kept listing every
                // account. Scoped to the room for the perf reason the Frames
                // term above gives, and with the same nothing lost.
                source == FramesIdentity.source ? (chrome.framesScope ?? "") : "",
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
    var headKey: String {
        headIdentity + (rowBudget == nil ? "|full" : "|bounded")
    }

    /// The two `@Query`-staleness safety nets' id, for `headKey`'s exact reason
    /// one job over (PERF 2026-09-01).
    ///
    /// Those nets compare a real SQL `COUNT` against `things.count` and fetch on
    /// a mismatch. `rowBudget` is the swipe's transient bound, so while it is
    /// set the mismatch is GUARANTEED and manufactured by us — 150 rows against
    /// a room of thousands — and the recovery fetch they then run is the largest
    /// single main-actor cost in this file, landing inside the frames the slide
    /// animation needs. That is the "lag swiping between screens" report,
    /// arriving by the one route the head task's own `rowBudget` guard did not
    /// already close.
    ///
    /// **The guard alone would be a correctness bug, and this key is why it is
    /// not.** `scenePhase` does not move when the budget lifts, so a net that
    /// declined mid-swipe would never re-run for the life of the mount — and a
    /// room entered by swiping is most rooms. The net would not be deferred but
    /// DISABLED, on exactly the device it exists to save (FB14619787). Same trap
    /// `headKey` documents above, same shape of fix: the budget is in the id, so
    /// the check follows a few hundred ms later on its own.
    ///
    /// **EMPTINESS IS IN THE KEY, and it is the other half of prd §592.** The
    /// two terms above move on a scene change and on a swipe, and a room that
    /// is populated when it mounts and goes empty LATER moves neither — so the
    /// net that exists to catch exactly that never looked again for the life of
    /// the mount. That is the reported sequence: a Wallet room drawing rows,
    /// one tap, and an empty room that stays empty until you leave it.
    ///
    /// A room that is HONESTLY empty re-runs one bounded fetch and returns
    /// without writing anything — the net's own `guard !scoped.isEmpty` is what
    /// makes that free — and the value flips at most twice in a room's life.
    ///
    /// **IT NO LONGER COSTS NOTHING TO ASK, AND THAT PREMISE WAS THIS KEY'S
    /// (build 537's watchdog, 2026-09-08).** This paragraph used to read "it
    /// costs nothing: `roomBody` already reads `things` on this pass
    /// (`Corpus.hasSurfaced`), so the query is materialised either way". That
    /// was true when it was written and is false now: `roomBody` binds the
    /// room's array ONCE and answers its own emptiness test from it, so on
    /// every pass where the room has rows nothing else reads `things` at all.
    /// A shared read is only free while somebody else is paying for it; the
    /// guard in the body below is what replaces the subsidy.
    /// **THE EMPTINESS TERM SHORT-CIRCUITS ON WHAT IS ALREADY DRAWN (PERF
    /// 2026-09-04, prd §600).** This key is evaluated on EVERY body pass — that
    /// is what a `.task(id:)` key is — and `things.isEmpty` is the `@Query`
    /// getter, so asking it materialised the room every time, twice per pass
    /// (both nets share this key). It was added on 2026-09-03 with §592's
    /// emptiness fix and is the newest per-body-pass materialisation on this
    /// screen.
    ///
    /// ONE-DIRECTIONAL, exactly like `roomBody`'s own `roomHasContent` test and
    /// for the same reason: a NON-EMPTY snapshot proves the room has rows, so
    /// the answer is `|rows` with no read at all; an empty or absent snapshot
    /// still asks the query, because a snapshot narrowed by a tag or a scope
    /// can be empty over a room that is not. Same answer in every case; the
    /// expensive read just stops happening whenever there is anything on
    /// screen, which is the case a person is in while they scroll.
    var safetyNetKey: String {
        let base = "\(scenePhase)" + (rowBudget == nil ? "|full" : "|bounded")
        // **A KEY FOR TWO TASKS THAT CANNOT RUN MUST NOT MATERIALISE THE ROOM
        // (crash report 2026-09-08, build 537).** This is `corpusRevision`'s own
        // ruling — "the room guard lives HERE rather than at the `.task(id:)`
        // below, so a per-source room doesn't even run the COUNT" — owed to this
        // key too, and it is the more expensive of the two: `things.isEmpty` is
        // the `@Query` getter, TWO tasks share this key so SwiftUI evaluates it
        // twice, and every page the pager has ever built keeps evaluating it
        // (`everBuilt` latches) on every graph update.
        //
        // `served` is exactly the conjunction of the guards the two task bodies
        // already apply — the All net wants `source == "All" && filter.tag ==
        // "All"`, the per-source net wants a non-All, non-pinned room, and both
        // want `scenePhase == .active` and `rowBudget == nil`. When it is false
        // both bodies return before touching anything, so the key's value is
        // free; `|idle` differs from both `|rows` and `|empty`, so crossing the
        // boundary in either direction still changes the key and still restarts
        // the nets. Behaviour is unchanged; the read is not paid.
        //
        // It also takes the read off the BACKGROUNDING path, which is where the
        // other half of this pair of reports died: leaving the app moves
        // `scenePhase`, the body re-evaluates, and until now that pass
        // materialised the room twice for two tasks that were both about to
        // return — main-thread work inside the exact scene update the
        // scene-update watchdog is timing (§614's family).
        let served = scenePhase == .active && rowBudget == nil
            && (source == "All" ? filter.tag == "All" : !Pinboard.isPinnedRoom(source))
        guard served else { return base + "|idle" }
        let drawn = (debouncedAllSnapshot.map { !$0.isEmpty } ?? false)
            || (sourceRoomFallbackSnapshot.map { !$0.isEmpty } ?? false)
        return base + (drawn || !things.isEmpty ? "|rows" : "|empty")
    }

    /// The room's ENTIRE contents, for the head alone (prd §600, 2026-09-04).
    ///
    /// **This is the other half of `sourceRoomFetchLimit`, and neither half is
    /// correct without it.** The 2026-08-14 ruling refused a permanent bound on
    /// a source room's query because `sourceHead` composed from `visible`, so a
    /// bound would make `XRoom`'s "your loudest year" describe the newest N
    /// posts — §83 fake status, in the room whose whole promise is that it
    /// holds your history. That objection is answered by separating the two
    /// readers rather than by refusing the bound: the LIST is bounded (nothing
    /// draws more than `windowRowBudget` rows anyway) and the HEAD reads
    /// everything, here.
    ///
    /// It is affordable for one reason and only that reason: the head is
    /// computed in `.task(id: headKey)` and memoised in `headMemo`, so this
    /// runs ONCE per (room, corpus revision) — not on every body pass, which is
    /// what the `@Query` it replaces was doing several times per swipe and once
    /// per bridge save during a foreground burst. The total work over a room's
    /// life goes DOWN; what changes is when it happens.
    ///
    /// Shape: predicated, sorted, unbounded, and **deliberately without
    /// `propertiesToFetch`** — that combination is the iOS 18.6 defect the
    /// query's own `init` documents at length, and this is the same known-good
    /// configuration a source room's `@Query` itself carried from 2026-08-31.
    /// The rows go through `liveVisible(rawOverride:)`, so the tag, wallet,
    /// and person scopes apply exactly as they do to the list — a head
    /// must describe the rows the room is showing, only more of them.
    ///
    /// **NEVER FEWER ROWS THAN THE LIST ALREADY HAS.** If this predicate is the
    /// one that is broken on a given device (§592's report: `$0.source ==
    /// source` disagreeing with a plain fetch on the same store), the fetch can
    /// come back short or empty. Then the caller keeps what it already had, so
    /// the worst case here is exactly the pre-§600 behaviour — a head over the
    /// bounded list — rather than a head over nothing, which would silently
    /// delete every reading in the room.
    ///
    /// All and Pinboard return the fallback untouched: All is bounded by its
    /// own ruling (2026-08-06, the user accepted recency-scoped derivations
    /// there) and Pinboard is unbounded already.
    @MainActor
    private func fullRoomRows(fallback: [Thing]) -> [Thing] {
        guard source != "All", !Pinboard.isPinnedRoom(source) else { return fallback }
        let d = FetchDescriptor<Thing>(
            predicate: #Predicate<Thing> { $0.source == source },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        guard let raw = try? modelContext.fetch(d) else { return fallback }
        // Never narrowed by a kind tile (prd §815): the tiles' presence and
        // the lead's foot describe the whole room.
        let full = liveVisible(rawOverride: raw, kindPick: false).live
        return full.count >= fallback.count ? full : fallback
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
    func recomputeHeads() {
        // `.live` at the read, inside the task: `visible` is re-read here rather
        // than captured by the body, and nothing suspends between this line and
        // the computation below, so every model is valid for the whole of it
        // (liveness corollary 6 — the one the audit's check 6 exists for, and
        // the reason a PERF change that moves a fetch is always also a liveness
        // change).
        // THE WHOLE ROOM, never the bounded list (prd §600) — see
        // `fullRoomRows`. This is what lets the query above carry a
        // `fetchLimit` without the head describing a truncated room, which is
        // the entire objection the 2026-08-14 ruling raised.
        let onScreen = visible.live
        let base = fullRoomRows(fallback: onScreen)
        let rows = base
        let head = sourceHead(rows)
        // A quiet head yields only where a cover can carry its line (§906).
        let quiet = head?.quietLine != nil && Shape(source: source).carriesCover
        var computed = RoomHeads(
            sourceHead: quiet ? nil : head,
            topicMap: FeedInsight.topicMap(source: source, things: rows),
            distribution: FeedInsight.distribution(source: source, things: rows),
            // Reads the follow stores and `FeedFreshness`, never `rows` — the
            // whole point is a feed that has stopped producing rows, so a
            // verdict derived from the room's contents could not see it.
            feedHealth: FeedRoomHealthSource.standing(for: source),
            quietHead: quiet ? head : nil)
        if let kindRoom = RoomKindTiles.Room(source: source) {
            let kinds = kindRoomReading(kindRoom, rows: rows)
            computed.kindTiles = kinds.tiles
            computed.kindAttention = kinds.attention
            RoomKindTileMemory.remember(kinds.tiles, for: source)
        }
        Self.headMemo[headIdentity] = computed
        heads = computed
        SwipeClock.mark("heads", detail: "rows=\(rows.count)")
    }

    /// The tiles and their dots, over the whole room.
    @MainActor
    private func kindRoomReading(_ room: RoomKindTiles.Room, rows: [Thing])
        -> (tiles: [RoomKindTile], attention: Set<RoomKindTile>) {
        let census = RoomKindTiles.Census(room: room, refs: rows.map(\.sourceRef))
        var kinds: Set<RoomKindTile> = []
        var hasUnkinded = false
        for thing in rows {
            if let kind = census.kind(ref: thing.sourceRef, url: thing.content, tags: thing.tags) {
                kinds.insert(kind)
            } else {
                hasUnkinded = true
            }
        }
        let tiles = RoomKindTiles.present(room: room, kinds: kinds, hasUnkinded: hasUnkinded)
        var attention: Set<RoomKindTile> = []
        switch room {
        case .safe:
            // "Your turn", read off the same model the head draws, so the dot
            // and the head's lede can never disagree. The module warning is
            // the head's own alert line again (prd §816).
            if let safe = SafeRoomSource.compose(things: rows), safe.awaitsYouCount > 0 {
                attention.insert(.queue)
            }
        case .stripe:
            let open = RoomKindTiles.openDisputes(rows.map { (url: Optional($0.content), tags: $0.tags, title: $0.title) })
            if open > 0 { attention.insert(.disputes) }
        case .splits:
            // A proposal waiting on signatures is the one thing in this room
            // somebody has to act on (prd §820).
            if rows.contains(where: { $0.sourceRef?.hasPrefix(SplitsShape.txPrefix) == true
                                      && $0.tags.contains(SplitsShape.waitingTag) }) {
                attention.insert(.queue)
            }
        case .github, .appStoreConnect, .huggingFace, .posthog, .l2beat, .walletbeat,
             .polar, .dodoPayments, .gitlab, .radicle, .sentry, .vercel, .pagerduty,
             .npm, .pypi, .aws, .cursor, .appleHealth:
            // No dot: a dot is a claim that something needs you, and none of
            // these rooms has a definition of that yet (prd §911).
            break
        }
        return (tiles, attention.intersection(tiles))
    }

    /// The kind tiles as one control (prd §815, §816), or nil when the room
    /// offers none. Where the room draws a head, the head carries it in its
    /// `scopes` slot — `DSRoomChassis.Head`'s own geometry, the Privy pattern;
    /// where it draws none, `kindTileSections` stands it under the cover. One
    /// construction for both, so a tile is the same control in either place.
    ///
    /// The agent whose room this is, and whose key is present (prd §840).
    ///
    /// Held in `@State` and resolved in `onAppear`, never read in a body:
    /// `AgentKey.configured` walks the Keychain on its first read per
    /// `TokenVault.generation`, and a Keychain read inside a body is build
    /// 525's defect (CLAUDE.md).
    ///
    /// **nil where there is no key, which is the §83 half.** An imported
    /// ChatGPT export gives that room rows without giving it anything to ask
    /// with, so the room draws no tiles at all and stays the list it already
    /// was. A Chat tile over a seat that cannot answer is a dead control.
    ///
    /// **The demo stands every agent's room as a keyed one.** It pours the
    /// rows of a connected account, and a connected agent's room has these
    /// tiles; reading the real Keychain there drew them on whichever room the
    /// device happened to hold a key for and on no other. A send with no key
    /// is refused out loud (`AgentAnswerFailure.noKey`), so the tile is not
    /// dead.
    func resolveRoomAgent() {
        let candidates = DemoMode.isActive ? AgentProvider.allCases : AgentKey.configured
        roomAgent = candidates.first { $0.agent == source }
    }

    /// The agent room's two tiles (prd §840). One tile is never drawn — the
    /// grid's own rule (§752) and §83's: All alone offers no choice.
    var agentTiles: DSScopeTiles<AgentRoomScope>? {
        guard roomAgent != nil else { return nil }
        return DSScopeTiles(sections: AgentRoomScope.allCases,
                            active: chrome.agentScope,
                            attention: []) { picked in
            withAnimation(DS.Motion.standard) { chrome.agentScope = picked }
        }
    }

    /// Before this visit's reading lands, the room draws the tiles it drew
    /// last time (`RoomKindTileMemory`, prd §830) — never the attention dot,
    /// which waits for the reading.
    var kindTilesInHead: DSScopeTiles<RoomKindTile>? {
        let room = RoomKindTiles.Room(source: source)
        var tiles = heads?.kindTiles
            ?? (room != nil ? RoomKindTileMemory.tiles(for: source) : nil)
        // GitHub's Watch verb, last (prd §1031) — where a key can act on it.
        if let room {
            tiles = RoomKindTiles.withVerbs(tiles ?? [], room: room,
                                            acting: room == .github && githubKeyed)
        }
        guard let tiles, !tiles.isEmpty else { return nil }
        return DSScopeTiles(sections: tiles,
                            active: roomKindPick,
                            attention: heads?.kindAttention ?? [],
                            verbs: Set(tiles.filter(\.isVerb))) { picked in
            // A verb acts and never scopes; Watch is the only one (§1031).
            if picked.isVerb {
                feedSheet = .githubWatch
                return
            }
            withAnimation(DS.Motion.standard) { chrome.roomKind = picked }
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
    var roomHead: some View {
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
            // Calendar's compose is its New TILE since prd §994 — the row
            // stood above the lead, at the top of the screen (§752). The mail
            // rooms' since prd §1019, for the same reason.
            if let bridge = activeSourceBridge, source != "Reminders", bridge.name != "Calendar",
               !MailScope.rooms.contains(bridge.name),
               let action = SourceActions.action(forSource: bridge.name),
               case .openURL = action.run {
                sourceComposeRow(action)
            }
            // GitHub's source feed leads with its contribution graph (moved
            // **THE GITHUB ROOM DRAWS NO HEAD AT ALL** (user ruling,
            // 2026-09-11: *"the room needs to be one equal list. it can't be a
            // row of words at top different than below. only a chart could be
            // at the top, otherwise whole room needs to be rows"*, then *"it is
            // just a row no sections… just a feed and those are tags"*).
            //
            // Two things went, and for one reason between them. §401's "what
            // is waiting on you" card drew RANKED ENTRIES — a face, a title, a
            // sub-line — which is a SECOND ROW ANATOMY stacked on top of the
            // room's own rows, against the 2026-07-06 band ruling that every
            // kind wears one. And the contributions heatmap is a chart, which
            // the ruling does allow at the top, but it answers "how much did I
            // write this year" and the room is opened to see what moved; it
            // draws on the account page now, where facts about the account sit.
            //
            // What the head was saying is carried by the ROWS instead: the ask
            // is already the first words of a notification's title, and the
            // TYPE of every row is now the tag under its timestamp
            // (`GitHubRowTag`), which is what made the head's ranking legible
            // as a list in the first place.
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

    enum SourceHead {
        case runway(CloudflareRunway)
        // Stripe's head came back with its kind tiles in its scopes slot (prd
        // §816, reversing §815's deletion).
        case stripe(StripeRoom)
        case polar(PolarRoom)
        // Dodo Payments (2026-09-01, prd §558) — the third Merchant of Record,
        // and the only one whose head may state a revenue figure: its bridge
        // lands EVERY succeeded payment, so the sample is the population. See
        // `DodoPaymentsRoom`'s type doc for why Stripe's identical refusal
        // still stands.
        case dodoPayments(DodoPaymentsRoom)
        case posthog(PostHogRoom)
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
        case privacyPools(PrivacyPoolsRoom)
        // ONE case for every onchain card (prd §858, was `gnosisPay`). The
        // seat rides along because `CardSpendRoomCard` needs it for the mark
        // and `openNewest` needs it for the lookup — the room itself is
        // seat-agnostic and must stay that way.
        case cardSpend(CardSpendRoom, seat: String)
        // A fourth wallet-riding seat (2026-08-11) — grouped by TOKEN rather
        // than by rail, since Railgun has no funding platform to rank.
        case railgun(RailgunRoom)
        // Privy (prd §803c) — the apps that made you a wallet, and what the
        // chain says is in them. Composed from `PrivyHomeStore`, because a
        // balance is chain state and lands no row.
        case privy(PrivyHomeFeed.Room)
        // Safe (2026-08-11) — the fifth, and the one that earned its own
        // source rather than joining the fold at "Wallet" (`SafeBridge`'s
        // top-of-file doc, amendment (8)). Ranked by "your turn" rather than
        // a proportion — a Safe has no lead-token/lead-rail shape. Its kind
        // tiles ride the head's scopes slot (prd §816, reversing §815's
        // deletion: "keep the safe head the way it was").
        case safe(SafeRoom)
        // X (2026-08-13, prd §375) — the first head over an IMPORT rather than
        // a live bridge, and the first that displaces a card the room already
        // drew (`FeedInsight.topicMap`). It declines under `XRoom`'s floors so
        // a shallow archive keeps the treemap; see that type's own note for
        // why the year rows carry each year's subject.
        // The journal and agent rooms had heads here (§398, §457) — a strip of
        // years, a strip of months — DELETED in prd §832 (user: "those charts
        // we have at their head is kind of useless"): they lead with their
        // newest entry or conversation, the one template.

        /// THE HEAD'S SENTENCE, WHEN THE SENTENCE IS ALL IT HAS (prd §760, user:
        /// "the cover should always be there"). A head with no rows, no axis and
        /// no strip is a line of words in a box the height of the wallet head,
        /// so the room leads with its newest thing as the cover instead, and
        /// this sentence rides under it. Nil for a head that draws anything
        /// else, which keeps its card. Walletbeat and L2BEAT always keep theirs:
        /// the directory link is the room's only door to that screen (§421).
        var quietLine: String? {
            let mask = BalancePrivacy.shared.withheld ? BalancePrivacy.mask : nil
            switch self {
            case .runway(let room):
                guard room.items.isEmpty, let next = room.next else { return nil }
                return CloudflareRunway.quietHeadline(days: next.days)
            case .stripe(let room):
                return room.items.isEmpty ? StripeRoom.headline(room) : nil
            case .polar(let room):
                return room.items.isEmpty ? PolarRoom.headline(room) : nil
            case .dodoPayments(let room):
                return room.retries.isEmpty && room.currencies.count <= 1
                    ? DodoPaymentsRoom.headline(room, mask: mask) : nil
            case .cardPointers(let room):
                return room.deadlines.isEmpty ? room.headline : nil
            case .peer(let room):
                return room.rails.count <= 1 ? PeerRoom.headline(room) : nil
            case .railgun(let room):
                return room.tokens.isEmpty ? RailgunRoom.headline(room) : nil
            case .privy(let room):
                return room.funded.isEmpty && room.readCount == 0 ? PrivyHomeFeed.headline(room) : nil
            case .safe(let room):
                // A module or a guard is a fact about money that keeps the card.
                return room.entries.isEmpty && SafeRoom.note(room) == nil
                    && SafeRoom.guardNote(room) == nil && SafeRoom.stateNote(room) == nil
                    ? SafeRoom.headline(room) : nil
            case .cardSpend(let room, _):
                return room.months.isEmpty && room.currencies.count <= 1
                    ? CardSpendRoom.headline(room, mask: mask) : nil
            case .posthog, .walletbeat, .l2beat, .privacyPools:
                return nil
            }
        }
    }

    /// Which rooms may lead with an anniversary: the two journals, over their
    /// entries, which is every row they have. Snapchat's memories room was the
    /// other and left in prd §832 — it leads with its newest thing.
    ///
    /// The import receipt is excluded for the reason every aggregate over these
    /// rooms excludes it (`Corpus.isImportReceipt`): "3 years ago today" over
    /// our own note about a sync is the app reminiscing about itself.
    func journalAnniversary(visible: [Thing]) -> OnThisDay.Echo? {
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
        // A quiet head draws no card (prd §760), so it is absent here too.
        sourceHead(liveVisible()).map { $0.quietLine != nil } ?? true
    }

    /// Resolve this room's own head, or nil. One `switch` so adding a fourth
    /// per-source head is one case here rather than an edit to five gates.
    private func sourceHead(_ visible: [Thing]) -> SourceHead? {
        switch source {
        case "Cloudflare":
            return CloudflareRunwaySource.compose(things: visible).map { .runway($0) }
        case "Stripe":
            return StripeRoomSource.compose(things: visible).map { .stripe($0) }
        case "Polar":
            return PolarRoomSource.compose(things: visible).map { .polar($0) }
        case DodoPaymentsRoomSource.source:
            return DodoPaymentsRoomSource.compose(things: visible).map { .dodoPayments($0) }
        case "PostHog":
            return PostHogRoomSource.compose(things: visible).map { .posthog($0) }
        case WalletbeatRoomSource.source:
            return WalletbeatRoomSource.compose(things: visible).map { .walletbeat($0) }
        case L2beatRoomSource.source:
            return L2beatRoomSource.compose(things: visible).map { .l2beat($0) }
        case CardPointersRoomSource.source:
            return CardPointersRoomSource.compose(things: visible).map { .cardPointers($0) }
        case PeerRoomSource.source:
            return PeerRoomSource.compose(things: visible).map { .peer($0) }
        case PrivacyPoolsRoomSource.source:
            return PrivacyPoolsRoomSource.compose(things: visible).map { .privacyPools($0) }
        case GnosisPayRoomSource.source:
            return GnosisPayRoomSource.compose(things: visible)
                .map { .cardSpend($0, seat: GnosisPayRoomSource.source) }
        // The second onchain card (prd §858). Same head, same judgements — the
        // only thing that differs is which rows it reads and whose mark it
        // wears.
        case MetaMaskCardRoomSource.source:
            return MetaMaskCardRoomSource.compose(things: visible)
                .map { .cardSpend($0, seat: MetaMaskCardRoomSource.source) }
        // The third and last onchain card (prd §868). Same head again — what
        // differs is that this room is SHARED with the staking half of the
        // seat, so its source declines the unstake and risk rows rather than
        // counting them as spends it could not price (`CardSpendSeat`).
        case EtherFiCashRoomSource.source:
            return EtherFiCashRoomSource.compose(things: visible)
                .map { .cardSpend($0, seat: EtherFiCashRoomSource.source) }
        case RailgunRoomSource.source:
            return RailgunRoomSource.compose(things: visible).map { .railgun($0) }
        case PrivyHomeFeed.source:
            let room = PrivyHomeStore.shared.room
            return room.appCount > 0 ? .privy(room) : nil
        case SafeRoomSource.source:
            return SafeRoomSource.compose(things: visible).map { .safe($0) }
        default:
            return nil
        }
    }

    /// The list-row chrome every insight hero mounts in (clear background, no
    /// separator, edge-to-edge — the card owns its own padding).
    @ViewBuilder
    func insightSection<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        Section {
            content()
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
        }
    }
}
