import SwiftUI

/// One stable color per project (V3b ruling 2026-07-07): the color belongs
/// to the person's own label, never the kind — "Lisbon trip" wears the same
/// hue on every feed row, on its Home map tile, and on its project screen.
/// Nothing to learn: the label is the person's own word; the color just
/// keeps it recognizable.
///
/// Assigned by a deterministic hash of the name — Swift's `hashValue` is
/// seeded per launch and must never decide anything persistent. Renaming a
/// project changes its color (the name IS the identity); a hand-picked
/// override is a later settings nicety.
enum ProjectHue {
    /// Ten hues, all readable as text on the dark page; light mode pulls
    /// them toward black at the call site.
    private static let palette: [String] = [
        "#2dd4bf", "#f472b6", "#a78bfa", "#fb923c", "#34d399",
        "#60a5fa", "#facc15", "#fb7185", "#22d3ee", "#c084fc",
    ]

    static func color(for name: String) -> Color {
        Color(hex: palette[index(for: name)])
    }

    private static func index(for name: String) -> Int {
        var h: UInt64 = 5381
        for b in name.lowercased().utf8 { h = (h &* 33) &+ UInt64(b) }
        return Int(h % UInt64(palette.count))
    }
}
