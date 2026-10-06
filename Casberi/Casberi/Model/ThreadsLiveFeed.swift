import Foundation

/// Threads' Activity feed, read the way threads.com's own page reads it (prd
/// §1130, §1131) — the pure half, Foundation-only so
/// `threads-live-selftest.sh` compiles it WHOLE. Everything that touches
/// `Thing` or the Keychain is `ThreadsLive`.
///
/// **What was measured, 2026-10-05, from a signed-in threads.com page:**
///   · There is no REST inbox: `/api/v1/news/inbox/` answers 500. The feed is
///     ONE persisted GraphQL query, `POST /api/graphql` with `doc_id` and
///     `variables`.
///   · No signature. The query answers with the session cookies plus ONE page
///     token, `fb_dtsg`, which a plain GET of `/activity` carries in
///     `DTSGInitialData`. Without it the reply is an HTML page; `lsd` and the
///     web app's `X-IG-App-ID` are not needed.
///   · A `doc_id` Threads no longer knows answers 200 with
///     `errors[0].message` "The GraphQL document with ID … was not found." The
///     id lives in a page script as the module
///     `BarcelonaActivityFeedV2StoryListContainerQuery_threadsRelayOperation`,
///     and that script is one of the nine the raw `/activity` page lists — so
///     a rotated id is found again from one page load.
///   · A signed-out GET of `/activity` redirects to `/login`.
///   · Opening Activity on the web ALSO fires
///     `BarcelonaActivityFeedMarkInboxAsSeenMutation`, which clears the
///     person's unread badge everywhere. This file never builds it.
///
/// **UNMEASURED:** the measured account held only Threads' own notices (a
/// digest, insights, a settings link), so a like, a reply, a mention and a
/// follow have not been seen. Every field is optional, and
/// `-threadsLiveProbe` prints one raw row so the first real one is a
/// one-launch correction.
enum ThreadsLiveFeed {
    /// Distinct from every other Threads ref there will ever be, so a notice
    /// about a post never shares a row with the post.
    static let refPrefix = "threads-live:notif:"
    static let source = "Threads"

    static let activityURL = "https://www.threads.com/activity"
    static let graphqlURL = "https://www.threads.com/api/graphql"
    static let loginURL = "https://www.threads.com/login"

    /// Where the page's scripts are served from.
    static let scriptHost = "static.cdninstagram.com"

    static let queryName = "BarcelonaActivityFeedV2StoryListContainerQuery"
    /// The id measured 2026-10-05. Used until Threads refuses it, then found
    /// again by `queryName` (`docID(inScript:)`).
    static let pinnedDocID = "38749413951373454"
    static let pageSize = 20

    /// A desktop Safari agent for the sign-in sheet AND every request, so the
    /// cookies and the reads always claim the same browser (`TikTokLiveFeed`'s
    /// reason).
    static let desktopUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"

    /// The page's own variables, as measured. `selected_filters: null` is the
    /// "All" tab.
    static var variables: String {
        "{\"first\":\(pageSize),\"selected_filters\":null,"
            + "\"__relay_internal__pv__BarcelonaHasCommunityTopContributorsrelayprovider\":false,"
            + "\"__relay_internal__pv__BarcelonaHasViewerRepliedrelayprovider\":true}"
    }

    // MARK: - The session

    /// The cookie jar a sign-in left, as one header. Nil until both
    /// `sessionid` and `ds_user_id` are in it: a signed-out visit writes `mid`
    /// and `csrftoken` too, and only a completed sign-in writes the pair.
    static func cookieHeader(_ cookies: [(name: String, value: String)]) -> String? {
        var seen = Set<String>()
        var pairs: [String] = []
        for cookie in cookies where !cookie.value.isEmpty && !seen.contains(cookie.name) {
            seen.insert(cookie.name)
            pairs.append("\(cookie.name)=\(cookie.value)")
        }
        guard seen.contains("sessionid"), seen.contains("ds_user_id") else { return nil }
        return pairs.joined(separator: "; ")
    }

    // MARK: - The page

