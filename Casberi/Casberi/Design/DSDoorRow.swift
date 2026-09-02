import SwiftUI

/// **THE DOOR ROW — a way out of a sheet, drawn once (prd §560, 2026-09-01).**
///
/// Three wallet sheets each carried a private `doorRow(icon:label:action:)`
/// with the same signature: `ENSRenewCard`, `SafeQueueCard` and
/// `ApprovalPrepareCard`. Two of the three were byte-identical apart from a
/// `.dsHover()`; the third set its glyph two points larger, dropped the icon
/// column and painted the whole row `DS.tint`.
///
/// **The tinted one is the drift, and this settles it toward the other two.**
/// A row painted entirely in the accent colour is web-footer grammar — it
/// reads as a link, and §480 already named "three blue links in a row" as a
/// fault on the sheet next door. A door here is a ROW: a secondary icon in a
/// fixed column so the labels align down the sheet, and the label in primary
/// ink because it is the thing you are reading, not a citation of it. The
/// accent survives where it means something — a verb tile, a real link out.
///
/// `DSSlabDoor` is the sibling and NOT the same object: it is §190's connect-
/// screen slab, a tall tinted card that `connect-shape-audit.py` enforces on
/// setup pages, and ~20 pushed screens draw it. This is the small one, for a
/// sheet whose content is a reading and whose doors sit under it.
///
/// Honesty (§83): the row is a `Button` with a `contentShape`, so its whole
/// width is the target — a door that only answers on its 18pt glyph is a
/// control that mostly does nothing.
struct DSDoorRow: View {
    /// The SF Symbol naming where this goes — an explorer, a settings page, a
    /// copy. It sits in a fixed-width column so a run of doors aligns.
    let icon: String
    let label: LocalizedStringKey
    let act: () -> Void

    var body: some View {
        Button(action: act) {
            HStack(spacing: DS.Space.s2) {
                Image(systemName: icon)
                    .dsGlyph(13, weight: .regular)
                    .foregroundStyle(DS.textSecondary)
                    // The column, not the glyph's own width: SF Symbols are
                    // not uniform, so without it a stack of doors staircases.
                    .frame(width: 18, alignment: .center)
                Text(label)
                    .dsText(.callout15)
                    .foregroundStyle(DS.textPrimary)
                Spacer(minLength: 0)
            }
            .padding(.vertical, DS.Space.s1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dsHover()
    }
}
