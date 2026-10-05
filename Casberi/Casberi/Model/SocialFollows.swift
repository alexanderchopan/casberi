import Foundation

/// Who an account follows, read from its own network (2026-07-16, prd 87).
/// Bluesky and Nostr publish the follow graph keylessly, so "bring in who they
/// follow" needs no sign-in — it's the same public surface `UserSearch`
/// already rides, asked a different question.
///
/// This is deliberately a READ, not a mirror. Nothing here watches anybody:
/// it hands the graph to a picker and the taps that watch are the person's
/// own. That's the same ruling the trending bridge earned — discovery shows, the tap watches — and here it's load
/// bearing rather than decorative, because the graph is big: a measured
/// account followed 1,848 people (2026-07-16). Mirroring that automatically
/// would turn a corpus into a timeline and pay 1,848 sync jobs per refresh.
enum SocialFollows {

    /// One person's follow graph as the network served it.
    struct Graph {
        /// In the order the network returned — no rank we didn't compute.
        /// Bluesky serves most-recently-followed first. Ranking by follower
        /// count was considered and dropped: it's ~1 extra request per 25
        /// people on Bluesky, and it surfaces the biggest accounts — the loudest feeds, covered
        /// everywhere else, which is the opposite of a personal corpus.
        let people: [UserSearch.Hit]
        /// The walk stopped before the graph ended — the page ceiling hit, or
        /// a page failed. Either way
        /// this list is a PREFIX, and the sheet says so: a capped list that
        /// presents as complete is the silent-truncation lie the honesty rule
        /// forbids. The two causes share a line deliberately — they mean the
        /// same thing to a person reading it ("we didn't get everyone").
        let truncated: Bool
        /// At least one page came back. FALSE means we never read the graph at
        /// all — and that is a different fact from "they follow nobody", which
        /// is an empty `people` with `reachable` true.
        ///
        /// Keeping them apart is not hypothetical: a rate-limited first page
        /// hit exactly this (2026-07-16). Collapsed into one state, the sheet told the truth
        /// about nothing and said the account follows nobody. Same rule the
        /// wallet earned in prd §85 — a read that failed and a read that found
        /// nothing may never share a line.
        let reachable: Bool

        /// Read nothing at all: offline, rate-limited, or a name that wouldn't
        /// resolve. NOT "follows nobody".
        static let unreachable = Graph(people: [], truncated: false, reachable: false)
    }

    /// A runaway guard, not a product cap — it bounds a walk whose length is
    /// the network's to decide. At the per-page size below that's 4,000
    /// people on Bluesky, past any measured real graph
    /// (the largest measured was 2,842). Hitting it sets `truncated`.
    private static let pageCeiling = 40

    /// Who this handle follows on that network. An unreachable or empty graph
    /// returns no people rather than an error — the sheet says "nobody", and
    /// typing a name still watches, unchanged.
    ///
    /// `onProgress` reports the running count as each page lands. A big graph
    /// takes real time to walk (a measured 1,848-follow account: 37 requests,
    /// ~31s), and a spinner that sits there for half a minute says nothing —
    /// this lets the sheet count out loud instead.
    static func graph(source: String, handle: String,
                      onProgress: @MainActor (Int) -> Void = { _ in }) async -> Graph {
        switch source {
        case "Bluesky":   return await bluesky(handle, onProgress: onProgress)
        case "Nostr":     return await nostr(handle, onProgress: onProgress)
        default:          return .unreachable
        }
    }

    // MARK: - Bluesky

