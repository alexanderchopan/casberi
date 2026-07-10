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
        for thing in (try? context.fetch(descriptor)) ?? [] {
            guard let ref = thing.sourceRef,
                  let route = TokenChart.route(from: thing.content) else { continue }
            if let fresh = pulses[ref], fresh.fetchedAt.timeIntervalSinceNow > -900 { continue }
            guard let chart = await TokenChart.fetch(chain: route.chain,
                                                     address: route.address) else { continue }
            pulses[ref] = Pulse(closes: chart.closes, change24h: chart.change24h,
                                fetchedAt: .now)
        }
    }
}
