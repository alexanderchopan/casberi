import Foundation
import Observation
import SwiftData

/// The Nostr bridge (2026-07-27) — the third social bridge, brought to parity
/// with Farcaster/Bluesky as far as the protocol allows. Nostr has no
/// canonical host: public relays serve NIP-01 reads with no account and no
/// key (measured live 2026-07-27 against nos.lol/relay.damus.io/
/// relay.primal.net/purplepag.es — no relay ever challenged a plain REQ with
/// NIP-42 auth), so this reads more like Farcaster (raw protocol events, no
/// hydration) than Bluesky (a single hydrated AppView). Notes land as chat
/// things linking to njump.me, the public web gateway that resolves any
/// `note`/`npub` without a login. An account's reactions (kind:7) stand in
/// for Likes, `#p`-tag mentions for Mentions, and a followed hashtag (`#t`
/// tag) is the closest keyless analog to a Farcaster channel/Bluesky feed.
///
/// A person is watched by npub, a raw hex pubkey, or a NIP-05 identifier
/// ("name@domain.com") — Nostr's closest thing to a memorable handle, since
/// there is no reliable global user-search API to type a few letters into
/// (relay.nostr.band's search timed out on every filter tried in the same
/// measurement pass, so this bridge offers no search — connect by pasting).
///
/// No event signature is verified — see `NostrRelay`'s own doc comment for
/// why that's an acceptable, disclosed simplification rather than an
/// oversight.
@Observable
final class NostrStore {
    static let shared = NostrStore()
    private static let key = "nostr.accounts"
    private static let hashtagsKey = "nostr.hashtags"

    struct Account: Codable, Identifiable, Equatable {
        var id = UUID()
        /// What was typed, normalized — an npub, a raw hex pubkey, or a
        /// NIP-05 identifier. Always present from the moment of add.
        var input: String
        /// The resolved 64-hex pubkey — instant for npub/hex input, one
        /// `.well-known/nostr.json` lookup (cached here after) for a NIP-05
        /// identifier. Empty until resolved, the same "fid" shape Farcaster
        /// caches.
        var pubkeyHex: String = ""
        /// Profile facts a relay's kind:0 event serves — refreshed each
        /// sync, worn by the account row.
        var displayName: String?
        var bio: String?
        var avatarURL: String?
        /// The account's own VERIFIED NIP-05 identifier, when their profile
        /// publishes one — preferred over `input` for display since it's
        /// confirmed by the domain itself, not just typed.
        var nip05: String?
        /// Watch their REACTIONS (kind:7) — any reaction that isn't an
        /// explicit "-" downvote lands its target note, the Likes analog.
        var likes = false
        /// Watch MENTIONS of them (`#p` tag) — notes naming this account land.
        var mentions = false

        init(input: String, pubkeyHex: String = "") {
            self.input = input
            self.pubkeyHex = pubkeyHex
        }

