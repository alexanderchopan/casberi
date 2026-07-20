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

    private static func wallet() async -> Result? {
        guard !WalletStore.shared.addresses.isEmpty else { return nil }
        guard let line = await WalletAsk.answer() else {
            return Result(delta: "", digest: "unreachable",
                          doc: ["root = Stack([ins])",
                                "ins = Insight(\"\(genSafe("Couldn't reach your wallet right now."))\")"])
        }
        // The line itself is the honest digest — it only changes when the
        // real figure does, same idiom as the Noticed line below.
        return Result(delta: line, digest: line,
                      doc: ["root = Stack([ins])", "ins = Insight(\"\(genSafe(line))\")"])
    }

    // MARK: - Watchlist

    private static func watchlist(context: ModelContext) async -> Result? {
        guard !TokensAsk.watched(context).isEmpty else { return nil }
        let moves = await TokensAsk.moves(context: context)
        let line = TokensAsk.line(moves)
        return Result(delta: line, digest: line,
                      doc: ["root = Stack([ins])", "ins = Insight(\"\(genSafe(line))\")"])
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
