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
    static var title: String {
        ProfileStore.shared.name ?? String(localized: "You")
    }

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
}
