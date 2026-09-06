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
    @State private var result: BridgeProof?
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

    /// The page's one presentation (`AccountPage.sheet`).
    @State private var sheet: AccountPageSheet?

    var body: some View {
        AccountPage(
            name: "Tokens", seatID: "tokens", source: "Tokens",
            state: AccountPageState.of(name: "Tokens", seatID: "tokens",
                                       connected: !watched.isEmpty, store: store),
            intro: "Watch a token below by name, symbol, address, or link.",
            mode: .noAccount,
            rows: rows,
            query: queryField,
            onRemoveRow: unwatch,
            onOpenRow: openToken,
            // The one verb only this seat has: in "My order", a row can be
            // pulled to the front. It rode the shelf's hold menu before §639;
            // it rides the roster's now rather than being lost with the shelf.
            rowMenu: moveToFrontItem,
            // A watched token IS its thing, so there's no separate store to
            // clear — "Remove its things too" is what drops the watchlist.
            teardown: {},
            sheet: $sheet,
            act: { addBlock },
            more: { EmptyView() },
            keySheet: { EmptyView() }
        )
        .toolbar {
            // The sort choice lived in the old watchlist section's header.
            // The roster has no header of its own, so it rides the toolbar.
            if watched.count > 1 {
                ToolbarItem(placement: .topBarTrailing) { sortMenu }
            }
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

    // MARK: - The roster

    /// One row per watched token, in the shared `TokenWatchOrder` (movers
    /// first by default). The shelf of logo discs under a caption coaching its
    /// own gestures ("Watching 5 · hold to unwatch") is the chassis's roster
    /// now, with one removal verb and its Mac mirror.
    ///
    /// The subline is the live pulse the feed's rows read from the SAME
    /// cache, so the two can never disagree. A token whose pulse hasn't
    /// landed shows no figure rather than a placeholder that reads like one.
    private var rows: [AccountPageShape.Row] {
        orderedWatched.filter(\.isLive).map { thing in
            let pulse = TokenPulse.shared.pulse(for: thing)
            let price = pulse?.closes.last.map { TokenChartStyle.priceText($0) }
            let change = pulse?.change24h.map { TokenChartStyle.changeText($0) }
            let line = [price, change].compactMap { $0 }.joined(separator: " · ")
            return AccountPageShape.Row(
                id: thing.id.uuidString,
                title: symbolLabel(thing),
                subline: line.isEmpty ? String(localized: "watching") : line,
                weekCount: 0, hasNew: false, isYou: false,
                avatarURL: thing.previewImageURL)
        }
    }

    private func openToken(_ id: String) {
        guard let uuid = UUID(uuidString: id) else { return }
        sheet = .thing(id: uuid)
    }

    private func unwatch(_ id: String) {
        guard let i = watched.firstIndex(where: { $0.id.uuidString == id }) else { return }
        unwatch(at: IndexSet(integer: i))
    }

    /// "Move to front", offered only where it does something: the manual
    /// order, with more than one row. A menu item that cannot reorder anything
    /// is the §83 dead control.
    private func moveToFrontItem(_ id: String) -> AnyView {
        let items = orderedWatched
        guard TokenWatchOrder.shared.mode == .manual, items.count > 1,
              let thing = items.first(where: { $0.id.uuidString == id }) else {
            return AnyView(EmptyView())
        }
        return AnyView(
            Button {
                moveToFront(thing, in: items)
            } label: {
                Label("Move to front", systemImage: "arrow.left.to.line")
            }
        )
    }


    @ViewBuilder private var addBlock: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
        DSSlabField(placeholder: String(localized: "Name, symbol, address, or link"),
                    text: $queryField, actionLabel: String(localized: "Watch"),
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
                             proof: result)
        // Commas still build a watchlist in one go — that trick moved to
        // the placeholder's own example rather than a paragraph (§190).
        DSSlabNote(text: "Public price data only — no wallet, no trading.", plain: true)
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
                    .dsGlyph(10)
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
                result = .failed(String(localized: "Couldn't find that token — try its contract address."))
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
            if watchedCount == 0 {
                result = .failed(String(localized: "Couldn't find any of those tokens — try contract addresses."))
            } else if failed.isEmpty {
                result = .says(String(localized: "Watching \(watchedCount) tokens"))
                DSHaptic.success()
            } else {
                // Mixed outcome is a FAILURE, and the type now says so where a
                // separate `resultIsError` flag once had to be remembered three
                // branches earlier. The shared row's shake and failure haptic
                // cover it — no success buzz to compete with them.
                result = .failed(String(localized: "Watching \(watchedCount) of \(queries.count) — couldn't find \(failed.joined(separator: ", "))"))
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
        if let thing = TokenWatch.add(token, context: modelContext) {
            result = .says(String(localized: "Watching \(thing.title)"))
            DSHaptic.success()
            queryField = ""
            hits = []
            loadWatched()
            register()
        } else {
            result = .says(String(localized: "\(token.name) is already on your watchlist."))
        }
    }

    private func register() {
        TokenWatch.registerBridge(store: store, context: modelContext)
    }
}
