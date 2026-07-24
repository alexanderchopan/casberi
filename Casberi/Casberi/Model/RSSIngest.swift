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

    /// Rewrites a followed URL once autodiscovery resolves a pasted SITE page
    /// to its real feed — later syncs then fetch the feed directly instead of
    /// re-crawling the homepage every time.
    func setURL(_ url: String, for id: UUID) {
        guard let i = feeds.firstIndex(where: { $0.id == id }),
              feeds[i].url != url,
              // Don't collapse two follows onto the same resolved feed.
              !feeds.contains(where: { $0.url.lowercased() == url.lowercased() })
        else { return }
        feeds[i].url = url
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

    /// One feed's fetch-and-parse outcome — everything the sequential
    /// bookkeeping loop below needs, computed off the main actor.
    private struct Fetched {
        let feed: RSSStore.Feed
        let parsed: FeedParser.Parsed
        /// Set when autodiscovery resolved a pasted SITE to its real feed.
        let resolvedURL: String?
    }

    /// The network fetch and XML parse are both stateless — no reason either
    /// ran serially, one feed at a time, on the main actor (2026-07-13). Only
    /// `FeedDiscovery.find`'s dead-ends cache is main-actor state, and it
    /// stays safe here since the compiler hops back to the main actor for
    /// that specific call.
    private static func fetchAndParse(_ feed: RSSStore.Feed) async -> Fetched? {
        guard let url = URL(string: feed.url) else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        var parsed = FeedParser.parse(data)
        var resolvedURL: String?
        // People paste a SITE, not a feed URL (the field even invites it) —
        // its homepage is HTML, so XML parsing yields no items and nothing
        // ever lands. Autodiscover the feed the page points to (its
        // <link rel="alternate">, then common feed paths) and remember it.
        if parsed.items.isEmpty,
           let (feedURL, discovered) = await FeedDiscovery.find(from: data, site: url) {
            parsed = discovered
            resolvedURL = feedURL.absoluteString
        }
        return Fetched(feed: feed, parsed: parsed, resolvedURL: resolvedURL)
    }

    /// The mark a landed row leads with: the feed's own logo when it
    /// advertises one, else the publisher's favicon derived from the article
    /// host (the feed host as a last resort). First-party only — the bridge's
    /// whole promise is "no server in between", so no third-party favicon
    /// service. A dead URL is fine: `RemoteThumb` degrades to the RSS glyph.
    private static func publisherIcon(feedIcon: String?, link: String, feedURL: String) -> String? {
        if let feedIcon, !feedIcon.isEmpty { return feedIcon }
        let host = URL(string: link)?.host() ?? URL(string: feedURL)?.host()
        guard let host, !host.isEmpty else { return nil }
        return "https://\(host)/favicon.ico"
    }

    @MainActor
    static func refresh(context: ModelContext) async -> Int? {
        let store = RSSStore.shared
        guard !store.feeds.isEmpty, !running else { return running ? 0 : nil }
        running = true
        defer { running = false }

        var existing = IngestSupport.existingSourceRefs(context, source: "RSS")
        let landed = IngestSupport.thingsByRef(context, source: "RSS")
        let backfill = ArtlessBackfill(context, source: "RSS")
        var added = 0
        var touched = false

        // Fetch and parse every followed feed concurrently, then process the
        // results back in feed order (the same ref appearing in two feeds
        // should resolve the same way it always did — first-in-list wins).
        // Only the ModelContext/RSSStore bookkeeping below still runs
        // sequentially. Capped at 8 in flight — feeds are diverse hosts
        // (unlike a single API key), but an unbounded burst still opens more
        // simultaneous connections than any real feed list needs.
        let fetched = await IngestSupport.boundedGather(store.feeds, maxConcurrent: 8) { feed in
            await fetchAndParse(feed)
        }

        var reachedAny = false
        for case let f? in fetched {
            reachedAny = true
            let feed = f.feed
            let parsed = f.parsed
            if let resolvedURL = f.resolvedURL { store.setURL(resolvedURL, for: feed.id) }
            if !parsed.title.isEmpty {
                store.setTitle(parsed.title, for: feed.id)
            }
            // The feed's own logo, resolved once — the same mark rides every
            // item this feed lands (per-item favicon still varies by article
            // host in the fallback path).
            let feedIcon = IngestSupport.imageURL(parsed.iconURL)
            // The publisher's NAME for the row's trailing label — the feed's
            // learned title (BBC News, TechCrunch), the host as a last resort.
            // Rides authorHandle, the same identity slot a Bluesky/Farcaster
            // row names its account in.
            let feedName = parsed.title.isEmpty ? feed.displayName : parsed.title
            // Newest 15 per feed — the feed is a firehose; the corpus isn't.
            for item in parsed.items.prefix(15) {
                let ref = "rss:\(item.guid.isEmpty ? item.link : item.guid)"
                let icon = Self.publisherIcon(feedIcon: feedIcon, link: item.link, feedURL: feed.url)
                if existing.contains(ref) {
                    // An already-landed item still in the feed's window can
                    // hand its lead image to the artless row it became.
                    backfill.patch(ref, image: item.imageURL)
                    // Titles stored before the entity decoder existed keep
                    // their raw "&#8217;" forever unless healed here.
                    if let thing = landed[ref] {
                        let decoded = IngestSupport.decodeHTMLEntities(thing.title)
                        if decoded != thing.title {
                            thing.title = decoded; touched = true
                            thing.embedding = nil   // title changed — re-embed on the next sweep
                        }
                        // Rows that landed before publisher icons existed heal
                        // in place (icon isn't part of the embedding text, so
                        // no re-embed). Only within the feed's window — older
                        // rows keep the RSS glyph, same as image backfill.
                        if (thing.authorAvatarURL ?? "").isEmpty, let icon {
                            thing.authorAvatarURL = icon; touched = true
                        }
                        if (thing.authorHandle ?? "").isEmpty, !feedName.isEmpty {
                            thing.authorHandle = feedName; touched = true
                        }
                    }
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
                // The publisher's own abstract (2026-07-22) — display copy,
                // so the sheet reads like a reader instead of a bare link.
                if !item.summary.isEmpty { thing.summary = item.summary }
                // The publisher's mark leads the row (like a post's author
                // avatar) — the article image, when there is one, rides after
                // the title instead of the leading slot — and its NAME rides
                // the trailing label.
                thing.authorAvatarURL = icon
                if !feedName.isEmpty { thing.authorHandle = feedName }
                context.insert(thing)
                existing.insert(ref)
                SpotlightIndex.index([thing])
                added += 1
            }
        }
        if added > 0 || backfill.any || touched { context.saveHonestly() }
        // Every feed unreachable is a failed sync, not "up to date".
        return reachedAny ? added : nil
    }
}

// MARK: - Autodiscovery (a pasted site → its feed)

/// Turns a followed SITE page into the feed it advertises. Two passes, cheapest
/// first: the page's own declared `<link rel="alternate" type="…rss/atom…">`,
/// then the handful of conventional feed paths off the site root. Only ever
/// runs for a followed URL that returned no items — a real feed URL pays
/// nothing here.
enum FeedDiscovery {

    /// Site URLs already crawled to no feed this session — a misconfigured
    /// follow (a page that advertises no feed and answers no common path)
    /// would otherwise re-run the whole probe storm on every screen visit and
    /// app foreground, since a no-items parse re-triggers discovery each time.
    @MainActor private static var deadEnds: Set<String> = []

    /// Returns the resolved feed URL and its parsed contents, or nil when the
    /// page advertises no feed and none of the common paths answer with one.
    @MainActor
    static func find(from data: Data, site: URL) async -> (URL, FeedParser.Parsed)? {
        if deadEnds.contains(site.absoluteString) { return nil }
        // 1) The page's own declared feed links, XML types first (FeedParser
        // is RSS/Atom only — a JSON Feed link would fetch and fail to parse,
        // so trying just the first declared link would strand a site that
        // lists a JSON or comments feed ahead of its real RSS one).
        if let html = String(data: data, encoding: .utf8) {
            for href in declaredFeedHrefs(in: html) {
                guard let url = URL(string: href, relativeTo: site)?.absoluteURL,
                      let parsed = await fetch(url), !parsed.items.isEmpty else { continue }
                return (url, parsed)
            }
        }
        // 2) Conventional paths off the site root (WordPress, Ghost, Hugo, …).
        if let scheme = site.scheme, let host = site.host() {
            let root = "\(scheme)://\(host)"
            for path in ["/feed", "/rss", "/feed.xml", "/rss.xml",
                         "/atom.xml", "/index.xml", "/feed/"] {
                guard let url = URL(string: root + path) else { continue }
                if let parsed = await fetch(url), !parsed.items.isEmpty {
                    return (url, parsed)
                }
            }
        }
        deadEnds.insert(site.absoluteString)
        return nil
    }

    private static func fetch(_ url: URL) async -> FeedParser.Parsed? {
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return FeedParser.parse(data)
    }

    private static let linkTag = try? NSRegularExpression(
        pattern: "<link[^>]+>", options: [.caseInsensitive])

    /// The hrefs of every `<link rel="alternate">` whose type is a feed — RSS
    /// and Atom first (the two FeedParser can read), any JSON Feed last as a
    /// long shot. Attribute order varies wildly across sites, so each tag is
    /// matched whole, then its attributes pulled out by name.
    private static func declaredFeedHrefs(in html: String) -> [String] {
        guard let linkTag else { return [] }
        // The head carries the feed links; scanning it alone keeps a huge body
        // from being walked (and avoids in-article <link>s).
        let head = html.range(of: "</head>", options: .caseInsensitive)
            .map { String(html[..<$0.lowerBound]) } ?? html
        let ns = head as NSString
        var xml: [String] = []
        var json: [String] = []
        for m in linkTag.matches(in: head, range: NSRange(location: 0, length: ns.length)) {
            // Read href off the ORIGINAL-case tag so the URL keeps its case.
            let original = ns.substring(with: m.range)
            let tag = original.lowercased()
            let isXML = tag.contains("application/rss+xml") || tag.contains("application/atom+xml")
            let isJSON = tag.contains("application/feed+json")
                || (tag.contains("application/json") && tag.contains("feed"))
            guard isXML || isJSON, let href = attribute("href", in: original) else { continue }
            if isXML { xml.append(href) } else { json.append(href) }
        }
        return xml + json
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        guard let re = try? NSRegularExpression(
            pattern: "\(name)\\s*=\\s*[\"']([^\"']+)[\"']", options: [.caseInsensitive])
        else { return nil }
        let ns = tag as NSString
        guard let m = re.firstMatch(in: tag, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > 1 else { return nil }
        return ns.substring(with: m.range(at: 1))
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
        /// The item's own abstract, tags stripped (2026-07-22) — the words a
        /// feed reader shows under the headline. Empty when the feed carries
        /// none (or carries only markup, e.g. an image-only Pinterest item).
        var summary = ""
    }

    struct Parsed {
        var title = ""
        /// The feed's OWN mark — the publisher's logo (Reuters, a blog), from
        /// the RSS `<channel><image><url>`, an `<itunes:image>`, or an Atom
        /// `<icon>`/`<logo>`. Empty when the feed advertises none; the ingest
        /// then falls back to the site's favicon. This is publisher identity,
        /// distinct from a per-item lead image (`Item.imageURL`).
        var iconURL = ""
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
            // The feed's OWN mark rides an href attribute in the iTunes and
            // (rarely) Media namespaces — captured only at channel level
            // (current == nil), so per-EPISODE art never becomes the
            // publisher icon.
            case "itunes:image", "media:image":
                if current == nil, result.iconURL.isEmpty, let href = attributes["href"] {
                    result.iconURL = Self.normalizeImage(href)
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
                // The publisher's mark: RSS nests it as <channel><image><url>
                // (a plain <url> element, guarded by the enclosing <image> so
                // an item enclosure can't stand in); Atom carries it as a
                // top-level <icon> or <logo>. Channel context only.
                if result.iconURL.isEmpty {
                    if name == "url", elementPath.contains("image") {
                        result.iconURL = Self.normalizeImage(value)
                    } else if name == "icon" || name == "logo" {
                        result.iconURL = Self.normalizeImage(value)
                    }
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
                // …and keep the WORDS too (2026-07-22). Until now this blob
                // was mined for an image and thrown away, so every RSS,
                // Reddit, YouTube, Substack, and Podcast thing landed with no
                // body at all — its sheet re-fetched a link preview to show
                // what the feed had already handed us. Publisher-authored, so
                // it's display copy (`Thing.summary`), not `enrichedText`.
                //
                // Keep the LONGEST candidate: a feed often carries both a
                // short `<description>` and a full `<content:encoded>`, in
                // either order, and the fuller one is the better read.
                if let text = Self.plainText(fromFeedHTML: value),
                   text.count > (current?.summary.count ?? 0) {
                    current?.summary = text
                }
            case "item", "entry":
                if let item = current { result.items.append(item) }
                current = nil
            default:
                break
            }
        }

        /// Feed HTML → readable prose, or nil when nothing legible survives.
        /// Strips tags (a feed's summary is usually a wrapped `<p>`, and a
        /// full `content:encoded` is a whole article's markup), decodes the
        /// entities that leaves behind, and collapses the whitespace the tags
        /// stood in for. Clamped to 600 characters: this is an abstract under
        /// a headline, not an offline copy of the article — and the sheet
        /// still offers the real link.
        static func plainText(fromFeedHTML html: String) -> String? {
            var s = html.replacingOccurrences(of: "<[^>]+>", with: " ",
                                              options: .regularExpression)
            s = IngestSupport.decodeHTMLEntities(s)
            s = s.replacingOccurrences(of: "\\s+", with: " ",
                                       options: .regularExpression)
            s = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard s.count >= 20 else { return nil }   // markup scraps, not prose
            guard s.count > 600 else { return s }
            // Cut on a word boundary so the clamp doesn't split a word.
            let cut = s.prefix(600)
            let end = cut.lastIndex(of: " ").map { cut[..<$0] } ?? cut
            return String(end) + "…"
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
