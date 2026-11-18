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

    /// prd §1880: a dollar's home message is round-ups' own (§1574), drained
    /// to the address; the dollars are the account's networks' own.
    @Test func theDollarMessageIsRoundUpsOwn() throws {
        let router = try #require(FreshTx.homeRouter)
        let deposit = "0xc63148e8" + String(repeating: "ab", count: 300)
        let depositBytes = try #require(SafeABI.hexBytes(deposit))
        let roundUps = try #require(PrivateBridge.message(router: router, deposit: depositBytes, budget: "19900000", account: payee))
        let fresh = try #require(FreshTx.bridgeMessage(router: router, deposit: deposit, budget: "19900000", drainTo: payee))
        #expect(SafeABI.hex(roundUps).dropFirst(2).lowercased() == fresh)
        for origin in FreshTx.homeOrigins {
            let net = try #require(YourAccountOp.networks.first { $0.chainId == origin.chainId })
            #expect(net.dollar.lowercased() == origin.dollar)
            #expect(net.dollarSymbol == origin.dollarSymbol)
        }
        #expect(YourAccountOp.ethereum.dollar.lowercased() == FreshTx.homeUSDC)
    }
}
