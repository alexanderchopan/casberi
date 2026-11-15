import SwiftUI

// A PAGE UNDER ACTIVITY HAS NO TILES (prd §1812, user: "honestly i think even
// the pink glyphs should go away", "they should be accessed some other way.
// like maybe they are rows themselves", "you still need to convert glyphs
// into their rows").
//
// A category's or an app's page drew a row of pink glyphs under its title,
// and one glyph filtered the list, the next raised a tray and the third
// opened another list, all looking alike. On the phone each is a row with
// its word and a chevron, where the tiles stood: a door, as every door in
// the app is. Taking one narrows the page, the title names it after the
// page's own name ("Activity · Social · To you"), and the name before it
// goes back. All is not a row: it is the page. The tiles stand as they were
// on the iPad and the Mac, and in the Wallet's family.
extension FeedScreen {
    /// One of a page's doors: `DSMoreRow`'s grey word and chevron, at the
    /// rows' inset, a full target tall.
    func pageDoorRow(_ title: String, count: Int? = nil, action: @escaping () -> Void) -> some View {
        // **A ROW, NOT A GREY WORD (prd §1815, user: "app's lists are rows
        // ok").** "Coming up ›" and "Following ›" stood right under the
        // title in a count-link's grey and read as a second title; they are
        // rows now, their count and chevron at the trailing edge.
        // A door to a list of the page's own wears the door's chevron
        // (§1815 item 1); a Feed row, its own door, still draws none (§1272).
        Button {
            DSHaptic.selection()
            action()
        } label: {
            HStack(spacing: DS.Space.s2) {
                Text(verbatim: title)
                    .dsText(.body17)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: DS.Space.s2)
                if let count, count > 0 {
                    Text(verbatim: "\(count)")
                        .dsText(.body17)
                        .monospacedDigit()
                        .foregroundStyle(DS.textSecondary)
                }
                Image(systemName: "chevron.right")
                    .dsGlyph(.tick, weight: .bold)
                    .foregroundStyle(DS.textSecondary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: DSFeed.headHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        .dsHover()
            .feedRowBackground()
            .listRowInsets(.init(top: 0, leading: DSRoomChassis.rowInset,
                                 bottom: 0, trailing: DSRoomChassis.rowInset))
            .listRowSeparator(.hidden)
    }

    /// **AN APP'S PAGE DRAWS ITS OWN DOORS (prd §1813).** With no category
    /// page, Follow, Watch and Subscriptions stand on the app that follows
    /// by name (`FollowByName`, the apps a section's + lists): Follow on
    /// Bluesky, Watch on GitHub, never Watch on Stripe. True with no app
    /// picked.
    var pageAppFollows: Bool {
        guard let seat = selectedSeat else { return true }
        return FollowByName.whats[seat.name] != nil
    }

    /// Mailing lists are Mail's (prd §1813): Life's Subscriptions row stands
    /// on a mail app's page, never on Calendar's or Health's.
    var pageAppIsMail: Bool {
        guard let seat = selectedSeat else { return true }
        return FeedLook.mailSources.contains(seat.name)
    }

    /// What a room follows, narrowed to the app whose page this is (prd
    /// §1813): GitHub's page lists GitHub's repos, not every watch in Work.
    func followingItems(_ room: Following.Room) -> [Following.Item] {
        let items = FollowingReading.shared.items(for: room)
        guard pageUnderActivity, let seat = selectedSeat else { return items }
        let source = seat.source ?? seat.name
        return items.filter { $0.seat == source || $0.seat == seat.name }
    }

    /// The door a page under Activity is narrowed through: its word, and the
    /// way back to the whole page. Nil on the whole page, off the phone, and
    /// in a sheet.
    var pageScope: (label: String, clear: () -> Void)? {
        guard pageUnderActivity else { return nil }
        let chrome = chrome
        switch source {
        case RoomAccounts.socialRoom where chrome.socialScope == .toYou:
            return (chrome.socialScope.label, { chrome.socialScope = .all })
        case RoomAccounts.workRoom where chrome.workScope != .all:
            return (chrome.workScope.label, { chrome.workScope = .all })
        case RoomAccounts.mediaRoom where chrome.mediaScope != .all:
            return (chrome.mediaScope.label, { chrome.mediaScope = .all })
        case RoomAccounts.lifeRoom where chrome.lifeScope != .all:
            return (chrome.lifeScope.label, { chrome.lifeScope = .all })
        default:
            return nil
        }
    }
}
