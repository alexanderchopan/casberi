import SwiftUI

/// One bridge routing table (2026-07-07). Every bridge that owns a dedicated
/// screen appears exactly once here, carrying its catalog offer name (the
/// setup key) and its BridgeStore seat id (the connected key); the eight token
/// bridges fold in from `TokenBridge`. Both the setup route (an offer's
/// Connect) and the connected route (a seat's Open) read this one table, so
/// adding a bridge is one row — a missed case can never silently push an
/// EmptyView. Replaces the three hand-kept switches (AppsScreen's
/// `SetupDestination` + `connectedDestination`, AppDetailScreen's id/"setup:"
/// routing).
enum BridgeRouter {

    /// A screen a bridge can navigate to.
    enum Destination: Identifiable, Hashable {
        case zerion
        case dexscreener
        case rss
        case chatgpt
        case bluesky
        case farcaster
        case token(TokenBridge)
        /// A connected seat with no dedicated screen (the demo seats — Gmail,
        /// Calendar, …) — the generic detail page, never EmptyView.
        case detail(id: String)

        var id: String {
            switch self {
            case .zerion:         "zerion"
            case .dexscreener:    "dexscreener"
            case .rss:            "rss"
            case .chatgpt:        "gpt"
            case .bluesky:        "bsky"
            case .farcaster:      "fc"
            case .token(let b):   b.bridgeID
            case .detail(let id): "detail:\(id)"
            }
        }
    }

    /// One dedicated bridge: its catalog offer name, its seat id, its screen.
    private struct Row {
        let offer: String
        let id: String
        let destination: Destination
    }

    /// The dedicated built-in bridges. Token bridges append from
    /// `TokenBridge.allCases`, so their eight setup screens need no rows here.
    private static let rows: [Row] = [
        Row(offer: "Zerion",    id: "zerion", destination: .zerion),
        Row(offer: "Dexscreener", id: "dexscreener", destination: .dexscreener),
        Row(offer: "RSS",       id: "rss",    destination: .rss),
        Row(offer: "ChatGPT",   id: "gpt",    destination: .chatgpt),
        Row(offer: "Bluesky",   id: "bsky",   destination: .bluesky),
        Row(offer: "Farcaster", id: "fc",     destination: .farcaster),
    ] + TokenBridge.allCases.map {
        Row(offer: $0.rawValue, id: $0.bridgeID, destination: .token($0))
    }

    /// Where an offer's Connect leads (setup route), keyed by catalog name.
    /// `nil` = the offer has no dedicated screen — its Connect runs
    /// `BridgeConnect` instead of pushing.
    static func destination(forOffer name: String) -> Destination? {
        rows.first { $0.offer == name }?.destination
    }

    /// Where a connected seat opens (connected route), keyed by BridgeStore id.
    /// Unknown ids — the demo seats — fall to the generic detail screen.
    static func destination(forID id: String) -> Destination {
        rows.first { $0.id == id }?.destination ?? .detail(id: id)
    }
}

/// Renders a `BridgeRouter.Destination` — the single place a bridge screen is
/// constructed, so every `navigationDestination` call site defers here.
struct BridgeDestinationView: View {
    let destination: BridgeRouter.Destination

    var body: some View {
        switch destination {
        case .zerion:         ZerionScreen()
        case .dexscreener:    DexscreenerScreen()
        case .rss:            RSSScreen()
        case .chatgpt:        ChatGPTImportScreen()
        case .bluesky:        HandleSetupScreen(bridge: .bluesky)
        case .farcaster:      HandleSetupScreen(bridge: .farcaster)
        case .token(let b):   TokenSetupScreen(bridge: b)
        case .detail(let id): BridgeDetailScreen(bridgeID: id)
        }
    }
}
