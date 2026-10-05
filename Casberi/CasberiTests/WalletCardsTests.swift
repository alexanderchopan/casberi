import Foundation
import SwiftData
import Testing
@testable import Casberi

/// **Which of the Wallet's card rows are spends** (prd §1048, step 2).
///
/// Five seats, three shapes of room. The onchain cards defer to
/// `CardSpendSeat` (§868); Apple Wallet's room also holds bank moves, dues,
/// price creep and silences; a refund on any of them is money back, not a
/// spend. Each wrong answer here renders as an ordinary total.
@MainActor
struct WalletCardsTests {

    private static func row(_ kind: ThingKind = .transaction, source: String, ref: String?,
                            tags: [String] = [], amount: Double? = 10, currency: String? = "USD",
                            daysAgo: Double = 1) -> Thing {
        let thing = Thing(kind: kind, title: "t", content: "c", source: source,
                          capturedAt: Date().addingTimeInterval(-daysAgo * 86_400), sourceRef: ref)
        thing.tags = tags
        thing.priceValue = amount
        thing.priceCurrency = currency
        return thing
    }

    @Test func anAppleCardPurchaseIsASpend() {
        #expect(WalletCards.isSpend(Self.row(source: AppleWalletBridge.sourceName, ref: "a",
                                             tags: ["Card"])))
    }

    /// Apple Cash and bank moves land in the same room, tagged Bank.
    @Test func aBankMoveIsNotASpend() {
        #expect(!WalletCards.isSpend(Self.row(source: AppleWalletBridge.sourceName, ref: "a",
                                              tags: ["Bank"])))
    }

    @Test func aRefundIsNotASpend() {
        #expect(!WalletCards.isSpend(Self.row(source: AppleWalletBridge.sourceName, ref: "a",
                                              tags: ["Card", "Refund"])))
    }

    /// A statement due date is a reminder in that room, and belongs in
    /// Coming up, not in what the cards spent.
    @Test func anAppleWalletDueIsNotASpend() {
        #expect(!WalletCards.isSpend(Self.row(.reminder, source: AppleWalletBridge.sourceName,
                                              ref: "due", tags: ["Card"])))
    }

    @Test func etherFiDefersToTheSharedSeatRule() {
        #expect(WalletCards.isSpend(Self.row(source: EtherFiCash.source,
                                             ref: EtherFiCash.spendRefPrefix + "0xabc:3")))
        #expect(!WalletCards.isSpend(Self.row(source: EtherFiCash.source,
                                              ref: "etherfi:unstake:0xabc")))
    }

    @Test func aPrivacyTransactionIsASpend() {
        #expect(WalletCards.isSpend(Self.row(source: WalletCards.privacySource,
                                             ref: "privacy:txn:abc")))
    }

    /// The Wallet's own transfers ride the same query and are never spends.
    @Test func aWalletTransferIsNotASpend() {
        #expect(!WalletCards.isSpend(Self.row(source: CategoryFold.walletRoom, ref: "w")))
    }

    @Test func onlyTheWalletCarriesTheCardSeats() {
        #expect(RoomAccounts.rides(room: CategoryFold.walletRoom, source: GnosisPayBridge.sourceName))
        #expect(!RoomAccounts.rides(room: "Markets", source: GnosisPayBridge.sourceName))
        #expect(RoomAccounts.roomSources("Markets") == ["Markets"])
        #expect(RoomAccounts.roomSources(CategoryFold.walletRoom).first == CategoryFold.walletRoom)
    }
}
