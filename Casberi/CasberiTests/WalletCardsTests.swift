import Foundation
import SwiftData
import Testing
@testable import Casberi

/// **Which rows the Wallet's Cards tile counts** (prd §1048, step 2).
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

    /// `isLive` needs a context, so a test on bare `Thing()`s would hand
    /// `compose` nothing and pass while proving nothing (`CardSpendSeatTests`'
    /// own lesson). Held by the caller: a released container deletes its rows.
    private static func inserted(_ rows: [Thing]) throws -> (ModelContainer, [Thing]) {
        let container = try ModelContainer(
            for: Thing.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        for row in rows { container.mainContext.insert(row) }
        return (container, rows)
    }

    /// Euros and dollars stay apart, and the busiest card leads by COUNT.
    @Test func cardsRankBySpendsAndCurrenciesAreNotSummed() throws {
        let (container, rows) = try Self.inserted([
            Self.row(source: GnosisPayBridge.sourceName, ref: "g1", amount: 40, currency: "EUR"),
            Self.row(source: AppleWalletBridge.sourceName, ref: "a1", tags: ["Card"], amount: 5),
            Self.row(source: AppleWalletBridge.sourceName, ref: "a2", tags: ["Card"], amount: 7),
        ])
        _ = container
        let reading = WalletCards.compose(things: rows)
        #expect(reading?.cards.map(\.seat) == [AppleWalletBridge.sourceName, GnosisPayBridge.sourceName])
        #expect(Set(reading?.all.currencies.map(\.code) ?? []) == ["USD", "EUR"])
        #expect(reading?.all.currencies.first(where: { $0.code == "USD" })?.total == 12)
    }

    /// Inserted, so a nil here means "no spends", not "no live rows".
    @Test func noSpendsIsNoReading() throws {
        let (container, rows) = try Self.inserted([Self.row(source: CategoryFold.walletRoom, ref: "w")])
        _ = container
        #expect(rows.allSatisfy { $0.isLive })
        #expect(WalletCards.compose(things: rows) == nil)
    }
}
