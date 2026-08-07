import Foundation
import Observation
import SwiftData

/// The GeckoTerminal bridge (2026-07-14) — the tokens trending RIGHT NOW on the
/// chains you watch land in your feed as links. It's the OpenSea bridge's exact
/// shape (follow a list of chains, fetch → filter → dedupe → things, no
/// algorithm of ours in between) pointed at a different endpoint: GeckoTerminal's
/// public `trending_pools`. Read-only, public price data — Casberi never shows a
/// path to buy, sell, or trade.
///
/// Two honest notes this bridge wears:
///   • "Trending" is someone's ranking, and we NAME whose — GeckoTerminal's, by
///     24h volume and price move. The screen and the feed say so; we don't
///     launder a paid boost list as neutral truth.
///   • It follows CHAINS, not tokens. You pick Ethereum, Base, Solana…; each
///     chain's current top movers land. There's no account and no key —
///     GeckoTerminal's trending endpoint is keyless, so there's nothing to mint
///     or store (this is where it's SIMPLER than OpenSea).
///
/// Each landed thing's `content` is the token's Dexscreener URL, which is what
/// `TokenChart.route(from:)` already parses — so a trending row's sheet draws the
/// same live on-device chart a watched token's does, for free. Watching a token
/// stays the Tokens bridge's job (an explicit tap): trending is discovery.

// MARK: - Chains

/// The chains Casberi watches for trending tokens — the networks with real
/// trending-token culture, each carrying two slugs because two APIs disagree on
/// spelling: GeckoTerminal's own network id (`gecko`, for the trending +
/// OHLCV calls) and Dexscreener's chain slug (`dex`, for the token URL, which
/// `TokenChart.route` reads). Curated, not exhaustive — a chain with no trading
/// culture would only pad the picker.
enum TrendingChain: String, CaseIterable, Identifiable {
    case ethereum, base, solana, bsc, arbitrum, polygon, optimism, avalanche, blast, robinhood

    var id: String { rawValue }

    /// The name shown in the picker and the "Trending on …" header.
    var display: String {
        switch self {
        case .ethereum:  "Ethereum"
        case .base:      "Base"
        case .solana:    "Solana"
        case .bsc:       "BNB Chain"
        case .arbitrum:  "Arbitrum"
        case .polygon:   "Polygon"
        case .optimism:  "Optimism"
        case .avalanche: "Avalanche"
        case .blast:     "Blast"
        case .robinhood: "Robinhood"
        }
    }

    /// GeckoTerminal's network id — the `trending_pools` path piece.
    var gecko: String {
        switch self {
        case .ethereum:  "eth"
        case .base:      "base"
        case .solana:    "solana"
        case .bsc:       "bsc"
        case .arbitrum:  "arbitrum"
        case .polygon:   "polygon_pos"
        case .optimism:  "optimism"
        case .avalanche: "avax"
        case .blast:     "blast"
        case .robinhood: "robinhood"
        }
    }

    /// Dexscreener's chain slug — the token URL uses this spelling so the
    /// thing sheet's `TokenChart.route` resolves the chart.
    var dex: String {
        switch self {
        case .ethereum:  "ethereum"
        case .base:      "base"
        case .solana:    "solana"
        case .bsc:       "bsc"
        case .arbitrum:  "arbitrum"
        case .polygon:   "polygon"
        case .optimism:  "optimism"
        case .avalanche: "avalanche"
        case .blast:     "blast"
        case .robinhood: "robinhood"
        }
    }

    static func from(_ id: String) -> TrendingChain? {
        TrendingChain(rawValue: id.lowercased())
    }
}

// MARK: - Store (just the watched chains — no key, nothing to mint)

@Observable
final class TrendingStore {
    static let shared = TrendingStore()
    private static let key = "gecko.trending.chains.v1"

    private var chainIDs: [String] { didSet { persist() } }

