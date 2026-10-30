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
            .demoTagOnTitle()
    }
}

extension HomeScope.Place {
    /// The place's word, as the tray's You folder draws it.
    var name: String {
        switch self {
        case .apps: String(localized: "Apps")
        case .settings: String(localized: "Settings")
        case .move: String(localized: "Move")
        }
    }
}

extension FeedScreen {
    /// You's place as the title's own word (prd §1156): Home or Notes,
    /// never your name before it (Markets is the Wallet's tile, §1337).
    var youPlaceName: String {
        if Pinboard.isPinnedRoom(source) { return String(localized: "Notes") }
        // "Today" until prd §1203: beside "Wallet" it named a time where the
        // other named a place, and said your money was not part of your day.
        return String(localized: "Feed")
    }

    /// The room's title row: the room's name, and its pick after a dot
    /// ("Wallet · Markets", "Notes · Books"), the name grey and pressable
    /// back to the whole room (prd §1262).
    ///
    /// **THE WALK'S TITLE IS DELETED (prd §1337).** Since the five tabs
    /// (§1327 item 5) Markets was the one page that still named a stop
    /// before it ("Wallet · Markets", §1325, the Wallet pressable back);
    /// Markets is the Wallet's own tile now, drawn in place, so it reads the
    /// same through `roomPick`, and `walkNeighbours`, `DSWalkTitleRow` and
    /// the walk's arms went with it.
    var roomTitle: some View {
        HStack(spacing: DS.Space.s3) {
            DSRoomTitleRow(title: roomName, pick: roomPick, onTitle: clearRoomPick,
                           onSettings: appSettings)
                .demoTagOnTitle()
            // THE ACCOUNTS ARE A MENU ON THE TITLE where the rail stands (prd
            // §1405): the strip that floated over the rows in the band is
            // gone, and the Mac has no tray to pick from (§1402).
            accountTitleMenu
            peopleTitleMenu
        }
    }

    /// A social room's people beside the title (prd §1407), where the rail
    /// stands: Everyone, then each account the room is made of, the one
    /// showing ticked; a pick narrows the room as the band's faces did
    /// (§362). Regular width only; the phone keeps its faces under the cover.
    @ViewBuilder
    var peopleTitleMenu: some View {
        if roomSizeClass == .regular {
            let accounts = SocialRoomSource.accounts(for: source)
            if SocialScopeRail.shows(source: source, accounts: accounts.count) {
                let showing = accounts.first { chrome.personScope == $0.key }
                Menu {
                    Button {
                        DSHaptic.selection()
                        withAnimation(DS.Motion.standard) { chrome.personScope = nil }
                    } label: {
                        if chrome.personScope == nil { Label("Everyone", systemImage: "checkmark") }
                        else { Text("Everyone") }
                    }
                    Divider()
                    ForEach(accounts, id: \.key) { account in
                        Button {
                            DSHaptic.selection()
                            withAnimation(DS.Motion.standard) { chrome.personScope = account.key }
                        } label: {
                            if chrome.personScope == account.key {
                                Label(account.title, systemImage: "checkmark")
                            } else {
                                Text(verbatim: account.title)
                            }
                        }
                    }
                } label: {
                    Chip(text: showing?.title ?? String(localized: "Everyone"), glyph: "chevron.down")
                }
                .buttonStyle(PressSpring())
                .fixedSize()
                .accessibilityLabel(Text("People"))
            }
        }
    }

    /// The wallet family's accounts beside the title (prd §1405): every slot
    /// the room published, the act it leads with (Follow a wallet), the one
    /// showing ticked. Regular width only; the phone picks from the tray.
    @ViewBuilder
    var accountTitleMenu: some View {
        if roomSizeClass == .regular, !HomeScope.contains(source),
           let rail = chrome.accountRail, rail.source == source, rail.slots.count > 1 {
            let showing = rail.slots.first { $0.isShowing(rail.scope) }
            Menu {
                if let action = rail.action {
                    Button(action: action.run) { Label(action.title, systemImage: action.symbol) }
                    Divider()
                }
                ForEach(rail.slots) { slot in
                    Button {
                        DSHaptic.selection()
                        rail.onPick(slot.id.isEmpty ? nil : slot.id)
                    } label: {
                        if slot.isShowing(rail.scope) {
                            Label(slot.name, systemImage: "checkmark")
                        } else {
                            Text(verbatim: slot.name)
                        }
                    }
                }
            } label: {
                Chip(text: showing?.name ?? String(localized: "All accounts"), glyph: "chevron.down")
            }
            .buttonStyle(PressSpring())
            .fixedSize()
            .accessibilityLabel(Text("Accounts"))
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
            // A page goes back to the page it opened from (prd §1480 item 9):
            // Tokens to Holdings, Places to Spending, Home's doors to Home.
            return {
                DSHaptic.selection()
                withAnimation(DS.Motion.standard) { chrome.walletSection = section.parent ?? .home }
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

    /// **AN APP'S SETTINGS ARE ON ITS PAGE (prd §1444, user: "the settings
    /// should be in the library somehow or on the apps actual feed page").**
    /// The app the title names, pressed, opens its account page, the one its long
    /// press's Settings opens (`RoomsTray.appItem`, `AppMenu`). Nil unless
    /// it IS an app: a category, an address, a Notes folder or a Wallet tile
    /// keeps the title a label.
    var appSettings: (() -> Void)? {
        let name: String
        let seatSource: String
        if let pick = roomPick {
            if let seat = selectedSeat, seat.name == pick, openNotesFolderName == nil {
                name = seat.name
                seatSource = seat.source ?? seat.name
            } else if let host = hostRoom, host != source,
                      pick == BridgeCatalog.seatName(forSource: source) {
                name = pick
                seatSource = source
            } else {
                return nil
            }
        } else {
            // An app's own page: the room IS the app (Library's tap, §1418).
            guard hostRoom == nil, pinnedWalletSection == nil, !HomeScope.contains(source),
                  !Pinboard.isPinnedRoom(source), !RoomAccounts.mergedRooms.contains(source)
            else { return nil }
            name = roomName
            seatSource = source
        }
        guard let id = bridges.bridges.first(where: { $0.name == name || $0.id == seatSource })?.id
                ?? BridgeRouter.id(forOffer: name) else { return nil }
        return {
            DSHaptic.selection()
            route.settingsFromApp = name
            route.openAccount(BridgeRouter.destination(forID: id))
        }
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
        // **AN APP PICKED IN THE WALLET IS NAMED ON EVERY TILE (prd §1618 item
        // 10, user: "is the app pages name in the header on all their
        // pages?").** "Wallet · Privy" on Home and on Holdings, Activity and
        // Spending alike; the lit tile says which page. A pushed page keeps
        // its own name.
        if source == CategoryFold.walletRoom, pinnedWalletSection == nil, let seat = selectedSeat {
            return seat.name
        }
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
