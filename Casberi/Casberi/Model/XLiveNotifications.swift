import Foundation
import SwiftData

/// X's own INTERNAL web GraphQL API, read with the user's OWN browser-session
/// cookies (prd §701) — not the paid public API, which this app will never
/// pay per-post for (§280's finding, which this supersedes for the live half
/// only; the archive stays the only door for bulk history).
///
/// **What this is, precisely, because the distinction matters.** `auth_token`
/// and `ct0` are the two cookies x.com's own web app sets on an ordinary
/// sign-in — the same pair your own Safari carries after you log in at
/// x.com. `XLiveLoginView` harvests them from an in-app `WKWebView` the
/// person signs into directly, nothing is extracted from X's own app binary,
/// and every request below carries the pair back exactly the way a browser
/// tab would. The bearer token is the public, UNAUTHENTICATED "guest" token
/// x.com embeds in every page load for every visitor — an app identifier,
/// not a secret, and not a credential this app minted or stole.
///
/// This is **not** the Instagram-style technique (an extracted proprietary
/// signing secret used to impersonate the official app to an anti-abuse
/// system) — it is closer to what any browser extension that shows your own
/// notifications does. It is still a deliberate, informed, ToS-gray-area
/// choice, made once by this app's sole user for their own account: reading
/// X outside its paid API carries real risk of that account being
/// rate-limited or throttled, possibly suspended. The setup screen says so
/// in plain words before the tap, and it is a SEPARATE act from the archive
/// import — turning live notifications off never touches an imported row.
enum XLiveAuth {
    private static let authTokenVaultKey = "x.live.authToken"
    private static let ct0VaultKey = "x.live.ct0"

    /// Both cookies together, or neither — `TrelloAuth`'s two-credential
    /// shape, because a lone `ct0` has no session behind it and a lone
    /// `auth_token` can't pass the CSRF check every GraphQL call still
    /// enforces (`X-Csrf-Token` must equal the `ct0` cookie).
    static var stored: (authToken: String, ct0: String)? {
        guard let a = TokenVault.get(authTokenVaultKey), !a.isEmpty,
              let c = TokenVault.get(ct0VaultKey), !c.isEmpty
        else { return nil }
        return (authToken: a, ct0: c)
    }

    static var connected: Bool { stored != nil }

    static func store(authToken: String, ct0: String) {
        TokenVault.set(authToken, for: authTokenVaultKey)
        TokenVault.set(ct0, for: ct0VaultKey)
    }

    /// Clears the live pair only — an imported archive's rows are untouched,
    /// the same "delete things vs. delete access are two verbs" ruling every
    /// other seat here follows (2026-07-13).
    static func clear() {
        TokenVault.delete(authTokenVaultKey)
        TokenVault.delete(ct0VaultKey)
    }
}

/// The read itself — X's `NotificationsTimeline` GraphQL query, over the same
/// internal endpoint the x.com web app's own bell icon calls.
///
/// **UNMEASURED, in this codebase's own sense of the word** (see
/// `TrelloAuth`/`JiraAuth`): authored against the publicly documented shape of
/// X's internal timeline GraphQL responses, with no live X session available
/// to this build host. Every parse fails to nil/empty rather than guessing, so
/// a shape drift lands nothing instead of landing something wrong —
/// `diagnose()` exists so that drift is a one-launch diagnosis, never a
/// silently empty room.
enum XLiveNotifications {
    /// Distinct from `XArchiveImport`'s `"x:"` prefix (`x:tweet:`, `x:like:`,
    /// …) ON PURPOSE — a live notification and an archived post can name the
    /// same underlying id, and folding them into one dedupe namespace would
    /// let a live read silently swallow an archived row or vice versa.
    static let sourceRefPrefix = "x-live:notif:"

    /// The public, UNAUTHENTICATED bearer x.com's own web client ships on
    /// every page load (see `XLiveAuth`'s header note) — an app identifier,
    /// not a secret. X rotates this occasionally with no notice.
    static let guestBearerToken =
        "AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs=1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA"

