import Foundation

/// **A 429 FROM ALCHEMY STOPS EVERY ALCHEMY REQUEST, NOT ONE (2026-10-20).**
///
/// The key is one pool for every install, and its per-second cap is what
/// refuses: Alchemy reported 10% of an hour's requests rate limited. Each
/// request used to retry ITSELF (0.5s, then 1.5s), so with four in flight a
/// hot key took up to three times the traffic exactly when it was over, and
/// every retry was another refusal on the dashboard.
///
/// Now the first 429 brakes the whole phone: every Alchemy request waits out
/// `pause(strikes:)` (2s, doubling to `maxPause`), then they are let go
/// `releaseGap` apart instead of all at once. A success clears the strikes.
/// `IngestSupport.send` is the one transport every Alchemy read rides, so it
/// asks `admission()` before sending and `note(status:)` after.
///
/// A brake is "not now", never "refused": no caller learns a chain is
/// unserved from it (`WalletIngest.RefusedNetworks`, prd §827b), because the
/// request still goes, later. `alchemy-brake-selftest.sh` holds the schedule.
actor AlchemyBrake {
    static let shared = AlchemyBrake()

    /// The gap kept between requests let go after a pause.
    static let releaseGap: TimeInterval = 0.25
    /// The longest a run of 429s may hold the brake.
    static let maxPause: TimeInterval = 16

    private var pausedUntil: Date = .distantPast
    private var nextRelease: Date = .distantPast
    private var strikes = 0

    /// Whether `host` is one of Alchemy's.
    nonisolated static func brakes(host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "alchemy.com" || host.hasSuffix(".alchemy.com")
    }

    /// How long a run of `strikes` 429s holds the brake: 2s, 4s, 8s, then
    /// `maxPause`. Zero strikes is no pause.
    nonisolated static func pause(strikes: Int) -> TimeInterval {
        guard strikes >= 1 else { return 0 }
        return min(maxPause, pow(2, Double(min(strikes, 10))))
    }

    /// The wait before one request may go, claiming its place in the release.
    /// Zero when the brake is off and nothing is queued behind a pause.
    func admission(now: Date = Date()) -> TimeInterval {
        guard pausedUntil > now || nextRelease > now else { return 0 }
        let slot = max(pausedUntil, nextRelease, now)
        nextRelease = slot.addingTimeInterval(Self.releaseGap)
        return slot.timeIntervalSince(now)
    }

    /// Learn from one response: a 429 brakes (longer each time in a row), a
    /// success clears the run. Anything else is not the brake's business.
    func note(status: Int, now: Date = Date()) {
        if status == 429 {
            strikes += 1
            pausedUntil = max(pausedUntil, now.addingTimeInterval(Self.pause(strikes: strikes)))
        } else if (200...299).contains(status) {
            strikes = 0
        }
    }

    /// Wait for this request's turn. The caller then sends.
    func waitForTurn() async {
        let wait = admission()
        if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
    }
}
