import Foundation
import Testing
@testable import Casberi

/// **A fake transfer is one somebody else sent** (2026-11-19, user: "i have
/// things listed as fake transfers but i did send them").
///
/// The rule had two halves, both about the token: you don't hold it, and
/// nobody prices it. Sending the last of an unpriced token passes both, so a
/// real send wore "You didn't send this". The third half is the fact the flag
/// claims: a receipt that says the wallet did not act in the transaction.
struct FakeTransferTests {

    private static let token = "0x6d2e1b9a4c7f30e85a1d9c42b7e6f03a18c5d9e4"
    private static let held: Set<String> = ["0x833589fcd6edb6e08f4c7c32d4f71b54bda02913"]

    private func fake(held: Set<String>? = FakeTransferTests.held, usd: Double? = nil,
                      priceWasRead: Bool = true, sentByWallet: Bool?) -> Bool {
        WalletSafety.isFakeOutboundTransfer(contract: Self.token, category: "erc20",
                                            held: held, pricedUSD: usd,
                                            priceWasRead: priceWasRead,
                                            sentByWallet: sentByWallet)
    }

    @Test func aSendOfYoursIsNeverFake() {
        // Unheld and unpriced, the old rule's whole case, and you sent it.
        #expect(!fake(sentByWallet: true))
    }

    @Test func anUnreadReceiptNeverFlags() {
        #expect(!fake(sentByWallet: nil))
    }

    @Test func aContractsClaimIsFake() {
        #expect(fake(sentByWallet: false))
    }

    @Test func somebodyElseSendingIsNotEnough() {
        // A Safe owner, a relayer: the token test still has to fail.
        #expect(!fake(usd: 12, sentByWallet: false))
        #expect(!fake(held: [Self.token], sentByWallet: false))
        #expect(!fake(held: nil, sentByWallet: false))
        #expect(!fake(priceWasRead: false, sentByWallet: false))
    }

    @Test func theFreeHalfMarksWhatIsWorthAReceipt() {
        #expect(WalletSafety.couldBeFakeOutbound(contract: Self.token, category: "erc20",
                                                 held: Self.held, pricedUSD: nil,
                                                 priceWasRead: true))
        #expect(!WalletSafety.couldBeFakeOutbound(contract: nil, category: "external",
                                                  held: Self.held, pricedUSD: nil,
                                                  priceWasRead: true))
    }

    @Test @MainActor func aFlagComesOffAlone() {
        let thing = Thing(kind: .link, title: "Sent 5 ABC", source: "Wallet")
        thing.addSecurityFlag("symbol")
        thing.addSecurityFlag("spam")
        thing.removeSecurityFlag("spam")
        #expect(thing.hasSecurityFlag("symbol"))
        #expect(!thing.hasSecurityFlag("spam"))
        thing.removeSecurityFlag("symbol")
        #expect(thing.securityFlag == nil)
    }
}
