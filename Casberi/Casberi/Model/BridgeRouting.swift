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
        /// Altana's keystore. A `walletSeats` member that owns addresses too
        /// (2026-08-28, amending §465) — the registry's own accounts, free and
        /// uncapped, because they are not your wallets and the read is keyless.
        case altana
        case exchange(ExchangeBridge.Venue)
        case ethValidators
        case kalshi
        case polymarket
        case stocktwits
        case openSea
        case geckoTerminal
        /// ENS (prd §534) — keyless with a FOLLOW list on screen, Walletbeat's
        /// exact reason: as `.token` it would inherit `finishesOnConnect ==
        /// true` and the raised sheet would dismiss itself the moment the first
        /// followed name registered the seat, and the first name almost always
        /// wants a second.
        case ens

        /// Walletbeat is keyless with a WATCH LIST on screen, so it needs its own
        /// destination rather than riding `.token`: as `.token` it would inherit
        /// `finishesOnConnect == true` and the raised sheet would dismiss itself the
        /// moment the first watched wallet registered the seat — and the first wallet
        /// almost always wants a second (prd §419).
        case walletbeat
        /// L2BEAT, for Walletbeat's exact reason (prd §428): keyless, with a WATCH
        /// LIST on screen, so as `.token` it would inherit `finishesOnConnect == true`
        /// and the raised sheet would dismiss itself the moment the first watched
        /// chain registered the seat — and the first chain almost always wants a second.
        case l2beat
        /// CardPointers (prd §420) — its own destination rather than `.token`
        /// because there is no token to paste: sign-in is a device flow, and
        /// the screen has a real state between "signed in" and "connected"
        /// (an account without CardPointers+), which `.token`'s
        /// `finishesOnConnect` would dismiss straight past.
        case cardPointers
        /// Circle's public x402 directory (2026-08-06) — a watch list of lanes,
        /// so it must NOT ride `.token`: it has no token at all, and the first
        /// lane usually wants a second.
        case circleX402
        case huggingFace
        case radicle
        /// Base's vibenet devnet — a WATCH LIST of addresses on
        /// screen with no single credential to paste, so it needs its own
        /// destination for the reason L2BEAT/Walletbeat do: riding `.token`
        /// would give it `finishesOnConnect == true` and dismiss the raised
        /// sheet the moment the first watched address registered the seat.
        case vibenet
        /// Ethrex Hegotá — a WATCH LIST like vibenet's, and its own
        /// destination for the same reason: riding `.token` would give it
        /// `finishesOnConnect == true` and dismiss the raised sheet the
        /// moment the first watched address registered the seat.
        case hegota
        case frames
        case shopify
        case deals
        case openFoodFacts
        case icloudMail
        case gmail
        case rss
        case chatgpt
        case instagram
        case claude
        /// Claude Code (2026-08-08) — an import like the three chat seats, but
        /// of a folder that is already on this machine rather than of a file
        /// somebody has to request and wait for.
        case claudeCode
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
        /// TikTok, same shape as Snapchat and for a harder reason: no RSS ever,
        /// a Display API that reads only your own posts, and an EEA-only
        /// portability API. The export is the whole door (prd §279).
        case tiktok
        /// X, the same file-pick shape and the hardest reason of the three:
        /// the free API tier was discontinued for new developers on
        /// 2026-02-06 and there is no keyless read left at any price worth
        /// taking. The archive is the only door (prd §280).
        case x
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
        case telegram
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
        /// Apple Wallet (prd §313) — FinanceKit. Its own Destination rather
        /// than `.token` because it has no token at all: consent is Apple's
        /// own per-account prompt, and the screen must state the entitlement's
        /// terms BEFORE that prompt is raised.
        case appleWallet
        /// Stripe is a TokenBridge for its key and seat id, but its screen has
        /// its own connected state (a balance and what it watches), so it takes
        /// its own Destination for PostHog's reason — riding `.token` would
        /// give it `finishesOnConnect == true` and dismiss the raised sheet the
        /// moment the key registered the seat.
        case stripe
        /// Polar is a TokenBridge for its token and seat id, but its screen
        /// has its own connected state (a revenue reading and what it
        /// watches), so it takes its own Destination for Stripe's exact
        /// reason — riding `.token` would give it `finishesOnConnect ==
        /// true` and dismiss the raised sheet the moment the token
        /// registered the seat.
        case polar
        /// Sentry is a TokenBridge for its token and seat id, but its screen
        /// resolves a HOST and an ORGANIZATION before it can read anything —
        /// so it takes its own Destination for PostHog's reason: riding
        /// `.token` would give it `finishesOnConnect == true` and drop the
        /// sheet the moment the token was stored, with no org picked yet.
        case sentry
        /// App Store Connect is a TokenBridge for its vault slot and seat id,
        /// but it takes THREE credentials (a `.p8`, a key ID, an issuer ID)
        /// and its connected state lists the apps it can see — so it takes its
        /// own Destination for PostHog's reason: riding `.token` would give it
        /// `finishesOnConnect == true` and drop the raised sheet the moment
        /// the key was stored, with no key ID entered yet.
        case appStoreConnect
        /// AWS is a TokenBridge for its secret key's vault slot and seat id,
        /// but it takes a THREE-field credential (access key ID, secret key,
        /// region) and its connected state shows what's standing — so it
        /// takes its own Destination for App Store Connect's exact reason.
        case aws
        /// npm and PyPI share one screen and one ingest, parameterised by
        /// registry — the `.exchange(venue)` shape. They are watch lists, so
        /// they must not ride `.token` (they have no token at all) and must
        /// not finish on connect: the first package usually wants a second.
        case packages(PackageRegistry)
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
        /// **NOTHING raises on Mac (2026-08-20, user: "when you go to connect
        /// an app a small modal pops up").**
        ///
        /// The reasoning above is a TOUCH argument and it stays true on touch:
        /// a phone has one screen, so raising a form over the page that sold it
        /// to you really is cheaper than walking a door. A Mac window is not one
        /// screen, and Catalyst does not present this the way iOS does — a modal
        /// with no explicit sizing becomes a **form sheet**, a fixed ~540×620
        /// card floating in the middle of whatever the window's real size is.
        /// So the argument inverts on three counts:
        ///
        ///   • The card is the same size in a 2000pt window as in a 980pt one,
        ///     which is the definition of a layout made for another device.
        ///   • A Catalyst form sheet reports **compact** horizontal size class,
        ///     so `dsAdaptiveContentWidth()` — which every setup screen wears —
        ///     is a no-op inside it. The form gets phone layout in a phone-sized
        ///     box on a desktop.
        ///   • The rail lives OUTSIDE the navigation stack and survives a push,
        ///     so a pushed connect form keeps the app's primary navigation
        ///     beside it. A sheet covers it.
        ///
        /// Pushing costs nothing that raising was buying: there IS no back-stack
        /// to walk on a Mac (⌘[ and the chevron are one gesture, and the rail
        /// never left), and the one behaviour the sheet owned — a one-shot form
        /// leaving once its key lands — is preserved by `ConnectPushWatcher`,
        /// which pops on exactly the same signal after exactly the same beat.
        ///
        /// The iOS exception below is about MECHANICS rather than taxonomy (a
        /// room that pushes its own doors through the stack behind a sheet), and
        /// on Mac that exception is simply the universal case.
        var raisedByConnect: Bool {
            #if targetEnvironment(macCatalyst)
            return false
            #else
            switch self {
            case .wallet, .walletHistory, .walletConnection, .detail:
                return false
            default:
                return true
            }
            #endif
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
                 .chatgpt, .claude, .claudeCode, .gemini,
                 .kindle, .dayOne, .appleJournal, .appleNotes, .bookmarks:
                true
            // Snapchat is an import, but NOT a one-shot: landing the export
            // is the first of two acts, and the second (fetching the
            // memories' pictures, against links that expire) only appears
            // once the first has run. Dismissing on connect would close the
            // sheet on the button the person still needs.
            // TikTok is the same two-act shape: the export lands, then the
            // saved videos are given their real faces. Same reason not to
            // dismiss — the second button only exists once the first has run.
            case .snapchat, .tiktok:
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
            case .chatgpt, .claude, .claudeCode, .gemini, .instagram, .snapchat, .tiktok, .x,
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
            case .altana:         "altana"
            // The venue's own raw value IS the seat id ("kraken", "coinbase"),
            // so the Row above and this can't drift apart.
            case .exchange(let venue): venue.rawValue
            case .ethValidators:  "ethvalidators"
            case .kalshi:         "kalshi"
            case .polymarket:     "polymarket"
            case .stocktwits:     "stocktwits"
            case .openSea:        "opensea"
            case .geckoTerminal:  "geckoterminal"
            case .ens:            "ens"
            case .walletbeat:     "walletbeat"
            case .l2beat:         "l2beat"
            case .cardPointers:   "cardpointers"
            case .circleX402:     "x402"
            case .huggingFace:    "huggingface"
            case .radicle:        "radicle"
            case .vibenet:        VibenetIdentity.seatID
            case .hegota:         HegotaIdentity.seatID
            case .frames:         FramesIdentity.seatID
            case .shopify:        "shopify"
            case .deals:          "deals"
            case .openFoodFacts:  "off"
            case .icloudMail:     "icloudmail"
            case .gmail:          "gmail"
            case .rss:            "rss"
            case .chatgpt:        "gpt"
            case .claude:         "claude"
            case .claudeCode:     "claudecode"
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
            case .x:              "x"
            case .tiktok:         "tiktok"
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
            case .telegram:       "telegram"
            case .kindle:         "kindle"
            case .dayOne:         "dayone"
            case .appleJournal:   "journal"
            case .appleNotes:     "notes"
            case .bookmarks:      "bookmarks"
            case .token(let b):   b.bridgeID
            case .appleWallet:    AppleWalletBridge.seatID
            case .posthog:        TokenBridge.posthog.bridgeID
            case .stripe:         TokenBridge.stripe.bridgeID
            case .polar:          TokenBridge.polar.bridgeID
            case .sentry:         TokenBridge.sentry.bridgeID
            case .appStoreConnect: TokenBridge.appStoreConnect.bridgeID
            case .aws:             TokenBridge.aws.bridgeID
            // The registry's own raw value IS the seat id ("npm", "pypi"), so
            // the Row and this can't drift apart — `.exchange`'s rule.
            case .packages(let r): r.bridgeID
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
        Row(offer: "Altana", id: "altana", destination: .altana),
        Row(offer: "Safe", id: "safe", destination: .safe),
        // Gnosis Pay has no screen of its own (prd §222). CONNECT routes to
        // the wallet manager, because watching the wallet is the only real
        // action — the §209 reasoning. What it must never route to is the
        // generic BridgeDetailScreen: that carries a Remove button, and this
        // seat is a MIRROR of "has a watched wallet spent on a card", so
        // removing it would silently re-register on the next foreground —
        // exactly the dead control the honesty rule forbids. OPEN no longer
        // comes here at all: the spends live in the feed, where every other
        // landed thing lives, so it opens that room (`roomSource(forID:)`).
        Row(offer: "Gnosis Pay", id: "gnosispay", destination: .wallet),
        // (Aave, Morpho, Uniswap, Hyperliquid and Aerodrome had rows here
        // until prd §515. They are not seats any more: all five land under
        // `source: "Wallet"`, so this table pointed Connect at the wallet
        // manager — a screen that cannot say why you are on it — and Open at
        // the Wallet room, which the Wallet seat's own Open already opens.
        // What the wallet reads for you is stated on the Wallet offer now;
        // `roomSource` below carries the rule that kept them out.)
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
        Row(offer: "ENS",        id: "ens",        destination: .ens),
        Row(offer: "Walletbeat", id: "walletbeat", destination: .walletbeat),
        Row(offer: "L2BEAT",     id: "l2beat",     destination: .l2beat),
        Row(offer: "CardPointers", id: "cardpointers", destination: .cardPointers),
        Row(offer: "Circle x402", id: "x402", destination: .circleX402),
        Row(offer: "Hugging Face", id: "huggingface", destination: .huggingFace),
        Row(offer: "Radicle",    id: "radicle",    destination: .radicle),
        Row(offer: "Base Vibenet", id: VibenetIdentity.seatID, destination: .vibenet),
        Row(offer: "Ethrex Hegotá", id: HegotaIdentity.seatID, destination: .hegota),
        Row(offer: "Frames Devnet", id: FramesIdentity.seatID, destination: .frames),
        Row(offer: "Shopify",    id: "shopify",    destination: .shopify),
        Row(offer: "Deals",      id: "deals",      destination: .deals),
        Row(offer: "Open Food Facts", id: "off",   destination: .openFoodFacts),
        Row(offer: "iCloud Mail", id: "icloudmail",  destination: .icloudMail),
        Row(offer: "Gmail",       id: "gmail",       destination: .gmail),
        Row(offer: "RSS",       id: "rss",    destination: .rss),
        Row(offer: "ChatGPT",   id: "gpt",    destination: .chatgpt),
        Row(offer: "Instagram", id: "instagram", destination: .instagram),
        Row(offer: "Claude",    id: "claude", destination: .claude),
        Row(offer: "Claude Code", id: "claudecode", destination: .claudeCode),
        Row(offer: "Gemini",    id: "gemini", destination: .gemini),
        Row(offer: "Venice",    id: "venice", destination: .venice),
        Row(offer: "Bankr",     id: "bankr",  destination: .bankr),
        Row(offer: "OpenRouter", id: "openrouter", destination: .openRouter),
        Row(offer: "Grok",       id: "grok",   destination: .grok),
        Row(offer: "Bluesky",   id: "bsky",   destination: .bluesky),
        Row(offer: "Farcaster", id: "fc",     destination: .farcaster),
        Row(offer: "Snapchat",  id: "snapchat", destination: .snapchat),
        Row(offer: "TikTok",    id: "tiktok",   destination: .tiktok),
        Row(offer: "X",         id: "x",        destination: .x),
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
        Row(offer: "Telegram",  id: "telegram", destination: .telegram),
        Row(offer: "Kindle",    id: "kindle",   destination: .kindle),
        Row(offer: "Day One",   id: "dayone", destination: .dayOne),
        Row(offer: "Apple Journal", id: "journal", destination: .appleJournal),
        // Apple Notes never registers a seat (nothing to connect) — the row
        // exists so Connect routes to the share-path explainer (prd 55).
        Row(offer: "Apple Notes", id: "notes", destination: .appleNotes),
        Row(offer: "Bookmarks", id: "bookmarks", destination: .bookmarks),
        Row(offer: "Apple Wallet", id: AppleWalletBridge.seatID, destination: .appleWallet),
        Row(offer: "PostHog", id: "posthog", destination: .posthog),
        Row(offer: "Stripe", id: "stripe", destination: .stripe),
        Row(offer: "Polar", id: "polar", destination: .polar),
        Row(offer: "Sentry", id: "sentry", destination: .sentry),
        Row(offer: "App Store Connect", id: "appstoreconnect", destination: .appStoreConnect),
        Row(offer: "AWS", id: "aws", destination: .aws),
        Row(offer: "npm",  id: "npm",  destination: .packages(.npm)),
        Row(offer: "PyPI", id: "pypi", destination: .packages(.pypi)),
    ] + TokenBridge.allCases.filter {
        $0 != .posthog && $0 != .stripe && $0 != .polar && $0 != .sentry
            && $0 != .appStoreConnect && $0 != .aws
    }.map {
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
        //
        // ALTANA IS NOT IN THIS LIST, and the reason is the bug that started
        // the session. It shipped (prd §403) with no row in `rows` and no
        // `Destination` of its own, so this returned nil for it — and Connect,
        // for a `needsSetup` offer, is `HomeRoute.openSetup`, whose first line
        // is `guard let dest else { return }`. The button was therefore a
        // SILENT NO-OP on every tap: the dead control the honesty rule forbids,
        // invisible to every check here because a missing switch case is not a
        // compile error and the screen sweep proves a page painted, never that
        // its button did anything. It has a `Row` and an `AltanaScreen` now
        // (2026-08-28) — routing it here instead would land Connect on the
        // wallet manager, which for this seat is the wrong screen twice over:
        // `WalletIngest.allChains` has no BNB entry, and the accounts worth
        // watching are the registry's, not your wallets'.
        if name == "Peer" || name == "0xBow Privacy Pools" || name == "Safe"
            || name == "Railgun" { return .wallet }
        return rows.first { $0.offer == name }?.destination
    }

    /// Where a connected seat opens (connected route), keyed by BridgeStore id.
    /// Unknown ids — the demo seats — fall to the generic detail screen.
    static func destination(forID id: String) -> Destination {
        rows.first { $0.id == id }?.destination ?? .detail(id: id)
    }

    /// A catalog offer's `BridgeStore` id — the join the catalog screens need
    /// to ask a seat about itself before it is connected (prd §515: which verb
    /// a wallet-riding seat wears, and what its page says under it). Nil for an
    /// offer with no row, which is every offer that registers no seat.
    static func id(forOffer name: String) -> String? {
        rows.first { $0.offer == name }?.id
    }

    /// The ROOM a connected seat opens INSTEAD of pushing a screen, keyed by
    /// `BridgeStore` id — a real `Thing.source`, never the catalog name. That
    /// is `RoomDoor`'s rule and it matters for the same reason: the two differ
    /// where the catalog brands a seat more fully than the bridge stamps it,
    /// and naming the catalog form lands on a room that can never hold a row,
    /// INVISIBLY (the pop happens, the filter is written, and the empty state
    /// looks like an honest empty state).
    ///
    /// Every entry is a WALLET-RIDING seat with no screen of its own (prd
    /// §494, 2026-08-26). Their Open used to push the wallet MANAGER, which is a
    /// roster of addresses — one step short of the thing the tile advertises:
    /// "Aerodrome · never miss the weekly vote" opened onto a list of wallets,
    /// with the lock's countdown another tap away through that screen's own
    /// `RoomDoor`. These seats are EVIDENCE-gated (`WalletSeatEvidence`), so
    /// one exists only once a real position has been SEEN — which leaves
    /// "show me it" as the only honest thing Open can mean here.
    ///
    /// It had seven entries until prd §515 and has two. The five DeFi
    /// protocols (Aave, Morpho, Uniswap, Hyperliquid, Aerodrome) all land
    /// `source: "Wallet"` (prd §349) — so what this table did for them was
    /// point Open at the room the WALLET seat's own Open opens, which is
    /// §494's fix working exactly as designed and revealing that the seat, not
    /// the door, was the mistake. They are not offers any more. Gnosis Pay and
    /// ether.fi land under sources of their own and stay: their rows' comment
    /// already said the spends "live in the feed, where every other landed
    /// thing lives", and no other seat opens those rooms.
    ///
    /// Two routes are deliberately UNCHANGED. **Connect** still lands on the
    /// manager (`destination(forOffer:)` above): watching a wallet is the only
    /// real action, and before one is watched there is nothing in a room to
    /// see. **Fix** still lands there too — a broken seat is repaired in the
    /// manager, and sending it to a room would be the dead control the honesty
    /// rule forbids. Only Open moves.
    ///
    /// Peer, 0xBow, Railgun and Safe ride wallets too and are NOT here: each
    /// owns a screen carrying something the room can't (a fill history, a
    /// signature queue, this phone's signer key), so pushing it is not a step
    /// short of anything.
    ///
    /// Altana joined them on 2026-08-28 and is NOT here either, though it took
    /// a wrong turn on the way. It shipped (§403) with no row and no
    /// `Destination`, so Open fell to `.detail(id:)` — the generic page — while
    /// the keys the tile advertises sat one room away. The first fix routed it
    /// HERE, to its room, on Gnosis Pay's terms. `setup-copy-audit.py` caught
    /// that: it now owns `AltanaScreen`, and a seat whose room is opened
    /// directly makes its own screen unreachable, since the catalog offers
    /// Open and nothing else once connected. So it opens the SCREEN, which
    /// carries a `RoomDoor` — Peer's and vibenet's shape, one door deeper and
    /// no dead end.
    static func roomSource(forID id: String) -> String? {
        switch id {
        // NOTHING MAY ANSWER "Wallet" HERE (prd §515). A seat whose rows land
        // under another seat's source has no room of its own, so its icon is
        // a second door to a room that already has one — which is exactly what
        // Aave, Morpho, Uniswap, Hyperliquid and Aerodrome were until they
        // stopped being offers. The rule is mechanical — `setup-copy-audit.py`
        // check 7e: a catalog seat lands rows under a source of its own, or it
        // is not a seat.
        case "gnosispay": GnosisPayBridge.sourceName
        case "etherfi":   EtherFiCash.source
        default: nil
        }
    }

    /// Open a CONNECTED seat — the one door every catalog Open takes, so the
    /// tile, the shelf row, the Open capsule, the product page and the
    /// `-openBridgeDetail` probe can never disagree about where a seat leads.
    ///
    /// POP FIRST when it is a room. `sourceRequest` is read by `MainSurface`,
    /// which sits BEHIND this pushed stack — asking before popping changes the
    /// room nobody is looking at (`RoomDoor`'s lesson, spelled again here
    /// because this fires from a different stack).
    @MainActor
    static func open(seatID id: String, route: HomeRoute, chrome: ShellChrome) {
        if let room = roomSource(forID: id) {
            route.path = []
            chrome.sourceRequest = room
        } else {
            route.pushBridge(destination(forID: id))
        }
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
        case .altana:         AltanaScreen()
        case .ethValidators:  EthValidatorScreen()
        case .kalshi:         KalshiScreen()
        case .polymarket:     PolymarketScreen()
        case .stocktwits:     StocktwitsScreen()
        case .openSea:        OpenSeaScreen()
        case .geckoTerminal:  GeckoTerminalScreen()
        case .ens:            ENSScreen()
        case .walletbeat:     WalletbeatScreen()
        case .l2beat:         L2beatScreen()
        case .cardPointers:   CardPointersScreen()
        case .circleX402:     CircleX402Screen()
        case .huggingFace:    HuggingFaceScreen()
        case .radicle:        RadicleScreen()
        case .vibenet:        VibenetScreen()
        case .hegota:         HegotaScreen()
        case .frames:         FramesScreen()
        case .shopify:        ShopifyScreen()
        case .deals:          DealsScreen()
        case .openFoodFacts:  OpenFoodFactsScreen()
        case .icloudMail:     MailScreen(provider: .icloud)
        case .gmail:          MailScreen(provider: .gmail)
        case .rss:            RSSScreen()
        case .chatgpt:        ChatGPTImportScreen()
        case .instagram:      InstagramImportScreen()
        case .claude:         ClaudeImportScreen()
        case .claudeCode:     ClaudeCodeImportScreen()
        case .gemini:         GeminiImportScreen()
        case .venice:         VeniceSetupScreen()
        case .bankr:          BankrSetupScreen()
        case .openRouter:     OpenRouterSetupScreen()
        case .grok:           GrokSetupScreen()
        case .exchange(let venue): ExchangeSetupScreen(venue: venue)
        case .bluesky:        HandleSetupScreen(bridge: .bluesky)
        case .farcaster:      HandleSetupScreen(bridge: .farcaster)
        case .snapchat:       SnapchatImportScreen()
        case .tiktok:         TikTokImportScreen()
        case .x:              XArchiveImportScreen()
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
        case .telegram:       HandleSetupScreen(bridge: .telegram)
        case .kindle:         KindleImportScreen()
        case .dayOne:         DayOneImportScreen()
        case .appleJournal:   JournalImportScreen()
        case .appleNotes:     NotesShareScreen()
        case .bookmarks:      BookmarksImportScreen()
        case .token(let b):   TokenSetupScreen(bridge: b)
        case .appleWallet:    AppleWalletScreen()
        case .posthog:        PostHogScreen()
        case .stripe:         StripeScreen()
        case .polar:          PolarScreen()
        case .sentry:         SentryScreen()
        case .appStoreConnect: AppStoreConnectScreen()
        case .aws:             AWSScreen()
        case .packages(let r): PackageWatchScreen(registry: r)
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
        // **This sheet had NO sizing of any kind, and it is the one that got
        // reported (2026-08-20, user: "these modals are way too small, user has
        // to scroll to read them in a tiny box").**
        //
        // Mac stopped raising this at all earlier the same day, so the Mac pass
        // never looked at it as a sheet — but an iPad presents it as a form
        // sheet exactly like a Mac did, and it holds a WHOLE setup screen:
        // a hero card, an "Open X settings" button, three steps of instructions,
        // a toggle and a folder picker, in a ~540x620 box. `.page` gives it the
        // window instead.
        //
        // The general lesson, which is why `dsPageSheet` is now idiom-gated
        // rather than `#if targetEnvironment(macCatalyst)`: "the Mac is the odd
        // one out" was the wrong frame. Every REGULAR idiom sizes its sheets,
        // and iPad had been quietly living with the same box all along.
        .dsPageSheet()
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

/// `ConnectFormSheet`'s one rule, kept for the PUSHED form Mac gets instead
/// (2026-08-20 — see `Destination.raisedByConnect` for why Mac pushes).
///
/// A one-shot form is FINISHED the moment its credential lands, and leaving
/// someone staring at a manager they arrived at by pasting a key is the thing
/// the sheet's self-dismissal exists to prevent. That reasoning is about the
/// FORM, not about the presentation, so it survives the move: same signal (the
/// seat reaching `.connected`), same 700ms beat so the screen's own success
/// moment is seen, and a pop instead of a dismiss.
///
/// **It pops only if this screen is still on top.** `goBack()` removes the last
/// node unconditionally, so a person who navigated onward inside the setup
/// screen during the beat would otherwise have a frame they were reading pulled
/// out from under them. Equality is exact — `Destination` is `Hashable` because
/// `HomeRoute.Node` requires it — so the guard can name the very frame it means.
///
/// Applied to EVERY pushed `.bridge` rather than only to connect pushes, which
/// is safe by construction: `onChange` fires on a CHANGE, and an Open push is
/// already connected at mount, so `live` never transitions and the timer never
/// starts. A destination that isn't `finishesOnConnect` is excluded outright.
private struct ConnectPushWatcher: ViewModifier {
    let destination: BridgeRouter.Destination
    @Environment(BridgeStore.self) private var store
    @Environment(HomeRoute.self) private var route

    private var live: Bool {
        store.bridges.first { $0.id == destination.id }?.status == .connected
    }

    func body(content: Content) -> some View {
        content.onChange(of: live) { _, isLive in
            guard isLive, destination.finishesOnConnect else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(700))
                guard route.path.last == .bridge(destination) else { return }
                route.goBack()
            }
        }
    }
}

extension View {
    /// Mac only — see `ConnectPushWatcher`. A no-op elsewhere, where the same
    /// behaviour is `ConnectFormSheet`'s.
    @ViewBuilder
    func connectPushWatcher(_ destination: BridgeRouter.Destination) -> some View {
        #if targetEnvironment(macCatalyst)
        modifier(ConnectPushWatcher(destination: destination))
        #else
        self
        #endif
    }
}
