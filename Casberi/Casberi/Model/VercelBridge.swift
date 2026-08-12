import Foundation

/// The Vercel bridge (2026-08-04) — what shipped, and what broke trying.
///
/// ## The design problem is the opposite of Sentry's
///
/// Sentry had to be stopped from landing counts. Vercel's every object is
/// already an event — a deployment happened at a moment and then it was over —
/// so the doctrine needs no carve-out here. The problem is VOLUME: a person
/// working normally pushes a dozen preview deployments a day, every one of
/// which succeeds, and landing them all turns the feed into a git log.
///
/// So exactly two shapes land, and the third is deliberately dropped:
///
///   • **A production deployment that went live.** This is the moment your
///     users got the new thing. It is rare enough to be news and important
///     enough to want a record of.
///   • **A deployment that FAILED or was CANCELED, on any target.** A broken
///     preview build is the whole reason to look at a deploy list at all, so
///     this one is not filtered by target.
///   • **A preview deployment that succeeded is NOT landed.** That is the git
///     log, and it is the firehose this bridge exists to not be.
///
/// A consequence worth stating because it is a feature: a deployment that has
/// finished is finished forever, so nothing here ever needs reconciling —
/// Cursor's property, for Cursor's reason. In-flight states (`BUILDING`,
/// `QUEUED`, `INITIALIZING`) are STATES (§216): they are on screen in Vercel
/// right now, they carry no outcome, and they'd be stale in ninety seconds.
///
/// ## Read-only is by CONDUCT, and the copy has to keep saying so
///
/// A Vercel token cannot be scoped read-only. There is no permission model on
/// a personal access token: a token that can list deployments can equally
/// create one, promote it to production, roll back, cancel a build, or delete
/// a project. That puts this in Cursor's and Privacy.com's tier, not PostHog's
/// or Sentry's.
///
/// So the promise is kept the only way it can be. This file issues exactly one
/// HTTP verb, `GET`, against exactly one path. There is no code here that
/// deploys, promotes, cancels, rolls back or deletes, and — worth its own
/// sentence because it is the thing a person would actually fear — nothing
/// here reads environment variables, which is where a Vercel project keeps its
/// secrets. **Tripwire: add a write to `VercelFetch` and `TokenBridge.canLine`
/// becomes a lie. Change it in the same commit, or don't add the write.**
/// Mechanical since 2026-08-04 — `scripts/vercel-selftest.sh` fails the build
/// on any write verb appearing in this file.
///
/// **MEASURED (2026-08-04)**: `api.vercel.com/v6/deployments` is reachable and
/// answers `403 {"error":{"code":"forbidden","missingToken":true}}` without a
/// token, confirming host, path and that auth is a bearer token.
/// **UNMEASURED**: every response shape below — no token is stored on this host.
/// The field map comes from Vercel's published REST reference. Every read is a
/// GET returning nil on failure, so it fails safe. Run `-vercelProbe YES`
/// against a real token before trusting it.
enum VercelState: String {
    case ready        = "READY"
    case error        = "ERROR"
    case canceled     = "CANCELED"
    case building     = "BUILDING"
    case queued       = "QUEUED"
    case initializing = "INITIALIZING"

    /// Whether the deployment is OVER.
    var terminal: Bool {
        switch self {
        case .ready, .error, .canceled:            true
        case .building, .queued, .initializing:    false
        }
    }

    /// The clause that LEADS an abnormal deployment's title, nil for a good
    /// one. Leading rather than trailing for `CursorAgentStatus.leadClause`'s
    /// reason: `titleLine` clamps at 80 characters and a commit message is
    /// exactly the kind of long tail that eats a trailing word — a failed
    /// deploy reading as a successful one is the §83 fake status.
    var leadClause: String? {
        switch self {
        case .error:    String(localized: "Build failed")
        case .canceled: String(localized: "Canceled")
        default:        nil
        }
    }
}

enum VercelShape {

