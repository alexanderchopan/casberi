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

    /// Matched on the catalogue name or the row source: a seat can register
    /// under either ("0xBow Privacy Pools" is the offer, "Privacy Pools" lands
    /// the rows).
    static func connected(in room: String, names: Set<String>) -> [Seat] {
        seats(for: room).filter { names.contains($0.name) || ($0.source.map(names.contains) ?? false) }
    }

    static func isConnected(_ seat: Seat, names: Set<String>) -> Bool {
        names.contains(seat.name) || (seat.source.map(names.contains) ?? false)
    }

    /// Whether `source` is an app folded into a merged room, and which room
    /// (prd §1048, step 4): its rows ride that room, it has no room of its
    /// own, and every door that named its room lands in the merged room
    /// scoped to it. Nil for a source that is its own room.
    static func host(ofSource source: String) -> (room: String, seat: Seat)? {
        for room in mergedRooms {
            if let seat = seats(for: room).first(where: { $0.source == source || $0.name == source }) {
                return (room, seat)
            }
        }
        return nil
    }

    /// Every room that has absorbed apps. The rooms tray draws these as rooms
    /// (a header that opens the room, circles that open settings).
    static let mergedRooms: [String] = [CategoryFold.walletRoom]

    /// Every source a room's query, its row filter and its safety-net probe
    /// fetch: the room alone, or the room with every app it folded in.
    static func roomSources(_ room: String) -> [String] {
        [room] + seats(for: room).compactMap(\.source)
    }

    /// Whether a row of `source` belongs in `room` as a folded app's row.
    static func rides(room: String, source: String) -> Bool {
        source != room && roomSources(room).contains(source)
    }

    private static let safes = String(localized: "Safes")
    private static let appWallets = String(localized: "App wallets")
    private static let exchanges = String(localized: "Exchanges and banks")
    private static let staking = String(localized: "Staking")
    private static let cards = String(localized: "Cards")
    private static let trades = String(localized: "Trades and privacy")
    private static let names = String(localized: "Names")
    private static let teams = String(localized: "Teams")

    /// The Wallet's (prd §1048; Bitrefill since §1051a). L2BEAT and Walletbeat
    /// are Reading's (§1051a), not the Wallet's.
    private static let wallet: [Seat] = [
        Seat(name: "Safe", source: SafeBridge.sourceName,
             holder: nil, group: safes, mark: "Safe"),
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
        Seat(name: "Wise", source: WiseShape.source,
             holder: WalletCash.holderPrefix + "wise", group: exchanges, mark: "Wise"),
        Seat(name: "Acorns", source: AcornsLive.source,
             holder: nil, group: exchanges, mark: "Acorns"),
        Seat(name: "ETH Validators", source: nil,
             holder: WalletPortfolio.validatorHolderID, group: staking, mark: "ETH Validators"),
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
        Seat(name: "CardPointers", source: CardPointersIngest.source,
             holder: nil, group: cards, mark: "CardPointers"),
        Seat(name: "Rocket Money", source: RocketMoneyLive.source,
             holder: nil, group: cards, mark: "Rocket Money"),
        Seat(name: "Bitrefill", source: "Bitrefill",
             holder: WalletCash.holderPrefix + "bitrefill", group: cards, mark: "Bitrefill"),
        Seat(name: "Peer", source: PeerBridge.sourceName,
             holder: nil, group: trades, mark: "Peer"),
        Seat(name: "0xBow Privacy Pools", source: PrivacyPoolsBridge.sourceName,
             holder: nil, group: trades, mark: "0xBow Privacy Pools"),
        Seat(name: "Railgun", source: RailgunBridge.sourceName,
             holder: nil, group: trades, mark: "Railgun"),
        Seat(name: "ENS", source: ENSWatch.source,
             holder: nil, group: names, mark: "ENS"),
        Seat(name: "Splits", source: SplitsShape.source,
             holder: nil, group: teams, mark: "Splits"),
    ]
}
