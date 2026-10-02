import Foundation
import Observation

/// THE COMPANIES BEHIND THE CATALOGUE (user, 2026-09-29: "a starter pack kind
/// of list that is the stock price and mcap of the company or crypto token …
/// probably should be a native feature somehow not just a starter pack").
///
/// A pack is a catalogue CATEGORY (`BridgeCatalog.categories`), and its
/// members are the makers of that category's accounts — GitHub and npm are
/// Microsoft, Slack is Salesforce, Gnosis Pay is GNO. Derived from the
/// catalogue, never curated beside it: an account added to Work joins the Work
/// pack by its row here, and an account with no row is simply not in a pack.
///
/// **A company with no listing reads n/a** (user: "we don't need to force fit
/// something there"). No last-round valuation, no estimate — a private
/// company's worth is not a price anyone can read, so the row says so and
/// stops. `Wise` is listed in London, which neither feed reads; n/a there is
/// the same honest "not available here", not a claim it is private.
///
/// `CompanyPacks` is pure; the quote reader below it is the only network.
enum CompanyPacks {

    /// Where a company's price comes from.
    enum Listing: Hashable, Sendable {
        /// A US ticker, read on Nasdaq's public quote.
        case stock(String)
        /// A crypto asset: its symbol, and its CoinPaprika id — the one keyless
        /// source whose market cap is the COIN's (a DEX pair's "cap" for a
        /// native coin is its wrapped supply: WBNB, not BNB).
        case token(symbol: String, paprika: String)
        /// No listing either feed reads — drawn as n/a.
        case unlisted

        /// The quote cache's key; nil for n/a.
        var key: String? {
            switch self {
            case .stock(let t):             return "stock:\(t)"
            case .token(_, let id):         return "token:\(id)"
            case .unlisted:                 return nil
            }
        }

        var ticker: String? {
            switch self {
            case .stock(let t):             return t
            case .token(let s, _):          return s
            case .unlisted:                 return nil
            }
        }
    }

    /// One row in a pack: the company, how it is listed, and the accounts in
    /// this category it makes (the first one's mark leads the row).
    struct Company: Identifiable, Hashable, Sendable {
        let name: String
        let listing: Listing
        let seats: [String]
        var id: String { name }
    }