        /// Accounts persisted before a later field decode with defaults
        /// instead of failing the whole list — the Farcaster/Bluesky rule.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            input = try c.decode(String.self, forKey: .input)
            pubkeyHex = try c.decodeIfPresent(String.self, forKey: .pubkeyHex) ?? ""
            displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
            bio = try c.decodeIfPresent(String.self, forKey: .bio)
            avatarURL = try c.decodeIfPresent(String.self, forKey: .avatarURL)
            nip05 = try c.decodeIfPresent(String.self, forKey: .nip05)
            likes = try c.decodeIfPresent(Bool.self, forKey: .likes) ?? false
            mentions = try c.decodeIfPresent(Bool.self, forKey: .mentions) ?? false
        }
    }

    /// A followed hashtag (`#t` tag) — Nostr's closest keyless analog to a
    /// Farcaster channel or Bluesky feed: a topic lane beside the people.
    struct Hashtag: Codable, Identifiable, Equatable {
        var id = UUID()
        var tag: String
    }

    var accounts: [Account] { didSet { persist() } }
    var hashtags: [Hashtag] { didSet { persistHashtags() } }

    var connected: Bool { !accounts.isEmpty || !hashtags.isEmpty }
    var inputs: [String] { accounts.map(\.input) }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([Account].self, from: data) {
            accounts = saved
        } else {
            accounts = []
        }
        if let data = UserDefaults.standard.data(forKey: Self.hashtagsKey),
           let saved = try? JSONDecoder().decode([Hashtag].self, from: data) {
            hashtags = saved
        } else {
            hashtags = []
        }
    }

    @discardableResult
    func add(_ raw: String) -> Bool {
        let n = Self.normalize(raw)
        guard !n.isEmpty, !accounts.contains(where: { $0.input == n || $0.pubkeyHex == n })
        else { return false }
        accounts.append(Account(input: n, pubkeyHex: isHex64Pubkey(n) ? n : ""))
        return true
    }

    /// Adds many at once, deduped, persisting ONCE — the follow import lands
    /// hundreds, the Farcaster/Bluesky rule. Each entry is a raw hex pubkey
    /// (the follow graph's own "p" tags carry nothing else), so every one
    /// resolves instantly with no further lookup.
    @discardableResult
    func add(contentsOf raws: [String]) -> Int {
        var known = Set(accounts.map(\.input)).union(accounts.map(\.pubkeyHex))
        var fresh: [Account] = []
        for raw in raws {
            let n = Self.normalize(raw)
            guard !n.isEmpty, known.insert(n).inserted else { continue }
            fresh.append(Account(input: n, pubkeyHex: isHex64Pubkey(n) ? n : ""))
        }
        guard !fresh.isEmpty else { return 0 }
        accounts.append(contentsOf: fresh)
        return fresh.count
    }

    /// Matches by either the typed input OR the resolved pubkey — a caller
    /// (the roster's remove gesture) may hold either, depending on whether
    /// this account had resolved yet the last time its key was read.
    func remove(_ key: String) { accounts.removeAll { $0.input == key || $0.pubkeyHex == key } }

    func removeAll() {
        accounts = []
        hashtags = []
    }

    func setPubkeyHex(_ hex: String, for input: String) {
        guard let i = accounts.firstIndex(where: { $0.input == input }) else { return }
        accounts[i].pubkeyHex = hex
    }

    /// Sync's write-back of a relay's kind:0 profile facts. One assignment,
    /// so the array's didSet (→ persist) fires once, not once per field.
    func setProfile(_ profile: NostrIngest.Profile, for input: String) {
        guard let i = accounts.firstIndex(where: { $0.input == input }) else { return }
        var a = accounts[i]
        a.displayName = profile.displayName
        a.bio = profile.bio
        a.avatarURL = profile.avatarURL
        a.nip05 = profile.nip05
        accounts[i] = a
    }

    func setLikes(_ on: Bool, for key: String) {
        guard let i = accounts.firstIndex(where: { $0.input == key || $0.pubkeyHex == key })
        else { return }
        accounts[i].likes = on
    }

    func setMentions(_ on: Bool, for key: String) {
        guard let i = accounts.firstIndex(where: { $0.input == key || $0.pubkeyHex == key })
        else { return }
        accounts[i].mentions = on
    }

    @discardableResult
    func addHashtag(_ hashtag: Hashtag) -> Bool {
        guard !hashtags.contains(where: { $0.tag == hashtag.tag }) else { return false }
        hashtags.append(hashtag)
        return true
    }

    func removeHashtag(_ tag: String) { hashtags.removeAll { $0.tag == tag } }

    /// The trailing-slot label a Nostr row shows — nil when it's the sole
    /// watched account (redundant, the same Farcaster/Bluesky rule), else
    /// "@" plus the best display form, unless that form already carries its
    /// own "@" (a NIP-05 identifier reads oddly double-prefixed otherwise).
    @MainActor
    func rowLabel(for pubkeyHex: String?) -> String? {
        guard let pubkeyHex, !pubkeyHex.isEmpty else { return nil }
        if accounts.count == 1, accounts[0].pubkeyHex == pubkeyHex { return nil }
        let label = displayHandle(for: pubkeyHex)
        return label.contains("@") ? label : "@\(label)"
    }

    /// The best human-facing string for a pubkey: a watched account's own
    /// verified NIP-05/name, else this launch's profile cache, else a short
    /// npub — always computable, since every event carries a pubkey even
    /// when its author never published a nameable profile (unlike Farcaster,
    /// where every fid resolves a real username by protocol guarantee).
    @MainActor
    func displayHandle(for pubkeyHex: String) -> String {
        if let account = accounts.first(where: { $0.pubkeyHex == pubkeyHex }) {
            if let nip05 = account.nip05, !nip05.isEmpty { return nip05 }
            if let name = account.displayName, !name.isEmpty { return name }
        }
        if let cached = NostrIngest.cachedProfile(hex: pubkeyHex) {
            if let nip05 = cached.nip05, !nip05.isEmpty { return nip05 }
            if let name = cached.displayName, !name.isEmpty { return name }
        }
        return SocialThread.shortHandle(pubkeyHex)
    }

    /// The watched accounts as the shared setup row renders them. `key` is
    /// the resolved pubkey once known (matching `Thing.authorHandle`, so the
    /// roster and the corpus agree on identity), falling back to `input`
    /// only in the brief window before the first sync resolves it — no
    /// thing can have landed under that account yet, so the fallback never
    /// collides with a real stored ref.
    @MainActor
    var socialAccounts: [SocialAccount] {
        accounts.map { a in
            let key = a.pubkeyHex.isEmpty ? a.input : a.pubkeyHex
            let label = a.nip05 ?? (a.pubkeyHex.isEmpty ? a.input : displayHandle(for: a.pubkeyHex))
            let handleLine = label.contains("@") ? label : "@\(label)"
            return SocialAccount(
                key: key,
                title: a.displayName ?? label,
                subtitle: SocialAccount.subtitle(handle: handleLine, bio: a.bio),
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

    private func persistHashtags() {
        if let data = try? JSONEncoder().encode(hashtags) {
            UserDefaults.standard.set(data, forKey: Self.hashtagsKey)
        }
    }

    /// Accepts an npub (bech32), a raw 64-hex pubkey, a NIP-05 identifier
    /// ("name@domain.com", or a bare "@domain.com" for that domain's root
    /// identifier), or any of those wrapped in an "nostr:" URI.
    static func normalize(_ raw: String) -> String {
        var n = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if n.lowercased().hasPrefix("nostr:") { n.removeFirst("nostr:".count) }
        n = n.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = n.lowercased()
        if lower.hasPrefix("npub1"), let hex = NostrBech32.npubToHex(lower) { return hex }
        if isHex64Pubkey(lower) { return lower }
        if n.hasPrefix("@") { n = "_" + n }   // "@domain.com" → the domain's root identifier
        return n.lowercased()
    }

    /// "#design", "design", and a pasted njump.me hashtag link all normalize
    /// to the bare tag.
    static func normalizeHashtag(_ raw: String) -> String {
        var n = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for junk in ["https://", "http://", "njump.me/t/", "primal.net/t/"] {
            if n.hasPrefix(junk) { n.removeFirst(junk.count) }
        }
        while n.hasPrefix("#") { n.removeFirst() }
        return n
    }
}

/// A 64-char lowercase-hex string — the shape of every Nostr id/pubkey.
/// Top-level so both `NostrStore` and `NostrIngest` share one definition.
fileprivate func isHex64Pubkey(_ s: String) -> Bool {
    s.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil
}

enum NostrIngest {

    @MainActor private static var running = false

    /// A relay's kind:0 profile content, parsed. All optional — many real
    /// Nostr accounts publish only some fields, some publish none at all.
    struct Profile: Equatable {
        var displayName: String?
        var bio: String?
        var avatarURL: String?
        var nip05: String?
    }
    @MainActor private static var profiles: [String: Profile] = [:]

    /// Every profile fetched this launch, exposed read-only — `NostrStore`'s
    /// display-name fallback reads the same cache the ingest already warmed,
    /// so a mention/like/reply author already resolved elsewhere never pays
    /// a second lookup just to render a row label.
    @MainActor
    static func cachedProfile(hex: String) -> Profile? { profiles[hex] }

    // MARK: - Identity resolution

    /// input → hex pubkey. Instant for an npub/hex input (already normalized
    /// to hex by `NostrStore.normalize` at add time); a NIP-05 identifier
    /// costs one keyless `.well-known/nostr.json` lookup, cached on the
    /// account afterward — the same run-once-then-remember discipline
    /// Farcaster's `fid(forName:)` uses.
    @MainActor
    static func pubkeyHex(for input: String) async -> String? {
        if isHex64Pubkey(input) { return input }
        if let cached = NostrStore.shared.accounts.first(where: { $0.input == input })?.pubkeyHex,
           !cached.isEmpty {
            return cached
        }
        guard let atIndex = input.firstIndex(of: "@"),
              let resolved = await resolveNIP05(input, atIndex: atIndex) else { return nil }
        NostrStore.shared.setPubkeyHex(resolved, for: input)
        return resolved
    }

    /// NIP-05: `GET https://<domain>/.well-known/nostr.json?name=<local>` —
    /// keyless by design, the whole point of the spec. A "_@domain.com" root
    /// identifier's local part is the literal string "_".
    private static func resolveNIP05(_ identifier: String, atIndex: String.Index) async -> String? {
        let name = String(identifier[identifier.startIndex..<atIndex])
        let domain = String(identifier[identifier.index(after: atIndex)...])
        guard !domain.isEmpty, !name.isEmpty,
              let encodedName = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        else { return nil }
        guard let root = await IngestSupport.getJSON(
            "https://\(domain)/.well-known/nostr.json?name=\(encodedName)",
            service: "Nostr") as? [String: Any],
              let names = root["names"] as? [String: Any] else { return nil }
        if let exact = names[name] as? String, isHex64Pubkey(exact.lowercased()) {
            return exact.lowercased()
        }
        // A case-insensitive fallback — NIP-05 local-part comparison is loose
        // in practice and some directories key by a differently-cased name.
        if let match = names.first(where: { $0.key.lowercased() == name.lowercased() })?.value as? String,
           isHex64Pubkey(match.lowercased()) {
            return match.lowercased()
        }
        return nil
    }

    // MARK: - Refresh

    /// Resolves each watched account (npub/hex instantly, NIP-05 via one
    /// cached lookup), fetches recent notes — plus reactions and mentions
    /// where those are watched, and every followed hashtag's feed — and
    /// lands new ones as chat things. Returns the new count, or nil when
    /// nothing could be reached at all.
    @MainActor
    static func refresh(context: ModelContext) async -> Int? {
        let store = NostrStore.shared
        guard store.connected, !running else { return store.connected ? 0 : nil }
        running = true
        healed = false
        resurfaced = 0
        defer { running = false }

        // `landed`'s keys already ARE every existing ref for this source — a
        // separate `existingSourceRefs` call used to re-fetch the exact same
        // rows a second time just for their sourceRef column (perf,
        // 2026-07-28), doubling the DB round trip for no new information.
        let landed = IngestSupport.thingsByRef(context, source: "Nostr")
        var existing = Set(landed.keys)
        let backfill = ArtlessBackfill(context, source: "Nostr")
        var added = 0
        var anyResolved = false

        for account in store.accounts {
            guard let hex = await pubkeyHex(for: account.input) else { continue }

            let result = await NostrRelay.requestAll(filter: ["authors": [hex], "kinds": [1], "limit": 30])
            // `reached` — not the notes count — is the honest "did we get
            // through" signal: a genuinely quiet account still says so.
            if result.reached { anyResolved = true }

            let who = await profile(pubkeyHex: hex)
            if let who,
               who.displayName != account.displayName || who.bio != account.bio
                || who.avatarURL != account.avatarURL || who.nip05 != account.nip05 {
                store.setProfile(who, for: account.input)
            }

            added += await landPage(result.events, existing: &existing, landed: landed,
                                    backfill: backfill, context: context)

            if account.likes {
                added += await landLikes(pubkeyHex: hex, existing: &existing, landed: landed,
                                         backfill: backfill, context: context)
            }
            if account.mentions {
                added += await landMentions(pubkeyHex: hex, existing: &existing, landed: landed,
                                            backfill: backfill, context: context)
            }
        }

        for tag in store.hashtags {
            let (count, reached) = await landHashtag(tag, existing: &existing, landed: landed,
                                                      backfill: backfill, context: context)
            if reached { anyResolved = true }
            added += count
        }

        guard anyResolved else { return nil }
        if added > 0 || backfill.any || healed { context.saveHonestly() }
        return added
    }

    // MARK: - Reactions, mentions, hashtags (parity with Farcaster's likes/mentions/channels)

    /// How recent a reaction has to be to count as NEWS — mirrors
    /// `FarcasterIngest.likeNewsWindow` exactly: the first pass over an
    /// account's reaction history must not throw its whole back catalogue at
    /// the top of a newest-first feed.
    private static let likeNewsWindow: TimeInterval = 86_400

    /// The account's reactions (kind:7) — each reacted-to note lands as a
    /// thing, stamped with the REACTION's time. Any content that isn't a
    /// literal "-" (NIP-25's explicit downvote) counts: real clients emit
    /// "+", an empty string, or an emoji for a plain like, and none of those
    /// is worth telling apart from the others here.
    ///
    /// A note the corpus ALREADY holds RESURFACES instead of re-landing —
    /// the Farcaster `landLikes`/`resurface` pattern, unchanged.
    @MainActor
    private static func landLikes(pubkeyHex: String, existing: inout Set<String>,
                                  landed: [String: Thing], backfill: ArtlessBackfill,
                                  context: ModelContext) async -> Int {
        let result = await NostrRelay.requestAll(
            filter: ["authors": [pubkeyHex], "kinds": [7], "limit": 50])
        var targets: [(id: String, liked: Date?)] = []
        for reaction in result.events {
            guard (reaction["content"] as? String ?? "+") != "-",
                  let eTag = tags(reaction).last(where: { $0.first == "e" && $0.count >= 2 })
            else { continue }
            let targetID = eTag[1]
            let liked = (reaction["created_at"] as? Int).map {
                Date(timeIntervalSince1970: TimeInterval($0))
            }
            guard !existing.contains("nostr:\(targetID)") else {
                resurface(landed["nostr:\(targetID)"], liked: liked)
                continue
            }
            targets.append((targetID, liked))
        }
        guard !targets.isEmpty else { return 0 }
        let ids = Array(Set(targets.map(\.id)))
        let fetched = await NostrRelay.requestAll(filter: ["ids": ids])
        let byID = Dictionary(uniqueKeysWithValues: fetched.events.compactMap { e -> (String, [String: Any])? in
            guard let id = e["id"] as? String else { return nil }
            return (id, e)
        })
        var added = 0
        for target in targets {
            guard let event = byID[target.id] else { continue }
            if await land(event: event, capturedAt: target.liked, why: "liked",
                          existing: &existing, landed: landed, backfill: backfill, context: context) {
                added += 1
            }
        }
        return added
    }

    /// Restamps a held note with the moment a watched account reacted to it
    /// — the exact contract as `FarcasterIngest.resurface`: forward only
    /// (a reaction can't predate the note it reacts to), news only (inside
    /// `likeNewsWindow`), live only (`isLive`, since `landed` was captured at
    /// the start of the refresh and a heal can delete out from under it).
    @MainActor
    private static func resurface(_ thing: Thing?, liked: Date?) {
        guard let thing, thing.isLive, let liked,
              liked > thing.capturedAt,
              Date.now.timeIntervalSince(liked) < likeNewsWindow else { return }
        thing.capturedAt = liked
        healed = true
        resurfaced += 1
    }

    /// How many held notes the last refresh moved back into view — mirrors
    /// `FarcasterIngest.resurfaced`.
    @MainActor private(set) static var resurfaced = 0

    /// Notes by OTHERS naming this account (`#p` tag) — replies included,
    /// since a mention usually is one. New ones ride "while I was away".
    @MainActor
    private static func landMentions(pubkeyHex: String, existing: inout Set<String>,
                                     landed: [String: Thing], backfill: ArtlessBackfill,
                                     context: ModelContext) async -> Int {
        let result = await NostrRelay.requestAll(
            filter: ["#p": [pubkeyHex], "kinds": [1], "limit": 30])
        return await landPage(result.events, why: "mention", existing: &existing, landed: landed,
                              backfill: backfill, context: context)
    }

    /// A followed hashtag's newest notes (`#t` tag) — the Nostr dose of
    /// Farcaster's channel/Bluesky's feed sync. Returns whether the read
    /// actually reached a relay, so a hashtags-only refresh can still say so.
    @MainActor
    private static func landHashtag(_ hashtag: NostrStore.Hashtag, existing: inout Set<String>,
                                    landed: [String: Thing], backfill: ArtlessBackfill,
                                    context: ModelContext) async -> (count: Int, reached: Bool) {
        let result = await NostrRelay.requestAll(
            filter: ["#t": [hashtag.tag], "kinds": [1], "limit": 30])
        let count = await landPage(result.events, hashtag: hashtag.tag, existing: &existing,
                                   landed: landed, backfill: backfill, context: context)
        return (count, result.reached)
    }

    /// Lands a page of notes: one batched fetch warms the author-profile
    /// cache and any quoted/replied-to note's card for every NEW note, then
    /// each note lands off the cache — Nostr's array-of-authors/array-of-ids
    /// filters mean a whole page's warmup costs ONE relay round trip, not
    /// one per note the way Farcaster's per-fid/per-hash lookups do.
    @MainActor
    private static func landPage(_ events: [[String: Any]], why: String? = nil,
                                 hashtag: String? = nil,
                                 existing: inout Set<String>, landed: [String: Thing],
                                 backfill: ArtlessBackfill, context: ModelContext) async -> Int {
        var authors: [String] = []
        var refs: Set<String> = []
        for event in events {
            guard let id = event["id"] as? String else { continue }
            let ref = "nostr:\(id)"
            let isNew = !existing.contains(ref)
            if isNew, let author = event["pubkey"] as? String { authors.append(author) }
            // A note being HEALED needs its quote/parent warmed too, not
            // just a new one — the Farcaster `landPage` lesson, unchanged.
            if isNew || landed[ref].map({ $0.quote == nil || $0.parent == nil }) == true {
                if let q = quoteTarget(event) { refs.insert(q) }
                if let p = replyTarget(event) { refs.insert(p) }
            }
        }
        await prefetchProfiles(authors)
        await prefetchCards(Array(refs))
        var added = 0
        for event in events {
            if await land(event: event, why: why, hashtag: hashtag,
                          existing: &existing, landed: landed, backfill: backfill, context: context) {
                added += 1
            }
        }
        return added
    }

    /// Lands one note. An author whose profile can't be resolved still
    /// lands — unlike Farcaster (where a nameless author means the cast is
    /// skipped and retried next time, since the permalink NEEDS a username),
    /// a Nostr permalink only needs the note's own id, so a silent author is
    /// no reason to drop the note.
    @MainActor
    @discardableResult
    private static func land(event: [String: Any], capturedAt: Date? = nil, why: String? = nil,
                             hashtag: String? = nil,
                             existing: inout Set<String>, landed: [String: Thing],
                             backfill: ArtlessBackfill, context: ModelContext) async -> Bool {
        guard let id = event["id"] as? String,
              let authorHex = event["pubkey"] as? String,
              let text = event["content"] as? String, !text.isEmpty,
              let created = event["created_at"] as? Int else { return false }
        let ref = "nostr:\(id)"
        let images = imageEmbeds(event)
        guard !existing.contains(ref) else {
            backfill.patch(ref, image: images.first)
            await heal(landed[ref], event: event, images: images, why: why, hashtag: hashtag)
            return false
        }
        guard let note = NostrBech32.hexToNote(id) else { return false }

        let thing = Thing(
            kind: .chat,
            title: IngestSupport.titleLine(text),
            content: "https://njump.me/\(note)",
            source: "Nostr",
            capturedAt: capturedAt ?? Date(timeIntervalSince1970: TimeInterval(created)),
            sourceRef: ref
        )
        thing.postText = text
        thing.imageURLs = images.compactMap(IngestSupport.imageURL)
        thing.previewImageURL = thing.imageURLs.first
        // The stable protocol identity, not a display string (2026-07-27) —
        // every downstream exact-match consumer (KeptAskComposers, the
        // roster's own key, `rowLabel`) needs a value that never changes
        // when a profile updates; display resolves at render time via
        // `SocialThread.shortHandle`/`NostrStore.displayHandle`.
        thing.authorHandle = authorHex
        thing.authorAvatarURL = await profile(pubkeyHex: authorHex)?.avatarURL
        thing.socialContext = why
        thing.channelName = hashtag
        thing.quote = await card(id: quoteTarget(event))
        thing.parent = await card(id: replyTarget(event))
        context.insert(thing)
        SpotlightIndex.index([thing])
        existing.insert(ref)
        return true
    }

    /// Fills the enrichment fields on a note that landed BEFORE they existed
    /// — the Farcaster/Bluesky `heal` contract exactly: only ever FILLS a
    /// gap, never rewrites what a good sync already landed.
    @MainActor
    private static func heal(_ thing: Thing?, event: [String: Any], images: [String],
                             why: String?, hashtag: String?) async {
        guard let thing else { return }
        if thing.socialContext == nil, let why {
            thing.socialContext = why
            healed = true
        }
        if thing.channelName == nil, let hashtag {
            thing.channelName = hashtag
            healed = true
        }
        if thing.postText == nil, let text = event["content"] as? String, !text.isEmpty {
            thing.postText = text
            healed = true
        }
        if thing.imageURLs.isEmpty, !images.isEmpty {
            thing.imageURLs = images.compactMap(IngestSupport.imageURL)
            healed = true
        }
        if thing.quote == nil, let quote = await card(id: quoteTarget(event)) {
            thing.quote = quote
            healed = true
        }
        if thing.parent == nil, let parent = await card(id: replyTarget(event)) {
            thing.parent = parent
            healed = true
        }
    }

    /// True once `heal` filled a gap this pass — joins the refresh's save
    /// condition. Reset each refresh; the `running` guard keeps one flag safe.
    @MainActor private static var healed = false

    // MARK: - Delete-sync

    @MainActor private static var healRunning = false
    private static let healInterval: TimeInterval = 3600
    private static let healKey = "nostr.lastHeal"

    /// Reconciles against what the relays still serve. Nostr relays support
    /// an array of ids in one filter (like Bluesky's batched `getPosts`), so
    /// this checks a whole chunk of stored refs per relay round trip.
    ///
    /// The honesty guard here is stronger than Bluesky's own heal needs to
    /// be: a SINGLE host's HTTP response can be trusted at face value, but a
    /// merge across several relays has no status code to check, so
    /// `NostrRelay.Result.reached` carries that signal instead — a chunk is
    /// only eligible to be "not returned" (deleted) when at least one relay
    /// actually completed the round trip for it. Every relay timing out on a
    /// chunk skips it entirely rather than reading the resulting emptiness
    /// as a mass deletion.
    @MainActor
    static func heal(context: ModelContext, force: Bool = false) async -> Int {
        guard !healRunning else { return 0 }
        if !force, let last = UserDefaults.standard.object(forKey: healKey) as? Date,
           Date.now.timeIntervalSince(last) < healInterval { return 0 }
        healRunning = true
        defer { healRunning = false }
        UserDefaults.standard.set(Date.now, forKey: healKey)

        let things = IngestSupport.thingsByRef(context, source: "Nostr")
        let idToRef = Dictionary(uniqueKeysWithValues: things.keys
            .filter { $0.hasPrefix("nostr:") }
            .map { (String($0.dropFirst("nostr:".count)), $0) })
        guard !idToRef.isEmpty else { return 0 }

        var present = Set<String>()
        let ids = Array(idToRef.keys)
        var removedIDs: [UUID] = []
        for start in stride(from: 0, to: ids.count, by: 100) {
            let chunk = Array(ids[start..<min(start + 100, ids.count)])
            let result = await NostrRelay.requestAll(filter: ["ids": chunk])
            guard result.reached else { continue }   // never treat a timed-out chunk as "gone"
            for event in result.events {
                if let id = event["id"] as? String { present.insert(id) }
            }
            for id in chunk where !present.contains(id) {
                guard let ref = idToRef[id], let thing = things[ref] else { continue }
                removedIDs.append(thing.id)
                context.delete(thing)
            }
        }
        guard !removedIDs.isEmpty else { return 0 }
        context.saveHonestly()
        SpotlightIndex.remove(ids: removedIDs)
        return removedIDs.count
    }

    // MARK: - Hashtags: follow

    @MainActor
    @discardableResult
    static func followHashtag(_ raw: String) -> NostrStore.Hashtag? {
        let tag = NostrStore.normalizeHashtag(raw)
        guard !tag.isEmpty else { return nil }
        if let existing = NostrStore.shared.hashtags.first(where: { $0.tag == tag }) { return existing }
        let hashtag = NostrStore.Hashtag(tag: tag)
        NostrStore.shared.addHashtag(hashtag)
        return hashtag
    }

    // MARK: - Replies (the sheet's thread context)

    @MainActor private static var threads: [String: [SocialReply]] = [:]

    /// The thread under one note, oldest first, capped — only events that
    /// actually MARK this as their reply target (NIP-10), since an `#e`
    /// filter also catches a quote or mention pointing at the same id.
    @MainActor
    static func replies(eventID: String, limit: Int = 8) async -> [SocialReply] {
        if let cached = threads[eventID] { return cached }
        let result = await NostrRelay.requestAll(
            filter: ["#e": [eventID], "kinds": [1], "limit": limit * 3])
        let replyEvents = result.events
            .filter { replyTarget($0) == eventID }
            .sorted { ($0["created_at"] as? Int ?? 0) < ($1["created_at"] as? Int ?? 0) }
        await prefetchProfiles(replyEvents.compactMap { $0["pubkey"] as? String })
        var out: [SocialReply] = []
        for event in replyEvents {
            guard let id = event["id"] as? String,
                  let author = event["pubkey"] as? String,
                  let text = event["content"] as? String, !text.isEmpty,
                  let note = NostrBech32.hexToNote(id) else { continue }
            out.append(SocialReply(
                id: id, handle: author, avatarURL: await profile(pubkeyHex: author)?.avatarURL,
                text: text,
                when: (event["created_at"] as? Int).map { Date(timeIntervalSince1970: TimeInterval($0)) },
                url: "https://njump.me/\(note)", ref: "nostr:\(id)"))
            if out.count == limit { break }
        }
        threads[eventID] = out   // a miss returned [] above, uncached — it retries
        return out
    }

    // MARK: - Profiles

    /// A pubkey's profile facts (kind:0) — fetched once per pubkey per
    /// launch. nil when no relay answered: a FAILURE IS NOT CACHED, so the
    /// next refresh retries instead of suppressing that author for good.
    @MainActor
    static func profile(pubkeyHex: String) async -> Profile? {
        if let cached = profiles[pubkeyHex] { return cached }
        let result = await NostrRelay.requestAll(
            filter: ["authors": [pubkeyHex], "kinds": [0], "limit": 1])
        guard let newest = result.events.max(by: {
            ($0["created_at"] as? Int ?? 0) < ($1["created_at"] as? Int ?? 0)
        }), let parsed = parseProfile(newest) else { return nil }
        profiles[pubkeyHex] = parsed
        return parsed
    }

    /// Warms the profile cache for a batch of pubkeys in ONE relay round
    /// trip — Nostr's `authors` filter takes an array, unlike Farcaster's
    /// per-fid `userDataByFid`.
    @MainActor
    private static func prefetchProfiles(_ hexes: [String]) async {
        let missing = Array(Set(hexes).filter { profiles[$0] == nil })
        guard !missing.isEmpty else { return }
        let result = await NostrRelay.requestAll(filter: ["authors": missing, "kinds": [0]])
        for event in result.events {
            guard let pk = event["pubkey"] as? String, profiles[pk] == nil,
                  let parsed = parseProfile(event) else { continue }
            profiles[pk] = parsed
        }
    }

    /// A kind:0 event's `content` is itself a JSON string (`{"name":…,
    /// "picture":…}`) — NIP-01's one double-encoded field. nil when nothing
    /// nameable came through, so a relay serving an empty/garbage profile
    /// reads as "no profile" rather than a hollow cache entry.
    static func parseProfile(_ event: [String: Any]) -> Profile? {
        guard let content = event["content"] as? String,
              let data = content.data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        let name = nonEmpty(json["display_name"] as? String)
            ?? nonEmpty(json["displayName"] as? String)
            ?? nonEmpty(json["name"] as? String)
        let about = nonEmpty(json["about"] as? String)
        let picture = IngestSupport.imageURL(json["picture"] as? String)
        let nip05 = nonEmpty(json["nip05"] as? String)
        guard name != nil || about != nil || picture != nil || nip05 != nil else { return nil }
        return Profile(displayName: name, bio: about, avatarURL: picture, nip05: nip05)
    }

    private static func nonEmpty(_ s: String?) -> String? {
        let trimmed = (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Quotes and parents (NIP-10/NIP-18)

    private static func tags(_ event: [String: Any]) -> [[String]] {
        (event["tags"] as? [[String]]) ?? []
    }

    private static func eTags(_ event: [String: Any]) -> [(id: String, marker: String?)] {
        tags(event).filter { $0.first == "e" }.compactMap { t in
            guard t.count >= 2, !t[1].isEmpty else { return nil }
            return (t[1], t.count >= 4 ? t[3] : nil)
        }
    }

    /// The note this one replies UNDER (NIP-10): the "reply"-marked e-tag
    /// when markers are used, else — the older positional convention, where
    /// unmarked e-tags read root-first/reply-last — the last e-tag. A note
    /// with no e-tags at all is top-level.
    private static func replyTarget(_ event: [String: Any]) -> String? {
        let es = eTags(event)
        guard !es.isEmpty else { return nil }
        if let marked = es.first(where: { $0.marker == "reply" }) { return marked.id }
        if es.allSatisfy({ $0.marker == nil }) { return es.last?.id }
        return nil
    }

    /// The note this one QUOTES: the newer "q" tag when present, else an
    /// e-tag explicitly marked "mention" — Nostr's closest signature form to
    /// Farcaster/Bluesky's structured quote embed.
    private static func quoteTarget(_ event: [String: Any]) -> String? {
        if let q = tags(event).first(where: { $0.first == "q" && $0.count >= 2 }) { return q[1] }
        if let mention = eTags(event).first(where: { $0.marker == "mention" }) { return mention.id }
        return nil
    }

    /// EVERY image a note carries, in order — NIP-92 `imeta` tags when the
    /// author's client wrote them, else a bare-URL sniff over the note's own
    /// text (Nostr has no structured embed otherwise, so a plain pasted
    /// image link is the only signal left).
    private static func imageEmbeds(_ event: [String: Any]) -> [String] {
        var out: [String] = []
        for tag in tags(event) where tag.first == "imeta" {
            var url: String?
            var isImage = false
            for field in tag.dropFirst() {
                if field.hasPrefix("url ") { url = String(field.dropFirst(4)) }
                if field.hasPrefix("m "), field.dropFirst(2).hasPrefix("image/") { isImage = true }
            }
            if isImage, let url { out.append(url) }
        }
        if out.isEmpty, let text = event["content"] as? String {
            out = extractImageURLs(text)
        }
        return out
    }

    private static func extractImageURLs(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).compactMap { token -> String? in
            let s = String(token)
            guard s.lowercased().hasPrefix("http") else { return nil }
            let path = URL(string: s)?.path.lowercased() ?? s.lowercased()
            return [".jpg", ".jpeg", ".png", ".gif", ".webp"].contains(where: path.hasSuffix) ? s : nil
        }
    }

    @MainActor private static var cards: [String: SocialCard] = [:]

    /// One referenced note as a card, by event id. Cached per launch, so a
    /// thread where many notes quote the same one costs one lookup.
    @MainActor
    static func card(id: String?) async -> SocialCard? {
        guard let id else { return nil }
        if let cached = cards[id] { return cached }
        let result = await NostrRelay.requestAll(filter: ["ids": [id]], timeout: 6)
        guard let event = result.events.first(where: { ($0["id"] as? String) == id }),
              let built = await cardFrom(event) else { return nil }
        cards[id] = built
        return built
    }

    /// `handle` carries the raw hex pubkey, not a resolved display string —
    /// same reasoning as `Thing.authorHandle`: a SocialCard is a frozen
    /// snapshot (Farcaster/Bluesky freeze theirs too, at fetch time), but
    /// whatever profile-lookup path a tap on this card takes needs a real,
    /// re-resolvable identity, not a truncated npub. `SocialThread.
    /// shortHandle` is what turns it into a display string wherever a
    /// SocialCard renders — already the single choke point every quote/
    /// parent view calls.
    private static func cardFrom(_ event: [String: Any]) async -> SocialCard? {
        guard let id = event["id"] as? String,
              let authorHex = event["pubkey"] as? String,
              let text = event["content"] as? String, !text.isEmpty,
              let note = NostrBech32.hexToNote(id) else { return nil }
        let avatar = await profile(pubkeyHex: authorHex)?.avatarURL
        return SocialCard(handle: authorHex, text: text, avatarURL: avatar,
                          url: "https://njump.me/\(note)", ref: "nostr:\(id)")
    }

    /// Warms the card cache for a batch of event ids in ONE relay round trip
    /// — Nostr's `ids` filter takes an array, unlike Farcaster's one-hash-
    /// per-request `castById`.
    @MainActor
    private static func prefetchCards(_ ids: [String]) async {
        let missing = ids.filter { cards[$0] == nil }
        guard !missing.isEmpty else { return }
        let result = await NostrRelay.requestAll(filter: ["ids": missing])
        for event in result.events {
            guard let id = event["id"] as? String, cards[id] == nil,
                  let built = await cardFrom(event) else { continue }
            cards[id] = built
        }
    }

    // MARK: - Follow list (kind:3 — SocialFollows' Nostr arm)

    /// The pubkeys in a person's kind:3 contact list — the WHOLE graph in
    /// one relay round trip (contact lists are a single replaceable event,
    /// unlike Farcaster/Bluesky's paginated follow feeds). `reached`
    /// distinguishes "no contact list published" from "couldn't reach a
    /// relay" the way every other read here does.
    @MainActor
    static func contactList(pubkeyHex: String) async -> (pubkeys: [String], reached: Bool) {
        let result = await NostrRelay.requestAll(filter: ["authors": [pubkeyHex], "kinds": [3], "limit": 1])
        guard let newest = result.events.max(by: {
            ($0["created_at"] as? Int ?? 0) < ($1["created_at"] as? Int ?? 0)
        }) else { return ([], result.reached) }
        var seen = Set<String>()
        let pubkeys = tags(newest)
            .filter { $0.first == "p" && $0.count >= 2 && !$0[1].isEmpty }
            .map { $0[1] }
            .filter { seen.insert($0).inserted }
        return (pubkeys, result.reached)
    }

    // MARK: - Engagement

    private static let reactionPage = 100

    /// A note's reactions/reposts/replies, counted live from the relays —
    /// page-capped the way Farcaster's are (no relay reports a network-wide
    /// total), so a full page means "at least this many".
    @MainActor
    static func engagement(for thing: Thing) async -> SocialEngagement? {
        guard thing.source == "Nostr", let ref = thing.sourceRef,
              ref.hasPrefix("nostr:") else { return nil }
        let id = String(ref.dropFirst("nostr:".count))
        async let likesResult = NostrRelay.requestAll(
            filter: ["#e": [id], "kinds": [7], "limit": reactionPage])
        async let repostsResult = NostrRelay.requestAll(
            filter: ["#e": [id], "kinds": [6], "limit": reactionPage])
        async let repliesResult = NostrRelay.requestAll(
            filter: ["#e": [id], "kinds": [1], "limit": reactionPage])
        let likes = await likesResult
        let reposts = await repostsResult
        let replies = await repliesResult
        let likeCount = likes.events.filter { ($0["content"] as? String ?? "+") != "-" }.count
        let replyCount = replies.events.filter { replyTarget($0) == id }.count
        let e = SocialEngagement(
            likes: SocialCount(value: likeCount, atLeast: likes.events.count >= reactionPage),
            reposts: SocialCount(value: reposts.events.count, atLeast: reposts.events.count >= reactionPage),
            replies: SocialCount(value: replyCount, atLeast: replies.events.count >= reactionPage))
        return e.isEmpty ? nil : e
    }
}
