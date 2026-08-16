import Foundation
import SwiftData
import WidgetKit

/// The Today brief (prd §166, user: "lets build b2 with b3 synthesis card") —
/// the screen the whisper capsule opens, and a keepable ask in its own right
/// (`kind == "today"`).
///
/// **The module doctrine, ruled 2026-07-22, hardened 2026-07-25.** A count is
/// almost never the fact: people receive dozens of things a day and care WHAT
/// landed. The 2026-07-25 amendment (user: "people do not care how many things
/// landed, b/c we have dozens a day") carries that from a preference to a law —
/// **volume is not news**, so a module whose whole content is arrival volume
/// doesn't earn a caption, it gets deleted. Two did: `sourceMix` ("What landed:
/// Bluesky 6, Photos 4…") and `hourStrip` ("When it landed"), both compositions
/// of how much rather than of what. The reading RECORD went with them — "most
/// reading to land in one day this month" is a tally wearing a surprise, and in
/// a deluge it fires constantly.
///
/// So every module here is exactly one of four shapes, and none of them is a
/// tally:
///   1. a **visualization** (the money hero's treemap + line, the themes map),
///   2. the **most recent thing itself**, rendered in full (the mention that
///      names you, the read worth opening),
///   3. **what's next** (the nearest real deadline),
///   4. a **synthesis card** — the agent's own read of the day.
/// Counts survive in exactly one place, where the count IS the event: money
/// moving ("1 transaction"). Everything else names its subject. The rule isn't
/// "no numbers" — "2 more overdue" is a STATE, not an arrival, and stays; it's
/// **no numbers about how much arrived**.
///
/// Order is RANK, not arrival (amended 2026-07-23, re-ruled 2026-07-25). The
/// crown is the MONEY (user: "when a user has a wallet active the money is
/// going to always be the most important thing") — it's the one read where a
/// number is itself the event, and the one that changes while you sleep, so the
/// hero leads and the synthesis card no longer sits above it. Above the hero
/// sits one line of display type, the `DayLede` (user: "that line should be
/// above wallet") — the money said in WORDS before it's said in digits, which
/// is the one thing the approved mockup's crown had that a number alone can't:
/// magnitude in dollars, and which holding moved. Its watchlist
/// stays glued to it (2026-07-23, one story, never split). Then the THEMES map,
/// which took the slot `sourceMix`/`hourStrip` vacated and answers what the day
/// was ABOUT rather than how much of it there was. Then the agent's read, then
/// the single things. Without a watched wallet the crown falls through to
/// themes — the same screen minus a section, because money leads when it's
/// yours and it moved, not because the app prefers the subject.
///
/// **The brief remembers itself (§214, 2026-07-25).** Everything above was a
/// fresh read of the current window, which is why the screen could never say
/// *still*, *again* or *third day running*, and why re-opening at 4pm re-led
/// with the mention it had already led with at 8am. `BriefLedger` is the
/// substrate: a capped record of what each window's brief actually SHOWED —
/// written only when `presenting` is true, so the background digest refresh
/// can't make the app claim to have told you something it merely computed.
/// Three things read it: the themes map's continuity subline, the leads'
/// novelty preference, and the absence note. (A fourth — the lede's "ETH has
/// done the lifting three days running" streak — retired 2026-08-13; see
/// `walletAttribution`.)
///
/// **The lede is a ladder now, not a wallet special case.** It was
/// wallet-only, so a day the wallet didn't move opened on a number with no
/// sentence over it. The rungs are ranked by what can still cost you
/// something: a liquidation risk, then the money's move, then someone
/// addressing you, then a deadline landing today. Nothing is ever padded — a
/// rung with no fact yields to the next, and an empty ladder emits no lede.
/// When risk takes the lede the money's attribution isn't lost, it falls back
/// to a synthesis note (where it lived before 2026-07-25).
///
/// **The observations cross sources.** Every original note read a single
/// field — a reply count, a word frequency, a percentage — which is a read
/// any single-source app could make. The families added in §214 are joins
/// only this corpus can do: a symbol that moved today which is also what
/// you've been reading, one person appearing in several sources at once, and
/// a habitual source that went quiet. Absence is the one genuinely new KIND
/// of fact — it's a state change rather than a tally, so it survives §213's
/// volume ruling, and it can't be manufactured because a day when nothing
/// landed at all is excluded.
///
/// Deterministic throughout (docs/agent-brief.md ruling 1) — every line is
/// template-composed from facts already held. No model, ever, on this path.
@MainActor
enum TodayBrief {

    /// The words that name this ask. ONE definition, read by the typed answer
    /// path (`RootShell.answerDocument`), the keepable-kind recognizer
    /// (`Composer`), and the whisper's own tap — so a question that answers
    /// can always also be kept, and none of the three can drift.
    static func matches(_ query: String) -> Bool {
        let q = query.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .trimmingCharacters(in: CharacterSet(charactersIn: "? "))
        // "What's going on" ABSORBED the feeds' prose pulse (§193, user ruling
        // 2026-07-23) — this screen is the richer answer to the same question,
        // so the phrase routes here and `StatusAsk`'s own pulse branch (which
        // sits below this one in `answerDocument`) no longer sees it. Exact
        // matches only, so "what's going on with sam" stays a real search.
        return q == "today" || q == "my day" || q == "how's my day" || q == "hows my day"
            || q == "what's my day" || q == "whats my day"
            || q == "what's going on" || q == "whats going on"
            || q.contains("brief me") || q.contains("my day so far")
            || q.contains("catch me up on today")
    }

    /// The same question asked of ONE scope — "How's my Money stuff?", "what's
    /// going on with my work stuff" (2026-08-10).
    ///
    /// Separate from `matches` on purpose: that one ROUTES an unscoped ask to
    /// this composer, and widening it would send a scoped ask down the
    /// unscoped path. This one only answers "is what's on screen a brief",
    /// which is what the scroll anchor needs — and getting that wrong is
    /// exactly the reported bug: `briefInView` was false for every scoped
    /// brief, so `.defaultScrollAnchor` took its `.bottom` branch and a
    /// composed document with a masthead opened at its own footer, the same
    /// complaint §288 already fixed once for the unscoped brief.
    ///
    /// Both halves are required — a scope NAME and a brief-shaped QUESTION —
    /// so an ordinary search that happens to say "money" ("money transfer
    /// receipt") is not mistaken for a brief and yanked to the top.
    static func matchesScoped(_ query: String) -> Bool {
        let q = query.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .trimmingCharacters(in: CharacterSet(charactersIn: "? "))
        let asksHow = q.hasPrefix("how's my") || q.hasPrefix("hows my")
            || q.hasPrefix("how is my") || q.contains("what's going on")
            || q.contains("whats going on")
        guard asksHow else { return false }
        return BriefScope.scopes.contains { q.contains($0.lowercased()) }
    }

    /// A brief of ANY kind is on screen — the whole day or one scope.
    static func matchesAny(_ query: String) -> Bool {
        matches(query) || matchesScoped(query)
    }

    /// The canonical question — what the whisper sends, and the title a kept
    /// pill wears. Matches the screen's own name (§193) so the pill, the
    /// capsule, and the masthead all say one thing.
    static let title = String(localized: "What's going on?")

    // MARK: - Compose

