import Foundation
import Observation

/// **THE SCANS AND WHAT THEY READ (prd §1701, §1701a, §1701c).** `NymisScan` is the
/// shape; this is the clock and the shelf: a tap asks Nymis's API for a scan,
/// a poll follows it while the app is open, and the reading is kept on this
/// phone (Nymis keeps a result 30 minutes). Device-only, never synced: what a
/// scan says about an address is the person's to keep.
///
/// One scan at a time: Nymis runs one public scan at once, so a second tap
/// waits for the first rather than earning a refusal. A refusal (429) says
/// when to try again, and the row says that time.
///
/// The scan token lives in memory only, never on disk or in a log. A scan a
/// past launch started is picked up by asking again with the SAME
/// idempotency key, which Nymis answers with the same scan for 30 minutes.
///
/// Nothing here starts a scan on its own. `scan(_:)` is called from the
/// Scan control and the `-nymisScan` probe, nowhere else
/// (`nymis-selftest.sh` holds that).
@MainActor @Observable
final class NymisScans {
    static let shared = NymisScans()

    enum State: Equatable {
        case none
        /// Asked for; `waiting` while another scan runs first.
        case scanning(waiting: Bool)
        case done(NymisScan.Reading)
        /// Nymis said to wait until this time; the reading before, if any,
        /// still stands.
        case busy(Date, NymisScan.Reading?)
        /// The last scan failed; the reading before it, if any, still stands.
        case failed(NymisScan.Reading?)
    }

    private(set) var readings: [String: NymisScan.Reading] = [:]
    /// Address key → the scan asked for.
    private(set) var running: [String: Running] = [:]
    private(set) var failed: Set<String> = []
    /// Nymis's limits are its own, for every address: past a 429 nothing is
    /// asked before this time.
    private(set) var busyUntil: Date?
    /// The addresses whose tap met that refusal.
    private(set) var busy: Set<String> = []

    struct Running: Codable, Equatable {
        let started: Date
        /// One UUIDv4 per scan the person asked for, reused for every retry.
        let idempotencyKey: String
        var scanID: String?
    }

    /// Address key → scan token. Memory only (Nymis: keep it out of logs,
    /// crash reports and analytics).
    @ObservationIgnored private var tokens: [String: String] = [:]
    @ObservationIgnored private var poll: Task<Void, Never>?
    /// Address key → the poll waiting on Nymis's summaries (§1701c).
    @ObservationIgnored private var summaryFollow: [String: Task<Void, Never>] = [:]

    static let readingsKey = "nymis.readings.v2"
    /// v1 held the scraped page's shape (§1701 item 5), which no longer decodes.
    static let retiredKeys = ["nymis.readings.v1", "nymis.running.v1"]
    static let runningKey = "nymis.running.v2"
    /// Past this a scan that never finished is called failed rather than
    /// polled forever; under Nymis's 30-minute reuse window, so asking again
    /// with the same key always reattaches.
    static let giveUp: TimeInterval = 15 * 60
    /// Nymis: poll every 10–15 seconds.
    static let pollEvery: Duration = .seconds(12)
    /// Nymis: while summaries are pending, every 5 seconds for at most 30.
    static let summaryEvery: Duration = .seconds(5)
    static let summaryPolls = 6

    private init() {
        let defaults = UserDefaults.standard
        for key in Self.retiredKeys where defaults.object(forKey: key) != nil {
            DefaultsWrite.remove(key)
        }
        if let data = defaults.data(forKey: Self.readingsKey),
           let saved = try? JSONDecoder().decode([String: NymisScan.Reading].self, from: data) {
            readings = saved
        }
        if let data = defaults.data(forKey: Self.runningKey),
           let saved = try? JSONDecoder().decode([String: Running].self, from: data) {
            running = saved.filter { Date.now.timeIntervalSince($0.value.started) < Self.giveUp }
        }
    }

    func state(_ address: String) -> State {
        let key = NymisScan.key(address)
        if running[key] != nil { return .scanning(waiting: isWaiting(key)) }
        if busy.contains(key), let until = busyUntil, until > .now { return .busy(until, readings[key]) }
        if failed.contains(key) { return .failed(readings[key]) }
        if let reading = readings[key] { return .done(reading) }
        return .none
    }

