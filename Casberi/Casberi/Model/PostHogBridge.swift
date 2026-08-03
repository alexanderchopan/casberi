import Foundation
import SwiftData

/// PostHog (2026-07-27) — the numbers behind what you ship, read the way
/// every other watch bridge here reads: you name a metric, the metric IS the
/// thing, and only NEWS lands beside it.
///
/// The design problem this bridge exists to solve: PostHog is a firehose of
/// COUNTS, and a count is exactly what the module doctrine forbids a thing to
/// be (a module is a visualization, the thing itself, what's next, or the
/// synthesis — never a tally). So a watched metric never re-lands weekly
/// wearing a new number. It updates IN PLACE, and three things — and only
/// three — are allowed to land as news:
///
///   1. **Annotations.** PostHog's own timeline notes ("shipped 2.4.0",
///      "started the onboarding test"). Already an event, already dated,
///      already written by a person. The one perfectly Casberi-shaped object
///      the product exposes — and each one carries the watched metric's delta
///      SINCE it, which is the whole reason to have both this and GitHub.
///   2. **Milestones.** A count is allowed to be a thing exactly when the
///      count IS the event — the same exception money moving gets in the day
///      brief. "signed_up crossed 1,000" is news once; 1,001 never is.
///   3. **Silence.** A watched event that STOPS firing is the most valuable
///      thing analytics can tell someone who ships: your signup flow is
///      broken. Gated on a real baseline, so a metric that never fired much
///      can't cry wolf.
///
/// Read-only, and structurally so — unlike `PrivacyBridge`, whose "can't
/// spend" promise is kept by conduct because Privacy's key isn't scoped.
/// PostHog personal API keys carry explicit scopes, so the setup screen tells
/// you to mint one with `query:read`, `annotation:read`,
/// `event_definition:read` and nothing else. A key minted that way CANNOT
/// write, ship a flag, or edit a dashboard, whatever this file did.
///
/// UNMEASURED against a live project (2026-07-27): built from PostHog's public
/// API docs — `POST /api/projects/:id/query/` with a `HogQLQuery` kind, the
/// `/api/users/@me/` org/teams shape, `/api/projects/:id/annotations/`, and
/// `/api/projects/:id/event_definitions/`. Two documented facts to reconcile
/// before hardening: the query endpoint's rate limit is published in two
/// places as both **120/hour** and **2400/hour**, and the `/events` endpoint
/// is DEPRECATED in favour of the query endpoint (which is why nothing here
/// touches it). Run `-posthogProbe YES` against a real project and reconcile
/// the raw shapes it dumps before trusting any of this.
enum PostHogAccount {

    /// The host is a field, not a constant — PostHog runs US cloud, EU cloud,
    /// and self-hosted, and a bridge that hardcodes `us.posthog.com` is
    /// simply broken for the other two (the Cal.com precedent).
    static let defaultHost = "us.posthog.com"

    private static let hostKey = "posthog.host"
    private static let projectKey = "posthog.project"
    private static let projectNameKey = "posthog.projectName"

    static var host: String {
        get { UserDefaults.standard.string(forKey: hostKey) ?? defaultHost }
        set { UserDefaults.standard.set(newValue, forKey: hostKey) }
    }

    /// The numeric project (team) id every read is scoped to. Empty until the
    /// key resolves one — never typed by hand, always picked from what the
    /// key itself can see.
    static var projectID: String {
        get { UserDefaults.standard.string(forKey: projectKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: projectKey) }
    }

    static var projectName: String {
        get { UserDefaults.standard.string(forKey: projectNameKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: projectNameKey) }
    }

    static var api: String { "https://\(host)/api" }

    /// A project's own web address, so a landed thing opens where it lives.
    static func projectURL(_ path: String = "") -> String {
        let base = "https://\(host)/project/\(projectID)"
        return path.isEmpty ? base : "\(base)/\(path)"
    }

    static var configured: Bool {
        !projectID.isEmpty && TokenVault.get(TokenBridge.posthog.tokenKey) != nil
    }

