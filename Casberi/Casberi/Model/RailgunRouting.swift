import Foundation

/// **WHICH PRIVATE POCKET A TOKEN GOES TO, AND HOW MUCH MOVES (prd §1713
/// items 1 and 2, §1721).** Foundation-only, so `railgun-selftest.sh`
/// compiles it whole and unmodified.
///
/// - **The person picks (2026-11-27, user: "now that we added privacy
///   providers user should be able to have the choice"; was "routing is by
///   token", §1721).** On Ethereum Railgun takes every token, ETH (wrapped
///   to WETH by its relay adapter) and USDC included; Privacy Pools still
///   takes ETH and USDC, so for those both are offered. Off Ethereum,
///   nothing goes to Railgun.
/// - **The same $10 floor** as Privacy Pools: any typed amount moves in
///   at $10 worth or more at the price Casberi reads (§1727). A token with
///   no price has no floor to measure, so it is not offered in. Taking back
///   has no floor.
enum RailgunRouting {
    /// Ethereum's USDC, the one dollar Privacy Pools holds there.
    static let ethereumUSDC = "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"
    static let ethereumChainID = 1
    static let floorUSD: Double = 10

    /// Native ETH, as the Railgun engine names it.
    static let eth = "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"

    static func goesToRailgun(symbol: String, contract: String?, chainId: Int) -> Bool {
        guard chainId == ethereumChainID else { return false }
        if contract == nil || contract?.isEmpty == true { return symbol.uppercased() == "ETH" }
        return true
    }

    /// Whether `units` of a token is worth `floorUSD` or more at `price`.
    /// A token with no price has no floor to measure: never.
    static func meetsFloor(units: String, decimals: Int, price: Double?, floorUSD: Double) -> Bool {
        guard let price, price > 0, let held = Decimal(string: units), held > 0 else { return false }
        let whole = NSDecimalNumber(decimal: held / pow(Decimal(10), decimals)).doubleValue
        return whole * price >= floorUSD * 0.999_999
    }

    /// The smallest 1, 2 or 5 times a power of ten at or above `x`.
    static func nice(_ x: Double) -> Double {
        guard x > 0 else { return 0 }
        let p = pow(10, floor(log10(x)))
        for m in [1.0, 2.0, 5.0, 10.0] where m * p >= x * 0.999_999 { return m * p }
        return 10 * p
    }

    // MARK: - Broadcasters (prd §1721 item 3, §1723)

    /// A relay's socket: `wss` to a declared domain or a host under it (Waku's
    /// peer exchange names the operator's other relays, `seed-a`,
    /// `support-1`…), on its Waku port (8000) or 443, and nothing else — no
    /// user, no other scheme, no lookalike domain.
    static func allowsSocket(_ url: URL, declared: [String]) -> Bool {
        guard url.scheme == "wss", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443 || url.port == 8000,
              let host = url.host?.lowercased(), !host.isEmpty else { return false }
        return declared.contains { d in
            let d = d.lowercased()
            return host == d || host.hasSuffix("." + d)
        }
    }

    /// Which token pays the broadcaster: the token being sent if a
    /// broadcaster takes it, else the first taken token the wallet can spend
    /// any of, in the broadcasters' own order. Nil when the wallet holds none:
    /// the send cannot pay its way (Move offers a little ETH for fees).
    static func feeToken(sending token: String, taken: [String], spendable: [String: Decimal]) -> String? {
        let has = { (t: String) in (spendable[t.lowercased()] ?? 0) > 0 }
        if let same = taken.first(where: { $0.lowercased() == token.lowercased() }), has(same) { return same }
        return taken.first(where: has)
    }

    /// Whether the wallet covers the send and its fee: in one token, both;
    /// in two, each its own.
    static func covers(amount: Decimal, of token: String, fee: Decimal, in feeToken: String,
                       spendable: [String: Decimal]) -> Bool {
        let a = spendable[token.lowercased()] ?? 0
        if token.lowercased() == feeToken.lowercased() { return amount + fee <= a }
        return amount <= a && fee <= (spendable[feeToken.lowercased()] ?? 0)
    }
}
