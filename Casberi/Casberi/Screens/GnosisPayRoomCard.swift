import SwiftUI

/// THE GNOSIS PAY ROOM'S HEAD (2026-08-10, prd §348) — what the card cost you
/// this month, and whether that's more than usual.
///
/// The anatomy is `CursorRoomCard`'s: kicker, heavy headline stating the whole
/// finding as a sentence, ranked rows, nothing drawn that isn't a reading.
///
/// ## No green, no red, no arrow
///
/// The card states a change in words ("18% more than the 30 days before") and
/// never paints it. Spending more is not a failure and spending less is not a
/// win — the app has no idea which of those the person wanted, and colouring it
/// would be the app taking a view on someone's life off a single number. It is
/// the same restraint `StripeRoomCard` shows over a dispute, applied to the one
/// place the temptation is strongest.
///
/// ## The rows exist only when there is more than one currency
///
/// A single-currency account — the ordinary case — gets the headline, the
/// change, and one bar. The per-currency rows appear only when the account
/// really settles in several, because a legend of one row is a restatement.
///
/// ## Liveness
///
/// Stores no `Thing` — only value types out of `GnosisPayRoom`, filtered at the
/// boundary by `GnosisPayRoomSource`. The tap hands back a `Currency` and the
/// section that owns the sheet does the lookup (corollary 5).
///
/// FLAT BY LAW: a plain VStack, no generic `Widget`/`Row` mount.
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
        VStack(alignment: .leading, spacing: 0) {
            Text(String(localized: "Gnosis Pay"))
                .dsText(.label12).fontWeight(.semibold)
                .foregroundStyle(Self.mark)

            Text(GnosisPayRoom.headline(room))
                .dsText(.heading22)
                .foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, DS.Space.s2)

            Text(GnosisPayRoom.note(room))
                .dsText(.subhead13)
                .foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, DS.Space.s1)

            // A single-currency account gets one bar and no rows. With several
            // currencies the lead gets its bar INSIDE its own row instead —
            // drawing it here as well would put the same bar on the card twice,
            // at two different widths once the rows rescale nothing.
            if drawn.count == 1, let lead = room.lead {
                ShareBar(fraction: GnosisPayRoom.share(spends: lead.spends, of: top),
                         reduceMotion: reduceMotion)
                    .padding(.top, DS.Space.s2)
            }

            if !room.months.isEmpty {
                monthStrip
                    .padding(.top, DS.Space.s3)
                if let caption = GnosisPayRoom.historyNote(room) {
                    Text(caption)
                        .dsText(.label12)
                        .foregroundStyle(DS.textTertiary)
                        .padding(.top, DS.Space.s1)
                }
            }

            // Only when the account really settles in several currencies — see
            // the type note.
            if drawn.count > 1 {
                ForEach(Array(drawn.enumerated()), id: \.element.id) { index, currency in
                    row(currency, index: index)
                        .chartArrival(index: index, reduceMotion: reduceMotion)
                }
                .padding(.top, DS.Space.s3)
            }

            if let footnote = GnosisPayRoom.footnote(room) {
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

    // MARK: - The history strip

    /// A column per month of the LEAD currency's spending, oldest at the left.
    /// It exists because this head outranks `FeedInsight.cardMonths`, the
    /// 12-month leaderboard the room drew before — a head that showed less than
    /// the card it displaced would be a regression wearing a new feature.
    ///
    /// Heights are a share of the biggest month DRAWN, so the strip is a
    /// comparison among the months you can see. Only the first and last months
    /// are labelled: twelve ticks at label size is a row of noise, and the two
    /// ends are what make the middle readable.
    private var monthStrip: some View {
        let top = room.months.map(\.total).max() ?? 0
        return VStack(alignment: .leading, spacing: DS.Space.s1) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(room.months) { month in
                    Capsule(style: .continuous)
                        .fill(Self.mark.opacity(0.85))
                        // Floored so a month with a single small spend is still
                        // a visible column rather than a sub-pixel nothing — a
                        // month that had spending must never draw as one that
                        // did not.
                        .frame(height: max(4, 34 * GnosisPayRoom.monthShare(total: month.total, of: top)))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 34, alignment: .bottom)
            .chartWipe(reduceMotion: reduceMotion)
            if let first = room.months.first, let last = room.months.last, room.months.count > 1 {
                HStack {
                    Text(GnosisPayRoom.monthLabel(first.start))
                    Spacer(minLength: DS.Space.s2)
                    Text(GnosisPayRoom.monthLabel(last.start))
                }
                .dsText(.label12)
                .foregroundStyle(DS.textTertiary)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text(GnosisPayRoom.historyNote(room) ?? ""))
    }

    // MARK: - Rows

    private func row(_ currency: GnosisPayRoom.Currency, index: Int) -> some View {
        Button {
            DSHaptic.selection()
            onOpen(currency)
        } label: {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                    Text(currency.code)
                        .dsText(.body17)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: DS.Space.s2)
                    Text(GnosisPayRoom.currencyLine(currency))
                        .dsText(.subhead13)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                }
                ShareBar(fraction: GnosisPayRoom.share(spends: currency.spends, of: top),
                         index: index,
                         reduceMotion: reduceMotion)
            }
            .padding(.vertical, DS.Space.s1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(currency.code), \(GnosisPayRoom.currencyLine(currency))"))
    }
}
