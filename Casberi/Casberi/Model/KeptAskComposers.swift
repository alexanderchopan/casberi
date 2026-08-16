import Foundation
import SwiftData

/// One deterministic doc-composer per kept-ask KIND (docs/agent-brief.md,
/// ruling 1). Mirrors `HomeComposition`'s own shape: hand-authored
/// `"root = Stack([...])"` line arrays, built directly from `Thing`/
/// `WalletStore`/`TokensAsk`/`HomeInsightStore` reads.
///
/// Deliberately NEVER calls `RootShell.answerDocument` — that function's
/// deterministic branches sit above a model-routing fallback by CONVENTION,
/// not a compiler-enforced boundary; a future edit reordering that routing
/// could silently start invoking the model for what someone believes is a
/// standing, no-LLM kept ask. `HomeComposition` and `RootShell` already each
/// read the same underlying primitives (`WalletIngest`, `Thing` fields)
/// independently rather than calling into one another — this follows that
/// same precedent, so the no-model guarantee is structural, not conventional.
@MainActor
enum KeptAskComposers {
    struct Result {
        let delta: String
        let digest: String
        let doc: [String]
        /// What a SEARCH filtered on, and how many things it really matched —
        /// nil for every other composer (2026-08-13). Carried on the result so
        /// the composer can draw its scope chips off the pass that just ran,
        /// rather than re-running the engine to ask it what it did; over a big
        /// corpus that second pass is the difference between a tap and a
        /// second of frozen UI. See `Composer.liveReadCeiling`.
        var find: (scopes: [Retriever.Scope], total: Int)?

        /// Every composer's document funnels through here, which is the one
        /// place a DUPLICATE ELEMENT ID can be caught (2026-08-13). `GenParser`
        /// keys elements in a dictionary and `GenRenderer`'s Stack draws them
        /// with `ForEach(id: \.self)`, so two lines sharing an id are one
        /// element referenced twice: the later line wins, the earlier module is
        /// destroyed with no error anywhere, and its replacement draws twice.
        /// Shipped in the Today brief exactly that way (`read = Insight` vs
        /// `read = Widget`), reported as "duplicative sections" and invisible
        /// to the build, the audits and the screen sweep — every element
        /// involved renders perfectly, which is what makes it unfindable by
        /// eye. DEBUG-only and non-fatal on purpose: a wrong-looking document
        /// is never worth killing the app over, and a composer may legitimately
        /// re-emit a line while streaming a partial.
        init(delta: String, digest: String, doc: [String]) {
            self.delta = delta
            self.digest = digest
            self.doc = doc
            #if DEBUG
            var seen = Set<String>()
            for line in doc {
                let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
                guard parts.count >= 2, parts[1] == "=" else { continue }
                let id = String(parts[0])
                if !seen.insert(id).inserted {
                    NSLog("[Casberi] docDupeID| %@ — one element, drawn where two were meant", id)
                }
            }
            #endif
        }
    }

    /// `things` must arrive newest-first (every existing caller's fetch order).
    /// `context` is threaded through explicitly (matching how `RootShell`
    /// already calls `TokensAsk.moves(context:)`/`.watched(_:)` — there is no
    /// shared/static ModelContext accessor in this codebase).
    ///
    /// `presenting` says whether the person is about to SEE this document or
    /// the app is only computing a digest (`KeptAskStore.refreshDigests` runs
    /// every kept kind in the background on each foreground). Only the Today
    /// brief reads it — its ledger (§214) must never record having told you
    /// something it merely composed — so it defaults to false and a new
    /// composer is silent by construction.
    /// `onPartial` is forwarded to `TodayBrief.compose` and to nothing else —
    /// the brief is the only kind whose document waits on a network read, so
    /// it is the only one with a half worth painting early. Every other
    /// composer is deterministic and returns in one pass.
    static func compose(_ kind: String, things: [Thing], context: ModelContext,
                        presenting: Bool = false,
                        onPartial: (([String]) -> Void)? = nil) async -> Result? {
        // `.live` at this ONE door, so every composer below is handed a valid
        // array (crash fix, build 250 — see `TodayBrief.compose`). The caller
        // that matters is `KeptAskStore.refreshDigests`, which awaits this
        // function once PER KIND in a loop while holding a single `things`
        // array: each await is a suspension in which the app's own foreground
        // heals can delete, so by the third kind the array it keeps passing can
        // hold tombstoned models. Filtering here re-validates on every call,
        // and this enum is `@MainActor`, so what a composer receives can't be
        // invalidated underneath it before it reads.
        let things = things.live
        if kind == "today" {
            return await TodayBrief.compose(things: things, context: context,
                                            presenting: presenting, onPartial: onPartial)
        }
        if kind == "away" { return away(things) }
        if kind == "wallet" { return await wallet(things) }
        if kind == "walletdefi" { return await walletDeFi() }
        if kind == "walletuniswap" { return await walletUniswap() }
        if kind == "walletgas" { return await walletGas() }
        if kind == "walletsafe" { return await walletSafe() }
        if kind == "watchlist" { return await watchlist(context: context) }
        if kind == "overdue" { return overdue(things) }
        if kind == "upcoming" { return upcoming(things) }
        if kind == "noticed" { return noticed() }
        if kind.hasPrefix("showtag:") {
            return showtag(String(kind.dropFirst("showtag:".count)), things: things)
        }
        if kind.hasPrefix("context:") {
            return contextRecap(String(kind.dropFirst("context:".count)), things: things)
        }
        if kind.hasPrefix("category:") {
            // Scoped "What's going on" briefs (scoped-brief-spec.md) — the
            // SAME pipeline `"today"` runs above, scoped to one catalog
            // category instead of the whole corpus. Was its own plain
            // "N things from your X apps this week" recap; that composer
            // (`categoryRecap`) is gone rather than kept alongside this, since
            // a kept `category:<c>` pill re-running through this dispatch
            // must show what the spec calls the SAME "daily brief format" a
            // scoped chip tap or free-text ask gets — two different answers
            // for the same kind string would be the drift `KeptAskComposers`'
            // own header rule (one composer per kind) exists to prevent.
            return await TodayBrief.compose(things: things, context: context,
                                            presenting: presenting,
                                            category: String(kind.dropFirst("category:".count)),
                                            onPartial: onPartial)
        }
        if kind.hasPrefix("handle:") {
            return handleRecap(String(kind.dropFirst("handle:".count)), things: things)
        }
        if kind == "throwback" { return throwback(things) }
        if kind == "moneyflow" { return moneyFlow(things) }
        if kind == "spend" { return spend(things) }
        if kind.hasPrefix("search:") {
            return search(String(kind.dropFirst("search:".count)), things: things,
                          standing: true)
        }
        return nil
    }

    // MARK: - What a kind actually reads (PERF 2026-08-13)

    /// The rows a kind's composer really touches — so the ASK path can fetch
    /// those instead of materialising the whole store.
    ///
    /// This exists because `RootShell.answerDocument` opened every kept-ask
    /// branch with `fullCorpus()`: an unbounded, fully-hydrated fetch of every
    /// `Thing`, on the main actor, before a single composer ran. That is the
    /// same class the 2026-08-11 pass fixed for the feed (`allRoomFetchLimit`)
    /// and the chip strip (`newestPerSource`) and did not reach here — which is
    /// exactly why opening the agent feels fast (its board fetch was moved off
    /// the critical path, `composeBoard`) and TAPPING A CHIP does not. Six of
    /// these kinds read no rows at all and still paid for the whole store.
    ///
    /// The scope is DERIVED from the constants the composers themselves filter
    /// on (`overdueSources`, `moneyFlowSources`, `walletDocSources`), never from
    /// a hand-copied list beside them — a second list is the drift this
    /// codebase has been bitten by repeatedly, and here it would be invisible:
    /// a leg added to `moneyFlow` without its source in the fetch reads as a
    /// room that quietly stopped counting, with every screen still perfect.
    /// `scripts/ask-scope-selftest.sh` fails the build if a dispatched kind has
    /// no case here, or if a composer goes back to filtering on a literal.
    ///
    /// A new kind is `.whole` by default, which is the old behaviour: slow,
    /// never wrong.
    enum CorpusNeed: Equatable {
        /// Reads no rows — the composer takes no `things` argument at all.
        case none
        /// Reads across everything (counts, tag vocabulary, a brief).
        case whole
        /// Only these source rooms.
        case sources(Set<String>)
        /// Only rows carrying a deadline.
        case dated
        /// Only rows written by one author.
        case handle(String)
    }

    static func corpusNeed(for kind: String) -> CorpusNeed {
        // The six that ignore `things` entirely — every one of them a live
        // read (wallet protocols, token candles) or a cached line.
        if ["watchlist", "noticed", "walletdefi", "walletuniswap",
            "walletgas", "walletsafe"].contains(kind) { return .none }
        if kind == "wallet" { return .sources(walletDocSources) }
        if kind == "overdue" { return .sources(overdueSources) }
        if kind == "upcoming" { return .dated }
        if kind == "throwback" { return .sources(Corpus.bulkImportSources) }
        if kind == "moneyflow" { return .sources(moneyFlowSources) }
        if kind == "spend" { return .sources(Corpus.cardSpendSources) }
        if kind.hasPrefix("context:") {
            return .sources([String(kind.dropFirst("context:".count))])
        }
        if kind.hasPrefix("category:") {
            let sources = categorySources(String(kind.dropFirst("category:".count)))
            return sources.isEmpty ? .whole : .sources(sources)
        }
        if kind.hasPrefix("handle:") {
            return .handle(String(kind.dropFirst("handle:".count)))
        }
        // `showtag:` is deliberately `.whole`: `tags` is a transformable
        // attribute, and a `#Predicate` testing membership on one compiles
        // clean and TRAPS at runtime inside CoreData (see CLAUDE.md). The
        // filter stays in Swift over a full fetch.
        //
        // `today`, `away` and `search:` span the corpus by definition.
        return .whole
    }

    /// The two task bridges `overdue` counts. One definition, read by the
    /// composer and by `corpusNeed` above.
    static let overdueSources: Set<String> = ["Reminders", "Todoist"]

    /// `moneyFlow`'s two named legs. Constants rather than literals so the
    /// union below cannot fall out of step with the filters that use them.
    static let moneyFlowInboundSource = "Peer"
    static let moneyFlowShieldedSource = "Privacy Pools"

    /// Every source `moneyFlow` reads — the card seats plus its two named legs.
    static var moneyFlowSources: Set<String> {
        Corpus.cardSpendSources.union([moneyFlowInboundSource, moneyFlowShieldedSource])
    }

    /// The rows `walletDoc` draws its approvals and activity from.
    static let walletDocSources: Set<String> = ["Wallet", "Peer"]

