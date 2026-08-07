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
        /// "my most liked post", "my best post on X", "most reposted in 2019"
        /// (2026-08-05, prd §307) — a superlative naming a real THING, not a
        /// tally: the answer is the post itself and the count is how it won.
        ///
        /// It exists because the archive carries `favorite_count` and
        /// `retweet_count` per post and X's own product makes your best post
        /// remarkably hard to find — there is no "sort by likes" anywhere in
        /// it, and scrolling fifteen years to eyeball one is not a search.
        case topThing(metric: Metric, source: String?,
                      range: ClosedRange<Date>?, rangeWords: String?)
    }

    /// Which engagement number a superlative is asking about.
    enum Metric {
        case likes, reposts

        var noun: String { self == .likes ? "liked" : "reposted" }
        func count(_ thing: Thing) -> Int? {
            self == .likes ? thing.likeCount : thing.repostCount
        }
    }

    /// `sources` is an `@autoclosure` (2026-07-21): every caller used to
    /// materialize the full corpus just to build this list BEFORE finding
    /// out whether the query even mentions "how many"/"most" — the two early
    /// exits below never touch it. Deferring the argument means a plain
    /// lookup query (the common case) never pays for it.
    static func parse(_ query: String, sources: @autoclosure () -> [String]) -> Intent? {
        let q = query.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "?! "))
        let date = DateQuery.match(in: q)
        let rangeWords = date.map { _ in rangePhrase(in: q) }

        // "which app/source sent the most", "most active app", "what app
        // landed the most" — a superlative over sources.
        if (q.contains("most") && (q.contains("app") || q.contains("source")))
            || q.contains("most active") {
            return .topSource(range: date?.range, rangeWords: rangeWords ?? nil)
        }

        // A superlative over THINGS, by what they earned. Checked after
        // `topSource` (whose own guard already requires the words "app" or
        // "source", so the two can't both match) and before "how many", which
        // is a count rather than a pick.
        //
        // BOTH HALVES REQUIRED — a superlative word AND an engagement word —
        // because "most" alone is one of the commonest words in a question and
        // matching it would hijack asks that have nothing to do with numbers.
        let superlatives = ["most", "best", "top", "biggest"]
        if superlatives.contains(where: { q.contains($0) }) {
            let metric: Metric? = {
                for word in ["repost", "retweet", "reshared", "shared most"]
                where q.contains(word) { return .reposts }
                for word in ["like", "liked", "popular", "favourite", "favorite"]
                where q.contains(word) { return .likes }
                // "my best post" / "top tweet" name no number, and likes is
                // what those mean in every product that has both.
                for word in ["post", "tweet"] where q.contains(word) { return .likes }
                return nil
            }()
            if let metric {
                return .topThing(metric: metric, source: namedSource(q, sources: sources()),
                                 range: date?.range, rangeWords: rangeWords ?? nil)
            }
        }

        guard q.contains("how many") else { return nil }
        var words = q.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        if let dateWords = date?.words { words.removeAll { dateWords.contains($0) } }

        let kind = ThingKind.allCases.first { k in
            words.contains(k.typeTag.lowercased()) || words.contains(k.typeTagPlural.lowercased())
        }
        let source = sources().first { s in
            let sw = s.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
            return !sw.isEmpty && sw.allSatisfy(words.contains)
        }
        return .count(kind: kind, source: source, range: date?.range,
                      rangeWords: rangeWords ?? nil)
    }

    /// A source the query names, matched on whole words so "X" can't be found
    /// inside another word. Shares `Retriever.sourceFilter`'s vocabulary and
    /// matching rule rather than spelling a second one — one definition, so a
    /// superlative and a search can never disagree about which room was named.
    private static func namedSource(_ q: String, sources: [String]) -> String? {
        Retriever.sourceFilter(in: q, sources: sources)?.source
    }

    /// The best thing by a metric, and the line naming it. nil when nothing in
    /// scope carries that number at all — which is the honest answer for a
    /// corpus whose rows never recorded one, and NOT the same as a tie at zero.
    static func topThing(metric: Metric, source: String?, range: ClosedRange<Date>?,
                         rangeWords: String?, things: [Thing]) -> (line: String, thing: Thing)? {
        let scoped = things.filter { thing in
            guard !Corpus.isImportReceipt(thing) else { return false }
            if let source, thing.source != source { return false }
            if let range, !range.contains(thing.capturedAt) { return false }
            return metric.count(thing) != nil
        }
        // `max(by:)` over the counts we actually have. A row with no count is
        // excluded above rather than treated as zero — an unrecorded number is
        // not a small one, the `messageCount` ruling in a second place.
        guard let best = scoped.max(by: { (metric.count($0) ?? 0) < (metric.count($1) ?? 0) }),
              let count = metric.count(best) else { return nil }
        let year = Calendar.current.component(.year, from: best.capturedAt)
        let when = rangeWords ?? String(year)
        let where_ = source.map { " on \($0)" } ?? ""
        return (String(localized: "Your most \(metric.noun) post\(where_) — \(count.formatted()), \(when)."),
                best)
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

    /// The name of the period BEFORE a given timeframe, for the comparative —
    /// only the timeframes with a clean, nameable predecessor (2026-07-22).
    /// "yesterday"/"on Monday" have none worth naming (yesterday-vs-the-day-
    /// before is noise), so they return nil and skip the clause.
    private static func priorPeriodLabel(_ rangeWords: String?) -> String? {
        switch rangeWords {
        case "this week":        return "last week"
        case "this month":       return "last month"
        case "today":            return "yesterday"
        case "over the weekend": return "the weekend before"
        default:                 return nil
        }
    }

    /// The one-line answer, computed. Returns nil only if the intent's
    /// filters name nothing that exists (a source typo, say) — the ask then
    /// falls through to the normal answer path.
    static func answer(_ intent: Intent, things: [Thing]) -> String {
        switch intent {
        case .count(let kind, let source, let range, let rangeWords):
            func filtered(_ base: [Thing], _ r: ClosedRange<Date>?) -> [Thing] {
                var pool = base
                if let kind { pool = pool.filter { $0.kind == kind } }
                if let source { pool = pool.filter { $0.source == source } }
                if let r { pool = pool.filter { r.contains($0.capturedAt) } }
                return pool
            }
            let pool = filtered(things, range)
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
            // A COMPARATIVE (2026-07-22, §177) — the same count over the period
            // BEFORE, when the timeframe is one with a nameable predecessor
            // ("this week" → "last week"). "23 links this week — 9 more than
            // last week" reads as intelligence and is pure arithmetic. Only a
            // real, non-zero delta earns the clause (a change that rounds to
            // nothing has nothing to say, §83); a period with no clean
            // predecessor (a bare weekday) simply omits it.
            if let range, let priorLabel = priorPeriodLabel(rangeWords) {
                // The prior window is normally the same-length span immediately
                // before (yesterday, last week, last month all fall out of
                // −duration). The WEEKEND is the exception: a 2-day span
                // shifted back by its own 2 days lands on Thu–Sat, not last
                // weekend — so it shifts back a full 7 days, keeping the same
                // Sat–Sun shape (caught in review, 2026-07-22).
                let dur = range.upperBound.timeIntervalSince(range.lowerBound)
                let prior: ClosedRange<Date>
                if rangeWords == "over the weekend" {
                    let week: TimeInterval = 7 * 86_400
                    prior = range.lowerBound.addingTimeInterval(-week)...range.upperBound.addingTimeInterval(-week)
                } else {
                    prior = range.lowerBound.addingTimeInterval(-dur)...range.lowerBound
                }
                let delta = pool.count - filtered(things, prior).count
                if delta != 0 {
                    let dir = delta > 0 ? "more" : "fewer"
                    return "\(pool.count) \(noun)\(when) — \(abs(delta)) \(dir) than \(priorLabel)."
                }
            }
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

        case .topThing(let metric, let source, let range, let rangeWords):
            // The line alone, for callers that render prose. `RootShell` uses
            // `topThing` directly so it can show the post beside it.
            return topThing(metric: metric, source: source, range: range,
                            rangeWords: rangeWords, things: things)?.line
                ?? String(localized: "Nothing here records how often a post was \(metric.noun).")
        }
    }
}

