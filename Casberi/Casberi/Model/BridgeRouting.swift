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
        case peer
        case privacyPools
        case exchange(ExchangeBridge.Venue)
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
        case openRouter
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
        /// Every wallet transaction, day by day (2026-07-20) — the page behind
        /// the Wallet feed's "See all". Carries the feed's wallet scope so the
        /// door doesn't silently widen it; nil is every watched wallet.
        case walletHistory(scope: String?)
        /// The wallet's connection plumbing — chains, WalletConnect key, and
        /// Disconnect (prd §182, 2026-07-22, amending §139). §139 killed doors
        /// to READS ("every safety fact had a better home that isn't a page");
        /// this is configuration, set once and rarely revisited, and it was
        /// charging every visit to the manager rent it shouldn't pay. One door
        /// for the one thing on this screen that actually IS a settings page.
        case walletConnection
        /// A connected seat with no dedicated screen (the demo seats — Gmail,
        /// Calendar, …) — the generic detail page, never EmptyView.
        case detail(id: String)

        /// True when this screen is a FORM you finish, not a manager you live
        /// in (prd §218, 2026-07-25). The distinction decides how Connect
        /// presents it: a form rises as a sheet over the product page you were
        /// reading — you never leave, and finishing drops you back where the
        /// promise was made — while a manager is pushed, because you'll return
        /// to it next month to add another feed.
        ///
        /// The test is whether there's anything left to do on the screen once
        /// it's connected. A pasted key, a signed-in account, a picked file:
        /// nothing. A watch list (§184's roster, §202's stars): everything.
        var isForm: Bool {
            switch self {
            case .token, .steam, .obsidian, .twitch, .spotify,
                 .icloudMail, .gmail, .exchange,
                 .venice, .bankr, .openRouter,
                 .chatgpt, .claude, .gemini,
                 .kindle, .dayOne, .appleJournal, .appleNotes:
                true
            // Managers, every one: a roster or a ledger you come back to.
            // `.wallet` covers Peer/0xBow's Connect too (§209) — routing a
            // person into another app's manager inside a sheet would strand
            // them there, which is exactly what pushing avoids.
            default:
                false
            }
        }

        var id: String {
            switch self {
            case .wallet:         "wallet"
            case .tokens:         "tokens"
            case .peer:           "peer"
            case .privacyPools:   "privacypools"
            // The venue's own raw value IS the seat id ("kraken", "coinbase"),
            // so the Row above and this can't drift apart.
            case .exchange(let venue): venue.rawValue
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
            case .openRouter:     "openrouter"
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
            case .walletHistory(let scope): "wallethistory:\(scope ?? "all")"
            case .walletConnection: "walletconnection"
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
        Row(offer: "Peer",      id: "peer",   destination: .peer),
        Row(offer: "0xBow Privacy Pools", id: "privacypools", destination: .privacyPools),
        // Gnosis Pay has no screen of its own, and routes BOTH ways to the
        // wallet manager (prd §222). Connect, because watching the wallet is
        // the only real action — the §209 reasoning. Open, because the
        // generic BridgeDetailScreen carries a Remove button, and this seat
        // is a MIRROR of "has a watched wallet spent on a card": removing it
        // would silently re-register on the next foreground, which is exactly
        // the dead control the honesty rule forbids. The spends themselves
        // live in the feed, where every other landed thing lives.
        Row(offer: "Gnosis Pay", id: "gnosispay", destination: .wallet),
        // Read-only exchange seats (prd §163) — Wallet group by ruling: their
        // balances merge into the combined total, so they belong beside the
        // wallets they join.
        Row(offer: "Coinbase",  id: "coinbase", destination: .exchange(.coinbase)),
        Row(offer: "Kraken",    id: "kraken",   destination: .exchange(.kraken)),
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
        Row(offer: "OpenRouter", id: "openrouter", destination: .openRouter),
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
        // Peer & 0xBow Privacy Pools have no setup of their own — "connecting"
        // them IS watching a wallet (prd §207/§209). So the CONNECT flow (every
        // caller of `forOffer`) routes straight to the Wallet manager instead
        // of a pass-through setup screen that only re-doored there — one fewer
        // screen between the catalog and the one real action. Their own screen
        // (recent fills) is unaffected: it's the OPEN/manage path, which resolves
        // through `destination(forID:)` below, and still returns `.peer`/
        // `.privacyPools` once a wallet is watched and the seat reads connected.
        if name == "Peer" || name == "0xBow Privacy Pools" { return .wallet }
        return rows.first { $0.offer == name }?.destination
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
        case .peer:           PeerScreen()
        case .privacyPools:   PrivacyPoolsScreen()
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
        case .openRouter:     OpenRouterSetupScreen()
        case .exchange(let venue): ExchangeSetupScreen(venue: venue)
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
        case .walletHistory(let scope): WalletHistoryScreen(scope: scope)
        case .walletConnection: WalletConnectionScreen()
        case .detail(let id): BridgeDetailScreen(bridgeID: id)
        }
    }
}

/// The connect form as a RAISED sheet (prd §218, 2026-07-25) — the bridge's
/// own setup screen, unedited, over the page that sold it to you.
///
/// It owns one rule the pushed route doesn't need: **a form leaves when it's
/// done.** The moment this bridge's seat reads `.connected`, the sheet
/// dismisses itself, so nobody is left staring at a manager they arrived at by
/// pasting a key. The seat is watched rather than a per-screen callback
/// because there are ~18 of these screens and not one of them had to change to
/// gain this behaviour — `BridgeStore` already records the exact moment a
/// connection becomes real, and it's the same record the product page's proof
/// pill and `BridgeDetailScreen` read.
struct ConnectFormSheet: View {
    let destination: BridgeRouter.Destination
    @Environment(BridgeStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// Live and healthy. `.attention` deliberately doesn't count — the Fix
    /// path raises this same sheet, and it should stay up until the
    /// connection actually works again.
    private var live: Bool {
        store.bridges.first { $0.id == destination.id }?.status == .connected
    }

    var body: some View {
        NavigationStack {
            BridgeDestinationView(destination: destination)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Close") { dismiss() }
                            .dsText(.callout15).foregroundStyle(DS.tint)
                    }
                }
        }
        .presentationDragIndicator(.visible)
        .onChange(of: live) { _, isLive in
            // A beat, so the screen's own success moment (the icon's coin
            // flip, the proof line counting up) is seen rather than cut off
            // by the dismissal it triggers.
            guard isLive else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(700))
                dismiss()
            }
        }
    }
}
