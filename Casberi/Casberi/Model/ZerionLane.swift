import Foundation

/// **ONE ZERION REQUEST AT A TIME, AND A REFUSAL IS WAITED OUT (prd §934).**
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
/// Two rules, both here so every Zerion read gets them by going through
/// `dataRows`:
///
/// - **The lane.** Requests are queued FIFO and run one at a time, with
///   `spacing` between them. A `Task` chain, not an actor method — an actor
///   method that awaits inside is re-entrant and serialises nothing.
/// - **The wait.** A `429` is retried after `Retry-After` (seconds, capped
///   at `maxWait`) or a doubling backoff from `firstWait`, `attempts` times.
///   Any other status is refused at once. `delay(attempt:retryAfter:)` is
///   pure so `zerion-lane-selftest.sh` can hold it to that.
actor ZerionLane {
    static let shared = ZerionLane()

    /// The gap kept between two requests. MEASURED 2026-09-26 off the
    /// response headers: the shipped key is `ratelimit-org-tier: demo`,
    /// `ratelimit-org-second-limit: 1` and `ratelimit-org-day-limit: 300`,
    /// for the whole org — every install together. So one a second, with a
    /// little to spare, and the day's pool watched (`exhaustedUntil`).
    static let spacing: TimeInterval = 1.05
    /// How many times a 429 is asked again before it is a refusal.
    static let attempts = 3
    static let firstWait: TimeInterval = 1
    static let maxWait: TimeInterval = 8

    private var tail: Task<Void, Never>?
    private var lastStarted: Date = .distantPast
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

    /// Run `op` after everything queued before it, `spacing` after the last.
    func run<T: Sendable>(_ op: @Sendable @escaping () async -> T) async -> T {
        let previous = tail
        let task = Task<T, Never> { [weak self] in
            await previous?.value
            if let self { await self.pace() }
            return await op()
        }
        tail = Task { _ = await task.value }
        return await task.value
    }

    private func pace() async {
        let gap = Self.spacing - Date().timeIntervalSince(lastStarted)
        if gap > 0 { try? await Task.sleep(nanoseconds: UInt64(gap * 1_000_000_000)) }
        lastStarted = Date()
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