/// Tag-vocabulary asks (2026-07-12) — "what tags do i have", "list my tags",
/// "how many tags". A meta-question about the tag SET itself, not a search
/// for content. It used to fall into the term-scored retriever, which read
/// the literal words ("tags", "have") as search terms and surfaced noise (or
/// nothing) — reading as "nothing happened" on send. Answered from the tag
/// set directly: computed, no model, always correct.
enum TagsAsk {
    enum Intent { case list, count }

    /// nil unless the WHOLE question is about the tag set. Phrase-gated on
    /// purpose: "what did i tag as work" is a search, "tag lisbon as Trip" is
    /// an organize command (both handled elsewhere) — neither should list
    /// every tag. Organize/navigate commands are parsed before the answer
    /// path, so by the time this runs a leading "tag "/"show " has already
    /// had its chance.
    static func parse(_ raw: String) -> Intent? {
        let q = raw.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .trimmingCharacters(in: CharacterSet(charactersIn: "?!. "))
        // Count wins over listing: "how many tags do i have".
        if q.contains("how many tags") { return .count }
        let listCues = ["what tags", "which tags", "what are my tags",
                        "what are all my tags", "list my tags", "list tags",
                        "show my tags", "show me my tags", "see my tags",
                        "my tags", "tags do i have", "tags i have",
                        "tags have i", "tags do i use", "tags have i made",
                        "tags do i", "all my tags"]
        return listCues.contains(where: { q.contains($0) }) ? .list : nil
    }
}

