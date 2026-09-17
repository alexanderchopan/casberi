import Foundation
import os

/// Every read of Safe's Transaction Service goes through here, so a refused
/// read is never mistaken for an empty answer (prd §789).
///
/// **What was measured (2026-09-16).** `api.safe.global/tx-service/<seg>/…`
/// answered every keyless call with `429 {"error_msg":"Monthly quota
/// exceeded"}` and `x-ratelimit-limit: 5000`, on `eth`, `base` and `wc` alike,
/// from two unrelated networks (a home connection and a hosted fetcher). Safe
/// documents the unauthenticated tier as 2 RPS and 5,000 requests a month, and
/// calls it SHARED: every keyless caller in the world draws on one pool. A 429
/// is therefore not about this phone, and asking again before the reset only
/// adds to the receipts.
///
/// **What it was doing before.** Each reader mapped any non-200 to nil, and
/// nil was folded into "nothing": the Safe page drew "Up to date" in confirm
/// green over a pass in which not one read answered, the ask said "No Safe
/// wallets detected", and the address book, told "not a Safe" on every chain,
/// labelled a Safe a smart account for thirty days.
///
/// **The gate.** A 429 closes it until `x-ratelimit-reset` seconds from now
/// (bounded; fifteen minutes when the header is missing), and while it is
/// closed a read is answered `.throttled` without being sent. Each outcome is
/// an event with a sequence number, so a caller can take a `mark()` before a
/// pass and ask `health(since:)` after it — the one question every surface
/// needs answered before it may say "nothing".
///
/// The fold itself is `SafeServiceLedger` (its own Foundation-only file), so
/// `safe-gate-selftest.sh` compiles it whole and drives it without the network.
enum SafeServiceGate {

    /// One read's outcome. `missing` is a real answer (a 404: not a Safe, no
    /// such transaction); `throttled` and `unreachable` are not answers.
    enum Read {
        case ok(Any)
        case missing
        case throttled(until: Date?)
        case unreachable

        var json: Any? { if case .ok(let json) = self { return json }; return nil }
    }

    typealias Health = SafeServiceHealth
    typealias Ledger = SafeServiceLedger

    // MARK: - The live gate

    private static let defaultsKey = "wallet.safe.serviceGate.v1"

    /// Held only for the in-memory fold. The `UserDefaults` write happens
    /// after the lock is released, through `DefaultsWrite` (prd §721).
    private static let lock = OSAllocatedUnfairLock<Ledger>(initialState: {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              var saved = try? JSONDecoder().decode(Ledger.self, from: data)
        else { return Ledger() }
        // Sequence numbers are per process: a mark taken in this launch must
        // never see a previous launch's events as new.
        saved.seq = 0; saved.lastAnswerSeq = 0; saved.lastFailureSeq = 0; saved.lastThrottleSeq = 0
        return saved
    }())

    // MARK: - The key (prd §789's capacity half)

    /// Safe's API key — a JWT made at developer.safe.global with no IP and no
    /// domain restriction, because a phone has neither: those fields match a
    /// server's fixed address or a browser's `Origin`, and a native app sends
    /// no `Origin` at all, so an entry in either one refuses every install.
    /// The shape is `IngestSupport.alchemyKey`'s and
    /// `GitHubDeviceFlow.shippedClientID`'s — a read-only key over public
    /// data whose worst case is quota use.
    ///
    /// **EMPTY, and what was measured says why (2026-09-17).** A real key from
    /// that dashboard, sent as `Authorization: Bearer`, got the SAME answer as
    /// no key at all on `tx-service/eth/api/v1/about/`: `429`,
    /// `x-ratelimit-limit: 5000`, `x-ratelimit-remaining: 0`, and resets one
    /// second apart (175239 keyed, 175238 keyless) — the same pool, metered at
    /// the KEYLESS tier's 5,000. `api/v2` answered 429 too. So the key was
    /// served as anonymous, and whether any key lifts this refusal is
    /// unproven. Until it is, shipping one would be a claim the app cannot
    /// keep: the header is wired, the constant is not filled.
    ///
    /// Two readings are still open and are told apart by an invalid bearer: a
    /// 401 means auth is evaluated (so the key or its activation is the fault),
    /// the same 429 means the edge refuses before auth is read at all (so no
    /// key helps and only fewer reads do).
    ///
    /// Safe's documented quota is counted PER ACCOUNT rather than per key, so
    /// one shipped key would be one pool across every install, and a drained
    /// pool is recovered by rotating it there — never by adding a second key.
    private static let shippedKey = ""

