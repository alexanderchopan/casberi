import Foundation

/// **THE WALLET OPENS ON ITS LAST READING (prd §1593, user: "it's better but
/// still takes a few seconds, maybe bc of Tor").** Every wallet read goes
/// through Tor (§1495), and a cold launch waits for Tor to connect and then
/// for the read itself, so the Wallet stood on "Reading" for seconds over
/// money it had shown an hour ago. The last live reading of each scope is
/// kept here and drawn at once, stamped with when it was read (§825's "as
/// of"), until the live read replaces it.
///
/// Kept per scope (All, Yours, Following, one wallet, one app) and only for
/// the same watched wallets: a follow or an unfollow changes what All is, so
/// a reading over another set is never drawn. Never in the demo.
enum WalletLastReading {
    static let key = "wallet.lastReading.v1"
    /// The scopes kept, newest first; the rest are dropped.
    static let keep = 8

    struct Entry: Codable {
        let wallets: String
        let at: Date
        let portfolio: WalletPortfolio
    }

    /// The watched wallets a reading stands on, order and case aside.
    static func signature(_ wallets: [String]) -> String {
        wallets.map { $0.lowercased() }.sorted().joined(separator: ",")
    }

    static func slot(_ scope: String?) -> String { scope ?? "all" }

    /// The last live reading of `scope` over these wallets, stamped with when
    /// it was read (or the older stamp it already carried).
    @MainActor static func reading(scope: String?, wallets: [String]) -> WalletPortfolio? {
        reading(scope: scope, wallets: wallets, in: stored())
    }

    static func reading(scope: String?, wallets: [String], in map: [String: Entry]) -> WalletPortfolio? {
        guard let entry = map[slot(scope)], entry.wallets == signature(wallets) else { return nil }
        var portfolio = entry.portfolio
        portfolio.asOf = min(portfolio.asOf ?? entry.at, entry.at)
        return portfolio
    }

    /// Keeps a live reading of `scope`, dropping the oldest past `keep`.
    static func remembering(_ portfolio: WalletPortfolio, scope: String?, wallets: [String],
                            at: Date = Date(), in map: [String: Entry]) -> [String: Entry] {
        var next = map
        next[slot(scope)] = Entry(wallets: signature(wallets), at: at, portfolio: portfolio)
        if next.count > keep {
            let gone = next.sorted { $0.value.at > $1.value.at }.dropFirst(keep).map(\.key)
            for slot in gone { next[slot] = nil }
        }
        return next
    }

    @MainActor static func remember(_ portfolio: WalletPortfolio, scope: String?, wallets: [String]) {
        let next = remembering(portfolio, scope: scope, wallets: wallets, in: stored())
        memo = next
        if let data = try? JSONEncoder().encode(next) { DefaultsWrite.set(data, forKey: key) }
    }

    /// Read once a process, then held: the Wallet asks on every scope change.
    @MainActor private static var memo: [String: Entry]?

    @MainActor static func stored() -> [String: Entry] {
        if let memo { return memo }
        let read = UserDefaults.standard.data(forKey: key)
            .flatMap { try? JSONDecoder().decode([String: Entry].self, from: $0) } ?? [:]
        memo = read
        return read
    }
}
