import Foundation

/// What this app reaches, and why (prd §205) — the honesty feature made
/// legible. Casberi has no server, so every network call goes STRAIGHT from
/// this iPhone to the service it names; the promise "nothing routes through
/// us" is only trustworthy if a person can see the whole list. This is that
/// list.
///
/// It is a CURATED registry, not a live request log, on purpose. A live log
/// would have to instrument ~18 call sites that each hold their own
/// URLSession — miss one and the log lies by omission, which is worse than
/// no log for a privacy surface. Instead every host literal in the app is
/// asserted to appear here by `scripts/network-reach-audit.sh` (run in
/// verify.sh), so the registry is complete BY CONSTRUCTION: a host added in
/// code that isn't listed here fails the build. That makes this provable
/// where a log would only be plausible.
///
/// Grouped by the SERVICE a person recognizes, not by raw host — one service
/// often spans several hosts (its API, its image CDN, its auth host). Each
/// entry says plainly what the calls are for, and which bridge owns them so
/// the screen can show what's reaching NOW versus only-if-you-connect-it.
enum NetworkReach {

    enum Reach {
        /// Reached only while its owning bridge is connected — the common case.
        case whenConnected(bridge: String)
        /// Reached regardless of any connection (a saved link's own page, a
        /// tapped location) — the small always-on set.
        case always
        /// Reached only when you add your own agent key AND tap "Try with
        /// your key" on an answer — inert until then.
        case onTapWithKey
    }

    struct Endpoint: Identifiable {
        /// Display name — matches the catalog offer where one exists, so the
        /// row wears the same brand mark the catalog does.
        let service: String
        let reach: Reach
        /// One honest sentence: what the calls carry and do.
        let purpose: String
        /// The hosts this service talks to. Shown small under the purpose.
        let hosts: [String]

        var id: String { service }
    }

