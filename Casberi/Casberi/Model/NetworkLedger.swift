import Foundation

/// Network receipts (prd §277, 2026-08-02) — the runtime half of §205.
///
/// `NetworkReach` is a CURATED registry: a hand-written list of what the app
/// *may* reach, kept honest by a static audit over host literals. This is the
/// other half — what it ACTUALLY reached, recorded as it happens, so the
/// privacy claim is checkable against behaviour rather than against a list
/// somebody remembered to update. A host that shows up here without a
/// registry entry is exactly the failure that shipped in build 214.
///
/// **Two deliberate limits, both stated in the screen's own copy — a receipt
/// that overstates its coverage is worse than no receipt.**
///
/// 1. **Hosts, counts and times — never payloads, never paths.** What was
///    asked is not recorded, because a log of that would be a more sensitive
///    artifact than the thing it audits.
/// 2. **It records where it can see, which is not everywhere.** Covered:
///    `IngestSupport`'s shared transport (~167 bridge call sites through one
///    funnel), `AgentAnswer` (the keyed agent — the request that carries
///    typed thought off the device), `LinkTitle`, and the ~27 bridges that
///    hold their own `URLSession` (RSS, Reddit, Spotify, Dropbox, the
///    exchanges, and the rest). NOT covered: images loaded straight into rows
///    as you scroll, the two WebSocket paths (`NostrRelay`,
///    `WalletConnectSocket`), and the WalletConnect SDK's own hosts, which
///    live in a vendored dependency and are invisible to source-level
///    instrumentation. Those are named in the registry and again on the
///    screen.
///
/// 3. **Some hosts can only be named by the caller.** A followed feed, a
///    Shopify store, a self-hosted PostHog, a saved link's own site: those
///    hosts come out of the person's own input, so no hand-written registry
///    could contain them and `NetworkReach.service(forHost:)` will never match
///    one. Those call sites pass their service name to `record(host:as:)`, and
///    the receipts screen falls back to it — see `Entry.service`. A host with
///    neither a registry entry nor an attribution is the real finding, which
///    is the whole point of keeping the "not on the list" section.
///
///    **This list shipped WRONG once** — it claimed "every bridge" while
///    those ~27 direct-`URLSession` bridges silently bypassed the funnel, so
///    a person with RSS and Reddit connected would have opened the screen and
///    seen neither. `scripts/receipts-coverage-audit.py` now fails the build
///    on a network call with no recorder above it, because the mistake is
///    invisible at runtime: the screen looks complete either way.
///
/// **Why aggregate rather than a per-request log.** A timestamped list of
/// every request is a behavioural timeline — when you woke up, when you
/// checked your wallet — sitting in cleartext `UserDefaults`. The receipt
/// people actually want is "which services did this app talk to, how often,
/// how recently", and that is what this keeps: one row per host with a count
/// and a first/last seen. Strictly less data, and it answers the question.
final class NetworkLedger: @unchecked Sendable {

    static let shared = NetworkLedger()

    struct Entry: Codable, Identifiable, Equatable {
        var host: String
        var count: Int
        var first: Date
        var last: Date
        /// Which service asked, when the CALLER knows and the registry
        /// structurally cannot (2026-08-03). A feed you follow, a Shopify
        /// store you named, your own self-hosted PostHog, a link you saved:
        /// the host comes out of your own input, so no hand-written list
        /// could ever have contained it. Without this the receipts screen
        /// read every such host as "not on the list — that's a bug, please
        /// report it", which is both wrong and alarming: `ethdaily.io` is a
        /// feed the person themselves added.
        ///
        /// Optional, and only a FALLBACK: `NetworkReach` stays the authority
        /// for every host it declares, and a name here is honoured only if
        /// the registry really carries a service by that name — so a caller
        /// can't launder an undisclosed host by inventing an attribution.
        /// Missing on rows written before this shipped, which decode as nil
        /// (`Optional` uses `decodeIfPresent`) and simply sort as they used to.
        var service: String?
        var id: String { host }
    }

