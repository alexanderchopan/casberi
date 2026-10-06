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
    /// A category's name is pink (prd §1129, user: "i meant for ONLY the
    /// category to be in pink"); a pushed screen's stays primary.
    var ink: Color = DS.textPrimary

    var body: some View {
        title
            .dsText(.heading34)
            .foregroundStyle(ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// **A CATEGORY'S TITLE ROW (prd §1129).** Its name in pink at the leading
/// edge and the pill that picks what it shows at the trailing edge, on one
/// axis. Every room draws it first in its list, and You's three screens
/// (Apps, Addresses, Settings) draw it in place of their own heads, so the
/// row never moves when the pick does.
struct DSRoomTitleRow<Pill: View>: View {
    let title: String
    @ViewBuilder let pill: () -> Pill

    var body: some View {
        HStack(alignment: .center, spacing: DS.Space.s3) {
            DSScreenHead(title: Text(verbatim: title), ink: DS.brandInk)
                // A name you gave the app can run 24 characters; it shrinks
                // to stay on the pill's line rather than wrap under it.
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Spacer(minLength: 0)
            pill()
        }
    }
}
