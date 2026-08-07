import Foundation

/// What the agent's room shows on a plain open — before anything is typed,
/// asked, or tapped (prd §332, 2026-08-07).
///
/// The complaint this answers: "the content and design of the agent when you
/// open it is terrible. we made all these changes, but i don't see them there."
/// That was exactly right, and the reason is structural rather than cosmetic.
/// Every synthesis this app learned to do in the last month — the brief's
/// modules, the room heads, the kept-ask digests, the ledger's streaks, the
/// cross-source joins — landed BEHIND A TAP. The open itself rendered a
/// greeting, one tinted sentence, and two rows of gray question-pills whose
/// whole content was the questions themselves. The work shipped; the front door
/// never changed.
///
/// So the rule here is one line: **the open answers before it is asked.** Every
/// element below is something the app ALREADY COMPUTES on that same open and
/// then throws away or hides:
///
///   • `KeptAskStore` composes each kept ask's digest on every open, purely to
///     decide whether to light a 7pt dot. The dot says "something moved"; the
///     computation behind it knows WHAT moved. `tiles` prints it.
///   • `OnDeviceModel.homeInsight` returns `(line, picks: [Int])` — plural —
///     and `HomeInsightStore` kept `picks.min()` and discarded the rest. Those
///     discarded picks are the evidence under `notice`, at no new model cost.
///   • `BriefLedger` has recorded which themes ran on which days since §214, and
///     nothing outside the brief ever read a streak. `threads` wears them.
///
/// Nothing here is a count of things (user ruling 2026-07-31: "i don't want to
/// see a count of 'things', that's an annoyance to the user"). Where a quantity
/// is the only honest thing to say, it names the SUBJECT and lets the number
/// trail as an aside — "Visa docs" and "+1 more", never "2 open".
///
/// **Foundation-only by design.** Everything below is pure over `Item`, a flat
/// value type the caller builds from `Thing`. That is not tidiness: it is what
/// lets `scripts/agent-open-selftest.sh` compile this file WHOLE and unmodified
/// and mutation-test the rankings, with no SwiftData stubs (`retriever-selftest`
/// needs six of them). It also means this file can never read a stored property
/// off a deleted model — the whole liveness-corollary class (checks 1–6) simply
/// cannot reach it, because by the time anything here runs the models are gone
/// and only their values remain.
enum AgentOpen {

    // MARK: - Input

    /// One thing, flattened to the fields this composition actually reads.
    ///
    /// Two fields are RESOLVED BY THE CALLER rather than derived here
    /// (`priorKeep`, `datedMoment`): both need app types this file deliberately
    /// doesn't import — `RelatedThings.keptBefore` walks the corpus, and
    /// `ScreenshotFacts.dates` runs `NSDataDetector` over OCR text. Passing the
    /// ANSWER in keeps the margin logic testable while leaving the expensive
    /// half where it already lives.
    struct Item: Equatable {
        var id: String
        var title: String
        var source: String
        var tags: [String] = []
        var author: String?
        var capturedAt: Date
        /// A real deadline the row carries (`Thing.dueAt`).
        var dueAt: Date?
        /// Replies gathered under a post of yours.
        var replyCount: Int?
        /// `"mention"` / `"liked"` / `"recast"` — `Thing.socialContext`.
        var socialContext: String?
        /// When this same thing was kept before (`RelatedThings.keptBefore`).
        var priorKeep: Date?
        /// An upcoming moment the row's own text names (`ScreenshotFacts.dates`).
        var datedMoment: Date?
    }

    // MARK: - Output

    /// The claim at the top, and the things it is a claim ABOUT.
    ///
    /// `evidence` may be empty, and that is a real state rather than a
    /// degenerate one: the model can return a line with no usable picks, and a
    /// claim standing alone is still worth more than the gray pills it
    /// replaced. It just can't be verified by tapping, so the card says less.
    struct Notice: Equatable {
        var claim: String
        var evidence: [Item]
        /// True when a deterministic observation stood in for the model's line.
        /// The card's kicker changes wording on it — "noticed overnight" claims
        /// the model looked, and saying that when no model exists is the fake
        /// status §83 forbids.
        var deterministic: Bool
    }