    /// Bridge-specific teardown — the host/project/watch state that isn't a
    /// Thing, so a reconnected DIFFERENT project never wears the prior one's
    /// cache (the `BitrefillBalance.clear()` precedent).
    static func clear() {
        let d = UserDefaults.standard
        d.removeObject(forKey: hostKey)
        d.removeObject(forKey: projectKey)
        d.removeObject(forKey: projectNameKey)
        PostHogState.clear()
    }
}

// MARK: - The milestone ladder

/// Which numbers deserve to be news. A fixed "every 1,000" is wrong at both
/// ends — noise for pageviews, unreachable for a new product's signups — so
/// the ladder is 1-2-5 × powers of ten, scaled to whatever the metric's own
/// volume turns out to be, and it starts at 100 so a metric's first week
/// doesn't fire six alerts on the way up.
enum PostHogMilestone {

    static let floor = 100

    /// The rungs themselves, built once. Two hand-walked loops (one counting
    /// up, one counting down) each carried their own overflow guard and had to
    /// be kept in step; the table states the sequence — and its bound — once.
    private static let rungs: [Int] = {
        var values: [Int] = []
        var magnitude = floor
        while magnitude <= Int.max / 10 {
            for step in [1, 2, 5] { values.append(magnitude * step) }
            magnitude *= 10
        }
        return values
    }()

    /// The next rung strictly above `n`.
    static func next(after n: Int) -> Int { rungs.first { $0 > n } ?? n }

    /// The highest rung at or below `n` — 0 before the first one, which is
    /// what makes the ring's progress honest for a brand-new metric.
    static func reached(_ n: Int) -> Int { rungs.last { $0 <= n } ?? 0 }

    /// How far along this metric is between the rung it's passed and the one
    /// it's chasing, 0…1 — the roster ring's whole content.
    static func progress(_ n: Int) -> Double {
        let low = reached(n), high = next(after: n)
        guard high > low else { return 0 }
        return min(max(Double(n - low) / Double(high - low), 0), 1)
    }
}

// MARK: - Per-metric state (not Things)

/// What a watched metric knows between refreshes: its last read total, the
/// highest milestone already announced, and whether it's currently in a
/// silence we've already reported. None of this is a Thing — it's a reading,
/// so it lives beside the bridge the way `BitrefillBalance` does, and it is
/// wiped on disconnect.
enum PostHogState {

    struct Metric: Codable {
        var total: Int = 0
        /// The daily counts behind the sparkline, oldest first.
        var series: [Int] = []
        /// The highest rung already landed — so a crossing lands ONCE.
        var announced: Int = 0
        /// Whether this metric has ever been READ. Distinct from
        /// `announced == 0`, and the distinction is load-bearing: a metric
        /// first seen at 50 has announced 0 legitimately, and its later climb
        /// past 100 is real news. Without this flag that first genuine
        /// crossing was swallowed as "history" (caught in review before ship).
        var seeded: Bool = false
        /// Whether a silence has already been reported for the outage the
        /// metric is currently in, cleared the moment it fires again — one
        /// alert per outage, not per pass. A Bool, not the date it started:
        /// the field held a "since" string nothing ever read (the alert's own
        /// day is stamped into its sourceRef), and a name promising a date the
        /// UI can't show is a small lie to the next reader.
        var silent: Bool = false
        var fetchedAt: Date?
    }

    private static let key = "posthog.metrics"

    static func all() -> [String: Metric] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: Metric].self, from: data)
        else { return [:] }
        return decoded
    }

    static func get(_ event: String) -> Metric { all()[event] ?? Metric() }

    static func set(_ event: String, _ metric: Metric) {
        var map = all()
        map[event] = metric
        replace(map)
    }

    /// Write the whole map at once — what a refresh pass does, having decoded
    /// it once at the top and threaded it through every stage.
    static func replace(_ map: [String: Metric]) {
        guard let data = try? JSONEncoder().encode(map) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func forget(_ event: String) {
        var map = all()
        map.removeValue(forKey: event)
        replace(map)
    }

    static func clear() { UserDefaults.standard.removeObject(forKey: key) }
}

// MARK: - The reads

enum PostHogFetch {

    struct Project: Identifiable, Hashable {
        let id: String
        let name: String
        let org: String
    }

    struct EventDef: Identifiable, Hashable {
        let name: String
        let lastSeen: Date?
        var id: String { name }
    }

    struct Annotation: Identifiable, Hashable {
        let id: String
        let content: String
        let date: Date
        let author: String?
    }

