import Foundation
import Observation
import SwiftData

/// The watchlist's 24h heartbeat (Option A ruling 2026-07-10) — an in-memory
/// cache of each watched token's recent closes and 24h change, refreshed each
/// foreground alongside the bridges, so a Tokens feed row can wear a
/// sparkline the way a Twitch row wears Live. Ephemeral by design: prices are
/// perishable, so nothing persists — a cold launch fetches fresh, and a row
/// without a pulse yet just shows its timestamp like any other.
@MainActor
@Observable
final class TokenPulse {
    static let shared = TokenPulse()

    struct Pulse {
        let closes: [Double]
        let change24h: Double   // fraction, e.g. -0.048 = -4.8%
        /// The live price and market size, riding the same fetch (2026-07-17,
        /// the fat-row build) — so a feed row can quote them without a
        /// request of its own. cap/fdv are nil when the source didn't say.
        let price: Double
        let marketCap: Double?
        let fdv: Double?
        let fetchedAt: Date
    }

    /// Keyed by the watchlist thing's sourceRef.
    private(set) var pulses: [String: Pulse] = [:]
    /// A followed STOCK's day line (prd §1250), by its sourceRef: Yahoo's day
    /// closes, the same read the stock's page draws, held fifteen minutes as
    /// a token's pulse is. Its own map, not a `Pulse`: a stock's price and day
    /// move stay Nasdaq's quote (`CompanyQuotes`), which the index row and
    /// the alerts read, so a row can never quote two prices for one ticker.
    private(set) var stockLines: [String: (closes: [Double], fetchedAt: Date)] = [:]
    private var refreshing = false
    /// Failed fetches ride the same 15-minute gate — a token neither
    /// provider can chart must not cost 3 GETs on every foreground forever.
    private var lastTried: [String: Date] = [:]

    private init() {}

    /// The row's pulse — nil for everything but a watched token.
    /// GECKOTERMINAL COUNTS TOO (2026-09-06, user: "on the demo the thing
    /// sheets do not show prices or anything"). A trending row is the same
    /// shape of thing as a watched one — a token, a ref, a price — and the
    /// demo seeds both. **Inert in production**: `refresh()` below filters to
    /// `source == "Tokens"`, so no GeckoTerminal ref is ever written into
    /// `pulses`, and a REAL trending row carries a Dexscreener URL that
    /// `TokenChart.route` matches first, so it takes the live `.token` branch
    /// and never reaches the pulse fallback at all. This only lights up the
    /// demo, where there is no network and the pulse IS the chart.
    func pulse(for thing: Thing) -> Pulse? {
        guard thing.source == "Markets" || thing.source == "GeckoTerminal",
              let ref = thing.sourceRef else { return nil }
        return pulses[ref]
    }

    /// A followed stock's day closes, or nil until they are read.
    func stockLine(for thing: Thing) -> [Double]? {
        guard let ref = thing.sourceRef, StockWatch.symbol(of: thing) != nil else { return nil }
        return stockLines[ref]?.closes
    }

    /// Reads one stock's day line when the row stands (its `.task`), held
    /// fifteen minutes. Never in the demo, which reaches nothing (§217).
    func loadStockLine(ref: String, symbol: String) async {
        guard !DemoMode.isActive else { return }
        if let line = stockLines[ref], line.fetchedAt.timeIntervalSinceNow > -900 { return }
        if let tried = lastTried[ref], tried.timeIntervalSinceNow > -900 { return }
        lastTried[ref] = .now
        guard let chart = await StockChart.fetch(ticker: symbol, range: .day) else { return }
        stockLines[ref] = (closes: chart.closes, fetchedAt: .now)
    }