    func reading(_ address: String) -> NymisScan.Reading? { readings[NymisScan.key(address)] }

    /// The Scan control: ask Nymis for a scan of this address and follow it.
    func scan(_ address: String) {
        guard NymisScan.isEVMAddress(address) else { return }
        let key = NymisScan.key(address)
        guard running[key] == nil else { return }
        failed.remove(key)
        if let until = busyUntil, until > .now {
            busy.insert(key)
            return
        }
        busy.remove(key)
        running[key] = Running(started: .now, idempotencyKey: UUID().uuidString.lowercased())
        saveRunning()
        follow()
    }

    /// Picks up scans a past launch started, when Threats is on screen.
    func resume() {
        if !running.isEmpty { follow() }
    }

    func forget(_ address: String) {
        let key = NymisScan.key(address)
        summaryFollow[key]?.cancel()
        summaryFollow[key] = nil
        readings[key] = nil
        failed.remove(key)
        busy.remove(key)
        saveReadings()
    }

    /// The scan that goes next: the one Nymis is running, else the oldest
    /// asked for.
    private var current: String? {
        running.first { $0.value.scanID != nil }?.key
            ?? running.min { $0.value.started < $1.value.started }?.key
    }

    private func isWaiting(_ key: String) -> Bool {
        guard let current else { return false }
        return current != key
    }

    private func follow() {
        guard poll == nil else { return }
        poll = Task { [weak self] in
            while let self, !self.running.isEmpty, !Task.isCancelled {
                // A scan just asked for is polled after Nymis's interval; one
                // that just ended lets the next one in line ask at once.
                if let wait = await self.round() { try? await Task.sleep(for: wait) }
            }
            self?.poll = nil
        }
    }

    /// One request for the current scan; how long to wait before the next.
    private func round() async -> Duration? {
        guard let key = current, let run = running[key] else { return nil }
        if Date.now.timeIntervalSince(run.started) > Self.giveUp {
            finish(key, nil)
            return nil
        }
        let polling = run.scanID != nil && tokens[key] != nil
        let request: URLRequest?
        if let id = run.scanID, let token = tokens[key] {
            request = NymisScan.pollRequest(scanID: id, token: token)
        } else {
            // First ask, or a scan a past launch started (its token was never
            // kept): the same key reattaches to the same scan.
            request = NymisScan.createRequest(address: key, idempotencyKey: run.idempotencyKey)
        }
        guard let request else { finish(key, nil); return nil }
        let reply = await IngestSupport.sendRequest(request)
        let answer = NymisScan.answer(status: reply?.1.statusCode ?? 0,
                                      retryAfter: reply?.1.value(forHTTPHeaderField: "Retry-After"),
                                      body: reply?.0, address: key, now: .now)
        guard running[key] != nil else { return nil }
        switch answer {
        case .processing(let id, let token):
            // A create reply must hand both, or there is nothing to poll.
            if !polling, id == nil || token == nil { finish(key, nil); return nil }
            if let token { tokens[key] = token }
            if let id, running[key]?.scanID != id { running[key]?.scanID = id; saveRunning() }
            return Self.pollEvery
        case .read(var reading, let summaryPending):
            if reading.scanID == nil { reading.scanID = run.scanID }
            // The findings stand at once; Nymis's summaries follow on the
            // same scan's poll (§1701c). A cached reply hands no token, so
            // whatever summaries it carried are all there are.
            let token = tokens[key]
            finish(key, reading)
            if summaryPending, let id = reading.scanID, let token {
                followSummaries(key, scanID: id, token: token, scannedAt: reading.scannedAt)
            }
            return nil
        case .busy(let until) where polling:
            // A scan Nymis is already running is not dropped for a poll
            // limit: the next poll waits until Nymis says.
            return .seconds(max(until.timeIntervalSinceNow, 1))
        case .busy(let until):
            busyUntil = until
            // Every scan in line meets the same limit.
            for waiting in running.keys { busy.insert(waiting); tokens[waiting] = nil }
            running.removeAll()
            saveRunning()
            #if DEBUG
            NSLog("nymis| busy | until %@", until.formatted(.iso8601))
            #endif
            return nil
        case .retry:
            return Self.pollEvery
        case .failed:
            finish(key, nil)
            return nil
        }
    }

