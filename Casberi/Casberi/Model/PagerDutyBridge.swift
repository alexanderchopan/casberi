import Foundation
import SwiftData

/// The PagerDuty bridge (2026-08-04) — what caught fire, and when it went out.
///
/// ## Both halves, and why the second one is the interesting one
///
/// PagerDuty is the rare service whose every object is already exactly the
/// shape this app wants: an incident is an event, it has a moment, and it is
/// over when it is over. No count is landed and none is tempting — nobody
/// wants "47 incidents this month" in a feed.
///
/// Two rows land per incident, and they are a LOOP-CLOSER pair, the shape
/// Stripe's disputes use:
///
///   • **Triggered** — what fired, on which service, how urgent, stamped with
///     the incident's own `created_at`.
///   • **Resolved** — the same incident, closed, carrying HOW LONG IT LASTED.
///
/// The duration is the entire reason the second row exists. "Checkout is down"
/// is a fact you already knew at 2am; "Checkout is down — resolved after 41
/// minutes" is the record you want three weeks later when someone asks what
/// happened. And unlike Hyperliquid — where a held-duration has to be grounded
/// in the app's own first-seen record because the API doesn't say when the
/// position opened — PagerDuty gives both ends itself, so the number is the
/// source's own truth rather than ours.
///
/// A resolved incident is resolved forever, so nothing here needs reconciling:
/// the second row IS the reconciliation, and it is a thing rather than an edit
/// because a resolution is a moment.
///
/// ## Read-only is STRUCTURAL
///
/// PagerDuty REST API keys carry a read-only flag set at creation, so this sits
/// in PostHog's, Stripe's and Sentry's tier rather than Cursor's. That matters
/// more here than for any other bridge in this app: a read-write PagerDuty key
/// can trigger an incident, which wakes up whoever is on call at 3am. The setup
/// step names the checkbox for exactly that reason.
///
/// ## The cursor, and why first sight lands only what's still burning
///
/// The read is windowed on `since`, advanced to the newest incident seen. On
/// FIRST sight there is no cursor, and the honest thing to land is the
/// incidents that are still OPEN — those are true right now and are the reason
/// someone just connected this. A resolved incident from last Tuesday is
/// history, and landing "Triggered" for something that finished days ago is
/// inventing a moment (the Hyperliquid first-sight bug). So first sight is
/// open-only, capped, stamped with real `created_at`s; every pass after that
/// lands both halves.
///
/// **MEASURED (2026-08-04)**: `api.pagerduty.com/incidents` is reachable and
/// answers `401` unauthenticated, confirming host, path and that it demands a
/// credential. **UNMEASURED**: every response shape below — no key is stored on
/// this host. The field map comes from PagerDuty's published REST reference.
/// Every read is a GET returning nil on failure, so it fails safe. Run
/// `-pagerdutyProbe YES` against a real key before trusting it.
enum PagerDutyCursor {
    private static let sinceKey = "pagerduty.since"
    private static let seededKey = "pagerduty.seeded"

    /// The newest `created_at` this bridge has already accounted for. The
    /// window read next pass starts here.
    static var since: Date? {
        get {
            let t = UserDefaults.standard.double(forKey: sinceKey)
            return t > 0 ? Date(timeIntervalSince1970: t) : nil
        }
        set { UserDefaults.standard.set(newValue?.timeIntervalSince1970 ?? 0, forKey: sinceKey) }
    }

    /// Whether first sight has happened. Distinct from `since != nil` for
    /// `PostHog.Metric.seeded`'s reason: an account with no incidents at all
    /// sets no cursor, and without this flag every pass would re-run the
    /// first-sight branch forever.
    static var seeded: Bool {
        get { UserDefaults.standard.bool(forKey: seededKey) }
        set { UserDefaults.standard.set(newValue, forKey: seededKey) }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: sinceKey)
        UserDefaults.standard.removeObject(forKey: seededKey)
    }
}

// MARK: - Pure shaping (harness-tested — see scripts/pagerduty-selftest.sh)

enum PagerDutyShape {

