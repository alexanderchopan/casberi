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
        case wallet
        case tokens
        case kalshi
        case stocktwits
        case openSea
        case geckoTerminal
        case shopify
        case deals
        case openFoodFacts
        case icloudMail
        case gmail
        case rss
        case chatgpt
        case claude
        case gemini
        case venice
        case bankr
        case bluesky
        case farcaster
        case pinterest
        case steam
        case obsidian
        case twitch
        case spotify
        case substack
        case reddit
        case youtube
        case podcasts
        case kindle
        case dayOne
        case appleJournal
        case appleNotes
        case token(TokenBridge)
        /// A connected seat with no dedicated screen (the demo seats — Gmail,
        /// Calendar, …) — the generic detail page, never EmptyView.
        case detail(id: String)

        var id: String {
            switch self {
            case .wallet:         "wallet"
            case .tokens:         "tokens"
            case .kalshi:         "kalshi"
            case .stocktwits:     "stocktwits"
            case .openSea:        "opensea"
            case .geckoTerminal:  "geckoterminal"
            case .shopify:        "shopify"
            case .deals:          "deals"
            case .openFoodFacts:  "off"
            case .icloudMail:     "icloudmail"
            case .gmail:          "gmail"
            case .rss:            "rss"
            case .chatgpt:        "gpt"
            case .claude:         "claude"
            case .gemini:         "gemini"
            case .venice:         "venice"
            case .bankr:          "bankr"
            case .bluesky:        "bsky"
            case .farcaster:      "fc"
            case .pinterest:      "pinterest"
            case .steam:          "steam"
            case .obsidian:       "obsidian"
            case .twitch:         "twitch"
            case .spotify:        "spotify"
            case .substack:       "substack"
            case .reddit:         "reddit"
            case .youtube:        "youtube"
            case .podcasts:       "podcasts"
            case .kindle:         "kindle"
            case .dayOne:         "dayone"
            case .appleJournal:   "journal"
            case .appleNotes:     "notes"
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
        Row(offer: "Wallet",    id: "wallet", destination: .wallet),
        Row(offer: "Tokens",    id: "tokens", destination: .tokens),
        Row(offer: "Kalshi",     id: "kalshi",     destination: .kalshi),
        Row(offer: "Stocktwits", id: "stocktwits", destination: .stocktwits),
        Row(offer: "OpenSea",    id: "opensea",    destination: .openSea),
        Row(offer: "GeckoTerminal", id: "geckoterminal", destination: .geckoTerminal),
        Row(offer: "Shopify",    id: "shopify",    destination: .shopify),
        Row(offer: "Deals",      id: "deals",      destination: .deals),
        Row(offer: "Open Food Facts", id: "off",   destination: .openFoodFacts),
        Row(offer: "iCloud Mail", id: "icloudmail",  destination: .icloudMail),
        Row(offer: "Gmail",       id: "gmail",       destination: .gmail),
        Row(offer: "RSS",       id: "rss",    destination: .rss),
        Row(offer: "ChatGPT",   id: "gpt",    destination: .chatgpt),
        Row(offer: "Claude",    id: "claude", destination: .claude),
        Row(offer: "Gemini",    id: "gemini", destination: .gemini),
        Row(offer: "Venice",    id: "venice", destination: .venice),
        Row(offer: "Bankr",     id: "bankr",  destination: .bankr),
        Row(offer: "Bluesky",   id: "bsky",   destination: .bluesky),
        Row(offer: "Farcaster", id: "fc",     destination: .farcaster),
        Row(offer: "Pinterest", id: "pinterest", destination: .pinterest),
        Row(offer: "Steam",     id: "steam",  destination: .steam),
        Row(offer: "Obsidian",  id: "obsidian", destination: .obsidian),
        Row(offer: "Twitch",    id: "twitch", destination: .twitch),
        Row(offer: "Spotify",   id: "spotify", destination: .spotify),
        Row(offer: "Substack",  id: "substack", destination: .substack),
        Row(offer: "Reddit",    id: "reddit",   destination: .reddit),
        Row(offer: "YouTube",   id: "youtube",  destination: .youtube),
        Row(offer: "Podcasts",  id: "podcasts", destination: .podcasts),
        Row(offer: "Kindle",    id: "kindle",   destination: .kindle),
        Row(offer: "Day One",   id: "dayone", destination: .dayOne),
        Row(offer: "Apple Journal", id: "journal", destination: .appleJournal),
        // Apple Notes never registers a seat (nothing to connect) — the row
        // exists so Connect routes to the share-path explainer (prd 55).
        Row(offer: "Apple Notes", id: "notes", destination: .appleNotes),
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
        case .wallet:         WalletScreen()
        case .tokens:         TokenWatchScreen()
        case .kalshi:         KalshiScreen()
        case .stocktwits:     StocktwitsScreen()
        case .openSea:        OpenSeaScreen()
        case .geckoTerminal:  GeckoTerminalScreen()
        case .shopify:        ShopifyScreen()
        case .deals:          DealsScreen()
        case .openFoodFacts:  OpenFoodFactsScreen()
        case .icloudMail:     MailScreen(provider: .icloud)
        case .gmail:          MailScreen(provider: .gmail)
        case .rss:            RSSScreen()
        case .chatgpt:        ChatGPTImportScreen()
        case .claude:         ClaudeImportScreen()
        case .gemini:         GeminiImportScreen()
        case .venice:         VeniceSetupScreen()
        case .bankr:          BankrSetupScreen()
        case .bluesky:        HandleSetupScreen(bridge: .bluesky)
        case .farcaster:      HandleSetupScreen(bridge: .farcaster)
        case .pinterest:      HandleSetupScreen(bridge: .pinterest)
        case .steam:          SteamScreen()
        case .obsidian:       ObsidianScreen()
        case .twitch:         TwitchScreen()
        case .spotify:        SpotifyScreen()
        case .substack:       HandleSetupScreen(bridge: .substack)
        case .reddit:         HandleSetupScreen(bridge: .reddit)
        case .youtube:        HandleSetupScreen(bridge: .youtube)
        case .podcasts:       HandleSetupScreen(bridge: .podcasts)
        case .kindle:         KindleImportScreen()
        case .dayOne:         DayOneImportScreen()
        case .appleJournal:   JournalImportScreen()
        case .appleNotes:     NotesShareScreen()
        case .token(let b):   TokenSetupScreen(bridge: b)
        case .detail(let id): BridgeDetailScreen(bridgeID: id)
        }
    }
}
