import SwiftUI

/// THE SHEET HEAD — one anatomy for what a thing sheet opens with (prd §495,
/// user: *"the sheet for activity should look in some way like the design we
/// have for wallet activity"*, then *"so should account sheets, and
/// permissions sheets"*).
///
/// **Lifted from `MoneyReceiptCard`, which is where this shape was settled**
/// (§363): a subject disc and a stamp on one row, then the lead, the subject's
/// own words, one supporting line, and one sentence saying what it means now.
/// That anatomy was written for money and is not about money — every part of
/// it answers a question any event has (who, what state, when, what happened,
/// what it means), which is why three vibenet sheets were each inventing a
/// worse version of it.
///
/// **It takes plain values, not a `MoneyReceipt`.** The receipt type carries
/// amounts, currencies and a finality that only a transaction has; coupling
/// the shape to it is what kept the shape in one room. What is shared here is
/// the ARRANGEMENT, and each caller decides what fills it.
///
/// The money receipt keeps its own card — it has a torn edge that carries
/// state (§363: torn means final, flat means the paper is still in the
/// machine) and an amount block with a signed figure, neither of which
/// generalises. This is its head, made available to sheets that have no
/// amount to draw.
struct DSSheetHead<Disc: View>: View {
    /// The subject, drawn as this sheet's own mark — a face, an identicon, a
    /// tinted glyph. Handed in rather than derived, so a room that already
    /// knows how to draw its subject keeps drawing it that way.
    @ViewBuilder let disc: () -> Disc
    /// The state word, top-right — "Authorized", "Revoked", "Locked". nil
    /// where the thing has no state worth stamping.
    var stamp: String?
    /// The stamp's ink. Neutral by default; a caller passes `DS.attention`
    /// only where the state is one somebody must act on.
    var stampInk: Color = DS.textSecondary
    /// When it happened, above the title — the receipt's own `lead`.
    var lead: String?
    /// The thing's own words. `heading22`, the receipt's `party` tier.
    let title: String
    /// One supporting line under the title — an id, a curve, a handle.
    var secondary: String?
    /// What it means NOW, in a sentence. The receipt's own closing line, and
    /// the part that makes a head an answer rather than a label.
    var sentence: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                disc()
                Spacer(minLength: DS.Space.s3)
                if let stamp {
                    Text(stamp)
                        .dsText(.label12)
                        .foregroundStyle(stampInk)
                        .padding(.horizontal, DS.Space.s2)
                        .padding(.vertical, 3)
                        .background(stampInk.opacity(0.14),
                                    in: Capsule(style: .continuous))
                        .accessibilityHidden(true)
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                if let lead {
                    Text(lead)
                        .dsText(.callout15)
                        .foregroundStyle(DS.textSecondary)
                }
                Text(title)
                    .dsText(.heading22)
                    .foregroundStyle(DS.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .padding(.top, DS.Space.s3)
            if let secondary {
                Text(secondary)
                    .dsText(.callout15)
                    .foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            if let sentence {
                Text(sentence)
                    .dsText(.callout15)
                    .foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, DS.Space.s4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