    /// The page token the query needs (measured: 84 characters).
    static func dtsg(inPage html: String) -> String? {
        first(#""DTSGInitialData",\[\],\{"token":"([^"]+)""#, in: html)
    }

    /// The signed-in account's handle, which the page names in its viewer
    /// block — so "signed in as" costs no request of its own.
    static func viewerUsername(inPage html: String) -> String? {
        first(#""viewer":\{[^{}]{0,400}?"username":"([A-Za-z0-9._]+)""#, in: html)
    }

    /// A GET of `/activity` that ended on the login page: the session is gone.
    static func isLoginPage(path: String?) -> Bool {
        (path ?? "").hasPrefix("/login")
    }

    /// The page's own scripts, in page order — where a rotated `doc_id` is
    /// found again.
    static func scriptURLs(inPage html: String) -> [String] {
        let pattern = "https://" + NSRegularExpression.escapedPattern(for: scriptHost)
            + #"/rsrc\.php/[^"\\\s]+?\.js[^"\\\s]*"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        var seen = Set<String>()
        var out: [String] = []
        for match in regex.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let range = Range(match.range, in: html) else { continue }
            let url = String(html[range])
            if seen.insert(url).inserted { out.append(url) }
        }
        return out
    }

    /// `__d("<queryName>_threadsRelayOperation",[],(function(t,n,r,o,a,i){a.exports="<id>"})`
    /// — the shape measured in the page's script.
    static func docID(inScript script: String) -> String? {
        let name = NSRegularExpression.escapedPattern(for: queryName + "_threadsRelayOperation")
        return first(#"__d\(""# + name + #"",\[\],\(function\([^)]*\)\{[A-Za-z_$]+\.exports="(\d{6,})""#,
                     in: script)
    }

    // MARK: - The query

    /// The form the page posts, minus everything it was measured not to need.
    static func formBody(docID: String, dtsg: String) -> String {
        var parts = URLComponents()
        parts.queryItems = [
            URLQueryItem(name: "fb_api_req_friendly_name", value: queryName),
            URLQueryItem(name: "fb_api_caller_class", value: "RelayModern"),
            URLQueryItem(name: "server_timestamps", value: "true"),
            URLQueryItem(name: "variables", value: variables),
            URLQueryItem(name: "doc_id", value: docID),
            URLQueryItem(name: "fb_dtsg", value: dtsg),
        ]
        // `URLComponents` leaves `+`, `:` and `,` bare inside a value, and a
        // form body reads a bare `+` as a space.
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return (parts.queryItems ?? []).map { item in
            let value = item.value?.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
            return "\(item.name)=\(value)"
        }.joined(separator: "&")
    }

    enum Failure: Error, Equatable {
        case noSession
        /// 401/403, or the page sent us to `/login`. The ONLY case that may
        /// clear the stored cookies (§711).
        case refused(Int)
        /// Threads no longer knows the `doc_id`. Never a refusal: the session
        /// is fine and the id is found again from the page.
        case staleQuery
        /// The query answered with a page instead of JSON — the page token was
        /// missing or refused. Fetched again next pass; the session is kept.
        case tokenRejected
        /// 429 — asked too often (§711b).
        case throttled
        /// No HTTP response at all.
        case unreachable
        /// A body this file does not know.
        case drifted
    }

    /// The query's reply, read down to the feed or the reason there is none.
    static func classify(status: Int, body: String?) -> Result<[String: Any], Failure> {
        switch status {
        case 0: return .failure(.unreachable)
        case 401, 403: return .failure(.refused(status))
        case 429: return .failure(.throttled)
        case 200: break
        default: return .failure(.drifted)
        }
        guard let body else { return .failure(.drifted) }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("<") { return .failure(.tokenRejected) }
        let json = trimmed.hasPrefix("for (;;);") ? String(trimmed.dropFirst(9)) : trimmed
        guard let data = json.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return .failure(.drifted) }
        if let errors = root["errors"] as? [[String: Any]],
           errors.contains(where: { (($0["message"] as? String) ?? "").contains("was not found") }) {
            return .failure(.staleQuery)
        }
        guard let feed = (root["data"] as? [String: Any])?["notifications"] as? [String: Any],
              feed["edges"] is [[String: Any]]
        else { return .failure(.drifted) }
        return .success(feed)
    }

    static func describe(_ failure: Failure) -> String {
        switch failure {
        case .noSession: return "not signed in"
        case .refused(let s): return "refused (\(s)) — the session is gone, sign in again"
        case .staleQuery: return "the query id changed — found again from the page"
        case .tokenRejected: return "the page token was refused — fetched again next pass"
        case .throttled: return "throttled — asked too often, try later"
        case .unreachable: return "unreachable — check the connection"
        case .drifted: return "unexpected shape — the web app's response changed"
        }
    }

    // MARK: - Notices