    private static func auth(_ key: String) -> String { "Bearer \(key)" }

    /// ClickHouse's own datetime spellings, built once. `dayValue` ran inside
    /// `series`'s per-row loop, so this was up to 30 `DateFormatter`
    /// allocations (each with two `dateFormat` recompiles) per metric per
    /// fetch. The cached-static shape is what `IngestSupport.iso` and
    /// `TokenBridges.allDayFormatter` already use.
    private static let clickhouseFormats: [DateFormatter] = {
        ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd"].map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.dateFormat = format
            return formatter
        }
    }()

    // MARK: Projects

    /// Every project the key can see, read off the key itself. A project id
    /// is never typed — a typed integer is a number someone can get wrong and
    /// then stare at an empty screen wondering why (the `BridgeFieldRow`
    /// lesson from Cal.com), and the key already knows the answer.
    static func projects(host: String, key: String) async -> [Project]? {
        // Attributed throughout this file: `host` is `us.posthog.com` by
        // default (declared in the reach registry) but self-hosting is
        // supported, and a self-hosted host is one the person typed — so
        // only the caller can name the service for it.
        let (json, status) = await IngestSupport.getJSONStatus(
            "https://\(host)/api/users/@me/", auth: auth(key), service: "PostHog")
        guard status == 200, let root = json as? [String: Any] else { return nil }

        // The documented shape carries the current org inline, with `teams`
        // (PostHog's internal word for a project) beneath it. Both spellings
        // are accepted so a wrapper rename degrades to "no projects" rather
        // than a crash.
        let org = root["organization"] as? [String: Any]
        let orgName = (org?["name"] as? String) ?? ""
        let teams = (org?["teams"] as? [[String: Any]])
            ?? (root["teams"] as? [[String: Any]]) ?? []
        return teams.compactMap { team in
            guard let id = team["id"] else { return nil }
            let name = (team["name"] as? String) ?? "Project \(id)"
            return Project(id: String(describing: id), name: name, org: orgName)
        }
    }

    // MARK: Event names

    /// The autocomplete behind the Watch field — real event names this
    /// project actually emits, in PostHog's own last-seen order. You pick
    /// from what exists; you never guess a string and watch a metric that can
    /// only ever read zero.
    static func eventNames(host: String, project: String, key: String,
                           query: String, limit: Int = 6) async -> [EventDef] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let url = "https://\(host)/api/projects/\(project)/event_definitions/?search=\(encoded)&limit=\(limit)"
        guard let root = await IngestSupport.getJSON(url, auth: auth(key),
                                                     service: "PostHog") as? [String: Any],
              let results = root["results"] as? [[String: Any]] else { return [] }
        return results.compactMap { row in
            guard let name = row["name"] as? String, !name.isEmpty else { return nil }
            return EventDef(name: name, lastSeen: IngestSupport.isoDate(row["last_seen_at"]))
        }
    }

    // MARK: HogQL

    /// One HogQL read — nil when PostHog didn't answer 200, so a rejected key
    /// and an empty result stay distinguishable at the call sites. The event
    /// name rides `values` rather than being interpolated into the query text:
    /// it comes from `event_definitions` so it is already a real name, but a
    /// bridge that string-builds SQL around user-reachable input is a habit
    /// worth not having.
    private static func hogql(host: String, project: String, key: String,
                              sql: String, event: String) async -> [[Any]]? {
        let body: [String: Any] = ["kind": "HogQLQuery", "query": sql,
                                   "values": ["event": event]]
        let (json, status) = await IngestSupport.postJSONStatus(
            "https://\(host)/api/projects/\(project)/query/",
            auth: auth(key), body: ["query": body], service: "PostHog")
        guard status == 200, let root = json as? [String: Any] else { return nil }
        return (root["results"] as? [[Any]]) ?? []
    }

    /// A metric's daily counts over `days` (oldest first, dense) AND its
    /// all-time total, in ONE request.
    ///
    /// These were two POSTs per metric per window. The query endpoint is the
    /// rate-limited one — the docs give 120/hour at the low end, and five
    /// watched metrics on a ten-minute window would have spent half of that
    /// on a bare `SELECT count()`. A `UNION ALL` carries the total as a
    /// sentinel row (day NULL) alongside the daily aggregate, so the cost is
    /// one round trip and one rate-limit slot.
    ///
    /// Empty days are filled in as real zeroes: a gap in a series is a zero
    /// that happened, and drawing it as a straight line between two peaks
    /// would flatter the curve into saying something untrue.
    static func reading(host: String, project: String, key: String,
                        event: String, days: Int = 30) async -> (series: [Int], total: Int?)? {
        let sql = """
        SELECT toStartOfDay(timestamp) AS day, count() AS total
        FROM events
        WHERE event = {event} AND timestamp >= now() - INTERVAL \(days) DAY
        GROUP BY day
        UNION ALL
        SELECT NULL AS day, count() AS total
        FROM events
        WHERE event = {event}
        """
        guard let rows = await hogql(host: host, project: project, key: key,
                                     sql: sql, event: event) else { return nil }

        var byDay: [Date: Int] = [:]
        var total: Int?
        let calendar = Calendar.current
        for row in rows where row.count >= 2 {
            // The sentinel row is the one with no day — it carries the
            // all-time count the milestone ladder measures against.
            // Deliberately all-time rather than a rolling window: a rolling
            // total crosses the same rung in both directions forever, so
            // "you crossed 1,000" would arrive every few weeks and mean
            // nothing.
            guard let day = dayValue(row[0]) else {
                total = intValue(row[1])
                continue
            }
            byDay[calendar.startOfDay(for: day)] = intValue(row[1])
        }
        let today = calendar.startOfDay(for: .now)
        let series = stride(from: days - 1, through: 0, by: -1).map { back -> Int in
            let day = calendar.date(byAdding: .day, value: -back, to: today) ?? today
            return byDay[day] ?? 0
        }
        return (series, total)
    }

    // MARK: Annotations

    /// The project's timeline notes, newest first. `date_marker` is the date
    /// the note is ABOUT (a deploy's own moment); `created_at` is when
    /// somebody typed it. The marker is the truth for a feed that orders by
    /// when things happened, with created_at only as the fallback.
    static func annotations(host: String, project: String, key: String,
                            limit: Int = 25) async -> [Annotation]? {
        let url = "https://\(host)/api/projects/\(project)/annotations/?limit=\(limit)"
        let (json, status) = await IngestSupport.getJSONStatus(url, auth: auth(key),
                                                               service: "PostHog")
        guard status == 200, let root = json as? [String: Any],
              let results = root["results"] as? [[String: Any]] else { return nil }
        return results.compactMap { row in
            guard let id = row["id"], let content = row["content"] as? String,
                  !content.isEmpty else { return nil }
            let date = IngestSupport.isoDate(row["date_marker"])
                ?? IngestSupport.isoDate(row["created_at"]) ?? .now
            let by = row["created_by"] as? [String: Any]
            let author = (by?["first_name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? (by?["email"] as? String)
            return Annotation(id: String(describing: id), content: content,
                              date: date, author: author)
        }
    }

    // MARK: Value coercion

    /// ClickHouse hands numbers back as Int, Double or String depending on
    /// the column and the transport — read all three rather than trusting one.
    static func intValue(_ any: Any) -> Int {
        if let n = any as? Int { return n }
        if let d = any as? Double { return Int(d) }
        if let s = any as? String, let n = Int(s) { return n }
        return 0
    }

    /// A `toStartOfDay` value — ISO8601 in the documented shape, with the
    /// bare "yyyy-MM-dd HH:mm:ss" ClickHouse also emits accepted alongside it.
    static func dayValue(_ any: Any) -> Date? {
        guard let raw = any as? String else { return any as? Date }
        if let iso = IngestSupport.isoDate(raw) { return iso }
        for formatter in clickhouseFormats {
            if let date = formatter.date(from: raw) { return date }
        }
        return nil
    }
}

// MARK: - The watch (the thing IS the watch)

enum PostHogWatch {

    static let source = "PostHog"
    static let metricPrefix = "posthog:metric:"

    static func metricRef(_ event: String) -> String { "\(metricPrefix)\(event)" }

    static func isMetricRef(_ ref: String?) -> Bool {
        ref?.hasPrefix(metricPrefix) ?? false
    }

    static func event(from thing: Thing) -> String? {
        guard let ref = thing.sourceRef, ref.hasPrefix(metricPrefix) else { return nil }
        return String(ref.dropFirst(metricPrefix.count))
    }

    /// Watches a metric. The thing IS the watch (the TokenWatch/StockWatch
    /// precedent) — there's no side store to drift out of sync, and deleting
    /// the row is unwatching.
    @MainActor
    @discardableResult
    static func add(_ event: String, context: ModelContext) -> Thing? {
        let ref = metricRef(event)
        guard !IngestSupport.hasSourceRef(context, source: source, ref: ref) else { return nil }
        let thing = Thing(
            kind: .link,
            title: IngestSupport.titleLine(event),
            content: PostHogAccount.projectURL(),
            source: source,
            capturedAt: .now,
            tags: ["Watchlist"],
            sourceRef: ref
        )
        context.insert(thing)
        context.saveHonestly()
        SpotlightIndex.index([thing])
        return thing
    }

    @MainActor
    static func watchedEvents(context: ModelContext) -> [String] {
        IngestSupport.existingSourceRefs(context, source: source)
            .compactMap { $0.hasPrefix(metricPrefix) ? String($0.dropFirst(metricPrefix.count)) : nil }
            .sorted()
    }

    /// Disconnect teardown — drops the WATCH rows (a watch is access, and a
    /// kept one would re-register the seat on the next foreground), leaving
    /// landed annotations and milestones to follow the person's own "remove
    /// its things too" choice. The Stocktwits contract exactly.
    @MainActor
    static func unwatchAll(context: ModelContext) {
        let descriptor = FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == "PostHog" })
        let watches = ((try? context.fetch(descriptor)) ?? [])
            .filter { isMetricRef($0.sourceRef) }
        SpotlightIndex.remove(ids: watches.map(\.id))
        for thing in watches {
            if let event = event(from: thing) { PostHogState.forget(event) }
            context.delete(thing)
        }
        context.saveHonestly()
    }

    /// The seat rule, owned in one place: connected while a key, a project and
    /// at least one watch all exist. Clears itself the moment the last watch
    /// goes, so the catalog can never show a seat that reads nothing.
    @MainActor
    static func registerBridge(store: BridgeStore, context: ModelContext) {
        let count = watchedEvents(context: context).count
        guard PostHogAccount.configured, count > 0 else {
            store.remove(TokenBridge.posthog.bridgeID)
            return
        }
        let project = PostHogAccount.projectName
        store.registerConnected(
            id: TokenBridge.posthog.bridgeID, name: source,
            proof: "\(count) metric\(count == 1 ? "" : "s") watched"
                + (project.isEmpty ? "" : " · \(project)"),
            // The read-only promise has ONE home (`TokenBridge.canLine`) —
            // PostHog routes away from TokenSetupScreen, so a second copy here
            // would be the only reader of a string nothing else renders, and
            // the two would drift.
            can: [TokenBridge.posthog.canLine])
    }
}

