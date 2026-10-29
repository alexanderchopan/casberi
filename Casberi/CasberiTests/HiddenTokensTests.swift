import Foundation
import Testing
@testable import Casberi

/// **Hiding one contract, not a name** (prd §1591): a spam token wearing a
/// real symbol sums into the real one's row, so a hide must take that one
/// contract off the row, the wallet that held it and the total, and leave
/// the real money standing.
struct HiddenTokensTests {

    static let real = HiddenTokens.contractKey(network: "eth-mainnet", contract: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48")
    static let fake = HiddenTokens.contractKey(network: "base-mainnet", contract: "0xdeadbeef00000000000000000000000000000e07a")

    /// Two wallets: one holds real USDC, the other a fake USDC and ETH.
    static var portfolio: WalletPortfolio {
        var a = WalletIngest.HoldingsGroup(label: "A", address: "0xaaa", cells: [], totalUSD: 900, tokenCount: 1)
        a.bySymbolAll = ["USDC": 900]
        a.routeBySymbol = ["USDC": "ethereum:0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"]
        a.partsBySymbol = ["USDC": [real: 900]]
        var b = WalletIngest.HoldingsGroup(label: "B", address: "0xbbb", cells: [], totalUSD: 1_600, tokenCount: 2)
        b.bySymbolAll = ["USDC": 1_000, "ETH": 600]
        b.routeBySymbol = ["USDC": "base:0xdeadbeef00000000000000000000000000000e07a"]
        b.partsBySymbol = ["USDC": [fake: 1_000], "ETH": [HiddenTokens.contractKey(network: "eth-mainnet", contract: nil): 600]]
        return WalletPortfolio.from(groups: [a, b])
    }

    @Test func theKeyIsTheNetworkAndContractLowercased() {
        #expect(HiddenTokens.contractKey(network: "Base-Mainnet", contract: "0xABC") == "base-mainnet:0xabc")
        #expect(HiddenTokens.contractKey(network: "eth-mainnet", contract: nil) == "eth-mainnet:native")
    }

    @Test func theMergeKeepsEachContract() {
        let usdc = Self.portfolio.positions.first { $0.symbol == "USDC" }
        #expect(usdc?.usd == 1_900)
        #expect(usdc?.contracts.map(\.key) == [Self.fake, Self.real])
    }

    /// The failure this exists for: hiding the spam by name hides your USDC.
    @Test func hidingTheFakeLeavesTheReal() {
        let shown = Self.portfolio.hiding(HiddenTokens.Choice(contracts: [Self.fake]))
        let usdc = shown.positions.first { $0.symbol == "USDC" }
        #expect(usdc?.usd == 900)
        #expect(usdc?.holders.map(\.address) == ["0xaaa"])
        #expect(shown.totalUSD == 1_500)
        // Its route pointed at the fake: it must not open the spam's chart.
        #expect(usdc?.route == nil)
        #expect(usdc?.contracts.map(\.key) == [Self.real])
    }

    @Test func hidingTheNameTakesTheWholeRow() {
        let shown = Self.portfolio.hiding(HiddenTokens.Choice(symbols: ["USDC"]))
        #expect(shown.positions.map(\.symbol) == ["ETH"])
        #expect(shown.totalUSD == 600)
    }

    @Test func hidingEveryContractTakesTheRow() {
        let shown = Self.portfolio.hiding(HiddenTokens.Choice(contracts: [Self.fake, Self.real]))
        #expect(!shown.positions.contains { $0.symbol == "USDC" })
        #expect(shown.totalUSD == 600)
    }

    @Test func theHiddenRowNamesWhereEachContractIs() {
        let items = Self.portfolio.hiddenItems(HiddenTokens.Choice(symbols: ["ETH"], contracts: [Self.fake]))
        #expect(items.count == 2)
        #expect(items.contains { $0.target == .symbol("ETH") && $0.place == nil && $0.usd == 600 })
        #expect(items.contains { $0.target == .contract(Self.fake) && $0.place == "Base · \(AddressTail.short("0xdeadbeef00000000000000000000000000000e07a"))" && $0.usd == 1_000 })
    }

    @Test func nothingHiddenIsTheSamePortfolio() {
        #expect(Self.portfolio.hiding(HiddenTokens.Choice()) == Self.portfolio)
        #expect(Self.portfolio.hiddenItems(HiddenTokens.Choice()).isEmpty)
    }

    /// One source hides by name as before; two or more offer each contract.
    @Test func theMenuSplitsOnlyWhereThereIsMoreThanOneSource() {
        let p = Self.portfolio
        #expect(TokenHideMenu.sources(p.positions.first { $0.symbol == "USDC" }!) == 2)
        #expect(TokenHideMenu.sources(p.positions.first { $0.symbol == "ETH" }!) == 1)
        let withExchange = WalletPortfolio.from(groups: [], exchange: [(symbol: "USDC", usd: 50, venue: .coinbase)])
        #expect(TokenHideMenu.sources(withExchange.positions[0]) == 1)
    }
}
