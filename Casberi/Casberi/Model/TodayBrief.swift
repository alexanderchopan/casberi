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
/// Four things read it: the lede's streak ("ETH has done the lifting three
/// days running"), the themes map's continuity subline, the leads' novelty
/// preference, and the absence note.
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
    /// whole pipeline for free; only the wallet/markets modules read live
    /// bridge state INSTEAD of `things` (holdings, watchlist moves, DeFi risk,
    /// resolved markets), so those are separately gated below on the category
    /// actually being Wallet/Markets/unscoped.
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
    static func compose(things: [Thing], context: ModelContext,
                        presenting: Bool = false, category: String? = nil) async -> KeptAskComposers.Result? {
        // Filtered on ENTRY as well as after the awaits below (crash fix,
        // build 250). The caller's array can ALREADY be stale: `RootShell`
        // fetches it, then awaits `KeptAskStore.refreshDigests` before handing
        // it here — a suspension of its own, in which a heal can delete. So
        // `DayBrief.landed` on the next line would read a tombstoned model
        // before this function ever suspends.
        var things = things.live
        let now = Date.now

        // Stage 1 (deterministic app selection, spec's own term): the
        // category's candidate sources are every catalog offer whose
        // `BridgeCatalog.category(of:)` names it — "connected" needs no
        // separate check, since a source with no connected bridge can never
        // have landed a `Thing` in the first place.
        if let category {
            let candidateSources = Set(BridgeCatalog.offers
                .filter { BridgeCatalog.category(of: $0) == category }.map(\.name))
            // A category with literally nothing ever landed from it is not
            // "quiet since you last checked", it's not connected at all — the
            // spec's own edge case, distinct from "connected but nothing new"
            // below. Checked against the WHOLE corpus, before any window.
            guard things.contains(where: { candidateSources.contains($0.source) }) else {
                return KeptAskComposers.Result(
                    delta: "", digest: String(localized: "unconnected"),
                    doc: ["root = Stack([ins])",
                          "ins = Insight(\"\(genSafe(String(localized:
                              "No apps connected in \(category) yet — add one from Apps.")))\")"])
            }
            things = things.filter { candidateSources.contains($0.source) }
        }
        // Wallet/Markets modules below read LIVE bridge state instead of
        // `things` (holdings, watchlist prices, DeFi risk, resolved markets),
        // so the Stage-1 filter above can't scope them — gated explicitly.
        let scopedToWallet = category == nil || category == "Wallet"
        let scopedToMarkets = category == nil || category == "Markets"

        // The window boundary: the whole day's away-window/midnight boundary
        // for the unscoped brief (UNCHANGED — spec: "the scheduled daily
        // brief keeps its current window"), or this category's own "since I
        // last checked" moment for a scoped ask.
        let windowStart = category.map { BriefScope.since(category: $0, now: now) }
            ?? DayBrief.windowStart(now: now)
        var landed = DayBrief.landed(things, now: now, since: windowStart)
        let move = scopedToWallet ? DayBrief.walletMove(now: now) : nil
        // The ledger is read ONCE here and threaded through every module that
        // asks it something (the `ChipMemory.snapshot()` discipline) — five
        // separate reads would decode the same JSON five times per rise.
        let ledger = BriefLedger.snapshot()
        let told = BriefLedger.told(ledger, windowStart: windowStart, now: now)
        let weights = ChipMemory.snapshot()

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
        async let holdingsRead = (presenting && scopedToWallet) ? liveHoldings() : []
        async let movesRead = scopedToMarkets ? liveMoves(context: context) : []
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
        async let riskRead = (presenting && scopedToWallet) ? worstDebt() : nil
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
        // above, and those reads suspend for up to `liveReadBudget` (8s). The
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
        // Re-filtering HERE is sufficient and airtight: this enum is
        // `@MainActor` and there is no further `await` in `compose`, so the
        // whole remainder runs with exclusive main-actor access — no delete can
        // land between this line and the reads that follow.
        things = things.live
        landed = landed.live

        var ids: [String] = []
        var lines: [String] = []

        // 1. The lede — the day in ONE sentence, in display type, above
        // everything (user, 2026-07-25: "that line should be above wallet").
        // A ranked ladder since §214: risk, then money, then a person, then a
        // deadline. Nothing is padded to fill the slot — an empty ladder emits
        // no lede and the brief opens on the hero instead.
        let lede = ledeLine(move: move, risk: risk, landed: landed, things: things,
                            ledger: ledger, now: now)
        if !lede.text.isEmpty {
            ids.append("lede")
            lines.append("lede = DayLede(\"\(genSafe(lede.text))\", \"\(genSafe(dateline(now: now)))\", \"\(genSafe(lede.figure))\", \"\(lede.direction)\")")
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
        if category == nil {
            publishLedeToWidget(lede.text)
            publishThemesToWidget(things: things, now: now)
        }

        // 2. The money hero — the CROWN (2026-07-25), the day's one fused
        // visualization and the only read where a number is itself the event.
        if let hero = moneyHero(move: move, holdings: holdings, landed: landed) {
            ids.append("hero")
            lines.append(hero)
        }

        // 3. The pair: what's moving, what's next. Stays glued to the hero
        // above it (user ruling 2026-07-23: "keep wallet and watchlist
        // together") — the watchlist IS money, so putting anything between it
        // and the wallet splits one story across two places.
        var tiles: [String] = []
        if let movers = moversTile(moves) {
            tiles.append("tmov")
            lines.append(movers)
        }
        if let next = nextTile(things) {
            tiles.append("tnext")
            lines.append(next)
        }
        if !tiles.isEmpty {
            ids.append("pair")
            lines.append("pair = TilePair([\(tiles.joined(separator: ", "))])")
        }
        // A watched market that resolved — an EVENT, so it follows the pair
        // rather than joining it (a tile pair is state at a glance; this is
        // news). Silent on every day nothing settled, like every module here.
        if scopedToMarkets, let resolved = marketResolvedToday(MarketsAsk.moves(context: context), now: now) {
            ids.append("tmkt")
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
            lines.append(flow)
        }

        // 4. The themes map — the second whole-day summary, and the one that
        // replaced "what landed" and "when it landed" outright (2026-07-25,
        // user: the themes treemap "is more important than 'what landed' and
        // when"). Same slot, same geometry; a different question — what today
        // was ABOUT, which survives a deluge, where a source tally doesn't.
        var themeNames: [String] = []
        if let themes = themesMap(things: things, now: now, ledger: ledger, windowStart: windowStart) {
            ids.append("themes")
            lines.append(themes.line)
            themeNames = themes.names
        }

        // 5 and 6 COMPOSE in the other order than they render (2026-07-31).
        // The leads are the screen's richest statement of a single thing — the
        // post in full, the read with its image and its tap — so an
        // observation that would name the same thing above them is the same
        // fact told twice, worse first (user: "then below it will be another
        // card with that specific item in it"). Composing the leads first lets
        // `observations` see what's already being said and drop its own copy.
        // The render order is unchanged: `ids` still appends notes, then leads.
        let topic = dominantTopic(landed)
        var leadIDs: [String] = []
        var leadLines: [String] = []
        var leadRefs: [String] = []
        // The leads — a thing in full, per shape that landed. Both prefer
        // something this window hasn't already led with, then the sources you
        // actually visit (§214) — see `ranked`.
        if let mention = mentionCard(landed, told: told, weights: weights) {
            leadRefs.append("men")
            leadLines += mention.lines
            leadIDs.append(mention.id)
        }
        if let reading = readingCard(landed, topic: topic, told: told, weights: weights) {
            leadRefs.append("read")
            leadLines += reading.lines
            leadIDs.append(reading.id)
        }

        // The synthesis card (B3) — only the observations that fired. Sits
        // BELOW the summaries (2026-07-25): it used to open the screen,
        // which made the agent's read the crown instead of the money.
        // A scoped brief covers fewer apps, so more of what actually fired
        // earns a line instead of losing the last seat to the unscoped
        // brief's cap (spec: "depth scales inversely with scope").
        let notes = observations(things: things, landed: landed, move: move, moves: moves,
                                 now: now, ledger: ledger, ledeTookRisk: lede.tookRisk,
                                 topic: topic, leads: Set(leadIDs),
                                 cap: category == nil ? 3 : 6)
        // The agent's READ of the day (2026-08-07) — a genuine model paragraph
        // leading the synthesis section, where the deterministic notes below are
        // single facts. The fix for "the brief feels generic": the notes are a
        // fixed menu of single-field detectors, so the card reads the same shape
        // every morning; this says what the day was actually ABOUT, and varies.
        //
        // PRESENTING-ONLY (the `worstDebt()` precedent, §214) — the
        // background/widget/digest compose never pays the model's latency, and
        // this element changes no `digest`, `delta`, or ledger fact, only the
        // display, so the whisper's changed-dot stays deterministic (ruling 5).
        // Nil off Apple-Intelligence devices and on a thin day; the notes card
        // then stands alone exactly as before (zero regression). Grounded on the
        // day's own facts with the prior briefs' topics as continuity.
        if presenting,
           let read = await OnDeviceModel.dayRead(
               evidence: dayReadEvidence(landed: landed, notes: notes, topic: topic),
               continuity: dayReadContinuity(ledger)) {
            ids.append("read")
            lines.append("read = Insight(\"\(genSafe(read))\")")
        }
        if !notes.isEmpty {
            ids.append("notes")
            lines.append("notes = DayNotes([\(notes.indices.map { "n\($0)" }.joined(separator: ", "))])")
            for (i, n) in notes.enumerated() {
                lines.append("n\(i) = DayNote(\"\(n.glyph)\", \"\(genSafe(n.text))\", \"\(n.thingID)\")")
            }
        }
        ids += leadRefs
        lines += leadLines

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
            return KeptAskComposers.Result(
                delta: "", digest: String(localized: "quiet"),
                doc: ["root = Stack([ins])", "ins = Insight(\"\(genSafe(line))\")"])
        }
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
        let chapters = ["hero", "themes", "read", "notes", leadRefs.first]
            .compactMap { $0 }
            .filter { ids.contains($0) && $0 != ids.first }
        return KeptAskComposers.Result(delta: digest, digest: digest,
                                       doc: ["root = Stack([\(ids.joined(separator: ", "))], \"\(chapters.joined(separator: ","))\")"] + lines)
    }

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
            let attribution = walletAttribution(move, ledger: ledger, now: now).text
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

        // A source that has landed something every time the brief looked, and
        // didn't today. Rare by construction (four unbroken appearances and
        // five days of calendar), and gated on the day having landed SOMETHING
        // — on a genuinely empty day every source is quiet and naming one
        // would be a coincidence dressed as an observation.
        if !landed.isEmpty,
           let gone = BriefLedger.absent(ledger, landedSources: Set(landed.map(\.source)),
                                         now: now) {
            let since = gone.since.formatted(.dateTime.month(.abbreviated).day())
            out.append(Note(glyph: "moon.zzz",
                            text: String(localized:
                                "Nothing from \(gone.source) today — the first quiet day since \(since).")))
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
        // Every watched wallet's cells merged — this is the PORTFOLIO's day,
        // not the first wallet's (§155's combined read, same principle).
        let cells = holdings.flatMap(\.cells)
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
            subline = String(localized: "Nothing moved today")
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

    /// "Up $184 today. ETH did the lifting." — the brief's LEDE (`DayLede`),
    /// the sentence the screen opens with, above the hero.
    ///
    /// It carries the two facts the number and its pill can't. The MAGNITUDE
    /// in money, because a percentage hides whether +1.5% is a coffee or a
    /// month's rent. And WHICH holding did it — the day-scoped attribution
    /// (§166, `holdingsDeltas(forAddress:since:)`), never the all-time one, so
    /// the sentence spans exactly what the percentage claims.
    ///
    /// It has now been in three places in one day (2026-07-25): a synthesis
    /// note buried three modules down, then the hero's own subtitle when the
    /// money took the crown, then here — the user's call, and the one the
    /// approved mockup drew. Above the number it reads as the day's headline;
    /// under it, it read as a caption on a chart. Both halves fail
    /// independently and silently — no move, no line; no snapshot pair
    /// covering the window, just the dollar half.
    private static func walletAttribution(_ move: DayBrief.WalletMove?,
                                          ledger: [BriefLedger.Entry],
                                          now: Date) -> Lede {
        guard let move, move.anchorUSD > 0 else { return Lede() }
        let delta = move.usd - move.anchorUSD
        guard abs(delta) >= 1 else { return Lede() }
        // The figure is captured as the SAME string the sentence is built from
        // — not re-derived — so the accented run and the words can never
        // disagree about what the day's number was.
        let figure = compactUSD(abs(delta))
        let direction = delta > 0 ? "up" : "down"
        var line = delta > 0
            ? String(localized: "Up \(compactUSD(delta)) today.")
            : String(localized: "Down \(compactUSD(abs(delta))) today.")
        let deltas = WalletStore.shared.holdingsDeltas(forAddress: nil, since: move.since)
        guard let top = deltas.first, abs(top.delta) >= 1 else {
            return Lede(text: line, figure: figure, direction: direction)
        }
        // The CONTINUITY half (§214): when the same holding has carried the
        // wallet several days in a row, saying so is strictly more than
        // naming it once more. Consecutive CALENDAR days, checked in
        // `BriefLedger.streak` — three opens across a week must never wear
        // the words "three days running".
        let run = BriefLedger.symbolStreak(ledger, symbol: top.symbol, now: now)
        if run >= 3 {
            line += " " + (top.delta > 0
                ? String(localized: "\(top.symbol) has done the lifting \(spelled(run)) days running.")
                : String(localized: "\(top.symbol) has taken it back \(spelled(run)) days running."))
        } else {
            line += " " + (top.delta > 0
                ? String(localized: "\(top.symbol) did the lifting.")
                : String(localized: "\(top.symbol) took it back."))
        }
        return Lede(text: line, symbol: top.symbol, figure: figure, direction: direction)
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
                                 ledger: [BriefLedger.Entry], now: Date) -> Lede {
        // 1. Something is close to liquidation.
        if let risk {
            let chain = WalletIngest.displayName(forNetwork: risk.network) ?? risk.network
            return Lede(text: String(localized:
                "Your \(risk.protocolName) position on \(chain) is close to liquidation — health factor \(WalletIngest.format(risk.hf))."),
                        tookRisk: true)
        }
        // 2. The money moved.
        let money = walletAttribution(move, ledger: ledger, now: now)
        if !money.text.isEmpty { return money }
        // 3. Someone addressed you by name. The mention card below shows the
        // POST; this says who, which is the half a headline is for.
        if let mention = landed.first(where: { $0.socialContext == "mention" }),
           let who = mention.authorHandle, !who.isEmpty {
            return Lede(text: String(localized: "\(who) mentioned you."))
        }
        // 4. A deadline lands today. Deadlines only, never calendar events —
        // the same scoping `nextTile` holds to (§101's day-planner ruling).
        if let due = dueToday(things) {
            let name = clamp(due.title, max: 44)
            let stop = name.hasSuffix("…") ? "" : "."
            return Lede(text: (due.dueAt ?? .now) < .now
                ? String(localized: "\(name) is overdue\(stop)")
                : String(localized: "\(name) is due today\(stop)"))
        }
        return Lede()
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
    private static let liveReadBudget: TimeInterval = 8

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

    private static func nextTile(_ things: [Thing]) -> String? {
        let open = things.filter { $0.mark != .done && $0.dueAt != nil }
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
        return "\(Int(s / 86_400))d"
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
