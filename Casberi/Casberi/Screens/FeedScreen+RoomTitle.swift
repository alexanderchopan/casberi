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
/// Settings): the place alone, in pink (prd §1156, amending §1129 — your
/// name lives on the tray's You row, so the title's first word is always
/// pink and always says where you are).
struct YouHead: View {
    let place: HomeScope.Place

    var body: some View {
        DSRoomTitleRow(title: place.name)
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
    /// You's place as the title's own word (prd §1156): Home, Notes or
    /// Markets, never your name before it.
    var youPlaceName: String {
        if Pinboard.isPinnedRoom(source) { return String(localized: "Notes") }
        if HomeScope.isMarkets(source) { return String(localized: "Markets") }
        // "Today" until prd §1203: beside "Wallet" it named a time where the
        // other named a place, and said your money was not part of your day.
        return String(localized: "Feed")
    }

    /// The room's title row: the two poles' title on the phone's Feed and
    /// unpicked Wallet (prd §1203 item 5), else the category and its pick.
    @ViewBuilder
    var roomTitle: some View {
        if let walletStands = poleStanding {
            DSPoleTitleRow(walletStands: walletStands) {
                chrome.sourceRequest = walletStands ? "All" : CategoryFold.walletRoom
            }
        } else {
            DSRoomTitleRow(title: roomName, pick: roomPick)
        }
    }

    /// Which pole this page is on the phone — true for the Wallet, false for
    /// the Feed — or nil anywhere else, a picked Wallet included: "Wallet ·
    /// Safe" is a level in, and names itself.
    private var poleStanding: Bool? {
        guard roomScopeInRoom, roomPick == nil else { return nil }
        if source == "All" { return false }
        if source == CategoryFold.walletRoom { return true }
        return nil
    }

    /// What the title names after the category's dot, or nil while the room
    /// shows everything (prd §1133): the app or account picked, or the
    /// network the Testnets room is showing. You's places name themselves
    /// (`youPlaceName`, §1156), so they pick nothing.
    var roomPick: String? {
        if HomeScope.contains(source) { return nil }
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
