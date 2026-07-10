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
    }

    private var addSection: some View {
        Section {
            BridgeFieldRow(placeholder: "Token address, symbol, or link",
                           text: $queryField,
                           buttonLabel: "Watch", action: watch)
            BridgeSyncStatusRows(syncing: working,
                                 syncingLine: "Finding the token…",
                                 result: result, resultIsError: resultIsError)
        } header: {
            Text("Watch a token").dsText(.label12)
                .foregroundStyle(DS.textTertiary)
        } footer: {
            Text("Paste a token address or a Dexscreener link — its live price chart lands in your feed.")
                .dsText(.callout15).foregroundStyle(DS.textTertiary)
        }
    }

    /// The watchlist manages itself the way Wallet's addresses do — swipe a
    /// row to unwatch (native delete on a management screen, the WalletScreen
    /// precedent; the Feed's reads-only swipe rule governs feed rows). A
    /// watched token could already be pinned from Feed (it's a normal thing,
    /// same swipe everywhere) but not from here, where you're most likely to
    /// reach for it right after watching one — a leading-edge pin swipe
    /// closes that gap (2026-07-09), same verb, same icon, as Feed's own.
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
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button {
                        DSHaptic.tap()
                        thing.pinned.toggle()
                        try? modelContext.save()
                    } label: {
                        Label(thing.pinned ? "Unpin" : "Pin",
                              systemImage: thing.pinned ? "pin.slash" : "pin")
                    }
                    .tint(DS.tint)
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
            resultIsError = false
            if let thing = TokenWatch.add(token, context: modelContext) {
                result = "Watching \(thing.title)"
                queryField = ""
                loadWatched()
                register()
            } else {
                result = "\(token.name) is already on your watchlist."
            }
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
