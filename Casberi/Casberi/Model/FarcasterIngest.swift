import Foundation
import Observation
import SwiftData

/// The Farcaster bridge (2026-07-07) — like Bluesky, an open protocol whose
/// posts are public: a username alone connects it. The Farcaster team's own
/// public Snapchain node serves name→fid and a person's casts with no key
/// and no password. Casts land as chat things linking to farcaster.xyz.
/// Grown 2026-07-14: the same keyless node also serves an account's LIKES
/// (like it there, it lands here), MENTIONS of them (rides "while I was
/// away"), CHANNEL feeds (/design by name, a topic beside the people), a
/// cast's replies (the thing sheet shows the thread), and profile facts
/// (the account row wears the face, display name, and bio).
@Observable
final class FarcasterStore {
    static let shared = FarcasterStore()
    private static let key = "farcaster.accounts"
    private static let channelsKey = "farcaster.channels"
    private static let legacyNameKey = "farcaster.username"
    private static let legacyFidKey = "farcaster.fid"

    struct Account: Codable, Identifiable, Equatable {
        var id = UUID()
        var username: String
        /// Resolved once per username, then cached (name→fid costs a request).
        var fid: Int = 0
        /// Profile facts the node serves — refreshed each sync, worn by the
        /// account row (display name over @username · bio).
        var displayName: String?
        var bio: String?
        var avatarURL: String?
        /// Watch what they LIKE too — liked casts land as things. On your
        /// own account that is the save verb: like it on Farcaster, it's here.
        var likes = false
        /// Watch MENTIONS of them — casts naming this account land, so
        /// "while I was away" can answer with who talked to you.
        var mentions = false

        init(username: String, fid: Int = 0) {
            self.username = username
            self.fid = fid
        }