    /// The `NotificationsTimeline` query id. X versions every GraphQL query by
    /// a hash-like id that rotates without notice and with no keyless way to
    /// discover the current one — pinned here, and a break shows up as a 404
    /// on this exact path. `diagnose()` prints the raw status so that is a
    /// one-launch diagnosis rather than a silently empty room.
    static let notificationsQueryID = "Ev6UMJRROInk_RMH2oVbBg"

    @MainActor private static var running = false

    /// Lands the newest notifications as things, deduped by `sourceRefPrefix`.
    /// nil = couldn't run at all (not signed in, or the read failed outright);
    /// 0 or more = a real read, however many were new.
    @MainActor
    @discardableResult
    static func refresh(context: ModelContext) async -> Int? {
        guard let auth = XLiveAuth.stored else { return nil }
        guard !running else { return 0 }
        running = true
        defer { running = false }

        let (json, status) = await fetch(auth: auth)
        guard status == 200, let entries = notificationEntries(json) else { return nil }

        let existing = IngestSupport.existingSourceRefs(context, source: "X")
        var added = 0
        for entry in entries {
            guard let id = entry["entryId"] as? String, !id.isEmpty else { continue }
            let ref = sourceRefPrefix + id
            guard !existing.contains(ref) else { continue }
            guard let thing = thing(from: entry, ref: ref) else { continue }
            context.insert(thing)
            SpotlightIndex.index([thing])
            added += 1
        }
        if added > 0 { context.saveHonestly() }
        return added
    }

    /// The measure tool for a bridge authored against a rotating,
    /// undocumented API and never run live — `TrelloAuth.diagnose()`'s exact
    /// shape: one NSLog per phase, printing enough to diagnose a stale query
    /// id or a cookie X has since invalidated without guessing.
    @MainActor
    static func diagnose() async {
        guard let auth = XLiveAuth.stored else {
            NSLog("[Casberi] xLive| not signed in — connect from the X account page first")
            return
        }
        let (json, status) = await fetch(auth: auth)
        NSLog("[Casberi] xLive| HTTP %d", status)
        guard status == 200 else {
            switch status {
            case 401, 403:
                NSLog("[Casberi] xLive| refused — the stored cookies are stale, sign in again")
            case 0:
                NSLog("[Casberi] xLive| unreachable — check the connection")
            default:
                NSLog("[Casberi] xLive| unexpected status — the query id or the feature flags may have rotated")
            }
            // `getJSONStatus` discards the body on non-200 by design (every
            // other bridge's `diagnose()` never needed it) — this bridge
            // does, since it's UNMEASURED and the whole point of `diagnose`
            // is a one-launch cause, not just a code. Re-issue the same
            // request directly for X's own error body — never the request's
            // cookie header. Found the wrong guest bearer token AND a stale
            // query id this way on the first real measurement (2026-09-11).
            if let url = requestURL() {
                var request = URLRequest(url: url)
                request.setValue("Bearer \(guestBearerToken)", forHTTPHeaderField: "Authorization")
                request.setValue("auth_token=\(auth.authToken); ct0=\(auth.ct0)", forHTTPHeaderField: "Cookie")
                request.setValue(auth.ct0, forHTTPHeaderField: "X-Csrf-Token")
                request.setValue("yes", forHTTPHeaderField: "X-Twitter-Active-User")
                request.setValue("OAuth2Session", forHTTPHeaderField: "X-Twitter-Auth-Type")
                request.setValue("https://x.com", forHTTPHeaderField: "Origin")
                request.setValue("https://x.com/", forHTTPHeaderField: "Referer")
                if let (data, _) = try? await URLSession.shared.data(for: request) {
                    let body = String(data: data.prefix(600), encoding: .utf8) ?? "(non-UTF8 body)"
                    NSLog("[Casberi] xLiveDebugBody| %@", body)
                }
            }
            return
        }
        guard let root = json as? [String: Any] else {
            NSLog("[Casberi] xLive| 200 with no JSON object — shape drift")
            return
        }
        NSLog("[Casberi] xLive| top-level keys: %@", Array(root.keys).sorted().joined(separator: ", "))
        if let errors = root["errors"] as? [[String: Any]], !errors.isEmpty {
            NSLog("[Casberi] xLive| %d GraphQL error(s), first: %@", errors.count,
                  (errors.first?["message"] as? String) ?? "(no message)")
        }
        let entries = notificationEntries(json) ?? []
        NSLog("[Casberi] xLive| %d entries parsed", entries.count)
        for entry in entries.prefix(5) {
            NSLog("[Casberi] xLiveEntry| id=%@ text=%@",
                  (entry["entryId"] as? String) ?? "MISSING",
                  (notificationText(entry) ?? "MISSING").prefix(80).description)
        }
    }

