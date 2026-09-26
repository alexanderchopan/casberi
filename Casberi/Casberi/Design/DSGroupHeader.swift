import SwiftUI

/// **A LIST'S GROUP HEADER, NAMED BY SOMETHING OTHER THAN TIME (prd §940,
/// §944).** The feed's day header in primary ink (a day wears the brand hue,
/// §740; a group does not), standing on the tiles' edge — text is a box, so it
/// takes the line the tiles and the account menu share. Its own `List` row.
struct DSGroupHeader: View {
    let word: String

    var body: some View {
        Text(word)
            .dsText(.heading24)
            .foregroundStyle(DS.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, DSRoomChassis.inset)
            .padding(.top, DS.Space.s6)
            .padding(.bottom, DS.Space.s1)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .accessibilityAddTraits(.isHeader)
    }
}
