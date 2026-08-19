import Foundation

/// The corpus tools a KEYED agent gets (2026-08-06) — the fix for the oldest
/// asymmetry in the BYOK path: the free on-device answer has been a real agent
/// since 2026-07-15 (`AnswerTools` — search the corpus, pull the recent things,
/// decide what to look at, follow a lead with a second retrieval), while the
/// paid one was a single-shot summarizer handed ONE pre-retrieved candidate
/// set by `RootShell.keyedAnswerDocument` and asked to write it up.
///
/// That is backwards twice over. The frontier model is the one that can
/// actually USE a tool loop, and it was the one denied it; and the single-shot
/// shape inherits every limit of the local retriever, so the §307 complaint
/// ("search my X stuff" answering with five unrelated things over a
/// three-thousand-post room) reproduced on the path somebody is PAYING for,
/// where a second look would have cost them a fraction of a cent.
///
/// **The honesty rail is unchanged and is the whole design.** These tools read
/// a plain `Sendable` snapshot of real things and return their real ids; the
/// rows painted under a keyed answer are the things the tools actually
/// returned, in the order they surfaced. The model still cannot invent a
/// thing — it can only ask to see more of them.
///
/// Four tools now (`linked_things` joined 2026-08-08, prd §340), and two of
/// them are easy to leave out and shouldn't be. `list_sources`: a model cannot
/// filter by a source whose name it has never seen, and this corpus's source
/// names are the person's own connected apps — so without it, "what did I save
/// from Linear?" degrades to a keyword search for the word "Linear", which is
/// exactly the §307 bug in miniature. `linked_things`: `search_things` only
/// ever finds things that use the same WORDS as the query, which is a
/// different question from "what did this person actually connect to that
/// thing" — a note that wikilinks an article, a post whose text carries its
/// URL. Those edges (`ThingLinks`) already power the thing sheet's "Points at
/// this" shelf; this is the same read, so a multi-hop ask ("what have I
/// written about the place my March note mentions?") can follow a real
/// connection instead of guessing a second search term.
///
/// **Redaction happens HERE, not at the call site.** `AgentAnswer.synthesize`
/// scrubs the candidates it was handed (prd §277), but a tool result is corpus
/// text this file fetches AFTER that gate and hands straight to somebody
/// else's API — so it would have sailed past the tripwire entirely. Every
/// title and excerpt leaving through `serialize` (and `linked_things`'s own
/// serialization, which cannot share `serialize` — see below) goes through
/// `SecretScan.redacted` first, and a thing whose full text `carriesSecret`
/// is dropped from the result rather than redacted, because a tool result is
/// evidence the model will quote and a half-redacted quote is worse than a
/// thing it never saw.
enum AgentCorpusTools {

    /// How many times the model may go back for more before it must answer.
    ///
    /// Three, and the number is a BILLING decision, not a capability one:
    /// every round is a fresh request carrying the whole transcript so far, so
    /// round N costs roughly N times the first one. Two rounds covers the
    /// multi-hop ask this exists for ("did I save anything about the place in
    /// yesterday's note?" — one read to find the note, one to search what it
    /// named); the third is slack for a model that opens with `list_sources`.
    /// Past that the spend climbs faster than the answer improves.
    ///
    /// The last round is issued with NO tools declared (see
    /// `AgentAnswer.synthesize`), so the model is never left holding a tool it
    /// can't use — it is asked a question it must answer from what it has.
    static let maxRounds = 3

    /// How many things one tool call may return. Deliberately smaller than the
    /// on-device tools' 8: these rows are billed as input tokens on EVERY
    /// subsequent round of the loop, so a wide first call is paid for three
    /// times over.
    static let pageLimit = 6

    // MARK: - What the model asked for, and what it got back

    /// One tool call the model made — the provider's own id for it (needed to
    /// pair the result back on every wire shape), the tool name, and the raw
    /// JSON argument string, which is accumulated from stream fragments and so
    /// is not parsed until it's complete.
    struct Call: Sendable {
        let id: String
        let name: String
        let arguments: String
    }

    /// What we hand back for one call. `content` is plain text, never JSON —
    /// all three wire shapes accept a string, and a model reads a labelled
    /// list more reliably than it reads a nested object.
    struct Result: Sendable {
        let id: String
        let name: String
        let content: String
    }

