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
/// A scan starts from a tap (`scan(_:)`: the Scan control, Scan again and
/// the `-nymisScan` probe) or on its own ONCE, for your own account only,
/// when its first transaction lands (`scanOnActivity`, from `WalletIngest`;
/// prd §1744, §1744a), never when the account is made, because a new address
/// has nothing to find. A wallet you follow is scanned only on a tap: Nymis's
/// public API allows 50 fresh scans a day across everyone and 3 per IP.
/// `nymis-selftest.sh` holds both caller lists.
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
        /// Requests spent on this scan, retries included (Nymis's budget is
        /// 30). Optional so a scan saved before §1701d still decodes.
        var requests: Int?
        /// Started on its own (§1744), not by a tap: its end does not buzz.
        var auto: Bool?
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
    /// with the same key always reattaches (Nymis: 25 minutes, §1701d).
    static let giveUp: TimeInterval = NymisScan.maxAge
    /// Nymis: while summaries are pending, every 5 seconds for at most 30.
    static let summaryEvery: Duration = .seconds(5)
    static let summaryPolls = 6
    /// The address a scan has started on its own for (§1744a: your account
    /// only): never again
    /// on its own, whatever it read; a tap scans again.
    static let autoKey = "nymis.auto.v1"
    private(set) var autoAsked: Set<String> = []

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
        if let data = defaults.data(forKey: Self.autoKey),
           let saved = try? JSONDecoder().decode([String].self, from: data) {
            autoAsked = Set(saved)
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

    /// When the running scan of this address was asked for; the row's line
    /// says how long it takes from this.
    func started(_ address: String) -> Date? { running[NymisScan.key(address)]?.started }

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

    /// The wallets a transfer or swap just landed at (§1744): your own
    /// account's first one scans it.
    func scanOnActivity(_ addresses: Set<String>) {
        guard let mine = YourAccountKey.address,
              addresses.contains(where: { WalletWatch.sameAddress($0, mine) }) else { return }
        scanOnItsOwn(mine)
    }

    /// Once per address, never over a reading or a running scan, never past
    /// Nymis's limit (a refusal waits for a tap, and marks no row), never in
    /// the demo, and in DEBUG only with `-liveChains YES`, so a probe that
    /// follows a wallet spends none of Nymis's public quota.
    private func scanOnItsOwn(_ address: String) {
        guard Self.scansOnItsOwn, NymisScan.isEVMAddress(address) else { return }
        let key = NymisScan.key(address)
        guard readings[key] == nil, running[key] == nil, !autoAsked.contains(key) else { return }
        if let until = busyUntil, until > .now { return }
        autoAsked.insert(key)
        if let data = try? JSONEncoder().encode(autoAsked.sorted()) { DefaultsWrite.set(data, forKey: Self.autoKey) }
        failed.remove(key)
        busy.remove(key)
        running[key] = Running(started: .now, idempotencyKey: UUID().uuidString.lowercased(), auto: true)
        saveRunning()
        #if DEBUG
        NSLog("nymis| %@ | on its own", key)
        #endif
        follow()
    }

    static var scansOnItsOwn: Bool {
        if DemoMode.isActive { return false }
        #if DEBUG
        return !ChainReadsOff.isOn
        #else
        return true
        #endif
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
        if Date.now.timeIntervalSince(run.started) > Self.giveUp
            || (run.requests ?? 0) >= NymisScan.requestBudget {
            finish(key, nil)
            return nil
        }
        // Every request counts against the scan's budget, a retry included.
        running[key]?.requests = (run.requests ?? 0) + 1
        saveRunning()
        let next = Duration.seconds(NymisScan.pollInterval(age: Date.now.timeIntervalSince(run.started)))
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
            return next
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
            return next
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
        let auto = running[key]?.auto == true
        running[key] = nil
        tokens[key] = nil
        saveRunning()
        if let reading {
            readings[key] = reading
            failed.remove(key)
            saveReadings()
            // A scan nobody tapped for lands quietly (§1744).
            if !auto { DSHaptic.success() }
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
            scanID: "11111111-1111-4111-8111-111111111111",
            gives: ["related addresses", "exchanges", "identity"],
            facts: [.init(label: "Related addresses", value: "2, 1 named", kind: "related"),
                    .init(label: "Exchanges and payments", value: "Coinbase, MoonPay"),
                    .init(label: "Identity", value: "X, ENS"),
                    .init(label: "Active", value: "Mar 2023 to Nov 2026")],
            related: [.init(address: "0x0000000000000000000000000000000000000b0b", name: "quill",
                            platform: "Polymarket", transfers: 21),
                      .init(address: "0x0000000000000000000000000000000000000c0c", name: nil,
                            platform: nil, transfers: 4)])
        saveReadings()
    }
    #endif
}
