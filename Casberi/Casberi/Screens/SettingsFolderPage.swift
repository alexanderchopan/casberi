import SwiftUI

/// **CASBERI'S SETTINGS, AS A LIST IN THE PANE (prd §1400).** On the phone
/// the folder springs open over Library as tiles (§1321); where Library has
/// a pane the same rows stand in it, one per setting, the colophon under
/// them — Mail's shape, not a card over the list. A row's page stacks on
/// this one (`SettingsRows.open`), so Back returns to the folder.
struct SettingsFolderPage: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                DSScreenHead(title: Text(verbatim: "Casberi"))
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.top, DS.Space.s6)
                SettingsRows(style: .rows)
                    .padding(.horizontal, DS.Space.s4)
            }
            .padding(.bottom, DS.Space.s8)
        }
        .scrollIndicators(.hidden)
        .environment(\.dsInPane, true)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(DS.surfaceSheet.ignoresSafeArea())
    }
}