        /// Accounts persisted before the likes/mentions/profile fields
        /// decode with defaults instead of failing the whole list.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            username = try c.decode(String.self, forKey: .username)
            fid = try c.decodeIfPresent(Int.self, forKey: .fid) ?? 0
            displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
            bio = try c.decodeIfPresent(String.self, forKey: .bio)
            avatarURL = try c.decodeIfPresent(String.self, forKey: .avatarURL)
            likes = try c.decodeIfPresent(Bool.self, forKey: .likes) ?? false
            mentions = try c.decodeIfPresent(Bool.self, forKey: .mentions) ?? false
        }
    }

    /// A followed channel — the name resolves once against the channel
    /// directory (name → the protocol parent URL its casts hang under) and
    /// the url is cached, the way an account caches its fid.
    struct Channel: Codable, Identifiable, Equatable {
        var id = UUID()
        var name: String
        var url: String
        var imageURL: String?
    }

    /// The usernames whose public casts land — more than one is a small
    /// following feed, not just your own mirror (2026-07-10).
    var accounts: [Account] {
        didSet { persist() }
    }

    /// The followed channels — topic feeds beside the people (2026-07-14).
    var channels: [Channel] {
        didSet { persistChannels() }
    }

    var connected: Bool { !accounts.isEmpty || !channels.isEmpty }
    var usernames: [String] { accounts.map(\.username) }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([Account].self, from: data) {
            accounts = saved
        } else if let legacy = UserDefaults.standard.string(forKey: Self.legacyNameKey),
                  !legacy.isEmpty {
            let fid = UserDefaults.standard.integer(forKey: Self.legacyFidKey)
            accounts = [Account(username: legacy, fid: fid)]   // migrate the single name
        } else {
            accounts = []
        }
        if let data = UserDefaults.standard.data(forKey: Self.channelsKey),
           let saved = try? JSONDecoder().decode([Channel].self, from: data) {
            channels = saved
        } else {
            channels = []
        }
    }

    @discardableResult
    func add(_ raw: String) -> Bool {
        let n = Self.normalize(raw)
        guard !n.isEmpty, !accounts.contains(where: { $0.username == n }) else { return false }
        accounts.append(Account(username: n))
        return true
    }

    func remove(_ username: String) { accounts.removeAll { $0.username == username } }

    /// Teardown clears the whole connection — people and channels both.
    func removeAll() {
        accounts = []
        channels = []
    }

    /// Adds a username together with an already-known fid — search resolves
    /// both in one call, so this skips the first sync's separate name→fid
    /// lookup for it (the fid-caching invariant lives here, not in a caller).
    @discardableResult
    func add(_ raw: String, fid: Int) -> Bool {
        let added = add(raw)
        setFid(fid, for: Self.normalize(raw))
        return added
    }

    /// Caches an fid once resolved, so the name→fid lookup runs once per name.
    func setFid(_ fid: Int, for username: String) {
        guard let i = accounts.firstIndex(where: { $0.username == username }) else { return }
        accounts[i].fid = fid
    }

    /// Sync's write-back of the node's profile facts — the account row wears
    /// the face and the words. One assignment, so the array's didSet
    /// (→ persist) fires once, not once per field.
    func setProfile(_ profile: FarcasterIngest.Profile, for username: String) {
        guard let i = accounts.firstIndex(where: { $0.username == username }) else { return }
        var a = accounts[i]
        a.displayName = profile.displayName
        a.bio = profile.bio
        a.avatarURL = profile.avatarURL
        accounts[i] = a
    }

    func setLikes(_ on: Bool, for username: String) {
        guard let i = accounts.firstIndex(where: { $0.username == username }) else { return }
        accounts[i].likes = on
    }

    func setMentions(_ on: Bool, for username: String) {
        guard let i = accounts.firstIndex(where: { $0.username == username }) else { return }
        accounts[i].mentions = on
    }

    @discardableResult
    func addChannel(_ channel: Channel) -> Bool {
        guard !channels.contains(where: { $0.name == channel.name }) else { return false }
        channels.append(channel)
        return true
    }

    func removeChannel(_ name: String) { channels.removeAll { $0.name == name } }

    /// The name a cast's row shows. Your ONE watched mirror stays unlabeled
    /// (redundant); everything else — several accounts, a liked cast's
    /// author, a channel's caster — names itself, the Bluesky/Wallet voice.
    func rowLabel(for username: String?) -> String? {
        guard let username, !username.isEmpty else { return nil }
        if accounts.count == 1, accounts[0].username == username { return nil }
        return "@\(username)"
    }

    /// The watched accounts as the shared setup row renders them — face,
    /// name, bio, and the Likes/Mentions toggles Farcaster offers.
    var socialAccounts: [SocialAccount] {
        accounts.map { a in
            SocialAccount(
                key: a.username,
                title: a.displayName ?? a.username,
                subtitle: SocialAccount.subtitle(handle: "@\(a.username)", bio: a.bio),
                avatarURL: a.avatarURL,
                watches: [SocialWatch(kind: .likes, on: a.likes),
                          SocialWatch(kind: .mentions, on: a.mentions)])
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(accounts) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    private func persistChannels() {
        if let data = try? JSONEncoder().encode(channels) {
            UserDefaults.standard.set(data, forKey: Self.channelsKey)
        }
    }

    /// "@dwr" and "dwr.eth" both normalize to the registered name.
    static func normalize(_ raw: String) -> String {
        var n = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for junk in ["https://", "http://", "www.", "farcaster.xyz/", "warpcast.com/", "@"] {
            if n.hasPrefix(junk) { n.removeFirst(junk.count) }
        }
        if let slash = n.firstIndex(of: "/") { n = String(n[..<slash]) }
        return n
    }

    /// "/design", "design", and a pasted channel URL all normalize to the
    /// bare channel name.
    static func normalizeChannel(_ raw: String) -> String {
        var n = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for junk in ["https://", "http://", "www.",
                     "farcaster.xyz/~/channel/", "warpcast.com/~/channel/"] {
            if n.hasPrefix(junk) { n.removeFirst(junk.count) }
        }
        while n.hasPrefix("/") { n.removeFirst() }
        if let slash = n.firstIndex(of: "/") { n = String(n[..<slash]) }
        return n
    }
}

enum FarcasterIngest {

    private static let node = "https://snap.farcaster.xyz:3381"
    /// Snapchain timestamps count seconds from the Farcaster epoch.
    private static let epoch = Date(timeIntervalSince1970: 1_609_459_200)

    @MainActor private static var running = false

    /// Profile facts by fid, cached per launch — likes, channels, mentions,
    /// and replies all surface OTHER people's casts, and each unique author
    /// costs one userDataByFid call, ever.
    struct Profile {
        var username: String?
        var displayName: String?
        var bio: String?
        var avatarURL: String?
    }
    @MainActor private static var profiles: [Int: Profile] = [:]

    /// Resolves each username (once), fetches recent casts — plus likes and
    /// mentions where those are watched, and every followed channel's feed —
    /// and lands new ones as chat things. Returns the new count, or nil when
    /// nothing could be resolved.
    @MainActor
    static func refresh(context: ModelContext) async -> Int? {
        let store = FarcasterStore.shared
        guard store.connected, !running else {
            return store.connected ? 0 : nil
        }
        running = true
        defer { running = false }

        var existing = IngestSupport.existingSourceRefs(context)
        let landed = IngestSupport.thingsByRef(context, source: "Farcaster")
        let backfill = ArtlessBackfill(context, source: "Farcaster")
        var added = 0
        var touched = false
        var anyResolved = false

        for account in store.accounts {
            var fid = account.fid
            if fid == 0 {
                guard let proof = await IngestSupport.getJSON(
                    "\(node)/v1/userNameProofByName?name=\(account.username)") as? [String: Any],
                      let resolved = proof["fid"] as? Int else { continue }
                fid = resolved
                store.setFid(fid, for: account.username)
            }

            guard let root = await IngestSupport.getJSON(
                "\(node)/v1/castsByFid?fid=\(fid)&pageSize=30&reverse=true") as? [String: Any],
                  let messages = root["messages"] as? [[String: Any]] else { continue }
            anyResolved = true

            // One profile lookup covers the cast avatars AND the account
            // row's display name and bio (2026-07-14). A failed fetch
            // changes nothing — stored facts never get clobbered by nils.
            let who = await profile(fid: fid)
            if let who, who.username != nil,
               who.displayName != account.displayName || who.bio != account.bio
                || who.avatarURL != account.avatarURL {
                store.setProfile(who, for: account.username)
            }
            // Backfill the face onto EVERY existing cast of theirs that
            // predates the field, so the whole feed wears faces, not just
            // casts landed since (2026-07-10, user: they expected the
            // author's avatar).
            if let avatar = who?.avatarURL {
                for t in landed.values where t.authorAvatarURL == nil
                    && t.content.contains("/\(account.username)/") {
                    t.authorHandle = account.username
                    t.authorAvatarURL = avatar
                    touched = true
                }
            }

            added += await landPage(messages, topLevelOnly: true, existing: &existing,
                                    backfill: backfill, context: context)

            if account.likes {
                added += await landLikes(fid: fid, existing: &existing,
                                         backfill: backfill, context: context)
            }
            if account.mentions {
                added += await landMentions(of: fid, existing: &existing,
                                            backfill: backfill, context: context)
            }
        }

        for channel in store.channels {
            let landed = await landChannel(channel, existing: &existing,
                                           backfill: backfill, context: context)
            if let landed {
                anyResolved = true
                added += landed
            }
        }

        guard anyResolved else { return nil }
        if added > 0 || backfill.any || touched { try? context.save() }
        return added
    }

    // MARK: - Likes, mentions, channels (2026-07-14)

    /// The account's likes — each liked cast lands as a thing, stamped with
    /// the LIKE's time (when it entered your attention), not the cast's.
    @MainActor
    private static func landLikes(fid: Int, existing: inout Set<String>,
                                  backfill: ArtlessBackfill, context: ModelContext) async -> Int {
        guard let root = await IngestSupport.getJSON(
            "\(node)/v1/reactionsByFid?fid=\(fid)&reaction_type=Like&pageSize=25&reverse=true")
                as? [String: Any],
              let messages = root["messages"] as? [[String: Any]] else { return 0 }
        var targets: [(fid: Int, hash: String, liked: Date?)] = []
        for message in messages {
            guard let data = message["data"] as? [String: Any],
                  let body = data["reactionBody"] as? [String: Any],
                  let target = body["targetCastId"] as? [String: Any],
                  let targetFid = target["fid"] as? Int,
                  let targetHash = target["hash"] as? String,
                  !existing.contains("fc:\(targetHash)") else { continue }
            targets.append((targetFid, targetHash,
                            (data["timestamp"] as? Double).map { epoch.addingTimeInterval($0) }))
        }
        guard !targets.isEmpty else { return 0 }
        // The liked casts' bodies, a few at a time — the ref dedupe above
        // keeps the steady state at zero of these lookups.
        let casts = await IngestSupport.boundedGather(targets, maxConcurrent: 4) { t in
            await IngestSupport.getJSON("\(node)/v1/castById?fid=\(t.fid)&hash=\(t.hash)")
                as? [String: Any]
        }
        await prefetchProfiles(targets.map(\.fid))
        var added = 0
        for (target, cast) in zip(targets, casts) {
            guard let cast else { continue }
            if await land(cast: cast, capturedAt: target.liked, existing: &existing,
                          backfill: backfill, context: context) {
                added += 1
            }
        }
        return added
    }

    /// Casts by OTHERS that name this account — replies included, since a
    /// mention usually is one. New ones ride "while I was away" like any
    /// landed thing.
    @MainActor
    private static func landMentions(of fid: Int, existing: inout Set<String>,
                                     backfill: ArtlessBackfill, context: ModelContext) async -> Int {
        guard let root = await IngestSupport.getJSON(
            "\(node)/v1/castsByMention?fid=\(fid)&pageSize=25&reverse=true") as? [String: Any],
              let messages = root["messages"] as? [[String: Any]] else { return 0 }
        return await landPage(messages, existing: &existing,
                              backfill: backfill, context: context)
    }

    /// A followed channel's newest top-level casts. Returns nil when the
    /// node didn't answer (so a channels-only refresh can still say so).
    @MainActor
    private static func landChannel(_ channel: FarcasterStore.Channel,
                                    existing: inout Set<String>, backfill: ArtlessBackfill,
                                    context: ModelContext) async -> Int? {
        var comps = URLComponents(string: "\(node)/v1/castsByParent")!
        comps.queryItems = [URLQueryItem(name: "url", value: channel.url),
                            URLQueryItem(name: "pageSize", value: "25"),
                            URLQueryItem(name: "reverse", value: "true")]
        guard let url = comps.url,
              let root = await IngestSupport.getJSON(url) as? [String: Any],
              let messages = root["messages"] as? [[String: Any]] else { return nil }
        // castsByParent serves DOUBLE the asked pageSize (verified live:
        // 25 → 50) — cap here so a channel sync stays a page, not a flood.
        return await landPage(Array(messages.prefix(25)), existing: &existing,
                              backfill: backfill, context: context)
    }

    /// Lands a page of casts: one capped fan-out warms the profile cache
    /// for every new cast's author and mentions, then each cast lands in
    /// order off the cache — the shared tail of every flow, so a page
    /// never pays one serial profile round-trip per cast.
    @MainActor
    private static func landPage(_ messages: [[String: Any]], topLevelOnly: Bool = false,
                                 existing: inout Set<String>, backfill: ArtlessBackfill,
                                 context: ModelContext) async -> Int {
        var fids: [Int] = []
        for message in messages {
            guard let hash = message["hash"] as? String, !existing.contains("fc:\(hash)"),
                  let data = message["data"] as? [String: Any],
                  let body = data["castAddBody"] as? [String: Any] else { continue }
            if let fid = data["fid"] as? Int { fids.append(fid) }
            fids.append(contentsOf: (body["mentions"] as? [Int]) ?? [])
        }
        await prefetchProfiles(fids)
        var added = 0
        for message in messages {
            if await land(cast: message, topLevelOnly: topLevelOnly, existing: &existing,
                          backfill: backfill, context: context) {
                added += 1
            }
        }
        return added
    }

    /// Lands one cast by whoever wrote it. The author's name and face come
    /// from the per-fid profile cache; a cast whose author can't be named
    /// right now is skipped, not lost — its ref never enters the corpus, so
    /// the next refresh retries it (its permalink needs the username).
    @MainActor
    private static func land(cast message: [String: Any], topLevelOnly: Bool = false,
                             capturedAt: Date? = nil,
                             existing: inout Set<String>, backfill: ArtlessBackfill,
                             context: ModelContext) async -> Bool {
        guard let hash = message["hash"] as? String,
              let data = message["data"] as? [String: Any],
              let casterFid = data["fid"] as? Int,
              let body = data["castAddBody"] as? [String: Any],
              let text = body["text"] as? String, !text.isEmpty else { return false }
        if topLevelOnly,
           !(body["parentCastId"] is NSNull || body["parentCastId"] == nil) {
            return false   // casts, not replies (the mirror's rule)
        }
        let ref = "fc:\(hash)"
        let image = imageEmbed(body)
        guard !existing.contains(ref) else {
            backfill.patch(ref, image: image)
            return false
        }
        guard let author = await profile(fid: casterFid),
              let username = author.username, !username.isEmpty else { return false }

        let short = String(hash.prefix(10))
        let when = capturedAt
            ?? (data["timestamp"] as? Double).map { epoch.addingTimeInterval($0) }
        let thing = Thing(
            kind: .chat,
            title: IngestSupport.titleLine(await splicingMentions(into: text, body: body)),
            content: "https://farcaster.xyz/\(username)/\(short)",
            source: "Farcaster",
            capturedAt: when ?? .now,
            sourceRef: ref
        )
        thing.previewImageURL = IngestSupport.imageURL(image)
        thing.authorHandle = username
        thing.authorAvatarURL = author.avatarURL
        context.insert(thing)
        SpotlightIndex.index([thing])
        existing.insert(ref)
        return true
    }

    // MARK: - Channels: name → parent URL

    /// name → the channel's protocol parent URL plus its face, via the
    /// channel directory (the Farcaster client API; the warpcast.com twin
    /// answers if the primary host ever moves). nil when no such channel.
    static func resolveChannel(_ raw: String) async -> FarcasterStore.Channel? {
        let name = FarcasterStore.normalizeChannel(raw)
        guard !name.isEmpty,
              let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        else { return nil }
        for host in ["https://api.farcaster.xyz", "https://api.warpcast.com"] {
            guard let root = await IngestSupport.getJSON(
                "\(host)/v1/channel?channelId=\(encoded)") as? [String: Any],
                  let result = root["result"] as? [String: Any],
                  let channel = result["channel"] as? [String: Any],
                  let url = channel["url"] as? String, !url.isEmpty else { continue }
            return FarcasterStore.Channel(
                name: name, url: url,
                imageURL: IngestSupport.imageURL(channel["imageUrl"] as? String))
        }
        return nil
    }

    /// Resolve-and-follow in one move — the setup screen's Follow and the
    /// `-fcChannel` probe both come through here.
    @MainActor
    @discardableResult
    static func followChannel(_ raw: String) async -> FarcasterStore.Channel? {
        guard let channel = await resolveChannel(raw) else { return nil }
        FarcasterStore.shared.addChannel(channel)
        return channel
    }

    // MARK: - Replies (the sheet's thread context, 2026-07-14)

    /// A Farcaster thing's replies — fetched live when the sheet opens,
    /// shown only when there are any.
    @MainActor
    static func replies(for thing: Thing, limit: Int = 8) async -> [SocialReply] {
        guard thing.source == "Farcaster", let ref = thing.sourceRef, ref.hasPrefix("fc:"),
              let handle = thing.authorHandle, !handle.isEmpty else { return [] }
        return await replies(handle: handle, hash: String(ref.dropFirst(3)), limit: limit)
    }

    /// The thread under one cast, oldest first, capped. The author's fid
    /// comes from the store when watched, else one name lookup. Threads
    /// fetched this launch are cached — reopening a sheet costs nothing.
    @MainActor
    static func replies(handle: String, hash: String, limit: Int = 8) async -> [SocialReply] {
        let key = "\(handle):\(hash)"
        if let cached = threads[key] { return cached }
        var fid = FarcasterStore.shared.accounts
            .first(where: { $0.username == handle })?.fid ?? 0
        if fid == 0 {
            guard let proof = await IngestSupport.getJSON(
                "\(node)/v1/userNameProofByName?name=\(handle)") as? [String: Any],
                  let resolved = proof["fid"] as? Int else { return [] }
            fid = resolved
        }
        guard let root = await IngestSupport.getJSON(
            "\(node)/v1/castsByParent?fid=\(fid)&hash=\(hash)&pageSize=\(limit)")
                as? [String: Any],
              let messages = root["messages"] as? [[String: Any]] else { return [] }
        await prefetchProfiles(messages.compactMap {
            ($0["data"] as? [String: Any])?["fid"] as? Int
        })
        var replies: [SocialReply] = []
        for message in messages {
            guard let replyHash = message["hash"] as? String,
                  let data = message["data"] as? [String: Any],
                  let casterFid = data["fid"] as? Int,
                  let body = data["castAddBody"] as? [String: Any],
                  let text = body["text"] as? String, !text.isEmpty else { continue }
            guard let author = await profile(fid: casterFid),
                  let username = author.username, !username.isEmpty else { continue }
            replies.append(SocialReply(
                id: replyHash, handle: username, avatarURL: author.avatarURL,
                text: await splicingMentions(into: text, body: body),
                when: (data["timestamp"] as? Double).map { epoch.addingTimeInterval($0) }))
            if replies.count == limit { break }   // the node serves 2× the asked page
        }
        threads[key] = replies   // a node miss returned [] above, uncached — it retries
        return replies
    }

    /// Threads fetched this launch, keyed by "handle:hash".
    @MainActor private static var threads: [String: [SocialReply]] = [:]

    // MARK: - Profiles

    /// A user's profile facts from the hub — fetched once per fid per
    /// launch. nil when the node didn't answer, and a FAILURE IS NOT
    /// CACHED: the next refresh retries instead of suppressing that
    /// author's casts for the whole launch. The endpoint ignores the
    /// user_data_type filter and returns EVERY profile field in a
    /// `messages` array, so one scan collects the pfp, username, display
    /// name, and bio together (verified 2026-07-10/14).
    @MainActor
    static func profile(fid: Int) async -> Profile? {
        if let cached = profiles[fid] { return cached }
        guard let root = await IngestSupport.getJSON(
            "\(node)/v1/userDataByFid?fid=\(fid)") as? [String: Any],
              let messages = root["messages"] as? [[String: Any]] else { return nil }
        var profile = Profile()
        for message in messages {
            guard let data = message["data"] as? [String: Any],
                  let body = data["userDataBody"] as? [String: Any],
                  let value = body["value"] as? String, !value.isEmpty else { continue }
            switch body["type"] as? String {
            case "USER_DATA_TYPE_USERNAME": profile.username = value
            case "USER_DATA_TYPE_DISPLAY":  profile.displayName = value
            case "USER_DATA_TYPE_BIO":      profile.bio = value
            case "USER_DATA_TYPE_PFP":      profile.avatarURL = IngestSupport.imageURL(value)
            default: break
            }
        }
        profiles[fid] = profile
        return profile
    }

    /// Warms the profile cache for a batch of fids, a few at a time — the
    /// landing loops then read the cache instead of paying one serial
    /// round-trip per author (the boundedGather shape every ingest uses).
    @MainActor
    private static func prefetchProfiles(_ fids: [Int]) async {
        let missing = Array(Set(fids).filter { profiles[$0] == nil })
        guard !missing.isEmpty else { return }
        _ = await IngestSupport.boundedGather(missing, maxConcurrent: 4) { fid in
            await profile(fid: fid)
        }
    }

    /// Casts store @mentions out-of-band (fids + UTF-8 byte offsets), so the
    /// raw text reads "hey  look" — splice the @names back in for the title.
    /// Insertions run END-first so earlier offsets stay valid; a tie (two
    /// adjacent mentions at one offset) keeps its original order because the
    /// LATER mention inserts first and ends up second in the text.
    @MainActor
    private static func splicingMentions(into text: String, body: [String: Any]) async -> String {
        guard let fids = body["mentions"] as? [Int], !fids.isEmpty,
              let positions = body["mentionsPositions"] as? [Int],
              positions.count == fids.count else { return text }
        var bytes = Array(text.utf8)
        let ordered = zip(fids, positions).enumerated().sorted {
            $0.element.1 != $1.element.1 ? $0.element.1 > $1.element.1 : $0.offset > $1.offset
        }
        for (_, mention) in ordered {
            let (fid, position) = mention
            guard position >= 0, position <= bytes.count,
                  let name = await profile(fid: fid)?.username, !name.isEmpty else { continue }
            bytes.insert(contentsOf: Array("@\(name)".utf8), at: position)
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// A cast's first image embed. Snapchain serves raw protocol data — no
    /// hydrated thumbs — so only URLs that are plainly images qualify:
    /// Farcaster's own image CDN, or a file extension that says so. A cast
    /// embedding an article link keeps the chat glyph.
    private static func imageEmbed(_ body: [String: Any]) -> String? {
        for embed in (body["embeds"] as? [[String: Any]]) ?? [] {
            guard let url = embed["url"] as? String else { continue }
            let lower = url.lowercased()
            // Extension check runs on the PATH — a query string
            // ("photo.jpg?maxwidth=640") defeated hasSuffix on the raw URL.
            let path = URL(string: lower)?.path ?? lower
            if lower.contains("imagedelivery.net")
                || [".jpg", ".jpeg", ".png", ".gif", ".webp"].contains(where: path.hasSuffix) {
                return url
            }
        }
        return nil
    }
}