// MARK: - The sweep

enum PostHogIngest {

    @MainActor private static var running = false

    /// How stale a metric reading may be before it's re-bought. The §216
    /// split, applied: a metric curve reports a STATE (a ten-minute-old chart
    /// is dated, not wrong) so it sits behind a window; annotations report
    /// EVENTS and are read every pass, unwindowed. The window also keeps a
    /// busy foreground clear of the query endpoint's rate limit, which the
    /// docs give as both 120/hour and 2400/hour — reconcile before loosening.
    static var metricWindow: TimeInterval = 600

    /// How many metric reads run at once. Watch lists are small, and the
    /// query endpoint is the rate-limited one — enough concurrency to stop
    /// serialising round trips, not enough to burst it.
    private static let maxConcurrentReads = 3

    /// Reads annotations (always) and each watched metric (behind the
    /// window), lands whatever counts as news, and returns how much did.
    /// nil is the honest "couldn't read" — no key, rejected key, or offline.
    ///
    /// The readings map is decoded ONCE here and threaded through every stage
    /// that needs it. Each stage used to call `PostHogState.get` per event —
    /// and `deltaSince` did it per event PER annotation — which decoded the
    /// whole UserDefaults blob ~80 times on a five-metric, ten-note pass.
    @MainActor
    static func refresh(context: ModelContext) async -> Int? {
        guard !running else { return 0 }
        guard PostHogAccount.configured,
              let key = TokenVault.get(TokenBridge.posthog.tokenKey) else { return nil }
        running = true
        defer { running = false }

        let host = PostHogAccount.host, project = PostHogAccount.projectID
        let events = PostHogWatch.watchedEvents(context: context)
        var readings = PostHogState.all()

        // Metrics and annotations are independent reads — the annotation call
        // doesn't wait behind the metric fan-out.
        async let notesTask = PostHogFetch.annotations(host: host, project: project, key: key)
        let fresh = await readMetrics(events, readings: readings,
                                      host: host, project: project, key: key)
        let annotations = await notesTask

        var reachedAny = annotations != nil
        for (event, reading) in fresh {
            readings[event] = reading
            reachedAny = true
        }
        guard reachedAny else { return nil }

        var landed: [Thing] = []
        landed.append(contentsOf: annotationThings(annotations ?? [], readings: readings))
        landed.append(contentsOf: milestoneThings(events, readings: &readings))
        landed.append(contentsOf: silenceThings(events, readings: &readings))
        PostHogState.replace(readings)

        return land(landed, context: context)
    }

