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
    private var refreshing = false
    /// Failed fetches ride the same 15-minute gate — a token neither
    /// provider can chart must not cost 3 GETs on every foreground forever.
    private var lastTried: [String: Date] = [:]

    private init() {}

    /// The row's pulse — nil for everything but a watched token.
    func pulse(for thing: Thing) -> Pulse? {
        guard thing.source == "Tokens", let ref = thing.sourceRef else { return nil }
        return pulses[ref]
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
            $0.source == "Tokens"
        })
        var stale: [(ref: String, chain: String, address: String)] = []
        // Kept alongside `stale` so the new-high check below can read each
        // ref's watch-time anchor and title without a second fetch.
        var anchors: [String: Thing] = [:]
        for thing in (try? context.fetch(descriptor)) ?? [] {
            guard let ref = thing.sourceRef,
                  let route = TokenChart.route(from: thing.content) else { continue }
            anchors[ref] = thing
            if let fresh = pulses[ref], fresh.fetchedAt.timeIntervalSinceNow > -900 { continue }
            if let tried = lastTried[ref], tried.timeIntervalSinceNow > -900 { continue }
            stale.append((ref, route.chain, route.address))
        }
        guard !stale.isEmpty else { return }
        let stamp = Date.now
        for item in stale { lastTried[item.ref] = stamp }

        // Tokens are independent and TokenChart.fetch can be up to 4 GETs
        // strung together across its tiers — an uncapped fan-out burst on
        // the same Alchemy key WalletIngest reads wallets with drew silent
        // 429s (2026-07-13); capped at 4 in flight for the same reason.
        // Land every pulse in ONE dictionary write so the feed repaints
        // once, not once per token.
        let fetched = await IngestSupport.boundedGather(stale, maxConcurrent: 4) { item in
            (item.ref, await TokenChart.fetch(chain: item.chain, address: item.address))
        }
        var out: [String: Pulse] = [:]
        for (ref, chart) in fetched {
            guard let chart else { continue }
            out[ref] = Pulse(closes: chart.closes, change24h: chart.change,
                             price: chart.price, marketCap: chart.marketCap,
                             fdv: chart.fdv, fetchedAt: stamp)
            noteGainSinceWatched(ref: ref, price: chart.price, anchor: anchors[ref])
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

    /// "SOL is up 38% since you watched it 📈" (delight pass 2026-07-21) —
    /// the same "since you watched" anchor `TokenChartContent`'s sheet
    /// already draws (`thing.watchPriceUsd`, the real price the moment you
    /// added it), turned into a moment instead of a line you only see on
    /// open. Fires ONCE ever per token, at a genuinely notable gain (25%) —
    /// not a repeated all-time-high chase like the wallet's mark, because
    /// this anchor never moves: re-firing at every small new high above the
    /// SAME watch price would be noise, not news. Asymmetric by design, like
    /// every moment here: a loss earns only the honest red pill on the row.
    private func noteGainSinceWatched(ref: String, price: Double, anchor: Thing?) {
        guard let anchor, let watchPrice = anchor.watchPriceUsd, watchPrice > 0,
              price > watchPrice * 1.25
        else { return }
        let key = "moment.tokenGain.\(ref)"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        let pct = Int(((price / watchPrice) - 1) * 100)
        let name = TokensAsk.name(of: anchor.title)
        SourceMoments.shared.fire(
            String(localized: "\(name) is up \(pct)% since you watched it 📈"), source: "Tokens")
    }
}
