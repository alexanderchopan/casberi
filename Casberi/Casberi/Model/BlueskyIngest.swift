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
        /// Watch what they REPOST (2026-07-31) — Farcaster's Recasts toggle,
        /// in Bluesky's noun. Keyless where likes are not: `getActorLikes`
        /// needs an app password, but a repost rides the account's own public
        /// feed, so the one amplification signal Bluesky can honestly offer is
        /// this one.
        var recasts = false
        /// Watch MENTIONS of them — posts naming this account land, so
        /// "while I was away" can answer with who talked to you.
        var mentions = false
        /// This account is YOURS (2026-07-31) — turns on the INBOUND reads in
        /// `SocialInbound`: who replied, who liked your posts, who started
        /// following you. All three are keyless on the AppView, so unlike
        /// likes-you-gave this half needs no sign-in.
        var mine = false

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
            recasts = try c.decodeIfPresent(Bool.self, forKey: .recasts) ?? false
            mentions = try c.decodeIfPresent(Bool.self, forKey: .mentions) ?? false
            mine = try c.decodeIfPresent(Bool.self, forKey: .mine) ?? false
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

    func remove(_ handle: String) {
        accounts.removeAll { $0.handle == handle }
        SocialInbound.FollowerLedger.forget(key: Self.followerLedgerKey(handle))
    }

    /// Teardown clears the whole connection — people and feeds both, plus
    /// every follower ledger, so reconnecting seeds fresh instead of
    /// announcing a year of arrivals as today's news.
    func removeAll() {
        for account in accounts {
            SocialInbound.FollowerLedger.forget(key: Self.followerLedgerKey(account.handle))
        }
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

    func setRecasts(_ on: Bool, for handle: String) {
        guard let i = accounts.firstIndex(where: { $0.handle == handle }) else { return }
        accounts[i].recasts = on
    }

    func setMentions(_ on: Bool, for handle: String) {
        guard let i = accounts.firstIndex(where: { $0.handle == handle }) else { return }
        accounts[i].mentions = on
    }

    func setMine(_ on: Bool, for handle: String) {
        guard let i = accounts.firstIndex(where: { $0.handle == handle }) else { return }
        accounts[i].mine = on
        // Off forgets the follower ledger, so back on seeds fresh instead of
        // announcing everyone who arrived meanwhile as today's news.
        if !on { SocialInbound.FollowerLedger.forget(key: Self.followerLedgerKey(handle)) }
    }

    /// Where one account's seen-followers ledger lives.
    static func followerLedgerKey(_ handle: String) -> String { "bluesky.followers.\(handle)" }

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
    /// name, bio, and the keyless watches Bluesky can honestly offer:
    /// Reposts and Mentions (likes still need sign-in).
    var socialAccounts: [SocialAccount] {
        accounts.map { a in
            SocialAccount(
                key: a.handle,
                title: a.displayName ?? "@\(Self.short(a.handle))",
                subtitle: SocialAccount.subtitle(handle: "@\(Self.short(a.handle))", bio: a.bio),
                avatarURL: a.avatarURL,
                watches: [SocialWatch(kind: .recasts, on: a.recasts, word: "Reposts"),
                          SocialWatch(kind: .mentions, on: a.mentions),
                          SocialWatch(kind: .mine, on: a.mine)])
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
        resurfaced = 0
        defer { running = false }

        var existing = IngestSupport.existingSourceRefs(context, source: "Bluesky")
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

            if account.recasts {
                added += await landReposts(feed, existing: &existing, landed: landed,
                                           backfill: backfill, context: context)
            }
            if account.mentions {
                added += await landMentions(of: handle, existing: &existing, landed: landed,
                                            backfill: backfill, context: context)
            }
            if account.mine {
                added += await landInbound(handle: handle, existing: &existing, landed: landed,
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

    // MARK: - Inbound: what happened to YOU (2026-07-31)

    /// The three inbound reads for an account marked `mine` — replies to your
    /// posts, likes on them, and new followers. See `SocialInbound` for the
    /// doctrine; the Farcaster arm is `FarcasterIngest.landInbound`, and the
    /// two are deliberately the same shape.
    ///
    /// Every endpoint here is on the AppView's UNAUTHENTICATED host. That's
    /// the happy divergence from likes-you-gave, which stays unbuilt because
    /// `getActorLikes` needs an app password: what happens TO you is public
    /// on Bluesky even though what you did is not.
    @MainActor
    private static func landInbound(handle: String, existing: inout Set<String>,
                                    landed: [String: Thing], backfill: ArtlessBackfill,
                                    context: ModelContext) async -> Int {
        let mine = SocialInbound.ownRecentPosts(landed, handle: handle, refPrefix: "bsky:")
        var added = 0
        for post in mine {
            guard post.isLive, let ref = post.sourceRef else { continue }
            let uri = String(ref.dropFirst("bsky:".count))
            added += await landReplies(to: uri, ownHandle: handle, existing: &existing,
                                       landed: landed, backfill: backfill, context: context)
            await readLikes(on: post, uri: uri, ownHandle: handle)
        }
        added += await landFollowers(handle: handle, existing: &existing, context: context)
        return added
    }

    /// The replies under one of YOUR posts, landed as things. `searchPosts
    /// mentions:` can't see these — a Bluesky reply names its parent in the
    /// record, not in the text, so answering someone never mentions them.
    @MainActor
    private static func landReplies(to uri: String, ownHandle: String,
                                    existing: inout Set<String>, landed: [String: Thing],
                                    backfill: ArtlessBackfill,
                                    context: ModelContext) async -> Int {
        var comps = URLComponents(string: "\(host)/app.bsky.feed.getPostThread")!
        comps.queryItems = [URLQueryItem(name: "uri", value: uri),
                            URLQueryItem(name: "depth", value: "1")]
        guard let url = comps.url,
              let root = await IngestSupport.getJSON(url) as? [String: Any],
              let thread = root["thread"] as? [String: Any],
              let raw = thread["replies"] as? [[String: Any]] else { return 0 }
        // A blocked or deleted reply comes back as a stub with no `post` —
        // compactMap drops those. Your OWN replies in your own thread aren't
        // someone replying to you, so they go too.
        let posts = raw.compactMap { $0["post"] as? [String: Any] }
            .filter { (($0["author"] as? [String: Any])?["handle"] as? String) != ownHandle }
        guard !posts.isEmpty else { return 0 }
        return await landPage(posts, why: "reply", existing: &existing, landed: landed,
                              backfill: backfill, context: context)
    }

    /// Who liked one of YOUR posts. The AppView already hydrates an exact
    /// `likeCount` on every post view (that's what `applyCounts` stores), so
    /// unlike the Farcaster arm this read is not about the NUMBER at all — it
    /// is only ever about the NAMES, which the count can never carry: a like
    /// from someone you watch resurfaces the post and says so once.
    @MainActor
    private static func readLikes(on post: Thing, uri: String, ownHandle: String) async {
        var comps = URLComponents(string: "\(host)/app.bsky.feed.getLikes")!
        comps.queryItems = [URLQueryItem(name: "uri", value: uri),
                            URLQueryItem(name: "limit", value: "100")]
        guard let url = comps.url,
              let root = await IngestSupport.getJSON(url) as? [String: Any],
              let likes = root["likes"] as? [[String: Any]] else { return }
        guard post.isLive else { return }   // the pass awaited; a heal may have landed
        let watched = Set(BlueskyStore.shared.accounts.map(\.handle))
        for like in likes {
            guard let actor = like["actor"] as? [String: Any],
                  let liker = actor["handle"] as? String,
                  liker != ownHandle, watched.contains(liker) else { continue }
            let when = IngestSupport.isoDate(like["createdAt"])
                ?? IngestSupport.isoDate(like["indexedAt"])
            resurface(post, reactedAt: when)
            if (when ?? .now).timeIntervalSinceNow > -SocialInbound.newsWindow {
                SourceMoments.shared.fire(
                    String(localized: "@\(BlueskyStore.short(liker)) liked your post"),
                    source: "Bluesky")
            }
        }
    }

    /// Who started following you since the last pass. First sight seeds the
    /// ledger SILENTLY.
    ///
    /// The AppView returns followers newest-first but carries NO follow
    /// timestamp anywhere in the payload — which is exactly why
    /// `SocialInbound.FollowerLedger` is a set rather than a cursor, and why a
    /// landed follower here is stamped `.now` (when you learned of it) rather
    /// than with a date the network never told us.
    @MainActor
    private static func landFollowers(handle: String, existing: inout Set<String>,
                                      context: ModelContext) async -> Int {
        var comps = URLComponents(string: "\(host)/app.bsky.graph.getFollowers")!
        comps.queryItems = [URLQueryItem(name: "actor", value: handle),
                            URLQueryItem(name: "limit", value: "50")]
        guard let url = comps.url,
              let root = await IngestSupport.getJSON(url) as? [String: Any],
              let followers = root["followers"] as? [[String: Any]] else { return 0 }
        let byDID = Dictionary(
            followers.compactMap { profile -> (String, [String: Any])? in
                guard let did = profile["did"] as? String else { return nil }
                return (did, profile)
            }, uniquingKeysWith: { first, _ in first })
        let order = followers.compactMap { $0["did"] as? String }
        guard !order.isEmpty else { return 0 }

        var ledger = SocialInbound.FollowerLedger(key: BlueskyStore.followerLedgerKey(handle))
        let firstSight = ledger.isFirstSight
        let fresh = ledger.newcomers(in: order)
        ledger.record(order)
        guard !firstSight, !fresh.isEmpty else { return 0 }

        var added = 0
        for did in fresh.prefix(SocialInbound.followerLandCap) {
            guard let profile = byDID[did],
                  let followerHandle = profile["handle"] as? String,
                  !followerHandle.isEmpty else { continue }
            guard SocialInbound.landFollower(
                id: did, handle: BlueskyStore.short(followerHandle),
                displayName: profile["displayName"] as? String,
                avatarURL: IngestSupport.imageURL(profile["avatar"] as? String),
                profileURL: "https://bsky.app/profile/\(followerHandle)",
                when: nil, source: "Bluesky", existing: &existing, context: context) != nil
            else { continue }
            added += 1
            SourceMoments.shared.fire(
                String(localized: "@\(BlueskyStore.short(followerHandle)) started following you"),
                source: "Bluesky")
        }
        return added
    }

    // MARK: - Reposts (2026-07-31)

    /// How recent a repost has to be to count as NEWS — the window inside
    /// which one may resurface a post the corpus already holds. Farcaster's
    /// `likeNewsWindow`, same 24h, same reasoning: switching Reposts on for
    /// an account with a long history must not throw their back catalogue at
    /// the top of the feed.
    private static let repostNewsWindow: TimeInterval = 86_400

    /// The posts a watched account REPOSTED, out of the author feed already
    /// in hand — so this costs NO extra request, unlike Farcaster's separate
    /// `reactionsByFid` read. Each lands stamped with the REPOST's time (when
    /// it entered your attention), not the post's, exactly as a Farcaster
    /// like/recast does.
    ///
    /// A repost arrives as a feed ENTRY wearing a `reason`, wrapping someone
    /// else's `post` — which is precisely why `land`'s `ownHandle` filter used
    /// to drop every one of them on the floor (the filter is what keeps a
    /// mention's author out of the account feed, and it can't tell the two
    /// cases apart). This reads the entries the filter discards.
    ///
    /// A post the corpus already holds RESURFACES rather than being skipped —
    /// §221's ruling, which was written for Farcaster likes and is the same
    /// bug here: your own post, reposted by someone you watch, is exactly the
    /// shape that could never come back.
    ///
    /// UNMEASURED (2026-07-31, no network from the authoring host): the author
    /// feed is fetched with `filter=posts_no_replies`, and whether the AppView
    /// includes repost entries under that filter is the one fact to check
    /// before trusting this. If it strips them, nothing lands (an honest
    /// silence, not a wrong answer) and the fix is the filter, not this code.
    @MainActor
    private static func landReposts(_ feed: [[String: Any]], existing: inout Set<String>,
                                    landed: [String: Thing], backfill: ArtlessBackfill,
                                    context: ModelContext) async -> Int {
        var reposts: [(post: [String: Any], at: Date?)] = []
        for entry in feed {
            guard let reason = entry["reason"] as? [String: Any],
                  let type = reason["$type"] as? String,
                  type.hasSuffix("#reasonRepost"),
                  let post = entry["post"] as? [String: Any],
                  let uri = post["uri"] as? String else { continue }
            // `indexedAt` on the REASON is when the repost happened; the
            // post's own `createdAt` is when it was written, often long
            // before. The distinction is the whole point of the stamp.
            let at = IngestSupport.isoDate(reason["indexedAt"])
            guard !existing.contains("bsky:\(uri)") else {
                resurface(landed["bsky:\(uri)"], reactedAt: at)
                continue
            }
            reposts.append((post, at))
        }
        guard !reposts.isEmpty else { return 0 }
        await prefetchCards(reposts.compactMap { parentURI($0.post) })
        var added = 0
        for repost in reposts {
            // ownHandle nil — a repost is by definition someone ELSE's post,
            // so the author filter that guards the account feed must not run.
            if await land(post: repost.post, ownHandle: nil, capturedAt: repost.at,
                          why: "recast", existing: &existing, landed: landed,
                          backfill: backfill, context: context) {
                added += 1
            }
        }
        return added
    }

    /// Restamps a post the corpus already holds with the moment someone
    /// reacted to it — a watched account reposting it (`landReposts`), or
    /// anyone liking one of YOUR posts (`readLikes`). `FarcasterIngest.
    /// resurface`, same three guards (forward only, news only, live only) and
    /// the same convergence argument: once `capturedAt` IS the reaction's
    /// time, the forward-only guard stops firing, so no cursor is needed to
    /// make it once-only.
    @MainActor
    private static func resurface(_ thing: Thing?, reactedAt: Date?) {
        guard let thing, thing.isLive, let reactedAt,
              reactedAt > thing.capturedAt,
              Date.now.timeIntervalSince(reactedAt) < repostNewsWindow else { return }
        thing.capturedAt = reactedAt
        // Joins the refresh's save condition — a pass that only resurfaced
        // landed nothing new, and must still persist what it moved.
        healed = true
        resurfaced += 1
    }

    /// How many held posts the last refresh moved back into view. A resurface
    /// lands no thing, so `refresh`'s count reports 0 for a pass that did the
    /// whole job — without this a probe can't tell that from a pass that did
    /// nothing. Reset per refresh, like `healed`, under the same single-flight
    /// `running` guard.
    @MainActor private(set) static var resurfaced = 0

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
    /// feed, the mentions flow, and the repost flow. `ownHandle` non-nil
    /// filters to that author, which is what keeps someone else's post out of
    /// an account's own feed; nil accepts anyone (mentions, reposts — both are
    /// by definition NOT the watched account's own words). The author is
    /// hydrated on the post, so its name and face come free; a post the
    /// AppView didn't hydrate an author for is skipped.
    @MainActor
    @discardableResult
    private static func land(post: [String: Any], ownHandle: String?,
                             capturedAt: Date? = nil,
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
        // A repost stamps the post with when it was AMPLIFIED, not when it was
        // written (`landReposts`); everything else uses the post's own date.
        let date = capturedAt ?? IngestSupport.isoDate(record["createdAt"])

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
        // Item 1 of the 2026-07-27 social pass: a post sharing an article
        // used to keep only the permalink — the article itself never entered
        // the corpus, invisible to Find/Retriever/the themes map. Landed as
        // its own `.link` thing, deduped through the same `existing` set.
        if let link = linkEmbed(post) {
            landLinkedArticle(link, sharedBy: authorHandle, capturedAt: date ?? .now,
                              existing: &existing, context: context)
        }
        // Item 5 of the 2026-07-27 polish pass: a mention is the highest-
        // signal event social has, and it used to land silently. Fires the
        // same delight bus a wallet high or a quiet-account return already
        // rides. NEWS ONLY (the Privacy Pools/§221 doctrine): a mention
        // older than a day heals in silently — connecting an account for
        // the first time shouldn't rain 40 toasts for months of old @s.
        if why == "mention", (date ?? .now).timeIntervalSinceNow > -86400 {
            SourceMoments.shared.fire(
                String(localized: "@\(authorHandle) mentioned you"), source: "Bluesky")
        }
        // "The crossing" (item 6 of the 2026-07-27 polish pass): two watched
        // accounts replying to or quoting each other. Detected purely from
        // data already on the landed thing — `parent`/`quote` both carry the
        // referenced post's author — so this is a pure corpus join, not a
        // network read, and nothing else on the phone can see it.
        fireCrossingIfWatched(author: authorHandle, other: thing.parent?.handle ?? thing.quote?.handle,
                              when: date)
        return true
    }

    /// Fires the crossing moment when BOTH sides of a reply/quote are
    /// accounts this account watches — never when only one is (that's an
    /// ordinary mention or an ordinary post). NEWS ONLY, the mention
    /// moment's own discipline: an old crossing heals in silently, so
    /// connecting an account doesn't rain for months of history.
    @MainActor
    private static func fireCrossingIfWatched(author: String, other: String?, when: Date?) {
        guard let other, other != author,
              (when ?? .now).timeIntervalSinceNow > -86400 else { return }
        let watched = Set(BlueskyStore.shared.accounts.map(\.handle))
        guard watched.contains(author), watched.contains(other) else { return }
        SourceMoments.shared.fire(
            String(localized: "@\(author) and @\(other) are talking"), source: "Bluesky")
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

    // MARK: - Delete-sync (2026-07-23)

    @MainActor private static var healRunning = false
    private static let healInterval: TimeInterval = 3600
    private static let healKey = "bluesky.lastHeal"

    /// Reconciles against what the AppView still serves — a post deleted by
    /// its author (or removed) never tells Casberi. `getPosts` answers only
    /// for uris it can still serve and silently omits the rest — no error,
    /// no partial-failure marker (verified live 2026-07-23: a real uri plus
    /// a fabricated one in one request → HTTP 200, one post back, the fake
    /// one just missing) — so "asked for, not returned" IS the deleted set,
    /// the same shape as Mail's UID FETCH. Batched 25 at a time (`getPosts`'
    /// own cap); a failed CHUNK is `continue`d past rather than counted, so
    /// a transient network blip can never read as a mass delete — only a uri
    /// whose chunk actually got an answer is eligible to be "not returned".
    /// Throttled like Mail's heal: a real network round trip, not a local
    /// check like Photos'.
    @MainActor
    static func heal(context: ModelContext, force: Bool = false) async -> Int {
        guard !healRunning else { return 0 }
        if !force, let last = UserDefaults.standard.object(forKey: healKey) as? Date,
           Date.now.timeIntervalSince(last) < healInterval { return 0 }
        healRunning = true
        defer { healRunning = false }
        UserDefaults.standard.set(Date.now, forKey: healKey)

        let things = IngestSupport.thingsByRef(context, source: "Bluesky")
        let uriToRef = Dictionary(uniqueKeysWithValues: things.keys
            .filter { $0.hasPrefix("bsky:") }
            .map { (String($0.dropFirst("bsky:".count)), $0) })
        guard !uriToRef.isEmpty else { return 0 }

        var present = Set<String>()
        var attempted = Set<String>()
        let uris = Array(uriToRef.keys)
        for start in stride(from: 0, to: uris.count, by: 25) {
            let chunk = Array(uris[start..<min(start + 25, uris.count)])
            var comps = URLComponents(string: "\(host)/app.bsky.feed.getPosts")!
            comps.queryItems = chunk.map { URLQueryItem(name: "uris", value: $0) }
            guard let url = comps.url,
                  let root = await IngestSupport.getJSON(url) as? [String: Any],
                  let posts = root["posts"] as? [[String: Any]] else { continue }
            attempted.formUnion(chunk)
            for post in posts {
                if let uri = post["uri"] as? String { present.insert(uri) }
            }
        }

        var removedIDs: [UUID] = []
        for (uri, ref) in uriToRef where attempted.contains(uri) && !present.contains(uri) {
            guard let thing = things[ref] else { continue }
            removedIDs.append(thing.id)
            context.delete(thing)
        }
        guard !removedIDs.isEmpty else { return 0 }
        context.saveHonestly()
        SpotlightIndex.remove(ids: removedIDs)
        return removedIDs.count
    }

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

    /// The post's external-link card, when it has one — Bluesky's AppView
    /// fully hydrates a shared article's title, description, and thumbnail
    /// (unlike Farcaster's bare embedded URL), so landing it costs no extra
    /// fetch. A post whose external embed carries an image thumb but no
    /// article (rare) still qualifies — `title` simply comes back nil and
    /// `landLinkedArticle` falls back to a live title fetch.
    private static func linkEmbed(_ post: [String: Any]) -> (url: String, title: String?, thumb: String?)? {
        guard let embed = post["embed"] as? [String: Any] else { return nil }
        let media = (embed["media"] as? [String: Any]) ?? embed
        guard let external = media["external"] as? [String: Any],
              let uri = external["uri"] as? String, !uri.isEmpty else { return nil }
        return (uri, external["title"] as? String, external["thumb"] as? String)
    }

    /// Lands a post's shared article as its own `.link` thing — a real,
    /// separately retrievable record, not just a URL sitting inside the
    /// post's `postText`. Dedupes through the SAME `existing` set posts use,
    /// keyed on the URL, so the same article shared twice never lands twice.
    @MainActor
    private static func landLinkedArticle(_ link: (url: String, title: String?, thumb: String?),
                                          sharedBy handle: String, capturedAt: Date,
                                          existing: inout Set<String>, context: ModelContext) {
        let ref = "link:\(link.url)"
        guard !existing.contains(ref) else { return }
        existing.insert(ref)
        let hasTitle = (link.title?.isEmpty == false)
        let thing = Thing(
            kind: .link,
            title: hasTitle ? link.title! : link.url,
            content: link.url,
            source: "Bluesky",
            capturedAt: capturedAt,
            sourceRef: ref
        )
        thing.authorHandle = handle
        thing.previewImageURL = IngestSupport.imageURL(link.thumb)
        context.insert(thing)
        SpotlightIndex.index([thing])
        // Bluesky hydrates the title already; only fall back to a live fetch
        // (the established detached pattern, `RootShell`'s paste-a-link path)
        // when the AppView's own card carried none.
        if !hasTitle {
            Task { @MainActor in await LinkTitle.enrich(thing, context: context) }
        }
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