    /// How long an incident lasted, in the words a person would use.
    ///
    /// Deliberately COARSE past the hour — "resolved after 3 hours" is what
    /// anyone would say, and "after 3 hours 11 minutes" is a precision the
    /// reader has no use for and which makes the title longer at exactly the
    /// point `titleLine` starts cutting. Under a minute reads as "under a
    /// minute" rather than "0 minutes", which would look like a bug.
    ///
    /// Nil for a negative or absurd interval — a resolution timestamp before
    /// the trigger is a clock disagreement, and printing "resolved after -4
    /// minutes" is worse than printing nothing.
    static func duration(from start: Date?, to end: Date?) -> String? {
        guard let start, let end else { return nil }
        let seconds = end.timeIntervalSince(start)
        guard seconds >= 0 else { return nil }
        if seconds < 60 { return String(localized: "under a minute") }
        let minutes = Int(seconds / 60)
        if minutes < 60 {
            return String(localized: "\(minutes) min")
        }
        let hours = Int(seconds / 3600)
        if hours < 48 {
            return String(localized: "\(hours) hr")
        }
        return String(localized: "\(Int(seconds / 86400)) days")
    }

    /// `"Checkout API · Payments failing"`, with the outcome in front.
    ///
    /// The SERVICE leads for Cursor's repository reason: an incident title is
    /// written by whatever monitor fired it ("HTTP 500 rate > 5%"), and in a
    /// feed beside everything else it means nothing without the system it
    /// happened to.
    ///
    /// The outcome LEADS rather than trails because `titleLine` clamps at 80
    /// and an incident title is exactly the kind of long machine-generated
    /// string that eats a trailing clause — and a resolved incident reading as
    /// an open one is the §83 fake status, in the domain where believing it
    /// costs the most.
    static func title(service: String?, title: String, resolved: Bool,
                      lasted: String?) -> String {
        var lead: String?
        if resolved {
            lead = lasted.map { String(localized: "Resolved after \($0)") }
                ?? String(localized: "Resolved")
        }
        let parts = [lead, service, title]
            .compactMap { $0 }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.joined(separator: " · ")
    }

    static func triggeredRef(id: String) -> String { "pagerduty:incident:\(id)" }
    static func resolvedRef(id: String) -> String { "pagerduty:resolved:\(id)" }
}

// MARK: - Read

enum PagerDutyFetch {

    private static let base = "https://api.pagerduty.com"

    /// One page. PagerDuty's own default is 25 and its maximum is 100; asked
    /// explicitly so their default moving can't change what a first sight sees.
    static let pageSize = 25

    /// PagerDuty's scheme is its own — `Token token=<key>`, not Bearer — and
    /// the versioned Accept header is REQUIRED, not optional politeness: v1 and
    /// v2 differ in the envelope, and omitting it means the shape you get back
    /// is whatever their default happens to be that year.
    private static func headers(_ key: String) -> [String: String] {
        ["Authorization": "Token token=\(key)",
         "Accept": "application/vnd.pagerduty+json;version=2"]
    }

    struct Incident {
        let id: String
        let title: String
        let service: String?
        let status: String
        let urgency: String?
        let htmlURL: String?
        let createdAt: Date?
        let resolvedAt: Date?

        var isResolved: Bool { status.caseInsensitiveCompare("resolved") == .orderedSame }
        var isOpen: Bool { !isResolved }
    }

    /// Incidents, newest first, optionally windowed.
    ///
    /// `since` is exclusive-ish on PagerDuty's side (it filters on
    /// `created_at`), which is why the ingest below still dedupes on
    /// `sourceRef` rather than trusting the window to be exact — a boundary
    /// incident arriving twice must land once.
    static func incidents(key: String, since: Date?, openOnly: Bool) async -> [Incident]? {
        var url = "\(base)/incidents?limit=\(pageSize)&sort_by=created_at:desc"
        if openOnly {
            url += "&statuses%5B%5D=triggered&statuses%5B%5D=acknowledged"
        }
        if let since {
            let stamp = ISO8601DateFormatter().string(from: since)
            if let escaped = stamp.addingPercentEncoding(
                withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-_.~"))) {
                url += "&since=\(escaped)"
            }
        }
        guard let root = await IngestSupport.getJSON(url, headers: headers(key)) as? [String: Any],
              let rows = root["incidents"] as? [[String: Any]] else { return nil }
        return rows.compactMap(parse)
    }

