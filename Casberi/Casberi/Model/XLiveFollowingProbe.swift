#if DEBUG
import Foundation

/// A MEASUREMENT, not a feature (2026-10-27): can the X live session
/// (`XLiveAuth`, prd §701) read the person's Following timeline — the
/// `HomeLatestTimeline` GraphQL request x.com's own Following tab makes — with
/// the same cookies, CSRF header and public bearer the notifications read
/// sends, and nothing else? In particular, no `x-client-transaction-id`: X
/// demands that obfuscated header on some timelines and answers a request
/// without it with a bare 404 (or a 403 naming the header), which is the
/// question this exists to settle before anything is built.
///
/// ONE request per launch, the newest page, no paging. It logs the SHAPE only:
/// status, the rate-limit headers, how the query id was found, and entry
/// counts by kind — never a post's words, a handle or an id. Read-only: the
/// request sends no `seenTweetIds` and nothing here marks anything seen.
enum XLiveFollowingProbe {
    /// A POST with a JSON body unless `mode` is `get`. MEASURED 2026-10-27:
    /// the GET the tracker lists answers 200 with the two cursors and no
    /// posts; the POST answers the page (89 entries). Either way, one request.
    @MainActor
    static func run(mode: String, queryOverride: String?) async {
        guard let auth = XLiveAuth.stored else {
            NSLog("[Casberi] xFollowing| not signed in — sign in on the X account page first")
            return
        }
        let queryID = queryOverride.flatMap { $0.isEmpty ? nil : $0 } ?? XLiveFollowing.queryID
        let post = mode.lowercased() != "get"
        NSLog("[Casberi] xFollowing| query id %@ (%@), %@, no x-client-transaction-id",
              queryID, queryOverride == nil ? "XLiveFollowing.queryID, pinned 2026-10-27" : "-xFollowingQueryID",
              post ? "POST" : "GET")

        let variables: [String: Any] = [
            "count": 20,
            "includePromotedContent": false,
            "latestControlAvailable": true,
            "requestContext": "launch",
        ]
        guard let request = request(queryID: queryID, variables: variables, post: post, auth: auth) else {
            NSLog("[Casberi] xFollowing| could not build the request")
            return
        }
        guard let (data, http) = await IngestSupport.sendRequest(request, service: "X") else {
            NSLog("[Casberi] xFollowing| unreachable — no response at all")
            return
        }

        let status = http.statusCode
        let limit = http.value(forHTTPHeaderField: "x-rate-limit-limit") ?? "none"
        let remaining = http.value(forHTTPHeaderField: "x-rate-limit-remaining") ?? "none"
        let resetRaw = http.value(forHTTPHeaderField: "x-rate-limit-reset")
        let resetIn = resetRaw.flatMap(TimeInterval.init).map {
            String(format: "%.1f min", ($0 - Date().timeIntervalSince1970) / 60)
        } ?? "none"
        NSLog("[Casberi] xFollowing| HTTP %d · %d bytes · rate limit %@, remaining %@, reset %@ (in %@)",
              status, data.count, limit, remaining, resetRaw ?? "none", resetIn)

        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let errors = json?["errors"] as? [[String: Any]], !errors.isEmpty {
            // X's own error words — a missing feature, a rotated id, a demand
            // for the header — never a post's.
            for e in errors.prefix(3) {
                NSLog("[Casberi] xFollowing| GraphQL error code %@: %@",
                      String(describing: e["code"] ?? "none"),
                      String((e["message"] as? String ?? "").prefix(240)))
            }
        }
        guard status == 200 else {
            switch status {
            case 404 where data.isEmpty:
                NSLog("[Casberi] xFollowing| bare 404 with no body — X's answer to a missing x-client-transaction-id, or a rotated query id")
            case 404:
                NSLog("[Casberi] xFollowing| 404 with a body — likely a rotated query id")
            case 403:
                let body = String(data: data.prefix(300), encoding: .utf8) ?? ""
                NSLog("[Casberi] xFollowing| 403 — %@", body.localizedCaseInsensitiveContains("transaction")
                      ? "names the transaction id: X demands the header"
                      : "refused; the cookies may be stale")
            case 401:
                NSLog("[Casberi] xFollowing| 401 — the stored session is no longer signed in")
            case 429:
                NSLog("[Casberi] xFollowing| 429 — rate limited")
            default:
                NSLog("[Casberi] xFollowing| unexpected status")
            }
            if json == nil, !data.isEmpty {
                NSLog("[Casberi] xFollowing| non-JSON body: %@",
                      String(data: data.prefix(200), encoding: .utf8) ?? "(non-UTF8)")
            }
            return
        }
        guard let json else {
            NSLog("[Casberi] xFollowing| 200 with no JSON object")
            return
        }
        logShape(json)
        // What the landing would take (prd §1582), counted, never shown.
        if let posts = XFollowingRead.posts(json, me: XLiveAuth.userID, now: .now) {
            NSLog("[Casberi] xFollowing| parsed %d posts: %d reposts, %d quotes, %d with pictures, %d words-only",
                  posts.count, posts.filter { $0.repostedBy != nil }.count,
                  posts.filter { $0.quoted != nil }.count,
                  posts.filter { !$0.imageURLs.isEmpty }.count,
                  posts.filter { $0.imageURLs.isEmpty }.count)
        } else {
            NSLog("[Casberi] xFollowing| parsed nil — not the measured shape")
        }
        if mode.lowercased() == "shape" { writeSkeleton(json) }
    }

