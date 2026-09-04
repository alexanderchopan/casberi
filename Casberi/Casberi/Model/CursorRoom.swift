import Foundation

/// THE CURSOR ROOM'S HEAD (2026-08-08, prd §340) — what your coding agents
/// actually did.
///
/// §303 landed the runs and §340 gave each one a row that draws its report.
/// Neither answers the question you have when you open the room, which is not
/// about any single run: **which repository is my machine working on, and is
/// anything coming back broken?** A room of thirty reports read newest-first
/// tells you what happened last; it does not tell you that four of the last six
/// runs on one repo never finished, which is the only fact here that changes
/// what you do next.
///
/// ## It spends nothing
///
/// Every field is already on a landed row — the title, the outcome tag, the
/// repository `CursorFetch` stamps on `authorHandle`, and `capturedAt`. No
/// request, no new `Thing` property, no CloudKit deploy, no `UserDefaults`
/// (the `StripeRoom`/`ASCRoom` contract: a head that costs a call is a head
/// that can fail, and a room's lede must not fail differently from the rows
/// beneath it). Unlike `ASCRoom`, which reads STATE and no rows at all, this
/// head is *entirely* the rows — the runs are the subject, so replaying them
/// is not a reconstruction, it is the reading.
///
/// ## Reading the outcome back, twice, in a deliberate order
///
/// A landed run says how it went in two places and NEITHER is a status field:
///
///   1. an unlocalized TAG (`CursorAgentStatus.facetTag` — "Failed",
///      "Expired", "Cancelled"), and
///   2. the title's own LEAD CLAUSE, which is localized
///      (`CursorAgentStatus.leadClause`).
///
/// The tag wins whenever it is there. The title is the fallback, and it exists
/// for exactly one population: rows landed BEFORE §340 added the tag, which
/// carry neither a tag nor an `authorHandle` and would otherwise all read as
/// unplaced successes. Parsing a localized string is the weaker read and is
/// treated as such — it matches the ENGLISH words only, so a legacy row landed
/// on a non-English device reads as a success. That is the safe direction and
/// the same one `CursorAgentStatus.failed(tags:)` chose: **never claim a
/// failure we cannot evidence.**
///
/// ## Never invent a repository
///
/// The card groups by repo, so a run whose repo cannot be named has nowhere
/// honest to go. It is EXCLUDED and COUNTED (`excluded`), never bucketed into
/// an "Unknown" repository that would then rank beside real ones and could
/// lead the card. The stored repo is trusted as data; a repo read out of a
/// title has to earn it (`looksLikeRepo`), because `IngestSupport.titleLine`
/// clamps at 80 characters and a truncated title's second component may be
/// half a repository name.
///
/// ## What it may NOT draw
///
/// No duration (v0 reports no finish time, so every "took 4 minutes" would be
/// invented), no success RATE as a percentage over a window nobody chose, and
/// no trend — a room capped at the newest 30 runs cannot say whether things are
/// getting worse, and a curve drawn over 30 arbitrary rows would say it anyway.
///
/// Foundation-only by design so `scripts/cursor-room-selftest.sh` can compile
/// it WHOLE and unmodified.
struct CursorRoom: Equatable {

    // MARK: - Outcomes

    /// How a finished run went.
    ///
    /// The raw values ARE `CursorAgentStatus.facetTag`'s words — one table, so
    /// the two cannot drift into disagreeing about what "Failed" is spelled
    /// like. That mirror is drift-guarded by the harness, because this file
    /// cannot import the enum it mirrors: `CursorBridge.swift` reaches `Thing`,
    /// `IngestSupport` and `TokenVault`, so nothing there can be compiled by a
    /// harness at all.
    enum Outcome: String, Equatable, CaseIterable {
        case succeeded = "Succeeded"
        case failed    = "Failed"
        case expired   = "Expired"
        case cancelled = "Cancelled"

