import SwiftUI
import SwiftData

/// The live book at the head of a prediction-market room (prd §234,
/// 2026-07-29) — Kalshi's or Polymarket's whole open market list, browsable
/// the moment the exchange is connected, with nothing followed and nothing
/// landed.
///
/// This is where browse BELONGS, and the reason is structural rather than
/// aesthetic. Connecting an exchange here is not a sync: there is no
/// account, no key, and nothing to fetch on your behalf — the book is public
/// and identical for everyone. So "connected Kalshi" can only sensibly mean
/// *I want to see this book*, and the book is a ROOM's content, not a setup
/// screen's. The first pass (§233) put it in `KalshiScreen`/
/// `PolymarketScreen` instead, which made the connect page a market browser
/// and left the room itself empty until you'd picked something — exactly
/// backwards (user, 2026-07-29: "the app connect page should ONLY be
/// connect").
///
/// Following is the ONLY write. Browsing reads the live API and lands
/// nothing, so the All feed stays clean until a market is explicitly
/// followed — the corpus keeps meaning "things I chose", which is the whole
/// contract the source strip rests on.
struct PredictionRoomBook: View {
    /// "Kalshi" or "Polymarket" — the room this is heading.
    let source: String

    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store

    @State private var scope: PredictionVenueScope = .all
    @State private var didSetScope = false

    /// The OTHER exchange, connected? The venue switcher only exists when
    /// both are (the `walletSwitcherBar` rule — a scope control with one
    /// scope is not a control), and until then the room is simply this
    /// venue's own book.
    private var bothConnected: Bool {
        let connected = Set(store.bridges.filter { $0.status == .connected }.map(\.name))
        return connected.contains("Kalshi") && connected.contains("Polymarket")
    }

    private var ownScope: PredictionVenueScope {
        source == "Polymarket" ? .polymarket : .kalshi
    }

    /// How many of this room's markets are actually followed — a count, only
    /// ever used to decide whether the "Following" divider has anything to
    /// divide. Never rendered as a number (the module doctrine's tally ban).
    private var followingCount: Int {
        (try? modelContext.fetchCount(FetchDescriptor<Thing>(
            predicate: #Predicate<Thing> { $0.source == source }))) ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            if bothConnected {
                PredictionVenueSwitcher(scope: $scope)
            }
            PredictionBrowseSection(
                scope: bothConnected ? scope : ownScope,
                onWatchedKalshi: { _ in registerIfNeeded(name: "Kalshi", id: "kalshi") },
                onWatchedPolymarket: { _ in registerIfNeeded(name: "Polymarket", id: "polymarket") })
            // Names the boundary: everything above is the live book (nothing
            // saved), everything the feed renders below is what you actually
            // follow. Shown only when there IS something below — an empty
            // room shouldn't promise a section that isn't there.
            if followingCount > 0 {
                Text("Following").dsText(.label12).foregroundStyle(DS.textTertiary)
                    .padding(.top, DS.Space.s2)
            }
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.bottom, DS.Space.s3)
        .onAppear {
            // Default to this room's OWN venue, not All — you tapped the
            // Kalshi chip. Widening is the switcher's job, and only once
            // there's a second venue to widen to. Guarded so a re-appear
            // (a pager swipe back) doesn't stomp a scope you chose.
            guard !didSetScope else { return }
            didSetScope = true
            scope = ownScope
        }
    }

    /// Following a market from the OTHER venue's rows (possible in `.all`
    /// scope) has to register that bridge too — otherwise its things land
    /// with no catalog seat and no chip.
    private func registerIfNeeded(name: String, id: String) {
        registerPredictionBridge(source: name, id: id, store: store, context: modelContext)
    }
}