    /// Nymis writes its summaries after scoring (§1701c): the same scan is
    /// polled every 5 s for at most 30 s, stopping at `ready` or
    /// `unavailable`. Read-only, and never asks for another scan. The token
    /// stays in this task's memory.
    private func followSummaries(_ key: String, scanID: String, token: String, scannedAt: Date) {
        summaryFollow[key]?.cancel()
        summaryFollow[key] = Task { [weak self] in
            for _ in 0..<Self.summaryPolls {
                try? await Task.sleep(for: Self.summaryEvery)
                guard let self, !Task.isCancelled,
                      self.readings[key]?.scannedAt == scannedAt,
                      let request = NymisScan.pollRequest(scanID: scanID, token: token) else { return }
                let reply = await IngestSupport.sendRequest(request)
                let answer = NymisScan.answer(status: reply?.1.statusCode ?? 0,
                                              retryAfter: reply?.1.value(forHTTPHeaderField: "Retry-After"),
                                              body: reply?.0, address: key, now: .now)
                switch answer {
                case .read(let later, let pending):
                    if pending { continue }
                    // A new scan of the address in the meantime wins.
                    guard let now = self.readings[key], now.scannedAt == scannedAt else { return }
                    self.readings[key] = now.adding(summariesOf: later)
                    self.saveReadings()
                    #if DEBUG
                    NSLog("nymis| %@ | summaries | %@", key,
                          later.overview == nil && later.financial == nil ? "unavailable" : "ready")
                    #endif
                    self.summaryFollow[key] = nil
                    return
                case .retry, .processing:
                    continue
                case .busy, .failed:
                    self.summaryFollow[key] = nil
                    return
                }
            }
            self?.summaryFollow[key] = nil
        }
    }

    private func finish(_ key: String, _ reading: NymisScan.Reading?) {
        running[key] = nil
        tokens[key] = nil
        saveRunning()
        if let reading {
            readings[key] = reading
            failed.remove(key)
            saveReadings()
            DSHaptic.success()
        } else {
            failed.insert(key)
        }
        #if DEBUG
        NSLog("nymis| %@ | %@ | %@", key, reading == nil ? "failed" : "read",
              reading.flatMap(NymisScan.rowLine) ?? "-")
        #endif
    }

    private func saveReadings() {
        guard let data = try? JSONEncoder().encode(readings) else { return }
        DefaultsWrite.set(data, forKey: Self.readingsKey)
    }

    private func saveRunning() {
        guard let data = try? JSONEncoder().encode(running) else { return }
        DefaultsWrite.set(data, forKey: Self.runningKey)
    }

    #if DEBUG
    /// `-nymisSample YES`: a made-up reading for an address, so the row and
    /// the sheet draw on a simulator with no scan (never the person's own).
    func seedSample(_ address: String) {
        let key = NymisScan.key(address)
        readings[key] = NymisScan.Reading(
            address: key,
            groups: [
                .init(name: "Identity", findings: [
                    .init(id: "sample-ens", title: "Linked to an ENS name", severity: "high",
                          explanation: "The address resolves to quillmark.eth, which names a public profile on X."),
                ]),
                .init(name: "Financial", findings: [
                    .init(id: "sample-cex", title: "Funded from Coinbase", severity: "medium",
                          explanation: "Inbound transfers from Coinbase tie the address to an account that passed identity checks."),
                    .init(id: "sample-related", title: "Related addresses", severity: "medium",
                          explanation: "Two addresses send to and receive from this one on a repeating pattern."),
                ]),
                .init(name: "Behavioral", findings: [
                    .init(id: "sample-hours", title: "Active at the same hours", severity: "low",
                          explanation: "Most transactions land between 8 and 11 in the evening, Central European time."),
                ]),
            ],
            partial: false, scannedAt: .now.addingTimeInterval(-3600),
            overview: "This address is publicly linked to quillmark.eth, with a profile on X. Two related addresses send to and receive from it on a repeating pattern.",
            financial: "Inbound transfers from Coinbase create a KYC-adjacent attribution point.",
            scanID: "11111111-1111-4111-8111-111111111111")
        saveReadings()
    }
    #endif
}
