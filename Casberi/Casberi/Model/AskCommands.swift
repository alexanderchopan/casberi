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
    /// answer to repeat back.
    private static func rangePhrase(in q: String) -> String? {
        for phrase in ["yesterday", "today", "last week", "this week", "the week",
                       "this month", "weekend", "my week"] where q.contains(phrase) {
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
