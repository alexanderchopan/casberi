import Foundation

/// **THE WALLET'S CARDS (prd §1232, user: "is having a cards section useful in
/// a way that isn't covered by spending? if so we should have it too").**
/// Spending answers where the money went; this answers what each card asks of
/// you: what it spent this month, what it owes and when, and the offers on it.
///
/// Foundation-only, so `wallet-card-roll-selftest.sh` compiles it whole: the
/// order a card is drawn in, and what counts toward a month, are the facts a
/// screenshot cannot check.
enum WalletCardRoll {

    struct Card: Equatable, Identifiable {
        var id: String { name }
        /// As the person knows it ("Apple Card", "Amex Gold").
        var name: String
        /// The source that reads it, for its mark and its page.
        var app: String
        /// Dollars spent this month, refunds netted.
        var spent: Double = 0
        var purchases: Int = 0
        /// What the card owes, in `owedCurrency`, as its issuer says it.
        var owed: Double?
        var owedCurrency: String = "USD"
        /// The issuer's own payment date, never inferred.
        var due: Date?
        /// Offers on the card still in play.
        var offers: Int = 0
        /// When the soonest of them ends.
        var offerEnds: Date?
        /// The newest purchase, whatever the month.
        var lastSpend: Date?

        /// The soonest day the card asks something of you.
        var asks: Date? { [due, offerEnds].compactMap { $0 }.min() }
    }

    struct Spend {
        var card: String
        var app: String
        /// Negative for a refund.
        var usd: Double
        var at: Date
    }

    struct Owed {
        var card: String
        var app: String
        var amount: Double?
        var currency: String
        var due: Date?
    }

    struct Offer {
        var card: String
        var app: String
        var expires: Date?
    }

    /// One card per name, in the order the box and the list draw them: what
    /// asks something of you soonest first, then the most spent this month,
    /// then by name.
    static func compose(spends: [Spend], owed: [Owed], offers: [Offer],
                        now: Date, calendar: Calendar = .current) -> [Card] {
        var cards: [String: Card] = [:]
        func card(_ name: String, _ app: String) -> Card {
            cards[name.lowercased()] ?? Card(name: name, app: app)
        }
        let month = calendar.dateInterval(of: .month, for: now)
        for spend in spends {
            var c = card(spend.card, spend.app)
            if let month, spend.at >= month.start, spend.at <= now {
                c.spent += spend.usd
                if spend.usd > 0 { c.purchases += 1 }
            }
            if spend.usd > 0 { c.lastSpend = max(c.lastSpend ?? spend.at, spend.at) }
            cards[spend.card.lowercased()] = c
        }
        for o in owed {
            var c = card(o.card, o.app)
            if let amount = o.amount, amount > 0 {
                c.owed = amount
                c.owedCurrency = o.currency
            }
            c.due = o.due
            cards[o.card.lowercased()] = c
        }
        for offer in offers {
            // An offer already past its end is not one you can use.
            if let ends = offer.expires, ends < now { continue }
            var c = card(offer.card, offer.app)
            c.offers += 1
            if let ends = offer.expires { c.offerEnds = min(c.offerEnds ?? ends, ends) }
            cards[offer.card.lowercased()] = c
        }
        return cards.values.sorted { a, b in
            switch (a.asks, b.asks) {
            case let (x?, y?) where x != y: return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default:
                if a.spent != b.spent { return a.spent > b.spent }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
        }
    }
}
