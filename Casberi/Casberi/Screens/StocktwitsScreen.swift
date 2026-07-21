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
    /// The corpus rows, split by what they are: the watchlist (one row per
    /// ticker — the watch itself) and the latest landed posts.
    @State private var watched: [Thing] = []
    @State private var posts: [Thing] = []
    @State private var syncing = false
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

    /// The one swipe lesson, shared across every screen that teaches by
    /// swipe — whichever screen a person meets the gesture on first retires
    /// it everywhere (the TokenWatchScreen grammar).
    @AppStorage("coach.swipe.done") private var swipeCoachDone = false

    /// The row that plays the swipe demo — the first watched stock, once
    /// ever, retiring the moment any screen's demo (or a real swipe) does.
    private var hintStockID: UUID? {
        guard !swipeCoachDone else { return nil }
        return watched.first?.id
    }

    var body: some View {
        List {
            BridgeSetupHeader(name: "Stocktwits")
            addSection.listRowSeparator(.hidden)
            if !watched.isEmpty {
                watchlistSection.listRowSeparator(.hidden)
            }
            if !posts.isEmpty {
                RecentThingsSection(header: String(localized: "Latest takes"),
                                    things: posts, titleLines: 2)
                    .listRowSeparator(.hidden)
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
        .dsSoftTopEdge()
        .navigationTitle("Stocktwits")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            load()
            // Opening the screen doesn't connect — watching a ticker does.
            // Only refresh when something's already watched.
            if !watched.isEmpty { Task { await sync() } }
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
            BridgeFieldRow(placeholder: String(localized: "Ticker or company name"),
                           text: $queryField,
                           buttonLabel: String(localized: "Watch"), action: watch)
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
        } header: {
            Text("Watch a stock").dsText(.label12)
                .foregroundStyle(DS.textTertiary)
        } footer: {
            Text("Type a ticker or company name — matches appear as you type. A watched stock's live chart lands in your feed, and the most-followed takes about it land on each visit.")
                .dsText(.callout15).foregroundStyle(DS.textTertiary)
        }
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

    /// The watchlist manages itself the way Tokens' does — swipe to unwatch;
    /// unwatching deletes the thing (the thing IS the watch), and its
    /// sourceRef leaving the store lets a re-add resolve.
    private var watchlistSection: some View {
        Section {
            ForEach(watched) { thing in
                VStack(alignment: .leading, spacing: 2) {
                    Text(thing.title)
                        .dsText(.body17).foregroundStyle(DS.textPrimary)
                        .lineLimit(2)
                    Text(LiveTimeText.short(thing.capturedAt))
                        .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                }
                .dsListCardRow()
                .modifier(SwipeHintNudge(active: thing.id == hintStockID) { swipeCoachDone = true })
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        if let i = watched.firstIndex(where: { $0.id == thing.id }) {
                            unwatch(at: IndexSet(integer: i))
                        }
                    } label: {
                        Label("Unwatch", systemImage: "trash")
                    }
                }
            }
            .onDelete(perform: unwatch)
        } header: {
            Text("Watchlist").dsText(.label12)
                .foregroundStyle(DS.textTertiary)
        } footer: {
            Text("Swipe a stock to stop watching it. Its landed takes stay unless you remove them below.")
                .dsText(.callout15).foregroundStyle(DS.textTertiary)
        }
    }

    private var footerSection: some View {
        Section {
            Text("Takes are what traders post publicly on Stocktwits — each bullish or bearish call is its author's, never a rating of ours. Charts draw from public market data on this iPhone. Read-only: nothing here trades or sees a portfolio.")
                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                .listRowBackground(Color.clear)
        }
    }

    // MARK: - Actions

    private func load() {
        // Unbounded on purpose: the watchlist is bounded by the person's own
        // taps, and a fetch limit here once let accumulating posts push
        // watch rows out of the list while they were still watched (review
        // 2026-07-15). Posts cap for display only.
        let descriptor = FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == "Stocktwits" },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
        )
        let things = (try? modelContext.fetch(descriptor)) ?? []
        watched = things.filter { $0.sourceRef?.hasPrefix("stocktwits:sym:") == true }
        posts = Array(things.filter { $0.sourceRef?.hasPrefix("stocktwits:msg:") == true }
            .prefix(8))
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
