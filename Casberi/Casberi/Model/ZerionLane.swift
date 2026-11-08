import Foundation

/// **THREE ZERION REQUESTS IN FLIGHT, SPACED, HOLDINGS FIRST, AND A REFUSAL
/// IS WAITED OUT (prd §934, §1722).**
///
/// The shared key is one pool for every install (§826), and the ingest was
/// its own worst client: `boundedGather(maxConcurrent: 4)` fired four
/// wallets' positions reads at once, each refused filtered call retried
/// unfiltered at once, and the transactions sweep did the same beside it.
/// Zerion answered `429` — measured 2026-09-26, every fake wallet every
/// time and the real one about half the time — and a 429 was `nil`, which
/// downstream means "unreached": the wallet quietly fell to Alchemy or
/// stood empty, so one wallet read "$1.1M across 507 tokens" and, a launch
/// later, "$26K across 14 tokens".
///
/// §934 answered with ONE request at a time, paced for the demo tier's one
/// a second. The key moved to the Developer tier on 2026-10-20 (three a
/// second, 2,000 a day), and the lane kept the old pace — which, with every
/// Zerion read riding Tor at 6–45s (§1495), meant three wallets' holdings
/// waited behind three wallets' transactions, one Tor round trip after
/// another (user, 2026-11-07: "even after refreshing take about ten seconds
/// to be accurate"). So, §1722:
///
/// - **The lane.** Up to `concurrent` requests in flight, their STARTS at
///   least `spacing` apart, so no second ever sees more than the tier
///   allows. Waiters are FIFO, except that a request marked `ahead` — a
///   holdings read, the number the person is looking at — goes before every
///   plain waiter (a transactions sweep). An actor whose methods await is
///   re-entrant, so the admission is explicit: a slot is taken or a
///   continuation parked BEFORE any await, and the next start time is
///   reserved the same way.
/// - **The wait.** A `429` is retried after `Retry-After` (seconds, capped
///   at `maxWait`) or a doubling backoff from `firstWait`, `attempts` times.
///   Any other status is refused at once. `delay(attempt:retryAfter:)` is
///   pure so `zerion-lane-selftest.sh` can hold it to that.
actor ZerionLane {
    static let shared = ZerionLane()

    /// How many requests may be on the wire at once. The tier allows three
    /// a second; three in flight over Tor is three wallets read together.
    static let concurrent = 3
    /// The gap kept between two STARTS: 2.5 a second at most, under the
    /// Developer tier's `ratelimit-org-second-limit: 3` with room to spare.
    /// The day's pool is read off the headers (`exhaustedUntil`), never
    /// assumed.
    static let spacing: TimeInterval = 0.4
    /// How many times a 429 is asked again before it is a refusal.
    static let attempts = 3
    static let firstWait: TimeInterval = 1
    static let maxWait: TimeInterval = 8

    private var inFlight = 0
    private var waiting: [(ahead: Bool, resume: CheckedContinuation<Void, Never>)] = []
    /// The earliest moment the next request may start.
    private var nextStart: Date = .distantPast
    /// When the day's pool ran dry (`ratelimit-org-day-remaining: 0` on a
    /// refusal), until the reset the headers name: every read until then is
    /// refused HERE, at no cost, and the wallet falls to Alchemy (§826).
    private var exhaustedUntil: Date?

    /// Whether the day's pool is known to be empty right now.
    var isExhausted: Bool {
        guard let until = exhaustedUntil else { return false }
        if until > Date() { return true }
        exhaustedUntil = nil
        return false
    }

    /// Learn from a response's rate-limit headers (case-insensitive, as
    /// `HTTPURLResponse` serves them).
    func note(dayRemaining: String?, dayReset: String?, status: Int) {
        if let until = Self.exhaustion(status: status, dayRemaining: dayRemaining, dayReset: dayReset) {
            exhaustedUntil = until
        }
    }

    /// The moment the pool refills, when a REFUSED response says the day's
    /// remaining count is zero — or nil for anything else. A `200` with zero
    /// remaining is the last one that got through, not a refusal; the reset
    /// is seconds from `now`, capped at a day so a garbage header cannot
    /// close Zerion for a week.
    nonisolated static func exhaustion(status: Int, dayRemaining: String?, dayReset: String?,
                                       now: Date = Date()) -> Date? {
        guard status == 429,
              let remaining = dayRemaining.flatMap({ Int($0.trimmingCharacters(in: .whitespaces)) }),
              remaining <= 0,
              let reset = dayReset.flatMap({ Double($0.trimmingCharacters(in: .whitespaces)) }),
              reset > 0 else { return nil }
        return now.addingTimeInterval(min(reset, 86_400))
    }

    /// Run `op` once a slot is free, `spacing` after the last start. An
    /// `ahead` request takes the next free slot before every plain waiter.
    func run<T: Sendable>(ahead: Bool = false, _ op: @Sendable @escaping () async -> T) async -> T {
        await admit(ahead: ahead)
        await pace()
        let result = await op()
        release()
        return result
    }

    /// Takes a slot now, or parks until `release` hands one over. Nothing
    /// awaits between the check and the write, so two callers can never
    /// both see the same free slot.
    private func admit(ahead: Bool) async {
        if inFlight < Self.concurrent, waiting.isEmpty {
            inFlight += 1
            return
        }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            if ahead, let i = waiting.firstIndex(where: { !$0.ahead }) {
                waiting.insert((ahead: true, resume: c), at: i)
            } else {
                waiting.append((ahead: ahead, resume: c))
            }
        }
    }

    /// Frees a slot and, if anyone is parked, hands it straight to the first
    /// waiter — the slot is theirs before they wake, so a newcomer cannot
    /// slip in ahead of them.
    private func release() {
        inFlight -= 1
        guard inFlight < Self.concurrent, !waiting.isEmpty else { return }
        inFlight += 1
        waiting.removeFirst().resume.resume()
    }

    /// Reserves the next start time synchronously, then sleeps until it.
    private func pace() async {
        let slot = max(Date(), nextStart)
        nextStart = slot.addingTimeInterval(Self.spacing)
        let wait = slot.timeIntervalSinceNow
        if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
    }

    /// How long to wait before attempt `attempt` (1-based) is retried, or nil
    /// when the attempts are spent. `retryAfter` is the header's raw value
    /// (`Retry-After`, or Zerion's own `ratelimit-reset` — seconds until the
    /// per-second window opens); only a plain number of seconds is honoured
    /// (an HTTP-date is ignored), and every wait is capped at `maxWait`.
    nonisolated static func delay(attempt: Int, retryAfter: String?) -> TimeInterval? {
        guard attempt >= 1, attempt < attempts else { return nil }
        if let raw = retryAfter?.trimmingCharacters(in: .whitespaces),
           let seconds = Double(raw), seconds >= 0 {
            return min(seconds, maxWait)
        }
        return min(firstWait * pow(2, Double(attempt - 1)), maxWait)
    }
}