    /// A kept ask, with its answer on its face.
    struct Tile: Equatable {
        var kind: String
        /// The ask's own name, as the person kept it ("How's my wallet?").
        var title: String
        /// The answer, big. Never a bare tally.
        var headline: String
        /// The qualifier under it, or nil.
        var sub: String?
        /// Something moved since this was last seen — the old dot's meaning,
        /// kept as emphasis rather than as the whole message.
        var changed: Bool
    }

    /// A run of things that belong together, and why.
    struct Thread: Equatable {
        /// The shared term, title-cased for display — or the loose bucket's name.
        var name: String
        /// "4 days running", when the ledger says so. nil on a thread that is
        /// only today's.
        var streak: String?
        var rows: [Row]
        /// The catch-all bucket. Ranked last and never wears a streak.
        var loose: Bool
    }

    /// One row, and the one fact the agent can add to it.
    struct Row: Equatable {
        var item: Item
        /// The margin — a DETERMINISTIC fact about this thing, or nil.
        ///
        /// Never a model judgment. The mockup that led here said "this reverses
        /// the first draft", and that sentence is exactly what this must not
        /// contain: it is a claim only a reader could make, and a margin that
        /// can be wrong poisons the rows it is supposed to be enriching. What
        /// survives is what a join can prove — a deadline, a date in the text,
        /// a thing kept before, a reply that arrived.
        var margin: String?
        /// True when the margin is a live signal (tint) rather than plain
        /// metadata (quiet gray).
        var marginIsSignal: Bool
    }

    /// What didn't earn a row.
    struct Fold: Equatable {
        var count: Int
        /// Distinct sources, for the stacked marks — capped for the view.
        var sources: [String]
    }

    struct Composition: Equatable {
        var notice: Notice?
        var tiles: [Tile] = []
        var threads: [Thread] = []
        var fold: Fold?
        /// `BriefLedger.absent`'s sentence — a source that always lands and
        /// didn't. Rare by construction; nil almost every day.
        var quiet: String?

        /// True when there is genuinely nothing to show. The caller falls back
        /// to the old greeting-and-chips rest state, which remains correct for
        /// a new install — this composition has nothing to say about an empty
        /// corpus and must not invent a shape to fill.
        var isEmpty: Bool {
            notice == nil && tiles.isEmpty && threads.isEmpty && fold == nil && quiet == nil
        }
    }

    // MARK: - Bounds

    /// At most three threads before everything else folds. Four fit, and four
    /// is where the screen stops reading as "here is what happened" and starts
    /// reading as an inbox — which is the feed's job, one surface down.
    static let maxThreads = 3
    /// Rows shown per thread.
    static let rowsPerThread = 3
    /// Rows shown in the loose bucket.
    static let looseRows = 2
    /// Tiles across. Three fit the width at `callout15`; a fourth truncates.
    static let maxTiles = 3
    /// A term needs this many things before it is a theme rather than a
    /// coincidence. Two is deliberately low — the window is one away-gap, and
    /// demanding three means a corpus that only lands a few things a night
    /// never sees a thread at all, which is most people most nights.
    static let threadFloor = 2

    // MARK: - Compose

    /// - Parameters:
    ///   - window: what landed in the away window, newest-first.
    ///   - kept: the kept asks, in `KeptAskStore.order`.
    ///   - streakFor: the ledger's answer for a theme, injected so this file
    ///     stays free of `BriefLedger` (and so the harness can drive it).
    static func compose(window: [Item],
                        kept: [KeptAsk] = [],
                        notice: Notice? = nil,
                        quiet: String? = nil,
                        streakFor: (String) -> Int = { _ in 0 },
                        now: Date = .now) -> Composition {
        var out = Composition()
        out.notice = notice
        out.quiet = quiet
        out.tiles = tiles(from: kept)

        let (threads, folded) = group(window, streakFor: streakFor, now: now)
        out.threads = threads
        out.fold = folded
        return out
    }

