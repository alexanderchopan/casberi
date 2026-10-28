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
    /// `HomeLatestTimeline`'s query id, as x.com's logged-in web bundle named
    /// it on 2026-10-27 (read off a public tracker of that bundle,
    /// fa0311/TwitterInternalAPIDocument, regenerated the same day). Pinned
    /// like `XLiveNotifications.notificationsQueryID`: X rotates it without
    /// notice, a rotation reads as a 404 on this path, and
    /// `-xFollowingQueryID <id>` tries another without a rebuild.
    static let pinnedQueryID = "KQPfcqQJJqF6M0D77p3JKw"

    /// The feature switches the same bundle sends with this query, verbatim.
    /// X answers 400 naming any it wants and did not get.
    private static let features: [String: Any] = [
        "rweb_video_screen_enabled": false,
        "rweb_cashtags_enabled": true,
        "profile_label_improvements_pcf_label_in_post_enabled": true,
        "responsive_web_profile_redirect_enabled": true,
        "rweb_tipjar_consumption_enabled": false,
        "verified_phone_label_enabled": false,
        "creator_subscriptions_tweet_preview_api_enabled": true,
        "responsive_web_graphql_timeline_navigation_enabled": true,
        "premium_content_api_read_enabled": false,
        "communities_web_enable_tweet_community_results_fetch": true,
        "c9s_tweet_anatomy_moderator_badge_enabled": true,
        "responsive_web_grok_analyze_button_fetch_trends_enabled": false,
        "responsive_web_grok_analyze_post_followups_enabled": true,
        "rweb_cashtags_composer_attachment_enabled": true,
        "responsive_web_jetfuel_frame": true,
        "rweb_sports_post_context_enabled": true,
        "responsive_web_grok_share_attachment_enabled": true,
        "responsive_web_grok_annotations_enabled": true,
        "articles_preview_enabled": true,
        "responsive_web_edit_tweet_api_enabled": true,
        "graphql_is_translatable_rweb_tweet_is_translatable_enabled": true,
        "view_counts_everywhere_api_enabled": true,
        "longform_notetweets_consumption_enabled": true,
        "responsive_web_twitter_article_tweet_consumption_enabled": true,
        "content_disclosure_indicator_enabled": true,
        "content_disclosure_ai_generated_indicator_enabled": true,
        "responsive_web_grok_show_grok_translated_post": true,
        "responsive_web_grok_analysis_button_from_backend": true,
        "post_ctas_fetch_enabled": false,
        "freedom_of_speech_not_reach_fetch_enabled": true,
        "standardized_nudges_misinfo": true,
        "tweet_with_visibility_results_prefer_gql_limited_actions_policy_enabled": true,
        "longform_notetweets_rich_text_read_enabled": true,
        "longform_notetweets_inline_media_enabled": false,
        "responsive_web_nested_quote_preview_enabled": true,
        "responsive_web_grok_image_annotation_enabled": true,
        "responsive_web_grok_imagine_annotation_enabled": true,
        "responsive_web_grok_community_note_auto_translation_is_enabled": true,
        "responsive_web_enhance_cards_enabled": false,
    ]

    /// A POST with a JSON body unless `mode` is `get`. MEASURED 2026-10-27:
    /// the GET the tracker lists answers 200 with the two cursors and no
    /// posts; the POST answers the page (89 entries). Either way, one request.
    @MainActor
    static func run(mode: String, queryOverride: String?) async {
        guard let auth = XLiveAuth.stored else {
            NSLog("[Casberi] xFollowing| not signed in — sign in on the X account page first")
            return
        }
        let queryID = queryOverride.flatMap { $0.isEmpty ? nil : $0 } ?? pinnedQueryID
        let post = mode.lowercased() != "get"
        NSLog("[Casberi] xFollowing| query id %@ (%@), %@, no x-client-transaction-id",
              queryID, queryOverride == nil ? "pinned 2026-10-27 from the web bundle's tracker" : "-xFollowingQueryID",
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
    }

    private static func request(queryID: String, variables: [String: Any], post: Bool,
                                auth: (authToken: String, ct0: String)) -> URLRequest? {
        let base = "https://x.com/i/api/graphql/\(queryID)/HomeLatestTimeline"
        var request: URLRequest
        if post {
            guard let url = URL(string: base),
                  let body = try? JSONSerialization.data(withJSONObject: [
                      "variables": variables, "features": features, "queryId": queryID,
                  ]) else { return nil }
            request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        } else {
            guard let v = try? JSONSerialization.data(withJSONObject: variables, options: [.sortedKeys]),
                  let f = try? JSONSerialization.data(withJSONObject: features, options: [.sortedKeys]),
                  var comps = URLComponents(string: base) else { return nil }
            comps.queryItems = [
                URLQueryItem(name: "variables", value: String(data: v, encoding: .utf8)),
                URLQueryItem(name: "features", value: String(data: f, encoding: .utf8)),
            ]
            guard let url = comps.url else { return nil }
            request = URLRequest(url: url)
        }
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
