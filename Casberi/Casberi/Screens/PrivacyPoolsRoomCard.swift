import SwiftUI

/// THE PRIVACY POOLS ROOM'S HEAD (2026-08-10, prd §349) — where every deposit
/// stands with the screener.
///
/// The anatomy is `CursorRoomCard`'s — kicker, heavy headline, ranked rows, no
/// decoration that isn't a reading — with one substitution: the drawing is a
/// SPLIT, not a set of bars, because these states are mutually exclusive and
/// cover every deposit the room holds. `PrivacyPoolsRoom.share` states why that
/// is honest here where `CursorRoom` refused a split of its own.
///
/// ## Two weights, one hue, and no red
///
/// The split encodes exactly one thing: **is this still in play.** Open states
/// (in review, needs your proof) take the card's hue at full strength; resolved
/// ones (cleared, declined) take the faint fill. A declined deposit is NOT
/// painted red — the design law's honesty rule is that state is stated in
/// words, never in a colour that does the arguing (the Stripe dispute
/// precedent), and here it would be actively wrong: a decline costs nothing but
/// a reclaim, while a cleared deposit is the outcome you wanted. Both are over.
/// The legend beneath carries the exact counts and what each one MEANS.
///
/// ## The gap in the bar is the unknown
///
/// The denominator is every deposit including the ones carrying no state tag,
/// so a room with unknown deposits draws a bar that does not reach the end. The
/// gap is deliberate and the footnote names it — filling the bar by dividing
/// through the tagged count alone would present partial knowledge as complete.
///
/// ## Liveness
///
/// Stores no `Thing` — only value types out of `PrivacyPoolsRoom`, filtered at
/// the boundary by `PrivacyPoolsRoomSource`. The tap hands back a `State` and
/// the section that owns the sheet does the lookup (corollary 5).
///
/// FLAT BY LAW: a plain VStack, no generic `Widget`/`Row` mount.
struct PrivacyPoolsRoomCard: View {
    let room: PrivacyPoolsRoom
    /// Hands back the STATE, not a `Thing`. A state owns many deposits, so the
    /// honest landing is that state's newest deposit — resolved by the feed.
    var onOpen: (PrivacyPoolsRoom.State) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let mark = DS.legibleCardFill(for: "Privacy Pools")

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String(localized: "Privacy Pools"))
                .dsText(.label12).fontWeight(.semibold)
                .foregroundStyle(Self.mark)

            Text(PrivacyPoolsRoom.headline(room))
                .dsText(.heading22)
                .foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, DS.Space.s2)

            Text(PrivacyPoolsRoom.note(room))
                .dsText(.subhead13)
                .foregroundStyle(DS.textSecondary)
                .padding(.top, DS.Space.s1)

            if !room.segments.isEmpty {
                splitBar
                    .padding(.top, DS.Space.s3)
                legend
                    .padding(.top, DS.Space.s3)
            }

            if let footnote = PrivacyPoolsRoom.footnote(room) {
                Text(footnote)
                    .dsText(.label12)
                    .foregroundStyle(DS.textTertiary)
                    .padding(.top, DS.Space.s3)
            }
        }
        .padding(DS.Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsWidgetSurface()
        .padding(.horizontal, DS.Space.s4)
        .padding(.top, DS.Space.s2)
        .contentShape(Rectangle())
        .onTapGesture {
            guard let lead = room.lead else { return }
            DSHaptic.selection()
            onOpen(lead.state)
        }
    }

    // MARK: - The split

    /// Drawn in the ranked order, so the state that needs you leads the bar as
    /// well as the headline. The track behind it is the unknown: a segment set
    /// that does not sum to the whole leaves it showing, on purpose.
    private var splitBar: some View {
        GeometryReader { geo in
            let gaps = CGFloat(max(room.segments.count - 1, 0)) * 2
            ZStack(alignment: .leading) {
                Capsule(style: .continuous).fill(DS.fillFaint)
                HStack(spacing: 2) {
                    ForEach(room.segments) { segment in
                        fill(segment.state)
                            // Floored at 3pt so a single deposit among forty is
                            // still visible rather than a sub-pixel sliver —
                            // the `UnitTreemap` rule: rank can never hide a
                            // state that needs you.
                            .frame(width: max((geo.size.width - gaps)
                                              * CGFloat(PrivacyPoolsRoom.share(count: segment.count,
                                                                               of: room.deposits)), 3))
                    }
                    Spacer(minLength: 0)
                }
                .clipShape(Capsule(style: .continuous))
            }
        }
        .frame(height: 12)
        // A split is read as proportions of one length, so revealing along that
        // length is the split being stated (`DistributionHero`'s ruling).
        .chartWipe(reduceMotion: reduceMotion)
        .accessibilityHidden(true)
    }

    /// Full strength while the review is open, faint once it is over — see the
    /// type note. One hue throughout.
    private func fill(_ state: PrivacyPoolsRoom.State) -> Color {
        state.resolved ? Self.mark.opacity(0.35) : Self.mark
    }

    // MARK: - Legend

    private var legend: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            ForEach(room.segments) { segment in
                Button {
                    DSHaptic.selection()
                    onOpen(segment.state)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                        Circle()
                            .fill(fill(segment.state))
                            .frame(width: 7, height: 7)
                            .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                        Text(segment.state.rawValue)
                            .dsText(.body17)
                            .foregroundStyle(DS.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: DS.Space.s2)
                        Text(PrivacyPoolsRoom.segmentLine(segment))
                            .dsText(.subhead13)
                            .foregroundStyle(DS.textSecondary)
                            .lineLimit(1)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("\(segment.state.rawValue), \(PrivacyPoolsRoom.segmentLine(segment))"))
            }
        }
    }
}
