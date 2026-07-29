import SwiftUI
import SwiftData

/// Kalshi's CONNECT page (prd §234, 2026-07-29) — and only that. Kalshi is
/// a CFTC-regulated event-contracts exchange whose market data is public and
/// keyless (no auth, no wallet, no account), so connecting it is a plain
/// statement of interest rather than a sign-in: the tap registers the seat,
/// which lights the Kalshi source chip, whose ROOM holds the live book.
/// Browsing markets happens there (`PredictionRoomBook`), never here.
/// Read-only throughout — Casberi never places a trade or shows a path to one.
struct KalshiScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @State private var watched: [Thing] = []

    @AppStorage("coach.swipe.done") private var swipeCoachDone = false

    private var hintTokenID: UUID? {
        guard !swipeCoachDone else { return nil }
        return liveWatched.first?.id
    }

    private func loadWatched() {
        watched = recentBridgeThings(source: "Kalshi", context: modelContext)
    }

    /// A settled market can never move again, so it stops being a WATCH and
    /// becomes a record — split here so the watchlist reads as what you're
    /// actually following, not a graveyard of finished questions.
    private var liveWatched: [Thing] { watched.filter { $0.isLive && $0.marketResolvedYes == nil } }
    private var settledWatched: [Thing] { watched.filter { $0.isLive && $0.marketResolvedYes != nil } }

    var body: some View {
        List {
            BridgeSetupHeader(name: "Kalshi")
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
                BridgeDisconnectSection(bridgeID: "kalshi", name: "Kalshi",
                                        teardown: {})
                    .listRowSeparator(.hidden)
            }
            footerSection.listRowSeparator(.hidden)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .bridgeSetupWash(name: "Kalshi")
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .dsScreenTitle("Kalshi")
        .onAppear { loadWatched() }
    }

    /// Connect ONLY (prd §234, user 2026-07-29: "the connect page should ONLY
    /// be connect"). The market book moved to the Kalshi ROOM, where browsing
    /// belongs — this screen connects the exchange, says what that gets you,
    /// and manages what you already follow. It does not list markets.
    ///
    /// Connecting is a real standalone action here, which it never was
    /// before: Kalshi has no account and no key, so the old screen had
    /// nothing to connect WITH and quietly treated "watched your first
    /// market" as the connection. That's what forced a browser onto a setup
    /// page. Now the tap registers the seat, which lights the source chip,
    /// which opens the room holding the book.
    private var addSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                if connected {
                    DSSlabButton(title: "Open the Kalshi room",
                                 systemImage: "arrow.forward") {
                        DSHaptic.tap()
                        FeedFilter.shared.source = "Kalshi"
                        HomeRoute.shared.path.removeAll()
                    }
                    DSSlabNote(text: "Browse every open market in the room, and follow the ones you want to keep.")
                } else {
                    DSSlabButton(title: "Connect Kalshi", systemImage: "link") {
                        DSHaptic.tap()
                        register()
                        DSHaptic.success()
                    }
                    DSSlabNote(text: "No account, no key — Kalshi's odds are public. Connecting adds a Kalshi room where you can browse every open market.")
                }
                DSSlabNote(text: "Public odds only — nothing here places a trade.")
            }
        }
        .dsSlabSection()
    }

    private var connected: Bool {
        store.bridges.contains { $0.id == "kalshi" && $0.status == .connected }
    }

    /// Same swipe grammar as every watchlist screen (Tokens, Wallet):
    /// full trailing swipe pins, the explicit group carries Unwatch.
    /// Unwatching deletes the thing — the thing IS the watch.
    /// Finished questions, kept but set apart — the record of what you were
    /// watching and how it turned out. Not swipeable-to-unwatch by accident:
    /// same gesture, but these are history, so the list leads with the answer.
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
                            if let watched = thing.watchPriceUsd {
                                Text("You followed at \(Int((watched * 100).rounded()))%")
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
            Text("These can't move again — they're a record of what you were following.")
                .dsText(.callout15).foregroundStyle(DS.textTertiary)
        }
    }

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
            Text("Public odds from Kalshi, a CFTC-regulated exchange — nothing about you leaves your iPhone.\n\nRead-only: nothing here places a trade. Opens on Kalshi.")
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
        registerPredictionBridge(source: "Kalshi", id: "kalshi",
                                 store: store, context: modelContext)
    }
}
