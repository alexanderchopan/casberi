import SwiftUI
import SwiftData

/// Kalshi, connected — the prediction-market watch screen. Search a team or
/// event; the busiest matching market resolves through Kalshi's public open
/// events (no key) and joins your watchlist as a thing whose sheet shows its
/// live odds. Read-only public price data — no account, no trading.
struct KalshiScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @State private var queryField = ""
    @State private var working = false
    @State private var result: String?
    @State private var resultIsError = false
    @State private var watched: [Thing] = []

    /// Markets matching what's typed so far, busiest first, UNFILTERED — the
    /// field doubles as a finder. Kept unfiltered (not just the not-yet-
    /// watched ones) so the Watch button can reuse `hits.first` as the exact
    /// answer a fresh resolve() would give. Cleared on watch and on emptying.
    @State private var hits: [KalshiWatch.Resolved] = []

    /// What the search rows actually show — already-watched markets are in
    /// the watchlist below, so they drop out here for display only.
    private var displayHits: [KalshiWatch.Resolved] {
        let refs = Set(watched.compactMap(\.sourceRef))
        return hits.filter { !refs.contains("kalshi:\($0.ticker)") }
    }

    @AppStorage("coach.swipe.done") private var swipeCoachDone = false

    private var hintTokenID: UUID? {
        guard !swipeCoachDone else { return nil }
        return watched.first?.id
    }

    private func loadWatched() {
        watched = recentBridgeThings(source: "Kalshi", context: modelContext)
    }

    var body: some View {
        List {
            BridgeSetupHeader(name: "Kalshi")
            addSection.listRowSeparator(.hidden)
            if !watched.isEmpty {
                watchlistSection.listRowSeparator(.hidden)
            }
            if !watched.isEmpty {
                // A watched market IS its thing, so there's no separate store
                // to clear — "Remove its things too" is what drops the watchlist.
                BridgeDisconnectSection(bridgeID: "kalshi", name: "Kalshi",
                                        teardown: {})
                    .listRowSeparator(.hidden)
            }
            footerSection.listRowSeparator(.hidden)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .bridgeSetupWash(name: "Kalshi")
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .dsScreenTitle("Kalshi")
        .onAppear { loadWatched() }
        // minLength: 0 — unlike every other bridge's finder, an empty query
        // isn't "nothing to show": KalshiWatch.search("") already returns the
        // busiest open markets (no text filter applied), so the screen leads
        // with live odds to browse, not a blank field waiting for input.
        .task(id: queryField) {
            let q = queryField.trimmingCharacters(in: .whitespacesAndNewlines)
            if let found = await debouncedSearch(q, minLength: 0, fetch: { await KalshiWatch.search(q) }) {
                hits = found
            }
        }
    }

    private var addSection: some View {
        // Field + search hits + status in ONE list row (a VStack) — a headed
        // Section of stacked rows leaks a hairline between them that row-level
        // .listRowSeparator(.hidden) won't suppress (SwiftUI first-post-header
        // separator). Design law: no hairlines, zero exceptions.
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                DSSlabField(placeholder: String(localized: "Team, player, or event"),
                            text: $queryField, actionLabel: String(localized: "WATCH"),
                            action: watch)
                ForEach(displayHits) { market in
                    BridgeSearchResultRow(
                        imageURL: nil, fallbackIcon: "Kalshi",
                        title: market.title,
                        subtitle: "\(Int((market.probability * 100).rounded()))% · \(market.subtitle)",
                        action: { watchHit(market) })
                }
                BridgeSyncStatusRows(syncing: working,
                                     syncingLine: String(localized: "Finding the market…"),
                                     result: result, resultIsError: resultIsError)
                DSSlabNote(text: "Public odds only — nothing here places a trade.")
            }
        }
        .dsSlabSection()
    }

    /// Same swipe grammar as every watchlist screen (Tokens, Wallet):
    /// full trailing swipe pins, the explicit group carries Unwatch.
    /// Unwatching deletes the thing — the thing IS the watch.
    private var watchlistSection: some View {
        Section {
            ForEach(watched.keyed) { row in
                let thing = row.thing
                VStack(alignment: .leading, spacing: 2) {
                    Text(thing.title)
                        .dsText(.body17).foregroundStyle(DS.textPrimary)
                        .lineLimit(2)
                    Text(LiveTimeText.short(thing.capturedAt))
                        .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                }
                .dsListCardRow()
                .modifier(SwipeHintNudge(active: thing.id == hintTokenID) { swipeCoachDone = true })
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
            Text("Swipe a market to stop watching it.")
                .dsText(.callout15).foregroundStyle(DS.textTertiary)
        }
    }

    private var footerSection: some View {
        Section {
            Text("Public odds from Kalshi, a CFTC-regulated exchange — nothing about you leaves your iPhone.\n\nRead-only: nothing here places a trade. Opens on Kalshi.")
                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                .listRowBackground(Color.clear)
        }
    }

    private func unwatch(at offsets: IndexSet) {
        let dropped = offsets.map { watched[$0] }
        SpotlightIndex.remove(ids: dropped.map(\.id))
        for thing in dropped { modelContext.delete(thing) }
        modelContext.saveHonestly()
        DSHaptic.tap()
        loadWatched()
        register()
    }

    private func watch() {
        let q = queryField.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !working else { return }
        DSHaptic.tap()
        if let top = hits.first {
            add(top)
            return
        }
        working = true
        Task {
            let market = await KalshiWatch.resolve(q)
            working = false
            guard let market else {
                result = String(localized: "Couldn't find an open market for that — try a team name.")
                resultIsError = true
                return
            }
            add(market)
        }
    }

    private func watchHit(_ market: KalshiWatch.Resolved) {
        guard !working else { return }
        DSHaptic.tap()
        add(market)
    }

    private func add(_ market: KalshiWatch.Resolved) {
        resultIsError = false
        if let thing = KalshiWatch.add(market, context: modelContext) {
            result = String(localized: "Watching \(thing.title)")
            queryField = ""
            hits = []
            loadWatched()
            register()
        } else {
            result = String(localized: "\(market.title) is already on your watchlist.")
        }
    }

    private func register() {
        let proof = "\(watched.count) market\(watched.count == 1 ? "" : "s") watched"
        if let existing = store.bridges.first(where: { $0.name == "Kalshi" }) {
            store.reconnect(existing.id, proof: proof)
        } else {
            store.bridges.append(BridgeApp(
                id: "kalshi", name: "Kalshi", status: .connected,
                statusLine: proof,
                can: ["Watches the markets you add.", "Read-only — public odds, no trading."]
            ))
            DSHaptic.success()
        }
    }
}
