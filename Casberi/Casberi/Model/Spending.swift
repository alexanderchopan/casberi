import Foundation

/// What left your accounts this calendar month, by place (the Wallet's Home
/// Spending section). A place is a merchant a card names, the card itself when
/// the chain does not name one (MetaMask Card, ether.fi), or an onchain
/// counterparty — a name the book or the exchange label gives, else the short
/// address. A move between your own accounts is never spending, and a refund
/// takes its amount back off its place.
///
/// Compared with LAST month TO THE SAME DAY, never last month whole: on the
/// 8th a whole September would always read as more.
///
/// Foundation-only and pure.
enum Spending {

    struct Charge: Equatable {
        var place: String
        /// Dollars; a refund is negative.
        var usd: Double
        var at: Date
    }

    struct Place: Equatable {
        var name: String
        var usd: Double
        var count: Int
    }

    struct Reading: Equatable {
        var total: Double
        /// Last month up to this day of it, or nil when nothing was read then.
        var earlier: Double?
        /// Largest first; a place whose refunds cancelled it is left out.
        var places: [Place]
    }

    static func read(_ charges: [Charge], now: Date, calendar: Calendar = .current) -> Reading {
        guard let month = calendar.dateInterval(of: .month, for: now),
              let lastStart = calendar.date(byAdding: .month, value: -1, to: month.start)
        else { return Reading(total: 0, earlier: nil, places: []) }
        // The same point a month back, clamped by the calendar (Mar 31 → Feb 28).
        let lastEnd = calendar.date(byAdding: .month, value: -1, to: now) ?? month.start

        var byPlace: [String: Place] = [:]
        var earlier: Double = 0
        var sawEarlier = false
        for charge in charges {
            if charge.at >= month.start && charge.at <= now {
                let key = charge.place.lowercased()
                var place = byPlace[key] ?? Place(name: charge.place, usd: 0, count: 0)
                place.usd += charge.usd
                if charge.usd > 0 { place.count += 1 }
                byPlace[key] = place
            } else if charge.at >= lastStart && charge.at <= lastEnd {
                earlier += charge.usd
                sawEarlier = true
            }
        }
        let places = byPlace.values
            .filter { $0.usd >= 0.005 }
            .sorted { $0.usd != $1.usd ? $0.usd > $1.usd : $0.name < $1.name }
        return Reading(total: places.reduce(0) { $0 + $1.usd },
                       earlier: sawEarlier ? max(0, earlier) : nil,
                       places: places)
    }
}
