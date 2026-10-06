import SwiftUI

/// YOU'S TILES (prd §1136 item 1): Home · Markets · Notes · Settings, drawn
/// under the box on every place in You, in the same spot, so moving between
/// them never moves the frame. Each pick lands the place the tray's You row
/// lands: a feed through `sourceRequest`, Settings through `route.present`.
struct YouTilesRow: View {
    let active: YouTile
    @Environment(ShellChrome.self) private var chrome
    @Environment(HomeRoute.self) private var route

    var body: some View {
        DSScopeTiles(sections: YouTile.allCases, active: active) { picked in
            guard picked != active else { return }
            YouTilesRow.open(picked, chrome: chrome, route: route)
        }
    }

    /// The one act behind a You tile, shared with the tray's You row.
    @MainActor
    static func open(_ tile: YouTile, chrome: ShellChrome, route: HomeRoute) {
        DSHaptic.selection()
        switch tile {
        case .settings:
            route.present(.casberi)
        case .markets where (chrome.categoryVenues[HomeScope.markets] ?? []).isEmpty:
            // Markets' own page until something is watched (prd §1123).
            route.openSetup(forOffer: HomeScope.markets)
        default:
            if !route.path.isEmpty { route.path = [] }
            chrome.lastChipTouch = Date.timeIntervalSinceReferenceDate
            switch tile {
            case .feed:    chrome.sourceRequest = "All"
            case .notes:   chrome.sourceRequest = Pinboard.room
            default:       chrome.sourceRequest = HomeScope.markets
            }
        }
    }
}

extension FeedScreen {
    /// You's tiles for a lead that takes a `DSScopeTiles` (`standaloneLead`).
    func youTiles(_ active: YouTile) -> DSScopeTiles<YouTile> {
        DSScopeTiles(sections: YouTile.allCases, active: active) { picked in
            guard picked != active else { return }
            YouTilesRow.open(picked, chrome: chrome, route: route)
        }
    }

    /// You's tiles as a list row, in the slot every room's tiles stand in:
    /// under the box, the box's gap below (`standaloneLead`'s insets).
    @ViewBuilder
    func youTilesSection(_ active: YouTile) -> some View {
        Section {
            YouTilesRow(active: active)
                .dsRoomTilesListRow()
        }
    }
}

/// The two rooms in You whose own tiles ride the floating bar: Markets'
/// (prd §1081) and Notes' (prd §1136 item 2). Pass false to take one down.
struct FeedRoomDocks: ViewModifier {
    let tokens: Bool
    let notes: Bool
    let tokensScope: TokensScope
    let notesScope: NotesScope
    let notesHold: DSScopeTiles<NotesScope>.Hold
    let pickTokens: (TokensScope) -> Void
    let pickNotes: (NotesScope) -> Void

    func body(content: Content) -> some View {
        content
            .dsScopeDock(sections: tokens ? TokensScope.bar : [],
                         active: tokensScope, verbs: [.search], clearance: 0, onPick: pickTokens)
            .dsScopeDock(sections: notes ? NotesScope.allCases : [],
                         active: notesScope, verbs: [.new, .search], clearance: 0,
                         hold: notesHold, onPick: pickNotes)
    }
}
