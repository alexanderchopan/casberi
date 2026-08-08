import Foundation

/// The Cursor bridge (2026-08-04, prd §303) — what your coding agents actually
/// did, landing beside everything else you keep.
///
/// Cursor's Cloud (Background) Agents run on a repository without you watching:
/// you launch one from the dashboard or the IDE, it works, and some minutes
/// later there is a branch and usually a pull request. This reads the list of
/// those runs and lands the ones that are OVER — what the agent was asked to
/// do, what it says it did, and the PR it opened.
///
/// **This is the corpus's own missing third chair.** Casberi already holds
/// ChatGPT and Claude conversation imports; an agent run is the same kind of
/// artefact — a thing you asked a model for, and its output — except this one
/// has a real API behind it, so it arrives on its own instead of via a file
/// pick.
///
/// ## Why v0 and not v1
///
/// Cursor publishes two generations of this API. `v1` is current and is where
/// artifacts, streaming and usage live; `v0` is labelled legacy by the same
/// docs and still documented as available. **This reads v0 on purpose**, and
/// the reason is the shape of what this bridge needs rather than nostalgia:
///
///   • v0 answers the entire question in ONE GET. A list row already carries
///     `status`, `summary`, `source.repository` and `target.prUrl` — every
///     field below. v1 deliberately does not: its list returns "durable
///     identity fields" only, and its own docs say to call `GET /v1/agents/
///     {id}` for the full record, then `…/runs/{runId}` for the execution
///     status, because v1 splits a durable agent from its per-prompt runs.
///     That is three round trips per agent to learn what v0 states once, on a
///     foreground sweep that already has ~27 other bridges to get through.
///   • v1 is self-described public beta — "APIs may change before general
///     availability". v0's response shape is pinned by a verbatim documented
///     example and corroborated by two independently-shipping clients.
///
/// So the trade is deliberate: an API the vendor calls legacy, in exchange for
/// one request and a shape that two other people's code agrees on. **The
/// migration is known, not discovered** — when v0 goes, `things` moves to the
/// three-call v1 walk and the field map below is the diff. Note v1 also renames
/// `autoCreatePr` → `autoCreatePR` and moves `prUrl` to
/// `run.git.branches[].prUrl`; neither is read here, but both are the kind of
/// silent rename that empties a room (the Kalshi `event_ticker` lesson).
///
/// ## Read-only is by CONDUCT, and it is the weakest such promise here
///
/// A Cursor API key **cannot be scoped read-only**. There is no permission, no
/// scope, no read/write toggle — a key that can `GET /v0/agents` can equally
/// `POST /v0/agents` to launch one (which costs the person real money and
/// writes a branch to their repository) and `DELETE` one. That puts this in
/// Privacy.com's tier rather than PostHog's/Stripe's/Trello's, and one rung
/// below Privacy.com at that: Privacy's key can move money, this one can spend
/// money AND write code.
///
/// So the promise is kept the only way it can be — by conduct. This file issues
/// exactly one HTTP verb, `GET`, against exactly one path. There is no code
/// here that launches, follows up, stops, archives or deletes an agent, and the
/// catalog copy plus `TokenBridge.canLine` say so in those words. If a future
/// pass adds a write to this file, that copy becomes a lie: change the copy in
/// the same commit or don't add the write.
///
/// ## What lands, and what deliberately doesn't
///
/// Only a run that is OVER. `CREATING` and `RUNNING` are STATES (§216) — an
/// in-flight agent is on screen in Cursor right now, it carries no `summary`
/// yet and no PR, and it would land as a row that says nothing and is stale
/// within minutes. A finished run is an EVENT, which is what a thing is.
///
/// A consequence worth stating because it is a feature: since only terminal
/// runs land, **nothing here ever needs reconciling**. Linear, Trello and
/// Cloudflare all carry a `reconcile…` pass because they land rows whose state
/// keeps moving; a finished agent run is finished forever.
///
/// **UNMEASURED (2026-08-04).** Authored on Linux with no Xcode, no key stored,
/// and no egress to `api.cursor.com` from this host — the field map comes from
/// Cursor's own documented example plus the Raycast and Sim clients, not from a
/// live call. Every read is a GET that returns nil on any failure, so it fails
/// safe: a drifted field empties the room rather than landing a wrong one. Run
/// `-cursorProbe YES` against a real key before trusting any of it.
enum CursorAgentStatus: String {
    case creating  = "CREATING"
    case running   = "RUNNING"
    case finished  = "FINISHED"
    case error     = "ERROR"
    case expired   = "EXPIRED"
    /// Not in v0's documented five — it is v1's. Carried anyway because it
    /// costs one line and the alternative is the silent kind of wrong: if v0
    /// ever gains it, a cancelled run would match no case, be judged
    /// non-terminal, and never land, with nothing anywhere saying so.
    case cancelled = "CANCELLED"

