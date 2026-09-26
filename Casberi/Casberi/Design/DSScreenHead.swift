import SwiftUI

/// A screen's name, in its content (prd §767).
///
/// The system's large title stood at the top edge at 34pt, beside a back
/// chevron. The name sits in the rows' column and scrolls away with them
/// (§767) — and since prd §915 it takes its OWN rung, `heading34`: at
/// `heading24` the screen's name, its sections, its switcher and "Since you
/// left" were four jobs on one rung, so nothing on the Accounts screen
/// outranked anything else. One scale now: the screen at 34, a section at
/// 24, a switcher's words at 17.
///
/// **A room wears one too, since prd §930.** Until then no room had a title:
/// the dock's lit tile named the category under your thumb. With the strip
/// folded into the rooms tray, nothing on the screen said which room you were
/// in, so every room names itself here, first in its list, the way a pushed
/// screen does.
struct DSScreenHead: View {
    let title: Text

    var body: some View {
        title
            .dsText(.heading34)
            .foregroundStyle(DS.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}