    /// Catalogue offer name → its maker. Offers with no maker worth pricing
    /// (RSS, Bookmarks, Deals, the devnets, the app's own Wallet and Tokens
    /// seats, a foundation like PyPI's) have no row and stand in no pack.
    /// Every ticker and id here was read live on 2026-09-29.
    static let makers: [String: (company: String, listing: Listing)] = {
        let apple: (String, Listing) = ("Apple", .stock("AAPL"))
        let amazon: (String, Listing) = ("Amazon", .stock("AMZN"))
        let alphabet: (String, Listing) = ("Alphabet", .stock("GOOGL"))
        let microsoft: (String, Listing) = ("Microsoft", .stock("MSFT"))
        let atlassian: (String, Listing) = ("Atlassian", .stock("TEAM"))
        let anthropic: (String, Listing) = ("Anthropic", .unlisted)
        let meta: (String, Listing) = ("Meta", .stock("META"))
        func own(_ name: String) -> (String, Listing) { (name, .unlisted) }
        func coin(_ name: String, _ symbol: String, _ id: String) -> (String, Listing) {
            (name, .token(symbol: symbol, paprika: id))
        }
        let rows: [String: (String, Listing)] = [
            // Wallet
            "0xBow Privacy Pools": own("0xBow"),
            "Acorns": own("Acorns"),
            "Apple Wallet": apple,
            "Binance": coin("BNB", "BNB", "bnb-binance-coin"),
            "CardPointers": own("CardPointers"),
            "Coinbase": ("Coinbase", .stock("COIN")),
            "Dodo Payments": own("Dodo Payments"),
            "ENS": coin("ENS", "ENS", "ens-ethereum-name-service"),
            "ETH Validators": coin("Ethereum", "ETH", "eth-ethereum"),
            "Gemini Exchange": ("Gemini", .stock("GEMI")),
            "Gnosis Pay": coin("Gnosis", "GNO", "gno-gnosis"),
            "Kraken": own("Kraken"),
            "L2BEAT": own("L2BEAT"),
            "MetaMask Card": own("Consensys"),
            "NerdWallet": ("NerdWallet", .stock("NRDS")),
            "Peer": own("Peer"),
            "Privacy": own("Privacy.com"),
            "Privy": own("Privy"),
            "Railgun": coin("Railgun", "RAIL", "rail-railgun"),
            "Rocket Money": ("Rocket Companies", .stock("RKT")),
            "Safe": coin("Safe", "SAFE", "safe-safe"),
            "Splits": own("Splits"),
            "Wise": own("Wise"),
            "ether.fi": coin("ether.fi", "ETHFI", "ethfi-etherfi"),
            // Work
            "AWS": amazon,
            "App Store Connect": apple,
            "Cloudflare": ("Cloudflare", .stock("NET")),
            "GitHub": microsoft,
            "GitLab": ("GitLab", .stock("GTLB")),
            "Hugging Face": own("Hugging Face"),
            "Jira": atlassian,
            "Linear": own("Linear"),
            "Notion": own("Notion"),
            "PagerDuty": ("PagerDuty", .stock("PD")),
            "Polar": own("Polar"),
            "PostHog": own("PostHog"),
            "Radicle": coin("Radicle", "RAD", "rad-radicle"),
            "Sentry": own("Sentry"),
            "Slack": ("Salesforce", .stock("CRM")),
            "Stripe": own("Stripe"),
            "Trello": atlassian,
            "Vercel": own("Vercel"),
            "npm": microsoft,
            // Life
            "Apple Health": apple,
            "Cal.com": own("Cal.com"),
            "Calendar": apple,
            "Calendly": own("Calendly"),
            "Contacts": apple,
            "Dropbox": ("Dropbox", .stock("DBX")),
            "Duolingo": ("Duolingo", .stock("DUOL")),
            "Files": apple,
            "Garmin": ("Garmin", .stock("GRMN")),
            "Gmail": alphabet,
            "Photos": apple,
            "Reminders": apple,
            "Strava": own("Strava"),
            "Todoist": own("Doist"),
            "iCloud Mail": apple,
            // Agents
            "Apple Intelligence": apple,
            "Bankr": coin("Bankr", "BNKR", "bnkr-bankrcoin"),
            "ChatGPT": own("OpenAI"),
            "Claude": anthropic,
            "Claude Code": anthropic,
            "Cursor": own("Anysphere"),
            "Gemini": alphabet,
            "Grok": own("xAI"),
            "Muse": meta,
            "NEAR AI": coin("NEAR", "NEAR", "near-near-protocol"),
            "OpenRouter": own("OpenRouter"),
            "Venice": coin("Venice", "VVV", "vvv-venice-token"),
            // Media
            "Apple Music": apple,
            "Pinterest": ("Pinterest", .stock("PINS")),
            "Podcasts": apple,
            "Spotify": ("Spotify", .stock("SPOT")),
            "Steam": own("Valve"),
            "Twitch": amazon,
            "YouTube": alphabet,
            // Social
            "Bluesky": own("Bluesky"),
            "Farcaster": own("Farcaster"),
            "Instagram": meta,
            "Snapchat": ("Snap", .stock("SNAP")),
            "Telegram": own("Telegram"),
            "TikTok": own("ByteDance"),
            "X": own("X"),
            // Reading
            "Kindle": amazon,
            "Raindrop": own("Raindrop"),
            "Readwise": own("Readwise"),
            "Substack": own("Substack"),
            // Shopping
            "Bitrefill": own("Bitrefill"),
            "Shopify": ("Shopify", .stock("SHOP")),
            // Notes
            "Apple Journal": apple,
            "Day One": own("Automattic"),
            "Obsidian": own("Obsidian"),
        ]
        return rows.mapValues { (company: $0.0, listing: $0.1) }
    }()

