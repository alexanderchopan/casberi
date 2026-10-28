import Foundation
import SwiftData

/// YOUR X FOLLOWING TIMELINE, LANDED (prd §1582, user, 2026-10-27: "it would
/// be good if instead of seeing 'new posts from Bob and 9 others' it instead
/// showed one of their posts"; "most people will read from the feed").
///
/// One read of the newest page of x.com's own Following tab
/// (`HomeLatestTimeline`), riding the X notifications sweep — so the same
/// foreground-only, ten-minute throttle (`BridgeRefresh.dueForHeal("x.live")`)
/// and the same session, cookies, CSRF header and public bearer
/// (`XLiveNotifications.headers`). MEASURED 2026-10-27: answers 200 with no
/// `x-client-transaction-id`, 500 requests per 15 minutes; this spends at
/// most six an hour. No paging, nothing marked seen: read-only, the cookie
/// seats' rule.
///
/// A post you never open goes after `XFollowingRead.keepDays`; one you open
/// stays, like anything else you keep.
enum XLiveFollowing {
    /// Distinct from the notices' `x-live:notif:` and the archive's `x:`.
    static let refPrefix = "x-live:post:"

    /// `HomeLatestTimeline`'s query id as x.com's web client named it on
    /// 2026-10-27. X rotates it without notice; a rotation reads as a 404,
    /// the read lands nothing, and the "New post" notices come back (see
    /// `XLiveNotifications.refresh`). `-xFollowingProbe` names the cause.
    static let queryID = "KQPfcqQJJqF6M0D77p3JKw"

    /// The feature switches the web client sends with this query, verbatim.
    /// X answers 400 naming any it wants and did not get.
    static let features: [String: Any] = [
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

    /// The newest page, as the web client asks for it: a POST with a JSON
    /// body. MEASURED: the GET form answers 200 with the cursors and no posts.
    /// No `seenTweetIds`: nothing is reported seen.
    static func request(queryID: String = queryID,
                        auth: (authToken: String, ct0: String)) -> URLRequest? {
        guard let url = URL(string: "https://x.com/i/api/graphql/\(queryID)/HomeLatestTimeline"),
              let body = try? JSONSerialization.data(withJSONObject: [
                  "variables": [
                      "count": 20,
                      "includePromotedContent": false,
                      "latestControlAvailable": true,
                      "requestContext": "launch",
                  ] as [String: Any],
                  "features": features,
                  "queryId": queryID,
              ])
        else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(XLiveNotifications.guestBearerToken)", forHTTPHeaderField: "Authorization")
        for (field, value) in XLiveNotifications.headers(auth) {
            request.setValue(value, forHTTPHeaderField: field)
        }
        return request
    }

    /// One read, landed, then the prune. nil when the read failed (the caller
    /// then keeps landing the "New post" notices); otherwise how many posts
    /// were new.
    @MainActor
    static func refresh(auth: (authToken: String, ct0: String), context: ModelContext) async -> Int? {
        guard let request = request(auth: auth),
              let (data, http) = await IngestSupport.sendRequest(request, service: "X"),
              http.statusCode == 200,
              let posts = XFollowingRead.posts(try? JSONSerialization.jsonObject(with: data),
                                               me: XLiveAuth.userID, now: .now)
        else { return nil }
        let (added, renamed) = land(posts, context: context)
        let pruned = prune(context: context, now: .now) + retireNotices(context: context)
        if added > 0 || renamed > 0 || pruned > 0 { context.saveHonestly() }
        return added
    }

    /// The "New post from…" notices already landed go once the posts do
    /// (user: "real posts replace the 'new posts from Bob and 9 others'
    /// notices"). Only while the read answers, which is the only time this
    /// runs: a failed read keeps them, and keeps landing them.
    @MainActor
    private static func retireNotices(context: ModelContext) -> Int {
        let prefix = XLiveNotifications.sourceRefPrefix
        let descriptor = FetchDescriptor<Thing>(predicate: #Predicate {
            $0.source == "X" && ($0.sourceRef?.starts(with: prefix) ?? false)
        })
        var removed: [UUID] = []
        for thing in (try? context.fetch(descriptor)) ?? [] where thing.isLive {
            guard XFollowingRead.isNewPostNotice(thing.title) else { continue }
            removed.append(thing.id)
            context.delete(thing)
        }
        if !removed.isEmpty { SpotlightIndex.remove(ids: removed) }
        return removed.count
    }

