import Foundation

/// THE WALLET'S CARDS TILE (prd §1048, step 2): every card's spends in one
/// list, under one figure. Gnosis Pay, MetaMask Card and ether.fi were three
/// rooms on one head (`CardSpendRoom`, §858); Apple Card and Privacy.com were
/// two more. The Wallet room's query carries these seats' rows, and this says
/// which of them are SPENDS.
///
/// The arithmetic is `CardSpendRoom`'s, unchanged, so its judgements carry
/// over: currencies are never summed, an unreadable amount is counted and
/// never zeroed, and a comparison is refused against a window the rows never
/// observed.
enum WalletCards {

    /// Privacy.com's `Thing.source`, as `PrivacyBridge` stamps it.
    static let privacySource = "Privacy"

    /// The card seats whose rows ride the Wallet room, in the order the
    /// figure names them when their counts tie.
    static let seats: [String] = [
        GnosisPayBridge.sourceName,
        MetaMaskCardBridge.source,
        EtherFiCash.source,
        AppleWalletBridge.sourceName,
        privacySource,
    ]

    /// Whether a row is a card spend. The three onchain cards go through
    /// `CardSpendSeat`, which already knows that ether.fi's room also holds
    /// unstake and credit-line rows (§868). Apple Wallet's room holds bank
    /// moves, dues, price creep and silences beside its card purchases, so
    /// only a `.transaction` tagged Card counts. A refund is not a spend.
    static func isSpend(_ thing: Thing) -> Bool {
        guard !isRefund(thing) else { return false }
        switch thing.source {
        case GnosisPayBridge.sourceName, MetaMaskCardBridge.source, EtherFiCash.source:
            return CardSpendSeat.isSpend(thing, seat: thing.source)
        case AppleWalletBridge.sourceName:
            return thing.kind == .transaction && thing.tags.contains("Card")
        case privacySource:
            return thing.kind == .transaction
                && (thing.sourceRef?.hasPrefix("privacy:txn:") ?? false)
        default:
            return false
        }
    }

    static func isRefund(_ thing: Thing) -> Bool {
        thing.tags.contains("Refund") || thing.transferDirection == "received"
    }

    /// One card's own spending, for the figure's per-card lines.
    struct Card: Equatable {
        let seat: String
        let room: CardSpendRoom
    }

    struct Reading: Equatable {
        /// Every card together: the figure's headline and its month strip.
        let all: CardSpendRoom
        /// Each card that spent in the window, most spends first.
        let cards: [Card]
    }

    @MainActor
    static func compose(things: [Thing], now: Date = .now) -> Reading? {
        let spends = things.live.filter(isSpend)
        guard !spends.isEmpty else { return nil }
        let all = CardSpendRoom.compose(spends: spends.map(sighting), now: now)
        guard !all.isEmpty else { return nil }
        let bySeat = Dictionary(grouping: spends, by: \.source)
        let cards = seats.compactMap { seat -> Card? in
            guard let rows = bySeat[seat] else { return nil }
            let room = CardSpendRoom.compose(spends: rows.map(sighting), now: now)
            guard (room.lead?.spends ?? 0) > 0 else { return nil }
            return Card(seat: seat, room: room)
        }
        // Stable on ties: `seats` order stands where the counts are equal.
        .enumerated()
        .sorted { ($0.element.room.lead?.spends ?? 0, -$0.offset) > ($1.element.room.lead?.spends ?? 0, -$1.offset) }
        .map(\.element)
        return Reading(all: all, cards: cards)
    }

    /// **THE WINDOW IN DOLLARS (prd §1078, reversing §1048a's "no rate
    /// between them").** The Wallet's total already turns cash into dollars
    /// at Kraken's mid price (`WalletCash`), so the Cards tile uses the same
    /// rate rather than stating "$972.12 in USD, plus another currency". Nil
    /// when any currency in the window has no rate: then the figure keeps
    /// `CardSpendRoom`'s own words, and nothing is counted at par.
    struct InDollars: Equatable {
        struct Card: Equatable {
            let seat: String
            let usd: Double
            let spends: Int
            /// The card's own money when it settled in one other currency
            /// ("€123.20"), so the converted figure never hides what was paid.
            let native: CardSpendRoom.Currency?
        }
        let total: Double
        /// Most dollars first; ties keep `seats` order.
        let cards: [Card]
        /// The non-dollar codes converted, with the rate used (USD per unit).
        let rates: [(code: String, rate: Double)]

        static func == (a: InDollars, b: InDollars) -> Bool {
            a.total == b.total && a.cards == b.cards
                && a.rates.map(\.code) == b.rates.map(\.code)
                && a.rates.map(\.rate) == b.rates.map(\.rate)
        }
    }

    /// Every non-dollar code spent in the window, for the rate request.
    static func codes(_ reading: Reading) -> Set<String> {
        Set(reading.all.currencies.map(\.code)).subtracting(["USD"])
    }

    static func inDollars(_ reading: Reading, rates: [String: Double]) -> InDollars? {
        func usd(_ room: CardSpendRoom) -> Double? {
            var sum = 0.0
            for currency in room.currencies {
                guard let value = WalletCash.usd(currency.total, currency.code, rates: rates) else { return nil }
                sum += value
            }
            return sum
        }
        guard let total = usd(reading.all) else { return nil }
        var cards: [InDollars.Card] = []
        for card in reading.cards {
            guard let value = usd(card.room) else { return nil }
            let native = card.room.currencies.count == 1 && card.room.lead?.code != "USD"
                ? card.room.lead : nil
            cards.append(.init(seat: card.seat, usd: value, spends: card.room.spends, native: native))
        }
        let ranked = cards.enumerated()
            .sorted { ($0.element.usd, -$0.offset) > ($1.element.usd, -$1.offset) }
            .map(\.element)
        let used = codes(reading).sorted().compactMap { code in rates[code].map { (code, $0) } }
        return InDollars(total: total, cards: ranked, rates: used)
    }

    @MainActor
    private static func sighting(_ thing: Thing) -> CardSpendRoom.Sighting {
        CardSpendRoom.Sighting(amount: thing.priceValue,
                               currency: thing.priceCurrency,
                               at: thing.capturedAt)
    }
}
