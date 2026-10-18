import SwiftUI

/// **ONE DOOR TO THE REST OF A LIST (prd §1386, the 2026-10-17 design audit,
/// finding 2: "More" had three bodies).** A capped list ends in one row:
/// grey words and a chevron, at the rows' own inset, a full target tall,
/// whether it adds rows in place ("More from Notes"), opens the whole list
/// ("See all 11") or folds it back ("Show fewer", no chevron: it goes
/// nowhere). Never centred, never on a disc, never in the tint: a door is a
/// place to go, not a thing that is on (prd §1385). `DSMoreLink` stays for
/// the small count-link beside a label; a row under a list is this.
struct DSMoreRow: View {
    let title: Text
    var opens = true
    let action: () -> Void

    var body: some View {
        Button {
            DSHaptic.selection()
            action()
        } label: {
            HStack(spacing: DS.Space.s1) {
                title
                    .dsText(.body17)
                    .monospacedDigit()
                    .lineLimit(1)
                if opens {
                    Image(systemName: "chevron.right")
                        .dsGlyph(.caption, weight: .semibold)
                        .accessibilityHidden(true)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(DS.textSecondary)
            .frame(minHeight: DS.Hit.min)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        .dsHover()
    }
}
