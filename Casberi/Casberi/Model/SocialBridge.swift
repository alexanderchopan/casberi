import Foundation
import SwiftData

/// The source-neutral social surfaces (2026-07-14) — the shapes both the
/// Farcaster and Bluesky bridges answer, so the shared setup row and the
/// thing sheet's thread render from ONE path instead of a per-bridge fork.
/// When a third social bridge arrives it fills these in; nothing in the UI
/// learns its name.

/// One reply under a post/cast — the thing sheet's thread context. `url` is
/// the reply's own web permalink (the Open verb); `ref` is its PROTOCOL ref in
/// `sourceRef` form ("fc:<hash>", "bsky:<at-uri>"), which is what reading its
/// own replies needs — the web permalink can't stand in, because Farcaster's
/// carries only the first 10 characters of the hash (2026-07-16).
struct SocialReply: Identifiable {
    let id: String
    let handle: String
    let avatarURL: String?
    let text: String
    let when: Date?
    let url: String?
    var ref: String? = nil

    /// This reply as a post card — what opening it in-app renders.
    var card: SocialCard {
        SocialCard(handle: handle, text: text, avatarURL: avatarURL, url: url, ref: ref)
    }
}

/// One engagement number as the network actually reported it (2026-07-16).
/// `atLeast` is the honesty valve: Bluesky's AppView serves exact totals, but
/// Snapchain serves reaction MESSAGES, so a Farcaster count is the size of one
/// page — a full page means "at least this many", and the sheet says "100+"
/// rather than claiming a total nobody counted.
struct SocialCount: Equatable {
    let value: Int
    var atLeast: Bool = false

    /// "42", or "100+" when the page capped.
    var text: String { atLeast ? "\(value)+" : "\(value)" }
}

/// A post's engagement at read time. A count the source didn't report stays
/// nil — distinct from a reported zero, which means "none" (honesty rule).
struct SocialEngagement: Equatable {
    var likes: SocialCount?
    var reposts: SocialCount?
    var replies: SocialCount?

    var isEmpty: Bool { likes == nil && reposts == nil && replies == nil }
}

/// A post/cast's replies, dispatched by source. A thing that isn't a social
/// post (or a source with no thread reader) returns nothing.
enum SocialThread {
    /// The sources that carry an author, a thread, and a network wash — the
    /// UI keys its social treatment (author eyebrow, Open-thread verb, thread
    /// section) off this, never off a hardcoded name.
    static let sources: Set<String> = ["Bluesky", "Farcaster", "Nostr"]
    static func isSocial(_ source: String) -> Bool { sources.contains(source) }

    /// Sources that earn a CONTEXT LABEL ("Mentions you", a channel name) in
    /// a row's trailing slot or a sheet's eyebrow — without the rest of the
    /// social treatment `isSocial` gates (thread reader, profile card, live
    /// engagement counts). Slack's mentions bridge (2026-07-28) has an author
    /// and a channel but no thread API and no profile lookup to back those,
    /// so it earns only this half — `isSocial`/`sources` above stay the
    /// thread-capable set, untouched.
    ///
    /// X joined on the same terms (2026-08-06). Its archive has an author and
    /// a provenance word ("Liked") and will never have a thread API or a
    /// profile lookup — X has no free read left at all — so it earns this half
    /// and not the other, exactly like Slack. It is what tells the two halves
    /// of that room apart once every row renders as a post card: your own
    /// writing and posts you liked, which otherwise differ only by a handle
    /// that `fetchFaces` may not have named yet.
    /// Instagram joined 2026-08-18 (prd §395) on X's own terms and for its own
    /// reason: once the room draws every row as a post card, a saved post and a
    /// liked one differ only by a marker, and both differ from something you
    /// wrote only by a handle the caption pass may not have reached yet. The
    /// export states the act, so the card can say it.
    static let contextSources: Set<String> = sources.union(["Slack", "X", "Instagram"])
    static func hasContext(_ source: String) -> Bool { contextSources.contains(source) }

