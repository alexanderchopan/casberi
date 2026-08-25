import Foundation
#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
import ActivityKit

/// THE TIMELOCK, ON THE LOCK SCREEN (prd §473).
///
/// A vibenet account can be put into an unlock delay — a security timelock
/// that runs for a fixed, known stretch and then opens. §472 made the in-app
/// countdown actually tick (it had been computed from `Date.now` at draw time
/// and frozen ever since), and a countdown to a known instant that you are
/// waiting on is the textbook Live Activity: the one reading in this room that
/// changes on its own, bounded, with an end you can name in advance.
///
/// **THE STATE CARRIES THE END, NOT THE REMAINDER, AND THAT IS THE WHOLE
/// DESIGN.** `MoneyActivityAttributes` has to carry `checkedAt` and be
/// refreshed, because "has this card charge settled" is a question only the
/// app can re-answer. A countdown to a fixed instant is not: hand the system
/// `unlocksAt` and `Text(timerInterval:)` counts down by itself, forever,
/// with **zero updates from us** — no background task, no push, nothing to
/// keep alive, and no way for the lock screen and the app to disagree about
/// the number. An activity carrying "18 minutes left" would be wrong within a
/// minute of being written.
///
/// **NOTHING HERE IS A SECRET AND NOTHING HERE IS MONEY.** The payload is an
/// account's display name and an instant. No balance, no key id, no address —
/// the §374 withholding rule the widget payload settled, applied to the
/// surface that is most stood next to.
struct VibenetUnlockActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// When the delay ends. The view hands this straight to
        /// `Text(timerInterval:)`, so the countdown is the system's own and
        /// needs no update from the app.
        var unlocksAt: Date
        /// Set when the account is no longer unlocking — it opened, or the
        /// owner re-locked it. The activity ends on it rather than being left
        /// to expire, so a cancelled unlock does not keep counting down to a
        /// moment that stopped meaning anything.
        var finished: Bool
    }

    /// The account's own name, or its short address — whatever the room calls
    /// it, passed through rather than re-derived so the lock screen can never
    /// name an account differently from the screen that started this.
    var accountName: String
    /// The watched address, so tapping the activity can scope the room to it.
    var address: String
}
#endif
