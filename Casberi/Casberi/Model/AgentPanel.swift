import Foundation

/// What is left of the agent's instrument panel (prd §334) — the value types
/// the answer's dial and semantic map still draw from.
///
/// The panel itself went in §386p, and its last surface, the source chip's
/// long-press peek on the iPad/Mac rail, went in §836 (user: "i don't think we
/// need that on ipad and mac"). With it went every per-room figure the peek
/// previewed — treemap, bars, rail, pulse, curve, wall, flow, runway, worth —
/// and the ranking that chose between them (§723: a figure deleted from the
/// surface is deleted from the model). What stays has a live producer: the
/// dial (`KeptAskComposers.dialLine` → `GenDial`) and the map's dots
/// (`AgentPanelFigures.scatter` → `ScatterFigure`).
///
/// **Foundation-only by design**: it holds no `Thing` and no SwiftUI, so
/// `scripts/agent-panel-selftest.sh` compiles it WHOLE with no stubs.
enum AgentPanel {

    // MARK: - Figures

    /// One mark on the day dial — a thing at its hour, with how recent it is.
    struct DialMark: Equatable {
        /// 0…24, fractional. Hour of day is the whole point: the heatmaps
        /// answer WHICH DAYS and nothing in the app answers which hours.
        var hour: Double
        /// 0 (oldest in window) … 1 (today) — drives the radius, so today
        /// rides the rim and the week fades inward.
        var recency: Double
        /// The room, for hue.
        var source: String
    }

    /// One dot on the semantic map — a thing already projected into the unit
    /// square. The PROJECTION happens upstream (`SemanticProjection`), never
    /// here: this file stays arithmetic, and the projection has to be cached
    /// anyway or the map would reshuffle between opens.
    struct Dot: Equatable, Sendable {
        var x: Double
        var y: Double
        var source: String
    }

    /// A named cluster on the semantic map — its centre and its own top term.
    struct DotCluster: Equatable, Sendable {
        var label: String
        var x: Double
        var y: Double
        var radius: Double
    }

    /// What a figure draws.
    ///
    /// Every case is a SHAPE, never a sentence. Adding a `.text` case is the
    /// tripwire for this whole feature: the moment a figure can be words, it
    /// is the list it replaced.
    enum Figure: Equatable {
        /// The day dial (prd §337) — a week of things on a 24-hour clock.
        /// Radially symmetric: no labels to clip, hue carries identity, and
        /// the shape itself is the reading.
        case dial([DialMark])

        /// The fewest marks that read as a RHYTHM rather than as dots.
        ///
        /// Spelled as a constant because it has a second reader: the answer
        /// ladder's WHEN rung composes a dial of its own
        /// (`KeptAskComposers.dialLine`), and it must decline on exactly this
        /// number or the emitter and the drawing disagree — a line the composer
        /// thought was worth emitting and the renderer refuses to draw is an
        /// answer with a hole where its figure was.
        static let dialFloor = 12

        /// A figure with nothing in it draws nothing.
        var isEmpty: Bool {
            switch self {
            // A dial of three marks is three dots on a circle, not a rhythm —
            // and rhythm is the only thing it claims.
            case .dial(let m):    return m.count < Self.dialFloor
            }
        }
    }

    /// Money, compact — the ONE formatter the panel uses (prd §341).
    ///
    /// The tiers mirror `WalletIngest.HoldingsGroup.subline`, which is what the
    /// Wallet room itself prints, because the panel is a window onto that room
    /// and the two must never disagree about the same number. They did: the
    /// panel's own formatter stopped at K, so a watched wallet holding $7.26M
    /// rendered "$7258k" on the hero while the room three taps away said
    /// "$7.0M". `TodayBrief.compactUSD` had the identical ceiling and the
    /// identical bug.
    ///
    /// A B tier exists because the app watches whoever you point it at, and
    /// "$7258k" is exactly what a missing tier looks like one order up.
    /// Forwards to `MoneyFormat` (2026-08-14). The table moved to `Shared/` when
    /// the wallet widget started drawing the same figures in another process —
    /// see that file for why a second copy was not an option.
    static func compactUSD(_ usd: Double) -> String { MoneyFormat.compactUSD(usd) }
}
