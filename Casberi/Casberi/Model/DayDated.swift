import Foundation

/// **DAY IS WHAT'S COMING, FROM EVERY APP AND THE WALLET (prd §1327 item 3).**
/// Coming up held only what is STORED with a date ahead (an event's start, a
/// deadline's `dueAt`). The dated things the app COMPUTES were missing: a
/// plan's next renewal (`Subscriptions.Item.next`) and a card's payment date
/// (`WalletCardRoll.Card.due`). This turns each place's own reading into
/// Coming up's entries; it never decides a date itself. A renewal's day is
/// the Wallet's (`Subscriptions.compose`: the card series' `nextExpected`, a
/// Rocket Money bill's due, a hand-tracked plan's `nextRenewal`), a card's is
/// its issuer's, as FinanceKit last said it.
///
/// A mail list's "day" is NOT here: `MailSubscriptions` reads a median gap
/// (how often) and predicts no day, and a newsletter has no date anyone set,
/// so a day for it would be a guess (§83).
///
/// Foundation-only: `scripts/day-dated-selftest.sh` compiles it whole with
/// `Subscriptions.swift`, `AppleWalletRoom.swift` and `WalletCardRoll.swift`.
enum DayDated {

    /// Where an entry comes from: the line names it, place first (§1329).
    enum Place: String, Equatable, Sendable {
        case subscription, card
    }

    /// What the day is to that place.
    enum Word: Equatable, Sendable {
        /// A plan with a known cadence renews.
        case renews
        /// A plan whose cadence nothing said (a Rocket Money bill): its next
        /// charge, never called a renewal.
        case nextCharge
        /// A card's payment date.
        case due
    }

    /// What a tap opens: the same sheet the entry opens in its own place.
    enum Opens: Equatable, Hashable, Sendable {
        /// The plan's sheet, by its key (`Subscriptions.Item.id`).
        case plan(String)
        /// The app that reads the card, as the Wallet's Cards row opens it.
        case card(app: String)
    }

    struct Entry: Equatable, Identifiable {
        /// "plan:<key>" or "card:<name>", unique across both.
        let id: String
        /// The plan's or the card's name.
        let name: String
        let when: Date
        let place: Place
        let word: Word
        /// The figure: one charge of the plan, or what the card owes. Nil
        /// when the place's reading does not say.
        let amount: Double?
        let currency: String
        /// The price before a rise still fresh enough for the Wallet to say
        /// (`Subscriptions.Item.was`), so Day says it too.
        let was: Double?
        /// What pays a plan ("Apple Card"); nil for a card.
        let paysWith: String?
        let opens: Opens
    }

    /// Whether a day falls in Coming up's window: from the start of today
    /// (a renewal has no time of day, so one due this morning is still
    /// today's) to `end`, the midnight after the week's last day.
    static func inWindow(_ when: Date, now: Date, end: Date, calendar: Calendar) -> Bool {
        when >= calendar.startOfDay(for: now) && when < end
    }

    /// Every renewal in the window, as the Wallet's reading dates it. A plan
    /// with no `next` is not dated, and none is invented.
    static func renewals(_ items: [Subscriptions.Item], now: Date, end: Date,
                         calendar: Calendar) -> [Entry] {
        items.compactMap { item in
            guard let next = item.next, inWindow(next, now: now, end: end, calendar: calendar)
            else { return nil }
            return Entry(id: "plan:\(item.id)", name: item.name, when: next, place: .subscription,
                         word: item.cadenceDays == nil ? .nextCharge : .renews,
                         amount: item.amount, currency: item.currency,
                         was: item.was, paysWith: item.paysWith, opens: .plan(item.id))
        }
    }

    /// Every card payment date in the window, as its issuer said it. A card
    /// with no due date asks nothing dated of you.
    static func cardDues(_ cards: [WalletCardRoll.Card], now: Date, end: Date,
                         calendar: Calendar) -> [Entry] {
        cards.compactMap { card in
            guard let due = card.due, inWindow(due, now: now, end: end, calendar: calendar)
            else { return nil }
            return Entry(id: "card:\(card.name)", name: card.name, when: due, place: .card,
                         word: .due, amount: card.owed, currency: card.owedCurrency,
                         was: nil, paysWith: nil, opens: .card(app: card.app))
        }
    }

    /// Every place's entries as one list: soonest first, a tie by name, then
    /// by id, so the order never depends on the order handed in.
    static func entries(_ places: [[Entry]]) -> [Entry] {
        var seen = Set<String>()
        return places.joined()
            .filter { seen.insert($0.id).inserted }
            .sorted { a, b in
                if a.when != b.when { return a.when < b.when }
                let byName = a.name.localizedStandardCompare(b.name)
                if byName != .orderedSame { return byName == .orderedAscending }
                return a.id < b.id
            }
    }

    /// One day of Coming up: the stored rows on it (their order kept), then
    /// the computed entries on it.
    struct Day<ID: Hashable>: Equatable {
        let start: Date
        var stored: [ID]
        var dated: [Entry]
    }

    /// Stored rows and computed entries merged into days, soonest day first.
    /// A day only an entry stands on is a day too. `stored` arrives soonest
    /// first and keeps its order; `dated` arrives as `entries` sorted it.
    static func days<ID: Hashable>(stored: [(id: ID, when: Date)], dated: [Entry],
                                   calendar: Calendar) -> [Day<ID>] {
        var byDay: [Date: Day<ID>] = [:]
        for row in stored {
            let day = calendar.startOfDay(for: row.when)
            byDay[day, default: Day(start: day, stored: [], dated: [])].stored.append(row.id)
        }
        for entry in dated {
            let day = calendar.startOfDay(for: entry.when)
            byDay[day, default: Day(start: day, stored: [], dated: [])].dated.append(entry)
        }
        return byDay.values.sorted { $0.start < $1.start }
    }
}