    // MARK: - While I was away

    private static func away(_ things: [Thing]) -> Result? {
        guard let pulse = StatusAsk.pulse("while i was away", things: things) else { return nil }
        let arrived = pulse.pool
        let mentions = arrived.filter { $0.socialContext == "mention" }.count
        let delta = arrived.isEmpty ? "" : "\(arrived.count) new"
        let line = arrived.isEmpty
            ? "Nothing new since your last visit."
            : (mentions > 0
               ? "\(arrived.count) new while you were away, \(mentions) mentioning you."
               : "\(arrived.count) new while you were away.")
        var doc = ["root = Stack([ins])", "ins = Insight(\"\(genSafe(line))\")"]
        let shown = Array(arrived.prefix(4))
        if !shown.isEmpty {
            doc[0] = "root = Stack([ins, res])"
            doc += rows(shown, title: "Worth a look")
        }
        return Result(delta: delta, digest: "\(arrived.count)|\(mentions)", doc: doc)
    }

    // MARK: - How's my money

    /// The summary line PLUS the real holdings treemap — the same `TagMap`
    /// idiom the Wallet feed itself draws (`WalletIngest.portfolioRead`).
    /// Standing rule: any kept ask backed by a real visualization always
    /// shows it, never text alone (matches `RootShell.answerDocument`'s
    /// watchlist branch below, which already did this for TokenChip rows).
    private static func wallet(_ things: [Thing]) async -> Result? {
        guard !WalletStore.shared.addresses.isEmpty else { return nil }
        guard let line = await WalletAsk.answer() else {
            // The corpus sections are local reads, so an unreachable LIVE
            // read still shows what the wallet bridges already landed.
            return Result(delta: "", digest: "unreachable",
                          doc: walletDoc(line: "Couldn't reach your wallet right now.",
                                         groups: [], things: things))
        }
        // The line itself is the honest digest — it only changes when the
        // real figure does, same idiom as the Noticed line below.
        let groups = await WalletIngest.topHoldingsByWallet()
        return Result(delta: line, digest: line,
                      doc: walletDoc(line: line, groups: groups, things: things))
    }

    /// Shared by the kept-ask composer and `RootShell.answerDocument`'s
    /// free-text wallet branch, so both never disagree about what a wallet
    /// answer looks like. A whole wallet brief now, not a balance check
    /// (user, 2026-07-21): the value line, the balance SPARKLINE over recorded
    /// samples (ValueSpark), a glance StatRow (approvals / activity / tokens),
    /// the holdings treemap, a per-wallet split (AllocBar) when more than one
    /// is watched, then what the wallets have DONE — the newest token approvals
    /// (each row's sheet carries the prepare card and the Revoke.cash door) and
    /// the latest activity, transfers drawn as TxRows. Every section is a read
    /// over local samples or things the bridges already landed — no extra
    /// network, still deterministic — and each gates itself out when thin, so a
    /// fresh wallet degrades to exactly the old line + treemap.
    static func walletDoc(line: String, groups: [WalletIngest.HoldingsGroup],
                          things: [Thing]) -> [String] {
        let walletThings = things.filter { walletDocSources.contains($0.source) }
        let allApprovals = walletThings.filter(isApproval)
        let allActivity = walletThings.filter { !isApproval($0) }
        let approvals = Array(allApprovals.prefix(3))
        let activity = Array(allActivity.prefix(4))

        var ids: [String] = []
        var sections: [String] = []

        // The balance sparkline, from this wallet's (or the combined) recorded
        // value samples — the one fact the line summarizes but couldn't show.
        if let spark = valueSparkLine() {
            ids.append("spark")
            sections.append(spark)
        }
        // A glance strip — approvals is what the user asked to see, so it leads.
        // "This week" is genuinely recent (not the all-time transfer count,
        // which would be "recent" in name only); tokens is what's held now.
        let now = Date.now
        let recentActivity = allActivity.filter { $0.capturedAt >= now.addingTimeInterval(-7 * 86_400) }.count
        let tokenCount = groups.reduce(0) { $0 + $1.tokenCount }
        if !allApprovals.isEmpty || !allActivity.isEmpty {
            ids.append("stat")
            sections.append("stat = StatRow(\"\(allApprovals.count)\", \"approvals\", \"\(recentActivity)\", \"this week\", \"\(tokenCount)\", \"tokens\")")
        }
        for (i, g) in groups.enumerated() {
            ids.append("w\(i)")
            sections.append("w\(i) = TagMap(\"\(genSafe(g.label))\", \"\(genSafe(g.subline))\", [\(g.cells.joined(separator: ", "))], \"token\")")
        }
        // How the total splits across wallets — only meaningful with two+.
        if groups.count >= 2 {
            let segs = groups
                .map { "\(allocSafe($0.label))|\(Int($0.totalUSD))" }
                .joined(separator: ",")
            ids.append("alloc")
            sections.append("alloc = AllocBar(\"\(String(localized: "Across your wallets"))\", \"\(segs)\")")
        }
        if !approvals.isEmpty {
            ids.append("ap")
            sections += rows(approvals, title: "Token approvals", widgetID: "ap", rowPrefix: "p")
        }
        if !activity.isEmpty {
            ids.append("act")
            sections += activityRows(activity, title: "Latest activity")
        }
        return ["root = Stack([ins\(ids.isEmpty ? "" : ", " + ids.joined(separator: ", "))])",
                "ins = Insight(\"\(genSafe(line))\")"] + sections
    }

    /// The `ValueSpark` doc line for the watched wallets — the combined series
    /// when more than one is watched, that single wallet's otherwise. nil (no
    /// section) with fewer than two samples: a one-point line is a dot claiming
    /// a trend. The subline names the anchor date, matching the value line's
    /// "since Jul 18".
    static func valueSparkLine() -> String? {
        let store = WalletStore.shared
        guard !store.addresses.isEmpty else { return nil }
        let samples = store.addresses.count > 1
            ? store.combinedValueSamples()
            : store.valueSamples(forAddress: store.addresses[0].address)
        guard samples.count >= 2, let first = samples.first else { return nil }
        let csv = samples.map { String(format: "%.2f", $0.usd) }.joined(separator: ",")
        let since = first.at.formatted(.dateTime.month(.abbreviated).day())
        return "spark = ValueSpark(\"\(String(localized: "Balance"))\", \"\(String(localized: "since \(since)"))\", \"\(csv)\")"
    }

    /// Latest-activity rows: a transfer draws its `TxRow` (asset mark,
    /// direction, amount, counterparty), everything else (swaps, Peer fills,
    /// Solana moves) keeps the generic `Row` on its title. One Widget hosting
    /// both, which `GenWidget.rowContent` now dispatches.
    private static func activityRows(_ things: [Thing], title: String) -> [String] {
        let ids = things.indices.map { "a\($0)" }
        var lines = ["act = Widget(\"\(title)\", \"\(things.count)\", [\(ids.joined(separator: ", "))])"]
        for (i, t) in things.enumerated() {
            if let dir = t.transferDirection, !dir.isEmpty {
                let action = dir == "received" ? "Received" : "Sent"
                lines.append("a\(i) = TxRow(\"\(action)\", \"\(genSafe(t.transferAmount ?? ""))\", \"\(genSafe(t.transferCounterparty ?? ""))\")")
            } else {
                lines.append("a\(i) = Row(\"\(genSafe(t.title))\", \"\(t.kind.typeTag)\", \"\(t.source)\", \"\(shortTime(t.capturedAt))\", \"\(t.id.uuidString)\")")
            }
        }
        return lines
    }

    /// An approval/Permit2 thing from `WalletApprovals` — the refs that pass
    /// carries (`wallet:approval:`/`wallet:permit2:`), vs the transfer/swap/
    /// Solana refs the activity pass lands.
    private static func isApproval(_ t: Thing) -> Bool {
        let ref = t.sourceRef ?? ""
        return ref.hasPrefix("wallet:approval:") || ref.hasPrefix("wallet:permit2:")
    }

    /// A wallet label safe for the AllocBar segment grammar — its `,` and `|`
    /// are the field/segment separators, so strip them (a name never needs
    /// them; a short address never has them).
    private static func allocSafe(_ s: String) -> String {
        genSafe(s).replacingOccurrences(of: "|", with: " ")
            .replacingOccurrences(of: ",", with: " ")
    }

    // MARK: - Aave / gas / Safe (2026-07-20)

    /// Simple `Insight`-only docs — these answer a single live number, not a
    /// list of things, so there's no `Thing`-backed row shape to build (the
    /// `rows()`/`TokenChip` idioms below both key off a real `Thing.id`).
    private static func walletDeFi() async -> Result? {
        guard let line = await WalletDeFiAsk.answer() else { return nil }
        return Result(delta: line, digest: line,
                      doc: ["root = Stack([ins])", "ins = Insight(\"\(genSafe(line))\")"])
    }

    private static func walletUniswap() async -> Result? {
        guard let line = await UniswapAsk.answer() else { return nil }
        return Result(delta: line, digest: line,
                      doc: ["root = Stack([ins])", "ins = Insight(\"\(genSafe(line))\")"])
    }

    private static func walletGas() async -> Result? {
        guard let line = await WalletGasAsk.answer() else { return nil }
        return Result(delta: line, digest: line,
                      doc: ["root = Stack([ins])", "ins = Insight(\"\(genSafe(line))\")"])
    }

    private static func walletSafe() async -> Result? {
        guard let line = await SafeAsk.answer() else { return nil }
        return Result(delta: line, digest: line,
                      doc: ["root = Stack([ins])", "ins = Insight(\"\(genSafe(line))\")"])
    }

    // MARK: - Watchlist

    /// The summary line PLUS a `TokenChip` row per mover — mirrors
    /// `RootShell.answerDocument`'s free-text watchlist branch exactly (same
    /// 6-shown cap, same route guard), so a kept "How's my watchlist?" and a
    /// typed one can never disagree about what's shown.
    private static func watchlist(context: ModelContext) async -> Result? {
        // Markets count as a watchlist too (2026-07-28). Before this the ask
        // was tokens-only, so someone watching five Kalshi markets and no
        // tokens asked "how's my watchlist?" and was told it was empty —
        // which was a fake status, not an answer (honesty rule).
        let markets = MarketsAsk.moves(context: context)
        guard !TokensAsk.watched(context).isEmpty || !markets.isEmpty else { return nil }
        let moves = await TokensAsk.moves(context: context)
        guard !moves.isEmpty || !markets.isEmpty else {
            // Watched, but every pulse fetch failed — not the same as an
            // empty watchlist (honesty rule already paid for in
            // RootShell.answerDocument; this composer was missing it).
            return Result(delta: "", digest: "unreachable",
                          doc: ["root = Stack([ins])",
                                "ins = Insight(\"\(genSafe("Couldn't read your watchlist's prices right now."))\")"])
        }
        // Tokens lead when there are any (the older, denser read); a
        // markets-only watchlist speaks in its own voice rather than
        // borrowing a line about prices.
        let line = moves.isEmpty ? MarketsAsk.line(markets) : TokensAsk.line(moves)
        return Result(delta: line, digest: line,
                      doc: watchlistDoc(line: line, moves: moves, markets: markets))
    }

