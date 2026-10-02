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

    /// Step 4's fold: a folded app's room name lands in the Wallet, scoped to
    /// it; the Wallet itself and the rooms that stay apart are their own.
    @Test func aFoldedAppHasTheWalletAsItsRoom() {
        let gnosis = RoomAccounts.host(ofSource: GnosisPayBridge.sourceName)
        #expect(gnosis?.room == CategoryFold.walletRoom)
        #expect(gnosis?.seat.name == "Gnosis Pay")
        #expect(RoomAccounts.host(ofSource: SafeBridge.sourceName)?.room == CategoryFold.walletRoom)
        // The source and the catalogue name both resolve (Privacy Pools lands
        // rows as "Privacy Pools"; its seat is "0xBow Privacy Pools").
        #expect(RoomAccounts.host(ofSource: PrivacyPoolsBridge.sourceName)?.seat.name == "0xBow Privacy Pools")
        #expect(RoomAccounts.host(ofSource: "0xBow Privacy Pools") != nil)
        // Bitrefill folded in with §1051a; L2BEAT and Walletbeat went to Reading.
        #expect(RoomAccounts.host(ofSource: "Bitrefill")?.room == CategoryFold.walletRoom)
        #expect(RoomAccounts.host(ofSource: "L2BEAT")?.room == RoomAccounts.readingRoom)
        #expect(RoomAccounts.host(ofSource: "Walletbeat")?.room == RoomAccounts.readingRoom)
        for room in [CategoryFold.walletRoom, "Markets", RoomAccounts.testnetsRoom, "Bluesky"] {
            #expect(RoomAccounts.host(ofSource: room) == nil, "\(room) stays its own room")
        }
    }

    // MARK: - Reading (prd §1052)

    /// Reading's menu is the catalogue's Reading members, A to Z, with
    /// NerdWallet, L2BEAT and Walletbeat among them and no Wallet app.
    @Test func readingListsItsCatalogueAppsAToZ() {
        let names = RoomAccounts.seats(for: RoomAccounts.readingRoom).map(\.name)
        for app in ["RSS", "Substack", "Readwise", "Kindle", "Bookmarks", "Raindrop",
                    "NerdWallet", "L2BEAT", "Walletbeat"] {
            #expect(names.contains(app), "\(app) is in Reading")
        }
        #expect(!names.contains("Safe"))
        #expect(names == names.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
        #expect(BridgeCatalog.category(forSource: "NerdWallet") == "Reading")
    }

    /// A folded reading app lands in Reading, scoped to it, and its rows ride
    /// the room; an app's own rows are its own and nobody else's.
    @Test func aReadingAppFoldsIntoReading() throws {
        let host = try #require(RoomAccounts.host(ofSource: "L2BEAT"))
        #expect(host.room == RoomAccounts.readingRoom)
        #expect(host.seat.owns("L2BEAT"))
        #expect(!host.seat.owns("Walletbeat"))
        #expect(RoomAccounts.rides(room: RoomAccounts.readingRoom, source: "RSS"))
        #expect(!RoomAccounts.rides(room: RoomAccounts.readingRoom, source: "GitHub"))
        #expect(BridgeCatalog.category(forSource: RoomAccounts.readingRoom) == "Reading")
    }

    // MARK: - Agents (prd §1054)

    /// Every agent is a seat of Agents, keyed or imported, and each agent
    /// provider's name is one of them — so New's pick always has a seat.
    @Test func agentsHoldsEveryAgent() {
        let names = Set(RoomAccounts.seats(for: RoomAccounts.agentsRoom).map(\.name))
        for provider in AgentProvider.allCases {
            #expect(names.contains(provider.agent), "\(provider.agent) is in Agents")
        }
        #expect(names.contains("Claude Code"))
        #expect(RoomAccounts.host(ofSource: "Claude")?.room == RoomAccounts.agentsRoom)
        #expect(AgentRoomScope.new.label == "New")
    }

    // MARK: - Media (prd §1055)

    /// Media holds the watching, listening, games and pictures apps, Photos
    /// included (§1050b), and Photos is no longer Life's.
    @Test func mediaHoldsPhotosAndTheMediaApps() {
        let names = Set(RoomAccounts.seats(for: RoomAccounts.mediaRoom).map(\.name))
        for app in ["YouTube", "Twitch", "Apple Music", "Spotify", "Podcasts", "Steam",
                    "Pinterest", "Photos"] {
            #expect(names.contains(app), "\(app) is in Media")
        }
        #expect(BridgeCatalog.category(forSource: "Photos") == "Media")
        #expect(RoomAccounts.host(ofSource: "Spotify")?.room == RoomAccounts.mediaRoom)
    }

    // MARK: - Life and Day (prd §1056)

    /// Life is what you made, kept or did; Day what needs you next; Notes is
    /// no category, its journals Life's.
    @Test func lifeAndDaySplit() {
        let life = Set(RoomAccounts.seats(for: RoomAccounts.lifeRoom).map(\.name))
        let day = Set(RoomAccounts.seats(for: RoomAccounts.dayRoom).map(\.name))
        for app in ["Apple Journal", "Day One", "Obsidian", "Files", "Dropbox", "Apple Health",
                    "Duolingo"] {
            #expect(life.contains(app), "\(app) is in Life")
        }
        for app in ["Calendar", "Reminders", "Todoist", "Cal.com", "Calendly", "Gmail", "iCloud Mail"] {
            #expect(day.contains(app), "\(app) is in Day")
        }
        #expect(life.isDisjoint(with: day))
        #expect(!life.contains("Photos"))
        #expect(!BridgeCatalog.categories.map(\.name).contains("Notes"))
        #expect(CategoryOrder.defaultOrder.contains("Day"))
    }

    // MARK: - Work (prd §1057)

    /// Every builder seat stays, Dodo Payments moved in from the Wallet
    /// shelf, and Watch offers only the seats that keep a watch.
    @Test func workHoldsEveryBuilderSeat() {
        let work = Set(RoomAccounts.seats(for: RoomAccounts.workRoom).map(\.name))
        for app in ["GitHub", "GitLab", "Radicle", "Hugging Face", "Linear", "Jira", "Trello",
                    "Notion", "Slack", "Sentry", "Vercel", "PagerDuty", "Cloudflare", "AWS",
                    "npm", "PyPI", "App Store Connect", "PostHog", "Stripe", "Polar",
                    "Dodo Payments"] {
            #expect(work.contains(app), "\(app) is in Work")
        }
        #expect(Set(WorkWatch.allCases.map(\.rawValue)).isSubset(of: work))
        #expect(RoomAccounts.host(ofSource: "Dodo Payments")?.room == RoomAccounts.workRoom)
    }

    // MARK: - Testnets (prd §1050k)

    /// The two networks fold into Testnets, never into the Wallet: test money
    /// and real money never share a room (§1050).
    @Test func theTestnetsFoldIntoTestnetsNotTheWallet() {
        for source in [FramesIdentity.source, LogosRoom.source] {
            #expect(RoomAccounts.host(ofSource: source)?.room == RoomAccounts.testnetsRoom)
            #expect(!RoomAccounts.rides(room: CategoryFold.walletRoom, source: source))
        }
        #expect(RoomAccounts.seats(for: CategoryFold.walletRoom).allSatisfy { !$0.ownScreen })
    }

    /// The room no seat names is its own category, so the strip folds it there
    /// and the tray opens it.
    @Test func testnetsIsItsCategory() {
        #expect(BridgeCatalog.category(forSource: RoomAccounts.testnetsRoom) == "Testnets")
        #expect(RoomAccounts.room(ofCategory: "Testnets") == RoomAccounts.testnetsRoom)
        #expect(RoomAccounts.room(ofCategory: "Social") == nil)
    }

    /// The room shows the picked network's screen, the first connected one
    /// with no pick, never a network that is not connected, and nothing for a
    /// room that draws itself.
    @Test func theRoomShowsOneConnectedNetwork() {
        let room = RoomAccounts.testnetsRoom
        let both: Set = [FramesIdentity.source, LogosRoom.source]
        #expect(RoomAccounts.shownSource(room: room, scope: nil, names: both) == FramesIdentity.source)
        #expect(RoomAccounts.shownSource(room: room, scope: "seat:Logos", names: both) == LogosRoom.source)
        #expect(RoomAccounts.shownSource(room: room, scope: "seat:Logos",
                                         names: [FramesIdentity.source]) == FramesIdentity.source)
        #expect(RoomAccounts.shownSource(room: room, scope: nil, names: []) == nil)
        #expect(RoomAccounts.shownSource(room: CategoryFold.walletRoom, scope: "seat:Safe",
                                         names: ["Safe"]) == nil)
    }

    /// The query, the history screen and the row filter read one list.
    @Test func theWalletReadsEveryFoldedSourceAndItsOwn() {
        let sources = RoomAccounts.roomSources(CategoryFold.walletRoom)
        #expect(sources.first == CategoryFold.walletRoom)
        #expect(sources.contains(SafeBridge.sourceName))
        #expect(sources.contains(GnosisPayBridge.sourceName))
        #expect(!RoomAccounts.rides(room: CategoryFold.walletRoom, source: CategoryFold.walletRoom))
        #expect(RoomAccounts.rides(room: CategoryFold.walletRoom, source: PeerBridge.sourceName))
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
