import Foundation
import SwiftData

/// The INBOUND half of a social account (2026-07-31).
///
/// Every social read this app had was OUTBOUND: what a watched account posts,
/// what they liked, what they recast, who they follow. The one exception was
/// `@`-mentions. So the whole half of a network that answers "what happened to
/// ME" — who replied, who liked it, who started following — was structurally
/// invisible, and prd §221 named the reason precisely: the stores model
/// accounts you WATCH and have no concept of which account is YOURS.
///
/// This is that concept. One flag per account (`mine`), and three reads it
/// turns on, mirrored across Farcaster and Bluesky:
///
/// - **likes received** — who liked your post. A like from someone you watch
///   RESURFACES the post (§221's ruling, arriving from the other direction:
///   §221 catches it when the liker is watched and their likes are read;
///   this catches it when the liker is anyone at all).
/// - **replies received** — a reply usually carries no `@`, so `castsByMention`
///   / `searchPosts mentions:` structurally cannot see one. This is the gap
///   that made "someone answered you" unanswerable.
/// - **new followers** — diffed against a ledger, first sight seeded silently.
///
/// **Module doctrine holds throughout**: a count is never a thing. Likes
/// received update the post's own `likeCount` and can resurface it; they never
/// land "12 people liked your post" as a record. A named person IS an event, so
/// a new follower lands — a reply lands as the reply itself.
enum SocialInbound {

    /// How many of your own recent posts the inbound pass reads likes and
    /// replies for, per account, per refresh.
    ///
    /// This is the whole cost control. Both networks need ONE REQUEST PER POST
    /// for each of the two reads (Snapchain's `reactionsByCast`/`castsByParent`
    /// take one cast; Bluesky's `getLikes`/`getPostThread` take one uri), so
    /// the pass is `2 × ownPostPage` requests per account marked yours —
    /// usually exactly one account. Six keeps that at a dozen keyless requests
    /// on a foreground refresh, beside the ~4 the bridge already makes.
    static let ownPostPage = 6

    /// How far back a post of yours stays eligible for the inbound reads. A
    /// month-old post gains a like a week; re-asking about it forever is spend
    /// with no news in it, and the recent window is where every answer that
    /// matters lives.
    static let ownPostWindow: TimeInterval = 7 * 86_400

    /// Most new followers landed in one pass. First sight seeds silently
    /// (below), so this only ever bounds a genuine burst — and a burst is
    /// exactly when an unbounded landing would bury the rest of the feed.
    static let followerLandCap = 5

    /// How recent an inbound event has to be to FIRE a moment. The
    /// alerts-are-news doctrine every bridge follows (Privacy Pools §228, the
    /// mention moment, §221's resurface): marking an account as yours must not
    /// rain months of history as toasts.
    static let newsWindow: TimeInterval = 86_400

    /// Your own recent posts from a source, newest first, bounded by
    /// `ownPostPage` and `ownPostWindow` — what the likes-received and
    /// replies-received reads ask about.
    ///
    /// `.isLive` at the boundary (corollary 4 of the SwiftData liveness rule):
    /// this hands an array of models onward to readers that will read stored
    /// properties off them, so the guarantee is made HERE, where it's local
    /// and provable, not promised to callers.
    @MainActor
    static func ownRecentPosts(_ landed: [String: Thing], handle: String,
                               refPrefix: String) -> [Thing] {
        let cutoff = Date.now.addingTimeInterval(-ownPostWindow)
        return landed.values
            .filter { thing in
                thing.isLive
                    && thing.authorHandle == handle
                    && thing.capturedAt > cutoff
                    && (thing.sourceRef?.hasPrefix(refPrefix) ?? false)
                    // A post you LANDED because someone else amplified or
                    // mentioned it isn't yours to be replied to — the author
                    // check above passes for your own cast either way, but a
                    // marker means it arrived by another road and its thread
                    // was already read there.
                    && thing.socialContext == nil
            }
            .sorted { $0.capturedAt > $1.capturedAt }
            .prefix(ownPostPage)
            .map { $0 }
    }

