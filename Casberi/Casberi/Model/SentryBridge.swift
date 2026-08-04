import Foundation
import SwiftData

/// The Sentry bridge (2026-08-04) — the errors your users hit, landing beside
/// everything else you keep.
///
/// ## The module doctrine is the whole design, and Sentry fights it harder
/// ## than PostHog did
///
/// Sentry is, by volume, a counter. Every issue it holds carries `count`,
/// `userCount`, a 24h sparkline and a 14d sparkline, and its own UI leads with
/// all four. **None of them land here.** A count is never a thing (the PostHog
/// ruling), and "TypeError happened 1,204 times" is the purest possible form of
/// the tally this app refuses — it renders beautifully, means nothing on its
/// own, and would re-land wearing a bigger number every single sync.
///
/// Exactly three shapes are events, and all three are TRANSITIONS rather than
/// states:
///
///   • **A new issue.** It did not exist, and now it does. This is the same
///     rule Hugging Face applies to a repo: `firstSeen`, never `lastSeen`
///     (which moves every time anyone hits the error, so a row keyed on it
///     would be perpetually "new").
///   • **A regression.** Something you closed came back. This is the flagship
///     — it is the one thing Sentry knows that nothing else in your day is
///     going to tell you, and it is exactly the shape a feed is good at.
///   • **An escalation.** Something you archived got loud enough that Sentry
///     un-archived it on your behalf.
///
/// ## Why a ledger, and not a `sourceRef` that encodes the moment
///
/// A new issue is easy — one issue, one row, `sentry:issue:<id>` forever. A
/// regression is not, because the SAME issue can regress repeatedly and each
/// time is real news. Keying the row on anything that moves (`lastSeen`, a
/// timestamp) would land a fresh row every sync for as long as the issue is
/// live; keying it on the issue id alone swallows every regression after the
/// first.
///
/// So this keeps a small per-issue ledger of the last substatus it saw and
/// counts the transitions, exactly the way `PostHog.Metric` counts announced
/// milestones. A row lands only when an issue CROSSES into regressed or
/// escalating, and its ref carries the crossing number. That makes the second
/// regression a different thing from the first, which is true, and makes a
/// sync that changes nothing land nothing, which is the point.
///
/// **`seeded` is separate from "the ledger is empty" and it is load-bearing** —
/// the PostHog lesson, which was a real bug there. An account connected while
/// an issue is already sitting at `regressed` must not be told it just
/// regressed: that moment happened before you connected, and reporting it is
/// the fake-status the honesty rule forbids. First sight records where every
/// issue currently stands WITHOUT announcing any of it, then lands the newest
/// few genuinely-new issues as proof the connection works — stamped with their
/// real `firstSeen`, so a three-month-old error sorts back three months and
/// cannot fake today's urgency. That is Hugging Face's split, for its reason.
///
/// ## Read-only is STRUCTURAL here
///
/// Sentry auth tokens carry real scopes, so this sits in PostHog's and
/// Stripe's tier rather than Cursor's and Privacy.com's: the setup screen names
/// `org:read`, `project:read` and `event:read`, and a token minted with those
/// three cannot resolve an issue, comment, delete a project, or write anything
/// back — not by our conduct, but because Sentry will refuse it. The promise
/// does not depend on this file behaving.
///
/// ## Self-hosted, and regions
///
/// `sentry.io` is the default and covers the US SaaS org. Two other cases are
/// real and both are just a different host: Sentry's EU region answers on
/// `de.sentry.io`, and a self-hosted install answers on whatever domain it was
/// installed at. The host is therefore a field, PostHog's shape exactly — and
/// like PostHog's it comes from the PERSON, so it can never be a literal in
/// `NetworkReach`; the reads below name their service to `NetworkLedger` so the
/// receipts screen can still attribute them (prd §289).
///
/// **MEASURED (2026-08-04)**: `sentry.io/api/0/organizations/` is reachable and
/// answers `401 {"detail":"Authentication credentials were not provided."}`
/// unauthenticated, which confirms the host, the path and the auth scheme.
/// **UNMEASURED**: every response SHAPE below — no token is stored on this host
/// and none of these endpoints answer without one. The field map comes from
/// Sentry's published API reference. Every read is a GET returning nil on any
/// failure, so it fails safe: drifted fields land nothing rather than landing
/// something wrong. Run `-sentryProbe YES` against a real token before trusting
/// any of it.
enum SentryAccount {

