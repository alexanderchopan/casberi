import SwiftUI

// HOME'S YOU PILL (prd §1127, user: "i think home should have the pill that
// says You and each of the pink icons are in it").
//
// The tray's You row, as the glass pill every merged room wears in its title
// row (§1066): Home · Notes · Markets · Apps · Addresses · Settings, each on
// its pink disc. Notes and Markets are Home's scopes, so the title keeps
// "Home" and the pill names the pick; Apps, Addresses and Settings push their
// screens, as the tray's doors do. The tray keeps its row too.
extension FeedScreen {
    /// The six doors, in the tray's order. Home is the "All" slot (`id` ""),
    /// so the pill reads You while Home's own feed shows.
    private var youSlots: [DSAccountSlot] {
        func door(_ id: String, _ name: String, _ glyph: String) -> DSAccountSlot {
            DSAccountSlot(id: id, name: name, sub: nil, faces: [], symbol: glyph, brandDisc: true)
        }
        return [
            door("", String(localized: "Home"), "house"),
            door("notes", String(localized: "Notes"), "note"),
            door("markets", String(localized: "Markets"), CategoryFold.glyph(for: HomeScope.markets)),
            door("apps", String(localized: "Apps"), ScopeTileGlyph.apps),
            door("addresses", String(localized: "Addresses"), "at"),
            door("settings", String(localized: "Settings"), "gearshape"),
        ]
    }

    var youPill: some View {
        let slots = youSlots
        let showingID = Pinboard.isPinnedRoom(source) ? "notes"
            : HomeScope.isMarkets(source) ? "markets" : ""
        let showing = slots.first { $0.id == showingID } ?? slots[0]
        return DSScopeMenu(slots: slots, showing: showing,
                           spoken: { String(localized: "You: \($0)") },
                           allLabel: String(localized: "You"),
                           onPick: { id in openYouDoor(id ?? "") })
        #if DEBUG
        .task { if Pinboard.isPinnedRoom(source) { notesProbe() } }
        #endif
    }

    /// What a You door does: Home and Notes land, Markets lands once
    /// something is watched and opens its page before that (§1123), and the
    /// other three push their screens.
    private func openYouDoor(_ id: String) {
        switch id {
        case "notes": chrome.sourceRequest = Pinboard.room
        case "markets":
            if (chrome.categoryVenues[HomeScope.markets] ?? []).isEmpty {
                route.openSetup(forOffer: HomeScope.markets)
            } else {
                chrome.sourceRequest = HomeScope.markets
            }
        case "apps": route.present(.apps)
        case "addresses": route.present(.addresses)
        case "settings": route.present(.casberi)
        default: chrome.sourceRequest = "All"
        }
    }
}