    // MARK: - The request

    private static func fetch(auth: (authToken: String, ct0: String)) async -> (json: Any?, status: Int) {
        guard let url = requestURL() else { return (nil, 0) }
        let cookie = "auth_token=\(auth.authToken); ct0=\(auth.ct0)"
        let headers: [String: String] = [
            "Cookie": cookie,
            "X-Csrf-Token": auth.ct0,
            "X-Twitter-Active-User": "yes",
            "X-Twitter-Auth-Type": "OAuth2Session",
            "Origin": "https://x.com",
            "Referer": "https://x.com/",
        ]
        return await IngestSupport.getJSONStatus(
            url.absoluteString, auth: "Bearer \(guestBearerToken)",
            headers: headers, service: "X")
    }

    /// Best-effort variables/features, url-encoded onto the query string
    /// (prd §701's mechanics). X's GraphQL surface gates many queries behind
    /// dozens of feature flags that rotate with no announcement; this is
    /// authored against the publicly documented shape of a notifications
    /// timeline call and marked UNMEASURED for the same reason the query id
    /// above is.
    private static func requestURL() -> URL? {
        let variables: [String: Any] = [
            "timeline_type": "All",
            "count": 40,
        ]
        let features: [String: Any] = [
            "responsive_web_graphql_timeline_navigation_enabled": true,
            "rweb_tipjar_consumption_enabled": true,
            "verified_phone_label_enabled": false,
            "creator_subscriptions_tweet_preview_api_enabled": true,
            "responsive_web_graphql_exclude_directive_enabled": true,
            "responsive_web_graphql_skip_user_profile_image_extensions_enabled": false,
            "communities_web_enable_tweet_community_results_fetch": true,
            "c9s_tweet_anatomy_moderator_badge_enabled": true,
            "articles_preview_enabled": true,
            "tweetypie_unmention_optimization_enabled": true,
            "responsive_web_edit_tweet_api_enabled": true,
            "graphql_is_translatable_rweb_tweet_is_translatable_enabled": true,
            "view_counts_everywhere_api_enabled": true,
            "longform_notetweets_consumption_enabled": true,
            "responsive_web_twitter_article_tweet_consumption_enabled": true,
            "tweet_awards_web_tipping_enabled": false,
            "creator_subscriptions_quote_tweet_preview_enabled": false,
            "freedom_of_speech_not_reach_fetch_enabled": true,
            "standardized_nudges_misinfo": true,
            "tweet_with_visibility_results_prefer_gql_limited_actions_policy_enabled": true,
            "rweb_video_timestamps_enabled": true,
            "longform_notetweets_rich_text_read_enabled": true,
            "longform_notetweets_inline_media_enabled": true,
            "responsive_web_enhance_cards_enabled": false,
        ]
        guard let variablesJSON = jsonString(variables),
              let featuresJSON = jsonString(features) else { return nil }
        var comps = URLComponents(
            string: "https://x.com/i/api/graphql/\(notificationsQueryID)/NotificationsTimeline")
        comps?.queryItems = [
            URLQueryItem(name: "variables", value: variablesJSON),
            URLQueryItem(name: "features", value: featuresJSON),
        ]
        return comps?.url
    }