    /// Shared by the kept-ask composer and `RootShell.answerDocument`'s
    /// free-text watchlist branch.
    static func watchlistDoc(line: String, moves: [TokensAsk.Move],
                             markets: [MarketsAsk.Move] = []) -> [String] {
        let shown = moves.prefix(6).compactMap { m in
            TokenChart.route(from: m.thing.content).map { (move: m, route: $0) }
        }
        let marketRows = MarketsAsk.rows(markets)
        // One mover earns the FULL scrubbable curve (ChartCard), not a lone
        // chip — the same tall-vs-compact dose split TokenChart draws
        // everywhere else (2026-07-21). Two or more keep the chip list.
        // Markets never displace that: they follow as their own group, so a
        // watchlist holding both reads as two lists, not one blended one.
        if shown.count == 1, marketRows.isEmpty {
            let s = shown[0]
            return ["root = Stack([ins, chart])",
                    "ins = Insight(\"\(genSafe(line))\")",
                    "chart = ChartCard(\"\(genSafe(s.move.symbol))\", \"\(s.route.chain)\", \"\(s.route.address)\")"]
        }
        let kids = ["ins", shown.isEmpty ? nil : "res", marketRows.isEmpty ? nil : "mkt"]
            .compactMap(\.self).joined(separator: ", ")
        var doc = ["root = Stack([\(kids)])",
                   "ins = Insight(\"\(genSafe(line))\")"]
        if !shown.isEmpty {
            let ids = shown.indices.map { "t\($0)" }
            doc.append("res = Widget(\"\(String(localized: "Watchlist"))\", \"\(shown.count)\", [\(ids.joined(separator: ", "))])")
            for (i, s) in shown.enumerated() {
                doc.append("t\(i) = TokenChip(\"\(genSafe(s.move.symbol))\", \"\(s.route.chain)\", \"\(s.route.address)\", \"\(s.move.thing.id.uuidString)\", \"\")")
            }
        }
        doc.append(contentsOf: marketRows)
        return doc
    }

    // MARK: - What's overdue

    /// Mirrors `HomeComposition.tileSignal`'s Reminders/Todoist branch —
    /// light, deliberate duplication of ~3 lines rather than reaching into
    /// that private function, consistent with how HomeComposition and
    /// RootShell already each read `Thing` fields independently.
    private static func overdue(_ things: [Thing]) -> Result? {
        let open = things.filter { $0.mark != .done && overdueSources.contains($0.source) }
        let overdue = open.filter { ($0.dueAt ?? .distantFuture) < .now }
        guard !overdue.isEmpty else {
            return Result(delta: "", digest: "0",
                          doc: ["root = Stack([ins])",
                                "ins = Insight(\"\(genSafe("Nothing overdue."))\")"])
        }
        let sorted = overdue.sorted { ($0.dueAt ?? .now) < ($1.dueAt ?? .now) }
        let delta = "\(overdue.count), \(overdue.count == 1 ? "1 thing" : "\(overdue.count) things") late"
        let line = String(localized: "\(overdue.count) thing overdue.")
        // AgendaRow, not the generic Row — an overdue task has a due date, so
        // it draws on the time rail (the most-overdue leads, emphasized).
        // The axis leads when there's a spread to show (2026-08-14, prd §384):
        // four rows can't say whether the lateness is one bad afternoon or a
        // month of drift — the runway can, and the standing rule above
        // (`compose`'s own doc) is that an ask backed by a real visualization
        // always shows it. Over EVERY overdue thing, not the four listed,
        // for `TodayBrief.runwayCard`'s reason: truncating the shape
        // understates a pile-up precisely when there is one.
        let axis = runwayAxis(sorted)
        return Result(delta: delta, digest: "\(overdue.count)",
                      doc: ["root = Stack([\(axis == nil ? "ins, res" : "ins, axis, res")])",
                            "ins = Insight(\"\(genSafe(line))\")"]
                          + (axis.map { [$0] } ?? [])
                          + agendaRows(Array(sorted.prefix(4)), title: "Overdue"))
    }

    // MARK: - What's coming up

    /// The forward half of `overdue` (2026-07-21) — the deadlines that HAVEN'T
    /// passed yet.
    ///
    /// Nothing in the app surfaced a future `dueAt` before this. The old "Coming
    /// up" card did, and it died with the Home board (prd §131) as a renderer
    /// with no surviving emitter; since then `dueAt` has only ever been read
    /// looking BACKWARD, by `overdue`. That left a real gap rather than a
    /// cosmetic one: 1Claw already lands grant expiries as a structured
    /// `dueAt`, and they were invisible until the day they expired.
    ///
    /// Scoped to DEADLINES, never to calendar events. An event's start rides
    /// `capturedAt`, and folding those in here would rebuild the lane §101 cut
    /// back for making the feed "something it isn't" — a person who sees their
    /// whole day in Casberi stops opening their calendar. A chip you ask beats a
    /// card that announces, which is also why this is the surface the §131
    /// settlement points at.
    ///
    /// Unlike `overdue` this is NOT restricted to Reminders/Todoist: any bridge
    /// that lands a real deadline belongs here, which is the whole reason it can
    /// carry grant expiries and (next) ENS names without being touched again.
    /// The words that name this ask. ONE definition, read by both the typed
    /// answer path (`RootShell.answerDocument`) and the keepable-kind
    /// recognizer (`Composer`) — so a query that answers can always also be
    /// kept, and neither can drift from the other.
    static func matchesUpcoming(_ query: String) -> Bool {
        let q = query.lowercased()
        return q.contains("coming up") || q.contains("due soon")
            || q.contains("what's due") || q.contains("whats due")
    }

    private static func upcoming(_ things: [Thing]) -> Result? {
        let horizon = Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now
        let due = things
            .filter { t in
                guard t.mark != .done, let when = t.dueAt else { return false }
                // `>= .now` keeps this and `overdue` disjoint — a deadline is in
                // exactly one of the two chips, never counted by both.
                return when >= .now && when <= horizon
            }
            .sorted { ($0.dueAt ?? .now) < ($1.dueAt ?? .now) }
        guard !due.isEmpty else {
            return Result(delta: "", digest: "0",
                          doc: ["root = Stack([ins])",
                                "ins = Insight(\"\(genSafe(String(localized: "Nothing due in the next week.")))\")"])
        }
        let line = due.count == 1
            ? String(localized: "1 thing due in the next week.")
            : String(localized: "\(due.count) things due in the next week.")
        let delta = "\(due.count), \(due.count == 1 ? "1 thing" : "\(due.count) things") due"
        // The axis leads (2026-08-14, prd §384) — the rows can't show the
        // SPREAD, which is the one thing "what's due" is really asking: a
        // clear week with one Friday deadline and a pile-up tomorrow are the
        // same four rows without it.
        let axis = runwayAxis(due)
        return Result(delta: delta, digest: "\(due.count)",
                      doc: ["root = Stack([\(axis == nil ? "ins, res" : "ins, axis, res")])",
                            "ins = Insight(\"\(genSafe(line))\")"]
                          + (axis.map { [$0] } ?? [])
                          + agendaRows(Array(due.prefix(4)), title: String(localized: "Coming up")))
    }

    /// The `Runway` axis over date-bearing things, in due order — nil under 2
    /// dots (`GenRunway`'s own floor: one dot on an axis is a dot). Labels
    /// carry the ends as DATES, never a count — the Insight line above each
    /// caller already states the count, and `TodayBrief.runwayCard`'s
    /// `statedOverdue` lesson is that an axis restating the headline is the
    /// duplication complaint in miniature. When everything is overdue the
    /// window ends at now, so the labels swap sides to stay truthful.
    /// Internal rather than private since 2026-08-16 (`AnswerFigure`'s time
    /// rung). Callers must hand it rows that really carry a `dueAt`, in due
    /// order — the `?? now` below is a formatting fallback, not a filter.
    static func runwayAxis(_ sorted: [Thing]) -> String? {
        guard sorted.count >= 2 else { return nil }
        let now = Date.now
        let lanes = sorted.map {
            "\(Int(($0.dueAt ?? now).timeIntervalSince1970))|\(genSafe($0.source))"
        }
        let allOverdue = sorted.allSatisfy { ($0.dueAt ?? .distantFuture) < now }
        let near = allOverdue
            ? (sorted.first?.dueAt ?? now).formatted(.dateTime.month(.abbreviated).day())
            : String(localized: "now")
        let far = allOverdue
            ? String(localized: "now")
            : (sorted.last?.dueAt ?? now).formatted(.dateTime.month(.abbreviated).day())
        return "axis = Runway(\"\", \"\(lanes.joined(separator: ";"))\", \"\(Int(now.timeIntervalSince1970))\", \"\(genSafe(near))\", \"\(genSafe(far))\")"
    }

    /// Agenda rows for date-bearing things — the due date on the time rail,
    /// the title beside it, the first row emphasized ("next" — start here).
    private static func agendaRows(_ things: [Thing], title: String) -> [String] {
        let ids = things.indices.map { "r\($0)" }
        var lines = ["res = Widget(\"\(title)\", \"\(things.count)\", [\(ids.joined(separator: ", "))])"]
        for (i, t) in things.enumerated() {
            let when = (t.dueAt ?? t.capturedAt).formatted(.dateTime.month(.abbreviated).day())
            let state = i == 0 ? "next" : ""
            lines.append("r\(i) = AgendaRow(\"\(genSafe(when))\", \"\(genSafe(t.title))\", \"\(t.source)\", \"\(state)\")")
        }
        return lines
    }

    // MARK: - Show <tag>

    private static func showtag(_ tag: String, things: [Thing]) -> Result? {
        let matched = things.filter { thing in
            thing.tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
        }
        guard !matched.isEmpty else { return nil }
        let line = String(localized: "\(matched.count) thing tagged \(tag).")
        return Result(delta: "\(matched.count) things", digest: "\(matched.count)",
                      doc: ["root = Stack([ins, res])", "ins = Insight(\"\(genSafe(line))\")"]
                          + rows(Array(matched.prefix(6)), title: "Tagged \(tag)"))
    }

    // MARK: - Named asks (2026-07-22, user: "i should be able to ask things
    // like 'synthesize my verge feed' or 'what happened in bbc'")

