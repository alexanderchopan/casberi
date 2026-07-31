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
    static let contextSources: Set<String> = sources.union(["Slack"])
    static func hasContext(_ source: String) -> Bool { contextSources.contains(source) }

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
        case "recast":  return recastWord(thing.source)
        case "mention": return String(localized: "Mentions you")
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
    enum Kind: String { case likes = "Likes", recasts = "Recasts", mentions = "Mentions" }
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
