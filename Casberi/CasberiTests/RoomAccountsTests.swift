import Foundation
import Testing
@testable import Casberi

/// **The account menu's apps** (prd §1048b): a pick is a scope id, a scope id
/// names one app, and the app's slice of the total holds only its own money.
/// The failure this guards was measured: the Wallet's whole total drawn under
/// an app's name.
struct RoomAccountsTests {

    private var gnosis: RoomAccounts.Seat? {
        RoomAccounts.seats(for: CategoryFold.walletRoom).first { $0.name == "Gnosis Pay" }
    }
    private var appleWallet: RoomAccounts.Seat? {
        RoomAccounts.seats(for: CategoryFold.walletRoom).first { $0.name == "Apple Wallet" }
    }

    @Test func aSeatScopeRoundTrips() throws {
        let seat = try #require(gnosis)
        let scope = RoomAccounts.scopeID(seat)
        #expect(RoomAccounts.isSeat(scope))
        #expect(RoomAccounts.seat(scope, in: CategoryFold.walletRoom) == seat)
    }

    /// An address is never mistaken for an app, and All is neither.
    @Test func anAddressIsNotASeat() {
        #expect(!RoomAccounts.isSeat("0x3f2a9b7c1d4e5f60718293a4b5c6d7e8f90191c4"))
        #expect(!RoomAccounts.isSeat(nil))
        #expect(RoomAccounts.seat("", in: CategoryFold.walletRoom) == nil)
    }

    /// A room not merged yet lists nothing, so a stale pick reads as All.
    @Test func anUnmergedRoomListsNoApps() {
        #expect(RoomAccounts.seats(for: "Markets").isEmpty)
        #expect(RoomAccounts.seat("seat:Gnosis Pay", in: "Markets") == nil)
    }

    @Test func onlyConnectedAppsAreListed() {
        let listed = RoomAccounts.connected(in: CategoryFold.walletRoom, names: ["Wise", "Gnosis Pay"])
        #expect(Set(listed.map(\.name)) == ["Wise", "Gnosis Pay"])
    }

    @Test func aPrefixHolderMatchesItsAccountsAndNothingElse() throws {
        let seat = try #require(appleWallet)
        #expect(seat.holds("cash:applewallet:Savings"))
        #expect(!seat.holds("cash:wise"))
        #expect(!seat.holds("coinbase"))
    }

    /// The measured failure: a card that holds nothing in the total must
    /// slice to nothing, never to the whole portfolio.
    @Test func aSliceHoldsOnlyItsOwnMoney() throws {
        let whole = WalletPortfolio.from(
            groups: [],
            venues: [(symbol: "USD", usd: 9_400, holderID: "cash:applewallet:Savings", label: "Savings"),
                     (symbol: "USD", usd: 3_000, holderID: "cash:wise", label: "Wise"),
                     (symbol: "ETH", usd: 500, holderID: "privy:zora", label: "Zora")])
        let apple = whole.scoped(to: try #require(appleWallet))
        #expect(apple.totalUSD == 9_400)
        #expect(apple.positions.map(\.symbol) == ["USD"])
        #expect(whole.scoped(to: try #require(gnosis)).isEmpty)
        // Idempotent: the box slices again at render.
        #expect(apple.scoped(to: try #require(appleWallet)) == apple)
    }
}