        /// Whether this run produced nothing.
        ///
        /// A CANCELLED run is deliberately NOT here. Failed and expired are
        /// both "you asked for something and nothing came back"; cancelled is a
        /// decision the person made themselves, and counting it as a problem
        /// would put their own choice at the top of a card that ranks by what
        /// stops you. It still counts as a run.
        var unfinished: Bool { self == .failed || self == .expired }
    }

    /// Where a fact came from — carried so the probe can tell a room reading
    /// modern rows from one falling back to title-parsing on legacy ones. The
    /// two behave identically on screen and fail very differently.
    enum Provenance: String, Equatable {
        /// A stored field the bridge landed (a tag, or `authorHandle`).
        case stored
        /// Parsed back out of the display title — the legacy path.
        case title
        /// Neither said anything.
        case none
    }

    // MARK: - Values

    /// One landed row, reduced to the four facts this card reads. The source
    /// builds these; every judgement below is made on them, so the whole
    /// reading is harness-testable without a `Thing` in sight.
    struct Sighting: Equatable {
        let title: String
        /// The row's tags, as landed. `CursorAgentStatus.facetTag` lives here.
        let tags: [String]
        /// `Thing.authorHandle` — the repository, as data. Nil on any row
        /// landed before §340 stamped it.
        let repo: String?
        let at: Date
    }

    /// One sighting, read.
    struct Run: Equatable {
        /// Nil means the run could not be placed in a repository — it is
        /// counted as excluded and drawn nowhere.
        let repo: String?
        let outcome: Outcome
        let at: Date
        let repoFrom: Provenance
        let outcomeFrom: Provenance
    }

    /// One repository's standing, already reduced to what the card draws.
    struct Repo: Identifiable, Equatable {
        /// The repository label itself — what the card hands back, so it never
        /// has to hold a `Thing` (corollary 5).
        var id: String { name }
        let name: String
        let runs: Int
        /// Failed + expired. See `Outcome.unfinished`.
        let unfinished: Int
        let newest: Date
    }

    /// Ranked — see `ordered`. Holds EVERY repository, not just the drawn ones;
    /// the card prefixes and `note` counts the remainder, so the headline can
    /// never disagree with the note about how many there are (the `StripeRoom`
    /// bug, caught in its own review).
    let repos: [Repo]
    /// Runs that were PLACED in a repository. `excluded` is not in here.
    let totalRuns: Int
    let totalUnfinished: Int
    /// Runs whose repository could not be named. Counted, never bucketed.
    let excluded: Int
    /// The newest run in the room — over EVERY sighting including the excluded
    /// ones, because "no runs for 12 days" would be false if an unplaced run
    /// landed this morning.
    let newest: Date?

    /// Below this the card is not worth drawing: one run is a row, and the row
    /// already says everything this card would.
    static let minimumRuns = 2

    var lead: Repo? { repos.first }

    /// Nothing worth a card. A connected key whose account has run one agent —
    /// or none — gets no head; the room's rows and its empty-read note already
    /// say more than this card could.
    var isEmpty: Bool { repos.isEmpty || totalRuns < CursorRoom.minimumRuns }

    // MARK: - Reading a landed row

    /// The separator `CursorFetch.title` joins its parts with.
    static let separator = " · "

    /// A word that leads an abnormal title, or nil. `succeeded` is not a
    /// marker — nothing leads a successful run's title, which is why an
    /// unrecognised head is read as success rather than as a problem.
    static func marker(_ word: String) -> Outcome? {
        guard let outcome = Outcome(rawValue: word), outcome != .succeeded else { return nil }
        return outcome
    }

    /// The outcome, tag first and title second — see the type note for the
    /// order and its ceiling.
    static func outcome(tags: [String], title: String) -> (Outcome, Provenance) {
        for tag in tags {
            if let found = marker(tag) { return (found, .stored) }
        }
        let head = title.components(separatedBy: separator).first ?? title
        if let found = marker(head) { return (found, .title) }
        return (.succeeded, .none)
    }

