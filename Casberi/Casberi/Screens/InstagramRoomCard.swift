import SwiftUI

/// THE INSTAGRAM ROOM'S HEAD (2026-08-18, prd §395) — the library: how big it
/// is, how long it took, and how much of it Instagram has since deleted.
///
/// **The account board is deleted (prd §745).** This card carried
/// `FeedInsight.leaderboard`'s "Who you save most" forward whole — its own doc
/// said so, on §349's rule that a head may never draw less than what it
/// displaces. §723 then deleted that board from every room as visualization for
/// its own sake, and this copy survived only because it was drawn by hand here
/// rather than through the leaderboard. What is left is the three facts the
/// board could not state, which were always the reason for this head.
///
/// ## Liveness
///
/// Stores no `Thing` — only value types out of `InstagramRoom`, filtered at the
/// boundary by `InstagramRoomSource`. The tap hands back an `Account` and the
/// section that owns the sheet does the lookup (corollary 5).
struct InstagramRoomCard: View {
    let room: InstagramRoom
    /// Hands back the ACCOUNT, not a `Thing` — an account owns many rows, so the
    /// honest landing is its newest kept post.
    var onOpen: (InstagramRoom.Account) -> Void

    var body: some View {
        DSRoomChassis.Head(
            lead: .figure(InstagramRoom.lede(room), otherwise: InstagramRoom.headline(room)),
            door: room.accounts.first.map { lead in
                DSRoomChassis.Door(hint: Text("Opens the newest post you kept")) { onOpen(lead) }
            },
            notes: [.note(InstagramRoom.note(room))],
            footnotes: [.quiet(InstagramRoom.footnote(room))])
    }
}
