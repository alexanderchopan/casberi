import Foundation
import SwiftData

/// Watched prediction markets, as an answer (2026-07-28) — the piece that
/// made markets visible to the agent at all. Until this, `TokensAsk` owned
/// the whole "How's my watchlist?" ask, so someone watching five markets and
/// no tokens asked the natural question and was told their watchlist was
/// empty. It wasn't; the composer just couldn't see markets.
///
/// Deterministic and free: it reads `PredictionPulse`'s already-fetched
/// cache rather than issuing requests of its own, so asking costs nothing
/// and can never disagree with what the feed rows show.
///
/// The same line the rest of this pair holds: this reports ODDS and what
/// you were watching, never a position, a stake, or a payout.
@MainActor
enum MarketsAsk {

    struct Move {
        let thing: Thing
        let probability: Double
        /// Points since watched — nil without an anchor. POINTS, not percent.
        let sinceWatched: Double?
        let resolved: Bool
        let yesWon: Bool?
        let thin: Bool
    }

    /// Every watched market, live ones first, then the settled records.
    static func watched(_ context: ModelContext) -> [Thing] {
        let descriptor = FetchDescriptor<Thing>(predicate: #Predicate<Thing> {
            $0.source == "Kalshi" || $0.source == "Polymarket"
        })
        return ((try? context.fetch(descriptor)) ?? [])
            .filter(\.isLive)
            .sorted { $0.capturedAt > $1.capturedAt }
    }

    /// The watched markets that have a reading, biggest mover first. Reads
    /// the pulse cache only — a market whose pulse hasn't landed is simply
    /// absent rather than shown at a guessed number.
    static func moves(context: ModelContext) -> [Move] {
        watched(context).compactMap { thing -> Move? in
            guard let pulse = PredictionPulse.shared.pulse(for: thing) else { return nil }
            return Move(thing: thing, probability: pulse.probability,
                        sinceWatched: pulse.sinceWatched,
                        resolved: thing.marketResolvedYes != nil || pulse.resolved,
                        yesWon: thing.marketResolvedYes ?? pulse.yesWon,
                        thin: pulse.thin)
        }
        .sorted { abs($0.sinceWatched ?? 0) > abs($1.sinceWatched ?? 0) }
    }

    /// "3 markets — the biggest move is Greenland, up 14 points since you
    /// watched." One sentence, and it names the mover rather than counting
    /// (the module doctrine: a tally is not news, the movement is).
    static func line(_ moves: [Move]) -> String {
        guard !moves.isEmpty else { return String(localized: "Nothing on your market watchlist yet.") }
        let settled = moves.filter(\.resolved)
        let live = moves.filter { !$0.resolved }
        // A market that RESOLVED leads — it's the only thing here that
        // became a fact rather than moved.
        if let just = settled.first {
            let answer = just.yesWon == true ? String(localized: "happened") : String(localized: "didn't happen")
            return String(localized: "\u{201c}\(just.thing.title)\u{201d} \(answer).")
        }
        guard let top = live.first, let move = top.sinceWatched, abs(move * 100) >= 1 else {
            let n = live.count
            return n == 1
                ? String(localized: "1 market watched — it hasn't moved since you added it.")
                : String(localized: "\(n) markets watched — none has moved much since you added them.")
        }
        let pts = Int(abs(move * 100).rounded())
        let dir = move > 0 ? String(localized: "up") : String(localized: "down")
        let count = live.count == 1
            ? String(localized: "1 market")
            : String(localized: "\(live.count) markets")
        return String(localized: "\(count) — \u{201c}\(top.thing.title)\u{201d} is \(dir) \(pts) points since you watched it.")
    }

    /// Rows for the answer document — one per market, the odds (or the
    /// settled answer) on the trailing edge. Capped at 6, the same dose the
    /// token watchlist shows.
    static func rows(_ moves: [Move], prefix: String = "m") -> [String] {
        let shown = Array(moves.prefix(6))
        guard !shown.isEmpty else { return [] }
        let ids = shown.indices.map { "\(prefix)\($0)" }
        var lines = ["mkt = Widget(\"\(String(localized: "Markets"))\", \"\(shown.count)\", [\(ids.joined(separator: ", "))])"]
        for (i, m) in shown.enumerated() {
            let trailing: String = if m.resolved {
                m.yesWon == true ? String(localized: "Yes") : String(localized: "No")
            } else {
                "\(Int((m.probability * 100).rounded()))%"
            }
            lines.append("\(prefix)\(i) = Row(\"\(KeptAskComposers.genSafe(m.thing.title))\", \"\(m.thing.kind.typeTag)\", \"\(m.thing.source)\", \"\(trailing)\", \"\(m.thing.id.uuidString)\")")
        }
        return lines
    }
}
