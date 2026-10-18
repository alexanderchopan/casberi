import Foundation
import NaturalLanguage

/// Two questions the corpus can answer about a thing you're looking at, both
/// on-device and both free of the model (prd §282, 2026-08-02):
///
///   • **Have I kept this before?** — deterministic. Same normalized title,
///     or the same link once the tracking junk is off it. Never a guess, so
///     the row can say it plainly.
///   • **What else is this near?** — the sentence-embedding neighbours
///     (`EmbeddingIndex`), which the Related shelf already used but only ever
///     asked for a TAGGED thing.
///
/// Kept apart from `ThingSheetView` on purpose: the duplicate rule is pure
/// arithmetic over strings and wants to be readable and testable in one place,
/// not spelled out inside a view body.
enum RelatedThings {

    // MARK: - Kept before

    /// A previously-kept copy of this thing, oldest first — "you kept this in
    /// April", the answer to the small recurring annoyance of saving the same
    /// article twice from two apps.
    ///
    /// **Deliberately deterministic, and deliberately NOT the embedding.** A
    /// cosine of 0.95 means "these are about the same thing", which is a fine
    /// basis for a Related shelf and a bad one for a claim — two different
    /// write-ups of one launch would trip it, and a row asserting you already
    /// kept something you didn't is exactly the fake status §83 bans. Same
    /// title or same link is a fact.
    ///
    /// **`sourceRef` equality is NOT a duplicate here**, though it looks like
    /// the obvious rule: two rows sharing a sourceRef are a dedupe BUG (that's
    /// what `-corpusDupeProbe` hunts), and surfacing our own bug to a person as
    /// "you kept this before" would launder it into a feature.
    static func keptBefore(_ thing: Thing, in corpus: [Thing]) -> Thing? {
        guard thing.isLive else { return nil }
        // A reading of an account — a charge, a proposal, a deploy, a block —
        // shares its app's title month after month ("Quillmark Pro · $29.00"),
        // so a same-title match there is a different record (the sweep's P6).
        let account = readsAccount(thing.source)
        // A dated thing — an event, anything with a due date — repeats by
        // design: tomorrow's "Dinner with Sam" and Friday's standup are other
        // occurrences, not an earlier save (prd §1413, user: "what does this
        // mean this is some fluff"). It matches by link alone.
        let dated = thing.kind == .event || thing.dueAt != nil
        let title = account || dated ? nil : normalizedTitle(thing.title)
        let link = objectLink(thing)
        // A thing with neither a distinctive title nor an object link can't be
        // matched honestly — a wall of untitled screenshots is not a pile of
        // duplicates, and a dashboard link is not an object.
        guard title != nil || link != nil else { return nil }

        return corpus
            .filter { other in
                guard other.isLive, other.id != thing.id else { return false }
                // A row from the same sync that carries the same ref is our
                // bookkeeping, not the person's second save.
                if let a = thing.sourceRef, let b = other.sourceRef, a == b { return false }
                if let link, objectLink(other) == link { return true }
                if let title, !readsAccount(other.source), normalizedTitle(other.title) == title {
                    // Same words in the same KIND. A note and a screenshot that
                    // happen to share a headline are two different objects.
                    return other.kind == thing.kind
                }
                return false
            }
            // The one you kept FIRST is the interesting one — that's the copy
            // this is a repeat of.
            .min { $0.capturedAt < $1.capturedAt }
    }

    // MARK: - The same object, never the same dashboard (the sweep's P6)

    /// The rooms whose rows are readings of an account, stamped with one
    /// dashboard, queue or explorer link (the Safe queue, Polar's and Dodo's
    /// dashboards, Bitrefill's orders page, PostHog, Logos' and Aztec's
    /// explorers). There a row is the same object only by a link that NAMES
    /// one — §1079's per-service test (`ObjectFold.workKey`).
    static let accountRooms: Set<String> = [CategoryFold.walletRoom, RoomAccounts.testnetsRoom,
                                            RoomAccounts.workRoom]

