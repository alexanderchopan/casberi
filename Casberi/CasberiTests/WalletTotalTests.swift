import Foundation
import Testing
@testable import Casberi

/// **What the Wallet total adds up** (prd §1048): cash at a bank and Privy's
/// app wallets join the chains and exchanges, each as a PLACE.
///
/// `wallet-total-audit.py` holds the read's shape (Privy never alone, cash
/// only on the combined page). This holds the arithmetic it hands over: a
/// rate applied the right way up, a currency with no rate left out rather
/// than counted at par, and every new place kept off the address rail.
struct WalletTotalTests {

    @Test func dollarsCountAtPar() {
        #expect(WalletCash.usd(250, "USD", rates: [:]) == 250)
    }

    @Test func aQuotedCurrencyIsConverted() {
        let usd = WalletCash.usd(100, "EUR", rates: ["EUR": 1.12])
        #expect(abs((usd ?? 0) - 112) < 0.000_001)
    }

    /// The failure this exists for: counting 1,000 SGD as $1,000 is a number
    /// that looks right and isn't.
    @Test func aCurrencyWithNoRateIsLeftOut() {
        #expect(WalletCash.usd(1_000, "SGD", rates: ["EUR": 1.12]) == nil)
        #expect(WalletCash.usd(1_000, "EUR", rates: ["EUR": 0]) == nil)
    }

    /// Kraken lists only these six against USD (measured 2026-10-01), and one
    /// unknown pair fails the whole call, so the two sets must not overlap.
    @Test func theQuotedSetsAreDisjoint() {
        #expect(WalletCash.quotedOverUSD.isDisjoint(with: WalletCash.quotedUnderUSD))
        #expect(!WalletCash.quotedOverUSD.contains("USD"))
        #expect(!WalletCash.quotedUnderUSD.contains("USD"))
    }

    @Test func cashAndPrivyArePlacesNotAddresses() {
        #expect(WalletPortfolio.isVenue("cash:wise"))
        #expect(WalletPortfolio.isVenue("cash:applewallet:Apple Cash"))
        #expect(WalletPortfolio.isVenue("privy:zora"))
        #expect(!WalletPortfolio.isVenue("0x3f2a9b7c1d4e5f60718293a4b5c6d7e8f90191c4"))
    }

    @Test func venuesJoinTheTotalAndTheirPositions() {
        let portfolio = WalletPortfolio.from(
            groups: [],
            venues: [(symbol: "USD", usd: 7_612, holderID: "cash:wise", label: "Wise"),
                     (symbol: "ETH", usd: 400, holderID: "privy:zora", label: "Zora"),
                     (symbol: "USD", usd: 0, holderID: "cash:applewallet:Savings", label: "Savings")])
        #expect(portfolio.totalUSD == 8_012)
        #expect(portfolio.holders(forSymbol: "USD").map(\.label) == ["Wise"])
        #expect(Set(portfolio.venueTotals.map(\.label)) == ["Wise", "Zora"])
    }
}
