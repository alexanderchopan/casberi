import SwiftUI

/// THE APPLE WALLET ROOM'S HEAD (2026-08-06, prd §313) — what changed since last
/// time, and what is coming.
///
/// Two things get drawn, in the order they cost you to miss:
///  1. **The change line** — a recurring price that rose, a subscription that
///     stopped. This is the room's reason to exist: your bank told you about
///     the charge, nothing told you about the delta.
///  2. **The clock rail** — what's due, soonest first.
///
/// **The merchant board is deleted (prd §745).** It ranked who you pay by
/// amount under ten-pixel bars — "Who you actually pay" — which is the
/// card-spend board §723 deleted from every other room ("visualization data
/// just for the sake of it"), surviving here because this head drew it by hand
/// rather than through `FeedInsight.leaderboard`. The lede still names the top
/// merchant, and every charge is its own row a scroll below.
///
/// Judgement lives in `AppleWalletRoom` (Foundation-only, harness-compiled);
/// this file only draws. It holds NO `Thing` (corollary 5) and, with the board
/// gone, no door: nothing on it names a single row.
struct AppleWalletRoomCard: View {
    let room: AppleWalletRoom.Card

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Apple Card's own graphite, from the brand table — never inlined.
    private static let mark = DS.brandHue(for: "Apple Wallet") ?? Color.fixed("#1d1d1f")

    var body: some View {
        DSRoomChassis.Head(
            lead: .figure(room.lede, otherwise: room.headline),
            notes: [.note(room.subline)],
            footnotes: [.quiet(room.note)]) {
            if !room.upcoming.isEmpty {
                DSRoomChassis.Block { rail }
            }
        }
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
