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
    }

    /// `things` must arrive newest-first (every existing caller's fetch order).
    /// `context` is threaded through explicitly (matching how `RootShell`
    /// already calls `TokensAsk.moves(context:)`/`.watched(_:)` — there is no
    /// shared/static ModelContext accessor in this codebase).
    static func compose(_ kind: String, things: [Thing], context: ModelContext) async -> Result? {
        if kind == "today" { return await TodayBrief.compose(things: things, context: context) }
        if kind == "away" { return away(things) }
        if kind == "wallet" { return await wallet(things) }
        if kind == "walletdefi" { return await walletDeFi() }
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
            return categoryRecap(String(kind.dropFirst("category:".count)), things: things)
        }
        if kind.hasPrefix("handle:") {
            return handleRecap(String(kind.dropFirst("handle:".count)), things: things)
        }
        if kind.hasPrefix("search:") {
            return search(String(kind.dropFirst("search:".count)), things: things)
        }
        return nil
    }

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
        let walletThings = things.filter { $0.source == "Wallet" || $0.source == "Peer" }
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
    private static func valueSparkLine() -> String? {
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
        guard !TokensAsk.watched(context).isEmpty else { return nil }
        let moves = await TokensAsk.moves(context: context)
        guard !moves.isEmpty else {
            // Watched, but every pulse fetch failed — not the same as an
            // empty watchlist (honesty rule already paid for in
            // RootShell.answerDocument; this composer was missing it).
            return Result(delta: "", digest: "unreachable",
                          doc: ["root = Stack([ins])",
                                "ins = Insight(\"\(genSafe("Couldn't read your watchlist's prices right now."))\")"])
        }
        let line = TokensAsk.line(moves)
        return Result(delta: line, digest: line, doc: watchlistDoc(line: line, moves: moves))
    }

    /// Shared by the kept-ask composer and `RootShell.answerDocument`'s
    /// free-text watchlist branch.
    static func watchlistDoc(line: String, moves: [TokensAsk.Move]) -> [String] {
        let shown = moves.prefix(6).compactMap { m in
            TokenChart.route(from: m.thing.content).map { (move: m, route: $0) }
        }
        // One mover earns the FULL scrubbable curve (ChartCard), not a lone
        // chip — the same tall-vs-compact dose split TokenChart draws
        // everywhere else (2026-07-21). Two or more keep the chip list.
        if shown.count == 1 {
            let s = shown[0]
            return ["root = Stack([ins, chart])",
                    "ins = Insight(\"\(genSafe(line))\")",
                    "chart = ChartCard(\"\(genSafe(s.move.symbol))\", \"\(s.route.chain)\", \"\(s.route.address)\")"]
        }
        var doc = ["root = Stack([ins\(shown.isEmpty ? "" : ", res")])",
                   "ins = Insight(\"\(genSafe(line))\")"]
        if !shown.isEmpty {
            let ids = shown.indices.map { "t\($0)" }
            doc.append("res = Widget(\"\(String(localized: "Watchlist"))\", \"\(shown.count)\", [\(ids.joined(separator: ", "))])")
            for (i, s) in shown.enumerated() {
                doc.append("t\(i) = TokenChip(\"\(genSafe(s.move.symbol))\", \"\(s.route.chain)\", \"\(s.route.address)\", \"\(s.move.thing.id.uuidString)\", \"\")")
            }
        }
        return doc
    }

    // MARK: - What's overdue

    /// Mirrors `HomeComposition.tileSignal`'s Reminders/Todoist branch —
    /// light, deliberate duplication of ~3 lines rather than reaching into
    /// that private function, consistent with how HomeComposition and
    /// RootShell already each read `Thing` fields independently.
    private static func overdue(_ things: [Thing]) -> Result? {
        let open = things.filter { $0.mark != .done && ($0.source == "Reminders" || $0.source == "Todoist") }
        let overdue = open.filter { ($0.dueAt ?? .distantFuture) < .now }
        guard !overdue.isEmpty else {
            return Result(delta: "", digest: "0",
                          doc: ["root = Stack([ins])",
                                "ins = Insight(\"\(genSafe("Nothing overdue."))\")"])
        }
        let sorted = overdue.sorted { ($0.dueAt ?? .now) < ($1.dueAt ?? .now) }
        let delta = "\(overdue.count), \(overdue.count == 1 ? "1 thing" : "\(overdue.count) things") late"
        let line = "\(overdue.count) thing\(overdue.count == 1 ? "" : "s") overdue."
        // AgendaRow, not the generic Row — an overdue task has a due date, so
        // it draws on the time rail (the most-overdue leads, emphasized).
        return Result(delta: delta, digest: "\(overdue.count)",
                      doc: ["root = Stack([ins, res])", "ins = Insight(\"\(genSafe(line))\")"]
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
        return Result(delta: delta, digest: "\(due.count)",
                      doc: ["root = Stack([ins, res])", "ins = Insight(\"\(genSafe(line))\")"]
                          + agendaRows(Array(due.prefix(4)), title: String(localized: "Coming up")))
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
        let line = "\(matched.count) thing\(matched.count == 1 ? "" : "s") tagged \(tag)."
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
        /// deterministic composers below window it again, independently
        /// (the same "light duplication of window logic" `contextRecap`/
        /// `categoryRecap` already own, not a shared dependency).
        func pool(in things: [Thing]) -> [Thing] {
            switch self {
            case .source(let s): return things.filter { $0.source == s }
            case .handle(let h): return things.filter { $0.authorHandle == h }
            case .category(let c):
                let sources = Set(BridgeCatalog.offers
                    .filter { BridgeCatalog.category(of: $0) == c }.map(\.name))
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
    static func namedAskTarget(_ query: String, things: [Thing])
        -> (target: NamedAskTarget, synthesize: Bool)? {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
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
            if let handle = bestHandle(matching: name, things: things) {
                return (.handle(handle), synth)
            }
            if let source = Set(things.map(\.source)).first(where: { $0.lowercased() == name }) {
                return (.source(source), synth)
            }
            if let cat = BridgeCatalog.categories.first(where: { $0.name.lowercased() == name })?.name {
                return (.category(cat), synth)
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
        // Person/sender phrasings (2026-07-22) — resolve to the same handle
        // scope (a sender's name lives in `authorHandle` like a publisher's).
        // Deliberately SPECIFIC prefixes: a bare "what's " would fuzzy-match
        // "what's new" to "BBC News" (contains "new"), so the person forms
        // all carry a distinguishing word ("did"/"from").
        ("what did ", false),
        ("anything from ", false), ("anything new from ", false),
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
        let line = "\(pool.count) thing\(pool.count == 1 ? "" : "s") from \(handle) \(windowWords)."
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
        let line = "\(pool.count) thing\(pool.count == 1 ? "" : "s") from \(source) \(windowWords)."
        return Result(delta: "\(pool.count) things", digest: "\(pool.count)",
                      doc: recapDoc(line: line, pool: pool,
                                    barsEyebrow: "This week", rowsTitle: "From \(source)"))
    }

    // MARK: - What's up with my <category>

    /// A whole-CATEGORY recap ("How's my Markets stuff?") — the app catalog's
    /// own vocabulary (`BridgeCatalog.categories`), not just one source.
    /// Same 3-day/week widening as `contextRecap`, scoped to every source the
    /// category owns (`BridgeCatalog.category(of:) == category`) rather than
    /// one — light duplication of the window logic, same precedent noted
    /// above.
    private static func categoryRecap(_ category: String, things: [Thing]) -> Result? {
        let sourcesInCategory = Set(BridgeCatalog.offers
            .filter { BridgeCatalog.category(of: $0) == category }
            .map(\.name))
        let now = Date.now
        var pool = things.filter { sourcesInCategory.contains($0.source) && $0.capturedAt >= now.addingTimeInterval(-3 * 86_400) }
        var windowWords = "in the last three days"
        if pool.isEmpty {
            pool = things.filter { sourcesInCategory.contains($0.source) && $0.capturedAt >= now.addingTimeInterval(-7 * 86_400) }
            windowWords = "in the last week"
        }
        guard !pool.isEmpty else {
            return Result(delta: "", digest: "0",
                          doc: ["root = Stack([ins])",
                                "ins = Insight(\"\(genSafe("Nothing new from your \(category) apps recently."))\")"])
        }
        let line = "\(pool.count) thing\(pool.count == 1 ? "" : "s") from your \(category) apps \(windowWords)."
        return Result(delta: "\(pool.count) things", digest: "\(pool.count)",
                      doc: recapDoc(line: line, pool: pool,
                                    barsEyebrow: "This week", rowsTitle: category))
    }

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
    private static func dailyBars(_ things: [Thing], eyebrow: String) -> String? {
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

    // MARK: - Kept search

    /// A free-text ask kept as a standing search (docs/agent-brief.md ruling
    /// 13, 2026-07-20) — re-runs `Retriever.rank` EVERY time, the same
    /// deterministic engine `RootShell.answerDocument`'s general retrieval
    /// branch uses, never the model. The honest degradation this requires:
    /// a kept "summarize my week" shows what the summary was drawn from, not
    /// a re-synthesized summary — the chip's title is the ORIGINAL question,
    /// the answer is "here's what matches now."
    private static func search(_ query: String, things: [Thing]) -> Result? {
        let hits = Retriever.rank(query, in: things, isPoolRefinement: false)
        guard !hits.isEmpty else {
            return Result(delta: "", digest: "0",
                          doc: ["root = Stack([ins])",
                                "ins = Insight(\"\(genSafe("Nothing matches anymore."))\")"])
        }
        let line = "\(hits.count) thing\(hits.count == 1 ? "" : "s") match."
        // Bare count, matching `showtag`/`contextRecap`/`overdue`'s digest
        // shape exactly — the pill renders this digest verbatim as its own
        // trailing signal text (`Composer.keptAskPills`), so it has to be
        // display-safe, not just a good change-detection key. (A same-count
        // reshuffle of WHICH things match goes undetected — the same
        // accepted limitation every other count-only composer already has.)
        return Result(delta: "\(hits.count) things", digest: "\(hits.count)",
                      doc: ["root = Stack([ins, res])", "ins = Insight(\"\(genSafe(line))\")"]
                          + rows(Array(hits.prefix(6)), title: "Matches"))
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
                             widgetID: String = "res", rowPrefix: String = "r") -> [String] {
        let ids = things.indices.map { "\(rowPrefix)\($0)" }
        var lines = ["\(widgetID) = Widget(\"\(title)\", \"\(things.count)\", [\(ids.joined(separator: ", "))])"]
        for (i, t) in things.enumerated() {
            lines.append("\(rowPrefix)\(i) = Row(\"\(genSafe(t.title))\", \"\(t.kind.typeTag)\", \"\(t.source)\", \"\(shortTime(t.capturedAt))\", \"\(t.id.uuidString)\")")
        }
        return lines
    }

    private static func shortTime(_ date: Date) -> String {
        let s = Date.now.timeIntervalSince(date)
        if s < 3600 { return "\(max(1, Int(s / 60)))m" }
        if s < 86_400 { return "\(Int(s / 3600))h" }
        return "\(Int(s / 86_400))d"
    }

    /// Strips what would break the one-line gen-UI grammar — the same
    /// treatment `HomeComposition.q`/`RootShell.genSafe` each already give
    /// their own doc lines, kept local here rather than shared (both existing
    /// copies are already file-private; a third file-private copy matches the
    /// standing convention instead of introducing a new shared utility).
    private static func genSafe(_ s: String) -> String {
        s.replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
