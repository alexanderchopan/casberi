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
            // **RANKED BARS, NOT DOTS ON A TRACK** (2026-08-26, prd §483 —
            // Risk "R3", chosen over a single figure and over an arc gauge).
            //
            // The axis this replaces was one track carrying every position as
            // a dot, with alternating labels above and below to keep them off
            // each other. Two costs, both structural rather than tuning: the
            // dots crowd at exactly the end that matters (a wallet in trouble
            // has several positions near the edge, which is when the drawing
            // is least readable), and reading it at all meant matching a label
            // to a dot by eye. One bar per position collides with nothing at
            // any density, and Screen Time's own idiom answers the question in
            // the ranking itself: THE SHORTEST BAR IS THE WORRY, so no colour
            // scale has to say which — which is why the track's warm end is
            // gone rather than restyled. §299's "dots on a track read as
            // nothing" survives here; this is that finding taken one step
            // further.
            Text(String(localized: "Room to move"))
                .dsText(.heading22).foregroundStyle(DS.textPrimary)
            Text(String(localized: "before each position closes"))
                .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: DS.Space.s4) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    row(entry, index: index)
                }
            }
            .padding(.top, DS.Space.s4)
        }
        // The set still speaks as ONE sentence in the ranked order (§299's
        // ruling, unchanged by the redraw): a screen reader hearing seven
        // separate bars has to hold the order itself, which is the whole
        // reading.
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

    /// One position: its own words on the right of the title line, its room as
    /// the bar beneath.
    ///
    /// **Colour marks the alarm and NOTHING else.** A green "safe" bar beside
    /// an orange one would be this app grading a position, and the length
    /// already grades it; `DS.tint` is the room's ordinary voice, so a bar
    /// that is merely long says so by being long.
    @ViewBuilder
    private func row(_ entry: WalletRiskScale.Entry, index: Int) -> some View {
        let body = VStack(alignment: .leading, spacing: DS.Space.s2) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                Text(entry.label)
                    .dsText(.subhead13).foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: DS.Space.s2)
                // The PROTOCOL's own number, never restated as a percentage of
                // ours — `WalletRiskScale.Entry.detail` exists for exactly
                // that, and the bar is the only thing here in our units.
                Text(entry.detail)
                    .dsText(.label12)
                    .foregroundStyle(entry.atRisk ? DS.attention : DS.textSecondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
            }
            ShareBar(fraction: clamped(entry.headroom), index: index,
                     fill: entry.atRisk ? DS.attention : DS.tint,
                     reduceMotion: reduceMotion)
        }
        if let onPick {
            Button {
                DSHaptic.selection()
                onPick(entry)
            } label: { body.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .dsHover()
                // The combined element above carries the speech and the
                // actions; a label here would be written and never read.
                .accessibilityHidden(true)
        } else {
            body
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
