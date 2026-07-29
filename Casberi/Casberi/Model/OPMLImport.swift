import Foundation
import Observation

/// OPML import/export — a bulk on-ramp (and off-ramp) for the RSS bridge
/// (2026-07-28). OPML is just a list of feed URLs, the standard format every
/// other reader (Feedly, NetNewsWire, Reeder, Inoreader) writes when a person
/// migrates in or out — not a new source, so it's a second way to fill
/// `RSSStore.feeds`, not a catalog offer of its own.
enum OPMLImport {
    struct Feed: Equatable {
        let title: String
        let url: String
        var displayName: String {
            title.isEmpty ? (URL(string: url)?.host()?.replacingOccurrences(of: "www.", with: "") ?? url) : title
        }
    }

    /// One `<outline>` folder's feeds — real OPML nesting (Feedly-style
    /// categories) collapses to the feed's IMMEDIATE enclosing folder; deeper
    /// hierarchy isn't a distinction `RSSStore.feeds` can carry (prd §184: no
    /// tiers or toggles), and every real export this was checked against
    /// (NetNewsWire, Reeder, Feedly) nests one level deep anyway.
    struct Group: Equatable {
        let name: String   // "" = not inside any named folder
        var feeds: [Feed]
    }

    struct Parsed {
        var groups: [Group]
        var allFeeds: [Feed] { groups.flatMap(\.feeds) }
        /// Named folders only — a flat export (every feed at "") has none,
        /// and the screen offers just one scope: everything in the file.
        var namedGroups: [Group] { groups.filter { !$0.name.isEmpty } }
    }

    struct Summary {
        var added = 0
        var skipped = 0
        var failed = false
    }

    /// Parses without landing anything — picking a file previews what's in
    /// it (the Bookmarks two-phase pattern) before a single feed is
    /// followed. nil when the file carries no `<outline>` at all (not an
    /// OPML export), and nil when the XML itself is malformed: a truncated
    /// file parses to a PREFIX of its feeds, and previewing that prefix as
    /// the whole file would silently drop the rest.
    static func parse(data: Data) -> Parsed? {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse(), delegate.sawOutline else { return nil }
        return Parsed(groups: delegate.groups)
    }

    /// Lands the chosen feeds through the exact path a pasted URL takes —
    /// `RSSStore.add` already validates the scheme and dedupes against the
    /// person's current follows, so re-importing the same file (or two
    /// files sharing a feed) only ever adds what's new. The OPML file's own
    /// title lands with it, so a row reads with its real name immediately
    /// instead of waiting for the first fetch to learn it.
    static func land(_ feeds: [Feed]) -> Summary {
        var summary = Summary()
        for feed in feeds {
            if RSSStore.shared.add(feed.url, title: feed.title) {
                summary.added += 1
            } else {
                summary.skipped += 1
            }
        }
        return summary
    }

    /// The other half of the bridge: the person's current follows as a
    /// standard OPML 2.0 document, so leaving Casberi never means retyping
    /// every feed by hand into whatever reader comes next.
    static func export(_ feeds: [RSSStore.Feed]) -> Data {
        let items = feeds.map { feed -> String in
            let name = xmlEscape(feed.title.isEmpty ? feed.displayName : feed.title)
            let url = xmlEscape(feed.url)
            return "    <outline text=\"\(name)\" title=\"\(name)\" type=\"rss\" xmlUrl=\"\(url)\"/>"
        }.joined(separator: "\n")
        return Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
        <head><title>Casberi feeds</title></head>
        <body>
        \(items)
        </body>
        </opml>
        """.utf8)
    }

    private static func xmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "\"", with: "&quot;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var sawOutline = false
        private var folderStack: [String] = []
        private(set) var groups: [Group] = []
        private var groupIndex: [String: Int] = [:]

        func parser(_ parser: XMLParser, didStartElement name: String,
                    namespaceURI: String?, qualifiedName: String?,
                    attributes: [String: String] = [:]) {
            guard name == "outline" else { return }
            sawOutline = true
            let label = (attributes["title"] ?? attributes["text"] ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let xmlUrl = attributes["xmlUrl"]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !xmlUrl.isEmpty {
                let groupName = folderStack.last ?? ""
                let feed = Feed(title: label, url: xmlUrl)
                if let idx = groupIndex[groupName] {
                    groups[idx].feeds.append(feed)
                } else {
                    groupIndex[groupName] = groups.count
                    groups.append(Group(name: groupName, feeds: [feed]))
                }
            }
            // Every outline — feed or folder — pushes its own label so
            // didEndElement pops in step; a feed's own frame is never read
            // by anything (a feed has no children in a real file), so what
            // it carries doesn't matter, only that the stack stays balanced.
            folderStack.append(label)
        }

        func parser(_ parser: XMLParser, didEndElement name: String,
                    namespaceURI: String?, qualifiedName: String?) {
            guard name == "outline", !folderStack.isEmpty else { return }
            folderStack.removeLast()
        }
    }
}

/// A file handed to the app via AirDrop / Share Sheet ("Open in Casberi")
/// before RSSScreen exists to receive it — `RootShell`'s `onOpenURL` sets
/// this and raises the RSS sheet; RSSScreen consumes it once mounted (the
/// sheet's own view doesn't exist yet at the moment the URL arrives, so it
/// can't just be handed the URL directly).
@Observable
final class PendingOPMLFile {
    static let shared = PendingOPMLFile()
    var url: URL?
    private init() {}
}