    /// What a "name a source/publisher" ask actually scopes to. A PUBLISHER
    /// name (an RSS feed's own title, a Substack, a watched social handle —
    /// all stamped in `Thing.authorHandle`) is a real, useful scope that
    /// "verge"/"bbc" name — and a DIFFERENT one from the bridge-level
    /// `.source`/`.category` cases below (Calendar, GitHub, "my Markets
    /// stuff"), which `namedAskTarget` already answered before this.
    enum NamedAskTarget {
        case source(String)
        case handle(String)
        case category(String)

        /// The kept-ask KIND this target composes as — ONE mapping, so the
        /// live path and the kept-pill re-run can never answer the same
        /// target two different ways.
        var keptKind: String {
            switch self {
            case .source(let s):   return "context:\(s)"
            case .handle(let h):   return "handle:\(h)"
            case .category(let c): return "category:\(c)"
            }
        }

        /// The bare resolved name (the publisher/source/category), for a
        /// caller that wants to rephrase the ask ("synthesize <name>") — one
        /// accessor, so name extraction lives on the enum, not re-switched at
        /// each call site.
        var name: String {
            switch self {
            case .source(let s):   return s
            case .handle(let h):   return h
            case .category(let c): return c
            }
        }

        /// The raw pool this target scopes to, BEFORE any recency windowing —
        /// `RootShell`'s live synthesis path windows/caps this itself; the
        /// deterministic composers below window it again, independently (the
        /// same "light duplication of window logic" `contextRecap` and
        /// `TodayBrief.compose(category:)`'s own Stage-1 filter each own, not
        /// a shared dependency).
        func pool(in things: [Thing]) -> [Thing] {
            switch self {
            case .source(let s): return things.filter { $0.source == s }
            case .handle(let h): return things.filter { $0.authorHandle == h }
            case .category(let c):
                let sources = KeptAskComposers.categorySources(c)   // hoisted: once, not per row
                return things.filter { sources.contains($0.source) }
            }
        }

        /// Whether this target is safe to KEEP — `.source`/`.handle` are
        /// self-gating by construction (`namedAskTarget` only ever returns
        /// one that already has a matching thing), but `.category` names a
        /// fixed catalog entry independent of what's actually connected, so
        /// it needs its own check (mirrors the "never mint a kind that can
        /// only ever say nothing" rule every other kept kind already keeps).
        func hasRealThings(in things: [Thing]) -> Bool {
            switch self {
            case .source, .handle: return true
            case .category: return !pool(in: things).isEmpty
            }
        }
    }

    /// A per-publisher or per-source ask — "synthesize my Verge feed", "what
    /// happened in BBC", "what's new in Calendar", "how's my GitHub". ONE
    /// definition, read by BOTH `RootShell.answerDocument` (the live path)
    /// and `Composer.recognizeKeptAskKind` (the keepable-kind recognizer) —
    /// the same precedent `matchesUpcoming` already sets.
    ///
    /// A PUBLISHER/HANDLE match is tried FIRST: RSS/Substack/Podcasts/social
    /// accounts all stamp their author in `Thing.authorHandle` ("The Verge",
    /// "BBC News", a Farcaster handle) — so "verge"/"bbc" name a publisher
    /// WITHIN a bridge, not the bridge itself, and the earlier bridge-only
    /// recognizer had no way to answer them at all. Matched FUZZILY
    /// (case-insensitive, either containing the other, via `bestHandle`)
    /// because a publisher's real name is free text someone names casually
    /// ("verge" for "The Verge") — unlike a bridge SOURCE or catalog
    /// CATEGORY, both small fixed vocabularies that stay exact-match. Falls
    /// back to the exact bridge/category match otherwise — every phrase that
    /// already worked keeps working.
    ///
    /// The sources a BRIEF SCOPE (Money/Work/Life) covers. ONE join, so the
    /// live ask, a kept `category:` pill, `TodayBrief.compose(category:)`'s
    /// Stage-1 filter and the SCOPED FETCH that feeds them can never disagree
    /// about what a scope contains — four readers, one definition.
    /// `nonisolated` because `NamedAskTarget.pool(in:)` is — a nested type in a
    /// `@MainActor` enum does not inherit that isolation, and this reads only
    /// the catalog's own static tables.
    nonisolated static func categorySources(_ scope: String) -> Set<String> {
        Set(BridgeCatalog.offers
            .filter { BriefScope.scope(forCatalogCategory: BridgeCatalog.category(of: $0)) == scope }
            .map(\.name))
    }

    /// `things` is an `@autoclosure` (PERF 2026-08-11), for the reason
    /// `AggregateAsk.parse` and `StatusAsk.pulse` already take theirs that
    /// way: every check that can resolve WITHOUT the corpus runs first — the
    /// polite-lead strip, the prefix table, the brief-scope names and the
    /// catalog category names — and only `bestHandle`'s fuzzy match and the
    /// source lookup need it. So "what's going on with money", which is what
    /// the scope chips send, now resolves its target without materialising a
    /// single row. Evaluated at most once here, whatever the caller passes.
    static func namedAskTarget(_ query: String, things fetchThings: @autoclosure () -> [Thing])
        -> (target: NamedAskTarget, synthesize: Bool)? {
        var cached: [Thing]?
        func things() -> [Thing] {
            if let cached { return cached }
            let fetched = fetchThings()
            cached = fetched
            return fetched
        }
        var q = query.lowercased().trimmingCharacters(in: .whitespaces)
        // A politeness lead is not part of the ask (2026-08-05). "Can you
        // search my X stuff" is the same question as "search my X", and
        // without this it matched no prefix at all and fell through to the
        // term-scored retriever, which is how a question naming a real source
        // came back with things that merely contain the word "can".
        for lead in politeLeads where q.hasPrefix(lead) {
            q = String(q.dropFirst(lead.count)).trimmingCharacters(in: .whitespaces)
            break
        }
        for (prefix, synth) in namedAskPrefixes where q.hasPrefix(prefix) {
            var name = String(q.dropFirst(prefix.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "? "))
                .trimmingCharacters(in: .whitespaces)
            // "...Markets STUFF?" / "...verge FEED" — casual phrasing tacks a
            // generic filler noun onto the real name; strip it so "markets
            // stuff"/"verge feed" match the bare name "markets"/"verge".
            for filler in [" feed", " stuff", " things", " activity"] where name.hasSuffix(filler) {
                name = String(name.dropLast(filler.count))
            }
            // "what did Sam SEND ME" / "what's mara.eth POSTING" — the person
            // phrasings (2026-07-22) tack a trailing verb and/or pronoun onto
            // the name; drop those so bestHandle sees just "sam"/"mara.eth".
            // Trailing-only and a fixed verb/pronoun set, so a real name that
            // happens to contain one of these words mid-string is untouched.
            var words = name.split(separator: " ").map(String.init)
            while let last = words.last, trailingPersonWords.contains(last) {
                words.removeLast()
            }
            name = words.joined(separator: " ")
            guard !name.isEmpty else { continue }
            // Checked BEFORE `bestHandle` (moved 2026-08-08, found live: "how's
            // my work stuff" resolved to "@workspaces" — a real demo handle,
            // matched because `bestHandle` is a SUBSTRING test
            // (`lower.contains(name)`, so "workspaces".contains("work") is
            // true) and used to run first). An EXACT match against the brief
            // scope's small, fixed vocabulary ("money"/"work"/"life") must
            // beat a fuzzy match against arbitrary corpus handles, or any
            // scope name that happens to prefix a real handle is
            // unreachable by voice for as long as that handle is connected.
            // Checked in this order so BOTH vocabularies resolve: the brief
            // SCOPE name directly ("money", "work", "life" — what the chips
            // and the "How's my X stuff?" phrasing actually send), and the
            // app catalog's own ten category names ("wallet", "markets",
            // "agents", "notes", …), mapped through the same join
            // `TodayBrief.compose(category:)` uses — so "what's going on
            // with wallet" and "what's going on with money" answer
            // identically rather than one silently falling through.
            if let scope = BriefScope.scopes.first(where: { $0.lowercased() == name }) {
                return (.category(scope), synth)
            }
            if let cat = BridgeCatalog.categories.first(where: { $0.name.lowercased() == name })?.name {
                return (.category(BriefScope.scope(forCatalogCategory: cat)), synth)
            }
            if let handle = bestHandle(matching: name, things: things()) {
                return (.handle(handle), synth)
            }
            // `Corpus.earnsRoom` gates it (ruling 2026-08-02): this intent's
            // whole payload is "land on that source's room", and a source
            // without one would mint a `context:` ask — keepable, pinned, and
            // permanently landing on All. The only producer of `.source`, so
            // guarding here retires the destination rather than papering over
            // it at the navigation end.
            if let source = Set(things().map(\.source))
                .first(where: { $0.lowercased() == name && Corpus.earnsRoom($0) }) {
                return (.source(source), synth)
            }
        }
        return nil
    }

    /// The verbs a named ask can wear, and whether each ASKS FOR REAL PROSE.
    /// "synthesize"/"summarize"/"recap" want the model's own synthesis over
    /// the pool (RootShell's live-only upgrade, honest-degrading to the
    /// deterministic recap below when the model declines or is unavailable);
    /// "what's new in"/"what happened in"/"how's my" want the plain counted
    /// recap they've always gotten. A KEPT pill ignores this flag entirely —
    /// it always re-runs the deterministic recap (ruling 13's principle: a
    /// kept ask never re-synthesizes, it shows what the answer was drawn
    /// from), so the same target answers identically on every future open
    /// regardless of which verb minted it.
    private static let namedAskPrefixes: [(prefix: String, synth: Bool)] = [
        ("synthesize my ", true), ("synthesize ", true),
        ("summarize my ", true), ("summarize ", true),
        ("recap my ", true), ("recap ", true),
        ("what happened in ", false), ("what happened with ", false), ("what happened on ", false),
        ("whats happened in ", false), ("whats happened with ", false), ("whats happened on ", false),
        ("what's new in ", false), ("whats new in ", false),
        ("what's new from ", false), ("whats new from ", false),
        ("what's up with my ", false), ("whats up with my ", false),
        ("how's my ", false), ("hows my ", false),
        // Scoped "What's going on" briefs (scoped-brief-spec.md): "what's
        // going on with work" names a CATEGORY the same way "how's my Work
        // stuff" already does — `namedAskTarget`'s own category-name match
        // below only fires once the prefix is stripped and the remainder is
        // an exact `BridgeCatalog.categories` name, so a real subject that
        // ISN'T a category ("what's going on with sam") still falls through
        // exactly as before (the bare, subjectless phrase stays
        // `TodayBrief.matches`' own exact match, checked earlier and
        // unaffected — this prefix only ever fires with a trailing name).
        ("what's going on with ", false), ("whats going on with ", false),
        ("what's going on in ", false), ("whats going on in ", false),
        // Person/sender phrasings (2026-07-22) — resolve to the same handle
        // scope (a sender's name lives in `authorHandle` like a publisher's).
        // Deliberately SPECIFIC prefixes: a bare "what's " would fuzzy-match
        // "what's new" to "BBC News" (contains "new"), so the person forms
        // all carry a distinguishing word ("did"/"from").
        ("what did ", false),
        ("anything from ", false), ("anything new from ", false),
        // The plain LOOKUP verbs (2026-08-05). A person who has just imported
        // years of something asks for it by name — "search my X", "show me my
        // Instagram" — and every phrasing above wanted news instead, so the
        // most natural way to reach a room was the one way that missed. Longer
        // forms lead, matching this table's own convention, since the loop
        // takes the first prefix that both matches and resolves.
        //
        // Safe to widen: a residual that names no real source, handle or
        // category returns nil and the caller falls straight through to the
        // retriever, which is what these queries already did.
        ("search my ", false), ("search ", false),
        ("show me my ", false), ("show me ", false), ("show my ", false),
        ("look through my ", false), ("look through ", false),
        ("go through my ", false),
    ]

