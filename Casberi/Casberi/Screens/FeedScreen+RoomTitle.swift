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
        // A PAGE OPENED FROM THE FEED READS "Feed · Day" (prd §1321, user:
        // "why do we have a dot between some titles and not others"): the
        // dot means inside or opened from, so Day and Notes take it and
        // "Feed" goes back; Markets is a Wallet tile (prd §1232), so it reads
        // "Wallet · Markets" and "Wallet" goes back. Only the two pages you
        // swipe between, Feed and Wallet, stand side by side without one. A
        // pick inside the page ("Notes · Books") names the page and its pick
        // instead.
        if let walk = walkNeighbours, walk.after == nil, let parent = walk.before,
           parent == "All" || parent == CategoryFold.walletRoom, roomPick == nil {
            DSRoomTitleRow(title: Self.walkWord(parent), pick: roomName) {
                DSHaptic.selection()
                chrome.sourceRequest = parent
            }
        } else if let walk = walkNeighbours {
            DSWalkTitleRow(before: walk.before.map(Self.walkWord),
                           title: roomName,
                           pick: roomPick,
                           onTitle: clearRoomPick,
                           after: walk.after.map(Self.walkWord)) { forward in
                chrome.sourceRequest = forward ? walk.after : walk.before
            }
        } else {
            DSRoomTitleRow(title: roomName, pick: roomPick, onTitle: clearRoomPick)
        }
    }

    /// The title's category word pressed: drop the pick `roomPick` names and
    /// show the whole category (prd §1262), as the tray's category row does.
    /// Nil wherever the pick is not one to drop: You's places, and a network
    /// the Testnets room stands on (it has no view across networks).
    var clearRoomPick: (() -> Void)? {
        guard roomPick != nil else { return nil }
        // An open Notes folder: "Notes" goes back to the folders (prd §1312).
        if Pinboard.isPinnedRoom(source), openNotesFolderName != nil {
            return {
                DSHaptic.selection()
                withAnimation(DS.Motion.standard) { chrome.notesFolder = nil }
            }
        }
        if !Pinboard.isPinnedRoom(source), let rail = chrome.accountRail,
           rail.source == source || source == RoomAccounts.testnetsRoom,
           rail.slots.contains(where: { !$0.id.isEmpty && $0.isShowing(rail.scope) }) {
            return {
                DSHaptic.selection()
                rail.onPick(nil)
            }
        }
        if source == CategoryFold.walletRoom, selectedSeat == nil,
           let section = chrome.walletSection, section != .home {
            return {
                DSHaptic.selection()
                withAnimation(DS.Motion.standard) { chrome.walletSection = .home }
            }
        }
        guard selectedSeat != nil else { return nil }
        let room = source
        return {
            DSHaptic.selection()
            withAnimation(DS.Motion.standard) {
                if room == CategoryFold.walletRoom {
                    chrome.walletScope = nil
                } else {
                    chrome.mergedScope[room] = nil
                }
            }
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
        // Day too, since it became a page beside the Feed (prd §1321).
        // Markets opens from the Wallet's tile (prd §1232), so the Wallet
        // stands before it.
        if HomeScope.isMarkets(source) { return (CategoryFold.walletRoom, nil) }
        if HomeScope.contains(source) || source == RoomAccounts.dayRoom, source != "All" { return ("All", nil) }
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
        // Notes names the open folder (prd §1312), else the app you picked
        // from the tray (prd §1235).
        if Pinboard.isPinnedRoom(source) { return openNotesFolderName ?? selectedSeat?.name }
        if HomeScope.contains(source) { return nil }
        if let rail = chrome.accountRail,
           rail.source == source || source == RoomAccounts.testnetsRoom,
           let slot = rail.slots.first(where: { !$0.id.isEmpty && $0.isShowing(rail.scope) }) {
            return slot.name
        }
        if mergedMenuDraws, let seat = selectedSeat { return seat.name }
        if let host = hostRoom, host != source { return BridgeCatalog.seatName(forSource: source) }
        // The Wallet's tile, now a page (prd §1321): "Wallet · Holdings".
        if source == CategoryFold.walletRoom, pinnedWalletSection == nil,
           let section = chrome.walletSection, section != .home {
            return section.label
        }
        return nil
    }

    /// The open Notes folder's name as the title draws it (a vault folder
    /// without its prefix), or nil when no folder is open.
    var openNotesFolderName: String? {
        guard chrome.notesScope == .folders, let open = chrome.notesFolder else { return nil }
        return open.hasPrefix(Pinboard.vaultPrefix) ? String(open.dropFirst(Pinboard.vaultPrefix.count)) : open
    }

    #if DEBUG
    /// The Notes room's probes, which rode the deleted pill's mount.
    var notesProbeHook: some View {
        Color.clear.frame(width: 0, height: 0)
            .task { if Pinboard.isPinnedRoom(source) { notesProbe() } }
    }
    #endif
}
