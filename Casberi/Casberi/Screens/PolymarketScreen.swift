import SwiftUI
import SwiftData

/// Polymarket, connected — the onchain prediction-market watch screen.
/// Search any question; the busiest matching market resolves through
/// Polymarket's public Gamma API (no key, no wallet) and joins your
/// watchlist as a thing whose sheet shows its live odds and real price
/// curve. Read-only public price data — no account, no trading.
struct PolymarketScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @State private var queryField = ""
    @State private var working = false
    @State private var result: String?
    @State private var resultIsError = false
    @State private var watched: [Thing] = []

    /// Matching what's typed so far, busiest first, UNFILTERED — the field
    /// doubles as a finder. Kept unfiltered so the Watch button can reuse
    /// `hits.first` as the exact answer a fresh resolve() would give.
    @State private var hits: [PolymarketBridge.Resolved] = []

    /// What the search rows actually show — already-watched markets are in
    /// the watchlist below, so they drop out here for display only.
    private var displayHits: [PolymarketBridge.Resolved] {
        let refs = Set(watched.compactMap(\.sourceRef))
        return hits.filter { !refs.contains("polymarket:\($0.conditionId)") }
    }

    /// The same question on Kalshi, found after a watch — the twin offer.
    @State private var twin: PredictionTwin.Offer?

    @AppStorage("coach.swipe.done") private var swipeCoachDone = false

    private var hintTokenID: UUID? {
        guard !swipeCoachDone else { return nil }
        return liveWatched.first?.id
    }

    /// A settled market can never move again — it stops being a WATCH and
    /// becomes a record, so the watchlist reads as what you're following.
    private var liveWatched: [Thing] { watched.filter { $0.isLive && $0.marketResolvedYes == nil } }
    private var settledWatched: [Thing] { watched.filter { $0.isLive && $0.marketResolvedYes != nil } }

    private func loadWatched() {
        watched = recentBridgeThings(source: "Polymarket", context: modelContext)
    }

    var body: some View {
        List {
            BridgeSetupHeader(name: "Polymarket")
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
                BridgeDisconnectSection(bridgeID: "polymarket", name: "Polymarket",
                                        teardown: {})
                    .listRowSeparator(.hidden)
            }
            footerSection.listRowSeparator(.hidden)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .bridgeSetupWash(name: "Polymarket")
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .dsScreenTitle("Polymarket")
        .onAppear { loadWatched() }
        // minLength: 0 — an empty query still shows the busiest open
        // markets to browse, the same dose as Kalshi's own finder.
        .task(id: queryField) {
            let q = queryField.trimmingCharacters(in: .whitespacesAndNewlines)
            if let found = await debouncedSearch(q, minLength: 0, fetch: { await PolymarketBridge.search(q) }) {
                hits = found
            }
        }
    }

    private var addSection: some View {
        // Field + search hits + status in ONE list row (a VStack) — a headed
        // Section of stacked rows leaks a hairline between them that row-level
        // .listRowSeparator(.hidden) won't suppress. Design law: no
        // hairlines, zero exceptions.
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                DSSlabField(placeholder: String(localized: "Any question or topic"),
                            text: $queryField, actionLabel: String(localized: "WATCH"),
                            action: watch)
                ForEach(displayHits) { market in
                    BridgeSearchResultRow(
                        imageURL: nil, fallbackIcon: "Polymarket",
                        title: market.title,
                        subtitle: "\(Int((market.probability * 100).rounded()))%" + (market.subtitle.isEmpty ? "" : " · \(market.subtitle)"),
                        action: { watchHit(market) })
                }
                BridgeSyncStatusRows(syncing: working,
                                     syncingLine: String(localized: "Finding the market…"),
                                     result: result, resultIsError: resultIsError)
                if let twin {
                    BridgeSearchResultRow(
                        imageURL: nil, fallbackIcon: twin.source.rawValue,
                        title: twin.line,
                        subtitle: String(localized: "Watch it on \(twin.source.rawValue) too"),
                        action: { acceptTwin(twin) })
                }
                DSSlabNote(text: "Public odds only — nothing here places a trade.")
            }
        }
        .dsSlabSection()
    }

    /// Finished questions, kept but set apart — the record of what you were
    /// watching and how it turned out.
    private var settledSection: some View {
        Section {
            ForEach(settledWatched.keyed) { row in
                let thing = row.thing
                HStack(spacing: DS.Space.s3) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(thing.title)
                            .dsText(.body17).foregroundStyle(DS.textSecondary)
                            .lineLimit(2)
                        if let at = thing.watchPriceUsd {
                            Text("You watched at \(Int((at * 100).rounded()))%")
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
        } header: {
            Text("Resolved").dsText(.label12)
                .foregroundStyle(DS.textTertiary)
        } footer: {
            Text("These can\u{2019}t move again — they\u{2019}re a record of what you were watching.")
                .dsText(.callout15).foregroundStyle(DS.textTertiary)
        }
    }

    /// Same swipe grammar as every watchlist screen (Tokens, Kalshi, Wallet):
    /// full trailing swipe pins, the explicit group carries Unwatch.
    /// Unwatching deletes the thing — the thing IS the watch.
    private var watchlistSection: some View {
        Section {
            ForEach(liveWatched.keyed) { row in
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
            Text("Public odds from Polymarket's onchain order book — nothing about you leaves your iPhone.\n\nRead-only: nothing here places a trade. Opens on Polymarket.")
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
            let market = await PolymarketBridge.resolve(q)
            working = false
            guard let market else {
                result = String(localized: "Couldn't find an open market for that — try another word.")
                resultIsError = true
                return
            }
            add(market)
        }
    }

    private func watchHit(_ market: PolymarketBridge.Resolved) {
        guard !working else { return }
        DSHaptic.tap()
        add(market)
    }

    private func add(_ market: PolymarketBridge.Resolved) {
        resultIsError = false
        if let thing = PolymarketBridge.add(market, context: modelContext) {
            result = String(localized: "Watching \(thing.title)")
            queryField = ""
            hits = []
            loadWatched()
            register()
            // …and ask Kalshi whether it prices the same question.
            twin = nil
            Task { twin = await PredictionTwin.find(for: market.prediction, context: modelContext) }
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
        if let existing = store.bridges.first(where: { $0.name == "Polymarket" }) {
            store.reconnect(existing.id, proof: proof)
        } else {
            store.bridges.append(BridgeApp(
                id: "polymarket", name: "Polymarket", status: .connected,
                statusLine: proof,
                can: ["Watches the markets you add.", "Read-only — public odds, no trading."]
            ))
            DSHaptic.success()
        }
    }
}