    /// Whether a title component can honestly be named as a repository.
    ///
    /// The stored `authorHandle` skips this entirely — it is what the bridge
    /// read off the API, and a single-component remote ("myrepo", from a
    /// `source.repository` with no host) is a real answer. A component pulled
    /// out of a TITLE is a guess and has to earn it:
    ///
    ///   · it carries a slash, which every `CursorFetch.repoLabel` result that
    ///     survived a host strip does, and which an agent name ("fix the flaky
    ///     test") does not;
    ///   · it carries no whitespace, which a URL path cannot and an agent name
    ///     almost always does;
    ///   · it does not end in the ellipsis `IngestSupport.titleLine` appends,
    ///     because half a repository name is a repository that does not exist.
    static func looksLikeRepo(_ candidate: String) -> Bool {
        guard candidate.count > 1, candidate.contains("/") else { return false }
        guard !candidate.contains("…"), !candidate.contains(" ") else { return false }
        guard !candidate.hasPrefix("/"), !candidate.hasSuffix("/") else { return false }
        return true
    }

    /// The repository out of a display title, or nil. Skips a leading outcome
    /// clause if there is one — the repo is the component after it.
    static func repoInTitle(_ title: String) -> String? {
        var parts = title.components(separatedBy: separator)
        if let head = parts.first, marker(head) != nil { parts.removeFirst() }
        guard let candidate = parts.first, looksLikeRepo(candidate) else { return nil }
        return candidate
    }

    /// One sighting, read into a run. Stored fields win; the title is the
    /// fallback for rows that predate them.
    static func read(_ sighting: Sighting) -> Run {
        let (outcome, outcomeFrom) = outcome(tags: sighting.tags, title: sighting.title)
        let stored = sighting.repo?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let stored, !stored.isEmpty {
            return Run(repo: stored, outcome: outcome, at: sighting.at,
                       repoFrom: .stored, outcomeFrom: outcomeFrom)
        }
        if let parsed = repoInTitle(sighting.title) {
            return Run(repo: parsed, outcome: outcome, at: sighting.at,
                       repoFrom: .title, outcomeFrom: outcomeFrom)
        }
        return Run(repo: nil, outcome: outcome, at: sighting.at,
                   repoFrom: .none, outcomeFrom: outcomeFrom)
    }

    // MARK: - Composing

    /// The whole card, off landed rows and nothing else.
    static func compose(runs sightings: [Sighting]) -> CursorRoom {
        var runs = 0, unfinished = 0, excluded = 0
        var newest: Date?
        // Value tuples in a dictionary, keyed by the repository's own name —
        // grouping cannot invent a bucket, so a run with no repo has nowhere
        // to land by construction rather than by remembering to exclude it.
        var buckets: [String: (runs: Int, unfinished: Int, newest: Date)] = [:]

        for sighting in sightings {
            let run = read(sighting)
            // Over EVERY sighting, placed or not — see `newest`.
            if newest == nil || run.at > newest! { newest = run.at }
            guard let repo = run.repo else { excluded += 1; continue }
            runs += 1
            if run.outcome.unfinished { unfinished += 1 }
            var bucket = buckets[repo] ?? (runs: 0, unfinished: 0, newest: run.at)
            bucket.runs += 1
            if run.outcome.unfinished { bucket.unfinished += 1 }
            if run.at > bucket.newest { bucket.newest = run.at }
            buckets[repo] = bucket
        }

        let repos = buckets.map { name, bucket in
            Repo(name: name, runs: bucket.runs, unfinished: bucket.unfinished,
                 newest: bucket.newest)
        }
        return CursorRoom(repos: ordered(repos), totalRuns: runs,
                          totalUnfinished: unfinished, excluded: excluded,
                          newest: newest)
    }

    // MARK: - Ranking

