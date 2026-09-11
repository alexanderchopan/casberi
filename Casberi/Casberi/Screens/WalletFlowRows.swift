import SwiftUI

/// WHERE THE MONEY MOVED, AS ROWS — the Wallet Home list (prd §692, user:
/// *"i don't like the sankey on the home list area it looks weird to have a
/// chart there now that i see it. can we change it to a list format"*).
///
/// **The reading is unchanged; the shape is not.** §690 put `WalletFlowBand`
/// in Home's list half because the crown says how much moved and the band says
/// through whom. That substance stands — this draws the SAME
/// `WalletFlow.Band`, so no number here can disagree with the one the brief's
/// band states. What changed is that the list half of a room is a list
/// everywhere else in this app, and a diagram sitting in it reads as a second
/// figure under the crown's own.
///
/// **Two blocks, because in and out are two facts.** A single list of signed
/// amounts makes the reader do the grouping the band did for free; captioned
/// blocks are the grammar this app already uses when one scope holds two kinds
/// of thing (`RoomListBlock`, Frames' sponsor list before it).
///
/// **A row says WHO, HOW MANY and HOW MUCH, and nothing else.** No share bar:
/// the amounts are already comparable as numbers down one column, and a bar
/// per row is the tally §292 refused. The folded "Other" lane keeps its own
/// row — dropping it would leave the two block totals unaccounted for, which
/// is the §510 contradiction (a census and a capped drawing disagreeing with
/// nothing to reconcile them).
///
/// The band itself is NOT deleted: `GenRenderer` draws it from
/// `TodayBrief.flowBand`, where a diagram in a brief is the right shape.
struct WalletFlowRows: View {
    let band: WalletFlow.Band
    /// The window the band was read over — "the last 24 hours", say. Stated
    /// once above the blocks rather than per block, since both describe it.
    let windowLabel: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s6) {
            if !band.inLanes.isEmpty {
                RoomListBlock(caption: String(localized: "Came in · \(windowLabel)")) {
                    lanes(band.inLanes, incoming: true)
                }
            }
            if !band.outLanes.isEmpty {
                RoomListBlock(caption: String(localized: "Went out · \(windowLabel)")) {
                    lanes(band.outLanes, incoming: false)
                }
            }
            if let note = unpricedNote {
                Text(note)
                    .dsText(.label11).foregroundStyle(DS.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func lanes(_ lanes: [WalletFlow.Lane], incoming: Bool) -> some View {
        VStack(spacing: DS.Space.s2) {
            ForEach(Array(lanes.enumerated()), id: \.element.id) { index, lane in
                WalletRow(mark: mark(lane),
                          title: title(lane),
                          subtitle: lane.count == 1
                              ? String(localized: "1 transaction")
                              : String(localized: "\(String(lane.count)) transactions")) {
                    // **THE SIGN IS THE DIRECTION, and the block caption says
                    // it too.** Both, deliberately: a row read alone — by
                    // VoiceOver, or scrolled past its caption — has to carry
                    // which way the money went.
                    WalletRowValue(value: (incoming ? "+" : "−") + WalletValue.money(lane.usd))
                }
                .chartArrival(index: index, reduceMotion: reduceMotion)
            }
        }
    }

    /// A counterparty wears its FACE; the folded lane wears a glyph, because
    /// it is not a party at all.
    private func mark(_ lane: WalletFlow.Lane) -> WalletRow.Mark {
        if lane.isOther { return .symbol("ellipsis", tint: DS.textTertiary) }
        return .face(lane.key)
    }

    /// **An unnamed counterparty shows its ADDRESS, not an empty line.** The
    /// band could draw a value alone in a slab this narrow; a row has a title
    /// column that would sit blank, and a short address is what every other
    /// list in this app puts there.
    private func title(_ lane: WalletFlow.Lane) -> String {
        if !lane.name.isEmpty { return lane.name }
        return WalletStore.shortAddress(lane.key)
    }

    /// What the blocks could not price, said once. The band draws this inside
    /// its own frame; a list has no frame, so it goes at the foot.
    private var unpricedNote: String? {
        var parts: [String] = []
        if band.unpricedCount > 0 {
            parts.append(band.unpricedCount == 1
                         ? String(localized: "1 move had no price to read")
                         : String(localized: "\(String(band.unpricedCount)) moves had no price to read"))
        }
        if band.predatingCount > 0 {
            parts.append(band.predatingCount == 1
                         ? String(localized: "1 predates what this app priced")
                         : String(localized: "\(String(band.predatingCount)) predate what this app priced"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