    struct Notice: Equatable {
        var id: String
        /// The row's line: Threads' own sentence ("mia liked your post"), or
        /// the post's words where Threads' title is only a name (measured: a
        /// digest's title is the poster's handle and its body is the post).
        var text: String
        /// What the line did not carry — Threads' reason for a suggestion
        /// ("Because you follow"), the post an insight is about, a reply's
        /// words. nil when there is nothing more.
        var detail: String?
        var at: Date
        var notifName: String?
        var actorHandle: String?
        var actorAvatar: String?
        /// The post the notice is about: its shortcode and its author.
        var postCode: String?
        var postAuthor: String?
        var image: String?
        var isFollow: Bool
        /// A post Threads recommends (its daily digests, measured), not
        /// something somebody did to you.
        var isSuggestion: Bool

        /// The post, when the notice names one and its author; the actor's
        /// page; the Activity page itself — never a guessed post.
        var permalink: String {
            if let code = postCode, let author = postAuthor {
                return "https://www.threads.com/@\(author)/post/\(code)"
            }
            if let handle = actorHandle { return "https://www.threads.com/@\(handle)" }
            return ThreadsLiveFeed.activityURL
        }
    }

    /// Every row of the feed. A bucket header ("New", "Earlier") lands nothing.
    static func notices(_ feed: [String: Any]) -> [Notice] {
        let edges = (feed["edges"] as? [[String: Any]]) ?? []
        return edges.compactMap { ($0["node"] as? [String: Any]).flatMap(notice(from:)) }
    }

    static func notice(from node: [String: Any]) -> Notice? {
        guard (node["__typename"] as? String) == "XTHNotificationFeedRow",
              let id = string(node["edge_id"]) ?? string(node["ndid"]),
              let text = words(node["title"])
        else { return nil }
        let sender = ((node["sender_users"] as? [String: Any])?["edges"] as? [[String: Any]])?
            .first?["node"] as? [String: Any]
        let media = node["ufi_media"] as? [String: Any]
        let handle = sender.flatMap { string($0["username"]) }
        let code = media.flatMap { string($0["code"]) }
        // A notice about nobody and nothing is Threads talking about itself —
        // the measured "unified settings link" was one. It lands nothing.
        guard handle != nil || code != nil else { return nil }
        let stamp = (node["timestamp"] as? Double) ?? (node["timestamp"] as? Int).map(Double.init)
        let image = (node["image_list"] as? [Any])?.lazy.compactMap { item -> String? in
            if let s = item as? String { return s.hasPrefix("https://") ? s : nil }
            if let d = item as? [String: Any] { return string(d["uri"]) ?? string(d["url"]) }
            return nil
        }.first
        let subtitle = words(node["subtitle"])
        let body = words(node["body"])
        // A title that is ONE person, end to end, is a byline and not a
        // sentence: the post's words lead and Threads' reason follows.
        let line: String
        let detail: String?
        if let body, titleIsOnlyAName(node["title"], text: text) {
            line = body
            detail = subtitle
        } else {
            line = text
            detail = body ?? subtitle
        }
        let notifName = string(node["notif_name"])
        return Notice(
            id: id,
            text: line,
            detail: detail.flatMap { $0 == line ? nil : $0 },
            at: stamp.map { Date(timeIntervalSince1970: $0) } ?? .now,
            notifName: notifName,
            actorHandle: handle,
            actorAvatar: sender.flatMap { string($0["profile_picture_uri"]) },
            postCode: code,
            postAuthor: (media?["user"] as? [String: Any]).flatMap { string($0["username"]) },
            image: image,
            // UNMEASURED: a follow has not been seen. The feed carries an
            // inline follow button's actor for one, and the notice's own name
            // is read as the second witness.
            isFollow: node["inline_follow_actor"] is [String: Any]
                || (code == nil && (notifName ?? "").contains("follow")),
            isSuggestion: (notifName ?? "").contains("digest"))
    }

    /// One `XTHUser` range covering the whole title.
    private static func titleIsOnlyAName(_ title: Any?, text: String) -> Bool {
        guard let ranges = (title as? [String: Any])?["ranges"] as? [[String: Any]], ranges.count == 1,
              let range = ranges.first,
              (range["entity"] as? [String: Any])?["__typename"] as? String == "XTHUser",
              (range["offset"] as? Int) == 0, (range["length"] as? Int) == text.utf16.count
        else { return false }
        return true
    }

    /// `{ "text": "…", "ranges": [...] }` — Threads' rich-text object.
    private static func words(_ any: Any?) -> String? {
        guard let text = ((any as? [String: Any])?["text"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    private static func string(_ any: Any?) -> String? {
        if let s = any as? String { return s.isEmpty ? nil : s }
        if let n = any as? NSNumber { return n.stringValue }
        return nil
    }

    private static func first(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
}
