import SwiftUI

// MARK: - Media (prd §1055, tiles §1118; Reading folded in, §1204)

extension FeedScreen {
    /// The Media room: the newest thing in the box, All · Play · Read ·
    /// Subscriptions under it, the menu, then the days (prd §1204, user:
    /// "another alternative is we get rid of 'highlights' and the then
    /// buttons are all, reading, media, subscriptions", then "i like 'play'").
    ///
    /// Play is what was the Media room: what you watch, play and listen to,
    /// one square grid (§1055). Read is what was the Reading room: what you
    /// read and save, as rows, one article saved in several apps standing once
    /// (§1079). All is both, each day its rows and then its grid, and only
    /// Play's apps ever tile, so an article with a picture stays a row.
    /// Subscriptions lists the sites you follow, then the channels, shows and
    /// boards. Highlights is deleted with its tile: a passage you keep is a
    /// note of yours (§1020), so Notes holds it.
    @ViewBuilder
    func mediaRoomSections(_ visible: [Thing], nextEventID: UUID?, heroShown: Bool) -> some View {
        let scope = chrome.mediaScope
        let subscriptions = scope == .subscriptions
        let read = RoomAccounts.readSources
        let rows: [Thing] = switch scope {
        case .play: visible.filter { !read.contains($0.source) }
        case .read: objectFolded(visible.filter { read.contains($0.source) })
        case .all, .subscriptions: objectFolded(visible)
        }
        let days = chronoDays(rows)
        let cover: Thing? = {
            guard !heroShown, !subscriptions, let id = ledeThingID(in: days) else { return nil }
            return rows.first { $0.isLive && $0.id == id }
        }()
        if subscriptions {
            // The box states the channels while there are any, else the sites
            // (a site's box counts what you follow, §1118). Both lists read.
            let boxRoom: Following.Room = FollowingReading.shared.items(for: .media).isEmpty
                && !FollowingReading.shared.items(for: .reading).isEmpty ? .reading : .media
            Section {
                followingBox(boxRoom)
                    .task(id: followingKey(.reading)) {
                        FollowingReading.shared.refresh(.reading, context: modelContext)
                    }
                    .task(id: followingKey(.media)) {
                        FollowingReading.shared.refresh(.media, context: modelContext)
                    }
            }
        } else if let cover {
            Section { ledeListRow(cover) }
        } else if !heroShown {
            Section {
                emptyLeadRow(headline: DSProse.text("Nothing yet"), words: {
                    switch scope {
                    case .play: Text("What you watch, play and listen to lands here")
                    case .read: Text("What you read and save lands here")
                    case .all, .subscriptions: Text("What you read, watch and listen to lands here")
                    }
                }())
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
            followingSections(.reading, verb: String(localized: "Follow a site"))
            followingSections(.media, verb: String(localized: "Follow a channel or show"))
        } else {
            groupedSections(liftingCover(days, id: cover?.id), nextEventID: nextEventID,
                            boundary: boundaryThingID(in: days),
                            isTile: scope == .read ? nil : { !read.contains($0.source) && Self.isMediaTile($0) },
                            tileShape: .square)
        }
    }
}
