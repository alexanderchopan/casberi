import Foundation

/// THE WALLET'S SUBSCRIPTIONS TILE (prd §1105) — what repeats, what it costs,
/// and when it renews next. It took the Cards tile's place: a card's spends
/// stay on Home and one pick away in the account menu, and the question the
/// tile answers instead is the one the money direction is built on, "what am I
/// paying for, and what does it cost me".
///
/// ## Where a subscription comes from
///
/// Three readings and one hand, merged by name:
///   • a charge that repeats on a card or account that names its merchant
///     (Apple Wallet through FinanceKit, Privacy.com), found by
///     `AppleWalletRoom.recurringSeries` — the same arithmetic that already
///     finds a price rise and a charge that stopped, so the tile and those
///     rows can never disagree about what recurs;
///   • a bill Rocket Money dates (`RocketMoneyLive`, prd §1048f);
///   • one the person added (`SubscriptionStore`), for anything none of the
///     above can see.
/// The onchain cards are NOT read: a chain row says what was spent, never
/// where (`GnosisPayBridge`'s standing ceiling), so no merchant can recur.
///
/// ## What it refuses to claim
///
/// A cadence is believed only on the series' own evidence (three settled
/// charges, every gap within tolerance). A Rocket Money bill whose frequency
/// the page did not say is listed with its next charge and left out of the
/// monthly total, named, rather than assumed monthly (§83). A charge that
/// stopped (`hasStopped`) is not a subscription any more and is not listed,
/// however long ago it stopped (prd §1106b). Currencies are never summed without a rate (`total`).
///
/// Foundation-only, and it reads `AppleWalletRoom` (also Foundation-only), so
/// `scripts/subscriptions-selftest.sh` compiles both WHOLE.
enum Subscriptions {

    /// Days in an average month, for a cadence's monthly equivalent.
    static let monthDays = 30.4375
    /// A cadence this long or longer reads as yearly.
    static let yearlyFromDays = 300
    /// A cadence inside this band reads as monthly, and costs its price.
    static let monthlyDays = 25...35
    /// The shortest cadence believed as a subscription. `recurringSeries`
    /// believes six days, which is right for the Apple Wallet room's own
    /// rows and wrong here: a weekly coffee at the same shop recurs and is
    /// not something you subscribe to (measured on the demo: Uber read as a
    /// subscription with a "price rise").
    static let minCadenceDays = 25
    /// How far a charge before the latest may sit from their median and still
    /// read as the same price. A shop's bill moves; a plan's does not.
    static let steadyTolerance = 0.02

    /// One subscription, as the tile, the calendar and the sheet draw it.
    struct Item: Equatable, Identifiable {
        /// The merge key (`key(_:)`), stable across refreshes.
        var id: String
        var name: String
        /// One charge, in `currency`. Nil when nothing says the price.
        var amount: Double?
        var currency: String
        /// Nil when the frequency is unknown — never guessed.
        var cadenceDays: Int?
        var next: Date?
        /// What it is charged to, as the person knows it ("Apple Card").
        var paysWith: String?
        /// The first charge seen.
        var since: Date?
        /// Every settled charge seen, summed (same currency, by construction).
        var paid: Double?
        /// The price before a rise still fresh enough to say (`creepFreshDays`).
        var was: Double?
        /// A website the person gave, for the billing door.
        var site: String?
        /// The id of the hand-added entry behind this item, when there is one.
        var manualID: String?
        /// Every reading that saw it, in order: seats' sources, then "You".
        var foundIn: [String]

        /// What it costs a month: the price itself for a monthly cadence, a
        /// twelfth of it for a yearly one. Nil without a price or a known
        /// cadence.
        var monthly: Double? {
            guard let amount, let days = cadenceDays, days > 0 else { return nil }
            if Subscriptions.monthlyDays.contains(days) { return amount }
            if days >= Subscriptions.yearlyFromDays { return amount / 12 }
            return amount * Subscriptions.monthDays / Double(days)
        }

