import SwiftUI

/// **A LIST'S GROUP HEADER, NAMED BY SOMETHING OTHER THAN TIME (prd §940,
/// §944).** The feed's day header in primary ink (a day wears the brand hue,
/// §740; a group does not), standing on the tiles' edge — text is a box, so it
/// takes the line the tiles and the account menu share. Its own `List` row.
/// The rung is the day header's own, `heading20` semibold (prd §1413, user:
/// "those 'needs you' section titles are really large … they should be the
/// same like 'today'"); it had drifted a rung up.
struct DSGroupHeader: View {
    let word: String

    var body: some View {
        Text(word)
            .dsText(.heading20)
            .foregroundStyle(DS.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            // The rows' own column (prd §1387): "Today" and the marks stand there.
            .padding(.leading, DSRoomChassis.rowInset)
            .padding(.top, DS.Space.s6)
            .padding(.bottom, DS.Space.s1)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .accessibilityAddTraits(.isHeader)
    }
}