    /// `presenting` is what separates a brief a person SAW from one the app
    /// merely computed: `KeptAskStore.refreshDigests` composes every kept kind
    /// in the background on each foreground, and recording those would let the
    /// ledger claim it had already told you things it never drew. Defaults to
    /// false so a new caller is silent by construction; the three display
    /// routes (the typed ask, the kept pill's tap, the whisper's tap — all
    /// three funnel through `RootShell.answerDocument`) pass true.
    ///
    /// `category` scopes the brief to one app-catalog category (`BridgeCatalog
    /// .categories`' own names — "Work", "Social", …) — nil is the unscoped,
    /// whole-corpus brief this function has always composed (spec: scoped-
    /// brief-spec.md, "one pipeline, two parameters, not a new feature").
    /// Everything downstream of the Stage-1 filter below — the lede's mention/
    /// deadline rungs, the themes map, the leads, the synthesis notes — reads
    /// `things`/`landed`, so filtering those two arrays ONCE, here, scopes the
    /// whole pipeline for free; only the money modules read live bridge state
    /// INSTEAD of `things` (holdings, watchlist moves, DeFi risk, resolved
    /// markets), so those are separately gated below on the SCOPE actually
    /// being Money/unscoped.
    ///
    /// `category` here is a BRIEF SCOPE (`BriefScope.scopes` — "Money",
    /// "Work", "Life"), NOT one of the app catalog's own ten categories
    /// (`BridgeCatalog.categories`, unchanged everywhere else). The two
    /// taxonomies are deliberately different sizes: `BriefScope.scope(
    /// forCatalogCategory:)` is the one join between them.
    ///
    /// Stage 2 of the spec ("item filtering… only items relevant to the
    /// requested category") collapses into Stage 1 here: every catalog offer
    /// carries exactly ONE category (`BridgeCatalog.category(of:)` returns a
    /// single name), so there is no source in this catalog today whose things
    /// legitimately split across categories the way the spec's email example
    /// does. A `Thing` is scoped by its `source`'s one category, full stop —
    /// if a future bridge genuinely needs per-item relevance (a unified inbox
    /// spanning Work and Social), that's a new signal to filter on, not
    /// something to fake here with `things` alone.
    /// `onPartial` makes the brief PROGRESSIVE (2026-08-12).
    ///
    /// The document composes atomically — nothing paints until every live read
    /// has returned or given up — so `liveReadBudget` was, structurally, the
    /// chip's latency. That is what made the Money/Work/Life chips feel slow:
    /// measured on a 12,000-row corpus, the whole corpus half of the brief is
    /// ready in ~250ms and then sits there while ONE read (`worstDebt`, at
    /// 1.3–2.6s) finishes deciding whether the lede gets a risk rung.
    ///
    /// So the corpus half is emitted first, through this callback, and the
    /// complete document replaces it when the reads land. `GenStream.paint`
    /// swaps a whole document, so the second call simply supersedes the first.
    ///
    /// It is composed by calling THIS function again with `skipLiveReads`,
    /// rather than by extracting the module block: two passes through one
    /// composer cannot drift, and a partial assembled by a second, reduced
    /// copy of the module chain is exactly the drift this file's own
    /// "one composer per kind" rule exists to prevent. The second pass costs
    /// one more walk of the corpus modules (~180ms measured) and overlaps the
    /// live reads, which are already in flight by the time it runs.
    ///
    /// The inner pass takes `presenting: false`, which is load-bearing three
    /// times over: it skips the model read (the partial must be fast), it
    /// skips `BriefLedger.record` and `BriefScope.markViewed` (a brief must
    /// not record having told you something twice), and it passes no
    /// `onPartial`, so the recursion is exactly one level deep.
    static func compose(things: [Thing], context: ModelContext,
                        presenting: Bool = false, category: String? = nil,
                        skipLiveReads: Bool = false,
                        onPartial: (([String]) -> Void)? = nil) async -> KeptAskComposers.Result? {
        #if DEBUG
        let composeT0 = Date.now
        defer { NSLog("[Casberi] composeTimingDEBUG| category=%@ TOTAL=%dms",
                      category ?? "nil", Int(Date.now.timeIntervalSince(composeT0) * 1000)) }
        #endif
        // THE DEMO REACHES NOTHING — folded in HERE, at the one place the three
        // live reads below are gated, rather than as a third condition on each
        // of them, so a read added later inherits the rule for free.
        //
        // `BridgeRefresh.refreshAllConnected` has returned instantly under
        // `DemoMode.isActive` since the furnished demo shipped, but this
        // composer is a SECOND door onto the same network: `RootShell` composes
        // the brief on every foreground, and `liveHoldings` / `worstDebt` walk
        // the chain RPCs and Morpho directly, bypassing the sweep entirely.
        // Measured 2026-08-13 by verify.sh's own reach check: a demo session
        // made 61 requests to six hosts (rpc.mevblocker.io, mainnet.base.org,
        // mainnet.optimism.io, arb1.arbitrum.io, polygon.api.onfinality.io,
        // blue-api.morpho.org).
        //
        // Not merely a privacy-copy violation. The demo's wallet address is
        // SEEDED and fake, so a real read answers with nothing and writes a
        // zero value sample over the seeded curve — the balance-fell-off-a-
        // cliff failure the demo's own doc calls out. Skipping the reads is
        // also the honest result here: every module they feed is seeded.
        let skipLiveReads = skipLiveReads || DemoMode.isActive
        // Filtered on ENTRY as well as after the awaits below (crash fix,
        // build 250). The caller's array can ALREADY be stale: `RootShell`
        // fetches it, then awaits `KeptAskStore.refreshDigests` before handing
        // it here — a suspension of its own, in which a heal can delete. So
        // `DayBrief.landed` on the next line would read a tombstoned model
        // before this function ever suspends.
        // Per-module timing (DEBUG only, 2026-08-12). "The Life brief is slow"
        // is not answerable from the total: this composes a dozen independent
        // modules over the scope's rows, they differ by orders of magnitude,
        // and which one dominates depends entirely on WHICH scope — Life spans
        // 44 sources where Work spans 27. A total says panic; this says where.
        #if DEBUG
        var moduleMarks: [(String, Double)] = []
        var lastMark = Date.now
        #endif
        func mark(_ name: String) {
            #if DEBUG
            let t = Date.now
            moduleMarks.append((name, t.timeIntervalSince(lastMark) * 1000))
            lastMark = t
            #endif
        }
        var things = things.live
        mark("entry.live")
        let now = Date.now

        // Stage 1 (deterministic app selection, spec's own term): the
        // scope's candidate sources are every catalog offer whose category
        // maps to it (`BriefScope.scope(forCatalogCategory:)`) — "connected"
        // needs no separate check, since a source with no connected bridge
        // can never have landed a `Thing` in the first place.
        if let category {
            // One definition of what a scope covers, shared with the kept
            // pill's own pool and with the SCOPED FETCH that feeds this
            // (`RootShell.categoryCorpus`) — see `categorySources`.
            let candidateSources = KeptAskComposers.categorySources(category)
            // A scope with literally nothing ever landed from it is not
            // "quiet since you last checked", it's not connected at all — the
            // spec's own edge case, distinct from "connected but nothing new"
            // below. Checked against the WHOLE corpus, before any window.
            guard things.contains(where: { candidateSources.contains($0.source) }) else {
                let line = String(localized: "No apps connected in \(category) yet — add one from Apps.")
                return KeptAskComposers.Result(
                    delta: "", digest: String(localized: "unconnected"),
                    doc: ["root = Stack([ins])", "ins = Insight(\"\(genSafe(line))\")"])
            }
            things = things.filter { candidateSources.contains($0.source) }
            mark("stage1.scope")
        }
        // The money modules below read LIVE bridge state instead of `things`
        // (holdings, watchlist prices, DeFi risk, resolved markets), so the
        // Stage-1 filter above can't scope them — gated explicitly. ONE gate
        // now (was two: Wallet, Markets) — those merged into a single "Money"
        // scope (user, 2026-08-08), so a wallet balance and a watchlist mover
        // answer the same question again.
        let scopedToMoney = category == nil || category == "Money"

        // The window boundary: the whole day's away-window/midnight boundary
        // for the unscoped brief (UNCHANGED — spec: "the scheduled daily
        // brief keeps its current window"), or this category's own "since I
        // last checked" moment for a scoped ask.
        let windowStart = category.map { BriefScope.since(category: $0, now: now) }
            ?? DayBrief.windowStart(now: now)
        var landed = DayBrief.landed(things, now: now, since: windowStart)
        mark("landed")
        // A scoped Money brief measures the move against ITS OWN window
        // (`windowStart` is `BriefScope.since(category: "Money")` there),
        // not the unscoped brief's fixed ~20h floor — the item list below
        // already spans the real gap since you last checked, and the hero's
        // delta must span the same one or the two disagree on screen.
        let move = scopedToMoney
            ? DayBrief.walletMove(now: now, since: category != nil ? windowStart : nil)
            : nil
        // The ledger is read ONCE here and threaded through every module that
        // asks it something (the `ChipMemory.snapshot()` discipline) — five
        // separate reads would decode the same JSON five times per rise.
        let ledger = BriefLedger.snapshot()
        let told = BriefLedger.told(ledger, windowStart: windowStart, now: now)
        let weights = ChipMemory.snapshot()
        mark("ledger")

        // The three live reads run CONCURRENTLY (2026-07-25). They were
        // sequential, so each new read added its full latency to the rise;
        // `async let` makes the brief pay the slowest rather than the sum,
        // which is what left room for the risk read the lede's top rung needs.
        //
        // …and each is now BOUNDED (2026-08-03, user: "Brief takes too long to
        // load"). Paying the slowest instead of the sum only helps when the
        // slowest is fast: the whole document composes atomically, so nothing
        // paints until all three return, and none of them had a ceiling. One
        // unreachable RPC host owned the screen for minutes. See
        // `liveReadBudget` — the block now costs at most that, and a read that
        // misses it simply doesn't contribute its module.
        // Gated on `presenting` for the same reason `worstDebt` below is
        // (2026-08-04): holdings reach exactly ONE module, the money hero, and
        // on the background path the entire document is discarded — the caller
        // (`KeptAskStore.refreshDigests`) keeps only `.digest`, which is
        // `DayBrief.detail` → `whisper` → `walletMove`, all recorded samples
        // and none of them this read. So every foreground was paying a network
        // portfolio read (measured at 6.8s) to build a hero nobody would ever
        // see. The lede doesn't touch holdings either, so the widget line it
        // publishes is unaffected.
        async let holdingsRead = (!skipLiveReads && presenting && scopedToMoney) ? liveHoldings() : []
        async let movesRead = (!skipLiveReads && scopedToMoney) ? liveMoves(context: context) : []
        // Gated on `presenting` (2026-07-25): the risk rung only ever reaches
        // the LEDE, and the digest — the one thing the background path uses —
        // is `DayBrief.detail`, which never carries it. So on the digest
        // refresh this read's result is discarded, and it is the single
        // most expensive thing here: `WalletDeFi.positions` walks its pools
        // and addresses SEQUENTIALLY, so a cold 60s cache costs several
        // round-trips. `KeptAskStore.refreshDigests` runs on every foreground
        // and every composer open for anyone who has kept this ask — paying
        // chain latency there to compute a sentence nobody is looking at is
        // work with no reader. The cost of the gate: `-todayProbe` composes
        // with `presenting: false`, so it can't show the risk rung.
        async let riskRead = (!skipLiveReads && presenting && scopedToMoney) ? worstDebt() : nil
        // The corpus half, painted NOW — see `onPartial`. Placed after the
        // three `async let`s on purpose: those tasks are already in flight, so
        // this pass overlaps them rather than delaying them.
        if let onPartial, presenting, !skipLiveReads {
            if let draft = await compose(things: things, context: context,
                                         presenting: false, category: category,
                                         skipLiveReads: true) {
                onPartial(draft.doc)
            }
        }
        // Where an open's wait actually goes, per read (2026-08-04). DEBUG-only
        // and free in release, the same bargain `LaunchPerf`'s span markers
        // make — kept rather than deleted because "the brief feels slow" is a
        // recurring report and the answer is never guessable: the reads run
        // concurrently, so the total is the slowest one, and only a per-read
        // breakdown says WHICH. It's what turned this round from a guess into
        // a one-line fix (holdings 7598ms, moves 0, risk 0).
        let t0 = Date.now
        let holdings = await holdingsRead
        let tH = Date.now.timeIntervalSince(t0)
        let moves = await movesRead
        let tM = Date.now.timeIntervalSince(t0)
        let risk = await riskRead
        let tR = Date.now.timeIntervalSince(t0)
        #if DEBUG
        NSLog("briefPerf| presenting=%@ holdings=%.0fms moves=%.0fms risk=%.0fms TOTAL=%.0fms",
              String(presenting), tH * 1000, (tM - tH) * 1000, (tR - tM) * 1000, tR * 1000)
        #endif

        // CRASH FIX (build 250, 2026-08-03) — the "never read a dead Thing"
        // class, reached from ASYNC MODEL CODE rather than a view, where none
        // of the view-side guards (keying, the leaf-body check, the boundary
        // filter) can help.
        //
        // `things` and `landed` were captured BEFORE the three live reads
        // above, and those reads suspend for up to `liveReadBudget` (5s; it
        // was 8s when this crash was diagnosed — the exact number moves the
        // race's width, never its existence, which is why the re-filter below
        // is the fix and the budget is not). The
        // app's own foreground bridge sweep runs heals that DELETE Things in
        // exactly that window, so on resume this array can hold tombstoned
        // models — and every module below (`ledeLine`, `moneyHero`, `nextTile`,
        // `flowBand`, `themesMap`, `observations`, `DayBrief.detail`) reads
        // stored properties off them. Build 250 trapped in `moneyHero`, on
        // `$0.kind == .transaction`, five times in ninety minutes.
        //
        // It surfaced now because RootShell started composing this
        // UNCONDITIONALLY on every foreground (2026-08-03, to keep the widget
        // fresh) — before that it only ran for someone who had KEPT the
        // "today" ask, which most people never do, so the path was rare.
        //
        // Re-filtering here covers every module down to the model read. It was
        // documented as covering the whole remainder — "there is no further
        // `await` in `compose`, so the whole remainder runs with exclusive
        // main-actor access" — and that was WRONG from the day `dayRead`
        // landed (2026-08-07): `OnDeviceModel.dayRead` is awaited below and is
        // deliberately NOT `@MainActor`, precisely so the main actor is
        // genuinely yielded while the model runs. It is a ~2.1s suspension,
        // i.e. a race far wider than the one that produced build 250, and
        // `BriefLedger.record`'s `landed.map(\.source)` plus `DayBrief.detail`
        // both read stored properties after it. There is a SECOND re-filter
        // after that await for exactly this reason (2026-08-14).
        //
        // Standing rule for this file: every `await` added to `compose` needs
        // its own re-filter after it. The guarantee is per-suspension, not
        // per-function, and a comment asserting otherwise is how this one
        // survived a year.
        things = things.live
        landed = landed.live
        mark("postAwait.live")


        var ids: [String] = []
        var lines: [String] = []

        // The alerts are computed FIRST and rendered second (2026-08-13). The
        // lede's deadline rung has to know which deadlines the callout below
        // already took, or the most urgent item in the scope is the sentence
        // AND the first alert row — the leads-vs-observations rule, one module
        // earlier than it used to reach. Nothing about the render order moved:
        // `ids` still takes `lede` before `alerts`, immediately below.
        let alerts = alertsCard(things, now: now, category: category)
        // The section header carries the count the card's eyebrow used to
        // (prd §386g) — the one place a count IS the reading here: how many
        // things want you. No other section gets one; "Money · 4" would be
        // counting cards, which is the tally §213 bans.
        var sectionQualifiers: [String: String] = [:]
        if let alerts, alerts.count > 1 {
            // A READING, not a tally (prd §386l): "2 late" says something the
            // rows cannot say together, where "5" only counts the rows you
            // are already looking at. Silent when nothing is late — then the
            // count really would be a tally.
            let late = things.filter {
                $0.mark != .done && ($0.dueAt ?? .distantFuture) < now
            }.count
            if late > 0 {
                sectionQualifiers["Needs you"] = late == 1
                    ? String(localized: "1 late")
                    : String(localized: "\(late) late")
            }
        }

        // 1. The lede — the day in ONE sentence, in display type, above
        // everything (user, 2026-07-25: "that line should be above wallet").
        // A ranked ladder since §214: risk, then money, then a person, then a
        // deadline. Nothing is padded to fill the slot — an empty ladder emits
        // no lede and the brief opens on the hero instead.
        let lede = ledeLine(move: move, risk: risk, landed: landed, things: things,
                            now: now, alerted: alerts?.ids ?? [])
        // THE MONUMENT (2026-08-16, mockup C, user: "ok do c") — the day's one
        // figure at display scale, with the sentence demoted to its support
        // line. Chosen by the CLOCK, §386d's own permutation rule reaching the
        // lede: neither Apple's Weather nor Cash App leads with a sentence in
        // a box, but Cash App gets to assume money is always the subject and
        // this corpus cannot — a morning with three late things leads with the
        // THREE, an evening with a real wallet move leads with the MOVE, and a
        // day that is neither leads with what arrived. Empty on a day with
        // nothing to say, and then the sentence stands alone (never a padded
        // figure — the ladder's own no-padding rule).
        let monumentHour = Calendar.current.component(.hour, from: now)
        let monumentLate = things.filter {
            $0.mark != .done && ($0.dueAt ?? .distantFuture) < now
        }.count
        var monument: (figure: String, word: String, tone: String) = ("", "", "")
        if category == nil {
            if monumentHour < 12, monumentLate > 0 {
                monument = ("\(monumentLate)",
                            monumentLate == 1 ? String(localized: "needs you")
                                              : String(localized: "need you"),
                            "attention")
            } else if let move, abs(move.pct) >= 0.05 {
                monument = (String(format: "%+.1f%%", move.pct),
                            String(localized: "today"),
                            move.pct >= 0 ? "up" : "down")
            } else if !landed.isEmpty {
                monument = ("\(landed.count)",
                            monumentHour < 12 ? String(localized: "overnight")
                                              : String(localized: "new things"),
                            "plain")
            } else if let people = dayPeopleCount(things, now: now), people > 0 {
                // A QUIET WINDOW IS NOT AN EMPTY DAY (2026-08-16, from a
                // device shot: a Sunday-morning open showed no monument at
                // all, on a corpus whose own fold card was saying "950 more ·
                // 176 people"). The three rungs above all measure what
                // arrived SINCE YOU LOOKED, which on a second open of the
                // morning is legitimately nothing — and the screen then led
                // with a blank where its largest element should be.
                //
                // This rung measures the DAY rather than the window, so it
                // can still speak when the window can't. It is not padding:
                // the figure is a real count of distinct people in the day's
                // things, the same set the fold card draws faces from. Nil
                // when there are none, and then the sentence stands alone —
                // the ladder's no-padding rule survives at the bottom.
                monument = ("\(people)", String(localized: "people"), "plain")
            }
        }
        if !lede.text.isEmpty {
            ids.append("lede")
            mark("lede")
            lines.append("lede = DayLede(\"\(genSafe(lede.text))\", \"\(genSafe(dateline(now: now)))\", \"\(genSafe(lede.figure))\", \"\(lede.direction)\", \"\(genSafe(monument.figure))\", \"\(genSafe(monument.word))\", \"\(monument.tone)\")")
        }
        // The home/Lock Screen widget carries this SAME sentence (2026-07-25).
        // Published here rather than at a display route so it refreshes on
        // every foreground — `KeptAskStore.refreshDigests` composes the brief
        // for anyone who has kept this ask, and the widget should not have to
        // wait for someone to actually open the brief to stop being stale.
        // Publishing is NOT recording: the ledger's `presenting` discipline is
        // about claiming "I already told you this", and a widget line is the
        // telling, not a claim about it.
        //
        // SKIPPED for a scoped brief (`category != nil`): the widget's whole
        // promise is the DAY'S lede/themes, and a "What's going on with Work?"
        // ask overwriting that with a Work-only sentence would make the
        // Lock Screen lie about the rest of the corpus the next time it's
        // glanced at, unrelated to whether anyone actually opened the widget.
        //
        // AND skipped for the draft pass (`skipLiveReads`, 2026-08-14). That
        // pass exists to paint the corpus half instantly and composes its lede
        // WITHOUT the risk rung and without live holdings — so leaving it
        // ungated published a knowingly-incomplete sentence to the Home
        // Screen and then overwrote it a few seconds later. Two real writes,
        // because the values genuinely differ, which is two `reloadTimelines`
        // out of a budget the system meters; and for the window between them
        // the most-glanced surface in the OS carried the lesser of two ledes
        // we already knew how to compute. The background/digest compose is
        // untouched — it does not set `skipLiveReads`, so the widget still
        // refreshes without anyone opening the brief.
        //
        // SECOND CONSEQUENCE, intended and worth naming: `skipLiveReads` is
        // force-ORed with `DemoMode.isActive`, so the demo no longer publishes
        // its lede to the Home Screen either. That is the §217 demo doctrine
        // already applied everywhere else — `BridgeRefresh` returns instantly
        // and `Notifications.submit` returns `[]` under demo, so that a fake
        // £240 dispute can never reach a real surface — and a widget is the
        // most public surface the OS has. Previously a demo lede was published
        // and, since `DemoMode.exit` unwinds by NAME, nothing was named to
        // take it back down again.
        if category == nil, !skipLiveReads {
            publishLedeToWidget(lede.text)
            publishThemesToWidget(things: things, now: now)
        }

        // 1b. What NEEDS YOU (2026-08-10) — above the crown, and the only
        // module ranked purely by urgency rather than by what the scope is
        // "about". It sits under the lede rather than over it because the lede
        // is one sentence naming the day and this is the list you act on: the
        // sentence frames, the callout demands. Everything below reports.
        //
        // Reads the WHOLE scope, not `landed` — an alert does not stop being
        // an alert because it arrived before the window opened. That is the
        // deliberate divergence from every other module here, all of which are
        // "what's new"; a dispute opened on Monday is still what needs you on
        // Thursday, and scoping this to the window would hide exactly the
        // alerts that have been waiting longest.
        if let alerts {
            ids.append("alerts")
            mark("alerts")
            lines.append(alerts.line)
        }

        // 1b. THE NOTICE (2026-08-14, prd §386d) — the agent's own daily
        // observation, on the page rather than only behind a chip beside it.
        // `AgentNoticed` is ≤1/day, deterministic and shown-once-ever, so it
        // cannot become furniture; on the ~most days it has nothing, this
        // composes nothing. Drawn as an `Insight` carrying its first evidence
        // id, so the claim opens the thing it stands on — the glint's payoff
        // without having to pick the right chip for it.
        //
        // Below the alerts and above the money: what NEEDS you outranks what
        // is merely interesting, and both outrank a number that did not move.
        // Unscoped only — a scoped brief asks a narrower question than "did
        // anything interesting happen today".
        // THE NOTICE IS RETIRED FROM THE BRIEF (2026-08-15, prd §386g, user:
        // "'noticed' seems weak. can we actually provide value there? i don't
        // think so. i'd rather try to use on device intelligence to visualise
        // things"). It was a SENTENCE — the form this whole pass has been
        // cutting — that fired on a minority of days and, when it did, said
        // something the cluster map now SHOWS ("Farcaster and Obsidian are
        // both on Onchain today" is a claim; two hulls overlapping is the
        // evidence). `AgentNoticed` stays compiled and still answers its own
        // typed ask, so nothing is unreachable; it simply no longer takes a
        // slot on the day's one screen.

        // 2. The money hero — the CROWN (2026-07-25), the day's one fused
        // visualization and the only read where a number is itself the event.
        if let hero = moneyHero(move: move, holdings: holdings, landed: landed) {
            ids.append("hero")
            mark("hero")
            lines.append(hero)
        }

        // 3. The pair: what's moving, what's next. Stays glued to the hero
        // above it (user ruling 2026-07-23: "keep wallet and watchlist
        // together") — the watchlist IS money, so putting anything between it
        // and the wallet splits one story across two places.
        //
        // The RUNWAY (user, 2026-08-08: "Work is the only room organized by
        // deadlines") supersedes the single `nextTile` once there are enough
        // deadlines to show a real spread — composed FIRST so the pair below
        // can skip `nextTile` rather than repeat its own top item a second
        // time (the leads-vs-observations precedent above: never the same
        // fact told twice). Below the ≥2 floor, `nextTile` alone is the
        // honest degrade — one deadline is a fact, not a runway.
        let runway = runwayCard(things, excluding: alerts?.ids ?? [],
                                statedOverdue: lede.statedDeadlines,
                                titled: category != nil)
        var tiles: [String] = []
        if let movers = moversTile(moves) {
            tiles.append("tmov")
            lines.append(movers)
        }
        if runway == nil, let next = nextTile(things, excluding: alerts?.ids ?? []) {
            tiles.append("tnext")
            lines.append(next)
        }
        if !tiles.isEmpty {
            ids.append("pair")
            mark("pair")
            lines.append("pair = TilePair([\(tiles.joined(separator: ", "))])")
        }
        if let runway {
            // Two ids, one module: the axis and its rows are separate elements
            // so the axis can be a `Runway` and the rows a `Widget`, but they
            // are one reading and neither opens a chapter of its own.
            ids.append("axis")
            mark("axis")
            ids.append("runway")
            mark("runway")
            lines += runway
        }
        // A watched market that resolved — an EVENT, so it follows the pair
        // rather than joining it (a tile pair is state at a glance; this is
        // news). Silent on every day nothing settled, like every module here.
        if scopedToMoney, let resolved = marketResolvedToday(MarketsAsk.moves(context: context), now: now) {
            ids.append("tmkt")
            mark("tmkt")
            lines.append(resolved)
        }
        // Where the money MOVED — the flow band (§232), closing the money
        // block. Everything the crown says above is money as STATE (the total,
        // its delta, the holdings treemap, the balance curve — all "what you
        // have"); this is the only read that says through WHOM it left and
        // arrived. The room already draws it and its own header calls money
        // moving "the module doctrine's standing exception to never a tally",
        // so it arrives here already ruled — it just had no way to be called,
        // being a per-room view rather than a composer.
        if let flow = flowBand(things) {
            ids.append("flow")
            mark("flow")
            lines.append(flow)
        }

        // 4. The themes map — the second whole-day summary, and the one that
        // replaced "what landed" and "when it landed" outright (2026-07-25,
        // user: the themes treemap "is more important than 'what landed' and
        // when"). Same slot, same geometry; a different question — what today
        // was ABOUT, which survives a deluge, where a source tally doesn't.
        // THE TREEMAP IS RETIRED (2026-08-15, prd §386g, user: "agree then
        // lets kill treemap"). The semantic cluster map answers the same
        // question — what your things are ABOUT — with the thing a treemap
        // structurally cannot carry: adjacency. A treemap's area is a count
        // and its boxes are unordered, so two themes sitting side by side
        // means nothing; the map's positions come from the embeddings, so
        // clusters that sit together really are about similar things. Two
        // figures answering one question was the duplication §386e was
        // reported for, and this is the same call made deliberately.
        //
        // `themesMap` still composes for the LEDGER (§214's theme continuity
        // and absence reads are built on `themeNames`), it just no longer
        // draws — the one place the map's clustering is still the right tool.
        var themeNames: [String] = []
        if let themes = themesMap(things: things, now: now, ledger: ledger, windowStart: windowStart) {
            themeNames = themes.names
        }

        // 4b. The contact sheet (2026-08-10, user: "on life, the treemap alone
        // is insufficient") — directly under the themes map, and the pairing is
        // the argument for it: the treemap says what your things were ABOUT in
        // words you may not have chosen, and the sheet shows the things. One
        // abstracts, one shows; the treemap alone left Life as a diagram.
        //
        // Composed over `things` rather than `landed` — a window's worth of
        // pictures is usually a handful and often none, and this is a "what
        // your life looks like" module rather than a "what arrived" one. The
        // ≥6 floor keeps it silent where that isn't true.
        // NOT in Money (2026-08-10, user: "on 'what's going on with my money
        // stuff' it shows 'what you saw', which goes in life and work not
        // money"). Money's own reading is the crown and the flow band — what
        // you HAVE and where it MOVED, both of them numbers — and a wall of
        // photographs above them answers a question nobody asked of that
        // scope. It reached Money at all because this shipped ungated: the
        // ≥6-picture floor was doing the scoping by accident, and a corpus
        // with enough screenshots filed under a money source cleared it.
        // 4b. WHAT TODAY WAS MADE OF, as ONE card (2026-08-15, prd §386g,
        // user: "i love the idea of the fold what today was made of into one
        // card"). `contactSheet` + `faces` + `sourceMixLine` were three
        // stacked cards answering one question from three angles — the
        // pictures, the people, the rooms — and they cost three of the
        // brief's slots to say "here is what your day was". `DayFold` says it
        // once: pictures lead (they ARE the day rather than an abstraction of
        // it — `WidgetDayLead`'s own ladder makes the same call), people and
        // rooms share the line beneath, and the subline carries every
        // remainder so nothing is silently dropped.
        //
        // NOT in Money (§386's own ruling, kept): a wall of photographs above
        // a balance answers a question nobody asked of that scope.
        // 2b. THE BALANCE LINE, when the hero could not compose (2026-08-15,
        // prd §386h, user: "you can't just show the sankey we still need the
        // sparkline and perhaps even the treemap of holdings").
        //
        // `moneyHero` requires non-empty HOLDINGS, and holdings are a LIVE
        // read — so the entire balance block (number, curve and holdings
        // treemap) disappears whenever that read is empty or times out,
        // leaving Money as a sankey and a spend bar with nothing saying what
        // you actually have. That is not a rare state: §288 bounds the read
        // at 8s and says outright that a read which misses the budget
        // "contributes no module", and the demo corpus reaches nothing at all
        // by design.
        //
        // The fallback is the RECORDED sample history — the same series the
        // panel's own wallet curve draws, written by `recordSample` on every
        // foreground rather than fetched now. It states its own window
        // ("since Aug 3"), so it never claims a stale number is current, and
        // it is exactly the shape the hero would have drawn had the read
        // landed. Never BOTH: the hero already carries a curve.
        if scopedToMoney, !ids.contains("hero"),
           let spark = KeptAskComposers.valueSparkLine() {
            ids.append("spark")
            mark("spark")
            lines.append(spark)
            // …and WHAT IT IS MADE OF, from the same recorded history.
            // `ValueSample.holdings` snapshots symbol → USD at each sample,
            // so the newest one draws the composition treemap the hero would
            // have drawn — off history rather than off a live read, which is
            // the whole point of this fallback. Nil on samples written before
            // that field existed, and then the map simply doesn't draw.
            if let holdings = holdingsMapFromHistory() {
                ids.append("holdmap")
                mark("holdmap")
                lines.append(holdings)
            }
        }

        // 4a. WHERE YOU SPEND, in the Money section (prd §386g) — the panel
        // card moved INTO the brief. It answers what no other money module
        // does: the hero is how much you hold and the flow is which rails it
        // moved on; only this names a merchant. Emitted as `Bars` rather than
        // as a docked panel tile so the whole money story renders through one
        // system, in one place, under one header.
        if scopedToMoney, let spend = spendBars(things) {
            ids.append("spend")
            mark("spend")
            lines.append(spend)
        }

        // 4a-ii. WORK — the section's first real member (prd §386g, user:
        // "work section isn't only posthog, it would be github for example
        // which we need to account for"). PostHog's busiest watched metric
        // leads because it is the one work figure that is a CURVE; GitHub's
        // contribution calendar and the deploy/incident rooms are the next
        // members and are not wired yet (stated in §386g rather than left to
        // look like an oversight).
        if category == nil, let work = workCurve() {
            ids.append("work")
            mark("work")
            lines.append(work)
        }
        // GitHub's contribution calendar — built since the Home board and
        // reachable only from its own feed room until now (prd §386j, user:
        // "work section isn't only posthog, it would be github for example").
        // The store fetches on its own schedule and caches; this reads what
        // is already there and never triggers a fetch, so a brief costs
        // nothing for a room it merely mentions.
        if category == nil, let gh = githubCalendar() {
            ids.append("ghgraph")
            mark("ghgraph")
            lines.append(gh)
        }
        // The rest of Work (prd §386m) — the deadlines the shipping rooms
        // carry. `Runway` is the same axis "Coming up" draws, which is the
        // point: a cert expiry and a dispute deadline are the same KIND of
        // fact as a reminder, they just belong to a different part of the
        // day. Both composers already exist for the panel and read landed
        // rows alone, so this costs no request.
        if category == nil, let ship = shippingRunway(things) {
            ids.append("ship")
            mark("ship")
            lines.append(ship)
        }

        // WHAT GOES TOGETHER (prd §386j) — the semantic map, finally a module
        // under its own header rather than a card docked below the document.
        // Composed off the main actor (`AgentPanelFigures.scatter` is
        // Foundation-only over value types), and it reads the embeddings that
        // are already on disk — no model call, so §386a's "the brief no
        // longer awaits a model" holds.
        // NOT on the partial pass (prd §386k, measured same-day: the PCA cost
        // ~1,800ms and the partial exists to be FAST — running it there made
        // the "instant" corpus half slower than the §288 live-read budget it
        // was built to hide). The final compose draws it; the partial simply
        // paints without the map for the second it takes to arrive.
        if category == nil, !skipLiveReads, let map = await clusterMap(context: context) {
            ids.append("map")
            mark("map")
            lines.append(map)
        }

        if category != "Money", let fold = dayFold(things: things, landed: landed) {
            ids.append("fold")
            mark("fold")
            lines.append(fold)
            // The section says what the day HELD; the card shows it. One
            // reading the pictures and faces cannot state together.
            if !landed.isEmpty {
                sectionQualifiers["Your day"] = landed.count == 1
                    ? String(localized: "1 new")
                    : String(localized: "\(landed.count) new")
            }
        }

        if let posts = yourPostsCard(things, windowStart: windowStart) {
            ids.append("posts")
            mark("posts")
            lines.append(contentsOf: posts)
        }

        // 5 and 6 COMPOSE in the other order than they render (2026-07-31).
        // The leads are the screen's richest statement of a single thing — the
        // post in full, the read with its image and its tap — so an
        // observation that would name the same thing above them is the same
        // fact told twice, worse first (user: "then below it will be another
        // card with that specific item in it"). Composing the leads first lets
        // `observations` see what's already being said and drop its own copy.
        // The render order is unchanged: `ids` still appends notes, then leads.
        // WHAT THE LEADS READ (2026-08-13). Normally the window — a lead is
        // "here is a thing that just arrived, in full". But a SCOPED brief's
        // window is "since you last checked", so re-opening Money twenty
        // minutes later gives it nothing at all, and the scope collapses to
        // charts with not one thing you can open or read. Seen on the sim:
        // Money, Work and Life each ended on an aggregate, every time.
        //
        // So when a scope's window is genuinely empty, the leads fall back to
        // the scope's newest things regardless of age — the bulk-import
        // ARCHIVE-RECAP precedent (§307): a room whose window can be
        // structurally empty is owed its contents rather than a blank. Nothing
        // claims these are new — every lead row carries its own timestamp, and
        // `shortTime` prints a DATE past a week rather than "412d" — and the
        // unscoped brief is untouched, since its window is the day itself and
        // an empty day should read as an empty day.
        let leadPool = (category != nil && landed.isEmpty) ? Array(things.prefix(24)) : landed
        var leadIDs: [String] = []
        var leadLines: [String] = []
        var leadRefs: [String] = []
        // The leads — a thing in full, per shape that landed. Both prefer
        // something this window hasn't already led with, then the sources you
        // actually visit (§214) — see `ranked`.
        if let mention = mentionCard(leadPool, told: told, weights: weights) {
            leadRefs.append("men")
            leadLines += mention.lines
            leadIDs.append(mention.id)
        }
        // Who's around (2026-08-08) — leads before the reading card: a face
        // is a stronger claim than an article, the same ordering `mention`
        // already gets over `reading` for the identical reason.
        if let people = peopleRow(leadPool) {
            leadRefs.append("people")
            leadLines += people.lines
            leadIDs.append(people.id)
        }
        // THE READING CARD, THE NOTES CARD AND THE DAY-READ PARAGRAPH ALL
        // RETIRED (user ruling 2026-08-14, prd §386a: "i don't like these …
        // reading … blocks of text facts"). What survives of the synthesis
        // section is what the user named good: the figures (hero, movers,
        // flow, runway, themes), the pictures (sheet), the people (faces,
        // peopleRow) and the mention lead. The paragraph's retirement also
        // takes the brief's ONLY model await out of the compose path — the
        // ~2.1s the reveal machinery spent three rulings hiding is simply
        // gone — and with it the module where the prompt-echo leak lived
        // (§386's tripwire stays on `dayRead` for any future caller).
        // `observations`/`readingCard`/`dayReadEvidence` remain compiled but
        // uncalled (the `PredictionVenueSwitcher` dormant-not-deleted shape),
        // so re-admitting one is a ruling away rather than a rebuild.
        ids += leadRefs
        lines += leadLines

        // PAINT TWO: everything deterministic, with the live reads in.
        //
        // Paint one (the recursive `skipLiveReads` pass above) is the corpus
        // half alone. This one adds the holdings hero, the movers tile and
        // the lede's risk rung — and, crucially, it lands BEFORE the model is
        // asked anything. Without it the entire finished document arrived in
        // one lump at `max(live reads) + dayRead`, which is what made the
        // brief read as a 20-25s skeleton: the corpus half was on screen in
        // well under a second, and then nothing changed for twenty seconds.
        //
        // Guarded exactly as paint one is, so the inner pass (`presenting:
        // false`, no `onPartial`) can never reach it and the recursion stays
        // one level deep.
        // `!ids.isEmpty` matters: the quiet-day early return further down
        // replaces the whole document with one "nothing has landed" line, and
        // without this an empty day would paint a bare `Stack([])` first — a
        // flash of nothing between the skeleton and the sentence.
        if let onPartial, presenting, !skipLiveReads, !ids.isEmpty {
            onPartial(Self.assemble(ids: ids, lines: lines,
                                    category: category, leadRefs: leadRefs,
                                    hour: Calendar.current.component(.hour, from: now),
                                    sectionQualifiers: sectionQualifiers,
                                    final: false))
        }
        // The `dayread` paragraph's emission stood here until 2026-08-14
        // (prd §386a) — see the retirement note above the leads.
        // The SECOND re-filter (2026-08-14) — see the long note at the first
        // one. The model await that used to sit here is retired, but the live
        // reads and the partial-paint compose above are still suspensions,
        // and the two reads still to come (`landed.map(\.source)` in the
        // ledger write, `DayBrief.detail(things:)` in the digest) both touch
        // stored properties. Everything after this line is synchronous and
        // `@MainActor`, so this one really is the last word.
        things = things.live
        landed = landed.live

        // What this window's brief showed — the memory every §214 read is
        // built on. Written last, so it records what was actually composed,
        // and only when a person is looking at it.
        //
        // SKIPPED for a scoped brief. `BriefLedger` tracks the WHOLE day's
        // streaks/themes/absence — recording a Work-only slice into it under
        // the unscoped brief's own `windowStart` would corrupt tomorrow's
        // "ETH has done the lifting N days running" and theme-continuity
        // reads with a fact that was never about the whole day. A category's
        // own continuity is `BriefScope`'s job (below), not this ledger's.
        if presenting, category == nil {
            BriefLedger.record(into: ledger, windowStart: windowStart, leadIDs: leadIDs,
                               ledeSymbol: lede.symbol, themes: themeNames,
                               sources: Array(Set(landed.map(\.source))), now: now)
        }
        // A brief a person actually saw counts as having checked every
        // category it covers (spec: "update it when a brief containing that
        // category renders") — this category alone when scoped, every
        // category at once for the unscoped/"Everything" brief.
        if presenting {
            BriefScope.markViewed(category: category, at: now)
        }

        // Nothing to draw at all — an honest empty window, not an empty
        // screen. The scoped wording names WHEN rather than claiming "today",
        // since a scoped window is "since you last checked", not necessarily
        // today at all (spec: "render the brief shell with a single line
        // stating nothing new since [time]").
        guard !ids.isEmpty else {
            let since = windowStart.formatted(.dateTime.hour().minute())
            let line = category.map { String(localized: "Nothing new in \($0) since \(since).") }
                ?? String(localized: "Nothing has landed yet today.")
            // A QUIET DAY IS STILL A DAY (2026-08-16). One grey sentence on an
            // otherwise blank screen is the only state in this whole file that
            // renders as a failure — and it is the most COMMON state for a new
            // corpus, which makes it the first thing many people ever see the
            // brief do. Fitness and Photos never draw nothing; they reach back.
            //
            // So does this now, and only ever to something REAL: the corpus's
            // own anniversary if this day carries one, else the newest thing
            // there is. Both are the module doctrine's second shape — the thing
            // itself, in full — so neither is a tally and neither invents. When
            // the corpus is genuinely empty (a fresh install, the one case
            // where there is nothing to reach for) the sentence stands alone,
            // exactly as before.
            let pool = things.live.filter { !Corpus.isImportReceipt($0) }
            var doc = ["root = Stack([ins])", "ins = Insight(\"\(genSafe(line))\")"]
            if let echo = OnThisDay.find(in: pool, now: now) {
                doc[0] = "root = Stack([ins, back])"
                doc.append(reachBack(echo.thing, meta: echo.label))
            } else if let newest = pool.max(by: { $0.capturedAt < $1.capturedAt }) {
                doc[0] = "root = Stack([ins, back])"
                doc.append(reachBack(newest,
                                     meta: String(localized: "The last thing you kept")))
            }
            return KeptAskComposers.Result(
                delta: "", digest: String(localized: "quiet"), doc: doc)
        }
        // (The Life permutation and the chapter marks moved into `assemble`
        // below, 2026-08-14, so the pre-model partial renders through exactly
        // the same ordering rules as the final document. Two copies of this
        // would mean the brief could re-order itself under the reader the
        // moment the model answered.)
        //
        // The digest IS the whisper's own detail line for the unscoped brief
        // — so the kept pill's trailing signal and the capsule that teases
        // this screen say the same thing, and the changed-dot fires on
        // exactly the days the whisper would have changed. (The whisper's
        // TITLE is deliberately not part of it: a pill that already reads
        // "How's my day?" doesn't need "Your Wednesday brief" repeated after
        // it.) A scoped brief has no whisper to match, and `DayBrief.detail`
        // reads whole-corpus wallet state regardless of `things` — so its
        // digest is built straight from what this window actually composed:
        // count plus which modules fired, which changes on exactly the asks
        // that would show something new.
        let digest = category == nil
            ? (DayBrief.detail(things: things, now: now) ?? String(localized: "quiet"))
            : "\(landed.count)|\(ids.joined(separator: ","))"
        // WHICH MODULES a scope actually composed (2026-08-09). Kept for the
        // same reason `briefPerf` above is: "the Work brief looks empty" is a
        // recurring report whose cause is never guessable from the screen —
        // a module can be missing because its data is thin, because its gate
        // is scoped out, or because it silently lost a registry entry, and
        // those look identical. One compact line per compose says which.
        #if DEBUG
        NSLog("[Casberi] briefModules| category=%@ ids=%@", category ?? "nil", ids.joined(separator: ","))
        NSLog("[Casberi] briefModuleMs| category=%@ %@", category ?? "nil",
              moduleMarks.filter { $0.1 >= 1 }
                  .sorted { $0.1 > $1.1 }
                  .map { "\($0.0)=\(Int($0.1))ms" }
                  .joined(separator: " "))
        #endif
        let doc = Self.assemble(ids: ids, lines: lines,
                                category: category, leadRefs: leadRefs,
                                hour: Calendar.current.component(.hour, from: now),
                                sectionQualifiers: sectionQualifiers,
                                // A DRAFT MUST NOT CLAIM TO BE THE END. This
                                // same function composes the corpus-half paint
                                // (the recursive `skipLiveReads` pass), and a
                                // terminus on that one says "that's your day"
                                // and then keeps growing modules above itself —
                                // which is a worse version of the confusion the
                                // terminus exists to remove.
                                final: !skipLiveReads)
        // What each module SAID, for the next brief's quiet set — written
        // last and only when presenting, so a background digest compose can
        // never spend the novelty of a brief nobody saw (`BriefLedger.record`
        // one screen up takes the same guard for the same reason). Unscoped
        // only: a scoped brief draws a different subset, and letting it write
        // here would make the whole overview read as "unchanged" the next
        // morning because a Money-only compose had touched three of its ids.
        if presenting, category == nil {
            Self.recordModuleDigests(ids: ids, lines: lines)
            // The session's last presented doc — what the NEXT rise paints
            // instantly while the fresh compose runs (prd §386k).
            Self.lastPresentedDoc = doc
        }
        return KeptAskComposers.Result(delta: digest, digest: digest, doc: doc)
    }