        var isYearly: Bool { (cadenceDays ?? 0) >= Subscriptions.yearlyFromDays }
    }

    /// A dated bill a seat hands over (Rocket Money's upcoming page).
    struct Bill: Equatable {
        var name: String
        var amount: Double?
        var currency: String
        var due: Date
        var source: String
    }

    /// One charge found repeating, with what paid it.
    struct Found: Equatable {
        var series: AppleWalletRoom.Series
        /// The card or account, as the person knows it.
        var paysWith: String
        /// The `Thing.source` its rows land under.
        var source: String
        /// The price before a fresh rise, when `AppleWalletRoom.creeps` saw one.
        var was: Double?
    }

    /// One the person added by hand.
    struct Manual: Codable, Equatable, Identifiable {
        var id: String
        var name: String
        var amount: Double
        var currency: String
        var yearly: Bool
        /// A renewal date the person gave; the next one rolls forward from it.
        var anchor: Date
        var paysWith: String?
        var site: String?
        /// When it was added or last changed — the mirror's stamp.
        var at: Date
    }

    /// The reading that marks a hand-added item in `foundIn`.
    static let byYou = "You"

    /// The merge key: the merchant's name as `AppleWalletRoom` groups it, so a
    /// name added by hand matches the same merchant found on a card.
    static func key(_ name: String) -> String {
        AppleWalletRoom.merchantKey(name)
    }

    // MARK: - What counts

    /// Whether a series found repeating is a SUBSCRIPTION: a cadence of a
    /// month or longer, and one price — every charge before the latest within
    /// `steadyTolerance` of their median, so a rise on the latest charge is
    /// still the same plan (the price-rise word), while groceries, rides and
    /// coffee, whose bills move every time, are not.
    static func believes(_ series: AppleWalletRoom.Series) -> Bool {
        guard series.cadenceDays >= minCadenceDays else { return false }
        let earlier = series.charges.dropLast().map(\.amount)
        guard let median = AppleWalletRoom.median(earlier), median > 0 else { return false }
        return earlier.allSatisfy { abs($0 - median) <= median * steadyTolerance }
    }

    // MARK: - Compose