    /// Collects the things the tools surfaced, in first-seen order, so the
    /// caller can map the model's `PICKS:` line back to real rows. The numbers
    /// the model sees (`#4`) are 1-based indices into this — assigned ACROSS
    /// the whole exchange, not per call, so a thing returned by two different
    /// searches keeps one number and the model can refer to it consistently.
    final class Sink: @unchecked Sendable {
        private let lock = NSLock()
        private var positions: [String: Int] = [:]
        private var order: [String] = []
        /// How many labels are already spoken for by the numbered candidates
        /// in the prompt. The first thing a tool surfaces is therefore
        /// `reserved + 1`, so the model reads ONE continuous run of numbers
        /// across both lists and a `PICKS:` line is never ambiguous about
        /// which list it meant.
        private let reserved: Int

        init(reserved: Int = 0) { self.reserved = reserved }

        /// Returns the label for each id, recording any new ones. A thing
        /// returned by two different searches keeps the number it was given
        /// the first time — a model that reads `#4` in round one and `#9` for
        /// the same thing in round three will cite both.
        func label(_ ids: [String]) -> [Int] {
            lock.lock(); defer { lock.unlock() }
            return ids.map { id in
                if let existing = positions[id] { return reserved + existing + 1 }
                positions[id] = order.count
                order.append(id)
                return reserved + order.count
            }
        }

        var ids: [String] {
            lock.lock(); defer { lock.unlock() }
            return order
        }
    }

    // MARK: - Declarations (one schema, three wire shapes)

    /// The tools, described once. Each provider's declaration builder below
    /// renders THIS into its own shape — the descriptions are what the model
    /// actually reads, so they live in one place or they drift apart and a
    /// question answered well on Claude answers badly on Gemini for reasons
    /// nothing in the code would show.
    private struct Spec {
        let name: String
        let description: String
        /// property name → (JSON type, description). All optional except where
        /// `required` names them.
        let properties: [(String, String, String)]
        let required: [String]
    }

    private static let specs: [Spec] = [
        Spec(name: "search_things",
             description: """
             Search everything the person has saved. Returns matching things, \
             each with a reference number, title, kind, source app, when it \
             was saved, and a short excerpt. Call this before answering, and \
             call it again with different words to follow a lead.
             """,
             properties: [
                ("query", "string",
                 "The words to search for, e.g. 'lisbon flight' or 'quarterly budget'."),
                ("source", "string",
                 "Optional: only things from this source app. Use list_sources first to learn the exact names."),
                ("kind", "string",
                 "Optional: only things of this kind — note, link, screenshot, chat, event, reminder, mail, voice, product, transaction."),
             ],
             required: ["query"]),
        Spec(name: "recent_things",
             description: """
             The person's most recently saved things, newest first, optionally \
             narrowed by source app or kind. Use this when the question is \
             about what is recent rather than about particular words.
             """,
             properties: [
                ("source", "string",
                 "Optional: only things from this source app. Use list_sources first to learn the exact names."),
                ("kind", "string",
                 "Optional: only things of this kind — note, link, screenshot, chat, event, reminder, mail, voice, product, transaction."),
             ],
             required: []),
        Spec(name: "linked_things",
             description: """
             What else in the person's things POINTS AT a particular thing — \
             notes that link to it by name, and posts or notes whose own text \
             carries its link. Use this to follow a trail rather than searching \
             again with different words: search finds things that use the same \
             words, this finds things the person actually connected. Returns \
             nothing for most things, which is normal.
             """,
             properties: [
                ("title", "string",
                 "The title of the thing to look up, copied exactly from a result you have already seen."),
             ],
             required: ["title"]),
        Spec(name: "list_sources",
             description: """
             The apps and services this person has connected, with how many \
             things each has contributed. Call this when the question names a \
             place ("my Linear tickets", "what's in Obsidian") so you can pass \
             the exact source name to the other tools.
             """,
             properties: [],
             required: []),
    ]

    static let names: Set<String> = Set(specs.map(\.name))

    /// Anthropic's `tools` entries: a flat `input_schema` per tool.
    static func anthropicDeclarations() -> [[String: Any]] {
        specs.map { spec in
            ["name": spec.name,
             "description": spec.description,
             "input_schema": jsonSchema(spec)]
        }
    }

    /// The OpenAI-compatible `tools` entries (ChatGPT, Venice, OpenRouter,
    /// Grok): the same schema wrapped in a `function` envelope.
    static func openAIDeclarations() -> [[String: Any]] {
        specs.map { spec in
            ["type": "function",
             "function": ["name": spec.name,
                          "description": spec.description,
                          "parameters": jsonSchema(spec)]]
        }
    }