/// Apps asks (2026-07-17) — "what apps do you have", "which apps are
/// connected", "how many apps". A meta-question about the app SET itself —
/// the connected seats and the catalog — not a search for content. It used
/// to fall into the term-scored retriever, which read the literal words
/// ("apps", "have") as search terms and surfaced noise — the answer read as
/// nonsense. Answered from BridgeStore + BridgeCatalog directly: computed,
/// no model, always correct (the TagsAsk move, applied to apps).
enum AppsAsk {
    enum Intent {
        /// "what apps are connected", "what apps do i have" — the seats.
        case connected
        /// "what apps do you have", "which apps can i connect" — the catalog.
        case catalog
        /// "how many apps …" — the counted line.
        case count
    }

    /// nil unless the WHOLE question is about the app set. Phrase-gated on
    /// purpose: "anything new from my apps" is a status ask and "which app
    /// sent the most" is arithmetic over sources (both handled elsewhere) —
    /// neither should list the catalog.
    static func parse(_ raw: String) -> Intent? {
        let q = raw.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .trimmingCharacters(in: CharacterSet(charactersIn: "?!. "))
        // A superlative over sources is AggregateAsk's ("which app sent the most").
        guard !q.contains("most") else { return nil }
        guard q.contains("apps") || q.contains("what's connected")
                || q.contains("whats connected") || q.contains("what is connected")
        else { return nil }
        if q.contains("how many") { return .count }
        // The person's own set first — "connected"/"do i have" ask about the
        // seats, not the shelf. "can i connect" stays a catalog ask: it asks
        // what's possible, not what's done.
        let connectedCues = ["connected", "do i have", "have i got", "i have",
                             "did i add", "have i added", "am i using",
                             "what are my apps", "which of my apps",
                             "list my apps", "show my apps", "show me my apps",
                             "see my apps"]
        if connectedCues.contains(where: q.contains),
           !q.contains("can i connect"), !q.contains("could i connect") {
            return .connected
        }
        let catalogCues = ["what apps", "which apps", "do you have",
                           "do you support", "do you offer", "can i connect",
                           "could i connect", "can i add", "are available",
                           "are there", "catalog"]
        return catalogCues.contains(where: q.contains) ? .catalog : nil
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
                               "what's up", "whats up", "fill me in", "the latest",
                               "while i was away", "since i was away", "since i left"]

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
        "around", "here", "right", "now", "recently", "please", "really",
        "while", "away", "since", "left", "gone", "back"
    ]

    /// The parsed pulse, or nil when the query isn't a status ask.
    /// `things` must arrive newest-first (the answer path's fetch order).
    /// `things` is an `@autoclosure` (2026-07-21): the cue/filler-word guards
    /// above reject the vast majority of queries before ever touching the
    /// corpus, so the caller's fetch should only happen for an actual status
    /// ask, not every ask that reaches this check.
    static func pulse(_ query: String, things: @autoclosure () -> [Thing], now: Date = .now) -> Pulse? {
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
        let things = things()

        // The librarian's window (prd §67 ⑥): an away-shaped ask grounds on
        // the FROZEN gap between last background and this foreground — not a
        // calendar window — so the answer is exactly what arrived while you
        // were gone. Never really away (gap under an hour, or a first visit):
        // the honest empty pulse; the counted line words it plainly.
        if q.contains("away") || q.contains("i left") {
            guard let away = AppVisit.away else {
                return Pulse(windowWords: "while you were away", pool: [], sample: [])
            }
            let pool = things.filter { away.contains($0.capturedAt) }
            return Pulse(windowWords: "while you were away", pool: pool,
                         sample: sample(of: pool))
        }

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
            i == 0 ? String(localized: "\(e.value) thing from \(e.key)")
                   : "\(e.value) from \(e.key)"
        }
        if ranked.count > shown.count {
            let rest = ranked.count - shown.count
            parts.append(String(localized: "more from \(rest) other app"))
        }
        let joined = parts.count == 1
            ? parts[0]
            : parts.dropLast().joined(separator: ", ") + ", and " + parts.last!
        return "\(opener): \(joined)."
    }
}

