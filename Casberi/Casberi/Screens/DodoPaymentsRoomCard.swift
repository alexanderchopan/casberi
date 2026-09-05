import SwiftUI

/// THE DODO PAYMENTS ROOM'S HEAD (2026-09-01, prd §558) — what came in, what
/// went back out, and what needs you.
///
/// The anatomy is `GnosisPayRoomCard`'s crossed with `PolarRoomCard`'s, because
/// this room is both of those rooms at once: a windowed money reading like the
/// card, and a deadline rail like the Merchant of Record. Kicker retired (§452 —
/// a head renders only inside its own source's room, under a lit chip bearing
/// that source's name), heavy headline stating the whole finding as a sentence,
/// one axis drawn once, ranked rows, nothing drawn that isn't a reading.
///
/// ## No green, no red, no arrow
///
/// `GnosisPayRoomCard`'s restraint, and here the temptation is stronger still:
/// this is revenue, and a card that paints a good month green is a card that
/// paints a bad one red at the moment somebody least needs an opinion from an
/// app. The change is stated in words and never coloured. A dispute gets the
/// card's one hue on its chip because it is a STATE that changes what you would
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
///
/// FLAT BY LAW: a plain VStack, no generic `Widget`/`Row` mount.
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
        VStack(alignment: .leading, spacing: 0) {
            Text(DodoPaymentsRoom.headline(room, mask: mask))
                .dsText(.heading22)
                .foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(DodoPaymentsRoom.note(room, mask: mask))
                .dsText(.subhead13)
                .foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, DS.Space.s1)

            if !room.retries.isEmpty {
                rail
                    .padding(.top, DS.Space.s4)

                ForEach(Array(room.retries.enumerated()), id: \.element.id) { index, retry in
                    retryRow(retry, lead: index == 0)
                        .chartArrival(index: index, reduceMotion: reduceMotion)
                }
                .padding(.top, DS.Space.s1)
            }

            if room.currencies.count > 1 {
                ForEach(Array(room.currencies.enumerated()), id: \.element.id) { index, currency in
                    currencyRow(currency, index: index)
                }
                .padding(.top, DS.Space.s2)
            }

            notes
        }
        .padding(DS.Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsWidgetSurface()
        .padding(.horizontal, DS.Space.s4)
        .padding(.top, DS.Space.s2)
    }

    // MARK: - The retry rail

    /// The card's time axis, drawn by the shared component.
    ///
    /// The placement stays here on purpose: the marks go through this
    /// room's own `position`, so the room's selftest keeps asserting the
    /// arithmetic it ships with.
    private var rail: some View {
        // Hoisted out of the view builder: these change only when the
        // deadlines do, and a closure would re-run on every layout pass.
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

    // MARK: - Rows

    private func retryRow(_ retry: DodoPaymentsRoom.Retry, lead: Bool) -> some View {
        Button {
            DSHaptic.selection()
            onOpenRetry(retry)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(retry.name)
                        .dsText(.heading17)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    HStack(spacing: DS.Space.s1 + 2) {
                        Text(DodoPaymentsRoom.retryChip(retry))
                            .dsText(.label11).fontWeight(.bold)
                            .foregroundStyle(Color.fixed("#ffffff"))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Self.mark,
                                        in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                        Text("Subscription")
                            .dsText(.label12)
                            .foregroundStyle(DS.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: DS.Space.s2)
                Text(DodoPaymentsRoom.value(days: retry.days))
                    .dsText(.price16)
                    .foregroundStyle(retry.days < 0 ? DS.textPrimary : DS.textSecondary)
                    .monospacedDigit()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, DS.Space.s2)
    }

    private func currencyRow(_ currency: DodoPaymentsRoom.Currency, index: Int) -> some View {
        Button {
            DSHaptic.selection()
            onOpenCurrency(currency)
        } label: {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                    Text(currency.code)
                        .dsText(.body17)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: DS.Space.s2)
                    Text(DodoPaymentsRoom.currencyLine(currency, mask: mask))
                        .dsText(.subhead13)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                }
                ShareBar(fraction: DodoPaymentsRoom.share(payments: currency.payments, of: top),
                         index: index,
                         reduceMotion: reduceMotion)
            }
            .padding(.vertical, DS.Space.s1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(currency.code), \(DodoPaymentsRoom.currencyLine(currency, mask: mask))"))
    }

    @ViewBuilder
    private var notes: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let refunds = DodoPaymentsRoom.refundNote(room, mask: mask) {
                note(refunds)
            }
            if let coverage = DodoPaymentsRoom.coverageNote(room) {
                note(coverage)
            }
            if let footnote = DodoPaymentsRoom.footnote(room) {
                note(footnote)
            }
        }
        .padding(.top, DS.Space.s3)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .dsText(.label11)
            .foregroundStyle(DS.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
