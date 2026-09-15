import SwiftUI

/// THE DODO PAYMENTS ROOM'S HEAD (2026-09-01, prd §558) — what came in, what
/// went back out, and what needs you.
///
/// This room is two rooms at once: a windowed money reading like Gnosis Pay's
/// card, and a deadline rail like the Merchant of Record's. So it draws both of
/// the template's blocks for those shapes — the rail with its `DeadlineRow`s,
/// then the currency `Row`s — under one sentence (prd §745).
///
/// ## No green, no red, no arrow
///
/// `GnosisPayRoomCard`'s restraint, and here the temptation is stronger still:
/// this is revenue, and a card that paints a good month green is a card that
/// paints a bad one red at the moment somebody least needs an opinion from an
/// app. The change is stated in words and never coloured. A dispute gets the
/// card's one hue on its stamp because it is a STATE that changes what you would
/// do today, not a verdict on the number beside it.
///
/// ## The currency rows exist only when there is more than one currency
///
/// A single-currency account — the ordinary case — gets the headline, the
/// change and the rail. A legend of one row is a restatement of the sentence
/// above it (`GnosisPayRoomCard`'s rule, unchanged).
///
/// ## Liveness
///
/// Stores no `Thing` — only value types out of `DodoPaymentsRoom`, filtered at
/// the boundary by `DodoPaymentsRoomSource`. Both taps hand back a value and the
/// section that owns the sheet does the lookup (corollary 5).
struct DodoPaymentsRoomCard: View {
    let room: DodoPaymentsRoom
    /// Hands back the CURRENCY — a currency owns many payments, so the honest
    /// landing is its most recent one.
    var onOpenCurrency: (DodoPaymentsRoom.Currency) -> Void
    /// Hands back the retry, which owns exactly one row.
    var onOpenRetry: (DodoPaymentsRoom.Retry) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let mark = DS.legibleCardFill(for: "Dodo Payments")

    private var mask: String? {
        BalancePrivacy.shared.withheld ? BalancePrivacy.mask : nil
    }

    /// The busiest currency's payment count — the bar's full width, so every bar
    /// sits on one scale. By COUNT, never by amount: the totals are in different
    /// currencies and drawing them on one axis would state a conversion nobody
    /// made (`DodoPaymentsRoom.share`'s own rule).
    private var top: Int { room.lead?.payments ?? 0 }

    var body: some View {
        DSRoomChassis.Head(
            lead: .sentence(DodoPaymentsRoom.headline(room, mask: mask)),
            notes: [.note(DodoPaymentsRoom.note(room, mask: mask))],
            footnotes: [.quiet(DodoPaymentsRoom.refundNote(room, mask: mask)),
                        .quiet(DodoPaymentsRoom.coverageNote(room)),
                        .quiet(DodoPaymentsRoom.footnote(room))]) {
            if !room.retries.isEmpty {
                DSRoomChassis.Block {
                    rail
                    DSRoomChassis.Rows(items: room.retries) { index, retry in
                        DSRoomChassis.DeadlineRow(
                            name: retry.name,
                            stamp: DodoPaymentsRoom.retryChip(retry),
                            kind: String(localized: "Subscription"),
                            value: DodoPaymentsRoom.value(days: retry.days),
                            overdue: retry.days < 0,
                            fill: Self.mark,
                            index: index) { onOpenRetry(retry) }
                    }
                }
            }

            if room.currencies.count > 1 {
                DSRoomChassis.Block {
                    DSRoomChassis.Rows(items: room.currencies) { index, currency in
                        DSRoomChassis.Row(
                            title: currency.code,
                            glyph: "banknote",
                            line: DodoPaymentsRoom.currencyLine(currency, mask: mask),
                            index: index,
                            action: { onOpenCurrency(currency) }) {
                            ShareBar(fraction: DodoPaymentsRoom.share(payments: currency.payments, of: top),
                                     index: index,
                                     reduceMotion: reduceMotion)
                        }
                    }
                }
            }
        }
    }

    /// The card's time axis, drawn by the shared component.
    ///
    /// The placement stays here on purpose: the marks go through this
    /// room's own `position`, so the room's selftest keeps asserting the
    /// arithmetic it ships with.
    private var rail: some View {
        let span = DodoPaymentsRoom.span(days: room.retries.map(\.days))
        let retries = room.retries
        return DSRunwayRail(
            marks: retries.map { retry in
                DSRunwayRail.Mark(id: retry.id,
                                  position: DodoPaymentsRoom.position(days: retry.days, span: span),
                                  lead: retry.id == retries.first?.id)
            },
            spanLabel: DodoPaymentsRoom.spanLabel(span: span),
            leadFill: Self.mark,
            reduceMotion: reduceMotion)
    }
}
