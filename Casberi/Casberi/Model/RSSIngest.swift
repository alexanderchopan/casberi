import Foundation
import Observation
import SwiftData

/// The RSS bridge (2026-07-07) — the fifth real connectable, and the first
/// that reaches OUTSIDE the phone: any site with a feed, fetched directly by
/// the app. No account, no server, no algorithm in between. This bridge
/// establishes the remote-ingest pattern (fetch → parse → dedupe → things)
/// that Bluesky and the token bridges reuse.

// MARK: - The person's feed list

@Observable
final class RSSStore {
    static let shared = RSSStore()
    private static let key = "rss.feeds"

    struct Feed: Codable, Identifiable, Equatable {
        var id = UUID()
        var url: String
        /// The feed's own title, learned on first successful fetch.
        var title: String = ""

        var displayName: String {
            if !title.isEmpty { return title }
            return URL(string: url)?.host()?.replacingOccurrences(of: "www.", with: "") ?? url
        }
    }

    var feeds: [Feed] {
        didSet { persist() }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([Feed].self, from: data) {
            feeds = saved
        } else {
            feeds = []
        }
    }

    /// Adds a pasted URL. Scheme-forgiving — people paste bare domains.
    @discardableResult
    func add(_ raw: String) -> Bool {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        if !text.contains("://") { text = "https://" + text }
        guard URL(string: text) != nil,
              !feeds.contains(where: { $0.url.lowercased() == text.lowercased() })
        else { return false }
        feeds.append(Feed(url: text))
        return true
    }

    func remove(at offsets: IndexSet) {
        feeds.remove(atOffsets: offsets)
    }

    func setTitle(_ title: String, for id: UUID) {
        guard let i = feeds.firstIndex(where: { $0.id == id }),
              feeds[i].title != title else { return }
        feeds[i].title = title
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(feeds) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}

// MARK: - Ingest

enum RSSIngest {

    /// Fetches every feed and lands new posts as link things. Returns the
    /// number of NEW things. Safe to call repeatedly — posts dedupe on their
    /// guid (falling back to the link).
    /// Serializes refreshes — two concurrent runs both read "existing"
    /// before either saves and double-insert (seen live: the launch hook
    /// racing the foreground refresh). Overlapping calls bail.
    @MainActor private static var running = false

    @MainActor
    static func refresh(context: ModelContext) async -> Int? {
        let store = RSSStore.shared
        guard !store.feeds.isEmpty, !running else { return running ? 0 : nil }
        running = true
        defer { running = false }
        var reachedAny = false

        var existing = IngestSupport.existingSourceRefs(context)
        var added = 0

        for feed in store.feeds {
            guard let url = URL(string: feed.url) else { continue }
            guard let (data, _) = try? await URLSession.shared.data(from: url) else { continue }
            reachedAny = true
            let parsed = FeedParser.parse(data)
            if !parsed.title.isEmpty {
                store.setTitle(parsed.title, for: feed.id)
            }
            // Newest 15 per feed — the feed is a firehose; the corpus isn't.
            for item in parsed.items.prefix(15) {
                let ref = "rss:\(item.guid.isEmpty ? item.link : item.guid)"
                guard !existing.contains(ref), !item.title.isEmpty else { continue }
                let thing = Thing(
                    kind: .link,
                    title: item.title,
                    content: item.link,
                    source: "RSS",
                    capturedAt: item.date ?? .now,
                    sourceRef: ref
                )
                context.insert(thing)
                existing.insert(ref)
                SpotlightIndex.index([thing])
                added += 1
            }
        }
        if added > 0 { try? context.save() }
        // Every feed unreachable is a failed sync, not "up to date".
        return reachedAny ? added : nil
    }
}

// MARK: - Parser (RSS 2.0 + Atom, the two that matter)

enum FeedParser {
    struct Item {
        var title = ""
        var link = ""
        var guid = ""
        var date: Date?
    }

    struct Parsed {
        var title = ""
        var items: [Item] = []
    }

    static func parse(_ data: Data) -> Parsed {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.result
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var result = Parsed()
        private var current: Item?
        private var text = ""
        private var inChannelTitle = false
        private var elementPath: [String] = []

        private static let rfc822: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
            return f
        }()
        private static let iso = ISO8601DateFormatter()

        func parser(_ parser: XMLParser, didStartElement name: String,
                    namespaceURI: String?, qualifiedName: String?,
                    attributes: [String: String] = [:]) {
            elementPath.append(name)
            text = ""
            switch name {
            case "item", "entry":
                current = Item()
            case "link" where current != nil:
                // Atom links ride an attribute, not text.
                if let href = attributes["href"],
                   attributes["rel"] == nil || attributes["rel"] == "alternate" {
                    current?.link = href
                }
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            text += string
        }

        func parser(_ parser: XMLParser, didEndElement name: String,
                    namespaceURI: String?, qualifiedName: String?) {
            defer { elementPath.removeLast() }
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if current == nil {
                // Channel/feed metadata — only the title, and only at depth
                // (channel|feed) > title so item titles don't overwrite it.
                if name == "title", result.title.isEmpty,
                   elementPath.count <= 3 {
                    result.title = value
                }
                return
            }
            switch name {
            case "title":
                if current?.title.isEmpty == true { current?.title = value }
            case "link":
                if current?.link.isEmpty == true { current?.link = value }
            case "guid", "id":
                current?.guid = value
            case "pubDate", "published", "updated":
                if current?.date == nil {
                    current?.date = Self.rfc822.date(from: value) ?? Self.iso.date(from: value)
                }
            case "item", "entry":
                if let item = current { result.items.append(item) }
                current = nil
            default:
                break
            }
        }
    }
}
