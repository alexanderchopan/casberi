import Foundation
import SwiftData

/// Watching a company from the index (prd §1082), one rule for the room's
/// stars, "Watch all", the company's page and Search.
///
/// A stock is watched by its ticker. A token is watched as the most liquid
/// token wearing exactly its symbol (Dexscreener's search, the same ranking
/// Add uses), because the index knows a coin by its CoinPaprika id and not by
/// a contract; a symbol nobody trades on a DEX finds nothing and says so.
@MainActor
enum MarketsWatch {
    /// The tickers you watch, upper-cased: a stock's ticker, a token's symbol.
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
        case .token(let symbol, _):
            guard !DemoMode.isActive else { return .failure(.demo) }
            let found = await TokenWatch.search(symbol, limit: 8)
            guard let token = found.first(where: { $0.symbol.uppercased() == symbol.uppercased() }) else {
                return .failure(.notFound)
            }
            guard let thing = TokenWatch.add(token, context: context) else { return .failure(.already) }
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
        case notTraded, already, notFound, demo

        var message: String {
            switch self {
            case .notTraded: String(localized: "Not traded, so there's nothing to watch")
            case .already:   String(localized: "Already on your watchlist")
            case .notFound:  String(localized: "Couldn't find it on an exchange")
            case .demo:      String(localized: "Watching works once you leave the demo")
            }
        }
    }

    static func entry(_ company: CompanyPacks.Company) -> MarketsIndex.Entry {
        MarketsIndex.Entry(name: company.name, ticker: company.listing.ticker, apps: company.seats)
    }
}