    /// Demo mode (prd §351 follow-up, 2026-08-11, user: "how come on tokens
    /// there isn't a sparkline and up down percent") — the same problem
    /// `-seedWalletHistory` solves for the balance curve, here for the
    /// Tokens room. `DemoMode.begin` runs `BridgeRefresh.refreshAllConnected`
    /// as a no-op (the fake wallet address must never get a real balance
    /// overwritten with zero), and that took `refresh()` above down with it —
    /// so every demo-watched token's pulse stayed nil forever and its row
    /// showed nothing but a timestamp. This writes `pulses` DIRECTLY, the
    /// same dictionary `refresh()` writes, so a row can't tell the difference
    /// — but it never calls `TokenChart.fetch` and therefore never touches
    /// the network, which matters here specifically: `DemoSeedAll.rooms()`
    /// deliberately drops the Dexscreener content URL from every demo token
    /// row (P4, 2026-08-07) so `ThingChart.kind(for:)` can never route a
    /// sheet-open into a live fetch for a fabricated address. Seeding
    /// `pulses` by ref rather than by route keeps that guarantee intact.
    ///
    /// The curve is a deterministic wiggle around the seeded
    /// `thing.watchPriceUsd` (`sin`, not `Double.random` — this file's own
    /// corpus-wide rule: a demo that reshuffles between two opens over
    /// identical data reads as broken), 24 points for a day's worth of an
    /// hourly close, ANCHORED so `closes.first`/`closes.last` land exactly on
    /// `price / (1 + change24h)` and `price` — the row's pill reads
    /// `change24h` directly, but the sheet's chart (`TokenChart.from(closes:)`)
    /// derives its OWN change from the closes array's first-vs-last, with no
    /// knowledge `change24h` exists. Unanchored, the two independently-true
    /// numbers disagreed (measured: a seeded +2.3% rendered as -1.6% on the
    /// chart) — the same row silently telling two different stories depending
    /// on which control you looked at. The wiggle stays OFF the two endpoints
    /// for exactly this reason: perturbing them would reopen the same gap by
    /// a smaller amount instead of closing it.
    func seedDemo(_ tokens: [(ref: String, price: Double, change24h: Double,
                              marketCap: Double?, phase: Double)]) {
        var seeded: [String: Pulse] = [:]
        for t in tokens {
            let start = t.price / (1 + t.change24h)
            let closes = (0..<24).map { i -> Double in
                let trend = start + (t.price - start) * (Double(i) / 23.0)
                guard i > 0, i < 23 else { return trend }
                return trend * (1 + 0.01 * sin(Double(i) * 0.9 + t.phase))
            }
            seeded[t.ref] = Pulse(closes: closes, change24h: t.change24h, price: t.price,
                                  marketCap: t.marketCap, fdv: nil, fetchedAt: .now)
        }
        pulses.merge(seeded) { _, new in new }
    }

    /// `demoTokens` in one place — `seedDemo` above takes raw tuples (kept
    /// generic/testable), everything else calls through here so the per-token
    /// direction/phase constants are spelled exactly once.
    private static func demoTokens() -> [(ref: String, price: Double, change24h: Double,
                                          marketCap: Double?, phase: Double)] {
        DemoSeedAll.tokenSeeds.enumerated().map { i, t in
            (ref: "demo:token:\(i)", price: t.price,
             change24h: [0.023, -0.011, 0.084][i % 3], marketCap: t.marketCap,
             phase: Double(i) * 2.1)
        }
    }

    func seedDemo() { seedDemo(Self.demoTokens()) }

    /// Re-seeds if the process just (re)started with demo mode already
    /// active — `pulses` is in-memory only (real prices are perishable, this
    /// file's own opening doc), so a fresh launch starts empty and
    /// `DemoMode.begin()`'s one-time `seedDemo()` call never runs again for
    /// the rest of that demo session. Called from the exact place a REAL
    /// launch's foreground sweep would have refreshed this cache instead —
    /// see `BridgeRefresh.refreshAllConnected`'s `DemoMode.isActive` gate.
    /// Cheap to call on every such gate hit: it's a dictionary-emptiness
    /// check, and it only actually seeds when something is missing.
    func reseedDemoIfNeeded() {
        guard Self.demoTokens().contains(where: { pulses[$0.ref] == nil }) else { return }
        seedDemo()
    }

    /// Reverses `seedDemo` — called from `DemoMode.exit` so a real Tokens
    /// connection afterward starts from a genuinely empty cache rather than
    /// one still wearing fabricated demo prices.
    func teardownDemo(_ refs: [String]) {
        for ref in refs { pulses.removeValue(forKey: ref) }
    }

