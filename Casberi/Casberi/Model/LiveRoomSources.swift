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
    static let all: Set<String> = ["Kalshi", "Polymarket"]

    static func has(_ source: String) -> Bool { all.contains(source) }
}