    /// Sources whose PERSON ROOM can be opened (2026-08-18, prd §395).
    ///
    /// A THIRD set, and it is genuinely a third question. `isSocial` asks
    /// whether a network can be reached — a thread read, a profile lookup, a
    /// Watch verb — and X can never answer yes to any of it. `hasContext` asks
    /// whether a row carries a provenance word. This asks whether the CORPUS
    /// can describe a person, which needs nothing from the network at all: an
    /// X archive holds your replies to somebody, your posts naming them and
    /// their posts you liked, spanning years X's own search cannot reach.
    ///
    /// So `SocialProfileCard` stays gated on `isSocial` — its one verb is
    /// Watch and on X that is impossible, which would be the dead control the
    /// honesty law bans — while `PersonRoomScreen`, which only ever reads what
    /// is already here, opens for either.
    static let personSources: Set<String> = sources.union(["X"])
    static func hasPersonRoom(_ source: String) -> Bool { personSources.contains(source) }

    /// How many replies a thread fetch returns — the sheet shows this many at
    /// most, so a thread AT this count may have more (the header says "N+").
    static let replyCap = 8

    /// A handle without Bluesky's ".bsky.social" tail — the name the person
    /// knows. Farcaster handles have no tail, so they pass through unchanged.
    /// A raw 64-hex Nostr pubkey (what `Thing.authorHandle`/`SocialCard.
    /// handle` store for that source, since a display name isn't always
    /// available) becomes a short npub instead — the one choke point every
    /// quote/parent/reply render already calls, so making it hex-aware here
    /// fixes every one of those views at once.
    static func shortHandle(_ handle: String) -> String {
        if handle.hasSuffix(".bsky.social") {
            return String(handle.dropLast(".bsky.social".count))
        }
        if handle.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil,
           let npub = NostrBech32.hexToNpub(handle) {
            return NostrBech32.shortNpub(npub)
        }
        return handle
    }

    @MainActor
    static func replies(for thing: Thing) async -> [SocialReply] {
        // Build 256: a detached Task runs LATER than it was created, so this
        // row can already be deleted by the time this line does (prd §297).
        guard thing.isLive else { return [] }
        // GitHub isn't a social source (no author eyebrow, no context label)
        // but an issue/PR's comment thread is the identical "read live when
        // the sheet opens" shape, so it rides the same section (2026-07-16).
        if thing.source == "GitHub" {
            return await GitHubFeedFetch.comments(for: thing)
        }
        guard let ref = thing.sourceRef else { return [] }
        return await replies(source: thing.source, ref: ref, handle: thing.authorHandle)
    }

    /// A post's replies by its protocol ref — the one reader, so a thing's
    /// thread and a REPLY's own thread come through the same door and the
    /// conversation can be walked in-app (2026-07-16). Farcaster needs the
    /// author's handle to resolve the fid its node keys casts by; Bluesky's
    /// at-uri carries everything.
    @MainActor
    static func replies(source: String, ref: String, handle: String?) async -> [SocialReply] {
        switch source {
        case "Farcaster":
            guard ref.hasPrefix("fc:"), let handle, !handle.isEmpty else { return [] }
            return await FarcasterIngest.replies(handle: handle,
                                                 hash: String(ref.dropFirst(3)), limit: replyCap)
        case "Bluesky":
            guard ref.hasPrefix("bsky:") else { return [] }
            return await BlueskyIngest.replies(uri: String(ref.dropFirst("bsky:".count)),
                                               limit: replyCap)
        case "Nostr":
            // No handle needed — an `#e`-tag filter finds a note's replies by
            // its own id alone, unlike Farcaster's fid-keyed lookup.
            guard ref.hasPrefix("nostr:") else { return [] }
            return await NostrIngest.replies(eventID: String(ref.dropFirst("nostr:".count)),
                                             limit: replyCap)
        default:
            return []
        }
    }

