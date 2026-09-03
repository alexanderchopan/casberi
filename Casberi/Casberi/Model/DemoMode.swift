import Foundation
import SwiftData

/// The furnished demo, as a state someone can enter and leave — the onboarding
/// fork's fourth card.
///
/// **Why it exists.** Every hero this app has — the treemaps, the sankey, the
/// day dial, the room heads, the agent panel, the brief — needs a corpus to
/// draw, so a new install shows none of them. The three fork cards each fix
/// that with the person's OWN data, which is the right answer and is also a
/// commitment: a folder, a wallet, or somebody to follow. Someone still
/// deciding whether this app is for them has nothing to look at until they
/// have already decided. The demo is the fourth answer: see it furnished
/// first, commit second.
///
/// **Why it is not the lead card.** The three real cards produce evidence from
/// your own life, and that is what converts; a demo that led would make the
/// common path "explore a stranger's beautiful corpus, then land on an empty
/// lot". So it sits last, phrased as the option for someone not ready to
/// connect anything — an escape hatch, not the nudge.
///
/// **Why it writes to the real store rather than a container of its own.**
/// An isolated container makes exit free (close the door, nothing to delete)
/// and keeps the rows off the person's iCloud. It was still declined: the app
/// holds exactly one container by design — `SharedStore.live`'s own comment
/// records that opening the store twice gives two contexts over one file that
/// silently disagree — and swapping containers mid-session would put that
/// invariant on the demo path, where a bug reads as data loss. The demo rows
/// use only existing `Thing` fields, so nothing here touches CloudKit's
/// Production schema; what it costs is ~400 rows mirroring to the person's
/// zone and then a matching set of deletes on exit. That is a real cost, and
/// the honest mitigation is that leaving is always one tap away and always
/// complete (`DemoSeedAll.teardown`).
///
/// **The §83 obligation.** A fake Stripe dispute and a fake $12,480 crown in
/// the app's ordinary chrome are exactly the fake status the honesty rule
/// bans. So the demo is never silent: while it is active the shell wears a
/// standing banner that says so and carries the way out. If that banner is
/// ever made dismissible, this stops being honest.
enum DemoMode {
    private static let activeKey = "demo.mode.active"

    /// Read from `BridgeStore.init` and from view bodies, so it stays cheap
    /// and non-isolated — one `UserDefaults` read.
    static var isActive: Bool { ScratchDefaults.standard.bool(forKey: activeKey) }

    private static let seenKey = "demo.mode.hasSeen"

    /// Sticky once the demo has ever been entered, and never cleared by
    /// leaving — that is the point. The fork uses it to stop offering a tour
    /// of a room the person has just walked out of.
    static var hasSeen: Bool { ScratchDefaults.standard.bool(forKey: seenKey) }

    /// The standing questions a furnished install would plausibly have kept.
    ///
    /// Four now (2026-08-07, was two) — each checked against the actual seed
    /// rather than reasoned about, because a kept ask whose composer comes
    /// back empty renders as a chip that answers nothing, worse than not
    /// offering it:
    ///   • `today` composes over whatever the corpus holds.
    ///   • `wallet` has the seeded address and its balance curve behind it.
    ///   • `showtag:Release` — `Corpus.tags.contains("Release")` matches 7
    ///     seeded rows (the Vercel deploys + npm/PyPI releases in
    ///     `DemoSeedAll.infra`), which is also the exact count the Themes
    ///     treemap draws ("Release · 7 things") — the same fact, two places.
    ///   • `context:Linear` — two Linear issues land inside 3 days
    ///     (`DemoSeedAll.work`'s `issues` at days 1 and 2), so the composer's
    ///     3-day window (not its 7-day fallback) is what actually answers.
    /// Widen further only against a real run, never by reasoning about what
    /// the seed probably contains — re-verify both counts if `infra`/`work`
    /// changes.
    /// ONE (prd §577b, user: "these prepopulated answers SHOULD NOT BE THERE
    /// … all of that is crap that will return garbage answers anyways. the
    /// only thing useful is 'how's my wallet'").
    ///
    /// It was four, and the other three are the §543 class the demo was still
    /// paying: a kept pill is supposed to mean "you pinned this", and seeding
    /// four of them puts standing questions on a new person's agent that they
    /// never asked for and cannot have wanted. Worse, they answer BADLY —
    /// "Show Release" and "What's new in Linear?" recite a tag and a source
    /// over a corpus somebody has had for ninety seconds, which is the
    /// demo's own furniture read back to it.
    ///
    /// The wallet ask survives because it is the one that answers with
    /// something the person cannot get by looking: a figure, a delta and what
    /// moved it. Keeping exactly one also demonstrates the FEATURE — that a
    /// question can be pinned — without pretending anybody pinned four.
    ///
    /// `teardown` iterates this same list, so removing an entry here removes
    /// its seed and its cleanup together; a pill seeded by an older build
    /// simply stays kept, which is correct — it is the person's now.
    private static let keptAsks: [(kind: String, title: String)] = [
        ("wallet", String(localized: "How's my wallet?")),
    ]

