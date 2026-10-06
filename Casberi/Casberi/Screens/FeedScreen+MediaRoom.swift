import SwiftUI

// MARK: - Media (prd §1055, tiles §1118)

extension FeedScreen {
    /// The Media room: the newest thing in the box, All · Subscriptions under
    /// it, the menu, then the one square grid (§1055). Subscriptions draws
    /// its own box and list: every channel, show and board you follow, with
    /// Track a subscription first, and the Twitch channels your account
    /// follows (prd §1118).
    @ViewBuilder
    func mediaRoomSections(_ visible: [Thing], nextEventID: UUID?, heroShown: Bool) -> some View {
        let subscriptions = chrome.mediaScope == .subscriptions
        let days = chronoDays(visible)
        let cover: Thing? = {
            guard !heroShown, !subscriptions, let id = ledeThingID(in: days) else { return nil }
            return visible.first { $0.isLive && $0.id == id }
        }()
        if subscriptions {
            Section { followingBox(.media) }
        } else if let cover {
            Section { ledeListRow(cover) }
        } else if !heroShown {
            Section {
                emptyLeadRow(headline: DSProse.text("Nothing yet"),
                             words: Text("What you watch, play and listen to lands here"))
            }
        }
        Section {
            DSScopeTiles(sections: MediaScope.allCases, active: chrome.mediaScope,
                         attention: [], verbs: []) { picked in
                withAnimation(DS.Motion.standard) { chrome.mediaScope = picked }
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: DSRoomChassis.inset,
                                      bottom: DSRoomChassis.leadGap,
                                      trailing: DSRoomChassis.inset))
        }
        roomScopeSection
        if subscriptions {
            followingSections(.media)
        } else {
            groupedSections(liftingCover(days, id: cover?.id), nextEventID: nextEventID,
                            boundary: boundaryThingID(in: days),
                            isTile: Self.isMediaTile, tileShape: .square)
        }
    }
}
