import SwiftUI

/// THE ROOM'S FRAME, ONE TEMPLATE (prd §1136f, user: "the box should never
/// move down!"; "everything should always be in the same place on every
/// screen!"; "you shouldn't be handrolling"; "it should be a template").
///
/// Every room and every place in You draws its top as three list rows — the
/// title, the box, the tiles — in a list styled once. Sources hand-rolled
/// the same three in a scroll view, matched to the feed by measurement, and
/// drifted by a few points the moment the title's length changed. Through
/// these the rows are the SAME rows, so the box and the tiles stand at one y
/// on every screen by construction, never by measurement.
extension View {
    /// The list every room draws in.
    func dsRoomList() -> some View {
        listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListHeaderHeight, 0)
            .environment(\.defaultMinListRowHeight, 0)
            .scrollIndicators(.hidden)
    }

    /// The title row: the room's name in the rows' column. The demo's pill
    /// reserves its band above it (prd §1005).
    func dsRoomTitleListRow() -> some View {
        listRowInsets(.init(top: DS.Space.s2 + DSDemoMark.screenClearance,
                            leading: DSRoomChassis.inset,
                            bottom: 0, trailing: DSRoomChassis.inset))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    /// The box's row: the lead at its one size (prd §760), the box's gap under
    /// it (prd §1102: an empty room's tiles stand where a full room's do).
    func dsRoomLeadListRow() -> some View {
        listRowInsets(.init(top: DS.Space.s2, leading: DSRoomChassis.inset,
                            bottom: DSRoomChassis.leadGap, trailing: DSRoomChassis.inset))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    /// THE ROOM'S BOX OUTSIDE A LIST (prd §1179): a thing sheet's card at a
    /// room's one size — `leadBox` inside the head's well, in the rows'
    /// column — so a sheet's card and a room's box are the same box, never a
    /// second one drawn to match. What does not fit is clipped: the box never
    /// grows (§760), the rest of the sheet carries the overflow.
    func dsRoomBox() -> some View {
        frame(maxWidth: .infinity, minHeight: DSRoomChassis.leadBox,
              maxHeight: DSRoomChassis.leadBox, alignment: .topLeading)
            .clipped()
            .dsRoomHeadBlock()
            .padding(.horizontal, DSRoomChassis.inset)
    }

    /// The tiles' row, straight under the box.
    func dsRoomTilesListRow() -> some View {
        listRowInsets(.init(top: 0, leading: DSRoomChassis.inset,
                            bottom: DSRoomChassis.leadGap, trailing: DSRoomChassis.inset))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}
