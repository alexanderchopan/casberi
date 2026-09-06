import SwiftUI
import SwiftData

/// Stocktwits, on the account page — watch any stock by its ticker. A watched
/// ticker is a thing whose sheet draws the live price chart (StockChart/Yahoo),
/// and the takes traders post about it on Stocktwits land as chat things, each
/// wearing its author's own Bullish/Bearish call. Keyless — Stocktwits'
/// public streams, the same REST its website reads. Read-only: nothing here
/// trades, and a watched ticker can never see a portfolio.
///
/// **ON `AccountPage` SINCE §639 (2026-09-06).** The watchlist was an
/// `AssetRosterShelf` — a horizontal shelf of ticker discs under a note line
/// coaching its own gestures ("Watching 3 · hold to unwatch"). It is the
/// page's "Watching · N" roster now: one row per ticker, the same list shape
/// every other seat's watched things wear, with the one removal verb. The
/// shelf's own coaching goes with it — a swipe and a right-click are the
/// chassis's, and a control that has to explain itself in a caption was the
/// thing §639 was fixing.
struct StocktwitsScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    /// The page's one bar (§639 amendment) — the ticker to add, and the filter
    /// over the tickers already watched.
    @State private var queryField = ""
    @State private var working = false
    @State private var result: BridgeProof?
    /// The watchlist rows — one per ticker, the watch itself. The landed
    /// posts no longer preview here (prd §185, the recents ruling: the feed
    /// shows what landed, a manager manages).
    @State private var watched: [Thing] = []
    @State private var syncing = false
    /// Each watched ticker's live day quote (price + change), fetched on
    /// appear from the same Yahoo read the chart sheet does — the row's one
    /// live fact (prd §185). A ticker Yahoo won't serve simply shows its
    /// exchange instead, the honest fallback.
    @State private var quotes: [String: TokenChart] = [:]
    /// A ticker watched while a sync is mid-flight requeues the sync so its
    /// posts land now, not next visit (the GeckoTerminal lesson).
    @State private var syncPending = false
    /// This week's landed takes per ticker, for the roster's own subline and
    /// its active/quiet split.
    @State private var weekly: [String: (week: Int, new: Bool)] = [:]

    /// Symbols matching what's typed so far — Stocktwits' own autocomplete
    /// order, unfiltered so the Watch button can reuse `hits.first` as the
    /// exact answer a fresh resolve() would give (the TokenWatch pattern).
    @State private var hits: [StockWatch.Resolved] = []
    /// The query `hits` answers — the Watch button trusts hits.first only
    /// when it matches the field NOW, else an edit inside the debounce
    /// window would watch the previous query's top match.
    @State private var hitsQuery = ""

    /// What the search rows actually show — already-watched tickers are in
    /// the roster below, so they drop out here for display only.
    private var displayHits: [StockWatch.Resolved] {
        let refs = Set(watched.compactMap(\.sourceRef))
        return hits.filter { !refs.contains(StockWatch.symbolRef($0.symbol)) }
    }

    @FocusState private var fieldFocused: Bool
    /// The page's one presentation. A roster row's tap opens its chart, and
    /// the chassis raises it — see `AccountPageSheet.thing`.
    @State private var sheet: AccountPageSheet?

    private var connected: Bool { !watched.isEmpty }

    var body: some View {
        AccountPage(
            name: "Stocktwits", seatID: "stocktwits", source: "Stocktwits",
            state: AccountPageState.of(name: "Stocktwits", seatID: "stocktwits",
                                       connected: connected, store: store),
            intro: "Watch a ticker below by symbol or company name.",
            mode: .noAccount,
            rows: rows,
            query: queryField,
            onRemoveRow: unwatch,
            onOpenRow: openTicker,
            // A watched ticker IS its thing — no separate store to clear.
            // Teardown drops the WATCHLIST rows (the watch is access — a kept
            // watch row would re-register the seat on the next visit and keep
            // the foreground poll landing posts); the posts are history and
            // follow the person's own "remove its things too" choice.
            teardown: {
                StockWatch.unwatchAll(context: modelContext)
                load()
            },
            sheet: $sheet,
            act: { actBlock },
            more: { EmptyView() },
            keySheet: { EmptyView() }
        )
        .onAppear {
            load()
            // Opening the page doesn't connect — watching a ticker does.
            // Only refresh when something's already watched.
            if connected {
                Task { await sync() }
                Task { await loadQuotes() }
            }
        }
        // The debounced ticker search.
        .task(id: queryField) {
            let q = queryField.trimmingCharacters(in: .whitespacesAndNewlines)
            if let found = await debouncedSearch(q, fetch: { await StockWatch.search(q) }) {
                hits = found
                hitsQuery = q
            }
        }
    }

    // MARK: - The act field

    @ViewBuilder private var actBlock: some View {
        DSSlabField(placeholder: connected
                        ? AccountPageShape.findPlaceholder(String(localized: "a ticker"))
                        : String(localized: "Ticker or company name"),
                    text: $queryField, actionLabel: String(localized: "Watch"),
                    focus: $fieldFocused, action: watch)
        if !displayHits.isEmpty {
            Text(AccountPageShape.onLabel("Stocktwits"))
                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                .padding(.top, DS.Space.s2)
        }
        ForEach(displayHits) { stock in
            BridgeSearchResultRow(
                imageURL: nil, fallbackIcon: "Stocktwits",
                title: "\(stock.title) · $\(stock.symbol)",
                subtitle: subtitle(for: stock),
                action: { watchHit(stock) })
        }
        BridgeSyncStatusRows(syncing: working || syncing,
                             syncingLine: working
                                ? String(localized: "Finding the ticker…")
                                : String(localized: "Syncing takes…"),
                             proof: result)
        // The intro sentence is pure action, on purpose — this note carries
        // the load-bearing honesty fact instead: a take is its author's
        // opinion, not a rating this app computed. Presenting somebody's
        // bullish call as though we endorsed it is exactly the fake status §83
        // bans, so the fact stays here, beside the field that starts the
        // watching.
        DSSlabNote(text: "Read-only — nothing trades or sees a portfolio. Every bullish or bearish take is its author's.",
                   plain: true)
    }

    /// "NASDAQ · 982K watching" — the exchange names the market, the count
    /// is Stocktwits' own watchlist number (scale, not endorsement).
    private func subtitle(for stock: StockWatch.Resolved) -> String {
        var parts: [String] = []
        if !stock.exchange.isEmpty { parts.append(stock.exchange) }
        if stock.watchers > 0 { parts.append("\(compact(stock.watchers)) watching") }
        return parts.joined(separator: " · ")
    }

    private func compact(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.0fK", Double(n) / 1_000) }
        return String(n)
    }

    // MARK: - The roster

    /// One row per watched ticker: the COMPANY's name as the title (the ticker
    /// is in the subline, and printing it twice reads as a stutter), the live
    /// day quote where Yahoo served one, and this week's takes where it did
    /// not. No quote renders no figure rather than a placeholder — unreachable
    /// is a fact we don't have.
    ///
    /// Keyed on the thing's id captured while the model is valid, and every
    /// stored read happens HERE, in one pass, rather than inside a row body
    /// SwiftUI may re-run against a deleted model (`ThingRowKeying`, corollary
    /// 3): the chassis is handed values, not models.
    private var rows: [AccountPageShape.Row] {
        watched.filter(\.isLive).map { thing in
            let symbol = ticker(for: thing)
            let counted = weekly[symbol] ?? (week: 0, new: false)
            return AccountPageShape.Row(
                id: thing.id.uuidString,
                title: companyName(thing, fallback: symbol),
                subline: subline(symbol: symbol, week: counted.week),
                weekCount: counted.week, hasNew: counted.new,
                isYou: false, avatarURL: nil)
        }
    }

    /// "$226.10 · +1.2% · 4 takes this week" — the live day quote first (the
    /// row's one live fact, §185), then the week the whole roster grammar is
    /// built on. A ticker Yahoo won't serve simply drops the first half; no
    /// quote renders no figure rather than a placeholder, because unreachable
    /// is a fact we don't have.
    private func subline(symbol: String, week: Int) -> String {
        let counted = AccountPageShape.subline(nouns: String(localized: "takes"), weekCount: week)
        guard let quote = quotes[symbol] else { return counted }
        return "\(TokenChartStyle.priceText(quote.price)) · \(TokenChartStyle.changeText(quote.change)) · \(counted)"
    }

    private func openTicker(_ id: String) {
        guard let uuid = UUID(uuidString: id) else { return }
        sheet = .thing(id: uuid)
    }

    private func unwatch(_ id: String) {
        guard let i = watched.firstIndex(where: { $0.id.uuidString == id }) else { return }
        unwatch(at: IndexSet(integer: i))
    }

    /// The company's own name, off the front of the watch title
    /// ("Apple Inc · $AAPL" → "Apple Inc"). Falls back to the ticker when a
    /// title doesn't carry one, so a row is never blank.
    private func companyName(_ thing: Thing, fallback: String) -> String {
        let name = thing.title.split(separator: "·").first
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        return name.isEmpty ? fallback : name
    }

    /// The ticker behind a watchlist thing — its sourceRef minus the prefix.
    private func ticker(for thing: Thing) -> String {
        let prefix = "stocktwits:sym:"
        guard let ref = thing.sourceRef, ref.hasPrefix(prefix) else { return "" }
        return String(ref.dropFirst(prefix.count))
    }

    /// One day-quote per watched ticker, concurrently — the chart sheet's
    /// exact fetch (hosts, UA quirk, symbol mapping all in StockChart), so
    /// this line can never disagree with the chart behind the row's tap.
    private func loadQuotes() async {
        let tickers = watched.filter(\.isLive).map(ticker(for:)).filter { !$0.isEmpty }
        guard !tickers.isEmpty else { return }
        await withTaskGroup(of: (String, TokenChart?).self) { group in
            for t in tickers where quotes[t] == nil {
                group.addTask { (t, await StockChart.fetch(ticker: t, range: .day)) }
            }
            for await (t, chart) in group {
                if let chart { quotes[t] = chart }
            }
        }
    }

    // MARK: - Actions

    private func load() {
        // Unbounded on purpose: the watchlist is bounded by the person's own
        // taps, and a fetch limit here once let accumulating posts push
        // watch rows out of the list while they were still watched (review
        // 2026-07-15).
        let descriptor = FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == "Stocktwits" },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
        )
        let things = ((try? modelContext.fetch(descriptor)) ?? []).filter(\.isLive)
        watched = things.filter { $0.sourceRef?.hasPrefix("stocktwits:sym:") == true }
        countWeek(things)
    }

    /// This week's takes per ticker. A take carries every ticker it names in
    /// `tags`, the STREAM's symbol first (`StocktwitsIngest`'s own ordering),
    /// so a post that landed from $AAPL while arguing about $MSFT counts once,
    /// under the stream the person actually watches. Read in Swift, never as a
    /// predicate — a `.contains` on a transformable array crashes mid-fetch
    /// (CLAUDE.md's own rule).
    private func countWeek(_ things: [Thing]) {
        let since = Date.now.addingTimeInterval(-7 * 86_400)
        let lastLooked = AccountVisits.lastLooked("stocktwits")
        var book: [String: (week: Int, new: Bool)] = [:]
        for thing in things where thing.capturedAt >= since && thing.kind == .chat {
            guard let symbol = thing.tags.first?.uppercased(), !symbol.isEmpty else { continue }
            let was = book[symbol] ?? (0, false)
            book[symbol] = (was.week + 1,
                            was.new || (lastLooked.map { thing.capturedAt > $0 } ?? false))
        }
        weekly = book
    }

    private func unwatch(at offsets: IndexSet) {
        let dropped = offsets.map { watched[$0] }
        SpotlightIndex.remove(ids: dropped.map(\.id))
        for thing in dropped { modelContext.delete(thing) }
        modelContext.saveHonestly()
        DSHaptic.tap()
        load()
        StockWatch.registerBridge(store: store, context: modelContext)
    }

    private func watch() {
        let q = queryField.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !working else { return }
        DSHaptic.tap()
        // The debounced search already ran this exact query — its top hit
        // IS what a fresh resolve() would return. Only when it really was
        // THIS query: mid-debounce, hits still answer the previous text.
        if hitsQuery == q, let top = hits.first {
            add(top)
            return
        }
        working = true
        Task {
            let stock = await StockWatch.resolve(q)
            working = false
            guard let stock else {
                result = .failed(String(localized: "Couldn't find that ticker on Stocktwits."))
                return
            }
            add(stock)
        }
    }

    private func watchHit(_ stock: StockWatch.Resolved) {
        guard !working else { return }
        DSHaptic.tap()
        add(stock)
    }

    private func add(_ stock: StockWatch.Resolved) {
        guard let thing = StockWatch.add(stock, context: modelContext) else {
            result = .says(String(localized: "\(stock.title) is already on your watchlist."))
            return
        }
        result = .says(String(localized: "Watching \(thing.title)"))
        queryField = ""
        hits = []
        load()
        StockWatch.registerBridge(store: store, context: modelContext)
        Task { await sync() }
        Task { await loadQuotes() }
    }

    /// Fetch + land the watched tickers' latest takes; the seat's status
    /// line carries the proof.
    private func sync() async {
        if syncing { syncPending = true; return }
        syncing = true
        defer { syncing = false }
        repeat {
            syncPending = false
            let added = await StocktwitsIngest.refresh(context: modelContext)
            load()
            // registerBridge owns the seat rule — it clears the seat itself
            // when the last watch is gone (disconnect mid-sync included).
            StockWatch.registerBridge(store: store, context: modelContext)
            guard connected else { return }
            if let added {
                result = .landed(added)
            } else {
                result = .failed(String(localized: "Couldn't reach Stocktwits — check your connection."))
            }
        } while syncPending
    }
}