    /// Asks this demo USED to pin, and the titles it pinned them under.
    ///
    /// `exit` iterates the CURRENT list, so an ask the demo planted and later
    /// stopped planting can never be taken back by it: it stays pinned for
    /// good on every device that ran that build. Three of them shipped —
    /// found 2026-09-02 on a simulator carrying "How's my day?", "Show
    /// Release" and "What's new in Linear?" long after the list had been cut
    /// to one — and a pinned question nobody chose is exactly wrong in the one
    /// place the product promises the person's OWN standing questions.
    ///
    /// The title must match too, and that is the whole safety argument. A
    /// person is free to keep "How's my day?" themselves, and by KIND alone
    /// this would delete it — so the seeded title is the strongest evidence
    /// available that the pin is ours rather than theirs. It is
    /// `String(localized:)` on both sides, so a device that ran the demo in
    /// Spanish matches its own Spanish title; anything else simply does not
    /// match and the pill stays, which is the right way to be wrong.
    private static let retiredKeptAsks: [(kind: String, title: String)] = [
        ("today", String(localized: "How's my day?")),
        ("showtag:Release", String(localized: "Show Release")),
        ("context:Linear", String(localized: "What's new in Linear?")),
    ]

    private static let retiredAsksSweptKey = "demo.mode.retiredAsksSwept.v1"

    /// Take back the pins the demo left behind, ONCE.
    ///
    /// Once, because a person who re-keeps one of these on purpose afterwards
    /// must keep it — a sweep that ran every launch would delete their choice
    /// every launch, which is a far worse bug than the one it fixes.
    ///
    /// Gated on `hasSeen` because only a device that ran the demo can be
    /// holding one, so an install that never did is never touched at all.
    @MainActor
    static func sweepRetiredKeptAsks() {
        guard !ScratchDefaults.standard.bool(forKey: retiredAsksSweptKey) else { return }
        ScratchDefaults.standard.set(true, forKey: retiredAsksSweptKey)
        guard hasSeen else { return }
        for ask in retiredKeptAsks
        where KeptAskStore.shared.titles[ask.kind] == ask.title {
            KeptAskStore.shared.remove(ask.kind)
        }
    }

    /// The prior-window brief history, the tap-learning counters, and the
    /// away window — the agent's MEMORY, as distinct from its corpus. A
    /// furnished feed with none of this composes a Today brief with no
    /// streak lede, offers composer tiles in a flat unlearned order, and can
    /// never answer "while I was away" on a fresh install — three flagship
    /// surfaces reading as day-one over data staged to look lived-in.
    ///
    /// `symbol`/`themes` are read off the SAME facts the live corpus will
    /// independently produce, not invented: "ETH" because the seeded wallet
    /// curve is 62% ETH (`DemoSeedAll.seedBridgeState`'s `holdings` split),
    /// "Release"/"Alert" because those are real `Thing.tags` values on rows
    /// the Themes treemap already counts — so `BriefLedger.symbolStreak`/
    /// `themeStreak`, which compare a seeded PAST entry against what the LIVE
    /// compose produces, actually match rather than silently miss.
    private static let ledgerSymbol = "ETH"
    private static let ledgerThemes = ["Release", "Alert"]
    private static let ledgerSources = ["X", "Photos", "Obsidian", "Linear"]
    private static let ledgerDays = 6

