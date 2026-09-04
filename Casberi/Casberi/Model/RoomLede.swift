import Foundation

/// THE LEDE — one figure, loud, with a sentence whispering under it (prd §585,
/// 2026-09-03, user: *"we have added exaggerated font sizes in the Devnets and
/// the Chat functionality which i like, and we added it on the All feed
/// too… for the lede"*).
///
/// **The device the three liked surfaces share is not "big type", it is a
/// SHORT FIGURE at the head rung with the words demoted under it.** That
/// distinction is the whole of this type's reason to exist, and it was bought
/// the hard way: §584 tried to make room heads louder by setting their
/// existing HEADLINE at 40pt, measured it, and found a composed sentence takes
/// 141pt on a card ~250pt tall. A figure cannot do that — it is short by
/// nature — so the loud rung is available to it and not to the sentence.
///
/// **NEVER PARSED OUT OF THE HEADLINE.** A room's `headline(_:)` is localized
/// prose; splitting a figure back out of it is exactly the "assembled from
/// stamped fields, never parsed back out of a localized title" rule §363 set
/// for the money receipt, and `money-receipt-selftest` greps for the violation.
/// Each room composes its lede from the SAME stored values its headline reads,
/// so the two can disagree only if the room itself is wrong.
///
/// **Returning nil is a real answer and the common one.** Measured across the
/// 20 rooms with a headline, roughly half open on a figure ("312 posts", "£1,240
/// this month", "14 days straight") and half on a statement with no figure at
/// all ("Payments have stopped", "Evidence was due yesterday", "Nothing to
/// report"). A statement keeps `heading22` and is CORRECT there — §584's
/// measurement is the reason, and forcing a figure out of a room that has none
/// would be inventing one, which on a money surface is §83.
struct RoomLede: Equatable {
    /// The figure, already locale-formatted by whoever stamped it. Drawn
    /// `verbatim` at `price40` — never re-interpolated (`MoneyReceiptCard`'s
    /// own rule: the string is a bridge's stamp or a `.formatted()` result and
    /// re-formatting it double-groups the digits).
    var figure: String
    /// The unit beside the figure — a currency code, "days", "posts". A rung
    /// DOWN at `label12`, so the number reads first.
    var unit: String?
    /// The sentence under it. This is where the app's voice lives — "days
    /// straight in 2023" rather than "streak: 14" — and it is the reason the
    /// figure can afford to say nothing on its own.
    var caption: String
    /// The figure as a `Double` where one really was counted, for the digit
    /// roll's direction. Optional and usually nil for money, whose display
    /// string is authoritative (`MoneyReceipt.Amount.numeric`'s own reasoning).
    var numeric: Double?

    init(figure: String, unit: String? = nil, caption: String, numeric: Double? = nil) {
        self.figure = figure
        self.unit = unit
        self.caption = caption
        self.numeric = numeric
    }
}
