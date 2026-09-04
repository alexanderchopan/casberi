import SwiftUI

/// THE STATE STAMP — the word in the top-right corner of a sheet head, saying
/// where the thing it describes currently stands (2026-08-28 component sweep).
///
/// **It was drawn twice and the two already disagreed.** `MoneyReceiptCard`'s
/// `ReceiptStampPill` washed its ink at 0.16 and stood 24pt tall; `DSSheetHead`
/// drew its own inline, washed at 0.14 with 3pt of vertical padding and took a
/// free-form `stampInk: Color`. Same word, two weights and two heights, on
/// sheets a person moves between in two taps — a wallet receipt and a vibenet
/// account, key or event. Neither is visible in a screenshot of one of them,
/// which is why it survived: this is the `design-ramp-audit` class ("one
/// screen, two states, two sizes") one level up, in a component.
///
/// **A closed WEIGHT, never an open colour.** The old `stampInk: Color` is what
/// let the drift happen at the call sites as well as in the two views: an
/// arbitrary colour on a state badge is how "Locked" ends up a different red
/// from "Revoked" with every check still green. The five weights are the money
/// receipt's own, which is where this vocabulary was settled — and note that
/// `waiting` and `urgent` share an ink deliberately. They are one colour and
/// two meanings, kept apart so a caller states which it means rather than
/// picking a colour, and so a future ruling can separate them in one place.
///
/// `quiet` is a real answer, not an absence — a settled refund is information,
/// not an alarm — and it is the default, so a caller that has not thought about
/// weight cannot accidentally raise an alarm.
struct DSStamp: View {
    enum Weight: Equatable {
        /// It went well and is over. Confirm green.
        case good
        /// It is in flight and nobody has to do anything yet.
        case waiting
        /// It is waiting on YOU. Same ink as `waiting`, different meaning.
        case urgent
        /// True, and not news. The default.
        case quiet
        /// Deliberately unknowable — the shield hue, never a warning colour.
        case shielded
    }

    let word: String
    var weight: Weight = .quiet

    var body: some View {
        Text(verbatim: word)
            .dsText(.label12)
            .foregroundStyle(ink)
            // A WORD, NOT A CAPSULE (prd §583, 2026-09-03). The wash and the
            // horizontal padding are deleted with the paper this pill used to
            // sit on: a capsule is a small card, and the ruling that took the
            // card off the head takes the card off the badge in the corner of
            // it for the same reason.
            //
            // **The ink is what carried the meaning and the ink is untouched**
            // — green still means it went well, attention still means it is in
            // flight or waiting on you — so nothing this component says is
            // lost. What goes is the second boundary drawn around one word.
            //
            // The 24pt minimum height STAYS, and is not leftover chrome: it is
            // what keeps the word's baseline where it was relative to the
            // subject disc across the row, so removing the wash does not
            // silently re-align six heads.
            .frame(minHeight: 24)
            // NOT hidden from VoiceOver here, deliberately. Whether the word
            // is already spoken is the CALLER's fact: `DSSheetHead` restates
            // it in the sentence below and hides the pill, the money receipt
            // does not and leaves it audible. Hiding it in the component
            // would have silently taken the state word off the receipt — the
            // kind of regression a component merge makes and nothing catches.
    }

    private var ink: Color {
        switch weight {
        case .good:     return DS.confirm
        case .waiting:  return DS.attention
        case .urgent:   return DS.attention
        case .quiet:    return DS.textTertiary
        case .shielded: return DS.receiptPour(.shield)
        }
    }

    // `wash` was HERE and is deleted with the capsule (prd §583). Its own doc
    // recorded the reason it was awkward — "a tertiary-grey wash is invisible
    // on a raised surface" — which was `quiet` telling us a fill behind one
    // word was never carrying much.
}
