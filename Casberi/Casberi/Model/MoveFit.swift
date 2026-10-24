import Foundation

/// **MOVE'S SENTENCE IS ONE SIZE, PICKED BY FIT (prd §1479).**
///
/// Every word of the sentence wears one rung (§1466), and the rung is the
/// largest at which every clause still stands whole on its line — 52, then
/// 44, then 34 (`DSTextStyle.heading52/44/34`). The flow measures its widest
/// clause at whatever rung it is drawn at; because the three rungs are one
/// face at one weight, a clause's width at any other rung is that width
/// scaled by the ratio of the sizes, so one measurement answers for the
/// whole ladder and the pick never has to try a size on screen.
///
/// Stepping up asks for two points of slack, so a clause that fits by a
/// rounding error at the bigger size does not flip the sentence back and
/// forth between two rungs (the Figtree advances round per glyph).
enum MoveFit {
    /// Top to floor, in points.
    static let ladder: [Double] = [52, 44, 34]
    /// What a step up must clear, over the width itself.
    static let slack: Double = 2

    /// The rung to draw at, given the widest clause measured at `drawn`
    /// and the width the sentence has. Nothing measured yet, or no width:
    /// stay where you are.
    static func pick(widest: Double, drawnAt drawn: Double, width: Double) -> Double {
        guard widest > 0, width > 0, drawn > 0 else { return drawn }
        for rung in ladder {
            let predicted = widest * rung / drawn
            let margin = rung > drawn ? slack : 0
            if predicted <= width - margin { return rung }
        }
        return ladder[ladder.count - 1]
    }
}