    /// A stale tile (offered past `AskMemory.neglectThreshold` with no tap)
    /// so the composer's live demotion is visible on the first open — the
    /// exact proof CLAUDE.md documents for the real feature ("seed pulse:12,
    /// watch pulse move last"). `week` is a real composer kind (`Shell/
    /// Composer.swift`'s `AskOption(kind: "week", …)`), always offered, so
    /// there's always something for it to demote BEHIND.
    private static let neglectedAsk = "week"
    /// A kind that is NOT in `keptAsks` above, primed past
    /// `AskMemory.mintThreshold` so its "you ask this a lot — keep it?"
    /// upgrade is already showing rather than requiring three live taps in
    /// the middle of a demo. `overdue`'s composer (`KeptAskComposers
    /// .overdue`) reads ONLY `Reminders`/`Todoist` rows with a past `dueAt`
    /// — `DemoSeedAll.schedule`'s Todoist task "Book the dentist" is dated
    /// one day overdue, the single row that qualifies. (The composer never
    /// returns nil — an empty overdue list still composes "Nothing
    /// overdue." — so this is checked for a REAL non-empty answer, not
    /// merely a non-crashing one.)
    private static let primedMintAsk = "overdue"

    /// The rooms somebody actually OPENED while the demo was furnished —
    /// read by the onboarding fork to decide which card to lead with
    /// (prd §422; the fork it ordered was deleted 2026-08-31).
    ///
    /// **Why this can't just read `ChipMemory`.** That store already counts
    /// room opens, and `DemoSeedAll.teardown` calls
    /// `ChipMemory.forgetDemo(demoVisits.keys)` on the way out — which
    /// removes those keys OUTRIGHT, seeded weight and the person's own taps
    /// together. That is the correct behaviour there (leaving must not leave
    /// a stranger's tap-learning behind), and it means every source the demo
    /// furnishes has its count erased at exactly the moment the fork needs
    /// it. So the fork keeps its own record, of the person's taps only.
    ///
    /// Cleared by `begin` and NOT by `exit`, deliberately: a second demo run
    /// starts a fresh record, and the record has to outlive the demo by one
    /// screen or it answers nothing. It is counts against source names in
    /// local defaults — the same shape and the same reach as `ChipMemory`
    /// and `AskMemory`, with no edit surface and nothing that leaves.
    private static let roomVisitsKey = "demo.mode.roomVisits"

    static var roomVisits: [String: Int] {
        ScratchDefaults.standard.dictionary(forKey: roomVisitsKey) as? [String: Int] ?? [:]
    }

    /// Record a room open. A no-op outside the demo, so the ordinary
    /// tap-learning path pays one `Bool` read for it.
    ///
    /// "All" is excluded for `ChipMemory.visited`'s own reason: it is the
    /// baseline every session starts from, not a room competing for a front
    /// slot — and here it would also be the one label that maps to no
    /// catalog category at all.
    nonisolated static func noteRoomVisit(_ source: String) {
        guard source != "All", isActive else { return }
        var visits = roomVisits
        visits[source, default: 0] += 1
        ScratchDefaults.standard.set(visits, forKey: roomVisitsKey)
    }

    /// Set while the rows have been promised but not yet poured.
    private static let pendingKey = "demo.mode.pourPending"

    /// Rows per beat, and the beat. Together these spend ~1.8s on a ~400-row
    /// seed. Small enough that each step is well inside a frame's budget;
    /// slow enough to read as arriving rather than as a stutter.
    ///
    /// The count is MEASURED, not estimated (2026-08-17): the All room alone
    /// censuses 378 rows, and this file's own race note below quotes a real
    /// launch pouring 370 and then 406. It read "~330" everywhere until then,
    /// a figure from the seed's first week that four separate comments had
    /// copied from each other — harmless on its own, and worth correcting
    /// because it is the number anyone sizing this pour would reason from.
    private static let pourChunk = 12
    private static let pourBeat = Duration.milliseconds(55)