    /// Whether this deployment is one of the two shapes that land.
    ///
    /// Pure, and harness-tested, because it is the whole editorial judgement
    /// of the bridge in one function: get it wrong in one direction and the
    /// feed becomes a git log, wrong in the other and a broken production
    /// deploy passes in silence.
    /// The `terminal` half of this guard is REDUNDANT today and deliberately
    /// kept — `scripts/vercel-selftest.sh` records it as an equivalent mutant,
    /// so nobody has to rediscover why removing it changes nothing. The switch
    /// below returns false for every in-flight state through its `default`, so
    /// the guard only earns its keep the day someone adds a case here and
    /// forgets that a deployment has to be OVER before it can be news.
    static func lands(state: VercelState?, target: String?) -> Bool {
        guard let state, state.terminal else { return false }
        switch state {
        case .error, .canceled:
            // Any target. A preview build that broke is the reason to look.
            return true
        case .ready:
            // Production only. A successful preview is the firehose.
            return isProduction(target)
        default:
            return false
        }
    }

    /// Vercel writes the production target as the literal string
    /// `"production"`; a preview carries `null` and a custom environment
    /// carries its own name. Matched case-insensitively and never by
    /// `contains`, so an environment somebody names "pre-production" cannot
    /// masquerade as the real one.
    static func isProduction(_ target: String?) -> Bool {
        guard let target = target?.trimmingCharacters(in: .whitespacesAndNewlines)
        else { return false }
        return target.caseInsensitiveCompare("production") == .orderedSame
    }

    /// `"my-app · Fix the header on mobile"`, with the outcome in front when
    /// it wasn't a clean ship.
    ///
    /// The PROJECT leads for Cursor's repository reason: a commit message is
    /// written against a context you had at the time, and in a feed beside
    /// everything else it needs to say what it changed.
    ///
    /// Falls back to the deployment's own hostname when there is no commit
    /// message — a deploy from the CLI or a redeploy has no git metadata at
    /// all, and a row reading just "my-app" says nothing.
    static func title(project: String?, commitMessage: String?, host: String?,
                      state: VercelState?) -> String {
        // A commit message is a full message, newlines and all — take its
        // subject line, the way git itself does, before `titleLine` flattens
        // the rest into one run-on string.
        let subject = commitMessage?
            .split(separator: "\n").first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = (subject?.isEmpty == false ? subject : nil) ?? host
        let parts = [state?.leadClause, project, detail]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        return parts.joined(separator: " · ")
    }
}

enum VercelFetch {

    /// v6 is the current documented version of the LIST endpoint specifically
    /// — Vercel versions each path independently, and the deployments list has
    /// been v6 across the whole life of the v2 platform, while sibling paths
    /// sit at v9/v13. Pinned rather than left implicit because an unversioned
    /// path is not a thing this API offers.
    private static let base = "https://api.vercel.com/v6/deployments"

    /// How many to ask for. Asked wider than what lands because the filter
    /// above discards successful previews, which for most accounts is most of
    /// the list.
    static let pageSize = 40

    /// How many land, matching the newest-30 window `TokenIngest` takes.
    private static let landCap = 30

    private static func auth(_ token: String) -> String { "Bearer \(token)" }

    /// The deployments that are over and worth a row, newest 30. One GET.
    ///
    /// Nil means the read failed. An EMPTY array is a real answer with a cause
    /// worth naming, which is why this bridge carries a
    /// `TokenBridge.emptyReadNote`: a token scoped to a personal account
    /// cannot see a team's projects.
    static func things(token: String) async -> [Thing]? {
        guard let root = await IngestSupport.getJSON(
            "\(base)?limit=\(pageSize)", auth: auth(token)) as? [String: Any],
              let rows = root["deployments"] as? [[String: Any]] else { return nil }
        return Array(rows.compactMap { thing(from: $0) }.prefix(landCap))
    }