    /// Fetches 24h curves for watched tokens whose pulse is stale (15 min —
    /// the foreground cadence; TokenChart is up to 4 GETs per token across
    /// its three tiers, so a same-minute re-foreground shouldn't refetch the
    /// lot). BridgeRefresh fires this; it exits instantly when nothing is
    /// watched.
    func refresh(context: ModelContext) async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }

        let descriptor = FetchDescriptor<Thing>(predicate: #Predicate {
            $0.source == "Markets"
        })
        var stale: [(ref: String, chain: String, address: String)] = []
        // A followed coin (prd §1250) reads CoinPaprika, by the id its ref
        // carries; a followed stock its day line. Both ride this gate.
        var coins: [(ref: String, id: String)] = []
        var stocks: [(ref: String, symbol: String)] = []
        for thing in (try? context.fetch(descriptor)) ?? [] {
            guard let ref = thing.sourceRef else { continue }
            if let tried = lastTried[ref], tried.timeIntervalSinceNow > -900 { continue }
            if let symbol = StockWatch.symbol(of: thing) {
                if let line = stockLines[ref], line.fetchedAt.timeIntervalSinceNow > -900 { continue }
                stocks.append((ref, symbol))
                continue
            }
            if let fresh = pulses[ref], fresh.fetchedAt.timeIntervalSinceNow > -900 { continue }
            if let id = CoinFollow.id(fromRef: ref) {
                coins.append((ref, id))
            } else if let route = TokenChart.route(from: thing.content) {
                stale.append((ref, route.chain, route.address))
            }
        }
        guard !stale.isEmpty || !coins.isEmpty || !stocks.isEmpty else { return }
        let stamp = Date.now
        for item in stale { lastTried[item.ref] = stamp }
        for item in coins { lastTried[item.ref] = stamp }
        for item in stocks { lastTried[item.ref] = stamp }

        // Tokens are independent and TokenChart.fetch can be up to 4 GETs
        // strung together across its tiers — an uncapped fan-out burst on
        // the same Alchemy key WalletIngest reads wallets with drew silent
        // 429s (2026-07-13); capped at 4 in flight for the same reason.
        // Land every pulse in ONE dictionary write so the feed repaints
        // once, not once per token.
        let fetched = await IngestSupport.boundedGather(stale, maxConcurrent: 4) { item in
            (item.ref, await TokenChart.fetch(chain: item.chain, address: item.address))
        }
        let fetchedCoins = await IngestSupport.boundedGather(coins, maxConcurrent: 4) { item in
            (item.ref, await CoinWatch.pulse(id: item.id))
        }
        let fetchedStocks = await IngestSupport.boundedGather(stocks, maxConcurrent: 2) { item in
            (item.ref, await StockChart.fetch(ticker: item.symbol, range: .day))
        }
        var out: [String: Pulse] = [:]
        for (ref, chart) in fetched {
            guard let chart else { continue }
            out[ref] = Pulse(closes: chart.closes, change24h: chart.change,
                             price: chart.price, marketCap: chart.marketCap,
                             fdv: chart.fdv, fetchedAt: stamp)
        }
        // A coin's price, day move and cap are its ticker's; its line is the
        // day's ticks when they answered, else no line (never a made one). A
        // ticker without a day move reads no move, not a flat one.
        for (ref, read) in fetchedCoins {
            guard let read, let change = read.ticker.change24h else { continue }
            out[ref] = Pulse(closes: read.closes, change24h: change,
                             price: read.ticker.price, marketCap: read.ticker.marketCap,
                             fdv: nil, fetchedAt: stamp)
        }
        for (ref, chart) in fetchedStocks {
            guard let chart else { continue }
            stockLines[ref] = (closes: chart.closes, fetchedAt: stamp)
        }
        pulses.merge(out) { _, new in new }
        // Home's watchlist tile reads this cache from a plain compose
        // function, not a live SwiftUI body — @Observable's automatic
        // re-render only covers reads made DURING body evaluation (the
        // Feed's rows qualify; this doesn't), so without an explicit bump
        // a fresh pulse landing after the first compose would leave the
        // tile's movers-first order and up/down subtitle frozen at
        // whatever they were (usually nothing) before this fetch finished.
        if !out.isEmpty { CorpusSignal.shared.bump() }
    }

}
