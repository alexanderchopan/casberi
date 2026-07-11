import Foundation
import NaturalLanguage
import SwiftData

/// Count-and-aggregate asks (2026-07-10) — "how many links this week",
/// "which app sent the most today". Pure arithmetic over the corpus: no
/// model, no retrieval scoring, always correct. Parsed strictly — anything
/// that doesn't clearly ask for a number falls through to the answer path.
enum AggregateAsk {

    enum Intent {
        /// "how many <kind|source|things> <timeframe>"
        case count(kind: ThingKind?, source: String?, range: ClosedRange<Date>?, rangeWords: String?)
        /// "which app sent the most <timeframe>" / "most active app"
        case topSource(range: ClosedRange<Date>?, rangeWords: String?)
    }

    static func parse(_ query: String, sources: [String]) -> Intent? {
        let q = query.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "?! "))
        let date = DateQuery.match(in: q)
        let rangeWords = date.map { _ in rangePhrase(in: q) }

        // "which app/source sent the most", "most active app", "what app
        // landed the most" — a superlative over sources.
        if (q.contains("most") && (q.contains("app") || q.contains("source")))
            || q.contains("most active") {
            return .topSource(range: date?.range, rangeWords: rangeWords ?? nil)
        }

        guard q.contains("how many") else { return nil }
        var words = q.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        if let dateWords = date?.words { words.removeAll { dateWords.contains($0) } }

        let kind = ThingKind.allCases.first { k in
            words.contains(k.typeTag.lowercased()) || words.contains(k.typeTagPlural.lowercased())
        }
        let source = sources.first { s in
            let sw = s.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
            return !sw.isEmpty && sw.allSatisfy(words.contains)
        }
        return .count(kind: kind, source: source, range: date?.range,
                      rangeWords: rangeWords ?? nil)
    }

    /// The timeframe as the person said it ("this week", "today"), for the
    /// answer to repeat back. Internal so StatusAsk names windows the same way.
    /// "weekend" is checked BEFORE the week phrases — "this weekend" contains
    /// "this week", and matching the wrong one labels weekend counts as the
    /// week's (review 2026-07-11); it reads back as "over the weekend" so the
    /// answer scans as a sentence.
    static func rangePhrase(in q: String) -> String? {
        for phrase in ["yesterday", "today", "weekend", "last week", "this week",
                       "the week", "this month", "my week"] where q.contains(phrase) {
            if phrase == "weekend" { return "over the weekend" }
            return phrase == "the week" || phrase == "my week" ? "this week" : phrase
        }
        // A weekday name.
        for name in Calendar.current.weekdaySymbols.map({ $0.lowercased() })
        where q.contains(name) {
            return "on \(name.capitalized)"
        }
        return nil
    }

    /// The one-line answer, computed. Returns nil only if the intent's
    /// filters name nothing that exists (a source typo, say) — the ask then
    /// falls through to the normal answer path.
    static func answer(_ intent: Intent, things: [Thing]) -> String {
        switch intent {
        case .count(let kind, let source, let range, let rangeWords):
            var pool = things
            if let kind { pool = pool.filter { $0.kind == kind } }
            if let source { pool = pool.filter { $0.source == source } }
            if let range { pool = pool.filter { range.contains($0.capturedAt) } }
            let noun: String
            if let kind {
                noun = pool.count == 1 ? kind.typeTag.lowercased()
                                       : kind.typeTagPlural.lowercased()
            } else if let source {
                noun = pool.count == 1 ? "thing from \(source)" : "things from \(source)"
            } else {
                noun = pool.count == 1 ? "thing" : "things"
            }
            let when = rangeWords.map { " \($0)" } ?? ""
            return "\(pool.count) \(noun)\(when)."

        case .topSource(let range, let rangeWords):
            var pool = things
            if let range { pool = pool.filter { range.contains($0.capturedAt) } }
            let when = rangeWords.map { " \($0)" } ?? ""
            guard !pool.isEmpty else { return "Nothing landed\(when)." }
            var counts: [String: Int] = [:]
            for t in pool { counts[t.source, default: 0] += 1 }
            let top = counts.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }!
            let noun = top.value == 1 ? "thing" : "things"
            return "\(top.key) sent the most\(when) — \(top.value) \(noun)."
        }
    }
}

