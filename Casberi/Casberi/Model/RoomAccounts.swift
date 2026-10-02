import Foundation

/// THE APPS A MERGED ROOM'S ACCOUNT MENU LISTS (prd §1048b; every merged room
/// gets this menu). When a category becomes one room, its apps stop
/// being rooms of their own and become entries in the room's menu, and a pick
/// narrows the room to that app.
///
/// One table per room, read by the menu, the row filter and the total, so the
/// three cannot disagree about what an app owns. Only the Wallet and Testnets
/// have entries so far; each room merged later adds its own beside it.
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
        /// Whether a pick shows the app's own screen inside the merged room
        /// rather than narrowing the room's (prd §1050k): a testnet's tiles,
        /// verbs and accounts are its own, and no view adds the two networks.
        var ownScreen = false

        /// Whether a row of `source` is this app's: its own source, its
        /// catalogue name, or a name it was renamed from (`Corpus.renamedSources`).
        func owns(_ source: String) -> Bool {
            source == self.source || source == name
                || Corpus.renamedSources[source]?.current == name
        }

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
        switch room {
        case CategoryFold.walletRoom: return wallet
        case testnetsRoom: return testnets
        case readingRoom: return reading
        case agentsRoom: return agents
        case mediaRoom: return media
        case lifeRoom: return life
        case dayRoom: return day
        case workRoom: return work
        case socialRoom: return social
        default: return []
        }
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
            if let seat = seats(for: room).first(where: { $0.owns(source) }) {
                return (room, seat)
            }
        }
        return nil
    }

    /// Every room that has absorbed apps. Each is named for its category,
    /// so the category's tray row and the room are one name (the Wallet's
    /// balance room always was).
    static let mergedRooms: [String] = [CategoryFold.walletRoom, testnetsRoom, readingRoom, agentsRoom, mediaRoom,
                                          lifeRoom, dayRoom, workRoom, socialRoom]

    /// The Testnets room (prd §1050, built §1050k). No seat carries the name;
    /// the room exists while Hegotá Frames or Logos is connected.
    static let testnetsRoom = "Testnets"

    /// The Reading room (prd §1049, §1050d, §1051a, built §1052).
    static let readingRoom = "Reading"

    /// The Agents room (prd §1049, built §1054).
    static let agentsRoom = "Agents"

    /// The Media room (prd §1049, §1050b, built §1055).
    static let mediaRoom = "Media"

    /// The Life and Day rooms (prd §1049, §1050c, built §1056).
    static let lifeRoom = "Life"
    static let dayRoom = "Day"

    /// The Work room (prd §1049, built §1057).
    static let workRoom = "Work"

    /// The Social room (prd §1068): the networks fold in, the last category
    /// to become one room.
    static let socialRoom = "Social"

    /// The merged room a category opens, nil while the category still opens
    /// its apps' own rooms.
    static func room(ofCategory category: String) -> String? {
        mergedRooms.contains(category) ? category : nil
    }

    /// THE SCREEN A ROOM OF OWN-SCREEN APPS SHOWS (prd §1050k): the picked
    /// app's when it is connected, else the first connected one in menu
    /// order. Nil for a room that draws itself (the Wallet), and for one with
    /// nothing connected.
    static func shownSource(room: String, scope: String?, names: Set<String>) -> String? {
        let own = connected(in: room, names: names).filter(\.ownScreen)
        guard !own.isEmpty else { return nil }
        let picked = seat(scope, in: room).flatMap { pick in own.first { $0 == pick } }
        return (picked ?? own[0]).source
    }

    /// Every source a room's query, its row filter and its safety-net probe
    /// fetch: the room alone, or the room with every app it folded in.
    static func roomSources(_ room: String) -> [String] {
        let seats = seats(for: room)
        let names = Set(seats.map(\.name))
        // Rows stamped under a seat's old name still belong to it (§647).
        let renamed = Corpus.renamedSources.filter { names.contains($0.value.current) }.keys.sorted()
        return [room] + seats.compactMap(\.source) + renamed
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
    private static let networks = String(localized: "Networks")

    /// A category's catalogue members as seats, A to Z (§995's order for a
    /// room's picks): a room whose apps have no money to slice and no screen
    /// of their own needs no table of its own, so a new app in the category
    /// joins the menu with nothing to add here. `group` is empty: the menu
    /// draws flat.
    private static func catalogSeats(_ category: String) -> [Seat] {
        BridgeCatalog.allOffers.filter { BridgeCatalog.category(of: $0) == category }
            .map { Seat(name: $0.name, source: $0.name, holder: nil, group: "", mark: $0.name) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Reading's (prd §1049): RSS, Substack, Readwise, Kindle, Bookmarks,
    /// Raindrop, NerdWallet, L2BEAT and Walletbeat (§1051a).
    private static let reading = catalogSeats(readingRoom)

    /// Agents' (prd §1049): every agent, its imported history and its keyed
    /// conversations alike.
    private static let agents = catalogSeats(agentsRoom)

    /// Media's (prd §1049, §1050b): YouTube, Twitch, Apple Music, Spotify,
    /// Podcasts, Steam, Pinterest and Photos.
    private static let media = catalogSeats(mediaRoom)

    /// Life's (prd §1049): Apple Journal, Day One, Obsidian, Files, Dropbox,
    /// Apple Health with Strava and Garmin, Duolingo, Contacts. Contacts
    /// lands no row (§916), so it never reaches the menu.
    private static let life = catalogSeats(lifeRoom)

    /// Day's (prd §1049): Calendar, Reminders, Todoist, Cal.com, Calendly,
    /// Gmail and iCloud Mail.
    private static let day = catalogSeats(dayRoom)

    /// Work's (prd §1049): every builder seat, Dodo Payments included.
    private static let work = catalogSeats(workRoom)

    /// Social's (prd §1068): X, Instagram, TikTok, Snapchat, Telegram,
    /// Farcaster, Bluesky and Nostr.
    private static let social = catalogSeats(socialRoom)

    /// The testnets (prd §1050): test money, never in the Wallet's menu or
    /// total (§83).
    private static let testnets: [Seat] = [
        Seat(name: FramesIdentity.source, source: FramesIdentity.source,
             holder: nil, group: networks, mark: FramesIdentity.source, ownScreen: true),
        Seat(name: LogosRoom.source, source: LogosRoom.source,
             holder: nil, group: networks, mark: LogosRoom.source, ownScreen: true),
    ]

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
