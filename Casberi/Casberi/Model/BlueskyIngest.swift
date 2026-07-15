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

    /// The handles whose public posts land — more than one is a small
    /// following feed of people you care about, not just your own mirror
    /// (2026-07-10). Order is the person's; add/remove are theirs.
    var accounts: [Account] {
        didSet { persist() }
    }

    var connected: Bool { !accounts.isEmpty }
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
    }

    /// Adds a handle, deduped. Returns false if it was empty or already there.
    @discardableResult
    func add(_ raw: String) -> Bool {
        let h = Self.normalize(raw)
        guard !h.isEmpty, !accounts.contains(where: { $0.handle == h }) else { return false }
        accounts.append(Account(handle: h))
        return true
    }

    func remove(_ handle: String) { accounts.removeAll { $0.handle == handle } }
    func removeAll() { accounts = [] }

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
        let accounts = BlueskyStore.shared.accounts
        guard !accounts.isEmpty, !running else { return accounts.isEmpty ? nil : 0 }
        running = true
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

            for entry in feed {
                if let post = entry["post"] as? [String: Any],
                   land(post: post, ownHandle: handle, existing: &existing,
                        backfill: backfill, context: context) {
                    added += 1
                }
            }

            if account.mentions {
                added += await landMentions(of: handle, existing: &existing,
                                            backfill: backfill, context: context)
            }
        }
        // Nothing resolving is the "couldn't find that" signal; one landing
        // means the connection is good.
        guard anyResolved else { return nil }
        if added > 0 || backfill.any || touched { try? context.save() }
        return added
    }

    /// Posts by OTHERS that name this account (searchPosts' `mentions:`
    /// operator) — replies and quotes included, since a mention usually is
    /// one. New ones ride "while I was away" like any landed thing. The
    /// search results hydrate each author (handle, name, avatar), so no
    /// per-mentioner profile lookup is needed.
    @MainActor
    private static func landMentions(of handle: String, existing: inout Set<String>,
                                     backfill: ArtlessBackfill, context: ModelContext) async -> Int {
        var comps = URLComponents(string: "\(searchHost)/app.bsky.feed.searchPosts")!
        comps.queryItems = [URLQueryItem(name: "q", value: "mentions:\(handle)"),
                            URLQueryItem(name: "limit", value: "25")]
        guard let url = comps.url,
              let root = await IngestSupport.getJSON(url) as? [String: Any],
              let posts = root["posts"] as? [[String: Any]] else { return 0 }
        var added = 0
        for post in posts {
            if land(post: post, ownHandle: nil, existing: &existing,
                    backfill: backfill, context: context) {
                added += 1
            }
        }
        return added
    }

    /// Lands one post by whoever wrote it — the shared tail of the author
    /// feed and the mentions flow. `ownHandle` non-nil filters to that
    /// author (the feed excludes reposts of others); nil accepts anyone
    /// (mentions). The author is hydrated on the post, so its name and face
    /// come free; a post the AppView didn't hydrate an author for is skipped.
    @MainActor
    @discardableResult
    private static func land(post: [String: Any], ownHandle: String?,
                             existing: inout Set<String>, backfill: ArtlessBackfill,
                             context: ModelContext) -> Bool {
        guard let uri = post["uri"] as? String,
              let record = post["record"] as? [String: Any],
              let text = record["text"] as? String, !text.isEmpty,
              let author = post["author"] as? [String: Any],
              let authorHandle = author["handle"] as? String, !authorHandle.isEmpty
        else { return false }
        if let ownHandle, authorHandle != ownHandle { return false }
        let ref = "bsky:\(uri)"
        let image = embedThumb(post)
        guard !existing.contains(ref) else {
            backfill.patch(ref, image: image)
            return false
        }
        // at://did:…/app.bsky.feed.post/<rkey> → the web permalink.
        let rkey = uri.split(separator: "/").last.map(String.init) ?? ""
        let link = "https://bsky.app/profile/\(authorHandle)/post/\(rkey)"
        let date = IngestSupport.isoDate(record["createdAt"])

        let thing = Thing(
            kind: .chat,
            title: IngestSupport.titleLine(text),
            content: link,
            source: "Bluesky",
            capturedAt: date ?? .now,
            sourceRef: ref
        )
        thing.previewImageURL = IngestSupport.imageURL(image)
        thing.authorHandle = authorHandle
        thing.authorAvatarURL = IngestSupport.imageURL(author["avatar"] as? String)
        context.insert(thing)
        SpotlightIndex.index([thing])
        existing.insert(ref)
        return true
    }

    // MARK: - Replies (the sheet's thread context, 2026-07-14)

    /// A Bluesky thing's replies — fetched live when the sheet opens, shown
    /// only when there are any. Cached per launch, so reopening is free.
    @MainActor
    static func replies(for thing: Thing, limit: Int = 8) async -> [SocialReply] {
        guard thing.source == "Bluesky", let ref = thing.sourceRef,
              ref.hasPrefix("bsky:") else { return [] }
        return await replies(uri: String(ref.dropFirst("bsky:".count)), limit: limit)
    }

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
                text: text, when: IngestSupport.isoDate(record["createdAt"])))
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

    /// A post's attached image, or an external card's thumb — the AppView
    /// hydrates ready-to-fetch CDN URLs on the post-level embed view. A
    /// text-only post returns nil and keeps the butterfly glyph: the image
    /// leads only when the post actually has one.
    private static func embedThumb(_ post: [String: Any]) -> String? {
        guard let embed = post["embed"] as? [String: Any] else { return nil }
        // Images attached directly, or nested under record-with-media.
        let media = (embed["media"] as? [String: Any]) ?? embed
        if let images = media["images"] as? [[String: Any]],
           let thumb = images.first?["thumb"] as? String { return thumb }
        if let external = media["external"] as? [String: Any],
           let thumb = external["thumb"] as? String { return thumb }
        return nil
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