    /// `ids` + `lines` → the document the Stack reads.
    ///
    /// Extracted 2026-08-14 so the pre-model partial and the final return
    /// render through ONE set of ordering rules. Both the Life permutation and
    /// the chapter marks live here; with a copy in each caller, the brief
    /// could legitimately re-order itself under someone mid-read the instant
    /// the model answered, which is a worse artifact than the latency this
    /// whole pass exists to remove. Pure — no model reads, no `Thing`.
    /// The quiet day's one real module — a thing, drawn whole, with a meta line
    /// saying WHY it is the one being shown.
    ///
    /// `LeadRow` rather than `Row`: it carries the picture, and on the one
    /// screen whose problem is emptiness a photograph is the difference between
    /// a reach-back and a second grey sentence. It is also already the shape the
    /// leads use, so a quiet day and a busy one draw the same object.
    private static func reachBack(_ thing: Thing, meta: String) -> String {
        "back = LeadRow(\"\(genSafe(clamp(thing.title, max: 60)))\", \"\(genSafe(meta))\", "
            + "\"\(genSafe(thing.previewImageURL ?? ""))\", \"\(thing.id.uuidString)\", "
            + "\"\(genSafe(thing.source))\")"
    }

    private static func assemble(ids: [String], lines: [String],
                                 category: String?, leadRefs: [String],
                                 hour: Int,
                                 sectionQualifiers: [String: String] = [:],
                                 final: Bool) -> [String] {
        var ids = ids
        // The clock's permutation runs FIRST, so the Life ruling below —
        // which is about one scope's subject, not about the hour — gets the
        // last word on the arrangement it cares about.
        ids = timeOrdered(ids, hour: hour)
        // …then the SUBJECT grouping, which supersedes both for the unscoped
        // brief (prd §386g). See `sectioned`.
        var lines = lines
        // LIFE IS PEOPLE-FIRST (2026-08-13, from walking the three scopes on
        // the sim). Every other ordering decision in this file is about rank —
        // what is most consequential — and that ladder is right for a day and
        // for Work, where the consequential thing is a deadline. In Life it
        // produced a to-do list wearing the word "Life": the lede, the axis and
        // the "Coming up" card are all deadlines, so four of six modules were
        // chores, and the two modules that are actually somebody's life — the
        // pictures they saw and the people around them — sat below the fold
        // where the demo corpus put them two full screens down.
        //
        // A PERMUTATION of what already composed, never a different
        // composition: same modules, same gates, same lines — only the order
        // `ids` names them in, which is all the Stack reads. So no module can
        // appear or disappear here, and every other scope is untouched.
        if category == "Life" {
            let people = ["sheet", "faces"].filter { ids.contains($0) }
            if let deadlines = ids.firstIndex(where: { ["axis", "runway", "pair"].contains($0) }),
               !people.isEmpty {
                var reordered = ids.filter { !people.contains($0) }
                let at = min(reordered.firstIndex(where: { ["axis", "runway", "pair"].contains($0) })
                             ?? deadlines, reordered.count)
                reordered.insert(contentsOf: people, at: at)
                ids = reordered
            }
        }
        // The CHAPTERS (2026-07-31) — which modules open a new movement, so
        // the rank order this file spent three rulings establishing is
        // legible as rhythm rather than only as sequence. Every module
        // self-pads the same 8pt, which drew the whole brief as one dense
        // column: the money story, the day's subject, the agent's read and
        // the things themselves all sat at the same distance from each other
        // as the hero sits from its own watchlist.
        //
        // What is NOT a chapter is the point: `pair` stays glued to `hero`
        // (user ruling 2026-07-23, one story never split) and `tmkt` with
        // them (a resolved market is money news), and the second lead stays
        // glued to the first. Composed rather than hard-coded in the renderer
        // because only this file knows which of them actually fired.
        // `dayread`/`notes` left the chapter list with their modules (prd
        // §386a); the filter would have dropped the absent ids anyway, but a
        // list naming retired modules reads as if they might come back.
        // A SECTION HEADER IS ALREADY A CHAPTER (prd §386g) — it carries its
        // own `s6` of air above it, so a module that sits under one must not
        // ALSO take the chapter gap: on the sim that stacked two openings and
        // left a hole between the header and the card it names. The headers
        // are the chapters now wherever they exist; the list below survives
        // for the scoped briefs, which have no headers at all.
        var chapters = ["alerts", "hero", "themes", leadRefs.first]
            .compactMap { $0 }
            .filter { ids.contains($0) && $0 != ids.first }
        // The SUBJECT grouping (prd §386g) — unscoped only, and last, so it
        // has the final word on arrangement. A scoped brief keeps the rank
        // order: it covers one subject already, so naming sections inside it
        // would label a room with the name of the building.
        if category == nil {
            let grouped = sectioned(ids: ids, qualifiers: sectionQualifiers)
            ids = grouped.ids
            lines += grouped.lines
            // THE SECTION HEADERS ARE THE CHAPTERS (2026-08-15, §386i
            // amendment). §386g filtered headed modules out of the chapter
            // list so the air wouldn't stack twice — right on the phone, and
            // it silently EMPTIED the list, which is the one thing
            // `GenFrontPage` keys its wide-surface columns on: the Mac brief
            // fell back to a single narrow column and nothing reported it
            // (`qualifies` returning false is indistinguishable from a doc
            // that never had chapters). The headers are the brief's
            // movements now, so they are the column seams.
            chapters = grouped.sections.filter { $0 != ids.first }
        }
        // The QUIET set (prd §386d) — modules whose line is byte-identical to
        // the last brief this device SHOWED. Arg 2, absent everywhere else,
        // and an empty arg is a no-op, so every other `Stack` emitter is
        // untouched.
        // THE DOCUMENT ENDS (2026-08-16). Every module here composes only when
        // it has something to say, which is right, and means the brief simply
        // stops when the last one runs out — so a short day and a document that
        // failed to finish assembling look identical from the bottom of the
        // scroll. On a streamed page that is the worse reading of the two: the
        // brief paints progressively, so "nothing more arrived" is exactly what
        // a stall looks like.
        //
        // "That's your day", NOT "you're all caught up". The brief folds things
        // away by design — the day card counts what it left out ("69 more · 176
        // people") — so a claim about the FEED being empty would be false on
        // the very screen that just admitted otherwise. This says only what it
        // can: the document is over.
        //
        // `Coach` rather than a component of its own: it is already the page's
        // quiet secondary line, and a terminus is the same drawing with a
        // different sentence in it.
        if final {
            ids.append("end")
            lines.append("end = Coach(\"\(genSafe(category.map { String(localized: "That's \($0).") } ?? String(localized: "That's your day.")))\")")
        }
        let quiet = quietIDs(ids: ids, lines: lines)
        return ["root = Stack([\(ids.joined(separator: ", "))], \"\(chapters.joined(separator: ","))\", \"\(quiet.joined(separator: ","))\")"] + lines
    }

    /// The brief's SUBJECTS, in order, and which module ids belong to each
    /// (2026-08-15, prd §386g).
    ///
    /// The order is the user's own: what NEEDS you, then money, then what is
    /// coming, then the day itself, then the people reacting to it, then work,
    /// then what it was all about. It replaces a pure consequence rank whose
    /// visible symptom was money appearing in three places with the deadlines
    /// sitting in the middle of it — a split nobody could see precisely
    /// because nothing was named.
    ///
    /// A section is emitted ONLY when it has a member, and its header is a
    /// real element in `ids`, so the whole thing inherits the quiet set, the
    /// front-page columns and the chapter air for free.
    ///
    /// **"Needs you" and "Coming up" sit TOGETHER** (2026-08-15, prd §386i,
    /// user: "'needs you' and 'coming up' seem like they should go together").
    /// They are one subject — what you owe, ordered by urgency — and the only
    /// thing separating them was that one is late and one is not. The cost the
    /// user named ("but then that puts wallet all the way down") is real and is
    /// paid by the ANCHOR CHIPS instead: with a nav at the top of the brief,
    /// what sits third stops being a question of what you can reach.
    private static let sectionPlan: [(title: String, hue: String, room: String, ids: [String])] = [
        // THE THREE CARDS, BY NAME (2026-08-15, user, against the approved
        // deck mockup: "needs you was yellow… wallet… probably blue b/c
        // wallet is money… your day… opposite of wallet").
        //
        // Needs you and Coming up now share the ATTENTION hue rather than
        // holding two — §386i already ruled them one subject ("what you owe,
        // ordered by urgency"; the only thing separating them is that one is
        // late), and once the hue is a whole card ground rather than a chip
        // tint, giving one subject two colours says they are two. Money takes
        // the blue that Coming up vacates.
        ("Needs you", "attention", "", ["alerts"]),
        ("Coming up", "attention", "Reminders", ["axis", "runway"]),
        // `hero` and `spark` are alternatives, never both — the hero carries
        // its own curve, and the spark is what stands in when the live
        // holdings read left the hero unable to compose (§386h).
        ("Money", "tint", "Wallet", ["hero", "spark", "holdmap", "pair", "tmkt", "flow", "spend"]),
        ("Your day", "life", "", ["fold", "posts", "map"]),
        ("Work", "work", "GitHub", ["work", "ghgraph", "ship"]),
    ]

    /// Regroups `ids` under `sectionPlan`, prefixing each populated section
    /// with its own `Section` line.
    ///
    /// Anything the plan does not name keeps its relative order and follows in
    /// a TRAILING run with no header — the leads, and any module added later
    /// that nobody has filed yet. That is the safe default: an unfiled module
    /// still draws, it just draws unlabelled, rather than vanishing because a
    /// plan forgot it. `lede` is deliberately unfiled — it is the headline,
    /// above every section.
    private static func sectioned(ids: [String],
                                  qualifiers: [String: String])
        -> (ids: [String], lines: [String], sections: [String]) {
        var remaining = ids
        var out: [String] = []
        var lines: [String] = []
        var sections: [String] = []
        // The headline stays at the very top, outside every section.
        if let lede = remaining.firstIndex(of: "lede") {
            out.append(remaining.remove(at: lede))
        }
        var n = 0
        for section in sectionPlan {
            let members = remaining.filter { section.ids.contains($0) }
            guard !members.isEmpty else { continue }
            let id = "sec\(n)"
            n += 1
            // The qualifier is the section's own count where a count is a
            // real reading — "Needs you · 3" is how many things want you.
            // Nowhere else: "Money · 4" would be counting cards, which is
            // the tally §213 bans.
            lines.append("\(id) = Section(\"\(genSafe(section.title))\", \"\(genSafe(qualifiers[section.title] ?? ""))\", \"\(section.hue)\", \"\(genSafe(section.room))\")")
            sections.append(id)
            out.append(id)
            out.append(contentsOf: members)
            remaining.removeAll { members.contains($0) }
        }
        // Whatever the plan didn't name, in its original order.
        out.append(contentsOf: remaining)
        return (out, lines, sections)
    }

    /// The module order, permuted by TIME OF DAY (2026-08-14, prd §386d).
    ///
    /// A PERMUTATION of what already composed, never a different composition —
    /// the `category == "Life"` reordering above is the precedent and the same
    /// rules apply: same modules, same gates, same lines, only the order `ids`
    /// names them in, which is all the `Stack` reads. So no module can appear
    /// or disappear here.
    ///
    /// MORNING (before noon) leads with the day AHEAD: the deadlines climb to
    /// just under the alerts, above the money. EVENING (17:00 on) leads with
    /// the day BEHIND: what you saw, who reached you and where it came from
    /// climb above the deadlines, which by evening are mostly tomorrow's
    /// problem. The middle of the day keeps the pure consequence rank, which
    /// is what every hour used to get.
    ///
    /// The clock is the DEVICE's, read once and passed in, so a compose and
    /// its partial can never straddle a boundary and reorder mid-paint.
    private static func timeOrdered(_ ids: [String], hour: Int) -> [String] {
        let ahead = ["axis", "runway", "pair"]
        let behind = ["posts", "sheet", "faces", "mix"]
        let group: [String], anchor: [String]
        switch hour {
        case ..<12:  group = ahead;  anchor = ["hero"]
        case 17...:  group = behind; anchor = ahead
        default:     return ids
        }
        let moving = ids.filter { group.contains($0) }
        guard !moving.isEmpty,
              let at = ids.firstIndex(where: { anchor.contains($0) })
        else { return ids }
        // Re-find the anchor AFTER the movers are pulled out — removing an
        // element ahead of it shifts every later index, and inserting at the
        // stale one drops the group in the wrong place (or traps).
        var rest = ids.filter { !group.contains($0) }
        let insertAt = rest.firstIndex(where: { anchor.contains($0) }) ?? min(at, rest.count)
        rest.insert(contentsOf: moving, at: insertAt)
        return rest
    }

    /// Which of this brief's modules say exactly what they said last time.
    ///
    /// The comparison is on the module's own DOC LINES — the rendered facts,
    /// byte for byte — so "unchanged" means what a reader would call
    /// unchanged, not what a hash of some upstream state would. Stored in its
    /// own UserDefaults key rather than on `BriefLedger.Entry`: that type is
    /// decoded with `try?` onto an empty fallback, and a new key in a
    /// synthesized `Codable` is exactly the shape that silently empties a
    /// persisted store (the `RSSStore.Feed` lesson, CLAUDE.md).
    ///
    /// **Dimming is a CONTRAST device, so it is all-or-nothing**: if NOTHING
    /// changed there is nothing to contrast against, and dimming the whole
    /// screen reads as a broken render rather than as "you have seen this".
    /// The lede is never dim — a greyed-out headline is the same failure at
    /// the top of the page.
    ///
    /// Nor is the TERMINUS (2026-08-16), for a stronger reason than taste: it
    /// says the same sentence every single day by construction, so it is
    /// unchanged on every brief there will ever be. Left in, it would be the
    /// one module guaranteed to dim on a day when everything else was new —
    /// the end of the document greying out precisely when the document was at
    /// its most interesting — and it would sit in `shown` permanently skewing
    /// the all-or-nothing count that decides whether anything dims at all.
    private static func quietIDs(ids: [String], lines: [String]) -> [String] {
        let now = digests(ids: ids, lines: lines)
        let shown = ids.filter { $0 != "lede" && $0 != "end" }
        let previous = UserDefaults.standard.dictionary(forKey: quietKey) as? [String: String] ?? [:]
        let unchanged = shown.filter { id in
            guard let a = now[id], let b = previous[id] else { return false }
            return a == b
        }
        guard unchanged.count < shown.count else { return [] }
        return unchanged
    }

    /// Records what each module SAID, for the next brief's quiet set. Written
    /// only when a person is actually looking (the `BriefLedger.record` rule):
    /// a background digest compose must not consume the novelty of a brief
    /// nobody saw.
    private static func recordModuleDigests(ids: [String], lines: [String]) {
        UserDefaults.standard.set(digests(ids: ids, lines: lines), forKey: quietKey)
    }

    /// One module → everything it draws, as one string.
    ///
    /// **A module's digest MUST include its CHILD lines.** A widget's own line
    /// names its refs and nothing else (`posts = Widget("Your posts", "",
    /// [pr0, pr1])`), so four completely different rows under an unchanged
    /// header hash identically — the card would dim on the day its contents
    /// turned over, which is the exact opposite of what this is for. Children
    /// are emitted immediately after their parent by every composer here
    /// (`agendaRows`, `yourPostsCard`, `rows`), so a module owns every line
    /// from its own up to the next line whose id is a module.
    private static func digests(ids: [String], lines: [String]) -> [String: String] {
        func head(_ line: String) -> String? {
            guard let eq = line.firstIndex(of: "=") else { return nil }
            return line[..<eq].trimmingCharacters(in: .whitespaces)
        }
        let moduleIDs = Set(ids)
        var out: [String: String] = [:]
        var current: String?
        for line in lines {
            if let id = head(line), moduleIDs.contains(id) { current = id }
            guard let current else { continue }
            out[current, default: ""] += line
        }
        return out
    }

    private static let quietKey = "brief.module.digests"

    // MARK: - Synthesis (direction B3)

    struct Note {
        let glyph: String
        let text: String
        var thingID: String = ""
    }

