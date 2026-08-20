import Foundation
import Observation
import SwiftData

/// The prediction-markets' foreground heartbeat (2026-07-28) — the
/// TokenPulse pattern applied to Kalshi + Polymarket, and the fix for a real
/// gap: a watched market used to go dead the moment KalshiScreen closed
/// (nothing refreshed it until its OWN sheet reopened and refetched). Now
/// every watched market's odds refresh each foreground alongside the token
/// watchlist.
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

    // MARK: - Demo

    /// The demo's watched markets (2026-08-12). `PredictionRow` is mounted
    /// ONLY when a pulse exists — its own doc says so — and nothing ever
    /// seeded one, so all four demo markets fell back to a plain band row: a
    /// title and a timestamp, no odds, no delta. The exact shape of the
    /// Tokens gap found the same day, in the room next door, and invisible
    /// to every check because the ROWS were all present and correct.
    ///
    /// One of the four is SETTLED on purpose. The receipt ("You followed at
    /// 42%") is the payoff of the whole feature (prd §235) and it reports
    /// attention, never winnings — a first-time opener should see that this
    /// app closes the loop, which a room of four open markets can't show.
    func seedDemo() {
        let seeds: [(ref: String, probability: Double, since: Double?,
                     resolved: Bool, yesWon: Bool?)] = [
            ("demo:kalshi:0", 0.72, 0.06, false, nil),
            ("demo:kalshi:1", 0.61, 0.19, true, true),
            ("demo:polymarket:0", 0.27, 0.08, false, nil),
            ("demo:polymarket:1", 0.70, 0.09, false, nil),
        ]
        let stamp = Date.now
        for s in seeds {
            pulses[s.ref] = Pulse(probability: s.probability, resolved: s.resolved,
                                  yesWon: s.yesWon, sinceWatched: s.since,
                                  thin: false, fetchedAt: stamp)
        }
    }

    /// Re-seeds when the process restarted with the demo already active —
    /// `pulses` is in-memory only, so a relaunch empties it and
    /// `DemoMode.begin`'s one-time call never runs again. Mirrors
    /// `TokenPulse.reseedDemoIfNeeded`, and is called from the same gate.
    func reseedDemoIfNeeded() {
        guard pulses["demo:kalshi:0"] == nil else { return }
        seedDemo()
    }

    /// Reverses `seedDemo` — so a real Kalshi/Polymarket watch afterward
    /// starts from a genuinely empty cache rather than fabricated odds.
    func teardownDemo(_ refs: [String]) {
        for ref in refs { pulses.removeValue(forKey: ref) }
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
        var dirty = false
        for (thing, ref, market) in fetched {
            guard let market, thing.isLive else { continue }
            out[ref] = Pulse(probability: market.probability, resolved: market.resolved,
                             yesWon: market.yesWon,
                             sinceWatched: thing.watchPriceUsd.map { market.probability - $0 },
                             thin: market.isThin, fetchedAt: stamp)

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
        if !out.isEmpty { CorpusSignal.shared.bump() }
    }
}
