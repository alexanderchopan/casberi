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
/// It is not an alarm and must not become one — the dots land at their true
/// positions and stop, with no overshoot past the far end and no repeat.
struct WalletRiskStrip: View {
    let entries: [WalletRiskScale.Entry]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var travelled = false

    /// Room for the label rows above and below the track.
    private let labelBand: CGFloat = 30
    private let dotSize: CGFloat = 15

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            WalletSectionLabel(title: String(localized: "Distance to liquidation"))
            GeometryReader { geo in
                track(width: geo.size.width)
            }
            .frame(height: labelBand * 2 + dotSize)
            // Dots on a track read as nothing (2026-08-04, prd §299). The
            // card's whole claim is an ORDER — which position is closest to
            // liquidation — so the sentence is that order, spoken.
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(spokenAxis))
            HStack {
                Text("comfortable")
                    .dsText(.label12).foregroundStyle(DS.textTertiary)
                Spacer(minLength: 0)
                Text("liquidation")
                    .dsText(.label12).foregroundStyle(DS.textTertiary)
            }
            if let worst = entries.first, worst.atRisk {
                // The strip's own sentence, and the only place it spends
                // words: a dot at the far end is the thing the person came
                // here to find out.
                Text("\(worst.label) is the closest — \(worst.detail)")
                    .dsText(.label12).foregroundStyle(DS.attention)
                    .lineLimit(2)
            }
        }
        .padding(DS.Space.s3)
        .background(DS.fillFaint,
                    in: RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
        // A plain set: each dot owns its own delayed spring below, so the
        // stagger is per-entry rather than one move for the whole set.
        .onAppear { travelled = true }
    }

    /// The travel, staggered by rank. `nil` under Reduce Motion so the position
    /// change lands with no animation at all — the final frame, immediately.
    private func travel(_ index: Int) -> Animation? {
        reduceMotion ? nil
            : .spring(response: 0.75, dampingFraction: 0.9)
                // The track wipes itself in first: a reading travelling along
                // an axis that isn't drawn yet is a dot floating in a card.
                .delay(ChartEntrance.offset(index: index) + 0.25)
    }

    /// The axis as a sentence, nearest-the-edge first — the order the dots
    /// are already ranked in, so the drawing and the speech agree.
    private var spokenAxis: String {
        guard !entries.isEmpty else { return String(localized: "Nothing leveraged.") }
        let listed = entries.map { "\($0.label), \($0.detail)" }.joined(separator: "; ")
        return String(localized: "Distance to liquidation, closest first: \(listed).")
    }

    private func track(width: CGFloat) -> some View {
        // Dots are inset by their own radius so one sitting at either extreme
        // stays fully on the track instead of half-hanging off the card.
        let inset = dotSize / 2
        let usable = max(1, width - dotSize)
        return ZStack(alignment: .topLeading) {
            Capsule()
                .fill(
                    LinearGradient(
                        // Neutral for almost its whole length, warming only at
                        // the very end — orientation, not a threshold. The
                        // stop sits past every real dot's reach so it can't be
                        // read as a boundary anything crosses.
                        stops: [
                            .init(color: DS.fillLine, location: 0),
                            .init(color: DS.fillLine, location: 0.72),
                            .init(color: DS.destructive.opacity(0.45), location: 1),
                        ],
                        startPoint: .leading, endPoint: .trailing)
                )
                .frame(height: 9)
                .offset(y: labelBand + (dotSize - 9) / 2)
                .chartWipe(reduceMotion: reduceMotion)

            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                // Every reading starts at the comfortable end and travels to
                // where it actually sits — see the type doc.
                let x = inset + usable * (travelled ? clamped(entry.axis) : 0)
                // Alternating sides — see the type doc.
                let above = index.isMultiple(of: 2)
                // The name rides WITH its dot rather than fading in after: a
                // label that arrives late reads as belonging to whichever dot
                // is nearest when it lands, which on the crowded end is the
                // wrong one. A `Group` distributes the pair to both children,
                // so the two can't drift.
                Group {
                    dot(entry)
                        .position(x: x, y: labelBand + dotSize / 2)
                    label(entry, above: above)
                        .frame(width: 128)
                        .position(x: labelPosition(x, width: width),
                                  y: above ? labelBand / 2 : labelBand * 1.5 + dotSize)
                }
                .opacity(travelled ? 1 : 0)
                .animation(travel(index), value: travelled)
            }
        }
    }

    private func dot(_ entry: WalletRiskScale.Entry) -> some View {
        Circle()
            .fill(entry.atRisk ? DS.attention : DS.textPrimary)
            .frame(width: dotSize, height: dotSize)
            // The page showing through, not a stroke: a ring in a line colour
            // would be a hairline by another name, and two dots that overlap
            // still need to read as two.
            .overlay(Circle().stroke(DS.page, lineWidth: 3))
    }

    private func label(_ entry: WalletRiskScale.Entry, above: Bool) -> some View {
        VStack(alignment: .center, spacing: 0) {
            Text(entry.label)
                .dsText(.label12).foregroundStyle(DS.textPrimary)
                .lineLimit(1)
            Text(entry.detail)
                .dsText(.label12)
                .foregroundStyle(entry.atRisk ? DS.attention : DS.textTertiary)
                .lineLimit(1)
        }
        .multilineTextAlignment(.center)
    }

    /// Keeps a label's 128pt box inside the card even when its dot is at an
    /// extreme — the text stays centred on the dot everywhere it can.
    private func labelPosition(_ x: CGFloat, width: CGFloat) -> CGFloat {
        min(max(x, 64), max(64, width - 64))
    }

    private func clamped(_ v: Double) -> CGFloat {
        CGFloat(min(max(v, 0), 1))
    }
}