    /// The agent's read of the day — at most three observations, each a
    /// deterministic pattern that actually fired. The discipline this module
    /// lives or dies by: **a pattern that didn't fire produces no line**.
    /// Three strong lines read as intelligence; three padded ones read as a
    /// horoscope, so nothing here has a filler branch — a patternless day
    /// simply drops the card and the brief starts at the money hero.
    ///
    /// `topic` and `leads` are handed in rather than recomputed: both leads
    /// (§166's cards) are composed BEFORE this now, so an observation can see
    /// what the screen is already about to render in full and decline to say
    /// it a second time.
    ///
    /// `cap` is the depth knob a scoped brief raises (spec: "depth scales
    /// inversely with scope" — fewer apps in view, so more of what fired
    /// earns a seat instead of losing it to the unscoped brief's 3-note
    /// ceiling). Defaults to 3, the unscoped brief's original, unchanged cap.
    static func observations(things: [Thing], landed: [Thing], move: DayBrief.WalletMove?,
                             moves: [TokensAsk.Move], now: Date,
                             ledger: [BriefLedger.Entry], ledeTookRisk: Bool,
                             topic: Topic? = nil, leads: Set<String> = [], cap: Int = 3) -> [Note] {
        var out: [Note] = []

        // The money's own sentence, displaced. When a liquidation risk takes
        // the lede the attribution has nowhere else to go, so it comes back
        // here — the seat it held before 2026-07-25 — rather than the day's
        // biggest number going unexplained. Never both: if the lede said it,
        // this doesn't.
        if ledeTookRisk {
            let attribution = walletAttribution(move).text
            if !attribution.isEmpty {
                out.append(Note(glyph: "dollarsign.circle", text: attribution))
            }
        }

        // A RECORD — the rarest, best kind of surprise (2026-07-22). Checked
        // early so it competes for a slot ahead of the routine observations;
        // still capped by the same `.prefix(3)` at the end, so a record never
        // grows the card, it just earns a better seat in it. Positive-only by
        // design: celebrating a big DROP as a "record" would be tone-deaf, and
        // the discipline every other note already keeps (never pad, never
        // invent) rules out a negative-framed one too.
        if let record = records(things: things, landed: landed, move: move, now: now) {
            out.append(record)
        }

        // THE JOINS (§214). Everything above and below this pair reads a
        // single field — a reply count, a word frequency, a percentage — which
        // is a read any single-source app could make. These two cross sources,
        // which is the only thing this corpus can do that a feed reader can't,
        // so they sit ahead of the single-signal families.
        if let echo = marketReadingEcho(moves: moves, things: things, now: now) {
            out.append(echo)
        }
        if let person = personEcho(landed) {
            out.append(person)
        }

        // On this day (2026-07-28) — the corpus's own anniversary, promoted
        // from a card that only ever rendered beside a habit source's own
        // heatmap (`OnThisDay`/`FeedScreen.calendarHeatmapSection`) — so
        // someone who never opens the Day One/Obsidian feed directly still
        // gets the reach-back. Same rule as everywhere else `OnThisDay` is
        // read: a real match only, never invented.
        if let echo = OnThisDay.find(in: things) {
            out.append(Note(glyph: "clock.arrow.circlepath",
                            text: String(localized: "\(echo.label): \(clamp(echo.thing.title, max: 60))"),
                            thingID: echo.thing.id.uuidString))
        }

        // A mention that's gathering a conversation — the reply count is the
        // pattern, not the mention itself (any mention already leads its own
        // card below; this fires only when people are talking under it).
        //
        // And only for a mention the card below ISN'T already leading with
        // (2026-07-31): that card renders the post in full and its meta line
        // already carries the same reply count, so on the common day — one
        // mention, and it's the busy one — the note was the card's own
        // sentence, printed above the card. It still fires when the lead is a
        // different mention, which is the case where it says something new.
        if let hot = landed
            .filter({ $0.socialContext == "mention" && ($0.replyCount ?? 0) >= 3
                        && !leads.contains($0.id.uuidString) })
            .max(by: { ($0.replyCount ?? 0) < ($1.replyCount ?? 0) }),
           let replies = hot.replyCount {
            let who = hot.authorHandle ?? String(localized: "someone")
            out.append(Note(glyph: "bubble.left.and.bubble.right",
                            text: String(localized: "\(who)'s mention is gathering replies — \(replies) so far."),
                            thingID: hot.id.uuidString))
        }

        // A dominant topic across the day's reading — the same word carried by
        // a third or more of the day's titles.
        //
        // The note NAMES NO READ (2026-07-31, user: "then below it will be
        // another card with that specific item in it"). It used to spell out
        // the outlier's headline, clamped to 60 — and the Reading card
        // directly beneath it leads with that exact thing, in full, with its
        // image and its tap. So the interesting read arrived twice, worse
        // first. The observation now states only the pattern, which is the
        // half the card can't state, and the card below says which read is the
        // exception (`readingCard`'s own title). Same precedent as the wallet
        // attribution moving into the hero: one screen, one place per fact.
        if let topic {
            out.append(Note(glyph: "newspaper",
                            text: topic.outlier == nil
                                ? String(localized: "Your reading keeps circling \(topic.word).")
                                : String(localized:
                                    "Your reading keeps circling \(topic.word) — every read today but one.")))
        }

        // (The wallet attribution — "ETH did the lifting" — used to be a note
        // here. It moved INTO the hero on 2026-07-25, where it reads as the
        // crown's own sentence directly under the number it explains; see
        // `walletAttribution`. Leaving it here too would have said the same
        // thing twice on one screen.)

        // A watchlist leader worth naming — only a real move, and only when
        // it clearly leads the rest (a 0.2% "leader" is noise wearing a
        // ranking). Skipped once three observations already fired.
        if out.count < cap, let leader = moves.max(by: { abs($0.change) < abs($1.change) }),
           abs(leader.change) >= 0.03 {
            out.append(Note(glyph: "chart.xyaxis.line",
                            text: String(format: "%@ leads your watchlist at %+.1f%%.",
                                         leader.symbol, leader.change * 100),
                            thingID: leader.thing.id.uuidString))
        }

        return Array(out.prefix(cap))
    }

    /// The day's real facts, flattened to plain lines for the model's read of
    /// the day (2026-08-07). Every line is something a deterministic pass
    /// already established — the fired notes, then the day's own landed things
    /// the notes didn't already name — so the model's job is only to find the
    /// thread across them, never to discover a new fact. The money total is
    /// deliberately absent (the hero owns it), so the read can't restate it.
    /// Bounded so it fits the on-device context window.
    static func dayReadEvidence(landed: [Thing], notes: [Note], topic: Topic?) -> String {
        var lines: [String] = []
        for note in notes where !note.text.isEmpty { lines.append("- " + note.text) }
        if let topic { lines.append("- Several of today's reads are about \(topic.word).") }
        let named = Set(notes.map(\.thingID)).subtracting([""])
        for thing in landed where thing.isLive && !named.contains(thing.id.uuidString) {
            let title = clamp(thing.title, max: 70)
            guard !title.isEmpty else { continue }
            lines.append("- \(title) (\(thing.source))")
            if lines.count >= 14 { break }
        }
        return lines.joined(separator: "\n")
    }

    /// The topics the last few briefs kept returning to — continuity fuel for
    /// the read, so a week reads as a thread. Distinct theme words from the
    /// recent ledger, most-recent first, three at most; nil when the ledger is
    /// empty (the read then simply carries no continuity clause).
    static func dayReadContinuity(_ ledger: [BriefLedger.Entry]) -> String? {
        var seen = Set<String>()
        var out: [String] = []
        for entry in ledger.suffix(4).reversed() {
            for theme in entry.themes where seen.insert(theme.lowercased()).inserted {
                out.append(theme)
                if out.count == 3 { break }
            }
            if out.count == 3 { break }
        }
        return out.isEmpty ? nil : out.joined(separator: ", ")
    }

    /// The 4th observation family (2026-07-22, user: "how would you improve
    /// the surprise & delight"): a deterministic RECORD — the most reading in
    /// a day this month, or the wallet's best day since watching began. Both
    /// are rare by construction (they only fire when a genuine local max is
    /// actually beaten), which is what makes them a real surprise rather than
    /// a threshold dressed up as one — there is no "big green day" confetti
    /// here, because a fixed percentage threshold is exactly the horoscope
    /// failure mode this card's whole discipline exists to avoid. Checks in
    /// priority order; returns the first that fires.
    ///
    /// ONE family now (2026-07-25): the reading record ("most reading to land
    /// in one day this month — 12 so far") was cut with the volume modules. It
    /// is a tally wearing a surprise, and for someone receiving dozens a day
    /// the monthly maximum is beaten constantly, so it was neither rare nor
    /// news. The wallet record survives because it measures a MOVE, not an
    /// arrival count.
    private static func records(things: [Thing], landed: [Thing],
                                move: DayBrief.WalletMove?, now: Date) -> Note? {
        walletRecord(move, now: now)
    }

    /// Today's wallet gain beats every prior day's gain since watching began.
    /// Compares day-over-day moves off the LAST sample of each calendar day
    /// (`combinedValueSamples()` — cached, no network read). Needs real
    /// history (4+ distinct prior days) before "record" means anything; a
    /// two-day-old wallet can't have a "best day" yet.
    private static func walletRecord(_ move: DayBrief.WalletMove?, now: Date) -> Note? {
        guard let move, move.pct > 0 else { return nil }
        let samples = WalletStore.shared.combinedValueSamples()
        guard samples.count >= 8 else { return nil }
        let cal = Calendar.current
        var lastPerDay: [Date: Double] = [:]
        for s in samples {
            // Samples arrive chronologically, so the LAST write for a day
            // naturally wins — no explicit sort needed.
            lastPerDay[cal.startOfDay(for: s.at)] = s.usd
        }
        let days = lastPerDay.keys.sorted()
        guard days.count >= 4 else { return nil }
        var priorMoves: [Double] = []
        for i in 1..<days.count {
            guard !cal.isDate(days[i], inSameDayAs: now) else { continue }   // today isn't "prior"
            guard let prev = lastPerDay[days[i - 1]], prev > 0,
                  let cur = lastPerDay[days[i]] else { continue }
            priorMoves.append((cur - prev) / prev * 100)
        }
        guard priorMoves.count >= 3, let bestPrior = priorMoves.max(), move.pct > bestPrior
        else { return nil }
        return Note(glyph: "trophy",
                    text: String(format: String(localized:
                        "Your wallet's best day since you started watching — %@."),
                        String(format: "%+.1f%%", move.pct)))
    }

    /// What the day's reading is ABOUT, when it's about one thing — and, only
    /// when the claim is literally true, the single read that isn't.
    struct Topic {
        let word: String
        /// Non-nil ONLY when exactly one read lacks the word. "The one that
        /// doesn't" is a claim of uniqueness, and it was being made about one
        /// of seven equally-unrelated reads (user, 2026-07-31: "it never really
        /// makes sense"). When several reads sit outside the topic there is no
        /// outlier — there's just a topic — so this is nil and the note says
        /// only what it can defend.
        let outlier: Thing?
    }

    /// The word the day's reads share, and the one read that doesn't carry it.
    /// Deterministic and cheap: significant words only (4+ characters, not a
    /// stopword), counted once per title.
    ///
    /// Three gates, each paid for (2026-07-31):
    ///
    /// 1. **Coverage** — the word must reach at least a THIRD of the day's
    ///    reading. At the old bare floor of 3 titles, a 20-read day let any
    ///    word appearing three times claim the whole day "keeps circling" it,
    ///    which is a coincidence wearing a pattern's clothes.
    /// 2. **A deterministic leader** — `Dictionary.max(by: value)` resolves a
    ///    tie by hash order, which is seeded per PROCESS, so two words tied at
    ///    the top named a different topic on each rise of the same day's brief.
    ///    Ties break alphabetically instead, so the brief says one thing.
    /// 3. **A real outlier or none** — see `Topic.outlier`.
    ///
    /// Membership is decided by the SAME tokenizer that does the counting, not
    /// by `title.contains(key)`: substring matching called a read carrying
    /// "openai" a member of the topic "open", and it read the raw title while
    /// the count read `topicText` (GitHub's repo path stripped), so a read
    /// could be counted out of the topic and out of the outlier slot at once.
    private static func dominantTopic(_ landed: [Thing]) -> Topic? {
        let reads = reads(landed)
        guard reads.count >= 4, let lead = topicLead(titles: reads.map(topicText))
        else { return nil }
        return Topic(word: lead.display,
                     outlier: lead.without.count == 1 ? reads[lead.without[0]] : nil)
    }

    /// The pure half of `dominantTopic` — titles in, the leading word and the
    /// POSITIONS of the titles that don't carry it out. Split out so the gates
    /// can be exercised against real title sets with no corpus, no SwiftData
    /// and no simulator (`ScreenshotTopics.terms`' precedent).
    static func topicLead(titles: [String]) -> (key: String, display: String, without: [Int])? {
        var counts: [String: Int] = [:]
        var display: [String: String] = [:]
        // Each title's significant words, kept so membership and the outlier
        // are read off the same tokenization the count used.
        var carried: [Set<String>] = []
        for title in titles {
            // Count each word ONCE per title — a headline repeating a word
            // must not out-vote three separate articles sharing it.
            var keys = Set<String>()
            for word in words(of: title) {
                let key = word.lowercased()
                guard key.count >= 4, !stopwords.contains(key), keys.insert(key).inserted
                else { continue }
                counts[key, default: 0] += 1
                if display[key] == nil { display[key] = word }
            }
            carried.append(keys)
        }
        let leader = counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
        guard let top = leader.first, top.value >= 3, top.value * 3 >= titles.count
        else { return nil }
        return (top.key, display[top.key] ?? top.key,
                carried.indices.filter { !carried[$0].contains(top.key) })
    }

    /// A read's title, stripped of an "owner/repo" token when the read is
    /// FROM GITHUB — `notifications`/`stars`/`following` bake the full repo
    /// path into the title (`GitHubFeedFetch.thing`), so a person's own
    /// account name (or repo name) wins "dominant topic" purely because
    /// GitHub repeats its own path in some feeds' titles and not others
    /// (an `.involved` issue/PR title never carries it). That isn't a topic,
    /// it's the source's own formatting — and the "one that doesn't" outlier
    /// it produced was really just another item from the SAME repo whose
    /// title shape happens not to spell the path out (caught on-device
    /// 2026-07-27: "keeps circling <username>" flagged a same-repo GitHub
    /// issue as the exception). Scoped to GitHub only, so a genuine
    /// "Apple/Google" in an article headline elsewhere is untouched.
    private static func topicText(_ read: Thing) -> String {
        guard read.source == "GitHub" else { return read.title }
        return read.title.replacingOccurrences(
            of: #"\b[\w.-]+/[\w.-]+\b"#, with: " ", options: .regularExpression)
    }

    /// Words that carry no topic — common English plus the vocabulary every
    /// headline shares. Small on purpose: the 3-title floor does most of the
    /// filtering, this only stops the obvious false leaders.
    private static let stopwords: Set<String> = [
        "this", "that", "with", "from", "your", "have", "here", "what", "when",
        "will", "just", "into", "over", "more", "than", "then", "they", "them",
        "about", "after", "before", "could", "would", "should", "their", "there",
        "these", "those", "which", "while", "where", "https", "http", "www",
        "new", "news", "says", "said", "make", "makes", "made", "like", "still",
        "first", "best", "everything", "announced", "announcement",
    ]

    // MARK: - The money hero (the crown, and the fused visualization)

    /// `MoneyHero(total, delta, csv, subline, [cells])` — the day's one big
    /// read: the combined total, its day move, the balance line and the
    /// holdings treemap side by side, and beneath them the transactions that
    /// actually settled. The single place a count is allowed (money moving IS
    /// the event), and it names the transaction whenever there's just one.
    private static func moneyHero(move: DayBrief.WalletMove?,
                                  holdings: [WalletIngest.HoldingsGroup],
                                  landed: [Thing]) -> String? {
        guard !holdings.isEmpty else { return nil }
        let total = holdings.reduce(0) { $0 + $1.totalUSD }
        guard total > 0 else { return nil }
        // Every watched wallet's holdings merged BY SYMBOL — this is the
        // PORTFOLIO's day, not the first wallet's (§155's combined read, same
        // principle).
        //
        // It used to concatenate each wallet's own top-5 cells, which drew ETH
        // twice (seen on the sim, 2026-08-13: "ETH $8K" beside "ETH $3K", with
        // nothing saying they were different wallets) — a treemap whose whole
        // claim is "this is what you hold, sized by how much" cannot show one
        // holding as two rectangles. Summing first and cutting the top 5 after
        // is also the only way the ranking is true of the portfolio: a token
        // held in modest amounts across three wallets could out-rank one of
        // the cells drawn, and never appeared at all.
        //
        // `treemapCells` is `WalletIngest`'s own, so the merged map is cut,
        // weighted, marked and routed by the exact rule a single wallet's
        // cells already follow — no second formatting to drift. Falls back to
        // the old concatenation when the groups carry no by-symbol map, which
        // is what a last-known snapshot from an older build looks like.
        var merged: [String: Double] = [:]
        var routes: [String: String] = [:]
        for group in holdings {
            for (symbol, usd) in group.bySymbolAll { merged[symbol, default: 0] += usd }
            for (symbol, route) in group.routeBySymbol where routes[symbol] == nil {
                routes[symbol] = route
            }
        }
        let cells = merged.isEmpty
            ? holdings.flatMap(\.cells)
            : WalletIngest.treemapCells(bySymbol: merged, routes: routes)
        guard !cells.isEmpty else { return nil }
        // The balance SPARKLINE and its delta come from recorded value
        // HISTORY (`combinedValueSamples`) — a separate, honest data source
        // from the live holdings read, so they draw whenever there are ≥2
        // samples, flat line included (a flat curve honestly reads "steady").
        // Staleness (a failed live read) only concerns the TREEMAP's currency:
        // its one effect is the anchor line, which reads "as of Xh ago"
        // instead of the curve's own "since" date. The curve itself, being
        // recorded history, ends at that same last-known moment either way.
        let staleAt = holdings.compactMap(\.stale).min()
        let samples = WalletStore.shared.combinedValueSamples()
        let csv = samples.count >= 2
            ? samples.suffix(60).map { String(format: "%.2f", $0.usd) }.joined(separator: ",")
            : ""
        let delta = move.map { String(format: "%+.1f%%", $0.pct) } ?? ""
        // The settled money of the window — the honest count, plus the name
        // when there's exactly one.
        let settled = landed.filter { $0.kind == .transaction || $0.source == "Peer" }
        // A single named transaction draws as a real ROW (title/meta/id, args
        // 6–8); the plural and empty cases have no one thing to name, so they
        // keep the plain subline.
        var subline = ""
        var txTitle = "", txMeta = "", txID = ""
        if settled.count == 1 {
            let tx = settled[0]
            txTitle = clamp(tx.title, max: 52)
            txMeta = String(localized: "settled \(tx.capturedAt.formatted(.dateTime.hour().minute()))")
            txID = tx.id.uuidString
        } else if settled.count > 1 {
            subline = String(localized: "\(settled.count) transactions settled")
        } else {
            // "Nothing SETTLED", never "nothing moved" (2026-08-13). This
            // counts transactions, and the word "moved" made it a claim about
            // the BALANCE — which the delta pill beside it, the watchlist rows
            // below it and the day brief's own lede ("Up $269 today. ETH has
            // done the lifting") can all be contradicting at the same moment,
            // every one of them correct. Seen on the sim exactly that way. The
            // flow band further down is literally titled "Where it moved", so
            // the word was doing double duty on one screen; this line owns
            // "settled", which is also the word the single-transaction meta
            // beside it already uses.
            subline = String(localized: "Nothing settled today")
        }
        // The line's anchor — what span the curve covers, named the way
        // `ValueSpark`'s own subline names it; or, when stale, the honest
        // "as of Xh ago" that dates the last-known read.
        let anchor: String
        if let staleAt {
            anchor = String(localized: "as of \(staleAgo(staleAt, now: Date.now))")
        } else {
            anchor = samples.count >= 2
                ? (move.map { String(localized: "since \($0.since.formatted(.dateTime.month(.abbreviated).day()))") } ?? "")
                : ""
        }
        // The raw numbers, alongside the pre-formatted total (2026-07-22) — so
        // the renderer can ROLL the total from the day's anchor value to the
        // current one on mount (`GenMoneyHero`'s own delight pass) instead of
        // just printing a static string. `rollFrom` is the same anchor the %
        // delta is measured against; empty when there's no real move to roll
        // from, so a wallet with no day-scale history just shows the number
        // plainly.
        let rollFrom = move.map { String(format: "%.2f", $0.anchorUSD) } ?? ""
        return "hero = MoneyHero(\"\(genSafe(compactUSD(total)))\", \"\(delta)\", \"\(csv)\", \"\(genSafe(subline))\", [\(cells.prefix(6).joined(separator: ", "))], \"\(genSafe(anchor))\", \"\(genSafe(txTitle))\", \"\(genSafe(txMeta))\", \"\(txID)\", \"\(String(format: "%.2f", total))\", \"\(rollFrom)\")"
    }

    /// "Up $184 today." — the brief's LEDE (`DayLede`), the sentence the screen
    /// opens with, above the hero.
    ///
    /// It carries the fact the number and its pill can't: the MAGNITUDE in
    /// money, because a percentage hides whether +1.5% is a coffee or a month's
    /// rent. That is the whole sentence.
    ///
    /// **The attribution clause is GONE (user ruling, 2026-08-13: "the whole
    /// 'has done the lifting' and 'took it back' in the headlines is dumb. we
    /// can just say how much up").** It named the day's biggest mover and, on a
    /// streak, how many days running — §166's day-scoped attribution plus
    /// §214's continuity half. Both were true and neither was worth the words:
    /// the headline's job is the number, the holdings treemap directly beneath
    /// already shows which position is doing the work, and a stock phrase
    /// ("did the lifting", "took it back") wrapped around a symbol reads as
    /// voice rather than as information — the sort of writing that sounds like
    /// a newsletter and tells you nothing you couldn't see.
    ///
    /// Consequences worth knowing rather than rediscovering: the lede no longer
    /// reads `holdingsDeltas` at all (one local walk saved per compose), and it
    /// no longer credits a symbol, so `Lede.symbol` stays empty and
    /// `BriefLedger` records no `ledeSymbol` — `BriefLedger.symbolStreak` now
    /// has no caller (see its own note). The ledger's field and the
    /// `-briefLedger "symbol=…"` seed are left in place: they are a persisted
    /// format with a demo seeder, and nothing is served by churning them for a
    /// copy change.
    ///
    /// It has now been in three places in one day (2026-07-25): a synthesis
    /// note buried three modules down, then the hero's own subtitle when the
    /// money took the crown, then here — the user's call, and the one the
    /// approved mockup drew. Above the number it reads as the day's headline;
    /// under it, it read as a caption on a chart. It fails silently — no move,
    /// no line.
    private static func walletAttribution(_ move: DayBrief.WalletMove?) -> Lede {
        guard let move, move.anchorUSD > 0 else { return Lede() }
        let delta = move.usd - move.anchorUSD
        guard abs(delta) >= 1 else { return Lede() }
        // The figure is captured as the SAME string the sentence is built from
        // — not re-derived — so the accented run and the words can never
        // disagree about what the day's number was.
        let figure = compactUSD(abs(delta))
        let direction = delta > 0 ? "up" : "down"
        let line = delta > 0
            ? String(localized: "Up \(compactUSD(delta)) today.")
            : String(localized: "Down \(compactUSD(abs(delta))) today.")
        return Lede(text: line, figure: figure, direction: direction)
    }

    /// The ladder itself — the rungs in the order they can cost you something.
    ///
    /// Risk outranks the move on purpose: +$800 is the day's biggest number,
    /// but a health factor under `DeFiRisk.floor` is the day's
    /// biggest CONSEQUENCE, and it's the one a person can still act on. The
    /// money isn't lost when that happens — its attribution falls back to a
    /// synthesis note, which is where it lived before the crown pass.
    ///
    /// Every rung yields rather than padding: no debt, no risk line; no
    /// snapshot pair spanning the window, no money line; and an empty ladder
    /// returns "" so the brief simply opens on the hero.
    ///
    /// **This is not `DayBrief.lead`, and the orders differ on purpose.** That
    /// one ranks a mention above money; this one ranks money above a mention.
    /// Neither is wrong: `DayBrief.lead` feeds the whisper capsule and the
    /// kept pill, where the line stands ALONE and someone addressing you is
    /// the most human thing a lone line can carry — while this sentence sits
    /// directly above the money hero, which is about to say the number
    /// anyway, so a lede that named a mention instead would leave the crown
    /// uncaptioned. Don't "fix" one to match the other.
    private static func ledeLine(move: DayBrief.WalletMove?, risk: DeFiRisk.Debt?,
                                 landed: [Thing], things: [Thing],
                                 now: Date, alerted: Set<UUID> = []) -> Lede {
        // 1. Something is close to liquidation.
        if let risk {
            let chain = WalletIngest.displayName(forNetwork: risk.network) ?? risk.network
            return Lede(text: String(localized:
                "Your \(risk.protocolName) position on \(chain) is close to liquidation — health factor \(WalletIngest.format(risk.hf))."),
                        tookRisk: true)
        }
        // 2. The money moved.
        let money = walletAttribution(move)
        if !money.text.isEmpty { return money }
        // 3. Someone addressed you by name. The mention card below shows the
        // POST; this says who, which is the half a headline is for.
        if let mention = landed.first(where: { $0.socialContext == "mention" }),
           let who = mention.authorHandle, !who.isEmpty {
            return Lede(text: String(localized: "\(who) mentioned you."))
        }
        // 4. The deadlines — as a SHAPE when the runway will draw one, as the
        // item itself when it won't (2026-08-13).
        //
        // It used to always name the nearest item, which on any scope with a
        // runway said the same thing three times before you scrolled: the
        // sentence ("Book dentist is overdue"), the axis label ("2 overdue")
        // and the card's own first row ("Book dentist · overdue"). One fact,
        // three tellings, in the first screen — the leads-vs-observations rule
        // this file already keeps between the observations and the leads.
        //
        // The split is the runway's own ≥2 floor, so the two can never
        // disagree about which shape is on screen: at two or more the runway
        // draws the items and the lede states what the pile IS, which is the
        // one thing the list can't say; below it there is no runway, so naming
        // the single deadline is the only telling there is. `runwayCard` is
        // told the lede took it (`statedOverdue`) and drops its own "N overdue"
        // label, since a scale marker restating the headline is the same
        // duplication one type size down.
        //
        // Both rungs read the DEDUPED set, so "Book dentist" (Reminders) and
        // "Book the dentist" (Todoist) — one errand, two apps — count once.
        let open = dedupeDeadlines(things.filter {
            $0.mark != .done && $0.dueAt != nil && !alerted.contains($0.id)
        })
        if open.count >= 2 {
            let overdue = open.filter { ($0.dueAt ?? .distantFuture) < now }.count
            let ahead = open.count - overdue
            let far = open.compactMap(\.dueAt).max() ?? now
            let by = far.formatted(.dateTime.month(.abbreviated).day())
            // Never "0 overdue" and never "and 0 more": each half is spoken
            // only when it is a real count, which is also what keeps the
            // sentence short on the common day when nothing is late.
            let text: String
            if overdue > 0 && ahead > 0 {
                text = String(localized: "\(spelledLow(overdue)) overdue, \(spelledLow(ahead)) more due by \(by).")
            } else if overdue > 0 {
                text = String(localized: "\(spelledLow(overdue)) overdue.")
            } else {
                text = String(localized: "\(spelledLow(ahead)) due by \(by).")
            }
            return Lede(text: text.prefix(1).uppercased() + text.dropFirst(),
                        statedDeadlines: true)
        }
        // Deadlines only, never calendar events — the same scoping `nextTile`
        // holds to (§101's day-planner ruling).
        if let due = dueToday(open.isEmpty ? things : open) {
            let name = clamp(due.title, max: 44)
            let stop = name.hasSuffix("…") ? "" : "."
            return Lede(text: (due.dueAt ?? .now) < .now
                ? String(localized: "\(name) is overdue\(stop)")
                : String(localized: "\(name) is due today\(stop)"))
        }
        return Lede()
    }

    /// One errand, one row — the same task tracked in two apps counted once
    /// (2026-08-13, seen on the sim: "Book dentist" from Reminders and "Book
    /// the dentist" from Todoist, side by side in Life's "Coming up").
    ///
    /// The match is deliberately STRICT: identical titles once articles and
    /// punctuation are removed, AND due dates within a week of each other. A
    /// looser rule (fuzzy titles, or no date window) would merge two genuinely
    /// different things and silently drop a deadline, which is far worse than
    /// showing one twice — this brief is where someone finds out what is late.
    /// The survivor is the one due SOONEST, so the earlier clock is never lost.
    ///
    /// Ordering is preserved: the caller's sort still decides what leads.
    private static func dedupeDeadlines(_ things: [Thing]) -> [Thing] {
        let window: TimeInterval = 7 * 86_400
        var kept: [Thing] = []
        for thing in things.sorted(by: { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }) {
            let key = deadlineKey(thing.title)
            guard !key.isEmpty else { kept.append(thing); continue }
            let twin = kept.first {
                deadlineKey($0.title) == key
                    && abs(($0.dueAt ?? .distantPast).timeIntervalSince(thing.dueAt ?? .distantFuture)) <= window
            }
            if twin == nil { kept.append(thing) }
        }
        return kept
    }

    /// A task title reduced to the words that identify it: lowercased, stripped
    /// of everything but letters and digits, with the English articles dropped.
    /// Short enough to be conservative — two titles collide only when they are
    /// the same words in the same order.
    private static func deadlineKey(_ title: String) -> String {
        let words = title.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !["the", "a", "an", "my"].contains($0) }
        return words.joined()
    }

