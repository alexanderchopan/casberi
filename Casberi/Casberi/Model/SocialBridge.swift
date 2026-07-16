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
    static let sources: Set<String> = ["Bluesky", "Farcaster"]
    static func isSocial(_ source: String) -> Bool { sources.contains(source) }

    /// How many replies a thread fetch returns — the sheet shows this many at
    /// most, so a thread AT this count may have more (the header says "N+").
    static let replyCap = 8

    /// A handle without Bluesky's ".bsky.social" tail — the name the person
    /// knows. Farcaster handles have no tail, so they pass through unchanged.
    static func shortHandle(_ handle: String) -> String {
        handle.hasSuffix(".bsky.social")
            ? String(handle.dropLast(".bsky.social".count)) : handle
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
        guard isSocial(thing.source) else { return nil }
        if let channel = thing.channelName, !channel.isEmpty {
            // Farcaster channels ARE "/design" to the person; a Bluesky feed
            // is a proper name ("Science"), so it wears no slash.
            return thing.source == "Farcaster" ? "/\(channel)" : channel
        }
        switch thing.socialContext {
        case "liked":   return String(localized: "Liked")
        case "mention": return String(localized: "Mentions you")
        default:        return nil
        }
    }

    /// The same fact as a CLAUSE, for the sheet's eyebrow — where it sits in a
    /// sentence ("@dwr · in /design · 2h ago") rather than alone in a label
    /// slot. Same source of truth, different grammar: a row has room for a
    /// word, a sentence wants a phrase.
    static func contextPhrase(for thing: Thing) -> String? {
        guard isSocial(thing.source) else { return nil }
        if let channel = thing.channelName, !channel.isEmpty {
            return thing.source == "Farcaster"
                ? String(localized: "in /\(channel)") : String(localized: "in \(channel)")
        }
        switch thing.socialContext {
        case "liked":   return String(localized: "you liked this")
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
    /// A two-source set today; a third bridge would make this a list.
    static func otherSource(_ source: String) -> String? {
        SocialThread.sources.subtracting([source]).first
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
        default: return false
        }
    }

    /// Refresh whichever bridge just gained an account, so a Watch from the
    /// card lands their posts immediately instead of at the next foreground.
    @MainActor
    static func sync(source: String, context: ModelContext) async {
        switch source {
        case "Farcaster": _ = await FarcasterIngest.refresh(context: context)
        case "Bluesky":   _ = await BlueskyIngest.refresh(context: context)
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

/// One "watch more" toggle on an account row (Likes / Mentions) — the
/// capability a bridge offers per account. Bluesky offers Mentions only
/// (likes need sign-in); Farcaster offers both.
struct SocialWatch: Identifiable, Equatable {
    enum Kind: String { case likes = "Likes", mentions = "Mentions" }
    let kind: Kind
    let on: Bool
    var id: String { kind.rawValue }
    var label: String { kind.rawValue }
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
