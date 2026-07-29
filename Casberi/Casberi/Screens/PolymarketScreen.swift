import SwiftUI
import SwiftData

/// Polymarket's CONNECT page (prd §234, 2026-07-29) — and only that. Its
/// Gamma API is public and keyless (no account, no wallet), so connecting is
/// a statement of interest, not a sign-in: the tap registers the seat, which
/// lights the Polymarket source chip, whose ROOM holds the live book (and
/// the real price curves Kalshi can't serve). Browsing markets happens
/// there (`PredictionRoomBook`), never here. Read-only throughout.
struct PolymarketScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @State private var watched: [Thing] = []

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
            if connected {
                // A followed market IS its thing, so there's no separate store
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
    }

    /// Connect ONLY (prd §234) — the market book lives in the Polymarket
    /// ROOM. See `KalshiScreen.addSection` for the full reasoning; the two
    /// screens are deliberately identical in shape.
    private var addSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                if connected {
                    DSSlabButton(title: "Open the Polymarket room",
                                 systemImage: "arrow.forward") {
                        DSHaptic.tap()
                        FeedFilter.shared.source = "Polymarket"
                        HomeRoute.shared.path.removeAll()
                    }
                    DSSlabNote(text: "Browse every open market in the room, and follow the ones you want to keep.")
                } else {
                    DSSlabButton(title: "Connect Polymarket", systemImage: "link") {
                        DSHaptic.tap()
                        register()
                        DSHaptic.success()
                    }
                    DSSlabNote(text: "No account, no wallet — Polymarket's odds are public. Connecting adds a Polymarket room where you can browse every open market.")
                }
                DSSlabNote(text: "Public odds only — nothing here places a trade.")
            }
        }
        .dsSlabSection()
    }

    private var connected: Bool {
        store.bridges.contains { $0.id == "polymarket" && $0.status == .connected }
    }

    /// Finished questions, kept but set apart — the record of what you were
    /// watching and how it turned out.
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
                            if let at = thing.watchPriceUsd {
                                Text("You followed at \(Int((at * 100).rounded()))%")
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
                            Label("Unfollow", systemImage: "trash")
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
                            Label("Unfollow", systemImage: "trash")
                        }
                    }
                }
            }
            .onDelete(perform: unwatch)
        } header: {
            Text("Following").dsText(.label12)
                .foregroundStyle(DS.textTertiary)
        } footer: {
            Text("Swipe a market to stop following it.")
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

    private func register() {
        registerPredictionBridge(source: "Polymarket", id: "polymarket",
                                 store: store, context: modelContext)
    }
}
