import Foundation

/// Sources whose ROOM has content of its own, independent of the corpus
/// (prd §234, 2026-07-29).
///
/// Every other bridge in this app is corpus-shaped: connecting it lands
/// things, and its chip exists in `MainSurface.chipLabels` precisely because
/// things with that source exist. The prediction markets aren't — Kalshi and
/// Polymarket have no account and no sync; their whole book is public and
/// live, and "following" one market is a CHOICE made against that book, not
/// something a sync hands you. Modelled the corpus way, connecting them
/// meant nothing at all (the setup screen conflated connect with watching
/// your first market, which is why it grew into a browse screen it had no
/// business being) and a connected exchange with nothing followed yet had no
/// chip and therefore no room to browse FROM.
///
/// So: these sources get a chip the moment they're connected, and their room
/// renders the live book above whatever the corpus holds. Deliberately a
/// short explicit list rather than "every connected bridge" — a bridge whose
/// room would be empty without landed things must NOT get a chip that opens
/// onto nothing, which is exactly what a blanket rule would do to Gmail,
/// Photos and every other sync-shaped seat.
enum LiveRoomSources {
    /// Sources whose ROOM has live content, so the chip is earned by the
    /// connection rather than by landed things — and so the room must not draw
    /// the generic "nothing here yet" empty state.
    static let all: Set<String> = ["Kalshi", "Polymarket", HegotaIdentity.source]

    /// **The prediction venues, and ONLY them.**
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
    /// so the next landless seat inherits a chip and nothing else — which is
    /// the property that makes this a fix rather than a patch.
    static let predictionVenues: Set<String> = ["Kalshi", "Polymarket"]

    static func has(_ source: String) -> Bool { all.contains(source) }

    /// Is this room one of the prediction venues? Read by the browse book and
    /// by the pull-to-refresh cache invalidation, never by the chip.
    static func isPredictionVenue(_ source: String) -> Bool {
        predictionVenues.contains(source)
    }
}
