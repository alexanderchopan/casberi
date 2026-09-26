import SwiftUI

/// Every leveraged position on one axis — "Distance to liquidation"
/// (2026-08-01, ruled in from `design/wallet-viz`).
///
/// The room states risk per protocol in each protocol's own units, so "which
/// of these is closest to the edge" was arithmetic across three scales. The
/// axis that makes them comparable — and the reason it's an honest comparison
/// rather than an invented one — is derived in `WalletRiskScale`.
///
/// Two design decisions worth not undoing:
///
/// **The track carries no crossing point.** It would be prettier as a
/// green→amber→red gradient, and it would be a lie: the two shipped alert
/// thresholds sit at different headroom (33% for lending, 15% for perps), so
/// any single painted boundary must disagree with one of the two sweeps. The
/// track is a neutral well with only its far END tinted, and each dot's colour
/// comes from its own protocol's rule.
///
/// **Labels alternate above and below.** Three dots on a 300pt track collide
/// constantly at the crowded end, and the crowded end is exactly where the
/// dangerous positions are. Alternating buys roughly double the label room
/// where it's needed most.
///
/// No `Thing` is stored anywhere here — the entries are value types by the
/// time they arrive — so the liveness rules (CLAUDE.md corollaries 1–5) have
/// nothing to bite on.
/// **The dots travel** (2026-08-03, prd §297). Each one starts at the
/// comfortable end and moves to its reading, closest-to-the-edge FIRST —
/// `entries` is already sorted worst-first, so following index order for the
/// stagger makes the entrance narrate the ranking the card already made (the
/// treemap's largest-first rule, on a different axis). This is the
/// one entrance on the card that isn't decoration: the whole card is an
/// argument that three incomparable protocol units share one axis, and watching
/// a dot travel ALONG that axis is that argument made in time. A fade-in would
/// have said nothing the static frame doesn't.
///
/// It is not an alarm and must not become one — each bar grows to its true
/// length and stops, with no overshoot and no repeat.
struct WalletRiskStrip: View {
    let entries: [WalletRiskScale.Entry]
    /// The scope's caption, the crown's own (prd §927).
    var caption: String? = nil
    var onPick: ((WalletRiskScale.Entry) -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// **THE PRESSED POSITION (prd §927)** — while set, the reading reads it
    /// and the rest go quiet; the reading is then its door (`onPick`).
    @State private var lit: String?

    private static let columnCap = 4
    private var shown: [WalletRiskScale.Entry] { Array(entries.prefix(Self.columnCap)) }
    private var pressed: WalletRiskScale.Entry? { lit.flatMap { id in shown.first { $0.id == id } } }
    /// Closest to the floor first — the entries come sorted that way.
    private var closest: WalletRiskScale.Entry? { entries.first }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            reading
            // **THE FLOOR IS THE FLOOR (prd §927).** The bars stand on the
            // bottom of the figure and that edge IS liquidation — the word
            // sits there, in the alarm ink, and nothing draws a line (the
            // 1.5pt red rule is gone). Height is room before the floor, as
            // `WalletRiskScale` derives it; colour is each protocol's own
            // alarm, as §before, never a painted threshold.
            GeometryReader { geo in
                columns(height: geo.size.height)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(alignment: .top, spacing: DS.Space.s3) {
                ForEach(shown) { entry in
                    Text(entry.label)
                        .dsText(.label12)
                        .foregroundStyle(lit == entry.id ? DS.textPrimary : DS.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.55)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .opacity(lit != nil && lit != entry.id ? 0.3 : 1)
                }
            }
            Text(String(localized: "liquidation"))
                .dsText(.label12)
                .foregroundStyle(DS.destructive)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(reduceMotion ? nil : DS.Motion.standard, value: lit)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(spokenAxis))
    }

    /// **ONE NUMBER, ONE CAPTION (prd §936).** At rest, how many positions
    /// are leveraged, with the at-risk count in the alarm ink; under a press,
    /// that position's room before liquidation, and a door to it.
    @ViewBuilder
    private var reading: some View {
        let door: (() -> Void)? = pressed.flatMap { entry in onPick.map { pick in { pick(entry) } } }
        let atRisk = entries.filter(\.atRisk).count
        let block: DSFigureReading = {
            if let pressed {
                let room = Int((min(max(pressed.headroom, 0), 1) * 100).rounded())
                return DSFigureReading(number: "\(room)%",
                                       caption: String(localized: "\(pressed.label) · room before liquidation"),
                                       numberInk: pressed.atRisk ? DS.destructive : DS.textPrimary)
            }
            return DSFigureReading(number: String(entries.count),
                                   caption: [String(localized: "leveraged"), caption].compactMap { $0 }
                                       .joined(separator: " · "),
                                   alarm: atRisk > 0 ? String(localized: "\(String(atRisk)) at risk") : nil)
        }()
        if let door {
            Button(action: door) { block.contentShape(Rectangle()) }
                .buttonStyle(.plain)
        } else {
            block
        }
    }

    @ViewBuilder
    private func columns(height: CGFloat) -> some View {
        HStack(alignment: .bottom, spacing: DS.Space.s3) {
            ForEach(shown) { entry in
                let h = max(8, clamped(entry.headroom) * height)
                let quiet = lit != nil && lit != entry.id
                Button {
                    DSHaptic.selection()
                    lit = lit == entry.id ? nil : entry.id
                } label: {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(entry.atRisk ? DS.destructive : DS.tint)
                            .frame(height: h)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .opacity(quiet ? 0.3 : 1)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressSpring())
                .accessibilityLabel(Text("\(entry.label), \(entry.detail)"))
                .accessibilityAddTraits(lit == entry.id ? .isSelected : [])
            }
        }
        .frame(height: height)
    }

    private func clamped(_ v: Double) -> CGFloat {
        CGFloat(min(max(v, 0), 1))
    }

    private var spokenAxis: String {
        guard !entries.isEmpty else { return String(localized: "Nothing leveraged.") }
        let listed = entries.map { "\($0.label), \($0.detail)" }.joined(separator: "; ")
        return String(localized: "Distance to liquidation, closest first: \(listed).")
    }
}
