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
    /// Tapping a row walks to the card that states that position in full
    /// (2026-08-20, prd §417).
    ///
    /// Under §416's "What it's doing" header this strip is visibly the
    /// OVERVIEW and the cards below it the detail — which is exactly the pair
    /// this card's own doc describes ("the cards below state each position in
    /// its own protocol's units, and this is the one view that puts them in an
    /// order") and which the reader previously had to reconnect by scrolling
    /// and matching labels by eye.
    ///
    /// nil leaves every row inert, which is the honesty rule doing its job: a
    /// row with nowhere to go must not behave like a control. The card is
    /// still reachable by scrolling, so nothing here is tap-only.
    var onPick: ((WalletRiskScale.Entry) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // **COLUMNS STANDING ON A LIQUIDATION FLOOR (user pick, prd §493),
            // replacing the ranked bars of §483.**
            //
            // Those bars were correct and not visual enough: four horizontal
            // tracks with a percentage on each is a table with the numbers
            // right-aligned. The floor is the reading — a red line every column
            // stands on, and the shortest column visibly nearest it — and it is
            // a metaphor that is literally TRUE here, because the line is a
            // real price at which a real thing happens.
            //
            // §299's finding survives and is why this is columns rather than
            // dots: dots on a track read as nothing, and they crowd at exactly
            // the end that matters. A column has length, which is the property
            // being compared.
            Text(String(localized: "Room before liquidation"))
                .dsText(.label12).foregroundStyle(DS.textTertiary)
            GeometryReader { geo in
                floor(width: geo.size.width)
            }
            .frame(height: Self.chartHeight)
            .padding(.top, DS.Space.s2)
        }
        // The set speaks as ONE sentence in the ranked order (§299's ruling,
        // unchanged by the redraw): a screen reader hearing seven columns has
        // to hold the order itself, which is the whole reading.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(spokenAxis))
        .accessibilityActions {
            if let onPick {
                ForEach(entries) { entry in
                    Button("Open \(entry.label)") { onPick(entry) }
                }
            }
        }
    }

    /// **THE BOX, LESS THIS STRIP'S OWN CHROME (prd §588).** Wallet's scopes
    /// pass `reservesHeadline: false`, so this figure gets the whole of
    /// `visualSlot`; the chrome is the `label12` caption at 15 and the `s2`
    /// under it. At the old literal 158 this drew ~117pt of dead air once the
    /// box went to 300.
    private static var chartHeight: CGFloat {
        DSRoomChassis.crownLine(box: DSRoomChassis.visualSlot, chrome: 25)
    }
    /// Where the floor sits. Columns grow UP from it, so the space below is
    /// only the label strip's.
    ///
    /// **DERIVED FROM `chartHeight`, AND THAT IS THE POINT (prd §588).** Five
    /// things key off this number — the column heights
    /// (`clamped(headroom) * (floorY - 22)`), the floor line, the
    /// "liquidation" label and the name strip — so it is not a second constant
    /// but the same drawing's waistline. As a literal pair the two could be
    /// edited apart, and the failure is a floor line drawn across the middle
    /// of columns that grew past it. They were 118 of 158; the RATIO is what
    /// is preserved here, not either number.
    private static var floorY: CGFloat { (chartHeight * 118 / 158).rounded() }
    /// How many positions the slot draws before folding.
    private static let columnCap = 4

    @ViewBuilder
    private func floor(width: CGFloat) -> some View {
        let shown = Array(entries.prefix(Self.columnCap))
        let step = width / CGFloat(max(1, shown.count))
        let barWidth = max(20, step - DS.Space.s4)
        ZStack(alignment: .topLeading) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, entry in
                let h = max(8, clamped(entry.headroom) * (Self.floorY - 22))
                VStack(alignment: .leading, spacing: 0) {
                    // The PROTOCOL's own number, above its own column — never
                    // restated in a unit the protocol does not use, which is
                    // `Entry.detail`'s whole reason for existing.
                    Text(entry.detail)
                        .dsText(.label11).fontWeight(.semibold)
                        .foregroundStyle(entry.atRisk ? DS.attention : DS.confirm)
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .frame(width: barWidth, alignment: .leading)
                        .padding(.bottom, 3)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(entry.atRisk ? DS.attention : DS.confirm.opacity(0.8))
                        .frame(width: barWidth, height: h)
                    Spacer(minLength: 0)
                }
                .padding(.top, Self.floorY - h - 18)
                .offset(x: CGFloat(index) * step)
                .contentShape(Rectangle())
                .onTapGesture { onPick?(entry) }
                .accessibilityHidden(true)
            }
            // THE FLOOR. Drawn over the columns rather than under them, so a
            // position sitting at zero headroom still shows a line through it
            // rather than a bar that merely stops somewhere.
            Rectangle()
                .fill(DS.destructive)
                .frame(height: 1.5)
                .offset(y: Self.floorY)
            Text(String(localized: "liquidation"))
                .dsText(.label11).foregroundStyle(DS.destructive)
                .padding(.top, Self.floorY + 4)
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { _, entry in
                    Text(entry.label)
                        .dsText(.label11).foregroundStyle(DS.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .frame(width: barWidth, alignment: .leading)
                        .frame(width: step, alignment: .leading)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, Self.floorY + 22)
        }
    }

    private func clamped(_ v: Double) -> CGFloat {
        CGFloat(min(max(v, 0), 1))
    }

    /// The axis as a sentence, nearest-the-edge first — the order the bars
    /// are already ranked in, so the drawing and the speech agree.
    private var spokenAxis: String {
        guard !entries.isEmpty else { return String(localized: "Nothing leveraged.") }
        let listed = entries.map { "\($0.label), \($0.detail)" }.joined(separator: "; ")
        return String(localized: "Distance to liquidation, closest first: \(listed).")
    }
}
