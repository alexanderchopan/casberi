import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Tool-calling answer path (2026-07-15) — the step from a one-shot summarizer
/// to an actual agent. Instead of handing the model ONE pre-retrieved candidate
/// set and asking it to summarize, this gives it TOOLS (search the corpus,
/// pull the recent things) and lets it decide what to look at — so a multi-hop
/// ask ("did I save anything about the place in yesterday's note?") can do two
/// retrievals, which the single-shot path can't.
///
/// The honesty rail survives intact: the tools search a SNAPSHOT of real things
/// and return their real ids; every id the model's answer rests on maps back to
/// a real `Thing`, so the grounding rows are real and the model still can't
/// invent one. The tools read a plain `Sendable` snapshot (never SwiftData
/// across actors), taken once before the session runs.
///
/// This is the DEFAULT path for a fresh LOOKUP ask (`answerDocument`) on an
/// Apple-Intelligence device — a follow-up stays on the pool-refined compose so
/// "those"/"them" keep their anchor, and synthesis keeps its streaming path.
/// Where the model is unavailable or declines, the caller falls back to the
/// scoring doc (zero regression). Also exercisable in isolation via the
/// `-toolAnswer` probe.
enum AnswerTools {

    /// A real thing, flattened to plain `Sendable` text for the tools — no
    /// SwiftData, so a tool's `call` never touches the model context off its
    /// actor. `id` is the real `Thing.id`, so a hit maps back to a real row.
    struct Snapshot: Sendable {
        let id: String
        let title: String
        let kind: String
        let source: String
        let when: String
        let text: String
    }

    /// The agent's answer: the prose it wrote, and the ids of the things its
    /// tools surfaced (newest-first, de-duped) — the caller paints those as
    /// real grounding rows. nil when the model is unavailable, declines, or
    /// errors; the caller then falls back to the scoring doc (zero regression).
    struct Result {
        let prose: String
        let hitIDs: [String]
    }

    static func answer(query: String, corpus: [Snapshot]) async -> Result? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return await AnswerToolsModel.answer(query: query, corpus: corpus)
        }
        #endif
        return nil
    }
}

#if canImport(FoundationModels)
import FoundationModels

/// Collects the ids every tool returns across a session, so the caller can map
/// the model's grounding back to real things. Reference type shared into the
/// (value-type) tools; a lock guards the concurrent tool calls. `@unchecked`
/// because the lock provides the safety the compiler can't see.
@available(iOS 26.0, *)
final class ToolHitSink: @unchecked Sendable {
    private let lock = NSLock()
    private var seen = Set<String>()
    private var order: [String] = []

    func record(_ ids: [String]) {
        lock.lock(); defer { lock.unlock() }
        for id in ids where seen.insert(id).inserted { order.append(id) }
    }

    var ids: [String] {
        lock.lock(); defer { lock.unlock() }
        return order
    }
}

/// Keyword scoring over the snapshot — the tools' own small retriever (the
/// RootShell scorer works over `Thing`s and can't reach here). Title beats
/// text; a term must be a whole word somewhere in the thing.
@available(iOS 26.0, *)
enum ToolScore {
    static func rank(_ query: String, _ corpus: [AnswerTools.Snapshot], limit: Int) -> [AnswerTools.Snapshot] {
        let terms = query.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 }
        guard !terms.isEmpty else { return Array(corpus.prefix(limit)) }
        func words(_ s: String) -> Set<String> {
            Set(s.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty })
        }
        return corpus.compactMap { snap -> (AnswerTools.Snapshot, Int)? in
            let title = words(snap.title)
            let text = words(snap.text + " " + snap.source)
            var score = 0
            for term in terms {
                if title.contains(term) { score += 3 }
                if text.contains(term) { score += 1 }
            }
            return score > 0 ? (snap, score) : nil
        }
        .sorted { $0.1 > $1.1 }
        .prefix(limit)
        .map(\.0)
    }
}