    /// Each post as a thing of its own, the row anatomy Bluesky's posts take:
    /// the words are the title and `postText`, the author is the face.
    @MainActor
    private static func land(_ posts: [XFollowingRead.Post], context: ModelContext) -> (added: Int, renamed: Int) {
        var byRef: [String: Thing] = [:]
        for thing in landed(context: context) where thing.isLive {
            if let ref = thing.sourceRef { byRef[ref] = thing }
        }
        var added = 0
        var renamed = 0
        for post in posts {
            let ref = refPrefix + post.restID
            let words = post.text.map(IngestSupport.decodeHTMLEntities)
            let title = IngestSupport.titleLine(IngestSupport.decodeHTMLEntities(post.title))
            if let existing = byRef[ref] {
                // An edited post, or one this parser now reads better, renames
                // in place; never a second row.
                if existing.title != title || existing.postText != words {
                    existing.title = title
                    existing.postText = words
                    renamed += 1
                }
                continue
            }
            let thing = Thing(
                kind: .chat,
                title: title,
                content: post.permalink,
                source: "X",
                capturedAt: post.at,
                sourceRef: ref)
            thing.postText = words
            thing.authorHandle = post.handle
            thing.authorAvatarURL = post.avatarURL
            thing.imageURLs = post.imageURLs
            thing.previewImageURL = post.imageURLs.first
            thing.likeCount = post.likes
            thing.repostCount = post.reposts
            thing.replyCount = post.replies
            // An account you follow reposted it: Bluesky's word (`recast`),
            // which the row and the sheet already say.
            if post.repostedBy != nil { thing.socialContext = "recast" }
            if let q = post.quoted {
                thing.quote = SocialCard(handle: q.handle,
                                         text: IngestSupport.decodeHTMLEntities(q.text),
                                         avatarURL: q.avatarURL, url: q.permalink, ref: q.restID)
            }
            context.insert(thing)
            SpotlightIndex.index([thing])
            added += 1
        }
        return (added, renamed)
    }

    /// The posts gone past `keepDays` that you never opened. By AGE, never by
    /// absence from a read: an empty page deletes nothing.
    @MainActor
    @discardableResult
    static func prune(context: ModelContext, now: Date) -> Int {
        let opened = Opened.refs
        var removed: [UUID] = []
        for thing in landed(context: context) where thing.isLive {
            guard let ref = thing.sourceRef,
                  XFollowingRead.prunes(at: thing.capturedAt, opened: opened.contains(ref), now: now)
            else { continue }
            removed.append(thing.id)
            context.delete(thing)
        }
        if !removed.isEmpty { SpotlightIndex.remove(ids: removed) }
        return removed.count
    }

    /// The thing sheet calls this on every open; only a Following post is
    /// remembered.
    static func noteOpened(_ thing: Thing) {
        guard let ref = thing.sourceRef, ref.hasPrefix(refPrefix) else { return }
        Opened.insert(ref)
    }

    /// Scoped by the ref prefix, never the source: the X archive is thousands
    /// of rows (`XLiveNotifications.landedNotices`' reason).
    @MainActor
    private static func landed(context: ModelContext) -> [Thing] {
        let prefix = refPrefix
        let descriptor = FetchDescriptor<Thing>(predicate: #Predicate {
            $0.source == "X" && ($0.sourceRef?.starts(with: prefix) ?? false)
        })
        return (try? context.fetch(descriptor)) ?? []
    }

    /// The Following posts you opened, on this device: a post opened here is
    /// never pruned here. Bounded to the newest `cap`; a post outlives its
    /// place in this list only by days, never by hundreds of opens. Written
    /// from the main thread only (the sheet, the sweep, a sign-out), the
    /// `ThingCast` discipline.
    enum Opened {
        private static let key = "x.live.following.opened"
        private static let cap = 500
        private static var cache: [String]?

        static var refs: Set<String> { Set(load()) }

        static func insert(_ ref: String) {
            var list = load()
            guard !list.contains(ref) else { return }
            list.append(ref)
            if list.count > cap { list.removeFirst(list.count - cap) }
            cache = list
            if let data = try? JSONEncoder().encode(list) { DefaultsWrite.set(data, forKey: key) }
        }

        /// With the session (`XLiveAuth.clear`).
        static func forget() {
            cache = []
            DefaultsWrite.remove(key)
        }

        private static func load() -> [String] {
            if let cache { return cache }
            let list = UserDefaults.standard.data(forKey: key)
                .flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
            cache = list
            return list
        }
    }
}
