import Foundation

/// WHAT A ROOM SAYS WHEN IT HAS NOTHING (2026-08-04, prd §299).
///
/// Until now every empty room in the app said the same thing: *"Let's fill this
/// feed. Connect an app and things start landing on their own."* That sentence
/// is right exactly once — on All, for someone who has connected nothing. In a
/// SOURCE room it is wrong in three different ways at once, and the third is a
/// real failure:
///
/// - **Connected and quiet** reads as "you haven't connected anything", to
///   someone looking at the room of an app they connected this morning.
/// - **Paused** reads the same way, so the state they chose is invisible.
/// - **Broken** reads the same way too — and that is the bad one. A bridge
///   whose token was refused, whose account was disconnected, whose key
///   expired, renders as a cheerful invitation to connect an app. The one
///   screen where the failure should be unmissable is the one screen that
///   hides it.
///
/// This is the generalisation of a ruling the app already made once, for
/// Trello (§291 follow-up): *a successful read that finds NOTHING explains
/// itself*, because a working connection that legitimately lands zero is
/// otherwise indistinguishable from a broken one. That was a sentence on one
/// setup screen. This is the same sentence where people actually stand.
///
/// ## The rule
///
/// The room states the CONNECTION's state, then what that means for the
/// emptiness. Never an invitation to connect something already connected, and
/// never a cheerful line over a broken bridge.
///
/// Foundation-only so `scripts/room-heads-selftest.sh` compiles it whole. `Seat`
/// mirrors `BridgeApp.Status` rather than importing it — that type lives in a
/// SwiftUI file (it carries a `Color`), and a harness can't compile SwiftUI.
/// The mirror is three cases and the caller maps them in one `switch`; a drift
/// guard in the harness keeps the two in step.
enum RoomQuiet {

    enum Seat: Equatable {
        /// No bridge seat for this room at all — a room whose things arrive by
        /// capture (Photos before connecting, a pasted link) rather than by a
        /// connection. The generic invitation is correct here, so `compose`
        /// declines and the caller keeps what it had.
        case none
        case connected
        case attention
        case paused
    }

    struct Words: Equatable {
        let headline: String
        let detail: String
        /// Whether the room should offer the catalog door. A connected room
        /// must not (there is nothing to connect); a broken one must, because
        /// the fix lives on its setup screen.
        let offersDoor: Bool
    }

    /// What this room says instead of the generic invitation, or nil to keep
    /// it.
    ///
    /// `emptyRead` is the bridge's own `emptyReadNote` — the sentence that
    /// explains why a WORKING read can legitimately find nothing (Trello reads
    /// only cards you're a member of; Cloudflare lands only what is close to
    /// expiring). Where a bridge has one it beats anything generic, because it
    /// names the actual reason.
    static func words(source: String, seat: Seat,
                      statusLine: String, emptyRead: String?) -> Words? {
        switch seat {
        case .none:
            return nil

        case .attention:
            // The failure, stated. This is the case the old copy actively hid.
            return Words(
                headline: String(localized: "\(source) needs attention."),
                detail: statusLine.isEmpty
                    ? String(localized: "Open it to see what went wrong and reconnect.")
                    : statusLine,
                offersDoor: true)

        case .paused:
            return Words(
                headline: String(localized: "\(source) is paused."),
                detail: String(localized: "Nothing new lands while it's paused. Resume it whenever you like."),
                offersDoor: true)

        case .connected:
            // Working, and genuinely empty. The bridge's own explanation wins
            // where it has one — it names the real reason, which no generic
            // sentence can.
            return Words(
                headline: String(localized: "\(source) is connected."),
                detail: emptyRead ?? String(localized: "Nothing has landed here yet. It syncs on its own — this room fills as things arrive."),
                offersDoor: false)
        }
    }
}
