import Foundation

/// A token on the watchlist (prd §1632), by DeFiLlama's coin id: a
/// CoinGecko coin (`coingecko:hyperliquid`) or a contract on a chain
/// (`base:0x…`). The id is what every read asks for; the symbol and name are
/// what the search answered when you watched it.
struct WatchedToken: Codable, Equatable, Identifiable, Hashable, Sendable {
    let id: String
    let symbol: String
    let name: String
}

/// **THE WATCHLIST'S RULES (prd §1632), pure.** The list's order, the price
/// window, the day's change in words, and the three keyless answers it reads:
/// CoinGecko's search, DeFiLlama's prices and change, DeFiLlama's chart.
/// Foundation only, so `watchlist-selftest.sh` compiles it alone.
///
/// **Keyless, never Zerion (amends §1632 item 8).** The ruling allowed one
/// batched Zerion call; measured 2026-10-31, DeFiLlama answers a price, the
/// day's change and a chart for a CoinGecko id and for a contract alike, and
/// CoinGecko's search answers a name or a ticker, both with no key. So the
/// watchlist spends nothing from the one Zerion budget every install shares.
enum WatchlistRules {

    /// A price is read at most once in this window (§216's ten minutes).
    static let window: TimeInterval = 10 * 60
    /// DeFiLlama's own confidence, under which a price is not shown (§83):
    /// the line `DefiLlamaPrices` already draws.
    static let confidenceFloor = 0.9
    /// What the search offers at most.
    static let searchCap = 8

    /// A price and the day's change in PERCENT (DeFiLlama's unit), nil when
    /// the change did not answer.
    struct Quote: Equatable, Sendable {
        let price: Double
        let change: Double?
    }

    // MARK: - The list

    /// Watching adds to the end: rows keep the order you added them in.
    static func adding(_ token: WatchedToken, to list: [WatchedToken]) -> [WatchedToken] {
        list.contains { $0.id == token.id } ? list : list + [token]
    }

    static func removing(_ id: String, from list: [WatchedToken]) -> [WatchedToken] {
        list.filter { $0.id != id }
    }

    static func movingToTop(_ id: String, in list: [WatchedToken]) -> [WatchedToken] {
        guard let i = list.firstIndex(where: { $0.id == id }), i > 0 else { return list }
        var out = list
        out.insert(out.remove(at: i), at: 0)
        return out
    }

    /// Whether the last reading is past the window, or there is none.
    static func isStale(readAt: Date?, now: Date) -> Bool {
        guard let readAt else { return true }
        return now.timeIntervalSince(readAt) >= window
    }

    // MARK: - The day's change

    enum Tone: Equatable { case up, down, flat }

    /// "+2.1%", "−4.6%", or "0.0%" with no sign when it rounds to zero (§83:
    /// a change that rounds to zero has no sign or colour).
    static func change(_ percent: Double) -> (words: String, tone: Tone) {
        let tenths = (percent * 10).rounded()
        guard tenths != 0, percent.isFinite else { return ("0.0%", .flat) }
        let magnitude = String(format: "%.1f%%", abs(tenths) / 10)
        return tenths > 0 ? ("+" + magnitude, .up) : ("\u{2212}" + magnitude, .down)
    }

    /// The token that moved most today, either way, for Home's door: never
    /// an average (a basket nobody holds), and nil when every change rounds
    /// to zero or none has answered. A tie goes to the earlier on the list.
    static func biggestMover(_ tokens: [WatchedToken], quotes: [String: Quote])
        -> (symbol: String, change: (words: String, tone: Tone))? {
        var best: (symbol: String, magnitude: Double, percent: Double)?
        for t in tokens {
            guard let p = quotes[t.id]?.change, p.isFinite, change(p).tone != .flat else { continue }
            if best == nil || abs(p) > best!.magnitude { best = (t.symbol, abs(p), p) }
        }
        return best.map { ($0.symbol, change($0.percent)) }
    }

    // MARK: - Where a token lives

