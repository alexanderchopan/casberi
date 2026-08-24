import SwiftUI
import SwiftData

/// Kalshi's CONNECT page — and only that (prd §234, amended 2026-07-29,
/// user: *"the connect page should be ONLY about connecting… it's like yes
/// or no. Do you wanna follow Kalshi prediction markets, or yes or no do
/// you wanna follow Polymarket prediction markets — also on both their
/// pages"*). Kalshi is a CFTC-regulated event-contracts exchange whose
/// market data is public and keyless (no auth, no wallet, no account), so
/// this page asks exactly one thing, twice: follow this exchange's markets,
/// and follow the other one's too. Browsing, following, and every receipt
/// live in the ROOM (`PredictionRoomBook`) — never here, and never again a
/// list of markets on this screen (that was §233's mistake, corrected by
/// §234, and drifted right back in with "Open the Kalshi room").
struct KalshiScreen: View {
    @Environment(BridgeStore.self) private var store

    private var connected: Bool {
        store.bridges.contains { $0.id == "kalshi" && $0.status == .connected }
    }

    var body: some View {
        List {
            BridgeSetupHeader(
                name: "Kalshi",
                mode: .noAccount,
                intro: "No account, no wallet, no key — Kalshi's odds are public, so following just brings the markets you pick into your feed. Nothing here ever places a trade.",
                connected: connected)
            // The way back to your things (§460).
            if connected {
                RoomDoor(name: "Kalshi", source: "Kalshi")
                    .listRowSeparator(.hidden)
            }
            PredictionVenueConnect(ownVenue: .kalshi)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .bridgeSetupWash(name: "Kalshi")
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .dsScreenTitle("Kalshi")
    }
}
