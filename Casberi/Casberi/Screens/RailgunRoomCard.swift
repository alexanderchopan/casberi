import SwiftUI

/// THE RAILGUN ROOM'S HEAD (2026-08-11; redrawn 2026-08-26, prd §485) — what's
/// moving through the shielded pool, by token.
///
/// ## What the 2026-08-26 pass changed, and why (user: "the railgun room looks
/// messy — clean it up in the restrained style we are doing for wallet")
///
///   1. **Four sentences said one thing.** `RailgunRoom.note` is deleted, not
///      merely undrawn — the totals it stated are the sums of two columns now on
///      screen.
///   2. **The lead had a bar and no row.** Every drawn token gets a row now,
///      the lead included.
///   3. **The bar and the text measured different quantities.** The move-count
///      bar is replaced by `RailgunRoom.pair`: in against back, on the token's
///      own scale, which is the one comparison this room's data supports.
///
/// ## The drawing
///
/// Two lines per token, and deliberately NO track behind them: a track is a
/// shared axis, and no two tokens here share a unit (see `RailgunRoom.pair`).
/// Length is the reading, weight is constant. Arriving money is `DS.confirm` and
/// everything else is neutral ink, the wallet family's standing grammar — in is
/// green, out is neutral, never red.
///
/// ## Liveness
///
/// Stores no `Thing` — only value types out of `RailgunRoom`, filtered at the
/// boundary by `RailgunRoomSource`. The tap hands back a `Token` and the
/// section that owns the sheet does the lookup (corollary 5).
///
/// Composed through `DSRoomChassis.Head` and its ranked `Row` (prd §745); the
/// pair is this room's own measure under the template's row.
struct RailgunRoomCard: View {
    let room: RailgunRoom
    /// Hands back the TOKEN, not a `Thing` — the card never holds one, and a
    /// token owns many rows so there is no single `sourceRef` it could name.
    var onOpen: (RailgunRoom.Token) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var drawn: [RailgunRoom.Token] {
        Array(room.tokens.prefix(RailgunRoomSource.rowCap))
    }

    private var mask: String? { BalancePrivacy.shared.withheld ? BalancePrivacy.mask : nil }

    var body: some View {
        DSRoomChassis.Head(
            lead: .sentence(RailgunRoom.headline(room)),
            door: room.lead.map { lead in
                DSRoomChassis.Door(hint: Text("Opens this token")) { onOpen(lead) }
            },
            footnotes: [.quiet(RailgunRoom.footnote(room, drawn: drawn.count))]) {
            if !drawn.isEmpty {
                DSRoomChassis.Block {
                    DSRoomChassis.Rows(items: drawn) { index, token in
                        // No symbol inside the figures — the row's leading label
                        // is already the token's name.
                        DSRoomChassis.Row(
                            title: token.symbol,
                            glyph: "hexagon",
                            line: RailgunRoom.tokenLine(token, mask: mask),
                            spoken: "\(token.symbol), \(RailgunRoom.tokenLine(token, symbol: token.symbol, mask: mask))",
                            index: index,
                            action: { onOpen(token) }) {
                            // Absent whenever either side's amount is unknown: a
                            // pair is a comparison, and half of one drawn as a
                            // whole is the partial-sum failure `RailgunRoom.Token`
                            // exists to refuse.
                            if let pair = RailgunRoom.pair(token) {
                                DirectionPair(into: pair.into, back: pair.back,
                                              index: index, reduceMotion: reduceMotion)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - The pair

    /// Two lines: what went into the pool, and what came back out of it.
    ///
    /// No track behind either — see the type doc. Each line grows from nothing
    /// on the shared arrival cadence, which is `ChartEntrance`'s contract and
    /// what keeps `design-motion-audit` satisfied that a drawing sized from
    /// data has an entrance.
    private struct DirectionPair: View {
        let into: Double
        let back: Double
        let index: Int
        let reduceMotion: Bool

        @State private var entered = false

        private static let weight: CGFloat = 3

        var body: some View {
            GeometryReader { geo in
                VStack(alignment: .leading, spacing: 3) {
                    line(width: geo.size.width * (entered ? into : 0),
                         ink: DS.textPrimary.opacity(0.42))
                    line(width: geo.size.width * (entered ? back : 0),
                         ink: DS.confirm)
                }
            }
            .frame(height: Self.weight * 2 + 3)
            .accessibilityHidden(true)
            .onAppear {
                guard !entered else { return }
                guard !reduceMotion else { entered = true; return }
                withAnimation(ChartEntrance.arrive(index: index)) { entered = true }
            }
        }

        /// A zero-width capsule draws nothing at all, which is the correct
        /// picture of "none of it came back" — no floor, or an absence would
        /// read as a small amount.
        private func line(width: CGFloat, ink: Color) -> some View {
            Capsule(style: .continuous)
                .fill(ink)
                .frame(width: max(0, width), height: Self.weight)
        }
    }
}
