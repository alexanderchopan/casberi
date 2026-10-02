import SwiftUI

// THE ACCOUNT MENU OF A MERGED ROOM THAT DRAWS NO SCREEN OF ITS OWN
// (prd §1049, §1050d, built §1050m). Reading first; Agents, Media, Life, Day
// and Work follow. The Wallet keeps its own menu (addresses and apps), and
// Testnets crosses networks from each network's menu (§1050k). A pick
// narrows the list to that app (`selectedSeat`, through `walletScopeAllows`)
// and the box to that app's own head, or to its newest row.
extension FeedScreen {
    /// The apps the menu lists: the room's connected ones, and only once
    /// there are two to choose between.
    var mergedMenuSeats: [RoomAccounts.Seat] {
        guard source != CategoryFold.walletRoom, RoomAccounts.mergedRooms.contains(source)
        else { return [] }
        let seats = RoomAccounts.connected(in: source, names: connectedSeatNames)
            .filter { !$0.ownScreen }
        return seats.count > 1 ? seats : []
    }

    var mergedMenuDraws: Bool { !mergedMenuSeats.isEmpty }

    /// The menu, under the lead in the rows' column — `sourceScopeMenu`'s
    /// placement, on every size class, as the Wallet's is.
    @ViewBuilder
    var mergedRoomMenu: some View {
        let seats = mergedMenuSeats
        let all = DSAccountSlot(id: "", name: String(localized: "All apps"), sub: nil,
                                faces: seats.prefix(2).map { .mark(url: nil, source: $0.mark) })
        let slots = [all] + seats.map { seat in
            DSAccountSlot(id: RoomAccounts.scopeID(seat), name: seat.name, sub: nil,
                          faces: [.mark(url: nil, source: seat.mark)])
        }
        let picked = selectedSeat.map(RoomAccounts.scopeID)
        let showing = slots.first { !$0.id.isEmpty && $0.id == picked } ?? all
        let room = source
        Section {
            DSScopeMenu(slots: slots, showing: showing,
                        spoken: { String(localized: "Showing: \($0)") },
                        onPick: { id in
                            withAnimation(DS.Motion.standard) {
                                chrome.mergedScope[room] = (id?.isEmpty ?? true) ? nil : id
                            }
                        })
                .frame(maxWidth: .infinity, alignment: .leading)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: DSRoomChassis.inset,
                                          bottom: DSRoomChassis.leadGap,
                                          trailing: DSRoomChassis.inset))
        }
    }
}