    /// Sentry's US SaaS host. EU orgs are `de.sentry.io`; self-hosted is
    /// whatever it was installed at. Stored rather than assumed because
    /// guessing wrong is a 401 that reads exactly like a bad token.
    static let defaultHost = "sentry.io"

    private static let hostKey = "sentry.host"
    private static let orgKey = "sentry.org"
    private static let orgNameKey = "sentry.orgName"

    static var host: String {
        get {
            let stored = UserDefaults.standard.string(forKey: hostKey) ?? ""
            return stored.isEmpty ? defaultHost : stored
        }
        set { UserDefaults.standard.set(normalizeHost(newValue), forKey: hostKey) }
    }

    /// The organization slug every issue read is scoped to. Resolved off
    /// `/organizations/` rather than typed — a slug is not what the person sees
    /// in Sentry's own UI header, and a typo there is another 401-shaped
    /// failure. PostHog resolves its project id the same way and for the same
    /// reason.
    static var org: String {
        get { UserDefaults.standard.string(forKey: orgKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: orgKey) }
    }

    /// The org's display name, for the setup screen. Cosmetic — its absence
    /// never blocks a read.
    static var orgName: String {
        get { UserDefaults.standard.string(forKey: orgNameKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: orgNameKey) }
    }

    static var api: String { "https://\(host)/api/0" }

    static var configured: Bool { !org.isEmpty }

    /// Accepts what a person actually pastes: a bare host, a URL, a trailing
    /// slash, or the whole organization page they were looking at.
    static func normalizeHost(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for prefix in ["https://", "http://"] where s.hasPrefix(prefix) {
            s = String(s.dropFirst(prefix.count))
        }
        s = s.split(separator: "/").first.map(String.init) ?? s
        return s.isEmpty ? defaultHost : s
    }

    static func clear() {
        let d = UserDefaults.standard
        d.removeObject(forKey: hostKey)
        d.removeObject(forKey: orgKey)
        d.removeObject(forKey: orgNameKey)
        SentryIssueLedger.clear()
    }
}

// MARK: - What an issue is doing, and what that makes it

/// Sentry's own `substatus` vocabulary, narrowed to what this bridge acts on.
///
/// Carried as a type rather than compared as strings so an unrecognised value
/// is a single explicit `nil` with one meaning — "this build does not know what
/// this is, so land nothing" — instead of a comparison that silently fails in
/// whichever branch happened to be written first. `diagnose` names the unknown
/// values it saw, so drift shows up as a probe line rather than as silence
/// (the Cursor rule).
enum SentrySubstatus: String {
    case new         = "new"
    case ongoing     = "ongoing"
    case regressed   = "regressed"
    case escalating  = "escalating"
    case archivedUntilEscalating = "archived_until_escalating"
    case archivedUntilConditionMet = "archived_until_condition_met"
    case archivedForever = "archived_forever"

    /// Whether CROSSING into this substatus is news. `new` is deliberately not
    /// here: a new issue is landed off `firstSeen` by the ingest, which works
    /// on the older installs and self-hosted versions that predate substatus
    /// entirely, so routing it through here too would land it twice.
    var isCrossing: Bool {
        switch self {
        case .regressed, .escalating: true
        default: false
        }
    }

    /// The clause that LEADS the row's title.
    ///
    /// Leading, not trailing, for the reason `CursorAgentStatus.leadClause`
    /// documents: `IngestSupport.titleLine` clamps at 80 characters and a long
    /// stack-frame title will eat anything parked at the end. "Regressed" is
    /// the entire reason the row exists, so it cannot be the part that gets
    /// cut.
    var leadClause: String? {
        switch self {
        case .regressed:  String(localized: "Regressed")
        case .escalating: String(localized: "Escalating")
        default:          nil
        }
    }
}

/// The per-issue record of where each issue stood last time we looked.
///
/// Deliberately UserDefaults and not a `Thing` field: this is bookkeeping, not
/// corpus, so it needs no CloudKit schema deploy and disappears with the
/// bridge. Bounded — see `prune`.
enum SentryIssueLedger {
    private static let key = "sentry.issues.v1"
    private static let seededKey = "sentry.seeded.v1"
    /// How many issues the ledger remembers. Sentry accounts routinely hold
    /// thousands; the read below only ever sees the newest page, so anything
    /// past a few pages' worth is a row we will never be asked about again.
    /// Bounded rather than unbounded because this is a preferences value that
    /// syncs nowhere and grows forever otherwise.
    static let cap = 500

