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
        // Activity since prd §1807 ("Feed" from §1203, "Today" before it):
        // what happened, beside Home, what you have.
        return PlaceTab.feed.label
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
                           onSettings: appSettings, root: titleRoot)
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

    /// **THE TITLE IS THE WHOLE PATH (prd §1813, amending §1812's last
    /// three).** The hierarchy is Home, Activity, an app: a category is a
    /// word on Activity and has no page. An app's page reads "Home ·
    /// Activity · App Store Connect"; a door taken on it reads "Activity ·
    /// App Store Connect · Coming up", where Home is the bar's own seat.
    /// Each grey name goes to its page. Nil on Home's own pages and on
    /// Activity, which already lead with Home.
    var titleRoot: DSTitleBack? {
        guard pageUnderActivity, roomPick != nil, clearRoomPick != nil else { return nil }
        let room = hostRoom ?? source
        // The middle name is Activity: the root is Home.
        if roomName == PlaceTab.feed.label {
            return DSTitleBack(word: PlaceTab.wallet.label) {
                DSHaptic.selection()
                withAnimation(DS.Motion.standard) {
                    // Home, not the category you left Activity from.
                    chrome.activityReturn = nil
                    chrome.mergedScope[room] = nil
                    chrome.openWallet()
                }
            }
        }
        // The middle name is an app (a door taken on its page) or Notes (a
        // folder): the root is Activity.
        let scope = pageScope
        return DSTitleBack(word: PlaceTab.feed.label) {
            DSHaptic.selection()
            withAnimation(DS.Motion.standard) {
                scope?.clear()
                chrome.mergedScope[room] = nil
                chrome.notesFolder = nil
                chrome.sourceRequest = "All"
            }
        }
    }

    /// The title's category word pressed: drop the pick `roomPick` names and
    /// show the whole category (prd §1262), as the tray's category row does.
    /// Nil wherever the pick is not one to drop: You's places, and a network
    /// the Testnets room stands on (it has no view across networks).
    var clearRoomPick: (() -> Void)? {
        guard roomPick != nil else { return nil }
        // A door taken on a page (prd §1812): the page's name goes back to
        // the whole of it.
        if let scope = pageScope {
            return {
                DSHaptic.selection()
                withAnimation(DS.Motion.standard) { scope.clear() }
            }
        }
        // "Home · Activity": Home goes home (prd §1809).
        if activityUnderHome {
            return {
                DSHaptic.selection()
                withAnimation(DS.Motion.standard) { chrome.openWallet() }
            }
        }
        // "Activity · Bluesky": Activity goes back to Activity, where you
        // were in it (no return to the top), the one step an app's page
        // stands from it (prd §1813). Notes narrowed to a folder or an app
        // goes back to Notes first, below.
        if pageUnderActivity, !(Pinboard.isPinnedRoom(source) && notesNarrowed) {
            let room = hostRoom ?? source
            return {
                DSHaptic.selection()
                withAnimation(DS.Motion.standard) {
                    chrome.mergedScope[room] = nil
                    chrome.sourceRequest = "All"
                }
            }
        }
        // An open Notes folder: "Notes" goes back to the folders (prd §1312).
        if Pinboard.isPinnedRoom(source), openNotesFolderName != nil {
            return {
                DSHaptic.selection()
                withAnimation(DS.Motion.standard) { chrome.notesFolder = nil }
            }
        }
        // A page or an app's pick that Activity opened goes back there, a pick
        // and all (prd §1826).
        if walletBacksToActivity {
            return {
                DSHaptic.selection()
                withAnimation(DS.Motion.standard) { chrome.walletGoBack() }
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
        // The private account's page goes back to Account (prd §1786).
        if walletOnPrivateAccountPage {
            return {
                DSHaptic.selection()
                withAnimation(DS.Motion.standard) { chrome.yourAccountShowsAztec = false }
            }
        }
        if source == CategoryFold.walletRoom, selectedSeat == nil,
           let section = chrome.walletSection, section != .home {
            // A page goes back to where you opened it (prd §1826, amending
            // §1480 item 9's fixed map): Needs you to Activity, Following
            // to Account, Tokens to Holdings (`ShellChrome.walletBackStep`).
            return {
                DSHaptic.selection()
                withAnimation(DS.Motion.standard) { chrome.walletGoBack() }
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

    /// **THE SWIPE RIGHT IS THE TITLE'S WAY BACK (prd §1814).** The word a
    /// swipe right goes back to inside this room, on the phone: the name
    /// `clearRoomPick` is pressed on. Nil where the way back leaves the room
    /// (Activity to Home, a page to Activity), which the pager walks.
    var pageBackWord: String? {
        guard roomSizeClass == .compact, !inSheet, clearRoomPick != nil else { return nil }
        if pageScope == nil {
            if activityUnderHome { return nil }
            if pageUnderActivity, !(Pinboard.isPinnedRoom(source) && notesNarrowed) { return nil }
            // A Wallet page opened from Activity: another place, which the
            // pager walks to (prd §1826).
            if walletBacksToActivity { return nil }
        }
        return roomName
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
        if Pinboard.isPinnedRoom(source) {
            // "Activity · Notes" on the phone; a folder or an app picked
            // reads "Notes · Books", as before.
            return openNotesFolderName ?? selectedSeat?.name
                ?? (pageUnderActivity ? String(localized: "Notes") : nil)
        }
        if activityUnderHome { return PlaceTab.feed.label }
        if HomeScope.contains(source) { return nil }
        // A door taken on a page names itself last (prd §1812).
        if let scope = pageScope { return scope.label }
        // The page at Activity's place: the app picked, else the category.
        if pageUnderActivity { return selectedSeat?.name ?? BridgeCatalog.seatName(forSource: hostRoom ?? source) }
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
            if walletOnPrivateAccountPage { return String(localized: "Private account") }
            // A token's page is named by the token (prd §1632 item 5).
            if section == .watchedToken, let token = Watchlist.shared.token(chrome.watchedTokenID) {
                return token.symbol
            }
            return section.label
        }
        return nil
    }

    /// Activity on the phone, titled under Home (prd §1809). The rail's
    /// layouts keep "Activity": their places stand side by side in the rail.
    var activityUnderHome: Bool {
        source == "All" && !inSheet && roomSizeClass == .compact
    }

    /// A category or an app standing as a page at Activity's place on the
    /// phone (prd §1809, `ShellChrome.pageRoom`).
    ///
    /// Every page off Home and Activity reads this way, Notes and Testnets
    /// included: with no bar (§1809) the title's first word is the way back.
    var pageUnderActivity: Bool {
        roomSizeClass == .compact && !inSheet && source != "All"
            && (hostRoom ?? source) != CategoryFold.walletRoom && !HomeScope.isMarkets(source)
    }

    /// Notes showing one folder or one app's notes.
    var notesNarrowed: Bool { openNotesFolderName != nil || selectedSeat != nil }

    /// The Wallet on the screen goes back to Activity (prd §1826): a page,
    /// or an app's pick on Home, that Activity opened. The title's word, its
    /// press and the swipe right all read this one fact.
    var walletBacksToActivity: Bool {
        source == CategoryFold.walletRoom && pinnedWalletSection == nil && !inSheet
            && !walletOnPrivateAccountPage && chrome.walletBacksToActivity
    }

    /// The Wallet's Account page is showing the private account's own page.
    var walletOnPrivateAccountPage: Bool {
        source == CategoryFold.walletRoom && pinnedWalletSection == nil && selectedSeat == nil
            && chrome.walletSection == .yourAccount && walletOnPrivateAccount
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
