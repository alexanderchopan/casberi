import SwiftUI
import SwiftData

/// Polymarket's CONNECT page — mirrors `KalshiScreen` exactly (prd §234,
/// amended 2026-07-29). Its Gamma API is public and keyless (no account, no
/// wallet), so this page asks the same yes/no `KalshiScreen` does, own venue
/// first: follow Polymarket's markets, and follow Kalshi's too. Browsing,
/// following, and every receipt live in the ROOM (`PredictionRoomBook`),
/// never here.
struct PolymarketScreen: View {
    @Environment(BridgeStore.self) private var store

    private var connected: Bool {
        store.bridges.contains { $0.id == "polymarket" && $0.status == .connected }
    }

    var body: some View {
        List {
            BridgeSetupHeader(
                name: "Polymarket",
                mode: .noAccount,
                intro: "No account, no wallet, no key — Polymarket's odds are public, so following just brings the markets you pick into your feed. Nothing here ever places a trade.",
                connected: connected)
            PredictionVenueConnect(ownVenue: .polymarket)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .bridgeSetupWash(name: "Polymarket")
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .dsScreenTitle("Polymarket")
    }
}
