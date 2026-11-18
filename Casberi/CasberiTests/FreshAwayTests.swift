import Foundation
import Testing
@testable import Casberi

/// **A private send to Base or Robinhood carries Swap's own message**
/// (prd §1879). `FreshTx.awayMessage` is hand-written so the pure harness
/// can compile it; a wrong answer is a fill that runs a message Across's
/// MulticallHandler reads differently from the one Swap's crossings carry,
/// which have landed for real.
@MainActor
struct FreshAwayTests {
    private let payee = "0xd30c41652e0330df0c8c1334ffd70e948a50ca8d"

    @Test func theMessageIsSwapsOwn() throws {
        for chain in [8453, 4663] {
            let swap = try #require(YourAccountAcross.message(to: chain, amount: "4968484188956779", account: payee))
            let fresh = try #require(FreshTx.awayMessage(to: chain, amount: "4968484188956779", payee: payee))
            #expect(SafeABI.hex(swap).dropFirst(2).lowercased() == fresh)
        }
    }

    @Test func theSpokeAndHandlerAreAcrosss() {
        #expect(FreshTx.awaySpoke == YourAccountAcross.spokes[1])
        #expect(FreshTx.awayHandler == YourAccountAcross.handler)
        for origin in FreshTx.homeOrigins {
            #expect(YourAccountAcross.spokes[origin.chainId] == origin.spoke)
            #expect(YourAccountSwap.book(origin.chainId)?.weth.lowercased() == origin.weth)
        }
        #expect(FreshTx.homeSelector == "0x" + SafeCalldata.selector(YourAccountAcross.depositSignature).dropFirst(2).lowercased())
    }
}
