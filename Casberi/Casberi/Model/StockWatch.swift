import Foundation
import SwiftData

/// Watching a STOCK (2026-07-15, the Stocktwits seat until 2026-09-29, when
/// its watches moved into Markets beside the tokens). A typed name or ticker
/// resolves through Stocktwits' keyless symbol search, and the watch lands as
/// a thing in Markets whose sheet draws the ticker's live chart (StockChart,
/// Yahoo v8). The traders' takes this seat used to land are gone with the
/// seat (user: drop them).
///
/// It watches tickers, never portfolios — holdings are not public anywhere —
/// and nothing here trades.

enum StockWatch {

    struct Resolved: Identifiable {
        let symbol: String     // "AAPL"
        let title: String      // "Apple Inc"
        let exchange: String   // "NASDAQ", "NYSE", "CRYPTO", …
        let watchers: Int      // Stocktwits watchlist_count — the row's scale cue
        var id: String { symbol }
    }

    /// The top matching symbols for a typed query — Stocktwits' own keyless
    /// symbol search (the site's autocomplete), its relevance order kept.
    static func search(_ query: String, limit: Int = 6) async -> [Resolved] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty,
              let encoded = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let root = await IngestSupport.getJSON(
                "https://api.stocktwits.com/api/2/search/symbols.json?q=\(encoded)")
                as? [String: Any],
              let results = root["results"] as? [[String: Any]]
        else { return [] }

        return results.compactMap { r -> Resolved? in
            // Crypto is Markets' token half (Dexscreener); Stocktwits lists
            // coins too ("BTC.X", exchange CRYPTO), and one coin found twice
            // under two prices is the confusion one field must not make.
            guard (r["type"] as? String) == "symbol",
                  (r["exchange"] as? String)?.uppercased() != "CRYPTO",
                  let symbol = r["symbol"] as? String, !symbol.isEmpty,
                  let title = r["title"] as? String else { return nil }
            return Resolved(symbol: symbol, title: title,
                            exchange: (r["exchange"] as? String) ?? "",
                            watchers: (r["watchlist_count"] as? Int) ?? 0)
        }
        .prefix(limit).map { $0 }
    }

    /// Resolves a query to its top match — the Watch button's path.
    static func resolve(_ query: String) async -> Resolved? {
        await search(query, limit: 1).first
    }

    /// The stock namespace. It kept its Stocktwits name when the watches
    /// moved into Markets: the search is still Stocktwits', and a rewrite of
    /// every watched row's ref would buy nothing.
    static let refPrefix = "stocktwits:sym:"

    static func symbolRef(_ symbol: String) -> String {
        refPrefix + symbol.uppercased()
    }

    /// The ticker a watched stock row carries, or nil for any other row.
    /// A stock's logo (prd §1081): Financial Modeling Prep's public 250px
    /// image, keyless. A ticker it has no image for answers 404 and the row
    /// keeps its lettered mark.
    static func logoURL(_ symbol: String) -> String? {
        let ticker = symbol.uppercased().filter { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }
        guard !ticker.isEmpty else { return nil }
        return "https://financialmodelingprep.com/image-stock/\(ticker).png"
    }

    static func symbol(of thing: Thing) -> String? {
        guard let ref = thing.sourceRef, ref.hasPrefix(refPrefix) else { return nil }
        return String(ref.dropFirst(refPrefix.count))
    }

    /// Adds a ticker to the watchlist as a thing whose sheet draws the live
    /// chart. Returns nil when it's already watched. The insert is
    /// immediate; the since-you-watched anchor (the live price at this
    /// moment, so the sheet can later say "+12% since you watched" against
    /// a number that was really true) backfills in the background — Yahoo
    /// can be rate-limiting, and a Watch tap must not sit behind its
    /// timeouts. No anchor lands when Yahoo's unreachable: the line simply
    /// never renders (the TokenWatch precedent).
    @MainActor
    @discardableResult
    static func add(_ stock: Resolved, context: ModelContext) -> Thing? {
        let ref = symbolRef(stock.symbol)
        // One-ref dedupe — a targeted count, not the whole-corpus ref set.
        let existing = (try? context.fetchCount(FetchDescriptor<Thing>(
            predicate: #Predicate { $0.sourceRef == ref }))) ?? 0
        guard existing == 0 else { return nil }
        let thing = Thing(
            kind: .link,
            title: TitleSeam.join(stock.title, "$\(stock.symbol)"),
            // The Stocktwits symbol page — what StockChart.route reads, and
            // a real page when opened.
            content: "https://stocktwits.com/symbol/\(stock.symbol)",
            source: TokenWatch.source,
            capturedAt: .now,
            // The market it trades on, when the search told us. It's the fact
            // that separates $BTC.X from $AAPL, and until now it lived only in
            // the search sheet's own subtitle (`StocktwitsScreen.detail`) —
            // read on the way past and then dropped, so a landed watchlist row
            // couldn't say which market it belonged to. Empty for the rare
            // result that names none, never a guessed exchange.
            tags: ["Watchlist"] + (stock.exchange.isEmpty ? [] : [stock.exchange]),
            sourceRef: ref
        )
        // The SYMBOL as a stamped field (prd §369 amendment, 2026-08-16) — see
        // `TokenWatch`'s twin of this line for why it rides `authorHandle`
        // rather than earning a new `Thing` property.
        thing.authorHandle = stock.symbol
        context.insert(thing)
        context.saveHonestly()
        SpotlightIndex.index([thing])
        let symbol = stock.symbol
        Task { @MainActor in
            guard let price = await StockChart.fetch(ticker: symbol, range: .day)?.price
            else { return }
            thing.watchPriceUsd = price
            context.saveHonestly()
        }
        return thing
    }

    /// Watched tickers, derived from the corpus — the thing IS the watch, so
    /// deleting the row is unwatching.
    @MainActor
    static func watchedSymbols(context: ModelContext) -> [String] {
        let source = TokenWatch.source
        var descriptor = FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == source && $0.sourceRef != nil })
        descriptor.propertiesToFetch = [\.sourceRef]
        return ((try? context.fetch(descriptor)) ?? [])
            .compactMap(\.sourceRef)
            .compactMap { $0.hasPrefix(refPrefix) ? String($0.dropFirst(refPrefix.count)) : nil }
            .sorted()
    }
}