    /// A post's likes/reposts/replies, read LIVE when the sheet opens — a count
    /// is only true at the moment it's read, so the sheet asks rather than
    /// trusting what a sync stored hours ago. nil when the network reported
    /// nothing we'd stand behind.
    @MainActor
    static func engagement(for thing: Thing) async -> SocialEngagement? {
        // Build 256: a detached Task runs LATER than it was created, so this
        // row can already be deleted by the time this line does (prd §297).
        guard thing.isLive else { return nil }
        switch thing.source {
        case "Farcaster": return await FarcasterIngest.engagement(for: thing)
        case "Bluesky":   return await BlueskyIngest.engagement(for: thing)
        case "Nostr":     return await NostrIngest.engagement(for: thing)
        default:          return nil
        }
    }

    /// WHY this post is here, in one word the row can wear (2026-07-16) —
    /// "Liked", "Mentions you", "/design". A liked cast, a channel cast, and
    /// your own post used to render identically, so the feed couldn't say why
    /// any of them had arrived. nil for the plain case (an account you watch
    /// posted it), where the face already says everything.
    ///
    /// The channel wins over the provenance word: a mention that arrives in a
    /// channel is more usefully "/design" than "Mentions you" — the channel is
    /// the lane, and the sheet's eyebrow still carries both.
    static func contextLabel(for thing: Thing) -> String? {
        guard hasContext(thing.source) else { return nil }
        if let channel = thing.channelName, !channel.isEmpty {
            // Farcaster channels ARE "/design" to the person, a followed
            // Nostr hashtag is "#design", and a Bluesky feed is a proper
            // name ("Science") that wears neither mark.
            switch thing.source {
            case "Farcaster": return "/\(channel)"
            case "Nostr":     return "#\(channel)"
            default:          return channel
            }
        }
        switch thing.socialContext {
        case "liked":   return String(localized: "Liked")
        // Instagram's other half. A save is a deliberate keep and a like is a
        // reaction in passing — §247 refuses to sum them into one ranking, and
        // the card refuses to spell them with one word for the same reason.
        case "saved":   return String(localized: "Saved")
        case "recast":  return recastWord(thing.source)
        case "mention": return String(localized: "Mentions you")
        case "reply":   return String(localized: "Replied to you")
        case "follow":  return String(localized: "Followed you")
        default:        return nil
        }
    }

    /// The word a network uses for an amplified post — one shared marker
    /// ("recast") on the thing, spoken in each network's own noun. Nostr
    /// calls it a repost too (NIP-18), so Farcaster is the exception here,
    /// not the rule.
    static func recastWord(_ source: String) -> String {
        source == "Farcaster" ? String(localized: "Recast") : String(localized: "Reposted")
    }

    /// The same fact as a CLAUSE, for the sheet's eyebrow — where it sits in a
    /// sentence ("@dwr · in /design · 2h ago") rather than alone in a label
    /// slot. Same source of truth, different grammar: a row has room for a
    /// word, a sentence wants a phrase.
    static func contextPhrase(for thing: Thing) -> String? {
        guard hasContext(thing.source) else { return nil }
        if let channel = thing.channelName, !channel.isEmpty {
            switch thing.source {
            case "Farcaster": return String(localized: "in /\(channel)")
            case "Nostr":     return String(localized: "in #\(channel)")
            default:          return String(localized: "in \(channel)")
            }
        }
        switch thing.socialContext {
        case "liked":   return String(localized: "you liked this")
        // Deliberately NOT "you recast this" (§221's open falsity, which the
        // likes phrase above still carries): a recast marker is written by
        // whichever WATCHED account amplified it, which is usually not you.
        // The thing carries no recaster handle, so the phrase says exactly
        // what's known and no more.
        case "recast":
            return thing.source == "Farcaster"
                ? String(localized: "recast by an account you watch")
                : String(localized: "reposted by an account you watch")
        case "mention": return String(localized: "mentions you")
        case "reply":   return String(localized: "replied to you")
        case "follow":  return String(localized: "started following you")
        default:        return nil
        }
    }
}

/// A person on a social network, as the profile card shows them (2026-07-16).
/// The card is reached by tapping any face — a row's author, a reply's author,
/// a quoted post's author — so a mention or a reply becomes a door to the
/// person, and watching them is one tap from there.
struct SocialProfile: Identifiable, Hashable {
    let source: String
    let handle: String
    let displayName: String?
    let bio: String?
    let avatarURL: String?
    /// Farcaster only — carried so the card's Watch skips the name→fid resolve.
    var fid: Int? = nil

