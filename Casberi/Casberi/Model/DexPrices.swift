import Foundation

/// A keyless price for a token that trades ONLY in a DEX pool, read off
/// GeckoTerminal's multi-token endpoint (2026-09-28). The last backstop in
/// `WalletIngest.backstopPrices`, after DeFiLlama, and only on the chains in
/// `network` — the ones where a person's real money sits in tokens neither
/// Zerion nor DeFiLlama will value.
///
/// MEASURED on the user's own wallet (accountless.eth, Robinhood Chain): it
/// held 869,602 MUSEGOD, about $185 at $0.000213 in a SushiSwap pool with
/// $67K of reserve, and Zerion's `/positions` left it out altogether — Zerion's
/// own chart for the wallet fell from $123.94 to $3.06 the same day. DeFiLlama
/// answered `coins: {}` for all fourteen tokens there. The crown showed eight
/// dollars.
///
/// **A pool price is only as honest as the pool is deep.** Anyone can seed a
/// pool with a dollar and quote an airdrop at any price, so a price is taken
/// only when the token's pools hold `reserveFloor` or more, and a holding is
/// valued only when it is no more than `depthShare` of that reserve — past
/// that, the figure is money you could not sell for. Measured on the same
/// wallet: BERRY and sushicat sit in pools under a dollar, and are dropped.
enum DexPrices {

    /// Alchemy network id → GeckoTerminal network id. A chain belongs here only
    /// when real holdings on it are known to go unvalued upstream — each entry
    /// is a request on every holdings pass for anyone following the chain.
    static let network: [String: String] = [
        // `robinhood` — measured 2026-09-28: MUSEGOD, USDG, DOG and HUMANITY
        // on chain 4663 all answered with `price_usd` and
        // `total_reserve_in_usd`.
        "robinhood-mainnet": "robinhood",
    ]

    /// Below this much pool reserve (USD), a quoted price is not believed.
    static let reserveFloor: Double = 10_000

    /// The most of a token's pool reserve one holding may be valued at.
    static let depthShare: Double = 0.25

    struct Priced {
        let price: Double
        let reserveUSD: Double

        /// Whether `amount` of the token may be counted at this price.
        func admits(amount: Double) -> Bool {
            let usd = amount * price
            return usd.isFinite && reserveUSD >= DexPrices.reserveFloor
                && usd <= reserveUSD * DexPrices.depthShare
        }
    }

    /// Prices the given `(network, contract)` tokens, keyed `"network|contract"`
    /// with the contract exactly as given (the key `DefiLlamaPrices.prices`
    /// uses). A token on a chain not in `network`, or one GeckoTerminal has no
    /// price for, is absent. `[:]` on total failure, so the caller's candidates
    /// stand as they were.
    static func prices(for mints: [(network: String, contract: String)]) async -> [String: Priced] {
        // GeckoTerminal lowercases every address it returns.
        var byChain: [String: [String: String]] = [:]   // gecko net → lower → key
        for m in mints {
            guard let net = network[m.network], m.contract.hasPrefix("0x") else { continue }
            byChain[net, default: [:]][m.contract.lowercased()] = "\(m.network)|\(m.contract)"
        }
        var out: [String: Priced] = [:]
        for (net, keys) in byChain {
            // 30 addresses a call is the endpoint's own limit, and the keyless
            // tier is 30 calls a minute, so a spam-heavy wallet is capped at
            // three calls a pass (in API order, like the DeFiLlama cap).
            let addresses = Array(keys.keys).sorted()
            for chunk in stride(from: 0, to: min(addresses.count, 90), by: 30).map({
                Array(addresses[$0..<min($0 + 30, addresses.count)])
            }) {
                let url = "https://api.geckoterminal.com/api/v2/networks/\(net)/tokens/multi/"
                    + chunk.joined(separator: ",")
                guard let root = await IngestSupport.getJSON(url) as? [String: Any],
                      let data = root["data"] as? [[String: Any]] else { continue }
                for row in data {
                    guard let a = row["attributes"] as? [String: Any],
                          let address = (a["address"] as? String)?.lowercased(),
                          let key = keys[address],
                          let price = number(a["price_usd"]), price > 0,
                          let reserve = number(a["total_reserve_in_usd"]) else { continue }
                    out[key] = Priced(price: price, reserveUSD: reserve)
                }
            }
        }
        return out
    }

    /// GeckoTerminal sends every figure as a decimal STRING, some fifty digits
    /// long; `Double(_:)` reads those, and a non-finite result is refused.
    private static func number(_ raw: Any?) -> Double? {
        if let s = raw as? String, let d = Double(s), d.isFinite { return d }
        if let d = raw as? Double, d.isFinite { return d }
        return nil
    }
}
