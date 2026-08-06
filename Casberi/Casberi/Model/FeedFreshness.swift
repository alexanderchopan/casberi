import Foundation

/// What one feed fetch came back as (2026-08-05).
///
/// Three outcomes where there used to be two. `RSSIngest` and
/// `FeedFollowIngest` both spelled a fetch as `Data?`, which folded "the
/// publisher says nothing has changed" into "we couldn't reach it" — and both
/// of those into "here are the same fifteen items you already have." The
/// distinction is the whole point of the conditional GET below, and it is also
/// what lets a sync say the feed was REACHED without re-parsing a body it
/// already holds.
enum FeedFetchOutcome {
    /// A 200 with a body — parse it.
    case fresh(Data)
    /// A 304. The publisher answered and nothing has changed since the
    /// validators we sent. Reached, nothing to parse.
    case notModified
    /// Non-2xx, or no response at all. `status` is 0 for a transport failure
    /// (offline, DNS, reset) and the real code otherwise — the two read
    /// differently on the feed's own row.
    case failed(status: Int)
}

/// Per-feed HTTP bookkeeping: conditional GET, and whether a feed is still
/// answering at all (2026-08-05).
///
/// TWO FEATURES, ONE STORE, because they are the same three fields. A
/// conditional GET needs the validators the publisher last handed us; a health
/// line needs when the publisher last answered. Both are keyed by feed URL and
/// both are pure local bookkeeping, so they share a record rather than two
/// parallel dictionaries that could disagree about whether a fetch happened.
///
/// WHY CONDITIONAL GET. Every foreground re-downloaded every followed feed
/// whole — the RSS bridge polls on each app activation and on every visit to
/// its own screen, and a feed body is tens to hundreds of kilobytes. `ETag` /
/// `Last-Modified` are what the format was designed with; a 304 is no body and
/// no parse. Nothing about what lands changes.
///
/// HOW OFTEN IT ACTUALLY HELPS — MEASURED 2026-08-06, and the answer is "about
/// half of RSS and none of the rest", which is worth knowing before anyone
/// counts on it:
///
///     techcrunch.com/feed/          ETag + Last-Modified   ← 304, 0 bytes vs 17,250
///     theverge.com/rss/index.xml    ETag
///     overreacted.io/rss.xml        ETag
///     feeds.bbci.co.uk/news/rss.xml neither
///     news.ycombinator.com/rss      neither
///     reddit.com/r/…/.rss           neither
///     youtube.com/feeds/videos.xml  neither
///
/// So the two hosts the feed-follow bridges lean on hardest offer nothing, and
/// this saves them nothing. That is fine — a feed with no validators costs
/// exactly what it always did, since the headers are simply absent and the
/// request is an ordinary GET — but it means this is a courtesy that pays off
/// unevenly, not a uniform win. `-feedHealthProbe`'s `cond=` column is the
/// only place that fact is visible; a feed silently not participating looks
/// identical to one that is.
///
/// WHY THE RECORD LIVES IN USERDEFAULTS AND NOT ON `RSSStore.Feed` /
/// `FeedFollowEntry`. Those two are `Codable` structs persisted as JSON, and
/// Swift's synthesized decoder does NOT fall back to a property's default value
/// for a missing key — it throws. Both stores decode with `try?` and fall back
/// to an EMPTY list, so adding a field to either would silently unfollow every
/// feed on the device on first launch after the update. A separate store is not
/// merely tidier here; it is the only safe shape. (This record decodes every
/// field with `decodeIfPresent` for the same reason, so a future field is
/// additive — and a lost cache costs one full fetch, never a follow.)
///
/// SHARED BY BOTH BRIDGES on purpose: RSS and the four feed-follow kinds all
/// end up fetching a feed URL, and a URL is a URL. Keyed by that URL, so
/// following the same feed through two doors shares one record instead of
/// racing two.
///
/// NOT `@MainActor`, and lock-guarded instead — the `HandOffState` shape.
/// `RSSIngest.fetchAndParse` and `FeedFollowIngest.fetchAndParse` were both
/// deliberately moved OFF the main actor so a dozen feeds fetch and parse
/// concurrently; a main-actor store would put two hops back into each of them.
/// The stores that own follows (`RSSStore`, `FeedFollowStore`) aren't
/// main-actor either, and they need to `forget` a removed feed at the point of
/// removal rather than trusting each screen to remember.
enum FeedFreshness {

    /// One feed URL's HTTP history. Every field optional-decoded — see the
    /// type doc.
    struct Record: Codable {
        var etag: String?
        var lastModified: String?
        /// When we last took a full BODY (not a 304). Bounds how long a
        /// conditional GET may keep the ingest from seeing feed contents —
        /// see `revalidateAfter`.
        var bodyAt: Date?
        /// When the publisher last ANSWERED usefully — a 200 or a 304. This
        /// is what "hasn't answered in N days" counts from.
        var successAt: Date?
        /// Consecutive failed fetches since the last success.
        var failures: Int
        /// The status of the most recent failure (0 = transport).
        var lastStatus: Int