    /// Leading politeness that isn't part of the question. Stripped before the
    /// prefix table is consulted, so "can you search my X stuff" is the same
    /// ask as "search my X".
    private static let politeLeads = [
        "can you please ", "could you please ", "can you ", "could you ",
        "would you ", "please ", "hey ", "ok ", "okay ",
    ]

    /// Trailing verbs/pronouns the person phrasings tack onto a name —
    /// stripped so "what did sam send me" resolves to "sam".
    private static let trailingPersonWords: Set<String> = [
        "send", "sent", "sending", "post", "posted", "posting", "share",
        "shared", "sharing", "say", "said", "saying", "write", "wrote",
        "writing", "me", "us", "lately", "recently",
    ]

    /// The real, stored handle that best matches a fuzzy name. Case-
    /// insensitive, either containing the other ("verge" ⊂ "The Verge",
    /// "bbc" ⊂ "BBC News"); the handle with the MOST things wins when more
    /// than one qualifies — the one useful single choice, no disambiguation
    /// UI. nil when nothing in the corpus is close.
    private static func bestHandle(matching name: String, things: [Thing]) -> String? {
        var counts: [String: Int] = [:]
        for t in things {
            guard let raw = t.authorHandle?.trimmingCharacters(in: .whitespaces), !raw.isEmpty
            else { continue }
            let lower = raw.lowercased()
            guard lower.contains(name) || name.contains(lower) else { continue }
            counts[raw, default: 0] += 1
        }
        return counts.max(by: { $0.value < $1.value })?.key
    }

    // MARK: - What's new from <publisher>

    /// A per-PUBLISHER recap ("what happened in BBC") — `contextRecap`'s
    /// handle-scoped twin. Filters by the EXACT, already-resolved
    /// `authorHandle` `namedAskTarget` matched fuzzily once, at recognition
    /// time — never re-fuzzed here, so a kept pill's re-run stays a fixed,
    /// honest lookup forever, the same discipline `context:<source>` already
    /// keeps for bridges.
    private static func handleRecap(_ handle: String, things: [Thing]) -> Result? {
        // A handle that belongs to an IMPORTED room has `contextRecap`'s
        // always-empty window for the same reason (2026-08-05), and it became
        // reachable the day X's face pass started stamping the authors of
        // liked posts: "what did I like from @someone" over an archive is a
        // question about years, and a three-day window answers it "nothing"
        // every time. Decided on where the handle's things actually LIVE, not
        // on the handle, since the same person can be a followed publisher in
        // one room and an imported author in another.
        let owned = things.filter { $0.authorHandle == handle }
        if !owned.isEmpty, owned.allSatisfy({ Corpus.bulkImportSources.contains($0.source) }) {
            return archiveRecap(label: handle, pool: owned)
        }
        let now = Date.now
        var pool = things.filter { $0.authorHandle == handle && $0.capturedAt >= now.addingTimeInterval(-3 * 86_400) }
        var windowWords = "in the last three days"
        if pool.isEmpty {
            pool = things.filter { $0.authorHandle == handle && $0.capturedAt >= now.addingTimeInterval(-7 * 86_400) }
            windowWords = "in the last week"
        }
        guard !pool.isEmpty else {
            return Result(delta: "", digest: "0",
                          doc: ["root = Stack([ins])",
                                "ins = Insight(\"\(genSafe("Nothing new from \(handle) recently."))\")"])
        }
        let line = String(localized: "\(pool.count) thing from \(handle) \(windowWords).")
        return Result(delta: "\(pool.count) things", digest: "\(pool.count)",
                      doc: recapDoc(line: line, pool: pool,
                                    barsEyebrow: "This week", rowsTitle: "From \(handle)"))
    }

    // MARK: - What's new in <source>

    /// A per-source recap ("What's new in GitHub?") — the same recency
    /// window `StatusAsk`'s no-timeframe default uses (three days, widening
    /// to a week when quiet), scoped to one source. Light duplication of
    /// that widening rather than reaching into `StatusAsk.pulse` (which
    /// parses a natural-language CUE, not a bare source name) — same
    /// precedent as `overdue`'s duplication above.
    private static func contextRecap(_ source: String, things: [Thing]) -> Result? {
        // An ARCHIVE is never "new" and asking it what arrived this week is a
        // question with one possible answer (2026-08-05). Every
        // `Corpus.bulkImportSources` member lands its whole corpus in one pass,
        // dated across the years it really happened in — so the three-day and
        // one-week windows below are both empty the moment the import
        // finishes, and "what's new in X" answered "Nothing new from X
        // recently" over a room holding thousands of things, permanently.
        // These rooms get a recap of what they HOLD instead.
        if Corpus.bulkImportSources.contains(source) {
            return archiveRecap(source, things: things)
        }
        let now = Date.now
        var pool = things.filter { $0.source == source && $0.capturedAt >= now.addingTimeInterval(-3 * 86_400) }
        var windowWords = "in the last three days"
        if pool.isEmpty {
            pool = things.filter { $0.source == source && $0.capturedAt >= now.addingTimeInterval(-7 * 86_400) }
            windowWords = "in the last week"
        }
        guard !pool.isEmpty else {
            return Result(delta: "", digest: "0",
                          doc: ["root = Stack([ins])",
                                "ins = Insight(\"\(genSafe("Nothing new from \(source) recently."))\")"])
        }
        let line = String(localized: "\(pool.count) thing from \(source) \(windowWords).")
        return Result(delta: "\(pool.count) things", digest: "\(pool.count)",
                      doc: recapDoc(line: line, pool: pool,
                                    barsEyebrow: "This week", rowsTitle: "From \(source)"))
    }

    /// What an imported room HOLDS, for the sources whose whole corpus arrived
    /// at once (2026-08-05, prd §280 amendment).
    ///
    /// The shape follows from what the question can honestly mean here. "How's
    /// my X?" over an archive is not a question about this week — there is no
    /// this week — it's a question about a body of things, so the answer states
    /// its SIZE and its SPAN and then shows the newest of it. The span is the
    /// fact a person can't get any other way and the one that makes the room
    /// feel like a corpus rather than a list: "3,214 things from X, 2011 to
    /// 2026" is the sentence that says the import worked.
    ///
    /// No `dailyBars`: a seven-day chart over a decade-old archive is seven
    /// empty columns, which reads as a broken card rather than as an honest
    /// zero. `rows` alone, newest first, each a door into the room.
    private static func archiveRecap(_ source: String, things: [Thing]) -> Result? {
        archiveRecap(label: source, pool: things.filter { $0.source == source })
    }

    /// The archive shape over an already-scoped pool — shared by the
    /// source-scoped recap above and the handle-scoped one, which has the same
    /// always-empty window for the same reason once a handle belongs to an
    /// imported room.
    private static func archiveRecap(label: String, pool unsorted: [Thing]) -> Result? {
        // The import's own receipt is the app talking about itself, and every
        // other aggregate over these rooms already excludes it.
        let pool = unsorted
            .filter { !Corpus.isImportReceipt($0) }
            .sorted { $0.capturedAt > $1.capturedAt }
        guard let newest = pool.first, let oldest = pool.last else {
            return Result(delta: "", digest: "0",
                          doc: ["root = Stack([ins])",
                                "ins = Insight(\"\(genSafe("Nothing imported from \(label) yet."))\")"])
        }
        let calendar = Calendar.current
        let from = calendar.component(.year, from: oldest.capturedAt)
        let to = calendar.component(.year, from: newest.capturedAt)
        // A single-year archive says the year once rather than "2026 to 2026".
        let span = from == to ? "\(from)" : "\(from) to \(to)"
        let line = String(localized: "\(pool.count) things from \(label), \(span).")
        return Result(delta: "\(pool.count) things", digest: "\(pool.count)|\(span)",
                      doc: ["root = Stack([ins, res])",
                            "ins = Insight(\"\(genSafe(line))\")"]
                          + rows(Array(pool.prefix(6)), title: "Newest from \(label)"))
    }

    // MARK: - What's up with my <category>
    //
    // The whole-CATEGORY recap ("How's my Markets stuff?") used to live here
    // as its own plain "N things from your X apps this week" composer. It's
    // gone (scoped-brief-spec.md): `category:<c>` now dispatches straight to
    // `TodayBrief.compose(category:)` above, which is the SAME signal-board
    // pipeline `"today"` runs — the spec's own "one pipeline, two parameters,
    // not a new feature" — rather than a second, plainer answer shape for the
    // same question.

    /// A recap document: the summary line, a `Bars` chart of when the pool's
    /// things landed over the last week (dropped when too few to shape), then
    /// the rows. Shared by the per-source and per-category recaps so they can't
    /// drift. `dailyBars` counts in-memory over `capturedAt` — no model.
    private static func recapDoc(line: String, pool: [Thing],
                                 barsEyebrow: String, rowsTitle: String) -> [String] {
        let bars = dailyBars(pool, eyebrow: barsEyebrow)
        let ids = bars == nil ? "ins, res" : "ins, bars, res"
        var doc = ["root = Stack([\(ids)])", "ins = Insight(\"\(genSafe(line))\")"]
        if let bars { doc.append(bars) }
        return doc + rows(Array(pool.prefix(6)), title: rowsTitle)
    }