    /// Whether the run is OVER. Only terminal runs become things — see the
    /// type's own note.
    var terminal: Bool {
        switch self {
        case .creating, .running:                       false
        case .finished, .error, .expired, .cancelled:   true
        }
    }

    /// The clause that LEADS an abnormal run's title, and nil for the happy
    /// one. Leading rather than trailing is deliberate: `IngestSupport.
    /// titleLine` clamps at 80 characters, so an outcome parked at the end of
    /// "org/repo · a long agent name…" is exactly the word the clamp eats — and
    /// a failed run reading as a successful one is the fake-status the honesty
    /// rule forbids. In front, it cannot be cut.
    var leadClause: String? {
        switch self {
        case .finished:              nil
        case .error:                 String(localized: "Failed")
        case .expired:               String(localized: "Expired")
        case .cancelled:             String(localized: "Cancelled")
        case .creating, .running:    nil   // never landed
        }
    }

    /// The outcome as a STABLE marker, and nil for a plain success.
    ///
    /// This exists because `leadClause` is localized and the title is the only
    /// place the outcome was ever recorded (2026-08-08, prd §340). A room that
    /// wants to rank failures first, or a facet that wants to filter to them,
    /// would have to parse the title back — and that comparison is against
    /// whatever language the device was in WHEN THE ROW LANDED. Change the
    /// language and every past failure silently reads as a success, which is
    /// the §83 fake status in the one place it is most expensive.
    ///
    /// So the outcome is landed as a tag as well, in English, never localized:
    /// a tag is stable, survives a language change, and doubles as the §308
    /// facet that makes "cursor failed runs" answerable. Deliberately three
    /// distinct words rather than one "Failed" bucket — an expired run and a
    /// crashed one are different facts, and a person filtering for one does
    /// not mean the other.
    var facetTag: String? {
        switch self {
        case .finished:              nil
        case .error:                 "Failed"
        case .expired:               "Expired"
        case .cancelled:             "Cancelled"
        case .creating, .running:    nil   // never landed
        }
    }

    /// Every tag this type can produce — so a reader can recognise an outcome
    /// tag without hard-coding the list a second time and letting the two
    /// drift (the `ToolScore.rank` lesson).
    static var facetTags: [String] {
        [Self.error, .expired, .cancelled].compactMap(\.facetTag)
    }

    /// Whether a landed row's tags say the run did NOT simply succeed.
    /// Absence of an outcome tag means success — which is also the right
    /// answer for a row landed before this tag existed and never re-read,
    /// since those were overwhelmingly successes and the alternative is
    /// claiming a failure we cannot evidence.
    static func failed(tags: [String]) -> Bool {
        tags.contains { facetTags.contains($0) }
    }
}

enum CursorFetch {

    /// Cursor's own base. v0 — see the file note.
    private static let base = "https://api.cursor.com/v0"

    /// How many runs to ask for. v0 documents `limit` as 1…100 (default 20).
    /// Asked wider than the 30 that land because the terminal filter below
    /// discards the in-flight ones, and a person with several agents running
    /// would otherwise get a short page of history.
    private static let pageSize = 50

    /// How many land, matching the newest-30 window every other bridge in
    /// `TokenIngest` takes.
    private static let landCap = 30

    /// Bearer, not Basic. Cursor's overview documents both for this API and
    /// says they "behave identically" — Bearer is what every other keyed
    /// bridge in this app already sends, so it is one less shape to remember.
    private static func auth(_ token: String) -> String { "Bearer \(token)" }

    // MARK: - Read

    /// The agent runs that are over, newest 30. One GET.
    ///
    /// Nil means the read failed (no key, refused key, offline) — `TokenIngest`
    /// words that to the person as "check the token", which is right. An EMPTY
    /// array is a real and very common answer: plenty of Cursor users have
    /// never launched a CLOUD agent at all, which is why this bridge carries a
    /// `TokenBridge.emptyReadNote`.
    static func things(token: String) async -> [Thing]? {
        guard let root = await IngestSupport.getJSON(
            "\(base)/agents?limit=\(pageSize)", auth: auth(token)) as? [String: Any],
              let rows = root["agents"] as? [[String: Any]] else { return nil }
        return Array(rows.compactMap { thing(from: $0) }.prefix(landCap))
    }

