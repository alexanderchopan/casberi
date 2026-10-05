import Foundation
import SwiftData
import Testing
@testable import Casberi

/// **The One Wallet's five improvements** (prd §1078): own moves as one row,
/// Coming up's figure, and the Cards tile in dollars. Each wrong answer here
/// draws as an ordinary, confident number.
@MainActor
struct WalletImprovementsTests {

    // MARK: - Own moves

    private static let now = Date(timeIntervalSince1970: 1_800_000_000)
    private static let everyday = "0xAAA0000000000000000000000000000000000001"
    private static let savings = "0xbbb0000000000000000000000000000000000002"

    private static func leg(_ sent: Bool, address: String?, counterparty: String?,
                            amount: String? = "0.5 ETH", link: String? = nil,
                            minutes: Double = 0) -> WalletOwnMoves.Leg {
        .init(id: UUID(), sent: sent, address: address, counterparty: counterparty,
              amount: amount, link: link, at: now.addingTimeInterval(minutes * 60))
    }

    @Test func aMoveBetweenYourAccountsPairs() {
        let out = Self.leg(true, address: Self.everyday, counterparty: Self.savings.lowercased())
        let into = Self.leg(false, address: Self.savings, counterparty: Self.everyday.lowercased(), minutes: 3)
        #expect(WalletOwnMoves.pairs([out, into]) == [.init(sent: out.id, received: into.id)])
    }

    /// The same link is the same transaction, whatever else the legs say.
    @Test func aSharedLinkPairs() {
        let out = Self.leg(true, address: "0x1", counterparty: nil, amount: "ETH", link: "https://basescan.org/tx/0xf")
        let into = Self.leg(false, address: "0x2", counterparty: nil, amount: nil, link: "https://basescan.org/tx/0xf",
                            minutes: 600)
        #expect(WalletOwnMoves.pairs([out, into]).count == 1)
    }

    /// A payment to a stranger and an unrelated receipt of the same size are
    /// two things that happened.
    @Test func aDifferentAddressNeverPairs() {
        let out = Self.leg(true, address: Self.everyday, counterparty: "0xstranger")
        let into = Self.leg(false, address: Self.savings, counterparty: "0xsomeoneelse")
        #expect(WalletOwnMoves.pairs([out, into]).isEmpty)
    }

    @Test func aDifferentAmountNeverPairs() {
        let out = Self.leg(true, address: Self.everyday, counterparty: Self.savings)
        let into = Self.leg(false, address: Self.savings, counterparty: Self.everyday, amount: "0.4 ETH")
        #expect(WalletOwnMoves.pairs([out, into]).isEmpty)
    }

    @Test func legsHoursApartNeverPair() {
        let out = Self.leg(true, address: Self.everyday, counterparty: Self.savings)
        let into = Self.leg(false, address: Self.savings, counterparty: Self.everyday, minutes: 60 * 5)
        #expect(WalletOwnMoves.pairs([out, into]).isEmpty)
    }

    /// "ETH" alone, or zeros, says nothing about two legs being one move.
    @Test func anAmountWithNoFigureNeverPairs() {
        let out = Self.leg(true, address: Self.everyday, counterparty: Self.savings, amount: "0.0000 ETH")
        let into = Self.leg(false, address: Self.savings, counterparty: Self.everyday, amount: "0.0000 ETH")
        #expect(WalletOwnMoves.pairs([out, into]).isEmpty)
    }

    /// The received leg names its sender: it must be the account the sent
    /// leg left.
    @Test func aReceiptFromSomeoneElseNeverPairs() {
        let out = Self.leg(true, address: Self.everyday, counterparty: Self.savings)
        let into = Self.leg(false, address: Self.savings, counterparty: "0xsomeoneelse")
        #expect(WalletOwnMoves.pairs([out, into]).isEmpty)
    }

    /// Two identical moves pair one to one, each with its nearest leg.
    @Test func eachLegPairsOnceWithTheNearest() {
        let out1 = Self.leg(true, address: Self.everyday, counterparty: Self.savings, minutes: 0)
        let out2 = Self.leg(true, address: Self.everyday, counterparty: Self.savings, minutes: 60)
        let in1 = Self.leg(false, address: Self.savings, counterparty: Self.everyday, minutes: 2)
        let in2 = Self.leg(false, address: Self.savings, counterparty: Self.everyday, minutes: 62)
        let pairs = WalletOwnMoves.pairs([out1, out2, in1, in2])
        #expect(Set(pairs.map(\.sent)) == [out1.id, out2.id])
        #expect(pairs.contains(.init(sent: out1.id, received: in1.id)))
        #expect(pairs.contains(.init(sent: out2.id, received: in2.id)))
    }

    // MARK: - Coming up

    private static func bill(_ source: String, _ amount: Double?, _ currency: String? = "USD",
                             days: Double, title: String = "Bill") -> WalletDue.Bill {
        .init(title: title, source: source, amount: amount, currency: currency,
              due: now.addingTimeInterval(days * 86_400))
    }

    @Test func billsInsideTheWindowAddUp() {
        let reading = WalletDue.compose(bills: [
            Self.bill(AppleWalletBridge.sourceName, 15.49, days: 2),
            Self.bill(AppleWalletBridge.sourceName, 240, days: 20),
            Self.bill(AppleWalletBridge.sourceName, 99, days: 45),
        ], waiting: 0, rates: [:], now: Self.now)
        #expect(abs(reading.total - 255.49) < 0.001)
        #expect(reading.counted == 2)
    }

    /// Coming up also holds money ARRIVING and deadlines with no money; only
    /// a bill's source counts. Rocket Money's bills repeat, so they are
    /// Subscriptions' since prd §1105 and Coming up's box does not add them.
    @Test func onlyABillSourceCounts() {
        let reading = WalletDue.compose(bills: [Self.bill("Peer", 500, days: 1),
                                                Self.bill("World App", 40, days: 3),
                                                Self.bill(RocketMoneyLive.source, 20, days: 3)],
                                        waiting: 0, rates: [:], now: Self.now)
        #expect(!reading.hasFigure)
        #expect(reading.uncounted.isEmpty)
    }

    /// Apple's payment row carries a date, not a sum: named, never zero.
    @Test func aBillWithNoAmountIsNamedNotCounted() {
        let reading = WalletDue.compose(bills: [
            Self.bill(AppleWalletBridge.sourceName, nil, nil, days: 9, title: "Apple Card payment due"),
            Self.bill(AppleWalletBridge.sourceName, 20, days: 4),
        ], waiting: 2, rates: [:], now: Self.now)
        #expect(reading.total == 20)
        #expect(reading.uncounted == ["Apple Card payment due"])
        #expect(WalletDue.waitingLine(reading.waiting) != nil)
    }

    @Test func aBillInAnUnpricedCurrencyIsNamed() {
        let reading = WalletDue.compose(bills: [Self.bill(AppleWalletBridge.sourceName, 30, "SGD", days: 4, title: "Gym")],
                                        waiting: 0, rates: ["EUR": 1.1], now: Self.now)
        #expect(reading.counted == 0)
        #expect(reading.uncounted == ["Gym"])
    }
}
