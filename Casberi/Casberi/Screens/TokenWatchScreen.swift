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
    @FocusState private var fieldFocused: Bool

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

    /// The token whose chart sheet is open — a tapped coin on the roster
    /// (prd §185). The shelf replaced a list row that wasn't tappable at all,
    /// so the chart is newly reachable from here.
    @State private var openThing: Thing?

    /// The watchlist's shared order (2026-07-15) — read as a computed
    /// property, not cached, so a mode switch or a fresh pulse repaints it
    /// immediately (an @Observable read inside `body` tracks both).
    private var orderedWatched: [Thing] {
        // `.live` at the boundary (build 177's lesson) — `apply` reads
        // `sourceRef` off every element of this @State-held array.
        TokenWatchOrder.shared.apply(watched.live, sourceRef: \.sourceRef,
                                      change24h: { TokenPulse.shared.pulse(for: $0)?.change24h })
    }

    private func loadWatched() {
        watched = recentBridgeThings(source: "Tokens", context: modelContext)
    }

    var body: some View {
        List {
            // No header coin card, no section furniture (prd §185) — the
            // omnibox is the screen's first act, the wallet manager's own
            // opening. The nav title already says Tokens.
            addSection.listRowSeparator(.hidden)
            if !watched.isEmpty {
                rosterSection
            }
            if !watched.isEmpty {
                // A watched token IS its thing, so there's no separate store to
                // clear — "Remove its things too" is what drops the watchlist.
                BridgeDisconnectSection(bridgeID: "tokens", name: "Tokens",
                                        teardown: {})
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .bridgeSetupWash(name: "Tokens")
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .dsScreenTitle("Tokens")
        .toolbar {
            // The sort choice lived in the old watchlist section's header;
            // the shelf has no header, so it rides the toolbar (prd §185).
            // Edit-mode drag handles are gone with the vertical list — a
            // shelf reorders by "Move to front" in the hold menu instead.
            if watched.count > 1 {
                ToolbarItem(placement: .topBarTrailing) { sortMenu }
            }
        }
        .sheet(item: $openThing) { thing in
            ThingSheetView(thing: thing)
        }
        .onAppear {
            loadWatched()
            // The rows' price column reads the SAME cached TokenPulse the
            // feed's rows do — refreshed here too (prd §185) so the manager
            // is live on open, not whenever the feed last looked.
            Task { await TokenPulse.shared.refresh(context: modelContext) }
        }
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
            VStack(alignment: .leading, spacing: DS.Space.s2) {
            DSSlabField(placeholder: String(localized: "Name, symbol, address, or link"),
                        text: $queryField, actionLabel: String(localized: "WATCH"),
                        focus: $fieldFocused, action: watch)
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
            // Commas still build a watchlist in one go — that trick moved to
            // the placeholder's own example rather than a paragraph (§190).
            DSSlabNote(text: "Public price data only — no wallet, no trading.")
            }
        }
        .dsSlabSection()
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
    /// The watchlist as a roster of coins (prd §185) — the same shelf of
    /// circles the wallet's addresses and the social screens' people wear,
    /// since a watched token is an identity too. Tap opens its chart; hold
    /// unwatches, and in "My order" also moves it to the front.
    private var rosterSection: some View {
        let items = orderedWatched
        return AssetRosterShelf(note: rosterNote) {
            ForEach(items.keyed) { row in
                // Corollary 3 (build 176) — see `ThingRowKeying`.
                if let thing = row.live { rosterSlot(thing, in: items) }
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
            ? String(localized: "Watching 1 · hold to unwatch")
            : String(localized: "Watching \(n) · hold to unwatch")
    }

    /// One coin on the shelf — its own logo (the same one the search row wore
    /// when it was watched, 2026-07-17), its symbol, and the live pulse the
    /// feed's rows read from the SAME cache, so the two can never disagree.
    /// A token whose pulse hasn't landed shows no figure rather than a
    /// placeholder that reads like one.
    private func rosterSlot(_ thing: Thing, in items: [Thing]) -> some View {
        let pulse = TokenPulse.shared.pulse(for: thing)
        return AssetRosterSlot(label: symbolLabel(thing),
                               price: pulse?.closes.last,
                               change: pulse?.change24h) {
            BridgeLogo(imageURL: thing.previewImageURL, fallbackIcon: "Tokens",
                       size: 56)
        }
        .onTapGesture {
            DSHaptic.tap()
            openThing = thing
        }
        .contextMenu {
            if TokenWatchOrder.shared.mode == .manual, items.count > 1 {
                Button {
                    moveToFront(thing, in: items)
                } label: {
                    Label("Move to Front", systemImage: "arrow.left.to.line")
                }
            }
            Button(role: .destructive) {
                if let i = watched.firstIndex(where: { $0.id == thing.id }) {
                    unwatch(at: IndexSet(integer: i))
                }
            } label: {
                Label("Unwatch", systemImage: "trash")
            }
        }
    }

    /// The shelf's label — the token's SYMBOL, not its full title. A slot is
    /// 76pt wide, and "Ethereum · $ETH" truncates to nothing readable in it;
    /// the symbol is the name a watchlist is actually read by. Falls back to
    /// the title when a pre-symbol watch has none to parse.
    private func symbolLabel(_ thing: Thing) -> String {
        if let symbol = thing.title.split(separator: "·").last
            .map({ $0.trimmingCharacters(in: .whitespaces) }), symbol.hasPrefix("$") {
            return symbol
        }
        return thing.title
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

    private func unwatch(at offsets: IndexSet) {
        unwatch(displayed: watched, at: offsets)
    }

    /// Drops the tapped rows from whichever array the caller was actually
    /// showing (`watched`'s own order for the swipe button, `orderedWatched`
    /// for native Edit-mode delete) — the two can differ once a sort mode
    /// reorders the list, so an offset only ever means something against the
    /// array it came from.
    private func unwatch(displayed items: [Thing], at offsets: IndexSet) {
        // Liveness filtered on the DROPPED rows, not on `items`: `offsets`
        // index the array the caller displayed (resolved via `firstIndex` at
        // the tap), so filtering the source would misalign them. Build 177's
        // lesson applied where it doesn't break the indices — and a row a
        // heal already deleted needs no unwatching.
        let dropped = offsets
            .compactMap { items.indices.contains($0) ? items[$0] : nil }
            .filter(\.isLive)
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

    /// The shelf's reorder verb (prd §185). A horizontal drag-to-reorder is
    /// the custom-gesture-over-a-scroll-view fight the retired Home board
    /// already lost, so "My order" is set one coin at a time from the hold
    /// menu instead — which keeps the mode a live control rather than a
    /// setting with no way to set it (the no-dead-controls rule). Saves the
    /// whole new sequence, the way the drag did.
    private func moveToFront(_ thing: Thing, in items: [Thing]) {
        var refs = items.map { $0.sourceRef ?? "" }
        guard let ref = thing.sourceRef, let i = refs.firstIndex(of: ref) else { return }
        refs.move(fromOffsets: IndexSet(integer: i), toOffset: 0)
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
                DSHaptic.success()
            } else {
                // Mixed outcome: resultIsError stays true for this line, so
                // the shared status row's shake + failure haptic already
                // covers it — no separate success buzz to compete with it.
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
            DSHaptic.success()
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
