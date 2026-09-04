import SwiftUI

/// THE LEDE, DRAWN (prd §585) — `FeedLedeCard.moneyBlock`'s shape, made
/// available to every room head that has a figure to lead with.
///
/// **One shape, so the app reads as one hand.** The All feed's lede, the two
/// devnet heads and the chat composer had each arrived at the same
/// arrangement independently — a `price40` figure, its unit a rung down, the
/// words demoted underneath — and the other twenty-odd room heads opened on a
/// `heading22` sentence instead. This is that arrangement extracted rather
/// than re-drawn, so a room joining it cannot drift into a fifth version of
/// it (§498's rule, and the reason §583 kept a modifier when it deleted the
/// paper).
///
/// **The arrival and the roll are BUILT IN, not left to the caller** (§585
/// items 3 and 4). The app had four separate entrance modifiers and
/// `numericText` on sixteen files but not on every big figure, so a number
/// might count up in one room and blink in the next. Personality in motion
/// comes from ONE recognisable move; putting it inside the component is what
/// makes that true by construction rather than by memory.
struct RoomLedeView: View {
    let lede: RoomLede
    /// The accessible sentence for the whole block. The figure and its caption
    /// are one statement, so they are spoken as one — reading "312" and "posts
    /// saved from 48 accounts" as two elements is how a screen reader turns a
    /// lede back into a jumble.
    var spoken: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2 - 2) {
                Text(verbatim: lede.figure)
                    // The hero rung. `price40` and never `price48`: §506's
                    // crown is one per surface, and a room head sits under
                    // the chip strip that already spends it.
                    .dsText(.price40)
                    .monospacedDigit()
                    // IT COUNTS TO ITS VALUE (§585). `value:` gives the roll a
                    // direction where a real number was counted; without it
                    // the digits still transition, they just do not know which
                    // way they are going — `MoneyReceiptCard`'s own note.
                    .contentTransition(lede.numeric.map { .numericText(value: $0) }
                                       ?? .numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(DS.textPrimary)
                if let unit = lede.unit {
                    Text(verbatim: unit)
                        .dsText(.label12)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                }
            }
            Text(lede.caption)
                // The quiet tier, and it stays quiet. §584 measured what
                // happens when this is promoted: in an extreme-proportion
                // system most text SHOULD whisper, or nothing shouts.
                .dsText(.label12)
                .foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // ONE arrival for every figure in the app.
        .settleIn()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(spoken ?? "\(lede.figure) \(lede.unit ?? "") \(lede.caption)"))
    }
}