    /// Rows older than this are dropped on the next write. A receipt is for
    /// checking recent behaviour, not for building a history.
    static let retention: TimeInterval = 7 * 86_400

    /// A ceiling so a pathological run can't grow the store without bound.
    /// Reached only if the app touches this many distinct hosts in a week.
    static let maxHosts = 300

    private let storeKey = "network.receipts.v1"
    private let lock = NSLock()
    private var entries: [String: Entry] = [:]
    private var lastFlush = Date.distantPast
    /// Writing JSON on every request would be wasteful on a sweep that makes
    /// dozens back to back; readers flush first, so nothing ever reads stale.
    private let flushInterval: TimeInterval = 5

    private init() {
        if let data = UserDefaults.standard.data(forKey: storeKey),
           let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = decoded
        }
    }

    // MARK: - Recording

    /// `service` names the caller for a host the registry can't declare in
    /// advance — see `Entry.service`. Pass it ONLY where the host comes from
    /// the person's own input (a feed, a store, a saved link); a host that is
    /// fixed in code belongs in `NetworkReach`, where the static audit can
    /// keep it honest.
    func record(host: String, as service: String? = nil) {
        let clean = host.lowercased()
        guard !clean.isEmpty else { return }
        let now = Date()
        lock.lock()
        if var existing = entries[clean] {
            existing.count += 1
            existing.last = now
            // Learn an attribution the first time one is offered, and don't
            // let a later unattributed call erase it: one host can be reached
            // by both an attributed path and a generic one (a saved link
            // whose site you also follow as a feed), and the name is more
            // useful than its absence.
            if existing.service == nil { existing.service = service }
            entries[clean] = existing
        } else {
            entries[clean] = Entry(host: clean, count: 1, first: now, last: now,
                                   service: service)
        }
        // Claim the flush HERE, while the lock is held. Advancing `lastFlush`
        // inside `flush()` instead let every concurrent request in a
        // foreground sweep observe `due == true` before any of them moved the
        // stamp — dozens of JSON encodes and `UserDefaults` writes where the
        // coalescing was supposed to give one.
        let due = now.timeIntervalSince(lastFlush) > flushInterval
        if due { lastFlush = now }
        lock.unlock()
        if due { flush() }
    }

    /// Convenience for the call sites that hold a request rather than a host.
    func record(_ request: URLRequest, as service: String? = nil) {
        if let host = request.url?.host() { record(host: host, as: service) }
    }

    /// …and for the ones that hand `URLSession` a bare URL.
    func record(_ url: URL, as service: String? = nil) {
        if let host = url.host() { record(host: host, as: service) }
    }

    // MARK: - Reading

    /// Every host reached inside the retention window, most recent first.
    func snapshot() -> [Entry] {
        flush()
        lock.lock()
        let all = Array(entries.values)
        lock.unlock()
        return all.sorted { $0.last > $1.last }
    }

    func forget() {
        lock.lock()
        entries = [:]
        lastFlush = Date()
        lock.unlock()
        UserDefaults.standard.removeObject(forKey: storeKey)
    }

    // MARK: - Persistence

    /// Prune, then persist. The `UserDefaults` write stays INSIDE the lock:
    /// outside it, two flushes racing could persist out of order and leave
    /// the older snapshot on disk.
    private func flush() {
        lock.lock()
        defer { lock.unlock() }
        let cutoff = Date().addingTimeInterval(-Self.retention)
        entries = entries.filter { $0.value.last > cutoff }
        if entries.count > Self.maxHosts {
            let keep = entries.values.sorted { $0.last > $1.last }.prefix(Self.maxHosts)
            entries = Dictionary(uniqueKeysWithValues: keep.map { ($0.host, $0) })
        }
        lastFlush = Date()
        if let payload = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(payload, forKey: storeKey)
        }
    }
}
