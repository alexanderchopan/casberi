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
        case .sources:
            // The master list; Casberi's own options are its first row
            // (prd §1231).
            chrome.settingsPick = .sources
            route.present(.casberi)
        default:
            if !route.path.isEmpty { route.path = [] }
            chrome.lastChipTouch = Date.timeIntervalSinceReferenceDate
            // Day and Notes rise as sheets over the Feed (`routeIntoFeed`).
            chrome.sourceRequest = switch tile {
            case .day: RoomAccounts.dayRoom
            case .notes: Pinboard.room
            default: "All"
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
        // Not in a sheet (prd §1208l): the Feed's tiles belong to the Feed.
        if !inSheet {
            Section {
                YouTilesRow(active: active)
                    .dsRoomTilesListRow()
            }
        }
    }
}
