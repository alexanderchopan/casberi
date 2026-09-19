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
        // Safe's head is a FIGURE, not a text hero (2026-08-17):
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
        // Walletbeat is the third exception, for X's and Safe's exact reason (prd §419):
        // its head is a FIGURE — a coverage bar per watched wallet — so leaving it out
        // makes the peek preview NOTHING (the room has no topic map, no leaderboard and
        // no heatmap registry entry), and long-pressing the chip draws a blank.
        //
        // THE VALUE IS THE JUDGED COUNT, never the pass count. A bar drawn from passes
        // would rank the wallet nobody has examined alongside one that passed nothing,
        // which is the single reading this whole feature exists to prevent — and the
        // `detail` says the fraction out loud so the peek can never imply a verdict the
        // room's own gate would refuse to draw.
        if source == WalletbeatRoomSource.source,
           let room = WalletbeatRoomSource.compose(things: things) {
            let rows = room.items.prefix(4)
            guard !rows.isEmpty else { return nil }
            return card(WalletbeatRoom.headline(room),
                        WalletbeatRoom.note(room),
                        .bars(rows.map {
                            AgentPanel.Bar(label: $0.name, value: $0.counts.judged,
                                           detail: "\($0.counts.judged)/\($0.counts.applicable)")
                        }))
        }
        // L2BEAT is the fourth exception, for Walletbeat's exact reason (prd §428):
        // its head is a FIGURE, so leaving it out makes the peek preview NOTHING — the
        // room has no topic map, no leaderboard and no heatmap registry entry.
        //
        // THE VALUE IS HOW MANY OF THE FIVE L2BEAT FLAGS, and the `detail` says the
        // fraction out loud. Deliberately NOT the stage rung: a bar chart of rungs is a
        // league table of chains, which is the one reading this feature refuses to draw
        // — and at tile scale, with no legend, a taller bar reads as better rather than
        // as "more was flagged".
        if source == L2beatRoomSource.source,
           let room = L2beatRoomSource.compose(things: things) {
            let rows = room.items.prefix(4)
            guard !rows.isEmpty else { return nil }
            return card(L2beatRoom.headline(room),
                        L2beatRoom.note(room),
                        .bars(rows.map {
                            AgentPanel.Bar(label: $0.name, value: $0.flagged,
                                           detail: "\($0.flagged)/\($0.risks.count)")
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
        // The art wall and the habit pulse stood here and went with the room
        // figures they previewed (prd §832): the peek shows what the room draws.
        return nil
    }

    static func toneIndex(_ tone: FeedInsight.Tone) -> Int {
        switch tone {
        case .positive: return 1
        case .negative: return 2
        default:        return 0
        }
    }
}