/// Searches the person's saved things by keyword.
@available(iOS 26.0, *)
struct SearchThingsTool: Tool {
    let name = "search_things"
    let description = """
    Search the person's saved things by keyword. Returns matching things, each \
    with its number, title, kind, source, when it was saved, and a short text \
    excerpt. Call this to find things before answering. You may call it more \
    than once with different keywords to follow a lead.
    """
    let corpus: [AnswerTools.Snapshot]
    let sink: ToolHitSink

    @Generable
    struct Arguments {
        @Guide(description: "The keywords to search for, e.g. 'lisbon flight' or 'work notes'.")
        var query: String
    }

    func call(arguments: Arguments) async throws -> [String] {
        let hits = ToolScore.rank(arguments.query, corpus, limit: 8)
        sink.record(hits.map(\.id))
        guard !hits.isEmpty else { return ["No saved things match \"\(arguments.query)\"."] }
        return hits.map(lineFor)
    }
}

/// Pulls the most recent saved things, optionally filtered by kind or source —
/// for time-anchored asks ("what did I save yesterday", "my latest links").
@available(iOS 26.0, *)
struct RecentThingsTool: Tool {
    let name = "recent_things"
    let description = """
    Get the person's most recently saved things, newest first. Optionally \
    filter by kind (note, link, screenshot, chat, event, reminder, mail, voice, \
    product, transaction) or by source (the app a thing came from). Use this \
    when the ask is about what's recent rather than a keyword.
    """
    let corpus: [AnswerTools.Snapshot]
    let sink: ToolHitSink

    @Generable
    struct Arguments {
        @Guide(description: "Kind to filter by, or empty for any kind.")
        var kind: String
        @Guide(description: "Source (app name) to filter by, or empty for any source.")
        var source: String
    }

    func call(arguments: Arguments) async throws -> [String] {
        let kind = arguments.kind.trimmingCharacters(in: .whitespaces).lowercased()
        let source = arguments.source.trimmingCharacters(in: .whitespaces).lowercased()
        let hits = corpus.filter { snap in
            (kind.isEmpty || snap.kind.lowercased() == kind)
            && (source.isEmpty || snap.source.lowercased() == source)
        }.prefix(8)
        sink.record(hits.map(\.id))
        guard !hits.isEmpty else { return ["Nothing recent matches that filter."] }
        return hits.map(lineFor)
    }
}

/// One serialization for both tools' rows — number-free (the model gets a
/// list), title/kind/source/when plus the excerpt when it adds anything.
@available(iOS 26.0, *)
private func lineFor(_ snap: AnswerTools.Snapshot) -> String {
    var line = "\(snap.title) — \(snap.kind), from \(snap.source), \(snap.when)"
    if !snap.text.isEmpty { line += " — \(snap.text)" }
    return line
}

@available(iOS 26.0, *)
enum AnswerToolsModel {
    static func answer(query: String, corpus: [AnswerTools.Snapshot]) async -> AnswerTools.Result? {
        guard OnDeviceModel.isAvailable, !corpus.isEmpty else { return nil }
        let sink = ToolHitSink()
        let tools: [any Tool] = [
            SearchThingsTool(corpus: corpus, sink: sink),
            RecentThingsTool(corpus: corpus, sink: sink),
        ]
        let instructions = """
        You help someone find and make sense of the things they have saved. \
        You have tools to search and list their things — USE them to find real \
        things before answering; never answer from memory. The app will DISPLAY \
        the things you found as a list of rows right beneath your answer, so DO \
        NOT list, number, or restate them — that would just repeat what's \
        already on screen. Instead write ONE short sentence (two at most) that \
        says what you found and ties it together — the gist, not an inventory. \
        Speak TO them as "you" — never write in the first person. Ground every \
        word in what the tools returned; never invent a thing, a number, or a \
        detail. If the tools find nothing, say so plainly. No preamble ("Here \
        are…", "I found…"), no markdown, no bullet or numbered lists.
        """ + LanguageStore.shared.llmLanguageDirective
        do {
            let session = LanguageModelSession(tools: tools, instructions: instructions)
            let response = try await session.respond(to: "Question: \"\(query)\"")
            let prose = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !prose.isEmpty else { return nil }
            return AnswerTools.Result(prose: prose, hitIDs: sink.ids)
        } catch {
            return nil
        }
    }
}
#endif
