import Foundation

/// BILLERS IN THE ADDRESS BOOK (prd §1106) — every merchant that charges you
/// on a schedule, as a row in Addresses beside the people and wallets.
///
/// A biller is wider than a subscription on purpose. A subscription is ONE
/// price recurring (`Subscriptions.believes`); a biller is anything recurring
/// a month apart or longer, so the power bill whose amount moves every month
/// is a biller and never a subscription. Everything else is the Subscriptions
/// tile's reading, reused whole, so the two can never disagree about a
/// merchant they both list:
///   • every subscription (`Subscriptions.compose`: cards, Rocket Money's
///     bills, the ones you added), marked `subscription`;
///   • a card's series that keeps a cadence of `Subscriptions.minCadenceDays`
///     or longer while its price moves, unmarked.
/// A charge that stopped (`hasStopped`) is no biller, however long ago. The
/// onchain cards name no merchant, so they add none.
///
/// Foundation-only, reading `Subscriptions` and `AppleWalletRoom` (both
/// Foundation-only), so `scripts/billers-selftest.sh` compiles all three WHOLE.
enum Billers {

    struct Biller: Equatable, Identifiable {
        /// What the tile's sheet draws: name, last amount, cadence, next
        /// charge, what pays it, since, paid so far, a site you gave.
        var item: Subscriptions.Item
        /// One price recurring — it is on the Subscriptions tile too.
        var subscription: Bool

        /// The merge key (`Subscriptions.key`), which `Identity.key(.biller,…)`
        /// spells behind its prefix.
        var id: String { item.id }
    }

    static func compose(found: [Subscriptions.Found], bills: [Subscriptions.Bill],
                        manual: [Subscriptions.Manual], now: Date,
                        calendar: Calendar = .current) -> [Biller] {
        let subscriptions = Subscriptions.compose(found: found, bills: bills, manual: manual,
                                                  now: now, calendar: calendar)
        let stopped = Set(found.map(\.series).filter { hasStopped($0, now: now) }
            .map { Subscriptions.key($0.merchant) })
        // A stopped card series ends the biller only when the card is all
        // that saw it: a Rocket Money bill or one you added still says it is
        // live (paid from a card that is not connected, say).
        let cards = Set(found.map(\.source))
        let standing = subscriptions.filter { item in
            !stopped.contains(item.id) || item.foundIn.contains { !cards.contains($0) }
        }
        var out = standing.map { Biller(item: $0, subscription: true) }
        var seen = Set(standing.map(\.id))

        // Newest charge first, as `Subscriptions.compose` takes them, so a
        // merchant two cards paid names the card that paid it last.
        for f in found.sorted(by: { $0.series.last.date > $1.series.last.date }) {
            let key = Subscriptions.key(f.series.merchant)
            guard !key.isEmpty, !seen.contains(key), !stopped.contains(key),
                  f.series.cadenceDays >= Subscriptions.minCadenceDays else { continue }
            seen.insert(key)
            let charges = f.series.charges
            out.append(Biller(item: Subscriptions.Item(
                id: key, name: f.series.merchant,
                amount: f.series.last.amount, currency: f.series.currency,
                cadenceDays: f.series.cadenceDays, next: f.series.nextExpected,
                paysWith: f.paysWith, since: charges.first?.date,
                paid: charges.reduce(0) { $0 + $1.amount },
                // A moving bill has no "was": a rise is a subscription's word.
                was: nil, site: nil, manualID: nil, foundIn: [f.source]),
                subscription: false))
        }
        return out
    }

    /// A card's series that stopped: as late as `AppleWalletRoom.silences`
    /// calls silent, with NO ceiling. `silences` stops reporting at
    /// `silenceCeilingDays` because a long-quit plan is no NEWS; a biller is
    /// a standing fact, and a plan quit five months ago is not one, so the
    /// ceiling cannot apply here (measured: a plan last charged 126 days ago
    /// passed `Subscriptions.compose` with a renewal date in the past).
    static func hasStopped(_ series: AppleWalletRoom.Series, now: Date) -> Bool {
        let late = now.timeIntervalSince(series.nextExpected) / 86_400
        let threshold = max(Double(AppleWalletRoom.silenceFloorDays),
                            Double(series.cadenceDays) * (AppleWalletRoom.silenceFactor - 1))
        return late >= threshold
    }
}
