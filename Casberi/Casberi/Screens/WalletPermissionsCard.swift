import SwiftUI

/// WHO CAN ACT FOR YOU — the `Permissions` scope's lead drawing (prd §490,
/// reshaped as COUNTS by §546).
///
/// Every judgement is `WalletPermissions`'; this is its shape. Five things it
/// does on purpose:
///
/// - **Aggregate figures, no names (§546).** The slot used to draw each rung
///   as a count beside a name subline — which on a sparse wallet was the
///   acting list below restated word for word (user: *"we can't just repeat
///   the list"*). Counts are the one reading the per-actor list genuinely
///   does not have, so the slot is now up to four large numerals in a
///   two-column grid, each with its rung's sentence, and NOTHING here names a
///   holder — the list below owns the names, this owns the arithmetic.
/// - **The count is the figure and the sentence completes it.** The number is
///   meaningless without the rung it counts, which is what keeps this from
///   being the tally §292 refused.
/// - **Colour marks UNBOUNDEDNESS and nothing else.** Not severity, which
///   would be this app grading somebody's own decisions — a capped grant made
///   on purpose is not an alarm.
/// - **A rung states its total only when every holder in it is priced**
///   (`Rung.usd`), so a figure here is never a partial sum wearing a complete
///   one's clothes. It sits BESIDE the numeral rather than under the phrase —
///   a height decision, see `stat(_:)`.
/// - **Bare on the page**, like every other scope's lead (§483: *"we don't do
///   cards"*).
struct WalletPermissionsCard: View {
    let holders: [WalletPermissions.Holder]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var rungs: [WalletPermissions.Rung] { WalletPermissions.rungs(holders) }

    /// Two columns, top-leading. Four rungs at most (`rungsShown`) means the
    /// grid is never taller than two rows, which is what fits the slot — see
    /// the budget note on `stat(_:)`.
    private static let columns = [
        GridItem(.flexible(), spacing: DS.Space.s4, alignment: .topLeading),
        GridItem(.flexible(), spacing: DS.Space.s4, alignment: .topLeading)
    ]

    var body: some View {
        let drawn = Array(rungs.prefix(WalletPermissions.rungsShown))
        VStack(alignment: .leading, spacing: 0) {
            eyebrow
            LazyVGrid(columns: Self.columns, alignment: .leading, spacing: DS.Space.s2) {
                ForEach(drawn) { rung in
                    stat(rung)
                }
            }
            .padding(.top, DS.Space.s2)
            if let folded = WalletPermissions.foldedCount(rungs) {
                Text(String(localized: "and \(folded) more"))
                    .dsText(.label12).foregroundStyle(DS.textTertiary)
                    .padding(.top, 2)
            }
        }
        // ONE spoken sentence rather than four elements plus an eyebrow: the
        // card's claim is the ORDER, and a reader hearing each rung alone has
        // to hold that order themselves (§299, and `WalletRiskStrip`'s own
        // treatment two scopes over).
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(spoken))
    }

    /// The total, which the rungs deliberately cannot carry: they answer
    /// "what can be done", this answers "to how much". Silent when nothing
    /// here has a figure at all — a wallet whose only holder is a Safe module
    /// has real exposure and no dollars to state, and "$0" there would be the
    /// most misleading thing on the card.
    @ViewBuilder
    private var eyebrow: some View {
        if let total = WalletPermissions.totalUSD(holders) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                Text(WalletApprovalExposure.money(total))
                    .dsText(.stat24).foregroundStyle(DS.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
                Text(String(localized: "in reach"))
                    .dsText(.subhead13).foregroundStyle(DS.textSecondary)
            }
        } else {
            Text(String(localized: "Who can act for you"))
                .dsText(.stat24).foregroundStyle(DS.textPrimary)
        }
    }

    /// One cell of the grid: a large numeral, the rung's sentence beneath it.
    ///
    /// **The height budget, spelled from the ramp rather than measured**
    /// (`DSRoomChassis.headlineRow`'s own reasoning): the slot is a hard,
    /// clipped 210pt. Eyebrow 28 (`stat24`) + s2 + two grid rows of
    /// (40 numeral + 2 + 34 two-line phrase) + s2 between them = ~192, which
    /// clears the box with the fold line to spare. That budget is WHY the
    /// rung's dollar figure sits BESIDE the numeral rather than under the
    /// phrase — a third line per cell is 16pt spent four times, and the
    /// fourth rung's sentence is what it would shear off.
    ///
    /// The numeral is `price40`, the "figure that leads a card without being
    /// its crown" — one rung under the wallet total, which is right: this is
    /// a scope's figure, not the room's.
    private func stat(_ rung: WalletPermissions.Rung) -> some View {
        let tint = rung.power.isUnbounded ? DS.attention : DS.textPrimary
        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                Text("\(rung.count)")
                    .dsText(.price40).foregroundStyle(tint)
                    .monospacedDigit()
                if let aside = aside(rung) {
                    Text(aside)
                        .dsText(.label12).foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
            Text(rung.power.phrase)
                .dsText(.subhead13)
                .foregroundStyle(rung.power.isUnbounded
                                 ? DS.attention.opacity(0.9) : DS.textSecondary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The rung's total, beside its numeral — only when the rung is FULLY
    /// priced (§490's refusal: a partial sum looks complete, which is worse
    /// than no sum), and "no amount to state" only where a figure was
    /// EXPECTED (`Power.canCarryAmount`) — on a module or a collection grant
    /// it is an apology for a fact.
    ///
    /// No names, ever: the acting list and the approvals list directly below
    /// carry every holder, and a name here is the slot restating them (§546).
    private func aside(_ rung: WalletPermissions.Rung) -> String? {
        if let usd = rung.usd {
            return WalletApprovalExposure.money(usd)
        }
        if rung.hasUnpriced, rung.power.canCarryAmount {
            return String(localized: "no amount to state")
        }
        return nil
    }

    /// The card as one sentence, in the drawn order.
    private var spoken: String {
        guard !rungs.isEmpty else { return String(localized: "Nobody else can act for this wallet.") }
        let listed = rungs.map { "\($0.count) \($0.power.phrase)" }.joined(separator: "; ")
        if let total = WalletPermissions.totalUSD(holders) {
            return String(localized: "\(WalletApprovalExposure.money(total)) in reach. \(listed).")
        }
        return String(localized: "Who can act for you: \(listed).")
    }
}
