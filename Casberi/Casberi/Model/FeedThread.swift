import Foundation

/// The feed's cross-source thread — the head of the All feed (2026-08-07).
///
/// The design problem it answers: most people READ their feed far more than
/// they ASK the agent, so the synthesis the agent can do belongs at the top of
/// the feed, not behind a typed question. And the one synthesis no single-source
/// room can make — the one worth leading with — is a SUBJECT running across
/// several apps at once: a token you hold that you also saved a link about and
/// that a cast is discussing; a place named in a note, a calendar hold, and a
/// photo. Every per-source room already leads with its own hero (a topic map, a
/// heatmap, a roster); the All feed had none, and this is it.
///
/// DETERMINISTIC BY CONTRACT. No model, no async, no network — the feed head
/// must render instantly and identically on every device, so the model's own
/// read of the day stays in the brief (the ask surface). A thread is only ever
/// a set of REAL recent things sharing a real subject; the framing line names
/// the sources it spans and nothing more. RARE by construction — a genuine
/// cross-source cluster is uncommon, so on most days `find` returns nil and the
/// feed opens straight on its rows (the honest quiet-day state).
///
/// Holds NO `Thing` (the head-card contract in FeedScreen): each member carries
/// its `id`, and the feed resolves that against the live corpus when tapped, so
/// nothing here can read a stored property off a deleted model.
enum FeedThread {

    struct Member: Equatable, Sendable {
        /// `Thing.id.uuidString` — resolved against the live feed on tap.
        let id: String
        let title: String
        let source: String
        /// A short trailing fact — an age ("3h") or a reply count.
        let meta: String
    }

    struct Thread: Equatable, Sendable {
        /// The shared subject, in its own words ("Base airdrop", "Lisbon").
        let subject: String
        /// The deterministic framing line — the sources it runs across.
        let line: String
        let members: [Member]
    }

    /// The strongest cross-source thread among recent things, or nil.
    ///
    /// - `withinDays`: only recent things — a months-old cluster isn't news.
    /// - `minMembers` / `minSources`: the honesty gates. A subject must be
    ///   carried by several things spanning several apps to count; three things
    ///   from one app is that room's own topic (already its hero), not a thread.
    static func find(in things: [Thing], now: Date = .now,
                     withinDays: Int = 4, minMembers: Int = 3,
                     minSources: Int = 2, maxMembers: Int = 4) -> Thread? {
        let cutoff = now.addingTimeInterval(-Double(withinDays) * 86_400)
        // Liveness at the boundary (corollary 4) — every read below is a stored
        // property, and a heal pass deletes things under the feed constantly.
        // Import receipts are excluded: several "Imported N things from …"
        // rows across sources would otherwise mint a false "imported" thread —
        // the receipt is a fact about a sync, never a subject.
        let recent = things.filter {
            $0.isLive && $0.capturedAt >= cutoff && !Corpus.isImportReceipt($0)
        }
        guard recent.count >= minMembers else { return nil }

        // Candidate subjects: each thing's curated tags and its significant
        // title words, counted ONCE per thing, tracking which things (by id) and
        // which sources carry each. Counting once per thing stops a word
        // repeated in one headline out-voting three separate things sharing it
        // (the `TodayBrief.dominantTopic` lesson).
        struct Agg { var display: String; var ids: [String] = []; var sources: Set<String> = [] }
        var agg: [String: Agg] = [:]
        for thing in recent {
            let id = thing.id.uuidString
            let source = thing.source
            var keys = Set<String>()
            func credit(_ display: String, _ key: String) {
                guard keys.insert(key).inserted else { return }
                var entry = agg[key] ?? Agg(display: display)
                entry.ids.append(id)
                entry.sources.insert(source)
                agg[key] = entry
            }
            for tag in thing.tags {
                let key = tag.lowercased()
                if key.count >= 3, !stops.contains(key), !nonSubjectTags.contains(key) {
                    credit(tag, key)
                }
            }
            for word in significantWords(in: thing.title) {
                credit(word, word.lowercased())
            }
        }

        // Qualify and rank DETERMINISTICALLY: most sources, then most things,
        // then alphabetically — never `max(by:)` over hash order, which is
        // per-process and would name a different subject on each rise of the
        // same feed (the `dominantTopic` tie-break lesson).
        let winner = agg
            .filter { $0.value.ids.count >= minMembers && $0.value.sources.count >= minSources }
            .sorted { a, b in
                if a.value.sources.count != b.value.sources.count {
                    return a.value.sources.count > b.value.sources.count
                }
                if a.value.ids.count != b.value.ids.count {
                    return a.value.ids.count > b.value.ids.count
                }
                return a.key < b.key
            }
            .first
        guard let winner else { return nil }

        // Build members from the REAL things carrying the subject, newest
        // first, capped. Keyed off the same `recent` array — no second fetch.
        let byID = Dictionary(recent.map { ($0.id.uuidString, $0) },
                              uniquingKeysWith: { first, _ in first })
        let memberThings = winner.value.ids
            .compactMap { byID[$0] }
            .sorted { $0.capturedAt > $1.capturedAt }
            .prefix(maxMembers)
        let members = memberThings.map { thing in
            Member(id: thing.id.uuidString,
                   title: clamp(thing.title, 64),
                   source: thing.source,
                   meta: meta(for: thing, now: now))
        }
        guard members.count >= minMembers else { return nil }
        let sources = orderedDistinct(members.map(\.source))
        return Thread(subject: winner.value.display,
                      line: framing(sources: sources),
                      members: Array(members))
    }