    /// One person on one network — what `.sheet(item:)` keys the card on.
    var id: String { "\(source):\(handle)" }
    var shortHandle: String { SocialThread.shortHandle(handle) }
    var title: String { displayName ?? "@\(shortHandle)" }
}

/// The people layer: look one up, know whether they're watched, watch them —
/// dispatched by source, so the card never learns a bridge's name (2026-07-16).
enum SocialPeople {

    /// The OTHER social network — what "are they over here too?" searches.
    /// Restricted to the two networks with a real user-search API: Nostr has
    /// no reliable global search (see `NostrIngest`'s own doc comment), so
    /// "find them on Nostr" would have nothing to search with — asking FROM
    /// a Nostr profile, or searching FOR one, both correctly find nothing.
    static func otherSource(_ source: String) -> String? {
        let searchable: Set<String> = ["Bluesky", "Farcaster"]
        guard searchable.contains(source) else { return nil }
        return searchable.subtracting([source]).first
    }

    /// Whether this handle is already watched on its network.
    @MainActor
    static func isWatched(handle: String, source: String) -> Bool {
        switch source {
        case "Farcaster":
            return FarcasterStore.shared.accounts.contains {
                $0.username == FarcasterStore.normalize(handle)
            }
        case "Bluesky":
            return BlueskyStore.shared.accounts.contains {
                $0.handle == BlueskyStore.normalize(handle)
            }
        case "Nostr":
            return NostrStore.shared.accounts.contains {
                $0.pubkeyHex == handle || $0.input == NostrStore.normalize(handle)
            }
        default: return false
        }
    }

    /// Starts watching them. Returns false when they were already watched —
    /// the card says so rather than claiming a second connect.
    @MainActor
    @discardableResult
    static func watch(_ profile: SocialProfile) -> Bool {
        switch profile.source {
        case "Farcaster":
            if let fid = profile.fid, fid > 0 {
                return FarcasterStore.shared.add(profile.handle, fid: fid)
            }
            return FarcasterStore.shared.add(profile.handle)
        case "Bluesky":
            return BlueskyStore.shared.add(profile.handle)
        case "Nostr":
            return NostrStore.shared.add(profile.handle)
        default: return false
        }
    }

    /// A handle in the form its store keeps. Hits carry the network's raw
    /// handle (the stores normalize again on add — harmless), so anything
    /// COMPARING a hit against the watch list has to normalize first.
    static func normalize(_ handle: String, source: String) -> String {
        switch source {
        case "Farcaster": return FarcasterStore.normalize(handle)
        case "Bluesky":   return BlueskyStore.normalize(handle)
        case "Nostr":     return NostrStore.normalize(handle)
        default:          return handle
        }
    }

    /// Every handle watched on this network. The import sheet snapshots this
    /// once rather than asking `isWatched` per row — a graph runs to ~1,800
    /// people, and a per-row scan of the watch list is quadratic.
    @MainActor
    static func watchedHandles(source: String) -> Set<String> {
        switch source {
        case "Farcaster": return Set(FarcasterStore.shared.accounts.map(\.username))
        case "Bluesky":   return Set(BlueskyStore.shared.accounts.map(\.handle))
        case "Nostr":
            return Set(NostrStore.shared.accounts.map { $0.pubkeyHex.isEmpty ? $0.input : $0.pubkeyHex })
        default:          return []
        }
    }

