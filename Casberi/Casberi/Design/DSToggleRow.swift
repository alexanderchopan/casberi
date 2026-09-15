import SwiftUI

/// **THE SETTING ROW — a switch with the sentence that says what it costs
/// (prd §715, 2026-09-13).**
///
/// `DSSlabSwitch` is the setup-screen slab: a 56pt gray block whose detail is
/// one `label12` line. Every SETTING in a List needed the other shape — a
/// title, a wrapping sentence under it, the switch — and eleven places drew
/// it by hand at two title rungs. This is that shape, with no fill and no
/// insets, so it sits in a `dsListCardRow` or a sheet column alike.
///
/// `detailTone` carries a row's own verdict (a failing sync reads red) on the
/// line that states the fact, never on a badge beside it.
struct DSToggleRow: View {
    let title: Text
    var detail: Text? = nil
    var detailTone: Color = DS.textTertiary
    @Binding var isOn: Bool
    var tint: Color = DS.tint

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                title
                    .dsText(.body17).fontWeight(.medium)
                    .foregroundStyle(DS.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    detail
                        .dsText(.subhead12)
                        .foregroundStyle(detailTone)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .tint(tint)
    }
}
