import Foundation
import SwiftData

/// NerdWallet (2026-09-15) — personal-finance journalism, landing as links.
///
/// **The seat is ONE feed with nothing to configure, and that is a measured
/// fact rather than a simplification.** NerdWallet publishes a single RSS
/// document at `/blog/feed/`. The per-topic feeds a reader would reach for do
/// not exist: `/blog/category/<topic>/feed/` answers 301 to the site root for
/// every topic tried (mortgages, credit-cards, investing, banking, loans,
/// insurance, travel, small-business), `/blog/tag/<topic>/feed` and
/// `/investing/feed` answer HTML or 404, and `?cat=<topic>` is accepted,
/// parsed and IGNORED — the filtered and unfiltered documents come back with
/// identical item titles. So there is no list to follow, no field to type
/// into, and the only honest controls are on and off.
///
/// **That is why this is not a `FeedFollowKind`.** All five of those seats
/// watch a LIST of names the person supplies — a publication, a subreddit, a
/// channel, a show. Rendering that grammar over a fixed single feed would put
/// a "follow a publication" field on the page that can hold exactly one value
/// nobody chose, which is §83's dead control arriving as a text field.
///
/// **What this seat is NOT, stated because the name invites the other
/// reading.** Nothing here reaches an account. There is no sign-in, no token,
/// no cookie and no personal data in either direction — NerdWallet's own
/// money-tracking product is gone, and this is the publisher's public feed,
/// fetched by this iPhone exactly as the RSS seat fetches any other. The
/// catalog tagline says "news" for that reason, and the account page's one
/// footnote says it again in words.
enum NerdWalletBridge {
    static let source = "NerdWallet"
    static let seatID = "nerdwallet"
    /// Namespaced like every other bridge's (§311: one spelling, one file) —
    /// a NerdWallet article and an RSS follow of the same URL are different
    /// rows, and the prefix is what keeps them from deduping into each other.
    static let refPrefix = "nerdwallet:"

    static let feedURL = URL(string: "https://www.nerdwallet.com/blog/feed/")!
    /// Where the seat's door goes. Not fetched — the browser opens it.
    static let site = URL(string: "https://www.nerdwallet.com")!

    /// Whether the seat is on. A flag rather than a `Thing`, for
    /// `WalletbeatWatch.following`'s reason: there is no entity to be — a
    /// watch names something and this names nothing.
    private static let followingKey = "nerdwallet.following"

    static var following: Bool {
        get { UserDefaults.standard.bool(forKey: followingKey) }
        set { UserDefaults.standard.set(newValue, forKey: followingKey) }
    }

    /// Turning the seat off forgets the feed's HTTP record, so a later
    /// reconnect re-reads the whole window instead of being handed a 304 for
    /// a body this device no longer has parsed. `FeedFollowStore.remove`'s
    /// rule, for the same reason. Landed articles are untouched — they are
    /// yours once they arrive.
    static func stopFollowing() {
        following = false
        FeedFreshness.forget(feedURL.absoluteString)
    }
}

enum NerdWalletIngest {
    @MainActor private static var running = false

