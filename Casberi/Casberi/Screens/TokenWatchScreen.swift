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
            Text("Type a name, symbol, address, or link — matching tokens appear as you type. A watched token's live price chart lands in your feed.")
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
            .onDelete(perform: unwatch)
        } header: {
            Text("Watchlist").dsText(.label12)
                .foregroundStyle(DS.textTertiary)
        } footer: {
            Text("Swipe a token to pin it to Home and Feed, or to stop watching it.")
                .dsText(.callout15).foregroundStyle(DS.textTertiary)
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
        // The debounced search already ran this exact query — its top hit
        // IS what a fresh resolve() would return, so reuse it rather than
        // repeating the network round-trip.
        if let top = hits.first {
            add(top)
            return
        }
        working = true
        Task {
            let token = await TokenWatch.resolve(q)
            working = false
            guard let token else {
                result = String(localized: "Couldn't find that token — try its contract address.")
                resultIsError = true
                return
            }
            add(token)
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