    /// Claim the mode WITHOUT landing any rows — instant, so the caller can
    /// lift the onboarding cover immediately.
    ///
    /// Split from the pour on purpose, and the split IS the delight: seeding
    /// behind the cover would hand someone a finished feed, which reads as a
    /// screenshot. Lifting first and pouring after lets them watch the app
    /// fill — chips appearing, rows landing, the crown arriving — which is the
    /// one moment that shows what this product actually does rather than
    /// describing it.
    @MainActor
    static func begin(store: BridgeStore) {
        ScratchDefaults.standard.set(true, forKey: activeKey)
        ScratchDefaults.standard.set(true, forKey: pendingKey)
        ScratchDefaults.standard.set(true, forKey: seenKey)
        // A fresh run, a fresh record of what gets opened in it — see
        // `roomVisitsKey`. Cleared here rather than on exit so the fork can
        // still read the run that just ended.
        ScratchDefaults.standard.removeObject(forKey: roomVisitsKey)
        // The catalog must not contradict the feed: rooms full of rows over a
        // catalog claiming nothing is connected reads as a bug. `bridges`
        // persists on write, so this survives relaunch with no init path of
        // its own.
        store.bridges = BridgeApp.demo
        for ask in keptAsks { KeptAskStore.shared.keep(ask.kind, title: ask.title) }

        // The agent's MEMORY, not just its corpus (2026-08-07) — see the
        // property docs above for what's seeded and why each composes
        // non-empty. The checkpoint runs BEFORE the ledger seed so it
        // captures the true pre-demo state (empty, on every real first
        // entry) rather than the state this call is about to create.
        BriefLedger.demoCheckpoint()
        BriefLedger.seedDemo(days: ledgerDays, symbol: ledgerSymbol,
                             themes: ledgerThemes, sources: ledgerSources)
        AskMemory.seedDemo(neglect: [neglectedAsk: AskMemory.neglectThreshold + 2],
                           made: [primedMintAsk: AskMemory.mintThreshold])
        AppVisit.seedDemo()
        // The Tokens room's sparkline/price/percent (2026-08-11) — see
        // `TokenPulse.seedDemo`'s own doc for why this can't just be
        // `BridgeRefresh.refreshAllConnected` running for real. Only the
        // FIRST seed for this demo session happens here — `pulses` is
        // in-memory only, so every later relaunch reseeds from
        // `BridgeRefresh`'s own gate instead (`TokenPulse.reseedDemoIfNeeded`).
        TokenPulse.shared.seedDemo()
        // The two prediction rooms' watched-market odds — same reasoning,
        // same lifecycle (2026-08-12). `PredictionRow` mounts only when a
        // pulse exists, so without this the demo's four markets drew as
        // bare title-and-timestamp rows.
        PredictionPulse.shared.seedDemo()

        NSLog("[Casberi] demoMode: began")
    }

    /// Pour the rows in, a handful at a time, yielding between each so the
    /// feed can draw every beat.
    ///
    /// The chunking is `ImportCommit`'s shape and exists for its reason as
    /// well as for the animation: these are main-actor inserts into the
    /// context a live `@Query` is watching, so doing all ~400 at once holds
    /// the main thread through the exact frames this is trying to make
    /// beautiful. A chunk is a commit here too, which is what makes the pour
    /// safe to interrupt — a kill mid-pour leaves the pending flag set and
    /// the next launch finishes the job, because `seed` dedupes on
    /// `sourceRef`.
    ///
    /// True while a pour is actually running on this process — an in-memory
    /// guard, not persisted (`pendingKey` is the cross-launch one).
    ///
    /// Necessary because THIS FUNCTION HAS TWO INDEPENDENT CALL SITES on the
    /// same launch (`RootShell.handleActivation`'s unconditional call, added
    /// so a pour interrupted mid-flight resumes on the next foreground —
    /// see that call site's own comment — and `-demoEnter YES`'s headless
    /// probe hook), and `pendingKey` alone does NOT serialize them: this
    /// function is `async` and suspends every chunk (`Task.sleep`, the
    /// entrance beat), so a SECOND call starting while the first is
    /// suspended mid-pour reads `pendingKey` still `true` (it's only cleared
    /// at the very end) and `landed` from an INCOMPLETE snapshot — then
    /// inserts its own copy of whatever the first call hasn't gotten to yet.
    /// Caught exactly that way on the sim (2026-08-07): a fresh `-demoEnter`
    /// launch poured 370 rows, then 406 more on the SAME launch — 776
    /// against a ~360-row corpus, the duplicate-`sourceRef` class this
    /// codebase has no unique constraint to catch for free.
    private static var pouring = false

    /// Idempotent and self-clearing; cheap to call on every launch.
    @MainActor
    static func pourIfNeeded(context: ModelContext) async {
        guard ScratchDefaults.standard.bool(forKey: pendingKey) else { return }
        guard !pouring else { return }
        pouring = true
        defer { pouring = false }

        // State before rows: the crown, the balance curve and the seller
        // tables are what the room HEADS read, and a head that arrives after
        // its own rows reads as a late correction rather than a filling app.
        DemoSeedAll.seedBridgeStateForDemo()

        let landed = Set(((try? context.fetch(FetchDescriptor<Thing>())) ?? [])
            .compactMap(\.sourceRef))
        let rows = DemoSeedAll.rooms().filter { !landed.contains($0.sourceRef ?? "") }
        for start in stride(from: 0, to: rows.count, by: pourChunk) {
            for thing in rows[start..<min(start + pourChunk, rows.count)] {
                context.insert(thing)
            }
            context.saveHonestly()
            try? await Task.sleep(for: pourBeat)
        }
        ScratchDefaults.standard.set(false, forKey: pendingKey)
        NSLog("[Casberi] demoMode: poured %d rows", rows.count)
    }