    // MARK: - Tiles

    /// A kept ask as the store holds it — its name, and the two strings its
    /// composer already produced.
    struct KeptAsk: Equatable {
        var kind: String
        var title: String
        /// `KeptAskComposers.Result.delta`.
        var delta: String
        /// `KeptAskComposers.Result.digest`.
        var digest: String
        var changed: Bool
        /// The leading thing this ask is about, when the ask has one — the
        /// soonest deadline for `overdue`/`upcoming`.
        ///
        /// It is supplied rather than parsed BECAUSE it cannot be parsed: the
        /// task composers' `delta` is `"3, 3 things late"` and carries no
        /// subject at all. Without this the tile can only ever print a tally,
        /// which is the one thing the ruling above forbids — so the subject
        /// travels separately, and a tile with one says the name.
        var subject: String?
    }

    /// Turn each kept ask into a face.
    ///
    /// The per-kind reduction is the whole job, and it exists because `delta`
    /// is NOT uniform: the money kinds hand back a real sentence
    /// (`TokensAsk.line`), while the task kinds hand back "3, 3 things late" —
    /// a tally twice over. Printing `delta` raw would have put exactly the
    /// counts the ruling forbids into the biggest type on the screen.
    ///
    /// A tile with nothing to say is DROPPED, not shown empty. An ask whose
    /// composer couldn't reach the network reports `"unreachable"` as its
    /// digest, and a tile reading "—" beside two live ones is worse than three
    /// tiles where one is missing: it looks like an answer.
    static func tiles(from kept: [KeptAsk]) -> [Tile] {
        var out: [Tile] = []
        for ask in kept {
            guard let face = face(for: ask) else { continue }
            out.append(Tile(kind: ask.kind, title: ask.title,
                            headline: face.headline, sub: face.sub, changed: ask.changed))
            if out.count == maxTiles { break }
        }
        return out
    }

    private static func face(for ask: KeptAsk) -> (headline: String, sub: String?)? {
        // Nothing was read — never a tile. `unreachable` and an empty delta are
        // both "we don't know", which §83 says to show as nothing at all.
        guard ask.digest != "unreachable" else { return nil }
        let delta = ask.delta.trimmingCharacters(in: .whitespaces)
        guard !delta.isEmpty else { return nil }

        switch ask.kind {
        case "overdue", "upcoming":
            // "3, 3 things late" → the SUBJECT, with the rest as an aside. The
            // composer's delta leads with the count and then repeats it, and
            // the count is precisely the half we don't want — so the tile names
            // the thing and lets the remainder trail.
            return taskFace(delta, subject: ask.subject)
        default:
            // The money and text kinds already speak in sentences. Split the
            // first clause up as the headline so the tile has a shape — the
            // rest reads as its qualifier.
            return splitSentence(delta)
        }
    }

    /// A task delta is `"<n>, <n> things late"` — a count, then the same count
    /// again in words. The tile shows neither when it can help it.
    ///
    /// With a subject: the NAME leads and the remainder trails as "+2 more",
    /// which is the shape the design asked for and the only one that survives
    /// the no-tallies ruling — "+2 more" is a quantity about things NOT shown,
    /// which is an aside, where "3 things late" is a scoreboard.
    ///
    /// Without one: the plain word ("Late") over the amount. That is the
    /// fallback, not the target — it fires when the composer counted deadlines
    /// this screen can't name, and a tile saying "Late · 3 things" is still a
    /// truthful answer to a question the person chose to keep.
    static func taskFace(_ delta: String, subject: String?) -> (headline: String, sub: String?)? {
        let parts = delta.split(separator: ",", maxSplits: 1).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard parts.count == 2, !parts[1].isEmpty else { return nil }
        let count = Int(parts[0]) ?? 0

        if let subject, !subject.trimmingCharacters(in: .whitespaces).isEmpty {
            let extra = count - 1
            return (clamp(subject, max: 22),
                    extra > 0 ? String(localized: "+\(extra) more") : nil)
        }
        // "3 things late" → ("Late", "3 things").
        let tail = parts[1]
        if let sp = tail.range(of: " ", options: .backwards) {
            let word = String(tail[sp.upperBound...])          // "late" / "due"
            let amount = String(tail[..<sp.lowerBound])        // "3 things"
            return (word.capitalizedFirst, amount)
        }
        return (tail.capitalizedFirst, nil)
    }

