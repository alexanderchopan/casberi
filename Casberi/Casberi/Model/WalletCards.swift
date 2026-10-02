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

    @MainActor
    private static func sighting(_ thing: Thing) -> CardSpendRoom.Sighting {
        CardSpendRoom.Sighting(amount: thing.priceValue,
                               currency: thing.priceCurrency,
                               at: thing.capturedAt)
    }
}
