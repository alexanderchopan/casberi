import Foundation
import Observation
import SwiftData

/// The prediction-markets' foreground heartbeat (2026-07-28) — the
/// TokenPulse pattern applied to Kalshi + Polymarket, and the fix for a real
/// gap: a watched market used to go dead the moment KalshiScreen closed
/// (nothing refreshed it until its OWN sheet reopened and refetched). Now
/// every watched market's odds refresh each foreground alongside the token
/// watchlist, and PredictionMoments gets a chance to fire off the delta.
/// Ephemeral like TokenPulse's cache — prices/odds are perishable, nothing
/// persists here.
@MainActor
@Observable
final class PredictionPulse {
    static let shared = PredictionPulse()

    struct Pulse {
        let probability: Double
        let resolved: Bool
        let yesWon: Bool?
        /// Points moved since the day this market was watched (0.34 → 0.61 is
        /// +0.27), or nil when there's no anchor. POINTS, never percent: a
        /// 34%→61% move is +27 points, and calling it "+79%" would be a
        /// different, wrong claim about the same number.
        let sinceWatched: Double?
        /// The book is too thinly traded for its number to carry much —
        /// the row says so instead of printing a confident percentage.
        let thin: Bool
        let fetchedAt: Date
    }

    /// Keyed by the watched thing's sourceRef.
    private(set) var pulses: [String: Pulse] = [:]
    private var refreshing = false
    private var lastTried: [String: Date] = [:]

    private init() {}

    /// The row's pulse — nil for everything but a watched Kalshi/Polymarket market.
    func pulse(for thing: Thing) -> Pulse? {
        guard let ref = thing.sourceRef,
              thing.source == PredictionSource.kalshi.rawValue
                || thing.source == PredictionSource.polymarket.rawValue
        else { return nil }
        return pulses[ref]
    }

    /// Refetches odds for watched markets whose pulse is stale (15 min,
    /// matching TokenPulse's cadence). Exits instantly when nothing is
    /// watched. BridgeRefresh fires this each foreground.
    func refresh(context: ModelContext) async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }

        let descriptor = FetchDescriptor<Thing>(predicate: #Predicate<Thing> {
            $0.source == "Kalshi" || $0.source == "Polymarket"
        })
        var stale: [(thing: Thing, ref: String)] = []
        for thing in (try? context.fetch(descriptor)) ?? [] {
            guard thing.isLive, let ref = thing.sourceRef else { continue }
            // A SETTLED market is finished — its number can never move again,
            // so refetching it forever would spend a request per foreground
            // to re-learn the same fact. It keeps its last pulse for display.
            if thing.marketResolvedYes != nil { continue }
            if let fresh = pulses[ref], fresh.fetchedAt.timeIntervalSinceNow > -900 { continue }
            if let tried = lastTried[ref], tried.timeIntervalSinceNow > -900 { continue }
            stale.append((thing, ref))
        }
        guard !stale.isEmpty else { return }
        let stamp = Date.now
        for item in stale { lastTried[item.ref] = stamp }

        // Independent, network-bound reads across two hosts — capped the
        // same way TokenPulse caps its token fan-out, so a big watchlist
        // can't burst every request in the same instant.
        let fetched = await IngestSupport.boundedGather(stale, maxConcurrent: 4) { item in
            (item.thing, item.ref, await PredictionMarket.fetch(for: item.thing))
        }

        var out: [String: Pulse] = [:]
        var moments: [(thing: Thing, before: Double?, market: PredictionMarket)] = []
        var dirty = false
        for (thing, ref, market) in fetched {
            guard let market, thing.isLive else { continue }
            let before = pulses[ref]?.probability
            out[ref] = Pulse(probability: market.probability, resolved: market.resolved,
                             yesWon: market.yesWon,
                             sinceWatched: thing.watchPriceUsd.map { market.probability - $0 },
                             thin: market.isThin, fetchedAt: stamp)
            moments.append((thing, before, market))

            // A close time can move (an event is postponed, a race is called
            // early), and the deadline lane reads `dueAt` — so keep it true
            // rather than frozen at whatever it was on the day you watched.
            if let close = market.closeTime, thing.dueAt != close {
                thing.dueAt = close
                dirty = true
            }
            // End of life: stamped ONCE, when the exchange says which way it
            // went. `resolved` alone isn't enough — a market can close with
            // its answer still under arbitration, and that isn't a record yet.
            if market.resolved, let won = market.yesWon, thing.marketResolvedYes == nil {
                thing.marketResolvedYes = won
                dirty = true
            }
        }
        if dirty { context.saveHonestly() }
        pulses.merge(out) { _, new in new }
        if !out.isEmpty {
            CorpusSignal.shared.bump()
            PredictionMoments.check(moments, context: context)
        }
    }
}
