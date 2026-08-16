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

    /// A pasted string as it would be FOLLOWED, or nil when it isn't an
    /// address at all. Scheme-forgiving — people paste bare domains.
    ///
    /// Split out of `add` (2026-08-16) so a caller can tell the two ways a
    /// follow gets refused apart. They read identically from `add`'s `Bool`,
    /// and the screen showed nothing for either, so a typo and a feed already
    /// in the list both landed as a FOLLOW button that did precisely nothing.
    func normalized(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }
        // `URL(string:)` is RFC 3986-strict on iOS 17+, so a pasted address
        // carrying a space or a stray character is nil here rather than a URL
        // that fails later.
        guard let url = URL(string: text), url.host()?.isEmpty == false else { return nil }
        return text
    }

    func isFollowing(_ raw: String) -> Bool {
        guard let text = normalized(raw) else { return false }
        return feeds.contains { $0.url.lowercased() == text.lowercased() }
    }

    /// Adds a pasted URL. `title` carries a name already known at add time (an
    /// OPML file's own `text`/`title` attribute) so a row reads right away
    /// instead of waiting on the first fetch to learn the feed's name.
    @discardableResult
    func add(_ raw: String, title: String = "") -> Bool {
        guard let text = normalized(raw),
              !feeds.contains(where: { $0.url.lowercased() == text.lowercased() })
        else { return false }
        feeds.append(Feed(url: text, title: title.trimmingCharacters(in: .whitespacesAndNewlines)))
        return true
    }

    func remove(at offsets: IndexSet) {
        // Drop the feed's HTTP record with the follow itself (2026-08-05), so
        // re-following a URL that had been failing starts clean instead of
        // inheriting the streak the person just removed it over.
        for i in offsets where feeds.indices.contains(i) { FeedFreshness.forget(feeds[i].url) }
        feeds.remove(atOffsets: offsets)
    }

    /// Disconnect. Assigning `feeds = []` directly would leave every feed's
    /// HTTP record behind, so the one caller that used to do that goes
    /// through here (2026-08-05).
    func removeAll() {
        for feed in feeds { FeedFreshness.forget(feed.url) }
        feeds = []
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

    /// How long a caller that asked to WAIT will wait for the pass in flight
    /// before giving up, and how often it looks. Bounded so a wedged pass can
    /// never wedge its caller too.
    private static let waitPoll: Duration = .milliseconds(150)
    private static let waitLimit: TimeInterval = 8

    /// One feed's fetch-and-parse outcome — everything the sequential
    /// bookkeeping loop below needs, computed off the main actor.
    private struct Fetched {
        let feed: RSSStore.Feed
        /// nil when the publisher answered 304 — the feed was REACHED and has
        /// nothing new, which is a different fact from a fetch that failed
        /// (that returns no `Fetched` at all). Nothing to parse, nothing to
        /// land, and nothing to heal from either: a body we already saw can't
        /// carry a field we didn't store last time.
        let parsed: FeedParser.Parsed?
        /// Set when autodiscovery resolved a pasted SITE to its real feed.
        let resolvedURL: String?
        /// The address answered, and there is no feed at it — not a failure
        /// (nothing went wrong on the wire) and not a success (nothing can
        /// ever land). Carried out separately because every OTHER signal this
        /// struct has reads as healthy for exactly this case.
        let noFeed: Bool
    }

    /// The network fetch and XML parse are both stateless — no reason either
    /// ran serially, one feed at a time, on the main actor (2026-07-13). Only
    /// `FeedDiscovery.find`'s dead-ends cache is main-actor state, and it
    /// stays safe here since the compiler hops back to the main actor for
    /// that specific call.
    private static func fetchAndParse(_ feed: RSSStore.Feed) async -> Fetched? {
        guard let url = URL(string: feed.url) else { return nil }
        // Conditional GET, and the feed's own health, both live in
        // `FeedFreshness` (2026-08-05) — which also attributes the host to
        // "RSS" for the receipts screen. A feed URL is whatever the person
        // pasted, so it can never be in the reach registry (prd §205 lists
        // "the feeds you follow") and the call site has to name the service
        // itself (prd §289).
        let outcome = await FeedFreshness.fetch(url, as: "RSS")
        let data: Data
        switch outcome {
        case .fresh(let body):
            data = body
        case .notModified:
            // Reached, unchanged. Not a failure, and not a parse.
            return Fetched(feed: feed, parsed: nil, resolvedURL: nil, noFeed: false)
        case .failed:
            return nil
        }
        var parsed = FeedParser.parse(data)
        var resolvedURL: String?
        var noFeed = false
        // People paste a SITE, not a feed URL (the field even invites it) —
        // its homepage is HTML, so there is nothing to land. Autodiscover the
        // feed the page points to (its <link rel="alternate">, then common
        // feed paths) and remember it.
        //
        // Gated on the body not being a feed DOCUMENT rather than on it
        // carrying no items (2026-08-16) — see `Parsed.isFeed`. A real feed
        // that happens to be empty no longer sends a crawl off its host on
        // every pass, and a page that is not a feed is now SAID so instead of
        // sitting in the list looking healthy forever.
        if !parsed.isFeed {
            if let (feedURL, discovered) = await FeedDiscovery.find(from: data, site: url) {
                parsed = discovered
                resolvedURL = feedURL.absoluteString
            } else {
                noFeed = FeedFreshness.noFeedFound(at: feed.url)
            }
        } else {
            // It is a feed today. Clear any verdict from back when it wasn't,
            // so a site that has since added one is picked up by this ordinary
            // fetch rather than by waiting out `noFeedRecheckAfter`.
            FeedFreshness.noteFeedFound(feed.url)
        }
        return Fetched(feed: feed, parsed: parsed, resolvedURL: resolvedURL, noFeed: noFeed)
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

    /// `waitForInFlight` is for a pass the PERSON asked for — following a new
    /// feed. Dropping an overlapping call is right for the periodic sweep (the
    /// next one is minutes away and nothing is waiting on it) and wrong for a
    /// tap: a feed followed while any other pass happened to be mid-flight was
    /// simply never fetched, so its posts didn't appear and the screen said
    /// "Up to date" about a feed it had not read. That is one half of "I can
    /// add two feeds and then it stops working" — the other half is how long a
    /// pass could take, which `FeedDiscovery`'s budget now bounds.
    @MainActor
    static func refresh(context: ModelContext, waitForInFlight: Bool = false) async -> Int? {
        let store = RSSStore.shared
        guard !store.feeds.isEmpty else { return nil }
        if running {
            guard waitForInFlight else { return 0 }
            let until = Date().addingTimeInterval(waitLimit)
            while running, Date() < until {
                try? await Task.sleep(for: waitPoll)
            }
            // Still going after the limit — the in-flight pass covers most of
            // what ours would do anyway, so report it rather than run a second
            // one alongside and re-open the double-insert race this guards.
            if running { return 0 }
        }
        running = true
        defer { running = false }

        // `landed`'s keys already ARE every existing ref for this source — a
        // separate `existingSourceRefs` call used to re-fetch the exact same
        // rows a second time just for their sourceRef column (perf,
        // 2026-07-28), doubling the DB round trip for no new information.
        let landed = IngestSupport.thingsByRef(context, source: "RSS")
        var existing = Set(landed.keys)
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
            // Answered, and publishes nothing to follow. The row says so
            // (`FeedFreshness.trouble`); there is no body to land or heal from.
            if f.noFeed { continue }
            // A 304 — the publisher answered and nothing changed. Counted as
            // reached above (a sync that got five 304s is up to date, not
            // offline), then skipped: there is no body to land or heal from.
            guard let parsed = f.parsed else { continue }
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
                // An item with neither a <guid> nor a <link> has nothing to key
                // on, and the bare "rss:" it used to mint collided EVERY such
                // item onto one row — each pass overwriting the last. The
                // feed-follow path has always guarded this; this one never did.
                let key = item.guid.isEmpty ? item.link : item.guid
                if key.isEmpty { continue }
                let ref = "rss:\(key)"
                let icon = Self.publisherIcon(feedIcon: feedIcon, link: item.link, feedURL: feed.url)
                // A podcast episode often carries only a <guid> and its audio
                // enclosure — no <link> at all — and landed with an empty
                // `content`, i.e. a row nothing could open. The audio file IS
                // the episode, so it stands in (2026-08-06).
                let openURL = item.link.isEmpty ? item.mediaURL : item.link
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
                        // Rows that landed before the fields below existed
                        // heal in place, within the feed's window — same bar
                        // as the icon and image backfills above.
                        if thing.content.isEmpty, !openURL.isEmpty {
                            thing.content = openURL; touched = true
                        }
                        if (thing.externalLink ?? "").isEmpty, !item.mediaURL.isEmpty {
                            thing.externalLink = item.mediaURL; touched = true
                        }
                        if thing.postAuthor == nil,
                           let author = FeedParser.author(item.author, feedName: feedName) {
                            thing.postAuthor = author; touched = true
                        }
                        // Appended, never assigned — a row's other tags (its
                        // type tag, a project's) are not this feed's to drop.
                        for tag in item.categories
                        where !thing.tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
                            thing.tags.append(tag); touched = true
                        }
                    }
                    continue
                }
                guard !item.title.isEmpty else { continue }
                let thing = Thing(
                    kind: .link,
                    title: IngestSupport.decodeHTMLEntities(item.title),
                    content: openURL,
                    source: "RSS",
                    capturedAt: item.date ?? .now,
                    tags: item.categories,
                    sourceRef: ref
                )
                // The item's lead image — the parser already pulls Media RSS
                // thumbnails, image enclosures, a per-episode `<itunes:image>`
                // and the first inline <img>; only PinterestIngest was using
                // it (fixed 2026-07-10).
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
                // The person who wrote it, when the feed names someone other
                // than itself (`FeedParser.author`) — a multi-author
                // publication used to collapse onto its own name, since
                // `authorHandle` is the feed's identity, not a writer's.
                if let author = FeedParser.author(item.author, feedName: feedName) {
                    thing.postAuthor = author
                }
                // The episode's own audio, when the feed declares one. Kept
                // whether or not it stood in for `content` above: the row's
                // bytes are its link, this is the media file itself.
                if !item.mediaURL.isEmpty { thing.externalLink = item.mediaURL }
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
    /// The DURABLE half of the same fact lives in `FeedFreshness.noFeedAt`
    /// (2026-08-16) — this set alone was per-launch, so every cold start paid
    /// the whole crawl again for a follow that had already been proved dead.
    @MainActor private static var deadEnds: Set<String> = []

    /// How long one speculative probe may go silent. Deliberately far tighter
    /// than `FeedFreshness`'s own fetch timeout: that one is the feed the
    /// person actually asked for and is worth waiting on, these are guesses.
    private static let probeTimeout: TimeInterval = 8

    /// The most wall-clock ONE site's crawl may spend, across every candidate.
    ///
    /// The per-request timeout alone does not bound this: there are up to
    /// eight candidates and they are tried IN ORDER, so a host that stalls
    /// every connection costs eight timeouts back to back. `RSSIngest.running`
    /// and the RSS screen's own `syncing` flag are both held for that whole
    /// stretch, which is what turned a slow site into a bridge that looked
    /// frozen and silently dropped every feed followed in the meantime.
    private static let crawlBudget: TimeInterval = 20

    /// Conventional feed paths off a site root (WordPress, Ghost, Hugo, …).
    private static let commonPaths = ["/feed", "/rss", "/feed.xml", "/rss.xml",
                                      "/atom.xml", "/index.xml", "/feed/"]

    /// Returns the resolved feed URL and its parsed contents, or nil when the
    /// page advertises no feed and none of the common paths answer with one.
    @MainActor
    static func find(from data: Data, site: URL) async -> (URL, FeedParser.Parsed)? {
        let key = site.absoluteString
        if deadEnds.contains(key) { return nil }
        if FeedFreshness.noFeedFound(at: key) {
            // Proved dead on an earlier launch. Mirror it into this session's
            // set so the store isn't asked again for every feed, every pass.
            deadEnds.insert(key)
            return nil
        }
        let deadline = Date().addingTimeInterval(crawlBudget)
        /// True when the budget cut the crawl short — we stopped looking
        /// rather than finished looking, so nothing may be concluded.
        var ranOut = false

        // 1) The page's own declared feed links, XML types first (FeedParser
        // is RSS/Atom only — a JSON Feed link would fetch and fail to parse,
        // so trying just the first declared link would strand a site that
        // lists a JSON or comments feed ahead of its real RSS one).
        if let html = String(data: data, encoding: .utf8) {
            for href in declaredFeedHrefs(in: html) {
                if Date() >= deadline { ranOut = true; break }
                guard let url = URL(string: href, relativeTo: site)?.absoluteURL,
                      let parsed = await fetch(url), parsed.isFeed else { continue }
                FeedFreshness.noteFeedFound(key)
                return (url, parsed)
            }
        }
        // 2) Conventional paths off the site root.
        if !ranOut, let scheme = site.scheme, let host = site.host() {
            let root = "\(scheme)://\(host)"
            for path in commonPaths {
                if Date() >= deadline { ranOut = true; break }
                guard let url = URL(string: root + path) else { continue }
                if let parsed = await fetch(url), parsed.isFeed {
                    FeedFreshness.noteFeedFound(key)
                    return (url, parsed)
                }
            }
        }
        // Only a crawl that RAN OUT of candidates has proved anything. One
        // that ran out of time has not, and must not put a week of silence on
        // an address that may well publish a feed — nor even this session's
        // silence, so it isn't filed as a dead end either.
        if !ranOut {
            deadEnds.insert(key)
            FeedFreshness.noteNoFeed(key)
        }
        return nil
    }

    /// One speculative probe. A candidate is adopted only when it answers with
    /// a feed DOCUMENT (`Parsed.isFeed`) — the check used to be "did it parse
    /// any items", which a site that answers 200 for every path (a soft 404,
    /// which every SPA-routed site is) satisfies by accident on neither side:
    /// it never yields items, so all seven candidates were tried and all seven
    /// downloaded in full.
    private static func fetch(_ url: URL) async -> FeedParser.Parsed? {
        var request = URLRequest(url: url)
        request.timeoutInterval = probeTimeout
        request.setValue(FeedFreshness.userAgent, forHTTPHeaderField: "User-Agent")
        NetworkLedger.shared.record(url, as: "RSS")
        guard let (data, response) = try? await URLSession.shared.data(for: request) else { return nil }
        // A soft 404 answers 200, so the status is not enough on its own — but
        // a hard one is free to reject before parsing a page.
        if let http = response as? HTTPURLResponse,
           !(200..<300).contains(http.statusCode) { return nil }
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
        /// A YouTube entry's `<media:community><media:statistics views="…">`
        /// (2026-07-28) — a per-VIDEO view count, not carried by any other
        /// feed this app follows. nil when the feed doesn't report one.
        var viewCount: Int?
        /// The entry's own author — an Atom `<author><name>` or the
        /// `<dc:creator>` most RSS 2.0 publishers use. A channel's own name on
        /// YouTube (the same name the feed title carries), a poster's
        /// `/u/name` on Reddit, the WRITER on a multi-author Substack (the one
        /// thing FeedFollowKind's generic authorHandle-as-feed-identity can't
        /// carry). Lands on `Thing.postAuthor` through `FeedParser.author`,
        /// which drops the ones that only repeat the feed's own name. Empty
        /// when absent.
        var author = ""
        /// The item's own media enclosure — a podcast episode's audio (or
        /// video) file. Never an image: an image enclosure lands on `imageURL`
        /// above, and the two are read for different things. Empty when the
        /// item declares none, which is every non-podcast feed.
        var mediaURL = ""
        /// What the item files itself under — an RSS `<category>`, an Atom
        /// `<category term/label>`, an `<itunes:category text>`. On a Reddit
        /// `u/name` feed this is the ONLY place the payload names which
        /// subreddit a post is in. Cleaned and capped at `categoryCap`; lands
        /// on `Thing.tags`, which feeds §308 facet filtering, so junk here
        /// degrades search.
        var categories: [String] = []
        /// Every `<a href>` found in the item's own body HTML, in document
        /// order, capped at 5 — Reddit's crossing check reads this for the
        /// post's first OUTBOUND (non-reddit.com) link; every other bridge
        /// ignores it. Captured alongside `summary` so the raw HTML doesn't
        /// need re-fetching later.
        var links: [String] = []
    }

    struct Parsed {
        /// The document's ROOT element, qualified as it arrived (namespace
        /// processing is off) — `rss`, `feed`, `rdf:RDF` for the three feed
        /// formats, `html` for a web page, empty when nothing parsed at all.
        /// Read only through `isFeed`.
        var root = ""
        var title = ""
        /// The feed's OWN mark — the publisher's logo (Reuters, a blog), from
        /// the RSS `<channel><image><url>`, an `<itunes:image>`, or an Atom
        /// `<icon>`/`<logo>`. Empty when the feed advertises none; the ingest
        /// then falls back to the site's favicon. This is publisher identity,
        /// distinct from a per-item lead image (`Item.imageURL`).
        var iconURL = ""
        /// The FEED's own categories — a show's `<itunes:category>`, a
        /// channel-level `<category>`. Distinct from `Item.categories`: this
        /// describes the publication, not the item, so only Podcasts reads it
        /// (see `FeedFollowIngest.refresh`). Empty when the feed declares none.
        var categories: [String] = []
        var items: [Item] = []

        /// Whether this body is a feed DOCUMENT — asked of the root element,
        /// never of the item count (2026-08-16).
        ///
        /// "Has no items" was standing in for "is not a feed", and the two are
        /// different in both directions. A brand-new feed with nothing posted
        /// yet is a real feed, and treating it as a site sent an eight-request
        /// autodiscovery crawl off its host on every single refresh, forever.
        /// The other direction is worse and is why this can't lean on the
        /// title either: `XMLParser` walks a good way into an HTML page before
        /// it gives up, so a web page arrives here carrying its `<title>` —
        /// the page's own headline, which would then be adopted as the feed's
        /// name on a follow that is not a feed at all.
        var isFeed: Bool {
            // `rdf` is RSS 1.0, whose root is `<rdf:RDF>`.
            let local = (root.split(separator: ":").last.map(String.init) ?? root).lowercased()
            return local == "rss" || local == "feed" || local == "rdf"
        }
    }

    /// The item's own author, when the feed names someone the feed itself
    /// isn't. `Thing.authorHandle` already carries the feed's identity (the
    /// channel, publication, subreddit, show), and a YouTube entry's
    /// `<author><name>` is that same channel — filing it again as a person
    /// would make a publication read as one. A multi-author Substack is what
    /// this is for: its posts name their writer while the feed names the
    /// publication. nil when the feed named nobody, or named only itself.
    static func author(_ raw: String, feedName: String) -> String? {
        let author = IngestSupport.decodeHTMLEntities(raw)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !author.isEmpty,
              author.caseInsensitiveCompare(feedName) != .orderedSame else { return nil }
        return author
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
            if elementPath.isEmpty { result.root = name }
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
            // A podcast's `<enclosure type="audio/…">` is the one enclosure
            // that isn't an image — it's the episode itself, and it used to be
            // read for its type and then dropped.
            case "media:thumbnail", "media:content", "enclosure":
                guard let u = attributes["url"] else { break }
                let type = attributes["type"] ?? ""
                let medium = attributes["medium"] ?? ""
                let isImage = name == "media:thumbnail"
                    || type.hasPrefix("image") || medium == "image"
                    || (name == "media:content" && type.isEmpty && medium.isEmpty)
                // Both only land on an item (the inner guards) — a
                // channel-level image never becomes a row's thumbnail.
                if isImage {
                    if current?.imageURL.isEmpty == true { current?.imageURL = Self.normalizeImage(u) }
                } else if name == "enclosure", current?.mediaURL.isEmpty == true,
                          type.hasPrefix("audio") || type.hasPrefix("video") {
                    current?.mediaURL = u
                }
            // A mark rides an href attribute in the iTunes and (rarely) Media
            // namespaces, and it means two different things depending on where
            // it sits: at channel level it's the PUBLISHER's own logo, on an
            // item it's that episode's own art. Kept apart — per-episode art
            // must never become the publisher icon, which is what refusing it
            // outright used to enforce, at the cost of every episode landing
            // imageless (2026-08-06).
            case "itunes:image", "media:image":
                guard let href = attributes["href"] else { break }
                if current == nil {
                    if result.iconURL.isEmpty { result.iconURL = Self.normalizeImage(href) }
                } else if current?.imageURL.isEmpty == true {
                    current?.imageURL = Self.normalizeImage(href)
                }
            // What the item (or the show) files itself under. Atom and iTunes
            // put the words in an attribute; RSS 2.0 puts them in the
            // element's text, read at didEndElement below. Reddit's label
            // reads "r/swift" where its term is the bare name, so the label
            // wins.
            case "category", "itunes:category":
                noteCategory(attributes["label"] ?? attributes["term"] ?? attributes["text"])
            // A YouTube entry's view count (2026-07-28) — only meaningful on
            // an item, so the channel-level guard matches every other
            // per-item attribute case above.
            case "media:statistics":
                if current != nil, let v = attributes["views"], let n = Int(v) {
                    current?.viewCount = n
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
                // RSS 2.0's text form of a channel category (the attribute
                // forms are read at didStartElement, at either level).
                if name == "category" { noteCategory(value) }
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
            case "name":
                // The Atom <author><name> — only when nested directly under
                // <author> (elementPath still holds "name" itself here, the
                // pop happens in the caller's defer), so a channel-level or
                // differently-nested <name> never gets mistaken for one.
                if current != nil, current?.author.isEmpty == true,
                   elementPath.dropLast().last == "author" {
                    current?.author = value
                }
            case "dc:creator":
                // What most RSS 2.0 publishers name a writer with — Atom's
                // <author><name> above has no RSS equivalent (RSS's own
                // <author> is an email address, not a name).
                if current?.author.isEmpty == true { current?.author = value }
            case "category":
                // RSS 2.0's text form; Atom's and iTunes' attribute forms are
                // read at didStartElement.
                noteCategory(value)
            case "description", "content:encoded", "summary", "media:description", "content":
                // No attribute image yet — pull the first <img> out of the
                // (usually CDATA) description HTML. This is Pinterest's path.
                if current?.imageURL.isEmpty == true,
                   let src = Self.firstImageSrc(in: value),
                   !Self.looksLikeTracker(src) {
                    current?.imageURL = Self.normalizeImage(src)
                }
                // Every outbound <a href> in the raw body — Reddit's link-
                // crossing check reads it later; every other bridge ignores
                // it. Extracted here (once, from the same raw HTML the image
                // pull already sees) rather than re-fetched at check time.
                if current?.links.isEmpty == true {
                    current?.links = Self.extractLinks(in: value)
                }
                // …and keep the WORDS too (2026-07-22). Until then this blob
                // was mined for an image and thrown away, so every RSS,
                // Reddit, YouTube, Substack, and Podcast thing landed with no
                // body at all — its sheet re-fetched a link preview to show
                // what the feed had already handed us. Publisher-authored, so
                // it's display copy (`Thing.summary`), not `enrichedText`.
                //
                // `media:description` is YouTube's, and it joined this list
                // only on 2026-08-06 — the parser runs with namespace
                // processing OFF, so element names arrive QUALIFIED and a
                // `<media:group><media:description>` never matched
                // "description". A YouTube entry carries no `<summary>` or
                // `<content>` either, so despite the fix above every video
                // went on landing with no body at all.
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

        /// A feed category is free text, and it lands on `Thing.tags` — the
        /// same field §308 facets filter on — so a sentence, a URL or a raw
        /// "&amp;" would degrade search rather than sharpen it. Cleaned,
        /// length-capped, deduped case-insensitively, and capped in number:
        /// four is a subject list, twenty is a keyword-stuffed feed.
        /// "Uncategorized" is refused by name — it is WordPress's default for
        /// a post filed under nothing, so it says the opposite of a tag.
        private static let categoryCap = 4
        private static let categoryMaxLength = 40
        private static let categoryStoplist: Set<String> = ["uncategorized"]

        /// Files a category on the current item, or on the FEED when one
        /// arrives at channel level (`current == nil`) — see
        /// `Parsed.categories` for why the two are kept apart.
        private func noteCategory(_ raw: String?) {
            guard let raw else { return }
            let t = IngestSupport.decodeHTMLEntities(raw)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if t.count > Self.categoryMaxLength { return }
            guard !t.isEmpty, !t.contains("://"),
                  !Self.categoryStoplist.contains(t.lowercased()) else { return }
            func fits(_ existing: [String]) -> Bool {
                existing.count < Self.categoryCap
                    && !existing.contains { $0.caseInsensitiveCompare(t) == .orderedSame }
            }
            if current == nil {
                if fits(result.categories) { result.categories.append(t) }
            } else if let own = current?.categories, fits(own) {
                current?.categories.append(t)
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

        /// Every `<a href>` in a blob of feed HTML, in document order,
        /// capped at 5 — a post body rarely needs more than a handful
        /// checked for Reddit's crossing pass.
        private static let linkRegex = try? NSRegularExpression(
            pattern: #"<a\s+[^>]*href=["']([^"']+)["']"#, options: [.caseInsensitive])

        private static func extractLinks(in html: String) -> [String] {
            guard let linkRegex else { return [] }
            let ns = html as NSString
            let matches = linkRegex.matches(in: html, range: NSRange(location: 0, length: ns.length))
            return matches.prefix(5).compactMap { m in
                guard m.numberOfRanges > 1 else { return nil }
                return ns.substring(with: m.range(at: 1))
            }
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