    /// `shape`: the STRUCTURE of one post entry, one conversation and one
    /// repost — every key kept, every value replaced by its type — written to
    /// the app's Documents as `xFollowingShape.json`. No words, ids or handles
    /// survive it; it is what the parser is written against.
    private static func writeSkeleton(_ root: [String: Any]) {
        let instructions = ((((root["data"] as? [String: Any])?["home"] as? [String: Any])?["home_timeline_urt"]
            as? [String: Any])?["instructions"] as? [[String: Any]]) ?? []
        let entries = instructions.flatMap { $0["entries"] as? [[String: Any]] ?? [] }
        func id(_ e: [String: Any]) -> String { e["entryId"] as? String ?? "" }
        let post = entries.first { id($0).hasPrefix("tweet-") && !String(describing: $0).contains("retweeted_status_result") }
        let repost = entries.first { id($0).hasPrefix("tweet-") && String(describing: $0).contains("retweeted_status_result") }
        let conversation = entries.first { id($0).hasPrefix("home-conversation") }
        let quote = entries.first { id($0).hasPrefix("tweet-") && String(describing: $0).contains("quoted_status_result") }
        var out: [String: Any] = [:]
        // Posts whose words are a bare x.com status address: what else they
        // carry, and whether the address is the post's own. No words kept.
        var linkOnly: [[String: Any]] = []
        for e in entries where id(e).hasPrefix("tweet-") || id(e).hasPrefix("home-conversation") {
            let item = ((e["content"] as? [String: Any])?["itemContent"] as? [String: Any])
                ?? ((((e["content"] as? [String: Any])?["items"] as? [[String: Any]])?.last?["item"] as? [String: Any])?["itemContent"] as? [String: Any])
            guard let raw = (item?["tweet_results"] as? [String: Any])?["result"] as? [String: Any] else { continue }
            let r = XPostShape.unwrap(raw)
            let inner = ((r["legacy"] as? [String: Any])?["retweeted_status_result"] as? [String: Any])?["result"] as? [String: Any]
            let body = inner.map(XPostShape.unwrap) ?? r
            guard let words = XPostShape.words(body).map({ XPostShape.expandLinks($0, result: body) }),
                  words.range(of: #"^https?://\S+/status/\d+\S*$"#, options: .regularExpression) != nil
            else { continue }
            let rest = body["rest_id"] as? String ?? "?"
            let tail = words.split(separator: "/").suffix(2).map { $0.allSatisfy(\.isNumber) ? "<id>" : String($0) }
            let qid = (body["legacy"] as? [String: Any])?["quoted_status_id_str"] as? String ?? ""
            let parsed = XFollowingRead.post(r, me: XLiveAuth.userID, now: .now)
            linkOnly.append(["selfLink": words.contains(rest), "tail": tail.joined(separator: "/"),
                             "linkIsQuoted": !qid.isEmpty && words.contains(qid),
                             "dropsToEmpty": !qid.isEmpty && XFollowingRead.dropping(qid, from: words).isEmpty,
                             "parsedTextNil": parsed.map { $0.text == nil } ?? false,
                             "parsedNil": parsed == nil,
                             "hostShape": words.replacingOccurrences(of: #"/status/.*"#, with: "", options: .regularExpression)
                                 .replacingOccurrences(of: #"[A-Za-z0-9_]+$"#, with: "<h>", options: .regularExpression),
                             "skeleton": skeleton(body)])
        }
        if !linkOnly.isEmpty { out["linkOnly"] = linkOnly }
        if let post { out["post"] = skeleton(post) }
        if let repost { out["repost"] = skeleton(repost) }
        if let conversation { out["conversation"] = skeleton(conversation) }
        if let quote { out["quote"] = skeleton(quote) }
        // A created_at's FORMAT, never its value: the digits become 9s.
        if let legacy = (((((post?["content"] as? [String: Any])?["itemContent"] as? [String: Any])?["tweet_results"]
            as? [String: Any])?["result"] as? [String: Any])?["legacy"] as? [String: Any]),
           let created = legacy["created_at"] as? String {
            out["created_at_format"] = String(created.map { $0.isNumber ? "9" : $0 })
        }
        guard let data = try? JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys]),
              let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        else { return }
        let url = dir.appendingPathComponent("xFollowingShape.json")
        try? data.write(to: url)
        NSLog("[Casberi] xFollowing| skeleton written: %@ (%d bytes)", url.path, data.count)
    }

    private static func skeleton(_ value: Any, depth: Int = 0) -> Any {
        guard depth < 18 else { return "…" }
        switch value {
        case let dict as [String: Any]:
            return dict.mapValues { skeleton($0, depth: depth + 1) }
        case let array as [Any]:
            return array.isEmpty ? [] : ["\(array.count)×", skeleton(array[0], depth: depth + 1)]
        case let n as NSNumber:
            return CFGetTypeID(n) == CFBooleanGetTypeID() ? "bool" : "number"
        case is String:
            return "string"
        default:
            return "null"
        }
    }

    private static func request(queryID: String, variables: [String: Any], post: Bool,
                                auth: (authToken: String, ct0: String)) -> URLRequest? {
        if post { return XLiveFollowing.request(queryID: queryID, auth: auth) }
        guard let v = try? JSONSerialization.data(withJSONObject: variables, options: [.sortedKeys]),
              let f = try? JSONSerialization.data(withJSONObject: XLiveFollowing.features, options: [.sortedKeys]),
              var comps = URLComponents(string: "https://x.com/i/api/graphql/\(queryID)/HomeLatestTimeline")
        else { return nil }
        comps.queryItems = [
            URLQueryItem(name: "variables", value: String(data: v, encoding: .utf8)),
            URLQueryItem(name: "features", value: String(data: f, encoding: .utf8)),
        ]
        guard let url = comps.url else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(XLiveNotifications.guestBearerToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (field, value) in XLiveNotifications.headers(auth) {
            request.setValue(value, forHTTPHeaderField: field)
        }
        return request
    }

    /// `data.home.home_timeline_urt.instructions[].entries`, counted by the
    /// kind its `entryId` names — never its content.
    private static func logShape(_ root: [String: Any]) {
        NSLog("[Casberi] xFollowing| top-level keys: %@", root.keys.sorted().joined(separator: ", "))
        guard let data = root["data"] as? [String: Any],
              let home = data["home"] as? [String: Any],
              let urt = home["home_timeline_urt"] as? [String: Any],
              let instructions = urt["instructions"] as? [[String: Any]]
        else {
            let dataKeys = (root["data"] as? [String: Any])?.keys.sorted().joined(separator: ", ") ?? "none"
            NSLog("[Casberi] xFollowing| no data.home.home_timeline_urt.instructions — data keys: %@", dataKeys)
            return
        }
        NSLog("[Casberi] xFollowing| instructions: %@",
              instructions.map { $0["type"] as? String ?? "?" }.joined(separator: ", "))
        let entries = instructions.flatMap { $0["entries"] as? [[String: Any]] ?? [] }
        var kinds: [String: Int] = [:]
        var resolved = 0
        for entry in entries {
            let id = entry["entryId"] as? String ?? ""
            let kind = ["promoted-tweet", "tweet", "home-conversation", "cursor-top", "cursor-bottom",
                        "who-to-follow", "community-to-join", "messageprompt"]
                .first { id.hasPrefix($0) } ?? "other"
            kinds[kind, default: 0] += 1
            let content = entry["content"] as? [String: Any]
            let item = content?["itemContent"] as? [String: Any]
            if let result = (item?["tweet_results"] as? [String: Any])?["result"] as? [String: Any],
               result["legacy"] != nil || (result["tweet"] as? [String: Any])?["legacy"] != nil {
                resolved += 1
            }
        }
        NSLog("[Casberi] xFollowing| %d entries: %@ · %d single posts resolve to a body",
              entries.count,
              kinds.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "),
              resolved)
    }
}
#endif
