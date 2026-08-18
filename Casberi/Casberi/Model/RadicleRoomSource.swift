import Foundation
import SwiftData

/// The Radicle room head's reading half (prd §401).
///
/// It reads **no rows at all** — the `ASCRoomSource` shape, and for the same
/// reason. A landed Radicle row says a patch was PROPOSED or an issue OPENED;
/// nothing in the corpus can say either is still unresolved. "Has no merge row
/// yet" is a different and wrong claim, since an ARCHIVED patch never gets one
/// either and would sit on this card forever.
///
/// So the subject is bridge STATE: `RadicleStore.openItems`, written by the
/// sweep from the patch and issue pages it already fetches. `things` is taken
/// for signature parity with every other `…RoomSource` in the `sourceHead`
/// chain and deliberately ignored — which also means this card and the setup
/// screen can never disagree about the same repos.
enum RadicleRoomSource {

    static let source = "Radicle"

    @MainActor
    static func compose(things: [Thing] = [], now: Date = .now) -> RadicleRoom? {
        RadicleRoom.compose(repos: RadicleStore.shared.allOpen)
    }
}
