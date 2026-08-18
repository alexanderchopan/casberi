import Foundation
import SwiftData

/// ONE ROOM'S FIGURE, composed on demand (2026-08-15, prd §386p).
///
/// Lifted out of `Composer` when the agent panel was deleted. The panel built
/// one of these for EVERY connected room on every open — ~40 compositions to
/// fill a screen the brief replaced — and that loop is what went. The
/// per-room function survives because one caller still wants exactly one of
/// them: the source chip's long-press peek, which shows the room you are
/// about to open.
///
/// Pure over `[Thing]` plus the registries, exactly as it was inside the
/// panel, so the peek and the room it previews cannot disagree.
@MainActor
enum RoomFigure {
    static func roomFigure(source: String, things: [Thing]) -> AgentPanel.Card? {
        func card(_ title: String, _ caption: String,
                  _ figure: AgentPanel.Figure) -> AgentPanel.Card {
            AgentPanel.Card(source: source, key: source, title: title,
                            caption: AgentPanel.clamp(caption), figure: figure,
                            affinity: ChipMemory.weight(for: source),
                            reading: nil, rising: nil)
        }
        // The per-source heads OUTRANK everything below in the room itself, and
        // all but one of them are text heroes §334 excludes on purpose. X is
        // the exception (2026-08-13, prd §375): its head is a FIGURE — the
        // years of an archive — so leaving it out would make this tile preview
        // the topic treemap while the room draws a year strip, which is the
        // exact drift this chain's contract forbids.
        //
        // Drawn as bars rather than a pulse: the room's own rows are the top
        // years ranked, a tile fits four, and a year is a label a person reads.
        if let room = XRoomSource.compose(things: things), source == XRoomSource.source {
            return card(XRoom.headline(room), XRoom.note(room),
                        .bars(XRoom.rows(room).prefix(4).map {
                            AgentPanel.Bar(label: String($0.year), value: $0.posts,
                                           detail: $0.posts.formatted())
                        }))
        }
        // Safe is the second exception, and for X's exact reason (2026-08-17):
        // its head is a FIGURE, not a text hero — rings, one per pending
        // transaction, ranked. Leaving it out made the peek preview NOTHING at
        // all (no topic map, no leaderboard, no heatmap registry entry), so
        // long-pressing the one chip whose room might be asking for your
        // signature previewed a blank.
        //
        // Bars rather than a rail: the room's subject is a COUNT toward a
        // threshold, which is what the rings draw, and a rail would restate it
        // as a proportion — the exact shape `SafeRoomCard` rejected.
        if source == SafeRoomSource.source, let room = SafeRoomSource.compose(things: things) {
            let rows = room.entries.prefix(4)
            guard !rows.isEmpty else {
                // Module risk with an empty queue: the head still draws (it is
                // the highest-stakes thing this bridge says) but there are no
                // rings to preview, and a tile with no bars is a broken tile.
                return nil
            }
            return card(SafeRoom.headline(room),
                        SafeRoom.stateNote(room) ?? SafeRoom.note(room) ?? "",
                        .bars(rows.map {
                            AgentPanel.Bar(label: SafeRoom.waitLabel($0), value: $0.have,
                                           detail: "\($0.have)/\($0.required)")
                        }))
        }
        if let map = FeedInsight.topicMap(source: source, things: things) {
            // Four rows, not six: the inventory of small forms is explicit that
            // a six-cell map's last slot is one grid unit wide and its label
            // collapses to two clipped characters at tile scale.
            return card(map.title, map.subtitle,
                        .treemap(map.cells.prefix(4).map {
                            AgentPanel.Cell(label: $0.label, weight: $0.count)
                        }))
        }
        if let board = FeedInsight.leaderboard(source: source, things: things) {
            return card(board.title, board.subtitle,
                        .bars(board.rows.prefix(4).map {
                            AgentPanel.Bar(label: $0.label, value: $0.value, detail: $0.detail)
                        }))
        }
        if let split = FeedInsight.distribution(source: source, things: things) {
            let total = max(1, split.segments.reduce(0) { $0 + $1.count })
            return card(split.title, split.subtitle,
                        .rail(split.segments.map {
                            AgentPanel.Segment(label: $0.label,
                                               share: Double($0.count) / Double(total),
                                               tone: toneIndex($0.tone),
                                               count: $0.count)
                        }))
        }
        if let wall = FeedInsight.mosaic(source: source, things: things) {
            // `Mosaic.Tile` carries no per-item title, so every tile shares
            // the room's own mosaic title as its loading/failed label (spec
            // item 4) — "Your pins" while a Pinterest thumbnail is still
            // fetching reads as content; a bare gray box reads as broken.
            return card(wall.title, wall.subtitle,
                        .wall(wall.tiles.prefix(4).map {
                            AgentPanel.WallTile(url: $0.url, label: wall.title)
                        }))
        }
        if let label = FeedHeatmap.label(for: source) {
            // Only a HABIT earns the pulse tile (user, 2026-08-14, prd §386:
            // the casts/screenshots/posts grids were "kinda useless"). The
            // grid is a consistency-over-time reading, which is a real answer
            // where the acts are YOURS — journaling, writing, training,
            // chatting — and noise where the room is content that merely
            // arrived: three identical activity smudges saying "when" about
            // rooms whose whole point is WHO and WHAT. A content room whose
            // better figures (topic map, leaderboard, mosaic) all declined
            // now composes NO tile — an absent tile beats a tile that
            // answers nothing — while its FEED keeps the year heatmap as the
            // documented fallback (§247's chain, unchanged).
            guard pulseWorthy.contains(source) else { return nil }
            let counted = FeedHeatmap.counted(things, label: label)
            // Twelve weeks, not the room's 53. A full year at tile scale is
            // ~2.7pt cells — unreadable — while the windowed grid the social
            // rooms already draw reads fine.
            return card(label.title, label.units, .pulse(dailyCounts(counted, days: 7 * 12)))
        }
        return nil
    }

    static let pulseWorthy: Set<String> = [
        "Day One", "Apple Journal", "Obsidian", "Notion",
        "Apple Health", "Strava", "ChatGPT", "Claude", "Gemini",
    ]

    static func toneIndex(_ tone: FeedInsight.Tone) -> Int {
        switch tone {
        case .positive: return 1
        case .negative: return 2
        default:        return 0
        }
    }

    static func dailyCounts(_ things: [Thing], days: Int) -> [Int] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        var buckets = Array(repeating: 0, count: days)
        for thing in things {
            let d = cal.dateComponents([.day], from: cal.startOfDay(for: thing.capturedAt),
                                       to: today).day ?? -1
            guard d >= 0, d < days else { continue }
            buckets[days - 1 - d] += 1
        }
        return buckets
    }
}