    /// "ETH is up 2.1% — the rest is flat." → ("ETH is up 2.1%", "the rest is flat").
    ///
    /// Splits on the first em dash, then the first sentence end. A line with
    /// neither becomes a headline on its own, clamped — a tile is a glance, and
    /// a paragraph in a tile is a paragraph nobody reads.
    static func splitSentence(_ line: String) -> (headline: String, sub: String?) {
        for sep in [" — ", " – ", "; "] {
            if let r = line.range(of: sep) {
                return (clamp(String(line[..<r.lowerBound]), max: 34),
                        clamp(String(line[r.upperBound...]), max: 40))
            }
        }
        // First sentence, keeping its terminator off the face.
        if let dot = line.firstIndex(where: { $0 == "." || $0 == "!" }) {
            let head = String(line[..<dot])
            let rest = String(line[line.index(after: dot)...])
                .trimmingCharacters(in: .whitespaces)
            if !rest.isEmpty { return (clamp(head, max: 34), clamp(rest, max: 40)) }
            return (clamp(head, max: 34), nil)
        }
        return (clamp(line, max: 34), nil)
    }

    // MARK: - Threads

    /// Group the window into runs that share a real subject, and fold the rest.
    ///
    /// Single assignment, like `ScreenshotTopics.cells`: a thing belongs to its
    /// STRONGEST term and appears exactly once. Without that rule a thing about
    /// two subjects renders twice, and a screen that shows you the same row in
    /// two places reads as broken long before it reads as thorough.
    static func group(_ window: [Item],
                      streakFor: (String) -> Int = { _ in 0 },
                      now: Date = .now) -> ([Thread], Fold?) {
        guard !window.isEmpty else { return ([], nil) }

        // Term → the things carrying it.
        var byTerm: [String: [Item]] = [:]
        // Term → how the person themselves spells it.
        //
        // Matching is lowercased (or "Onchain" and "onchain" are two themes),
        // but DISPLAY must not be: a tag of "ETH" title-cased back up is "Eth",
        // and "x402" is "X402" — both wrong, and wrong in the heading of a
        // section about the person's own subject. So the first original
        // spelling seen wins, and `capitalizedFirst` only ever reaches a term
        // that had no original spelling to keep (a plain title word).
        var spelling: [String: String] = [:]
        for item in window {
            for tag in item.tags {
                let t = tag.trimmingCharacters(in: .whitespaces)
                let key = t.lowercased()
                if !t.isEmpty, spelling[key] == nil { spelling[key] = t }
            }
            for term in terms(of: item) { byTerm[term, default: []].append(item) }
        }
        // Only terms that actually recur are themes.
        let themes = byTerm.filter { $0.value.count >= threadFloor }

        // Strongest term per thing — bigger group wins, ties by the term itself
        // so the grouping is DETERMINISTIC. A composition that reshuffles
        // between two opens over identical data reads as broken (the §324
        // total-order ruling, one surface over).
        var assigned: [String: String] = [:]      // item id → term
        for item in window {
            let owned = terms(of: item).filter { themes[$0] != nil }
            guard !owned.isEmpty else { continue }
            let best = owned.sorted {
                let (a, b) = (themes[$0]?.count ?? 0, themes[$1]?.count ?? 0)
                return a == b ? $0 < $1 : a > b
            }.first
            if let best { assigned[item.id] = best }
        }

        // Build each thread in window order, so a thread's rows stay
        // newest-first the way the window arrived.
        var members: [String: [Item]] = [:]
        // …and remember the terms in FIRST-APPEARANCE order.
        //
        // Not decoration: `members` is a Dictionary, and Swift seeds its hashing
        // PER PROCESS, so iterating it directly orders equal-sized threads
        // differently on different launches — the same corpus, a different
        // screen, with nothing in the code to point at. Composing twice inside
        // one process (which is what a determinism test naturally does) cannot
        // see it, because the seed is fixed for that process's lifetime. So the
        // iteration order is made explicit here and the sort below carries a
        // total tie-break on top of it.
        var order: [String] = []
        for item in window {
            guard let term = assigned[item.id] else { continue }
            if members[term] == nil { order.append(term) }
            members[term, default: []].append(item)
        }
        // A term can fall below the floor once single assignment has moved its
        // things elsewhere — those go back to loose rather than standing as a
        // thread of one.
        var threads: [Thread] = order
            .compactMap { term in members[term].map { (term, $0) } }
            .filter { $0.1.count >= threadFloor }
            .map { term, items in
                let days = streakFor(term)
                return Thread(name: spelling[term] ?? term.capitalizedFirst,
                              streak: days >= 2 ? streakLine(days) : nil,
                              rows: items.prefix(rowsPerThread).map { row($0, in: window, now: now) },
                              loose: false)
            }
        // Biggest first, then by name — total, for the reason above.
        threads.sort { $0.rows.count == $1.rows.count ? $0.name < $1.name
                                                     : $0.rows.count > $1.rows.count }
        let kept = Array(threads.prefix(maxThreads))

        // Everything a kept thread didn't take.
        let threaded = Set(kept.flatMap { $0.rows.map(\.item.id) })
        let leftovers = window.filter { !threaded.contains($0.id) }

        var out = kept
        var fold: Fold?
        if !leftovers.isEmpty {
            let shown = Array(leftovers.prefix(looseRows))
            out.append(Thread(name: String(localized: "On its own"), streak: nil,
                              rows: shown.map { row($0, in: window, now: now) }, loose: true))
            let rest = leftovers.dropFirst(looseRows)
            if !rest.isEmpty {
                // Sources in first-appearance order, deduped — the marks read
                // as "who", and a set's order would shuffle per open.
                var seen: Set<String> = []
                var sources: [String] = []
                for item in rest where !seen.contains(item.source) {
                    seen.insert(item.source)
                    sources.append(item.source)
                }
                fold = Fold(count: rest.count, sources: Array(sources.prefix(4)))
            }
        }
        return (out, fold)
    }

