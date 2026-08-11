import SwiftUI

/// THE RAILGUN ROOM'S HEAD (2026-08-11) — what's actually moving through the
/// shielded pool, by token.
///
/// The anatomy is `PeerRoomCard`'s, which is `CursorRoomCard`'s: a kicker in
/// the card's own hue, a heavy headline stating the finding as a sentence,
/// ranked rows, no decoration that isn't a reading. No green/red — a shield
/// and an unshield are not good or bad, they're just which way the money went.
///
/// ## Liveness
///
/// Stores no `Thing` — only value types out of `RailgunRoom`, filtered at the
/// boundary by `RailgunRoomSource`. The tap hands back a `Token` and the
/// section that owns the sheet does the lookup (corollary 5).
///
/// FLAT BY LAW like its neighbours: a plain VStack, no generic `Widget`/`Row`
/// mount (the eager-head render-depth lesson).
struct RailgunRoomCard: View {
    let room: RailgunRoom
    /// Hands back the TOKEN, not a `Thing` — the card never holds one, and a
    /// token owns many rows so there is no single `sourceRef` it could name.
    var onOpen: (RailgunRoom.Token) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let mark = DS.legibleCardFill(for: "Railgun")

    private var drawn: [RailgunRoom.Token] {
        Array(room.tokens.prefix(RailgunRoomSource.rowCap))
    }

    private var top: Int { room.lead?.moves ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String(localized: "Railgun"))
                .dsText(.label12).fontWeight(.semibold)
                .foregroundStyle(Self.mark)

            Text(RailgunRoom.headline(room))
                .dsText(.heading22)
                .foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, DS.Space.s2)

            Text(RailgunRoom.note(room))
                .dsText(.subhead13)
                .foregroundStyle(DS.textSecondary)
                .padding(.top, DS.Space.s1)

            // Only the tokens BEYOND the lead get a row — the lead is already
            // in the headline. Its bar still draws, because the headline
            // doesn't carry a proportion.
            if let lead = room.lead {
                ShareBar(fraction: RailgunRoom.share(moves: lead.moves, of: top),
                         reduceMotion: reduceMotion)
                    .padding(.top, DS.Space.s2)
            }

            if drawn.count > 1 {
                ForEach(Array(drawn.dropFirst().enumerated()), id: \.element.id) { index, token in
                    row(token, index: index)
                        .chartArrival(index: index, reduceMotion: reduceMotion)
                }
                .padding(.top, DS.Space.s3)
            }

            if let footnote = RailgunRoom.footnote(room, drawn: drawn.count) {
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

    private func row(_ token: RailgunRoom.Token, index: Int) -> some View {
        Button {
            DSHaptic.selection()
            onOpen(token)
        } label: {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                    Text(token.symbol)
                        .dsText(.body17)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: DS.Space.s2)
                    Text(RailgunRoom.tokenLine(token))
                        .dsText(.subhead13)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                }
                // The stagger index is shared with the row's own arrival —
                // `ChartEntrance`'s rule, one beat per row.
                ShareBar(fraction: RailgunRoom.share(moves: token.moves, of: top),
                         index: index + 1,
                         reduceMotion: reduceMotion)
            }
            .padding(.vertical, DS.Space.s1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(token.symbol), \(RailgunRoom.tokenLine(token))"))
    }
}