/// Status asks (2026-07-11) — "tell me what's going on", "catch me up",
/// "anything new?". The ask names no content, so the term-scored retriever
/// would ground it on nothing (or on noise — a title that happens to say
/// "going"). Instead the grounding IS recency: the newest things from every
/// source in a recent window — the feeds' pulse. The on-device model
/// synthesizes over that sample; everywhere else the counted line answers.
enum StatusAsk {

    struct Pulse {
        /// The window as words the answer repeats ("today", "in the last three days").
        let windowWords: String
        /// Everything in the window, newest first — the honest counts.
        let pool: [Thing]
        /// The grounding set: every active source represented before any
        /// repeats (newest first, at most 2 per source, capped at 16).
        let sample: [Thing]
    }

    private static let cues = ["going on", "happening", "what's new", "whats new",
                               "anything new", "catch me up", "did i miss",
                               "what's up", "whats up", "fill me in", "the latest"]

    /// The words a status ask may be made of — anything else is CONTENT, and
    /// content means the scored retriever should run instead ("what's going
    /// on with bitcoin" stays a search).
    private static let filler: Set<String> = [
        "hey", "so", "tell", "me", "what", "whats", "s", "is", "are", "there",
        "was", "were", "been", "has", "have", "had", "it", "that", "a", "an",
        "going", "on", "up", "new", "newest", "latest", "lately", "happening",
        "happened", "anything", "any", "news", "catch", "fill", "in", "did",
        "i", "miss", "missed", "the", "my", "with", "everything", "all",
        "stuff", "things", "thing", "feeds", "feed", "apps", "app", "sources",
        "around", "here", "right", "now", "recently", "please", "really"
    ]

    /// The parsed pulse, or nil when the query isn't a status ask.
    /// `things` must arrive newest-first (the answer path's fetch order).
    static func pulse(_ query: String, things: [Thing], now: Date = .now) -> Pulse? {
        // iOS smart punctuation types U+2019 — "What's new?" must match the
        // "what's new" cue whichever apostrophe the keyboard chose.
        let q = query.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
        guard cues.contains(where: q.contains) else { return nil }
        var words = q.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        let date = DateQuery.match(in: q, now: now)
        if let dateWords = date?.words { words.removeAll { dateWords.contains($0) } }
        words.removeAll { filler.contains($0) }
        guard words.isEmpty else { return nil }

        if let date {
            // rangePhrase covers every DateQuery phrase today; "recently" is
            // the readable fallback if the two lists ever drift.
            let windowWords = AggregateAsk.rangePhrase(in: q) ?? "recently"
            let pool = things.filter { date.range.contains($0.capturedAt) }
            return Pulse(windowWords: windowWords, pool: pool, sample: sample(of: pool))
        }
        // No timeframe named: the last three days; a quiet stretch widens to
        // the week so the answer isn't "nothing" while the Feed shows things.
        var pool = things.filter { $0.capturedAt >= now.addingTimeInterval(-3 * 86_400) }
        var windowWords = "in the last three days"
        if pool.isEmpty {
            pool = things.filter { $0.capturedAt >= now.addingTimeInterval(-7 * 86_400) }
            windowWords = "in the last week"
        }
        return Pulse(windowWords: windowWords, pool: pool, sample: sample(of: pool))
    }

    /// Every active source speaks before any repeats: one thing per source
    /// first, then a second, newest first, capped at 16. One pass — the pool
    /// can be a whole month's window.
    private static func sample(of pool: [Thing]) -> [Thing] {
        var taken: [String: Int] = [:]
        var firsts: [Thing] = [], seconds: [Thing] = []
        for thing in pool {
            let n = taken[thing.source, default: 0]
            guard n < 2 else { continue }
            taken[thing.source] = n + 1
            if n == 0 { firsts.append(thing) } else { seconds.append(thing) }
        }
        return (firsts + seconds).prefix(16).sorted { $0.capturedAt > $1.capturedAt }
    }