    /// Which repository leads the card.
    ///
    ///   2 — something came back broken and only you can fix it.
    ///   1 — everything else.
    ///
    /// Deliberately two rungs and not a count: one failure outranks ten
    /// successes, so a repo with a single failed run leads a repo with twenty
    /// clean ones. Ranking by failure COUNT instead would let a busy repo's
    /// two failures out of forty bury a quiet repo whose only run broke, and
    /// the second is the one you did not already know about.
    static func rank(_ repo: Repo) -> Int { repo.unfinished > 0 ? 2 : 1 }

    /// Rank, then run count, then name — total, so two composes over the same
    /// data can never disagree. A card that reshuffles between opens over
    /// identical rows reads as broken, and the dictionary this is built from
    /// has no order of its own to fall back on.
    static func ordered(_ repos: [Repo]) -> [Repo] {
        repos.sorted { a, b in
            let ra = rank(a), rb = rank(b)
            if ra != rb { return ra > rb }
            if a.runs != b.runs { return a.runs > b.runs }
            return a.name < b.name
        }
    }

    /// How many repositories have something broken in them.
    static func failingRepos(_ room: CursorRoom) -> Int {
        room.repos.filter { $0.unfinished > 0 }.count
    }

    // MARK: - The bar

    /// A repository's run count as a share of the busiest one, 0…1 — the only
    /// drawing on this card, and it encodes ONE thing: how much of your agent
    /// time went here. Clamped, and zero when there is nothing to compare
    /// against (a zero denominator draws as nothing, which SwiftUI renders as
    /// a NaN-width capsule — the `AgentPanel` lesson).
    static func share(runs: Int, of top: Int) -> Double {
        guard top > 0 else { return 0 }
        return min(max(Double(runs) / Double(top), 0), 1)
    }

    // MARK: - Days

    /// Whole CALENDAR days, not `timeIntervalSince / 86400` — "no runs for 3
    /// days" means days, so an 11pm read the night after a run is one day on,
    /// not zero-point-oh-four. Negative is in the past.
    static func days(from now: Date, to later: Date, calendar: Calendar = .current) -> Int {
        let a = calendar.startOfDay(for: now)
        let b = calendar.startOfDay(for: later)
        return calendar.dateComponents([.day], from: a, to: b).day ?? 0
    }

    // MARK: - Words

    static func runsLabel(_ count: Int) -> String {
        count == 1 ? String(localized: "1 run") : String(localized: "\(count) runs")
    }

    /// The line beside a repository: what ran there, and what came back
    /// broken. "Didn't finish" rather than "failed" because the count holds
    /// two different outcomes — a crashed run and an expired one — and one
    /// word must not claim to be the other.
    static func repoLine(_ repo: Repo) -> String {
        var line = runsLabel(repo.runs)
        if repo.unfinished > 0 {
            line += separator + String(localized: "\(repo.unfinished) didn't finish")
        }
        return line
    }

    /// The one line at the top of the card.
    ///
    /// Trouble leads, always: what came back broken is the only thing here that
    /// changes what you do next. Failing that it states the volume, which is
    /// the everyday reading and the reason to open the room.
    /// WHAT THE HEAD IS ABOUT — decided ONCE, read twice (prd §585).
    ///
    /// Breakage outranks volume; that inversion is what this card exists to
    /// avoid. `headline` and `lede` must open on the same branch or the figure
    /// and the sentence describe different runs, and writing the ladder twice
    /// is how that happens — caught the hour it was written, when the
    /// harness's own mutation edited the first copy and the assertion, which
    /// reads `headline`, still passed.
    ///
    /// The branch conditions are deliberately not quoted in this comment: the
    /// mutations are `sed`, and prose above the code they edit is prose they
    /// edit instead.
    enum Lead: Equatable {
        /// Runs that did not finish, and how many repos they span.
        case unfinished(count: Int, repos: Int)
        /// Nothing broke; this is how much ran.
        case volume(count: Int, repos: Int)
        case quiet
    }