    // MARK: Per-metric read

    /// Every metric whose window has expired, read concurrently. Returns only
    /// the ones that actually came back, so a failed read leaves the previous
    /// reading standing rather than blanking it.
    private static func readMetrics(_ events: [String],
                                    readings: [String: PostHogState.Metric],
                                    host: String, project: String,
                                    key: String) async -> [String: PostHogState.Metric] {
        let stale = events.filter { event in
            let reading = readings[event] ?? PostHogState.Metric()
            guard let fetched = reading.fetchedAt, !reading.series.isEmpty else { return true }
            return Date.now.timeIntervalSince(fetched) >= metricWindow
        }
        guard !stale.isEmpty else { return [:] }

        let results = await IngestSupport.boundedGather(stale, maxConcurrent: maxConcurrentReads) { event -> (String, PostHogState.Metric)? in
            guard let fresh = await PostHogFetch.reading(host: host, project: project,
                                                         key: key, event: event) else { return nil }
            var reading = readings[event] ?? PostHogState.Metric()
            reading.series = fresh.series
            // Leave the previous total standing if this read didn't carry one
            // — a missing sentinel row is unread, not zero, and zero would
            // reset the ladder.
            if let total = fresh.total { reading.total = total }
            reading.fetchedAt = .now
            return (event, reading)
        }
        return Dictionary(uniqueKeysWithValues: results.compactMap { $0 })
    }

