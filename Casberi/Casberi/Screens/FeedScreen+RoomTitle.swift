import SwiftUI

// THE ROOM'S TITLE NAMES WHERE YOU ARE, AND PRESSES NOTHING (prd §1133, user:
// "ok, i like this direction"; amends §1127–§1129).
//
// Mail's shape: the face opens the tray, which says WHERE (a category, an app
// or account in it, You's places), and the tiles say WHAT (Home, Holdings…).
// The pill that picked an app or a You place in the title row is deleted from
// every room; the title reads "Category · Pick" once something is picked, so
// the row is one height picked or not, and you change the pick from the tray.

/// The title row of a You place that is a screen (Apps, Addresses,
/// Settings): the category's name and the place, where the screen's own name
/// stood (prd §1129).
struct YouHead: View {
    let place: HomeScope.Place

    var body: some View {
        DSRoomTitleRow(title: HomeScope.title, pick: place.name)
    }
}

extension HomeScope.Place {
    /// The place's word, as the tray's You folder draws it.
    var name: String {
        switch self {
        case .apps: String(localized: "Apps")
        case .addresses: String(localized: "Addresses")
        case .settings: String(localized: "Settings")
        }
    }
}

extension FeedScreen {
    /// What the title names after the category's dot, or nil while the room
    /// shows everything (prd §1133): You's place (Home is a place, so You
    /// always names one), the app or account picked, or the network the
    /// Testnets room is showing.
    var roomPick: String? {
        if HomeScope.contains(source) {
            if Pinboard.isPinnedRoom(source) { return String(localized: "Notes") }
            if HomeScope.isMarkets(source) { return String(localized: "Markets") }
            return String(localized: "Home")
        }
        if let rail = chrome.accountRail,
           rail.source == source || source == RoomAccounts.testnetsRoom,
           let slot = rail.slots.first(where: { !$0.id.isEmpty && $0.isShowing(rail.scope) }) {
            return slot.name
        }
        if mergedMenuDraws, let seat = selectedSeat { return seat.name }
        if let host = hostRoom, host != source { return BridgeCatalog.seatName(forSource: source) }
        return nil
    }

    #if DEBUG
    /// The Notes room's probes, which rode the deleted pill's mount.
    var notesProbeHook: some View {
        Color.clear.frame(width: 0, height: 0)
            .task { if Pinboard.isPinnedRoom(source) { notesProbe() } }
    }
    #endif
}
