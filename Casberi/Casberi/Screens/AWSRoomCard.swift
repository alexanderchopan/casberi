import SwiftUI

/// THE AWS ROOM'S HEAD (2026-08-30) — where an account stands right now, led
/// by whatever needs a person most: a firing alarm, a failed deploy, a
/// spend anomaly, or — the common, healthy case — nothing at all.
///
/// The anatomy is `AppStoreConnectRoomCard`'s/`CursorRoomCard`'s: a heavy
/// headline stating the whole finding as a sentence, a resource line under
/// it, and no colour coding a Stripe dispute wouldn't also refuse — the
/// finding is in the WORDS, never in green/red.
///
/// Holds no `Thing` — a value type out of `AWSStanding`, filtered at the
/// boundary by `AWSRoomSource`. The tap opens the room the ordinary way.
struct AWSRoomCard: View {
    let standing: AWSStanding
    var onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(AWSRoom.headline(standing))
                .dsText(.heading22)
                .foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .dsCardLead(Text("Opens AWS")) {
                    DSHaptic.selection()
                    onOpen()
                }

            if let resources = AWSRoom.resourceLine(standing) {
                Text(resources)
                    .dsText(.subhead13)
                    .foregroundStyle(DS.textSecondary)
                    .padding(.top, DS.Space.s1)
            }

            Text(standing.region)
                .dsText(.label12)
                .foregroundStyle(DS.textTertiary)
                .padding(.top, DS.Space.s2)
        }
        .padding(DS.Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsWidgetSurface()
        .padding(.horizontal, DS.Space.s4)
        .padding(.top, DS.Space.s2)
        .contentShape(Rectangle())
        .onTapGesture {
            DSHaptic.selection()
            onOpen()
        }
    }
}