    static var apiKey: String {
        #if DEBUG
        // `-safeKey "$(scripts/dev-keys.sh get safe)"` proves a key against the
        // real service before it ships in code — `GitHubDeviceFlow`'s
        // `-ghClientID` shape, for its reason.
        if let override = UserDefaults.standard.string(forKey: "safeKey"),
           !override.isEmpty { return override }
        #endif
        return shippedKey
    }

    /// The `Authorization` value, or nil when there is no key — so no header
    /// is sent at all rather than a `Bearer ` with nothing after it. §789
    /// measured that a bogus bearer changes nothing, which makes a malformed
    /// one indistinguishable from none; sending one would only turn a 401 we
    /// could diagnose into a quota refusal we could not.
    static var authorization: String? {
        let key = apiKey
        return key.isEmpty ? nil : "Bearer \(key)"
    }

    static func mark() -> UInt64 { lock.withLock { $0.seq } }

    static func health(since mark: UInt64) -> Health {
        lock.withLock { $0.health(since: mark) }
    }

    /// Nil while the service answers; the reopening time while it refuses.
    static func throttledUntil(now: Date = .now) -> Date? {
        lock.withLock { $0.isClosed(now: now) ? $0.throttledUntil : nil }
    }

    static func lastAnswerAt() -> Date? { lock.withLock { $0.lastAnswerAt } }

    /// GET `url` unless the gate is shut.
    static func get(_ url: String) async -> Read {
        let now = Date.now
        if let until = lock.withLock({ ledger -> Date? in
            guard ledger.isClosed(now: now) else { return nil }
            ledger.recordThrottle(until: nil)
            return ledger.throttledUntil
        }) {
            return .throttled(until: until)
        }
        let (json, status, response) = await IngestSupport.getJSONResponse(url, auth: authorization)
        let read: Read
        switch status {
        case 200 where json != nil: read = .ok(json!)
        case 404: read = .missing
        case 429:
            read = .throttled(until: Ledger.reopensAt(
                resetHeader: response?.value(forHTTPHeaderField: "x-ratelimit-reset"), now: .now))
        default: read = .unreachable
        }
        record(read)
        return read
    }

    /// `Read` carries the decoded body, which is not `Sendable`; the lock
    /// only needs which of the three it was.
    private enum Event: Sendable { case answer, throttle(Date?), failure }

    private static func record(_ read: Read) {
        let now = Date.now
        let event: Event
        switch read {
        case .ok, .missing: event = .answer
        case .throttled(let until): event = .throttle(until)
        case .unreachable: event = .failure
        }
        let persist: Data? = lock.withLock { ledger in
            let before = (ledger.throttledUntil, ledger.lastAnswerAt)
            switch event {
            case .answer: ledger.recordAnswer(now: now)
            case .throttle(let until): ledger.recordThrottle(until: until)
            case .failure: ledger.recordFailure()
            }
            // Write when the gate moved, or when the remembered answer time
            // is more than a minute stale — not once per read of a pass.
            let gateMoved = before.0 != ledger.throttledUntil
            let answerAged = ledger.lastAnswerAt.map { at in
                before.1.map { at.timeIntervalSince($0) > 60 } ?? true
            } ?? false
            guard gateMoved || answerAged else { return nil }
            return try? JSONEncoder().encode(ledger)
        }
        if let persist { DefaultsWrite.set(persist, forKey: defaultsKey) }
    }
}
