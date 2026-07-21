import Foundation
import SwiftData

/// The deterministic retrieval engine behind every free-text ask — extracted
/// verbatim from `RootShell.retrieve` (2026-07-20) so a kept-ask composer can
/// re-run the exact same scoring for a kept SEARCH, never the model.
/// `RootShell.answerDocument`'s model-routing sits entirely ABOVE this: this
/// function only ever ranks a corpus by keyword/tag/content/semantic score —
/// docs/agent-brief.md ruling 1's "kept path is deterministic" guarantee
/// depends on this file never importing FoundationModels.
enum Retriever {
    /// Matches are scored, not just found: title hits outweigh tag hits
    /// outweigh content hits, fresh things float, and kind words in the
    /// person's own words filter ("screenshots about work" searches
    /// screenshots for work). Returns the ranked grounding set (top 16 — a
    /// wide net for the model to rerank, well past the 4 the fallback
    /// paints; raised from 10, 2026-07-15).
    ///
    /// `isPoolRefinement` is true when `corpus` already arrived as a
    /// follow-up's narrowed pool rather than a fresh fetch — it skips the
    /// sentence-embedding pass (a narrowed pool carries no new words of its
    /// own to re-embed against).
    static func rank(_ query: String, in corpus: [Thing], isPoolRefinement: Bool) -> [Thing] {
        var terms = query.lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "? "))
            .split(separator: " ").map(String.init)

        // A kind word is a filter, not a search term.
        var kindFilter: ThingKind?
        terms.removeAll { term in
            if let kind = ThingKind.allCases.first(where: {
                $0.typeTag.lowercased() == term || $0.typeTagPlural.lowercased() == term
            }) {
                kindFilter = kind
                return true
            }
            return false
        }
        let stops: Set<String> = ["about", "my", "the", "a", "in", "from", "for", "of",
                                  "what", "whats", "what's", "landed", "on", "happened",
                                  "is", "are", "was", "were", "do", "does", "did", "i",
                                  "me", "you", "your", "who", "how", "when", "where",
                                  "why", "which", "it", "and", "or", "to", "with",
                                  // Command / query verbs (2026-07-15): a lookup
                                  // like "show me my events" or "which events do
                                  // I have" names an ACTION, not content — left
                                  // in, "show"/"have" scored as search terms and
                                  // matched nothing, so the ask returned empty. A
                                  // bare kind/date list then falls through to the
                                  // "list that kind" path as intended.
                                  "show", "find", "search", "list", "look", "up",
                                  "save", "saved", "have", "has", "had", "get",
                                  "see", "tell", "give", "all", "any"]
        terms.removeAll { stops.contains($0) }

        // A date phrase ("today", "last week", "thursday") is a WHEN filter,
        // not a text term — things outside the range drop out entirely.
        let dateMatch = DateQuery.match(in: query)
        if let dateMatch { terms.removeAll { dateMatch.words.contains($0) } }

        let all = corpus
        // Semantic widening: near-synonyms of the query's words, scored
        // BELOW exact matches — "car stuff" reaches "vehicle" titles.
        let expanded = SemanticExpand.expand(terms)

        // Sentence-level semantic match (2026-07-12): embed the natural-language
        // ask and score each thing by cosine to its stored vector — so a query
        // can reach a thing that shares NO words with it. The whole ASK is
        // embedded (a sentence embedding wants a sentence — the stripped keyword
        // fragments below would degrade it), only its trailing "?" trimmed.
        // Skipped for follow-up pool refinements and bare kind/date lists (no
        // words to carry meaning), and a no-op when the on-device embedding
        // model is unavailable — the keyword engine then stands alone (zero
        // regression). The query norm is computed once, not per thing.
        let ask = query.trimmingCharacters(in: CharacterSet(charactersIn: "? ").union(.whitespaces))
        let queryVec: [Float]? = (!isPoolRefinement && !terms.isEmpty)
            ? EmbeddingIndex.vector(for: ask) : nil
        let queryNorm = queryVec.map(EmbeddingIndex.norm) ?? 0
        // Similarity above the boost floor refines ranking; but a thing with NO
        // keyword score must clear the higher QUALIFY floor to answer at all —
        // so a loosely-related recent thing can't ride the freshness bonus into
        // a false answer, and the honest "nothing matches" path survives. The
        // lift is normalized 0…1 above the boost floor and weighted so a strong
        // meaning-match rivals a title hit (+3).
        let semanticBoostFloor = 0.55
        let semanticQualifyFloor = 0.62
        let semanticWeight = 3.0

        // Whole words, not substrings (2026-07-10): "what is my name" used
        // to match the "is" inside "Lisbon" and answer with nonsense — a
        // term now has to BE a word somewhere in the thing.
        func words(_ s: String) -> Set<String> {
            Set(s.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty })
        }
        return all.compactMap { thing -> (Thing, Double)? in
            if let kindFilter, thing.kind != kindFilter { return nil }
            if let dateMatch, !dateMatch.range.contains(thing.capturedAt) { return nil }
            let title = words(thing.title)
            let tags = words(thing.tags.joined(separator: " "))
            // The content scan reaches the thing's own body AND its enriched
            // text (a link's fetched article, 2026-07-15) — so a keyword the
            // title never says can still match a saved page.
            let content = words(thing.content + " " + (thing.enrichedText ?? ""))
            var score = 0.0
            for term in terms {
                if title.contains(term) { score += 3 }
                if tags.contains(term) { score += 2 }
                if content.contains(term) { score += 1 }
            }
            for term in expanded {
                if title.contains(term) { score += 1.5 }
                if tags.contains(term) { score += 1 }
                if content.contains(term) { score += 0.5 }
            }
            // Semantic lift: meaning-match adds to the score and can qualify a
            // thing that shares no words at all — but only a STRONG match
            // (>= qualify floor) may answer without a keyword hit.
            if let queryVec, let data = thing.embedding, !data.isEmpty {
                let sim = EmbeddingIndex.similarity(query: queryVec, queryNorm: queryNorm, packed: data)
                if sim >= semanticBoostFloor, score > 0 || sim >= semanticQualifyFloor {
                    score += semanticWeight * (sim - semanticBoostFloor) / (1 - semanticBoostFloor)
                }
            }
            // A bare kind query ("screenshots?") lists that kind; a bare date
            // query ("what landed today?") lists the day.
            if terms.isEmpty && (kindFilter != nil || dateMatch != nil) { score = 1 }
            guard score > 0 else { return nil }
            let age = Date.now.timeIntervalSince(thing.capturedAt)
            score += max(0, 1 - age / (7 * 86_400))   // fresh floats, capped +1
            return (thing, score)
        }
        .sorted { $0.1 > $1.1 }
        .prefix(16)
        .map(\.0)
    }
}