    /// The registry. Every functional host the app calls lives here under the
    /// service that owns it. Display/permalink hosts a person opens in their
    /// browser (block explorers, a store page) are described in the owning
    /// entry's purpose rather than listed as calls this app makes — the
    /// browser makes those, not us.
    static let endpoints: [Endpoint] = [

        // MARK: Always on — reached without connecting anything

        Endpoint(service: "Saved links",
                 reach: .always,
                 purpose: "When you save a link, \(DS.device) fetches that page once to read its title and preview image. The request goes to the link's own site — whatever you saved — and carries nothing about you.",
                 hosts: ["the site you saved"]),
        Endpoint(service: "Maps",
                 reach: .always,
                 purpose: "Opening a place opens Apple Maps. The location you tapped is all it carries.",
                 hosts: ["maps.apple.com"]),

        // MARK: Wallet & onchain — only while you watch a wallet or token

        Endpoint(service: "Wallet",
                 reach: .whenConnected(bridge: "Wallet"),
                 purpose: "Reads the public onchain activity, balances, approvals, and DeFi positions of the wallets you watch — across Ethereum, Base, Arbitrum, Optimism, Polygon and Solana. Each request carries only a public address you chose to watch. Block explorers (Etherscan, Basescan, Revoke.cash, Solscan) open in your browser when you tap a transaction — this app doesn't call them.",
                 hosts: ["api.g.alchemy.com", "api.zerion.io", "coins.llama.fi",
                         "rpc.mevblocker.io", "mainnet.base.org", "mainnet.optimism.io",
                         "arb1.arbitrum.io", "eth.api.onfinality.io", "polygon.api.onfinality.io"]),
        Endpoint(service: "Wallet names",
                 reach: .whenConnected(bridge: "Wallet"),
                 purpose: "Resolves .eth and .sol names and their avatars for the wallets you watch. Carries only the name or address being resolved.",
                 hosts: ["api.ensideas.com", "metadata.ens.domains", "app.ens.domains",
                         "sns-sdk-proxy.bonfida.workers.dev", "lite-api.jup.ag"]),
        Endpoint(service: "Wallet DeFi & Safe",
                 reach: .whenConnected(bridge: "Wallet"),
                 purpose: "Reads your Aave, Spark and Morpho lending positions, Hyperliquid perps/spot/staked HYPE, veAERO locks on Aerodrome, and any Safe signatures awaiting you, for the wallets you watch — keyless, public data. Also checks Aave's public rate against a Morpho vault you hold, to tell you when yours is falling behind.",
                 hosts: ["blue-api.morpho.org", "app.morpho.org", "app.aave.com", "app.spark.fi",
                         "api.safe.global", "yields.llama.fi", "api.hyperliquid.xyz"]),
        Endpoint(service: "Tokens",
                 reach: .whenConnected(bridge: "Tokens"),
                 purpose: "Fetches the public price history of a token you watch to draw its chart on \(DS.device). Carries only the token — nothing about you.",
                 hosts: ["api.dexscreener.com", "api.geckoterminal.com"]),
        Endpoint(service: "GeckoTerminal",
                 reach: .whenConnected(bridge: "GeckoTerminal"),
                 purpose: "Fetches the tokens trending on the chains you follow — GeckoTerminal's own public ranking.",
                 hosts: ["api.geckoterminal.com"]),
        Endpoint(service: "0xBow Privacy Pools",
                 reach: .whenConnected(bridge: "0xBow Privacy Pools"),
                 purpose: "Reads your Privacy Pools deposits from the public chain and their review status from 0xBow's public API, for the wallets you watch.",
                 hosts: ["api.0xbow.io", "rpc.mevblocker.io"]),
        Endpoint(service: "Peer",
                 reach: .whenConnected(bridge: "Peer"),
                 purpose: "Reads your settled Peer trades off Base's public chain, for the wallets you watch.",
                 hosts: ["mainnet.base.org"]),
        // Reach is WALLET, not "Gnosis Pay" — the seat only appears once a
        // card spend has been seen, but the read that discovers one runs for
        // every watched wallet. Declaring it under its own seat would say
        // this host is only reached after connecting, which is false.
        Endpoint(service: "Gnosis Pay",
                 reach: .whenConnected(bridge: "Wallet"),
                 purpose: "Reads your Gnosis Pay card spending off Gnosis Chain's public chain, for the wallets you watch — the amount and the moment, which is all the chain carries.",
                 hosts: ["rpc.gnosischain.com", "rpc.gnosis.gateway.fm"]),
        Endpoint(service: "Exchange rates",
                 reach: .whenConnected(bridge: "Tokens"),
                 purpose: "Fetches public reference prices to show token and wallet values in your currency. Carries only the pair being priced.",
                 hosts: ["api.coinbase.com", "api.kraken.com"]),
        // Binance/Gemini's own hosts, separate from the pricing entry above —
        // neither prices anything (Kraken's public book still does that for
        // every venue); these are reached only for the read-only key check
        // and the balance read, and only once that venue is connected.
        Endpoint(service: "Binance",
                 reach: .whenConnected(bridge: "binance"),
                 purpose: "Reads your Binance balance for the combined total. View-only key, checked before it's stored.",
                 hosts: ["api.binance.com", "api.binance.us"]),
        Endpoint(service: "Gemini Exchange",
                 reach: .whenConnected(bridge: "geminiExchange"),
                 purpose: "Reads your Gemini balance for the combined total. Auditor-role key, checked before it's stored.",
                 hosts: ["api.gemini.com"]),
        Endpoint(service: "ETH Validators",
                 reach: .whenConnected(bridge: "ethvalidators"),
                 purpose: "Reads the balance and status of the validator indices you watch, off a public beacon-chain API. No account, no key.",
                 hosts: ["ethereum-beacon-api.publicnode.com"]),
        // Reach is WALLET, not a Bitcoin-specific seat — Bitcoin has no
        // connect switch of its own, it rides watched wallet addresses the
        // same way Gnosis Pay's entry above does.
        Endpoint(service: "Bitcoin",
                 reach: .whenConnected(bridge: "Wallet"),
                 purpose: "Reads balance, sends/receives, and confirmation status for the Bitcoin addresses you watch, off two public Esplora APIs. No account, no key.",
                 hosts: ["mempool.space", "blockstream.info"]),
        // Host is user-configurable (self-hosted PostHog exists) — the
        // default cloud host is what's disclosed; a self-hosted host is
        // one the person named themselves in setup, not an undisclosed one.
        Endpoint(service: "PostHog",
                 reach: .whenConnected(bridge: "posthog"),
                 purpose: "Reads the metrics, annotations, and event counts you watch on your own PostHog project. Read-only scoped key.",
                 hosts: ["us.posthog.com"]),
        Endpoint(service: "Slack",
                 reach: .whenConnected(bridge: "slack"),
                 purpose: "Looks up mentions of you across Slack. Search-only user token — can't post, read files, or browse channels.",
                 hosts: ["slack.com"]),

        // MARK: Markets

        Endpoint(service: "Kalshi",
                 reach: .whenConnected(bridge: "Kalshi"),
                 purpose: "Fetches the live odds of the markets you watch on Kalshi. Public data, read-only.",
                 hosts: ["api.elections.kalshi.com"]),
        Endpoint(service: "Polymarket",
                 reach: .whenConnected(bridge: "Polymarket"),
                 purpose: "Fetches the live odds and price history of the markets you watch on Polymarket. Public data, read-only.",
                 hosts: ["gamma-api.polymarket.com", "clob.polymarket.com"]),
        Endpoint(service: "Stocktwits",
                 reach: .whenConnected(bridge: "Stocktwits"),
                 purpose: "Fetches the posts and price of the tickers you watch. Public data — a watched ticker never sees your portfolio.",
                 hosts: ["api.stocktwits.com"]),
        Endpoint(service: "OpenSea",
                 reach: .whenConnected(bridge: "OpenSea"),
                 purpose: "Fetches the newest NFT collections on the chains you watch. Public data, read-only.",
                 hosts: ["api.opensea.io"]),

        // MARK: Social — public accounts and feeds you follow

        Endpoint(service: "Bluesky",
                 reach: .whenConnected(bridge: "Bluesky"),
                 purpose: "Reads the public posts, replies, and profiles of the accounts and feeds you follow, plus their images. No sign-in — public AT Protocol data.",
                 hosts: ["public.api.bsky.app", "api.bsky.app", "bsky.app", "cdn.bsky.app"]),
        Endpoint(service: "Farcaster",
                 reach: .whenConnected(bridge: "Farcaster"),
                 purpose: "Reads the public casts, likes, mentions, channels, and profiles of the accounts you follow, plus their images. No sign-in — public data.",
                 hosts: ["api.farcaster.xyz", "client.farcaster.xyz", "snap.farcaster.xyz",
                         "api.warpcast.com", "media.firefly.land", "imagedelivery.net"]),
        Endpoint(service: "Reddit",
                 reach: .whenConnected(bridge: "Reddit"),
                 purpose: "Reads your saved posts. Connects through Reddit's own sign-in.",
                 hosts: ["oauth.reddit.com", "www.reddit.com"]),
        Endpoint(service: "Pinterest",
                 reach: .whenConnected(bridge: "Pinterest"),
                 purpose: "Reads a public Pinterest profile's pins.",
                 hosts: ["www.pinterest.com"]),

        // MARK: Media

        Endpoint(service: "YouTube",
                 reach: .whenConnected(bridge: "YouTube"),
                 purpose: "Reads a public channel's newest videos.",
                 hosts: ["www.youtube.com"]),
        Endpoint(service: "Spotify",
                 reach: .whenConnected(bridge: "Spotify"),
                 purpose: "Reads what you saved and listened to. Connects through Spotify's own sign-in.",
                 hosts: ["api.spotify.com", "accounts.spotify.com"]),
        Endpoint(service: "Twitch",
                 reach: .whenConnected(bridge: "Twitch"),
                 purpose: "Reads which of the channels you follow are live. Connects through Twitch's own sign-in.",
                 hosts: ["api.twitch.tv", "id.twitch.tv"]),
        Endpoint(service: "Steam",
                 reach: .whenConnected(bridge: "Steam"),
                 purpose: "Reads your public Steam profile — games and achievements — with a Steam API key.",
                 hosts: ["api.steampowered.com", "steamcommunity.com", "store.steampowered.com",
                         "cdn.cloudflare.steamstatic.com"]),
        Endpoint(service: "Podcasts",
                 reach: .whenConnected(bridge: "Podcasts"),
                 purpose: "Finds a show in Apple's public podcast directory and reads its feed for new episodes.",
                 hosts: ["itunes.apple.com"]),

        // MARK: Work

        Endpoint(service: "GitHub",
                 reach: .whenConnected(bridge: "GitHub"),
                 purpose: "Reads your notifications and activity with a token you provide. Connects through GitHub's own device sign-in.",
                 hosts: ["api.github.com", "github.com"]),
        Endpoint(service: "Linear",
                 reach: .whenConnected(bridge: "Linear"),
                 purpose: "Reads issues assigned to you with an API key you provide.",
                 hosts: ["api.linear.app"]),
        Endpoint(service: "Notion",
                 reach: .whenConnected(bridge: "Notion"),
                 purpose: "Reads pages you share with the integration, using a token you provide.",
                 hosts: ["api.notion.com"]),
        Endpoint(service: "Todoist",
                 reach: .whenConnected(bridge: "Todoist"),
                 purpose: "Reads your tasks with an API token you provide.",
                 hosts: ["api.todoist.com"]),
        Endpoint(service: "Readwise",
                 reach: .whenConnected(bridge: "Readwise"),
                 purpose: "Reads your highlights with an API token you provide.",
                 hosts: ["readwise.io"]),
        Endpoint(service: "Raindrop",
                 reach: .whenConnected(bridge: "Raindrop"),
                 purpose: "Reads your saved bookmarks with a token you provide.",
                 hosts: ["api.raindrop.io"]),
        Endpoint(service: "Cal.com",
                 reach: .whenConnected(bridge: "Cal.com"),
                 purpose: "Reads your bookings with an API key you provide.",
                 hosts: ["api.cal.com"]),
        Endpoint(service: "Calendly",
                 reach: .whenConnected(bridge: "Calendly"),
                 purpose: "Reads your scheduled events with a token you provide.",
                 hosts: ["api.calendly.com"]),

        // MARK: Storage

        Endpoint(service: "Dropbox",
                 reach: .whenConnected(bridge: "Dropbox"),
                 purpose: "Reads the folder you name, with a read-only key. Connects through Dropbox's own sign-in.",
                 hosts: ["api.dropboxapi.com", "content.dropboxapi.com", "www.dropbox.com"]),

        // MARK: Reading & feeds

        Endpoint(service: "RSS",
                 reach: .whenConnected(bridge: "RSS"),
                 purpose: "Fetches the feeds you follow for new posts. Each request goes to that feed's own site.",
                 hosts: ["the feeds you follow", "feeds.feedburner.com"]),
        Endpoint(service: "Substack",
                 reach: .whenConnected(bridge: "Substack"),
                 purpose: "Fetches a publication's public feed for new posts.",
                 hosts: ["the publication you follow"]),

        // MARK: Shopping

        Endpoint(service: "Shopify",
                 reach: .whenConnected(bridge: "Shopify"),
                 purpose: "Reads a store's public product catalog for new drops. Goes to the store's own site.",
                 hosts: ["the store you follow"]),
        Endpoint(service: "Deals",
                 reach: .whenConnected(bridge: "Deals"),
                 purpose: "Fetches the public deal feeds you follow.",
                 hosts: ["www.dealnews.com", "the deal sites you follow"]),
        Endpoint(service: "Open Food Facts",
                 reach: .whenConnected(bridge: "Open Food Facts"),
                 purpose: "Looks up a grocery barcode in the open food database. Carries only the barcode.",
                 hosts: ["world.openfoodfacts.org"]),
        Endpoint(service: "Bitrefill",
                 reach: .whenConnected(bridge: "Bitrefill"),
                 purpose: "Reads your Bitrefill orders and balance with an API key you provide.",
                 hosts: ["api-bitrefill.com", "www.bitrefill.com"]),
        Endpoint(service: "Privacy.com",
                 reach: .whenConnected(bridge: "Privacy"),
                 purpose: "Reads your approved card purchases with an API key you provide. Read-only by conduct — it only ever reads.",
                 hosts: ["api.privacy.com"]),
        Endpoint(service: "1Claw",
                 reach: .whenConnected(bridge: "1Claw"),
                 purpose: "Reads your vault grants with a read key you provide.",
                 hosts: ["1claw.xyz", "api.1claw.xyz"]),

        // MARK: On tap — your own agent key, only when you press it

        Endpoint(service: "Your agent key",
                 reach: .onTapWithKey,
                 purpose: "Only when you tap \"Try with your key\" on an answer, your question and the few matched things go straight from \(DS.device) to the provider you chose — Anthropic, OpenAI, Google, Venice, Bankr, OpenRouter, or xAI (Grok). Never otherwise, and never through us.",
                 hosts: ["api.anthropic.com", "api.openai.com", "generativelanguage.googleapis.com",
                         "api.venice.ai", "api.bankr.bot", "openrouter.ai", "api.x.ai"]),
    ]

    /// The hosts this registry accounts for — the audit script checks every
    /// host literal in the app against this set (real hosts only; the
    /// "the site you saved"-style prose entries are descriptive, not hosts).
    static var accountedHosts: Set<String> {
        Set(endpoints.flatMap(\.hosts).filter { $0.contains(".") })
    }
}
