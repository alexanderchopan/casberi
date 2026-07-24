import Foundation

/// The catalog — the 15 bridges research proved viable (PRD S9 grades), one
/// list read by the Apps tile (count), the Apps page (Available section),
/// and the catalog screen (grouped). Names are the join key everywhere.
enum BridgeCatalog {

    struct Offer {
        let name: String
        let tagline: String
        let group: String
        /// True = the bridge is wired today (local frameworks). The rest say
        /// "Arrives with bridges" instead of pretending.
        let connectable: Bool
        /// One plain sentence for the App-Store-style detail page — what
        /// connecting is worth, in Bob's words.
        let summary: String
        /// Extra capabilities beyond the hook, as short scannable lines
        /// (prd §192, 2026-07-23) — the fix for a real tension the three-beat
        /// summary rule exposed: Wallet's differentiated features (approval
        /// alerts, DeFi positions, the Safe queue) don't fit a one-sentence
        /// hook, but cramming them into the summary as a second run-on clause
        /// bloated it to 107 words and buried the actual promise. Rather than
        /// deleting real, true, differentiating information to match a word
        /// count, it moves to its own scannable list — same content, same
        /// checkmark grammar `BridgeConnectedState.capabilities` already
        /// established for the CONNECTED state, so a person reads the same
        /// visual language before and after they connect. Empty for the
        /// other 54 offers, whose one-sentence hook already says it all.
        var features: [String] = []
        /// True when connecting needs the person's input first (feed URLs,
        /// a pasted token) — Connect opens the bridge's setup screen instead
        /// of firing a permission ask. Setup bridges skip onboarding's
        /// mini store: that screen is one-tap connects only.
        var needsSetup: Bool = false

        /// The day this offer joined the catalog (nil = it has always been
        /// here / predates the stamp). This is what makes "Just added" HONEST
        /// where the old "New" badge was pure assertion (ruling 2026-07-16):
        /// a computable date, so a genuinely-recent offer can earn a Discover
        /// seat and the badge retires itself when the date ages out. Only
        /// stamp an offer the day it actually lands.
        var added: Date? = nil

        /// True when this offer joined within the last week — the window the
        /// Discover deck reads for a "Just added" seat. Time-relative on
        /// purpose: a stamped offer stops being new on its own, no cleanup.
        func isNew(asOf now: Date = Date()) -> Bool {
            guard let added else { return false }
            return now.timeIntervalSince(added) < 7 * 24 * 60 * 60
        }

        /// A one-word honest hook for the row badge and the story eyebrow —
        /// derived from HOW the bridge connects, never marketing. "One tap"
        /// (a system-permission bridge — a single grant, no fields), "No
        /// account" (keyless — a handle or address, no sign-in, public
        /// feeds), or "Import" (a one-time export you point at). Everything
        /// else stays unbadged: a row earns a badge only when the fact
        /// differentiates it. Never applied to a connected row (its subline
        /// already carries live status).
        var qualifier: String? {
            if connectable && !needsSetup { return "One tap" }
            let keyless: Set<String> = ["Wallet", "Tokens", "Peer", "0xBow Privacy Pools", "Reddit", "YouTube",
                "RSS", "Substack", "Podcasts", "Pinterest", "Farcaster",
                "Bluesky", "OpenSea", "Kalshi", "Shopify", "GeckoTerminal", "Deals",
                "Open Food Facts", "Stocktwits"]
            if keyless.contains(name) { return "No account" }
            let imports: Set<String> = ["ChatGPT", "Claude", "Gemini",
                "Day One", "Apple Journal", "Kindle"]
            if imports.contains(name) { return "Import" }
            return nil
        }
    }

