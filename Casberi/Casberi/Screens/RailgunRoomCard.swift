import SwiftUI

/// THE RAILGUN ROOM'S HEAD (2026-08-11; redrawn 2026-08-26, prd §485) — what's
/// moving through the shielded pool, by token.
///
/// The anatomy is `PeerRoomCard`'s, which is `CursorRoomCard`'s: a kicker in
/// the card's own hue, a heavy headline stating the finding as a sentence,
/// ranked rows, no decoration that isn't a reading.
///
/// ## What the 2026-08-26 pass changed, and why (user: "the railgun room looks
/// messy — clean it up in the restrained style we are doing for wallet")
///
/// Three defects, all of them the card talking over itself — §483's editing
/// pass applied one room over:
///
///   1. **Four sentences said one thing.** A headline naming the lead, a
///      subline splitting in from out, a line per token splitting in from out
///      again, and a footnote. "shielded"/"received" could appear five times
///      on one card. `RailgunRoom.note` is deleted, not merely undrawn — the
///      totals it stated are the sums of two columns now on screen.
///   2. **The lead had a bar and no row.** It was named inside the prose
///      headline, so the card's first bar measured a token whose label was two
///      lines up, and the bars below it sat on labelled rows. Every drawn
///      token gets a row now, the lead included.
///   3. **The bar and the text measured different quantities.** `share` was a
///      fraction of the busiest token's MOVE COUNT while the figures beside it
///      were AMOUNTS, so the bar read as a picture of the number printed next
///      to it. `RailgunRoom.pair` replaces it: in against back, on the token's
///      own scale, which is the one comparison this room's data supports.
///
/// ## The drawing
///
/// Two hairlines per token, and deliberately NO track behind them: a track is
/// a shared axis, and no two tokens here share a unit (see `RailgunRoom.pair`).
/// Length is the reading, weight is constant.
///
/// **Colour follows the money column in the rows below** (`BandRow`'s
/// `moneyColumn`, which this room now asks for): arriving money is `DS.confirm`
/// and everything else is neutral ink, the wallet family's standing grammar —
/// in is green, out is neutral, never red. This AMENDS this card's own
/// original "no green/red" line, which was written when the card had no drawing
/// at all: the rule it was defending is that neither direction is good or bad,
/// and nothing here is painted red or ranked by direction. What green says is
/// *this arrived*, which is what it says on every wallet row in the app.
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

    private var drawn: [RailgunRoom.Token] {
        Array(room.tokens.prefix(RailgunRoomSource.rowCap))
    }

    private var mask: String? { BalancePrivacy.shared.withheld ? BalancePrivacy.mask : nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The source-name eyebrow retired here 2026-08-22 (prd §452). A room
            // head renders only inside its own source's room, under a chip strip
            // where that source's chip is the lit one — so the card introduced
            // itself with a word already on screen, one row up.
            Text(RailgunRoom.headline(room))
                .dsText(.heading22)
                .foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .dsCardLead(Text("Opens this token")) {
                    guard let lead = room.lead else { return }
                    DSHaptic.selection()
                    onOpen(lead)
                }

            ForEach(Array(drawn.enumerated()), id: \.element.id) { index, token in
                row(token, index: index)
                    .chartArrival(index: index, reduceMotion: reduceMotion)
            }
            .padding(.top, DS.Space.s3)

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
                    // No symbol inside the figures — the row's leading label is
                    // already the token's name, and the old line said that word
                    // three times before it said anything.
                    Text(RailgunRoom.tokenLine(token, mask: mask))
                        .dsText(.subhead13)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                }
                // The stagger index is shared with the row's own arrival —
                // `ChartEntrance`'s rule, one beat per row. Absent whenever
                // either side's amount is unknown: a pair is a comparison, and
                // half of one drawn as a whole is the partial-sum failure
                // `RailgunRoom.Token` exists to refuse.
                if let pair = RailgunRoom.pair(token) {
                    DirectionPair(into: pair.into, back: pair.back,
                                  index: index, reduceMotion: reduceMotion)
                }
            }
            .padding(.vertical, DS.Space.s1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(token.symbol), \(RailgunRoom.tokenLine(token, symbol: token.symbol, mask: mask))"))
    }

    // MARK: - The pair

    /// Two hairlines: what went into the pool, and what came back out of it.
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
