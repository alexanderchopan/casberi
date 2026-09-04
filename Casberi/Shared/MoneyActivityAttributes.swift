import Foundation
#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
import ActivityKit

/// A record that hasn't finished, on the lock screen (prd §369 amendment,
/// 2026-08-16) — the receipt's unfinished state, outside the app.
///
/// **Why an unfinished record is the right thing to put here and a finished one
/// isn't.** The receipt already says finality — in its silhouette until prd
/// §583 took the paper away, and in its stamp before and after. History does
/// not need a lock screen. What does is the
/// half-dozen states where you are WAITING on somebody else — a card
/// authorization that can still change, a Privacy Pools deposit in screening, a
/// Safe transaction short of its signatures — and the app's own answer to "has
/// it cleared yet?" was previously "open the app and look".
///
/// ## Three rulings, and each is the difference between this and an overclaim
///
/// **1. It never says it is watching.** The app learns a state changed on a
/// sweep — a foreground pass, or a `BGAppRefreshTask` iOS schedules whenever it
/// feels like it. So this carries `checkedAt` and the view SAYS it ("checked
/// 2h ago"), which is §306's own rule about notification copy applied to the
/// surface where the temptation is strongest. A Live Activity's whole grammar
/// implies "now", and the honest version of that here is a timestamp, not a
/// spinner.
///
/// **2. It is opt-in, per record.** Starting one automatically for every
/// pending row would give a card user four activities they never asked for, and
/// would fail the same "did you already know?" test that keeps §313's card
/// charges from notifying at all. So it starts from a control that appears ONLY
/// on a flat receipt — the edge earns the verb — and the person picks the one
/// they are actually waiting on.
///
/// **3. NO FIGURE.** Not masked — absent. The lock screen is the most
/// stood-next-to surface the OS has, and §374's rule is that figures go while
/// shapes stay. Masking would mean carrying `••••` in a payload handed to the
/// system, and the widget payload already settled this shape: withholding
/// removes the leak path instead of papering it. Nothing here needs an amount
/// anyway — the question is "has it settled?", not "how much was it?", and the
/// answer to the second is one tap away in the app.
struct MoneyActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// The stamp word, exactly as the receipt draws it — "Pending",
        /// "Screening", "Your turn". Passed through rather than re-derived, so
        /// the lock screen and the card can never disagree about the state.
        var stamp: String
        /// When the app last CONFIRMED that stamp. The view renders this as a
        /// relative age and never hides it.
        var checkedAt: Date
        /// Set once the record tore. The activity ends on it.
        var settled: Bool
    }

    /// The receipt's lead and party — "Spent at Tartine Bakery", "Safe ·
    /// Treasury". Never an amount (see rule 3 above).
    var title: String
    /// `Thing.id`, so tapping the activity opens the receipt it belongs to.
    var thingID: String
}
#endif