    /// issue id → the last substatus string seen, plus how many crossings have
    /// been announced for it. Stored as a flat `[String: [String: Any]]`-ish
    /// pair of maps to stay JSON-plist-safe without a Codable dance.
    static func all() -> [String: Entry] {
        guard let raw = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: Entry].self, from: raw)
        else { return [:] }
        return decoded
    }

    struct Entry: Codable {
        var substatus: String = ""
        var crossings: Int = 0
    }

    static func get(_ id: String) -> Entry? { all()[id] }

    static func set(_ id: String, _ entry: Entry) {
        var map = all()
        map[id] = entry
        write(map)
    }

    /// Whether the bridge has recorded a first-sight baseline. Distinct from
    /// "the ledger is non-empty" for the reason `PostHog.Metric.seeded` is
    /// distinct from `announced == 0`: an org whose newest page is entirely
    /// archived issues records nothing, and without this flag every later pass
    /// would re-run the first-sight branch and re-decide the proof cap against
    /// a corpus that already has rows in it.
    static var seeded: Bool {
        get { UserDefaults.standard.bool(forKey: seededKey) }
        set { UserDefaults.standard.set(newValue, forKey: seededKey) }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults.standard.removeObject(forKey: seededKey)
    }

    private static func write(_ map: [String: Entry]) {
        let bounded = prune(map)
        guard let data = try? JSONEncoder().encode(bounded) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    /// Keeps the ledger under `cap`.
    ///
    /// Drops the entries with NOTHING announced first — an issue we have never
    /// reported on is one whose only value is "don't announce its current
    /// state as news", and that value expires as soon as the issue falls off
    /// the read window. An entry with crossings recorded is kept longer,
    /// because losing it means the next regression of that issue gets crossing
    /// number 1 again and collides with a row already in the corpus, which
    /// would silently swallow it.
    static func prune(_ map: [String: Entry]) -> [String: Entry] {
        guard map.count > cap else { return map }
        let ordered = map.sorted { a, b in
            if a.value.crossings != b.value.crossings { return a.value.crossings > b.value.crossings }
            return a.key > b.key
        }
        return Dictionary(uniqueKeysWithValues: ordered.prefix(cap).map { ($0.key, $0.value) })
    }
}

// MARK: - Pure shaping (harness-tested — see scripts/sentry-selftest.sh)

/// Everything about a Sentry row that can be decided without a network.
///
/// Split out from the fetch so `scripts/sentry-selftest.sh` can compile it
/// whole and assert against it. This bridge has never run against a live
/// organization, so the harness is the only proof these decisions are right —
/// the Stripe/Cursor argument, and here it is stronger than Cursor's, because
/// every failure below is a row that renders perfectly while saying the wrong
/// thing.
enum SentryShape {

    /// `"my-app · TypeError: undefined is not a function"`, with the crossing
    /// in front when there is one.
    ///
    /// The PROJECT leads for the reason Cursor's repository and Trello's board
    /// do: an error title is written against a context you had at the time
    /// ("KeyError: 'id'"), and in a feed beside a wallet alert and a podcast it
    /// means nothing without the thing it broke.
    static func title(project: String?, title: String, crossing: SentrySubstatus?) -> String {
        let parts = [crossing?.leadClause, project, title]
            .compactMap { $0 }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.joined(separator: " · ")
    }

    /// The ref for the row announcing that an issue EXISTS. One per issue,
    /// forever.
    static func newRef(id: String) -> String { "sentry:issue:\(id)" }

    /// The ref for the Nth time an issue crossed into `regressed`/`escalating`.
    ///
    /// The crossing number is what makes a second regression a different thing
    /// from the first — see the type's own note on why neither the issue id
    /// alone nor a timestamp works.
    static func crossingRef(id: String, substatus: SentrySubstatus, crossing: Int) -> String {
        "sentry:\(substatus.rawValue):\(id):\(crossing)"
    }

