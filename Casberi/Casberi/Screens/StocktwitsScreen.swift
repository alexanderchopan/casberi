import SwiftUI
import SwiftData

/// Stocktwits, connected — watch any stock by its ticker. A watched ticker is
/// a thing whose sheet draws the live price chart (StockChart/Yahoo), and the
/// takes traders post about it on Stocktwits land as chat things, each
/// wearing its author's own Bullish/Bearish call. Keyless — Stocktwits'
/// public streams, the same REST its website reads. Read-only: nothing here
/// trades, and a watched ticker can never see a portfolio.
struct StocktwitsScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @State private var queryField = ""
    @State private var working = false
    @State private var result: String?
    @State private var resultIsError = false
    /// The watchlist rows — one per ticker, the watch itself. The landed
    /// posts no longer preview here (prd §185, the recents ruling: the feed
    /// shows what landed, a manager manages).
    @State private var watched: [Thing] = []
    @State private var syncing = false
    /// Each watched ticker's live day quote (price + change), fetched on
    /// appear from the same Yahoo read the chart sheet does — the row's one
    /// live fact (prd §185). A ticker Yahoo won't serve simply shows its
    /// watched-since time instead, the honest fallback.
    @State private var quotes: [String: TokenChart] = [:]
    /// A ticker watched while a sync is mid-flight requeues the sync so its
    /// posts land now, not next visit (the GeckoTerminal lesson).
    @State private var syncPending = false

    /// Symbols matching what's typed so far — Stocktwits' own autocomplete
    /// order, unfiltered so the Watch button can reuse `hits.first` as the
    /// exact answer a fresh resolve() would give (the TokenWatch pattern).
    @State private var hits: [StockWatch.Resolved] = []
    /// The query `hits` answers — the Watch button trusts hits.first only
    /// when it matches the field NOW, else an edit inside the debounce
    /// window would watch the previous query's top match.
    @State private var hitsQuery = ""

    /// What the search rows actually show — already-watched tickers are in
    /// the watchlist below, so they drop out here for display only.
    private var displayHits: [StockWatch.Resolved] {
        let refs = Set(watched.compactMap(\.sourceRef))
        return hits.filter { !refs.contains(StockWatch.symbolRef($0.symbol)) }
    }

    @FocusState private var fieldFocused: Bool
    /// The stock whose chart sheet is open — a tapped disc on the roster
    /// (prd §185). The shelf states its own gestures in its note line, so
    /// there's no swipe left here to coach.
    @State private var openThing: Thing?

    var body: some View {
        List {
            // No header coin card, no "Latest takes" preview (prd §185) —
            // the omnibox leads, the roster follows, the feed already shows
            // what landed.
            addSection.listRowSeparator(.hidden)
            if !watched.isEmpty {
                watchlistSection
            }
            if !watched.isEmpty {
                // A watched ticker IS its thing — no separate store to clear;
                // "Remove its things too" is what drops the watchlist.
                // Teardown drops the WATCHLIST rows (the watch is access —
                // a kept watch row would re-register the seat on the next
                // visit and keep the foreground poll landing posts); the
                // posts are history and follow the person's own "remove its
                // things too" choice.
                BridgeDisconnectSection(bridgeID: "stocktwits", name: "Stocktwits",
                                        teardown: {
                                            StockWatch.unwatchAll(context: modelContext)
                                            load()
                                        })
                    .listRowSeparator(.hidden)
            }
            footerSection.listRowSeparator(.hidden)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .bridgeSetupWash(name: "Stocktwits")
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .navigationTitle("Stocktwits")
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $openThing) { thing in
            ThingSheetView(thing: thing)
        }
        .onAppear {
            load()
            // Opening the screen doesn't connect — watching a ticker does.
            // Only refresh when something's already watched.
            if !watched.isEmpty {
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

    // MARK: - Sections

    private var addSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
            DSSlabField(placeholder: String(localized: "Ticker or company name"),
                        text: $queryField, actionLabel: String(localized: "WATCH"),
                        focus: $fieldFocused, action: watch)
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
                                 result: result, resultIsError: resultIsError)
            DSSlabNote(text: "Read-only — nothing here trades or sees a portfolio.")
            }
        }
        .dsSlabSection()
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

    /// The watchlist as a roster of ticker discs (prd §185) — the same shelf
    /// of circles the wallet's addresses, the social screens' people, and
    /// Tokens' coins wear. A stock ships no logo, so its mark is the ticker
    /// itself in a round disc, never a faked one. Tap opens its chart; hold
    /// unwatches (the thing IS the watch, so unwatching deletes it, and its
    /// sourceRef leaving the store lets a re-add resolve).
    private var watchlistSection: some View {
        AssetRosterShelf(note: rosterNote) {
            ForEach(watched.keyed) { row in
                rosterSlot(row.thing)
            }
            AssetRosterAddSlot { fieldFocused = true }
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var rosterNote: String {
        let n = watched.count
        return n == 1
            ? String(localized: "Watching 1 · tap for its chart, hold to unwatch")
            : String(localized: "Watching \(n) · tap for its chart, hold to unwatch")
    }

    /// One stock on the shelf — its ticker disc, the COMPANY's name as the
    /// label, and the live day quote when Yahoo served one. The name rather
    /// than the ticker because the disc already says the ticker, and printing
    /// it twice reads as a stutter (the wallet roster's own rule, where an
    /// unnamed wallet drops the address line its name already is). No quote
    /// renders no figure rather than a placeholder: unreachable is a fact we
    /// don't have.
    private func rosterSlot(_ thing: Thing) -> some View {
        let symbol = ticker(for: thing)
        let quote = quotes[symbol]
        return AssetRosterSlot(label: companyName(thing, fallback: symbol),
                               price: quote?.price,
                               change: quote?.change) {
            TickerDisc(ticker: symbol)
        }
        .onTapGesture {
            DSHaptic.tap()
            openThing = thing
        }
        .contextMenu {
            Button(role: .destructive) {
                if let i = watched.firstIndex(where: { $0.id == thing.id }) {
                    unwatch(at: IndexSet(integer: i))
                }
            } label: {
                Label("Unwatch", systemImage: "trash")
            }
        }
    }

    /// The company's own name, off the front of the watch title
    /// ("Apple Inc · $AAPL" → "Apple Inc"). Falls back to the ticker when a
    /// title doesn't carry one, so a slot is never blank.
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
    /// this column can never disagree with the chart behind the row's tap.
    private func loadQuotes() async {
        let tickers = watched.map(ticker(for:)).filter { !$0.isEmpty }
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

    private var footerSection: some View {
        Section {
            Text("Takes are what traders post publicly on Stocktwits — each bullish or bearish call is its author's, never a rating of ours.\n\nCharts draw from public market data on this iPhone. Read-only: nothing here trades or sees a portfolio.")
                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                .listRowBackground(Color.clear)
        }
    }

    // MARK: - Actions

    private func load() {
        // Unbounded on purpose: the watchlist is bounded by the person's own
        // taps, and a fetch limit here once let accumulating posts push
        // watch rows out of the list while they were still watched (review
        // 2026-07-15). Landed posts aren't read here at all anymore — the
        // "Latest takes" preview retired with prd §185.
        let descriptor = FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == "Stocktwits" },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
        )
        let things = (try? modelContext.fetch(descriptor)) ?? []
        watched = things.filter { $0.sourceRef?.hasPrefix("stocktwits:sym:") == true }
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
                result = String(localized: "Couldn't find that ticker on Stocktwits.")
                resultIsError = true
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
        resultIsError = false
        guard let thing = StockWatch.add(stock, context: modelContext) else {
            result = String(localized: "\(stock.title) is already on your watchlist.")
            return
        }
        result = String(localized: "Watching \(thing.title)")
        queryField = ""
        hits = []
        load()
        StockWatch.registerBridge(store: store, context: modelContext)
        Task { await sync() }
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
            guard !watched.isEmpty else { return }
            if let added {
                result = added > 0 ? String(localized: "\(added) new")
                                   : String(localized: "Up to date")
                resultIsError = false
            } else {
                result = String(localized: "Couldn't reach Stocktwits — check your connection.")
                resultIsError = true
            }
        } while syncPending
    }
}
