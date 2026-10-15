import Foundation

/// What left your accounts this calendar month, by place (the Wallet's Home
/// Spending section). A place is a merchant a card names, the card itself when
/// the chain does not name one (MetaMask Card, ether.fi), or an onchain
/// counterparty — a name the book or the exchange label gives, else the short
/// address. A move between your own accounts is never spending, a trade is
/// never spending (`trades`), and a refund takes its amount back off its place.
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

    /// One onchain leg, as `trades` reads it.
    struct Leg: Equatable {
        var id: Int
        var wallet: String
        /// The transaction (its explorer link), so two legs of one swap meet.
        var tx: String
        var sent: Bool
        var usd: Double?
        var at: Date
    }

    /// How far apart a sell and its buy may land and still be one trade: a
    /// cross-chain swap or an intent fills in a second transaction, minutes on.
    static let tradeWindow: TimeInterval = 30 * 60
    /// What the buy may be worth against the sell: fees and slippage below,
    /// a price move between the two transactions above.
    static let tradeBand: ClosedRange<Double> = 0.8...1.25

    /// The sends that are one side of a trade, by id: money that came back to
    /// the same wallet. A swap is not spending (user, 2026-10-15: "I may have
    /// swapped $1000 in 10 different swaps, but I didn't spend $10,000", prd §1319), and
    /// ingest folds a swap into one row only when both legs land in one pass
    /// on one hash with two different symbols — a cross-chain swap, an intent
    /// filled later, a USDC → USDC.e route, or a leg landed a pass apart each
    /// left the sell standing as a plain send.
    ///
    /// Two rules: a send whose transaction also paid this wallet; else the
    /// nearest priced receipt to this wallet within `tradeWindow`, worth
    /// `tradeBand` of the send, each receipt matched once.
    static func trades(_ legs: [Leg]) -> Set<Int> {
        var out = Set<Int>()
        var used = Set<Int>()
        let paid = Set(legs.filter { !$0.sent }.map { "\($0.wallet)|\($0.tx)" })
        for leg in legs where leg.sent && paid.contains("\(leg.wallet)|\(leg.tx)") {
            out.insert(leg.id)
        }
        // A receipt on a trade's own transaction is that trade's buy.
        let tradeTx = Set(legs.filter { out.contains($0.id) }.map { "\($0.wallet)|\($0.tx)" })
        for leg in legs where !leg.sent && tradeTx.contains("\(leg.wallet)|\(leg.tx)") {
            used.insert(leg.id)
        }
        let receipts = legs.filter { !$0.sent && !used.contains($0.id) }
        for send in legs.filter({ $0.sent && !out.contains($0.id) }).sorted(by: { $0.at < $1.at }) {
            guard let sold = send.usd, sold > 0 else { continue }
            let match = receipts
                .filter { r in
                    guard !used.contains(r.id), r.wallet == send.wallet, let got = r.usd,
                          abs(r.at.timeIntervalSince(send.at)) <= tradeWindow else { return false }
                    return tradeBand.contains(got / sold)
                }
                .min { abs($0.at.timeIntervalSince(send.at)) < abs($1.at.timeIntervalSince(send.at)) }
            if let match {
                out.insert(send.id)
                used.insert(match.id)
            }
        }
        return out
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
