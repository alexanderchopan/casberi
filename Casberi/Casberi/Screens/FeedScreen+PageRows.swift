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
    func pageDoorRow(_ title: String, action: @escaping () -> Void) -> some View {
        DSMoreRow(title: Text(verbatim: title), action: action)
            .feedRowBackground()
            .listRowInsets(.init(top: 0, leading: DSRoomChassis.rowInset,
                                 bottom: 0, trailing: DSRoomChassis.rowInset))
            .listRowSeparator(.hidden)
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
