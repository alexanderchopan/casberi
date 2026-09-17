import Foundation

/// The pure half of `SafeServiceGate` (prd §789): what a sequence of Safe
/// Transaction Service outcomes says about a pass, and when a 429 reopens.
///
/// Foundation-only and free of the network, the lock and `UserDefaults`, so
/// `scripts/safe-gate-selftest.sh` compiles this file whole and unmodified.

/// What a pass could say about itself.
enum SafeServiceHealth: Equatable {
    /// Every read answered, or was served from a cache of an answer.
    case answered
    /// At least one read was refused for the shared quota — the pass is
    /// incomplete, whatever else answered.
    case throttled(until: Date?)
    /// Reads failed and none answered.
    case unreachable
}

struct SafeServiceLedger: Codable, Equatable {
    var seq: UInt64 = 0
    var lastAnswerSeq: UInt64 = 0
    var lastFailureSeq: UInt64 = 0
    var lastThrottleSeq: UInt64 = 0
    /// Persisted: the gate stays shut across a relaunch.
    var throttledUntil: Date?
    /// Persisted: when the service last answered anything, so a surface
    /// drawing a remembered queue can say how old it is.
    var lastAnswerAt: Date?

    /// Longest the gate is believed. The measured reset was 54 hours; a
    /// header claiming more than a month is not trusted for longer.
    static let maxClosed: TimeInterval = 32 * 86_400
    /// When a 429 carries no reset header — ONE MINUTE since 2026-09-17, and
    /// the change is the whole reason to read this line (prd §789b).
    ///
    /// Fifteen minutes was right for the transaction service, whose 429 is a
    /// MONTHLY pool running dry: it always sends `x-ratelimit-reset`, so this
    /// default only ever caught a malformed one, and waiting long was the
    /// polite guess. The reads now go to Safe's Client Gateway, which sends
    /// NO rate-limit header at all and whose 429 is a per-IP BURST —
    /// measured refilling within ~20 seconds (§789b point 4). Fifteen
    /// minutes there would take a two-second blip and turn it into a quarter
    /// hour of a room saying it cannot see the queue.
    ///
    /// One minute is three times the measured recovery, so it is a bound
    /// rather than a race, and a sequential pass never reaches the cap that
    /// produces this 429 in the first place.
    static let defaultClosed: TimeInterval = 60

    func isClosed(now: Date) -> Bool {
        guard let throttledUntil else { return false }
        return throttledUntil > now
    }

    /// When a 429 with this `x-ratelimit-reset` value reopens the gate.
    static func reopensAt(resetHeader: String?, now: Date) -> Date {
        let seconds = resetHeader
            .flatMap { TimeInterval($0.trimmingCharacters(in: .whitespaces)) }
            .map { min(max($0, 1), maxClosed) } ?? defaultClosed
        return now.addingTimeInterval(seconds)
    }

    mutating func recordAnswer(now: Date) {
        seq += 1
        lastAnswerSeq = seq
        lastAnswerAt = now
        throttledUntil = nil
    }

    mutating func recordFailure() {
        seq += 1
        lastFailureSeq = seq
    }

    /// A 429, or a read the closed gate answered without sending.
    mutating func recordThrottle(until: Date?) {
        seq += 1
        lastThrottleSeq = seq
        if let until { throttledUntil = until }
    }

    func health(since mark: UInt64) -> SafeServiceHealth {
        if lastThrottleSeq > mark { return .throttled(until: throttledUntil) }
        if lastFailureSeq > mark && lastAnswerSeq <= mark { return .unreachable }
        return .answered
    }
}