    /// One deployment row → a thing, or nil when it isn't one of the two
    /// shapes that land. Split out so the probe and the harness can shape a
    /// row without a network call.
    static func thing(from row: [String: Any]) -> Thing? {
        guard let uid = nonEmpty(row["uid"]) else { return nil }
        let state = state(of: row)
        let target = row["target"] as? String
        guard VercelShape.lands(state: state, target: target) else { return nil }

        let meta = row["meta"] as? [String: Any] ?? [:]
        let host = nonEmpty(row["url"])
        let project = nonEmpty(row["name"])

        // Where the row takes you. A production deploy that went live wants
        // the SITE — that is the payoff, and the same reasoning that makes
        // Cursor prefer a pull request over its own dashboard page. A failure
        // wants the inspector, which is where the build log is.
        let link: String
        if state == .ready, let host {
            link = host.hasPrefix("http") ? host : "https://\(host)"
        } else {
            link = nonEmpty(row["inspectorUrl"]) ?? "https://vercel.com"
        }

        let thing = Thing(
            kind: .link,
            title: IngestSupport.titleLine(
                VercelShape.title(project: project, commitMessage: commitMessage(meta),
                                  host: host, state: state)),
            content: link,
            source: "Vercel",
            // The deployment's REAL time, not `.now` — a first sync sorts a
            // month of deploys back into history rather than stacking them on
            // today (the Hugging Face rule). `created` is EPOCH MILLISECONDS,
            // not seconds and not a string: treating it as seconds dates every
            // row to 1970 and treating it as a string finds nothing at all.
            capturedAt: epochMillis(row["createdAt"] ?? row["created"]) ?? .now,
            tags: [state == .ready ? "Deploy" : "Build failure"],
            sourceRef: "vercel:deploy:\(uid)"
        )
        // The project as a FIELD, not only as a clause inside the joined title
        // (2026-08-12). `WorkStage` draws the owning project on the sheet, and
        // it will only ever draw one it can read off a stored field — slicing
        // it out of the title on a separator would put half a commit subject
        // in a row labelled "Project" the first time a commit message
        // contained one, and a wrong value in a labelled row renders exactly
        // like a right one. `authorHandle` is the field Cursor has meant
        // "the repo this ran on" since §303, and it is unused here.
        thing.authorHandle = project
        // The branch it came off, and who pushed it. Display copy — the Trello
        // card-back rule — because "which branch" is the first question a
        // failed build raises and the title has no room for it.
        var notes: [String] = []
        if let branch = commitRef(meta) { notes.append(branch) }
        if let who = nonEmpty((row["creator"] as? [String: Any])?["username"]) {
            notes.append(who)
        }
        if !notes.isEmpty { thing.summary = notes.joined(separator: " · ") }
        return thing
    }

    /// The deployment's state. `readyState` is the field v6 documents; `state`
    /// is carried as a fallback because Vercel's own examples show both and
    /// they hold the same vocabulary. Nil for a value this build hasn't heard
    /// of — which `lands` treats as non-landing, the safe direction, and
    /// `diagnose` names.
    static func state(of row: [String: Any]) -> VercelState? {
        guard let raw = nonEmpty(row["readyState"]) ?? nonEmpty(row["state"]) else { return nil }
        return VercelState(rawValue: raw.uppercased())
    }

    /// Git metadata is namespaced by PROVIDER — `githubCommitMessage`,
    /// `gitlabCommitMessage`, `bitbucketCommitMessage` — so a GitLab-hosted
    /// project would silently have no commit message at all if only GitHub's
    /// key were read. All three, in the order Vercel lists them.
    static func commitMessage(_ meta: [String: Any]) -> String? {
        for provider in ["github", "gitlab", "bitbucket"] {
            if let s = nonEmpty(meta["\(provider)CommitMessage"]) { return s }
        }
        return nil
    }

    static func commitRef(_ meta: [String: Any]) -> String? {
        for provider in ["github", "gitlab", "bitbucket"] {
            if let s = nonEmpty(meta["\(provider)CommitRef"]) { return s }
        }
        return nil
    }

