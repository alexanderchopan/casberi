import Foundation

/// WHAT EACH HOLDING DID TODAY (prd §1090), for the Holdings box's heat map.
///
/// Markets' box colours each watched name by its day (§1081); the Wallet's
/// holdings were grey blocks with a share each, so the one screen about your
/// own money said less about today than the one about money you only watch.
/// Zerion already sends a position's day change (`changes.percent_1d`) on the
/// `/positions` read the Wallet makes anyway, so this costs no request: the
/// read notes it here, keyed by the cleaned symbol the box's tiles are keyed
/// by, and the box colours a tile when its symbol has a fresh move.
///
/// **Stale is absent, never old.** A day move read eight hours ago describes
/// a different day (§83), so a move older than `freshFor` is not returned and
/// the tile goes back to the plain fill. Kept in defaults only so a cold
/// launch inside the holdings window (which reads nothing) still colours.
///
/// The pure half (`merge`, `isFresh`, `tally`) is Foundation-only, compiled
/// whole by `scripts/wallet-makeover-selftest.sh`.
enum HoldingMoves {
    struct Read: Equatable, Codable {
        let symbol: String
        let usd: Double
        let change: Double
    }

    /// One wallet's last read: the moves it held, and when.
    struct Note: Equatable, Codable {
        let at: Date
        let reads: [Read]
    }

    static let freshFor: TimeInterval = 6 * 3600

    /// One move per symbol, weighted by the dollars behind each read: the
    /// same token on two chains, or in two wallets, is one tile.
    static func merge(_ reads: [Read]) -> [String: Double] {
        var weight: [String: Double] = [:]
        var sum: [String: Double] = [:]
        for r in reads where r.change.isFinite && r.usd.isFinite && r.usd > 0 {
            let k = key(r.symbol)
            guard !k.isEmpty else { continue }
            weight[k, default: 0] += r.usd
            sum[k, default: 0] += r.usd * r.change
        }
        return sum.reduce(into: [:]) { out, pair in
            if let w = weight[pair.key], w > 0 { out[pair.key] = pair.value / w }
        }
    }

    static func key(_ symbol: String) -> String {
        symbol.trimmingCharacters(in: .whitespaces).uppercased()
    }

    static func isFresh(at: Date, now: Date) -> Bool {
        at <= now.addingTimeInterval(60) && now.timeIntervalSince(at) <= freshFor
    }

    /// "2 up, 1 down" over the tiles the box draws; a move that rounds to
    /// zero is neither (§83).
    static func tally(_ moves: [Double]) -> (up: Int, down: Int) {
        moves.reduce(into: (0, 0)) { t, m in
            if m >= 0.0005 { t.0 += 1 } else if m <= -0.0005 { t.1 += 1 }
        }
    }

    /// The demo reaches nothing (§483): its four holdings move by fixed,
    /// plausible amounts, so the box draws as the real one does.
    static let demo: [String: Double] = ["ETH": 0.021, "USDC": 0.0, "DEGEN": -0.064, "SOL": 0.038]

    /// The moves to draw: every wallet's FRESH note merged, so a read of one
    /// wallet (an approvals pass, a single-wallet refresh) never wipes what
    /// another wallet's read said, and a token in both is weighted by the
    /// combined dollars.
    static func combine(_ notes: [String: Note], now: Date) -> [String: Double] {
        merge(notes.values.filter { isFresh(at: $0.at, now: now) }.flatMap(\.reads))
    }

    /// Replaces the notes of exactly the wallets this read answered for — a
    /// holding a wallet sold is not still moving — and keeps the rest.
    static func replacing(_ notes: [String: Note], owners: [String], with reads: [(owner: String, read: Read)],
                          now: Date) -> [String: Note] {
        var out = notes
        for owner in owners {
            let k = owner.lowercased()
            out[k] = Note(at: now, reads: reads.filter { $0.owner.lowercased() == k }.map(\.read))
        }
        return out
    }

    // MARK: - The store

    private static let defaultsKey = "wallet.holdingMoves.v2"
    private static let lock = NSLock()
    private static var cached: [String: Note]? = nil

    private static func loaded() -> [String: Note] {
        if let cached { return cached }
        let stored = UserDefaults.standard.data(forKey: defaultsKey)
            .flatMap { try? JSONDecoder().decode([String: Note].self, from: $0) } ?? [:]
        cached = stored
        return stored
    }

    /// What a holdings read noted, for the wallets it answered for.
    static func note(owners: [String], _ reads: [(owner: String, read: Read)], now: Date = .now) {
        guard !owners.isEmpty else { return }
        lock.lock()
        let next = replacing(loaded(), owners: owners, with: reads, now: now)
        cached = next
        lock.unlock()
        // The defaults write happens OUTSIDE the lock (prd §721).
        if let data = try? JSONEncoder().encode(next) {
            DefaultsWrite.set(data, forKey: defaultsKey)
        }
    }

    /// The moves to draw now; empty when every note is stale.
    static func current(now: Date = .now) -> [String: Double] {
        lock.lock(); defer { lock.unlock() }
        return combine(loaded(), now: now)
    }
}
