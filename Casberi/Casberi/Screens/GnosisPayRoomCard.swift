import SwiftUI

/// THE GNOSIS PAY ROOM'S HEAD (2026-08-10, prd §349) — what the card cost you
/// this month, and whether that's more than usual.
///
/// ## No green, no red, no arrow
///
/// The card states a change in words ("18% more than the 30 days before") and
/// never paints it. Spending more is not a failure and spending less is not a
/// win — the app has no idea which of those the person wanted, and colouring it
/// would be the app taking a view on someone's life off a single number.
///
/// ## The rows exist only when there is more than one currency
///
/// A single-currency account — the ordinary case — gets the headline, the
/// change and the month span. The per-currency rows appear only when the
/// account really settles in several, because a legend of one row is a
/// restatement.
///
/// **The single-currency bar is deleted (prd §745).** It drew the lead's share
/// of the lead's own count — `top` is that count — so it was full on every card
/// it ever drew: one possible length, no reading.
///
/// ## Liveness
///
/// Stores no `Thing` — only value types out of `GnosisPayRoom`, filtered at the
/// boundary by `GnosisPayRoomSource`. The tap hands back a `Currency` and the
/// section that owns the sheet does the lookup (corollary 5).
///
/// Composed through `DSRoomChassis.Head`, its `SpanStrip` and its ranked `Row`.
struct GnosisPayRoomCard: View {
    let room: GnosisPayRoom
    /// Hands back the CURRENCY, not a `Thing` — a currency owns many spends, so
    /// the honest landing is its most recent one.
    var onOpen: (GnosisPayRoom.Currency) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let mark = DS.legibleCardFill(for: "Gnosis Pay")

    private var drawn: [GnosisPayRoom.Currency] {
        Array(room.currencies.prefix(GnosisPayRoomSource.rowCap))
    }

    /// The busiest currency's spend count — the bar's full width, so every bar
    /// is on one scale. By COUNT, never by amount: the totals are in different
    /// currencies and drawing them on one axis would state a conversion nobody
    /// made (`GnosisPayRoom.share`'s own rule).
    private var top: Int { room.lead?.spends ?? 0 }

    var body: some View {
        // THE LEDE (prd §585). The mask is threaded through rather than
        // applied after, so a hidden balance suppresses the digit ROLL as well
        // as the string.
        let mask = BalancePrivacy.shared.withheld ? BalancePrivacy.mask : nil
        DSRoomChassis.Head(
            lead: .figure(GnosisPayRoom.lede(room, mask: mask),
                          otherwise: GnosisPayRoom.headline(room, mask: mask)),
            door: room.lead.map { lead in
                DSRoomChassis.Door(hint: Text("Opens this currency")) { onOpen(lead) }
            },
            notes: [.note(GnosisPayRoom.note(room))],
            footnotes: [.quiet(GnosisPayRoom.footnote(room))]) {
            if !room.months.isEmpty {
                DSRoomChassis.Block {
                    monthStrip
                    if let caption = GnosisPayRoom.historyNote(room) {
                        DSRoomChassis.LineText(line: DSRoomChassis.Line(text: caption, tone: .quiet))
                            .padding(.top, DS.Space.s1)
                    }
                }
            }

            // Only when the account really settles in several currencies — see
            // the type note.
            if drawn.count > 1 {
                DSRoomChassis.Block {
                    DSRoomChassis.Rows(items: drawn) { index, currency in
                        let line = GnosisPayRoom.currencyLine(currency, mask: mask)
                        DSRoomChassis.Row(
                            title: currency.code,
                            glyph: "banknote",
                            line: line,
                            index: index,
                            action: { onOpen(currency) }) {
                            ShareBar(fraction: GnosisPayRoom.share(spends: currency.spends, of: top),
                                     index: index,
                                     reduceMotion: reduceMotion)
                        }
                    }
                }
            }
        }
    }

    // MARK: - The history strip

    /// A column per month of the LEAD currency's spending, oldest at the left.
    /// It exists because this head outranks `FeedInsight.cardMonths`, the
    /// 12-month board the room drew before.
    ///
    /// Heights are a share of the biggest month DRAWN, so the strip is a
    /// comparison among the months you can see.
    private var monthStrip: some View {
        let top = room.months.map(\.total).max() ?? 0
        return DSRoomChassis.SpanStrip(
            columns: room.months.enumerated().map { index, month in
                DSRoomChassis.SpanStrip.Column(
                    id: index,
                    share: GnosisPayRoom.monthShare(total: month.total, of: top))
            },
            fill: Self.mark,
            first: room.months.first.map { GnosisPayRoom.monthLabel($0.start) },
            last: room.months.last.map { GnosisPayRoom.monthLabel($0.start) },
            spoken: GnosisPayRoom.historyNote(room) ?? "")
    }
}