    /// 1 → "one", through nine, then numerals — `spelled`'s twin for the counts
    /// that can legitimately be one or two (`spelled` starts at three because
    /// its own sentence, a multi-day streak, cannot).
    private static func spelledLow(_ n: Int) -> String {
        let words = [1: String(localized: "one"), 2: String(localized: "two")]
        return words[n] ?? spelled(n)
    }

    /// The lede's three facts, named rather than positional. `text` and
    /// `symbol` are both plain Strings, so a positional tuple built at four
    /// separate rungs could transpose them and still compile — the one place
    /// in this file where the compiler couldn't catch a copy-paste slip.
    /// `symbol` is the holding the sentence credited, carried out for the
    /// ledger; `tookRisk` tells the synthesis card whether the money's
    /// attribution still needs a seat.
    ///
    /// `figure`/`direction` are the ACCENT pair (2026-07-31): the exact
    /// substring of `text` that is the day's number, and which way it went.
    /// The renderer colors that run and nothing else. Carried as the literal
    /// substring rather than as a number the view would re-format, so the
    /// coloring can never disagree with the words — and so a localized
    /// sentence needs no parsing rule of its own. Empty `figure` means no
    /// accent, which is every rung but the money one: a health factor, a
    /// handle and a deadline are not gains or losses.
    struct Lede {
        var text = ""
        var symbol = ""
        var tookRisk = false
        var figure = ""
        var direction = ""
        /// The sentence is the deadline AGGREGATE (2026-08-13) — so the runway
        /// below it drops its own "N overdue" scale label rather than saying it
        /// twice. Set on that rung alone; every other rung leaves it false and
        /// the axis labels itself exactly as it always did.
        var statedDeadlines = false
    }