    private static func streakLine(_ days: Int) -> String {
        String(localized: "\(days) days running")
    }

    // MARK: - Margins

    /// The one fact worth adding to a row, in priority order.
    ///
    /// Priority is by CONSEQUENCE, not by how interesting the join was to
    /// build: a deadline changes what you do today, a date in a screenshot
    /// changes what you do this month, and a thing you kept before changes only
    /// how you read this one. Exactly one margin ever shows — a row with three
    /// facts stacked under it is a row nobody finishes.
    static func row(_ item: Item, in window: [Item], now: Date = .now) -> Row {
        if let due = item.dueAt {
            let days = calendarDays(from: now, to: due)
            if days < 0 {
                return Row(item: item, margin: String(localized: "Overdue"), marginIsSignal: true)
            }
            return Row(item: item, margin: dueLine(due, days: days), marginIsSignal: true)
        }
        if let moment = item.datedMoment {
            return Row(item: item,
                       margin: String(localized: "Carries a date: \(dateLine(moment))"),
                       marginIsSignal: true)
        }
        if let prior = item.priorKeep {
            return Row(item: item,
                       margin: String(localized: "You kept this before, in \(monthLine(prior))"),
                       marginIsSignal: true)
        }
        // A reply gathering under something of yours — the count IS the event
        // (§166's money-moving exception, which the brief already applies to
        // exactly this signal), so it is the one place a number leads.
        if let replies = item.replyCount, replies >= 3, item.socialContext == "mention" {
            return Row(item: item,
                       margin: String(localized: "Gathering replies — \(replies) so far"),
                       marginIsSignal: true)
        }
        // The same person, twice, in one window. Deterministic and useful: it
        // is how a conversation announces itself before it looks like one.
        if let who = item.author,
           window.filter({ $0.author == who }).count >= 2 {
            return Row(item: item, margin: String(localized: "\(who), again today"),
                       marginIsSignal: true)
        }
        return Row(item: item, margin: nil, marginIsSignal: false)
    }

