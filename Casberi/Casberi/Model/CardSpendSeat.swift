import Foundation
import SwiftData

/// WHICH ROWS IN AN ONCHAIN CARD'S ROOM ARE SPENDS (2026-09-21, prd §868).
///
/// Three seats read a card that settles on a public chain — Gnosis Pay, MetaMask
/// Card, ether.fi Cash — and all three draw one head (`CardSpendRoom`, prd
/// §858). That head sums money, counts what it could not price, and refuses a
/// comparison it has not observed. Every one of those judgements is only as
/// honest as the set of rows handed to it, so the set is decided HERE, once,
/// and read by the head's three sources AND by the door `FeedScreen` opens
/// under it.
///
/// **It exists because ether.fi's room is SHARED and its siblings' are not.**
/// `EtherFiCash.source` is the whole seat — "ether.fi — Your staked ETH, and
/// the card" — so the same room holds card spends, credit-line risk crossings
/// and `EtherFiUnstake`'s withdrawal-queue rows. Filtering that room by source
/// alone, which is exactly right for the other two, hands the head a stack of
/// rows that are not purchases and carry no `priceValue`: they would land in
/// `allTime`, inflate "N spends before that", and be counted by the footnote as
/// "3 spends have no readable amount" — a sentence about money, on the screen
/// where money is the subject, describing rows that are not spends at all. It
/// compiles, it renders, and every number in it is wrong (§83).
///
/// **One rule, not two.** The head's filter and the door's lookup are the same
/// question asked twice, and the door was previously correct only by accident:
/// it matched on `priceCurrency`, which no unstake row happens to carry. A
/// coincidence is not a rule, and the day an ether.fi row lands with a currency
/// and is not a purchase, the head would decline it and the door would open it.
enum CardSpendSeat {

    /// Is this row one of `seat`'s card SPENDS?
    ///
    /// The source test comes first for every seat, so no rule below can reach
    /// across rooms. Then: for a room that holds nothing but the card, every
    /// row is a spend and there is nothing further to ask — that is the answer
    /// for Gnosis Pay and MetaMask Card, and it is stated rather than assumed.
    /// ether.fi's room is shared, so its spends are named by the namespace the
    /// bridge has always written them under.
    static func isSpend(_ thing: Thing, seat: String) -> Bool {
        guard thing.source == seat else { return false }
        guard seat == EtherFiCash.source else { return true }
        guard let ref = thing.sourceRef else { return false }
        return ref.hasPrefix(EtherFiCash.spendRefPrefix)
    }
}
