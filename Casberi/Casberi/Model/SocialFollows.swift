import Foundation

/// Who an account follows, read from its own network (2026-07-16, prd 87).
/// Both networks publish the follow graph keylessly, so "bring in who they
/// follow" needs no sign-in — it's the same public surface `UserSearch`
/// already rides, asked a different question.
///
/// This is deliberately a READ, not a mirror. Nothing here watches anybody:
/// it hands the graph to a picker and the taps that watch are the person's
/// own. That's the same ruling `SocialBridge.findElsewhere` and the trending
/// bridge earned — discovery shows, the tap watches — and here it's load
/// bearing rather than decorative, because the graph is big: a measured
/// account followed 1,848 people (2026-07-16). Mirroring that automatically
/// would turn a corpus into a timeline and pay 1,848 sync jobs per refresh.
enum SocialFollows {

    /// One person's follow graph as the network served it.
    struct Graph {
        /// In the order the network returned — no rank we didn't compute.
        /// Bluesky serves most-recently-followed first; Farcaster serves its
        /// own. Ranking by follower count was considered and dropped: it's
        /// free on Farcaster and ~1 extra request per 25 people on Bluesky,
        /// and it surfaces the biggest accounts — the loudest feeds, covered
        /// everywhere else, which is the opposite of a personal corpus.
        let people: [UserSearch.Hit]
        /// The walk stopped before the graph ended — the page ceiling hit, or
        /// a page failed (Farcaster rate-limits; see `farcaster`). Either way
        /// this list is a PREFIX, and the sheet says so: a capped list that
        /// presents as complete is the silent-truncation lie the honesty rule
        /// forbids. The two causes share a line deliberately — they mean the
        /// same thing to a person reading it ("we didn't get everyone").
        let truncated: Bool
        /// At least one page came back. FALSE means we never read the graph at
        /// all — and that is a different fact from "they follow nobody", which
        /// is an empty `people` with `reachable` true.
        ///
        /// Keeping them apart is not hypothetical: the first page of a fresh
        /// graph 429s while Farcaster's 20-per-10s window is still draining, so
        /// importing from one account and immediately opening another's picker
        /// hit exactly this. Collapsed into one state, the sheet told the truth
        /// about nothing and said the account follows nobody. Same rule the
        /// wallet earned in prd §85 — a read that failed and a read that found
        /// nothing may never share a line.
        let reachable: Bool

        /// Read nothing at all: offline, rate-limited, or a name that wouldn't
        /// resolve. NOT "follows nobody".
        static let unreachable = Graph(people: [], truncated: false, reachable: false)
    }

    /// A runaway guard, not a product cap — it bounds a walk whose length is
    /// the network's to decide. At the per-page sizes below that's 2,000
    /// people on Farcaster and 4,000 on Bluesky, past any measured real graph
    /// (the largest measured was 2,842). Hitting it sets `truncated`.
    private static let pageCeiling = 40

    /// Farcaster only — the gap between pages that keeps the client API under
    /// its stated ceiling of **20 requests per 10 seconds** (the 429 body says
    /// so in those words). Measured 2026-07-16 against a 37-page graph on one
    /// reused connection: 150ms dies at page 21, 400ms and 550ms both complete.
    /// 500ms sits between the two that worked, ~14 requests per 10s.
    private static let pageDelay = Duration.milliseconds(500)

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
        case "Farcaster": return await farcaster(handle, onProgress: onProgress)
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
    /// ceiling of the kind Farcaster's client API enforces. So the two arms
    /// differ on purpose: don't copy this loop's shape onto `farcaster`, and
    /// don't pace this one to match it.
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
                                  avatarURL: IngestSupport.imageURL(actor["avatar"] as? String),
                                  fid: nil))
            }
            cursor = root["cursor"] as? String
            pages += 1
            await onProgress(people.count)
        } while cursor != nil && pages < pageCeiling && !Task.isCancelled

        return Graph(people: people, truncated: cursor != nil, reachable: pages > 0)
    }

    // MARK: - Farcaster

    /// `client.farcaster.xyz/v2/following` — the Farcaster team's own client
    /// API, the host `UserSearch.farcaster` already rides, and the right one
    /// here for a measured reason: the keyless Snapchain node answers this
    /// too (`linksByFid`), but only as target FIDs, so a 1,848-follow graph
    /// would cost 1,848 name lookups. This serves hydrated profiles 50 at a
    /// time — the same graph in 37 requests. (Both agreed on dwr's count to
    /// within the self-follow the node includes, so neither is pruning.)
    ///
    /// `limit` is schema-capped at 50; asking for more is a 400, not a clamp.
    ///
    /// PACED, and it must stay paced — `pageDelay` is load bearing (measured
    /// 2026-07-16). The client API allows 20 requests per 10 seconds; past
    /// that it 429s, and since `IngestSupport.run` reports a non-200 as nil,
    /// the walk just stops and hands back a PREFIX. Unpaced, a 1,848-follow
    /// account came back as exactly 999 people — a wrong list, not an error.
    ///
    /// The trap worth knowing before you "fix" this: the ceiling is enforced
    /// **per connection**, so it does not reproduce with curl or any client
    /// that opens a fresh connection per request — those walked all 37 pages
    /// clean at 150ms and said the endpoint was fine. URLSession reuses one
    /// keep-alive connection, so the app hit the limit and nothing else did.
    /// Reproduce this against a single keep-alive connection or you'll
    /// conclude, four times over, that the delay is unnecessary.
    private static func farcaster(_ rawName: String,
                                  onProgress: @MainActor (Int) -> Void) async -> Graph {
        let name = FarcasterStore.normalize(rawName)
        guard !name.isEmpty, let fid = await FarcasterIngest.fid(forName: name),
              fid > 0 else { return .unreachable }   // no fid = no graph read, not an empty one
        var people: [UserSearch.Hit] = []
        var seen = Set<String>()
        var cursor: String?
        var pages = 0

        repeat {
            var comps = URLComponents(string: "https://client.farcaster.xyz/v2/following")!
            comps.queryItems = [URLQueryItem(name: "fid", value: "\(fid)"),
                                URLQueryItem(name: "limit", value: "50")]
            if let cursor { comps.queryItems?.append(URLQueryItem(name: "cursor", value: cursor)) }
            guard let url = comps.url,
                  let root = await IngestSupport.getJSON(url) as? [String: Any],
                  let users = (root["result"] as? [String: Any])?["users"] as? [[String: Any]]
            else { break }

            for user in users {
                // Deduped — see the Bluesky arm; this walk is ~31s wide, so a
                // follow landing mid-walk can shift the cursor window and
                // re-emit someone.
                guard let username = user["username"] as? String, !username.isEmpty,
                      seen.insert(username.lowercased()).inserted else { continue }
                let pfp = (user["pfp"] as? [String: Any])?["url"] as? String
                people.append(Hit(handle: username,
                                  displayName: UserSearch.name(user["displayName"],
                                                               fallback: username),
                                  avatarURL: IngestSupport.imageURL(pfp),
                                  fid: user["fid"] as? Int))
            }
            cursor = (root["next"] as? [String: Any])?["cursor"] as? String
            pages += 1
            await onProgress(people.count)
            // `try?` would swallow the cancellation and fall into one more
            // request against a rate-limited endpoint — check it, don't eat it.
            if cursor != nil {
                do { try await Task.sleep(for: pageDelay) } catch { break }
            }
        } while cursor != nil && pages < pageCeiling && !Task.isCancelled

        return Graph(people: people, truncated: cursor != nil, reachable: pages > 0)
    }

    private typealias Hit = UserSearch.Hit
}
