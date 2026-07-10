import Foundation
import Observation
import SwiftData

/// The watchlist's 24h heartbeat (Option A ruling 2026-07-10) — an in-memory
/// cache of each watched token's recent closes and 24h change, refreshed each
/// foreground alongside the bridges, so a Dexscreener feed row can wear a
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
        guard thing.source == "Dexscreener", let ref = thing.sourceRef else { return nil }
        return pulses[ref]
    }

    /// Fetches 24h curves for watched tokens whose pulse is stale (15 min —
    /// the foreground cadence; TokenChart is two GETs per token, so a
    /// same-minute re-foreground shouldn't refetch the lot). BridgeRefresh
    /// fires this; it exits instantly when nothing is watched.
    func refresh(context: ModelContext) async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }

        let descriptor = FetchDescriptor<Thing>(predicate: #Predicate {
            $0.source == "Dexscreener"
        })
        var stale: [(ref: String, chain: String, address: String)] = []
        for thing in (try? context.fetch(descriptor)) ?? [] {
            guard let ref = thing.sourceRef,
                  let route = TokenChart.route(from: thing.content) else { continue }
            if let fresh = pulses[ref], fresh.fetchedAt.timeIntervalSinceNow > -900 { continue }
            if let tried = lastTried[ref], tried.timeIntervalSinceNow > -900 { continue }
            stale.append((ref, route.chain, route.address))
        }
        guard !stale.isEmpty else { return }
        let stamp = Date.now
        for item in stale { lastTried[item.ref] = stamp }

        // Tokens are independent and TokenChart.fetch is 2-3 GETs strung
        // together — serially, N tokens cost up to 3N round trips end to
        // end. Fan out, then land every pulse in ONE dictionary write so
        // the feed repaints once, not once per token.
        let fetched = await withTaskGroup(of: (String, TokenChart?).self) { group in
            for item in stale {
                group.addTask {
                    (item.ref, await TokenChart.fetch(chain: item.chain, address: item.address))
                }
            }
            var out: [String: TokenChart] = [:]
            for await (ref, chart) in group {
                if let chart { out[ref] = chart }
            }
            return out
        }
        pulses.merge(fetched.mapValues {
            Pulse(closes: $0.closes, change24h: $0.change24h, fetchedAt: stamp)
        }) { _, new in new }
    }
}