    /// A catalog date at midnight UTC — the join key for `Offer.added`. Only
    /// used for the "Just added" window, so day granularity is enough.
    static func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day
        c.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: c) ?? Date(timeIntervalSince1970: 0)
    }

    /// Grouped by what they're worth, verb taglines (S25).
    static let offers: [Offer] = [
        Offer(name: "Photos",      tagline: "Screenshots, straight to your feed",            group: "Photos",    connectable: true,
              summary: "The screenshots you take flow into your feed, searchable by what's in them — no album to dig through."),
        Offer(name: "Calendar",    tagline: "Events join your things",               group: "Schedule",  connectable: true,
              summary: "Your events land alongside everything else, so your day shows up in your week — and Casberi can add one when you ask."),
        Offer(name: "Reminders",   tagline: "Lists stay in reach",                   group: "Schedule",  connectable: true,
              summary: "Your reminders join your things and stay findable, and Casberi can add one to your list when you ask."),
        Offer(name: "Wallet",      tagline: "Track any wallet's activity",          group: "Wallet",    connectable: true,
              summary: "Paste a wallet address — 0x…, an ENS name, or a .sol name — and its onchain activity lands in your feed like anything else, across Ethereum, Base, Arbitrum, Optimism, Polygon and Solana. Read-only, public data, no server — watching an address can never trade or move funds.",
              features: [
                "Flags new token approvals, including through Permit2.",
                "Warns if the wallet starts delegating its control.",
                "Catches transfers that look like address-poisoning scams.",
                "Tracks what you've paid in gas.",
                "Shows your Aave and Morpho positions.",
                "Surfaces any Safe signatures that need attention.",
              ],
              needsSetup: true),
        // Wallet group by ruling (user, 2026-07-21, prd §162). Privacy Pools
        // rides the watched wallets the Peer way: no account exists to
        // connect — deposits come from the person's own wallet, so the seat
        // is a switch over the watched list.
        Offer(name: "0xBow Privacy Pools", tagline: "Know when your deposit clears",       group: "Wallet",    connectable: true,
              summary: "Privacy Pools (by 0xBow) lets you move crypto with privacy and a compliance screen: you deposit, their screening reviews it, and once cleared you can withdraw to a fresh address privately. Connect and your deposits land in your feed — and Casberi tells you the moment a deposit clears review and is ready to withdraw privately, or if it's declined. Read from Ethereum's public chain and 0xBow's public API for the wallets you already watch. No account, no key, read-only: nothing here deposits, withdraws, or moves funds.",
              needsSetup: true, added: day(2026, 7, 21)),
        // Wallet group by ruling (user, 2026-07-21): the balances MERGE into
        // the combined portfolio, so an exchange belongs beside the wallets
        // whose total it joins — not in Markets, which is where things you
        // watch rather than own live.
        Offer(name: "Coinbase",    tagline: "Your exchange balance, in your total",  group: "Wallet",    connectable: true,
              summary: "Most people's crypto isn't all onchain. Connect Coinbase and your balances there join your watched wallets in one combined total and one map, so the number finally covers everything you hold. Connecting takes a view-only API key — and Casberi asks Coinbase what that key is allowed to do before storing it, handing it back if it can trade or move money. Read-only: no order, withdrawal or transfer is reachable from the app at all.",
              needsSetup: true, added: day(2026, 7, 21)),
        Offer(name: "Kraken",      tagline: "Your exchange balance, in your total",  group: "Wallet",    connectable: true,
              summary: "Most people's crypto isn't all onchain. Connect Kraken and your balances there join your watched wallets in one combined total and one map, so the number finally covers everything you hold. Connecting takes an API key with query permissions only — and Casberi asks Kraken what that key is allowed to do before storing it, handing it back if it can trade, withdraw, or manage withdrawal addresses. Read-only: no order, withdrawal or transfer is reachable from the app at all.",
              needsSetup: true, added: day(2026, 7, 21)),
        Offer(name: "Gmail",       tagline: "Your inbox, findable",                  group: "Mail",      connectable: true,
              summary: "Your recent mail becomes findable things. Connects over IMAP with a Google app password — your real password is never shared, and it's read-only. Needs 2-Step Verification on your Google account.",
              needsSetup: true),
        Offer(name: "iCloud Mail", tagline: "Your @icloud.com inbox, findable",      group: "Mail",      connectable: true,
              summary: "Your recent @icloud.com mail becomes findable things. Connects over IMAP with an app-specific password from appleid.apple.com — your real password is never shared, and it's read-only.",
              needsSetup: true),
        Offer(name: "ChatGPT",     tagline: "Import your chats, keep them findable", group: "Agent",     connectable: true,
              summary: "A one-time import of your chat history, kept searchable alongside your things. (No live read — OpenAI doesn't offer one; this is your export, backfilled.)",
              needsSetup: true),
        Offer(name: "Claude",      tagline: "Import your chats, keep them findable", group: "Agent",     connectable: true,
              summary: "A one-time import of your Claude chat history, kept searchable alongside your things. (No live read — Anthropic doesn't offer one; this is your export, backfilled.)",
              needsSetup: true),
        Offer(name: "Gemini",      tagline: "Import your chats, keep them findable", group: "Agent",     connectable: true,
              summary: "A one-time import of your Gemini history via Google Takeout, kept searchable alongside your things. (No live read — Google doesn't offer one; this is your export, backfilled.)",
              needsSetup: true),
        Offer(name: "Tokens",      tagline: "Track any token",                       group: "Markets",   connectable: true,
              summary: "Watch any token — paste its address or a link and its live price chart lands in your feed, drawn on your iPhone. Public price data only; nothing about you leaves the device.",
              needsSetup: true),
        Offer(name: "Kalshi",      tagline: "Watch real-event odds",                 group: "Markets",   connectable: true,
              summary: "Watch any market on Kalshi, the CFTC-regulated event exchange — search a team or event and its live odds land in your feed. Public price data only, read-only: nothing here places a trade.",
              needsSetup: true),
        Offer(name: "Stocktwits",  tagline: "Watch any stock",                      group: "Markets",   connectable: true,
              summary: "Watch any stock — search a ticker and the takes traders post about it on Stocktwits land in your feed, each wearing its author's own bullish or bearish call. The stock's live price chart draws on this iPhone from public market data. No account, no key, read-only: nothing here trades, and a watched ticker can never see your portfolio.",
              needsSetup: true),
        // Markets by ruling (user, 2026-07-17 — corrected from Onchain the
        // same day). Peer rides the Wallet bridge the way Strava rides Apple
        // Health (prd §113): no account exists to connect — trades settle
        // into the person's own wallet, so the seat is a switch over the
        // watched list.
        Offer(name: "Peer",        tagline: "Your Peer trades, as they settle",      group: "Markets",   connectable: true,
              summary: "Peer trades settle onchain into your own wallet — connect and each fill lands in your feed as it settles: which token, how much, and the payment app that paid for it (\"Bought 25 USDC with Venmo on Peer\"). Read from the public chain for the wallets you already watch; Peer's zero-knowledge design keeps your Venmo or PayPal side private, so the chain never shows it and neither does Casberi. No account, no key, read-only: nothing here ever starts a trade.",
              needsSetup: true, added: day(2026, 7, 17)),
        Offer(name: "GeckoTerminal", tagline: "Trending tokens, per chain",          group: "Markets",   connectable: true,
              summary: "Pick the chains you care about and the tokens trending on each — GeckoTerminal's own ranking, by 24-hour volume and price move — land in your feed as links. No account, no key: fetched straight from GeckoTerminal's public API by this iPhone. Read-only public price data; nothing here buys, sells, or trades. Each trending row opens to its live on-device chart.",
              needsSetup: true),
        Offer(name: "OpenSea",     tagline: "New NFT drops in your feed",            group: "NFTs",      connectable: true,
              summary: "Watch the chains you care about and their newest NFT collections land in your feed as links — the ones with real artwork, not the empty test contracts. Fetched straight from OpenSea's public API, read-only: nothing here buys, sells, or bids.",
              needsSetup: true),
        // Shopping, not Markets (2026-07-17): Bitrefill is your own commerce
        // account — orders and receipts — not a market you watch.
        Offer(name: "Bitrefill",   tagline: "Your gift cards, in reach",             group: "Shopping",  connectable: true,
              summary: "What you buy on Bitrefill lands in your feed — gift cards wearing their own artwork, phone top-ups, eSIMs, balance refills — with your balance at the top of the Bitrefill feed. Connects with an API key from Bitrefill's developer settings — it stays in this iPhone's Keychain. Read-only by conduct: nothing here ever buys, pays, or spends your balance.",
              needsSetup: true, added: day(2026, 7, 17)),
        // Shopping, beside Bitrefill: Privacy.com is your own card-spending
        // record — receipts across every merchant — not a market you watch.
        // Honesty note (2026-07-22): Privacy's key is NOT scoped read-only, so
        // the summary says plainly that the read-only promise is kept by
        // conduct, not by the credential (unlike every other keyed bridge).
        Offer(name: "Privacy",     tagline: "Your card purchases, in reach",         group: "Shopping",  connectable: true,
              summary: "What you buy with your Privacy.com virtual cards lands in your feed — each purchase with its merchant and amount, so your spending is findable next to everything else. Connects with an API key from your Privacy account (a paid Privacy plan is required); the key stays in this iPhone's Keychain. Read-only by conduct: Casberi only ever reads your transactions. One honest caveat — Privacy's key can't be scoped read-only, so the same key could manage cards on your account; Casberi never creates, closes, or funds a card.",
              needsSetup: true, added: day(2026, 7, 22)),
        Offer(name: "Shopify",     tagline: "Follow any store's new drops",          group: "Shopping",  connectable: true,
              summary: "Follow any Shopify store — paste its web address and its newest products, restocks, and sale prices land in your feed as things, opening back on the store's own page. Fetched straight from the store's public catalog by this iPhone: no account, no sign-in, read-only — nothing here checks out or pays. Some big stores block automated reads; those it can't follow, it says so.",
              needsSetup: true),
        Offer(name: "Deals",       tagline: "The best deals, as they drop",          group: "Shopping",  connectable: true,
              summary: "Follow the deal aggregators — Slickdeals, DealNews — and their newest deals land in your feed as products, each already priced in the headline and opening back on the deal's own page. Fetched straight from each source's public feed by this iPhone: no account, read-only — nothing here buys anything.",
              needsSetup: true),
        Offer(name: "Open Food Facts", tagline: "Scan a grocery barcode",           group: "Shopping",  connectable: true,
              summary: "Scan or enter a grocery item's barcode and the product lands in your feed — its name, picture, and Nutri-Score, from the open food database. Keyless and free: Open Food Facts is a public, collaborative catalog, so no account, and nothing about you leaves this iPhone but the barcode. Read-only.",
              needsSetup: true),
        Offer(name: "Venice",      tagline: "Private answers with your key",         group: "Agent",     connectable: true,
              summary: "Venice keeps chats on your own device by design, so there's nothing to read in — instead, your Venice key powers \"Try with your key\": any answer re-runs on Venice's private API, straight from this iPhone, only when you tap.",
              needsSetup: true),
        Offer(name: "Bankr",       tagline: "Answers that know your wallet",        group: "Agent",     connectable: true,
              summary: "Bankr is an agent with a wallet, so its answers can weigh what you hold and what the market is doing — not just what you saved. Your Bankr key powers \"Try with your key\": any answer re-runs on Bankr, straight from this iPhone, only when you tap. Make it a read-only key: every question says answer only, and nothing here trades, sends, or swaps.",
              needsSetup: true),
        // 1Claw is the agents' vault (2026-07-17, prd 111): grants, not
        // secrets — the feed answers "what can this key reach", never what
        // a secret's value is.
        Offer(name: "1Claw",       tagline: "What your agent's key can reach",       group: "Agent",     connectable: true,
              summary: "1Claw is a vault that holds your AI agents' secrets behind human-granted permissions. Paste an agent's API key and its actual reach lands in your feed — every vault it can see, and each grant's secret paths and permissions, straight from 1Claw's own records. Names and permissions only, read straight from this iPhone: nothing here ever reads a secret's value, signs, or spends.",
              needsSetup: true, added: day(2026, 7, 17)),
        Offer(name: "GitHub",      tagline: "Stars, releases, issues — your GitHub", group: "Work",      connectable: true,
              summary: "Pick the feeds you want — starred repos, new releases, gists, your contributions, watched repos, and the issues and pull requests that involve you. Connects with a read-only token you make in GitHub settings — it stays in this iPhone's Keychain.",
              needsSetup: true),
        Offer(name: "Linear",      tagline: "Your issues stay in reach",             group: "Work",      connectable: true,
              summary: "The issues assigned to you join your things and surface when they matter. Connects with a personal API key from Linear settings — it stays in this iPhone's Keychain.",
              needsSetup: true),
        Offer(name: "Notion",      tagline: "Pages join your things",                group: "Work",      connectable: true,
              summary: "The pages you connect become findable things, so what you wrote isn't stranded in one more app. Pages only. Connects with an integration token from notion.so — it stays in this iPhone's Keychain.",
              needsSetup: true),
        Offer(name: "Reddit",      tagline: "Follow subreddits and people",          group: "Saves",     connectable: true,
              summary: "Follow any subreddit or person on Reddit — their new posts land in your feed as links, through Reddit's own public feed. No account, no sign-in. Read-only.",
              needsSetup: true),
        Offer(name: "YouTube",     tagline: "Follow any channel",                    group: "Watching",  connectable: true,
              summary: "Follow any YouTube channel — its new uploads land in your feed as links, through YouTube's own public feed. Paste the channel's @handle or URL. No account. Read-only.",
              needsSetup: true),
        Offer(name: "Apple Music", tagline: "What you play stays in reach",          group: "Listening", connectable: true,
              summary: "What you've recently played lands in your feed, opening back in Apple Music. Uses Apple's own MusicKit with your permission — read-only, nothing added to your library. Everything stays on this iPhone."),
        Offer(name: "Spotify",     tagline: "Liked songs join your things",          group: "Listening", connectable: true,
              summary: "Your liked songs become things you can find and revisit alongside everything else. Connects with Spotify's own sign-in — PKCE, entirely on this iPhone, no server holds a secret.",
              needsSetup: true),
        Offer(name: "Apple Health", tagline: "Workouts land in your feed",           group: "Fitness",   connectable: true,
              summary: "Your workouts join your things — a run shows up next to the plan that inspired it. Everything stays on this iPhone: HealthKit never touches a server."),
        Offer(name: "Strava",      tagline: "Every activity, one record",            group: "Fitness",   connectable: true,
              summary: "Rides and runs land in your feed with distance and time — read from Apple Health, where Strava saves them. Turn on Strava's Health sync and everything stays on this iPhone; no Strava account is asked for."),
        Offer(name: "Cal.com",     tagline: "Bookings land in your feed",            group: "Schedule",  connectable: true,
              summary: "The meetings people book with you join your things as events, next to your calendar. Connects with an API key from Cal.com settings — it stays in this iPhone's Keychain.",
              needsSetup: true),
        Offer(name: "Calendly",    tagline: "Meetings join your things",             group: "Schedule",  connectable: true,
              summary: "Your scheduled meetings land as events beside everything else. Connects with a personal access token from Calendly's integrations page — it stays in this iPhone's Keychain.",
              needsSetup: true),
        Offer(name: "Todoist",     tagline: "Tasks beside your lists",               group: "Schedule",  connectable: true,
              summary: "Your open tasks join your things alongside Reminders. Connects with the API token from Todoist settings — it stays in this iPhone's Keychain.",
              needsSetup: true),
        Offer(name: "Pinterest",   tagline: "Your pins, in your feed",               group: "Images",    connectable: true,
              summary: "Your recent public pins land in your feed as links — what you saved on Pinterest joins everything else. Connects with just your username through Pinterest's own public feed: no password, nothing stored but the name. Public boards only.",
              needsSetup: true),
        Offer(name: "Raindrop",    tagline: "Bookmarks become findable",             group: "Saves",     connectable: true,
              summary: "Your Raindrop bookmarks join your things, searchable next to everything else you saved. Connects with a token from Raindrop settings — it stays in this iPhone's Keychain.",
              needsSetup: true),
        Offer(name: "Readwise",    tagline: "Highlights stay with you",              group: "Reading",   connectable: true,
              summary: "Your highlights land in your feed — what you read joins what you do. Connects with your Readwise access token — it stays in this iPhone's Keychain.",
              needsSetup: true),
        Offer(name: "Apple Journal", tagline: "Your entries, findable",              group: "Notes",     connectable: true,
              summary: "A one-time import of Journal's own export — entries become findable notes, dated as you wrote them. In Journal: your profile picture → Export Journal, unzip in Files, pick the folder here. Apple offers no live read.",
              needsSetup: true),
        Offer(name: "Day One",     tagline: "Import your journal",                   group: "Notes",     connectable: true,
              summary: "A one-time import of your Day One export — every entry becomes a findable note, dated as you wrote it, tags kept. Export JSON in Day One, unzip in Files, pick the file here. Re-imports add only what's new.",
              needsSetup: true),
        Offer(name: "Apple Notes", tagline: "Share notes in",                        group: "Notes",     connectable: true,
              summary: "Share any note straight into Casberi — open it in Notes, tap share, choose Casberi. Apple offers no export or live read for Notes, so they arrive one at a time, as you share them.",
              needsSetup: true),
        Offer(name: "RSS",         tagline: "Any site with a feed",                  group: "Reading",   connectable: true,
              summary: "Follow any site that publishes a feed — new posts land in your feed as links, fetched by this iPhone directly. No account, no algorithm in between.",
              needsSetup: true),
        // Social, with Bluesky (user ruling 2026-07-17, reversing the
        // 2026-07-14 "onchain network" shelving): Farcaster is a social account
        // first — it browses beside Bluesky, and its detail eyebrow says so.
        Offer(name: "Farcaster",   tagline: "Track any Farcaster account",           group: "Network",   connectable: true,
              summary: "An open social protocol — casts are public, so this connects with just a username: your own or anyone's, plus /channels by name. An account's likes and mentions can land too. No password, nothing stored but the name.",
              needsSetup: true),
        Offer(name: "Bluesky",     tagline: "Track any Bluesky account",             group: "Network",   connectable: true,
              summary: "Built on an open protocol — posts are public, so this connects with just a handle: your own or anyone's, and mentions of them can land too. No password, nothing stored but the name. Likes arrive with sign-in, later.",
              needsSetup: true),
        Offer(name: "Steam",       tagline: "What you play, in your feed",           group: "Games",     connectable: true,
              summary: "Recently played games land in your feed, linking to their store pages. Connects with a free Steam Web API key and your public profile name — the key stays in this iPhone's Keychain. Read-only.",
              needsSetup: true),
        Offer(name: "Obsidian",    tagline: "Your vault, beside your things",        group: "Notes",     connectable: true,
              summary: "Point at your vault folder and your notes land as things — findable next to everything else. Fully local: the vault is read in place, never modified, and nothing leaves this iPhone.",
              needsSetup: true),
        Offer(name: "Twitch",      tagline: "Live follows land in your feed",        group: "Watching",  connectable: true,
              summary: "When a channel you follow goes live, the stream lands in your feed as a link — catch it while it's on. Sign-in happens on Twitch's own page with a short code; read-only, no password in the app.",
              needsSetup: true),
        Offer(name: "Substack",    tagline: "Follow any publication",                group: "Reading",   connectable: true,
              summary: "Follow any Substack — new posts land in your feed as links, fetched straight from the publication's own feed. Paste its URL or name. No account. Read-only.",
              needsSetup: true),
        Offer(name: "Kindle",      tagline: "Import your highlights",                group: "Reading",   connectable: true,
              summary: "A one-time import of your Kindle's highlights — the My Clippings.txt the device writes becomes findable notes, grouped by book. No account; Amazon offers no live read.",
              needsSetup: true),
        Offer(name: "Podcasts",    tagline: "Follow any show",                       group: "Listening", connectable: true,
              summary: "Follow any podcast — new episodes land in your feed as links. Search for a show and pick it; episodes arrive through the show's own public feed. No account. Read-only.",
              needsSetup: true),
        Offer(name: "Contacts",    tagline: "The people you know, findable",         group: "People",    connectable: true,
              summary: "Your contacts become findable people — a name you're looking for turns up with everything it connects to. Search-only: they never crowd your feed. Everything stays on this iPhone — Contacts never touches a server. Read-only."),
        Offer(name: "HomeKit",     tagline: "Your home's accessories, at a glance",  group: "Home",      connectable: true,
              summary: "Your HomeKit accessories — locks, doors, sensors — land as things you can find, kept current while the app is open. Search-only: they never crowd your feed. Read-only — Casberi never controls anything."),
    ]

    /// Group order for the catalog screen (insertion order of first member).
    static var groups: [(String, [Offer])] {
        var order: [String] = []
        var buckets: [String: [Offer]] = [:]
        for offer in offers {
            if buckets[offer.group] == nil { order.append(offer.group) }
            buckets[offer.group, default: []].append(offer)
        }
        return order.map { ($0, buckets[$0] ?? []) }
    }

    // MARK: - Categories (merge map over Offer.group — Browse + chart filter
    // ONLY, never vertical section headers). Moved here from AppsScreen
    // (2026-07-20) so the agent's `category:<name>` kept-ask kind reads the
    // SAME mapping the catalog page shows — the whole point of this being
    // the ruled single source of truth.
    static let categories: [(name: String, exemplar: String, groups: Set<String>)] = [
        // The finance pair LEADS the catalog (user ruling 2026-07-17): the
        // "Onchain" category is dissolved — Markets is the front door, gathering
        // the watch-a-market bridges (Tokens, OpenSea, GeckoTerminal join
        // Kalshi, Stocktwits, Peer); Wallet stands on its own right behind it.
        ("Markets", "Kalshi",      ["Markets", "NFTs"]),
        ("Wallet",  "Wallet",      ["Wallet"]),
        // "People" (Contacts) joins Life explicitly (2026-07-20) — it always
        // landed here via the fallback below, this just says so honestly.
        ("Life",    "Photos",      ["Photos", "Schedule", "Fitness", "People"]),
        ("Home",    "HomeKit",     ["Home"]),
        ("Notes",   "Apple Notes", ["Notes"]),
        ("Social",  "Bluesky",     ["Network"]),
        ("Agents",  "Claude",      ["Agent"]),
        ("Mail",    "Gmail",       ["Mail"]),
        ("Work",    "GitHub",      ["Work"]),
        ("Reading", "Readwise",    ["Reading", "Saves"]),
        ("Media",   "Spotify",     ["Watching", "Listening", "Games", "Images"]),
        ("Shopping", "Shopify",    ["Shopping"]),
    ]

    static func category(of offer: Offer) -> String {
        categories.first { $0.groups.contains(offer.group) }?.name ?? "Life"
    }

    /// Offers not yet among the person's bridges — what the Apps page lists
    /// under Available and the tile counts as "to add". A–Z: the flat list is
    /// an inventory you scan by name (the grouped catalog keeps value order —
    /// its job is selling the worth; this list's job is lookup).
    static func available(besides bridgeNames: [String]) -> [Offer] {
        let taken = Set(bridgeNames)
        return offers.filter { !taken.contains($0.name) }
            .sorted { $0.name < $1.name }
    }
}
