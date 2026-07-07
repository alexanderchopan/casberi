import Foundation

/// Per-source Feed compositions (docs/handoff-shaped-feeds.md) — the mirror of
/// `HomeComposition` for the Feed screen. A shaped feed adds at most ONE
/// synthesis block; this authors that block as gen-doc lines the engine
/// streams (skeleton entrance, same grammar as Home and ZerionScreen).
///
/// Division of labor, deliberately: the interactive ROWS are the List's —
/// native swipes, taps, pins, and day groups survive because they stay native
/// (the custom-gesture feed died on device: a child DragGesture eats vertical
/// scroll — ruling 2026-07-04). The engine paints the synthesis blocks; the
/// shaped-row grammar also exists in GenRenderer for compositions to use.
enum SourceComposition {

    /// The one synthesis block a source earns, or nil (most earn none).
    static func block(source: String, demo: Bool) -> [String]? {
        switch source {
        case "Zerion":
            // Treemap-first (mock Z1): holdings lead every visit to the chip.
            // Demo-gated like ZerionScreen — no fake numbers for real users.
            guard demo else { return nil }
            return [
                "root = Stack([hold])",
                "hold = TagMap(\"Holdings\", null, [ETH 4210, USDC 1840, SOL 620, BONK 80])",
            ]
        default:
            return nil
        }
    }
}
