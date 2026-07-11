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

    /// Tokens matching what's typed so far (2026-07-11) — the field doubles
    /// as a finder, so "degen" shows its candidates instead of silently
    /// watching whichever is most liquid. Cleared on watch and on emptying.
    @State private var hits: [TokenWatch.Resolved] = []

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
        // The debounced token search — each keystroke restarts the task, so
        // only a 300ms pause actually asks the network. Already-watched
        // tokens stay out of the results; they're in the watchlist below.
        .task(id: queryField) {
            let q = queryField.trimmingCharacters(in: .whitespacesAndNewlines)
            guard q.count >= 2 else {
                if !hits.isEmpty { hits = [] }
                return
            }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            let refs = Set(watched.compactMap(\.sourceRef))
            let found = await TokenWatch.search(q)
                .filter { !refs.contains("dexscreener:\($0.id)") }
            guard !Task.isCancelled else { return }
            hits = found
        }
    }

    private var addSection: some View {
        Section {
            BridgeFieldRow(placeholder: "Token name, address, or link",
                           text: $queryField,
                           buttonLabel: "Watch", action: watch)
            ForEach(hits) { token in
                Button { watchHit(token) } label: {
                    HStack(spacing: DS.Space.s3) {
                        if let art = token.imageURL {
                            RemoteThumb(urlString: art, size: 28,
                                        fallback: "Dexscreener", circular: true)
                        } else {
                            BridgeIcon(name: "Dexscreener", size: 28, circular: true)
                        }
                        VStack(alignment: .leading, spacing: 0) {
                            Text("\(token.name) · $\(token.symbol)")
                                .dsText(.body17).foregroundStyle(DS.textPrimary)
                                .lineLimit(1)
                            Text(token.priceUsd.map { "\(token.chain.capitalized) · $\($0)" }
                                    ?? token.chain.capitalized)
                                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .listRowBackground(DS.surfaceSheet)
            }
            BridgeSyncStatusRows(syncing: working,
                                 syncingLine: "Finding the token…",
                                 result: result, resultIsError: resultIsError)
        } header: {
            Text("Watch a token").dsText(.label12)
                .foregroundStyle(DS.textTertiary)
        } footer: {
            Text("Type a name or paste an address — matching tokens appear as you type, and a watched token's live price chart lands in your feed.")
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
        working = true
        DSHaptic.tap()
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