    // MARK: The three news shapes

    /// A timeline note, carrying the watched metric's movement SINCE it. The
    /// delta is what makes this more than a mirrored string: "Shipped 2.4.0"
    /// is a fact PostHog already had, "signed_up +18% since" is the answer to
    /// the question the note makes you ask.
    private static func annotationThings(_ annotations: [PostHogFetch.Annotation],
                                         readings: [String: PostHogState.Metric]) -> [Thing] {
        annotations.map { note in
            var title = note.content
            if let delta = deltaSince(note.date, readings: readings) { title += " · \(delta)" }
            return Thing(
                kind: .link,
                title: IngestSupport.titleLine(title),
                content: PostHogAccount.projectURL(),
                source: PostHogWatch.source,
                capturedAt: note.date,
                tags: ["Annotation"],
                sourceRef: "posthog:annotation:\(note.id)"
            )
        }
    }

    /// "signed_up crossed 1,000" — the count as the event, landed once per
    /// rung. `announced` is what makes it once: a rung already named can never
    /// be named again, even if the total dips below it and climbs back.
    @MainActor
    private static func milestoneThings(_ events: [String],
                                        readings: inout [String: PostHogState.Metric]) -> [Thing] {
        var things: [Thing] = []
        for event in events {
            guard var state = readings[event] else { continue }
            // A total of 0 is either unread (the count query failed while the
            // series succeeded) or a genuinely empty event. Neither has a
            // ladder position, and seeding on an UNREAD total would make the
            // first real reading land a rung it passed long ago as news.
            guard state.total > 0 else { continue }
            let reached = PostHogMilestone.reached(state.total)

            // First sight of a metric that's ALREADY past a rung is history,
            // not news — record where it stands so the ring is honest from the
            // first frame, and never fake-celebrate a number from last year.
            guard state.seeded else {
                state.seeded = true
                state.announced = reached
                readings[event] = state
                continue
            }

            guard reached > state.announced else { continue }
            state.announced = reached
            readings[event] = state
            things.append(Thing(
                kind: .link,
                title: IngestSupport.titleLine("\(event) crossed \(formatted(reached))"),
                content: PostHogAccount.projectURL(),
                source: PostHogWatch.source,
                capturedAt: .now,
                tags: ["Milestone"],
                sourceRef: "posthog:milestone:\(event):\(reached)"
            ))
            // A milestone IS the count-as-event exception the module doctrine
            // carves out — it lands as a thing already, but used to land
            // silently (delight pass 2026-07-28). `state.announced` above is
            // what makes this fire-once-per-rung; no separate throttle needed.
            SourceMoments.shared.fire(
                String(localized: "\(event) crossed \(formatted(reached))"), source: PostHogWatch.source)
        }
        return things
    }

