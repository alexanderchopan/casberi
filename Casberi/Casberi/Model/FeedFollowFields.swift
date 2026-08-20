import Foundation

/// Two small readers for a feed-follow item's own fields, used while the row
/// is being landed (`FeedFollowBridges`).
///
/// Extracted from the old `FeedFollowMoments` when the in-app moment bus was
/// removed (2026-08-19). Everything else in that file existed to announce
/// something; these two decide what a landed row SAYS and where its door
/// goes, which is the feed's job and outlives the announcements.
enum FeedFollowFields {

    /// Reddit's Atom author name arrives as "/u/name" — the bare name reads
    /// better in a sentence.
    static func normalizedRedditAuthor(_ raw: String) -> String {
        var a = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["/u/", "u/"] where a.hasPrefix(prefix) {
            a.removeFirst(prefix.count)
            break
        }
        return a
    }

    /// The first link in `links` that doesn't point back at reddit.com/
    /// redd.it — what actually made the post worth reading, decoded (feed
    /// hrefs arrive HTML-escaped).
    static func firstExternalLink(_ links: [String]) -> String? {
        for raw in links {
            let link = IngestSupport.decodeHTMLEntities(raw)
            guard let host = URL(string: link)?.host?.lowercased(),
                  !host.contains("reddit.com"), !host.contains("redd.it") else { continue }
            return link
        }
        return nil
    }
}