    /// Every subscription, most expensive a month first; one without a known
    /// monthly cost after, by charge, then by name.
    static func compose(found: [Found], bills: [Bill], manual: [Manual],
                        now: Date, calendar: Calendar = .current) -> [Item] {
        var byKey: [String: Item] = [:]
        var order: [String] = []
        func put(_ item: Item) {
            if byKey[item.id] == nil { order.append(item.id) }
            byKey[item.id] = item
        }

        // A charge that stopped is not a subscription any more, however long
        // ago (`hasStopped`): a bill or a hand-added entry below can still
        // list it, because they say it is live.
        let stopped = Set(found.map(\.series).filter { hasStopped($0, now: now) }.map { key($0.merchant) })

        // Newest charge first, so the item takes the card that paid it LAST
        // when two cards both paid the same merchant.
        for f in found.sorted(by: { $0.series.last.date > $1.series.last.date }) {
            let k = key(f.series.merchant)
            guard believes(f.series), !stopped.contains(k) else { continue }
            if var standing = byKey[k] {
                if !standing.foundIn.contains(f.source) { standing.foundIn.append(f.source) }
                put(standing)
                continue
            }
            let charges = f.series.charges
            put(Item(id: k, name: f.series.merchant,
                     amount: f.series.last.amount, currency: f.series.currency,
                     cadenceDays: f.series.cadenceDays, next: f.series.nextExpected,
                     paysWith: f.paysWith, since: charges.first?.date,
                     paid: charges.reduce(0) { $0 + $1.amount }, was: f.was,
                     site: nil, manualID: nil, foundIn: [f.source]))
        }

        for bill in bills.sorted(by: { $0.due < $1.due }) {
            let k = key(bill.name)
            guard !k.isEmpty else { continue }
            if var standing = byKey[k] {
                if !standing.foundIn.contains(bill.source) { standing.foundIn.append(bill.source) }
                if standing.next == nil || standing.next! < now { standing.next = bill.due }
                put(standing)
                continue
            }
            put(Item(id: k, name: bill.name, amount: bill.amount, currency: bill.currency,
                     cadenceDays: nil, next: bill.due, paysWith: nil, since: nil,
                     paid: nil, was: nil, site: nil, manualID: nil, foundIn: [bill.source]))
        }

        for m in manual {
            let k = key(m.name)
            guard !k.isEmpty else { continue }
            if var standing = byKey[k] {
                // What a card or a bill read wins on price and date: it is the
                // charge itself. The hand adds what no reading carries.
                standing.manualID = m.id
                standing.site = m.site ?? standing.site
                standing.paysWith = standing.paysWith ?? m.paysWith
                if standing.cadenceDays == nil { standing.cadenceDays = m.yearly ? 365 : 30 }
                if standing.amount == nil { standing.amount = m.amount }
                if !standing.foundIn.contains(byYou) { standing.foundIn.append(byYou) }
                put(standing)
                continue
            }
            put(Item(id: k, name: m.name, amount: m.amount, currency: m.currency,
                     cadenceDays: m.yearly ? 365 : 30,
                     next: nextRenewal(anchor: m.anchor, yearly: m.yearly, now: now, calendar: calendar),
                     paysWith: m.paysWith, since: nil, paid: nil, was: nil,
                     site: m.site, manualID: m.id, foundIn: [byYou]))
        }

        let items = order.compactMap { byKey[$0] }
        return items.sorted { a, b in
            switch (a.monthly, b.monthly) {
            case let (x?, y?) where x != y: return x > y
            case (.some, nil): return true
            case (nil, .some): return false
            default:
                let (x, y) = (a.amount ?? 0, b.amount ?? 0)
                if x != y { return x > y }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
        }
    }

    /// A card's series that stopped (prd §1106b): as late as
    /// `AppleWalletRoom.silences` calls silent, with NO ceiling. `silences`
    /// stops reporting at `silenceCeilingDays` (120) because a long-quit plan
    /// is no NEWS; a subscription is a standing fact, so the ceiling cannot
    /// apply here. With it, a plan last charged 126 days ago was listed with a
    /// renewal date in the past and counted in the monthly total.
    static func hasStopped(_ series: AppleWalletRoom.Series, now: Date) -> Bool {
        let late = now.timeIntervalSince(series.nextExpected) / 86_400
        let threshold = max(Double(AppleWalletRoom.silenceFloorDays),
                            Double(series.cadenceDays) * (AppleWalletRoom.silenceFactor - 1))
        return late >= threshold
    }

    /// The first renewal on or after the start of today, stepping from the
    /// date the person gave by whole months or years.
    static func nextRenewal(anchor: Date, yearly: Bool, now: Date,
                            calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        var step = 0
        var date = anchor
        // Backwards too: an anchor far in the future still names the next one
        // honestly as itself, so only past anchors step.
        while date < today, step < 600 {
            step += 1
            date = calendar.date(byAdding: yearly ? .year : .month, value: step, to: anchor) ?? date
        }
        return date
    }

    // MARK: - The total

    struct Total: Equatable {
        /// What the counted subscriptions cost a month, in dollars.
        var monthly: Double
        var counted: Int
        /// Names left out: no price, no known cadence, or no rate.
        var uncounted: [String]
        var yearly: Double { monthly * 12 }
    }

    /// The monthly total in dollars. `usd` turns an amount and a code into
    /// dollars, nil when there is no rate — the Wallet's cash rule
    /// (`WalletCash.usd`), so nothing is ever counted at par.
    static func total(_ items: [Item], usd: (Double, String) -> Double?) -> Total {
        var sum = 0.0, counted = 0
        var uncounted: [String] = []
        for item in items {
            guard let monthly = item.monthly, let dollars = usd(monthly, item.currency) else {
                uncounted.append(item.name)
                continue
            }
            sum += dollars
            counted += 1
        }
        return Total(monthly: sum, counted: counted, uncounted: uncounted)
    }
}