    /// The default watch when someone connects with no chain chosen — the
    /// three chains with the most trending-token culture.
    static let defaultChains = ["ethereum", "base", "solana"]

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([String].self, from: data) {
            chainIDs = saved
        } else {
            chainIDs = []
        }
    }

    var connected: Bool { !chainIDs.isEmpty }
    var watchedChains: [TrendingChain] { chainIDs.compactMap(TrendingChain.from) }

    func isWatching(_ chain: TrendingChain) -> Bool { chainIDs.contains(chain.rawValue) }

    func add(_ chain: TrendingChain) {
        guard !chainIDs.contains(chain.rawValue) else { return }
        chainIDs.append(chain.rawValue)
    }

    func remove(_ chain: TrendingChain) {
        chainIDs.removeAll { $0 == chain.rawValue }
    }

    /// Connect with the default chains when nothing's watched yet — the
    /// one-tap path and the setup screen's first appearance.
    func connectDefaults() {
        guard chainIDs.isEmpty else { return }
        chainIDs = Self.defaultChains
    }

    func disconnect() {
        chainIDs = []
    }

    /// The "Trending on Ethereum, Base & Solana" line the setup screen and the
    /// feed section wear — names WHOSE trending (GeckoTerminal's) by naming the
    /// chains it's ranking. Empty watch → the bare word.
    var trendingHeader: String {
        let names = watchedChains.map(\.display)
        switch names.count {
        case 0:  return "Trending"
        case 1:  return "Trending on \(names[0])"
        case 2:  return "Trending on \(names[0]) & \(names[1])"
        default: return "Trending on \(names.dropLast().joined(separator: ", ")) & \(names.last!)"
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(chainIDs) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}

// MARK: - Ingest

enum TrendingIngest {

    /// Serializes refreshes — the launch hook can race the foreground refresh,
    /// and both would read "existing" before either saved (the RSS lesson).
    @MainActor private static var running = false

    /// One trending token worth landing — the pool's BASE token, parsed and
    /// quality-filtered at the door.
    private struct Trend {
        let name: String
        let symbol: String
        let tokenAddress: String
        let image: String?
        /// The base token's USD price the moment it trended. Nil when the
        /// payload didn't carry one — never 0, which would read as a
        /// worthless token rather than an unread field (§83).
        let priceUSD: Double?
    }

    /// The current trending tokens on one chain, or nil when the fetch failed
    /// (offline, an API hiccup). Empty (not nil) is a real answer: nothing on
    /// this chain cleared the liquidity floor this pass.
    ///
    /// `include=base_token` folds the token objects (name, symbol, image,
    /// address) into a top-level `included` array, keyed by the JSON:API id the
    /// pool's `base_token` relationship points at.
    private static func fetch(_ chain: TrendingChain) async -> [Trend]? {
        let url = "https://api.geckoterminal.com/api/v2/networks/\(chain.gecko)"
            + "/trending_pools?include=base_token&page=1"
        guard let root = await IngestSupport.getJSON(url) as? [String: Any],
              let pools = root["data"] as? [[String: Any]] else { return nil }

        // Index the included token objects by their JSON:API id so each pool
        // can resolve its base token in one lookup.
        var tokens: [String: [String: Any]] = [:]
        for item in (root["included"] as? [[String: Any]]) ?? [] {
            if (item["type"] as? String) == "token", let id = item["id"] as? String {
                tokens[id] = item["attributes"] as? [String: Any]
            }
        }

        return pools.compactMap { pool -> Trend? in
            guard let attrs = pool["attributes"] as? [String: Any],
                  let rels = pool["relationships"] as? [String: Any],
                  let baseRef = ((rels["base_token"] as? [String: Any])?["data"] as? [String: Any]),
                  let tokenID = baseRef["id"] as? String,
                  let token = tokens[tokenID],
                  let symbol = (token["symbol"] as? String)?
                      .trimmingCharacters(in: .whitespacesAndNewlines), !symbol.isEmpty,
                  let tokenAddress = token["address"] as? String, !tokenAddress.isEmpty
            else { return nil }

            // The one quality floor: a pool with almost no liquidity that spikes
            // into "trending" on wash volume is the token equivalent of OpenSea's
            // empty test contracts. GeckoTerminal's own ranking already filters
            // most of it; this catches the dust it doesn't. A pool with no
            // readable reserve is dust as far as this floor is concerned — it
            // can't clear a bar it doesn't reach.
            guard let reserve = Self.number(attrs["reserve_in_usd"]),
                  reserve >= 5_000 else { return nil }

            let name = (token["name"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? symbol
            // A price of exactly 0 is a token nobody quoted, not a free one —
            // so it reads as absent, the same way `WalletIngest` refuses a
            // zero price rather than storing it.
            let price = Self.number(attrs["base_token_price_usd"])
                .flatMap { $0 > 0 ? $0 : nil }
            return Trend(name: name, symbol: symbol, tokenAddress: tokenAddress,
                         image: IngestSupport.tokenLogoURL(token["image_url"]),
                         priceUSD: price)
        }
    }

    /// Fetches the current trending tokens on every watched chain and lands new
    /// ones as link things. Returns the number of NEW things, 0 when up to date,
    /// nil when nothing was reachable (offline).
    @MainActor
    static func refresh(context: ModelContext) async -> Int? {
        let chains = TrendingStore.shared.watchedChains
        guard !chains.isEmpty, !running else { return running ? 0 : nil }
        running = true
        defer { running = false }

        // GeckoTerminal's free tier is ~30 calls/min; one call per chain, capped
        // low, stays well under it.
        let results = await IngestSupport.boundedGather(chains, maxConcurrent: 3) { chain in
            (chain, await fetch(chain))
        }

        var existing = IngestSupport.existingSourceRefs(context, source: "GeckoTerminal")
        let backfill = ArtlessBackfill(context, source: "GeckoTerminal")
        // Fetched once, not per-token below — the crossing check is a plain
        // dictionary lookup against this, same shape as PostHogBridge.land's
        // one keyed fetch.
        let tokensByRef = IngestSupport.thingsByRef(context, source: "Tokens")
        var added = 0
        var reachedAny = false

        for (chain, trends) in results {
            guard let trends else { continue }
            reachedAny = true
            // Top 10 movers per chain — the endpoint returns 20; the corpus
            // doesn't need the tail.
            for t in trends.prefix(10) {
                // Dedupe by TOKEN, not pool: a token trends in several pools at
                // once (WBTC lands from three), and the person reading the feed
                // wants "WBTC is trending" once, not one row per liquidity pool.
                // `existing` grows as we insert, so a second pool of the same
                // token this pass is caught here, not just across refreshes.
                let ref = "gecko:\(chain.gecko):\(t.tokenAddress.lowercased())"
                if existing.contains(ref) {
                    backfill.patch(ref, image: t.image)
                    continue
                }
                let thing = Thing(
                    kind: .link,
                    // titleLine flattens newlines and caps length — token names
                    // and symbols are attacker-controlled and notoriously
                    // abusive (a name can carry a newline + a scam URL), so the
                    // corpus's one-line-title invariant is enforced at the door,
                    // same as OpenSea.
                    title: IngestSupport.titleLine("\(t.name) · $\(t.symbol)"),
                    // The Dexscreener URL is what TokenChart.route reads, so the
                    // sheet draws the live chart — and it opens to a real page.
                    content: "https://dexscreener.com/\(chain.dex)/\(t.tokenAddress)",
                    source: "GeckoTerminal",
                    capturedAt: .now,
                    tags: ["Trending"],
                    sourceRef: ref
                )
                thing.previewImageURL = t.image
                // The base token's price the moment it trended — the same
                // shape `StocktwitsBridge` and `TokenWatch` stamp one field
                // over, with the currency carried beside it instead of baked
                // into the field name. `capturedAt` is the matching WHEN.
                //
                // It goes NOWHERE on screen, and that is deliberate: nothing
                // renders `priceValue` for a `.link` (only the `.product`
                // branch of `ThingContent` does), and a price read at ingest
                // must never paint as the price now. The sheet already answers
                // "what's it worth?" the honest way — `TokenChart.route` reads
                // the Dexscreener URL in `content` and draws a curve fetched
                // live every time the sheet opens.
                if let price = t.priceUSD {
                    thing.priceValue = price
                    thing.priceCurrency = "USD"
                }
                context.insert(thing)
                existing.insert(ref)
                SpotlightIndex.index([thing])
                added += 1
                // "You were already watching this" — the crossing only this
                // app can see: a token just starting to trend that's ALREADY
                // on the Tokens watchlist (delight pass 2026-07-28). Exact
                // join, zero extra network cost — `chain.dex` is the same
                // slug TokenWatch.add stamps into its own sourceRef, so this
                // is a direct ref lookup, not fuzzy matching.
                let tokensRef = "tokens:\(chain.dex):\(t.tokenAddress.lowercased())"
                if let watched = tokensByRef[tokensRef] {
                    SourceMoments.shared.fire(
                        String(localized: "\(TokensAsk.name(of: watched.title)) is trending on \(chain.display) — you're already watching it"),
                        source: "GeckoTerminal")
                }
            }
        }
        if added > 0 || backfill.any { context.saveHonestly() }
        return reachedAny ? added : nil
    }

    // MARK: - Parsing helpers

    /// GeckoTerminal serves numbers as strings ("57740.3433") — accept either.
    /// Nil, never 0, when the field is missing or unreadable: the callers
    /// above all treat "we didn't read it" and "it is zero" as different
    /// answers, and collapsing them is the §83 invented value.
    private static func number(_ raw: Any?) -> Double? {
        if let d = raw as? Double { return d }
        if let i = raw as? Int { return Double(i) }
        if let s = raw as? String { return Double(s) }
        return nil
    }

    // MARK: - What this bridge deliberately does NOT land
    //
    // `reserve_in_usd` is still read only as the quality floor above, and
    // `volume_usd.h24`, `price_change_percentage`, `market_cap_usd` and
    // `fdv_usd` still sit unread in the same payload. Landing them as
    // `enrichedText` was considered on 2026-08-06 and declined, for two
    // reasons that both point the same way:
    //
    //   • **A stale magnitude is only safe if it says when it was true**, so
    //     the text has to carry its own moment ("liquidity when this trended:
    //     about $57K — a reading from then, not now"). That is roughly 150
    //     characters of BOILERPLATE, identical on every row.
    //   • `EmbeddingIndex.indexText` is title + content + summary +
    //     enrichedText, and `vector(for:)` reads the first 500 characters of
    //     it. A trending row's title is ~12 characters and its `content` is
    //     already a near-identical Dexscreener URL, so 150 characters of
    //     shared prose would DOMINATE the vector and make every trending
    //     token "related" to every other one — the failure the Watchlist tag
    //     already taught this app.
    //
    // And the retrieval it would buy is close to nothing: the retriever does
    // no numeric comparison, so "which ones had real volume" is unanswerable
    // either way, and the words themselves appear on every row, so they can't
    // discriminate between any two of them. A 24h price MOVE is worse still —
    // a percentage carries no moment inside it the way a dollar figure does,
    // which is exactly what makes it read as current.
    //
    // The price is the one number that escapes all of this: `priceValue` is a
    // structured field, not prose, so it costs the embedding nothing.
}