    /// How stale the newest demo row may get before a re-stamp fires. Under
    /// this, "Standup · 9:33 AM" dated yesterday still reads as a normal
    /// morning's lag; past it, a demo whose whole job is showing the app
    /// ALIVE starts showing the opposite.
    private static let staleAfter: TimeInterval = 20 * 3600

    /// Freshness re-stamp (2026-08-07) — a demo left alive for a week shows
    /// every row a week stale, the seat lines still say "Synced 4m ago", and
    /// the whisper never fires because nothing landed "today". Called on
    /// every activation while `isActive`; a no-op the moment the newest demo
    /// row is recent enough, so most calls cost one fetch and nothing more.
    ///
    /// **Whole days only**, and that's deliberate, not a rounding
    /// convenience: shifting by a whole number of days moves every row's DATE
    /// without touching its TIME OF DAY, so the day-dial's hour spread is
    /// untouched, and it moves every row by the SAME amount, so the RELATIVE
    /// spacing between rows — which is what a heatmap's "there was a cluster
    /// here" shape actually shows — survives even though each row's absolute
    /// weekday drifts. A demo whose interesting feature is a shape, not a
    /// specific Tuesday, should keep the shape.
    ///
    /// Scoped to what THIS file owns: `DemoSeedAll.refPrefixes` for Things,
    /// the demo wallet's balance curve, and the ledger entries `seedDemo`
    /// planted (`BriefLedger.shiftDemoWindows`) — never a real wallet or a
    /// real ledger entry recorded during the live session, which is why the
    /// ledger half tracks its OWN seeded set rather than shifting everything
    /// with a `windowStart` in the past.
    /// The `pouring` reasoning applies here too, one function over: this
    /// `async` function suspends (the chunked write loop's own yield), so a
    /// second concurrent call would read the "newest row" date from BEFORE
    /// the first call's shift landed and compute the identical `shiftDays`
    /// again — double-shifting every row rather than duplicating them, a
    /// different failure with the same root cause. Guarded even though no
    /// second call site exists yet, on the same reasoning `pouring` itself
    /// is: `pourIfNeeded` had exactly one call site too, right up until it
    /// didn't.
    private static var restamping = false

    @MainActor
    static func restampIfStale(context: ModelContext) async {
        guard isActive else { return }
        guard !restamping else { return }
        // NOT just `!restamping` — a pour IN PROGRESS anywhere must also
        // hold this off, and the reason is a real bug this exact function
        // shipped once already (caught on the sim, 2026-08-07): `pouring`'s
        // guard makes a second, blocked `pourIfNeeded` call return
        // INSTANTLY — which `handleActivation`'s sequential `await
        // pourIfNeeded(); await restampIfStale()` cannot distinguish from
        // "nothing was pending, safe to proceed". So the caller whose pour
        // got blocked walked straight into a restamp against a corpus only
        // PARTIALLY landed by the OTHER caller's still-running pour — an
        // early row or two, dated hours apart on purpose, read as stale
        // relative to a corpus that hadn't finished arriving, and
        // "re-stamped 24 rows" logged while "poured 406 rows" was still four
        // seconds from finishing. Deferring to ANY in-flight pour, not just
        // one this call started, is what actually closes it.
        guard !pouring else { return }
        restamping = true
        defer { restamping = false }

        var newest = FetchDescriptor<Thing>(
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        newest.propertiesToFetch = [\.capturedAt, \.sourceRef]
        newest.fetchLimit = 1
        // The newest row overall, not the newest DEMO row — on a demo-clean
        // install (the only state this mode is entered from) every row is
        // demo-owned, so the distinction only matters on a dev install with
        // real data mixed in, where the right answer is to do nothing rather
        // than misjudge staleness off a stranger's timeline.
        guard let head = (try? context.fetch(newest))?.first,
              let ref = head.sourceRef, DemoSeedAll.refPrefixes.contains(where: ref.hasPrefix),
              Date.now.timeIntervalSince(head.capturedAt) > staleAfter
        else { return }

        let calendar = Calendar.current
        let shiftDays = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: head.capturedAt),
            to: calendar.startOfDay(for: .now)).day ?? 0
        guard shiftDays > 0 else { return }

