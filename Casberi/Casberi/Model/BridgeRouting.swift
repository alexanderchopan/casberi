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
        case railgun
        /// The Safe multisig signature queue (2026-07-30) — same shape as
        /// `.peer`/`.privacyPools`: no account of its own, "connecting" IS
        /// watching a wallet (§207), and Connect for the "Safe" offer routes
        /// straight to the wallet manager (see `destination(forOffer:)`).
        case safe
        case exchange(ExchangeBridge.Venue)
        case ethValidators
        case kalshi
        case polymarket
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
        case instagram
        case claude
        case gemini
        case venice
        case bankr
        case openRouter
        case grok
        case bluesky
        case farcaster
        /// Snapchat sits with the social seats but behaves like the ChatGPT
        /// imports — Snap exposes no readable API, so its screen is a file
        /// pick, not a handle field.
        case snapchat
        case pinterest
        case steam
        case obsidian
        case files
        case dropbox
        case twitch
        case spotify
        case slack
        case substack
        case reddit
        case youtube
        case podcasts
        case kindle
        case dayOne
        case appleJournal
        case appleNotes
        case bookmarks
        case token(TokenBridge)
        /// PostHog is a TokenBridge for its key and seat id, but a WATCH LIST
        /// on screen — so it needs its own Destination rather than riding
        /// `.token`. As `.token` it inherited `finishesOnConnect == true` and
        /// the raised sheet dismissed itself the moment the first watched
        /// metric registered the seat (review, 2026-07-27).
        case posthog
        /// Stripe is a TokenBridge for its key and seat id, but its screen has
        /// its own connected state (a balance and what it watches), so it takes
        /// its own Destination for PostHog's reason — riding `.token` would
        /// give it `finishesOnConnect == true` and dismiss the raised sheet the
        /// moment the key registered the seat.
        case stripe
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

        /// **Connect raises; Open pushes** (prd §219, 2026-07-25, correcting
        /// §218's split). Connecting is one act, wherever it lands — paste a
        /// key, type a handle, pick a file — so it rises as a sheet over the
        /// page that sold it to you, and you never walk a door to do it.
        /// Coming BACK to a connection later is navigation, and that still
        /// pushes, through `destination(forID:)`.
        ///
        /// §218 split this by screen KIND instead — forms rose, watch-list
        /// managers pushed — on the theory that a manager is a place you
        /// return to. True, but it answered the wrong question: returning is
        /// Open's job, not Connect's. And since the catalog leads with Wallet,
        /// Markets and Social, nearly every app a person actually taps was on
        /// the pushing side, so the change was invisible where it mattered
        /// (user: "i don't see the form rising").
        ///
        /// One exception, and it's about mechanics, not taxonomy: **the wallet
        /// room pushes its own screens** (`.walletConnection`, `.walletHistory`)
        /// through `HomeRoute`, which is the stack BEHIND a sheet — so opening
        /// it in one would send its doors somewhere the person can't see. It's
        /// also where Peer/0xBow's Connect lands (§209).
        var raisedByConnect: Bool {
            switch self {
            case .wallet, .walletHistory, .walletConnection, .detail:
                false
            default:
                true
            }
        }

        /// Whether the raised sheet leaves ON ITS OWN once the connection goes
        /// live. A one-shot credential is FINISHED at that moment — staying
        /// would leave someone staring at a manager they reached by pasting a
        /// key. A watch list is not: the first handle usually wants a second
        /// and a third, and dropping the sheet after one would be the app
        /// deciding you were done. Those stay up until they're closed.
        var finishesOnConnect: Bool {
            switch self {
            case .token, .steam, .obsidian, .files, .dropbox, .twitch, .spotify, .slack,
                 .icloudMail, .gmail, .exchange,
                 // Grok is `OpenRouterSetupScreen` structurally (its own
                 // doc-comment says so) and was missed here when it landed
                 // 2026-07-31 — so a verified key left the raised sheet sitting
                 // there, alone among the agent seats (audit, 2026-07-31).
                 .venice, .bankr, .openRouter, .grok,
                 .chatgpt, .claude, .gemini,
                 .kindle, .dayOne, .appleJournal, .appleNotes, .bookmarks:
                true
            // Snapchat is an import, but NOT a one-shot: landing the export
            // is the first of two acts, and the second (fetching the
            // memories' pictures, against links that expire) only appears
            // once the first has run. Dismissing on connect would close the
            // sheet on the button the person still needs.
            case .snapchat:
                false
            default:
                false
            }
        }

        /// Connects by handing over a FILE you exported yourself, not by a
        /// live credential — so there is no "moment you connect" and nothing
        /// arrives later on its own. Everything in the export lands in one
        /// pass, each thing dated to when it actually happened. Used by
        /// `AppDetailScreen` to say which of those two worlds an offer is in.
        var isFileImport: Bool {
            switch self {
            case .chatgpt, .claude, .gemini, .instagram, .snapchat,
                 .kindle, .dayOne, .appleJournal, .bookmarks:
                true
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
            case .railgun:        "railgun"
            case .safe:           "safe"
            // The venue's own raw value IS the seat id ("kraken", "coinbase"),
            // so the Row above and this can't drift apart.
            case .exchange(let venue): venue.rawValue
            case .ethValidators:  "ethvalidators"
            case .kalshi:         "kalshi"
            case .polymarket:     "polymarket"
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
            case .grok:           "grok"
            case .bluesky:        "bsky"
            case .farcaster:      "fc"
            // Missing when Instagram landed (2026-07-31) — this switch has no
            // `default`, so its absence was a build break, and a seat with no
            // id can't resolve `destination(forID:)` either.
            case .instagram:      "instagram"
            case .snapchat:       "snapchat"
            case .pinterest:      "pinterest"
            case .steam:          "steam"
            case .obsidian:       "obsidian"
            case .files:          "files"
            case .dropbox:        "dropbox"
            case .twitch:         "twitch"
            case .spotify:        "spotify"
            case .slack:          "slack"
            case .substack:       "substack"
            case .reddit:         "reddit"
            case .youtube:        "youtube"
            case .podcasts:       "podcasts"
            case .kindle:         "kindle"
            case .dayOne:         "dayone"
            case .appleJournal:   "journal"
            case .appleNotes:     "notes"
            case .bookmarks:      "bookmarks"
            case .token(let b):   b.bridgeID
            case .posthog:        TokenBridge.posthog.bridgeID
            case .stripe:         TokenBridge.stripe.bridgeID
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
        Row(offer: "Railgun", id: "railgun", destination: .railgun),
        Row(offer: "Safe", id: "safe", destination: .safe),
        // Gnosis Pay has no screen of its own, and routes BOTH ways to the
        // wallet manager (prd §222). Connect, because watching the wallet is
        // the only real action — the §209 reasoning. Open, because the
        // generic BridgeDetailScreen carries a Remove button, and this seat
        // is a MIRROR of "has a watched wallet spent on a card": removing it
        // would silently re-register on the next foreground, which is exactly
        // the dead control the honesty rule forbids. The spends themselves
        // live in the feed, where every other landed thing lives.
        Row(offer: "Gnosis Pay", id: "gnosispay", destination: .wallet),
        // The five DeFi protocols seated 2026-07-30 route BOTH ways to the
        // wallet manager for the same two reasons Gnosis Pay does — watching
        // a wallet is the only real action, and the generic
        // `BridgeDetailScreen`'s Remove would be a dead control against a
        // seat that re-registers itself next foreground. They add a third:
        // their live book already has a home in the Wallet feed's own DeFi
        // tiles, so a screen here would only duplicate it. If one ever grows
        // something to manage that the feed can't carry, it earns its own
        // screen then — that's what Peer/0xBow/Safe have.
        Row(offer: "Aave",        id: "aave",        destination: .wallet),
        Row(offer: "Morpho",      id: "morpho",      destination: .wallet),
        Row(offer: "Uniswap",     id: "uniswap",     destination: .wallet),
        Row(offer: "Hyperliquid", id: "hyperliquid", destination: .wallet),
        Row(offer: "Aerodrome",   id: "aerodrome",   destination: .wallet),
        Row(offer: "ether.fi",    id: "etherfi",     destination: .wallet),
        // Read-only exchange seats (prd §163) — Wallet group by ruling: their
        // balances merge into the combined total, so they belong beside the
        // wallets they join.
        Row(offer: "Coinbase",  id: "coinbase", destination: .exchange(.coinbase)),
        Row(offer: "Kraken",    id: "kraken",   destination: .exchange(.kraken)),
        Row(offer: "Binance",   id: "binance",  destination: .exchange(.binance)),
        Row(offer: "Gemini Exchange", id: "geminiExchange", destination: .exchange(.geminiExchange)),
        Row(offer: "ETH Validators", id: "ethvalidators", destination: .ethValidators),
        Row(offer: "Kalshi",     id: "kalshi",     destination: .kalshi),
        Row(offer: "Polymarket", id: "polymarket", destination: .polymarket),
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
        Row(offer: "Instagram", id: "instagram", destination: .instagram),
        Row(offer: "Claude",    id: "claude", destination: .claude),
        Row(offer: "Gemini",    id: "gemini", destination: .gemini),
        Row(offer: "Venice",    id: "venice", destination: .venice),
        Row(offer: "Bankr",     id: "bankr",  destination: .bankr),
        Row(offer: "OpenRouter", id: "openrouter", destination: .openRouter),
        Row(offer: "Grok",       id: "grok",   destination: .grok),
        Row(offer: "Bluesky",   id: "bsky",   destination: .bluesky),
        Row(offer: "Farcaster", id: "fc",     destination: .farcaster),
        Row(offer: "Snapchat",  id: "snapchat", destination: .snapchat),
        Row(offer: "Pinterest", id: "pinterest", destination: .pinterest),
        Row(offer: "Steam",     id: "steam",  destination: .steam),
        Row(offer: "Obsidian",  id: "obsidian", destination: .obsidian),
        Row(offer: "Files",     id: "files",  destination: .files),
        Row(offer: "Dropbox",   id: "dropbox", destination: .dropbox),
        Row(offer: "Twitch",    id: "twitch", destination: .twitch),
        Row(offer: "Spotify",   id: "spotify", destination: .spotify),
        Row(offer: "Slack",    id: "slack",   destination: .slack),
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
        Row(offer: "Bookmarks", id: "bookmarks", destination: .bookmarks),
        Row(offer: "PostHog", id: "posthog", destination: .posthog),
        Row(offer: "Stripe", id: "stripe", destination: .stripe),
    ] + TokenBridge.allCases.filter { $0 != .posthog && $0 != .stripe }.map {
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
        if name == "Peer" || name == "0xBow Privacy Pools" || name == "Safe"
            || name == "Railgun" { return .wallet }
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
        case .railgun:        RailgunScreen()
        case .safe:           SafeScreen()
        case .ethValidators:  EthValidatorScreen()
        case .kalshi:         KalshiScreen()
        case .polymarket:     PolymarketScreen()
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
        case .instagram:      InstagramImportScreen()
        case .claude:         ClaudeImportScreen()
        case .gemini:         GeminiImportScreen()
        case .venice:         VeniceSetupScreen()
        case .bankr:          BankrSetupScreen()
        case .openRouter:     OpenRouterSetupScreen()
        case .grok:           GrokSetupScreen()
        case .exchange(let venue): ExchangeSetupScreen(venue: venue)
        case .bluesky:        HandleSetupScreen(bridge: .bluesky)
        case .farcaster:      HandleSetupScreen(bridge: .farcaster)
        case .snapchat:       SnapchatImportScreen()
        case .pinterest:      HandleSetupScreen(bridge: .pinterest)
        case .steam:          SteamScreen()
        case .obsidian:       ObsidianScreen()
        case .files:          FilesScreen()
        case .dropbox:        DropboxScreen()
        case .twitch:         TwitchScreen()
        case .spotify:        SpotifyScreen()
        case .slack:          SlackScreen()
        case .substack:       HandleSetupScreen(bridge: .substack)
        case .reddit:         HandleSetupScreen(bridge: .reddit)
        case .youtube:        HandleSetupScreen(bridge: .youtube)
        case .podcasts:       HandleSetupScreen(bridge: .podcasts)
        case .kindle:         KindleImportScreen()
        case .dayOne:         DayOneImportScreen()
        case .appleJournal:   JournalImportScreen()
        case .appleNotes:     NotesShareScreen()
        case .bookmarks:      BookmarksImportScreen()
        case .token(let b):   TokenSetupScreen(bridge: b)
        case .posthog:        PostHogScreen()
        case .stripe:         StripeScreen()
        case .walletHistory(let scope): WalletHistoryScreen(scope: scope)
        case .walletConnection: WalletConnectionScreen()
        case .detail(let id): BridgeDetailScreen(bridgeID: id)
        }
    }
}

/// The connect form as a RAISED sheet (prd §218, 2026-07-25) — the bridge's
/// own setup screen, unedited, over the page that sold it to you.
///
/// It owns one rule the pushed route doesn't need: **a one-shot form leaves
/// when it's done.** The moment such a bridge's seat reads `.connected`, the
/// sheet dismisses itself, so nobody is left staring at a manager they arrived
/// at by pasting a key. A watch list stays up — see `finishesOnConnect`. The
/// seat is watched rather than a per-screen callback because there are ~35 of
/// these screens and not one of them had to change to gain this behaviour:
/// `BridgeStore` already records the exact moment a connection becomes real,
/// and it's the same record the product page's proof pill and
/// `BridgeDetailScreen` read.
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
            guard isLive, destination.finishesOnConnect else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(700))
                dismiss()
            }
        }
    }
}
