import SwiftUI

/// The Ethrex Privacy room's drawing (prd §593).
///
/// **The window meter is the one thing this room has that nothing else in the
/// app does**, so it leads when there is one — and it is drawn only over a
/// LIVE root. An aged root gets the sentence and no meter, because a bar
/// reading near-empty and a bar with nothing to measure are different claims
/// (`PrivacyDevnetRoots.fraction` returns nil rather than zero for exactly
/// this reason, and the harness pins it).
///
/// **No colour carries state here.** The meter is the tint at one opacity and
/// the track is `DS.fillFaint`; nothing is red for aged or green for live,
/// because neither is good or bad — a proof whose snapshot has left the ring
/// was valid when it landed and its transaction is settled. Colour would say
/// something the chain does not.
struct PrivacyDevnetRoomCard: View {
    let head: PrivacyDevnetRoom.Head

    /// §299: a drawing sized from data gets an entrance, and the entrance
    /// honours Reduce Motion. The meter is the only thing here whose SIZE
    /// carries a number, so the wipe is on it and nothing else — animating the
    /// sentence would be motion on text that says the same thing either way.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // **The row is NOT reserved** (§495's rule): this card's own sentence
        // IS the headline, so reserving a blank line above it would push the
        // whole card down and misalign it with every other scope.
        DSRoomSlot(headline: nil, reservesHeadline: false) { content }
    }

    @ViewBuilder private var content: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            Text(PrivacyDevnetRoom.sentence(head))
                .dsText(.heading22)
                .fixedSize(horizontal: false, vertical: true)

            if let fraction = head.windowFraction {
                window(fraction)
            }

            if !facts.isEmpty {
                HStack(spacing: DS.Space.s4) {
                    ForEach(facts, id: \.label) { fact in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(fact.value)
                                .dsText(.stat24)
                                .monospacedDigit()
                            Text(fact.label)
                                .dsText(.subhead13)
                                .foregroundStyle(DS.textTertiary)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// How much of the 8192-slot ring the freshest referenced root has left.
    @ViewBuilder private func window(_ fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.fillFaint)
                    Capsule()
                        .fill(DS.tint)
                        // Clamped, because a head slot behind the reference
                        // would otherwise draw a bar wider than its track —
                        // and that state is real (a lagging RPC), not
                        // hypothetical.
                        .frame(width: geo.size.width * min(max(fraction, 0), 1))
                }
            }
            .frame(height: 6)
            // The wipe reveals the bar left to right, in the direction the
            // window actually drains.
            .chartWipe(reduceMotion: reduceMotion)
            Text(String(localized: "How much of the chain's memory this proof's snapshot still has"))
                .dsText(.subhead13)
                .foregroundStyle(DS.textTertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "Snapshot window"))
        .accessibilityValue(Text(String(format: "%.0f%%", fraction * 100)))
    }

    /// The counts under the sentence.
    ///
    /// **A count of ZERO is omitted rather than drawn**, and Sponsors is why
    /// that matters: no transaction measured on this chain has a payer
    /// differing from its sender, so a "0 sponsored" tile would be a permanent
    /// zero on every device — the dead control §83 bans, wearing a number.
    private struct Fact { let value: String; let label: String }

    private var facts: [Fact] {
        var out: [Fact] = []
        if head.nullifierCount > 0 {
            out.append(Fact(value: "\(head.nullifierCount)",
                            label: head.nullifierCount == 1
                                ? String(localized: "spend key")
                                : String(localized: "spend keys")))
        }
        if head.frameCount > 0 {
            out.append(Fact(value: "\(head.frameCount)",
                            label: head.frameCount == 1
                                ? String(localized: "frame")
                                : String(localized: "frames")))
        }
        if head.sponsoredCount > 0 {
            out.append(Fact(value: "\(head.sponsoredCount)",
                            label: String(localized: "sponsored")))
        }
        return out
    }
}
