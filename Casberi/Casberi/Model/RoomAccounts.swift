import Foundation

/// THE APPS A MERGED ROOM'S ACCOUNT MENU LISTS (prd §1048b; every merged room
/// gets this menu). When a category becomes one room, its apps stop
/// being rooms of their own and become entries in the room's menu, and a pick
/// narrows the room to that app.
///
/// One table per room, read by the menu, the row filter and the total, so the
/// three cannot disagree about what an app owns. Only the Wallet has entries
/// so far; each room merged later adds its own beside it.
enum RoomAccounts {

    struct Seat: Equatable {
        /// The catalogue's name for it (`BridgeApp.name`), which is how the
        /// menu knows it is connected.
        let name: String
        /// The `Thing.source` its rows land under, when they ride this room.
        let source: String?
        /// The `WalletPortfolio` holder id its money sits under in the total,
        /// matched exactly or as a prefix ending in ":".
        let holder: String?
        /// The menu section it stands in.
        let group: String
        /// The mark the menu draws.
        let mark: String

        func holds(_ holderID: String) -> Bool {
            guard let holder else { return false }
            return holder.hasSuffix(":") ? holderID.hasPrefix(holder) : holderID == holder
        }
    }

    /// A seat's scope id. The Wallet's other scopes are addresses, and no
    /// address starts with this.
    static let seatPrefix = "seat:"

    static func scopeID(_ seat: Seat) -> String { seatPrefix + seat.name }

    static func isSeat(_ scope: String?) -> Bool { scope?.hasPrefix(seatPrefix) ?? false }

    /// The seat a scope names in `room`, or nil for All or an address.
    static func seat(_ scope: String?, in room: String) -> Seat? {
        guard let scope, scope.hasPrefix(seatPrefix) else { return nil }
        let name = String(scope.dropFirst(seatPrefix.count))
        return seats(for: room).first { $0.name == name }
    }

    /// Every app the room can list, in menu order. The menu shows the
    /// connected ones (`connected`).
    static func seats(for room: String) -> [Seat] {
        room == CategoryFold.walletRoom ? wallet : []
    }

    static func connected(in room: String, names: Set<String>) -> [Seat] {
        seats(for: room).filter { names.contains($0.name) }
    }

    private static let appWallets = String(localized: "App wallets")
    private static let exchanges = String(localized: "Exchanges and banks")
    private static let cards = String(localized: "Cards")

    /// The Wallet's (prd §1048). Safe is not here: a Safe you watch is an
    /// address, and already a row of the menu's address half.
    private static let wallet: [Seat] = [
        Seat(name: "Privy", source: PrivyHomeFeed.source,
             holder: WalletPortfolio.privyHolderPrefix, group: appWallets, mark: "Privy"),
        Seat(name: ExchangeBridge.Venue.coinbase.display, source: nil,
             holder: ExchangeBridge.Venue.coinbase.rawValue, group: exchanges, mark: "Coinbase"),
        Seat(name: ExchangeBridge.Venue.kraken.display, source: nil,
             holder: ExchangeBridge.Venue.kraken.rawValue, group: exchanges, mark: "Kraken"),
        Seat(name: ExchangeBridge.Venue.binance.display, source: nil,
             holder: ExchangeBridge.Venue.binance.rawValue, group: exchanges, mark: "Binance"),
        Seat(name: ExchangeBridge.Venue.geminiExchange.display, source: nil,
             holder: ExchangeBridge.Venue.geminiExchange.rawValue, group: exchanges,
             mark: "Gemini Exchange"),
        Seat(name: "Wise", source: nil,
             holder: WalletCash.holderPrefix + "wise", group: exchanges, mark: "Wise"),
        Seat(name: "Apple Wallet", source: AppleWalletBridge.sourceName,
             holder: WalletCash.holderPrefix + "applewallet:", group: cards, mark: "Apple Wallet"),
        Seat(name: "Gnosis Pay", source: GnosisPayBridge.sourceName,
             holder: nil, group: cards, mark: "Gnosis Pay"),
        Seat(name: "MetaMask Card", source: MetaMaskCardBridge.source,
             holder: nil, group: cards, mark: "MetaMask Card"),
        Seat(name: "ether.fi", source: EtherFiCash.source,
             holder: nil, group: cards, mark: "ether.fi"),
        Seat(name: "Privacy", source: WalletCards.privacySource,
             holder: nil, group: cards, mark: "Privacy"),
    ]
}
