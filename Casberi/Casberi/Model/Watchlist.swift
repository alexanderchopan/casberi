import Foundation
import Observation

/// **THE WATCHLIST (prd §1632): tokens you watch, yours and no account's.**
/// Kept in `UserDefaults` under a key outside `markets.` and `tokens.watch.`,
/// which `SourceRename.sweepRetiredSeats` clears at every launch (§1529); no
/// `Thing`, so nothing reaches the Feed. The rules are `WatchlistRules`.
@Observable
@MainActor
final class Watchlist {
    static let shared = Watchlist()

    static let storeKey = "wallet.watchlist.v1"

    private(set) var tokens: [WatchedToken]

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.storeKey),
           let decoded = try? JSONDecoder().decode([WatchedToken].self, from: data) {
            tokens = decoded
        } else {
            tokens = []
        }
    }

    func contains(_ id: String) -> Bool { tokens.contains { $0.id == id } }

    func token(_ id: String?) -> WatchedToken? {
        guard let id else { return nil }
        return tokens.first { $0.id == id }
    }

    func watch(_ token: WatchedToken) {
        let next = WatchlistRules.adding(token, to: tokens)
        guard next != tokens else { return }
        tokens = next
        persist()
    }

    func stopWatching(_ id: String) {
        tokens = WatchlistRules.removing(id, from: tokens)
        persist()
    }

    func moveToTop(_ id: String) {
        tokens = WatchlistRules.movingToTop(id, in: tokens)
        persist()
    }

    func clear() {
        tokens = []
        DefaultsWrite.remove(Self.storeKey)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(tokens) else { return }
        DefaultsWrite.set(data, forKey: Self.storeKey)
    }
}

/// **THE WATCHLIST'S PRICES (prd §1632 item 8).** One batched DeFiLlama read
/// of every watched token's price and day's change, at most once in
/// `WatchlistRules.window`, asked only when Home or the Watchlist page comes
/// on screen, never by the background sweep. Between reads the last prices
/// stand, and `readAt` stamps them. Memory only: a price is perishable.
@Observable
@MainActor
final class WatchlistPrices {
    static let shared = WatchlistPrices()

    private(set) var quotes: [String: WatchlistRules.Quote] = [:]
    private(set) var readAt: Date?
    private var reading = false
    /// The ids the last read asked for: a token added since is read at once.
    private var readIDs: Set<String> = []

    /// Reads when the window has passed or a token is new to it.
    func refreshIfStale(_ tokens: [WatchedToken]) async {
        let ids = Set(tokens.map(\.id))
        guard !ids.isEmpty, !reading else { return }
        guard WatchlistRules.isStale(readAt: readAt, now: .now) || !ids.isSubset(of: readIDs) else { return }
        // The demo reaches nothing (§217): round prices, under its marking.
        if DemoMode.isActive {
            quotes = Self.demoQuotes(ids)
            readAt = .now
            readIDs = ids
            return
        }
        reading = true
        defer { reading = false }
        let read = await Self.read(Array(ids))
        guard !read.isEmpty else { return }
        quotes.merge(read) { $1 }
        readAt = .now
        readIDs = ids
    }

    /// Prices and the day's change for the ids, keyless; `[:]` on failure.
    nonisolated static func read(_ ids: [String]) async -> [String: WatchlistRules.Quote] {
        let path = ids.sorted().joined(separator: ",")
        async let pricesText = text("https://coins.llama.fi/prices/current/\(path)")
        async let changeText = text("https://coins.llama.fi/percentage/\(path)?period=24h")
        let prices = await pricesText.map { WatchlistRules.parsePrices(Data($0.utf8)) } ?? [:]
        let change = await changeText.map { WatchlistRules.parsePercent(Data($0.utf8)) } ?? [:]
        var out: [String: WatchlistRules.Quote] = [:]
        for (id, p) in prices { out[id] = .init(price: p.price, change: change[id]) }
        return out
    }

    /// A token's chart for a `TokenRange`, keyless, or nil when the range did
    /// not answer (the chart then says so rather than drawing anything else).
    nonisolated static func chart(id: String, range: TokenRange) async -> TokenChart? {
        guard let q = WatchlistRules.chartQuery(range.rawValue),
              let body = await text("https://coins.llama.fi/chart/\(id)?span=\(q.span)&period=\(q.period)") else { return nil }
        return TokenChart.from(closes: WatchlistRules.parseChart(Data(body.utf8), id: id))
    }

    /// The search: a pasted address asks every chain at once; words ask
    /// CoinGecko, then only the coins DeFiLlama prices are offered.
    nonisolated static func search(_ words: String) async -> [(token: WatchedToken, quote: WatchlistRules.Quote)] {
        let candidates = WatchlistRules.contractCandidates(words)
        var found: [WatchedToken]
        if !candidates.isEmpty {
            guard let body = await text("https://coins.llama.fi/prices/current/\(candidates.joined(separator: ","))") else { return [] }
            found = WatchlistRules.parsePrices(Data(body.utf8))
                .sorted { $0.key < $1.key }
                .map { WatchedToken(id: $0.key, symbol: $0.value.symbol.uppercased(),
                                    name: $0.value.symbol.uppercased()) }
        } else {
            guard let q = words.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let body = await text("https://api.coingecko.com/api/v3/search?query=\(q)") else { return [] }
            found = WatchlistRules.parseSearch(Data(body.utf8))
        }
        guard !found.isEmpty else { return [] }
        let quotes = await read(found.map(\.id))
        return found.compactMap { t in quotes[t.id].map { (t, $0) } }
    }

    nonisolated private static func text(_ url: String) async -> String? {
        guard let url = URL(string: url) else { return nil }
        return await IngestSupport.getText(url)
    }

    /// The demo's chart: an invented curve ending on its quote, the day's
    /// move spread over the range, so the box is never empty (§769).
    static func demoChart(id: String, range: TokenRange) -> TokenChart? {
        guard let quote = demoQuotes([id])[id] else { return nil }
        let n = 24
        let start = quote.price / (1 + (quote.change ?? 0) / 100)
        let closes = (0..<n).map { i -> Double in
            let t = Double(i) / Double(n - 1)
            return start + (quote.price - start) * t + quote.price * 0.006 * sin(Double(i) * 1.3 + Double(range.rawValue.count))
        }
        return TokenChart.from(closes: closes + [quote.price])
    }

    /// The demo's quotes: round, invented, drawn only under the demo's own
    /// marking (§864). A few coins move; the rest take `MainnetPrices`'
    /// demo price on a flat day.
    static func demoQuotes(_ ids: Set<String>) -> [String: WatchlistRules.Quote] {
        let moving: [String: (Double, Double)] = [
            "bitcoin": (64_000, 0.9), "ethereum": (2_600, 2.1), "hyperliquid": (38.2, -4.6),
            "solana": (150, 1.3), "worldcoin-wld": (1.2, -1.2),
        ]
        var out: [String: WatchlistRules.Quote] = [:]
        for id in ids where id.hasPrefix("coingecko:") {
            let coin = String(id.dropFirst("coingecko:".count))
            if let (p, c) = moving[coin] {
                out[id] = .init(price: p, change: c)
            } else if let p = MainnetPrices.demoPrices[coin] {
                out[id] = .init(price: p, change: 0)
            }
        }
        return out
    }
}
