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

    /// The same question on Polymarket, found after a watch (prd: the twin
    /// offer). nil most of the time — most markets have no counterpart.
    @State private var twin: PredictionTwin.Offer?

    /// Own venue by default — picking "Polymarket" or "All" shows that
    /// scope's browse content inline, without leaving this screen (prd §233,
    /// the wallet-switcher analogy: two chips stay two chips, the toggle
    /// lives inside each). Only ever offered once Polymarket is actually
    /// connected — see `polymarketConnected` below.
    @State private var venueScope: PredictionVenueScope = .kalshi

    private var polymarketConnected: Bool {
        store.bridges.contains(where: { $0.id == "polymarket" })
    }

    @AppStorage("coach.swipe.done") private var swipeCoachDone = false

    private var hintTokenID: UUID? {
        guard !swipeCoachDone else { return nil }
        return liveWatched.first?.id
    }

    private func loadWatched() {
        watched = recentBridgeThings(source: "Kalshi", context: modelContext)
    }

    /// A settled market can never move again, so it stops being a WATCH and
    /// becomes a record — split here so the watchlist reads as what you're
    /// actually following, not a graveyard of finished questions.
    private var liveWatched: [Thing] { watched.filter { $0.isLive && $0.marketResolvedYes == nil } }
    private var settledWatched: [Thing] { watched.filter { $0.isLive && $0.marketResolvedYes != nil } }

    var body: some View {
        List {
            BridgeSetupHeader(name: "Kalshi")
            addSection.listRowSeparator(.hidden)
            if !liveWatched.isEmpty {
                watchlistSection.listRowSeparator(.hidden)
            }
            if !settledWatched.isEmpty {
                settledSection.listRowSeparator(.hidden)
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
        // Runs only once there's actually a query to search — an empty
        // field's browse is the dedicated section below now, not this flat
        // hit list (prd §233).
        .task(id: queryField) {
            let q = queryField.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !q.isEmpty else { hits = []; return }
            if let found = await debouncedSearch(q, fetch: { await KalshiWatch.search(q) }) {
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
                if !queryField.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
                    if let twin {
                        // The other exchange prices the same question. Watching
                        // both is what makes the disagreement visible at all.
                        BridgeSearchResultRow(
                            imageURL: nil, fallbackIcon: twin.source.rawValue,
                            title: twin.line,
                            subtitle: String(localized: "Watch it on \(twin.source.rawValue) too"),
                            action: { acceptTwin(twin) })
                    }
                } else {
                    if polymarketConnected {
                        PredictionVenueSwitcher(scope: $venueScope)
                            .padding(.bottom, DS.Space.s1)
                    }
                    PredictionBrowseSection(
                        scope: venueScope,
                        onWatchedKalshi: { thing in
                            result = String(localized: "Watching \(thing.title)")
                            resultIsError = false
                            loadWatched()
                            register()
                        },
                        onWatchedPolymarket: { thing in
                            result = String(localized: "Watching \(thing.title) on Polymarket")
                            resultIsError = false
                            registerPredictionBridge(source: "Polymarket", id: "polymarket",
                                                     store: store, context: modelContext)
                        })
                }
                DSSlabNote(text: "Public odds only — nothing here places a trade.")
            }
        }
        .dsSlabSection()
    }

    /// Same swipe grammar as every watchlist screen (Tokens, Wallet):
    /// full trailing swipe pins, the explicit group carries Unwatch.
    /// Unwatching deletes the thing — the thing IS the watch.
    /// Finished questions, kept but set apart — the record of what you were
    /// watching and how it turned out. Not swipeable-to-unwatch by accident:
    /// same gesture, but these are history, so the list leads with the answer.
    private var settledSection: some View {
        Section {
            ForEach(settledWatched.keyed) { row in
                // Corollary 3 (build 176) — see `ThingRowKeying`.
                if let thing = row.live {
                    HStack(spacing: DS.Space.s3) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(thing.title)
                                .dsText(.body17).foregroundStyle(DS.textSecondary)
                                .lineLimit(2)
                            if let watched = thing.watchPriceUsd {
                                Text("You watched at \(Int((watched * 100).rounded()))%")
                                    .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                            }
                        }
                        Spacer(minLength: DS.Space.s2)
                        Text(thing.marketResolvedYes == true ? "Yes" : "No")
                            .dsText(.body17).fontWeight(.bold)
                            .foregroundStyle(DS.textPrimary)
                    }
                    .dsListCardRow()
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            if let i = watched.firstIndex(where: { $0.id == thing.id }) {
                                unwatch(at: IndexSet(integer: i))
                            }
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                    // A swipe has no Mac-mouse equivalent — right-click mirrors it
                    // (Mac polish, 2026-07-28).
                    .contextMenu {
                        Button(role: .destructive) {
                            if let i = watched.firstIndex(where: { $0.id == thing.id }) {
                                unwatch(at: IndexSet(integer: i))
                            }
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                }
            }
        } header: {
            Text("Resolved").dsText(.label12)
                .foregroundStyle(DS.textTertiary)
        } footer: {
            Text("These can't move again — they're a record of what you were watching.")
                .dsText(.callout15).foregroundStyle(DS.textTertiary)
        }
    }

    private var watchlistSection: some View {
        Section {
            ForEach(liveWatched.keyed) { row in
                // Corollary 3 (build 176) — see `ThingRowKeying`.
                if let thing = row.live {
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
                    // A swipe has no Mac-mouse equivalent — right-click mirrors it
                    // (Mac polish, 2026-07-28).
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
            // …and ask Polymarket whether it prices the same question.
            // Fire-and-forget: no twin is the common case and says nothing.
            twin = nil
            let prediction = PredictionMarket(
                source: .kalshi, id: market.ticker, title: market.title,
                subtitle: market.subtitle, url: thing.content,
                probability: market.probability, volume: market.volume,
                resolved: false, yesWon: nil, closeTime: market.closeTime)
            Task { twin = await PredictionTwin.find(for: prediction, context: modelContext) }
        } else {
            result = String(localized: "\(market.title) is already on your watchlist.")
        }
    }

    private func acceptTwin(_ offer: PredictionTwin.Offer) {
        DSHaptic.tap()
        PredictionTwin.accept(offer, context: modelContext)
        twin = nil
        result = String(localized: "Watching it on \(offer.source.rawValue) too.")
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