    /// "Thursday, July 31" — the brief's dateline (2026-07-31), the tertiary
    /// line above the lede.
    ///
    /// The whisper capsule that opens this screen says "Your Wednesday", and
    /// until now the screen it opened never named the day anywhere. It is a
    /// fact the brief already stands on (every module here is scoped to this
    /// window), so stating it is not padding — it's the masthead the lede
    /// hangs from, and it's what makes a brief re-opened at 4pm legible as
    /// today's rather than as an answer with no date on it.
    private static func dateline(now: Date) -> String {
        now.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    /// The nearest open deadline falling inside today, overdue included — the
    /// lede's fourth rung. Nil when the next deadline is tomorrow or later:
    /// "due Thursday" is not a headline, it's the `NextTile`'s job.
    private static func dueToday(_ things: [Thing], now: Date = .now) -> Thing? {
        let calendar = Calendar.current
        return things
            .filter { $0.mark != .done }
            .filter { thing in
                guard let due = thing.dueAt else { return false }
                return due < now || calendar.isDate(due, inSameDayAs: now)
            }
            .min { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
    }

    /// 3 → "three". Spelled through nine, then numerals — a sentence in
    /// display type reads better with the word, and past nine the word is
    /// longer than the fact deserves.
    private static func spelled(_ n: Int) -> String {
        let words = [3: String(localized: "three"), 4: String(localized: "four"),
                     5: String(localized: "five"), 6: String(localized: "six"),
                     7: String(localized: "seven"), 8: String(localized: "eight"),
                     9: String(localized: "nine")]
        return words[n] ?? "\(n)"
    }

    // MARK: - The live reads

    /// A watched wallet ALWAYS earns the money hero (user ruling 2026-07-22:
    /// "if a user has a wallet, show it no matter what — it's a rich
    /// visualization, even on a steady day"). The live read is tried first; if
    /// it comes back empty because the chain was unreachable this morning
    /// (offline / rate-limited), the hero falls back to the LAST-KNOWN
    /// holdings rather than vanishing — marked "as of Xh ago" so it never
    /// claims a stale number is current (§83).
    private static func liveHoldings() async -> [WalletIngest.HoldingsGroup] {
        guard !WalletStore.shared.addresses.isEmpty else { return [] }
        let read: [WalletIngest.HoldingsGroup]? = await bounded(budget: holdingsBudget) {
            await WalletIngest.topHoldingsByWallet()
        }
        // A read that timed out and a read that came back empty are the same
        // thing to the hero — it falls to the last-known holdings either way,
        // marked "as of Xh ago" so it never claims a stale number is current.
        let live = read ?? []
        return live.isEmpty ? WalletIngest.lastKnownHoldingsByWallet() : live
    }

    private static func liveMoves(context: ModelContext) async -> [TokensAsk.Move] {
        guard !TokensAsk.watched(context).isEmpty else { return [] }
        let moves: [TokensAsk.Move]? = await bounded {
            await TokensAsk.moves(context: context)
        }
        return moves ?? []
    }

    // MARK: - The read budget (2026-08-03)

    /// The ceiling on how long the brief waits for ANY ONE live read before
    /// composing without it. A ceiling, not a target: on a network that is
    /// working, none of the three reads comes anywhere near it, so this
    /// changes nothing about a normal open.
    ///
    /// It exists because the brief's load time was, structurally, "as slow as
    /// the worst third-party host of the day." Every live read here funnels
    /// into `WalletApprovals.call`, which walks a chain's hosts SEQUENTIALLY,
    /// each with `IngestSupport`'s 15s request timeout — so one unreachable
    /// RPC host multiplied by pools × wallets is minutes, not seconds, and
    /// the whole document is composed atomically, so nothing paints until the
    /// slowest of them returns. There was no bound anywhere on that path.
    ///
    /// Timing out is HONEST here, and that is what makes the bound safe rather
    /// than a shortcut: every module this feeds is already nil-able and
    /// already degrades by simply not being there. The hero falls to
    /// last-known holdings (labelled stale, §83); no movers means no movers
    /// tile; and the lede's risk rung yields to the next rung, exactly as it
    /// does on the overwhelming majority of days when nothing is at risk.
    /// Nothing is padded to fill a slot and nothing claims a number it didn't
    /// read — the brief's own module doctrine, applied to arrival time.
    ///
    /// The risk rung specifically is not LOST by a timeout, only this
    /// sentence about it: `WalletDeFi.sync` and `MorphoDeFi` land a thing on a
    /// new crossing into risk during `WalletIngest.refresh`, and the Wallet
    /// room states health per protocol. This is the convenience surfacing of a
    /// fact that lives in three other places.
    ///
    /// 8s → 2.5s → 5s, and the round trip is the point (2026-08-11/12).
    ///
    /// Eight seconds was a ceiling on a pathological case — an unreachable RPC
    /// host, where the alternative was minutes — and never a number anyone
    /// should WAIT. It became the chip's latency because the document composed
    /// atomically: nothing painted until the slowest concurrent read returned
    /// or gave up. So it was cut to 2.5s, which bought speed by giving up
    /// content — the movers tile and the lede's risk rung, whenever a read ran
    /// long.
    ///
    /// `onPartial` removed that trade. The corpus half now paints in ~64ms on
    /// a 12,000-row corpus (measured) and the complete document replaces it,
    /// so a live read no longer costs BLANK time — only how late its own
    /// module arrives on a page already being read. That makes a generous
    /// budget the right default again, and 2.5s the wrong one: it was
    /// discarding readings that a slow network would have delivered.
    ///
    /// 5s rather than back to 8s: the cost has changed shape, not vanished. A
    /// module inserting itself eight seconds after you started reading is its
    /// own kind of wrong, and the measured reads (`risk` at 1.3–1.6s) sit far
    /// enough under this that only a genuinely bad network reaches it.
    ///
    /// Losing the race still costs nothing false: every module here is
    /// nil-able and degrades by simply not being there, and the risk rung in
    /// particular is the convenience surfacing of a fact stated three other
    /// places (above).
    ///
    /// What it does NOT change: the loser is not cancelled (see `bounded`), so
    /// it still runs to completion and warms `WalletDeFi`/`MorphoDeFi`'s 60s
    /// coalescing caches — a read that misses the budget on the first tap is
    /// usually free on the second.
    private static let liveReadBudget: TimeInterval = 5

    /// The HOLDINGS read gets a much tighter ceiling than the other two
    /// (2026-08-04, user: "a bit of latency opening the daily brief… like 3
    /// seconds before it starts to fill"). Measured on the sim at the time:
    /// `holdings=7598ms`, with `moves` and `risk` both at 0 — so this one read
    /// WAS the brief's open latency, and the document composes atomically, so
    /// nothing painted until it returned.
    ///
    /// Two seconds is safe here in a way it wouldn't be for the risk rung,
    /// because losing this race costs almost nothing: the hero falls to
    /// `lastKnownHoldingsByWallet()` — recorded samples, instant, carrying its
    /// own treemap cells — and says "as of Xh ago" (§83). That fallback was
    /// already ruled honest enough to ship; it was simply reserved for a read
    /// that FAILED rather than one that was merely slow. Every animation the
    /// hero owns (the rolling total, the drawing sparkline, the staggering
    /// cells, the delta pill) reads recorded history or those cells, so none
    /// of the delight depends on winning this race.
    ///
    /// And `bounded` never cancels the loser: the read runs to completion and
    /// warms `HoldingsCache`, so the next open inside its 10-minute window
    /// (§216) reads fresh and free. Stale-while-revalidate, not a lost read.
    private static let holdingsBudget: TimeInterval = 2

    /// `read`'s answer, or nil if it hasn't arrived within `budget`.
    ///
    /// The read is started UNSTRUCTURED on purpose: losing the race must not
    /// cancel it. It shares `WalletDeFi`/`MorphoDeFi`'s 60s coalescing caches
    /// with the Wallet room and `WalletWarnings`, so cancelling mid-flight
    /// would hand a nil to whichever of them happened to be waiting on the
    /// same primitive — and `CoalescingCache` awaits an unstructured task
    /// itself, so a cancel wouldn't even land promptly. Letting the loser run
    /// to completion costs nothing and warms that cache, so the next open (or
    /// the Wallet screen a moment later) reads it free.
    private static func bounded<Value>(
        budget: TimeInterval? = nil,
        _ read: @escaping () async -> Value?
    ) async -> Value? {
        let budget = budget ?? liveReadBudget
        let gate = FirstArrival<Value>()
        Task {
            let value = await read()
            await gate.settle(value)
        }
        Task {
            try? await Task.sleep(for: .seconds(budget))
            await gate.settle(nil)
        }
        return await gate.wait()
    }

    /// The worst borrow across both lending protocols, and only when it has
    /// actually crossed the risk floor. Both the threshold and the read live
    /// in `DeFiRisk`, so this can't call a position dangerous on a screen
    /// where the Wallet room calls it fine. Reads nothing when no EVM wallet
    /// is watched.
    /// Bounded like the other two live reads (2026-08-03), and it is the one
    /// that most needed it: `DeFiRisk.atRisk` walks `WalletDeFi.positions`,
    /// which is a call per (pool, wallet) — six pools against five watched
    /// wallets is thirty `eth_call`s. Those now run concurrently per network
    /// (see `WalletDeFi.positions`), which fixes the sum but not the tail: one
    /// dead RPC host still spends 15s a call. See `liveReadBudget` for why
    /// yielding the rung is honest rather than a silent loss.
    private static func worstDebt() async -> DeFiRisk.Debt? {
        let watched = WalletStore.shared.addresses.map(\.address)
        guard !watched.isEmpty else { return nil }
        let addresses = await WalletIngest.resolvedAddresses(watched).filter { ENS.isHexAddress($0) }
        guard !addresses.isEmpty else { return nil }
        return await bounded { await DeFiRisk.atRisk(addresses: addresses) }
    }

    // MARK: - The joins (§214)

    /// A token that moved today which is ALSO what the corpus has been reading
    /// about — the observation neither a portfolio tracker nor a feed reader
    /// can make alone, because each holds only one half.
    ///
    /// It names the read rather than counting the reads: "in 3 of your saves
    /// this week" is a tally, and §213 outlawed those. The count still does
    /// the work — two independent reads before a symbol qualifies — it just
    /// never reaches the sentence.
    private static func marketReadingEcho(moves: [TokensAsk.Move], things: [Thing],
                                          now: Date) -> Note? {
        guard !moves.isEmpty else { return nil }
        let horizon = now.addingTimeInterval(-7 * 86_400)
        let recent = reads(things.filter { $0.capturedAt >= horizon })
        guard recent.count >= 2 else { return nil }
        // Each title is split and lowercased ONCE, up front. Testing every
        // symbol against every title instead re-tokenized the same title per
        // move — watched tokens times a week of reading, all of it thrown
        // away immediately.
        let tokenized = recent.map { (thing: $0, words: Set(words(of: $0.title).map { $0.lowercased() })) }
        for move in moves.sorted(by: { abs($0.change) > abs($1.change) }) {
            // Two letters is not a symbol, it's a syllable — "AI" or "ID"
            // would match half the headlines ever written.
            guard move.symbol.count >= 3 else { continue }
            let needle = move.symbol.lowercased()
            let hits = tokenized.filter { $0.words.contains(needle) }.map(\.thing)
            guard hits.count >= 2, let lead = hits.first else { continue }
            return Note(glyph: "arrow.triangle.merge",
                        text: String(localized:
                            "\(move.symbol) is \(TokenChartStyle.changeText(move.change)) today — and it's what you've been reading: \(clamp(lead.title, max: 52))"),
                        thingID: lead.id.uuidString)
        }
        return nil
    }

    /// A title's words — maximal runs of letters and digits, original casing
    /// kept so a caller that DISPLAYS one (`dominantTopic`) doesn't have to
    /// re-derive it. One definition of what a word is, shared by the topic
    /// count and the symbol match, which had spelled the same rule twice.
    private static func words(of title: String) -> [String] {
        title.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }

    /// One person turning up in several sources at once — the corpus noticing
    /// that a handle in your mail is the handle in your feed.
    ///
    /// Handles compare EXACTLY (lowercased, a leading `@` dropped) and never
    /// fuzzily: the networks share no identity system, so "mara" on Bluesky
    /// and "mara" on Farcaster may be two people. The claim we can keep is
    /// only that the same spelling appeared twice — so the line says where it
    /// appeared and lets the person judge, rather than asserting they're one.
    private static func personEcho(_ landed: [Thing]) -> Note? {
        var seen: [String: (handle: String, sources: [String], thing: Thing)] = [:]
        for thing in landed {
            let raw = (thing.authorHandle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { continue }
            var key = raw.lowercased()
            if key.hasPrefix("@") { key.removeFirst() }
            guard key.count >= 3 else { continue }
            if var entry = seen[key] {
                if !entry.sources.contains(thing.source) { entry.sources.append(thing.source) }
                seen[key] = entry
            } else {
                seen[key] = (raw, [thing.source], thing)
            }
        }
        // Sorted by handle before the max, so a tie (two people in two sources
        // each — the common shape) names the same person on every rise: a
        // Dictionary's iteration order is seeded per process, so `max` alone
        // let the brief change its mind about who "turns up everywhere" when
        // nothing about the day had changed. Same defect `dominantTopic` had.
        guard let best = seen.values
            .filter({ $0.sources.count >= 2 })
            .sorted(by: { $0.handle.lowercased() < $1.handle.lowercased() })
            .max(by: { $0.sources.count < $1.sources.count })
        else { return nil }
        return Note(glyph: "person.2",
                    text: String(localized:
                        "\(best.handle) turns up in \(list(best.sources)) today."),
                    thingID: best.thing.id.uuidString)
    }

    /// "Bluesky and Mail" / "Bluesky, Farcaster and Mail" — a sentence, never
    /// a count, capped at three so it stays one.
    private static func list(_ names: [String]) -> String {
        let shown = Array(names.prefix(3))
        switch shown.count {
        case 0:  return ""
        case 1:  return shown[0]
        case 2:  return String(localized: "\(shown[0]) and \(shown[1])")
        default: return String(localized: "\(shown[0]), \(shown[1]) and \(shown[2])")
        }
    }

    /// How both leads pick when several things qualify (§214): something this
    /// window hasn't already led with first, then the sources you actually
    /// visit (`ChipMemory`'s existing tap-learned weights — the same counters
    /// that order the source strip), then the caller's own order, which is
    /// newest-first everywhere this is called.
    ///
    /// Prefer-then-fall-back, never drop: if EVERY candidate has already been
    /// shown this window, the lead still draws. A brief that empties a card on
    /// a revisit reads as a bug, and there is genuinely nothing newer to say.
    /// The enumerated offset makes this a total order — `sorted` is not
    /// documented stable, so ties would otherwise shuffle between rises.
    private static func ranked(_ candidates: [Thing], told: Set<String>,
                               weights: ChipMemory.Weights)
        -> [Thing] {
        candidates.enumerated().sorted { a, b in
            let aTold = told.contains(a.element.id.uuidString)
            let bTold = told.contains(b.element.id.uuidString)
            if aTold != bTold { return !aTold }
            let aWeight = ChipMemory.weight(for: a.element.source,
                                            counts: weights.counts, lastVisit: weights.lastVisit)
            let bWeight = ChipMemory.weight(for: b.element.source,
                                            counts: weights.counts, lastVisit: weights.lastVisit)
            if aWeight != bWeight { return aWeight > bWeight }
            return a.offset < b.offset
        }.map(\.element)
    }

    // MARK: - The pair

    /// `MoversTile(label, "SYM|+4.2%|close,close,…;…")` — the watchlist at a
    /// glance. Real direction gets real color here (unlike `StatRow`'s
    /// neutral counts): a price move HAS a sign. A move that rounds to flat
    /// says "flat" and takes no color, per §83. Rows join on ";" (not ",")
    /// because each row's own closes are themselves comma-joined — the
    /// candidate B delight (2026-07-23, user: "add A and B those are both
    /// good components to have"): each row DRAWS its move instead of only
    /// stating it, reusing `TokenPulse`'s already-cached closes so the row
    /// costs nothing extra to fetch.
    private static func moversTile(_ moves: [TokensAsk.Move]) -> String? {
        guard !moves.isEmpty else { return nil }
        let rows = moves
            .sorted { abs($0.change) > abs($1.change) }
            .prefix(3)
            .map { m -> String in
                let pct = m.change * 100
                let value = abs(pct) < 0.05
                    ? String(localized: "flat")
                    : String(format: "%+.1f%%", pct)
                // Up to 20 recent closes — a legible tiny shape without
                // bloating the doc line; read straight off `TokenPulse`'s
                // cache (already warm from `moves(context:)`'s own refresh
                // moments ago) rather than `Move` carrying a second copy.
                let closes = (TokenPulse.shared.pulse(for: m.thing)?.closes ?? [])
                    .suffix(20).map { String(format: "%.4g", $0) }.joined(separator: ",")
                // The thing's own id, so the row can open it (§225, user: "how
                // would you improve the daily brief... in terms of UI and UX
                // and capacity" — a watchlist row was the one module in the
                // brief with no tap at all).
                return "\(tileSafe(m.symbol))|\(value)|\(closes)|\(m.thing.id.uuidString)"
            }
        return "tmov = MoversTile(\"\(String(localized: "Watchlist"))\", \"\(rows.joined(separator: ";"))\")"
    }

    /// `WalletFlow(windowLabel, "side|name|usd|count|other;…", inUSD, outUSD,
    /// unpriced, spineAddress)` — where the money moved (§232).
    ///
    /// **The window is a WEEK, not the brief's own.** Every other module here
    /// reads `DayBrief.windowStart` (since you last looked), and that is the
    /// wrong span for this one specifically: a band needs two surviving lanes
    /// and half its moves priced, and a since-you-last-looked window on an
    /// ordinary day holds nought or one transfer — so scoped that way the card
    /// would decline nearly every day and read as broken rather than absent.
    /// A week is the room's own default (`WalletRange.week`), and the label is
    /// that enum's own wording, so the two screens can never name the same
    /// period differently.
    ///
    /// **Nothing is gated here.** `WalletFlow.band` already declines on an
    /// unpriceable window, on fewer than two lanes, and on lanes too thin to
    /// draw honestly — re-deciding any of that in the composer would be a
    /// second opinion that could disagree with the room's.
    ///
    /// The band arrives as VALUES (`WalletFlowSource` reduced the things at
    /// the boundary), so serialising it here costs nothing and keeps the
    /// renderer free of any `Thing` — which is what makes this module immune
    /// to the liveness crash class rather than merely guarded against it.
    private static func flowBand(_ things: [Thing]) -> String? {
        guard let span = WalletRange.week.span,
              let band = WalletFlowSource.band(from: things,
                                               since: Date.now.addingTimeInterval(-span))
        else { return nil }
        let lanes = (band.inLanes.map { ("in", $0) } + band.outLanes.map { ("out", $0) })
            .map { side, lane in
                "\(side)|\(tileSafe(lane.name))|\(String(format: "%.2f", lane.usd))|\(lane.count)|\(lane.isOther ? 1 : 0)"
            }
        // The spine wears a face only when one wallet is unambiguously the
        // subject — the room's own rule (a face belonging to one of several
        // merged wallets would claim the flows were that wallet's).
        let watched = WalletStore.shared.addresses
        let spine = watched.count == 1 ? (watched.first?.address ?? "") : ""
        return "flow = WalletFlow(\"\(genSafe(WalletRange.week.flowLabel))\", \"\(lanes.joined(separator: ";"))\", \"\(String(format: "%.2f", band.inUSD))\", \"\(String(format: "%.2f", band.outUSD))\", \"\(band.unpricedCount)\", \"\(spine)\")"
    }

    /// `NextTile(label, title, when, alert, thingID)` — the nearest real
    /// DEADLINE, plus the overdue tail as its alert line.
    ///
    /// Deadlines only, never calendar events: an event's start rides
    /// `capturedAt`, and folding those in here would rebuild exactly the
    /// day-planner lane §101 cut ("a person who sees their whole day in
    /// Casberi stops opening their calendar"). Same scoping the `upcoming`
    /// composer already holds to.
    /// A watched market that BECAME A FACT today (2026-07-28) — the one
    /// prediction-market shape that belongs in this brief without arguing
    /// with the module doctrine. A market's odds are a STATE (the feed row
    /// carries those, §216); a market RESOLVING is an EVENT, and the only
    /// thing in the corpus that turns a probability into an answer. It also
    /// carries what nothing else can: the odds the day you started watching.
    ///
    /// Never a count of markets, never "3 markets moved" — that's the tally
    /// this file's header forbids. One resolution, or nothing.
    private static func marketResolvedToday(_ markets: [MarketsAsk.Move], now: Date) -> String? {
        let cal = Calendar.current
        guard let just = markets.first(where: { m in
            m.resolved && m.yesWon != nil && cal.isDate(m.thing.capturedAt, inSameDayAs: now) == false
                && (m.thing.dueAt.map { cal.isDate($0, inSameDayAs: now) } ?? false)
        }) ?? markets.first(where: { $0.resolved && $0.yesWon != nil }) else { return nil }
        // A Row, not a tile: this IS the thing itself (one of the four shapes
        // the doctrine allows), so it opens to the market it names. The
        // trailing slot carries the answer — the whole point of the module.
        let answer = just.yesWon == true ? String(localized: "Yes") : String(localized: "No")
        return "tmkt = Row(\"\(tileSafe(just.thing.title))\", \"\(just.thing.kind.typeTag)\", \"\(just.thing.source)\", \"\(answer)\", \"\(just.thing.id.uuidString)\")"
    }

    private static func nextTile(_ things: [Thing], excluding alerted: Set<UUID> = []) -> String? {
        // Same exclusion the runway takes, and for the same reason — this is
        // the degrade path below the runway's ≥2 floor, so without it a lone
        // dispute would be the alarm AND "Up next" (2026-08-10).
        // Deduped like the runway's own set — this is that card's degrade path,
        // so "Book dentist" and "Book the dentist" must not become "Up next"
        // plus "1 more overdue" (2026-08-13).
        let open = dedupeDeadlines(things.filter {
            $0.mark != .done && $0.dueAt != nil && !alerted.contains($0.id)
        })
        let ahead = open.filter { ($0.dueAt ?? .distantPast) >= .now }
            .sorted { ($0.dueAt ?? .now) < ($1.dueAt ?? .now) }
        let overdue = open.filter { ($0.dueAt ?? .distantFuture) < .now }
        guard let next = ahead.first ?? overdue.first else { return nil }
        let when = (next.dueAt ?? .now).formatted(.dateTime.weekday(.abbreviated).hour().minute())
        var alert = ""
        if !overdue.isEmpty {
            if overdue.count == 1, overdue[0].id == next.id {
                alert = String(localized: "overdue")
            } else {
                let late = overdue.filter { $0.id != next.id }
                if late.count == 1 {
                    alert = String(localized: "\(clamp(late[0].title, max: 28)) is late")
                } else if late.count > 1 {
                    alert = String(localized: "\(late.count) more overdue")
                }
            }
        }
        return "tnext = NextTile(\"\(String(localized: "Up next"))\", \"\(genSafe(clamp(next.title, max: 40)))\", \"\(genSafe(when))\", \"\(genSafe(alert))\", \"\(next.id.uuidString)\")"
    }

    /// The ALERTS callout (user, 2026-08-10: "we have things that qualify as
    /// alerts like disputes … they should be shown as their own thing as a
    /// call out in some way b/c they are more important") — the things in this
    /// window that want something from you, above everything that merely
    /// reports.
    ///
    /// Membership is `NotifySweep.classify` + `.alarm`, NOT a judgement made
    /// here. That reuse is the point: the app already decides what is worth
    /// interrupting someone for, mechanically, under `notify-selftest.sh`'s 79
    /// assertions — so the callout and the lock screen cannot drift into
    /// disagreeing about whether a dispute is urgent. A second rule set here
    /// would be a second opinion, and the one that got edited less often would
    /// quietly become wrong.
    ///
    /// Deliberately does NOT consult `NotifyLedger`: that ledger answers "have
    /// we already BUZZED about this", which is the right question for a
    /// notification and the wrong one for a screen. A dispute you were
    /// notified about on Tuesday is still your most important open item on
    /// Wednesday — suppressing it here would hide the alert precisely because
    /// it was important enough to announce.
    ///
    /// Scoped by the caller's own Stage-1 filter (`things` is already this
    /// scope's), so Money shows disputes and approvals, Work shows rejections
    /// and failed runs, Life shows its own deadlines — each from the same
    /// classifier, with no per-scope alert table to keep in sync.
    ///
    /// NO floor, unlike every other module here: one alert is not "a spread
    /// too thin to draw", it is one thing that wants you. The ≥2 rule the
    /// runway keeps is about whether a SHAPE is legible; this module has no
    /// shape to be illegible.
    /// "What happened to your posts" as doc lines — a `Widget` of `Row`s,
    /// likes first (the rarest and warmest read), then replies, then new
    /// followers, capped at four. Every row opens a real thing except the
    /// like roll's, which opens the POST it names. nil when the window holds
    /// none of it — most days, for most people, and correct.
    @MainActor
    private static func yourPostsCard(_ things: [Thing], windowStart: Date) -> [String]? {
        var rows: [String] = []
        var refs: [String] = []
        func add(_ line: String) {
            let id = "pr\(refs.count)"
            refs.append(id)
            rows.append("\(id) = \(line)")
        }
        // The newest like roll inside the window, joined back to its post so
        // the row can open it and quote it. `SocialLikers` keys rolls by the
        // post's own sourceRef.
        let byRef = Dictionary(grouping: things.filter { $0.isLive }, by: { $0.sourceRef ?? "" })
        let roll = SocialLikers.shared.rolls
            .filter { $0.value.when >= windowStart }
            .sorted { $0.value.when > $1.value.when }
            .compactMap { entry -> (SocialLikeRoll, Thing)? in
                guard let post = byRef[entry.key]?.first, entry.value.line != nil
                else { return nil }
                return (entry.value, post)
            }
            .first
        if let (r, post) = roll, let line = r.line {
            add("Row(\"\(genSafe(line))\", \"\(post.kind.typeTag)\", \"\(post.source)\", \"\(genSafe(shortTime(r.when)))\", \"\(post.id.uuidString)\", \"\", \"\(genSafe(clamp(post.title, max: 60)))\")")
        }
        // Replies and follows the inbound reads landed in the window —
        // `socialContext` is stamped by `SocialInbound` alone, so membership
        // can't drift into ordinary posts.
        let inbound = things
            .filter {
                $0.isLive && $0.capturedAt >= windowStart
                    && ($0.socialContext == "reply" || $0.socialContext == "follow")
            }
            .sorted { $0.capturedAt > $1.capturedAt }
        for t in inbound.prefix(4 - refs.count) {
            add("Row(\"\(genSafe(clamp(t.title, max: 60)))\", \"\(t.kind.typeTag)\", \"\(t.source)\", \"\(genSafe(shortTime(t.capturedAt)))\", \"\(t.id.uuidString)\", \"\", \"\(genSafe(t.socialContext == "reply" ? String(localized: "Replied to you") : String(localized: "Followed you")))\")")
        }
        guard !refs.isEmpty else { return nil }
        return ["posts = Widget(\"\(String(localized: "Your posts"))\", \"\", [\(refs.joined(separator: ", "))])"]
            + rows
    }

    /// `ClusterMap` over the corpus's stored embeddings (prd §386j).
    ///
    /// The projection runs OFF the main actor — it is power iteration over
    /// N × 512 and `Composer.buildPanel` already learned that lesson the hard
    /// way (measured at 521 of 707 samples there). The fetch is bounded and
    /// the entries are value types, so no `Thing` crosses the suspension.
    ///
    /// Cluster names are the terms actually present, upgraded to friendlier
    /// names by `ClusterNames` when the librarian has gotten to them — never
    /// awaited here, so a device without Apple Intelligence and a device that
    /// simply hasn't named them yet both draw the same honest map.
    /// The last projection, keyed by a cheap corpus signature (prd §386k).
    ///
    /// Measured the day the module shipped: the PCA cost ~1,800ms per compose
    /// in Debug — 99% of the whole brief — for a projection whose INPUT barely
    /// moves within a day (embeddings are written by the backfill sweep, a few
    /// rows per foreground). `HomeInsightStore`'s signature discipline: the
    /// newest embedded row's id + the embedded count identify the input, a
    /// matching signature returns the cached doc line in ~0ms, and a corpus
    /// that actually moved recomputes. In-memory only — a projection is
    /// seconds to rebuild after a relaunch and stale cache on disk would
    /// outlive the rows it plots.
    @MainActor private static var mapCache: (signature: String, line: String?)?

    /// The doc last shown to a person this session (prd §386k) — painted
    /// instantly on the next rise while the fresh compose runs. In-memory
    /// only, written beside `recordModuleDigests` under the same guards.
    @MainActor static var lastPresentedDoc: [String]?

    private static func clusterMap(context: ModelContext) async -> String? {
        var fd = FetchDescriptor<Thing>(
            predicate: #Predicate { $0.embedding != nil },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        fd.fetchLimit = 600
        guard let rows = try? context.fetch(fd) else { return nil }
        let live = rows.filter { $0.isLive && !Corpus.isImportReceipt($0) }.prefix(300)
        let signature = "\(live.count)|\(live.first?.id.uuidString ?? "")"
        if let cached = mapCache, cached.signature == signature {
            return cached.line
        }
        let entries: [AgentPanelFigures.Entry] = live
            .compactMap { thing in
                guard let packed = thing.embedding,
                      let vector = EmbeddingIndex.unpack(packed) else { return nil }
                return AgentPanelFigures.Entry(source: thing.source, at: thing.capturedAt,
                                               terms: thing.ocrTopics + thing.tags,
                                               vector: vector)
            }
        guard entries.count >= 12 else {
            mapCache = (signature, nil)
            return nil
        }
        let map = await Task.detached(priority: .userInitiated) {
            AgentPanelFigures.scatter(entries)
        }.value
        guard !map.dots.isEmpty, map.clusters.count >= 2 else {
            mapCache = (signature, nil)
            return nil
        }
        let dots = map.dots.map {
            "\(String(format: "%.4f", $0.x))|\(String(format: "%.4f", $0.y))|\(tileSafe($0.source))"
        }
        let named = ClusterNames.shared
        // Tell the librarian what to name next — recorded here, named on the
        // foreground sweep, never awaited by this compose (prd §386m).
        named.note(terms: map.clusters.map(\.label))
        let clusters = map.clusters.map { c in
            "\(tileSafe(named.name(for: c.label)))|\(String(format: "%.4f", c.x))|\(String(format: "%.4f", c.y))|\(String(format: "%.4f", c.radius))"
        }
        // The subtitle is the map's own instruction — the figure is unusual
        // enough that "things that sit close are about the same thing" is
        // information, not decoration (§386i's own naming ruling).
        // The card carries its own title again (prd §386l): the map moved
        // INTO "Your day", so the header no longer says this and §386g's
        // header-owns-the-name rule hands the name back.
        let line = "map = ClusterMap(\"\(String(localized: "What goes together"))\", \"\(String(localized: "things that sit close are about the same thing"))\", \"\(dots.joined(separator: ";"))\", \"\(clusters.joined(separator: ";"))\")"
        mapCache = (signature, line)
        return line
    }

    /// Stripe's and Cloudflare's deadlines on ONE axis (prd §386m).
    ///
    /// Merged rather than drawn twice: two rails stacked in a section is the
    /// duplication this pass keeps removing, and a dispute deadline and a
    /// certificate expiry genuinely share a scale — both are "days until
    /// somebody needs something from you". Each keeps its own source on the
    /// dot so the axis can still say WHOSE deadline is which.
    @MainActor
    private static func shippingRunway(_ things: [Thing]) -> String? {
        let now = Date.now
        var lanes: [(at: Date, source: String)] = []
        if let stripe = StripeRoomSource.compose(things: things) {
            for item in stripe.items {
                lanes.append((now.addingTimeInterval(Double(item.days) * 86_400), "Stripe"))
            }
        }
        if let cf = CloudflareRunwaySource.compose(things: things) {
            // A certificate with no published expiry has no place on an axis
            // — dropped rather than pinned somewhere invented.
            for item in cf.items where item.days != nil {
                lanes.append((now.addingTimeInterval(Double(item.days ?? 0) * 86_400), "Cloudflare"))
            }
        }
        guard lanes.count >= 2 else { return nil }
        let sorted = lanes.sorted { $0.at < $1.at }
        let rows = sorted.map { "\(Int($0.at.timeIntervalSince1970))|\(genSafe($0.source))" }
        let far = (sorted.last?.at ?? now).formatted(.dateTime.month(.abbreviated).day())
        return "ship = Runway(\"\(String(localized: "What's due"))\", \"\(rows.joined(separator: ";"))\", \"\(Int(now.timeIntervalSince1970))\", \"\(String(localized: "now"))\", \"\(genSafe(far))\")"
    }

    /// GitHub's contribution calendar as a `Bars` strip of the last 12 weeks
    /// (prd §386j). The full 53-week grid is the room's own hero; at brief
    /// scale a year is ~2.7pt cells, which is the same reasoning the panel's
    /// pulse tile already applies to its own window.
    @MainActor
    private static func githubCalendar() -> String? {
        guard let year = GitHubGraphStore.shared.year else { return nil }
        let weeks = year.weeks.suffix(12)
        guard weeks.count >= 6 else { return nil }
        let counts = weeks.map { week in week.days.reduce(0) { $0 + $1.count } }
        guard counts.contains(where: { $0 > 0 }) else { return nil }
        let labels = counts.indices.map { _ in "" }
        return "ghgraph = Bars(\"\(String(localized: "What you shipped"))\", \"\(String(localized: "the last 12 weeks"))\", \"\(counts.map(String.init).joined(separator: ","))\", \"\(labels.joined(separator: ","))\")"
    }

    /// The holdings treemap, drawn from the newest RECORDED sample rather
    /// than from a live read (prd §386h).
    ///
    /// `WalletStore.ValueSample.holdings` snapshots symbol → USD every time a
    /// sample is written, precisely so the combined sheet can attribute a
    /// move — which means the composition is already on disk and the hero's
    /// map does not actually need the network. Declines under two symbols
    /// (one cell is a title, not a map) and on samples written before that
    /// field existed.
    ///
    /// `iconMode` "token" so each cell wears its bundled coin mark, the same
    /// as the hero's own map — and the cells carry a `@t:` route only in the
    /// hero, which reads live prices; here they are labels over a snapshot,
    /// so the map states composition and offers no per-token chart it cannot
    /// currently price.
    @MainActor
    private static func holdingsMapFromHistory() -> String? {
        let store = WalletStore.shared
        guard !store.addresses.isEmpty else { return nil }
        // MERGED PER ADDRESS, never through `combinedValueSamples()` — that
        // function builds `ValueSample(at:usd:)` with no `holdings` at all,
        // so it drops the composition on the way to the total. Reading the
        // map through it meant the map could never draw for anyone watching
        // more than one wallet, which is silent: an absent module and a
        // module that declined look identical (found on the sim, prd §386h).
        var merged: [String: Double] = [:]
        var asOfDate: Date?
        for address in store.addresses {
            guard let newest = store.valueSamples(forAddress: address.address).last,
                  let holdings = newest.holdings else { continue }
            for (symbol, usd) in holdings where usd > 0 {
                merged[symbol, default: 0] += usd
            }
            // The map is "as of" the OLDEST of the wallets' newest samples —
            // the moment every figure in it was true together, which is the
            // only honest stamp for a merged snapshot.
            asOfDate = min(asOfDate ?? newest.at, newest.at)
        }
        let ranked = merged
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
        guard ranked.count >= 2, let stampedAt = asOfDate else { return nil }
        // `treemapWeight`'s sqrt scaling, the same the hero's map uses — a
        // wallet that is 95% one coin otherwise draws one cell and a seam.
        let cells = ranked.prefix(6).map { entry -> String in
            "\(tileSafe(entry.key)) \(WalletIngest.treemapWeight(entry.value))"
        }
        let asOf = stampedAt.formatted(.dateTime.month(.abbreviated).day())
        return "holdmap = TagMap(\"\(String(localized: "What you hold"))\", \"\(String(localized: "as of \(asOf)"))\", [\(cells.joined(separator: ", "))], \"token\")"
    }

    /// `Bars` of merchant share — where the card money actually went (prd
    /// §386g). Reads `AppleWalletRoom`'s own composer, so the brief and the
    /// room can never disagree about who is biggest; `share` is already the
    /// fraction of settled spend, so nothing is re-derived here.
    @MainActor
    private static func spendBars(_ things: [Thing]) -> String? {
        let spends = AppleWalletRoomSource.spends(from: things)
        guard let card = AppleWalletRoom.compose(spends: spends, now: .now),
              !card.merchants.isEmpty else { return nil }
        // `AllocBar`, NOT `Bars` (measured on the sim, prd §386g): `Bars`
        // draws each column as a `Capsule`, which rounds to half its SHORTER
        // side — right for the 24 narrow hour-bars and the 7-day recap it was
        // built for, and at four columns across a phone it renders the tallest
        // merchant as a filled circle and the shortest as a hairline. Share of
        // a whole is a segmented bar's question anyway, which is what
        // `AllocBar` already is.
        let shown = card.merchants.prefix(4)
        // `,` and `|` are this grammar's two separators — a merchant name
        // carrying either would shear the line (the `allocSafe` rule).
        let segs = shown.map { m -> String in
            let name = tileSafe(m.name)
            return "\(name)|\(m.share)"
        }
        return "spend = AllocBar(\"\(String(localized: "Where you spend"))\", \"\(segs.joined(separator: ","))\")"
    }

    /// The busiest watched product metric as its own curve (prd §386g) —
    /// `ValueSpark`, the same component the wallet's balance line uses, so a
    /// metric and a balance read as the same KIND of fact drawn twice, which
    /// is what they are. Declines under three readings (a two-point line is a
    /// slope, not a curve).
    @MainActor
    private static func workCurve() -> String? {
        let metrics = PostHogState.all()
        guard let busiest = metrics
            .filter({ $0.value.series.count >= 3 })
            .max(by: { $0.value.total < $1.value.total })
        else { return nil }
        let csv = busiest.value.series.map(String.init).joined(separator: ",")
        return "work = ValueSpark(\"\(tileSafe(busiest.key))\", \"\", \"\(csv)\")"
    }

    /// `DayFold(shots, faces, marks, subline)` — the day's pictures, people
    /// and rooms as ONE card (prd §386g). Each third is optional and the card
    /// declines only when all three are empty, so a day with photographs and
    /// nobody in them still draws.
    ///
    /// Every remainder is COUNTED into the subline rather than dropped: the
    /// pictures beyond four, the people beyond four, the rooms beyond three.
    /// The three cards this replaces each carried their own residual line and
    /// losing them would be exactly the silent truncation §307 ruled against.
    @MainActor
    /// How many distinct PEOPLE the day's things name — the monument's
    /// bottom rung (2026-08-16), counted through `SocialThread.hasContext`,
    /// the app's own answer to "does this source name a human", which is the
    /// same gate `dayFold` and `faces` use. One definition, so the monument
    /// and the faces it sits above can never disagree about who counts.
    private static func dayPeopleCount(_ things: [Thing], now: Date) -> Int? {
        let mine = ownHandles()
        var who = Set<String>()
        for t in things {
            guard SocialThread.hasContext(t.source),
                  let raw = t.authorHandle ?? t.postAuthor else { continue }
            let h = raw.trimmingCharacters(in: .whitespaces).lowercased()
            guard !h.isEmpty, !mine.contains(h) else { continue }
            who.insert(h)
        }
        return who.isEmpty ? nil : who.count
    }

    private static func dayFold(things: [Thing], landed: [Thing]) -> String? {
        // Pictures — newest first, one per thing, deduped by URL (the demo
        // placeholder lesson), URL images only (`contactSheet`'s own ceiling:
        // stored bytes have no URL to hand the doc grammar).
        var seenArt = Set<String>()
        var shots: [String] = []
        var artTotal = 0
        for t in things.filter({ !($0.previewImageURL ?? "").isEmpty || !$0.imageURLs.isEmpty })
            .sorted(by: { $0.capturedAt > $1.capturedAt }) {
            let url = !(t.previewImageURL ?? "").isEmpty
                ? (t.previewImageURL ?? "") : (t.imageURLs.first ?? "")
            guard !url.isEmpty, seenArt.insert(url).inserted else { continue }
            artTotal += 1
            if shots.count < 4 { shots.append("\(genSafe(url))|\(t.id.uuidString)") }
        }

        // People — the roster `faces` ranks, reduced to handle + avatar.
        var counts: [String: Int] = [:]
        var avatar: [String: String] = [:]
        let mine = ownHandles()
        for t in things {
            // `SocialThread.hasContext` is the app's own answer to "does this
            // source name a human" — the same gate `faces` uses, so the fold
            // and the roster it replaces can never disagree about who counts
            // as a person (RSS and Podcasts stamp a PUBLICATION here).
            guard SocialThread.hasContext(t.source),
                  let raw = t.authorHandle ?? t.postAuthor else { continue }
            let h = raw.trimmingCharacters(in: .whitespaces)
            guard !h.isEmpty, !mine.contains(h.lowercased()) else { continue }
            counts[h, default: 0] += 1
            if avatar[h] == nil, let a = t.previewImageURL, !a.isEmpty { avatar[h] = a }
        }
        let ranked = counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
        let people = ranked.prefix(4).map { "\(tileSafe($0.key))|\(genSafe(avatar[$0.key] ?? ""))" }

        // Rooms — the window's own source mix, biggest first.
        var roomCounts: [String: Int] = [:]
        for t in landed where !Corpus.isImportReceipt(t) { roomCounts[t.source, default: 0] += 1 }
        let rooms = roomCounts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
        let marks = rooms.prefix(3).map { tileSafe($0.key) }

        guard !shots.isEmpty || !people.isEmpty || !marks.isEmpty else { return nil }

        var parts: [String] = []
        if artTotal > shots.count {
            parts.append(String(localized: "\(artTotal - shots.count) more"))
        }
        if ranked.count > people.count {
            parts.append(String(localized: "\(ranked.count) people"))
        } else if !people.isEmpty {
            parts.append(String(localized: "\(people.count) people"))
        }
        if !rooms.isEmpty {
            parts.append(ListFormatter.localizedString(byJoining: rooms.prefix(3).map(\.key)))
        }
        let subline = parts.joined(separator: " · ")
        return "fold = DayFold(\"\(shots.joined(separator: ";"))\", \"\(people.joined(separator: ";"))\", \"\(marks.joined(separator: ";"))\", \"\(genSafe(subline))\")"
    }

    /// The single strongest "what happened to your posts" line, or nil.
    ///
    /// ONE definition, read by the widget's own lead (prd §386d) and drawn
    /// from exactly the sources `yourPostsCard` draws its rows from — so the
    /// tile and the overview can never disagree about the same day. The card
    /// shows up to four rows and the tile shows the lead; showing LESS is not
    /// disagreeing.
    @MainActor
    static func postsLine(_ things: [Thing], windowStart: Date) -> String? {
        let byRef = Dictionary(grouping: things.filter { $0.isLive }, by: { $0.sourceRef ?? "" })
        let roll = SocialLikers.shared.rolls
            .filter { $0.value.when >= windowStart && byRef[$0.key] != nil }
            .sorted { $0.value.when > $1.value.when }
            .first?.value.line
        if let roll, !roll.isEmpty { return roll }
        // No roll — the newest reply or follow, said as what it is.
        guard let next = things
            .filter({
                $0.isLive && $0.capturedAt >= windowStart
                    && ($0.socialContext == "reply" || $0.socialContext == "follow")
            })
            .sorted(by: { $0.capturedAt > $1.capturedAt })
            .first
        else { return nil }
        let who = (next.authorHandle?.isEmpty == false)
            ? "@\(next.authorHandle ?? "")" : clamp(next.title, max: 40)
        return next.socialContext == "reply"
            ? String(localized: "\(who) replied to you")
            : String(localized: "\(who) followed you")
    }

    /// `SourceMix(eyebrow, subline, ["Source N", …])` over the window's
    /// landed rows — nil under 2 sources or 4 things (one cell is a title,
    /// and a two-thing day reads as rows, not a map). Import receipts
    /// excluded, every aggregate's rule. Cells are ranked biggest-first with
    /// the alphabetical tie so two composes can't disagree.
    ///
    /// Internal, and PARAMETERIZED on its eyebrow, since 2026-08-15. This had
    /// gone dead the day §386g folded `contactSheet` + `faces` + this into one
    /// `DayFold` card — nothing called it, and `GenSourceMix` was consequently
    /// an unreachable case in the renderer's switch. `AnswerFigure` is its
    /// caller now, over a free-text answer's retrieved set, and that set is not
    /// a day: the eyebrow had "today" welded into it, which over a search
    /// result is a claim about a wider subject than the data (§83). The default
    /// keeps the brief's own wording exactly, so reviving this changed nothing
    /// about what the brief would draw if it drew it again.
    static func sourceMixLine(_ landed: [Thing],
                              eyebrow: String = String(localized: "Where today came from")) -> String? {
        var counts: [String: Int] = [:]
        for t in landed where !Corpus.isImportReceipt(t) {
            counts[t.source, default: 0] += 1
        }
        let total = counts.values.reduce(0, +)
        guard counts.count >= 2, total >= 4 else { return nil }
        let ranked = counts.sorted { a, b in
            a.value == b.value ? a.key < b.key : a.value > b.value
        }
        let cells = ranked.prefix(3).map { "\(tileSafe($0.key)) \($0.value)" }
        return "mix = SourceMix(\"\(genSafe(eyebrow))\", \"\", [\(cells.joined(separator: ", "))])"
    }

    private static func alertsCard(_ things: [Thing], now: Date,
                                   category: String?) -> (line: String, ids: Set<UUID>, count: Int)? {
        struct Ranked { let thing: Thing; let kind: NotifyKind }
        // AN ALARM NEEDS A CLOCK OR IT NEEDS TO BE NEW (2026-08-16, reported
        // from a device: an App Store Connect rejection from FRIDAY was still
        // leading "Needs you" on Sunday — and would have led it next week
        // too, since nothing here ever aged it out).
        //
        // `NotifySweep.classify` answers "what KIND of thing is this", not
        // "is this still news" — the sweep applies `newsWindow` itself before
        // it ever calls classify, and this card, which borrowed the
        // classifier without the window, inherited none of it.
        //
        // The rule is the doctrine already stated for the runway: a row stays
        // because it has a FUTURE DEADLINE (a dispute whose evidence is due
        // Tuesday is not stale on Wednesday-minus-one), otherwise it stays
        // only while it is news. Past that it is history wearing an alarm's
        // clothes, and the honest place to find it is its own room.
        let alarms: [Ranked] = things.compactMap { t in
            guard let k = NotifySweep.classify(t, now: now), k.cls == .alarm else { return nil }
            let hasFutureClock = (t.dueAt ?? .distantPast) > now
            let isNews = t.capturedAt > now.addingTimeInterval(-NotifySweep.newsWindow)
            guard hasFutureClock || isNews else { return nil }
            return Ranked(thing: t, kind: k)
        }
        // Severity first, then newest — the same total order `NotifySweep`
        // uses to pick which alarm wins a batch, so the row that would have
        // reached the lock screen is the row that leads here.
        let ranked = alarms.sorted {
            $0.kind.severity != $1.kind.severity
                ? $0.kind.severity > $1.kind.severity
                : $0.thing.capturedAt > $1.thing.capturedAt
        }
        let shownAlerts = Array(ranked.prefix(3))
        // OVERDUE TASKS join the card (user, 2026-08-14, prd §386b: "we need
        // 'needs you'") — below the alarms, most-overdue first, capped at
        // two. The alarm class alone fires rarely (a dispute, a rejection),
        // so the card the mockup sold was standing empty on most days while
        // real past-due tasks sat only in the runway's attention dots.
        // Scoped to `overdueSources` — the `overdue` composer's own rule: a
        // task source's past-due row is actionable; a bridge deadline that
        // already passed (an expired grant) is history wearing a clock.
        let alarmIDs = Set(shownAlerts.map { $0.thing.id })
        // DEDUPED (prd §386g, caught on the sim: "Book dentist" and "Book the
        // dentist" — the same errand from Reminders and Todoist — sat as two
        // separate things that need you). `dedupeDeadlines` is the same pass
        // the runway and `nextTile` already take, and this addition had
        // simply never been given it.
        let overdueAll = things.filter {
            $0.mark != .done && KeptAskComposers.overdueSources.contains($0.source)
                && ($0.dueAt ?? .distantFuture) < now && !alarmIDs.contains($0.id)
        }
        let overdue = dedupeDeadlines(overdueAll)
            .sorted { ($0.dueAt ?? now) < ($1.dueAt ?? now) }
            .prefix(2)
        guard !shownAlerts.isEmpty || !overdue.isEmpty else { return nil }
        let shown = shownAlerts.map(\.thing) + Array(overdue)
        let rows = shown.map { r -> String in
            // A deadline's own clock when it has one, else when it landed —
            // never a manufactured urgency word. `dueAt` is the only real
            // clock any of these carry (§306's own finding).
            let meta: String
            if let due = r.dueAt {
                meta = due < now
                    ? String(localized: "overdue")
                    : due.formatted(.dateTime.weekday(.abbreviated).hour().minute())
            } else {
                meta = r.capturedAt.formatted(.dateTime.weekday(.abbreviated).hour().minute())
            }
            return [genSafe(clamp(r.title, max: 46)), genSafe(meta),
                    genSafe(r.source), r.id.uuidString].joined(separator: "|")
        }
        // NO EYEBROW when a section header already says it (prd §386g,
        // caught on the sim: the header read "Needs you" and the card under
        // it read "Needs you · 5", which is the duplication these headers
        // exist to remove, committed by the headers themselves). The count
        // moves to the section's own qualifier — see `sectionQualifiers`.
        // Scoped briefs get no headers, so they keep the eyebrow.
        let eyebrow = category == nil ? "" : (shown.count == 1
            ? String(localized: "Needs you")
            : String(localized: "Needs you · \(shown.count)"))
        // The ids go back to the caller so the runway can SKIP them (2026-08-10).
        // Only the rows actually drawn — an alert past the cap of 3 was never
        // shown, so the runway naming it is the honest place to see it, not a
        // repeat. This is the leads-vs-observations rule ("never the same fact
        // told twice") applied to the pair it now affects: a Stripe dispute
        // carries a `dueAt`, which is exactly what `runwayCard` selects on, so
        // without this every dispute appears once as an alarm and again four
        // rows below as an ordinary deadline.
        // The exclusion set carries every TWIN of a drawn row, not just the
        // survivor (prd §386g, seen on the sim: "Book dentist" from Reminders
        // led Needs you while "Book the dentist" from Todoist — the same
        // errand, collapsed by `dedupeDeadlines` — reappeared four cards
        // later under Coming up). The runway excludes what this card SPEAKS
        // FOR, which is the whole collapsed group, not the one row that
        // happened to win the dedupe.
        let drawnTitles = Set(overdue.map { deadlineKey($0.title) })
        let spokenFor = Set(shown.map(\.id))
            .union(overdueAll.filter { drawnTitles.contains(deadlineKey($0.title)) }.map(\.id))
        return ("alerts = Alerts(\"\(eyebrow)\", \"\(rows.joined(separator: ";"))\")",
                spokenFor, shown.count)
    }

    /// The runway (user, 2026-08-08: "Work is the only room organized by
    /// deadlines") — several upcoming/overdue items on one axis, where
    /// `nextTile` above only ever names the nearest one. Reuses `LeadRow`
    /// (title/meta/image/id/source) under one `Widget`, the exact shape
    /// `readingCard` already wraps several refs in — no new doc-line type,
    /// so there's nothing here that isn't already proven to render.
    ///
    /// The ≥2 floor is the minimum this module doctrine already applies
    /// elsewhere (a runway's whole claim is the SPREAD — `AgentPanel.Figure
    /// .runway`'s own rule, "one dot on an axis is a dot"). Below it,
    /// `nextTile`'s plain single row is the honest degrade for a thin
    /// scope — a real fact stated plainly, never a chart strained to fill
    /// space (spec: "depth scales inversely with scope").
    /// The contact sheet (2026-08-10) — the pictures this scope actually
    /// landed, drawn as themselves.
    ///
    /// Only ever fires where there ARE pictures, which in practice means Life:
    /// measured across a demo corpus, 99 of 277 Life things carry an image
    /// against 4 of 71 for Money and 1 of 74 for Work (`-scopeMaterialProbe`).
    /// That asymmetry is the point rather than a limitation — it is what makes
    /// the Life brief look like nothing else in the app, and the floor below
    /// means the other scopes decline it on their own without a scope test
    /// here.
    ///
    /// URL images only. `previewImageData` is stored bytes with no URL to hand
    /// a remote loader, and plumbing a second image path through the doc
    /// grammar (which is strings) would mean base64 in a doc line — so a
    /// screenshot whose only copy is local contributes to neither the sheet
    /// nor its count. Stated because the gap is invisible: the sheet would
    /// simply look emptier than the library is.
    ///
    /// The ≥6 floor is a SHAPE floor, the runway's own reasoning: under two
    /// full rows this is a handful of thumbnails, which the leads already do
    /// better with room and a title.
    private static func contactSheet(_ things: [Thing]) -> String? {
        // Newest first — a contact sheet is "what you saw", and the most
        // recent is what that question means.
        let withArt = things
            .filter { !($0.previewImageURL ?? "").isEmpty || !$0.imageURLs.isEmpty }
            .sorted { $0.capturedAt > $1.capturedAt }
        guard withArt.count >= 6 else { return nil }
        // ONE picture per thing, never every image a post carries: a single
        // eight-image post would otherwise fill the sheet and read as eight
        // separate moments. And one per distinct IMAGE — a repeated picture
        // says nothing the first one didn't, and the same URL appearing twice
        // is either a genuine duplicate or a placeholder several rows share
        // (which is exactly what the demo corpus does: four bundled shots
        // across dozens of rows, so an undeduped sheet drew the same stadium
        // nine times and looked broken).
        var seenArt = Set<String>()
        var shown: [String] = []
        for t in withArt {
            let url = !(t.previewImageURL ?? "").isEmpty ? (t.previewImageURL ?? "") : (t.imageURLs.first ?? "")
            guard !url.isEmpty, seenArt.insert(url).inserted else { continue }
            shown.append("\(genSafe(url))|\(t.id.uuidString)")
            // FOUR, not twelve (user ruling 2026-08-14, prd §386a: "should
            // only be 4 images not 8") — one tight row that reads as the
            // day's four strongest scenes, with "N more" carrying the rest.
            if shown.count == 4 { break }
        }
        guard shown.count >= 4 else { return nil }
        // Counts the things this sheet stands for, not the pictures it dropped
        // as duplicates — "69 more" should mean more of your life, not more
        // copies of one image.
        let more = withArt.count - shown.count
        let subline = more > 0 ? String(localized: "\(more) more") : ""
        return "sheet = ContactSheet(\"\(String(localized: "What you saw"))\", \"\(genSafe(subline))\", \"\(shown.joined(separator: ";"))\", \"\(more)\")"
    }

    /// Since 2026-08-10 it leads with an AXIS (`Runway`) and keeps the rows
    /// beneath it. The rows stay because they are the tap targets and the only
    /// place the titles are readable; the axis is added because the list could
    /// not show the one thing a runway is for — the SPREAD. Four deadlines in
    /// one afternoon and four across a fortnight rendered as the same four
    /// rows. The axis draws every deadline it knows about, not just the four
    /// listed: the shape is the point, and truncating it to the visible rows
    /// would understate a pile-up precisely when there is one.
    private static func runwayCard(_ things: [Thing], excluding alerted: Set<UUID> = [],
                                   statedOverdue: Bool = false,
                                   titled: Bool = true) -> [String]? {
        let open = dedupeDeadlines(things.filter {
            $0.mark != .done && $0.dueAt != nil && !alerted.contains($0.id)
        })
        let ranked = open.sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
        guard ranked.count >= 2 else { return nil }
        let now = Date.now
        let shown = Array(ranked.prefix(4))
        var refs: [String] = []
        var doc: [String] = [""]
        for (i, item) in shown.enumerated() {
            let due = item.dueAt ?? now
            let meta = due < now
                ? String(localized: "overdue")
                : due.formatted(.dateTime.weekday(.abbreviated).hour().minute())
            refs.append("d\(i)")
            doc.append("d\(i) = LeadRow(\"\(genSafe(clamp(item.title, max: 40)))\", \"\(genSafe(meta))\", \"\", \"\(item.id.uuidString)\", \"\(genSafe(item.source))\")")
        }
        // Untitled under a section header that already says "Coming up"
        // (prd §386g) — the same de-duplication the alerts card takes.
        let widgetTitle = titled ? String(localized: "Coming up") : ""
        doc[0] = "runway = Widget(\"\(genSafe(widgetTitle))\", \"\", [\(refs.joined(separator: ", "))])"
        // The axis, over EVERY deadline (see the note above), plus the two end
        // labels. The far label names the last dot's own day rather than a
        // computed "in N days" — a date is a fact the row can be checked
        // against, a duration is arithmetic the reader has to trust.
        let lanes = ranked.map { item -> String in
            let due = item.dueAt ?? now
            return "\(Int(due.timeIntervalSince1970))|\(genSafe(item.source))"
        }
        let far = (ranked.last?.dueAt ?? now).formatted(.dateTime.month(.abbreviated).day())
        // The near label names the count ONLY when the lede didn't already
        // (2026-08-13) — otherwise the axis restates the headline sitting two
        // inches above it, in the smallest type on the screen, which is the
        // duplication complaint in miniature. Falls back to the axis's own
        // origin, which is what the marker actually means.
        let overdue = ranked.filter { ($0.dueAt ?? .distantFuture) < now }.count
        let near = overdue > 0 && !statedOverdue
            ? String(localized: "\(overdue) overdue")
            : String(localized: "now")
        return ["axis = Runway(\"\", \"\(lanes.joined(separator: ";"))\", \"\(Int(now.timeIntervalSince1970))\", \"\(genSafe(near))\", \"\(genSafe(far))\")"]
            + doc
    }

    // MARK: - The themes map

    /// `TagMap(eyebrow, subline, [cells], "plain")` — what you're actually
    /// into, drawn as the same treemap the All feed leads with
    /// (`HomeComposition.projectClusters`: any tag carrying 2+ things), and
    /// the module that replaced `sourceMix` and `hourStrip` outright on
    /// 2026-07-25. Same slot, same geometry, a different question — a source
    /// tally dies in a deluge, a theme survives one.
    ///
    /// Three things make it the brief's map rather than the feed's:
    ///
    /// 1. **It reads a month, not the day.** A theme is a shape that forms
    ///    over time; scoped to the window it would just be today's tags, which
    ///    is the volume read wearing better clothes.
    /// 2. **The cells print no count** ("plain" — see `GenTagMap.iconMode`).
    ///    Area already encodes magnitude; the number said the same fact twice,
    ///    and it's the fact nobody wanted.
    /// 3. **Its subline is the one thing the map can't draw: what's new.**
    ///    Deliberately NOT "new this week" (user, 2026-07-25) — a week means
    ///    nothing to someone receiving dozens a day, and the only claim we can
    ///    actually keep is that this theme didn't exist before today. So a
    ///    theme is new when its OLDEST thing landed inside the brief's own
    ///    window. Nothing new, no subline — never padded.
    ///
    /// Two clusters minimum: one cell isn't a map, it's a title.
    private static func themesMap(things: [Thing], now: Date,
                                  ledger: [BriefLedger.Entry], windowStart: Date)
        -> (line: String, names: [String])? {
        let horizon = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
        let clusters = HomeComposition.projectClusters(things: things.filter { $0.capturedAt >= horizon })
        guard clusters.count >= 2 else { return nil }
        // Six, matching the feed map's own cap and `GenTagMap`'s six-cell
        // frame set — a seventh cell has nowhere to tile.
        let shown = Array(clusters.prefix(6))
        // The count still rides each cell: it sizes the cell's AREA. Only the
        // printed line is gone.
        let cells = shown.map { "\(tileSafe($0.name)) \($0.things.count)" }
        let fresh = shown
            .filter { ($0.things.map(\.capturedAt).min() ?? .distantPast) >= windowStart }
            .map(\.name)
        var subline = newThemeLine(fresh)
        // Nothing new is the COMMON case once a corpus settles, and it used to
        // leave the map captionless. §214 fills that slot — and only that slot
        // — with the other thing the map can't draw: which theme has been
        // holding for days. Never both, since "X is new" and "X has been
        // building" are contradictory claims about the same shape.
        if subline.isEmpty {
            let runs = shown.compactMap { cluster -> (name: String, run: Int)? in
                let run = BriefLedger.themeStreak(ledger, theme: cluster.name, now: now)
                return run >= 4 ? (cluster.name, run) : nil
            }
            if let longest = runs.max(by: { $0.run < $1.run }) {
                subline = String(localized:
                    "\(clamp(longest.name, max: 24)) has been building for \(spelled(longest.run)) days.")
            }
        }
        return ("themes = TagMap(\"\(String(localized: "What you're into"))\", \"\(genSafe(subline))\", [\(cells.joined(separator: ", "))], \"plain\")",
                shown.map(\.name))
    }

    /// "Foldables is new." / "Foldables and Recipes are new." — the new themes
    /// NAMED, never counted, capped at three so the line stays a sentence
    /// rather than becoming the tally it exists to replace.
    private static func newThemeLine(_ names: [String]) -> String {
        let named = names.prefix(3).map { clamp($0, max: 24) }
        guard !named.isEmpty else { return "" }
        let subject = list(Array(named))
        return named.count == 1
            ? String(localized: "\(subject) is new.")
            : String(localized: "\(subject) are new.")
    }

    // MARK: - The leads (the thing itself, in full)

    /// The mention that names you, rendered as the real post — author, their
    /// words, their avatar. The card's title says WHY it's here.
    /// "Who's around" — Life's people row (user, 2026-08-08: "life should be
    /// rich with avatars"). Named, with a face, never counted (the likers-
    /// feature doctrine: a roll with nobody named is exactly the tally this
    /// app avoids). Reuses `LeadPost` — the SAME doc-line `mentionCard`
    /// already proves renders an avatar — for each person, wrapped under one
    /// `Widget` the way `readingCard` already wraps several refs. No new
    /// rendering surface.
    ///
    /// A person needs BOTH a handle and a real avatar URL to earn a row —
    /// someone named with no face is `mentionCard`'s territory, not this
    /// one's; the whole point here is faces. Deduped by handle so the same
    /// person appearing three times (a reply, a like, a mention) is one row,
    /// not three. Newest-first, capped at 3 — a row of faces is a glance,
    /// not a directory.
    /// Who turned up, ranked by how often (2026-08-10).
    ///
    /// Distinct from `peopleRow` below, which promotes ONE recent post per
    /// person and requires an avatar. This counts appearances across the whole
    /// scope and needs no picture — so it answers "who is around in my life"
    /// where that one answers "what did they just say".
    ///
    /// **`authorAvatarURL` is real and populated**, contrary to a first read of
    /// `-scopeMaterialProbe` (which measured a demo corpus and found zero, and
    /// was wrong about the product): `FarcasterIngest`, `BlueskyIngest`,
    /// `NostrIngest`, `RSSIngest`, `StocktwitsBridge`, `GitHubFeeds`,
    /// `SocialInbound` and `XArchiveImport` all write it. Coverage is UNEVEN
    /// rather than absent — a Farcaster cast carries a face, an X-archive like
    /// names a handle and carries none — which is exactly why the view falls
    /// back to a monogram instead of gating on a picture the way `peopleRow`
    /// does. Gating here would silently drop the people whose bridges simply
    /// don't serve avatars.
    ///
    /// YOU are excluded. Every social bridge stamps your own handle on your own
    /// posts, so an unfiltered count ranks you first by a wide margin in every
    /// corpus — a roster of yourself is not "who's around". Matched on the
    /// literal handle "you" (what the demo seeds) plus every watched account
    /// the social stores know to be yours.
    /// Internal rather than private since 2026-08-16, and no longer orphaned:
    /// §386g folded this into `DayFold` and left it with no caller at all, so
    /// one of the app's most legible figures was fully built, fully tested and
    /// unreachable. `AnswerFigure`'s people rung is its route back.
    static func faces(_ things: [Thing]) -> String? {
        var counts: [String: Int] = [:]
        var newest: [String: Thing] = [:]
        var avatar: [String: String] = [:]
        let mine = ownHandles()
        for t in things {
            // A PERSON, not a byline. `authorHandle` is written by RSS,
            // Substack, Podcasts and YouTube too, where it holds a
            // PUBLICATION — so an unscoped roster drew "The Verge", "Small
            // Things" and a podcast as the people in someone's life (seen on
            // the sim, 2026-08-10). `SocialThread.contextSources` is already the
            // app's own answer to "does this source name a human": the
            // thread-capable networks plus Slack and X, which name people and
            // will never name a masthead. Instagram/TikTok/Snapchat handles
            // are people too but live outside that set; they are left out
            // rather than special-cased, because the set is maintained for
            // this exact distinction and forking it here would give the app
            // two answers to one question.
            guard SocialThread.hasContext(t.source) else { continue }
            guard let raw = t.authorHandle ?? t.postAuthor else { continue }
            let handle = raw.trimmingCharacters(in: CharacterSet(charactersIn: "@ "))
            guard !handle.isEmpty, !mine.contains(handle.lowercased()) else { continue }
            let key = handle.lowercased()
            counts[key, default: 0] += 1
            if let prior = newest[key], prior.capturedAt >= t.capturedAt {} else { newest[key] = t }
            // Keep the first avatar any of this person's rows carried — one
            // bridge may serve a face while another names them bare.
            if avatar[key] == nil, let a = t.authorAvatarURL, !a.isEmpty { avatar[key] = a }
        }
        // Count first, then newest — a total order, so the roster can't
        // reshuffle between two opens over identical data.
        let ranked = counts.sorted {
            $0.value != $1.value
                ? $0.value > $1.value
                : (newest[$0.key]?.capturedAt ?? .distantPast) > (newest[$1.key]?.capturedAt ?? .distantPast)
        }
        guard ranked.count >= 3 else { return nil }
        // FIVE, not six (2026-08-13). The roster's diameters are 64/56/50/44/40
        // and the card is ~362pt wide inside its padding, so six faces overflow
        // by a few points — which drew the last person sliced vertically down
        // the middle with their name cut off, reading as a rendering fault
        // rather than as "scroll for more" (seen on the sim). Five fit, and the
        // tail is already counted honestly in the subline below, which is the
        // §300 folded-tail rule this module was built on.
        let shown = ranked.prefix(5).compactMap { (key, n) -> String? in
            guard let t = newest[key] else { return nil }
            let display = (t.authorHandle ?? t.postAuthor ?? key)
                .trimmingCharacters(in: CharacterSet(charactersIn: "@ "))
            return [genSafe(display), genSafe(avatar[key] ?? ""), "\(n)", t.id.uuidString]
                .joined(separator: "|")
        }
        guard shown.count >= 3 else { return nil }
        let more = ranked.count - shown.count
        let subline = more > 0 ? String(localized: "and \(more) more") : ""
        return "faces = Faces(\"\(String(localized: "Who's around"))\", \"\(genSafe(subline))\", \"\(shown.joined(separator: ";"))\")"
    }

    /// The handles that are YOURS — every account the social stores have been
    /// told you own, plus the literal "you" the demo stamps. Lowercased and
    /// stripped of a leading @, matching `faces`' own key.
    private static func ownHandles() -> Set<String> {
        var out: Set<String> = ["you"]
        for name in FarcasterStore.shared.accounts.filter(\.mine).map(\.username)
            + BlueskyStore.shared.accounts.filter(\.mine).map(\.handle) {
            out.insert(name.trimmingCharacters(in: CharacterSet(charactersIn: "@ ")).lowercased())
        }
        return out
    }

    private static func peopleRow(_ landed: [Thing]) -> (lines: [String], id: String)? {
        var seen = Set<String>()
        var people: [Thing] = []
        for thing in landed.sorted(by: { $0.capturedAt > $1.capturedAt }) {
            // A SOURCE THAT NAMES A HUMAN, and only that (2026-08-16, report:
            // "on 'what they're saying' it showed a github link, and that
            // shouldn't be part of what they're saying"). Exactly right — a
            // commit title is not somebody speaking. The gate was "has a
            // handle and an avatar", which GitHub satisfies (the author, their
            // gravatar) along with anything else that stamps an author.
            //
            // `SocialThread.hasContext` is the app's own answer to the
            // question this module is actually asking, and is already the gate
            // `dayFold` and `faces` use — so the three cards about people can
            // never disagree about who counts as one. It excludes GitHub, and
            // for the same reason excludes RSS and Podcasts, which stamp a
            // PUBLICATION in this field rather than a person.
            guard SocialThread.hasContext(thing.source),
                  let handle = thing.authorHandle, let avatar = thing.authorAvatarURL,
                  !avatar.isEmpty, seen.insert(handle.lowercased()).inserted
            else { continue }
            people.append(thing)
            if people.count == 3 { break }
        }
        guard people.count >= 2 else { return nil }
        var refs: [String] = []
        var doc: [String] = [""]
        for (i, thing) in people.enumerated() {
            let author = thing.authorHandle ?? thing.source
            let words = thing.postText ?? thing.title
            refs.append("p\(i)")
            doc.append("p\(i) = LeadPost(\"\(genSafe(author))\", \"\(genSafe(clamp(words, max: 120)))\", \"\(genSafe(thing.authorAvatarURL ?? ""))\", \"\", \"\(thing.id.uuidString)\")")
        }
        // NOT "Who's around" (user report, 2026-08-13: "duplicative sections").
        // `faces` above carries that title and answers that question — who is
        // around, ranked over the whole scope. This module answers a different
        // one and always did (its own doc comment says so): what the people
        // who turned up in THIS window actually just said. Two cards under one
        // title read as the brief repeating itself even though neither
        // repeats a fact, so the title says which question it answers.
        doc[0] = "people = Widget(\"\(String(localized: "What they're saying"))\", \"\", [\(refs.joined(separator: ", "))])"
        return (doc, people[0].id.uuidString)
    }

    private static func mentionCard(_ landed: [Thing], told: Set<String>,
                                    weights: ChipMemory.Weights)
        -> (lines: [String], id: String)? {
        let mentions = ranked(landed.filter { $0.socialContext == "mention" },
                              told: told, weights: weights)
        guard let mention = mentions.first else { return nil }
        let words = mention.postText ?? mention.title
        let author = mention.authorHandle ?? mention.source
        // The meta line carries the conversation's size and what's behind it —
        // the one place the module admits there's more, and it NAMES the rest
        // rather than only counting the first.
        var meta: [String] = []
        if let replies = mention.replyCount, replies > 0 {
            meta.append(replies == 1 ? String(localized: "1 reply")
                                     : String(localized: "\(replies) replies"))
        }
        if mentions.count > 1 {
            meta.append(String(localized: "\(mentions.count - 1) more behind it"))
        }
        return (["men = Widget(\"\(genSafe(String(localized: "\(mention.source) · mentions you")))\", \"\", [m0])",
                 "m0 = LeadPost(\"\(genSafe(author))\", \"\(genSafe(clamp(words, max: 200)))\", \"\(genSafe(mention.authorAvatarURL ?? ""))\", \"\(genSafe(meta.joined(separator: " · ")))\", \"\(mention.id.uuidString)\")"],
                mention.id.uuidString)
    }

    /// The one read worth opening — the topic outlier when the day has a
    /// dominant topic (the interesting one is the one that ISN'T like the
    /// others), else simply the newest. The residue is named, never counted:
    /// "the rest keeps circling Samsung".
    ///
    /// When the lead IS the outlier the card's own title says so ("Reading ·
    /// the odd one out", the `<source> · mentions you` grammar the mention
    /// card already keeps — a lead card's title states WHY this thing is
    /// here). That sentence used to live in the synthesis note above, which
    /// then had to spell the headline out to make sense; saying it here costs
    /// nothing and lets the note stay a pattern (2026-07-31).
    private static func readingCard(_ landed: [Thing], topic: Topic?, told: Set<String>,
                                    weights: ChipMemory.Weights)
        -> (lines: [String], id: String)? {
        let reads = ranked(reads(landed), told: told, weights: weights)
        guard !reads.isEmpty else { return nil }
        // The topic outlier still wins when there IS one — "the read that
        // isn't like the others" is a stronger claim than "the source you tap
        // most". The ranking decides only the fallback, which is where a plain
        // newest-first pick was leaving a habit source behind a stranger.
        let lead = topic?.outlier ?? reads[0]
        let meta = "\(genSafe(lead.source)) · \(shortTime(lead.capturedAt))"
        var refs = ["r0"]
        // The SOURCE rides as its own arg (2026-07-31) rather than only
        // inside `meta`: the row's art is a full-width banner now, and
        // `RemoteArt` needs a bridge name to fall back to when the URL turns
        // out dead — "never a gray hole" (`RemoteThumb`'s own 2026-07-10
        // ruling), which matters seven times more at banner size than it did
        // at 48pt. Passed whole, never parsed back out of `meta`.
        var doc = ["", "r0 = LeadRow(\"\(genSafe(lead.title))\", \"\(meta)\", \"\(genSafe(lead.previewImageURL ?? ""))\", \"\(lead.id.uuidString)\", \"\(genSafe(lead.source))\")"]
        // The residue gets somewhere to GO (2026-07-22) — it was a plain
        // subline naming a topic the person then had no way to see. Asking
        // the topic re-runs the deterministic retriever and pushes the result
        // onto the agent's own Stack.
        if let topic, reads.count >= 2 {
            // The label deliberately does NOT re-name the topic: the synthesis
            // note above already said "your reading keeps circling Samsung",
            // and repeating it here made the word appear three times on one
            // screen. The QUERY is still the topic — the link just doesn't
            // narrate what the card above it already established.
            refs.append("rmore")
            doc.append("rmore = AskMore(\"\(genSafe(String(localized: "See the rest")))\", \"\(genSafe(topic.word))\")")
        }
        let title = topic?.outlier == nil
            ? String(localized: "Reading")
            : String(localized: "Reading · the odd one out")
        doc[0] = "read = Widget(\"\(genSafe(title))\", \"\", [\(refs.joined(separator: ", "))])"
        return (doc, lead.id.uuidString)
    }

    // MARK: - Shared

    /// What "reading" actually means here: link things MINUS the sources whose
    /// links aren't things you READ. `.link` is the app's catch-all shape for
    /// "has a URL", so a great many non-articles wear it: a watched token and a
    /// trending pool land as `.link` (their content is a Dexscreener URL, which
    /// is what makes their sheet draw a chart), and so do a Spotify track, an
    /// Apple Music song, a Twitch stream, a Steam game, a Pinterest image, a
    /// Bitrefill order. Scoped by the catalog's OWN category vocabulary rather
    /// than a hardcoded source list, so a new source in an excluded category is
    /// handled for free.
    ///
    /// Twice caught on-device by exactly this leak: Markets/Wallet first
    /// ("dogwifhat · $WIF" won the topic outlier under Reading, 2026-07-22),
    /// then Media/Shopping (user, 2026-07-23: "daily brief tells me about my
    /// reading but lists my music"). The lesson both times is the same — a
    /// `.link` is a URL, not a read.
    private static func reads(_ landed: [Thing]) -> [Thing] {
        landed.filter { $0.kind == .link && !nonReadingSources.contains($0.source) }
    }

    /// The categories whose things are never "your reading" — money (a price
    /// isn't prose), media (a song/stream/game/image isn't prose), and shopping
    /// (an order isn't prose). Everything else counts, so a pasted link, an RSS
    /// article, a saved highlight, or a subreddit post all still read as
    /// reading — including sources with no catalog offer at all.
    private static let nonReadingSources: Set<String> = Set(
        BridgeCatalog.offers
            .filter { ["Markets", "Wallet", "Media", "Shopping"]
                .contains(BridgeCatalog.category(of: $0)) }
            .map(\.name)
    )

    /// $20,480 → "$20,480"; big numbers compact, matching the wallet room's
    /// own money grammar.
    /// The SAME ceiling bug the panel had (§341): this stopped at K, so a
    /// watched wallet holding $7.26M read "$7258K" in the brief while the
    /// Wallet room said "$7.0M". One formatter now, tiered like the room's.
    private static func compactUSD(_ usd: Double) -> String {
        AgentPanel.compactUSD(usd)
    }

    private static func shortTime(_ date: Date) -> String {
        let s = Date.now.timeIntervalSince(date)
        if s < 3600 { return "\(max(1, Int(s / 60)))m" }
        if s < 86_400 { return "\(Int(s / 3600))h" }
        // Past a week, the DATE (2026-08-13). An elapsed count is how you read
        // something that just happened; "412d" is arithmetic nobody performs,
        // and it became reachable the moment a scoped brief with an empty
        // window started leading with the scope's newest thing regardless of
        // age (see `leadPool`). A date is also checkable against the row.
        if s < 7 * 86_400 { return "\(Int(s / 86_400))d" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    /// "2h ago" / "3d ago" — the age of a last-known holdings read, matching
    /// `HoldingsGroup.subline`'s own staleness grammar.
    private static func staleAgo(_ date: Date, now: Date) -> String {
        let mins = max(1, Int(now.timeIntervalSince(date) / 60))
        if mins < 60 { return String(localized: "\(mins)m ago") }
        if mins < 60 * 24 { return String(localized: "\(mins / 60)h ago") }
        return String(localized: "\(mins / 1_440)d ago")
    }

    private static func clamp(_ s: String, max: Int) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count > max else { return t }
        let cut = t.prefix(max)
        if let space = cut.lastIndex(of: " ") {
            return String(cut[cut.startIndex..<space]) + "…"
        }
        return String(cut) + "…"
    }

    /// A symbol/source name safe for the `MoversTile`/`SourceMix` grammars,
    /// whose `,`, `|`, and `;` are all field or row separators somewhere in
    /// the two (the same treatment `KeptAskComposers.allocSafe` gives
    /// `AllocBar`'s segments).
    private static func tileSafe(_ s: String) -> String {
        genSafe(s).replacingOccurrences(of: "|", with: " ")
            .replacingOccurrences(of: ",", with: " ")
            .replacingOccurrences(of: ";", with: " ")
    }

    /// Strips what would break the one-line gen-UI grammar — the same
    /// file-private treatment `HomeComposition`/`RootShell`/`KeptAskComposers`
    /// each already keep their own copy of (the standing convention here).
    private static func genSafe(_ s: String) -> String {
        s.replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Widget publication

    /// Hands the lede to the widget through the app group, and asks it to
    /// re-read. The widget extension can't call into this file (app target
    /// only) and must not recompose the brief anyway — it runs in a ~30MB
    /// budget where the brief's live wallet reads are impossible. So the app
    /// publishes the finished sentence and the widget mirrors it.
    ///
    /// An EMPTY lede clears the key rather than leaving the last one standing:
    /// the brief itself opens on the hero when the ladder yields nothing, and a
    /// widget still showing yesterday's sentence would be the fake-status the
    /// honesty rule forbids. The widget's own fallback takes over.
    private static func publishLedeToWidget(_ text: String) {
        guard let group = UserDefaults(suiteName: SharedStore.appGroup) else { return }
        let previous = group.string(forKey: WidgetLede.textKey) ?? ""
        if text.isEmpty {
            group.removeObject(forKey: WidgetLede.textKey)
            group.removeObject(forKey: WidgetLede.stampKey)
        } else {
            group.set(text, forKey: WidgetLede.textKey)
            group.set(Date.now.timeIntervalSince1970, forKey: WidgetLede.stampKey)
        }
        // Only when the SENTENCE changed — the brief recomposes on every
        // foreground and on every composer open for anyone who kept the ask,
        // and a reload per compose would spend the widget's refresh budget on
        // writing the same words back.
        if previous != text {
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetLede.kind)
        }
    }

    /// Mirrors `themesMap`'s own clustering (same 30-day horizon, same
    /// two-cluster floor) into the App Group as plain cells — never the
    /// `TagMap(...)` doc-string `themesMap` composes, which is GenUI's
    /// format, not the widget's. Recomputed independently rather than
    /// threading `themesMap`'s result through: it's a pure, cheap read
    /// (`HomeComposition.projectClusters`, no async/NLTagger dependency),
    /// and the two callers wanting different shapes of the same clustering
    /// is cheaper than one contorting its return type for the other.
    private static func publishThemesToWidget(things: [Thing], now: Date) {
        guard let group = UserDefaults(suiteName: SharedStore.appGroup) else { return }
        let horizon = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
        let clusters = HomeComposition.projectClusters(things: things.filter { $0.capturedAt >= horizon })
        guard clusters.count >= 2 else {
            group.removeObject(forKey: WidgetLede.themesKey)
            group.removeObject(forKey: WidgetLede.themesStampKey)
            return
        }
        // Three, not `themesMap`'s six — the medium widget has room for
        // three legible cells before a fourth reads as clutter (mockup,
        // 2026-08-03).
        let cells = clusters.prefix(3).map { WidgetThemeCell(name: $0.name, weight: $0.things.count) }
        guard let data = try? JSONEncoder().encode(Array(cells)) else { return }
        group.set(data, forKey: WidgetLede.themesKey)
        group.set(Date.now.timeIntervalSince1970, forKey: WidgetLede.themesStampKey)
    }
}

/// Whichever arm of a race arrives first, delivered exactly once — the read or
/// the deadline (`TodayBrief.bounded`). `settle` is idempotent, so the losing
/// arm is a no-op rather than a double-resume of the same continuation; `wait`
/// has a single caller, which is why one waiter slot is enough.
private actor FirstArrival<Value> {
    private var settled = false
    private var arrived: Value?
    private var waiter: CheckedContinuation<Value?, Never>?

    func settle(_ value: Value?) {
        guard !settled else { return }
        settled = true
        arrived = value
        if let waiter {
            self.waiter = nil
            waiter.resume(returning: value)
        }
    }

    /// The continuation is installed INSIDE the actor, so an arm that settles
    /// before the wait begins is read back off `arrived` instead of being lost
    /// to a continuation that was never stored.
    func wait() async -> Value? {
        if settled { return arrived }
        return await withCheckedContinuation { self.waiter = $0 }
    }
}