    // MARK: - Pure helpers

    /// The framing line — the sources the thread runs across, and nothing else.
    /// No count, no model prose: the value is the grouping, not the sentence
    /// (§249's "no tallies" applied to the head).
    static func framing(sources: [String]) -> String {
        String(localized: "Across \(joinAnd(sources))")
    }

    private static func meta(for thing: Thing, now: Date) -> String {
        if let replies = thing.replyCount, replies > 0 {
            return String(localized: "\(replies) replies")
        }
        return age(thing.capturedAt, now: now)
    }

    /// A compact relative age — "40m", "3h", "2d".
    static func age(_ date: Date, now: Date) -> String {
        let s = max(0, now.timeIntervalSince(date))
        if s < 3600 { return "\(max(1, Int(s / 60)))m" }
        if s < 86_400 { return "\(Int(s / 3600))h" }
        return "\(Int(s / 86_400))d"
    }

    /// The significant words of a title — 4+ characters, at least one letter,
    /// not a stopword. One tokenizer so membership and count always agree.
    static func significantWords(in title: String) -> [String] {
        title.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { word in
                word.count >= 4 && !stops.contains(word.lowercased())
                    && word.contains(where: { $0.isLetter })
            }
    }

    static func orderedDistinct(_ items: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for item in items where seen.insert(item).inserted { out.append(item) }
        return out
    }

    static func joinAnd(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        case 2: return String(localized: "\(items[0]) and \(items[1])")
        default:
            let head = items.dropLast().joined(separator: ", ")
            return String(localized: "\(head), and \(items.last!)")
        }
    }

    private static func clamp(_ s: String, _ maximum: Int) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maximum else { return trimmed }
        return String(trimmed.prefix(maximum - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// Words that never name a subject — filler plus the vocabulary every
    /// headline shares. The cross-source gate does most of the filtering; this
    /// only removes the obvious false leaders.
    static let stops: Set<String> = [
        "this", "that", "with", "from", "your", "have", "here", "what", "when",
        "will", "just", "into", "over", "more", "than", "then", "they", "them",
        "about", "after", "before", "could", "would", "should", "their", "there",
        "these", "those", "which", "while", "where", "https", "http", "www",
        "news", "says", "said", "make", "like", "still", "today", "tomorrow",
        "week", "year", "much", "some", "only", "been", "being", "very",
    ]

    /// Tags that partition a room into halves but never name a subject — the
    /// importers' facet tags (Post / Reply / Liked / …) and the plain kind
    /// words. A thread is about a WHAT, not a shape or a kind.
    static let nonSubjectTags: Set<String> = [
        "post", "posts", "reply", "replies", "liked", "saved", "save", "comment",
        "comments", "conversation", "memory", "thread", "threads", "shorts",
        "review", "reviews", "release", "build", "gone", "link", "links", "note",
        "notes", "screenshot", "event", "chat", "mail", "voice", "product",
        "transaction", "reminder",
    ]
}
