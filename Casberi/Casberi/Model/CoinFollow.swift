import Foundation

/// A COIN FOLLOWED BY ITS OWN PRICE (prd §1247).
///
/// Bitcoin, Ether, Solana and every coin in the index (`CompanyPacks`'
/// `.token` listings) are followed by their CoinPaprika id (`btc-bitcoin`,
/// `eth-ethereum`, `sol-solana`) and priced from CoinPaprika's ticker: the
/// coin's price, its day move and its cap. Until now a native coin was its
/// wrapped token on one DEX (WBTC on Ethereum, wSOL) and an index coin was the
/// most liquid token wearing its symbol, so the price was one pool's and the
/// cap was the wrapper's supply.
///
/// A token followed by its contract stays a token (`TokenWatch`): the contract
/// is what the person chose. Only the wrapped forms the household names were
/// pinned to, and the index's own symbol matches from before this ruling,
/// converge onto the coin (`convergence`), on every launch (§647).
///
/// Foundation-only and pure: `scripts/markets-selftest.sh` compiles it whole.
/// The reads live in `CoinWatch`; nothing here reaches the network.
enum CoinFollow {

    /// The followed coin's namespace in Markets.
    static let refPrefix = "coin:"

    static func ref(_ id: String) -> String { refPrefix + id }

    /// The CoinPaprika id a followed coin's ref carries, or nil for any other row.
    static func id(fromRef ref: String?) -> String? {
        guard let ref, ref.hasPrefix(refPrefix) else { return nil }
        let id = String(ref.dropFirst(refPrefix.count))
        return id.isEmpty ? nil : id
    }

    /// The coin's public page: what a followed coin's row carries as its
    /// content, what its page opens, and what `route` reads back.
    static func page(_ id: String) -> String { "https://coinpaprika.com/coin/\(id)/" }

    /// The CoinPaprika id out of a coin page link, or nil.
    static func route(from content: String) -> String? {
        guard let url = URL(string: content),
              url.host()?.hasSuffix("coinpaprika.com") == true else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 2, parts[0] == "coin", !parts[1].isEmpty else { return nil }
        return parts[1]
    }

    /// The coin's mark on CoinPaprika's own image host. UNMEASURED: the path
    /// is the one CoinPaprika's pages draw; a coin without one answers 404 and
    /// the row keeps its lettered face.
    static func logo(_ id: String) -> String { "https://static.coinpaprika.com/coin/\(id)/logo.png" }

    struct Coin: Equatable {
        let id: String
        let name: String
        let symbol: String
    }

    /// The three coins people type by their household name.
    static let natives: [Coin] = [
        Coin(id: "eth-ethereum", name: "Ethereum", symbol: "ETH"),
        Coin(id: "btc-bitcoin", name: "Bitcoin", symbol: "BTC"),
        Coin(id: "sol-solana", name: "Solana", symbol: "SOL"),
    ]

    static func native(_ id: String) -> Coin? { natives.first { $0.id == id } }

    /// The wrapped tokens the household names were pinned to until §1247
    /// (`TokenWatch.householdNames`), by Dexscreener chain and address, case-
    /// folded the way a token's ref stores it (`tokens:<chain>:<lowercased>`).
    static let wrapped: [String: String] = [
        "ethereum:0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2": "eth-ethereum",   // WETH
        "ethereum:0x2260fac5e5542a773aa44fbcfedf7c193bc2c599": "btc-bitcoin",    // WBTC
        "solana:so11111111111111111111111111111111111111112": "sol-solana",       // wrapped SOL
    ]

    /// The coin a wrapped native stands for, or nil.
    static func wrappedCoin(chain: String, address: String) -> String? {
        wrapped["\(chain.lowercased()):\(address.lowercased())"]
    }

    /// Before this, the index followed a coin as the most liquid DEX token
    /// wearing its symbol (`MarketsWatch`), a row no different in the store
    /// from one the person picked in Add. A row captured before this moment
    /// whose symbol is an index coin's converges; one captured after it was
    /// picked by contract or by search and stays a token.
    static let indexCutoff = Date(timeIntervalSince1970: 1_791_936_000)   // 2026-10-14 00:00 UTC

    /// The coin a followed token converges to, or nil when it stays a token:
    /// a wrapped native by its address, always; an index coin by its exact
    /// symbol (`indexCoins`, SYMBOL → id), only for a row from before
    /// `indexCutoff`.
    static func convergence(tokenRef ref: String, symbol: String?, capturedAt: Date,
                            indexCoins: [String: String]) -> String? {
        guard ref.hasPrefix("tokens:") else { return nil }
        let parts = ref.split(separator: ":", maxSplits: 2).map(String.init)
        guard parts.count == 3 else { return nil }
        if let id = wrappedCoin(chain: parts[1], address: parts[2]) { return id }
        guard capturedAt < indexCutoff,
              let symbol = symbol?.trimmingCharacters(in: .whitespaces).uppercased(),
              !symbol.isEmpty else { return nil }
        return indexCoins[symbol]
    }

    /// One followed row, as the sweep sees it.
    struct Row: Equatable {
        let ref: String
        let symbol: String?
        let capturedAt: Date
    }

