import Foundation

/// "show my work stuff" / "open gmail" / "show my links" — a typed ask that
/// names a PLACE navigates there instead of streaming an answer about it.
/// Three destinations exist: a tag's view, a source's feed, a kind's feed.
/// Anything that doesn't name one falls through to the answer path.
enum NavigateIntent {
    case tag(String)
    case source(String)
    case kind(ThingKind)
    /// A room AND a half of it — "show my X replies", "open my Instagram
    /// saves" (2026-08-05, prd §307).
    ///
    /// The pair is the point. `FeedFilter` has carried both a `source` and a
    /// `tag` since it existed, and nothing could ever set them together: a
    /// navigation named one destination or the other, so the room's own halves
    /// were unreachable. An imported room is where that finally bites — the
    /// three thousand things behind the X chip are posts, replies and likes in
    /// one undifferentiated column, and "just my replies" is the first thing
    /// anyone wants from it.
    ///
    /// The FILTER, not a chip: prd §269 ruled the tag filter is the agent's and
    /// has no control of its own, so this reaches it the sanctioned way — the
    /// day-section header names what's on, and any source-chip tap clears it.
    case sourceFacet(source: String, tag: String)
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

        // A ROOM AND ITS HALF, before every single-destination match below:
        // "show my X replies" names both, and any of the checks that follow
        // would match only one word of it and navigate somewhere narrower than
        // was asked for. Both parts must resolve — a source that exists and a
        // facet with a real tag behind it — or this falls through untouched.
        if let source = sources.first(where: { name in
            Retriever.sourceFilter(in: stripped, sources: [name]) != nil
        }), let facet = Retriever.facetFilter(in: stripped),
           tags.contains(facet.tag) {
            // Nothing may be left over. "show my X replies about design" is a
            // filtered QUESTION, not a place — the same discipline that keeps
            // "show screenshots from trip last week" out of navigation.
            let claimed = Set(source.lowercased().split(separator: " ").map(String.init))
                .union(facet.words)
            if words.allSatisfy({ claimed.contains($0) }) {
                return .sourceFacet(source: source, tag: facet.tag)
            }
        }
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
