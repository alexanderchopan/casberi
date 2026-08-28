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
            .padding(.horizontal, DS.Space.s2)
            .frame(minHeight: 24)
            .background(wash, in: Capsule(style: .continuous))
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

    /// `quiet` takes the neutral fill rather than a wash of its own ink: a
    /// tertiary-grey wash is invisible on a raised surface, and a stamp you
    /// cannot see is worse than one that says nothing.
    private var wash: Color {
        switch weight {
        case .quiet: return DS.fillFaint
        default:     return ink.opacity(0.16)
        }
    }
}
