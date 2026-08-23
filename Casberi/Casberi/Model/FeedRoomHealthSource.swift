import Foundation

/// `FeedRoomHealth`'s door to the app — which feeds a reading room follows,
/// and the live freshness record (2026-08-23, prd §455).
///
/// Split from the model for the reason every `…RoomSource` here is: the model
/// is Foundation-only so a harness can compile it whole, and this half reads
/// two `@Observable` stores and `FeedFreshness`, none of which a harness can
/// stand up.
enum FeedRoomHealthSource {

    /// The five rooms whose rows arrive from a feed the person followed.
    ///
    /// RSS keeps its own store of pasted addresses; the other four keep a
    /// `FeedFollowStore` of resolved names. Both are read here so the room
    /// never has to know which kind it is.
    static func feeds(for source: String) -> [FeedRoomHealth.Feed] {
        if source == "RSS" {
            return RSSStore.shared.feeds.map {
                FeedRoomHealth.Feed(name: $0.displayName, url: $0.url)
            }
        }
        guard let kind = FeedFollowKind(rawValue: source) else { return [] }
        return kind.store.entries.map {
            FeedRoomHealth.Feed(name: $0.displayName, url: $0.feedURL)
        }
    }

    /// Whether this room is one that follows feeds at all. A room that isn't
    /// never draws the note and never pays for the read.
    static func isFeedRoom(_ source: String) -> Bool {
        source == "RSS" || FeedFollowKind(rawValue: source) != nil
    }

    /// The room's verdict, or nil for nothing to say.
    static func standing(for source: String) -> FeedRoomHealth.Standing? {
        guard isFeedRoom(source) else { return nil }
        return FeedRoomHealth.standing(feeds: feeds(for: source)) {
            FeedFreshness.trouble(for: $0)
        }
    }

    /// Where the note's tap lands — the screen that can actually fix it, which
    /// is the one holding the followed list.
    static func destination(for source: String) -> BridgeRouter.Destination? {
        switch source {
        case "RSS":      .rss
        case "Substack": .substack
        case "Reddit":   .reddit
        case "YouTube":  .youtube
        case "Podcasts": .podcasts
        default:         nil
        }
    }
}