    /// The computed status line — counts per source, no model, always
    /// correct. The non-AI answer, and the honest empty.
    static func line(_ pulse: Pulse) -> String {
        let opener = pulse.windowWords.prefix(1).uppercased() + pulse.windowWords.dropFirst()
        guard !pulse.pool.isEmpty else { return "Nothing landed \(pulse.windowWords)." }
        var counts: [String: Int] = [:]
        for t in pulse.pool { counts[t.source, default: 0] += 1 }
        let ranked = counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
        let shown = ranked.prefix(4)
        var parts = shown.enumerated().map { i, e in
            i == 0 ? "\(e.value) thing\(e.value == 1 ? "" : "s") from \(e.key)"
                   : "\(e.value) from \(e.key)"
        }
        if ranked.count > shown.count {
            let rest = ranked.count - shown.count
            parts.append("more from \(rest) other app\(rest == 1 ? "" : "s")")
        }
        let joined = parts.count == 1
            ? parts[0]
            : parts.dropLast().joined(separator: ", ") + ", and " + parts.last!
        return "\(opener): \(joined)."
    }
}

/// Pin/unpin spoken to the composer (2026-07-10) — "pin the last link",
/// "unpin ethereum". A pin is the app's lightest, undoable write (the Feed
/// swipe fires it without a confirm), so the composer executes it directly
/// and the toast carries Undo — same consent weight as the swipe.
enum PinAsk {

    struct Intent {
        let pin: Bool          // false = unpin
        let kind: ThingKind?   // "the last link"
        let words: [String]    // "ethereum" — title/tag words to match
    }

    private static let filler: Set<String> = ["the", "my", "last", "latest",
                                              "newest", "recent", "most", "a", "an",
                                              "thing", "to", "home", "from"]

    static func parse(_ raw: String) -> Intent? {
        let q = raw.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "?! "))
        let pin: Bool
        if q.hasPrefix("unpin ") { pin = false }
        else if q.hasPrefix("pin ") { pin = true }
        else { return nil }

        var words = q.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        words.removeFirst()   // the verb
        words.removeAll { filler.contains($0) }

        let kind = ThingKind.allCases.first { k in
            words.contains(k.typeTag.lowercased()) || words.contains(k.typeTagPlural.lowercased())
        }
        if let kind {
            words.removeAll {
                $0 == kind.typeTag.lowercased() || $0 == kind.typeTagPlural.lowercased()
            }
        }
        guard kind != nil || !words.isEmpty else { return nil }
        return Intent(pin: pin, kind: kind, words: words)
    }

    /// The newest thing the intent names — kind narrows, remaining words
    /// must all appear in the title or tags. Unpin searches pinned things
    /// only (you can only unpin what's pinned).
    static func target(_ intent: Intent, in things: [Thing]) -> Thing? {
        things.first { t in
            if intent.pin == false && !t.pinned { return false }
            if intent.pin && t.pinned { return false }
            if let kind = intent.kind, t.kind != kind { return false }
            guard !intent.words.isEmpty else { return intent.kind != nil }
            let hay = Set("\(t.title) \(t.tags.joined(separator: " "))".lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty })
            return intent.words.allSatisfy(hay.contains)
        }
    }
}

/// On-device semantic term expansion (2026-07-10) — Apple's word embedding
/// widens retrieval so "car stuff" can reach "vehicle"/"automobile" titles
/// without word overlap. Neighbors only (no per-thing vector math): cheap,
/// deterministic, fully on-device. Expanded matches score BELOW exact ones.
enum SemanticExpand {
    private static let embedding = NLEmbedding.wordEmbedding(for: .english)

    static func expand(_ terms: [String]) -> Set<String> {
        guard let embedding else { return [] }
        var out: Set<String> = []
        for term in terms {
            for (word, distance) in embedding.neighbors(for: term, maximumCount: 8)
            where distance < 1.0 {
                out.insert(word.lowercased())
            }
        }
        out.subtract(terms)
        return out
    }
}
