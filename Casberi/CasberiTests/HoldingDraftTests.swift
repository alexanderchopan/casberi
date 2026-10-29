import Foundation
import Testing
@testable import Casberi

/// **Send or Swap from a holding's long press** (prd §1609).
///
/// Offered only for your own account's tokens, opened on the network you
/// hold the most of them on, the token matched by `Tokens.Held.id`. A wrong
/// answer offers a Send Move cannot make (a watched wallet's token), or opens
/// Move on a network you hold none of the token on.
struct HoldingDraftTests {
    private let mine = "0xAbC0000000000000000000000000000000000001"
    private let theirs = "0x0000000000000000000000000000000000000002"
    private let usdcBase = "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913"
    private let usdcEth = "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"

    private func part(_ network: String, _ contract: String?, _ holder: String, _ usd: Double) -> WalletPortfolio.Part {
        WalletPortfolio.Part(key: HiddenTokens.contractKey(network: network, contract: contract), holder: holder, usd: usd)
    }

    @Test func aTokenYouHoldOpensWhereYouHoldMost() throws {
        let parts = [part("eth-mainnet", usdcEth, mine, 40), part("base-mainnet", usdcBase, mine, 900),
                     part("base-mainnet", usdcBase, theirs, 5_000)]
        let d = try #require(MoveSentence.holdingDraft(.send, symbol: "USDC", parts: parts, account: mine.lowercased()))
        #expect(d.verb == .send)
        #expect(d.network.chainId == 8453)
        #expect(d.networkPicked)
        #expect(d.withID == usdcBase)
        #expect(d.amount.isEmpty && d.to.isEmpty)
    }

    @Test func theCoinIsMatchedBySymbol() throws {
        let d = try #require(MoveSentence.holdingDraft(.swap, symbol: "ETH", parts: [part("base-mainnet", nil, mine, 10)], account: mine))
        #expect(d.verb == .swap)
        #expect(d.withID == "ETH")
    }

    @Test func anotherWalletsTokenOffersNothing() {
        #expect(MoveSentence.holdingDraft(.send, symbol: "USDC", parts: [part("base-mainnet", usdcBase, theirs, 5_000)], account: mine) == nil)
        #expect(MoveSentence.holdingDraft(.send, symbol: "USDC", parts: [part("base-mainnet", usdcBase, mine, 1)], account: nil) == nil)
    }

    @Test func aNetworkMoveDoesNotSignOnOffersNothing() {
        #expect(MoveSentence.holdingDraft(.send, symbol: "USDC", parts: [part("arb-mainnet", usdcBase, mine, 50)], account: mine) == nil)
        #expect(MoveSentence.holdingDraft(.send, symbol: "ETH", parts: [part("base-sepolia", nil, mine, 50)], account: mine) == nil)
    }

    @Test func onlySendAndSwap() {
        #expect(MoveSentence.holdingDraft(.receive, symbol: "USDC", parts: [part("base-mainnet", usdcBase, mine, 50)], account: mine) == nil)
    }
}