    /// Whether an issue counts as NEW rather than merely present.
    ///
    /// Keyed on `firstSeen` against a lookback rather than on `substatus ==
    /// "new"`, deliberately: substatus is a relatively recent Sentry concept
    /// and a self-hosted install a version or two behind does not send it at
    /// all, in which case every issue would silently fail this test and the
    /// bridge would land nothing forever with no error anywhere. `firstSeen`
    /// has always been there.
    static func isNew(firstSeen: Date?, now: Date, lookback: TimeInterval) -> Bool {
        guard let firstSeen else { return false }
        // A future `firstSeen` is a clock disagreement between this phone and
        // the server, not a new issue from tomorrow. Accepted rather than
        // rejected — being slightly early is harmless, and rejecting it would
        // silently drop real issues for anyone whose device clock runs behind.
        return now.timeIntervalSince(firstSeen) <= lookback
    }
}

// MARK: - Reads

enum SentryFetch {

    /// One page of issues. Sentry's own default page size is 25; asked
    /// explicitly so a change to their default cannot change how much of a
    /// backlog a first sight sees.
    static let pageSize = 25

    private static func auth(_ token: String) -> String { "Bearer \(token)" }

    /// The service name handed to `NetworkLedger`, since the host is the
    /// person's own (self-hosted, or a region) and therefore cannot be matched
    /// by the `NetworkReach` registry (prd §289).
    private static let service = "Sentry"

    struct Org {
        let slug: String
        let name: String
    }

