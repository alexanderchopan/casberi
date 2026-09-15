import SwiftUI

/// THE PEER ROOM'S HEAD (2026-08-10, prd §349) — which rail your money moves
/// on, and which way it goes.
///
/// A heavy headline stating the whole finding as a sentence, the other rails as
/// ranked rows, and no decoration that isn't a reading. No coloured rail down a
/// row's side and no green/red — a rail is not good or bad, it is the one you
/// use.
///
/// ## The one drawing, and what it means
///
/// A `ShareBar` per rail row, scaled against the busiest one, encoding ONE
/// thing: how much of your Peer traffic went this way. It is deliberately not a
/// buy/sell split bar — a two-tone bar invites reading the ratio as a balance
/// somebody chose, and the two counts are stated exactly in words beside it.
///
/// **The lead's own bar is deleted (prd §745).** `top` is the lead's fill
/// count, so the lead's bar was full on every card — `accessibility-audit.py`'s
/// "scale anchor carrying no information at all".
///
/// ## Liveness
///
/// Stores no `Thing` — only value types out of `PeerRoom`, filtered at the
/// boundary by `PeerRoomSource`. The tap hands back a `Rail` and the section
/// that owns the sheet does the lookup (corollary 5).
struct PeerRoomCard: View {
    let room: PeerRoom
    /// Hands back the RAIL, not a `Thing` — the card never holds one, and a
    /// rail owns many rows so there is no single `sourceRef` it could name.
    var onOpen: (PeerRoom.Rail) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var drawn: [PeerRoom.Rail] {
        Array(room.rails.prefix(PeerRoomSource.rowCap))
    }

    /// The busiest rail's fill count — the bar's full width, so every bar on
    /// the card is on one scale and two rows are comparable at a glance.
    private var top: Int { room.lead?.fills ?? 0 }

    var body: some View {
        DSRoomChassis.Head(
            lead: .sentence(PeerRoom.headline(room)),
            // The lead has no row of its own (see below), so the headline is
            // the only place its destination can be reached.
            door: room.lead.map { lead in
                DSRoomChassis.Door(hint: Text("Opens this rail")) { onOpen(lead) }
            },
            // The rail grouping and the token grouping are two different
            // readings of the same fills (2026-08-11) — the quiet line is the
            // second one, and it stays silent (see `tokenNote`) rather than
            // repeat the rail note in different words.
            notes: [.note(PeerRoom.note(room)), .quiet(PeerRoom.tokenNote(room))],
            footnotes: [.quiet(PeerRoom.footnote(room, drawn: drawn.count))]) {
            // Only the rails BEYOND the lead get a row — the lead is already in
            // the headline.
            if drawn.count > 1 {
                DSRoomChassis.Block {
                    DSRoomChassis.Rows(items: Array(drawn.dropFirst())) { index, rail in
                        DSRoomChassis.Row(
                            title: rail.name,
                            line: PeerRoom.railLine(rail),
                            index: index,
                            action: { onOpen(rail) }) {
                            ShareBar(fraction: PeerRoom.share(fills: rail.fills, of: top),
                                     index: index + 1,
                                     reduceMotion: reduceMotion)
                        }
                    }
                }
            }
        }
    }
}
