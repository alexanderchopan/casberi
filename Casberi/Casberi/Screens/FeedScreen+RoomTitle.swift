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

    /// The room's title row. On the phone it names the walk's neighbours
    /// (prd §1207 item 2): the stop before in grey, where you stand in pink
    /// (with its pick), the stop after in grey, each grey word pressable.
    @ViewBuilder
    var roomTitle: some View {
        if let walk = walkNeighbours {
            DSWalkTitleRow(before: walk.before.map(Self.walkWord),
                           title: roomName,
                           pick: roomPick,
                           after: walk.after.map(Self.walkWord)) { forward in
                chrome.sourceRequest = forward ? walk.after : walk.before
            }
        } else {
            DSRoomTitleRow(title: roomName, pick: roomPick)
        }
    }

    /// The stops either side of this page in the phone's walk, or nil off
    /// the walk and wherever the rail stands.
    private var walkNeighbours: (before: String?, after: String?)? {
        // A page risen as a sheet (prd §1208l) stands on nothing: its own
        // name alone, and the pull closes it.
        guard roomScopeInRoom, !inSheet else { return nil }
        // Notes and Markets are the Feed's own places (prd §1208c, user: "to
        // get back to feed its complicated"): the Feed stands before them,
        // pressable, and nothing after.
        if HomeScope.contains(source), source != "All" { return ("All", nil) }
        let walk = HomeScope.phoneWalk(chips: chrome.chipOrder)
        guard let i = walk.firstIndex(of: HomeScope.walkStop(source)) else { return nil }
        return (i > 0 ? walk[i - 1] : nil, i + 1 < walk.count ? walk[i + 1] : nil)
    }

    /// A stop's word in the title: the Feed for "All", else its category.
    private static func walkWord(_ stop: String) -> String {
        stop == "All" ? String(localized: "Feed") : stop
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
