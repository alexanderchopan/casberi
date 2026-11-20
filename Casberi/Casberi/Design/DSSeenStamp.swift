import SwiftUI

/// **A FINDING YOU PUT AWAY IS STAMPED, THEN LEAVES (prd §1919, user: "i
/// think so but couldn't tell what it actually did").** Mark all as seen
/// turned rows grey and nothing else; now each row on screen takes the word
/// "Seen" on its trailing edge, one after another with a tick each, and the
/// rows leave together once the last has landed. `order` is the row's place
/// in that run; a row put away alone is 0.
struct DSSeenStamp: View {
    /// The gap between one stamp landing and the next.
    static let beat = 0.095
    /// Past this many the rest land together: a long list is not a drum roll.
    static let longestRun = 12

    let order: Int
    @State private var landed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        DSStamp(word: String(localized: "Seen"))
            .scaleEffect(landed ? 1 : 1.8)
            .opacity(landed ? 1 : 0)
            .onAppear {
                let delay = Double(min(order, Self.longestRun)) * Self.beat
                if reduceMotion {
                    landed = true
                } else {
                    withAnimation(DS.Motion.press.delay(delay)) { landed = true }
                }
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(delay))
                    DSHaptic.tap()
                }
            }
    }
}

/// **THE FINDINGS HAVE A HEAD OF THEIR OWN (prd §1919, user: "shouldn't the
/// mark as all seen be in a more clearer place so it doesn't look like it is
/// for the cosigner only thing?").** Mark all as seen stood as a bare row
/// under whatever section came before it. Now the findings open on their
/// own state, a section's gap below that section: the red shield and "N
/// new" with Mark all as seen under it, or the green shield and "All seen",
/// Home's own word (§1587). The green shield bounces once as it lands.
struct DSRisksStateRow: View {
    /// The findings not yet seen; none says All seen.
    let new: Int
    @State private var landed = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: DS.Space.s3) {
            ZStack {
                Color.clear.frame(width: DS.Face.row, height: DS.Face.row)
                Image(systemName: new > 0 ? "exclamationmark.shield" : "checkmark.shield")
                    .dsGlyph(.body, weight: .semibold)
                    .foregroundStyle(new > 0 ? DS.destructive : DS.confirm)
                    .symbolEffect(.bounce, value: landed)
                    .accessibilityHidden(true)
            }
            Text(verbatim: new > 0 ? String(localized: "\(new) new") : String(localized: "All seen"))
                .dsText(.heading24)
                .monospacedDigit()
                .foregroundStyle(DS.textPrimary)
                .contentTransition(.numericText())
            Spacer(minLength: 0)
        }
        .frame(minHeight: DSFeed.headHeight)
        .padding(.top, DSRoomChassis.sectionGap - DS.Space.s4)
        .onAppear { if new == 0, !reduceMotion { landed += 1 } }
    }
}
