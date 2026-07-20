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
        if kind == "away" { return away(things) }
        if kind == "wallet" { return await wallet() }
        if kind == "watchlist" { return await watchlist(context: context) }
        if kind == "overdue" { return overdue(things) }
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
    /// idiom the Wallet feed itself draws (`WalletIngest.holdingsChart`).
    /// Standing rule: any kept ask backed by a real visualization always
    /// shows it, never text alone (matches `RootShell.answerDocument`'s
    /// watchlist branch below, which already did this for TokenChip rows).
    private static func wallet() async -> Result? {
        guard !WalletStore.shared.addresses.isEmpty else { return nil }
        guard let line = await WalletAsk.answer() else {
            return Result(delta: "", digest: "unreachable",
                          doc: ["root = Stack([ins])",
                                "ins = Insight(\"\(genSafe("Couldn't reach your wallet right now."))\")"])
        }
        // The line itself is the honest digest — it only changes when the
        // real figure does, same idiom as the Noticed line below.
        let groups = await WalletIngest.topHoldingsByWallet()
        return Result(delta: line, digest: line, doc: walletDoc(line: line, groups: groups))
    }

    /// Shared by the kept-ask composer and `RootShell.answerDocument`'s
    /// free-text wallet branch, so both never disagree about what a wallet
    /// answer looks like.
    static func walletDoc(line: String, groups: [WalletIngest.HoldingsGroup]) -> [String] {
        let ids = groups.indices.map { "w\($0)" }
        var doc = ["root = Stack([ins\(ids.isEmpty ? "" : ", " + ids.joined(separator: ", "))])",
                   "ins = Insight(\"\(genSafe(line))\")"]
        for (i, g) in groups.enumerated() {
            doc.append("w\(i) = TagMap(\"\(genSafe(g.label))\", \"\(genSafe(g.subline))\", [\(g.cells.joined(separator: ", "))], \"token\")")
        }
        return doc
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
        return Result(delta: delta, digest: "\(overdue.count)",
                      doc: ["root = Stack([ins, res])", "ins = Insight(\"\(genSafe(line))\")"]
                          + rows(Array(sorted.prefix(4)), title: "Overdue"))
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
                      doc: ["root = Stack([ins, res])", "ins = Insight(\"\(genSafe(line))\")"]
                          + rows(Array(pool.prefix(6)), title: "From \(source)"))
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
                      doc: ["root = Stack([ins, res])", "ins = Insight(\"\(genSafe(line))\")"]
                          + rows(Array(pool.prefix(6)), title: category))
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

    private static func rows(_ things: [Thing], title: String) -> [String] {
        let ids = things.indices.map { "r\($0)" }
        var lines = ["res = Widget(\"\(title)\", \"\(things.count)\", [\(ids.joined(separator: ", "))])"]
        for (i, t) in things.enumerated() {
            lines.append("r\(i) = Row(\"\(genSafe(t.title))\", \"\(t.kind.typeTag)\", \"\(t.source)\", \"\(shortTime(t.capturedAt))\", \"\(t.id.uuidString)\")")
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