    /// The followers already seen for one account — an ordered, capped ledger
    /// of network ids (Farcaster fids as strings, Bluesky DIDs).
    ///
    /// A SET, not a cursor, on purpose: Bluesky's `getFollowers` returns
    /// profiles in newest-first order with NO follow timestamp anywhere in the
    /// payload, so there is nothing for a cursor to compare against. Farcaster
    /// does carry a timestamp and could use one — but running the two arms on
    /// different mechanisms doubles the surface for the same job, and the
    /// timestamp is still used where it genuinely helps (stamping the landed
    /// thing with when the follow actually happened).
    ///
    /// Capped at `ledgerCap` newest-first. The cap is what keeps a popular
    /// account's ledger from growing without bound in UserDefaults; the cost of
    /// the cap is that someone who unfollows, falls off the end, and refollows
    /// much later can be announced twice. That is the right trade: the
    /// alternative is an unbounded list, and a second "they followed you"
    /// years later is true anyway.
    struct FollowerLedger {
        static let ledgerCap = 500

        let key: String
        private(set) var seen: [String]

        /// True when nothing has ever been recorded for this account — the
        /// first-sight case, which SEEDS SILENTLY rather than landing. Watching
        /// yourself for the first time must not land your entire follower list
        /// as today's news (the Peer/Morpho/Hyperliquid cursor-seed rule, and
        /// the bug that pass caught live: 22 open positions landing as 22
        /// "Opened" things).
        var isFirstSight: Bool { seen.isEmpty }

        init(key: String) {
            self.key = key
            seen = UserDefaults.standard.stringArray(forKey: key) ?? []
        }

        /// The ids in `current` (newest first) not already recorded.
        func newcomers(in current: [String]) -> [String] {
            let known = Set(seen)
            return current.filter { !known.contains($0) }
        }

        /// Records this pass's read. Newest first, deduped, capped.
        mutating func record(_ current: [String]) {
            var merged = current
            var known = Set(current)
            for id in seen where known.insert(id).inserted { merged.append(id) }
            seen = Array(merged.prefix(Self.ledgerCap))
            UserDefaults.standard.set(seen, forKey: key)
        }

        /// Forgets everything — disconnecting an account must not leave its
        /// follower ledger behind to seed a stale "new follower" on reconnect.
        static func forget(key: String) {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    /// The thing a new follower lands as: a `.link` to their profile, titled
    /// with what happened. Deliberately NOT a new `ThingKind` and NOT a chat
    /// thing — it has no post text and no permalink to any post, and `.link`
    /// already renders exactly this (a title, a face, an Open verb pointing at
    /// their profile), the same shape `ENSExpiry` uses for a reconciling row.
    ///
    /// Returns nil when the thing already exists, so a follower who drops off
    /// the ledger's tail and returns still can't land twice inside the same
    /// corpus.
    @MainActor
    static func landFollower(id: String, handle: String, displayName: String?,
                             avatarURL: String?, profileURL: String,
                             when: Date?, source: String,
                             existing: inout Set<String>,
                             context: ModelContext) -> Thing? {
        let ref = "\(source.lowercased()):follower:\(id)"
        guard !existing.contains(ref) else { return nil }
        let name = displayName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let thing = Thing(
            kind: .link,
            title: name.map { String(localized: "\($0) (@\(handle)) started following you") }
                ?? String(localized: "@\(handle) started following you"),
            content: profileURL,
            source: source,
            capturedAt: when ?? .now,
            sourceRef: ref
        )
        thing.authorHandle = handle
        thing.authorAvatarURL = avatarURL
        thing.socialContext = "follow"
        context.insert(thing)
        SpotlightIndex.index([thing])
        existing.insert(ref)
        return thing
    }
}