    /// Epoch MILLISECONDS → Date. Accepts the number in either of the shapes
    /// JSON can hand it back as; a string is accepted too because Vercel's
    /// docs show the field unquoted while some SDKs stringify large integers.
    static func epochMillis(_ raw: Any?) -> Date? {
        let ms: Double
        if let n = raw as? Double { ms = n }
        else if let n = raw as? Int { ms = Double(n) }
        else if let s = raw as? String, let n = Double(s) { ms = n }
        else { return nil }
        guard ms > 0 else { return nil }
        return Date(timeIntervalSince1970: ms / 1000)
    }

    static func nonEmpty(_ raw: Any?) -> String? {
        guard let s = (raw as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }

    // MARK: - Probe

    /// `-vercelProbe YES` — the read, phase by phase, with the STORED token.
    ///
    /// The `-cursorProbe` lesson. An empty Vercel room has FIVE causes and
    /// they render as one sentence:
    ///
    ///   1. no token stored,
    ///   2. a token Vercel refuses (403 — note NOT 401, measured),
    ///   3. a personal-scope token against an account whose projects all live
    ///      under a TEAM, which is the common real-world miss,
    ///   4. an account that deploys previews only and has never shipped to
    ///      production, so nothing passes the filter — not a bug, and the one
    ///      cause a landed count genuinely cannot distinguish,
    ///   5. shape drift — `deployments` renamed, or a state value this build
    ///      doesn't know.
    ///
    /// Only 5 is a bug. One `vercelDeploy|` line per row naming the four
    /// fields every shaping decision rests on, so 3 and 4 separate in one
    /// launch.
    @MainActor
    static func diagnose() async {
        guard let token = TokenVault.get(TokenBridge.vercel.tokenKey) else {
            NSLog("[Casberi] vercel| no token stored — connect first (-tokenBridge \"Vercel:<token>\")")
            return
        }
        let (json, status) = await IngestSupport.getJSONStatus(
            "\(base)?limit=\(pageSize)", auth: auth(token))
        NSLog("[Casberi] vercel| GET /v6/deployments HTTP %d", status)
        guard status != 403, status != 401 else {
            NSLog("[Casberi] vercel| refused — the token is wrong, or it's scoped to a team this token can't see.")
            return
        }
        guard let root = json as? [String: Any] else {
            NSLog("[Casberi] vercel| no JSON object — unreachable, or the envelope changed")
            return
        }
        guard let rows = root["deployments"] as? [[String: Any]] else {
            NSLog("[Casberi] vercel| no `deployments` array — SHAPE DRIFT. keys=%@",
                  root.keys.sorted().joined(separator: ","))
            return
        }
        NSLog("[Casberi] vercel| %d deployments on the first page (asked %d)", rows.count, pageSize)

        var lands = 0, previewsSkipped = 0, unknown: [String] = []
        for row in rows {
            let raw = nonEmpty(row["readyState"]) ?? nonEmpty(row["state"]) ?? "—"
            let parsed = state(of: row)
            if parsed == nil { unknown.append(raw) }
            let target = row["target"] as? String
            let would = VercelShape.lands(state: parsed, target: target)
            if would { lands += 1 }
            if parsed == .ready, !VercelShape.isProduction(target) { previewsSkipped += 1 }
            NSLog("[Casberi] vercelDeploy| state=%@ target=%@ lands=%@ project=%@ commit=%@",
                  raw, target ?? "(preview)", would ? "YES" : "no",
                  nonEmpty(row["name"]) ?? "—",
                  commitMessage(row["meta"] as? [String: Any] ?? [:]) != nil ? "yes" : "no")
        }
        if !unknown.isEmpty {
            NSLog("[Casberi] vercel| UNKNOWN state values, these land NOTHING: %@",
                  Set(unknown).sorted().joined(separator: ","))
        }
        NSLog("[Casberi] vercel| %d would land, %d successful previews skipped by design (cap %d)",
              lands, previewsSkipped, landCap)
        if rows.isEmpty {
            NSLog("[Casberi] vercel| the token works and this scope has no deployments — check whether your projects live under a team")
        }
    }
}