        init() {
            failures = 0
            lastStatus = 0
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            etag = try c.decodeIfPresent(String.self, forKey: .etag)
            lastModified = try c.decodeIfPresent(String.self, forKey: .lastModified)
            bodyAt = try c.decodeIfPresent(Date.self, forKey: .bodyAt)
            successAt = try c.decodeIfPresent(Date.self, forKey: .successAt)
            failures = try c.decodeIfPresent(Int.self, forKey: .failures) ?? 0
            lastStatus = try c.decodeIfPresent(Int.self, forKey: .lastStatus) ?? 0
        }
    }

    private static let storeKey = "feed.freshness"

    /// Feeds tracked at once. A record is ~150 bytes, so this is small — the
    /// cap exists so a person who imports a 400-feed OPML, prunes it to 20 and
    /// repeats doesn't grow this forever. Evicted least-recently-answered
    /// first. Deliberately NOT pruned against a caller's own feed list: RSS and
    /// the four feed-follow kinds share this store, so a prune scoped to one
    /// caller's URLs would wipe the other four.
    private static let cap = 400

    /// How long a conditional GET may go without seeing a body.
    ///
    /// A 304 hands the ingest nothing, which is right for LANDING (there is
    /// nothing new) and wrong for HEALING: both ingests patch already-landed
    /// rows from feed data on each pass — a publisher icon, the feed's name
    /// onto `authorHandle`, an entity-decoded title, a lead image for a row
    /// that landed artless. Those heals reach only rows still inside the
    /// feed's own window, and a permanently-304 feed would stall them forever.
    /// So the validators are dropped once a day and one full body is taken.
    /// A feed polled a dozen times a day still skips eleven of those bodies,
    /// and the heals it does need get their chance within the day.
    private static let revalidateAfter: TimeInterval = 24 * 3600

    /// Consecutive failures before a feed's row says anything.
    ///
    /// Three, and the floor is MEASURED rather than picked for feel. YouTube's
    /// `feeds/videos.xml` answers a client it has decided to throttle with a
    /// plain **404**, not a 429 — measured 2026-08-05, where the same channel
    /// id returned a full 200 body and then 404ed for the next twenty minutes
    /// across three different channels. A 404 is therefore not evidence that a
    /// channel is gone, and a health line that called it gone on first sight
    /// would libel a working feed within a day of shipping. Three consecutive
    /// misses spanning `quietDays` is a pattern; one is weather.
    private static let troubleAfter = 3

    /// Days without an answer before a feed that used to work says so. Feeds
    /// are polled many times a day, so three days is dozens of misses.
    private static let quietDays = 3

    // MARK: - The store

    /// Written from every concurrent feed fetch (`boundedGather` runs up to
    /// eight at once) and read from the main actor by the two screens, so
    /// every access below takes this. Writes are one small dictionary encode
    /// per fetch — cheap enough that a lock beats an actor's hop here.
    private static let lock = NSLock()
    private static var cache: [String: Record]?

    /// Caller must hold `lock`.
    private static func loaded() -> [String: Record] {
        if let cache { return cache }
        let decoded = (UserDefaults.standard.data(forKey: storeKey))
            .flatMap { try? JSONDecoder().decode([String: Record].self, from: $0) } ?? [:]
        cache = decoded
        return decoded
    }

    private static func all() -> [String: Record] {
        lock.lock(); defer { lock.unlock() }
        return loaded()
    }

