import SwiftUI

// THE YOU CATEGORY'S PILL (prd §1127, §1129; user: "i think home should have
// the pill that says You and each of the pink icons are in it"; "home should
// say You, and 'home' is what is selected").
//
// The tray's You row, as the glass pill beside a category's name (§1066):
// Home · Notes · Markets · Apps · Addresses · Settings, each on its pink
// disc. The title says You; the pill names the place showing. Every pick
// lands in place: Notes and Markets are feeds, Apps, Addresses and Settings
// are screens (`HomeScope.Place`), and none of them pushes or draws a back
// door. The tray keeps its row too.
struct YouPill: View {
    /// The place showing: "" is Home, else a slot id below.
    let showing: String
    @Environment(ShellChrome.self) private var chrome
    @Environment(HomeRoute.self) private var route

    /// The six doors, in the tray's order. Home is the "All" slot (`id` ""),
    /// so the pill reads Home while Home's own feed shows. The ids of the
    /// last three are `HomeScope.Place` raw values.
    private var slots: [DSAccountSlot] {
        func door(_ id: String, _ name: String, _ glyph: String) -> DSAccountSlot {
            DSAccountSlot(id: id, name: name, sub: nil, faces: [], symbol: glyph, brandDisc: true)
        }
        return [
            door("", String(localized: "Home"), "house"),
            door("notes", String(localized: "Notes"), "note"),
            door("markets", String(localized: "Markets"), CategoryFold.glyph(for: HomeScope.markets)),
            door(HomeScope.Place.apps.rawValue, String(localized: "Apps"), ScopeTileGlyph.apps),
            door(HomeScope.Place.addresses.rawValue, String(localized: "Addresses"), "at"),
            door(HomeScope.Place.settings.rawValue, String(localized: "Settings"), "gearshape"),
        ]
    }

    var body: some View {
        let slots = slots
        let picked = slots.first { $0.id == showing } ?? slots[0]
        // The row holds the WIDEST pick's width, so your name keeps one size
        // whichever place is showing: a pill growing from Home to Addresses
        // shrank a long name beside it, and the row is the one thing a
        // switch must not move (prd §1129). The stand-ins draw nothing and
        // take no touch.
        ZStack(alignment: .trailing) {
            ForEach(slots, id: \.id) { slot in
                menu(slots, showing: slot).hidden().accessibilityHidden(true)
            }
            menu(slots, showing: picked)
        }
    }

    private func menu(_ slots: [DSAccountSlot], showing: DSAccountSlot) -> DSScopeMenu {
        DSScopeMenu(slots: slots, showing: showing,
                    allLabel: String(localized: "Home"),
                    spoken: { String(localized: "You: \($0)") },
                    onPick: { id in open(id ?? "") })
    }

    /// What a door does: Home and Notes land, Markets lands once something
    /// is watched and opens its page before that (§1123), and the three
    /// screens land in place (§1129).
    private func open(_ id: String) {
        if let place = HomeScope.Place(rawValue: id) {
            route.present(HomeRoute.door(for: place))
            return
        }
        if !route.path.isEmpty { route.path = [] }
        switch id {
        case "notes": chrome.sourceRequest = Pinboard.room
        case "markets":
            if (chrome.categoryVenues[HomeScope.markets] ?? []).isEmpty {
                route.openSetup(forOffer: HomeScope.markets)
            } else {
                chrome.sourceRequest = HomeScope.markets
            }
        default: chrome.sourceRequest = "All"
        }
    }
}

/// The title row of a You place that is a screen (Apps, Addresses,
/// Settings): the category's name and its pill, where the screen's own name
/// stood, so switching places changes everything under the row and nothing
/// in it (prd §1129).
struct YouHead: View {
    let place: HomeScope.Place

    var body: some View {
        DSRoomTitleRow(title: HomeScope.title) {
            YouPill(showing: place.rawValue)
        }
    }
}

extension FeedScreen {
    /// The You pill on a feed in You: Home, Notes or a Markets room.
    var youPill: some View {
        let showingID = Pinboard.isPinnedRoom(source) ? "notes"
            : HomeScope.isMarkets(source) ? "markets" : ""
        return YouPill(showing: showingID)
        #if DEBUG
        .task { if Pinboard.isPinnedRoom(source) { notesProbe() } }
        #endif
    }
}
