import Foundation
import Testing
@testable import Casberi

/// **Which category a biller files under in Addresses** (prd §1106a).
///
/// The catalogue's category when the merchant is an app there, else Wallet.
/// A wrong answer renders as an ordinary filter: Claude's plan under Wallet
/// instead of Agents, or a store filed under an app it only resembles.
struct BillersCategoryTests {

    private static func category(ofOffer name: String) -> String? {
        BridgeCatalog.allOffers.first { $0.name == name }.map(BridgeCatalog.category(of:))
    }

    @Test func aCatalogueAppFilesUnderItsCategory() throws {
        let agents = try #require(BridgeCatalog.agentsCategory)
        #expect(BillersSource.category(ofMerchant: "Claude") == agents)
        #expect(BillersSource.category(ofMerchant: "Linear") == Self.category(ofOffer: "Linear"))
    }

    @Test func aCardsCasingAndWebSuffixStillMatch() throws {
        let agents = try #require(BridgeCatalog.agentsCategory)
        #expect(BillersSource.category(ofMerchant: "CLAUDE.AI") == agents)
        #expect(BillersSource.category(ofMerchant: "  claude ") == agents)
    }

    @Test func anUnknownMerchantIsWallet() {
        #expect(BillersSource.category(ofMerchant: "Netflix.com") == "Wallet")
        #expect(BillersSource.category(ofMerchant: "PG&E") == "Wallet")
    }

    @Test func aMerchantThatOnlyResemblesAnAppIsNotFiledThere() {
        // "Apple Store" is not Apple Music, Apple Wallet or Apple Health.
        #expect(BillersSource.category(ofMerchant: "Apple Store") == "Wallet")
        #expect(BillersSource.category(ofMerchant: "Claude Shannon Cafe") == "Wallet")
    }
}