        var descriptor = FetchDescriptor<Thing>()
        descriptor.propertiesToFetch = [\.sourceRef, \.createdAt, \.capturedAt, \.dueAt]
        let all = (try? context.fetch(descriptor)) ?? []
        let rows = all.filter { thing in
            guard let ref = thing.sourceRef else { return false }
            return DemoSeedAll.refPrefixes.contains { ref.hasPrefix($0) }
        }

        // `ImportCommit`'s shape: chunked, saved and yielded between chunks —
        // this is a main-actor write into a context a live `@Query` is
        // watching, so shifting several hundred rows in one pass would hold
        // the thread through exactly the frames someone is looking at.
        // Liveness is re-checked INSIDE the loop per row (corollary 3/6):
        // this function is `async` and yields between chunks, so a row held
        // from before a suspension may no longer be live after one.
        let chunk = 40
        for start in stride(from: 0, to: rows.count, by: chunk) {
            for thing in rows[start..<min(start + chunk, rows.count)] where thing.isLive {
                if let shifted = calendar.date(byAdding: .day, value: shiftDays, to: thing.createdAt) {
                    thing.createdAt = shifted
                }
                if let shifted = calendar.date(byAdding: .day, value: shiftDays, to: thing.capturedAt) {
                    thing.capturedAt = shifted
                }
                if let due = thing.dueAt,
                   let shifted = calendar.date(byAdding: .day, value: shiftDays, to: due) {
                    thing.dueAt = shifted
                }
            }
            context.saveHonestly()
            try? await Task.sleep(for: .milliseconds(5))
        }

        // The wallet curve — same key `seedBridgeState` writes, read via the
        // shared accessor so the format can't drift between the two call
        // sites (2026-08-07: was a duplicated string literal in three
        // places before this).
        let key = WalletStore.historyKey(DemoSeedAll.demoWallet)
        if let data = ScratchDefaults.standard.data(forKey: key),
           let samples = try? JSONDecoder().decode([WalletStore.ValueSample].self, from: data) {
            let shifted = samples.map { sample in
                WalletStore.ValueSample(
                    at: calendar.date(byAdding: .day, value: shiftDays, to: sample.at) ?? sample.at,
                    usd: sample.usd, holdings: sample.holdings)
            }
            if let reencoded = try? JSONEncoder().encode(shifted) {
                ScratchDefaults.standard.set(reencoded, forKey: key)
            }
        }

        BriefLedger.shiftDemoWindows(byDays: shiftDays)

        NSLog("[Casberi] demoMode: re-stamped %d rows forward %d day(s)", rows.count, shiftDays)
    }

    /// Leave, and leave nothing behind.
    ///
    /// The verb is EXIT, not delete — the person never chose to keep any of
    /// this, so asking them to "delete everything" would be asking them to
    /// take responsibility for rows the app poured in. What they land on is
    /// the ordinary empty feed, which already knows how to invite the first
    /// real thing.
    @MainActor
    static func exit(context: ModelContext, store: BridgeStore) {
        let rows = DemoSeedAll.teardown(context)
        store.bridges = []
        for ask in keptAsks { KeptAskStore.shared.remove(ask.kind) }
        ScratchDefaults.standard.set(false, forKey: activeKey)
        // A pour interrupted by Exit must not resume on the next launch —
        // otherwise the rows the person just removed pour straight back in,
        // and the app looks like it refused to let go.
        ScratchDefaults.standard.set(false, forKey: pendingKey)

        // The mirror of `begin`'s memory seed. `restoreDemoCheckpoint`
        // removes both the fake prior windows AND any real window recorded
        // DURING the live session (a Today-brief compose over the demo
        // corpus is real, but its facts describe a corpus that no longer
        // exists after this line) — see its own doc for why a blanket wipe
        // isn't used instead.
        BriefLedger.restoreDemoCheckpoint()
        AskMemory.forgetDemo(neglect: [neglectedAsk], made: [primedMintAsk])
        AppVisit.forgetDemo()
        TwitchIngest.forgetDemo()
        TokenPulse.shared.teardownDemo(DemoSeedAll.tokenSeeds.indices.map { "demo:token:\($0)" })
        PredictionPulse.shared.teardownDemo(
            (0..<2).map { "demo:kalshi:\($0)" } + (0..<2).map { "demo:polymarket:\($0)" })

        NSLog("[Casberi] demoMode: exited, %d rows removed", rows)
    }
}