    /// One agent row → a thing, or nil when it isn't over yet (or can't be
    /// identified). Split out from `things` so the probe can shape a row
    /// without a network call being the only way to see the result.
    static func thing(from row: [String: Any]) -> Thing? {
        guard let id = (row["id"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty,
              // Not `let status = status(of:)` — binding a local over the
              // function's own name inside its initializer is the shape Swift
              // rejects as "used within its own initial value".
              let runStatus = status(of: row), runStatus.terminal
        else { return nil }

        let target = row["target"] as? [String: Any] ?? [:]
        let source = row["source"] as? [String: Any] ?? [:]

        // The PR is the payoff, so it is the permalink when there is one; the
        // agent's own Cursor page is the fallback and always exists. A run that
        // failed usually has no PR, which is precisely when the fallback earns
        // its keep — the page is where you go to read what went wrong.
        let link = trimmed(target["prUrl"]) ?? trimmed(target["url"]) ?? ""

        // The outcome and the PR ride as tags beside the run marker — stable,
        // unlocalized, and filterable (see `facetTag`). "PR" is landed only
        // when there really is a pull request, so the facet can never promise
        // a link that isn't there.
        var tags = ["Agent run"]
        if let outcome = runStatus.facetTag { tags.append(outcome) }
        if trimmed(target["prUrl"]) != nil { tags.append("PR") }

        let thing = Thing(
            kind: .link,
            title: IngestSupport.titleLine(title(row: row, source: source, status: runStatus)),
            content: link,
            source: "Cursor",
            // The run's REAL start, not `.now` — a first sync lands a month of
            // history sorted back to where it happened, and can't fake a day's
            // worth of urgency (the Hugging Face rule).
            capturedAt: IngestSupport.isoDate(row["createdAt"]) ?? .now,
            tags: tags,
            sourceRef: "cursor:agent:\(id)"
        )
        // The repo, kept as data rather than only inside the title. Without it
        // a room grouping by repository has to re-parse a clamped display
        // string, and `titleLine`'s 80-character cut can take the repo with it
        // on a long agent name.
        if let repo = repoLabel(source) { thing.authorHandle = repo }
        // What the agent says it did. Display copy, the way a Trello card's
        // back and a Readwise highlight's full text are — this is the whole
        // reason to keep a finished run, so it must not ride the
        // retrieval-only `enrichedText`. Absent (not null) on runs that never
        // got far enough to write one.
        if let summary = trimmed(row["summary"]) { thing.summary = summary }
        return thing
    }

    // MARK: - Shaping

    /// `"org/repo · Add README documentation"`, with an outcome in front when
    /// the run didn't simply succeed.
    ///
    /// The repository LEADS for the reason a Trello card's board does: an agent
    /// name on its own is a fragment written against a context you had at the
    /// time ("fix the flaky test"), and in a feed beside everything else it
    /// means nothing without the repo it ran on.
    private static func title(row: [String: Any], source: [String: Any],
                              status: CursorAgentStatus) -> String {
        // Cursor can hand back an empty name (its own clients default it), so
        // this never trusts the field to be present or non-blank.
        let name = trimmed(row["name"]) ?? String(localized: "Background agent")
        let parts = [status.leadClause, repoLabel(source), name].compactMap { $0 }
        return parts.joined(separator: " · ")
    }

    /// `"your-org/your-repo"` out of `"https://github.com/your-org/your-repo"`.
    ///
    /// Host-agnostic on purpose — it drops a scheme and the first path
    /// component whatever they are, so a self-hosted or non-GitHub remote
    /// reads the same way rather than falling back to a bare URL. Nil when
    /// there is nothing usable, so the title is just the agent's name rather
    /// than a lone separator.
    static func repoLabel(_ source: [String: Any]) -> String? {
        guard var s = trimmed(source["repository"]) else { return nil }
        for prefix in ["https://", "http://", "git://", "ssh://"] where s.hasPrefix(prefix) {
            s = String(s.dropFirst(prefix.count))
        }
        if s.hasSuffix(".git") { s = String(s.dropLast(4)) }
        var parts = s.split(separator: "/").map(String.init)
        // Drop the HOST when there is one, keyed on the dot rather than on
        // position — v0 sends a full URL ("https://github.com/org/repo") while
        // v1 sends the same value with the scheme already stripped
        // ("github.com/org/repo"), so both land on `github.com` here and a
        // value that is already bare ("org/repo") keeps both components.
        //
        // Everything after the host is kept rather than the last two, because
        // a GitLab-style nested group really is "group/sub/project" and
        // trimming it to "sub/project" would name a repo that doesn't exist.
        if let first = parts.first, first.contains("."), parts.count > 1 {
            parts.removeFirst()
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: "/")
    }

    /// The run's status, or nil when the field is missing or a value this
    /// build has never heard of. Nil is treated as non-terminal by `thing`,
    /// which is the safe direction — an unrecognised status lands nothing
    /// rather than landing a row titled with a guess. `diagnose` names it, so
    /// a new status value shows up as a probe line instead of as silence.
    static func status(of row: [String: Any]) -> CursorAgentStatus? {
        guard let raw = trimmed(row["status"]) else { return nil }
        return CursorAgentStatus(rawValue: raw.uppercased())
    }

    private static func trimmed(_ raw: Any?) -> String? {
        guard let s = (raw as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }

    // MARK: - Reading a landed row back

    /// The title with any leading outcome clause removed, for a row that draws
    /// the outcome itself. One place, so the row and the room head cannot
    /// drift into disagreeing about what a title says.
    ///
    /// It strips against the CURRENT localization and against the English
    /// words too, because a row landed before a language change wears the old
    /// one. Failing to strip is the safe direction — the outcome then appears
    /// twice, which is redundant but true; stripping too eagerly would eat a
    /// real repository or agent name.
    static func displayTitle(_ title: String) -> String {
        let separator = " · "
        guard let range = title.range(of: separator) else { return title }
        let head = String(title[title.startIndex..<range.lowerBound])
        let known = Set(CursorAgentStatus.facetTags
            + [CursorAgentStatus.error, .expired, .cancelled].compactMap(\.leadClause))
        guard known.contains(head) else { return title }
        return String(title[range.upperBound...])
    }

    // MARK: - Probe

    /// `-cursorProbe YES` — the read, phase by phase, with the STORED key.
    ///
    /// The `-kalshiBookProbe`/`-trelloProbe` lesson: an empty Cursor room has
    /// FIVE causes and they all render as the same one sentence —
    ///
    ///   1. no key stored at all,
    ///   2. a key Cursor refuses (401) — including the live question of whether
    ///      an individual on a personal plan can mint one of these at all,
    ///      which Cursor's own docs and forum contradict each other about,
    ///   3. a key that works against an account that has genuinely never
    ///      launched a cloud agent (the common, healthy case),
    ///   4. every agent still in flight, so nothing is terminal yet,
    ///   5. shape drift — `agents` renamed, or a status value this build
    ///      doesn't know, which silently lands nothing.
    ///
    /// Only 5 is a bug, and it is invisible from the feed. One NSLog per line
    /// (the `-todayProbe` truncation lesson), and one `cursorAgent|` line per
    /// row naming the five fields every shaping decision above rests on.
    @MainActor
    static func diagnose() async {
        guard let token = TokenVault.get(TokenBridge.cursor.tokenKey) else {
            NSLog("[Casberi] cursor| no key stored — connect first (-tokenBridge \"Cursor:<key>\")")
            return
        }
        // NOT named `status` — that would shadow `status(of:)` below and make
        // every call to it a compile error against an Int.
        let (json, httpStatus) = await IngestSupport.getJSONStatus(
            "\(base)/agents?limit=\(pageSize)", auth: auth(token))
        NSLog("[Casberi] cursor| GET /v0/agents HTTP %d", httpStatus)
        guard httpStatus != 401 else {
            NSLog("[Casberi] cursor| 401 — the key was refused. Mint one at cursor.com/dashboard (API Keys).")
            return
        }
        guard let root = json as? [String: Any] else {
            NSLog("[Casberi] cursor| no JSON object — unreachable, or the envelope changed")
            return
        }
        guard let rows = root["agents"] as? [[String: Any]] else {
            NSLog("[Casberi] cursor| no `agents` array — SHAPE DRIFT. keys=%@",
                  root.keys.sorted().joined(separator: ","))
            return
        }
        NSLog("[Casberi] cursor| %d agents on the first page (asked %d)", rows.count, pageSize)

        var terminal = 0, unknown: [String] = []
        for row in rows {
            let raw = trimmed(row["status"]) ?? "—"
            let parsed = status(of: row)
            if parsed == nil { unknown.append(raw) }
            if parsed?.terminal == true { terminal += 1 }
            let target = row["target"] as? [String: Any] ?? [:]
            let src = row["source"] as? [String: Any] ?? [:]
            // The five fields the shaping rests on, plus whether this row would
            // actually land — a count of agents can't tell "all still running"
            // from "the status values moved".
            NSLog("[Casberi] cursorAgent| status=%@ lands=%@ repo=%@ pr=%@ summary=%@ name=%@",
                  raw,
                  parsed?.terminal == true ? "YES" : "no",
                  repoLabel(src) ?? "—",
                  trimmed(target["prUrl"]) != nil ? "yes" : "no",
                  trimmed(row["summary"]) != nil ? "yes" : "no",
                  trimmed(row["name"]) ?? "(empty)")
        }
        if !unknown.isEmpty {
            NSLog("[Casberi] cursor| UNKNOWN status values, these land NOTHING: %@",
                  Set(unknown).sorted().joined(separator: ","))
        }
        NSLog("[Casberi] cursor| %d of %d are over and would land (cap %d)",
              terminal, rows.count, landCap)
        if rows.isEmpty {
            NSLog("[Casberi] cursor| the key works and this account has run no cloud agents — not a bug")
        }
    }
}