    /// Starts watching a whole picked set at once (2026-07-16) — the follow
    /// import's landing. One store write for the lot, so a 200-person import
    /// persists once; each carries the fid/handle the graph read already knew.
    /// Returns how many were NEW, which is what the sheet reports (picking
    /// someone already watched is a no-op, not a second connect).
    @MainActor
    @discardableResult
    static func watch(_ people: [UserSearch.Hit], source: String) -> Int {
        switch source {
        case "Farcaster":
            return FarcasterStore.shared.add(contentsOf: people.map { ($0.handle, $0.fid) })
        case "Bluesky":
            return BlueskyStore.shared.add(contentsOf: people.map(\.handle))
        case "Nostr":
            // A Nostr `Hit.handle` from the follow-graph read is always a
            // raw hex pubkey (the contact list's own "p" tags carry
            // nothing else), so every one resolves with no further lookup.
            return NostrStore.shared.add(contentsOf: people.map(\.handle))
        default: return 0
        }
    }

    /// Refresh whichever bridge just gained an account, so a Watch from the
    /// card lands their posts immediately instead of at the next foreground.
    @MainActor
    static func sync(source: String, context: ModelContext) async {
        switch source {
        case "Farcaster": _ = await FarcasterIngest.refresh(context: context)
        case "Bluesky":   _ = await BlueskyIngest.refresh(context: context)
        case "Nostr":     _ = await NostrIngest.refresh(context: context)
        default: break
        }
    }

    /// One person's profile facts, from their network's own public API. Both
    /// bridges already cache profiles per launch, so opening a card for someone
    /// whose posts are already landed costs nothing.
    @MainActor
    static func profile(handle: String, source: String) async -> SocialProfile? {
        switch source {
        case "Bluesky":
            let h = BlueskyStore.normalize(handle)
            guard let p = await BlueskyIngest.profile(handle: h) else { return nil }
            return SocialProfile(source: source, handle: h, displayName: p.displayName,
                                 bio: p.bio, avatarURL: p.avatarURL)
        case "Farcaster":
            let n = FarcasterStore.normalize(handle)
            guard let fid = await FarcasterIngest.fid(forName: n),
                  let p = await FarcasterIngest.profile(fid: fid) else { return nil }
            return SocialProfile(source: source, handle: n, displayName: p.displayName,
                                 bio: p.bio, avatarURL: p.avatarURL, fid: fid)
        case "Nostr":
            guard let hex = await NostrIngest.pubkeyHex(for: NostrStore.normalize(handle)),
                  let p = await NostrIngest.profile(pubkeyHex: hex) else { return nil }
            return SocialProfile(source: source, handle: hex, displayName: p.displayName,
                                 bio: p.bio, avatarURL: p.avatarURL)
        default: return nil
        }
    }

    /// Search the OTHER network for this name (2026-07-16). Deliberately a
    /// SEARCH, not a join: nothing links a Farcaster username to a Bluesky
    /// handle (Farcaster's onchain verifications have no Bluesky analog), so
    /// claiming "@dwr here is @dwr there" would be a guess wearing the clothes
    /// of a fact — exactly what the honesty rule forbids. The card asks the
    /// question and hands the person the hits; the tap that watches one is
    /// theirs, and it's the same tap the setup screen's finder offers.
    static func findElsewhere(_ handle: String, from source: String) async -> [UserSearch.Hit] {
        guard let other = otherSource(source) else { return [] }
        let query = SocialThread.shortHandle(handle)
        switch other {
        case "Bluesky":   return await UserSearch.bluesky(query)
        case "Farcaster": return await UserSearch.farcaster(query)
        default:          return []
        }
    }
}

/// One "watch more" toggle on an account row (Likes / Recasts / Mentions) —
/// the capability a bridge offers per account. Bluesky offers Reposts and
/// Mentions (likes need sign-in); Farcaster offers all three.
struct SocialWatch: Identifiable, Equatable {
    /// `mine` is the odd one out and stays here anyway: it's the same gesture
    /// (a switch on a person, in the same strip) and it reads as one to the
    /// person flipping it. What it turns on is the INBOUND half — see
    /// `SocialInbound` — rather than another thing to fetch about them.
    enum Kind: String {
        case likes = "Likes", recasts = "Recasts", mentions = "Mentions", mine = "Mine"
    }
    let kind: Kind
    let on: Bool
    /// The word THIS network uses for the kind — Farcaster recasts, Bluesky
    /// reposts. The KIND is shared (one flag, one code path); only the noun
    /// differs, and a bridge never renames someone else's verb. Defaults to
    /// the kind's own name.
    var word: String? = nil
    var id: String { kind.rawValue }
    var label: String { word ?? kind.rawValue }
}

