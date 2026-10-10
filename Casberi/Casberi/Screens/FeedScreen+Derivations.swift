import SwiftUI
import SwiftData

// The feed's derivations: what is visible, the memo keys, and the room scopes, split out of
// FeedScreen.swift (prd §718). Nothing here changed but the file it lives
// in and, where another file reads a member, its access level.
extension FeedScreen {
    /// The themes lede's corpus walk, computed once per real change. Kept as a
    /// function (not inline in the `@ViewBuilder`) because a memo needs a
    /// statement body, which a ViewBuilder won't take.
    /// Takes the render's own `visible` (PERF 2026-07-31). It used to read
    /// `self.visible` twice — and for the All room every read is a `.live`
    /// filter over the WHOLE corpus, so the render paid for three passes where
    /// one would do. The caller already holds the array; passing it makes that
    /// obvious rather than incidental.
    func themesData(_ visible: [Thing]) -> (clusters: [HomeComposition.Cluster], doc: [String]?) {
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
    func derivationKey(_ things: [Thing]) -> Int {
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

    /// Identity of a snapshot's contents: what the grouping and bundling
    /// actually key on. Mirrors `derivationKey`'s non-All walk deliberately —
    /// if one ever learns about a new field, so must the other.
    func snapshotSignature(_ things: [Thing]) -> Int {
        var h = Hasher()
        h.combine(things.count)
        for t in things {
            h.combine(t.id)
            h.combine(t.capturedAt)
        }
        return h.finalize()
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
        // A non-All room reads `sourceRoomFallbackSnapshot` in preference to
        // `things` — see the `.task(id: scenePhase)` safety net below. Stays
        // nil (so this is a no-op) unless that task actually found a live
        // `@Query` disagreeing with a raw fetch on the same store.
        if source != "All", let fallback = sourceRoomFallbackSnapshot {
            return Pinboard.isPinnedRoom(source) ? notesOrder(fallback) : Corpus.surfaced(fallback, room: source)
        }
        return Pinboard.isPinnedRoom(source) ? notesOrder(things) : Corpus.surfaced(things, room: source)
    }

    /// `rawOverride` is the escape hatch the safety-net refresh below uses:
    /// when supplied, it stands in for `feedThings` (still run through
    /// `Corpus.surfaced`/pin-room handling the same way `feedThings` itself
    /// does) so the SAME filtering rules apply whether the source array
    /// came from the live `@Query` or from a raw fetch that bypassed it.
    func liveVisible(rawOverride: [Thing]? = nil) -> [Thing] {
        let base = rawOverride.map { Pinboard.isPinnedRoom(source) ? notesOrder($0) : Corpus.surfaced($0, room: source) }
            ?? feedThings
        // Resolved once, not per row (prd §1079).
        let people = socialScopeMembers
        // DAY IS ITS OWN DOOR (prd §1231): on the phone's scrolling Feed the
        // calendar and to-dos stand behind the Day tile, never in the Feed —
        // its box, its glances or its sections.
        let dropsDay = source == "All" && scrollsCategories
        return base.filter { thing in
            if dropsDay, BridgeCatalog.category(forSource: thing.source) == RoomAccounts.dayRoom {
                return false
            }
            // The Notes room's membership is decided entirely by the `@Query`
            // above (`source == "You"`, not the room's name), so there is no
            // source to match against
            // — and matching one is how this room shipped EMPTY (2026-08-10):
            // "Pinned" is not a source any thing carries, so `thing.source ==
            // source` was false for every row the query had just correctly
            // handed over, and the room drew its own "nothing pinned" line over
            // a list that wasn't.
            return (source == "All" || Pinboard.isPinnedRoom(source) || thing.source == source
             || RoomAccounts.rides(room: source, source: thing.source))
                // A bulk import (Instagram, Snapchat) keeps its own room but
                // stays OUT of All — thousands of things dated across years
                // would bury the day's real captures. All sees its receipt
                // only; the chip opens the room that holds the rest.
                && (source != "All" || Corpus.showsInAll(thing))
                && (filter.tag == "All" || thing.tags.contains(filter.tag))
                && walletScopeAllows(thing)
                && personScopeAllows(thing, people: people)
                && notesScopeAllows(thing)
                // Privy's display choices (prd §803e): hidden apps, and empty
                // apps nobody uses unless the person asked to see them.
                && (thing.source != PrivyHomeFeed.source
                    || PrivyHomeStore.shared.shows(thing, inRoom: source == PrivyHomeFeed.source))
        }
    }

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
    var walletbeatWatchedIDs: Set<String> {
        refreshWatchedIDs()
        return memo.walletbeatWatched
    }

    /// The chains the person said they use, for the L2BEAT room's milestone rows
    /// (prd §428). Derived from the room's own rows rather than fetched — making
    /// the watch a `Thing` is what makes that possible, and it means the marker
    /// can never disagree with the watch rows sitting above it in the same feed.
    ///
    /// Scoped to that room by construction: the only caller is `shapedRow`'s
    /// `.l2beat` case, so this walk costs nothing in any other room.
    var l2beatWatchedIDs: Set<String> {
        refreshWatchedIDs()
        return memo.l2beatWatched
    }

    /// Rebuild both watched-id sets, ONCE per body pass (prd §626).
    ///
    /// The two callers above are read per row, and each used to walk
    /// `visible.live` itself — the room's whole corpus per row. This walks it
    /// once and every later row reads a set. Both are built in the same pass
    /// because the walk is the cost and the two extractors are prefix checks
    /// on `sourceRef`; a flag each would save nothing and could disagree.
    ///
    /// Write-during-body, like `groups` and `windowHasMore` above, and safe
    /// for the same reason: `memo` is deliberately not `@Observable`, so
    /// filling it is memoization rather than state (see `DerivationMemo`).
    ///
    /// A stale key can only mean recomputing, never a wrong set.
    @MainActor
    private func refreshWatchedIDs() {
        guard memo.watchedKey != .some(memo.key) else { return }
        memo.watchedKey = .some(memo.key)
        let rows = visible.live
        memo.walletbeatWatched = Set(rows.compactMap { WalletbeatWatch.walletID(from: $0) })
        memo.l2beatWatched = Set(rows.compactMap { L2beatWatch.chainID(from: $0) })
    }

    var visible: [Thing] {
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
    ///
    /// **IT TAKES THE ARRAY, IT DOES NOT FETCH ONE (prd §646, 2026-09-08).**
    /// The non-All arm below read `things.count` — the `@Query` getter, so a
    /// full materialisation of the room on every body pass, to key an
    /// ANIMATION. It is `rows.count` now: the array `listBody` already binds
    /// and already draws. That is a real change of meaning and it is the
    /// meaning the All arm has always had — the count of what is ON SCREEN,
    /// not the count the query returned before the room's scope narrowed it —
    /// so the two arms finally answer the same question. What it costs is
    /// exactness in one direction only: a scope change that swaps which rows
    /// are drawn without changing HOW MANY now animates as no change, where the
    /// raw query count would also have said nothing, since the query is not
    /// what a scope narrows.
    func listRevision(_ rows: [Thing]) -> Int {
        guard source == "All", filter.tag == "All" else { return rows.count }
        // Never `things.count` here (PERF 2026-08-11) — see `corpusRevision`.
        // Before the snapshot exists there is nothing on screen to animate
        // against anyway, so 0 is the honest starting value.
        return debouncedAllSnapshot?.count ?? 0
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
    var roomTakesWalletScope: Bool {
        // Privy's rows are apps, not a watched wallet's transfers — they carry
        // no `walletAddress`, so a picked wallet would empty the room (§803c).
        BridgeCatalog.category(forSource: source) == CategoryFold.walletCategory
            && source != PrivyHomeFeed.source
    }

    /// The per-wallet scope (prd §128, widened to the whole Wallet category by
    /// §356) — everything passes in "All"; when scoped, only rows belonging to
    /// that watched wallet. Matched through `WalletStore.scopeMatches`
    /// (2026-07-20): things are stamped with the RESOLVED hex while the scope
    /// is the WATCHED spelling, so a raw compare empties an ENS/SNS-watched
    /// wallet's scoped feed entirely.
    private func walletScopeAllows(_ thing: Thing) -> Bool {
        // An app the menu picked (prd §1048b) keeps its own rows, and an app
        // whose rows don't ride this room keeps none: its money is in the box.
        if let seat = selectedSeat { return seat.owns(thing.source) }
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
    ///
    /// The merged Social room scopes to a PERSON across networks (prd §1079):
    /// `people` is the picked person's (network, handle) pairs, resolved once
    /// by the caller.
    private func personScopeAllows(_ thing: Thing, people: Set<FollowedPeople.Member>?) -> Bool {
        if let people {
            guard let handle = thing.authorHandle else { return false }
            return people.contains(FollowedPeople.Member(source: thing.source, handle: handle))
        }
        guard SocialRoom.hasRoster(source), let scope = chrome.personScope else { return true }
        return thing.authorHandle == scope
    }

    var filterLabel: String {
        let tagLabel = filter.tag == "All" ? nil
            : (ThingKind.from(typeTag: filter.tag)?.typeTagPlural ?? filter.tag)
        return [source == "All" ? nil : source, tagLabel]
            .compactMap { $0 }.joined(separator: " · ")
    }

    /// The connected bridge the feed is currently filtered to, if any. A source
    /// header appears only for a real, live seat — a plain source (Photos,
    /// Voice, Safari) owns no control panel, so it gets no door. Paused seats
    /// aren't "connected", so they don't either.
    var activeSourceBridge: BridgeApp? {
        guard source != "All" else { return nil }
        // Through the catalog, not against the source: a source name is not
        // always its seat's name ("Privacy Pools" against the "0xBow Privacy
        // Pools" seat), and a bare `==` meant that room silently owned no
        // seat — so it got no header and no door to its own control panel.
        let seat = BridgeCatalog.seatName(forSource: source)
        return bridges.bridges.first { $0.name == seat && $0.status != .paused }
    }
}