    /// DeFiLlama chain key → the network's name, for a contract's line.
    static let chains: [(key: String, name: String)] = [
        ("ethereum", "Ethereum"), ("base", "Base"), ("arbitrum", "Arbitrum"),
        ("optimism", "Optimism"), ("polygon", "Polygon"), ("bsc", "BNB Chain"),
        ("hyperliquid", "HyperEVM"), ("robinhood", "Robinhood"), ("wc", "World Chain"),
        ("solana", "Solana"),
    ]

    /// The network a contract id names, nil for a CoinGecko coin.
    static func network(of id: String) -> String? {
        guard let colon = id.firstIndex(of: ":") else { return nil }
        let key = String(id[..<colon])
        return chains.first { $0.key == key }?.name
    }

    /// The line under a token's name when you hold none: its network for a
    /// contract, the coin's own name for a coin.
    static func line(for token: WatchedToken) -> String {
        network(of: token.id) ?? token.name
    }

    // MARK: - A pasted contract

    static func isEVMAddress(_ s: String) -> Bool {
        s.count == 42 && s.hasPrefix("0x") && s.dropFirst(2).allSatisfy(\.isHexDigit)
    }

    static func isSolanaMint(_ s: String) -> Bool {
        let base58 = Set("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
        return (32...44).contains(s.count) && s.allSatisfy { base58.contains($0) }
    }

    /// The ids a pasted address could be, every chain asked at once; empty
    /// when the words are not an address. An EVM address is lowercased, a
    /// Solana mint never (its case IS the address).
    static func contractCandidates(_ raw: String) -> [String] {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if isEVMAddress(s) {
            return chains.filter { $0.key != "solana" }.map { "\($0.key):\(s.lowercased())" }
        }
        if isSolanaMint(s) { return ["solana:\(s)"] }
        return []
    }

    // MARK: - A holding of yours

    /// The ids a holding of yours is watched under, best first (prd §1632
    /// item 4): the coin's CoinGecko id when the symbol names a known coin
    /// (ETH on any chain is one coin), then each contract the account holds
    /// it at, on a chain DeFiLlama reads, in the order given. Empty when
    /// neither applies, and the tray asks the search by symbol.
    ///
    /// A ticker alone is not enough: CoinGecko's search offers only ranked
    /// coins, so a holding with no market-cap rank was never found and its
    /// plus did nothing (2026-11-01).
    ///
    /// `contracts` are `HiddenTokens.contractKey`s (`<network>:<contract|native>`,
    /// lowercased), so a Solana mint, whose case is its address, is taken
    /// from `route` (`solana:<mint>`, case kept) or not at all.
    static func holdingIDs(symbol: String, contracts: [String], route: String?,
                           coingecko: [String: String], llamaChains: [String: String]) -> [String] {
        var out: [String] = []
        if let coin = coingecko[symbol.lowercased()] { out.append("coingecko:\(coin)") }
        for key in contracts {
            let parts = key.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2, parts[1] != "native", let chain = llamaChains[parts[0]] else { continue }
            let id: String
            if chain == "solana" {
                guard let route, route.lowercased() == "solana:\(parts[1].lowercased())" else { continue }
                id = route
            } else {
                guard isEVMAddress(parts[1]) else { continue }
                id = "\(chain):\(parts[1].lowercased())"
            }
            if !out.contains(id) { out.append(id) }
        }
        return out
    }

    /// DeFiLlama chain key → CoinGecko's asset platform, for asking which
    /// coin a contract is (measured 2026-10-31 against `/asset_platforms` by
    /// chain id; Robinhood's MUSEGOD answered `musegod`).
    static let coingeckoPlatform: [String: String] = [
        "ethereum": "ethereum", "base": "base", "arbitrum": "arbitrum-one",
        "optimism": "optimistic-ethereum", "polygon": "polygon-pos",
        "hyperliquid": "hyperevm", "wc": "world-chain", "robinhood": "robinhood",
        "monad": "monad", "solana": "solana",
    ]

    /// `api.coingecko.com/api/v3/coins/<platform>/contract/<address>` for a
    /// contract id, nil for a coin or a chain CoinGecko is not asked on.
    ///
    /// **A holding DeFiLlama cannot price by its contract is found BY its
    /// contract (2026-11-01, user: "trying to click on musegod and it says no
    /// price").** DeFiLlama prices nothing on Robinhood by contract, so the
    /// plus fell to the ticker search, and only an exact symbol match was
    /// taken; this asks which coin the contract you hold IS.
    static func coinByContractPath(_ id: String) -> String? {
        let parts = id.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let platform = coingeckoPlatform[parts[0]] else { return nil }
        return "coins/\(platform)/contract/\(parts[1])"
    }

    /// CoinGecko's coin for a contract: its id, as a watchlist id.
    static func parseCoinByContract(_ data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = root["id"] as? String, !id.isEmpty else { return nil }
        return "coingecko:\(id)"
    }

    /// A ticker as the search and a holding compare it: letters and digits
    /// only, upper case, so a stray space or `$` is not another token.
    static func tickerKey(_ s: String) -> String {
        String(s.uppercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }

    // MARK: - The chart

    /// DeFiLlama's `span` and `period` for a chart range, by `TokenRange`'s
    /// raw value: an hour of five minutes, a day of hours, a week of four
    /// hours, a month of days (measured 2026-10-31: 12, 25, 43, 31 points).
    static func chartQuery(_ range: String) -> (span: Int, period: String)? {
        switch range {
        case "1H":  return (13, "5m")
        case "1D":  return (25, "1h")
        case "7D":  return (43, "4h")
        case "30D": return (31, "1d")
        default:    return nil
        }
    }

    // MARK: - Side by side (the Watchlist's box)

    /// **THE WATCHLIST'S BOX DRAWS ITS TOKENS SIDE BY SIDE (2026-11-01, user:
    /// "in the header it just says 2 tokens you watch"; of the mockups, "lets
    /// go with E").** Every token's window as a percent from where it began,
    /// one line each on one scale. The list is never capped; the box draws
    /// the first five, in the list's own order (Move to top decides).
    static let chartCap = 5

    static func charted(_ tokens: [WatchedToken]) -> [WatchedToken] {
        Array(tokens.prefix(chartCap))
    }

    /// One hue per charted line, by its place in the five, never green or
    /// red (those say up and down here); `ProjectHue`'s, readable on the page.
    static let lineHues = ["#60a5fa", "#facc15", "#c084fc", "#2dd4bf", "#fb923c"]

    /// Closes as the percent each is from the first; empty when there is no
    /// line to draw (under two closes, or a first close that is not a price).
    static func percentSeries(_ closes: [Double]) -> [Double] {
        guard closes.count >= 2, let first = closes.first, first > 0 else { return [] }
        return closes.map { ($0 / first - 1) * 100 }
    }

    /// Where each label's centre goes, in the order given: as near its line's
    /// end as it can be, never closer than `gap` to another, inside `lo…hi`.
    static func labelCenters(_ wanted: [Double], gap: Double, lo: Double, hi: Double) -> [Double] {
        let order = wanted.indices.sorted { wanted[$0] < wanted[$1] }
        var placed = order.map { wanted[$0] }
        for i in placed.indices { placed[i] = max(placed[i], i == 0 ? lo : placed[i - 1] + gap) }
        for i in placed.indices.reversed() {
            placed[i] = min(placed[i], i == placed.count - 1 ? hi : placed[i + 1] - gap)
        }
        for i in placed.indices { placed[i] = max(placed[i], i == 0 ? lo : placed[i - 1] + gap) }
        var out = wanted
        for (k, i) in order.enumerated() { out[i] = placed[k] }
        return out
    }

    /// At most `n` closes, each the mean of its stretch: a line in a 280pt
    /// box gains nothing from CoinGecko's 289 five-minute points, and picking
    /// every sixth kept a thin coin's tick-to-tick bounce as a comb of spikes
    /// (MUSEGOD, seen on the simulator 2026-11-01).
    static func thinned(_ xs: [Double], to n: Int) -> [Double] {
        guard xs.count > n, n >= 2 else { return xs }
        return (0..<n).map { k in
            let bucket = xs[(k * xs.count / n)..<((k + 1) * xs.count / n)]
            return bucket.reduce(0, +) / Double(bucket.count)
        }
    }

    /// CoinGecko's `market_chart` for a coin DeFiLlama has no window for
    /// (measured 2026-10-31: MUSEGOD answered one point a week and none a
    /// day there, 289 a day here): the days it asks, and for the hour, how
    /// much of the day's tail it keeps.
    static func coingeckoChartQuery(_ range: String) -> (days: Int, keepsSeconds: Double?)? {
        switch range {
        case "1H":  return (1, 3600)
        case "1D":  return (1, nil)
        case "7D":  return (7, nil)
        case "30D": return (30, nil)
        default:    return nil
        }
    }

    /// `api.coingecko.com/api/v3/coins/<id>/market_chart`: the closes, oldest
    /// first, only those within `keepsSeconds` of the last when given.
    static func parseCoinGeckoChart(_ data: Data, keepsSeconds: Double?) -> [Double] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = root["prices"] as? [[Any]] else { return [] }
        let points = rows.compactMap { r -> (Double, Double)? in
            guard r.count == 2, let t = number(r[0]), let v = number(r[1]), v > 0 else { return nil }
            return (t, v)
        }.sorted { $0.0 < $1.0 }
        guard let last = points.last?.0 else { return [] }
        let cutoff = keepsSeconds.map { last - $0 * 1000 } ?? -.infinity
        return points.filter { $0.0 >= cutoff }.map(\.1)
    }

    // MARK: - Reading the answers

    /// `coins.llama.fi/prices/current/…`: id → (price, symbol), only above
    /// the confidence floor and only a real number.
    static func parsePrices(_ data: Data) -> [String: (price: Double, symbol: String)] {
        guard let coins = coins(data) else { return [:] }
        var out: [String: (price: Double, symbol: String)] = [:]
        for (id, raw) in coins {
            guard let e = raw as? [String: Any],
                  let price = number(e["price"]), price > 0,
                  (number(e["confidence"]) ?? 0) >= confidenceFloor else { continue }
            out[id] = (price, (e["symbol"] as? String) ?? "")
        }
        return out
    }

    /// `coins.llama.fi/percentage/…?period=24h`: id → the day's change, in percent.
    static func parsePercent(_ data: Data) -> [String: Double] {
        guard let coins = coins(data) else { return [:] }
        var out: [String: Double] = [:]
        for (id, raw) in coins { if let p = number(raw) { out[id] = p } }
        return out
    }

    /// `coins.llama.fi/chart/<id>`: the closes, oldest first.
    static func parseChart(_ data: Data, id: String) -> [Double] {
        guard let coins = coins(data), let e = coins[id] as? [String: Any],
              let points = e["prices"] as? [[String: Any]] else { return [] }
        return points
            .compactMap { p -> (Double, Double)? in
                guard let t = number(p["timestamp"]), let v = number(p["price"]), v > 0 else { return nil }
                return (t, v)
            }
            .sorted { $0.0 < $1.0 }
            .map(\.1)
    }

    /// `api.coingecko.com/api/v3/search`: the coins it found, by market-cap
    /// rank. A coin with no rank is left out: it is the unlisted tail, where
    /// a fake wearing a real ticker lives (§1107a).
    static func parseSearch(_ data: Data) -> [WatchedToken] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let coins = root["coins"] as? [[String: Any]] else { return [] }
        let ranked: [(rank: Int, token: WatchedToken)] = coins.compactMap { c in
            guard let id = c["id"] as? String, !id.isEmpty,
                  let symbol = c["symbol"] as? String, !symbol.isEmpty,
                  let rank = number(c["market_cap_rank"]).map({ Int($0) }) else { return nil }
            return (rank, WatchedToken(id: "coingecko:\(id)", symbol: symbol.uppercased(),
                                       name: (c["name"] as? String) ?? symbol))
        }
        return ranked.sorted { $0.rank < $1.rank }.prefix(searchCap).map(\.token)
    }

    private static func coins(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["coins"] as? [String: Any]
    }

    private static func number(_ raw: Any?) -> Double? {
        if let d = raw as? Double, d.isFinite { return d }
        if let i = raw as? Int { return Double(i) }
        if let s = raw as? String, let d = Double(s), d.isFinite { return d }
        return nil
    }
}