/// A watched social account, rendered by the shared setup row: a face, a
/// display name over "@handle · bio", and the watch toggles the bridge
/// offers. `key` is what mutations use (the stored handle/username).
struct SocialAccount: Identifiable, Equatable {
    let key: String
    let title: String
    let subtitle: String
    let avatarURL: String?
    let watches: [SocialWatch]
    var id: String { key }

    /// "@handle · bio", or just "@handle" when there's no bio — the row's
    /// quiet second line, built the same way for every bridge.
    static func subtitle(handle: String, bio: String?) -> String {
        let b = (bio ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return b.isEmpty ? handle : "\(handle) · \(b)"
    }
}

/// Unfollowing a topic takes its posts with it (prd §286, 2026-08-02).
///
/// `FarcasterStore.removeChannel` and `BlueskyStore.removeFeed` only ever
/// edited their own list — nothing touched the corpus — so a channel you
/// unfollowed went on filling the feed forever, with no way to get rid of it
/// short of Delete everything. Reported 2026-08-02: "i was following a
/// channel, then i unfollowed the channel but my feed still shows the
/// channel's contents". Both bridges store the same fields, so this is one
/// path rather than a per-bridge fork (the `SocialBridge` doctrine).
///
/// **It removes only what the topic was the ONLY reason to hold**, which is
/// the whole difficulty: `channelName` does NOT mean "arrived via the
/// channel". Both bridges' heal back-fills it onto a post that landed for
/// another reason and later turned up in a followed channel (see
/// `FarcasterIngest`/`BlueskyIngest`'s `if thing.channelName == nil`), so
/// deleting on that field alone would take a watched friend's own post with
/// it and read as data loss. Two exemptions carry that:
///
///   - a `socialContext` (liked / recast / reply / mention) — the post is in
///     the corpus for a reason that has nothing to do with the topic;
///   - an author you WATCH — you follow the person, and you'd still have
///     their post with the channel gone.
///
/// Anything left is a stranger's post in a room you left.
enum SocialTopics {
    /// Returns how many were removed.
    @MainActor
    @discardableResult
    static func pruneTopic(source: String, channel: String,
                           watchedHandles: [String], context: ModelContext) -> Int {
        let name = channel.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return 0 }
        let watched = Set(watchedHandles.map { $0.lowercased() })

        // `source` is compared in the predicate (a plain String equality
        // SwiftData can push down); everything else is filtered in Swift —
        // the corpus-scale narrowing is already done, and a `#Predicate`
        // reaching into an array attribute crashes at runtime (see CLAUDE.md).
        let descriptor = FetchDescriptor<Thing>(predicate: #Predicate { $0.source == source })
        var removedIDs: [UUID] = []
        for thing in (try? context.fetch(descriptor)) ?? [] where thing.isLive {
            guard thing.channelName == name else { continue }
            guard thing.socialContext == nil else { continue }
            if let author = thing.authorHandle?.lowercased(), watched.contains(author) { continue }
            removedIDs.append(thing.id)
            context.delete(thing)
        }
        guard !removedIDs.isEmpty else { return 0 }
        context.saveHonestly()
        SpotlightIndex.remove(ids: removedIDs)
        return removedIDs.count
    }

