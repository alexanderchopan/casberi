import Foundation
import SwiftData

/// The Apple Wallet room head's READING half (2026-08-06, prd §313) — landed
/// rows and the stored balance/due snapshots, turned into the plain values
/// `AppleWalletRoom` judges.
///
/// The split is `StripeRoomSource`'s and exists for its reason, one degree
/// sharper: this file touches `Thing` and `UserDefaults` and so can never be
/// compiled by a harness, while `AppleWalletRoom.swift` is Foundation-only and
/// is compiled WHOLE by `scripts/applewallet-selftest.sh`. Everything that
/// could be wrong in a way that still renders perfectly — a price rise computed
/// off the wrong pair of charges, a cadence believed on two points, a
/// subscription called silent while it's merely late, a total that summed two
/// currencies — lives on the other side of that line.
///
/// It matters more here than for Stripe or PostHog: **no simulator has
/// FinanceKit data**, so this room can never be exercised by a sim sweep. The
/// harness is the only proof before a real device with a real Apple Card.
///
/// ## It spends nothing
///
/// Every fact is already on the device: rows the bridge landed, plus the
/// balance and `nextPaymentDueDate` snapshots `AppleWalletBridge` keeps behind
/// §216's ten-minute window. No request, no new `Thing` field, no CloudKit
/// deploy — `CloudflareRunwaySource`'s contract, for its reason: a head that
/// costs a call is a head that can fail, and a room's lede must not be able to
/// fail differently from the rows beneath it.
///
/// ## Reading money back out of a row
///
/// Unlike Stripe — whose amounts exist only as formatted substrings inside a
/// title, which is why its head refuses to do arithmetic — these rows carry
/// `priceValue` and `priceCurrency` as real numbers, stamped at landing. So
/// this card CAN total, and does. Nothing here re-parses prose.
enum AppleWalletRoomSource {

    /// Rows older than this are ignored entirely. `AppleWalletRoom` needs
    /// history to find a cadence (three charges of a monthly subscription is
    /// ~90 days), and a year bounds the walk without reaching data the
    /// leaderboard's own 30-day window would discard anyway.
    static let lookbackDays = 400

    /// Landed rows → the plain values the room judges.
    ///
    /// Split out of `compose` so `AppleWalletBridge.landChanges` reads the
    /// corpus through exactly this function: the price rise it LANDS and the
    /// price rise the card DRAWS are then computed from one reading, and a
    /// change to what counts as a spend can't leave the two disagreeing about
    /// whether a subscription went up.
    @MainActor
    static func spends(from things: [Thing], now: Date = .now) -> [AppleWalletRoom.Spend] {
        let floor = now.addingTimeInterval(-Double(lookbackDays) * 86_400)
        var out: [AppleWalletRoom.Spend] = []
        // Filtered to live at the BOUNDARY, before a single stored property is
        // read (corollary 4) — the caller's array may be a debounced snapshot.
        for thing in things.live where thing.source == AppleWalletBridge.sourceName {
            // A payment-due row is a clock, not a spend; a price-rise row is an
            // observation ABOUT spends. Neither carries `priceCurrency`+
            // counterparty in a way that would survive below — but skipping by
            // KIND says why, and stops a future row that gains an amount from
            // silently entering the leaderboard as a merchant.
            guard thing.kind == .transaction else { continue }
            guard let amount = thing.priceValue,
                  let currency = thing.priceCurrency,
                  let merchant = thing.transferCounterparty else { continue }
            guard thing.capturedAt >= floor else { continue }
            out.append(AppleWalletRoom.Spend(
                merchant: merchant,
                amount: abs(amount),
                currency: currency,
                date: thing.capturedAt,
                isSettled: !thing.tags.contains("Pending"),
                isRefund: thing.tags.contains("Refund")))
        }
        return out
    }

    @MainActor
    static func compose(things: [Thing], now: Date = .now) -> AppleWalletRoom.Card? {
        guard AppleWalletBridge.connected else { return nil }
        let spends = spends(from: things, now: now)

        let dues = AppleWalletBridge.dues.map { account, stamp -> AppleWalletRoom.Due in
            let date = Date(timeIntervalSince1970: stamp)
            return AppleWalletRoom.Due(account: account, date: date,
                                       amount: nil,
                                       currency: dominantDueCurrency(spends),
                                       isOverdue: date < now)
        }
        return AppleWalletRoom.compose(spends: spends, dues: dues, now: now)
    }

    /// A due date carries no currency of its own in the snapshot (it's a date,
    /// keyed by account name), so it inherits the room's. Falling back to the
    /// device's own code rather than a hardcoded "USD" — the room's rule is
    /// that a number never appears without the currency it's in, and guessing
    /// the wrong one is exactly the ambiguity that rule exists to prevent.
    private static func dominantDueCurrency(_ spends: [AppleWalletRoom.Spend]) -> String {
        AppleWalletRoom.dominantCurrency(spends.filter(\.isSettled))
            ?? Locale.current.currency?.identifier ?? "USD"
    }
}