    /// Gemini's `tools: [{ functionDeclarations: [...] }]`. One entry holding
    /// all three, and the schema types are UPPERCASE there — a lowercase
    /// "string" is rejected by the API, which is the kind of difference that
    /// only shows up as a 400 with no tool ever running.
    static func geminiDeclarations() -> [[String: Any]] {
        let declarations: [[String: Any]] = specs.map { spec in
            var entry: [String: Any] = ["name": spec.name, "description": spec.description]
            // Gemini rejects an empty `parameters` object on some model
            // versions — a tool that takes nothing simply omits the key.
            if !spec.properties.isEmpty {
                var properties: [String: Any] = [:]
                for (key, _, description) in spec.properties {
                    properties[key] = ["type": "STRING", "description": description]
                }
                var schema: [String: Any] = ["type": "OBJECT", "properties": properties]
                if !spec.required.isEmpty { schema["required"] = spec.required }
                entry["parameters"] = schema
            }
            return entry
        }
        return [["functionDeclarations": declarations]]
    }

    private static func jsonSchema(_ spec: Spec) -> [String: Any] {
        var properties: [String: Any] = [:]
        for (key, type, description) in spec.properties {
            properties[key] = ["type": type, "description": description]
        }
        var schema: [String: Any] = ["type": "object", "properties": properties]
        if !spec.required.isEmpty { schema["required"] = spec.required }
        return schema
    }

    // MARK: - Running a call

    /// Runs one tool against the snapshot and words the answer. Never throws
    /// and never returns empty: a tool that found nothing says so in a
    /// sentence, because a blank result reads to a model as a broken tool and
    /// it will simply call it again, which costs another round for nothing.
    ///
    /// An unknown tool name is answered the same way rather than dropped — a
    /// missing result for a call the model made leaves the transcript
    /// malformed on every wire shape here.
    static func run(_ call: Call, corpus: [AnswerTools.Snapshot], sink: Sink) -> Result {
        let arguments = (try? JSONSerialization.jsonObject(with: Data(call.arguments.utf8)))
            as? [String: Any] ?? [:]
        func string(_ key: String) -> String {
            (arguments[key] as? String ?? "").trimmingCharacters(in: .whitespaces)
        }

        let content: String
        switch call.name {
        case "search_things":
            let query = string("query")
            let scoped = filter(corpus, source: string("source"), kind: string("kind"))
            let hits = query.isEmpty ? Array(scoped.prefix(pageLimit))
                                     : rank(query, scoped, limit: pageLimit)
            content = serialize(hits, sink: sink, empty: query.isEmpty
                ? "Nothing saved matches that filter."
                : "Nothing saved matches \"\(query)\".")
        case "recent_things":
            let scoped = filter(corpus, source: string("source"), kind: string("kind"))
            content = serialize(Array(scoped.prefix(pageLimit)), sink: sink,
                                empty: "Nothing recent matches that filter.")
        case "linked_things":
            content = linked(string("title"), corpus: corpus, sink: sink)
        case "list_sources":
            content = sourceCensus(corpus)
        default:
            content = "There is no tool called \"\(call.name)\". The tools are: "
                + specs.map(\.name).joined(separator: ", ") + "."
        }
        return Result(id: call.id, name: call.name, content: content)
    }

    private static func filter(_ corpus: [AnswerTools.Snapshot],
                               source: String, kind: String) -> [AnswerTools.Snapshot] {
        guard !source.isEmpty || !kind.isEmpty else { return corpus }
        let source = source.lowercased(), kind = kind.lowercased()
        return corpus.filter { snap in
            (source.isEmpty || snap.source.lowercased() == source)
            && (kind.isEmpty || snap.kind.lowercased() == kind)
        }
    }

