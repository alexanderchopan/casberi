import Foundation

/// **NOTES AND MARKETS ARE PLACES IN HOME (prd §1127, user: "markets like
/// notes would have no swipe. they both become like all the other apps are
/// in a room. accessed by the toggle").**
///
/// Home's title row carries a glass pill that says You and lists the tray's
/// six pink doors. Notes and Markets are Home's two scopes, the way an app is
/// a merged room's: they leave the swipe, the title keeps "Home", and the
/// pill names the pick. A swipe from either walks as Home does.
enum HomeScope {
    /// The Markets category, which is a You door and not a room in the walk.
    static let markets = "Markets"

    /// Whether `source` stands in Home: the All feed, Notes, or a Markets room.
    static func contains(_ source: String) -> Bool {
        source == "All" || source == Pinboard.room || isMarkets(source)
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