    /// A `Bars` doc line — how many of `things` were captured on each of the
    /// last seven days, labeled by narrow weekday. nil when too few to shape
    /// (a two-item week reads as a list, not a chart). Deterministic,
    /// in-memory over `capturedAt`.
    ///
    /// Internal rather than file-private since 2026-08-15: `AnswerFigure` draws
    /// the same chart over a free-text answer's retrieved set. Note what that
    /// caller has to do and this one doesn't — the floor below counts what it is
    /// HANDED, not what falls inside the window, which is correct here (every
    /// caller in this file passes an already-window-scoped pool) and would draw
    /// seven empty columns over an archive. `AnswerFigure` filters to the window
    /// before calling; do the same for any new caller whose pool isn't already
    /// scoped, rather than moving the floor and changing this one's behaviour.
    static func dailyBars(_ things: [Thing], eyebrow: String) -> String? {
        guard things.count >= 4 else { return nil }
        let days = 7
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        var counts = [Int](repeating: 0, count: days)
        for t in things {
            let day = cal.startOfDay(for: t.capturedAt)
            let delta = cal.dateComponents([.day], from: day, to: today).day ?? 999
            if delta >= 0, delta < days { counts[days - 1 - delta] += 1 }
        }
        let labels = (0..<days).map { i -> String in
            let day = cal.date(byAdding: .day, value: -(days - 1 - i), to: today) ?? today
            return day.formatted(.dateTime.weekday(.narrow))
        }
        return "bars = Bars(\"\(genSafe(eyebrow))\", \"\", \"\(counts.map(String.init).joined(separator: ","))\", \"\(labels.joined(separator: ","))\")"
    }

    /// The dial's mark budget for an ANSWER (2026-08-16).
    ///
    /// `AgentPanelFigures.dial` caps at 400 of its own, which is right for a
    /// tile composed in memory and wrong for a line that has to be written into
    /// a document, streamed a character at a time and re-parsed on every
    /// snapshot: 400 marks is roughly a 9KB line. At the ~150pt the answer draws
    /// it, 120 dots already saturate the face, so the extra 280 buy nothing a
    /// person can see and cost something the renderer feels.
    static let dialMarkCap = 120

    /// A week of things on a 24-HOUR CLOCK — the WHEN rung above `dailyBars`
    /// (2026-08-16, user: "dial for when as an answer in composer is good").
    ///
    /// Answers the question the bars can only approximate. Seven columns say
    /// which DAYS; nothing else in this app says which HOURS, and for "when did
    /// these land" the hour is the more particular fact — a week that all
    /// happened after ten at night and a week spread across every waking hour
    /// draw the identical bar strip.
    ///
    /// THE ARITHMETIC IS NOT NEW and is deliberately not re-derived here.
    /// `AgentPanelFigures.dial` has placed marks on this clock since §339 and is
    /// covered by `agent-panel-selftest`; this hands it the rows and serialises
    /// what comes back. The figure lost its only home when the agent panel was
    /// deleted (§386p) — this is where it lives now.
    ///
    /// The window is `AnswerFigure.barsWindowDays` rather than the composer's
    /// own default, so the two WHEN rungs can never disagree about which week
    /// they are describing.
    static func dialLine(_ things: [Thing], eyebrow: String, now: Date = .now) -> String? {
        let marks = AgentPanelFigures.dial(
            things.map { AgentPanelFigures.Entry(source: $0.source, at: $0.capturedAt) },
            now: now, days: AnswerFigure.barsWindowDays, cap: dialMarkCap)
        // The RENDERER'S floor, not one of ours — a line this emitter thought
        // worth writing and `GenDial` refuses to draw is an answer with a hole
        // where its figure should be.
        guard marks.count >= AgentPanel.Figure.dialFloor else { return nil }
        let rows = marks.map {
            // Two decimals: the hour is fractional (9:41 is 9.68) and the ring
            // is a normalised 0…1, so this is the precision the drawing can
            // actually show — more of it is line length nobody sees.
            "\(round($0.hour * 100) / 100)|\(round($0.recency * 100) / 100)|\(mapSafe($0.source))"
        }
        return "dial = Dial(\"\(genSafe(eyebrow))\", \"\(rows.joined(separator: ";"))\")"
    }

    // MARK: - Kept search

    /// How many matches a find DRAWS. The count it REPORTS is the true total —
    /// the two were the same number until 2026-08-13, and that is the bug: the
    /// engine capped at 16 for the model's benefit and this drew 6 of them, so
    /// a search over a 3,500-post archive said "16 things match" and showed
    /// six, with no door to the rest. Twelve is a screenful you can scan; the
    /// remainder is now counted out loud rather than silently discarded.
    static let searchRowLimit = 12

    /// A free-text ask kept as a standing search (docs/agent-brief.md ruling
    /// 13, 2026-07-20) — re-runs `Retriever.rank` EVERY time, the same
    /// deterministic engine `RootShell.answerDocument`'s general retrieval
    /// branch uses, never the model. The honest degradation this requires:
    /// a kept "summarize my week" shows what the summary was drawn from, not
    /// a re-synthesized summary — the chip's title is the ORIGINAL question,
    /// the answer is "here's what matches now."
    ///
    /// Internal rather than file-private since 2026-07-25: the composer's Find
    /// chip calls this directly for an ad-hoc, un-kept search. That is the
    /// same engine on the same terms — the kept version just runs it on a
    /// schedule — so routing both through one function is what keeps "Find
    /// never synthesizes" true of both by construction rather than by two
    /// implementations agreeing.
    static func search(_ query: String, things: [Thing],
                       dropping: Set<Retriever.Scope.Kind> = [],
                       standing: Bool = false) -> Result? {
        let outcome = Retriever.find(query, in: things, dropping: dropping)
        let hits = outcome.hits
        guard !hits.isEmpty else {
            // A STANDING search that has gone quiet and a fresh find that
            // never matched are different sentences. "anymore" was written for
            // the kept chip re-running on a schedule, and reading it after
            // typing a word for the first time says the search used to work.
            let line = standing
                ? String(localized: "Nothing matches anymore.")
                : String(localized: "Nothing matches.")
            // An empty result whose filters are visible is explicable; one
            // whose filters are hidden reads as a broken search. Naming them
            // costs no second pass — `find` already reported what it applied.
            let why = outcome.scopes.isEmpty ? nil
                : String(localized: "Searched only \(scopeList(outcome.scopes)).")
            var empty = Result(delta: "", digest: "0",
                               doc: ["root = Stack([ins])",
                                     "ins = Insight(\"\(genSafe([line, why].compactMap { $0 }.joined(separator: " ")))\")"])
            // The scopes matter MOST on the empty path — they are the likeliest
            // reason it is empty, and the only ones the person can act on.
            empty.find = (outcome.scopes, 0)
            return empty
        }
        let shown = Array(hits.prefix(searchRowLimit))
        // The TRUE total, not the drawn count and not the engine's grounding
        // cap. `Retriever.find` returns every match for exactly this reason.
        var line = String(localized: "\(hits.count) thing match.")
        if !outcome.scopes.isEmpty {
            line += " " + String(localized: "In \(scopeList(outcome.scopes)).")
        }
        if hits.count > shown.count {
            line += " " + String(localized: "Showing the \(shown.count) closest.")
        }
        // Bare count, matching `showtag`/`contextRecap`/`overdue`'s digest
        // shape exactly — the pill renders this digest verbatim as its own
        // trailing signal text (`Composer.keptAskPills`), so it has to be
        // display-safe, not just a good change-detection key. (A same-count
        // reshuffle of WHICH things match goes undetected — the same
        // accepted limitation every other count-only composer already has.)
        // The ROOM, not the list (2026-08-14, prd §384): a result set has a
        // shape — where the matches live, what they look like — and twelve
        // uniform rows can't show either. Both figures read EVERY hit, not
        // the drawn twelve (`TodayBrief.runwayCard`'s rule: truncating the
        // shape understates it exactly when it matters), and both decline
        // below their floors so a three-hit find stays a plain list. Still
        // deterministic, still nothing synthesized — the "Matched on this
        // iPhone" badge stays true of the map and the sheet too.
        let map = sourceMapLine(hits)
        let sheet = contactSheetLine(hits)
        let kids = (["ins"] + (map == nil ? [] : ["map"])
                    + (sheet == nil ? [] : ["sheet"]) + ["res"]).joined(separator: ", ")
        var result = Result(delta: "\(hits.count) things", digest: "\(hits.count)",
                            doc: ["root = Stack([\(kids)])",
                                  "ins = Insight(\"\(genSafe(line))\")"]
                                + (map.map { [$0] } ?? [])
                                + (sheet.map { [$0] } ?? [])
                                + rows(shown, title: "Matches",
                                       snippetTerms: Retriever.contentTerms(query)))
        result.find = (outcome.scopes, hits.count)
        return result
    }

    /// The source treemap over a find's WHOLE hit set — where the matches
    /// live, sized by how many live there. nil under 6 hits or 2 sources (one
    /// cell is a title, and a map over a handful is noise). Mode "source" so
    /// each cell wears its bridge's own mark; a cell tap stays in the agent
    /// (`GenTagMap`'s §225 route — it asks the source's own recap). The
    /// subline is the span of YEARS the matches cover, the one fact neither
    /// the rows nor the count can show at a glance — `String(min)`, never a
    /// grouped interpolation (§375: a year printed as "2,019" is a quantity).
    /// Internal rather than private since 2026-08-16 (`AnswerFigure`'s richer
    /// WHERE rung, above `sourceMixLine`'s miniature).
    static func sourceMapLine(_ hits: [Thing]) -> String? {
        guard hits.count >= 6 else { return nil }
        var counts: [String: Int] = [:]
        for h in hits { counts[h.source, default: 0] += 1 }
        guard counts.count >= 2 else { return nil }
        let ranked = counts.sorted { a, b in
            a.value == b.value ? a.key < b.key : a.value > b.value
        }
        let cells = ranked.prefix(6).map { "\(mapSafe($0.key)) \($0.value)" }
        let years = hits.map { Calendar.current.component(.year, from: $0.capturedAt) }
        var subline = ""
        if let lo = years.min(), let hi = years.max(), lo < hi {
            subline = "\(String(lo))–\(String(hi))"
        }
        return "map = TagMap(\"\(String(localized: "Where they live"))\", \"\(genSafe(subline))\", [\(cells.joined(separator: ", "))], \"source\")"
    }

    /// The matched pictures as a contact-sheet grid, in rank order (the
    /// closest match's picture first — this is a search, not a diary). URL
    /// images only, `TodayBrief.contactSheet`'s stated limitation: stored
    /// bytes have no URL to hand the doc grammar. One picture per thing,
    /// deduped by URL (the demo-corpus lesson — a shared placeholder drawn
    /// nine times reads as broken). nil under 4 distinct pictures.
    /// Internal rather than private since 2026-08-16: `AnswerFigure` leads its
    /// ladder with this, so a free-text answer over pictures opens on them too.
    static func contactSheetLine(_ hits: [Thing]) -> String? {
        var seen = Set<String>()
        var shots: [String] = []
        for t in hits {
            let url = !(t.previewImageURL ?? "").isEmpty
                ? (t.previewImageURL ?? "") : (t.imageURLs.first ?? "")
            guard !url.isEmpty, seen.insert(url).inserted else { continue }
            shots.append("\(genSafe(url))|\(t.id.uuidString)")
            if shots.count == 12 { break }
        }
        guard shots.count >= 4 else { return nil }
        return "sheet = ContactSheet(\"\(String(localized: "In pictures"))\", \"\", \"\(shots.joined(separator: ";"))\", \"\")"
    }

