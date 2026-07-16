import SwiftUI
import SwiftData

/// Tokens, connected (renamed from Dexscreener, 2026-07-13 — the chart itself
/// blends GeckoTerminal/Alchemy/Dexscreener, so one vendor's name overclaimed).
/// Paste a token (address, symbol, or link); it resolves through public
/// search and joins your watchlist as a thing whose sheet draws its live
/// price chart. Read-only public price data — no wallet, no account, no
/// trading.
struct TokenWatchScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @State private var queryField = ""
    @State private var working = false
    @State private var result: String?
    @State private var resultIsError = false
    @State private var watched: [Thing] = []

    /// Tokens matching what's typed so far (2026-07-11), most liquid first,
    /// UNFILTERED — the field doubles as a finder, so "degen" shows its
    /// candidates instead of silently watching whichever is most liquid.
    /// Kept unfiltered (not just the not-yet-watched ones) so the Watch
    /// button can reuse `hits.first` as the exact answer a fresh resolve()
    /// would give, "already on your watchlist" included. Cleared on watch
    /// and on emptying.
    @State private var hits: [TokenWatch.Resolved] = []

    /// What the search rows actually show — already-watched tokens are in
    /// the watchlist below, so they drop out here for display only.
    private var displayHits: [TokenWatch.Resolved] {
        let refs = Set(watched.compactMap(\.sourceRef))
        return hits.filter { !refs.contains("tokens:\($0.id)") }
    }

    /// The one swipe lesson, shared across every screen that pins by swipe
    /// (2026-07-11) — whichever screen a person meets the gesture on first
    /// retires it everywhere.
    @AppStorage("coach.swipe.done") private var swipeCoachDone = false

    /// The row that plays the swipe demo — the first watched token, once
    /// ever, retiring the moment any screen's demo (or a real swipe) does.
    private var hintTokenID: UUID? {
        guard !swipeCoachDone else { return nil }
        return watched.first?.id
    }

    /// The watchlist's shared order (2026-07-15) — read as a computed
    /// property, not cached, so a mode switch or a fresh pulse repaints it
    /// immediately (an @Observable read inside `body` tracks both).
    private var orderedWatched: [Thing] {
        TokenWatchOrder.shared.apply(watched, sourceRef: \.sourceRef,
                                      change24h: { TokenPulse.shared.pulse(for: $0)?.change24h })
    }

    private func loadWatched() {
        watched = recentBridgeThings(source: "Tokens", context: modelContext)
    }

    var body: some View {
        List {
            BridgeSetupHeader(name: "Tokens")
            addSection.listRowSeparator(.hidden)
            if !watched.isEmpty {
                // Pin the whole watchlist to Home as one tile (ruling
                // 2026-07-12) — no longer one token at a time. Sits above the
                // list so it's in the same spot as every app (user, 2026-07-14).
                PinToHomeButton(source: "Tokens", inSection: true)
                    .listRowSeparator(.hidden)
                watchlistSection.listRowSeparator(.hidden)
            }
            if !watched.isEmpty {
                // A watched token IS its thing, so there's no separate store to
                // clear — "Remove its things too" is what drops the watchlist.
                BridgeDisconnectSection(bridgeID: "tokens", name: "Tokens",
                                        teardown: {})
                    .listRowSeparator(.hidden)
            }
            footerSection.listRowSeparator(.hidden)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .dsPageBackground()
        .navigationTitle("Tokens")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            // Drag handles only earn their keep in "My order" — the other
            // two modes already state their own order (movers, recency), so
            // showing Edit there would offer a drag that does nothing.
            if TokenWatchOrder.shared.mode == .manual, watched.count > 1 {
                ToolbarItem(placement: .topBarTrailing) { EditButton().tint(DS.textPrimary) }
            }
        }
        .onAppear { loadWatched() }
        // The debounced token search.
        .task(id: queryField) {
            let q = queryField.trimmingCharacters(in: .whitespacesAndNewlines)
            if let found = await debouncedSearch(q, fetch: { await TokenWatch.search(q) }) {
                hits = found
            }
        }
    }

    private var addSection: some View {
        Section {
            BridgeFieldRow(placeholder: "Name, symbol, address, or link",
                           text: $queryField,
                           buttonLabel: "Watch", action: watch)
            ForEach(displayHits) { token in
                BridgeSearchResultRow(
                    imageURL: token.imageURL, fallbackIcon: "Tokens",
                    title: "\(token.name) · $\(token.symbol)",
                    subtitle: token.priceUsd.map { "\(token.chain.capitalized) · $\($0)" }
                        ?? token.chain.capitalized,
                    action: { watchHit(token) })
            }
            BridgeSyncStatusRows(syncing: working,
                                 syncingLine: String(localized: "Finding the token…"),
                                 result: result, resultIsError: resultIsError)
        } header: {
            Text("Watch a token").dsText(.label12)
                .foregroundStyle(DS.textTertiary)
        } footer: {
            Text("Type a name, symbol, address, or link — matching tokens appear as you type. Separate several with commas (\"eth, sol, pepe\") to build a watchlist in one go. A watched token's live price chart lands in your feed.")
                .dsText(.callout15).foregroundStyle(DS.textTertiary)
        }
    }

    /// The watchlist manages itself the way Wallet's addresses do — swipe a
    /// row to unwatch (native delete on a management screen, the WalletScreen
    /// precedent; the Feed's reads-only swipe rule governs feed rows). A
    /// watched token could already be pinned from Feed (it's a normal thing,
    /// same swipe everywhere) but not from here, where you're most likely to
    /// reach for it right after watching one — the pin swipe closes that
    /// gap on the TRAILING edge, Feed's edge (2026-07-10: it briefly lived
    /// on leading here, so one verb had two directions).
    /// Unwatching deletes the thing: the thing IS the watch, not landed
    /// history — and its sourceRef leaving the store lets a re-add resolve.
    ///
    /// Rows wear the same live price + 24h sparkline the feed's rows do
    /// (2026-07-15) — the SAME cached TokenPulse, so the management screen
    /// can never disagree with the feed about which tokens moved. Row order
    /// follows the shared TokenWatchOrder (movers first by default).
    private var watchlistSection: some View {
        let items = orderedWatched
        return Section {
            ForEach(items) { thing in
                watchRow(thing)
                    .dsListCardRow()
                    .modifier(SwipeHintNudge(active: thing.id == hintTokenID) { swipeCoachDone = true })
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        // Full swipe = Unwatch (the explicit group replaces the
                        // system delete). Pinning a single token left the swipe
                        // (2026-07-12) — pin "Tokens" from its screen for a
                        // watchlist tile on Home, not one token at a time.
                        Button(role: .destructive) {
                            if let i = watched.firstIndex(where: { $0.id == thing.id }) {
                                unwatch(at: IndexSet(integer: i))
                            }
                        } label: {
                            Label("Unwatch", systemImage: "trash")
                        }
                    }
            }
            .onDelete { offsets in unwatch(displayed: items, at: offsets) }
            .onMove { from, to in reorder(displayed: items, from: from, to: to) }
            // Drag only means something in "My order" — the other two modes
            // already state their own ordering rule.
            .moveDisabled(TokenWatchOrder.shared.mode != .manual)
        } header: {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                Text("Watchlist").dsText(.label12)
                    .foregroundStyle(DS.textTertiary)
                Spacer(minLength: 0)
                sortMenu
            }
        } footer: {
            Text("Swipe a token to pin it to Home and Feed, or to stop watching it.")
                .dsText(.callout15).foregroundStyle(DS.textTertiary)
        }
    }

    /// One watchlist row: title, then either the live pulse (sparkline,
    /// price, signed 1D change — same anatomy the feed's BandRow wears) or,
    /// for a token whose pulse hasn't landed yet, the plain watched-since
    /// timestamp it always showed.
    @ViewBuilder
    private func watchRow(_ thing: Thing) -> some View {
        let pulse = TokenPulse.shared.pulse(for: thing)
        HStack(alignment: .top, spacing: DS.Space.s3) {
            Text(thing.title)
                .dsText(.body17).foregroundStyle(DS.textPrimary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let pulse, let last = pulse.closes.last {
                VStack(alignment: .trailing, spacing: 2) {
                    Sparkline(closes: pulse.closes, up: pulse.change24h >= 0)
                    Text(TokenChartStyle.priceText(last))
                        .dsText(.subhead13).foregroundStyle(DS.textPrimary)
                        .monospacedDigit()
                    TokenDeltaPill(change: pulse.change24h, label: "1D", compact: true)
                }
            } else {
                Text(LiveTimeText.short(thing.capturedAt))
                    .dsText(.subhead13).foregroundStyle(DS.textTertiary)
            }
        }
    }

    /// The sort choice — a menu, not a segmented control, so the header
    /// keeps its one-line height at every text size.
    private var sortMenu: some View {
        Menu {
            ForEach(TokenWatchSortMode.allCases, id: \.self) { mode in
                Button {
                    DSHaptic.selection()
                    TokenWatchOrder.shared.setMode(mode)
                } label: {
                    if mode == TokenWatchOrder.shared.mode {
                        Label(mode.label, systemImage: "checkmark")
                    } else {
                        Text(mode.label)
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Text(TokenWatchOrder.shared.mode.label)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
            .dsText(.label12).foregroundStyle(DS.textTertiary)
        }
    }

    private var footerSection: some View {
        Section {
            Text("Public price data only — nothing about you leaves your iPhone.")
                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                .listRowBackground(Color.clear)
        }
    }

    private func unwatch(at offsets: IndexSet) {
        unwatch(displayed: watched, at: offsets)
    }

    /// Drops the tapped rows from whichever array the caller was actually
    /// showing (`watched`'s own order for the swipe button, `orderedWatched`
    /// for native Edit-mode delete) — the two can differ once a sort mode
    /// reorders the list, so an offset only ever means something against the
    /// array it came from.
    private func unwatch(displayed items: [Thing], at offsets: IndexSet) {
        let dropped = offsets.map { items[$0] }
        for thing in dropped {
            if let ref = thing.sourceRef { TokenWatchOrder.shared.remove(ref) }
        }
        SpotlightIndex.remove(ids: dropped.map(\.id))
        for thing in dropped { modelContext.delete(thing) }
        modelContext.saveHonestly()
        DSHaptic.tap()
        loadWatched()
        register()
    }

    /// A drag in "My order" saves the whole new sequence — the manual order
    /// IS the displayed order from here on, not a diff against the old one.
    private func reorder(displayed items: [Thing], from source: IndexSet, to destination: Int) {
        var refs = items.map { $0.sourceRef ?? "" }
        refs.move(fromOffsets: source, toOffset: destination)
        TokenWatchOrder.shared.saveManual(refs)
        DSHaptic.tap()
    }

    private func watch() {
        let raw = queryField.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, !working else { return }
        DSHaptic.tap()
        // A comma-separated paste ("eth, sol, pepe") builds a whole
        // watchlist in one submit — each piece resolves independently so one
        // bad symbol doesn't block the rest (2026-07-15).
        let queries = raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if queries.count > 1 {
            watchMany(queries)
            return
        }
        // The debounced search already ran this exact query — its top hit
        // IS what a fresh resolve() would return, so reuse it rather than
        // repeating the network round-trip.
        if let top = hits.first {
            add(top)
            return
        }
        working = true
        Task {
            let token = await TokenWatch.resolve(raw)
            working = false
            guard let token else {
                result = String(localized: "Couldn't find that token — try its contract address.")
                resultIsError = true
                return
            }
            add(token)
        }
    }

    /// Resolves and watches each piece of a comma-separated list on its own
    /// — a bad symbol in the middle doesn't stop the rest, and the closing
    /// message says exactly how many landed vs. which couldn't be found.
    private func watchMany(_ queries: [String]) {
        working = true
        Task {
            var watchedCount = 0
            var failed: [String] = []
            for q in queries {
                if let token = await TokenWatch.resolve(q) {
                    if TokenWatch.add(token, context: modelContext) != nil { watchedCount += 1 }
                } else {
                    failed.append(q)
                }
            }
            working = false
            queryField = ""
            hits = []
            loadWatched()
            register()
            resultIsError = !failed.isEmpty
            if watchedCount == 0 {
                result = String(localized: "Couldn't find any of those tokens — try contract addresses.")
            } else if failed.isEmpty {
                result = String(localized: "Watching \(watchedCount) tokens")
            } else {
                result = String(localized: "Watching \(watchedCount) of \(queries.count) — couldn't find \(failed.joined(separator: ", "))")
            }
        }
    }

    /// A tapped search result skips the resolve — the search already
    /// carried everything the watchlist stores.
    private func watchHit(_ token: TokenWatch.Resolved) {
        guard !working else { return }
        DSHaptic.tap()
        add(token)
    }

    private func add(_ token: TokenWatch.Resolved) {
        resultIsError = false
        if let thing = TokenWatch.add(token, context: modelContext) {
            result = String(localized: "Watching \(thing.title)")
            queryField = ""
            hits = []
            loadWatched()
            register()
        } else {
            result = String(localized: "\(token.name) is already on your watchlist.")
        }
    }

    private func register() {
        TokenWatch.registerBridge(store: store, context: modelContext)
    }
}
