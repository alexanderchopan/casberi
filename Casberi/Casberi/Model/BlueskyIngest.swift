import Foundation
import Observation
import SwiftData

/// The Bluesky bridge (2026-07-07) — the sixth real connectable. The AT
/// Protocol's AppView API serves a person's own posts PUBLICLY, so v1 needs
/// only a handle: no password, no token, nothing to leak. Your posts land as
/// link things that open on bsky.app. Grown 2026-07-14 to match Farcaster's
/// keyless reach: MENTIONS of a watched account land (searchPosts), the
/// thing sheet shows a post's replies (getPostThread), and account rows wear
/// the profile (getProfile: display name, bio, face). LIKES still require an
/// app-password sign-in (getActorLikes is auth-only) — the footer says so.
@Observable
final class BlueskyStore {
    static let shared = BlueskyStore()
    private static let key = "bluesky.accounts"
    private static let feedsKey = "bluesky.feeds"
    private static let legacyKey = "bluesky.handle"

    struct Account: Codable, Identifiable, Equatable {
        var id = UUID()
        var handle: String
        /// Profile facts the AppView serves — worn by the account row.
        var displayName: String?
        var bio: String?
        var avatarURL: String?
        /// Watch MENTIONS of them — posts naming this account land, so
        /// "while I was away" can answer with who talked to you.
        var mentions = false

        init(handle: String) { self.handle = handle }

