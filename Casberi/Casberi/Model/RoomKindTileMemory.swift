import Foundation

/// The kind tiles each room drew last, remembered across launches (prd §830).
///
/// A room's tiles ride `FeedScreen.RoomHeads`, which is computed in a task
/// AFTER the room mounts — and deliberately so: it reads the whole room, and
/// doing that in the swipe's frames was §265's lag. But `headMemo` lives in
/// memory, so the first visit to a room after every launch drew the room with
/// no tiles and then pushed the list down under them when the reading landed
/// (user, 2026-09-19: "they are there but didn't load at first").
///
/// So the room draws the tiles it drew last time, from the first frame, and
/// the live reading confirms or corrects them. What is remembered is WHICH
/// tiles — a navigation control — and never the attention dot: a dot drawn
/// from memory would be a stale "needs you" (§83), so it waits for the
/// reading. The first visit after an install is still the late one; there is
/// nothing honest to draw before anything has been read.
@MainActor
enum RoomKindTileMemory {
    private static let key = "room.kindTiles.v1"

    /// Loaded once, the first time a room asks. Every later read is this map.
    private static var map: [String: [String]] = {
        UserDefaults.standard.data(forKey: key)
            .flatMap { try? JSONDecoder().decode([String: [String]].self, from: $0) } ?? [:]
    }()

    static func tiles(for source: String) -> [RoomKindTile]? {
        map[source].map { $0.compactMap(RoomKindTile.init(rawValue:)) }
    }

    /// Written only when a room's tiles actually changed, so a recompute that
    /// agrees with the last one costs nothing.
    static func remember(_ tiles: [RoomKindTile], for source: String) {
        let raw = tiles.map(\.rawValue)
        guard map[source] != raw else { return }
        map[source] = raw
        guard let data = try? JSONEncoder().encode(map) else { return }
        DefaultsWrite.set(data, forKey: key)
    }
}
