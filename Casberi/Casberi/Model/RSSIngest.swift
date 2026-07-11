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
        let backfill = ArtlessBackfill(context, source: "RSS")
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
                if existing.contains(ref) {
                    // An already-landed item still in the feed's window can
                    // hand its lead image to the artless row it became.
                    backfill.patch(ref, image: item.imageURL)
                    continue
                }
                guard !item.title.isEmpty else { continue }
                let thing = Thing(
                    kind: .link,
                    title: IngestSupport.decodeHTMLEntities(item.title),
                    content: item.link,
                    source: "RSS",
                    capturedAt: item.date ?? .now,
                    sourceRef: ref
                )
                // The item's lead image — the parser already pulls Media RSS
                // thumbnails, enclosures, and the first inline <img>; only
                // PinterestIngest was using it (fixed 2026-07-10).
                thing.previewImageURL = IngestSupport.imageURL(item.imageURL)
                context.insert(thing)
                existing.insert(ref)
                SpotlightIndex.index([thing])
                added += 1
            }
        }
        if added > 0 || backfill.any { try? context.save() }
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
        /// A lead image when the feed carries one (Media RSS, an enclosure, or
        /// the first <img> in the description) — used for the Pinterest row
        /// thumbnail. Empty when the feed has no image.
        var imageURL = ""
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
            // Image in an attribute: a Media RSS content/thumbnail or an
            // enclosure. media:thumbnail is always an image; the others only
            // when they say so (or say nothing, as Pinterest's media does).
            case "media:thumbnail", "media:content", "enclosure":
                // Only lands on an item (the inner guard) — a channel-level
                // image never becomes a row's thumbnail.
                if current?.imageURL.isEmpty == true, let u = attributes["url"] {
                    let type = attributes["type"] ?? ""
                    let medium = attributes["medium"] ?? ""
                    let isImage = name == "media:thumbnail"
                        || type.hasPrefix("image") || medium == "image"
                        || (name == "media:content" && type.isEmpty && medium.isEmpty)
                    if isImage { current?.imageURL = Self.normalizeImage(u) }
                }
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            text += string
        }

        // Pinterest (and many feeds) wrap the description HTML in CDATA, which
        // arrives here, not through foundCharacters — accumulate it so the
        // <img> extraction below can see it.
        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            text += String(data: CDATABlock, encoding: .utf8) ?? ""
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
            case "description", "content:encoded", "summary", "content":
                // No attribute image yet — pull the first <img> out of the
                // (usually CDATA) description HTML. This is Pinterest's path.
                if current?.imageURL.isEmpty == true,
                   let src = Self.firstImageSrc(in: value),
                   !Self.looksLikeTracker(src) {
                    current?.imageURL = Self.normalizeImage(src)
                }
            case "item", "entry":
                if let item = current { result.items.append(item) }
                current = nil
            default:
                break
            }
        }

        /// First `<img src>` in a blob of feed HTML, or nil. Compiled once.
        private static let imgRegex = try? NSRegularExpression(
            pattern: #"<img[^>]+src=[\"']([^\"']+)[\"']"#, options: [.caseInsensitive])

        private static func firstImageSrc(in html: String) -> String? {
            guard let imgRegex else { return nil }
            let range = NSRange(html.startIndex..., in: html)
            guard let m = imgRegex.firstMatch(in: html, range: range),
                  m.numberOfRanges > 1,
                  let r = Range(m.range(at: 1), in: html) else { return nil }
            return String(html[r])
        }

        /// Protocol-relative URLs (`//host/…`) become https so AsyncImage loads.
        private static func normalizeImage(_ url: String) -> String {
            url.hasPrefix("//") ? "https:" + url : url
        }

        /// The first <img> of general feed HTML is sometimes a 1×1 beacon or
        /// badge, not the article's lead image — the obvious ones never
        /// become a row's thumbnail (added when the imageURL went from
        /// Pinterest-only to every feed, 2026-07-10).
        private static func looksLikeTracker(_ src: String) -> Bool {
            // Whole path SEGMENTS only — a substring match ate real images
            // ("google-pixel-10-hero.jpg" contains "pixel"; review 2026-07-10).
            let path = (URL(string: src)?.path ?? src).lowercased()
            let segments = path.split(separator: "/").map(String.init)
            let markers: Set<String> = ["pixel", "pixels", "1x1", "spacer",
                                        "beacon", "track", "tracking", "tracker"]
            if segments.contains(where: markers.contains) { return true }
            // Tracker FILENAMES: "pixel.gif", "1x1.png", "spacer.gif".
            if let file = segments.last?.split(separator: ".").first,
               markers.contains(String(file)) { return true }
            return false
        }
    }
}
