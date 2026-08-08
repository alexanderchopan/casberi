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
    /// screenshots for work). Since 2026-08-06 (prd §318) the scoring is also
    /// SPECIFIC, three ways: a term's weight is its RARITY in this corpus
    /// (`idfWeight` — "Lisbon" outweighs "work"), a thing matching MORE of the
    /// query outranks one matching a single word (`coverageFactor` — the fix
    /// for one common word dragging noise into the grounding set), and
    /// adjacent query words found adjacent in a thing score extra ("climate
    /// change" as a phrase beats either word alone). Returns the ranked
    /// grounding set (top 16 — a wide net for the model to rerank, well past
    /// the 4 the fallback paints; raised from 10, 2026-07-15).
    ///
    /// `isPoolRefinement` is true when `corpus` already arrived as a
    /// follow-up's narrowed pool rather than a fresh fetch — it skips the
    /// sentence-embedding pass (a narrowed pool carries no new words of its
    /// own to re-embed against).
    static func rank(_ query: String, in corpus: [Thing], isPoolRefinement: Bool) -> [Thing] {
        let scoped = rank(query, in: corpus, isPoolRefinement: isPoolRefinement,
                          honourSource: true)
        guard scoped.isEmpty else { return scoped }
        // A SOURCE FILTER THAT EMPTIES THE ANSWER IS NOT A FILTER, IT IS A WALL
        // (2026-08-06, prd §318 amendment 2). §307 made a source name scope the
        // search and that ruling stands — "my X stuff" over a 3,500-post archive
        // must mean the X room. But a source name is often an ordinary word that
        // merely happens to be an app's: measured, "onchain wallet analytics"
        // returned NOTHING, because "wallet" resolved to the Wallet bridge,
        // scoped the search to four transactions and stripped itself from the
        // terms — while a Circle x402 row titled "Onchain alpha, wallet flow,
        // and DEX analytics" answered the question exactly.
        //
        // So the scope is TRIED FIRST and kept whenever it answers; only a
        // scoped read that comes back empty falls through to the whole corpus,
        // where the source name scores as the ordinary word it was. Every query
        // §307 fixed is unaffected — those return rows, and a non-empty result
        // never reaches this line.
        guard let named = Self.sourceFilter(in: query),
              corpus.contains(where: { $0.source == named.source }) else { return scoped }
        return rank(query, in: corpus, isPoolRefinement: isPoolRefinement,
                    honourSource: false)
    }

    private static func rank(_ query: String, in corpus: [Thing], isPoolRefinement: Bool,
                             honourSource: Bool) -> [Thing] {
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
        let named = honourSource ? Self.sourceFilter(in: query) : nil
        let sourceMatch = named.flatMap { match in
            corpus.contains { $0.source == match.source } ? match : nil
        }
        // Split the query the SAME way a thing's fields are tokenized below —
        // on every non-alphanumeric, not on spaces (2026-08-06).
        //
        // It used to split on spaces alone, so a query term kept its dots while
        // the fields it was matched against had theirs stripped: a handle
        // ("someone.bsky.social", "vitalik.eth"), a domain ("allium.so") or a
        // filename could NEVER match, because the engine looked for one token
        // with dots in a set that held three without. Precisely the values a
        // person is most likely to search a social or x402 room by.
        //
        // Single characters are dropped: splitting this way turns "what's" into
        // "what" + "s", and a bare "s" scored as a search term matches most of
        // the corpus. Source names are resolved off the RAW query above, so a
        // one-letter source ("X") is already claimed before this runs.
        var terms = query.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 }
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
        terms.removeAll { Self.stops.contains($0) }

        // A date phrase ("today", "last week", "thursday") is a WHEN filter,
        // not a text term — things outside the range drop out entirely.
        let dateMatch = DateQuery.match(in: query)
        if let dateMatch { terms.removeAll { dateMatch.words.contains($0) } }

        let all = corpus
        // Semantic widening: near-synonyms of the query's words, scored
        // BELOW exact matches — "car stuff" reaches "vehicle" titles.
        //
        // Expanded PER TERM rather than in one flat set (2026-08-06), because a
        // synonym's worth depends entirely on which word it stands in for.
        // Expanding a rare word is where this feature earns its place;
        // expanding a common one produces common neighbours and pure noise —
        // measured, "change" reaches "another", which put a Vogue piece and a
        // Ford review into a "climate change" answer. Attribution is what lets
        // the floor below credit a synonym against the term it replaced.
        var expansionsByTerm: [String: Set<String>] = [:]
        for term in terms { expansionsByTerm[term] = SemanticExpand.expand([term]) }
        let expanded = Set(expansionsByTerm.values.joined())

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
        let semanticQualifyFloor = Self.semanticQualifyFloor
        let semanticWeight = 3.0

        // Whole words, not substrings (2026-07-10): "what is my name" used
        // to match the "is" inside "Lisbon" and answer with nonsense — a
        // term now has to BE a word somewhere in the thing. Tokens are kept
        // ORDERED too (2026-08-06): the adjacency bonus needs word order, and
        // the membership sets are derived from the same single pass.
        func tokens(_ s: String) -> [String] {
            s.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
        }

        // Pass 1 — filter and tokenize each candidate ONCE. The hard filters
        // run first so a dropped thing costs no tokenization; the padded
        // joined strings exist for the adjacency check (" a b " containment
        // is a word-boundary phrase match with no regex).
        let prepared: [Prepared] = all.compactMap { thing -> Prepared? in
            if let sourceMatch, thing.source != sourceMatch.source { return nil }
            if let facetMatch, !thing.tags.contains(facetMatch.tag) { return nil }
            if writingScope != nil, Self.mine.isDisjoint(with: thing.tags) { return nil }
            if let kindFilter, thing.kind != kindFilter { return nil }
            if let dateMatch, !dateMatch.range.contains(thing.capturedAt) { return nil }
            let titleTokens = tokens(thing.title)
            // WHOSE it is scores like a tag (2026-08-06). `authorHandle` is the
            // poster on a social row, the seller on an x402 row, the creator on
            // an imported like — the field every "whose" room is already keyed
            // by — and until now the ranking engine could not see it at all, so
            // a handle only matched when it happened to appear in the title.
            let tagTokens = tokens(thing.tags.joined(separator: " ")
                                   + " " + (thing.authorHandle ?? ""))
            // The content scan reaches the thing's own body, its enriched text
            // (a link's fetched article, 2026-07-15), the FULL post text, and
            // the source's own abstract.
            //
            // `postText` is the one that mattered most and was missing: for
            // every social row `content` holds the PERMALINK, `title` is an
            // 80-char clamp, and the post's real words live only here — so the
            // searchable body of a Farcaster, Bluesky, Nostr, Slack or X row
            // was a URL, and anything said past the clamp could not be found.
            // `summary` is display copy the source wrote (a Trello card back, a
            // Cursor agent's account of its run, an x402 seller's line); the
            // embedding index has read it since 2026-07-22 and the keyword
            // engine never did.
            //
            // Each field's tokens are kept as their own RUN and joined with a
            // sentinel, so the phrase bonus can't match across a seam and
            // invent an adjacency that exists in neither field.
            let contentRuns = [thing.content, thing.enrichedText ?? "",
                               thing.postText ?? "", thing.summary ?? ""]
                .map(tokens).filter { !$0.isEmpty }
            let contentTokens = contentRuns.flatMap { $0 }
            return Prepared(thing: thing,
                            title: Set(titleTokens),
                            tags: Set(tagTokens),
                            content: Set(contentTokens),
                            titleText: " " + titleTokens.joined(separator: " ") + " ",
                            contentText: " " + contentRuns
                                .map { $0.joined(separator: " ") }
                                .joined(separator: " \u{1} ") + " ")
        }

        // Pass 2 — each term's weight is its RARITY in this corpus (prd §318):
        // document frequency counted over the filtered set, mapped through
        // `idfWeight` so "Lisbon" pulls several times harder than "work".
        // Computed here, once per query, never per thing.
        var idf: [String: Double] = [:]
        for term in terms {
            let df = prepared.reduce(0) { count, entry in
                count + ((entry.title.contains(term) || entry.tags.contains(term)
                          || entry.content.contains(term)) ? 1 : 0)
            }
            idf[term] = Self.idfWeight(corpus: prepared.count, holding: df)
        }
        // Adjacent query-word pairs, in the person's own order — "climate
        // change" found AS a phrase in a thing is stronger evidence than the
        // two words scattered. Stop-word removal above can join words that
        // weren't adjacent in the raw query; that only ever WIDENS what counts
        // as a phrase, and a bonus that occasionally fires on "trip … lisbon"
        // is still evidence of the right thing.
        let pairs: [String] = terms.count > 1
            ? (0..<(terms.count - 1)).map { " \(terms[$0]) \(terms[$0 + 1]) " } : []

        // The query's whole information content, for the floor below. Summed
        // once, not per thing.
        let totalMass = terms.reduce(0.0) { $0 + (idf[$1] ?? 1) }

        // A SYNONYM carries its own rarity too (prd §318 amendment, measured on
        // the simulator). `SemanticExpand` hands back up to eight neighbours
        // per term and they scored a flat 1.5/1/0.5 — unweighted, and exempt
        // from the mass floor because they are not exact matches. Measured
        // consequence over a real corpus: "climate change" returned a Vogue
        // piece ("gave another nod of approval") and a Ford review ("needs
        // another Taurus"), NEITHER of which contains either query word — they
        // matched the neighbour "another", a word most of the corpus says.
        // A synonym that common is not evidence of anything, so a neighbour is
        // weighted by its own rarity and dropped outright below
        // `expansionFloor`.
        var expandedIdf: [String: Double] = [:]
        for word in expanded {
            let df = prepared.reduce(0) { count, entry in
                count + ((entry.title.contains(word) || entry.tags.contains(word)
                          || entry.content.contains(word)) ? 1 : 0)
            }
            let weight = Self.idfWeight(corpus: prepared.count, holding: df)
            if weight >= Self.expansionFloor { expandedIdf[word] = weight }
        }

        return prepared.compactMap { entry -> (Thing, Double)? in
            let thing = entry.thing
            var exact = 0.0
            var matchedTerms = 0
            var matchedMass = 0.0
            // Synonym credit, accumulated here so it can be added AFTER the
            // coverage scaling below — an expanded hit is weaker evidence and
            // must not be multiplied by a coverage figure it didn't earn.
            var synonym = 0.0
            for term in terms {
                let weight = idf[term] ?? 1
                var hit = false
                if entry.title.contains(term) { exact += 3 * weight; hit = true }
                if entry.tags.contains(term) { exact += 2 * weight; hit = true }
                if entry.content.contains(term) { exact += 1 * weight; hit = true }
                if hit {
                    matchedTerms += 1
                    matchedMass += weight
                    continue                     // said the word itself — no stand-in needed
                }
                // This term is absent; a near-synonym may stand in for it, at
                // HALF the term's mass. Half because it is genuinely weaker
                // evidence, and crediting it in full would let "change" →
                // "another" satisfy a query about climate.
                var stoodIn = false
                for neighbour in expansionsByTerm[term] ?? [] {
                    guard let nWeight = expandedIdf[neighbour] else { continue }
                    if entry.title.contains(neighbour) { synonym += 1.5 * nWeight; stoodIn = true }
                    if entry.tags.contains(neighbour) { synonym += 1 * nWeight; stoodIn = true }
                    if entry.content.contains(neighbour) { synonym += 0.5 * nWeight; stoodIn = true }
                }
                if stoodIn { matchedTerms += 1; matchedMass += 0.5 * weight }
            }
            // COVERAGE (prd §318): a thing matching one of four query words is
            // demoted well below one matching all four — the single biggest
            // cause of "general answers" was OR-semantics letting a lone
            // common word ride into the grounding set. Scales the EXACT
            // subtotal only: synonym and semantic evidence below keep their
            // own paths, so "car stuff" still reaches a "vehicle" title.
            var score = exact * Self.coverageFactor(matched: matchedTerms, of: terms.count)
                + synonym
            for pair in pairs {
                if entry.titleText.contains(pair) { score += 2.5 }
                if entry.contentText.contains(pair) { score += 1 }
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
            // THE RELEVANCE FLOOR (prd §318 amendment, 2026-08-06 — measured on
            // the simulator, see below). Ranking is not filtering: coverage
            // demotes a one-common-word match, but with nothing better in the
            // corpus that match still leads, and sixteen of them still fill the
            // screen. Measured over a real 130-thing corpus, "climate change"
            // — a subject NOTHING there is about — answered "11 things match"
            // with a Ford Taurus review and a visa-rules piece, because both
            // say "change". That is the reported complaint exactly, and no
            // amount of reordering fixes it.
            //
            // The rule: a thing must carry a real share of what the query was
            // ASKING — measured in the terms' own rarity, not their count. So
            // matching "change" out of "climate change" is 0.38 of the mass and
            // fails, while matching three words of "pasta recipe lisbon trip"
            // is most of it and passes even though a rarer word is missing.
            //
            // ONE exemption: a strong sentence-embedding match still qualifies
            // on its own, the unchanged §282 rail.
            //
            // Synonyms used to be exempt too, and that hole is what kept the
            // reported query broken: a thing matching NO query word could
            // qualify on a near-neighbour alone, so "climate change" still
            // answered with "Vogue gave another nod" and "Ford needs another
            // Taurus" — neither containing either word — long after the floor
            // landed. Tightening the neighbour distance could not fix it
            // ("another" sits very close to "change") without gutting the
            // synonym reach the feature exists for. Crediting a synonym at half
            // its term's mass does fix it, and needs no exemption: a single-word
            // query answered by a synonym alone still clears the floor at
            // exactly 0.5, so "car" → a "vehicle" title survives, while a
            // synonym for one word of two carries 0.25 and does not.
            if !terms.isEmpty, totalMass > 0,
               matchedMass / totalMass < Self.massFloor {
                let strongMeaning: Bool = {
                    guard let queryVec, let queryLanguage,
                          let data = thing.embedding, !data.isEmpty else { return false }
                    return EmbeddingIndex.similarity(query: queryVec, queryNorm: queryNorm,
                                                     packed: data,
                                                     language: queryLanguage) >= semanticQualifyFloor
                }()
                if !strongMeaning { return nil }
            }
            let age = Date.now.timeIntervalSince(thing.capturedAt)
            score += max(0, 1 - age / (7 * 86_400))   // fresh floats, capped +1
            return (thing, score)
        }
        .sorted { $0.1 > $1.1 }
        .prefix(16)
        .map(\.0)
    }

    // MARK: - Scoring primitives (pure — verified by scripts/retriever-selftest.sh)

    /// One candidate, tokenized once. The membership sets answer "does this
    /// thing say that word"; the padded joined strings answer "does it say
    /// these two words TOGETHER" — a phrase match by containment, no regex.
    /// A plain struct rather than a tuple so `rank`'s two passes share one
    /// named shape rather than a six-field type spelled twice.
    private struct Prepared {
        let thing: Thing
        let title: Set<String>
        let tags: Set<String>
        let content: Set<String>
        let titleText: String
        let contentText: String
    }

    /// The words that carry no content — questions' scaffolding, command verbs,
    /// filler. Enum-scope so `contentTerms` shares the exact set `rank` strips.
    static let stops: Set<String> = ["about", "my", "the", "a", "in", "from", "for", "of",
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

    /// The share of a query's information a thing must actually carry to be a
    /// match at all (prd §318 amendment).
    ///
    /// MEASURED, and the margin is genuinely tight — do not round this number
    /// off. Over a real 130-thing corpus: a "climate change" candidate matching
    /// only "change" carries 0.38 of the query's mass, and a "vaccines fridge
    /// free" candidate matching only "free" carries 0.31 — both noise, both
    /// must fail. But a query naming two RARE words where the corpus holds only
    /// one ("lisbon tokyo" against a corpus with a Lisbon note) carries ~0.44,
    /// and that is an honest partial answer that must pass — so the round 0.5
    /// is wrong, and was measured refusing exactly that case.
    ///
    /// The band is NARROW and moves with corpus size, so treat 0.40 as MEASURED
    /// rather than principled: noise measured 0.31 and 0.34–0.38; honest
    /// partials measured 0.44 on a 12-thing corpus, rising toward 0.5 as the
    /// corpus grows and a rare word's weight approaches its ceiling. 0.40 sits
    /// between them with the most room on either side. Both bounds are pinned
    /// by fixtures in `scripts/retriever-selftest.sh` — retune this and one of
    /// them tells you which side you broke.
    ///
    /// The asymmetry is the whole point and is what makes the rule work: an
    /// absent term inflates the denominator (nothing says it, so it scores
    /// maximum rarity), which is why matching only a COMMON word fails while
    /// matching one of two RARE words passes. Matching "change" says nothing
    /// about climate; matching "lisbon" says a great deal about Lisbon.
    static let massFloor = 0.40

    /// How similar a thing must be, by SENTENCE EMBEDDING alone, to answer a
    /// question it shares no words with (prd §282's rail, exposed here 2026-08-06
    /// so it can be measured rather than argued about).
    ///
    /// This is the one number the keyword rules cannot reach: a thing with no
    /// exact match and no synonym still qualifies on meaning alone, which is
    /// the feature — and, measured on a real corpus, also the last source of
    /// "general answers". `-semanticFloor <n>` overrides it in DEBUG so a sweep
    /// can compare floors on the SAME corpus in one run; release builds always
    /// use the shipped value.
    static var semanticQualifyFloor: Double {
        #if DEBUG
        let override = UserDefaults.standard.double(forKey: "semanticFloor")
        if override > 0 { return override }
        #endif
        return 0.62
    }

    /// How distinctive a SYNONYM must be to count as evidence at all (prd §318
    /// amendment). `SemanticExpand` returns a word's eight nearest neighbours
    /// with no regard for whether the corpus is full of them, and a neighbour
    /// most things say is not evidence — measured, it was "another" putting a
    /// Vogue piece and a Ford review into a "climate change" answer. At 0.6 a
    /// neighbour has to sit in under roughly a quarter of the corpus, which is
    /// what removed both while leaving genuine synonym reach ("car" → a
    /// "vehicle" title) untouched.
    static let expansionFloor = 0.6

    /// A term's rarity weight over this corpus (prd §318): 1.5 for a word one
    /// thing says, tapering to 0.3 for a word every thing says. Log-scaled and
    /// normalized against the corpus size, so the spread is stable whether the
    /// corpus holds 40 things or 2,000 — a rare term pulls roughly 3–5× a
    /// ubiquitous one, never orders of magnitude (a floor of 0.3 keeps a
    /// common word a real, if small, signal rather than deleting it).
    static func idfWeight(corpus n: Int, holding df: Int) -> Double {
        guard n > 0 else { return 1 }
        let ceiling = log2(Double(n) + 1)
        guard ceiling > 0 else { return 1 }
        let raw = log2((Double(n) + 1) / (Double(df) + 1))
        return 0.3 + 1.2 * max(0, min(1, raw / ceiling))
    }

    /// How much of the query a thing actually matched, as a multiplier on its
    /// exact-keyword score (prd §318). Smooth, never zero: full coverage is
    /// 1.0, one-of-four is ~0.33, and a thing with only synonym evidence
    /// (matched 0) keeps a sliver rather than being deleted — the demotion is
    /// the point, not a hard AND (a hard AND would empty every query
    /// containing one word the corpus doesn't say).
    static func coverageFactor(matched: Int, of total: Int) -> Double {
        guard total > 0 else { return 1 }
        return (Double(matched) + 0.5) / (Double(total) + 0.5)
    }

    /// The window of `body` centered on its first whole-word hit of any term —
    /// what lets the model's per-thing snippet carry the passage that MATCHED
    /// instead of the opening pleasantries (prd §318: a long note's or fetched
    /// article's head-300 chars rarely contain the fact the person asked for).
    /// Nil when no term appears as a whole word, and nil when the first hit
    /// already sits inside the head window — the caller's own head excerpt
    /// serves both, identically and without a misleading leading ellipsis.
    static func matchWindow(in body: String, terms: [String], radius: Int = 150) -> String? {
        guard !terms.isEmpty, !body.isEmpty else { return nil }
        func word(_ c: Character) -> Bool { c.isLetter || c.isNumber }
        var earliest: Range<String.Index>?
        for term in terms where !term.isEmpty {
            var search = body.startIndex..<body.endIndex
            while let r = body.range(of: term, options: .caseInsensitive, range: search) {
                let beforeOK = r.lowerBound == body.startIndex
                    || !word(body[body.index(before: r.lowerBound)])
                let afterOK = r.upperBound == body.endIndex || !word(body[r.upperBound])
                if beforeOK, afterOK {
                    if earliest == nil || r.lowerBound < earliest!.lowerBound { earliest = r }
                    break
                }
                search = r.upperBound..<body.endIndex
            }
        }
        guard let hit = earliest else { return nil }
        let start = body.index(hit.lowerBound, offsetBy: -radius, limitedBy: body.startIndex)
            ?? body.startIndex
        guard start > body.startIndex else { return nil }
        let end = body.index(hit.upperBound, offsetBy: radius, limitedBy: body.endIndex)
            ?? body.endIndex
        var out = "…" + String(body[start..<end])
        if end < body.endIndex { out += "…" }
        return out
    }

    /// The query's content-bearing words — lowercased, stop-stripped, in query
    /// order. What `matchWindow` centers a snippet on. A light mirror of
    /// `rank`'s term prep on purpose (no source/kind/date resolution): a
    /// snippet centered on a filter word is harmless, and one centered on
    /// nothing falls back to the head excerpt.
    static func contentTerms(_ query: String) -> [String] {
        query.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !Self.stops.contains($0) }
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
            // The half of a YouTube room nothing could name before (2026-08-06,
            // `YouTubeShorts`). Same rule as every entry above and it matters
            // more here than most: "short" is an ordinary English word, so
            // this only ever filters alongside a named source — "shorts from
            // YouTube" narrows, "something short" can't quietly empty a
            // result.
            (["shorts", "short"], "Shorts"),
            // App Store Connect's three halves (2026-08-06, prd §324). The
            // room mixes what Apple decided, what customers wrote, and what
            // your builds did — three genuinely different questions, and until
            // now nothing could ask one of them.
            //
            // The gating rule earns its keep here more than anywhere: "review",
            // "release" and "build" are all ordinary English AND all words this
            // app's own corpus is full of (a saved article about a release, a
            // note about building something). Behind a named source they
            // narrow; unscoped they can never quietly empty a result.
            (["my reviews", "reviews", "review", "ratings", "rating"], "Review"),
            (["releases", "release", "versions", "version"], "Release"),
            (["builds", "build"], "Build"),
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
            // A SOURCE NAME INTRODUCED AS A SUBJECT IS NOT A SCOPE (2026-08-07,
            // prd §340). §318's escape hatch only fires when the scoped read
            // comes back EMPTY — and the case reported here never does: "what
            // did I post about a wallet" scoped to the Wallet room, stripped
            // "wallet" from the terms, and returned that room's newest
            // transactions. Non-empty, so the fallback never ran, and the
            // Farcaster post the person actually wrote never reached a model.
            //
            // English marks the difference plainly. "about X" makes X the
            // SUBJECT of the question, and an indefinite article ("a wallet",
            // "an email") makes it a common noun. Neither can be a room. "my X
            // stuff" and "search my X" carry no such marker and are untouched,
            // so every query §307 fixed still scopes.
            if ["about", "a", "an"].contains(where: { haystack.contains(" \($0)" + needle) }) {
                continue
            }
            let words = Set(needle.split(separator: " ").map(String.init))
            if best == nil || words.count > best!.words.count {
                best = (source, words)
            }
        }
        return best
    }
}
