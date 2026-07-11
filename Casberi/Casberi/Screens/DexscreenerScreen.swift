import SwiftUI
import SwiftData

/// Dexscreener, connected — the token-watch screen. Paste a token (address,
/// symbol, or Dexscreener link); it resolves through public search and joins
/// your watchlist as a thing whose sheet draws its live price chart. Read-only
/// public price data — no wallet, no account, no trading.
struct DexscreenerScreen: View {
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
        return hits.filter { !refs.contains("dexscreener:\($0.id)") }
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
        watched = recentBridgeThings(source: "Dexscreener", context: modelContext)
    }

    var body: some View {
        List {
            BridgeSetupHeader(name: "Dexscreener")
            addSection.listRowSeparator(.hidden)
            if !watched.isEmpty {
                watchlistSection.listRowSeparator(.hidden)
            }
            if !watched.isEmpty {
                // A watched token IS its thing, so there's no separate store to
                // clear — "Remove its things too" is what drops the watchlist.
                BridgeDisconnectSection(bridgeID: "dexscreener", name: "Dexscreener",
                                        teardown: {})
                    .listRowSeparator(.hidden)
            }
            footerSection.listRowSeparator(.hidden)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .dsPageBackground()
        .navigationTitle("Dexscreener")
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
                    imageURL: token.imageURL, fallbackIcon: "Dexscreener",
                    title: "\(token.name) · $\(token.symbol)",
                    subtitle: token.priceUsd.map { "\(token.chain.capitalized) · $\($0)" }
                        ?? token.chain.capitalized,
                    action: { watchHit(token) })
            }
            BridgeSyncStatusRows(syncing: working,
                                 syncingLine: "Finding the token…",
                                 result: result, resultIsError: resultIsError)
        } header: {
            Text("Watch a token").dsText(.label12)
                .foregroundStyle(DS.textTertiary)
        } footer: {
            Text("Type a name, symbol, address, or Dexscreener link — matching tokens appear as you type. A watched token's live price chart lands in your feed.")
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
                .listRowBackground(DS.surfaceSheet)
                .modifier(SwipeHintNudge(active: thing.id == hintTokenID) { swipeCoachDone = true })
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    // Full swipe = pin (Feed's grammar). The explicit group
                    // replaces the system delete, so Unwatch rides here too.
                    Button {
                        DSHaptic.tap()
                        thing.pinned.toggle()
                        try? modelContext.save()
                        CorpusSignal.shared.bump()
                    } label: {
                        Label(thing.pinned ? "Unpin" : "Pin",
                              systemImage: thing.pinned ? "pin.slash" : "pin")
                    }
                    .tint(DS.tint)
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
            Text("Your watchlist").dsText(.label12)
                .foregroundStyle(DS.textTertiary)
        } footer: {
            Text("Swipe a token to pin it to Home and Feed, or to stop watching it.")
                .dsText(.callout15).foregroundStyle(DS.textTertiary)
        }
    }

    private var footerSection: some View {
        Section {
            Text("Public price data only — nothing about you leaves your iPhone. Charts open on Dexscreener.")
                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                .listRowBackground(Color.clear)
        }
    }

    private func unwatch(at offsets: IndexSet) {
        let dropped = offsets.map { watched[$0] }
        SpotlightIndex.remove(ids: dropped.map(\.id))
        for thing in dropped { modelContext.delete(thing) }
        try? modelContext.save()
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
                result = "Couldn't find that token — try its contract address."
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
            result = "Watching \(thing.title)"
            queryField = ""
            hits = []
            loadWatched()
            register()
        } else {
            result = "\(token.name) is already on your watchlist."
        }
    }

    private func register() {
        let proof = "\(watched.count) token\(watched.count == 1 ? "" : "s") watched"
        if let existing = store.bridges.first(where: { $0.name == "Dexscreener" }) {
            store.reconnect(existing.id, proof: proof)
        } else {
            store.bridges.append(BridgeApp(
                id: "dexscreener", name: "Dexscreener", status: .connected,
                statusLine: proof,
                can: ["Watches the tokens you add.", "Read-only — public price data only."]
            ))
            DSHaptic.success()
        }
    }
}
