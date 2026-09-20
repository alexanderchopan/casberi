import Foundation

/// Sources whose ROOM has content of its own, independent of the corpus
/// (prd §234, 2026-07-29).
///
/// Every other bridge in this app is corpus-shaped: connecting it lands
/// things, and its chip exists in `MainSurface.chipLabels` precisely because
/// things with that source exist. The devnet rooms aren't — Hegotá, Frames and
/// the privacy devnet land no `Thing` ever; their content is live chain state.
/// Modelled the corpus way, a connected seat with nothing landed had no chip
/// and therefore no room. (The founding members were the prediction markets,
/// Kalshi and Polymarket, whose whole book was public and live; both were
/// deleted on 2026-09-06, prd §638.)
///
/// So: these sources get a chip the moment they're connected, and their room
/// renders its live content above whatever the corpus holds. Deliberately a
/// short explicit list rather than "every connected bridge" — a bridge whose
/// room would be empty without landed things must NOT get a chip that opens
/// onto nothing, which is exactly what a blanket rule would do to Gmail,
/// Photos and every other sync-shaped seat.
enum LiveRoomSources {
    /// Sources whose ROOM has live content, so the chip is earned by the
    /// connection rather than by landed things — and so the room must not draw
    /// the generic "nothing here yet" empty state.
    /// `FramesIdentity.source` joins for Hegotá's exact reason and NOT the
    /// venues' (prd §548): it lands no `Thing` ever, so without membership its
    /// room draws the corpus-shaped empty state over live chain content — and
    /// `FeedScreen`'s two arms both fall through, which is a BLACK SCREEN.
    /// It is deliberately absent from `venues` below: that narrower set drew
    /// `PredictionRoomBook`, and adding Hegotá to the wrong one is why a device
    /// report read "when i click on hegota it is showing me prediction
    /// markets".
    /// `PrivacyDevnetIdentity.source` joins for exactly Hegotá's and Frames'
    /// reason, and it is the same ruling rather than a third one: it lands no
    /// `Thing` ever. **NOT in `venues` below**, which is the mistake that
    /// produced "when i click on hegota it is showing me prediction markets" —
    /// that narrower set drew `PredictionRoomBook`.
    /// Kalshi and Polymarket were the founding members and left on 2026-09-06
    /// with their code (prd §638's third amendment). Their rows persist in a
    /// corpus that has them, but `Corpus.retiredSources` refuses those rows a
    /// room, so membership here could not reach them anyway.
    static let all: Set<String> = [HegotaIdentity.source, FramesIdentity.source,
                                   PrivacyDevnetIdentity.source]

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
    /// **It is SEPARATE from `all` above, and that separation is load-bearing.**
    /// `all` means "this room has live content and must not draw the corpus
    /// empty state", which for the three devnets is true forever because they
    /// land no `Thing` ever. An agent room is the opposite: it lands rows, it
    /// just has none YET. Folding these names into `all` would tell the feed
    /// this room never has rows, which is the mistake that file's own doc
    /// records twice — and `FeedScreen` already handles the empty agent room
    /// through `roomAgent` (§841), which draws the tiles over nothing.
    ///
    /// Read only by the dock's connected-seat door.
    static func keyedAgent(_ source: String) -> Bool {
        AgentProvider.allCases.contains { $0.agent == source }
    }

    /// **The prediction venues, and ONLY them — now EMPTY, and kept.**
    ///
    /// Kalshi and Polymarket, its only two members, were deleted on 2026-09-06.
    /// The set stays rather than going with them because the LESSON below is
    /// the file's whole reason for existing, and an empty set states it as
    /// plainly as a full one: a registry whose membership means several
    /// unrelated things hands every new member all of them. The next landless
    /// seat that wants a chip and nothing else adds itself to `all`, sees this
    /// set empty, and is told exactly why by the text under it.
    ///
    /// Split out of `all` on 2026-08-27, from a device report: adding Hegotá to
    /// this file made its room draw the Kalshi/Polymarket browse book —
    /// "when i click on hegota it is showing me prediction markets". The set had
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

    static func has(_ source: String) -> Bool { all.contains(source) }
}