    /// Caller must hold `lock`.
    private static func write(_ records: [String: Record]) {
        var records = records
        if records.count > cap {
            // Least-recently-answered out first. A record that never answered
            // sorts to the epoch, which is correct: it is the least worth
            // keeping.
            let doomed = records
                .sorted { ($0.value.successAt ?? .distantPast) < ($1.value.successAt ?? .distantPast) }
                .prefix(records.count - cap)
                .map(\.key)
            for key in doomed { records.removeValue(forKey: key) }
        }
        cache = records
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: storeKey)
        }
    }

    /// Drops one feed's record — called when a follow is removed, so a
    /// re-follow of the same URL starts clean rather than inheriting a
    /// failure streak the person just tried to fix.
    static func forget(_ url: String) {
        lock.lock(); defer { lock.unlock() }
        var records = loaded()
        guard records.removeValue(forKey: key(url)) != nil else { return }
        write(records)
    }

    /// Lowercased so two spellings of one feed share a record; trailing
    /// whitespace trimmed because a pasted URL carries it.
    private static func key(_ url: String) -> String {
        url.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    // MARK: - The fetch

    /// One feed GET, conditional when we hold validators for it, with the
    /// outcome recorded against the feed's health.
    ///
    /// The User-Agent matches `FeedFetch.data`'s (Reddit answers the default
    /// URLSession agent with a 429). RSS used to send no agent at all; sending
    /// one is strictly better and makes all five feed paths identical.
    ///
    /// `service` names the caller for the receipts screen. Every host here
    /// comes from the person's own input — a site they pasted, a Substack on
    /// its own domain, a podcast feed on whatever host the show publishes from
    /// — so the reach registry structurally cannot name it and the call site
    /// must (prd §289).
    static func fetch(_ url: URL, as service: String) async -> FeedFetchOutcome {
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (compatible; Casberi/1.0; +https://casberi.app)",
                         forHTTPHeaderField: "User-Agent")
        let record = all()[key(url.absoluteString)]
        // Validators only while the last full body is recent — see
        // `revalidateAfter`. A record with no `bodyAt` at all predates this
        // feature and revalidates once, which is the same thing.
        let bodyIsRecent = record?.bodyAt.map { $0.timeIntervalSinceNow > -revalidateAfter } ?? false
        if bodyIsRecent {
            if let etag = record?.etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
            if let modified = record?.lastModified {
                request.setValue(modified, forHTTPHeaderField: "If-Modified-Since")
            }
        }
        NetworkLedger.shared.record(request, as: service)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else {
            note(url, outcome: .failed(status: 0))
            return .failed(status: 0)
        }
        let outcome: FeedFetchOutcome
        switch http.statusCode {
        case 304:
            outcome = .notModified
        case 200..<300:
            outcome = .fresh(data)
        case let code:
            outcome = .failed(status: code)
        }
        note(url, outcome: outcome, response: http)
        return outcome
    }

    /// Records what a fetch came back as. Split out so the transport-failure
    /// path above and the status paths share one writer.
    private static func note(_ url: URL, outcome: FeedFetchOutcome,
                             response: HTTPURLResponse? = nil) {
        lock.lock(); defer { lock.unlock() }
        var records = loaded()
        var record = records[key(url.absoluteString)] ?? Record()
        switch outcome {
        case .fresh:
            record.successAt = .now
            record.bodyAt = .now
            record.failures = 0
            record.lastStatus = 200
            // Header names are case-insensitive on the wire and
            // `value(forHTTPHeaderField:)` matches that way, so one spelling
            // covers every server.
            record.etag = response?.value(forHTTPHeaderField: "ETag")
            record.lastModified = response?.value(forHTTPHeaderField: "Last-Modified")
        case .notModified:
            record.successAt = .now
            record.failures = 0
            record.lastStatus = 304
            // A 304 MAY carry a fresh ETag; when it doesn't, the one we sent
            // is still current, so it is kept rather than cleared.
            if let etag = response?.value(forHTTPHeaderField: "ETag") { record.etag = etag }
        case .failed(let status):
            record.failures += 1
            record.lastStatus = status
            // Validators are dropped on failure: a 404/410 usually means the
            // feed moved, and holding a dead feed's ETag would keep sending
            // it at whatever answers next.
            if status == 404 || status == 410 {
                record.etag = nil
                record.lastModified = nil
            }
        }
        records[key(url.absoluteString)] = record
        write(records)
    }

    // MARK: - Health

    /// What a feed's row should say about the feed itself, or nil when there
    /// is nothing to say — which is the common case and stays silent.
    ///
    /// A feed going quiet and a feed going DEAD look identical from the
    /// outside: both are rows that stop growing. The difference is whether the
    /// publisher is still answering, which only this store knows, and which no
    /// screen could see before. A dead follow (a blog that moved, a Substack
    /// that renamed, a channel deleted) otherwise sits in the list forever
    /// looking exactly like one that simply hasn't posted.
    ///
    /// Deliberately says only what was OBSERVED. It never claims the feed is
    /// gone — the app cannot know that from a status code (see `troubleAfter`
    /// on YouTube's throttle-404) — only that it has not answered, and for how
    /// long.
    static func trouble(for url: String) -> String? {
        guard let record = all()[key(url)], record.failures >= troubleAfter else { return nil }
        guard let successAt = record.successAt else {
            // Never once answered. This is the strong case: the address is
            // probably wrong, and saying so is more useful than a day count
            // that would read as "quiet" for something that never worked.
            return record.lastStatus == 404 || record.lastStatus == 410
                ? String(localized: "Hasn't answered once — check the address")
                : String(localized: "Hasn't answered yet")
        }
        let days = Int(-successAt.timeIntervalSinceNow / 86400)
        guard days >= quietDays else { return nil }
        return String(localized: "Hasn't answered in \(days) days")
    }

    /// The probe's view — every tracked feed's record, newest answer first.
    /// Counts and dates only; a validator is an opaque publisher token and
    /// there is no reason to print one.
    static func census() -> [(url: String, successAt: Date?, failures: Int,
                              lastStatus: Int, conditional: Bool)] {
        all().map {
            (url: $0.key, successAt: $0.value.successAt, failures: $0.value.failures,
             lastStatus: $0.value.lastStatus,
             conditional: $0.value.etag != nil || $0.value.lastModified != nil)
        }
        .sorted { ($0.successAt ?? .distantPast) > ($1.successAt ?? .distantPast) }
    }
}