    static func readsAccount(_ source: String) -> Bool {
        guard let room = RoomAccounts.host(ofSource: source)?.room else { return false }
        return accountRooms.contains(room)
    }

    /// The object a row's link names, or nil when the link is shared by many
    /// records. §1079's fold, reused: a Work object's own URL (a PR, an issue,
    /// a deployment) wherever it was kept; an account room's other links are
    /// its dashboards and name nothing; anything else is the page itself,
    /// with a path — two saves of one article.
    static func objectLink(_ thing: Thing) -> String? {
        let raw = thing.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if let key = ObjectFold.workKey(raw) { return key }
        guard !readsAccount(thing.source),
              let canonical = canonicalLink(thing),
              canonical.count >= 12, ThingLinks.hasPath(canonical) else { return nil }
        return "read:" + canonical
    }

    /// A title reduced to what it says: lowercased, punctuation and runs of
    /// whitespace collapsed. nil when there's too little left to be a claim —
    /// under 8 characters, or a placeholder every screenshot wears.
    static func normalizedTitle(_ raw: String) -> String? {
        let stripped = raw.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard stripped.count >= 8 else { return nil }
        guard stripped != ScreenshotTitle.placeholder.lowercased() else { return nil }
        return stripped
    }

    /// The thing's link, reduced so two saves of one page match: scheme and
    /// `www.` dropped, host lowercased, tracking parameters removed, trailing
    /// slash gone. nil when the thing carries no http(s) link.
    ///
    /// The rule itself moved to `ThingLinks.canonicalLink(_ raw:)` (2026-08-08)
    /// when the "points at this" shelf needed the identical form to match a URL
    /// written inside somebody's post against the same page saved here. Two
    /// canonicalizers drift, and then "you kept this before" and "mentions
    /// this" disagree about whether two saves of one page are the same page,
    /// for a reason invisible from either file — `AgentCorpusTools.rank` /
    /// `ToolScore.rank`'s split, avoided in advance. This stays as the
    /// `Thing`-shaped door because every caller here holds a `Thing`, and the
    /// pure file must not.
    static func canonicalLink(_ thing: Thing) -> String? {
        ThingLinks.canonicalLink(thing.content)
    }

    // MARK: - Neighbours

    /// How near two things have to be to sit on the Related shelf. Looser than
    /// the answer path's 0.62 qualify floor on purpose — "related" is a weaker
    /// claim than "answers your question" (the number this file inherited from
    /// `ThingSheetView`, unchanged).
    static let relatedFloor = 0.5

    /// The corpus ranked by on-device semantic similarity to `thing` — the
    /// meaning-based Related set, cross-source by nature: it scores by meaning,
    /// not source or tag, so a GitHub PR reaches the Linear ticket and the chat
    /// that share no tag at all.
    ///
    /// Empty when the embedding model is unavailable, this thing can't be
    /// embedded, or nothing clears the floor — the caller falls back to tag
    /// overlap, exactly as before.
    static func neighbours(of thing: Thing, in corpus: [Thing],
                           floor: Double = relatedFloor,
                           limit: Int = 6) -> [Thing] {
        guard thing.isLive, EmbeddingIndex.isAvailable else { return [] }
        let text = EmbeddingIndex.indexText(for: thing)
        // The thing's OWN language decides the comparison — its stored vector
        // was made that way, and a vector in another language is excluded
        // rather than compared (prd §282).
        let language = EmbeddingIndex.language(of: text) ?? EmbeddingIndex.fallbackLanguage
        guard let query = EmbeddingIndex.vector(for: text, language: language) else { return [] }
        let queryNorm = EmbeddingIndex.norm(query)
        guard queryNorm > 0 else { return [] }
        return corpus.compactMap { other -> (Thing, Double)? in
            guard other.isLive, other.id != thing.id,
                  let data = other.embedding, !data.isEmpty else { return nil }
            let sim = EmbeddingIndex.similarity(query: query, queryNorm: queryNorm,
                                                packed: data, language: language)
            return sim >= floor ? (other, sim) : nil
        }
        .sorted { $0.1 > $1.1 }
        .prefix(limit)
        .map(\.0)
    }
}
