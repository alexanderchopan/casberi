import SwiftUI

// WHOSE FEED THIS IS, IN THE ROOM (prd §959).
//
// On the phone the band under the face carried a capsule of faces in three
// kinds of room — the social rooms, GitHub and Pinterest — after §930 took
// away the dock strip it had belonged to, so it read as a leftover. The wallet
// family had already moved its pick into the room (§936). These rooms follow:
// the control stands under the room's lead (under the tiles where a room has
// them), in the rows' column, and scrolls with the feed.
//
// Two controls for two questions. GitHub and Pinterest pick a SOURCE — a
// watched repo, a person, a board — whose face is often an org's avatar or a
// cover shared by its neighbours, so the name does the work: the Wallet's
// pull-down (`DSScopeMenu`). The social rooms pick a PERSON whose own face,
// and the ring saying they posted since you looked, is the news: a row of
// faces (`FaceScopeRail`, standing alone). iPad and Mac keep the shell's rail.
extension FeedScreen {
    /// The phone. Everywhere the shell's rail stands, the band keeps the faces.
    var roomScopeInRoom: Bool { roomSizeClass != .regular }

    /// A scope is picked in a room whose control now lives in the room, so an
    /// empty result must keep the room (and the control) rather than hand it
    /// to the generic empty state — whose only door leaves the room (§538).
    var roomScopePicked: Bool {
        guard roomScopeInRoom else { return false }
        return (SocialRoom.hasRoster(source) && chrome.personScope != nil)
            || (source == "GitHub" && chrome.githubScope != nil)
            || (source == "Pinterest" && chrome.pinterestScope != nil)
    }

    /// Whether `roomScopeSection` draws anything — the three rails' own gates.
    var roomScopeDraws: Bool {
        guard roomScopeInRoom else { return false }
        return GitHubScopeRail.shows(source: source, watched: GitHubWatchStore.shared.watches.count)
            || PinterestScopeRail.shows(source: source, follows: PinterestStore.shared.follows.count)
            || SocialScopeRail.shows(source: source, accounts: SocialRoomSource.accounts(for: source).count)
    }

    /// The control, as its own List section. Draws nothing where the room
    /// has nothing to pick between, or off the phone.
    @ViewBuilder
    var roomScopeSection: some View {
        if roomScopeInRoom {
            if source == "GitHub" {
                githubScopeMenu
            } else if source == "Pinterest" {
                pinterestScopeMenu
            } else if SocialRoom.hasRoster(source) {
                socialFaceRow
            }
        }
    }

    @ViewBuilder
    private var githubScopeMenu: some View {
        let watches = GitHubWatchStore.shared.watches
        // ONE watch is enough here (`GitHubRowTag.railShows`): All is your
        // whole GitHub and a watched person is a strict slice of it.
        if GitHubScopeRail.shows(source: source, watched: watches.count) {
            sourceScopeMenu(GitHubScopeRail.items(watches),
                            scope: chrome.githubScope,
                            matches: GitHubScopeRail.matches,
                            allName: String(localized: "All activity"),
                            markWord: String(localized: "Repository")) { picked in
                chrome.githubScope = picked
            }
        }
    }

    @ViewBuilder
    private var pinterestScopeMenu: some View {
        let store = PinterestStore.shared
        if PinterestScopeRail.shows(source: source, follows: store.follows.count) {
            sourceScopeMenu(PinterestScopeRail.items(store),
                            scope: chrome.pinterestScope,
                            matches: GitHubScopeRail.matches,
                            allName: String(localized: "All pins"),
                            markWord: String(localized: "Board")) { picked in
                chrome.pinterestScope = picked
            }
        }
    }

    /// The rail's items as the menu's slots, "All" first. A slot's subtitle
    /// says what the rail's squircle-or-circle said: a mark is a repo or a
    /// board, an avatar a person.
    private func sourceScopeMenu(_ items: [FaceScopeRail.Item], scope: String?,
                                 matches: @escaping (String, String) -> Bool,
                                 // "All" names what it holds, as the Wallet's
                                 // "All accounts" does.
                                 allName: String,
                                 markWord: String,
                                 pick: @escaping (String?) -> Void) -> some View {
        let all = DSAccountSlot(id: "", name: allName, sub: nil,
                                faces: items.prefix(2).map(\.face))
        let slots = [all] + items.map { item in
            let isMark: Bool = { if case .mark = item.face { return true }; return false }()
            return DSAccountSlot(id: item.id, name: item.caption,
                                 sub: isMark ? markWord : String(localized: "Person"),
                                 faces: [item.face])
        }
        let showing = scope.flatMap { picked in
            slots.first { !$0.id.isEmpty && matches(picked, $0.id) }
        } ?? all
        return Section {
            DSScopeMenu(slots: slots, showing: showing,
                        spoken: { String(localized: "Showing: \($0)") },
                        subtitles: true, onPick: pick)
                .frame(maxWidth: .infinity, alignment: .leading)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: DSRoomChassis.inset,
                                          bottom: DSRoomChassis.leadGap,
                                          trailing: DSRoomChassis.inset))
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

    /// WATCHING STANDS IN THE GITHUB ROOM (prd §1030, user: "ok do both",
    /// amending the 2026-09-11 "only on the set up screen"). A verb is a row
    /// (§746), last, under the tiles and the menu — and drawn with NO watch
    /// too, because a room with no watch draws no menu, and this row is then
    /// the only sign that watching exists. Every platform: the shell's rail
    /// on iPad and Mac carries faces, not verbs. `eye` is the app's watch
    /// glyph (Follow address, the address book's Watch).
    @ViewBuilder
    var githubWatchSection: some View {
        if source == "GitHub", githubKeyed {
            Section {
                DevnetVerbRow(title: String(localized: "Watch a repo or person"),
                              glyph: "eye",
                              tint: DS.tint,
                              act: { feedSheet = .githubWatch })
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: DSRoomChassis.inset,
                                              bottom: DSRoomChassis.leadGap,
                                              trailing: DSRoomChassis.inset))
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
