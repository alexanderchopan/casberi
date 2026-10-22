import Foundation
import SwiftData

/// Following a coin by its own price (prd §1250; the rules are `CoinFollow`'s).
/// The follow, the launch sweep that converges the old wrapped and symbol-
/// matched token follows onto it, and CoinPaprika's two keyless reads: the
/// ticker (price, day move, cap, volume) and the historical ticks a chart and
/// the row's line draw. `api.coinpaprika.com` was declared for the index's
/// quotes (§1082); its image host is declared beside it.
@MainActor
enum CoinWatch {

    /// The index's coins, SYMBOL → CoinPaprika id (`CompanyPacks.makers`).
    static var indexCoins: [String: String] {
        var out: [String: String] = [:]
        for maker in CompanyPacks.makers.values {
            if case .token(let symbol, let id) = maker.listing { out[symbol.uppercased()] = id }
        }
        return out
    }

    /// The name the index knows a coin by ("Gnosis"), or nil.
    static func indexName(_ id: String) -> String? {
        CompanyPacks.makers.values.first { maker in
            if case .token(_, let paprika) = maker.listing { return paprika == id }
            return false
        }?.company
    }

    /// Follows a coin. Returns the new row, or nil when it is already
    /// followed. `price` is the price read with the choice, kept as the
    /// since-you-followed anchor; without one the anchor backfills from the
    /// ticker off the main path, or never lands (`StockWatch`'s precedent).
    @discardableResult
    static func add(id: String, name: String, symbol: String, price: Double?,
                    imageURL: String? = nil, context: ModelContext) -> Thing? {
        let ref = CoinFollow.ref(id)
        guard !IngestSupport.hasSourceRef(context, source: TokenWatch.source, ref: ref) else { return nil }
        let thing = Thing(
            kind: .link,
            title: TitleSeam.join(name, "$\(symbol)"),
            content: CoinFollow.page(id),
            source: TokenWatch.source,
            capturedAt: .now,
            tags: ["Watchlist"],
            sourceRef: ref
        )
        thing.watchPriceUsd = price.flatMap { $0 > 0 ? $0 : nil }
        thing.authorHandle = symbol
        // The DEX token's image when the search carried one (prd §1467),
        // else none: the letters draw (CoinPaprika's host is down, measured).
        thing.previewImageURL = imageURL
        context.insert(thing)
        context.saveHonestly()
        SpotlightIndex.index([thing])
        if thing.watchPriceUsd == nil, !DemoMode.isActive {
            Task { @MainActor in
                guard let read = await Self.ticker(id: id) else { return }
                // Re-fetched, not the captured row: an unfollow in between
                // would leave a deleted model.
                var d = FetchDescriptor<Thing>(predicate: #Predicate { $0.sourceRef == ref })
                d.fetchLimit = 1
                guard let live = try? context.fetch(d).first, live.isLive,
                      live.watchPriceUsd == nil else { return }
                live.watchPriceUsd = read.price
                context.saveHonestly()
            }
        }
        return thing
    }

    /// Follows a household coin by its native entry.
    @discardableResult
    static func add(_ coin: CoinFollow.Coin, price: Double?, context: ModelContext) -> Thing? {
        add(id: coin.id, name: coin.name, symbol: coin.symbol, price: price, context: context)
    }

    /// EVERY LAUNCH (§647), never a one-shot migration: a followed token that
    /// is a coin (`CoinFollow.convergence`) becomes the coin's follow IN PLACE
    /// — the same row, so when you followed it, the price then and its place
    /// in My order all stay — and its alerts move with its ref. A token whose
    /// coin is already followed folds into that row: its place and alerts go
    /// to the coin, the copy goes. A store with nothing to converge costs one
    /// fetch of Markets' rows; a second run finds nothing.
    /// EVERY LAUNCH (§647, prd §1467): a followed coin that pointed at
    /// CoinPaprika's image host (down, measured) points at nothing, so its
    /// letters draw instead of the broken-image glyph. Returns how many.
    @discardableResult
    static func clearDeadLogos(context: ModelContext) -> Int {
        let source = TokenWatch.source
        let rows = ((try? context.fetch(FetchDescriptor<Thing>(predicate: #Predicate { $0.source == source }))) ?? [])
            .filter { $0.isLive && ($0.previewImageURL?.hasPrefix(CoinFollow.deadLogoHost) ?? false) }
        for row in rows { row.previewImageURL = nil }
        if !rows.isEmpty { context.saveHonestly() }
        return rows.count
    }

    @discardableResult
    static func converge(context: ModelContext) -> Int {
        let source = TokenWatch.source
        let rows = ((try? context.fetch(FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == source }))) ?? [])
            .filter { $0.isLive && !PriceAlertStore.isAlertRow($0) }
        guard !rows.isEmpty else { return 0 }
        // Oldest first, so the follow that has stood longest is the one kept;
        // a row with no ref is no follow and is not handed in.
        let ordered = rows.filter { $0.sourceRef != nil }.sorted { $0.capturedAt < $1.capturedAt }
        let plan = CoinFollow.plan(ordered.map { thing in
            CoinFollow.Row(ref: thing.sourceRef ?? "",
                           symbol: thing.authorHandle ?? TokensAsk.symbol(of: thing.title),
                           capturedAt: thing.capturedAt)
        }, indexCoins: indexCoins)
        let map = plan.map
        var moved: [Thing] = []
        var folded: [Thing] = []
        for (thing, step) in zip(ordered, plan.steps) {
            let next: String
            switch step {
            case .stay:
                continue
            case .fold:
                folded.append(thing)
                continue
            case .move(let to):
                next = to
            }
            guard let id = CoinFollow.id(fromRef: next) else { continue }
            let native = CoinFollow.native(id)
            let symbol = native?.symbol ?? (thing.authorHandle ?? TokensAsk.symbol(of: thing.title)).uppercased()
            let name = native?.name ?? indexName(id) ?? TokensAsk.name(of: thing.title)
            thing.sourceRef = next
            thing.content = CoinFollow.page(id)
            thing.title = TitleSeam.join(name, "$\(symbol)")
            thing.authorHandle = symbol
            // The token row's image stays: it is the coin's (prd §1467).
            moved.append(thing)
        }
        guard !map.isEmpty else { return 0 }
        SpotlightIndex.remove(ids: folded.map(\.id))
        for thing in folded { context.delete(thing) }
        context.saveHonestly()
        SpotlightIndex.index(moved)
        if !TokenWatchOrder.shared.manual.isEmpty {
            TokenWatchOrder.shared.saveManual(
                CoinFollow.rewrite(order: TokenWatchOrder.shared.manual, map: map))
        }
        PriceAlertStore.shared.rewriteRefs(map)
        return map.count
    }

    // MARK: - CoinPaprika's reads

    /// The coin's ticker, or nil when CoinPaprika did not answer one.
    nonisolated static func ticker(id: String) async -> CoinFollow.Ticker? {
        CoinFollow.ticker(from: await IngestSupport.getJSON(CoinFollow.tickerURL(id)))
    }

    /// The row's heartbeat: the ticker, and the day's closes when the
    /// historical ticks answer (an empty line otherwise, never a made one).
    nonisolated static func pulse(id: String) async -> (ticker: CoinFollow.Ticker, closes: [Double])? {
        // No history URL is no history read: an empty address answers nil.
        let url = CoinFollow.historyURL(id, range: TokenRange.day.rawValue, now: .now) ?? ""
        async let tick = Self.ticker(id: id)
        async let history = IngestSupport.getJSON(url)
        guard let quote = await tick else { return nil }
        return (ticker: quote, closes: CoinFollow.closes(from: await history))
    }

    /// The coin's chart for a range, or nil when the range is not served (the
    /// hour) or the ticks did not answer: the chart then says the range is
    /// missing rather than drawing it from anything else. The figure is the
    /// ticker's live price when it answered, and the move is measured against
    /// it (`StockChart`'s rule: the percentage is about the number on screen).
    nonisolated static func chart(id: String, range: TokenRange) async -> TokenChart? {
        guard let url = CoinFollow.historyURL(id, range: range.rawValue, now: .now) else { return nil }
        async let history = IngestSupport.getJSON(url)
        async let tick = Self.ticker(id: id)
        let closes = CoinFollow.closes(from: await history)
        guard closes.count >= 2, let first = closes.first, let last = closes.last, first > 0
        else { return nil }
        let quote = await tick
        let price = quote?.price ?? last
        return TokenChart(closes: closes, price: price, change: (price - first) / first,
                          marketCap: quote?.marketCap)
    }
}