    /// What one launch's sweep does to each row, in the order given:
    /// `stay` (not a coin, or already one), `move` (becomes the coin's
    /// follow in place), or `fold` (its coin is already followed, or claimed
    /// by an earlier row this pass: the row goes and its place and alerts are
    /// the coin's). `map` renames every converging ref for the order and the
    /// alerts. A store already swept plans nothing but `stay`.
    enum Step: Equatable {
        case stay
        case move(to: String)
        case fold(into: String)
    }

    struct Plan: Equatable {
        var steps: [Step] = []
        var map: [String: String] = [:]
    }

    static func plan(_ rows: [Row], indexCoins: [String: String]) -> Plan {
        var claimed = Set(rows.compactMap { id(fromRef: $0.ref) })
        var plan = Plan()
        for row in rows {
            guard let id = convergence(tokenRef: row.ref, symbol: row.symbol,
                                       capturedAt: row.capturedAt, indexCoins: indexCoins) else {
                plan.steps.append(.stay)
                continue
            }
            let next = ref(id)
            plan.map[row.ref] = next
            plan.steps.append(claimed.insert(id).inserted ? .move(to: next) : .fold(into: next))
        }
        return plan
    }

    /// The saved order with every converged ref renamed. A ref that lands on
    /// one already in the order keeps the first place either held, so the
    /// list never shows one coin twice and never loses its place.
    static func rewrite(order: [String], map: [String: String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for ref in order {
            let next = map[ref] ?? ref
            if seen.insert(next).inserted { out.append(next) }
        }
        return out
    }

    /// The alerts with every converged ref renamed. A renamed alert takes the
    /// moment as its change, so a device that has not swept yet cannot sync
    /// the old ref back over it (`PriceAlert.merged`).
    static func rewrite(alerts: [PriceAlert], map: [String: String], now: Date) -> [PriceAlert] {
        alerts.map { alert in
            guard let next = map[alert.ref], next != alert.ref else { return alert }
            var moved = alert
            moved.ref = next
            moved.changedAt = now
            return moved
        }
    }

    // MARK: - CoinPaprika's answers

    /// One ticker: the price, the day move as a FRACTION (`TokenPulse`'s unit),
    /// the cap and the day's volume when CoinPaprika states them. A zero cap
    /// or volume is dropped, never drawn as "$0".
    struct Ticker: Equatable {
        let price: Double
        let change24h: Double?
        let marketCap: Double?
        let volume24h: Double?
    }

    static func tickerURL(_ id: String) -> String { "https://api.coinpaprika.com/v1/tickers/\(id)" }

    /// `GET /v1/tickers/{id}`: `quotes.USD.price`, `percent_change_24h` (a
    /// percent), `market_cap`, `volume_24h`. The ticker shape is the one
    /// `CompanyQuotes` has read since §1082.
    static func ticker(from json: Any?) -> Ticker? {
        guard let root = json as? [String: Any],
              let usd = (root["quotes"] as? [String: Any])?["USD"] as? [String: Any],
              let price = number(usd["price"]), price > 0 else { return nil }
        return Ticker(price: price,
                      change24h: number(usd["percent_change_24h"]).map { $0 / 100 },
                      marketCap: number(usd["market_cap"]).flatMap { $0 > 0 ? $0 : nil },
                      volume24h: number(usd["volume_24h"]).flatMap { $0 > 0 ? $0 : nil })
    }

    /// What a chart range asks CoinPaprika's historical ticks for, by the
    /// range's stored value (`TokenRange.rawValue`), or nil when the range is
    /// not asked at all: the hour wants five-minute ticks, which the free API
    /// does not serve (UNMEASURED, from its docs), so the hour is absent for a
    /// coin rather than drawn from coarser points.
    static func history(range: String) -> (interval: String, span: TimeInterval)? {
        switch range {
        case "1D":  return ("1h", 86_400)
        case "7D":  return ("2h", 7 * 86_400)
        case "30D": return ("1d", 30 * 86_400)
        default:    return nil
        }
    }

    /// `GET /v1/tickers/{id}/historical?start=<unix>&interval=<i>` for a range,
    /// or nil when the range is not asked.
    static func historyURL(_ id: String, range: String, now: Date) -> String? {
        guard let query = history(range: range) else { return nil }
        let start = Int(now.timeIntervalSince1970 - query.span)
        return "https://api.coinpaprika.com/v1/tickers/\(id)/historical?start=\(start)&interval=\(query.interval)"
    }

    /// The historical ticks as closes, oldest first: an array of
    /// `{timestamp, price}` (UNMEASURED, from CoinPaprika's docs), sorted by
    /// its own ISO-8601 stamp rather than trusted as ordered. Anything else,
    /// an error object included, is no closes.
    static func closes(from json: Any?) -> [Double] {
        guard let rows = json as? [[String: Any]] else { return [] }
        return rows.compactMap { row -> (String, Double)? in
            guard let stamp = row["timestamp"] as? String,
                  let price = number(row["price"]), price > 0 else { return nil }
            return (stamp, price)
        }
        .sorted { $0.0 < $1.0 }
        .map(\.1)
    }

    /// A JSON number that may arrive as a number or a string.
    static func number(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let s = any as? String { return Double(s) }
        return nil
    }
}
