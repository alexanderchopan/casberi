import SwiftUI

/// WHO CAN ACT FOR YOU — the `Permissions` scope's lead drawing (prd §490).
///
/// Every judgement is `WalletPermissions`'; this is its shape. Four things it
/// does on purpose:
///
/// - **The count is the figure and the sentence completes it.** "2 · can move
///   a token with no limit" reads as one clause, which is what keeps this from
///   being the tally §292 refused: the number is meaningless without the rung
///   it counts, so they are drawn as one thing.
/// - **Colour marks UNBOUNDEDNESS and nothing else.** Not severity, which
///   would be this app grading somebody's own decisions — a capped grant made
///   on purpose is not an alarm.
/// - **A rung states its total only when every holder in it is priced**
///   (`Rung.usd`), so a figure here is never a partial sum wearing a complete
///   one's clothes.
/// - **Bare on the page**, like every other scope's lead (§483: *"we don't do
///   cards"*).
struct WalletPermissionsCard: View {
    let holders: [WalletPermissions.Holder]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var rungs: [WalletPermissions.Rung] { WalletPermissions.rungs(holders) }

    var body: some View {
        let drawn = Array(rungs.prefix(WalletPermissions.rungsShown))
        VStack(alignment: .leading, spacing: 0) {
            eyebrow
            VStack(alignment: .leading, spacing: 0) {
                ForEach(drawn) { rung in
                    row(rung)
                }
            }
            // s1, not s2: the eyebrow, four rungs and the fold line have to
            // clear a hard 210pt box, and at s2 the fourth rung's name was
            // cut in half on the device.
            .padding(.top, DS.Space.s1)
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

    private func row(_ rung: WalletPermissions.Rung) -> some View {
        let tint = rung.power.isUnbounded ? DS.attention : DS.textPrimary
        return HStack(alignment: .firstTextBaseline, spacing: DS.Space.s3) {
            Text("\(rung.count)")
                .dsText(.stat24).foregroundStyle(tint)
                .monospacedDigit()
                // A fixed column so the sentences line up down the card —
                // ragged left edges here would read as four unrelated rows
                // rather than one ranked set.
                .frame(width: 24, alignment: .leading)
            VStack(alignment: .leading, spacing: 0) {
                Text(rung.power.phrase)
                    .dsText(.callout15).foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                if let sub = subline(rung) {
                    Text(sub)
                        .dsText(.label12).foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        // ZERO. Four rungs plus the eyebrow plus the fold line have to clear a
        // hard 210pt box, and this was measured down from 3 in three passes on
        // the device rather than guessed: a rung is two lines of type, so every
        // point spent here is spent eight times, and at 3 the fourth rung's
        // name was cut in half. The rungs still separate — each is a figure
        // beside a two-line block, which is its own visual unit.
        .padding(.vertical, 0)
    }

    /// Who, and how much — in that order, because the name is what you act on
    /// and the figure is what you weigh.
    ///
    /// The figure is appended only when the rung is FULLY priced; a rung
    /// holding one unpriced grant says so by omission rather than by printing
    /// a total that quietly excludes it.
    private func subline(_ rung: WalletPermissions.Rung) -> String? {
        var parts: [String] = []
        if !rung.names.isEmpty {
            var who = rung.names.joined(separator: " · ")
            let unnamed = rung.count - rung.names.count
            if unnamed > 0 { who += String(localized: " and \(unnamed) more") }
            parts.append(who)
        }
        if let usd = rung.usd {
            parts.append(WalletApprovalExposure.money(usd))
        } else if rung.hasUnpriced, rung.power.canCarryAmount, !rung.names.isEmpty {
            // Only where a figure was EXPECTED — see `Power.canCarryAmount`.
            parts.append(String(localized: "no amount to state"))
        }
        if let note = rung.note { parts.append(note) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
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
