import Foundation

/// **A DEVNET'S ASSETS, VALUED AT MAINNET PRICES (prd §922).**
///
/// A devnet token is a symbol and a quantity — no rate to the chain's own
/// coin, no price — so nothing on the chain can size one asset against
/// another. But a devnet's assets MIRROR mainnet's: vUSDC is a dollar, test
/// ETH is ETH, PEPE is PEPE. So the Holdings figure values them at mainnet
/// prices and SAYS SO ("at mainnet prices"), which is a stated convention and
/// not a claim about what a test token is worth (§83).
///
/// **A symbol with no mainnet counterpart is never guessed.** `mainnetSymbol`
/// answers nil for it, the figure keeps it out of the pack and counts it under
/// the drawing, and the row below still states its amount.
///
/// Prices come from the keyless DeFiLlama source the wallet already reads
/// (`DefiLlamaPrices`, host `coins.llama.fi` in `NetworkReach`), by CoinGecko
/// id, and are held for half an hour: a room mount asks at most once per
/// window, whatever it redraws.
enum MainnetPrices {
    /// Mainnet symbol → CoinGecko id. Small on purpose: the assets a devnet
    /// mirrors are the ones people mint there, and an id that is not here
    /// prices nothing rather than something wrong.
    static let ids: [String: String] = [
        "eth": "ethereum", "weth": "ethereum", "steth": "staked-ether",
        "wsteth": "wrapped-steth", "btc": "bitcoin", "wbtc": "wrapped-bitcoin",
        "cbbtc": "coinbase-wrapped-btc",
        "usdc": "usd-coin", "usdt": "tether", "dai": "dai", "usds": "usds",
        "eurc": "euro-coin", "pyusd": "paypal-usd",
        "pepe": "pepe", "shib": "shiba-inu", "doge": "dogecoin",
        "link": "chainlink", "uni": "uniswap", "aave": "aave", "ens": "ethereum-name-service",
        "matic": "matic-network", "pol": "matic-network", "op": "optimism",
        "arb": "arbitrum", "wld": "worldcoin-wld", "sol": "solana",
    ]

    /// The mainnet symbol a devnet symbol mirrors, or nil. "vUSDC" → "usdc",
    /// "test ETH" → "eth", "tDAI" → "dai"; a symbol that is itself known
    /// answers as it is, so "USDT" is never read as a test "SDT".
    static func mainnetSymbol(_ raw: String) -> String? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !s.isEmpty else { return nil }
        if ids[s] != nil { return s }
        for prefix in ["test ", "test-", "test", "v", "t"] where s.hasPrefix(prefix) {
            let rest = String(s.dropFirst(prefix.count))
            if ids[rest] != nil { return rest }
        }
        return nil
    }

    /// USD per unit, keyed by MAINNET symbol, for every symbol given that
    /// mirrors one. A symbol that mirrors nothing is simply absent.
    static func prices(for symbols: [String]) async -> [String: Double] {
        let mainnet = Set(symbols.compactMap(mainnetSymbol))
        guard !mainnet.isEmpty else { return [:] }
        let wanted = mainnet.compactMap { symbol in ids[symbol].map { (symbol: symbol, id: $0) } }
        // **THE DEMO REACHES NOTHING (§217, `demo-selftest.py`'s gate list).**
        // A poured demo values its invented holdings at invented prices — the
        // whole room is "Not your things" — and never asks a host.
        let fresh = DemoMode.isActive
            ? demoPrices
            : await MainnetPriceCache.shared.prices(ids: wanted.map(\.id))
        var out: [String: Double] = [:]
        for pair in wanted {
            if let price = fresh[pair.id] { out[pair.symbol] = price }
        }
        return out
    }
}

extension MainnetPrices {
    /// The demo's prices, by CoinGecko id — round, invented, and only ever
    /// drawn under the demo's own marking (§864).
    static let demoPrices: [String: Double] = [
        "ethereum": 2_600, "staked-ether": 2_600, "wrapped-steth": 3_100,
        "bitcoin": 64_000, "wrapped-bitcoin": 64_000, "coinbase-wrapped-btc": 64_000,
        "usd-coin": 1, "tether": 1, "dai": 1, "usds": 1, "euro-coin": 1.08, "paypal-usd": 1,
        "pepe": 0.000_01, "shiba-inu": 0.000_02, "dogecoin": 0.12,
        "chainlink": 14, "uniswap": 8, "aave": 160, "ethereum-name-service": 20,
        "matic-network": 0.4, "optimism": 1.6, "arbitrum": 0.6, "worldcoin-wld": 1.2, "solana": 150,
    ]
}

/// The half-hour memory behind `MainnetPrices`, an actor so two rooms
/// mounting at once ask once.
actor MainnetPriceCache {
    static let shared = MainnetPriceCache()
    static let ttl: TimeInterval = 30 * 60

    private var known: [String: (price: Double, at: Date)] = [:]
    private var inFlight: Task<[String: Double], Never>?

    func prices(ids: [String]) async -> [String: Double] {
        let now = Date()
        let stale = ids.filter { id in
            guard let hit = known[id] else { return true }
            return now.timeIntervalSince(hit.at) > Self.ttl
        }
        if !stale.isEmpty {
            if let inFlight {
                _ = await inFlight.value
            } else {
                let task = Task { await DefiLlamaPrices.prices(coingeckoIDs: stale) }
                inFlight = task
                let fetched = await task.value
                inFlight = nil
                for (id, price) in fetched { known[id] = (price, now) }
            }
        }
        var out: [String: Double] = [:]
        for id in ids { if let hit = known[id] { out[id] = hit.price } }
        return out
    }
}
