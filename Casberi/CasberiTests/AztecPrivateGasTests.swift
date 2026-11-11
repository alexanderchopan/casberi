import Foundation
import Testing
@testable import Casberi

/// **Private gas on Aztec** (prd §1700aa): gas kept in the shared private fee
/// contract, minted by the next send, and bought with a little of what is
/// being moved. A wrong answer here is a send told to mint a deposit the
/// account's own claim already took, an account stopped for want of AZTEC it
/// no longer needs, or a move that leaves nothing to buy its gas with.
@MainActor
struct AztecPrivateGasTests {
    private let prices: [String: Double] = ["USDC": 1, "WETH": 3000, "AZTEC": 0.0124]
    private let gwei04 = Decimal(400_000_000)

    private func deposit(_ nonce: UInt64, kind: String?, claimed: Bool = false) -> AztecAccountStore.GasDeposit {
        .init(nonce: nonce, amountUnits: "30000000000000000000", transaction: "0xaa", messageHash: "0x\(nonce)",
              leafIndex: "7", claimed: claimed, at: .now, kind: kind)
    }

    // MARK: - What a send may mint

    @Test func onlyUnmintedPrivateDepositsAreOffered() throws {
        let gas = [deposit(1, kind: nil), deposit(2, kind: "own"), deposit(3, kind: "private"),
                   deposit(4, kind: "private", claimed: true)]
        let rows = try #require(JSONSerialization.jsonObject(with: Data(AztecGas.unminted(gas).utf8)) as? [[String: String]])
        #expect(rows.count == 1, "a deposit of the account's own, or one already minted, is never offered")
        #expect(rows.first == ["nonce": "3", "amount": "30000000000000000000", "leafIndex": "7", "messageHash": "0x3"])
        #expect(AztecGas.unminted([deposit(1, kind: nil)]) == "[]")
    }

    @Test func aDepositFromBeforePrivateGasStillReadsAndIsTheAccountsOwn() throws {
        // What builds before §1700aa stored: no `kind`.
        let old = #"{"nonce":9,"amountUnits":"30000000000000000000","transaction":"0xaa","messageHash":"0xbb","leafIndex":"3","claimed":false,"at":0}"#
        let kept = try JSONDecoder().decode(AztecAccountStore.GasDeposit.self, from: Data(old.utf8))
        #expect(kept.kind == nil)
        #expect(!kept.isPrivate, "it is claimed on its own, as it always was")
    }

    // MARK: - Whether the account needs gas

    @Test func gasInEitherPlaceCounts() {
        let fifteen = Decimal(string: "15000000000000000000")!
        let ten = Decimal(string: "10000000000000000000")!
        #expect(AztecGas.needed(gas: [], inside: 0, own: 0))
        #expect(!AztecGas.needed(gas: [], inside: 0, own: fifteen), "its own gas still pays, in the open")
        #expect(!AztecGas.needed(gas: [], inside: ten, own: 0), "ten inside the contract is enough: its sends are measured")
        #expect(AztecGas.needed(gas: [], inside: ten - 1, own: fifteen - 1))
        #expect(!AztecGas.needed(gas: [deposit(3, kind: "private")], inside: 0, own: 0), "a deposit on its way is gas on its way")
        #expect(AztecGas.needed(gas: [deposit(3, kind: "private", claimed: true)], inside: 0, own: 0))
        let both = AztecAccountStore.Holding(kind: .feeJuice, address: "0x03", name: "Fee Juice", decimals: 18,
                                             privateUnits: "12000000000000000000", publicUnits: "5000000000000000000")
        #expect(both.gasUnits == Decimal(string: "17000000000000000000")!, "its own and what it keeps in the contract")
    }

    @Test func aMoveInBringsPrivateGasWhateverTheAccountHoldsOfItsOwn() {
        let ten = Decimal(string: "10000000000000000000")!
        // An account funded before §1700aa holds gas of its own, which names
        // it on every send: a move-in still brings private gas.
        #expect(AztecGas.ridesAlong(gas: [], inside: 0))
        #expect(AztecGas.ridesAlong(gas: [deposit(1, kind: nil)], inside: 0), "a deposit of its own on the way is not private gas")
        #expect(!AztecGas.ridesAlong(gas: [], inside: ten))
        #expect(!AztecGas.ridesAlong(gas: [deposit(3, kind: "private")], inside: 0), "one top-up at a time")
        #expect(AztecGas.ridesAlong(gas: [deposit(3, kind: "private", claimed: true)], inside: ten - 1))
    }

    // MARK: - Gas bought with what you move