    /// `tileSafe`'s treatment for a `TagMap` cell token — the cell list is
    /// comma-joined and the token's last space-separated word is its count,
    /// so a comma or pipe inside a source name would shear the grammar.
    private static func mapSafe(_ s: String) -> String {
        genSafe(s).replacingOccurrences(of: "|", with: " ")
            .replacingOccurrences(of: ",", with: " ")
            .replacingOccurrences(of: ";", with: " ")
    }

    /// The applied filters as one readable clause — "X", "X and Replies",
    /// "X, Replies and 2019".
    ///
    /// `ListFormatter` rather than a hand-built join: the first cut glued the
    /// parts with a standalone `String(localized: "and")`, which is the
    /// concatenation shape that has no correct translation — the joining word,
    /// the separator and the Oxford comma all differ by language, and Japanese
    /// and Chinese do not use a word there at all.
    private static func scopeList(_ scopes: [Retriever.Scope]) -> String {
        ListFormatter.localizedString(byJoining: scopes.map(\.label))
    }

    // MARK: - Where the money went

    /// The money's LIFECYCLE across the four wallet-riding seats (2026-08-05,
    /// prd §311) — in through Peer, out through the cards, shielded in 0xBow,
    /// coming back through ether.fi's unstake queue.
    ///
    /// THE READ ONLY A CORPUS CAN MAKE, and the reason is structural rather
    /// than clever: each of those four services can see exactly one leg. Peer
    /// knows you bought and nothing about what you spent; a card issuer knows
    /// what you spent and nothing about where it came from; 0xBow knows what
    /// you shielded and — by design, permanently — cannot know what you did
    /// next. Only something holding all four rows at once can put them in a
    /// sentence, and that is the whole argument for a corpus.
    ///
    /// Deterministic arithmetic over rows already landed: no request, no
    /// model, no new field. Every leg reads `priceValue` where it has one and
    /// COUNTS where it doesn't, because these rows settle in different tokens
    /// and summing across them to make one number would be exactly the quiet
    /// arithmetic §83 bans.
    private static func moneyFlow(_ things: [Thing]) -> Result? {
        struct Leg { let title: String; let rows: [Thing] }
        func rows(_ source: String) -> [Thing] {
            things.filter { $0.source == source && !Corpus.isImportReceipt($0) }
        }
        let inbound = rows(moneyFlowInboundSource)
        // Every card seat that stores real numbers, Apple Wallet included
        // since 2026-08-06 — before that this leg named the two onchain cards
        // and silently omitted the one most people actually spend on.
        let cards = things.filter {
            $0.kind == .transaction && Corpus.cardSpendSources.contains($0.source)
                && !$0.tags.contains("Pending") && !Corpus.isImportReceipt($0)
        }
        let shielded = rows(moneyFlowShieldedSource).filter { $0.tags.contains("Shielded") }

        var lines: [String] = []
        if !inbound.isEmpty {
            // The rail is the interesting half — "you funded with Venmo" says
            // more than a count, and it's stamped now (`PeerBridge`).
            let rails = Set(inbound.compactMap(\.authorHandle)).sorted()
            lines.append(rails.isEmpty
                ? String(localized: "\(inbound.count) in through Peer")
                : String(localized: "\(inbound.count) in through Peer, via \(rails.joined(separator: " and "))"))
        }
        if !cards.isEmpty {
            // One currency only — see `FeedInsight.cardMonths` for why.
            let currency = cards.first?.priceCurrency
            // Refunds SUBTRACT. Neither onchain card seat lands one (Gnosis
            // Pay's refunds settle off-chain, which its own copy states), so
            // this line summed raw amounts safely for as long as those two
            // were its only members — and Apple Wallet DOES land refunds,
            // stamped positive and tagged, so joining it without this turns
            // every refund into money spent.
            let spent = cards.filter { $0.priceCurrency == currency }
                .reduce(0.0) { total, row in
                    guard let value = row.priceValue else { return total }
                    return total + (row.tags.contains("Refund") ? -abs(value) : abs(value))
                }
            let money = PriceFormat.string(spent, currency: currency)
            lines.append(money.map { String(localized: "\($0) out on cards") }
                ?? String(localized: "\(cards.count) card purchases"))
        }
        if !shielded.isEmpty {
            let waiting = shielded.filter {
                $0.tags.contains("Pending") || $0.tags.contains("Needs proof")
            }.count
            lines.append(waiting > 0
                ? String(localized: "\(shielded.count) shielded, \(waiting) still clearing")
                : String(localized: "\(shielded.count) shielded"))
        }
        // Two legs minimum. One leg is a fact the room it came from already
        // states better, and calling that a "flow" would be a shape claiming
        // more than it has.
        guard lines.count >= 2 else { return nil }

        let recent = (inbound + cards + shielded)
            .sorted { $0.capturedAt > $1.capturedAt }
        return Result(delta: lines.first ?? "", digest: lines.joined(separator: "|"),
                      doc: ["root = Stack([ins, res])",
                            "ins = Insight(\"\(genSafe(lines.joined(separator: " · ")))\")"]
                          + Self.rows(Array(recent.prefix(6)), title: "Where it moved"))
    }

    /// "How's my card?" / "what's shielded?" / "anything to claim?" — the
    /// three standing questions the wallet-riding seats answer and that no ask
    /// reached (2026-08-05, prd §311). `WalletAsk`, `WalletDeFiAsk` and
    /// `SafeAsk` all existed; these four seats had none, so the only way to
    /// their rows was to find the chip and scroll.
    ///
    /// Each resolves to a SOURCE-scoped recap, which is the deterministic
    /// answer that already exists — no new composer, no model, and the same
    /// doc a kept pill would re-run.
    static func matchesSeatAsk(_ query: String) -> String? {
        let q = query.lowercased()
        for phrase in ["my card", "card spending", "what did i spend on my card"]
        where q.contains(phrase) { return "Gnosis Pay" }
        for phrase in ["shielded", "privacy pool", "privacy pools", "0xbow"]
        where q.contains(phrase) { return "Privacy Pools" }
        for phrase in ["to claim", "unstake", "unstaking", "claimable"]
        where q.contains(phrase) { return "ether.fi" }
        for phrase in ["on peer", "my peer", "peer trades"]
        where q.contains(phrase) { return "Peer" }
        return nil
    }

    // MARK: - What did I spend?

    /// "What did I spend this month?" — the plainest question a card room can
    /// be asked, and until now the app had no answer to it (2026-08-06).
    ///
    /// **Why it can exist at all.** Every other money row in this corpus keeps
    /// its amount as a formatted substring inside a title (`StripeRoomSource`
    /// says so, and it's why the Stripe head refuses arithmetic). Apple Wallet
    /// and the two onchain card seats stamp `priceValue`/`priceCurrency` as
    /// real numbers, so this is honest arithmetic over stored facts rather
    /// than prose re-parsed into a total.
    ///
    /// Deterministic, no model, no request. Three rules inherited whole from
    /// `AppleWalletRoom`, because a second answer that disagreed with the room
    /// on any of them would be worse than no answer:
    ///   · currencies are NEVER summed — one line per currency;
    ///   · a pending authorization is never counted;
    ///   · a refund subtracts.
    private static func spend(_ things: [Thing]) -> Result? {
        let recent = spendRows(things)
        guard !recent.isEmpty else { return nil }

        // Per currency, so nothing here ever states a total across two.
        var totals: [String: Double] = [:]
        for row in recent {
            guard let amount = row.priceValue, let currency = row.priceCurrency else { continue }
            totals[currency, default: 0] += row.tags.contains("Refund")
                ? -abs(amount) : abs(amount)
        }
        guard !totals.isEmpty else { return nil }
        // Largest first, ties on the code so two runs can't disagree.
        let ranked = totals.sorted { a, b in
            a.value == b.value ? a.key < b.key : a.value > b.value
        }
        let lines = ranked.map { AppleWalletRoom.money($0.value, $0.key) }

        // WHO, when we can honestly say it — the one field a card seat has and
        // the chain doesn't.
        //
        // **The merchant clause is scoped to the DOMINANT currency and gated on
        // attribution being nearly complete**, and both guards are load-bearing:
        // only Apple Wallet stores a counterparty at all (Gnosis Pay's stated
        // ceiling is "rows say what was spent, never where", and ether.fi is
        // the same), so an unguarded version reads the top Apple Wallet
        // merchant and attaches it to a total spanning three seats and two
        // currencies — "€900.00 · $30.00 on cards — most of it at Blue Bottle",
        // where Blue Bottle is 3% of it. "Most" also has to MEAN most, or one
        // named shop out of forty carries the sentence.
        let currency = ranked.first?.key
        let scoped = recent.filter { $0.priceCurrency == currency }
        let spends = scoped.compactMap { row -> AppleWalletRoom.Spend? in
            guard let amount = row.priceValue, let currency = row.priceCurrency,
                  let merchant = row.transferCounterparty else { return nil }
            return AppleWalletRoom.Spend(merchant: merchant, amount: abs(amount),
                                         currency: currency, date: row.capturedAt,
                                         isSettled: true,
                                         isRefund: row.tags.contains("Refund"))
        }
        let attributed = Double(spends.count) / Double(max(1, scoped.count))
        let top = attributed >= spendAttributionFloor
            ? AppleWalletRoom.leaderboard(spends).first : nil
        let head = lines.joined(separator: " · ")
        let line = top.flatMap { row -> String? in
            guard row.share >= spendLeadShare else { return nil }
            return String(localized: "\(head) on cards in the last 30 days — most of it at \(row.name)")
        } ?? String(localized: "\(head) on cards in the last 30 days")

        let newest = recent.sorted { $0.capturedAt > $1.capturedAt }
        // The weekly shape (2026-08-14, prd §384) — a total can't say whether
        // the month was steady or one bad weekend, which is the first thing a
        // spend answer gets asked next. Scoped to the DOMINANT currency only,
        // the same rule as the merchant clause above: bars summing euros and
        // dollars into one height would be a number nobody holds.
        let bars = weeklySpendBars(scoped, currency: currency ?? "")
        return Result(delta: lines.first ?? "", digest: lines.joined(separator: "|"),
                      doc: ["root = Stack([\(bars == nil ? "ins, res" : "ins, bars, res")])",
                            "ins = Insight(\"\(genSafe(line))\")"]
                          + (bars.map { [$0] } ?? [])
                          + rows(Array(newest.prefix(6)), title: "What you paid for"))
    }

