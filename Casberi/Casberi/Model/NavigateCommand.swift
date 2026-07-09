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
    /// leading verb only, so statements and questions stay asks.
    static func parse(_ raw: String, tags: [String], sources: [String]) -> NavigateIntent? {
        var q = raw.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "?! "))
        guard let verb = verbs.first(where: { q.hasPrefix($0 + " ") }) else { return nil }
        q.removeFirst(verb.count)

        let words = q.split(separator: " ").map(String.init).filter { !stops.contains($0) }
        guard !words.isEmpty else { return nil }
        let phrase = words.joined(separator: " ")

        // A kind word lists that kind ("show my links" → Feed filtered Link).
        if words.count == 1, let kind = ThingKind.allCases.first(where: {
            $0.typeTag.lowercased() == words[0] || $0.typeTagPlural.lowercased() == words[0]
        }) {
            return .kind(kind)
        }
        // A tag — whole phrase first ("book club"), then any single word.
        if let tag = tags.first(where: { $0.caseInsensitiveCompare(phrase) == .orderedSame }) {
            return .tag(tag)
        }
        for word in words {
            if let tag = tags.first(where: { $0.caseInsensitiveCompare(word) == .orderedSame }) {
                return .tag(tag)
            }
        }
        // A connected source's feed ("show gmail").
        if let source = sources.first(where: { $0.caseInsensitiveCompare(phrase) == .orderedSame }) {
            return .source(source)
        }
        return nil
    }
}
