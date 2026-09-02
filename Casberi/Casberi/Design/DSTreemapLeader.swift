import SwiftUI

/// **THE TREEMAP'S LEADER CELL, AT THE HEAD RUNG (prd §565).**
///
/// Every treemap in this app tiles `UnitTreemap.frames(_:)` — a fixed rank
/// table where AREA says "roughly where in the order" and `DS.ink(magnitude:)`
/// says "how much" — and until now every cell also wore the SAME label rung as
/// every other, so a map had two tiers of area and one tier of type. The
/// biggest slot said its name no louder than the smallest.
///
/// This is §559's grammar rotated onto a figure: the mark top-left where it
/// earns a place, the number at `price40` hard against the bottom-left, its
/// name dropped to `label12` beside the baseline. **Slot 0 only, and the tail
/// of the map is untouched** — same slots, same ramp, same 12pt names — so the
/// change is one cell and the tiling `x402-selftest.sh` guards never moves.
///
/// **THE RULE THAT DECIDES A CALLER: the leader must be sayable as a NUMBER.**
/// A share, a count, a tally. Where the leader is a WORD this must not be used:
/// a term at 40pt is a headline, a claim about importance made in the largest
/// type on the card, and §382a already demoted the themes map for exactly that
/// (its cells "are things you must read before they say anything"). The two
/// word maps — `TopicMapHero` and `GenTagMap` — are guarded OUT mechanically
/// rather than merely advised against.
///
/// **The figure and the name are separate parameters on purpose.** A single
/// "title" would let a caller pass "github.com" and get a headline, which is
/// the whole failure this component's rule exists to prevent; splitting them
/// makes the wrong call impossible to write by accident rather than merely
/// wrong when reviewed.
///
/// **THE DISC IS OPTIONAL, AND ABSENT IS THE COMMON CASE.** In the panel
/// (§553) the disc says HOW the act happens; here it would say WHO — so it
/// earns its place only when it carries identity the cell does not otherwise
/// draw, like a token's bundled brand mark. Where the fallback would be a
/// monogram of the very name printed beneath it, it is redundant and is left
/// out (`AssetMark`'s no-invented-hue rule, one step further: a mark that
/// restates its own caption is not a mark).
///
/// **What it must never carry: a balance.** §374's rule is that figures go and
/// shapes stay, so a share ("62%") and a count ("1,240") are safe where a
/// currency total is not. The callers below state counts; the Hegotá UTXO map
/// is deliberately NOT a caller because its leader would be an amount of ETH.
struct DSTreemapLeader<Mark: View>: View {
    /// The number, already formatted by the caller — only the caller knows
    /// whether its magnitude is requests, services, posts or a share.
    let figure: String
    /// What the number is OF. Sits at the quiet rung beside the baseline.
    let name: String
    /// The identity mark, where one exists that the caption does not restate.
    @ViewBuilder var mark: () -> Mark

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            mark()
            Spacer(minLength: DS.Space.s2)
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s1) {
                Text(figure)
                    .dsText(.price40)
                    .foregroundStyle(DS.textPrimary)
                    .monospacedDigit()
                    // A five-figure count at 40pt heavy runs wider than the
                    // 172pt slot 0 gets at six cells. It shrinks rather than
                    // truncates: a clipped number is a WRONG number, and this
                    // one is the card's whole claim.
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(name)
                    .dsText(.label12)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .padding(DS.Space.s3)
    }
}

extension DSTreemapLeader where Mark == EmptyView {
    /// The common case: no mark, because a monogram would restate the name.
    init(figure: String, name: String) {
        self.init(figure: figure, name: name, mark: { EmptyView() })
    }
}
