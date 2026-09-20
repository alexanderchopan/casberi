import SwiftUI

/// AN ONCHAIN CARD ROOM'S HEAD (2026-08-10 as `GnosisPayRoomCard`, prd §349;
/// generalised 2026-09-20, prd §858) — what the card cost you this month, and
/// whether that's more than usual.
///
/// Shared by Gnosis Pay and MetaMask Card. Only ONE thing here was ever
/// seat-specific — the mark's fill — so it is a parameter, and everything else
/// reads `CardSpendRoom`. A second copy of this view would be a second place
/// for the no-colour rule and the one-currency rule to drift.
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
/// Stores no `Thing` — only value types out of `CardSpendRoom`, filtered at the
/// boundary by `GnosisPayRoomSource`. The tap hands back a `Currency` and the
/// section that owns the sheet does the lookup (corollary 5).
///
/// Composed through `DSRoomChassis.Head`, its `SpanStrip` and its ranked `Row`.
struct CardSpendRoomCard: View {
    let room: CardSpendRoom
    /// The seat this head belongs to — its catalogue name, used for the mark's
    /// fill and nothing else. The room's judgements never vary by seat.
    let seat: String
    /// Hands back the CURRENCY, not a `Thing` — a currency owns many spends, so
    /// the honest landing is its most recent one.
    var onOpen: (CardSpendRoom.Currency) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var mark: Color { DS.legibleCardFill(for: seat) }

    private var drawn: [CardSpendRoom.Currency] {
        Array(room.currencies.prefix(CardSpendRoom.rowCap))
    }

    /// The busiest currency's spend count — the bar's full width, so every bar
    /// is on one scale. By COUNT, never by amount: the totals are in different
    /// currencies and drawing them on one axis would state a conversion nobody
    /// made (`CardSpendRoom.share`'s own rule).
    private var top: Int { room.lead?.spends ?? 0 }

    var body: some View {
        // THE LEDE (prd §585). The mask is threaded through rather than
        // applied after, so a hidden balance suppresses the digit ROLL as well
        // as the string.
        let mask = BalancePrivacy.shared.withheld ? BalancePrivacy.mask : nil
        DSRoomChassis.Head(
            lead: .figure(CardSpendRoom.lede(room, mask: mask),
                          otherwise: CardSpendRoom.headline(room, mask: mask)),
            door: room.lead.map { lead in
                DSRoomChassis.Door(hint: Text("Opens this currency")) { onOpen(lead) }
            },
            notes: [.note(CardSpendRoom.note(room))],
            footnotes: [.quiet(CardSpendRoom.footnote(room))]) {
            if !room.months.isEmpty {
                DSRoomChassis.Block {
                    monthStrip
                    if let caption = CardSpendRoom.historyNote(room) {
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
                        let line = CardSpendRoom.currencyLine(currency, mask: mask)
                        DSRoomChassis.Row(
                            title: currency.code,
                            glyph: "banknote",
                            line: line,
                            index: index,
                            action: { onOpen(currency) }) {
                            ShareBar(fraction: CardSpendRoom.share(spends: currency.spends, of: top),
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
                    share: CardSpendRoom.monthShare(total: month.total, of: top))
            },
            fill: mark,
            first: room.months.first.map { CardSpendRoom.monthLabel($0.start) },
            last: room.months.last.map { CardSpendRoom.monthLabel($0.start) },
            spoken: CardSpendRoom.historyNote(room) ?? "")
    }
}