    /// Lands new articles. nil = the pass could not run or the publisher did
    /// not answer; 0 or more = a real read, however many were new. A 304 is a
    /// REACHED feed with nothing to parse and returns 0, never nil — the
    /// distinction `FeedFetchOutcome` exists for, and the one that keeps a
    /// healthy quiet feed from reading as a broken bridge.
    @MainActor
    @discardableResult
    static func refresh(context: ModelContext) async -> Int? {
        guard NerdWalletBridge.following else { return nil }
        guard !running else { return 0 }
        running = true
        defer { running = false }

        let data: Data
        switch await FeedFreshness.fetch(NerdWalletBridge.feedURL,
                                         as: NerdWalletBridge.source) {
        case .notModified:     return 0
        case .failed:          return nil
        case .fresh(let body): data = body
        }

        let parsed = FeedParser.parse(data)
        // Asked of the ROOT element, never the item count (RSSIngest's own
        // 2026-08-16 ruling): an empty feed is still a feed, and an HTML error
        // page arrives here carrying its own `<title>`.
        guard parsed.isFeed else { return nil }

        let feedName = parsed.title.isEmpty ? NerdWalletBridge.source : parsed.title
        let icon = parsed.iconURL.isEmpty
            ? "https://www.nerdwallet.com/favicon.ico" : parsed.iconURL

        var existing = IngestSupport.existingSourceRefs(context,
                                                        source: NerdWalletBridge.source)
        // Fetched lazily, and only on the first already-landed ref — a feed
        // with nothing to heal pays nothing for this.
        var byRef: [String: Thing]?
        func stored(_ ref: String) -> Thing? {
            if byRef == nil {
                byRef = IngestSupport.thingsByRef(context, source: NerdWalletBridge.source)
            }
            return byRef?[ref]
        }

        var added = 0
        var touched = false
        var indexed: [Thing] = []

        for item in parsed.items {
            // The publisher's `<guid>`, falling back to the link — the key an
            // article keeps when its headline is edited, which NerdWallet does
            // to its rate-tracker posts every weekday.
            let key = item.guid.isEmpty ? item.link : item.guid
            guard !key.isEmpty else { continue }
            let ref = NerdWalletBridge.refPrefix + key

            if existing.contains(ref) {
                // Rows that landed before a field existed heal in place, only
                // within the feed's own window — RSSIngest's bar exactly.
                if let thing = stored(ref) {
                    let decoded = IngestSupport.decodeHTMLEntities(item.title)
                    if !decoded.isEmpty, decoded != thing.title {
                        thing.title = decoded
                        // The title is part of the embedding text, so a
                        // corrected headline must be re-embedded.
                        thing.embedding = nil
                        touched = true
                    }
                    if (thing.authorAvatarURL ?? "").isEmpty {
                        thing.authorAvatarURL = icon; touched = true
                    }
                    if (thing.authorHandle ?? "").isEmpty {
                        thing.authorHandle = feedName; touched = true
                    }
                    if thing.content.isEmpty, !item.link.isEmpty {
                        thing.content = item.link; touched = true
                    }
                    if (thing.summary ?? "").isEmpty, !item.summary.isEmpty {
                        thing.summary = item.summary; touched = true
                    }
                    if thing.postAuthor == nil,
                       let author = FeedParser.author(item.author, feedName: feedName) {
                        thing.postAuthor = author; touched = true
                    }
                    // Appended, never assigned — a row's other tags (its type
                    // tag, a project's) are not this feed's to drop.
                    for tag in item.categories
                    where !thing.tags.contains(where: {
                        $0.caseInsensitiveCompare(tag) == .orderedSame
                    }) {
                        thing.tags.append(tag); touched = true
                    }
                }
                continue
            }

            guard !item.title.isEmpty, !item.link.isEmpty else { continue }
            let thing = Thing(
                kind: .link,
                title: IngestSupport.decodeHTMLEntities(item.title),
                content: item.link,
                source: NerdWalletBridge.source,
                capturedAt: item.date ?? .now,
                tags: item.categories,
                sourceRef: ref
            )
            thing.previewImageURL = IngestSupport.imageURL(item.imageURL)
            if !item.summary.isEmpty { thing.summary = item.summary }
            // The publisher's mark leads the row and its name rides the
            // trailing label — the article's own art rides after the title.
            thing.authorAvatarURL = icon
            thing.authorHandle = feedName
            // NerdWallet bylines its writers, and the feed carries them in
            // `<dc:creator>`. `FeedParser.author` drops the ones that only
            // repeat the publication, so a house post stays unattributed
            // rather than being filed as a person called NerdWallet.
            if let author = FeedParser.author(item.author, feedName: feedName) {
                thing.postAuthor = author
            }
            context.insert(thing)
            existing.insert(ref)
            indexed.append(thing)
            added += 1
        }

        // One `CSSearchableIndex` call, not one per item. `.filter(\.isLive)`
        // at the boundary is the standing rule for handing `[Thing]` onward
        // (liveness corollary 4), not a suspicion about these.
        SpotlightIndex.index(indexed.filter(\.isLive))
        if added > 0 || touched { context.saveHonestly() }
        return added
    }
}
