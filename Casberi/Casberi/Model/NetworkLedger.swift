import Foundation

/// Network receipts (prd §276, 2026-08-02) — the runtime half of §205.
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
/// 2. **It records where it can see, which is not everywhere.** The
///    instrumented paths are `IngestSupport`'s shared transport (every bridge
///    — ~167 call sites through one funnel), `AgentAnswer` (the keyed agent,
///    the request that carries typed thought off the device) and `LinkTitle`
///    (a saved link's page fetch). NOT covered: images loaded straight into
///    rows, the two WebSocket paths (`NostrRelay`, `WalletConnectSocket`),
///    and the WalletConnect SDK's own hosts, which are inside a vendored
///    dependency and invisible to source-level instrumentation. Those are
///    named in the registry and named again on the screen.
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

    func record(host: String) {
        let clean = host.lowercased()
        guard !clean.isEmpty else { return }
        let now = Date()
        lock.lock()
        if var existing = entries[clean] {
            existing.count += 1
            existing.last = now
            entries[clean] = existing
        } else {
            entries[clean] = Entry(host: clean, count: 1, first: now, last: now)
        }
        let due = now.timeIntervalSince(lastFlush) > flushInterval
        lock.unlock()
        if due { flush() }
    }

    /// Convenience for the call sites that hold a request rather than a host.
    func record(_ request: URLRequest) {
        if let host = request.url?.host() { record(host: host) }
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

    private func flush() {
        lock.lock()
        let cutoff = Date().addingTimeInterval(-Self.retention)
        entries = entries.filter { $0.value.last > cutoff }
        if entries.count > Self.maxHosts {
            let keep = entries.values.sorted { $0.last > $1.last }.prefix(Self.maxHosts)
            entries = Dictionary(uniqueKeysWithValues: keep.map { ($0.host, $0) })
        }
        let payload = try? JSONEncoder().encode(entries)
        lastFlush = Date()
        lock.unlock()
        if let payload { UserDefaults.standard.set(payload, forKey: storeKey) }
    }
}
