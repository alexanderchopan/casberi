import Foundation
import Testing
@testable import Casberi

/// **What a private move on Aztec costs, in dollars** (prd §1700y), the
/// shape of Railgun's §1728 item 6. A wrong answer is a cost line that
/// leaves Shield's cut out, prices gas at the wrong unit, or offers a chip
/// Shield would refuse.
@MainActor
struct AztecMoveCostTests {
    /// Today's mainnet: 2,186,613,113,685 Fee Juice wei per unit of L2 gas,
    /// AZTEC $0.0124, ETH $3,000, Ethereum gas 0.4 gwei.
    private let prices: [String: Double] = ["USDC": 1, "WETH": 3000, "AZTEC": 0.0124]
    private let fee = Decimal(string: "2186613113685")!
    private let gwei04 = Decimal(400_000_000)
    private let aztecAddress = "0x038c142df384d4df8ef86f049e4099a7531da644c637bfc567b63225f5b2a155"

    @Test func aSendOnAztecCostsItsGasAtTheNodesFee() throws {
        let m = AztecMove()
        m.seedForTests(mode: .send, symbol: "USDC", held: "120000000", amount: "20", recipient: aztecAddress,
                       prices: prices, feePerL2Gas: fee, gasPriceWei: nil)
        let cost = try #require(m.cost)
        // 750,000 × 2.1866e12 = 1.64 Fee Juice × $0.0124 ≈ $0.0203
        #expect(abs(cost.usd - 0.0203) < 0.001)
        #expect(cost.parts.count == 1)
        #expect(cost.figure == "Costs about $0.02")
    }

    @Test func anExitAddsShieldsHalfPercent() throws {
        let m = AztecMove()
        m.seedForTests(mode: .send, symbol: "USDC", held: "120000000", amount: "100",
                       recipient: "0x7a16fF8270133F063aAb6C9977183D9e72835428",
                       prices: prices, feePerL2Gas: fee, gasPriceWei: nil)
        let cost = try #require(m.cost)
        #expect(cost.parts.first?.words == "Shield")
        #expect(cost.parts.first?.figure.hasPrefix("0.5") == true)
        #expect(cost.usd > 0.5 && cost.usd < 0.6) // $0.50 + ~$0.04 of gas
    }

    @Test func aMoveInAddsEthereumGasAndRideAlongGas() throws {
        let m = AztecMove()
        m.seedForTests(mode: .deposit, symbol: "USDC", held: "50000000", amount: "25",
                       prices: prices, feePerL2Gas: nil, gasPriceWei: gwei04, bringsGas: true)
        let cost = try #require(m.cost)
        // Shield $0.125 + 500K gas × 0.4 gwei × $3,000 = $0.60 + 30 AZTEC $0.372
        #expect(abs(cost.usd - (0.125 + 0.6 + 0.372)) < 0.01)
        #expect(cost.parts.count == 3)
    }

    @Test func noPriceNoDollars() {
        let m = AztecMove()
        m.seedForTests(mode: .send, symbol: "USDC", held: "120000000", amount: "20", recipient: aztecAddress,
                       prices: ["USDC": 1], feePerL2Gas: fee, gasPriceWei: nil)
        #expect(m.cost == nil, "without AZTEC's price the foot keeps its words")
    }

    @Test func halfAndAllAreExactAndShieldsCapHidesAll() {
        let m = AztecMove()
        m.seedForTests(mode: .deposit, symbol: "USDC", held: "7525000", amount: "",
                       prices: prices, feePerL2Gas: nil, gasPriceWei: gwei04, maxUSD: 5)
        #expect(m.amount(for: .half) == "3.7625")
        #expect(m.amount(for: .all) == nil, "all of $7.525 is over a $5 Shield cap")
        m.seedForTests(mode: .send, symbol: "USDC", held: "7525000", amount: "", recipient: aztecAddress,
                       prices: prices, feePerL2Gas: fee, gasPriceWei: nil)
        #expect(m.amount(for: .all) == "7.525")
        #expect(m.amountLine?.hasPrefix("you have $7.5") == true)
    }
}