        /// Accounts persisted before the profile/mentions fields decode
        /// with defaults instead of failing the whole list.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            handle = try c.decode(String.self, forKey: .handle)
            displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
            bio = try c.decodeIfPresent(String.self, forKey: .bio)
            avatarURL = try c.decodeIfPresent(String.self, forKey: .avatarURL)
            mentions = try c.decodeIfPresent(Bool.self, forKey: .mentions) ?? false
        }
    }

    /// A followed FEED — Bluesky's answer to a Farcaster channel (2026-07-16).
    /// Bluesky has no global channel names; its topical lanes are custom feed
    /// generators, addressed by at-uri and found by search. So the entry
    /// gesture differs (you search "science" and pick, rather than typing
    /// "/design" and having it resolve) — but once followed, a feed behaves
    /// exactly like a channel: its posts land beside the people's.
    /// `uri` is the generator's at-uri; the name and face come from its record.
    struct Feed: Codable, Identifiable, Equatable {
        var id = UUID()
        var name: String
        var uri: String
        var imageURL: String?
    }

    /// The handles whose public posts land — more than one is a small
    /// following feed of people you care about, not just your own mirror
    /// (2026-07-10). Order is the person's; add/remove are theirs.
    var accounts: [Account] {
        didSet { persist() }
    }

    /// The followed feeds — topic lanes beside the people (2026-07-16).
    var feeds: [Feed] {
        didSet { persistFeeds() }
    }

    /// Connected at all — a followed FEED with no account still counts (it
    /// syncs, it can disconnect), the same rule Farcaster's channels earned.
    var connected: Bool { !accounts.isEmpty || !feeds.isEmpty }
    var handles: [String] { accounts.map(\.handle) }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([Account].self, from: data) {
            accounts = saved
        } else if let legacy = UserDefaults.standard.string(forKey: Self.legacyKey),
                  !legacy.isEmpty {
            accounts = [Account(handle: legacy)]   // migrate the single handle
        } else {
            accounts = []
        }
        if let data = UserDefaults.standard.data(forKey: Self.feedsKey),
           let saved = try? JSONDecoder().decode([Feed].self, from: data) {
            feeds = saved
        } else {
            feeds = []
        }
    }

    @discardableResult
    func addFeed(_ feed: Feed) -> Bool {
        guard !feeds.contains(where: { $0.uri == feed.uri }) else { return false }
        feeds.append(feed)
        return true
    }

    func removeFeed(_ uri: String) { feeds.removeAll { $0.uri == uri } }

    private func persistFeeds() {
        if let data = try? JSONEncoder().encode(feeds) {
            UserDefaults.standard.set(data, forKey: Self.feedsKey)
        }
    }

    /// Adds a handle, deduped. Returns false if it was empty or already there.
    @discardableResult
    func add(_ raw: String) -> Bool {
        let h = Self.normalize(raw)
        guard !h.isEmpty, !accounts.contains(where: { $0.handle == h }) else { return false }
        accounts.append(Account(handle: h))
        return true
    }

    /// Adds many at once, deduped, persisting ONCE — the follow import lands
    /// hundreds, and `accounts` persists on every mutation, so appending in a
    /// loop would re-encode the whole growing list per person. Returns how
    /// many were new.
    @discardableResult
    func add(contentsOf raws: [String]) -> Int {
        var known = Set(accounts.map(\.handle))
        var fresh: [Account] = []
        for raw in raws {
            let h = Self.normalize(raw)
            guard !h.isEmpty, known.insert(h).inserted else { continue }
            fresh.append(Account(handle: h))
        }
        guard !fresh.isEmpty else { return 0 }
        accounts.append(contentsOf: fresh)
        return fresh.count
    }

    func remove(_ handle: String) { accounts.removeAll { $0.handle == handle } }

    /// Teardown clears the whole connection — people and feeds both.
    func removeAll() {
        accounts = []
        feeds = []
    }

    /// Sync's write-back of the AppView's profile facts. One assignment, so
    /// the array's didSet (→ persist) fires once, not once per field.
    func setProfile(displayName: String?, bio: String?, avatarURL: String?, for handle: String) {
        guard let i = accounts.firstIndex(where: { $0.handle == handle }) else { return }
        var a = accounts[i]
        a.displayName = displayName
        a.bio = bio
        a.avatarURL = avatarURL
        accounts[i] = a
    }

    func setMentions(_ on: Bool, for handle: String) {
        guard let i = accounts.firstIndex(where: { $0.handle == handle }) else { return }
        accounts[i].mentions = on
    }

    /// The name a post's row shows. Your ONE watched mirror stays unlabeled
    /// (redundant); everything else — several accounts, or a mentioner who
    /// isn't watched — names itself, so attribution never gets lost (the
    /// Farcaster/Wallet rule). ".bsky.social" comes off — the name is what
    /// the person knows.
    func rowLabel(for handle: String?) -> String? {
        guard let handle, !handle.isEmpty else { return nil }
        if accounts.count == 1, accounts[0].handle == handle { return nil }
        return "@\(Self.short(handle))"
    }

    static func short(_ handle: String) -> String {
        handle.hasSuffix(".bsky.social")
            ? String(handle.dropLast(".bsky.social".count)) : handle
    }

    /// The watched accounts as the shared setup row renders them — face,
    /// name, bio, and the Mentions toggle (Bluesky's only keyless watch;
    /// likes need sign-in).
    var socialAccounts: [SocialAccount] {
        accounts.map { a in
            SocialAccount(
                key: a.handle,
                title: a.displayName ?? "@\(Self.short(a.handle))",
                subtitle: SocialAccount.subtitle(handle: "@\(Self.short(a.handle))", bio: a.bio),
                avatarURL: a.avatarURL,
                watches: [SocialWatch(kind: .mentions, on: a.mentions)])
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(accounts) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    /// "@name.bsky.social" and bare "name" both normalize.
    static func normalize(_ raw: String) -> String {
        var h = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for junk in ["https://", "http://", "bsky.app/profile/", "@"] {
            if h.hasPrefix(junk) { h.removeFirst(junk.count) }
        }
        if let slash = h.firstIndex(of: "/") { h = String(h[..<slash]) }
        if !h.isEmpty, !h.contains(".") { h += ".bsky.social" }
        return h
    }
}

enum BlueskyIngest {

    /// The AppView's unauthenticated host. searchPosts is the exception: it
    /// 403s on public.api but is served keyless on `api.bsky.app` (the host
    /// the official client uses; verified live 2026-07-14) — so the mentions
    /// call, and only it, rides `searchHost`.
    private static let host = "https://public.api.bsky.app/xrpc"
    private static let searchHost = "https://api.bsky.app/xrpc"

    @MainActor private static var running = false

    /// Fetches each watched handle's recent posts from the public AppView,
    /// plus mentions where that's watched, and lands new ones as chat things.
    /// Returns the new count, or nil when nothing could be resolved.
    @MainActor
    static func refresh(context: ModelContext) async -> Int? {
        let store = BlueskyStore.shared
        let accounts = store.accounts
        guard store.connected, !running else { return store.connected ? 0 : nil }
        running = true
        healed = false
        defer { running = false }

        var existing = IngestSupport.existingSourceRefs(context)
        let landed = IngestSupport.thingsByRef(context, source: "Bluesky")
        let backfill = ArtlessBackfill(context, source: "Bluesky")
        var added = 0
        var touched = false
        var anyResolved = false

        for account in accounts {
            let handle = account.handle
            var comps = URLComponents(string: "\(host)/app.bsky.feed.getAuthorFeed")!
            comps.queryItems = [
                URLQueryItem(name: "actor", value: handle),
                URLQueryItem(name: "limit", value: "30"),
                URLQueryItem(name: "filter", value: "posts_no_replies"),
            ]
            guard let url = comps.url,
                  let root = await IngestSupport.getJSON(url) as? [String: Any],
                  let feed = root["feed"] as? [[String: Any]] else {
                continue   // one bad handle doesn't sink the others
            }
            anyResolved = true

            // The feed already hydrates the account's display name and avatar
            // (every post carries its author) — bio is the only field that
            // needs getProfile. So name and face come free from the feed and
            // the row is never bare even if getProfile is down; getProfile
            // enriches bio best-effort, and on failure the stored bio stays
            // (nils never clobber — the Farcaster rule).
            let feedAuthor = (feed.first?["post"] as? [String: Any])?["author"] as? [String: Any]
            let feedName = (feedAuthor?["displayName"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            let feedAvatar = IngestSupport.imageURL(feedAuthor?["avatar"] as? String)
            let who = await profile(handle: handle)
            let displayName = who?.displayName ?? feedName ?? account.displayName
            let avatar = who?.avatarURL ?? feedAvatar ?? account.avatarURL
            let bio = who != nil ? who?.bio : account.bio   // trust a fresh fetch, keep on failure
            if displayName != account.displayName || bio != account.bio
                || avatar != account.avatarURL {
                BlueskyStore.shared.setProfile(displayName: displayName, bio: bio,
                                               avatarURL: avatar, for: handle)
            }
            // Backfill the face onto EVERY existing post of theirs that
            // predates the field, so the whole feed wears faces, not just
            // posts landed since (2026-07-10).
            if let avatar {
                for t in landed.values where t.authorAvatarURL == nil
                    && t.content.contains("/profile/\(handle)/") {
                    t.authorHandle = handle
                    t.authorAvatarURL = avatar
                    touched = true
                }
            }

            added += await landPage(feed.compactMap { $0["post"] as? [String: Any] },
                                    ownHandle: handle, existing: &existing, landed: landed,
                                    backfill: backfill, context: context)

            if account.mentions {
                added += await landMentions(of: handle, existing: &existing, landed: landed,
                                            backfill: backfill, context: context)
            }
        }

        for feed in store.feeds {
            let count = await landFeed(feed, existing: &existing, landed: landed,
                                       backfill: backfill, context: context)
            if let count {
                anyResolved = true
                added += count
            }
        }
        // Nothing resolving is the "couldn't find that" signal; one landing
        // means the connection is good.
        guard anyResolved else { return nil }
        if added > 0 || backfill.any || touched || healed { context.saveHonestly() }
        return added
    }

    /// A followed feed's newest posts (2026-07-16) — the Bluesky dose of
    /// Farcaster's channel sync. `getFeed` proxies to the generator's own
    /// service and is served keyless for public feeds. Returns nil when the
    /// AppView didn't answer, so a feeds-only refresh can still say so.
    @MainActor
    private static func landFeed(_ feed: BlueskyStore.Feed, existing: inout Set<String>,
                                 landed: [String: Thing], backfill: ArtlessBackfill,
                                 context: ModelContext) async -> Int? {
        var comps = URLComponents(string: "\(host)/app.bsky.feed.getFeed")!
        comps.queryItems = [URLQueryItem(name: "feed", value: feed.uri),
                            URLQueryItem(name: "limit", value: "25")]
        guard let url = comps.url,
              let root = await IngestSupport.getJSON(url) as? [String: Any],
              let entries = root["feed"] as? [[String: Any]] else { return nil }
        return await landPage(entries.compactMap { $0["post"] as? [String: Any] },
                              channel: feed.name, existing: &existing, landed: landed,
                              backfill: backfill, context: context)
    }

    /// Lands a page of hydrated posts: one batched lookup warms the cards for
    /// every new post's PARENT (a reply's parent is a bare uri in the record —
    /// the only thing the AppView doesn't hydrate for us), then each post lands
    /// off the cache. The ref dedupe means the steady state pays nothing.
    @MainActor
    private static func landPage(_ posts: [[String: Any]], ownHandle: String? = nil,
                                 why: String? = nil, channel: String? = nil,
                                 existing: inout Set<String>, landed: [String: Thing],
                                 backfill: ArtlessBackfill,
                                 context: ModelContext) async -> Int {
        await prefetchCards(posts.compactMap { post in
            guard let uri = post["uri"] as? String, !existing.contains("bsky:\(uri)")
            else { return nil }
            return parentURI(post)
        })
        var added = 0
        for post in posts {
            if await land(post: post, ownHandle: ownHandle, why: why, channel: channel,
                          existing: &existing, landed: landed,
                          backfill: backfill, context: context) {
                added += 1
            }
        }
        return added
    }

    /// Posts by OTHERS that name this account (searchPosts' `mentions:`
    /// operator) — replies and quotes included, since a mention usually is
    /// one. New ones ride "while I was away" like any landed thing. The
    /// search results hydrate each author (handle, name, avatar), so no
    /// per-mentioner profile lookup is needed.
    @MainActor
    private static func landMentions(of handle: String, existing: inout Set<String>,
                                     landed: [String: Thing], backfill: ArtlessBackfill,
                                     context: ModelContext) async -> Int {
        var comps = URLComponents(string: "\(searchHost)/app.bsky.feed.searchPosts")!
        comps.queryItems = [URLQueryItem(name: "q", value: "mentions:\(handle)"),
                            URLQueryItem(name: "limit", value: "25")]
        guard let url = comps.url,
              let root = await IngestSupport.getJSON(url) as? [String: Any],
              let posts = root["posts"] as? [[String: Any]] else { return 0 }
        return await landPage(posts, why: "mention", existing: &existing, landed: landed,
                              backfill: backfill, context: context)
    }

    /// Lands one post by whoever wrote it — the shared tail of the author
    /// feed and the mentions flow. `ownHandle` non-nil filters to that
    /// author (the feed excludes reposts of others); nil accepts anyone
    /// (mentions). The author is hydrated on the post, so its name and face
    /// come free; a post the AppView didn't hydrate an author for is skipped.
    @MainActor
    @discardableResult
    private static func land(post: [String: Any], ownHandle: String?,
                             why: String? = nil, channel: String? = nil,
                             existing: inout Set<String>, landed: [String: Thing],
                             backfill: ArtlessBackfill,
                             context: ModelContext) async -> Bool {
        guard let uri = post["uri"] as? String,
              let record = post["record"] as? [String: Any],
              let text = record["text"] as? String, !text.isEmpty,
              let author = post["author"] as? [String: Any],
              let authorHandle = author["handle"] as? String, !authorHandle.isEmpty
        else { return false }
        if let ownHandle, authorHandle != ownHandle { return false }
        let ref = "bsky:\(uri)"
        let images = embedImages(post)
        guard !existing.contains(ref) else {
            backfill.patch(ref, image: images.first)
            heal(landed[ref], post: post, text: text, images: images,
                 why: why, channel: channel)
            return false
        }
        let date = IngestSupport.isoDate(record["createdAt"])

        let thing = Thing(
            kind: .chat,
            title: IngestSupport.titleLine(text),
            content: webURL(uri: uri, handle: authorHandle),
            source: "Bluesky",
            capturedAt: date ?? .now,
            sourceRef: ref
        )
        thing.postText = text
        thing.imageURLs = images.compactMap(IngestSupport.imageURL)
        thing.previewImageURL = thing.imageURLs.first
        thing.authorHandle = authorHandle
        thing.authorAvatarURL = IngestSupport.imageURL(author["avatar"] as? String)
        thing.socialContext = why
        thing.channelName = channel
        thing.quote = quoteCard(post)
        thing.parent = parentURI(post).flatMap { cards[$0] }
        // Bluesky's AppView hydrates engagement on every post view, so these
        // cost nothing here. They're a SNAPSHOT — the sheet re-reads live —
        // but storing them means the number is there the instant it opens.
        applyCounts(post, to: thing)
        context.insert(thing)
        SpotlightIndex.index([thing])
        existing.insert(ref)
        return true
    }

    /// at://did:…/app.bsky.feed.post/<rkey> → the web permalink.
    private static func webURL(uri: String, handle: String) -> String {
        let rkey = uri.split(separator: "/").last.map(String.init) ?? ""
        return "https://bsky.app/profile/\(handle)/post/\(rkey)"
    }

    private static func applyCounts(_ post: [String: Any], to thing: Thing) {
        thing.likeCount = post["likeCount"] as? Int
        thing.repostCount = post["repostCount"] as? Int
        thing.replyCount = post["replyCount"] as? Int
    }

    /// Fills the enrichment fields on a post that landed BEFORE they existed
    /// (2026-07-16) — see `FarcasterIngest.heal`, same contract: only ever
    /// FILLS a gap, never rewrites what a good sync landed. Counts are the one
    /// exception: they're a snapshot of a moving number, so a fresh read
    /// legitimately replaces a stale one.
    @MainActor
    private static func heal(_ thing: Thing?, post: [String: Any],
                             text: String, images: [String],
                             why: String?, channel: String?) {
        guard let thing else { return }
        // WHY it's here heals too — see `FarcasterIngest.heal`, same reasoning:
        // without this the marker would only ever reach posts landed from today
        // on, and an existing corpus would show none of them.
        if thing.socialContext == nil, let why {
            thing.socialContext = why
            healed = true
        }
        if thing.channelName == nil, let channel {
            thing.channelName = channel
            healed = true
        }
        if thing.postText == nil {
            thing.postText = text
            healed = true
        }
        if thing.imageURLs.isEmpty, !images.isEmpty {
            thing.imageURLs = images.compactMap(IngestSupport.imageURL)
            healed = true
        }
        if thing.quote == nil, let quote = quoteCard(post) {
            thing.quote = quote
            healed = true
        }
        if thing.parent == nil, let parent = parentURI(post).flatMap({ cards[$0] }) {
            thing.parent = parent
            healed = true
        }
        if thing.likeCount != post["likeCount"] as? Int {
            applyCounts(post, to: thing)
            healed = true
        }
    }

    /// True once `heal` filled a gap this pass — joins the refresh's save
    /// condition. Reset at each refresh; the `running` guard makes the pass
    /// single-flight, so one flag is safe.
    @MainActor private static var healed = false

    // MARK: - Replies (the sheet's thread context, 2026-07-14)

    /// The thread under one post (getPostThread, depth 1), oldest first,
    /// capped. Each reply's author is hydrated, so no extra lookups.
    @MainActor
    static func replies(uri: String, limit: Int = 8) async -> [SocialReply] {
        if let cached = threads[uri] { return cached }
        var comps = URLComponents(string: "\(host)/app.bsky.feed.getPostThread")!
        comps.queryItems = [URLQueryItem(name: "uri", value: uri),
                            URLQueryItem(name: "depth", value: "1")]
        guard let url = comps.url,
              let root = await IngestSupport.getJSON(url) as? [String: Any],
              let thread = root["thread"] as? [String: Any],
              let raw = thread["replies"] as? [[String: Any]] else { return [] }
        var replies: [SocialReply] = []
        for entry in raw {
            guard let post = entry["post"] as? [String: Any],
                  let replyURI = post["uri"] as? String,
                  let author = post["author"] as? [String: Any],
                  let handle = author["handle"] as? String, !handle.isEmpty,
                  let record = post["record"] as? [String: Any],
                  let text = record["text"] as? String, !text.isEmpty else { continue }
            replies.append(SocialReply(
                id: replyURI, handle: handle,
                avatarURL: IngestSupport.imageURL(author["avatar"] as? String),
                text: text, when: IngestSupport.isoDate(record["createdAt"]),
                url: webURL(uri: replyURI, handle: handle), ref: "bsky:\(replyURI)"))
            if replies.count == limit { break }
        }
        threads[uri] = replies   // a node miss returned [] above, uncached — it retries
        return replies
    }

    /// Threads fetched this launch, keyed by post uri.
    @MainActor private static var threads: [String: [SocialReply]] = [:]

    // MARK: - Profiles

    struct Profile {
        var displayName: String?
        var bio: String?
        var avatarURL: String?
    }
    @MainActor private static var profiles: [String: Profile] = [:]

    /// A handle's profile facts (getProfile) — fetched once per handle per
    /// launch. nil when the AppView didn't answer, and a FAILURE IS NOT
    /// CACHED: the next refresh retries instead of clobbering stored facts.
    @MainActor
    static func profile(handle: String) async -> Profile? {
        if let cached = profiles[handle] { return cached }
        guard let root = await IngestSupport.getJSON(
            "\(host)/app.bsky.actor.getProfile?actor=\(handle)") as? [String: Any],
              root["handle"] != nil else { return nil }
        let profile = Profile(
            displayName: (root["displayName"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            bio: (root["description"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            avatarURL: IngestSupport.imageURL(root["avatar"] as? String))
        profiles[handle] = profile
        return profile
    }

    /// EVERY image a post attaches, in order, else an external card's single
    /// thumb (2026-07-16 — it used to keep only the first, so a four-photo post
    /// lost three). The AppView hydrates ready-to-fetch CDN URLs on the
    /// post-level embed view. A text-only post returns none and keeps the
    /// butterfly glyph: the image leads only when the post actually has one.
    private static func embedImages(_ post: [String: Any]) -> [String] {
        guard let embed = post["embed"] as? [String: Any] else { return [] }
        // Images attached directly, or nested under record-with-media.
        let media = (embed["media"] as? [String: Any]) ?? embed
        if let images = media["images"] as? [[String: Any]] {
            let thumbs = images.compactMap { $0["thumb"] as? String }
            if !thumbs.isEmpty { return thumbs }
        }
        if let external = media["external"] as? [String: Any],
           let thumb = external["thumb"] as? String { return [thumb] }
        return []
    }

    // MARK: - Quotes and parents (2026-07-16)

    /// The post this one QUOTES. Bluesky hydrates a quote fully on the embed
    /// view — author, text, uri — so unlike Farcaster's bare {fid, hash} ref
    /// this costs no lookup. Two shapes carry it: `embed.record` IS the quoted
    /// record for a plain quote, and is `{record: …}` for record-with-media (a
    /// quote WITH photos), so the nested key is tried first.
    private static func quoteCard(_ post: [String: Any]) -> SocialCard? {
        guard let embed = post["embed"] as? [String: Any],
              let record = embed["record"] as? [String: Any] else { return nil }
        let view = (record["record"] as? [String: Any]) ?? record
        guard let uri = view["uri"] as? String,
              let author = view["author"] as? [String: Any],
              let handle = author["handle"] as? String, !handle.isEmpty,
              let value = view["value"] as? [String: Any],
              let text = value["text"] as? String else { return nil }
        return SocialCard(handle: handle, text: text,
                          avatarURL: IngestSupport.imageURL(author["avatar"] as? String),
                          url: webURL(uri: uri, handle: handle), ref: "bsky:\(uri)")
    }

    /// The at-uri of the post this one replies under — a bare ref in the
    /// record, the one thing the AppView doesn't hydrate for us.
    private static func parentURI(_ post: [String: Any]) -> String? {
        guard let record = post["record"] as? [String: Any],
              let reply = record["reply"] as? [String: Any],
              let parent = reply["parent"] as? [String: Any],
              let uri = parent["uri"] as? String, !uri.isEmpty else { return nil }
        return uri
    }

    /// A hydrated post view as a card.
    private static func card(from post: [String: Any]) -> SocialCard? {
        guard let uri = post["uri"] as? String,
              let author = post["author"] as? [String: Any],
              let handle = author["handle"] as? String, !handle.isEmpty,
              let record = post["record"] as? [String: Any],
              let text = record["text"] as? String else { return nil }
        return SocialCard(handle: handle, text: text,
                          avatarURL: IngestSupport.imageURL(author["avatar"] as? String),
                          url: webURL(uri: uri, handle: handle), ref: "bsky:\(uri)")
    }

    /// Referenced posts fetched this launch, keyed by at-uri.
    @MainActor private static var cards: [String: SocialCard] = [:]

    /// Warms the card cache for a batch of at-uris. `getPosts` takes up to 25
    /// at a time, so a whole page's parents cost one request, not one each.
    @MainActor
    private static func prefetchCards(_ uris: [String]) async {
        var seen = Set<String>()
        let missing = uris.filter { cards[$0] == nil && seen.insert($0).inserted }
        guard !missing.isEmpty else { return }
        for start in stride(from: 0, to: missing.count, by: 25) {
            let chunk = Array(missing[start..<min(start + 25, missing.count)])
            var comps = URLComponents(string: "\(host)/app.bsky.feed.getPosts")!
            comps.queryItems = chunk.map { URLQueryItem(name: "uris", value: $0) }
            guard let url = comps.url,
                  let root = await IngestSupport.getJSON(url) as? [String: Any],
                  let posts = root["posts"] as? [[String: Any]] else { continue }
            for post in posts {
                guard let uri = post["uri"] as? String, let card = card(from: post) else { continue }
                cards[uri] = card
            }
        }
    }

    // MARK: - Engagement (2026-07-16)

    /// A post's likes, reposts, and replies — EXACT totals: the AppView counts
    /// them itself and hydrates them on the post view, so unlike Farcaster's
    /// page-capped tallies these need no "+" hedge. One request, read live when
    /// the sheet opens.
    @MainActor
    static func engagement(for thing: Thing) async -> SocialEngagement? {
        guard thing.source == "Bluesky", let ref = thing.sourceRef,
              ref.hasPrefix("bsky:") else { return nil }
        let uri = String(ref.dropFirst("bsky:".count))
        var comps = URLComponents(string: "\(host)/app.bsky.feed.getPosts")!
        comps.queryItems = [URLQueryItem(name: "uris", value: uri)]
        guard let url = comps.url,
              let root = await IngestSupport.getJSON(url) as? [String: Any],
              let post = (root["posts"] as? [[String: Any]])?.first else { return nil }
        let e = SocialEngagement(
            likes: (post["likeCount"] as? Int).map { SocialCount(value: $0) },
            reposts: (post["repostCount"] as? Int).map { SocialCount(value: $0) },
            replies: (post["replyCount"] as? Int).map { SocialCount(value: $0) })
        return e.isEmpty ? nil : e
    }

    // MARK: - Feeds (Bluesky's channels, 2026-07-16)

    /// Search the public feed-generator directory by name — "science",
    /// "cats" — the finder behind the Feeds section. Bluesky has no global
    /// channel names to type, so the search IS the entry gesture (prd §75 held
    /// this pending exactly that decision).
    ///
    /// Host quirk, same family as searchPosts: the unspecced popular-feeds
    /// endpoint is served on `api.bsky.app` (the host the official client
    /// uses); public.api answers too for most deployments, so both are tried in
    /// order and the first that answers wins.
    static func searchFeeds(_ query: String) async -> [BlueskyStore.Feed] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        for base in [searchHost, host] {
            var comps = URLComponents(
                string: "\(base)/app.bsky.unspecced.getPopularFeedGenerators")!
            comps.queryItems = [URLQueryItem(name: "query", value: q),
                                URLQueryItem(name: "limit", value: "\(UserSearch.limit)")]
            guard let url = comps.url,
                  let root = await IngestSupport.getJSON(url) as? [String: Any],
                  let feeds = root["feeds"] as? [[String: Any]], !feeds.isEmpty else { continue }
            return feeds.compactMap { feed in
                guard let uri = feed["uri"] as? String, !uri.isEmpty,
                      let name = (feed["displayName"] as? String)?
                        .trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty
                else { return nil }
                return BlueskyStore.Feed(
                    name: name, uri: uri,
                    imageURL: IngestSupport.imageURL(feed["avatar"] as? String))
            }
        }
        return []
    }

    /// Follow-by-search-hit — the setup screen's tap and the `-bskyFeed` probe
    /// both come through here. A raw at-uri is accepted too (paste a feed's
    /// uri), resolved through the describe endpoint for its name and face.
    @MainActor
    @discardableResult
    static func followFeed(_ raw: String) async -> BlueskyStore.Feed? {
        let input = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let feed: BlueskyStore.Feed?
        if input.hasPrefix("at://") {
            feed = await describeFeed(uri: input)
        } else {
            feed = await searchFeeds(input).first
        }
        guard let feed else { return nil }
        BlueskyStore.shared.addFeed(feed)
        return feed
    }

    /// One feed generator's name and face, by at-uri.
    private static func describeFeed(uri: String) async -> BlueskyStore.Feed? {
        var comps = URLComponents(string: "\(host)/app.bsky.feed.getFeedGenerators")!
        comps.queryItems = [URLQueryItem(name: "feeds", value: uri)]
        guard let url = comps.url,
              let root = await IngestSupport.getJSON(url) as? [String: Any],
              let feed = (root["feeds"] as? [[String: Any]])?.first,
              let name = (feed["displayName"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
        return BlueskyStore.Feed(name: name, uri: uri,
                                 imageURL: IngestSupport.imageURL(feed["avatar"] as? String))
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
