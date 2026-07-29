import SwiftUI

/// A market's odds as a bar, with WHERE THEY WERE marked on it (prd §234).
///
/// The first pass drew a plain fill: every outcome, every venue, the same
/// tint, carrying nothing but length. But a prediction market's whole
/// subject is MOVEMENT — a number at 68% that was 59% yesterday is a
/// different story from one that has sat at 68% for a month, and both
/// bridges already parse `previousProbability` (Kalshi's previous close,
/// Polymarket's one-week change). Marking the prior level on the same bar
/// turns a static quantity into that story, using data already in hand and
/// no extra space.
///
/// Honest about small moves: under half a point there is no direction to
/// show (the `TokenDeltaPill.points` rule, §83 ③ — a change that rounds to
/// zero gets no sign and no colour), so the mark is simply omitted rather
/// than drawn flush against the fill where it would read as a hairline.
/// Design law forbids hairlines as SEPARATORS; this is a data mark inside a
/// visualization, the same class of thing as a chart's axis tick.
struct PredictionOddsBar: View {
    let probability: Double
    var previous: Double? = nil
    /// The leader in a race, or a binary market's own side — drawn in the
    /// accent. Also-rans read quieter so a field of four scans by weight.
    var isLead: Bool = true

    private var moved: Double? {
        guard let previous else { return nil }
        let delta = probability - previous
        return abs(delta * 100) >= 0.5 ? delta : nil
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(DS.fillFaint)
                Capsule()
                    .fill(isLead ? DS.tint : DS.textTertiary)
                    .frame(width: max(0, min(1, probability)) * width)
                if let moved, let previous {
                    // The prior level, as a notch. Green when the market has
                    // climbed away from it, red when it has fallen back —
                    // direction stated by position AND hue, never hue alone.
                    Capsule()
                        .fill(moved > 0 ? DS.confirm : DS.destructive)
                        .frame(width: 2)
                        .offset(x: max(0, min(1, previous)) * width - 1)
                }
            }
        }
    }
}
