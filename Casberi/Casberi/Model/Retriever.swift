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
        // A SOURCE word is a filter too (2026-08-05) — the other half of what
        // a thing is, and the half this engine could not see. Resolved off the
        // whole query before it's split, because a source name can be two
        // words ("Apple Health", "Day One") and per-term matching would never
        // find one. See `sourceFilter`.
        //
        // CONFIRMED AGAINST THE CORPUS before it's honoured. The vocabulary is
        // the catalog, which names sources this person may never have
        // connected — and a filter for a source with nothing behind it would
        // turn an ordinary question into "nothing matches" purely because one
        // of its words happens to be an app's name. Unconfirmed, it's dropped
        // and the words score normally, so a wrong resolution costs nothing.
        // (The caller may hand us a corpus already scoped to that source; then
        // this is trivially true and the filter is a no-op re-check.)
        let named = Self.sourceFilter(in: query)
        let sourceMatch = named.flatMap { match in
            corpus.contains { $0.source == match.source } ? match : nil
        }
        var terms = query.lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "? "))
            .split(separator: " ").map(String.init)
        if let sourceMatch { terms.removeAll { sourceMatch.words.contains($0) } }

        // A FACET word narrows within a named room — "my X replies", "what I
        // liked on X", "just my own posts on X" (2026-08-05, prd §307).
        //
        // GATED ON A SOURCE, deliberately, and this is the whole design. These
        // words are ordinary English and the tags they name are not rare:
        // letting "posts" filter an unscoped ask would hide every link and note
        // about the subject behind whichever things happen to carry a "Post"
        // tag, which is a worse answer than no filter at all. Inside a room the
        // person has already named, the same word is unambiguous — they are
        // asking about that room's own halves. Confirmed against the corpus
        // like the source, so a facet with nothing behind it is dropped rather
        // than emptying the answer.
        let facetMatch: (tag: String, words: Set<String>)? = sourceMatch.flatMap { _ in
            let named = Self.facetFilter(in: query)
            return named.flatMap { match in
                corpus.contains { $0.tags.contains(match.tag) } ? match : nil
            }
        }
        if let facetMatch { terms.removeAll { facetMatch.words.contains($0) } }

        // "everything I wrote" — YOUR words, across every room at once
        // (2026-08-05, prd §310). This is the read that needs the whole corpus
        // and so belongs to no single room: your Instagram captions, your X
        // posts and replies, your TikTok comments are one body of writing that
        // four separate exports happen to have split up.
        //
        // UNGATED, unlike the facet above, and the difference is the wording.
        // "posts" is an ordinary noun that could mean anything, which is why a
        // facet needs a named room to disambiguate it; "what I wrote" is an
        // explicit claim about authorship with no other reading, so it can
        // safely scope the whole corpus. Confirmed against that corpus like
        // every other filter here.
        let writingScope = Self.writingScope(in: query).flatMap { match in
            corpus.contains { !$0.tags.isEmpty && !Self.mine.isDisjoint(with: $0.tags) }
                ? match : nil
        }
        if let writingScope { terms.removeAll { writingScope.contains($0) } }

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
                                  "see", "tell", "give", "all", "any",
                                  // "can you search my X stuff" (2026-08-05) —
                                  // the polite forms and the filler noun that
                                  // `KeptAskComposers.namedAskTarget` has always
                                  // stripped. Left in, "can"/"stuff" scored as
                                  // content terms and matched every unrelated
                                  // thing whose text happens to say "can",
                                  // which is what an ask naming a source
                                  // actually answered with.
                                  "can", "could", "would", "please", "stuff"]
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
        // The ask's own language decides which sentence model embeds it, and a
        // thing embedded in a different one is excluded rather than compared
        // (2026-08-02, prd §282) — so a Spanish ask reaches Spanish things and
        // never scores noise against an English vector.
        let queried = (!isPoolRefinement && !terms.isEmpty)
            ? EmbeddingIndex.queryVector(for: ask) : nil
        let queryVec = queried?.vector
        let queryLanguage = queried?.language
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
            if let sourceMatch, thing.source != sourceMatch.source { return nil }
            if let facetMatch, !thing.tags.contains(facetMatch.tag) { return nil }
            if writingScope != nil, Self.mine.isDisjoint(with: thing.tags) { return nil }
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
            if let queryVec, let queryLanguage, let data = thing.embedding, !data.isEmpty {
                let sim = EmbeddingIndex.similarity(query: queryVec, queryNorm: queryNorm,
                                                    packed: data, language: queryLanguage)
                if sim >= semanticBoostFloor, score > 0 || sim >= semanticQualifyFloor {
                    score += semanticWeight * (sim - semanticBoostFloor) / (1 - semanticBoostFloor)
                }
            }
            // A bare kind query ("screenshots?") lists that kind; a bare date
            // query ("what landed today?") lists the day; a bare source query
            // ("my X stuff") lists that source. The freshness bonus below then
            // orders them, so a bare list is newest-first.
            if terms.isEmpty && (kindFilter != nil || dateMatch != nil
                                 || sourceMatch != nil || facetMatch != nil
                                 || writingScope != nil) {
                score = 1
            }
            guard score > 0 else { return nil }
            let age = Date.now.timeIntervalSince(thing.capturedAt)
            score += max(0, 1 - age / (7 * 86_400))   // fresh floats, capped +1
            return (thing, score)
        }
        .sorted { $0.1 > $1.1 }
        .prefix(16)
        .map(\.0)
    }

    /// The tags that mean YOU wrote it, across every import room. `Saved`,
    /// `Liked` and `Memory` are deliberately absent — they are things you
    /// TAPPED or were handed, and counting them as your writing is the whole
    /// distinction this scope exists to draw.
    static let mine: Set<String> = ["Post", "Reply", "Comment", "Thread"]

    /// Whether a query explicitly asks for the person's OWN writing, and the
    /// words that said so.
    ///
    /// Phrases only, never a bare noun. "What I wrote" and "my own words" have
    /// exactly one reading; "posts" has several, which is why that lives in
    /// `facetFilter` behind a named room. Getting this boundary wrong in the
    /// permissive direction would make an ordinary search silently exclude
    /// every link and note in the corpus.
    static func writingScope(in query: String) -> Set<String>? {
        let phrases = [
            "everything i wrote", "everything i've written", "everything ive written",
            "what i wrote", "what i've written", "what ive written",
            "things i wrote", "stuff i wrote", "my own words", "my writing",
            "posts i wrote", "anything i wrote",
        ]
        let haystack = " " + query.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ") + " "
        for phrase in phrases where haystack.contains(" " + phrase + " ") {
            return Set(phrase.split(separator: " ").map(String.init))
        }
        return nil
    }

    /// The FACET a query names within a room — a half of that room rather than
    /// a subject in it (2026-08-05, prd §307).
    ///
    /// The vocabulary is fixed and small on purpose. An importer's tags are the
    /// only ones that partition a room into halves a person would name out
    /// loud: X's `Post` / `Reply` / `Liked`, Instagram's and TikTok's `Saved` /
    /// `Liked`. A topic tag is NOT a facet — "design" names what a thing is
    /// about, and the scorer already handles that at double weight; promoting
    /// every tag to a hard filter would make an ask about a subject silently
    /// exclude everything not tagged with it.
    ///
    /// Longest phrase first, so "my own posts" reads as the `Post` facet rather
    /// than stopping at the bare word, and plurals and singulars both resolve.
    static func facetFilter(in query: String) -> (tag: String, words: Set<String>)? {
        // Order matters: the first entry whose phrase appears wins, so the
        // more specific phrasings lead.
        let table: [(phrases: [String], tag: String)] = [
            (["my own posts", "own posts", "my posts", "posts", "post"], "Post"),
            (["my replies", "replies", "reply", "replied"], "Reply"),
            (["what i liked", "i liked", "my likes", "likes", "liked"], "Liked"),
            (["my saves", "saves", "saved"], "Saved"),
            // The read X can't answer about your own corpus: posts you kept
            // that no longer exist there. Stamped by the author pass — see
            // `XArchiveImport.fetchFaces`.
            (["gone", "deleted", "no longer there", "disappeared"], "Gone"),
            (["threads", "thread"], "Thread"),
            // The remaining halves of the four import rooms (2026-08-05,
            // prd §309): Instagram's and TikTok's comments, and Snapchat's two.
            (["my comments", "comments", "comment"], "Comment"),
            (["conversations", "conversation", "chats", "chat"], "Conversation"),
            (["memories", "memory"], "Memory"),
        ]
        let haystack = " " + query.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ") + " "
        for entry in table {
            for phrase in entry.phrases where haystack.contains(" " + phrase + " ") {
                return (entry.tag, Set(phrase.split(separator: " ").map(String.init)))
            }
        }
        return nil
    }

    /// The source a query NAMES, and the words that named it.
    ///
    /// WHY THIS EXISTS. Until 2026-08-05 this engine scored `title`, `tags` and
    /// `content` and nothing else, so a source name was invisible to it: "can
    /// you search my X stuff" over a 3,500-post X archive stripped to the terms
    /// `can` / `x` / `stuff` and answered with whatever unrelated things happen
    /// to contain the word "can". A kind word had been a filter since the
    /// beginning ("screenshots about work"); a source word — the other half of
    /// what a thing IS — had no route in at all.
    ///
    /// THE VOCABULARY IS THE CATALOG, not the corpus. `BridgeCatalog.offers` is
    /// this app's own fixed set of source names, so resolving against it costs
    /// no fetch and — the part that matters — is COMPLETE: deriving the
    /// vocabulary from the things we happened to fetch would make a source
    /// nameable only while something of its own sits inside that window, which
    /// is exactly wrong for an archive dated across years. A name that resolves
    /// here but has nothing stored simply matches nothing, which is the honest
    /// answer anyway.
    ///
    /// MATCHED ON WORD BOUNDARIES and LONGEST FIRST. Boundaries because a
    /// substring match would let "Files" match "profiles"; longest first
    /// because "Apple Music" and "Apple Health" share a word and the shorter
    /// name must never win the query that named the longer one.
    static func sourceFilter(in query: String,
                             sources: [String] = BridgeCatalog.offers.map(\.name))
        -> (source: String, words: Set<String>)? {
        func padded(_ s: String) -> String {
            " " + s.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
                .joined(separator: " ") + " "
        }
        let haystack = padded(query)
        var best: (source: String, words: Set<String>)?
        for source in sources {
            let needle = padded(source)
            guard needle.count > 2, haystack.contains(needle) else { continue }
            let words = Set(needle.split(separator: " ").map(String.init))
            if best == nil || words.count > best!.words.count {
                best = (source, words)
            }
        }
        return best
    }
}
