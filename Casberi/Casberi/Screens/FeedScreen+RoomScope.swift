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
        if socialPeopleRoom { return chrome.personScope != nil }
        guard roomScopeInRoom else { return false }
        return SocialRoom.hasRoster(source) && chrome.personScope != nil
    }

    /// Whether a person scope narrows this room's rows.
    var personScoped: Bool {
        chrome.personScope != nil && (SocialRoom.hasRoster(source) || socialPeopleRoom)
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
        } else if Pinboard.isPinnedRoom(source) {
            notesKindPill
        } else if let rail = chrome.accountRail, rail.slots.count > 1 || rail.action != nil,
                  rail.source == source || source == RoomAccounts.testnetsRoom,
                  let first = rail.slots.first {
            // A rail with an act draws even over one account (prd §1107): the
            // act is how the second one gets here.
            let showing = rail.slots.first { $0.isShowing(rail.scope) } ?? first
            DSScopeMenu(slots: rail.slots, showing: showing, action: rail.action,
                        onPick: rail.onPick)
        }
    }

    /// The control, as its own List section. Draws nothing where the room
    /// has nothing to pick between, or off the phone.
    @ViewBuilder
    var roomScopeSection: some View {
        if socialPeopleRoom {
            socialPeopleRow
        } else if roomScopeInRoom, SocialRoom.hasRoster(source) {
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
    @ViewBuilder
    var socialFacesTray: some View {
        if socialPeopleRoom {
            let people = socialPeople
            SocialFacesTray(accounts: people.map(Self.faceAccount), source: source,
                            scope: chrome.personScope,
                            faceSources: Dictionary(people.map { ($0.id, $0.source) },
                                                    uniquingKeysWith: { a, _ in a })) { picked in
                withAnimation(DS.Motion.standard) { chrome.personScope = picked }
            }
        } else {
            SocialFacesTray(accounts: SocialRoomSource.accounts(for: source), source: source,
                            scope: chrome.personScope) { picked in
                withAnimation(DS.Motion.standard) { chrome.personScope = picked }
            }
        }
    }
}

// MARK: - The Social room's people (prd §1079)

// §1068 merged the networks into one Social room and the face row went with
// their rooms. It stands again here, over Farcaster and Bluesky at
// once, one face per PERSON: accounts the Addresses index joins into one
// contact are one face, and a pick keeps that person's posts on every network
// (`FollowedPeople`). On every size class: the shell's rail draws only for a
// network's own room, which no longer opens.
extension FeedScreen {
    /// The merged Social room.
    var socialPeopleRoom: Bool { source == RoomAccounts.socialRoom }

    /// The followed accounts of the networks with a roster, narrowed to the
    /// app the menu picked, grouped into people.
    var socialPeople: [FollowedPeople.Person] {
        let networks: [(String, Identity.Kind)] = [("Farcaster", .farcaster), ("Bluesky", .bluesky)]
        // The accounts marked yours, by network and key.
        var mine: Set<String> = []
        for a in FarcasterStore.shared.accounts where a.mine { mine.insert("Farcaster:\(a.username)") }
        for a in BlueskyStore.shared.accounts where a.mine { mine.insert("Bluesky:\(a.handle)") }
        var accounts: [FollowedPeople.Account] = []
        for (network, kind) in networks {
            if let seat = selectedSeat, !seat.owns(network) { continue }
            for account in SocialRoomSource.accounts(for: network) {
                accounts.append(FollowedPeople.Account(
                    source: network, key: account.key, title: account.title,
                    subtitle: account.subtitle, avatarURL: account.avatarURL,
                    identity: Identity.key(kind, account.key),
                    mine: mine.contains("\(network):\(account.key)")))
            }
        }
        return FollowedPeople.group(accounts) { ContactIndexSources.contact(forKey: $0)?.id }
    }

    /// The accounts a picked person keeps, or nil with no pick (or outside
    /// the room). A pick naming nobody keeps nothing rather than everything.
    var socialScopeMembers: Set<FollowedPeople.Member>? {
        guard socialPeopleRoom, let scope = chrome.personScope else { return nil }
        return FollowedPeople.members(of: scope, in: socialPeople) ?? []
    }

    /// A person as the rail's account value, so its order and its `+N`
    /// (`SocialScopeRail.visible`) are the network rooms' own.
    static func faceAccount(_ person: FollowedPeople.Person) -> SocialAccount {
        SocialAccount(key: person.id, title: person.title, subtitle: person.subtitle,
                      avatarURL: person.avatarURL, watches: [])
    }

    @ViewBuilder
    var socialPeopleRow: some View {
        let people = socialPeople
        if people.count > 1 {
            let byID = Dictionary(people.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let visible = SocialScopeRail.visible(people.map(Self.faceAccount),
                                                  recent: chrome.recentHandles,
                                                  scope: chrome.personScope)
            let fresh = chrome.freshHandles
            Section {
                FaceScopeRail(
                    items: visible.shown.compactMap { account in
                        byID[account.key].map { person in
                            FaceScopeRail.Item(
                                id: person.id, caption: person.title,
                                face: .avatar(url: person.avatarURL, source: person.source),
                                ringed: fresh.contains(person.id),
                                tooltip: person.subtitle)
                        }
                    },
                    scope: chrome.personScope,
                    compact: false,
                    matches: SocialScopeRail.matches,
                    onPick: { picked in
                        withAnimation(DS.Motion.standard) { chrome.personScope = picked }
                    },
                    // Re-tapping the lit face opens the person's own page on
                    // the network their first account is on.
                    onReTap: { item in
                        guard let person = byID[item.id], let first = person.members.first else { return }
                        chrome.personRequest = SocialProfile(
                            source: first.source, handle: first.handle,
                            displayName: person.title, bio: nil,
                            avatarURL: person.avatarURL)
                    },
                    more: visible.hidden,
                    onMore: { feedSheet = .socialFaces })
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: 0,
                                          bottom: DSRoomChassis.leadGap - DS.Space.s1,
                                          trailing: 0))
            }
        }
    }
}
