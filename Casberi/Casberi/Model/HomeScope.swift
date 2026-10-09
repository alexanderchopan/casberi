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
        case apps, addresses, settings

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

    /// **THE PHONE'S WALK (prd §1207 item 1, amends §1203's two poles).**
    /// Wallet, the Feed ("All", where You's places stand), then every
    /// category with a room in the dock's order, Testnets excepted (the
    /// tray's alone). Apps are never stops: an app is a pick inside its
    /// category's page. Left to right, so a swipe right walks toward the
    /// Wallet.
    @MainActor static func phoneWalk(chips: [String]) -> [String] {
        let present = Set(chips)
        let rest = CategoryOrder.current.filter {
            $0 != CategoryFold.walletRoom && $0 != RoomAccounts.testnetsRoom && present.contains($0)
        }
        return [CategoryFold.walletRoom, "All"] + rest
    }

    /// Where `source` stands in the walk: You's places at the Feed's, an
    /// app at its category's.
    @MainActor static func walkStop(_ source: String) -> String {
        contains(source) ? "All" : (RoomAccounts.host(ofSource: source)?.room ?? source)
    }
}

/// YOU'S FOUR PLACES AS TILES (prd §1136 item 1, user: "the magic of the app
/// is having the same view on each screen"). You is a room like every
/// category — title, box, tiles, list — and these are its tiles: Home first,
/// then A–Z, which here also runs from what you open daily to what you set
/// up rarely. Picking one never moves the box or the tiles; only the box's
/// face and the list change. The tray's You row is the same four.
///
/// Foundation-only, like every scope enum, so a harness can compile it whole;
/// the glyphs are `ScopeTileGlyphs.swift`'s.
enum YouTile: String, CaseIterable, Identifiable, Hashable, Sendable {
    /// Home: the feed, Today then Coming up (§1136 item 7). Spelled `feed`
    /// because `home` is the wallet family's Home tile, another glyph.
    ///
    /// **Feed · Markets · Sources · Settings (prd §1207 item 9).** Notes left
    /// the tiles: a note is written from ✎ in the bottom band, anywhere, and
    /// read from the note sheet and the bar. Sources is everything you have
    /// connected (the master list, §1136); Settings is Casberi's own options,
    /// which were the master list's pinned row.
    case feed, markets, sources, settings

    var id: String { rawValue }

    var label: String {
        switch self {
        // FEED (prd §1203, user: "Feed is good"; was "Today", §1166): beside
        // "Wallet" a time read wrong against a place. The date line under
        // the box still says it is today's.
        case .feed:     return String(localized: "Feed")
        case .markets:  return String(localized: "Markets")
        case .sources:  return String(localized: "Sources")
        case .settings: return String(localized: "Settings")
        }
    }

    /// Read by VoiceOver and the tooltip.
    var summary: String {
        switch self {
        case .feed:     return String(localized: "Today, then what is coming up")
        case .markets:  return String(localized: "What you watch")
        case .sources:  return String(localized: "Everything you have connected")
        case .settings: return String(localized: "Casberi's own options")
        }
    }

    /// The tile standing for the shell's `source`, or nil outside You.
    init?(source: String) {
        if source == "All" { self = .feed }
        else if HomeScope.isMarkets(source) { self = .markets }
        else if HomeScope.Place(source: source) == .settings { self = .sources }
        else { return nil }
    }
}

