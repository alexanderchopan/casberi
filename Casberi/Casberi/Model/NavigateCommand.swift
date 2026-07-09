import Foundation

/// "show my work stuff" / "open gmail" / "show my links" — a typed ask that
/// names a PLACE navigates there instead of streaming an answer about it.
/// Three destinations exist: a tag's view, a source's feed, a kind's feed.
/// Anything that doesn't name one falls through to the answer path.
enum NavigateIntent {
    case tag(String)
    case source(String)
    case kind(ThingKind)
}

enum NavigateCommand {

    private static let verbs = ["show", "open", "see", "go to", "goto", "view"]
    private static let stops: Set<String> = ["me", "my", "all", "the", "a",
                                             "stuff", "things", "thing", "everything",
                                             "please", "about", "in", "from"]

    /// Parses a navigation ask against the person's REAL tags and sources —
    /// leading verb only, and the WHOLE remainder must name one destination.
    /// "show screenshots from trip last week" carries qualifiers, so it stays
    /// an ask (the answer path honors kind + date); navigation never eats a
    /// filtered question by pouncing on one matching word.
    static func parse(_ raw: String, tags: [String], sources: [String]) -> NavigateIntent? {
        var q = raw.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "?! "))
        guard let verb = verbs.first(where: { q.hasPrefix($0 + " ") }) else { return nil }
        q.removeFirst(verb.count)

        let rawWords = q.split(separator: " ").map(String.init)
        let words = rawWords.filter { !stops.contains($0) }
        guard !words.isEmpty else { return nil }
        // Two phrases: as typed (tag names can CONTAIN stop words — "My
        // Reading") and stripped ("show my work stuff" → "work").
        let asTyped = rawWords.joined(separator: " ")
        let stripped = words.joined(separator: " ")

        // Tags outrank kinds: "show links" with a Links TAG opens the tag.
        if let tag = tags.first(where: {
            $0.caseInsensitiveCompare(asTyped) == .orderedSame
                || $0.caseInsensitiveCompare(stripped) == .orderedSame
        }) {
            return .tag(tag)
        }
        // A single kind word lists that kind ("show my links").
        if words.count == 1, let kind = ThingKind.allCases.first(where: {
            $0.typeTag.lowercased() == words[0] || $0.typeTagPlural.lowercased() == words[0]
        }) {
            return .kind(kind)
        }
        // A connected source's feed ("show gmail").
        if let source = sources.first(where: {
            $0.caseInsensitiveCompare(asTyped) == .orderedSame
                || $0.caseInsensitiveCompare(stripped) == .orderedSame
        }) {
            return .source(source)
        }
        return nil
    }
}
