import Foundation

/// **ONE SPEND LIMIT, IN ALL, ACROSS EVERY NETWORK (prd §1569, user:
/// "yes do option 2").**
///
/// The chain cannot keep this total. Each network holds its own copy of the
/// account, and Smart Sessions on Base cannot see what was spent on Ethereum;
/// within one network ETH and the dollar are two counters, with no price
/// between them (§1447 item 14). So the per-network sessions stay as they are
/// (each allowing the whole amount of each coin) as the CEILING, and the
/// phone keeps the total: the session key lives on this phone alone, so every
/// send made under the limit goes through here. `YourAccountChain.sessionSend`
/// asks `fits` before Face ID, and a send over the total goes to both keys,
/// exactly as one the chain refuses.
///
/// Stated, not assumed: the total holds as long as this app does. A phone or
/// an app taken over can still reach the ceiling, each coin's amount on each
/// network.
///
/// Pure arithmetic over plain numbers, so `spend-total-selftest.sh` runs it
/// with nothing else; the ledger's one store is at the bottom.
enum SpendTotal {
    /// One send on the session key: where, what it was worth in dollars when
    /// it went, and when (unix seconds).
    struct Spend: Codable, Equatable {
        let chainId: Int
        let dollars: Double
        let at: Int
    }

    /// The span the total counts in, `from` up to (not including) `until`.
    struct Period: Codable, Equatable {
        let from: Int
        let until: Int
    }

    /// The period that holds `now`: of each network's window holding now,
    /// the one that began first. One switch sets every network in the same
    /// minute, so their windows line up; a network put on later (Finish, or
    /// a network opened after Create) counts in the first one's periods.
    static func period(current: [Period], at now: Int) -> Period? {
        current.filter { $0.from <= now && now < $0.until }.min { $0.from < $1.from }
    }

    /// What was spent in `period`, on every network.
    static func spent(_ spends: [Spend], in period: Period) -> Double {
        spends.filter { period.from <= $0.at && $0.at < period.until }.reduce(0) { $0 + $1.dollars }
    }

    /// What is left of `cap` in `period`, never below zero.
    static func left(cap: Double, spends: [Spend], in period: Period) -> Double {
        max(cap - spent(spends, in: period), 0)
    }

    /// Whether `dollars` more fits under `cap` in `period`. A worth that
    /// could not be read never fits: both keys sign it.
    static func fits(_ dollars: Double?, cap: Double, spends: [Spend], in period: Period) -> Bool {
        guard let dollars, dollars.isFinite, dollars >= 0, cap > 0 else { return false }
        // A cent's float slack, so $100 of $100 fits.
        return spent(spends, in: period) + dollars <= cap + 0.000_001
    }

    /// What a send is worth: the network's dollar at a dollar (six
    /// decimals), ETH at `ethPrice`. nil when ETH moves and no price was
    /// read, or an amount does not read as a number.
    static func worth(dollarUnits: [String], wei: [String], ethPrice: Double?) -> Double? {
        var total = 0.0
        for units in dollarUnits {
            guard let n = Double(units), n >= 0 else { return nil }
            total += n / 1e6
        }
        for amount in wei {
            guard let n = Double(amount), n >= 0 else { return nil }
            guard n == 0 || (ethPrice.map { $0.isFinite && $0 > 0 } ?? false) else { return nil }
            total += n / 1e18 * (ethPrice ?? 0)
        }
        return total.isFinite ? total : nil
    }

    /// The ledger with one more send, keeping only what a period of
    /// `keepSeconds` could still count.
    static func recording(_ spend: Spend, to spends: [Spend], keepSeconds: Int) -> [Spend] {
        (spends + [spend]).filter { $0.at > spend.at - keepSeconds }
    }

    /// The longest period the switch offers (a month, `LimitPeriod.month`),
    /// with a day to spare.
    static let keepSeconds = 31 * 24 * 60 * 60

    // MARK: - The ledger, on this phone

    private static let key = "yourAccount.spendTotal"

    static var spends: [Spend] {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode([Spend].self, from: $0) } ?? []
    }

    static func record(_ spend: Spend) {
        let next = recording(spend, to: spends, keepSeconds: keepSeconds)
        if let data = try? JSONEncoder().encode(next) { UserDefaults.standard.set(data, forKey: key) }
    }

    /// Off on every network: nothing left to count.
    static func forget() { UserDefaults.standard.removeObject(forKey: key) }
}