    /// A `Bars` line of card spend per week across the 30-day window, dominant
    /// currency only. nil under 4 rows (`dailyBars`' own floor — too few to
    /// shape). Refunds subtract; a week that nets below zero clamps to the
    /// zero dot rather than inventing a negative bar height.
    private static func weeklySpendBars(_ rows: [Thing], currency: String) -> String? {
        guard rows.count >= 4, !currency.isEmpty else { return nil }
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let weeks = 5
        var totals = [Double](repeating: 0, count: weeks)
        for row in rows {
            guard let amount = row.priceValue else { continue }
            let days = cal.dateComponents([.day], from: cal.startOfDay(for: row.capturedAt),
                                          to: today).day ?? 999
            guard days >= 0, days < weeks * 7 else { continue }
            let bucket = weeks - 1 - (days / 7)
            totals[bucket] += row.tags.contains("Refund") ? -abs(amount) : abs(amount)
        }
        let labels = (0..<weeks).map { i -> String in
            let start = cal.date(byAdding: .day, value: -((weeks - 1 - i) * 7 + 6), to: today) ?? today
            return start.formatted(.dateTime.month(.abbreviated).day())
        }
        let values = totals.map { String(format: "%.0f", max(0, $0)) }
        let eyebrow = String(localized: "By week · \(currency)")
        return "bars = Bars(\"\(genSafe(eyebrow))\", \"\", \"\(values.joined(separator: ","))\", \"\(labels.joined(separator: ","))\")"
    }

    /// How much of the window's spend must carry a merchant name before the
    /// answer is allowed to name one. Below this the total spans seats that
    /// cannot say where money went, and "most of it at X" would be a claim
    /// about rows X had nothing to do with.
    private static let spendAttributionFloor = 0.8
    /// …and how large that merchant's own share must be for "most" to be true.
    private static let spendLeadShare = 0.3

    /// The rows the spend answer counts: a card purchase, settled, inside the
    /// window. Shared with `Composer.recognizeKeptAskKind` so the pill can
    /// never be minted for a question this composer would answer with nothing.
    static func spendRows(_ things: [Thing]) -> [Thing] {
        let window = Date.now.addingTimeInterval(-Double(AppleWalletRoom.windowDays) * 86_400)
        return things.filter {
            $0.kind == .transaction && Corpus.cardSpendSources.contains($0.source)
                && !$0.tags.contains("Pending") && !Corpus.isImportReceipt($0)
                && $0.capturedAt >= window && $0.priceValue != nil && $0.priceCurrency != nil
        }
    }

    /// Whether "What did I spend?" has a real answer right now.
    static func hasSpendToReport(_ things: [Thing]) -> Bool { !spendRows(things).isEmpty }

    /// The phrasings that ask for it. Deliberately narrow: "spend" alone also
    /// appears in "where did my money go", which `matchesMoneyFlow` answers
    /// better because it spans four seats rather than totalling one.
    static func matchesSpend(_ query: String) -> Bool {
        let q = query.lowercased()
        for phrase in ["what did i spend", "what have i spent", "how much did i spend",
                       "how much have i spent", "my spending", "what i spent"]
        where q.contains(phrase) { return true }
        return false
    }

    /// The phrasings that ask for it.
    static func matchesMoneyFlow(_ query: String) -> Bool {
        let q = query.lowercased()
        return q.contains("where did my money go") || q.contains("where my money went")
            || q.contains("money flow") || q.contains("where's my money")
            || q.contains("wheres my money") || q.contains("money moved")
    }

    // MARK: - On this day, across every import

    /// "What was I doing on this day?" — the same calendar day in prior years,
    /// read across ALL of the imported rooms at once (2026-08-05, prd §310).
    ///
    /// WHY IT ISN'T THE HEATMAP'S ECHO. `OnThisDay` already rides inside each
    /// room's own heatmap card, which means it can only ever speak about ONE
    /// room and only while you are standing in it. A person's 2019 was not an
    /// Instagram year or an X year — it was a year, and the four exports that
    /// happen to hold it are an accident of which companies they used. This is
    /// the read only a corpus can make, and it is the one thing none of those
    /// four apps can show you about yourself.
    ///
    /// Deterministic and cheap: a month/day comparison over things already in
    /// memory, no model and no request. Nil on nearly every day of the year,
    /// which is correct — an anniversary that fires constantly isn't one.
    private static func throwback(_ things: [Thing]) -> Result? {
        let calendar = Calendar.current
        let today = calendar.dateComponents([.month, .day], from: .now)
        let thisYear = calendar.component(.year, from: .now)

        // Imported rooms only. A live bridge's rows from this day last year are
        // ordinary history — it is the EXPORTS that hold the years nobody has
        // looked at, and mixing a calendar event from last April into a
        // throwback would dilute the one thing this is for.
        var hits: [(thing: Thing, years: Int)] = []
        for thing in things where Corpus.bulkImportSources.contains(thing.source) {
            guard !Corpus.isImportReceipt(thing) else { continue }
            let parts = calendar.dateComponents([.month, .day, .year], from: thing.capturedAt)
            guard parts.month == today.month, parts.day == today.day,
                  let year = parts.year, thisYear - year >= 1 else { continue }
            hits.append((thing, thisYear - year))
        }
        guard !hits.isEmpty else {
            return Result(delta: "", digest: "0",
                          doc: ["root = Stack([ins])",
                                "ins = Insight(\"\(genSafe("Nothing from this day in an earlier year."))\")"])
        }
        // Furthest back FIRST — the deepest year is the surprising one, and it
        // is what makes this different from scrolling a recent feed.
        hits.sort { $0.years > $1.years }
        let sources = Set(hits.map(\.thing.source)).count
        let deepest = hits[0].years
        let line = sources > 1
            ? String(localized: "\(hits.count) things from this day, going back \(deepest) years, across \(sources) apps.")
            : String(localized: "\(hits.count) things from this day, going back \(deepest) years.")
        return Result(delta: "\(hits.count) things", digest: "\(hits.count)|\(deepest)",
                      doc: ["root = Stack([ins, res])",
                            "ins = Insight(\"\(genSafe(line))\")"]
                          + rows(Array(hits.prefix(6)).map(\.thing), title: "On this day"))
    }

    /// The phrasings that ask for it. Read by `RootShell.answerDocument` and by
    /// the keepable-kind recognizer, the `matchesUpcoming` precedent.
    static func matchesThrowback(_ query: String) -> Bool {
        let q = query.lowercased()
        return q.contains("on this day") || q.contains("this day in")
            || q.contains("throwback") || q.contains("years ago today")
            || q.contains("what was i doing")
    }

    // MARK: - Noticed

    /// Ruling 10: reuse `HomeInsightStore`'s existing signature-gated, async
    /// on-device model call AS-IS — read its cached `line`/`pickedThingID`,
    /// never recompute here. `HomeInsightStore.shared.refresh(from:)` is what
    /// actually runs the model; this composer only ever reads the result.
    private static func noticed() -> Result? {
        let line = HomeInsightStore.shared.line ?? ""
        guard !line.isEmpty else { return nil }
        let openID = HomeInsightStore.shared.pickedThingID ?? ""
        // Leave the thing-id arg empty rather than falling back to "feed"
        // when there's no pick — a bare tap inside the agent must never
        // silently change the background feed filter behind it (ruling 9).
        return Result(delta: "1 connection", digest: line,
                      doc: ["root = Stack([ins])",
                            "ins = Insight(\"\(genSafe(line))\", \"\", \"\(openID)\", \"\")"])
    }

    // MARK: - Shared

    /// The id parameters exist for docs stacking more than one widget
    /// (`walletDoc`'s approvals + activity) — the defaults keep every
    /// single-widget caller's doc byte-identical to before.
    private static func rows(_ things: [Thing], title: String,
                             widgetID: String = "res", rowPrefix: String = "r",
                             snippetTerms: [String] = []) -> [String] {
        let ids = things.indices.map { "\(rowPrefix)\($0)" }
        var lines = ["\(widgetID) = Widget(\"\(title)\", \"\(things.count)\", [\(ids.joined(separator: ", "))])"]
        for (i, t) in things.enumerated() {
            // Arg 6 is the match snippet, and it is empty for every caller but
            // search (`GenRow` draws the second line only when it is not).
            let snip = snippetTerms.isEmpty ? "" : genSafe(snippet(of: t, terms: snippetTerms))
            lines.append("\(rowPrefix)\(i) = Row(\"\(genSafe(t.title))\", \"\(t.kind.typeTag)\", \"\(t.source)\", \"\(shortTime(t.capturedAt))\", \"\(t.id.uuidString)\", \"\", \"\(snip)\")")
        }
        return lines
    }

    /// WHY a row is in a result — the passage that carried the match.
    ///
    /// A search result that shows only a title is a list, not a search: the
    /// fields this engine scores hardest are the ones NO screen draws
    /// (`postText` holds a social row's real words, `enrichedText` a link's
    /// fetched article, `summary` the source's own copy), so a row could match
    /// on a sentence the person had no way to see (2026-08-13).
    ///
    /// `Retriever.matchWindow` returns nil when the hit already sits inside
    /// the body's head — its doc says the caller's own head excerpt serves
    /// that case identically and without a misleading leading ellipsis — so
    /// this falls back to that head rather than dropping the line.
    private static func snippet(of thing: Thing, terms: [String]) -> String {
        let body = [thing.content, thing.postText ?? "", thing.summary ?? "",
                    thing.enrichedText ?? ""]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && !$0.hasPrefix("http") } ?? ""
        guard !body.isEmpty else { return "" }
        // A tighter radius than the model's grounding snippet uses: this is
        // two lines under a row, not a passage for something to read.
        if let window = Retriever.matchWindow(in: body, terms: terms, radius: 90) {
            return window
        }
        return String(body.prefix(180))
    }

    private static func shortTime(_ date: Date) -> String {
        let s = Date.now.timeIntervalSince(date)
        if s < 3600 { return "\(max(1, Int(s / 60)))m" }
        if s < 86_400 { return "\(Int(s / 3600))h" }
        return "\(Int(s / 86_400))d"
    }

    /// Strips what would break the one-line gen-UI grammar — the same
    /// treatment `HomeComposition.q`/`RootShell.genSafe` each already give
    /// their own doc lines. Shared with `MarketsAsk` since 2026-07-28 — a
    /// fourth private copy would have been the point where the convention
    /// stopped paying for itself.
    static func genSafe(_ s: String) -> String {
        s.replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
