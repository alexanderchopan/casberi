import Foundation
import SwiftData

/// THE MARKET'S ANSWER TO THE ONE SEARCH (prd §1467): coins, tokens and
/// stocks for the words, as rows the tray draws under Markets, each one a
/// follow in place. The order and the folds are `MarketsSearch`'s; this is
/// the reads and the saves.
@MainActor
enum MarketsSearchRead {

    /// One market row.
    struct Hit: Identifiable, Equatable {
        enum Kind: Equatable {
            case coin(id: String, symbol: String)
            case token(chain: String, address: String)
            case stock(symbol: String, exchange: String)
        }
        let kind: Kind
        /// The ref its follow lands under, so the row can say it is followed.
        let ref: String
        let name: String
        let line: String
        let price: Double?
        let change: Double?
        let imageURL: String?
        /// A letter face when there is no image: the symbol.
        let lettered: String
        /// A stock's logo is drawn on white (`WatchFace`).
        let onWhite: Bool
        var id: String { ref }
    }

    /// Everything the market said for the words: the rows in order, and the
    /// counts the Show all line names.
    struct Reading: Equatable {
        var hits: [Hit] = []
        var chains: [(name: String, count: Int)] = []
        var stocks = 0

        static func == (a: Reading, b: Reading) -> Bool {
            a.hits == b.hits && a.stocks == b.stocks
                && a.chains.map(\.name) == b.chains.map(\.name) && a.chains.map(\.count) == b.chains.map(\.count)
        }
    }

    private struct Priced {
        let coin: MarketsSearch.Coin
        let ticker: CoinFollow.Ticker?
    }

    /// Asks the market. The demo reaches nothing (its rows are not yours to
    /// add to); a blank query reads nothing.
    static func read(_ query: String) async -> Reading {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !DemoMode.isActive else { return Reading() }
        let address = MarketsSearch.isAddress(q)
        async let coinJSON = coinSearch(q)
        async let tokens = TokenWatch.search(q, limit: MarketsSearch.tokenLimit)
        async let stocks: [StockWatch.Resolved] = address ? [] : StockWatch.search(q, limit: MarketsSearch.stockLimit)
        let coins = MarketsSearch.coins(from: await coinJSON)
        // The first few coins are priced, one ticker each, together.
        let priced: [Priced] = await IngestSupport.boundedGather(
            Array(coins.prefix(MarketsSearch.pricedCoins)), maxConcurrent: 4) { coin in
            Priced(coin: coin, ticker: await CoinWatch.ticker(id: coin.id))
        }
        let foundTokens = await tokens
        let foundStocks = await stocks
        let picks = MarketsSearch.picks(
            query: q, coins: coins,
            tokens: foundTokens.map { .init(chain: $0.chain, address: $0.address, liquidity: $0.liquidityUsd ?? 0) },
            stocks: foundStocks.count)
        var reading = Reading()
        var chainCounts: [String: Int] = [:]
        for pick in picks {
            switch pick {
            case .coin(let i):
                let coin = coins[i]
                let ticker = priced.first { $0.coin.id == coin.id }?.ticker
                // Its face: the DEX token that is the coin, when one was
                // found, else its letters (CoinPaprika's host is down).
                let image = foundTokens.first {
                    MarketsSearch.coin(ofTokenOn: $0.chain, address: $0.address, among: [coin]) != nil && $0.imageURL != nil
                }?.imageURL
                let line = [coin.symbol, ticker?.marketCap.map { String(localized: "\(TokenStats.compact($0)) cap") }]
                    .compactMap(\.self).joined(separator: " · ")
                reading.hits.append(Hit(kind: .coin(id: coin.id, symbol: coin.symbol), ref: CoinFollow.ref(coin.id),
                                        name: coin.name, line: line,
                                        price: ticker?.price, change: ticker?.change24h,
                                        imageURL: image, lettered: coin.symbol, onWhite: false))
            case .token(let i):
                let token = foundTokens[i]
                let chain = WatchAddSheet.chainName(token.chain)
                chainCounts[chain, default: 0] += 1
                let line = [chain,
                            token.liquidityUsd.map { String(localized: "\(TokenStats.compact($0)) liquidity") }
                                ?? token.marketCap.map { String(localized: "\(TokenStats.compact($0)) cap") }]
                    .compactMap(\.self).joined(separator: " · ")
                reading.hits.append(Hit(kind: .token(chain: token.chain, address: token.address),
                                        ref: tokenRef(token), name: token.name, line: line,
                                        price: token.priceUsd.flatMap(Double.init), change: token.change24h,
                                        imageURL: token.imageURL, lettered: token.symbol, onWhite: false))
            case .stock(let i):
                let stock = foundStocks[i]
                let line = [stock.symbol, stock.exchange.capitalized].filter { !$0.isEmpty }.joined(separator: " · ")
                reading.hits.append(Hit(kind: .stock(symbol: stock.symbol, exchange: stock.exchange), ref: StockWatch.symbolRef(stock.symbol),
                                        name: stock.title, line: line, price: nil, change: nil,
                                        imageURL: StockWatch.logoURL(stock.symbol), lettered: stock.symbol,
                                        onWhite: true))
            }
        }
        reading.chains = chainCounts.map { (name: $0.key, count: $0.value) }
        reading.stocks = foundStocks.count
        // The stocks' quotes, read after the rows stand (`CompanyQuotes`
        // publishes; the row draws the quote when it lands).
        if !foundStocks.isEmpty {
            let companies = foundStocks.map {
                CompanyPacks.Company(name: $0.title, listing: .stock($0.symbol), seats: [])
            }
            Task { await CompanyQuotes.shared.load(companies) }
        }
        return reading
    }

    private static func coinSearch(_ q: String) async -> Any? {
        guard let url = MarketsSearch.searchURL(q) else { return nil }
        return await IngestSupport.getJSON(url)
    }

    /// The ref a token's follow lands under: a household coin's wrapped
    /// token is followed as the coin (prd §1250, `TokenWatch.add`).
    static func tokenRef(_ token: TokenWatch.Resolved) -> String {
        if let id = CoinFollow.wrappedCoin(chain: token.chain, address: token.address) {
            return CoinFollow.ref(id)
        }
        return "tokens:\(token.chain):\(token.address.lowercased())"
    }

    /// The refs Markets follows now, so a row can wear its mark.
    static func followedRefs(context: ModelContext) -> Set<String> {
        let source = TokenWatch.source
        let rows = (try? context.fetch(FetchDescriptor<Thing>(predicate: #Predicate { $0.source == source }))) ?? []
        return Set(rows.filter { $0.isLive && !PriceAlertStore.isAlertRow($0) }.compactMap(\.sourceRef))
    }

    /// Follows the row: the new thing, or nil when it is followed already.
    @discardableResult
    static func follow(_ hit: Hit, context: ModelContext) -> Thing? {
        switch hit.kind {
        case .coin(let id, let symbol):
            return CoinWatch.add(id: id, name: hit.name, symbol: symbol, price: hit.price,
                                 imageURL: hit.imageURL, context: context)
        case .token(let chain, let address):
            let token = TokenWatch.Resolved(chain: chain, address: address, name: hit.name, symbol: hit.lettered,
                                            priceUsd: hit.price.map { String($0) }, imageURL: hit.imageURL,
                                            change24h: hit.change)
            return TokenWatch.add(token, context: context)
        case .stock(let symbol, let exchange):
            // The since-you-followed anchor backfills inside `StockWatch.add`.
            return StockWatch.add(StockWatch.Resolved(symbol: symbol, title: hit.name, exchange: exchange, watchers: 0),
                                  context: context)
        }
    }
}
