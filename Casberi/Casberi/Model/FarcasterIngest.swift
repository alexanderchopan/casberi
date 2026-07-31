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
        /// Watch what they RECAST (2026-07-31) — the same read as `likes`
        /// (`reactionsByFid`, one reaction type over), and arguably the
        /// stronger curation signal: a like is approval, a recast is
        /// rebroadcast — they put their own name on it.
        var recasts = false
        /// Watch MENTIONS of them — casts naming this account land, so
        /// "while I was away" can answer with who talked to you.
        var mentions = false
        /// This account is YOURS (2026-07-31) — the flag the bridge never had
        /// (prd §221 named its absence). It turns on the INBOUND reads in
        /// `SocialInbound`: who replied to you, who liked your casts, who
        /// started following you. Nothing about it changes the outbound reads.
        var mine = false
        /// The Ethereum addresses this fid has verified onchain (2026-07-15) —
        /// resolved once from the keyless node's `verificationsByFid`, cached
        /// like the fid. Powers the wallet↔Farcaster join: "Watch their wallet"
        /// on the account row, and naming a watched account's wallet in a
        /// transfer ("from @dwr"). Empty until resolved or when the fid verified
        /// none.
        var verifiedAddresses: [String] = []

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
            recasts = try c.decodeIfPresent(Bool.self, forKey: .recasts) ?? false
            mentions = try c.decodeIfPresent(Bool.self, forKey: .mentions) ?? false
            mine = try c.decodeIfPresent(Bool.self, forKey: .mine) ?? false
            verifiedAddresses = try c.decodeIfPresent([String].self, forKey: .verifiedAddresses) ?? []
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

    /// Adds many at once, deduped, persisting ONCE — the follow import lands
    /// hundreds, and `accounts` persists on every mutation, so appending in a
    /// loop would re-encode the whole growing list per person. Each carries
    /// the fid the graph read already knew, so the import also skips the
    /// name→fid lookup the first sync would otherwise pay PER account.
    /// Returns how many were new.
    @discardableResult
    func add(contentsOf raws: [(name: String, fid: Int?)]) -> Int {
        var known = Set(accounts.map(\.username))
        var fresh: [Account] = []
        for raw in raws {
            let n = Self.normalize(raw.name)
            guard !n.isEmpty, known.insert(n).inserted else { continue }
            fresh.append(Account(username: n, fid: raw.fid ?? 0))
        }
        guard !fresh.isEmpty else { return 0 }
        accounts.append(contentsOf: fresh)
        return fresh.count
    }

    func remove(_ username: String) {
        if let fid = accounts.first(where: { $0.username == username })?.fid, fid != 0 {
            FarcasterSigners.forget(fid: fid)
        }
        accounts.removeAll { $0.username == username }
        SocialInbound.FollowerLedger.forget(key: Self.followerLedgerKey(username))
    }

    /// Teardown clears the whole connection — people and channels both, plus
    /// every follower ledger, so reconnecting seeds fresh instead of
    /// announcing a year of arrivals as today's news.
    func removeAll() {
        for account in accounts {
            SocialInbound.FollowerLedger.forget(key: Self.followerLedgerKey(account.username))
            if account.fid != 0 { FarcasterSigners.forget(fid: account.fid) }
        }
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

    func setRecasts(_ on: Bool, for username: String) {
        guard let i = accounts.firstIndex(where: { $0.username == username }) else { return }
        accounts[i].recasts = on
    }

    func setMentions(_ on: Bool, for username: String) {
        guard let i = accounts.firstIndex(where: { $0.username == username }) else { return }
        accounts[i].mentions = on
    }

    func setMine(_ on: Bool, for username: String) {
        guard let i = accounts.firstIndex(where: { $0.username == username }) else { return }
        accounts[i].mine = on
        // Turning it OFF forgets the follower ledger, so turning it back on
        // seeds fresh rather than announcing everyone who arrived meanwhile
        // as today's news. The signer cursor goes too, for the opposite
        // reason: its first sight lands the whole inventory on purpose, and
        // resuming mid-history would silently skip everything granted while
        // the flag was off.
        if !on {
            SocialInbound.FollowerLedger.forget(key: Self.followerLedgerKey(username))
            if accounts[i].fid != 0 { FarcasterSigners.forget(fid: accounts[i].fid) }
        }
    }

    /// Where one account's seen-followers ledger lives. Keyed on the USERNAME
    /// (stable, and what every other per-account key here uses) rather than the
    /// fid, which is 0 until the first resolve.
    static func followerLedgerKey(_ username: String) -> String {
        "farcaster.followers.\(username)"
    }

    /// Caches an fid's verified onchain addresses (lowercased), once resolved —
    /// the same run-once-then-remember discipline as the fid and profile.
    func setVerifiedAddresses(_ addresses: [String], for username: String) {
        guard let i = accounts.firstIndex(where: { $0.username == username }) else { return }
        accounts[i].verifiedAddresses = addresses.map { $0.lowercased() }
    }

    /// The "@handle" of a watched account that verified this address, if any —
    /// consulted by `WalletIngest.counterpartyNames` so a transfer to/from a
    /// watched Farcaster account's own wallet reads "from @dwr". Only over
    /// WATCHED accounts (the reverse index we already hold), never a lookup.
    func handle(forAddress address: String) -> String? {
        let a = address.lowercased()
        guard let match = accounts.first(where: { $0.verifiedAddresses.contains(a) })
        else { return nil }
        return "@\(match.username)"
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
                          SocialWatch(kind: .recasts, on: a.recasts),
                          SocialWatch(kind: .mentions, on: a.mentions),
                          SocialWatch(kind: .mine, on: a.mine)])
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

    // MARK: - Verified wallets (the wallet↔Farcaster join, 2026-07-15)

    /// The Ethereum addresses this fid verified onchain (lowercased) — the
    /// keyless node's `verificationsByFid`. Only Ethereum verifications (a
    /// 0x/42-hex address) are kept; a Solana verification isn't an EVM wallet we
    /// read. Empty when the fid verified none or the fetch failed.
    static func verifiedEthAddresses(fid: Int) async -> [String] {
        guard let root = await IngestSupport.getJSON(
            "\(node)/v1/verificationsByFid?fid=\(fid)") as? [String: Any],
              let messages = root["messages"] as? [[String: Any]] else { return [] }
        var out: [String] = []
        for m in messages {
            guard let data = m["data"] as? [String: Any] else { continue }
            // The body key changed as the protocol went multi-chain — accept both.
            let body = (data["verificationAddEthAddressBody"] as? [String: Any])
                ?? (data["verificationAddAddressBody"] as? [String: Any])
            guard let address = body?["address"] as? String else { continue }
            let a = address.lowercased()
            guard ENS.isHexAddress(a), !out.contains(a) else { continue }
            out.append(a)
        }
        return out
    }

    /// name → fid, via the keyless node's username proof. The one place that
    /// lookup lives (2026-07-16) — the refresh, the thread reader, the wallet
    /// join, and the profile card all resolve through here, and a watched
    /// account's cached fid short-circuits it.
    @MainActor
    static func fid(forName raw: String) async -> Int? {
        let name = FarcasterStore.normalize(raw)
        guard !name.isEmpty else { return nil }
        if let cached = FarcasterStore.shared.accounts
            .first(where: { $0.username == name })?.fid, cached != 0 {
            return cached
        }
        guard let proof = await IngestSupport.getJSON(
            "\(node)/v1/userNameProofByName?name=\(name)") as? [String: Any],
              let resolved = proof["fid"] as? Int else { return nil }
        FarcasterStore.shared.setFid(resolved, for: name)   // no-op if unwatched
        return resolved
    }

    /// The verified wallets for a watched username — cached on the account, else
    /// resolved (its fid first if needed) and cached. Backs "Watch their wallet".
    @MainActor
    static func verifiedEthAddresses(username: String) async -> [String] {
        let store = FarcasterStore.shared
        guard let account = store.accounts.first(where: { $0.username == username }) else { return [] }
        if !account.verifiedAddresses.isEmpty { return account.verifiedAddresses }
        guard let fid = await fid(forName: account.username) else { return [] }
        let verified = await verifiedEthAddresses(fid: fid)
        if !verified.isEmpty { store.setVerifiedAddresses(verified, for: account.username) }
        return verified
    }

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
        healed = false
        resurfaced = 0
        defer { running = false }

        // `landed`'s keys already ARE every existing ref for this source — a
        // separate `existingSourceRefs` call used to re-fetch the exact same
        // rows a second time just for their sourceRef column (perf,
        // 2026-07-28), doubling the DB round trip for no new information.
        let landed = IngestSupport.thingsByRef(context, source: "Farcaster")
        var existing = Set(landed.keys)
        let backfill = ArtlessBackfill(context, source: "Farcaster")
        var added = 0
        var touched = false
        var anyResolved = false

        for account in store.accounts {
            guard let fid = await fid(forName: account.username) else { continue }

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
            // Cache this account's verified wallets once (the wallet↔Farcaster
            // join) — so a transfer to/from a watched account's own wallet reads
            // "from @dwr", and "Watch their wallet" is instant. Only when empty,
            // like the fid.
            if account.verifiedAddresses.isEmpty {
                let verified = await verifiedEthAddresses(fid: fid)
                if !verified.isEmpty { store.setVerifiedAddresses(verified, for: account.username) }
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
                                    landed: landed, backfill: backfill, context: context)

            if account.likes {
                added += await landReactions(fid: fid, type: "Like", why: "liked",
                                             existing: &existing, landed: landed,
                                             backfill: backfill, context: context)
            }
            if account.recasts {
                added += await landReactions(fid: fid, type: "Recast", why: "recast",
                                             existing: &existing, landed: landed,
                                             backfill: backfill, context: context)
            }
            if account.mentions {
                added += await landMentions(of: fid, existing: &existing, landed: landed,
                                            backfill: backfill, context: context)
            }
            if account.mine {
                added += await landInbound(account: account, fid: fid, existing: &existing,
                                           landed: landed, backfill: backfill, context: context)
            }
        }

        for channel in store.channels {
            let count = await landChannel(channel, existing: &existing, landed: landed,
                                          backfill: backfill, context: context)
            if let count {
                anyResolved = true
                added += count
            }
        }

        guard anyResolved else { return nil }
        if added > 0 || backfill.any || touched || healed { context.saveHonestly() }
        return added
    }

    // MARK: - Likes, recasts, mentions, channels (2026-07-14; recasts 2026-07-31)

    /// How recent a reaction has to be to count as NEWS — the window inside
    /// which a like or a recast may resurface a cast the corpus already holds.
    /// Mirrors the alerts-are-news doctrine the Privacy Pools sweep follows:
    /// the first pass over a curator's page walks their whole recent back
    /// catalogue, and a month of old likes must not arrive as a month of new
    /// arrivals.
    private static let likeNewsWindow: TimeInterval = 86_400

    /// The account's reactions of one type — each reacted-to cast lands as a
    /// thing, stamped with the REACTION's time (when it entered your
    /// attention), not the cast's.
    ///
    /// Two types ride this one path (2026-07-31): `Like` ("they approved of
    /// it") and `Recast` ("they rebroadcast it under their own name"). The
    /// endpoint, the target dedupe, the resurface, and the bounded fan-out
    /// are identical — only the `reaction_type` and the marker word differ,
    /// so a recast can never drift from a like in behaviour.
    ///
    /// A cast the corpus ALREADY holds is the case that used to fall through
    /// (fixed 2026-07-26). The target dedupe below skipped it BEFORE the fetch,
    /// so a watched account liking a post you already have changed nothing at
    /// all: nothing landed, `land`'s heal never got its dedupe hit, and the post
    /// kept its original date — which in a strictly newest-first feed
    /// (`FeedScreen`'s `@Query` sorts on `capturedAt` alone) means it stayed
    /// exactly as buried as it was. Your OWN cast is the sharpest version, since
    /// watching yourself is what puts it in the corpus in the first place:
    /// "vitalik liked my post and it isn't showing" was this, precisely.
    ///
    /// Such a target now RESURFACES — see `resurface`.
    @MainActor
    private static func landReactions(fid: Int, type: String, why: String,
                                      existing: inout Set<String>,
                                      landed: [String: Thing],
                                      backfill: ArtlessBackfill, context: ModelContext) async -> Int {
        guard let root = await IngestSupport.getJSON(
            "\(node)/v1/reactionsByFid?fid=\(fid)&reaction_type=\(type)&pageSize=25&reverse=true")
                as? [String: Any],
              let messages = root["messages"] as? [[String: Any]] else { return 0 }
        var targets: [(fid: Int, hash: String, reacted: Date?)] = []
        for message in messages {
            guard let data = message["data"] as? [String: Any],
                  let body = data["reactionBody"] as? [String: Any],
                  let target = body["targetCastId"] as? [String: Any],
                  let targetFid = target["fid"] as? Int,
                  let targetHash = target["hash"] as? String else { continue }
            let reacted = (data["timestamp"] as? Double).map { epoch.addingTimeInterval($0) }
            // Already held: resurface it in place. Deliberately BEFORE the
            // `targets` append, so the steady state still costs zero castById
            // lookups — the property the ref dedupe was there to buy.
            guard !existing.contains("fc:\(targetHash)") else {
                resurface(landed["fc:\(targetHash)"], reactedAt: reacted)
                continue
            }
            targets.append((targetFid, targetHash, reacted))
        }
        guard !targets.isEmpty else { return 0 }
        // The reacted-to casts' bodies, a few at a time — the ref dedupe above
        // keeps the steady state at zero of these lookups.
        let casts = await IngestSupport.boundedGather(targets, maxConcurrent: 4) { t in
            await IngestSupport.getJSON("\(node)/v1/castById?fid=\(t.fid)&hash=\(t.hash)")
                as? [String: Any]
        }
        await prefetchProfiles(targets.map(\.fid))
        await prefetchCards(casts.compactMap { $0 }.flatMap(referencedCasts))
        var added = 0
        for (target, cast) in zip(targets, casts) {
            guard let cast else { continue }
            // "Liked" / "Recast" is the marker this cast wears — a watched
            // account reacted to it there, so it's here; the row can say so
            // instead of reading as their own post.
            if await land(cast: cast, capturedAt: target.reacted, why: why,
                          existing: &existing, landed: landed,
                          backfill: backfill, context: context) {
                added += 1
            }
        }
        return added
    }

    /// Restamps a cast the corpus already holds with the moment a watched
    /// account liked or recast it, so a newest-first feed shows it again. No
    /// fetch: the `Thing` is already in hand, which is what keeps the
    /// resurface free.
    ///
    /// The date it writes is the same one a freshly reacted-to cast lands
    /// under — the REACTION's time, not the cast's — so both halves of the
    /// flow answer "when did this enter your attention?" the same way.
    ///
    /// Three guards, each load-bearing:
    /// - **forward only** (`reactedAt > capturedAt`) — a reaction can't predate
    ///   the cast it reacts to, so this can only ever move a thing later, never
    ///   rewrite the date of something that arrived after.
    /// - **news only** (inside `likeNewsWindow`) — an old reaction heals nothing
    ///   and stays silent, so enabling Likes or Recasts on an account with a
    ///   long history doesn't throw their back catalogue at the top of the feed.
    /// - **live only** (`isLive`) — `landed` was captured at the start of the
    ///   refresh and every bridge's foreground heal deletes upstream-gone rows,
    ///   so a tombstoned model can reach here; reading `capturedAt` off one
    ///   traps inside SwiftData.
    ///
    /// No cursor is needed to make this once-only: it CONVERGES. Once
    /// `capturedAt` is the reaction's time the forward-only guard stops firing,
    /// so re-reading the same reaction on the next refresh writes nothing.
    @MainActor
    private static func resurface(_ thing: Thing?, reactedAt: Date?) {
        guard let thing, thing.isLive, let reactedAt,
              reactedAt > thing.capturedAt,
              Date.now.timeIntervalSince(reactedAt) < likeNewsWindow else { return }
        thing.capturedAt = reactedAt
        // Joins the refresh's save condition — a pass that only resurfaced
        // landed nothing new, and must still persist what it moved.
        healed = true
        resurfaced += 1
    }

    /// How many held casts the last refresh moved back into view. A resurface
    /// lands no thing, so `refresh`'s count reports 0 for a pass that did the
    /// whole job — without this a probe can't tell that from a pass that did
    /// nothing. Reset per refresh, like `healed`, under the same single-flight
    /// `running` guard.
    @MainActor private(set) static var resurfaced = 0

    // MARK: - Inbound: what happened to YOU (2026-07-31)

    /// The three inbound reads for an account marked `mine` — replies to your
    /// casts, likes on them, and new followers. See `SocialInbound` for why
    /// this half existed nowhere before and what doctrine bounds it.
    ///
    /// Returns how many THINGS landed. Likes contribute none by design (a
    /// count is a property of your cast, never a record of its own); they show
    /// up as a filled `likeCount`, a resurfaced cast, and a moment.
    @MainActor
    private static func landInbound(account: FarcasterStore.Account, fid: Int,
                                    existing: inout Set<String>, landed: [String: Thing],
                                    backfill: ArtlessBackfill,
                                    context: ModelContext) async -> Int {
        let mine = SocialInbound.ownRecentPosts(landed, handle: account.username,
                                                refPrefix: "fc:")
        var added = 0
        for cast in mine {
            guard cast.isLive, let ref = cast.sourceRef else { continue }
            let hash = String(ref.dropFirst(3))
            added += await landReplies(to: hash, fid: fid, existing: &existing,
                                       landed: landed, backfill: backfill, context: context)
            await readLikes(on: cast, hash: hash, fid: fid)
        }
        added += await landFollowers(account: account, fid: fid,
                                     existing: &existing, context: context)
        // Which apps can post as you — `WalletApprovals` for social identity.
        added += await FarcasterSigners.sync(fid: fid, existing: &existing, context: context)
        return added
    }

    /// The replies under one of YOUR casts, landed as things.
    ///
    /// This is the read `castsByMention` structurally cannot make: a Farcaster
    /// reply carries a `parentCastId`, not a mention, so answering someone
    /// never names them. Before this, "did anyone answer me?" had no source.
    @MainActor
    private static func landReplies(to hash: String, fid: Int, existing: inout Set<String>,
                                    landed: [String: Thing], backfill: ArtlessBackfill,
                                    context: ModelContext) async -> Int {
        guard let root = await IngestSupport.getJSON(
            "\(node)/v1/castsByParent?fid=\(fid)&hash=\(hash)&pageSize=25") as? [String: Any],
              let messages = root["messages"] as? [[String: Any]] else { return 0 }
        // Your own replies in your own thread are not someone replying to you
        // — they'd land wearing "Replied to you", pointing at yourself.
        let others = messages.filter {
            (($0["data"] as? [String: Any])?["fid"] as? Int) != fid
        }
        // The node serves ~2× the asked page (the channel read's measured
        // quirk) — cap so one popular cast can't flood a refresh.
        return await landPage(Array(others.prefix(25)), why: "reply", existing: &existing,
                              landed: landed, backfill: backfill, context: context)
    }

    /// Who liked one of YOUR casts. Fills the cast's own `likeCount` — the
    /// count is a PROPERTY of the cast, never a thing of its own (the module
    /// doctrine's plainest case) — and does the two things a name makes
    /// possible: resurfaces the cast when the liker is someone you watch, and
    /// says so once, out loud.
    ///
    /// Snapchain reports no totals, only reaction MESSAGES, so the count is a
    /// page's size and a full page means "at least this many" — `SocialCount`'s
    /// honesty valve. `Thing.likeCount` is a bare Int with nowhere to carry
    /// `atLeast`, so a FULL page is deliberately left unwritten rather than
    /// stored as a total nobody counted.
    @MainActor
    private static func readLikes(on cast: Thing, hash: String, fid: Int) async {
        guard let root = await IngestSupport.getJSON(
            "\(node)/v1/reactionsByCast?target_fid=\(fid)&target_hash=\(hash)"
            + "&reaction_type=Like&pageSize=\(reactionPage)") as? [String: Any],
              let messages = root["messages"] as? [[String: Any]] else { return }
        guard cast.isLive else { return }   // the pass awaited; a heal may have landed
        if messages.count < reactionPage, cast.likeCount != messages.count {
            cast.likeCount = messages.count
            healed = true
        }
        // Names, not numbers: a liker you WATCH is a person the corpus knows,
        // and their like is the sharpest signal this network produces.
        let watched = Dictionary(
            FarcasterStore.shared.accounts.filter { $0.fid != 0 }.map { ($0.fid, $0.username) },
            uniquingKeysWith: { first, _ in first })
        for message in messages {
            guard let data = message["data"] as? [String: Any],
                  let likerFid = data["fid"] as? Int, likerFid != fid,
                  let liker = watched[likerFid] else { continue }
            let when = (data["timestamp"] as? Double).map { epoch.addingTimeInterval($0) }
            // §221 from the other direction: that ruling surfaces your post
            // when the liker's OWN likes are being read; this surfaces it
            // whenever they liked it, read from your cast's side. Same
            // restamp, same three guards, so the two can't disagree.
            resurface(cast, reactedAt: when)
            if (when ?? .now).timeIntervalSinceNow > -SocialInbound.newsWindow {
                SourceMoments.shared.fire(
                    String(localized: "@\(liker) liked your cast"), source: "Farcaster")
            }
        }
    }

    /// Who started following you since the last pass. First sight seeds the
    /// ledger SILENTLY — watching yourself must not land your whole follower
    /// list as today's news.
    ///
    /// `linksByTargetFid` answers the graph from the TARGET's side: link
    /// messages whose own `fid` is the follower. That's the one direction
    /// `SocialFollows` doesn't read (it walks who a person follows, outbound,
    /// through the client API), and it's keyless on the same node as
    /// everything else here.
    @MainActor
    private static func landFollowers(account: FarcasterStore.Account, fid: Int,
                                      existing: inout Set<String>,
                                      context: ModelContext) async -> Int {
        guard let root = await IngestSupport.getJSON(
            "\(node)/v1/linksByTargetFid?target_fid=\(fid)&link_type=follow"
            + "&pageSize=25&reverse=true") as? [String: Any],
              let messages = root["messages"] as? [[String: Any]] else { return 0 }
        var followers: [(fid: Int, when: Date?)] = []
        for message in messages {
            guard let data = message["data"] as? [String: Any],
                  let followerFid = data["fid"] as? Int, followerFid != fid else { continue }
            followers.append((followerFid,
                              (data["timestamp"] as? Double).map { epoch.addingTimeInterval($0) }))
        }
        guard !followers.isEmpty else { return 0 }

        var ledger = SocialInbound.FollowerLedger(
            key: FarcasterStore.followerLedgerKey(account.username))
        let firstSight = ledger.isFirstSight
        let fresh = ledger.newcomers(in: followers.map { String($0.fid) })
        ledger.record(followers.map { String($0.fid) })
        guard !firstSight, !fresh.isEmpty else { return 0 }

        let freshFids = fresh.compactMap(Int.init)
        await prefetchProfiles(freshFids)
        var added = 0
        for followerFid in freshFids.prefix(SocialInbound.followerLandCap) {
            guard let who = await profile(fid: followerFid),
                  let username = who.username, !username.isEmpty else { continue }
            let when = followers.first { $0.fid == followerFid }?.when
            guard SocialInbound.landFollower(
                id: String(followerFid), handle: username, displayName: who.displayName,
                avatarURL: who.avatarURL,
                profileURL: "https://farcaster.xyz/\(username)",
                when: when, source: "Farcaster", existing: &existing, context: context) != nil
            else { continue }
            added += 1
            if (when ?? .now).timeIntervalSinceNow > -SocialInbound.newsWindow {
                SourceMoments.shared.fire(
                    String(localized: "@\(username) started following you"), source: "Farcaster")
            }
        }
        return added
    }

    /// Casts by OTHERS that name this account — replies included, since a
    /// mention usually is one. New ones ride "while I was away" like any
    /// landed thing.
    @MainActor
    private static func landMentions(of fid: Int, existing: inout Set<String>,
                                     landed: [String: Thing],
                                     backfill: ArtlessBackfill, context: ModelContext) async -> Int {
        guard let root = await IngestSupport.getJSON(
            "\(node)/v1/castsByMention?fid=\(fid)&pageSize=25&reverse=true") as? [String: Any],
              let messages = root["messages"] as? [[String: Any]] else { return 0 }
        return await landPage(messages, why: "mention", existing: &existing, landed: landed,
                              backfill: backfill, context: context)
    }

    /// A followed channel's newest top-level casts. Returns nil when the
    /// node didn't answer (so a channels-only refresh can still say so).
    @MainActor
    private static func landChannel(_ channel: FarcasterStore.Channel,
                                    existing: inout Set<String>, landed: [String: Thing],
                                    backfill: ArtlessBackfill,
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
        return await landPage(Array(messages.prefix(25)), channel: channel.name,
                              existing: &existing, landed: landed,
                              backfill: backfill, context: context)
    }

    /// Lands a page of casts: one capped fan-out warms the profile cache
    /// for every new cast's author and mentions, then each cast lands in
    /// order off the cache — the shared tail of every flow, so a page
    /// never pays one serial profile round-trip per cast.
    @MainActor
    private static func landPage(_ messages: [[String: Any]], topLevelOnly: Bool = false,
                                 why: String? = nil, channel: String? = nil,
                                 existing: inout Set<String>, landed: [String: Thing],
                                 backfill: ArtlessBackfill,
                                 context: ModelContext) async -> Int {
        var fids: [Int] = []
        var refs: [(fid: Int, hash: String)] = []
        for message in messages {
            guard let hash = message["hash"] as? String,
                  let data = message["data"] as? [String: Any],
                  let body = data["castAddBody"] as? [String: Any] else { continue }
            let ref = "fc:\(hash)"
            let isNew = !existing.contains(ref)
            if isNew {
                if let fid = data["fid"] as? Int { fids.append(fid) }
                fids.append(contentsOf: (body["mentions"] as? [Int]) ?? [])
            }
            // A cast being HEALED needs its quote/parent warmed too, not just a
            // new one: heal calls quoteCard/parentCard, and an unwarmed card is
            // a serial castById inside the landing loop. Once the heal fills
            // them the cast stops asking, so this is a one-pass cost — but on
            // an existing corpus that one pass was ~30 sequential round-trips.
            if isNew || landed[ref].map({ $0.quote == nil || $0.parent == nil }) == true {
                refs.append(contentsOf: referencedCasts(message))
            }
        }
        await prefetchProfiles(fids)
        // The casts these ones QUOTE or REPLY UNDER (2026-07-16). Snapchain
        // serves raw protocol data — a quote/parent is a bare {fid, hash} ref,
        // not a hydrated post — so each costs a lookup. One capped fan-out
        // here, then the landing loop reads the cache; and the ref dedupe
        // above means the steady state is zero of these (the same argument
        // the likes flow makes): only a first sync pays.
        await prefetchCards(refs)
        var added = 0
        for message in messages {
            if await land(cast: message, topLevelOnly: topLevelOnly, why: why,
                          channel: channel, existing: &existing, landed: landed,
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
                             capturedAt: Date? = nil, why: String? = nil,
                             channel: String? = nil,
                             existing: inout Set<String>, landed: [String: Thing],
                             backfill: ArtlessBackfill,
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
        let images = imageEmbeds(body)
        guard !existing.contains(ref) else {
            backfill.patch(ref, image: images.first)
            await heal(landed[ref], body: body, images: images, why: why, channel: channel)
            return false
        }
        guard let author = await profile(fid: casterFid),
              let username = author.username, !username.isEmpty else { return false }

        let short = String(hash.prefix(10))
        let when = capturedAt
            ?? (data["timestamp"] as? Double).map { epoch.addingTimeInterval($0) }
        let full = await splicingMentions(into: text, body: body)
        let thing = Thing(
            kind: .chat,
            title: IngestSupport.titleLine(full),
            content: "https://farcaster.xyz/\(username)/\(short)",
            source: "Farcaster",
            capturedAt: when ?? .now,
            sourceRef: ref
        )
        thing.postText = full
        thing.imageURLs = images.compactMap(IngestSupport.imageURL)
        thing.previewImageURL = thing.imageURLs.first
        thing.authorHandle = username
        thing.authorAvatarURL = author.avatarURL
        thing.socialContext = why
        thing.channelName = channel
        thing.quote = await quoteCard(body)
        thing.parent = await parentCard(body)
        context.insert(thing)
        SpotlightIndex.index([thing])
        existing.insert(ref)
        // Item 1 of the 2026-07-27 social pass: a cast sharing an article
        // used to keep only the permalink — the article itself never entered
        // the corpus, invisible to Find/Retriever/the themes map. Landed as
        // its own `.link` thing, deduped through the same `existing` set.
        if let linkURL = linkEmbed(body) {
            landLinkedArticle(linkURL, sharedBy: username, capturedAt: when ?? .now,
                              existing: &existing, context: context)
        }
        // Item 5 of the 2026-07-27 polish pass: a mention is the highest-
        // signal event social has, and it used to land silently. Fires the
        // same delight bus a wallet high or a quiet-account return already
        // rides. NEWS ONLY (the Privacy Pools/§221 doctrine): a mention
        // older than a day heals in silently — connecting an account for
        // the first time shouldn't rain 40 toasts for months of old @s.
        if why == "mention", (when ?? .now).timeIntervalSinceNow > -86400 {
            SourceMoments.shared.fire(
                String(localized: "@\(username) mentioned you"), source: "Farcaster")
        }
        // "The crossing" (item 6 of the 2026-07-27 polish pass): two watched
        // accounts replying to or quoting each other. Detected purely from
        // data already on the landed thing — `parent`/`quote` both carry the
        // referenced cast's author — so this is a pure corpus join, not a
        // network read, and nothing else on the phone can see it.
        fireCrossingIfWatched(author: username, other: thing.parent?.handle ?? thing.quote?.handle,
                              when: when)
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
        let watched = Set(FarcasterStore.shared.accounts.map(\.username))
        guard watched.contains(author), watched.contains(other) else { return }
        SourceMoments.shared.fire(
            String(localized: "@\(author) and @\(other) are talking"), source: "Farcaster")
    }

    /// Fills the enrichment fields on a cast that landed BEFORE they existed
    /// (2026-07-16). A cast already in the corpus dedupes out of the landing
    /// path, so without this the full text, the extra images, and the quote
    /// card would only ever reach casts landed from today on — and the feed
    /// would read as half-enriched for weeks. Each refresh sees each account's
    /// recent page, so the recent past heals itself in a pass or two; casts
    /// older than the page keep their title alone, honestly.
    ///
    /// Only ever FILLS a gap — an already-set field is never rewritten, so a
    /// heal can't clobber what a good sync landed.
    @MainActor
    private static func heal(_ thing: Thing?, body: [String: Any], images: [String],
                             why: String?, channel: String?) async {
        guard let thing else { return }
        // WHY it's here heals too — else the marker would only ever reach casts
        // landed from today on, and a corpus that already holds your likes and
        // your channels would show none of them. Accurate, not a guess: this
        // cast really did just come back from that channel's feed, or from your
        // likes. A cast can reach us both ways (your own cast, also in /design);
        // first write wins, and either answer is true.
        if thing.socialContext == nil, let why {
            thing.socialContext = why
            healed = true
        }
        if thing.channelName == nil, let channel {
            thing.channelName = channel
            healed = true
        }
        if thing.postText == nil, let text = body["text"] as? String, !text.isEmpty {
            thing.postText = await splicingMentions(into: text, body: body)
            healed = true
        }
        if thing.imageURLs.isEmpty, !images.isEmpty {
            thing.imageURLs = images.compactMap(IngestSupport.imageURL)
            healed = true
        }
        if thing.quote == nil, let quote = await quoteCard(body) {
            thing.quote = quote
            healed = true
        }
        if thing.parent == nil, let parent = await parentCard(body) {
            thing.parent = parent
            healed = true
        }
    }

    /// True once `heal` filled a gap this pass — joins the refresh's save
    /// condition, so a pass that ONLY healed (landed nothing new, the steady
    /// state) still persists what it filled. Reset at each refresh; the
    /// `running` guard makes the pass single-flight, so one flag is safe.
    @MainActor private static var healed = false

    // MARK: - Delete-sync (2026-07-23)

    @MainActor private static var healRunning = false
    private static let healInterval: TimeInterval = 3600
    private static let healKey = "farcaster.lastHeal"

    /// Reconciles against what the node still serves — a cast deleted by
    /// its author never tells Casberi. Unlike Bluesky's `getPosts`,
    /// Snapchain's `castById` takes ONE cast per request (no batch form), so
    /// this fans a few out at a time instead. Its not-found shape, measured
    /// live 2026-07-23: HTTP 400 with `error_detail` containing "cast not
    /// found" — NOT 404. A malformed request (a bad hash) ALSO 400s, with a
    /// different message ("Invalid hash"), so `castIsGone` reads the body
    /// rather than trusting the status code alone — every hash checked here
    /// comes from our own stored refs, so a shape error would mean a bug in
    /// this code, not a real deletion, and must never be misread as one.
    @MainActor
    static func heal(context: ModelContext, force: Bool = false) async -> Int {
        guard !healRunning else { return 0 }
        if !force, let last = UserDefaults.standard.object(forKey: healKey) as? Date,
           Date.now.timeIntervalSince(last) < healInterval { return 0 }
        healRunning = true
        defer { healRunning = false }
        UserDefaults.standard.set(Date.now, forKey: healKey)

        let things = IngestSupport.thingsByRef(context, source: "Farcaster")
        let candidates = things.compactMap { ref, thing -> (ref: String, hash: String, handle: String)? in
            guard ref.hasPrefix("fc:"), let handle = thing.authorHandle, !handle.isEmpty
            else { return nil }
            return (ref, String(ref.dropFirst(3)), handle)
        }
        guard !candidates.isEmpty else { return 0 }

        // castById needs {fid, hash} — Snapchain has no lookup by hash alone
        // — so resolve each distinct author's fid once, fanned out.
        let handles = Array(Set(candidates.map(\.handle)))
        let fids = await IngestSupport.boundedGather(handles, maxConcurrent: 4) { handle in
            await fid(forName: handle)
        }
        let fidByHandle = Dictionary(uniqueKeysWithValues: zip(handles, fids))

        let checks = await IngestSupport.boundedGather(candidates, maxConcurrent: 4) {
            c -> (String, Bool) in
            guard let fid = fidByHandle[c.handle].flatMap({ $0 }) else { return (c.ref, false) }
            return (c.ref, await castIsGone(fid: fid, hash: c.hash))
        }

        var removedIDs: [UUID] = []
        for (ref, gone) in checks where gone {
            guard let thing = things[ref] else { continue }
            removedIDs.append(thing.id)
            context.delete(thing)
        }
        guard !removedIDs.isEmpty else { return 0 }
        context.saveHonestly()
        SpotlightIndex.remove(ids: removedIDs)
        return removedIDs.count
    }

    /// True only for a definitive "cast not found" — never for a transport
    /// failure, a malformed request, or any other status, so an outage or a
    /// bug in our own request can't masquerade as a real deletion.
    private static func castIsGone(fid: Int, hash: String) async -> Bool {
        guard let url = URL(string: "\(node)/v1/castById?fid=\(fid)&hash=\(hash)") else { return false }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 400,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let detail = json["error_detail"] as? String else { return false }
        return detail.localizedCaseInsensitiveContains("not found")
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

    /// The thread under one cast, oldest first, capped. The author's fid
    /// comes from the store when watched, else one name lookup. Threads
    /// fetched this launch are cached — reopening a sheet costs nothing.
    @MainActor
    static func replies(handle: String, hash: String, limit: Int = 8) async -> [SocialReply] {
        let key = "\(handle):\(hash)"
        if let cached = threads[key] { return cached }
        guard let fid = await fid(forName: handle) else { return [] }
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
                when: (data["timestamp"] as? Double).map { epoch.addingTimeInterval($0) },
                url: "https://farcaster.xyz/\(username)/\(String(replyHash.prefix(10)))",
                ref: "fc:\(replyHash)"))
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

    /// EVERY image a cast embeds, in order (2026-07-16 — it used to keep only
    /// the first, so a four-photo cast lost three). Snapchain serves raw
    /// protocol data — no hydrated thumbs — so only URLs that are plainly
    /// images qualify: Farcaster's own image CDN, or a file extension that says
    /// so. A cast embedding an article link contributes none and keeps the chat
    /// glyph.
    private static func imageEmbeds(_ body: [String: Any]) -> [String] {
        var out: [String] = []
        for embed in (body["embeds"] as? [[String: Any]]) ?? [] {
            guard let url = embed["url"] as? String else { continue }
            let lower = url.lowercased()
            // Extension check runs on the PATH — a query string
            // ("photo.jpg?maxwidth=640") defeated hasSuffix on the raw URL.
            let path = URL(string: lower)?.path ?? lower
            if lower.contains("imagedelivery.net")
                || [".jpg", ".jpeg", ".png", ".gif", ".webp"].contains(where: path.hasSuffix) {
                out.append(url)
            }
        }
        return out
    }

    /// The first embedded URL that ISN'T a picture (item 1 of the
    /// 2026-07-27 social pass) — a cast sharing an article, not just images.
    /// Reuses `imageEmbeds`' own filter, inverted.
    private static func linkEmbed(_ body: [String: Any]) -> String? {
        let images = Set(imageEmbeds(body))
        for embed in (body["embeds"] as? [[String: Any]]) ?? [] {
            guard let url = embed["url"] as? String, !images.contains(url),
                  url.lowercased().hasPrefix("http") else { continue }
            return url
        }
        return nil
    }

    /// Lands a cast's shared article as its own `.link` thing — a real,
    /// separately retrievable record, not just a URL sitting inside the
    /// cast's `postText`. Dedupes through the SAME `existing` set casts
    /// use, keyed on the URL, so the same article shared twice (by this
    /// account or another) never lands twice. The title starts as the bare
    /// URL and renames itself once `LinkTitle.enrich` fetches the real
    /// `<title>` — fired detached (the established pattern, `RootShell`'s
    /// own paste-a-link path) so an 8-second page fetch never serializes the
    /// cast-landing loop behind it.
    @MainActor
    private static func landLinkedArticle(_ url: String, sharedBy username: String,
                                          capturedAt: Date,
                                          existing: inout Set<String>,
                                          context: ModelContext) {
        let ref = "link:\(url)"
        guard !existing.contains(ref) else { return }
        existing.insert(ref)
        let thing = Thing(
            kind: .link,
            title: url,
            content: url,
            source: "Farcaster",
            capturedAt: capturedAt,
            sourceRef: ref
        )
        thing.authorHandle = username
        context.insert(thing)
        SpotlightIndex.index([thing])
        Task { @MainActor in await LinkTitle.enrich(thing, context: context) }
    }

    // MARK: - Quotes and parents (2026-07-16)

    /// The {fid, hash} of every cast this one points at — the cast it replies
    /// under, plus any it quotes. What `landPage` warms before it lands.
    private static func referencedCasts(_ message: [String: Any]) -> [(fid: Int, hash: String)] {
        guard let body = (message["data"] as? [String: Any])?["castAddBody"] as? [String: Any]
        else { return [] }
        var out: [(fid: Int, hash: String)] = []
        if let parent = castID(body["parentCastId"]) { out.append(parent) }
        for embed in (body["embeds"] as? [[String: Any]]) ?? [] {
            if let quoted = castID(embed["castId"]) { out.append(quoted) }
        }
        return out
    }

    /// A protocol cast reference — `{fid, hash}` — or nil for the NSNull the
    /// node sends on a top-level cast.
    private static func castID(_ raw: Any?) -> (fid: Int, hash: String)? {
        guard let dict = raw as? [String: Any],
              let fid = dict["fid"] as? Int,
              let hash = dict["hash"] as? String, !hash.isEmpty else { return nil }
        return (fid, hash)
    }

    /// The cast this one quotes — a cast embed, the signature form Farcaster
    /// carried and Casberi dropped until now (a quote-post read as a bare,
    /// contextless line). The FIRST quoted cast: a cast can technically embed
    /// two, but the sheet shows one card, and picking the first matches what
    /// every Farcaster client renders.
    @MainActor
    private static func quoteCard(_ body: [String: Any]) async -> SocialCard? {
        for embed in (body["embeds"] as? [[String: Any]]) ?? [] {
            if let id = castID(embed["castId"]),
               let card = await card(fid: id.fid, hash: id.hash) { return card }
        }
        return nil
    }

    /// The cast this one replies under — so the sheet can say "Replying to @…"
    /// and a landed mention (usually a reply) carries what it answers.
    @MainActor
    private static func parentCard(_ body: [String: Any]) async -> SocialCard? {
        guard let id = castID(body["parentCastId"]) else { return nil }
        return await card(fid: id.fid, hash: id.hash)
    }

    /// One referenced cast as a card — its author's face and name off the
    /// profile cache, its words spliced. Cached per launch by "fid:hash", so a
    /// thread where twenty casts quote the same one costs one lookup.
    @MainActor
    static func card(fid: Int, hash: String) async -> SocialCard? {
        let key = "\(fid):\(hash)"
        if let cached = cards[key] { return cached }
        guard let root = await IngestSupport.getJSON(
            "\(node)/v1/castById?fid=\(fid)&hash=\(hash)") as? [String: Any],
              let data = root["data"] as? [String: Any],
              let body = data["castAddBody"] as? [String: Any],
              let text = body["text"] as? String,
              let author = await profile(fid: fid),
              let username = author.username, !username.isEmpty else { return nil }
        let card = SocialCard(
            handle: username,
            text: await splicingMentions(into: text, body: body),
            avatarURL: author.avatarURL,
            url: "https://farcaster.xyz/\(username)/\(String(hash.prefix(10)))",
            // The FULL hash, not the permalink's 10-char prefix — this is what
            // reading the card's own thread needs. Without it, walking into a
            // Farcaster quote or parent dead-ends on a post with no replies,
            // while the same tap on Bluesky works.
            ref: "fc:\(hash)")
        cards[key] = card
        return card
    }

    /// Referenced casts fetched this launch, keyed "fid:hash". A miss returns
    /// nil uncached, so the next pass retries it (the profile cache's rule).
    @MainActor private static var cards: [String: SocialCard] = [:]

    /// Warms the card cache for a batch of refs, a few at a time — the
    /// boundedGather shape `prefetchProfiles` uses, for the same reason.
    @MainActor
    private static func prefetchCards(_ refs: [(fid: Int, hash: String)]) async {
        var seen = Set<String>()
        let missing = refs.filter { ref in
            let key = "\(ref.fid):\(ref.hash)"
            return cards[key] == nil && seen.insert(key).inserted
        }
        guard !missing.isEmpty else { return }
        _ = await IngestSupport.boundedGather(missing, maxConcurrent: 4) { ref in
            await card(fid: ref.fid, hash: ref.hash)
        }
    }

    // MARK: - Engagement (2026-07-16)

    /// A cast's likes and recasts, counted from the keyless node. Snapchain
    /// reports no totals — it serves the reaction MESSAGES — so each count is
    /// the size of one page, and a full page means "at least this many"
    /// (`atLeast`), never a fabricated total. Fetched live when the sheet opens,
    /// not stored at ingest: a count is only true at the moment it's read, and
    /// one cast at a time is a fetch the ingest can't afford per page.
    @MainActor
    static func engagement(for thing: Thing) async -> SocialEngagement? {
        guard thing.source == "Farcaster", let ref = thing.sourceRef, ref.hasPrefix("fc:"),
              let handle = thing.authorHandle,
              let fid = await fid(forName: handle) else { return nil }
        let hash = String(ref.dropFirst(3))
        async let likes = reactions(type: "Like", fid: fid, hash: hash)
        async let recasts = reactions(type: "Recast", fid: fid, hash: hash)
        let e = SocialEngagement(likes: await likes, reposts: await recasts, replies: nil)
        return e.isEmpty ? nil : e
    }

    /// One reaction type's count for a cast, capped at a page.
    private static let reactionPage = 100

    @MainActor
    private static func reactions(type: String, fid: Int, hash: String) async -> SocialCount? {
        guard let root = await IngestSupport.getJSON(
            "\(node)/v1/reactionsByCast?target_fid=\(fid)&target_hash=\(hash)"
            + "&reaction_type=\(type)&pageSize=\(reactionPage)") as? [String: Any],
              let messages = root["messages"] as? [[String: Any]] else { return nil }
        return SocialCount(value: messages.count, atLeast: messages.count >= reactionPage)
    }
}