    /// One incident row → the fields this bridge shapes on. Split out so the
    /// probe and the harness reach it without a network call.
    static func parse(_ row: [String: Any]) -> Incident? {
        guard let id = nonEmpty(row["id"]),
              let title = nonEmpty(row["title"]),
              let status = nonEmpty(row["status"]) else { return nil }
        // `resolved_at` is documented but is not always present on a resolved
        // incident; `last_status_change_at` is, and for a resolved incident it
        // IS the resolution. Falling back to it is what keeps the duration
        // from silently vanishing on the rows that have it.
        let resolved = IngestSupport.isoDate(row["resolved_at"])
            ?? IngestSupport.isoDate(row["last_status_change_at"])
        return Incident(
            id: id,
            title: title,
            service: nonEmpty((row["service"] as? [String: Any])?["summary"]),
            status: status,
            urgency: nonEmpty(row["urgency"]),
            htmlURL: nonEmpty(row["html_url"]),
            createdAt: IngestSupport.isoDate(row["created_at"]),
            resolvedAt: resolved
        )
    }

    static func nonEmpty(_ raw: Any?) -> String? {
        guard let s = (raw as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }
}

// MARK: - Ingest

enum PagerDutyIngest {

    @MainActor private static var running = false

    /// How many open incidents land on first sight, as proof the connection
    /// works. Low on purpose — a handshake, not an import.
    private static let firstSightCap = 5

    @MainActor
    static func refresh(context: ModelContext) async -> Int? {
        guard let key = TokenVault.get(TokenBridge.pagerduty.tokenKey),
              !running else { return running ? 0 : nil }
        running = true
        defer { running = false }

        let firstPass = !PagerDutyCursor.seeded
        guard let incidents = await PagerDutyFetch.incidents(
            key: key, since: firstPass ? nil : PagerDutyCursor.since,
            openOnly: firstPass) else { return nil }

        var existing = IngestSupport.existingSourceRefs(context, source: "PagerDuty")
        var added = 0
        var newest = PagerDutyCursor.since
        var budget = firstSightCap

        // Oldest first, so a window carrying several incidents inserts them in
        // the order they happened rather than reversed.
        for incident in incidents.reversed() {
            if let created = incident.createdAt, newest == nil || created > newest! {
                newest = created
            }
            if firstPass {
                guard budget > 0 else { continue }
                budget -= 1
            }
            // The trigger. Landed for every incident the window returns,
            // including one that has since resolved — it is stamped with its
            // real `created_at`, so it sorts back to when it fired rather than
            // pretending to be now.
            let triggeredRef = PagerDutyShape.triggeredRef(id: incident.id)
            if !existing.contains(triggeredRef) {
                let thing = Thing(
                    kind: .link,
                    title: IngestSupport.titleLine(
                        PagerDutyShape.title(service: incident.service, title: incident.title,
                                             resolved: false, lasted: nil)),
                    content: incident.htmlURL ?? "",
                    source: "PagerDuty",
                    capturedAt: incident.createdAt ?? .now,
                    tags: ["Incident"],
                    sourceRef: triggeredRef
                )
                // Urgency is display copy rather than part of the title: it is
                // one word, it is the same word on most rows, and putting it in
                // front would push the service out of the clamp on exactly the
                // long machine-generated titles that need it most.
                if let urgency = incident.urgency {
                    thing.summary = String(localized: "\(urgency) urgency")
                }
                // The service as a FIELD (2026-08-12) — see `VercelBridge` for
                // the reasoning; machine-generated incident titles are the
                // worst case for slicing a name out of a joined string.
                thing.authorHandle = incident.service
                context.insert(thing)
                existing.insert(triggeredRef)
                SpotlightIndex.index([thing])
                added += 1
            }

            // The resolution — never on first sight, where `openOnly` means
            // nothing resolved can be in this list anyway, and the guard is
            // belt-and-braces against that filter ever being relaxed.
            guard !firstPass, incident.isResolved else { continue }
            let resolvedRef = PagerDutyShape.resolvedRef(id: incident.id)
            guard !existing.contains(resolvedRef) else { continue }
            let lasted = PagerDutyShape.duration(from: incident.createdAt, to: incident.resolvedAt)
            let thing = Thing(
                kind: .link,
                title: IngestSupport.titleLine(
                    PagerDutyShape.title(service: incident.service, title: incident.title,
                                         resolved: true, lasted: lasted)),
                content: incident.htmlURL ?? "",
                source: "PagerDuty",
                // Stamped when it RESOLVED, not when it fired — this row is
                // the moment it went out.
                capturedAt: incident.resolvedAt ?? .now,
                tags: ["Resolved"],
                sourceRef: resolvedRef
            )
            thing.authorHandle = incident.service
            context.insert(thing)
            existing.insert(resolvedRef)
            SpotlightIndex.index([thing])
            added += 1
        }

        // The cursor advances only AFTER the rows are in the context — moving
        // it first would skip a window forever on a crash (the Stripe rule).
        if added > 0 { context.saveHonestly() }
        PagerDutyCursor.since = newest
        PagerDutyCursor.seeded = true
        return added
    }