    /// Every pass, drop what no current follow explains (prd §286 follow-up,
    /// 2026-08-02).
    ///
    /// `pruneTopic`/`pruneAuthor` fire at the MOMENT you tap unfollow, which
    /// leaves two holes: anyone who unfollowed BEFORE those existed still has
    /// the orphans (reported immediately — "the old farcaster channel is
    /// still showing"), and a reinstall can't clear them either, since the
    /// corpus comes back down from CloudKit exactly as it was. A tap-time
    /// prune also can't survive the app being killed mid-write. So the rule
    /// is enforced continuously instead of at the tap: this runs in the
    /// bridge's own refresh and removes anything the CURRENT follow lists no
    /// longer account for.
    ///
    /// Three deliberate abstentions, each of them the "never delete on a
    /// reading you can't trust" lesson from Mail (§284) and Photos (§231):
    ///
    ///   - **Nothing configured at all** — no accounts and no topics — is a
    ///     disconnected or not-yet-loaded store, NOT "you unfollowed
    ///     everything." Skipped entirely; this is the empty-read guard.
    ///   - **Anything wearing a `socialContext`** (liked / recast / reply /
    ///     mention) stays. The schema records THAT a post arrived by someone
    ///     else's activity but not WHOSE, so a like whose watcher is gone is
    ///     indistinguishable from one whose watcher remains — and guessing
    ///     would delete posts that are still earned.
    ///   - **An unattributable row** — neither `authorHandle` nor
    ///     `channelName` — is left alone. Those are pre-2026-07 rows landed
    ///     before the fields existed; there is no evidence to convict them on.
    @MainActor
    @discardableResult
    static func reconcile(source: String, watchedHandles: [String],
                          topics: [String], context: ModelContext) -> Int {
        guard !watchedHandles.isEmpty || !topics.isEmpty else { return 0 }
        let watched = Set(watchedHandles.map { $0.lowercased() })
        let keep = Set(topics.map { $0.lowercased() })

        let descriptor = FetchDescriptor<Thing>(predicate: #Predicate { $0.source == source })
        var removedIDs: [UUID] = []
        for thing in (try? context.fetch(descriptor)) ?? [] where thing.isLive {
            guard thing.socialContext == nil else { continue }
            let author = thing.authorHandle?.lowercased()
            let channel = thing.channelName?.lowercased()
            guard author != nil || channel != nil else { continue }
            if let author, watched.contains(author) { continue }
            if let channel, keep.contains(channel) { continue }
            removedIDs.append(thing.id)
            context.delete(thing)
        }
        guard !removedIDs.isEmpty else { return 0 }
        context.saveHonestly()
        SpotlightIndex.remove(ids: removedIDs)
        return removedIDs.count
    }

    /// Unfollowing a PERSON (or a feed) takes their posts with it — the same
    /// ruling as `pruneTopic`, one field over (user, 2026-08-02: "if you
    /// unfollow something it shouldn't show in your corpus"). Every social
    /// account and every RSS/YouTube/Reddit feed-follow shared ONE
    /// `removeName`, and none of them touched the corpus.
    ///
    /// The exemption is `pruneTopic`'s mirror image: a post of theirs that
    /// arrived through a topic you STILL follow stays, because that follow
    /// still explains it. Pass the topics that remain — for a bridge with no
    /// topic concept (the feed follows) that's simply empty.
    ///
    /// `handle` is matched against `authorHandle`, which is what every one of
    /// these bridges stores: a username on Farcaster, a handle on Bluesky,
    /// the resolved pubkey hex on Nostr, and the FEED'S OWN NAME on a feed
    /// follow (`FeedFollowBridges` sets it so several followed feeds stay
    /// distinguishable) — which is why the caller resolves the display name
    /// rather than passing the URL that was typed.
    @MainActor
    @discardableResult
    static func pruneAuthor(source: String, handle: String,
                            remainingTopics: [String], context: ModelContext) -> Int {
        let who = handle.trimmingCharacters(in: .whitespaces).lowercased()
        guard !who.isEmpty else { return 0 }
        let keep = Set(remainingTopics.map { $0.lowercased() })

        let descriptor = FetchDescriptor<Thing>(predicate: #Predicate { $0.source == source })
        var removedIDs: [UUID] = []
        for thing in (try? context.fetch(descriptor)) ?? [] where thing.isLive {
            guard thing.authorHandle?.lowercased() == who else { continue }
            if let channel = thing.channelName?.lowercased(), keep.contains(channel) { continue }
            removedIDs.append(thing.id)
            context.delete(thing)
        }
        guard !removedIDs.isEmpty else { return 0 }
        context.saveHonestly()
        SpotlightIndex.remove(ids: removedIDs)
        return removedIDs.count
    }
}