/// On-device semantic term expansion (2026-07-10) — Apple's word embedding
/// widens retrieval so "car stuff" can reach "vehicle"/"automobile" titles
/// without word overlap. Neighbors only (no per-thing vector math): cheap,
/// deterministic, fully on-device. Expanded matches score BELOW exact ones.
enum SemanticExpand {
    private static let embedding = NLEmbedding.wordEmbedding(for: .english)

    /// How near a neighbour must be to stand in for a query word.
    ///
    /// MEASURED 2026-08-06 (prd §318 amendment), and the reason the sweep
    /// exists: at the original 1.0 this was the last source of "general
    /// answers", and by a wide margin — over a real corpus "roman empire"
    /// answered with a story about Ukraine and "knitting patterns" with one
    /// about Spotify, neither sharing a single word with the query. NLEmbedding
    /// returns eight neighbours no matter how far away they are, and at 1.0
    /// every one of them counted; "car" → "vehicle" is close, "roman" →
    /// "russian" is not, and only the distance tells them apart.
    ///
    /// `-expandDistance <n>` overrides it in DEBUG so a sweep can compare
    /// cutoffs on one corpus in a single run.
    static var maxDistance: Double {
        #if DEBUG
        let override = UserDefaults.standard.double(forKey: "expandDistance")
        if override > 0 { return override }
        #endif
        return 0.82
    }

    static func expand(_ terms: [String]) -> Set<String> {
        guard let embedding else { return [] }
        let limit = maxDistance
        var out: Set<String> = []
        for term in terms {
            // Under `EmbeddingIndex.exclusively` for the reason recorded on
            // `EmbeddingIndex.nlLock`: `NLEmbedding` is not thread-safe, and
            // build 280 crashed on open with two threads inside one. This is a
            // DIFFERENT model object (words, not sentences) reached from a
            // nonisolated `Retriever.rank`, but it runs through the same
            // CoreNLP/BNNS machinery, so it takes the same lock rather than
            // resting on "nothing calls rank off the main actor today".
            for (word, distance) in EmbeddingIndex.exclusively({
                embedding.neighbors(for: term, maximumCount: 8)
            })
            where distance < limit {
                out.insert(word.lowercased())
            }
        }
        out.subtract(terms)
        return out
    }
}
