import SwiftUI

/// A pushed screen's name, in its content (prd §767).
///
/// The system's large title stood at the top edge at 34pt, beside a back
/// chevron, while no room has a title at all and a room's sections are named at
/// `heading24` (§764). A screen like Settings is one section, so its name takes
/// the section rung, sits in the rows' column and scrolls away with them.
struct DSScreenHead: View {
    let title: Text

    var body: some View {
        title
            .dsText(.heading24)
            .foregroundStyle(DS.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}
