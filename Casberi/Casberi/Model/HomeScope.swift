import Foundation

/// **NOTES AND MARKETS ARE PLACES IN HOME (prd §1127, user: "markets like
/// notes would have no swipe. they both become like all the other apps are
/// in a room. accessed by the toggle").**
///
/// Home's title row carries a glass pill that lists the tray's six pink
/// doors. Notes and Markets are Home's two scopes, the way an app is a merged
/// room's: they leave the swipe and the pill names the pick. A swipe from
/// either walks as Home does.
///
/// **THE CATEGORY IS YOU, AND EVERY DOOR IN IT IS A PLACE (prd §1129, user:
/// "when i switch to settings or apps it swipes the screen and has a back
/// button … the screen changes, but it doesn't move"; "home should say You,
/// and 'home' is what is selected").** Apps, Addresses and Settings stand in
/// the category as Notes and Markets do: the title says You, the pill names
/// the place, a pick cuts to it with no push and no back door.
enum HomeScope {
    /// The three places that are screens rather than feeds. Each has a source
    /// label of its own, so the shell's one switch (`filter.source`) holds it
    /// and a swipe from it walks as Home does. The labels carry a `you:`
    /// prefix no seat or catalogue category can spell ("Notes" taught that,
    /// prd §975).
    enum Place: String, CaseIterable {
        case apps, settings

        var source: String { "you:" + rawValue }

        init?(source: String) {
            guard source.hasPrefix("you:") else { return nil }
            self.init(rawValue: String(source.dropFirst(4)))
        }
    }

    /// The category's title: the name you gave the app, else You (prd §1129,
    /// user: "the user does set their name tho"; "it can be 'you' if they
    /// don't set a name"). Apple's own top-of-Settings card names you the
    /// same way. The name never leaves the device (`ProfileStore`).
    ///
    /// The demo is one person's life (prd §1026), and that person is Alex
    /// (user, 2026-10-06: "for the demo don't have my name … that's too long
    /// just have Alex"): the device's own name never titles somebody else's
    /// things, and a short one keeps "Alex · Sources" on one line.
    static var title: String {
        if DemoMode.isActive { return demoName }
        return ProfileStore.shared.name ?? String(localized: "You")
    }

    /// The demo person's name.
    static let demoName = "Alex"

    /// The Markets category, which is a You door and not a room in the walk.
    static let markets = "Markets"

    /// Whether `source` stands in You: the All feed (Home), Notes, a Markets
    /// room, or one of the three places.
    static func contains(_ source: String) -> Bool {
        source == "All" || source == Pinboard.room || isMarkets(source)
            || Place(source: source) != nil
    }

    /// Whether `source` is Markets' room.
    static func isMarkets(_ source: String) -> Bool {
        CategoryFold.isMember(source, of: markets)
    }

    /// Whether a strip label is one Home holds, so the walk leaves it out.
    static func leavesWalk(_ label: String) -> Bool {
        label == Pinboard.room || label == markets
    }

    /// **THE PHONE'S TWO PLACES (prd §1208 item 1, retires §1207's walk).**
    /// The Feed and the Wallet, one swipe apart; every category is a section
    /// of the Feed's scroll (`feedCategories`), never a page of the swipe.
    /// The Feed leads (prd §1208g, user: "lets put feed first since it's
    /// what user opens app to"), so its title reads "Feed  Wallet".
    ///
    /// **THE FIVE TABS SINCE prd §1327 item 6**: a swipe on a tab's own page
    /// walks the bar's order, Feed · Day · Wallet · Notes · Library.
    @MainActor static func phoneWalk(chips: [String]) -> [String] {
        PlaceTab.allCases.map(\.source)
    }

    /// The categories the Feed stacks (prd §1208 item 2): every one with a
    /// room, in the dock's order, the Wallet (its own place) and Testnets
    /// (the tray's) excepted.
    @MainActor static func feedCategories(chips: [String]) -> [String] {
        let present = Set(chips)
        // **DAY AND THE WALLET ARE FEED SECTIONS (prd §1343, user: "we just
        // make day a section", "wallet section should show last N things").**
        // Day leads by default and moves like any category; the Wallet's
        // section is a preview of its tab. Day stands whether or not a chip
        // names it: it is gathered, never one app's.
        return CategoryOrder.current.filter {
            $0 != RoomAccounts.testnetsRoom
                && ($0 == RoomAccounts.dayRoom || present.contains($0))
        }
    }

    /// Whether the phone shows `source` as a section of the Feed rather than
    /// a page: a category's combined room, the Wallet and Testnets excepted.
    @MainActor static func isFeedSection(_ source: String) -> Bool {
        // Day is a section since prd §1343; the Wallet keeps its tab.
        source != CategoryFold.walletRoom && source != RoomAccounts.testnetsRoom
            && RoomAccounts.mergedRooms.contains(source)
    }

    /// Where `source` stands in the walk: You's places at the Feed's, an
    /// app at its category's.
    @MainActor static func walkStop(_ source: String) -> String {
        contains(source) ? "All" : (RoomAccounts.host(ofSource: source)?.room ?? source)
    }
}

