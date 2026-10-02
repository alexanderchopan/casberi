import SwiftUI

// WHOSE FEED THIS IS, IN THE ROOM (prd §959).
//
// On the phone the band under the face carried a capsule of faces after §930
// took away the dock strip it had belonged to, so it read as a leftover. The
// wallet family had already moved its pick into the room (§936). The social
// rooms follow: the control stands under the room's lead, in the rows'
// column, and scrolls with the feed. They pick a PERSON whose own face, and
// the ring saying they posted since you looked, is the news: a row of faces
// (`FaceScopeRail`, standing alone). iPad and Mac keep the shell's rail. A
// merged room picks its app from the title row's pill (`titleAccountsPill`,
// prd §1066). (GitHub's and Pinterest's
// pull-downs left with their rooms, prd §1060.)
extension FeedScreen {
    /// The phone. Everywhere the shell's rail stands, the band keeps the faces.
    var roomScopeInRoom: Bool { roomSizeClass != .regular }

    /// A scope is picked in a room whose control now lives in the room, so an
    /// empty result must keep the room (and the control) rather than hand it
    /// to the generic empty state — whose only door leaves the room (§538).
    var roomScopePicked: Bool {
        if mergedMenuDraws && selectedSeat != nil { return true }
        guard roomScopeInRoom else { return false }
        return SocialRoom.hasRoster(source) && chrome.personScope != nil
    }

    /// **THE ACCOUNTS PILL, IN THE TITLE ROW (prd §1066).** A merged room's
    /// apps, or the wallet family's accounts from the rail its chrome
    /// publishes (`ShellChrome.accountRail`) — the Testnets room hosts a
    /// network's chrome, so its rail is a network's source, not the room's.
    /// Nothing where there is nothing to pick between.
    @ViewBuilder
    var titleAccountsPill: some View {
        if mergedMenuDraws {
            mergedAccountsPill
        } else if let rail = chrome.accountRail, rail.slots.count > 1,
                  rail.source == source || source == RoomAccounts.testnetsRoom {
            let showing = rail.slots.first { $0.isShowing(rail.scope) } ?? rail.slots[0]
            DSScopeMenu(slots: rail.slots, showing: showing, onPick: rail.onPick)
        }
    }

    /// The control, as its own List section. Draws nothing where the room
    /// has nothing to pick between, or off the phone.
    @ViewBuilder
    var roomScopeSection: some View {
        if roomScopeInRoom, SocialRoom.hasRoster(source) {
            socialFaceRow
        }
    }

    /// The social room's people: at most eight faces, the most recent poster
    /// first, the rest behind `+N` (prd §824) — the rail's own rules, standing
    /// in the room instead of the band.
    @ViewBuilder
    private var socialFaceRow: some View {
        let accounts = SocialRoomSource.accounts(for: source)
        if SocialScopeRail.shows(source: source, accounts: accounts.count) {
            let visible = SocialScopeRail.visible(accounts, recent: chrome.recentHandles,
                                                  scope: chrome.personScope)
            let room = source
            Section {
                FaceScopeRail(
                    items: SocialScopeRail.items(visible.shown, source: room,
                                                 fresh: chrome.freshHandles),
                    scope: chrome.personScope,
                    compact: false,
                    matches: SocialScopeRail.matches,
                    onPick: { picked in
                        withAnimation(DS.Motion.standard) { chrome.personScope = picked }
                    },
                    // Re-tapping the lit face opens that person's own room, as
                    // it did in the band (`MainSurface.socialScopeRail`).
                    onReTap: { item in
                        chrome.personRequest = SocialProfile(
                            source: room, handle: item.id,
                            displayName: item.caption, bio: nil,
                            avatarURL: {
                                if case .avatar(let url, _) = item.face { return url }
                                return nil
                            }())
                    },
                    more: visible.hidden,
                    onMore: { feedSheet = .socialFaces })
                // The rail pads its own `s4`; the row gives it the screen's
                // width so the strip scrolls edge to edge.
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: 0,
                                          bottom: DSRoomChassis.leadGap - DS.Space.s1,
                                          trailing: 0))
            }
        }
    }

    /// The `+N` tray, presented through the screen's one sheet.
    var socialFacesTray: some View {
        SocialFacesTray(accounts: SocialRoomSource.accounts(for: source), source: source,
                        scope: chrome.personScope) { picked in
            withAnimation(DS.Motion.standard) { chrome.personScope = picked }
        }
    }
}