    /// `app.bsky.graph.getFollows` on the AppView — the same keyless host the
    /// ingest rides, and it hands back HYDRATED profiles (handle, name, face)
    /// so a page renders with no second lookup. Caps at 100 per page.
    ///
    /// Unpaced on purpose: measured 2026-07-16, 40 back-to-back pages (3,757
    /// people, ~11s) drew no rate limit — the AppView has no per-connection
    /// ceiling, so don't pace this loop.
    private static func bluesky(_ rawHandle: String,
                                onProgress: @MainActor (Int) -> Void) async -> Graph {
        let handle = BlueskyStore.normalize(rawHandle)
        guard !handle.isEmpty else { return .unreachable }
        var people: [UserSearch.Hit] = []
        var seen = Set<String>()
        var cursor: String?
        var pages = 0

        repeat {
            var comps = URLComponents(
                string: "https://public.api.bsky.app/xrpc/app.bsky.graph.getFollows")!
            comps.queryItems = [URLQueryItem(name: "actor", value: handle),
                                URLQueryItem(name: "limit", value: "100")]
            if let cursor { comps.queryItems?.append(URLQueryItem(name: "cursor", value: cursor)) }
            guard let url = comps.url,
                  let root = await IngestSupport.getJSON(url) as? [String: Any],
                  let follows = root["follows"] as? [[String: Any]] else { break }

            for actor in follows {
                // Deduped by handle: cursor pagination over a graph that
                // changes mid-walk (this one is ~38 pages wide) can re-emit an
                // account, and `Hit.id` IS the handle — a duplicate makes the
                // picker's ForEach render undefined rows.
                guard let h = actor["handle"] as? String, !h.isEmpty,
                      seen.insert(h.lowercased()).inserted else { continue }
                people.append(Hit(handle: h,
                                  displayName: UserSearch.name(actor["displayName"], fallback: h),
                                  avatarURL: IngestSupport.imageURL(actor["avatar"] as? String)))
            }
            cursor = root["cursor"] as? String
            pages += 1
            await onProgress(people.count)
        } while cursor != nil && pages < pageCeiling && !Task.isCancelled

        return Graph(people: people, truncated: cursor != nil, reachable: pages > 0)
    }

    // MARK: - Nostr

    /// `NostrIngest.contactList` — a kind:3 event, the WHOLE follow graph in
    /// one relay round trip, unlike Bluesky's paginated walk:
    /// Nostr's contact list is a single replaceable event carrying every "p"
    /// tag inline, so there's no cursor to page through and `truncated` stays
    /// false for the follow list itself. Hydrating each pubkey's face/name
    /// (kind:0) is the one part that scales with graph size — batched via
    /// Nostr's array-of-authors filter, a guessed 100-per-request chunk
    /// (no measured relay cap on filter-array size; re-measure before
    /// hardening a bigger batch). `pageCeiling`-style truncation applies only
    /// to that hydration walk, never to the follow list read itself.
    private static func nostr(_ rawInput: String,
                             onProgress: @MainActor (Int) -> Void) async -> Graph {
        let input = NostrStore.normalize(rawInput)
        guard !input.isEmpty, let hex = await NostrIngest.pubkeyHex(for: input) else { return .unreachable }
        let (pubkeys, reached) = await NostrIngest.contactList(pubkeyHex: hex)
        guard reached else { return .unreachable }
        guard !pubkeys.isEmpty else { return Graph(people: [], truncated: false, reachable: true) }

        let capped = Array(pubkeys.prefix(pageCeiling * 50))   // the same runaway guard, in people not pages
        var hydrated: [String: NostrIngest.Profile] = [:]
        var pages = 0
        for start in stride(from: 0, to: capped.count, by: 100) {
            let chunk = Array(capped[start..<min(start + 100, capped.count)])
            let result = await NostrRelay.requestAll(filter: ["authors": chunk, "kinds": [0]])
            for event in result.events {
                guard let pk = event["pubkey"] as? String, let parsed = NostrIngest.parseProfile(event)
                else { continue }
                hydrated[pk] = parsed
            }
            pages += 1
            await onProgress(hydrated.count)
        }

        let people = capped.map { pk -> Hit in
            let profile = hydrated[pk]
            return Hit(handle: pk,
                      displayName: profile?.displayName ?? SocialThread.shortHandle(pk),
                      avatarURL: profile?.avatarURL)
        }
        return Graph(people: people, truncated: capped.count < pubkeys.count, reachable: true)
    }

    private typealias Hit = UserSearch.Hit
}
