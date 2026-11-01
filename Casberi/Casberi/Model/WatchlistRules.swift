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
