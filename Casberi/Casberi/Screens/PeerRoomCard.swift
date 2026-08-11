import SwiftUI

/// THE PEER ROOM'S HEAD (2026-08-10, prd §348) — which rail your money moves
/// on, and which way it goes.
///
/// The anatomy is `CursorRoomCard`'s, which took it from `StripeRoomCard`: a
/// kicker in the card's one hue, a heavy headline stating the whole finding as
/// a sentence, ranked rows, and no decoration that isn't a reading. No coloured
/// rail down a row's side and no green/red — a rail is not good or bad, it is
/// the one you use.
///
/// ## The one drawing, and what it means
///
/// A `ShareBar` per rail, scaled against the busiest one, encoding ONE thing:
/// how much of your Peer traffic went this way. It is deliberately not a
/// buy/sell split bar — a two-tone bar invites reading the ratio as a balance
/// somebody chose, and the two counts are stated exactly in words beside it,
/// where a number can be exact.
///
/// ## Liveness
///
/// Stores no `Thing` — only value types out of `PeerRoom`, filtered at the
/// boundary by `PeerRoomSource`. The tap hands back a `Rail` and the section
/// that owns the sheet does the lookup (corollary 5).
///
/// FLAT BY LAW like its neighbours: a plain VStack, no generic `Widget`/`Row`
/// mount (the eager-head render-depth lesson, paid three times).
struct PeerRoomCard: View {
    let room: PeerRoom
    /// Hands back the RAIL, not a `Thing` — the card never holds one, and a
    /// rail owns many rows so there is no single `sourceRef` it could name.
    var onOpen: (PeerRoom.Rail) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let mark = DS.legibleCardFill(for: "Peer")

    private var drawn: [PeerRoom.Rail] {
        Array(room.rails.prefix(PeerRoomSource.rowCap))
    }

    /// The busiest rail's fill count — the bar's full width, so every bar on
    /// the card is on one scale and two rows are comparable at a glance.
    private var top: Int { room.lead?.fills ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String(localized: "Peer"))
                .dsText(.label12).fontWeight(.semibold)
                .foregroundStyle(Self.mark)

            Text(PeerRoom.headline(room))
                .dsText(.heading22)
                .foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, DS.Space.s2)

            Text(PeerRoom.note(room))
                .dsText(.subhead13)
                .foregroundStyle(DS.textSecondary)
                .padding(.top, DS.Space.s1)

            // Only the rails BEYOND the lead get a row — the lead is already in
            // the headline, and repeating its name directly underneath is the
            // card arguing with itself. Its bar still draws, because the
            // headline does not carry a proportion.
            if let lead = room.lead {
                ShareBar(fraction: PeerRoom.share(fills: lead.fills, of: top),
                         reduceMotion: reduceMotion)
                    .padding(.top, DS.Space.s2)
            }

            if drawn.count > 1 {
                ForEach(Array(drawn.dropFirst().enumerated()), id: \.element.id) { index, rail in
                    row(rail, index: index)
                        .chartArrival(index: index, reduceMotion: reduceMotion)
                }
                .padding(.top, DS.Space.s3)
            }

            if let footnote = PeerRoom.footnote(room, drawn: drawn.count) {
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
            onOpen(lead)
        }
    }

    // MARK: - Rows

    private func row(_ rail: PeerRoom.Rail, index: Int) -> some View {
        Button {
            DSHaptic.selection()
            onOpen(rail)
        } label: {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                    Text(rail.name)
                        .dsText(.body17)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: DS.Space.s2)
                    Text(PeerRoom.railLine(rail))
                        .dsText(.subhead13)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                }
                // The stagger index is shared with the row's own arrival, so a
                // bar lands with the row that owns it rather than on a cadence
                // of its own (one beat per row — `ChartEntrance`'s rule).
                ShareBar(fraction: PeerRoom.share(fills: rail.fills, of: top),
                         index: index + 1,
                         reduceMotion: reduceMotion)
            }
            .padding(.vertical, DS.Space.s1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(rail.name), \(PeerRoom.railLine(rail))"))
    }
}
