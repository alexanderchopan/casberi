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
        /// What paid it, as the person knows it ("Apple Card"), or
        /// `Subscriptions.byYou` for a plan tracked by hand with no card
        /// behind it (prd §1469); nil when nothing names it.
        var via: String? = nil
    }

    struct Place: Equatable {
        var name: String
        var usd: Double
        var count: Int
        /// The same place last window to the same point (prd §1468), nil
        /// when it had nothing then — the row says "first time".
        var earlier: Double? = nil
        /// A plan the Subscriptions tile already believes recurs (prd §1468,
        /// §1469): it stands in the Subscriptions group, never in Places.
        var recurring: Bool = false
        /// The newest charge in the window, and what paid it — a
        /// subscription's line says both ("Oct 14 · Apple Card").
        var lastAt: Date? = nil
        var via: String? = nil
    }

    struct Reading: Equatable {
        var total: Double
        /// Last window up to this point of it, or nil when nothing was read then.
        var earlier: Double?
        /// Largest first; a place whose refunds cancelled it is left out.
        /// Never a subscription once the caller names them (prd §1469).
        var places: [Place]
        /// **THE SUBSCRIPTIONS GROUP (prd §1469):** the plans the
        /// Subscriptions tile believes, charged this window, newest first.
        /// Empty for Home's reading, which names none.
        var subscriptions: [Place] = []
        /// **RECURRING IS THE SUBSCRIPTIONS GROUP'S SUM (prd §1468, §1469)**,
        /// and the rest is Places': each figure in the box is one list
        /// under the tiles, added up.
        var recurring: Double = 0
        /// The same, last window to the same point; nil with `earlier`.
        var earlierRecurring: Double? = nil

        var rest: Double { max(0, total - recurring) }
        var earlierRest: Double? { earlier.map { max(0, $0 - (earlierRecurring ?? 0)) } }
    }

    /// **THE WINDOW THE TILE READS (prd §1468, user: "we just compare to
    /// last month"; "1 week 1 mo"; "get rid of 3 months b/c we won't have
    /// people that long"; of a day, "a day is a list").** This week against
    /// last week to the same point, or this month against last month to the
    /// same day. Nothing longer, because nobody will hold the data; no day,
    /// because a day's charges are a list, on Home and in the Feed.
    enum Window: String, CaseIterable, Sendable {
        case week, month
    }

    // MARK: - A wallet's sends

    /// One landed move of a watched wallet, as `walletSpends` reads it.
    /// Built by `SpendingSource` from the `Wallet` rows; every field is one
    /// the row already carries.
    struct Move: Equatable {
        /// The watched wallet, lowercased.
        var wallet: String
        /// The transaction, as the row's explorer link: every leg of one
        /// transaction carries it, whichever read landed the leg.
        var tx: String
        /// Which way it went: a send, money arriving, or a folded swap row
        /// (`wallet:swap:`, which stamps no direction).
        var way: Way
        var usd: Double?
        var at: Date
        /// The other side, lowercased.
        var counterparty: String? = nil
        /// What the read called the whole transaction when it was not a
        /// plain send (Zerion's operation type: "trade", "deposit",
        /// "execute"…), nil for a send or a leg no read classified.
        var operation: String? = nil
        /// The caller recognised the counterparty as machinery: a known
        /// router, wrap or protocol contract, or what the book files as a
        /// contract or a Safe.
        var machinery: Bool = false
        /// Where it went, as Spending names it; nil leaves the move out.
        var place: String? = nil

        enum Way: Equatable { case sent, received, swap }
    }

    /// How long after a send money may come back for the pair to read as one
    /// round trip, and how close the two must be in dollars. A cross-chain
    /// swap or a bridge sends on one chain and fills on another in seconds
    /// to minutes, in a transaction of its own, minus a fee and slippage.
    static let roundTripWindow: TimeInterval = 30 * 60
    static let roundTripTolerance = 0.05
    /// A fill can carry a block time a little before the send's on a faster
    /// chain.
    static let roundTripSkew: TimeInterval = 2 * 60

    /// The sends among a wallet's moves that are SPENDING (prd §1201): money
    /// that went to a place, never a move of your own, a swap or a contract.
    ///
    /// `own` is the wallets the person follows NOW, resolved and lowercased.
    ///
    /// Not spending:
    /// - **a send from a wallet you do not follow** — a row an unfollowed
    ///   wallet or Safe left behind is somebody else's money;
    /// - **a send to one of your own wallets**;
    /// - **a send in a transaction that also paid you something** — a trade,
    ///   whatever the symbols, however many passes its legs landed in (a
    ///   same-symbol swap, USDC.e for USDC, never folds into a swap row);
    /// - **a send the read classified as anything but a send** — a trade
    ///   whose other leg never landed, a deposit into a protocol, a call;
    /// - **a send to machinery** the caller recognised;
    /// - **a round trip**: money worth the same (within
    ///   `roundTripTolerance`) arriving at one of your wallets within
    ///   `roundTripWindow`, in a transaction of its own — a cross-chain swap
    ///   or a bridge. Each arrival answers one send at most.
    static func walletSpends(_ moves: [Move], own: Set<String>) -> [Move] {
        // Transactions that paid one of your wallets something.
        let paidBack = Set(moves.filter { $0.way != .sent }.map(\.tx))
        // Money that arrived from outside your own wallets, priced.
        var arrivals: [Move] = moves.filter { m in
            guard m.way == .received, own.contains(m.wallet),
                  let usd = m.usd, usd.isFinite, usd > 0 else { return false }
            return !(m.counterparty.map(own.contains) ?? false)
        }
        var out: [Move] = []
        for send in moves.filter({ $0.way == .sent }).sorted(by: { $0.at < $1.at }) {
            guard own.contains(send.wallet) else { continue }
            guard let usd = send.usd, usd.isFinite, usd > 0, send.place != nil else { continue }
            if let to = send.counterparty, own.contains(to) { continue }
            if send.machinery { continue }
            if paidBack.contains(send.tx) { continue }
            if let op = send.operation, op != "send" { continue }
            // The nearest arrival that answers it, taken so it answers no other.
            let answers = arrivals.indices.filter { i in
                let a = arrivals[i]
                guard a.tx != send.tx, let back = a.usd else { return false }
                let lag = a.at.timeIntervalSince(send.at)
                return lag >= -roundTripSkew && lag <= roundTripWindow
                    && abs(back - usd) <= usd * roundTripTolerance
            }
            if let i = answers.min(by: { abs(arrivals[$0].at.timeIntervalSince(send.at))
                                         < abs(arrivals[$1].at.timeIntervalSince(send.at)) }) {
                arrivals.remove(at: i)
                continue
            }
            out.append(send)
        }
        return out
    }

    /// The window's bounds: its start, and last window's start and the
    /// same point in it. A month back is clamped by the calendar (Mar 31 →
    /// Feb 28); a week back is seven days, to the minute.
    static func bounds(_ window: Window, now: Date, calendar: Calendar = .current)
        -> (start: Date, lastStart: Date, lastEnd: Date)? {
        switch window {
        case .month:
            guard let month = calendar.dateInterval(of: .month, for: now),
                  let lastStart = calendar.date(byAdding: .month, value: -1, to: month.start)
            else { return nil }
            let lastEnd = calendar.date(byAdding: .month, value: -1, to: now) ?? month.start
            return (month.start, lastStart, lastEnd)
        case .week:
            guard let week = calendar.dateInterval(of: .weekOfYear, for: now),
                  let lastStart = calendar.date(byAdding: .day, value: -7, to: week.start),
                  let lastEnd = calendar.date(byAdding: .day, value: -7, to: now)
            else { return nil }
            return (week.start, lastStart, lastEnd)
        }
    }

    /// `isRecurring` answers for a place's name as the caller keys it
    /// (`Subscriptions.key`); the default believes nothing recurs, which is
    /// Home's reading (§1201).
    static func read(_ charges: [Charge], now: Date, calendar: Calendar = .current,
                     window: Window = .month,
                     isRecurring: (String) -> Bool = { _ in false }) -> Reading {
        guard let (start, lastStart, lastEnd) = bounds(window, now: now, calendar: calendar)
        else { return Reading(total: 0, earlier: nil, places: []) }

        var byPlace: [String: Place] = [:]
        var earlierByPlace: [String: Double] = [:]
        var earlier: Double = 0
        var sawEarlier = false
        for charge in charges {
            if charge.at >= start && charge.at <= now {
                let key = charge.place.lowercased()
                var place = byPlace[key] ?? Place(name: charge.place, usd: 0, count: 0)
                place.usd += charge.usd
                if charge.usd > 0 { place.count += 1 }
                if charge.usd > 0, charge.at > (place.lastAt ?? .distantPast) {
                    place.lastAt = charge.at
                    place.via = charge.via
                }
                byPlace[key] = place
            } else if charge.at >= lastStart && charge.at <= lastEnd {
                earlier += charge.usd
                earlierByPlace[charge.place.lowercased(), default: 0] += charge.usd
                sawEarlier = true
            }
        }
        var places: [Place] = []
        var subscriptions: [Place] = []
        for place in byPlace.values where place.usd >= 0.005 {
            var p = place
            let earlierUSD: Double? = earlierByPlace[place.name.lowercased()]
            p.earlier = earlierUSD.map { max(0, $0) }
            p.recurring = isRecurring(place.name)
            if p.recurring { subscriptions.append(p) } else { places.append(p) }
        }
        places.sort { $0.usd != $1.usd ? $0.usd > $1.usd : $0.name < $1.name }
        subscriptions.sort { a, b in
            let l = a.lastAt ?? .distantPast, r = b.lastAt ?? .distantPast
            return l != r ? l > r : a.name < b.name
        }
        var recurring: Double = 0
        for p in subscriptions { recurring += p.usd }
        var rest: Double = 0
        for p in places { rest += p.usd }
        var earlierRecurring: Double = 0
        for (key, usd) in earlierByPlace where isRecurring(key) { earlierRecurring += max(0, usd) }
        return Reading(total: recurring + rest,
                       earlier: sawEarlier ? max(0, earlier) : nil,
                       places: places,
                       subscriptions: subscriptions,
                       recurring: recurring,
                       earlierRecurring: sawEarlier ? earlierRecurring : nil)
    }
}
