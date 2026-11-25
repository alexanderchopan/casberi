import Foundation

/// Seats whose ROOM is earned by the connection, not by landed things
/// (prd §234, 2026-07-29; §842; §1036).
///
/// Every bridge in this app is corpus-shaped: connecting it lands things,
/// and its chip exists in `MainSurface.chipLabels` because things with that
/// source exist. Modelled only that way, a connected seat with nothing
/// landed had no chip and therefore no room. The live-room members that
/// first earned a chip by connecting alone — Kalshi and Polymarket, then the
/// devnets, Logos the last — are deleted (prd §638, §1206, and Logos with
/// the Testnets category on 2026-11-25), so what is left is the two doors
/// below: a keyed agent, and every other connected seat's empty room.
enum LiveRoomSources {
    /// **A KEYED AGENT EARNS ITS CHIP BY HOLDING A KEY (prd §842).**
    ///
    /// §839 gave an agent a room by landing its conversations, which earns a
    /// chip the ordinary way — and left a chicken-and-egg nobody could get out
    /// of: adding a Bankr key lands nothing, so there is no row, so there is no
    /// chip, so there is no room, so there is no Chat tile, so the only way to
    /// have the first conversation is still the account page's "Ask Bankr" —
    /// the buried door this whole feature exists to replace. Reported the day
    /// it shipped (user: *"i just added key to bankr and it didn't create a
    /// bankr room or an agent folder in the dock"*).
    ///
    /// An agent room lands rows, it just has none YET; `FeedScreen` handles
    /// the empty agent room through `roomAgent` (§841), which draws the tiles
    /// over nothing.
    ///
    /// Read only by the dock's connected-seat door.
    static func keyedAgent(_ source: String) -> Bool {
        AgentProvider.allCases.contains { $0.agent == source }
    }

    /// **EVERY CONNECTED SEAT HAS A ROOM, EMPTY OR NOT (prd §1036, §998
    /// widened).** The room is where an app's settings live (its door beside
    /// the name, §1033), and Apps draws a connected row as a status with no
    /// way in — so a seat that had landed nothing yet (Apple Health with no
    /// workout) was connected and unreachable. Its room stands empty instead,
    /// wearing `quietState`, with the door. Calendar, Reminders and the mail
    /// seats came in by this door too (prd §998); since they folded into Day
    /// (prd §1056) the empty seat gives Day its room.
    static func earnsEmptyRoom(_ seat: String) -> Bool {
        !landsNothing.contains(seat)
    }

    /// The seats that land no row under a source of their own, ever — so no
    /// room, and Apps keeps their row's door (prd §1036). The exchanges'
    /// balances ride the wallet; an answer from
    /// Apple Intelligence stores nothing; the validator is read in place.
    static let landsNothing: Set<String> = [
        "Apple Intelligence", "ETH Validators",
        "Kraken", "Coinbase", "Binance", "Gemini Exchange",
    ]

    /// **The prediction venues, and ONLY them — now EMPTY, and kept.**
    ///
    /// Kalshi and Polymarket, its only two members, were deleted on 2026-09-06.
    /// The set stays rather than going with them because the LESSON below is
    /// the file's whole reason for existing, and an empty set states it as
    /// plainly as a full one: a registry whose membership means several
    /// unrelated things hands every new member all of them. The next landless
    /// seat that wants a chip and nothing else sees this set empty, and is
    /// told exactly why by the text under it.
    ///
    /// Split out of `all` (the live-room set, deleted with Logos on
    /// 2026-11-25) on 2026-08-27, from a device report: adding a devnet
    /// to this file made its room draw the Kalshi/Polymarket browse book —
    /// "it is showing me prediction markets". The set had
    /// quietly grown THREE jobs and nothing separated them, because for two
    /// years its only members were the two venues and every job was true of
    /// both at once:
    ///
    ///   1. earn a chip while connected but landless  (general — `all`)
    ///   2. suppress the corpus-shaped empty state    (general — `all`)
    ///   3. draw `PredictionRoomBook`                 (venues only)
    ///   4. invalidate Kalshi's cache on a pull       (venues only)
    ///
    /// A registry whose membership means several unrelated things is one that
    /// hands every new member all of them. Jobs 3 and 4 read this narrower set,
    /// so the next landless seat inherited a chip and nothing else — which is
    /// the property that made this a fix rather than a patch. Both jobs went
    /// with the venues' code, so nothing reads the set now.
    static let predictionVenues: Set<String> = []
}