    /// A watched event that has stopped firing. Gated on a BASELINE — it must
    /// have fired on most of the recent days — so a rare event can't be
    /// reported as broken, and cleared the moment it fires again so one
    /// outage is one alert.
    private static func silenceThings(_ events: [String],
                                      readings: inout [String: PostHogState.Metric]) -> [Thing] {
        var things: [Thing] = []
        let today = dayStamp(.now)
        for event in events {
            guard var state = readings[event] else { continue }
            let series = state.series
            guard series.count >= 8 else { continue }

            let todayCount = series.last ?? 0
            let yesterday = series[series.count - 2]
            // The baseline: the week BEFORE the two days being judged.
            let baseline = series.dropLast(2).suffix(7)
            let firedDays = baseline.filter { $0 > 0 }.count
            let quiet = todayCount == 0 && yesterday == 0

            guard quiet, firedDays >= 5 else {
                if !quiet, state.silent {
                    state.silent = false
                    readings[event] = state
                }
                continue
            }
            guard !state.silent else { continue }
            state.silent = true
            readings[event] = state
            things.append(Thing(
                kind: .link,
                title: IngestSupport.titleLine("\(event) hasn't fired since yesterday"),
                content: PostHogAccount.projectURL(),
                source: PostHogWatch.source,
                capturedAt: .now,
                tags: ["Silence"],
                sourceRef: "posthog:silence:\(event):\(today)"
            ))
        }
        return things
    }

    // MARK: Landing

    /// Lands what's new — and HEALS on the dedupe hit, which for annotations
    /// is the point rather than a nicety. A note lands the day it's written,
    /// when there is no "since" to report yet; its delta only becomes
    /// knowable a day or two later. The social bridge already established
    /// this shape (every ingest heals what it dedupes), and here it's what
    /// turns "Shipped 2.4.0" into "Shipped 2.4.0 · signed_up +18% since"
    /// without waiting for the note to be rewritten upstream.
    @MainActor
    private static func land(_ incoming: [Thing], context: ModelContext) -> Int {
        // One keyed fetch of this bridge's own rows — not the whole corpus,
        // and not a fresh fetch per annotation being healed (the Bluesky
        // refresh shape).
        let landed = IngestSupport.thingsByRef(context, source: PostHogWatch.source)
        var added = 0
        var healed = false
        for item in incoming {
            guard let ref = item.sourceRef else { continue }
            if let existing = landed[ref] {
                // Annotations only: a milestone and a silence are stamped with
                // the moment they happened and must never be rewritten.
                guard ref.hasPrefix("posthog:annotation:"),
                      existing.isLive, existing.title != item.title else { continue }
                existing.title = item.title
                SpotlightIndex.index([existing])
                healed = true
                continue
            }
            context.insert(item)
            SpotlightIndex.index([item])
            added += 1
        }
        if added > 0 || healed { context.saveHonestly() }
        return added
    }

    // MARK: Helpers