    /// The organizations this token can see. Nil on any failure.
    ///
    /// Also the validation call: a token with no `org:read` gets a 403 here,
    /// which the setup screen words differently from a 401, because "you minted
    /// it without the right scope" and "you pasted it wrong" are different
    /// mistakes with different fixes (the Stripe four-sentences ruling).
    static func organizations(host: String, token: String) async -> [Org]? {
        let (json, status) = await IngestSupport.getJSONStatus(
            "https://\(host)/api/0/organizations/", auth: auth(token), service: service)
        guard status == 200, let rows = json as? [[String: Any]] else { return nil }
        return rows.compactMap { row in
            guard let slug = (row["slug"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !slug.isEmpty else { return nil }
            return Org(slug: slug, name: (row["name"] as? String) ?? slug)
        }
    }

    struct Issue {
        let id: String
        let title: String
        let culprit: String?
        let permalink: String?
        let project: String?
        let level: String?
        let substatusRaw: String?
        let firstSeen: Date?
    }

    /// The organization's unresolved issues, newest first.
    ///
    /// `query=is:unresolved` is Sentry's own default filter and is what makes
    /// this a read about live problems rather than an archive walk. Nothing
    /// here asks for events, stack traces, or anything a user typed — an issue
    /// row is a title, a location in your code, and a timestamp.
    static func issues(host: String, org: String, token: String) async -> [Issue]? {
        guard let escaped = org.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else { return nil }
        let url = "https://\(host)/api/0/organizations/\(escaped)/issues/"
            + "?query=is:unresolved&limit=\(pageSize)&sort=date"
        guard let rows = await IngestSupport.getJSON(url, auth: auth(token),
                                                    service: service) as? [[String: Any]]
        else { return nil }
        return rows.compactMap(parse)
    }

    /// One issue row → the fields this bridge shapes on. Split out so the
    /// probe and the harness can both reach it without a network call.
    static func parse(_ row: [String: Any]) -> Issue? {
        guard let id = (row["id"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty,
              let title = (row["title"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty
        else { return nil }
        let project = (row["project"] as? [String: Any])?["slug"] as? String
        return Issue(
            id: id,
            title: title,
            culprit: nonEmpty(row["culprit"]),
            permalink: nonEmpty(row["permalink"]),
            project: project,
            level: nonEmpty(row["level"]),
            substatusRaw: nonEmpty(row["substatus"]),
            firstSeen: IngestSupport.isoDate(row["firstSeen"])
        )
    }

    static func nonEmpty(_ raw: Any?) -> String? {
        guard let s = (raw as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }
}

// MARK: - Ingest

enum SentryIngest {

    @MainActor private static var running = false

    /// How far back an issue's `firstSeen` can be and still land as new.
    ///
    /// Wide enough that a week away doesn't silently drop everything that
    /// broke while you were gone, narrow enough that connecting an account
    /// doesn't dump a quarter into today. The first-sight branch below bounds
    /// itself separately.
    static let newLookback: TimeInterval = 14 * 24 * 3600

    /// How many genuinely-new issues land on the very first pass, as proof the
    /// connection works. Low on purpose — this is a handshake, not an import.
    private static let firstSightCap = 3

    @MainActor
    static func refresh(context: ModelContext) async -> Int? {
        guard SentryAccount.configured,
              let token = TokenVault.get(TokenBridge.sentry.tokenKey),
              !running else { return running ? 0 : nil }
        running = true
        defer { running = false }

        guard let issues = await SentryFetch.issues(host: SentryAccount.host,
                                                    org: SentryAccount.org,
                                                    token: token) else { return nil }

        let firstPass = !SentryIssueLedger.seeded
        var existing = IngestSupport.existingSourceRefs(context, source: "Sentry")
        var incoming: [Thing] = []
        var ledgerWrites: [(String, SentryIssueLedger.Entry)] = []
        var proofBudget = firstSightCap

        for issue in issues {
            let known = SentryIssueLedger.get(issue.id)
            let substatus = issue.substatusRaw.flatMap(SentrySubstatus.init(rawValue:))
            var entry = known ?? SentryIssueLedger.Entry()

            // 1. Did it just start existing?
            //
            // On the first pass this is capped, because "new in the last 14
            // days" against a busy org is a page of rows all landing at once —
            // which is a backfill wearing news, the exact thing the Hugging
            // Face cap exists to prevent.
            if SentryShape.isNew(firstSeen: issue.firstSeen, now: .now, lookback: newLookback) {
                let ref = SentryShape.newRef(id: issue.id)
                if !existing.contains(ref), !firstPass || proofBudget > 0 {
                    if firstPass { proofBudget -= 1 }
                    incoming.append(thing(issue, crossing: nil, ref: ref))
                    existing.insert(ref)
                }
            }

            // 2. Did it cross into regressed or escalating?
            //
            // Only a CROSSING counts — an issue that was already regressed
            // last time we looked is still regressed, which is a state, not
            // news. And never on the first pass: that crossing happened before
            // this account was connected, so announcing it would be inventing
            // a moment (the Hyperliquid first-sight bug, exactly).
            if let substatus, substatus.isCrossing, entry.substatus != substatus.rawValue,
               !firstPass {
                entry.crossings += 1
                let ref = SentryShape.crossingRef(id: issue.id, substatus: substatus,
                                                  crossing: entry.crossings)
                if !existing.contains(ref) {
                    incoming.append(thing(issue, crossing: substatus, ref: ref))
                    existing.insert(ref)
                }
            }

            // The ledger records where the issue stands NOW whether or not
            // anything landed — that is what makes the next pass able to see a
            // crossing, and what makes the first pass silent.
            entry.substatus = substatus?.rawValue ?? entry.substatus
            ledgerWrites.append((issue.id, entry))
        }

        for (id, entry) in ledgerWrites { SentryIssueLedger.set(id, entry) }
        SentryIssueLedger.seeded = true

        var added = 0
        for item in incoming {
            context.insert(item)
            SpotlightIndex.index([item])
            added += 1
        }
        if added > 0 { context.saveHonestly() }
        return added
    }

    /// One issue → one row.
    ///
    /// A crossing row is stamped `.now` because the crossing IS now — we
    /// detected it this pass and Sentry's payload carries no "regressed at".
    /// A new-issue row is stamped with its real `firstSeen`, so a backlog
    /// landed on first sight sorts back to when it actually broke.
    private static func thing(_ issue: SentryFetch.Issue,
                              crossing: SentrySubstatus?, ref: String) -> Thing {
        let thing = Thing(
            kind: .link,
            title: IngestSupport.titleLine(
                SentryShape.title(project: issue.project, title: issue.title,
                                  crossing: crossing)),
            content: issue.permalink ?? "",
            source: "Sentry",
            capturedAt: crossing == nil ? (issue.firstSeen ?? .now) : .now,
            tags: [crossing == nil ? "Issue" : "Regression"],
            sourceRef: ref
        )
        // Where in your code it happened. Display copy — the Trello card-back
        // and Cursor summary rule — because it is the one field that turns
        // "KeyError: 'id'" into something you can act on without opening
        // Sentry. Never the retrieval-only `enrichedText`.
        if let culprit = issue.culprit { thing.summary = culprit }
        return thing
    }

    // MARK: - Probe

    /// `-sentryProbe YES` — the read, phase by phase, with the STORED token.
    ///
    /// The `-cursorProbe`/`-trelloProbe` lesson. An empty Sentry room has SIX
    /// causes and they render as one silence:
    ///
    ///   1. no token stored,
    ///   2. a token Sentry refuses (401),
    ///   3. a token minted without `org:read`/`event:read` (403) — a different
    ///      mistake with a different fix,
    ///   4. the wrong host (an EU org read against `sentry.io`, or a
    ///      self-hosted install), which fails looking exactly like 2,
    ///   5. an org that genuinely has no unresolved issues — the healthy case,
    ///   6. shape drift, or a substatus vocabulary this build doesn't know,
    ///      which lands nothing and says nothing.
    ///
    /// Only 6 is a bug. One NSLog per line (the `-todayProbe` truncation
    /// lesson), and one `sentryIssue|` line per issue naming the five fields
    /// every shaping decision above rests on.
    @MainActor
    static func diagnose() async {
        let host = SentryAccount.host
        NSLog("[Casberi] sentry| host=%@ org=%@ seeded=%@", host,
              SentryAccount.org.isEmpty ? "(none)" : SentryAccount.org,
              SentryIssueLedger.seeded ? "YES" : "no")
        guard let token = TokenVault.get(TokenBridge.sentry.tokenKey) else {
            NSLog("[Casberi] sentry| no token stored — connect first (-tokenBridge \"Sentry:<token>\")")
            return
        }
        let (orgJSON, orgStatus) = await IngestSupport.getJSONStatus(
            "https://\(host)/api/0/organizations/", auth: "Bearer \(token)", service: "Sentry")
        NSLog("[Casberi] sentry| GET /organizations/ HTTP %d", orgStatus)
        switch orgStatus {
        case 401:
            NSLog("[Casberi] sentry| 401 — token refused. Wrong token, or the wrong host: an EU org answers on de.sentry.io, self-hosted on your own domain.")
            return
        case 403:
            NSLog("[Casberi] sentry| 403 — the token works but lacks a scope. Needs org:read, project:read, event:read.")
            return
        default: break
        }
        if let orgs = orgJSON as? [[String: Any]] {
            NSLog("[Casberi] sentry| %d organizations: %@", orgs.count,
                  orgs.compactMap { $0["slug"] as? String }.joined(separator: ","))
        }
        guard SentryAccount.configured else {
            NSLog("[Casberi] sentry| no org chosen yet — pick one on the setup screen")
            return
        }
        guard let issues = await SentryFetch.issues(host: host, org: SentryAccount.org,
                                                    token: token) else {
            NSLog("[Casberi] sentry| issues read FAILED — unreachable, or the org slug is wrong")
            return
        }
        NSLog("[Casberi] sentry| %d unresolved issues on the first page (asked %d)",
              issues.count, SentryFetch.pageSize)
        if issues.isEmpty {
            NSLog("[Casberi] sentry| the token works and nothing is unresolved — not a bug")
        }
        var unknown: [String] = []
        var wouldLand = 0
        for issue in issues {
            let raw = issue.substatusRaw ?? "—"
            let parsed = issue.substatusRaw.flatMap(SentrySubstatus.init(rawValue:))
            if issue.substatusRaw != nil, parsed == nil { unknown.append(raw) }
            let isNew = SentryShape.isNew(firstSeen: issue.firstSeen, now: .now,
                                          lookback: newLookback)
            let known = SentryIssueLedger.get(issue.id)
            let crosses = parsed?.isCrossing == true && known?.substatus != parsed?.rawValue
            if isNew || crosses { wouldLand += 1 }
            NSLog("[Casberi] sentryIssue| substatus=%@ new=%@ crosses=%@ project=%@ link=%@ title=%@",
                  raw, isNew ? "YES" : "no", crosses ? "YES" : "no",
                  issue.project ?? "—", issue.permalink != nil ? "yes" : "no", issue.title)
        }
        if !unknown.isEmpty {
            NSLog("[Casberi] sentry| UNKNOWN substatus values, these announce NOTHING: %@",
                  Set(unknown).sorted().joined(separator: ","))
        }
        NSLog("[Casberi] sentry| %d of %d would land on the next sync (ledger holds %d)",
              wouldLand, issues.count, SentryIssueLedger.all().count)
    }
}
