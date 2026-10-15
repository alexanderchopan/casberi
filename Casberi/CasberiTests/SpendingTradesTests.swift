import Foundation
import Testing
@testable import Casberi

/// **A trade is not spending** (`Spending.trades`, user 2026-10-15: "I may
/// have swapped $1000 in 10 different swaps, but I didn't spend $10,000").
///
/// Ingest folds a swap into one row only when both legs land in one pass on
/// one hash with two symbols, so the sell of a cross-chain swap, an intent
/// filled in a second transaction, or a same-symbol route stood as a plain
/// send and Spending counted it at full value, once per swap.
struct SpendingTradesTests {

    private static let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    private static func leg(_ id: Int, sent: Bool, usd: Double?, minutes: Double = 0,
                            tx: String? = nil, wallet: String = "0xa") -> Spending.Leg {
        Spending.Leg(id: id, wallet: wallet, tx: tx ?? "tx\(id)", sent: sent, usd: usd,
                     at: t0.addingTimeInterval(minutes * 60))
    }

    @Test func sameTransactionIsATrade() {
        let legs = [Self.leg(1, sent: true, usd: 1_000, tx: "h"),
                    Self.leg(2, sent: false, usd: nil, tx: "h")]
        #expect(Spending.trades(legs) == [1])
    }

    @Test func tenSwapsAcrossTransactionsAreTenTrades() {
        // Sell, then the buy two minutes later in its own transaction.
        let legs = (0..<10).flatMap { n -> [Spending.Leg] in
            [Self.leg(n * 2, sent: true, usd: 1_000, minutes: Double(n) * 60),
             Self.leg(n * 2 + 1, sent: false, usd: 990, minutes: Double(n) * 60 + 2)]
        }
        #expect(Spending.trades(legs) == Set((0..<10).map { $0 * 2 }))
    }

    @Test func aSendWithNothingBackIsSpending() {
        #expect(Spending.trades([Self.leg(1, sent: true, usd: 1_000)]).isEmpty)
    }

    @Test func aReceiptOutsideTheWindowOrBandDoesNotCancel() {
        let late = [Self.leg(1, sent: true, usd: 1_000),
                    Self.leg(2, sent: false, usd: 1_000, minutes: 31)]
        let small = [Self.leg(1, sent: true, usd: 1_000),
                     Self.leg(2, sent: false, usd: 500, minutes: 1)]
        #expect(Spending.trades(late).isEmpty)
        #expect(Spending.trades(small).isEmpty)
    }

    @Test func anotherWalletsReceiptDoesNotCancel() {
        let legs = [Self.leg(1, sent: true, usd: 1_000, wallet: "0xa"),
                    Self.leg(2, sent: false, usd: 1_000, minutes: 1, wallet: "0xb")]
        #expect(Spending.trades(legs).isEmpty)
    }

    @Test func oneReceiptCancelsOneSend() {
        let legs = [Self.leg(1, sent: true, usd: 1_000),
                    Self.leg(2, sent: true, usd: 1_000, minutes: 1),
                    Self.leg(3, sent: false, usd: 1_000, minutes: 2)]
        #expect(Spending.trades(legs).count == 1)
    }

    @Test func aSameTransactionBuyIsNotReusedForAnotherSend() {
        let legs = [Self.leg(1, sent: true, usd: 1_000, tx: "h"),
                    Self.leg(2, sent: false, usd: 1_000, tx: "h"),
                    Self.leg(3, sent: true, usd: 1_000, minutes: 1)]
        #expect(Spending.trades(legs) == [1])
    }
}