    /// "signed_up +18% since" — the first watched metric with enough series
    /// on both sides of the note to say something true. Returns nil rather
    /// than a zero: a note older than the window, or one with no movement to
    /// report, simply doesn't get a clause.
    private static func deltaSince(_ date: Date,
                                   readings: [String: PostHogState.Metric]) -> String? {
        let daysAgo = Calendar.current.dateComponents([.day], from: date, to: .now).day ?? 0
        guard daysAgo >= 1, daysAgo <= 14 else { return nil }
        for (event, reading) in readings.sorted(by: { $0.key < $1.key }) {
            let series = reading.series
            guard series.count > daysAgo * 2 else { continue }
            let after = series.suffix(daysAgo).reduce(0, +)
            let before = series.dropLast(daysAgo).suffix(daysAgo).reduce(0, +)
            guard before > 0 else { continue }
            let change = Double(after - before) / Double(before)
            // A change that rounds to zero has no direction (the honesty
            // corollary) — so it gets no clause at all here.
            guard !TokenChartStyle.isFlat(change) else { continue }
            // The app's one delta formatter, so a PostHog row reads a percent
            // exactly as every wallet and token row does.
            return "\(event) \(TokenChartStyle.changeText(change)) since"
        }
        return nil
    }

    /// "1,000" — grouped, so a milestone reads as the moment it is. Called
    /// from view bodies, so it uses the value-type formatter rather than
    /// allocating a `NumberFormatter` per evaluation.
    static func formatted(_ n: Int) -> String {
        n.formatted(.number.grouping(.automatic))
    }

    private static let dayStampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static func dayStamp(_ date: Date) -> String {
        dayStampFormatter.string(from: date)
    }

    // MARK: Probe

    /// `-posthogProbe YES` — the measure tool for an UNMEASURED API. Connect
    /// first (`-tokenBridge "PostHog:<key>"` plus a project), then this reads
    /// the STORED key and NSLogs the RAW shapes: HTTP status per endpoint (so
    /// 401 wrong-key, 404 endpoint-gone and 0 unreachable stay distinct), the
    /// resolved projects, the annotation envelope, and — for each watched
    /// metric — the series length, the all-time total, the rung it's chasing
    /// and the silence verdict. Reads only; never a write.
    @MainActor
    static func probe(context: ModelContext) async {
        guard let key = TokenVault.get(TokenBridge.posthog.tokenKey) else {
            NSLog("[Casberi] posthogProbe: no stored key (connect via -tokenBridge \"PostHog:<key>\")")
            return
        }
        let host = PostHogAccount.host
        NSLog("[Casberi] posthogProbe: host=%@ project=%@", host, PostHogAccount.projectID)

        if let projects = await PostHogFetch.projects(host: host, key: key) {
            NSLog("[Casberi] posthogProbe projects: %d → %@", projects.count,
                  projects.map { "\($0.id):\($0.name)" }.joined(separator: ", "))
        } else {
            NSLog("[Casberi] posthogProbe projects: UNREADABLE (401 wrong key · 0 unreachable)")
        }

        let project = PostHogAccount.projectID
        guard !project.isEmpty else {
            NSLog("[Casberi] posthogProbe: no project picked — stopping before the scoped reads")
            return
        }

        if let notes = await PostHogFetch.annotations(host: host, project: project, key: key) {
            NSLog("[Casberi] posthogProbe annotations: %d", notes.count)
            if let first = notes.first {
                NSLog("[Casberi] posthogProbe firstNote → %@ · %@ · by %@",
                      first.content, ISO8601DateFormatter().string(from: first.date),
                      first.author ?? "—")
            }
        } else {
            NSLog("[Casberi] posthogProbe annotations: UNREADABLE")
        }

        for event in PostHogWatch.watchedEvents(context: context) {
            let fresh = await PostHogFetch.reading(host: host, project: project,
                                                   key: key, event: event)
            let series = fresh?.series ?? []
            let total = fresh?.total
            let last7 = series.suffix(7).reduce(0, +)
            NSLog("[Casberi] posthogProbe metric %@ → days=%d last7=%d total=%@ next=%@ progress=%.2f",
                  event, series.count, last7,
                  total.map(String.init) ?? "unread",
                  total.map { formatted(PostHogMilestone.next(after: $0)) } ?? "—",
                  total.map { PostHogMilestone.progress($0) } ?? 0)
        }
    }
}