    private static func dueLine(_ due: Date, days: Int) -> String {
        switch days {
        case 0:  return String(localized: "Due today")
        case 1:  return String(localized: "Due tomorrow")
        default: return String(localized: "Due \(dateLine(due)) — in \(days) days")
        }
    }

    // MARK: - Terms

    /// Words a thing is ABOUT. Tags first (someone chose those), then title
    /// words that survive the stoplist.
    ///
    /// The `includeDomains: false` half of §313's ruling is inherited wholesale:
    /// a hostname is not a subject. This never looks at links at all, which
    /// makes that failure unreachable rather than filtered.
    static func terms(of item: Item) -> Set<String> {
        var out = Set<String>()
        for tag in item.tags {
            let t = tag.lowercased().trimmingCharacters(in: .whitespaces)
            if t.count >= 3, !stoplist.contains(t) { out.insert(t) }
        }
        for word in item.title.lowercased().split(whereSeparator: { !$0.isLetter && $0 != "-" }) {
            let w = String(word)
            guard w.count >= 4, !stoplist.contains(w) else { continue }
            out.insert(w)
        }
        return out
    }

    /// Ordinary English, plus the words this corpus is structurally full of.
    ///
    /// The second group matters more than the first: "screenshot", "photo" and
    /// the like appear in a large share of titles for reasons that have nothing
    /// to do with subject, so without them the biggest thread every night is
    /// the word for the container rather than anything in it.
    static let stoplist: Set<String> = [
        "the", "and", "for", "with", "from", "that", "this", "your", "you", "its",
        "was", "were", "are", "have", "has", "had", "will", "would", "about",
        "into", "over", "than", "then", "they", "them", "their", "there", "here",
        "what", "when", "where", "which", "who", "why", "how", "all", "any",
        "new", "now", "out", "off", "just", "more", "most", "some", "such",
        "only", "own", "same", "too", "very", "can", "could", "should",
        "screenshot", "screenshots", "photo", "photos", "image", "images",
        "untitled", "note", "notes", "link", "links", "post", "posts",
        "video", "videos", "file", "files", "message", "messages",
    ]

    // MARK: - Shared

    static func clamp(_ s: String, max n: Int) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count > n else { return t }
        // Cut at a word boundary so a clamp never invents half a word.
        let head = t.prefix(n)
        if let sp = head.range(of: " ", options: .backwards) {
            return String(head[..<sp.lowerBound]) + "…"
        }
        return String(head) + "…"
    }

    static func calendarDays(from: Date, to: Date) -> Int {
        let cal = Calendar.current
        let a = cal.startOfDay(for: from), b = cal.startOfDay(for: to)
        return cal.dateComponents([.day], from: a, to: b).day ?? 0
    }

    static func dateLine(_ d: Date) -> String {
        d.formatted(.dateTime.month(.abbreviated).day())
    }

    static func monthLine(_ d: Date) -> String {
        d.formatted(.dateTime.month(.wide))
    }
}

/// File-scoped on purpose: `AgentLibrarian` already declares its own
/// `capitalizedFirst` the same way, and two INTERNAL extensions of the same
/// property on `String` is an ambiguity at every call site in the module.
/// Mirroring its privacy keeps both files self-contained — which this one needs
/// anyway, since the harness compiles it whole and alone.
private extension String {
    /// Uppercases the first character and leaves the rest alone — unlike
    /// `capitalized`, which lowercases everything after it and so turns "ETH"
    /// into "Eth" and "x402" into "X402" on a screen where those are names.
    var capitalizedFirst: String {
        guard let f = first else { return self }
        return String(f).uppercased() + dropFirst()
    }
}