    /// A pack from the offer names in one category, in catalogue order: one
    /// row per company (Apple once in Life, however many Apple apps), A to Z.
    static func pack(offers: [String]) -> [Company] {
        var order: [String] = []
        var seats: [String: [String]] = [:]
        var listing: [String: Listing] = [:]
        for offer in offers {
            guard let maker = makers[offer] else { continue }
            if seats[maker.company] == nil { order.append(maker.company) }
            seats[maker.company, default: []].append(offer)
            listing[maker.company] = maker.listing
        }
        return order
            .map { Company(name: $0, listing: listing[$0] ?? .unlisted, seats: seats[$0] ?? []) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

/// One quote: the price, its day change as a FRACTION (-0.048 is -4.8%,
/// `TokenPulse`'s unit, which `TokenDeltaPill` reads), and the market cap
/// when the feed states one. A feed's zero cap is dropped, never drawn as "$0".
struct CompanyQuote: Hashable, Sendable {
    let price: Double
    let change: Double?
    let marketCap: Double?
    let at: Date
}

/// The pack quotes, read on demand and held ten minutes — a pack is opened to
/// look, not watched, so nothing polls it. Two keyless public feeds: Nasdaq's
/// quote API for stocks (price and cap in two calls) and CoinPaprika's ticker
/// for coins. A read that fails leaves no quote, and the row says nothing
/// rather than a stale or invented figure (§83).
@MainActor @Observable
final class CompanyQuotes {
    static let shared = CompanyQuotes()

    private(set) var quotes: [String: CompanyQuote] = [:]
    private var inFlight: Set<String> = []
    private static let freshFor: TimeInterval = 600

    func quote(_ listing: CompanyPacks.Listing) -> CompanyQuote? {
        listing.key.flatMap { quotes[$0] }
    }

    /// Reads every listing in the pack that is not fresh, concurrently.
    func load(_ companies: [CompanyPacks.Company]) async {
        // The demo reaches nothing (verify's "Demo reaches nothing"): a demo
        // company row draws without a quote rather than asking Nasdaq.
        if DemoMode.isActive { return }
        let stale = companies.map(\.listing).filter { listing in
            guard let key = listing.key, !inFlight.contains(key) else { return false }
            guard let q = quotes[key] else { return true }
            return Date.now.timeIntervalSince(q.at) > Self.freshFor
        }
        guard !stale.isEmpty else { return }
        for l in stale { if let k = l.key { inFlight.insert(k) } }
        await withTaskGroup(of: (String, CompanyQuote?).self) { group in
            for listing in Set(stale) {
                guard let key = listing.key else { continue }
                group.addTask { (key, await Self.read(listing)) }
            }
            for await (key, quote) in group {
                inFlight.remove(key)
                if let quote { quotes[key] = quote }
            }
        }
    }

    nonisolated private static func read(_ listing: CompanyPacks.Listing) async -> CompanyQuote? {
        switch listing {
        case .stock(let ticker): return await stock(ticker)
        case .token(_, let id):  return await coin(id)
        case .unlisted:          return nil
        }
    }

    /// Nasdaq answers an app-shaped User-Agent and hangs on a bare one
    /// (measured 2026-09-29), so the phone's own browser UA rides along.
    nonisolated private static func stock(_ ticker: String) async -> CompanyQuote? {
        let base = "https://api.nasdaq.com/api/quote/\(ticker)"
        let headers = ["User-Agent": IngestSupport.safariUserAgent]
        async let info = IngestSupport.getJSON("\(base)/info?assetclass=stocks", headers: headers)
        async let summary = IngestSupport.getJSON("\(base)/summary?assetclass=stocks", headers: headers)
        let primary = ((await info as? [String: Any])?["data"] as? [String: Any])?["primaryData"] as? [String: Any]
        guard let price = number(primary?["lastSalePrice"]) else { return nil }
        let data = (await summary as? [String: Any])?["data"] as? [String: Any]
        let cap = ((data?["summaryData"] as? [String: Any])?["MarketCap"] as? [String: Any])?["value"]
        return CompanyQuote(price: price, change: number(primary?["percentageChange"]).map { $0 / 100 },
                            marketCap: number(cap).flatMap { $0 > 0 ? $0 : nil }, at: .now)
    }

    nonisolated private static func coin(_ id: String) async -> CompanyQuote? {
        guard let root = await IngestSupport.getJSON("https://api.coinpaprika.com/v1/tickers/\(id)") as? [String: Any],
              let usd = (root["quotes"] as? [String: Any])?["USD"] as? [String: Any],
              let price = usd["price"] as? Double else { return nil }
        let cap = usd["market_cap"] as? Double
        return CompanyQuote(price: price, change: (usd["percent_change_24h"] as? Double).map { $0 / 100 },
                            marketCap: cap.flatMap { $0 > 0 ? $0 : nil }, at: .now)
    }

    /// "$1,234.50", "-0.34%", "3,779,305,633,099" → a number; "N/A" → nil.
    nonisolated static func number(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        guard let s = any as? String else { return nil }
        let cleaned = s.filter { $0.isNumber || $0 == "." || $0 == "-" }
        return cleaned.isEmpty ? nil : Double(cleaned)
    }
}
