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
        /// Whose it is (prd §1524): the `Thing.source` its row landed under,
        /// and the wallet, lowercased, for a send or a card read off one.
        /// Nil for a plan tracked by hand, which is no account's.
        var app: String? = nil
        var wallet: String? = nil
    }

    /// **WHOSE SPENDING THE TILE READS (prd §1524).** All is every account's,
    /// added up; an account picked in the search tray is that account's
    /// alone: a wallet's sends and the cards read off it, or an app's rows.
    enum Scope: Equatable {
        case all
        /// A wallet, in every spelling it is followed by, lowercased.
        case wallet(Set<String>)
        /// An app: the `Thing.source`s its rows land under.
        case app(Set<String>)

        /// Whether a charge, a fee or a buy of `app` or `wallet` is this
        /// scope's. A plan tracked by hand (no app, no wallet) is All's only.
        func holds(app: String?, wallet: String?) -> Bool {
            switch self {
            case .all: return true
            case .wallet(let forms): return wallet.map { forms.contains($0.lowercased()) } ?? false
            case .app(let sources): return app.map { sources.contains($0) } ?? false
            }
        }
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
        /// **FEES (prd §1476):** gas, one row per network, largest first,
        /// each against the last window as a place is; their sum; last
        /// window's sum; and, when a send in this window carries no fee
        /// (landed before the fact was kept), the day the fees start from,
        /// so the row says so instead of counting low in silence (§83).
        /// Never part of `total`: a fee is not a place you spent at.
        var fees: [Place] = []
        var feesTotal: Double = 0
        var earlierFees: Double? = nil
        var feesFrom: Date? = nil
        /// **ROUND-UPS (prd §1523):** each buy this window, newest first;
        /// their sum; last window's sum; the change still waiting to buy
        /// (the caller's, never read off a row); and, when this window holds
        /// the first buy ever marked, its day, because buys before the mark
        /// was kept are not counted (§83). Never part of `total`.
        var roundUps: [RoundUp] = []
        var roundUpsTotal: Double = 0
        var earlierRoundUps: Double? = nil
        var roundUpsWaiting: Double = 0
        var roundUpsFrom: Date? = nil

        /// **THE RUNNING LINE (prd §1480 item 14):** what the window had
        /// spent by the end of each day, from its first day through today,
        /// so the last point is `total`. A place whose refunds cancelled it
        /// is left out here as it is from `total`.
        var running: [Double] = []

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
        /// What its transaction cost in gas, in USD, and on which network
        /// (prd §1476): the `.fee` fact a sent leg carries; nil on a row
        /// landed before the fact was kept, or one the read did not price.
        var feeUSD: Double? = nil
        var network: String? = nil
        /// What a round-up bought with this send (prd §1523): the `.roundUp`
        /// fact a sent leg to one of Relay's deposit addresses carries, or
        /// the dollar leg of a buy on the exchanges (§1545). On a received
        /// leg, the token that exchange buy brought back in its own
        /// transaction: never a payment back.
        var roundUp: RoundUp.Bought? = nil

        enum Way: Equatable { case sent, received, swap }
    }

    /// **ONE ROUND-UP'S BUY (prd §1523):** the dollars a send's change
    /// reached, paid to Relay for the token picked, and when.
    struct RoundUp: Equatable {
        struct Bought: Equatable {
            var symbol: String
            var network: String
        }
        var tx: String
        var usd: Double
        var at: Date
        var bought: Bought
        /// The wallet that paid it, lowercased (prd §1524).
        var wallet: String? = nil
    }

    /// **ROUND-UPS (prd §1523): what the change bought**, one per
    /// transaction, from a wallet you follow, priced. Kept apart from
    /// spending: the change was not spent, it became a token you hold.
    static func walletRoundUps(_ moves: [Move], own: Set<String>) -> [RoundUp] {
        var counted = Set<String>()
        var out: [RoundUp] = []
        for m in moves where m.way == .sent && own.contains(m.wallet) {
            guard let bought = m.roundUp, let usd = m.usd, usd.isFinite, usd > 0,
                  !counted.contains(m.tx) else { continue }
            counted.insert(m.tx)
            out.append(RoundUp(tx: m.tx, usd: usd, at: m.at, bought: bought, wallet: m.wallet))
        }
        return out
    }

    /// One transaction's gas (prd §1476): the fee a wallet of yours paid,
    /// once however many legs the transaction landed as.
    struct Fee: Equatable {
        var tx: String
        var network: String
        var usd: Double
        var at: Date
        /// The wallet that paid it, lowercased (prd §1524).
        var wallet: String? = nil
    }

    /// **FEES (prd §1476): gas on every transaction a wallet you follow
    /// sent**, one per transaction. Not only spending: a swap, a deposit and
    /// a move between your own wallets all paid gas, and the fee is the one
    /// part of them that left for good. A fee on a wallet you no longer
    /// follow is not yours (§1330). The first leg of a transaction that
    /// carries a fee speaks for it.
    static func walletFees(_ moves: [Move], own: Set<String>) -> [Fee] {
        var seen = Set<String>()
        var out: [Fee] = []
        for m in moves where own.contains(m.wallet) {
            guard let usd = m.feeUSD, usd.isFinite, usd > 0, let network = m.network,
                  !seen.contains(m.tx) else { continue }
            seen.insert(m.tx)
            out.append(Fee(tx: m.tx, network: network, usd: usd, at: m.at, wallet: m.wallet))
        }
        return out
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
    /// - **a round-up's buy** (prd §1523): the change, paid to Relay or
    ///   swapped on the exchanges (§1545) for a token you picked, is kept,
    ///   not spent. An exchange buy rides the send it rounded up, so its
    ///   token arrives in that same transaction: that arrival pays nothing
    ///   back, answers no send, and the read's "trade" for the transaction
    ///   is the buy's, not the send's;
    /// - **a round trip**: money worth the same (within
    ///   `roundTripTolerance`) arriving at one of your wallets within
    ///   `roundTripWindow`, in a transaction of its own — a cross-chain swap
    ///   or a bridge. Each arrival answers one send at most.
    static func walletSpends(_ moves: [Move], own: Set<String>) -> [Move] {
        // Transactions whose round-up was bought on the exchanges (prd §1545):
        // the token it bought came back in the same transaction.
        let boughtHere = Set(moves.filter { $0.way == .received && $0.roundUp != nil }.map(\.tx))
        // Transactions that paid one of your wallets something, a round-up's
        // own token aside.
        let paidBack = Set(moves.filter { $0.way != .sent && $0.roundUp == nil }.map(\.tx))
        // Money that arrived from outside your own wallets, priced.
        var arrivals: [Move] = moves.filter { m in
            guard m.way == .received, m.roundUp == nil, own.contains(m.wallet),
                  let usd = m.usd, usd.isFinite, usd > 0 else { return false }
            return !(m.counterparty.map(own.contains) ?? false)
        }
        // The nearest arrival that answers a send worth `usd`.
        func nearest(to send: Move, usd: Double) -> Int? {
            let answers = arrivals.indices.filter { i in
                let a = arrivals[i]
                guard a.tx != send.tx, let back = a.usd else { return false }
                let lag = a.at.timeIntervalSince(send.at)
                return lag >= -roundTripSkew && lag <= roundTripWindow
                    && abs(back - usd) <= usd * roundTripTolerance
            }
            return answers.min(by: { abs(arrivals[$0].at.timeIntervalSince(send.at))
                                     < abs(arrivals[$1].at.timeIntervalSince(send.at)) })
        }
        // A round-up's buy (prd §1523) takes the token Relay sends back
        // first, so that fill answers no send of yours: the buy rides the
        // same operation as a send, and a $5 send would read as a round trip.
        // An exchange buy's token came back in its own transaction, so it
        // takes nothing.
        for buy in moves where buy.way == .sent && buy.roundUp != nil && own.contains(buy.wallet)
            && !boughtHere.contains(buy.tx) {
            guard let usd = buy.usd, usd.isFinite, usd > 0,
                  let taken = nearest(to: buy, usd: usd) else { continue }
            arrivals.remove(at: taken)
        }
        var out: [Move] = []
        for send in moves.filter({ $0.way == .sent }).sorted(by: { $0.at < $1.at }) {
            guard own.contains(send.wallet) else { continue }
            guard let usd = send.usd, usd.isFinite, usd > 0, send.place != nil else { continue }
            if let to = send.counterparty, own.contains(to) { continue }
            if send.machinery { continue }
            if send.roundUp != nil { continue }
            if paidBack.contains(send.tx) { continue }
            if let op = send.operation, op != "send", !boughtHere.contains(send.tx) { continue }
            // The nearest arrival that answers it, taken so it answers no other.
            if let i = nearest(to: send, usd: usd) {
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
                     isRecurring: (String) -> Bool = { _ in false },
                     fees: [Fee] = [], unpricedSends: [Date] = [],
                     roundUps: [RoundUp] = [], roundUpsWaiting: Double = 0) -> Reading {
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
        var reading = Reading(total: recurring + rest,
                              earlier: sawEarlier ? max(0, earlier) : nil,
                              places: places,
                              subscriptions: subscriptions,
                              recurring: recurring,
                              earlierRecurring: sawEarlier ? earlierRecurring : nil)
        // The running line: each counted place's charges, by day.
        let counted = Set(byPlace.filter { $0.value.usd >= 0.005 }.keys)
        let firstDay = calendar.startOfDay(for: start)
        let dayCount = (calendar.dateComponents([.day], from: firstDay,
                                                to: calendar.startOfDay(for: now)).day ?? 0) + 1
        var perDay = [Double](repeating: 0, count: max(1, dayCount))
        for charge in charges where charge.at >= start && charge.at <= now
            && counted.contains(charge.place.lowercased()) {
            let i = calendar.dateComponents([.day], from: firstDay,
                                            to: calendar.startOfDay(for: charge.at)).day ?? 0
            perDay[min(max(0, i), perDay.count - 1)] += charge.usd
        }
        var sum: Double = 0
        reading.running = perDay.map { sum += $0; return sum }
        // Fees (prd §1476): by network, this window and the last.
        var byNetwork: [String: Place] = [:]
        var earlierByNetwork: [String: Double] = [:]
        var feesTotal: Double = 0, earlierFees: Double = 0
        var sawEarlierFee = false, firstFee: Date?
        for fee in fees {
            if fee.at >= start && fee.at <= now {
                var row = byNetwork[fee.network] ?? Place(name: fee.network, usd: 0, count: 0)
                row.usd += fee.usd
                row.count += 1
                if fee.at > (row.lastAt ?? .distantPast) { row.lastAt = fee.at }
                byNetwork[fee.network] = row
                feesTotal += fee.usd
                if firstFee.map({ fee.at < $0 }) ?? true { firstFee = fee.at }
            } else if fee.at >= lastStart && fee.at <= lastEnd {
                earlierByNetwork[fee.network, default: 0] += fee.usd
                earlierFees += fee.usd
                sawEarlierFee = true
            }
        }
        reading.fees = byNetwork.values.map { row in
            var r = row
            r.earlier = earlierByNetwork[row.name]
            return r
        }.sorted { $0.usd != $1.usd ? $0.usd > $1.usd : $0.name < $1.name }
        reading.feesTotal = feesTotal
        reading.earlierFees = sawEarlierFee ? earlierFees : nil
        if let firstFee, unpricedSends.contains(where: { $0 >= start && $0 <= now && $0 < firstFee }) {
            reading.feesFrom = firstFee
        }
        // Round-ups (prd §1523): this window's buys, and the last's sum.
        var earlierRoundUps: Double = 0, sawEarlierRoundUp = false
        for buy in roundUps {
            if buy.at >= start && buy.at <= now {
                reading.roundUps.append(buy)
                reading.roundUpsTotal += buy.usd
            } else if buy.at >= lastStart && buy.at <= lastEnd {
                earlierRoundUps += buy.usd
                sawEarlierRoundUp = true
            }
        }
        reading.roundUps.sort { $0.at > $1.at }
        reading.earlierRoundUps = sawEarlierRoundUp ? earlierRoundUps : nil
        reading.roundUpsWaiting = roundUpsWaiting.isFinite ? max(0, roundUpsWaiting) : 0
        if let first = roundUps.map(\.at).min(), first >= start, first <= now {
            reading.roundUpsFrom = first
        }
        return reading
    }
}
