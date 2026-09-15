import SwiftUI

/// THE AWS ROOM'S HEAD (2026-08-30) — where an account stands right now, led
/// by whatever needs a person most: a firing alarm, a failed deploy, a
/// spend anomaly, or — the common, healthy case — nothing at all.
///
/// The finding is a sentence, the resources a note under it, the region small
/// print — `DSRoomChassis.Head`'s anatomy since prd §745, and no colour coding
/// a Stripe dispute wouldn't also refuse: the finding is in the WORDS, never
/// in green/red.
///
/// Holds no `Thing` — a value type out of `AWSStanding`, filtered at the
/// boundary by `AWSRoomSource`. The tap opens the room the ordinary way.
struct AWSRoomCard: View {
    let standing: AWSStanding
    var onOpen: () -> Void

    var body: some View {
        DSRoomChassis.Head(
            lead: .sentence(AWSRoom.headline(standing)),
            door: DSRoomChassis.Door(hint: Text("Opens AWS"), action: onOpen),
            notes: [.note(AWSRoom.resourceLine(standing))],
            footnotes: [.quiet(standing.region)])
    }
}
