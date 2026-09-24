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

    /// How far back a post of yours is PREFERRED for the inbound reads. A
    /// month-old post gains a like a week; re-asking about it before a fresh
    /// one is spend with no news in it, and the recent window is where every
    /// answer that matters lives.
    ///
    /// Preferred, not required — see `ownRecentPosts`. As a hard cutoff this
    /// silently switched the whole inbound half off for anyone who posts less
    /// than weekly.
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
    /// Read out of the corpus, not the network: your posts are already landing
    /// (that's what watching your own account does), so asking the network for
    /// them again would be a second copy of a read the pass just made. The
    /// consequence to know is that the VERY FIRST sync of a brand-new account
    /// finds nothing here — `landed` is snapshotted before your casts land —
    /// so the inbound reads begin on the second pass. `-inboundProbe` reports
    /// this count for exactly that reason.
    ///
    /// **The window is a PREFERENCE, not a gate (2026-08-07, prd §331).** It
    /// used to be a hard filter, and that made marking an account `mine` a
    /// silent no-op for anyone who doesn't post weekly: every cast older than
    /// seven days was excluded, so a monthly poster's inbound half read
    /// NOTHING, forever, with no error and nothing on any screen to say why.
    /// Reported as exactly that — "i marked a farcaster profile as mine and
    /// expected to see likes given to me, i even tapped that".
    ///
    /// So when the window holds nothing, this falls back to your newest posts
    /// regardless of age. The cost is unchanged — `ownPostPage` bounds the
    /// result either way — which is what makes this a floor rather than a
    /// widening: a person with fresh posts still gets exactly the old
    /// behaviour, and a person without one stops being told nothing.
    ///
    /// **This reads the corpus, so it can only ever see what the account's own
    /// page LANDED — and from §239 (2026-07-31) until §804 (2026-09-17) both
    /// pages excluded your replies**
    /// (Farcaster's `topLevelOnly`, Bluesky's `filter=posts_no_replies`).
    /// Every read below is therefore an invariant of the landing rule, not of
    /// this function: with replies excluded, `landReplies` was asking
    /// "did anyone answer?" about top-level casts alone, and on both networks
    /// most conversation happens under a reply. Both pages now land your
    /// replies when the account is marked `mine`, and that is what makes this
    /// list the thing its name says it is. If either filter is ever widened
    /// back, this goes blind again with nothing to report it.
    ///
    /// `.isLive` at the boundary (corollary 4 of the SwiftData liveness rule):
    /// this hands an array of models onward to readers that will read stored
    /// properties off them, so the guarantee is made HERE, where it's local
    /// and provable, not promised to callers.
    @MainActor
    static func ownRecentPosts(_ landed: [String: Thing], handle: String,
                               refPrefix: String) -> [Thing] {
        let mine = landed.values
            .filter { thing in
                thing.isLive
                    && thing.authorHandle == handle
                    && (thing.sourceRef?.hasPrefix(refPrefix) ?? false)
                    // A post you LANDED because someone else amplified or
                    // mentioned it isn't yours to be replied to — the author
                    // check above passes for your own cast either way, but a
                    // marker means it arrived by another road and its thread
                    // was already read there.
                    && thing.socialContext == nil
            }
            .sorted { $0.capturedAt > $1.capturedAt }
        let cutoff = Date.now.addingTimeInterval(-ownPostWindow)
        let fresh = mine.filter { $0.capturedAt > cutoff }
        return share(fresh.isEmpty ? mine : fresh)
    }

    /// Splits `ownPostPage` between your top-level posts and your replies, so
    /// neither kind can starve the other.
    ///
    /// **This exists because the fix for §804 could otherwise have swapped one
    /// blindness for the other.** Before it, replies were excluded and only
    /// your top-level posts were asked about; afterwards the page holds both
    /// and the list is simply the newest six — so an account that mostly
    /// replies (which on these networks is most active accounts) would fill
    /// all six slots with replies and stop asking about its own posts
    /// entirely. Nothing would look wrong: the pass still runs, still costs
    /// the same, still lands replies. It would just have quietly moved which
    /// half of your notifications you never see.
    ///
    /// So each side is guaranteed a floor and the leftovers go to whichever
    /// side has more. The cost is unchanged — `ownPostPage` bounds the result
    /// either way — and a person with only posts, or only replies, gets the
    /// whole page exactly as before.
    ///
    /// A reply is one wearing a `parent` card. A reply whose parent could not
    /// be fetched (deleted, or a node that wouldn't answer) reads as top-level
    /// here, which costs nothing wrong: it is still your post and still worth
    /// asking about. `pool` is already `.isLive`-filtered by the one caller.
    ///
    /// The result is NOT re-sorted. Both reads iterate it and fetch per entry;
    /// which one goes first changes nothing.
    @MainActor
    static func share(_ pool: [Thing]) -> [Thing] {
        let rootFloor = max(1, ownPostPage / 2)
        let replyFloor = ownPostPage - rootFloor
        var roots = 0, replies = 0
        var taken: [Thing] = []
        for thing in pool where taken.count < ownPostPage {
            if thing.parent == nil {
                if roots < rootFloor { taken.append(thing); roots += 1 }
            } else if replies < replyFloor {
                taken.append(thing)
                replies += 1
            }
        }
        // Whatever the other side didn't use. An account with no replies takes
        // the whole page in posts here, which is the pre-§804 behaviour intact.
        if taken.count < ownPostPage {
            // Spelled as a closure, not `.map(ObjectIdentifier.init)`:
            // that initialiser is overloaded (`AnyObject` and `Any.Type`)
            // and an unapplied reference asks the type checker to pick.
            // Written in a session with no Swift toolchain, so the form
            // that cannot be ambiguous is the one that ships.
            var held = Set(taken.map { ObjectIdentifier($0) })
            for thing in pool where taken.count < ownPostPage {
                if held.insert(ObjectIdentifier(thing)).inserted { taken.append(thing) }
            }
        }
        return taken
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
                             bio: String? = nil,
                             avatarURL: String?, profileURL: String,
                             when: Date?, source: String,
                             existing: inout Set<String>,
                             context: ModelContext) -> Thing? {
        let ref = "\(source.lowercased()):follower:\(id)"
        guard !existing.contains(ref) else { return nil }
        let name = displayName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        // Who they say they are (prd §910): the profile's own bio, which both
        // networks hand over with the follower list. DISPLAY copy — they wrote
        // it — and the one thing a "started following you" row can say about a
        // stranger besides their name.
        let about = bio?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
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
        thing.summary = about
        context.insert(thing)
        SpotlightIndex.index([thing])
        existing.insert(ref)
        return thing
    }
}
