import Foundation
import SwiftData

/// Watching a company from the index (prd §1082), one rule for the room's
/// stars, "Watch all", the company's page and Search.
///
/// A stock is watched by its ticker. A coin is followed by its CoinPaprika id
/// and priced from CoinPaprika's ticker (prd §1250, `CoinWatch`): until then
/// it was the most liquid DEX token wearing its symbol, one pool's price and
/// a wrapper's cap.
@MainActor
enum MarketsWatch {
    /// The tickers you watch, upper-cased: a stock's ticker, a coin's or a
    /// token's symbol.
    static func watchedTickers(_ things: [Thing]) -> Set<String> {
        Set(things.compactMap { thing -> String? in
            guard thing.isLive, thing.source == TokenWatch.source,
                  !PriceAlertStore.isAlertRow(thing) else { return nil }
            return (StockWatch.symbol(of: thing) ?? thing.authorHandle)?.uppercased()
        })
    }

    /// The watched row a company is, when you watch it.
    static func watchedThing(_ company: CompanyPacks.Company, context: ModelContext) -> Thing? {
        guard let ticker = company.listing.ticker?.uppercased() else { return nil }
        let source = TokenWatch.source
        let rows = (try? context.fetch(FetchDescriptor<Thing>(predicate: #Predicate { $0.source == source }))) ?? []
        return rows.first { thing in
            guard thing.isLive, !PriceAlertStore.isAlertRow(thing) else { return false }
            return (StockWatch.symbol(of: thing) ?? thing.authorHandle)?.uppercased() == ticker
        }
    }

    /// Watches a company; the new row, or nil with why.
    static func watch(_ company: CompanyPacks.Company,
                      context: ModelContext) async -> Result<Thing, Failure> {
        switch company.listing {
        case .unlisted:
            return .failure(.notTraded)
        case .stock(let ticker):
            let stock = StockWatch.Resolved(symbol: ticker, title: company.name,
                                            exchange: "", watchers: 0)
            guard let thing = StockWatch.add(stock, context: context) else { return .failure(.already) }
            return .success(thing)
        case .token(let symbol, let id):
            guard !DemoMode.isActive else { return .failure(.demo) }
            guard watchedThing(company, context: context) == nil else { return .failure(.already) }
            // The price the index row drew is the since-you-followed anchor.
            let price = CompanyQuotes.shared.quote(company.listing)?.price
            let name = CoinFollow.native(id)?.name ?? company.name
            guard let thing = CoinWatch.add(id: id, name: name, symbol: symbol.uppercased(),
                                            price: price, context: context) else { return .failure(.already) }
            return .success(thing)
        }
    }

    /// Stops watching a company: its row and its alerts.
    static func unwatch(_ company: CompanyPacks.Company, context: ModelContext) {
        guard let thing = watchedThing(company, context: context) else { return }
        if let ref = thing.sourceRef {
            TokenWatchOrder.shared.remove(ref)
            PriceAlertStore.shared.removeAll(ref: ref)
        }
        SpotlightIndex.remove(ids: [thing.id])
        context.delete(thing)
        context.saveHonestly()
    }

    enum Failure: Error {
        case notTraded, already, demo

        var message: String {
            switch self {
            case .notTraded: String(localized: "Not traded, so there's nothing to follow")
            case .already:   String(localized: "Already on your watchlist")
            case .demo:      String(localized: "Following works once you leave the demo")
            }
        }
    }

    static func entry(_ company: CompanyPacks.Company) -> MarketsIndex.Entry {
        MarketsIndex.Entry(name: company.name, ticker: company.listing.ticker, apps: company.seats)
    }
}
