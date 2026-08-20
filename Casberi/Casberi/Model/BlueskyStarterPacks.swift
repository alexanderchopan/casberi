import Foundation

/// Bluesky starter packs (item 4 of the 2026-07-27 social enrichment pass) —
/// someone else's curated follow list, addressed by at-uri the way a
/// followed feed is (prd 75's analog for people instead of topics). The
/// honest fix to `SocialFollows`' own measured problem: nobody wants to
/// picker through a graph that runs to 1,848 people one checkbox at a time.
/// A pack is 10-50 people, already sorted by someone's taste — one tap
/// follows the whole set.
///
/// Fully keyless — `app.bsky.graph.searchStarterPacks` / `getList` on the
/// same public AppView host `SocialFollows`/`UserSearch` already ride.
/// MEASURED live 2026-07-27 (curl, no auth, no key): both endpoints answered
/// clean. Re-measure from the app itself (`-starterPackProbe`) before
/// leaning on this in a release build — the standing discipline every
/// keyless bridge in this codebase follows (see `WalletApprovals`,
/// `PrivacyPoolsBridge`, `GnosisPayBridge` for the pattern).
enum BlueskyStarterPacks {
    struct Pack: Identifiable, Equatable {
        let uri: String
        var id: String { uri }
        let name: String
        let description: String?
        let creatorHandle: String
        let creatorAvatarURL: String?
        /// The underlying list's at-uri — what `members(of:)` reads. A pack
        /// record IS a name + description wrapped around one list.
        let listURI: String
    }

    struct Member: Identifiable, Equatable {
        let handle: String
        var id: String { handle }
        let displayName: String?
        let avatarURL: String?
    }

    /// Packs matching a free-text query — the same discovery gesture
    /// following a Bluesky feed by search already uses (prd 75), asked of
    /// packs instead of feed generators.
    static func search(_ query: String) async -> [Pack] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        var comps = URLComponents(
            string: "https://public.api.bsky.app/xrpc/app.bsky.graph.searchStarterPacks")!
        comps.queryItems = [URLQueryItem(name: "q", value: q),
                            URLQueryItem(name: "limit", value: "20")]
        guard let url = comps.url,
              let root = await IngestSupport.getJSON(url) as? [String: Any],
              let packs = root["starterPacks"] as? [[String: Any]] else { return [] }
        return packs.compactMap { pack -> Pack? in
            guard let uri = pack["uri"] as? String,
                  let record = pack["record"] as? [String: Any],
                  let name = record["name"] as? String, !name.isEmpty,
                  let listURI = record["list"] as? String, !listURI.isEmpty else { return nil }
            let creator = pack["creator"] as? [String: Any]
            let description = record["description"] as? String
            return Pack(uri: uri, name: name,
                       description: (description?.isEmpty == false) ? description : nil,
                       creatorHandle: (creator?["handle"] as? String) ?? "",
                       creatorAvatarURL: IngestSupport.imageURL(creator?["avatar"] as? String),
                       listURI: listURI)
        }
    }

    /// A pack's members — `getList` on its underlying list, hydrated (face,
    /// name, handle) the same shape `SocialFollows.bluesky` reads a follow
    /// graph in. One page (100 — past any measured pack; packs run 10-50
    /// people by the convention Bluesky's own client encourages).
    static func members(of pack: Pack) async -> [Member] {
        var comps = URLComponents(string: "https://public.api.bsky.app/xrpc/app.bsky.graph.getList")!
        comps.queryItems = [URLQueryItem(name: "list", value: pack.listURI),
                            URLQueryItem(name: "limit", value: "100")]
        guard let url = comps.url,
              let root = await IngestSupport.getJSON(url) as? [String: Any],
              let items = root["items"] as? [[String: Any]] else { return [] }
        return items.compactMap { item -> Member? in
            guard let subject = item["subject"] as? [String: Any],
                  let handle = subject["handle"] as? String, !handle.isEmpty else { return nil }
            return Member(handle: handle,
                          displayName: subject["displayName"] as? String,
                          avatarURL: IngestSupport.imageURL(subject["avatar"] as? String))
        }
    }

    /// Follows every member at once — `BlueskyStore.add(contentsOf:)`, the
    /// same batched-persist-once path the full follow-graph import uses, so
    /// a 30-person pack doesn't re-encode the growing accounts array 30
    /// times. Returns how many were new.
    ///
    /// The count is the ANSWER, not an announcement: the button that calls
    /// this relabels itself with it ("Followed 43"), which is where somebody
    /// who just tapped is already looking.
    @discardableResult
    @MainActor
    static func followAll(_ members: [Member]) -> Int {
        BlueskyStore.shared.add(contentsOf: members.map(\.handle))
    }
}