    @Test func aSaleIsThirtyAztecAndFourPercentOver() {
        // 30 × $0.0124 = $0.372, × 1.04 = $0.38688 of USDC, rounded up.
        #expect(AztecGas.saleUnits(sellPrice: 1, aztecPrice: 0.0124, decimals: 6) == "386880")
        // In WETH at $3,000: 0.00012896, 18 decimals.
        #expect(AztecGas.saleUnits(sellPrice: 3000, aztecPrice: 0.0124, decimals: 18) == "128960000000000")
        #expect(AztecGas.saleUnits(sellPrice: nil, aztecPrice: 0.0124, decimals: 6) == nil)
        #expect(AztecGas.saleUnits(sellPrice: 1, aztecPrice: nil, decimals: 6) == nil)
        #expect(AztecGas.saleUnits(sellPrice: 0, aztecPrice: 0.0124, decimals: 6) == nil)
    }

    @Test func holdingNoAztecBuysGasAndHoldingEnoughDoesNot() {
        let m = AztecMove()
        m.seedForTests(mode: .deposit, symbol: "USDC", held: "50000000", amount: "25",
                       prices: prices, feePerL2Gas: nil, gasPriceWei: gwei04, bringsGas: true, safeAZTEC: "0")
        #expect(m.buysGas)
        #expect(m.gasSale == "386880")
        m.seedForTests(mode: .deposit, symbol: "USDC", held: "50000000", amount: "25",
                       prices: prices, feePerL2Gas: nil, gasPriceWei: gwei04, bringsGas: true)
        #expect(!m.buysGas, "an account holding its 30 AZTEC sends them, as before")
        #expect(m.gasSale == nil)
        m.seedForTests(mode: .deposit, symbol: "USDC", held: "50000000", amount: "25",
                       prices: prices, feePerL2Gas: nil, gasPriceWei: gwei04, bringsGas: false, safeAZTEC: "0")
        #expect(!m.buysGas, "no gas rides along: nothing is sold")
    }

    @Test func allLeavesWhatBuysGasAndMoreIsRefusedInWords() {
        let m = AztecMove()
        m.seedForTests(mode: .deposit, symbol: "USDC", held: "50000000", amount: "50",
                       prices: prices, feePerL2Gas: nil, gasPriceWei: gwei04, bringsGas: true, safeAZTEC: "0")
        #expect(m.amount(for: .all) == "49.61312", "All is what you hold less the sale")
        #expect(m.amount(for: .half) == "25")
        if case .leavesNoGas = m.amountProblem {} else {
            Issue.record("typing everything you hold leaves nothing to buy gas with")
        }
        m.amount = "49.61312"
        #expect(m.amountProblem == nil)
        m.amount = "60"
        if case .moreThanHeld = m.amountProblem {} else { Issue.record("more than held is still said first") }
    }

    @Test func theCostNamesTheSaleInItsOwnToken() throws {
        let m = AztecMove()
        m.seedForTests(mode: .deposit, symbol: "USDC", held: "50000000", amount: "25",
                       prices: prices, feePerL2Gas: nil, gasPriceWei: gwei04, bringsGas: true, safeAZTEC: "0")
        let cost = try #require(m.cost)
        // Shield $0.125 + 750K gas × 0.4 gwei × $3,000 = $0.90 + the sale $0.387
        #expect(abs(cost.usd - (0.125 + 0.9 + 0.387)) < 0.01)
        #expect(cost.parts.last?.words == "Aztec's gas, bought with your USDC")
        #expect(cost.parts.contains { $0.figure == "30 AZTEC" } == false)
    }

    @Test func noPriceNoSaleAndNoDollars() {
        let m = AztecMove()
        m.seedForTests(mode: .deposit, symbol: "USDC", held: "50000000", amount: "25",
                       prices: ["USDC": 1, "WETH": 3000], feePerL2Gas: nil, gasPriceWei: gwei04, bringsGas: true, safeAZTEC: "0")
        #expect(m.buysGas)
        #expect(m.gasSale == nil, "without AZTEC's price the sale is not sized")
        #expect(m.cost == nil)
        #expect(m.amount(for: .all) == nil, "All waits for the price: the whole balance would leave nothing for gas")
        #expect(m.amount(for: .half) == "25")
    }

    // MARK: - The calls

    @Test func theDepositCallsApproveThePortalThenDepositToTheNamedAddress() {
        let to = String(repeating: "0", count: 63) + "5"
        let amount = String(repeating: "0", count: 62) + "1e"
        let hash = String(repeating: "a", count: 64)
        let calls = AztecGas.calls(to: to, amount: amount, secretHash: hash)
        #expect(calls.count == 2)
        #expect(calls[0].to == AztecGas.token)
        #expect(calls[0].data == "0x095ea7b3" + String(repeating: "0", count: 24) + AztecGas.portal.dropFirst(2) + amount)
        #expect(calls[1].to == AztecGas.portal)
        #expect(calls[1].data == "0x284b5dc6" + to + amount + hash)
        #expect(calls.allSatisfy { $0.value == "0" })
    }
}
