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
                RecentThingsSection(header: "YOUR WATCHLIST", things: watched)
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
            Text("WATCH A TOKEN").dsText(.label12).kerning(0.7)
                .foregroundStyle(DS.textTertiary)
        } footer: {
            Text("Paste a token address or a Dexscreener link — its live price chart lands in your feed.")
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
