import SwiftUI

/// **THE FOLLOW MARK (prd §1230)**: the one control at the end of every add
/// tray's row — a plus in the tint that turns into a quiet check once
/// followed (or tracked). Markets' star, the trays' hand-drawn pluses and
/// checks all draw this, so "follow" looks the same wherever it is offered.
struct DSFollowMark: View {
    let on: Bool
    /// Followable no further (a cap reached): drawn quiet, like the check.
    var dimmed = false
    /// Bounces once when it becomes `on` (the save lands).
    var bounce = false

    var body: some View {
        Image(systemName: on ? "checkmark" : "plus")
            .dsGlyph(.title, weight: .regular)
            .foregroundStyle(on || dimmed ? DS.textTertiary : DS.tint)
            .symbolEffect(.bounce, value: bounce)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
    }
}