    // MARK: - Probe

    /// `-pagerdutyProbe YES` — the read, phase by phase, with the STORED key.
    ///
    /// An empty PagerDuty room has FIVE causes rendering as one silence:
    ///
    ///   1. no key stored,
    ///   2. a key PagerDuty refuses (401),
    ///   3. a key minted at USER scope rather than account scope, which sees a
    ///      different (often empty) slice,
    ///   4. an account that is genuinely quiet — the good case, and by far the
    ///      most common,
    ///   5. shape drift — `incidents` renamed, or the date fields moving,
    ///      which lands rows with no duration and no error anywhere.
    ///
    /// Only 5 is a bug. One `pdIncident|` line per incident naming the five
    /// fields the shaping rests on — including both timestamps, since a
    /// missing `resolved_at` is what silently turns "resolved after 41 min"
    /// into a bare "Resolved".
    @MainActor
    static func diagnose() async {
        NSLog("[Casberi] pagerduty| since=%@ seeded=%@",
              PagerDutyCursor.since.map { ISO8601DateFormatter().string(from: $0) } ?? "(none)",
              PagerDutyCursor.seeded ? "YES" : "no")
        guard let key = TokenVault.get(TokenBridge.pagerduty.tokenKey) else {
            NSLog("[Casberi] pagerduty| no key stored — connect first (-tokenBridge \"PagerDuty:<key>\")")
            return
        }
        let (json, status) = await IngestSupport.getJSONStatus(
            "https://api.pagerduty.com/incidents?limit=\(PagerDutyFetch.pageSize)&sort_by=created_at:desc",
            headers: ["Authorization": "Token token=\(key)",
                      "Accept": "application/vnd.pagerduty+json;version=2"])
        NSLog("[Casberi] pagerduty| GET /incidents HTTP %d", status)
        guard status != 401 else {
            NSLog("[Casberi] pagerduty| 401 — the key was refused. Mint one at pagerduty.com → Integrations → API Access Keys.")
            return
        }
        guard let root = json as? [String: Any] else {
            NSLog("[Casberi] pagerduty| no JSON object — unreachable, or the envelope changed")
            return
        }
        guard let rows = root["incidents"] as? [[String: Any]] else {
            NSLog("[Casberi] pagerduty| no `incidents` array — SHAPE DRIFT. keys=%@",
                  root.keys.sorted().joined(separator: ","))
            return
        }
        NSLog("[Casberi] pagerduty| %d incidents on the first page (asked %d)",
              rows.count, PagerDutyFetch.pageSize)
        if rows.isEmpty {
            NSLog("[Casberi] pagerduty| the key works and nothing has fired — not a bug")
        }
        var open = 0, resolved = 0, undated = 0
        for row in rows {
            guard let incident = PagerDutyFetch.parse(row) else {
                NSLog("[Casberi] pdIncident| UNPARSEABLE keys=%@",
                      row.keys.sorted().joined(separator: ","))
                continue
            }
            if incident.isResolved { resolved += 1 } else { open += 1 }
            if incident.createdAt == nil { undated += 1 }
            NSLog("[Casberi] pdIncident| status=%@ urgency=%@ created=%@ resolved=%@ lasted=%@ service=%@ title=%@",
                  incident.status, incident.urgency ?? "—",
                  incident.createdAt != nil ? "yes" : "MISSING",
                  incident.resolvedAt != nil ? "yes" : "no",
                  PagerDutyShape.duration(from: incident.createdAt, to: incident.resolvedAt) ?? "—",
                  incident.service ?? "—", incident.title)
        }
        if undated > 0 {
            NSLog("[Casberi] pagerduty| %d incidents carry NO created_at — those land stamped now, which is wrong. SHAPE DRIFT.", undated)
        }
        NSLog("[Casberi] pagerduty| %d open, %d resolved", open, resolved)
    }
}