    private static func jsonString(_ object: [String: Any]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: object,
                                                      options: [.sortedKeys]) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Parsing (best-effort — see the type's own UNMEASURED note)

    /// Walks `data.viewer.notification_timeline.timeline.instructions[].entries`
    /// — the publicly documented shape of an X timeline response, an
    /// `instructions` array of `entries` arrays, several instruction types
    /// mixed together (adds, pins, terminators). Only entries are read; every
    /// other instruction type is silently skipped.
    private static func notificationEntries(_ json: Any?) -> [[String: Any]]? {
        guard let root = json as? [String: Any],
              let data = root["data"] as? [String: Any],
              let viewerV2 = data["viewer_v2"] as? [String: Any],
              let userResults = viewerV2["user_results"] as? [String: Any],
              let result = userResults["result"] as? [String: Any],
              let timeline = (result["notification_timeline"] as? [String: Any])?["timeline"] as? [String: Any],
              let instructions = timeline["instructions"] as? [[String: Any]]
        else { return nil }
        return instructions.flatMap { $0["entries"] as? [[String: Any]] ?? [] }
    }

    /// The notification's own words, off `itemContent.rich_message.text` —
    /// MEASURED against a real signed-in session (prd §701's first
    /// measurement pass, 2026-09-11): a like/follow/mention notice carries a
    /// plain-text summary there ("New post notifications for Jebu Ittiachen
    /// and 8 others"), independent of whether the underlying post resolves.
    /// (The `itemContent.notification.message` path this replaced was never
    /// real — authored against a guess, and this build's own measurement is
    /// what corrected it.)
    private static func notificationText(_ entry: [String: Any]) -> String? {
        guard let content = entry["content"] as? [String: Any],
              let itemContent = content["itemContent"] as? [String: Any],
              let richMessage = itemContent["rich_message"] as? [String: Any],
              let text = richMessage["text"] as? String, !text.isEmpty
        else { return nil }
        return text
    }

    /// The permalink a notification's underlying post resolves to, when one
    /// is embedded — MEASURED against a real signed-in session (prd §701's
    /// first measurement pass, 2026-09-11): `itemContent.template` directly
    /// (not nested under a "notification" key), whose `target_objects` is a
    /// bare array of `TimelineNotificationTweetRef`s, each carrying
    /// `tweet_results.result.rest_id` — the guessed
    /// `template.aggregateUserActionsV1.targetObjects` path this replaced was
    /// never real. nil for a notice with no single post behind it (a follow,
    /// a list add), which lands with no `content` URL rather than a guessed
    /// one.
    private static func notificationPermalink(_ entry: [String: Any]) -> String? {
        guard let content = entry["content"] as? [String: Any],
              let itemContent = content["itemContent"] as? [String: Any],
              let template = itemContent["template"] as? [String: Any],
              let targetObjects = template["target_objects"] as? [[String: Any]],
              let first = targetObjects.first,
              let tweetResults = first["tweet_results"] as? [String: Any],
              let result = tweetResults["result"] as? [String: Any],
              let restID = result["rest_id"] as? String
        else { return nil }
        return "https://x.com/i/web/status/\(restID)"
    }

    private static func thing(from entry: [String: Any], ref: String) -> Thing? {
        guard let text = notificationText(entry) else { return nil }
        let permalink = notificationPermalink(entry) ?? "https://x.com/notifications"
        return Thing(
            kind: .link,
            title: IngestSupport.titleLine(IngestSupport.decodeHTMLEntities(text)),
            content: permalink,
            source: "X",
            capturedAt: .now,
            sourceRef: ref)
    }
}
