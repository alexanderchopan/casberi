import SwiftUI

/// THE CURSOR ROOM'S HEAD (2026-08-08, prd §340) — what your coding agents
/// actually did, and where.
///
/// A heavy headline stating the whole finding as a sentence, the other
/// repositories as ranked rows, and no decoration that isn't a reading. No
/// coloured rail down a row's side and **no green/red**: a repository with
/// broken runs is stated in words and by its position, never painted, exactly
/// as a Stripe dispute is.
///
/// ## The one drawing, and what it means
///
/// A `ShareBar` per repository row, scaled against the busiest one, encoding
/// ONE thing: how much of your agent time went there. It is deliberately not a
/// pass/fail split bar — a two-tone bar invites reading the ratio as a success
/// rate, which over the newest thirty runs is a statistic nobody chose the
/// window for (§83). The failures are counted in words beside it.
///
/// **The lead's own bar is deleted (prd §745).** It was scaled against `top`,
/// which IS the lead's run count, so it drew full on every card that ever
/// rendered — a bar with one possible length encodes nothing, and
/// `accessibility-audit.py` had already filed it as "a scale anchor carrying no
/// information at all". The lead's line stays as the note under the headline.
///
/// ## Liveness
///
/// Stores no `Thing` — only value types out of `CursorRoom`, filtered at the
/// boundary by `CursorRoomSource`. The tap hands back a `Repo` and the section
/// that owns the sheet does the lookup (corollary 5).
struct CursorRoomCard: View {
    let room: CursorRoom
    /// Hands back the REPOSITORY, not a `Thing` — the card never holds one.
    /// A repo owns many rows, so there is no single `sourceRef` it could name.
    var onOpen: (CursorRoom.Repo) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var drawn: [CursorRoom.Repo] {
        Array(room.repos.prefix(CursorRoomSource.rowCap))
    }

    /// The busiest repository's run count — the bar's full width, so every bar
    /// on the card is on one scale and two rows are comparable at a glance.
    private var top: Int { room.lead?.runs ?? 0 }

    var body: some View {
        DSRoomChassis.Head(
            // THE LEDE (prd §585). The door rides whichever branch draws,
            // because the headline is still the ONLY place the lead
            // repository's destination can be reached.
            lead: .figure(CursorRoom.lede(room), otherwise: CursorRoom.headline(room)),
            door: room.lead.map { lead in
                DSRoomChassis.Door(hint: Text("Opens this repository")) { onOpen(lead) }
            },
            notes: [.note(room.lead.map(CursorRoom.repoLine))],
            footnotes: [.quiet(CursorRoom.note(room, drawn: drawn.count))]) {
            // Only the repositories BEYOND the lead get a row — the lead is the
            // headline, and repeating its name directly underneath is the card
            // arguing with itself.
            if drawn.count > 1 {
                DSRoomChassis.Block {
                    ForEach(Array(drawn.dropFirst().enumerated()), id: \.element.id) { index, repo in
                        DSRoomChassis.Row(
                            title: repo.name,
                            truncation: .middle,
                            line: CursorRoom.repoLine(repo),
                            index: index,
                            action: { onOpen(repo) }) {
                            ShareBar(fraction: CursorRoom.share(runs: repo.runs, of: top),
                                     index: index + 1,
                                     reduceMotion: reduceMotion)
                        }
                    }
                }
            }
        }
    }
}