    /// Keyword scoring over the snapshot — title beats body, and a term counts
    /// only as a WHOLE word, so "art" doesn't match "start". Shared with the
    /// on-device tools' `ToolScore`, which forwards here: two copies of a
    /// retriever drift, and then the same question answers differently
    /// depending on whether a key is configured, for no reason anybody could
    /// see from either file.
    static func rank(_ query: String, _ corpus: [AnswerTools.Snapshot],
                     limit: Int) -> [AnswerTools.Snapshot] {
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

    /// Finds the thing named `title` and reports what points at it —
    /// `ThingLinks.pointingAt`, over the same snapshot every other tool reads.
    ///
    /// Matched by EXACT title, case-insensitive, never a fuzzy or substring
    /// match: the tool's own description asks the model to copy a title it has
    /// already seen in a result, and a loose match here would silently answer
    /// about the wrong thing — the same failure `list_sources` names a source
    /// wrong would cause, one tool over. A title matching two different things
    /// (a duplicate save) picks the first, which is an accepted imprecision
    /// against building a disambiguation round nobody asked for.
    ///
    /// Cannot share `serialize` above: a tie's own reason (`links here` /
    /// `mentions this`) has nowhere to sit in a row shaped for keyword hits, so
    /// this is `serialize`'s redaction discipline (the same drop-not-redact
    /// rule, the same "N more are hidden" honesty) with `edge.reason` where
    /// `kind` sits in the other one.
    private static func linked(_ title: String, corpus: [AnswerTools.Snapshot],
                               sink: Sink) -> String {
        let needle = title.lowercased()
        guard !needle.isEmpty else { return "Provide a title to look up." }
        guard let target = corpus.first(where: { $0.title.lowercased() == needle }) else {
            return "No saved thing titled \"\(title)\" was found — copy the title exactly from a result already shown."
        }
        let nodes = corpus.map(\.node)
        let ties = ThingLinks.pointingAt(target.node, in: nodes, limit: pageLimit)
        guard !ties.isEmpty else {
            // Scrubbed like every other line this file hands back: a tool
            // result is corpus text on its way into a provider's context
            // window, and an error string is not an exception to that.
            return "Nothing in the person's things points at \"\(SecretScan.redacted(target.title))\"."
        }
        let bySnapshotID = Dictionary(uniqueKeysWithValues: corpus.map { ($0.id, $0) })
        let safe = ties.filter { tie in
            guard let snap = bySnapshotID[tie.id] else { return false }
            return !SecretScan.carriesSecret(snap.title + " " + snap.text)
        }
        guard !safe.isEmpty else {
            return "Nothing in the person's things points at \"\(target.title)\"."
        }
        let labels = sink.label(safe.map(\.id))
        var lines: [String] = []
        for (label, tie) in zip(labels, safe) {
            guard let snap = bySnapshotID[tie.id] else { continue }
            var line = "#\(label) \(SecretScan.redacted(tie.title)) — \(tie.edge.reason), from \(tie.source), \(snap.when)"
            let excerpt = SecretScan.redacted(snap.text)
            if !excerpt.isEmpty { line += " — \(excerpt)" }
            lines.append(line)
        }
        if safe.count < ties.count {
            let hidden = ties.count - safe.count
            lines.append("(\(hidden) more matched but are hidden because they contain a password or key.)")
        }
        return lines.joined(separator: "\n")
    }

    /// Renders hits as numbered lines and records them in the sink, dropping
    /// anything whose text carries a credential (see the type doc). The
    /// numbers are the sink's, so `#4` means the same thing in round three as
    /// it did in round one.
    private static func serialize(_ hits: [AnswerTools.Snapshot], sink: Sink,
                                  empty: String) -> String {
        let safe = hits.filter { !SecretScan.carriesSecret($0.title + " " + $0.text) }
        guard !safe.isEmpty else { return empty }
        let labels = sink.label(safe.map(\.id))
        var lines: [String] = []
        for (label, snap) in zip(labels, safe) {
            var line = "#\(label) \(SecretScan.redacted(snap.title)) — \(snap.kind), from \(snap.source), \(snap.when)"
            let excerpt = SecretScan.redacted(snap.text)
            if !excerpt.isEmpty { line += " — \(excerpt)" }
            lines.append(line)
        }
        // A dropped row is NAMED rather than silently missing: the model is
        // about to reason about a result set, and "6 matched, 1 is hidden" is
        // a different fact from "5 matched".
        if safe.count < hits.count {
            let hidden = hits.count - safe.count
            lines.append("(\(hidden) more matched but are hidden because they contain a password or key.)")
        }
        return lines.joined(separator: "\n")
    }

    /// The connected sources with counts, biggest first — capped, because a
    /// person with forty bridges would otherwise spend a third of a round's
    /// budget on a directory.
    private static func sourceCensus(_ corpus: [AnswerTools.Snapshot]) -> String {
        var counts: [String: Int] = [:]
        for snap in corpus where !snap.source.isEmpty {
            counts[snap.source, default: 0] += 1
        }
        guard !counts.isEmpty else { return "Nothing is connected yet." }
        let ranked = counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
        let shown = ranked.prefix(30)
        var line = shown.map { "\($0.key) (\($0.value))" }.joined(separator: ", ")
        if ranked.count > shown.count { line += ", and \(ranked.count - shown.count) more" }
        return "Sources, with how many of the things read here came from each: " + line + "."
    }
}
