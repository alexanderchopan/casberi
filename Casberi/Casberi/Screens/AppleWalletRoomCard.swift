import SwiftUI

/// THE APPLE WALLET ROOM'S HEAD (2026-08-06, prd §313) — who you actually pay,
/// and what changed since last time.
///
/// Three things get drawn, in the order they cost you to miss:
///  1. **The change line** — a recurring price that rose, a subscription that
///     stopped. This is the room's reason to exist: your bank told you about
///     the charge, nothing told you about the delta.
///  2. **The merchants** — ranked bars, because money ranks by AMOUNT and
///     `FeedInsight.leaderboard` ranks by ROW COUNT. Ten coffees and one
///     flight are the same height there and nothing alike here.
///  3. **The clock rail** — what's due, soonest first.
///
/// Judgement lives in `AppleWalletRoom` (Foundation-only, harness-compiled);
/// this file only draws. It holds NO `Thing` (corollary 5) — every tap hands
/// back a merchant name and the lookup happens against the live corpus.
///
/// The `chartArrival` entrances are the design-motion audit's requirement for a
/// drawing sized from data (prd §299), and every one honours Reduce Motion.
struct AppleWalletRoomCard: View {
    let room: AppleWalletRoom.Card
    /// Hands back the MERCHANT NAME, never a `Thing`.
    var onOpenMerchant: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Apple Card's own graphite, from the brand table — never inlined.
    private static let mark = DS.brandHue(for: "Apple Wallet") ?? Color.fixed("#1d1d1f")
    private static let barHeight: CGFloat = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The source-name eyebrow retired here 2026-08-22 (prd §452). A room
            // head renders only inside its own source's room, under a chip strip
            // where that source's chip is the lit one — so the card introduced
            // itself with a word already on screen, one row up.
            Text(room.headline)
                .dsText(.heading22)
                .foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let subline = room.subline {
                Text(subline)
                    .dsText(.subhead13)
                    .foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, DS.Space.s1)
            }

            if !room.merchants.isEmpty {
                merchants.padding(.top, DS.Space.s4)
            }

            if !room.upcoming.isEmpty {
                rail.padding(.top, DS.Space.s4)
            }

            if let note = room.note {
                Text(note)
                    .dsText(.label11)
                    .foregroundStyle(DS.textTertiary)
                    .padding(.top, DS.Space.s3)
            }
        }
        .padding(DS.Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsWidgetSurface()
        .padding(.horizontal, DS.Space.s4)
        .padding(.top, DS.Space.s2)
    }

    // MARK: - Who you actually pay

    /// Bars are proportional to NET SPEND and to nothing else. Opacity carries
    /// rank so the eye lands on the top row, and neither channel carries state
    /// — the reach-map invariant (§300): area means magnitude and only
    /// magnitude.
    private var merchants: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            ForEach(Array(room.merchants.enumerated()), id: \.element.name) { index, row in
                Button {
                    DSHaptic.selection()
                    onOpenMerchant(row.name)
                } label: {
                    merchantRow(row, lead: index == 0)
                }
                .buttonStyle(.plain)
                .chartArrival(index: index, reduceMotion: reduceMotion)
            }

            // The tail is FOLDED and named, never truncated — a dropped sixth
            // merchant looks exactly like a card that only had five (§300).
            if room.moreMerchants > 0 {
                Text(room.moreMerchants == 1
                     ? String(localized: "1 more merchant")
                     : String(localized: "\(room.moreMerchants) more merchants"))
                    .dsText(.label11)
                    .foregroundStyle(DS.textTertiary)
            }
        }
    }

    private func merchantRow(_ row: AppleWalletRoom.MerchantRow, lead: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                Text(row.name)
                    .dsText(.subhead13)
                    .fontWeight(lead ? .semibold : .regular)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: DS.Space.s2)
                Text(AppleWalletRoom.money(row.total, row.currency))
                    .dsText(.subhead13)
                    .fontWeight(lead ? .semibold : .regular)
                    .foregroundStyle(lead ? DS.textPrimary : DS.textSecondary)
                    .monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.fillLine)
                    Capsule()
                        .fill(Self.mark.opacity(lead ? 0.95 : 0.55))
                        .frame(width: max(3, geo.size.width * row.share))
                }
            }
            .frame(height: Self.barHeight)
            Text(row.count == 1
                 ? String(localized: "1 charge")
                 : String(localized: "\(row.count) charges"))
                .dsText(.label11)
                .foregroundStyle(DS.textTertiary)
        }
        .contentShape(Rectangle())
    }

    // MARK: - The clock rail

    /// What's coming. A real payment deadline wears a filled mark; an inferred
    /// recurring date wears a hollow one — the card must not let our own
    /// arithmetic look like the bank's fact.
    private var rail: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            Text(String(localized: "Coming up"))
                .dsText(.label12).fontWeight(.semibold)
                .foregroundStyle(DS.textSecondary)
            ForEach(Array(room.upcoming.enumerated()), id: \.offset) { index, item in
                railRow(item)
                    .chartArrival(index: index, reduceMotion: reduceMotion)
            }
        }
    }

    /// Split out of `rail`'s ForEach: inline, the ternaries inside the
    /// modifier chain take the type-checker past its budget and the build
    /// fails with an error that names no cause. Same view, one function down.
    private func railRow(_ item: AppleWalletRoom.Upcoming) -> some View {
        let isPayment = item.kind == .payment
        let markColor: Color = isPayment ? Self.mark : DS.fillStrong
        let width: CGFloat = isPayment ? 4 : 1.5
        let trailing: String = item.isOverdue
            ? String(localized: "overdue")
            : AppleWalletRoom.dayLabel(item.date)
        return HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
            Circle()
                .strokeBorder(markColor, lineWidth: width)
                .frame(width: 9, height: 9)
                .offset(y: 2)
            Text(item.label)
                .dsText(.subhead13)
                .foregroundStyle(DS.textPrimary)
                .lineLimit(1)
            Spacer(minLength: DS.Space.s2)
            Text(trailing)
                .dsText(.label11)
                .foregroundStyle(item.isOverdue ? DS.textPrimary : DS.textTertiary)
        }
    }
}
