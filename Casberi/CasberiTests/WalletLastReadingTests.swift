import Foundation
import Testing
@testable import Casberi

/// **The Wallet opens on its last reading** (prd §1593): drawn at once,
/// stamped with when it was read, and never over a different set of wallets.
struct WalletLastReadingTests {

    static var portfolio: WalletPortfolio {
        var g = WalletIngest.HoldingsGroup(label: "You", address: "0xAAA", cells: [], totalUSD: 589, tokenCount: 1)
        g.bySymbolAll = ["ETH": 589]
        g.partsBySymbol = ["ETH": [HiddenTokens.contractKey(network: "eth-mainnet", contract: nil): 589]]
        return WalletPortfolio.from(groups: [g])
    }

    static let read = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func aReadingComesBackStampedWithWhenItWasRead() {
        let map = WalletLastReading.remembering(Self.portfolio, scope: nil, wallets: ["0xAAA"], at: Self.read, in: [:])
        let back = WalletLastReading.reading(scope: nil, wallets: ["0xaaa"], in: map)
        #expect(back?.totalUSD == 589)
        #expect(back?.asOf == Self.read)
    }

    /// The failure this exists for: an unfollow changes what All is, and the
    /// old All must not stand under the new one's name.
    @Test func anotherSetOfWalletsGetsNothing() {
        let map = WalletLastReading.remembering(Self.portfolio, scope: nil, wallets: ["0xAAA", "0xBBB"], at: Self.read, in: [:])
        #expect(WalletLastReading.reading(scope: nil, wallets: ["0xAAA"], in: map) == nil)
        #expect(WalletLastReading.reading(scope: nil, wallets: ["0xbbb", "0xaaa"], in: map) != nil)
    }

    @Test func eachScopeIsItsOwn() {
        let map = WalletLastReading.remembering(Self.portfolio, scope: "0xAAA", wallets: ["0xAAA"], at: Self.read, in: [:])
        #expect(WalletLastReading.reading(scope: nil, wallets: ["0xAAA"], in: map) == nil)
        #expect(WalletLastReading.reading(scope: "0xAAA", wallets: ["0xAAA"], in: map) != nil)
    }

    /// A reading that was already last-known keeps its older stamp.
    @Test func anOlderStampIsKept() {
        var stale = Self.portfolio
        stale.asOf = Self.read.addingTimeInterval(-3_600)
        let map = WalletLastReading.remembering(stale, scope: nil, wallets: ["0xAAA"], at: Self.read, in: [:])
        #expect(WalletLastReading.reading(scope: nil, wallets: ["0xAAA"], in: map)?.asOf == stale.asOf)
    }

    @Test func onlyTheNewestScopesAreKept() {
        var map: [String: WalletLastReading.Entry] = [:]
        for i in 0..<(WalletLastReading.keep + 3) {
            map = WalletLastReading.remembering(Self.portfolio, scope: "s\(i)", wallets: ["0xAAA"],
                                                at: Self.read.addingTimeInterval(Double(i)), in: map)
        }
        #expect(map.count == WalletLastReading.keep)
        #expect(map["s0"] == nil)
        #expect(map["s\(WalletLastReading.keep + 2)"] != nil)
    }

    @Test func aPortfolioSurvivesStorage() throws {
        let data = try JSONEncoder().encode(Self.portfolio)
        #expect(try JSONDecoder().decode(WalletPortfolio.self, from: data) == Self.portfolio)
    }
}