    static func lead(of room: CursorRoom) -> Lead {
        guard room.lead != nil else { return .quiet }
        if room.totalUnfinished > 0 {
            return .unfinished(count: room.totalUnfinished, repos: failingRepos(room))
        }
        guard room.totalRuns > 0 else { return .quiet }
        return .volume(count: room.totalRuns, repos: room.repos.count)
    }

    /// THE LEDE (prd §585) — the runs that did not finish, or the runs there
    /// were. Nil on a room with no lead: "Nothing to report" is a statement,
    /// and §584 measured that a statement belongs at `heading22`.
    static func lede(_ room: CursorRoom) -> RoomLede? {
        guard let name = room.lead?.name else { return nil }
        switch lead(of: room) {
        case .unfinished(let count, let repos):
            let caption = repos > 1
                ? String(localized: "runs didn't finish, across \(repos) repos")
                : String(localized: "runs didn't finish, in \(name)")
            return RoomLede(figure: count.formatted(), caption: caption,
                            numeric: Double(count))
        case .volume(let count, let repos):
            let caption = repos > 1
                ? String(localized: "agent runs, across \(repos) repos")
                : String(localized: "agent runs, in \(name)")
            return RoomLede(figure: count.formatted(), caption: caption,
                            numeric: Double(count))
        case .quiet:
            return nil
        }
    }

    static func headline(_ room: CursorRoom) -> String {
        guard let lead = room.lead else { return String(localized: "Nothing to report") }
        switch Self.lead(of: room) {
        case .unfinished(let count, let repos):
            if repos > 1 {
                return String(localized: "\(count) runs didn't finish across \(repos) repos")
            }
            return count == 1
                ? String(localized: "1 run didn't finish in \(lead.name)")
                : String(localized: "\(count) runs didn't finish in \(lead.name)")
        case .volume(let count, let repos):
            if repos > 1 {
                return String(localized: "\(count) agent runs across \(repos) repos")
            }
            return count == 1
                ? String(localized: "1 agent run in \(lead.name)")
                : String(localized: "\(count) agent runs in \(lead.name)")
        case .quiet:
            return String(localized: "Nothing to report")
        }
    }

    /// The quiet line under the card: repositories not drawn, runs that could
    /// not be placed, and how long it has been since anything ran. Any of
    /// them, all of them, or nothing.
    ///
    /// The excluded clause is not optional politeness — a run this card cannot
    /// place is a run missing from every number above it, and a total that
    /// silently omits rows is the failure `-xArchiveImport`'s own drop counters
    /// exist to prevent, one room over.
    static func note(_ room: CursorRoom, drawn: Int, now: Date = .now) -> String? {
        var parts: [String] = []
        let hidden = room.repos.count - drawn
        if hidden > 0 {
            parts.append(hidden == 1 ? String(localized: "1 more repo")
                                     : String(localized: "\(hidden) more repos"))
        }
        if room.excluded > 0 {
            parts.append(room.excluded == 1
                         ? String(localized: "1 run has no repo")
                         : String(localized: "\(room.excluded) runs have no repo"))
        }
        if let idle = idleNote(newest: room.newest, now: now) { parts.append(idle) }
        return parts.isEmpty ? nil : parts.joined(separator: separator)
    }

    /// "no runs for 9 days" — said only once the silence is long enough to
    /// mean something. Under the threshold it says nothing, because a room
    /// that ran yesterday needs no explanation, and a card that narrates every
    /// ordinary gap is a card people stop reading.
    ///
    /// It is deliberately NOT a staleness apology (`ASCRoom.staleNote`'s job):
    /// this bridge reads on every foreground sweep and the rows are history,
    /// so an old newest run means nobody launched an agent — a fact about the
    /// person, not about the connection.
    static func idleNote(newest: Date?, now: Date = .now, quietAfter: Int = 7) -> String? {
        guard let newest else { return nil }
        let days = days(from: newest, to: now)
        guard days >= quietAfter else { return nil }
        return String(localized: "no runs for \(days) days")
    }
}
