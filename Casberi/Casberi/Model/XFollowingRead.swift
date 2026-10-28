import Foundation

/// One X post, as X's web GraphQL serves it — the shape the notifications read
/// (prd §704, §707) and the Following read (prd §1582) both take apart. One
/// parser for one shape, so the two can never drift.
///
/// Pure Foundation: `x-following-selftest.sh` compiles this file whole.
enum XPostShape {
    /// `TweetWithVisibilityResults` wraps a post whenever a visibility rule
    /// applies; the real post sits under `.tweet`.
    static func unwrap(_ result: [String: Any]) -> [String: Any] {
        (result["tweet"] as? [String: Any]) ?? result
    }

    /// The post's author, off `core.user_results.result`.
    static func author(_ result: [String: Any]) -> (handle: String?, avatar: String?) {
        guard let core = result["core"] as? [String: Any],
              let userResults = core["user_results"] as? [String: Any],
              let user = userResults["result"] as? [String: Any]
        else { return (nil, nil) }
        return face(of: user)
    }

    /// One user object → its handle and its face, across both user shapes X
    /// has shipped: `legacy.screen_name`/`profile_image_url_https` on the
    /// older, `core.screen_name`/`avatar.image_url` on the newer (MEASURED on
    /// the Following timeline, 2026-10-27). The avatar is upgraded off X's
    /// 48px `_normal` to its named `_400x400`.
    static func face(of user: [String: Any]) -> (handle: String?, avatar: String?) {
        let legacy = user["legacy"] as? [String: Any]
        let userCore = user["core"] as? [String: Any]
        let handle = (legacy?["screen_name"] as? String)
            ?? (userCore?["screen_name"] as? String)
        let avatar = (legacy?["profile_image_url_https"] as? String)
            ?? ((user["avatar"] as? [String: Any])?["image_url"] as? String)
        return (handle.flatMap { $0.isEmpty ? nil : $0 },
                avatar.flatMap {
                    $0.isEmpty ? nil : $0.replacingOccurrences(of: "_normal.", with: "_400x400.")
                })
    }

    /// The post's own words: a long post's full text on `note_tweet` first
    /// (`legacy.full_text` truncates it at 280), then `legacy.full_text`.
    static func words(_ result: [String: Any]) -> String? {
        if let note = result["note_tweet"] as? [String: Any],
           let noteResults = note["note_tweet_results"] as? [String: Any],
           let noteResult = noteResults["result"] as? [String: Any],
           let text = noteResult["text"] as? String, !text.isEmpty {
            return text
        }
        guard let legacy = result["legacy"] as? [String: Any] else { return nil }
        let text = (legacy["full_text"] as? String) ?? (legacy["text"] as? String)
        guard let text, !text.isEmpty else { return nil }
        return text
    }

    /// t.co out, the real link in; the t.co pointing at the post's own photo
    /// dropped, since the picture is drawn above the words.
    static func expandLinks(_ text: String, result: [String: Any]) -> String {
        guard let legacy = result["legacy"] as? [String: Any] else { return text }
        var out = text
        let entities = legacy["entities"] as? [String: Any]
        for url in (entities?["urls"] as? [[String: Any]]) ?? [] {
            guard let short = url["url"] as? String,
                  let expanded = url["expanded_url"] as? String, !short.isEmpty
            else { continue }
            out = out.replacingOccurrences(of: short, with: expanded)
        }
        let media = ((legacy["extended_entities"] as? [String: Any])?["media"] as? [[String: Any]])
            ?? (entities?["media"] as? [[String: Any]]) ?? []
        for item in media {
            guard let short = item["url"] as? String, !short.isEmpty else { continue }
            out = out.replacingOccurrences(of: short, with: "")
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The post's pictures; a video's poster frame rides the same key.
    static func imageURLs(_ result: [String: Any]) -> [String] {
        guard let legacy = result["legacy"] as? [String: Any] else { return [] }
        let media = ((legacy["extended_entities"] as? [String: Any])?["media"] as? [[String: Any]])
            ?? ((legacy["entities"] as? [String: Any])?["media"] as? [[String: Any]]) ?? []
        return media.compactMap { item in
            (item["media_url_https"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        }
    }

    /// The post's permalink, with the author's handle where we have one.
    static func permalink(restID: String, handle: String?) -> String {
        handle.map { "https://x.com/\($0)/status/\(restID)" } ?? "https://x.com/i/web/status/\(restID)"
    }
}

/// THE FOLLOWING TIMELINE (prd §1582): the newest page x.com's own Following
/// tab reads (`HomeLatestTimeline`), taken apart into posts. MEASURED
/// 2026-10-27 against a signed-in session: ~90 entries a page — single posts
/// (`tweet-`), reply threads (`home-conversation-`, the newest reply last),
/// ads (`promoted-tweet-`, dropped) and cursors.
enum XFollowingRead {
    struct Quoted: Equatable {
        var restID: String
        var handle: String
        var text: String
        var avatarURL: String?
        var permalink: String
    }

    struct Post: Equatable {
        var restID: String
        var handle: String
        var avatarURL: String?
        /// Links expanded; nil when the author wrote no words.
        var text: String?
        var imageURLs: [String]
        var likes: Int?
        var reposts: Int?
        var replies: Int?
        /// When it reached your timeline: written, or reposted.
        var at: Date
        var permalink: String
        /// The account you follow that reposted it; nil for its own post.
        var repostedBy: String?
        var quoted: Quoted?
        /// What the author says the first picture shows.
        var altText: String?
        /// Whom it quotes, even when the quoted post has no words to card.
        var quotedHandle: String?

        /// The row's name. The words where there are any; a post of no words
        /// says what it is, never a bare "Photo" or the link X keeps for a
        /// quoted post: the picture's alt text, else whose picture it is,
        /// else whom it quotes.
        var title: String {
            if let text { return text }
            if let altText { return altText }
            if !imageURLs.isEmpty { return "Photo from @\(handle)" }
            if let quoted = quoted?.handle ?? quotedHandle { return "Quoting @\(quoted)" }
            return "Quoting a post"
        }
    }

    /// How long an unopened Following post stays (user, 2026-10-27:
    /// "unopened posts pruned after a few days"). A post older than this is
    /// never landed either, so a prune can never be undone by the next read.
    static let keepDays: TimeInterval = 3 * 86_400

    /// The X notices the posts replace: "New post from mia" and its digest
    /// ("New post notifications for Bob and 9 others").
    static let newPostNotices = ["New post from", "New post notifications"]

    static func isNewPostNotice(_ text: String) -> Bool {
        newPostNotices.contains { text.hasPrefix($0) }
    }

    /// Whether a landed post goes: older than `keepDays` and never opened.
    static func prunes(at: Date, opened: Bool, now: Date) -> Bool {
        !opened && now.timeIntervalSince(at) > keepDays
    }

    /// The posts on the page, newest first as X ordered them, deduped by
    /// post. `me` is the signed-in account's numeric id: your own posts and
    /// reposts are not news from someone you follow. nil when the page is not
    /// the shape this was measured against.
    static func posts(_ json: Any?, me: String?, now: Date) -> [Post]? {
        guard let root = json as? [String: Any],
              let data = root["data"] as? [String: Any],
              let home = data["home"] as? [String: Any],
              let urt = home["home_timeline_urt"] as? [String: Any],
              let instructions = urt["instructions"] as? [[String: Any]]
        else { return nil }
        var out: [Post] = []
        var seen = Set<String>()
        for entry in instructions.flatMap({ $0["entries"] as? [[String: Any]] ?? [] }) {
            let id = entry["entryId"] as? String ?? ""
            let content = entry["content"] as? [String: Any]
            let itemContent: [String: Any]?
            if id.hasPrefix("tweet-") {
                itemContent = content?["itemContent"] as? [String: Any]
            } else if id.hasPrefix("home-conversation-") {
                // A reply thread: the post that brought it here is its last.
                let items = content?["items"] as? [[String: Any]]
                itemContent = (items?.last?["item"] as? [String: Any])?["itemContent"] as? [String: Any]
            } else {
                continue    // ads, cursors, suggestions
            }
            guard let itemContent, itemContent["promotedMetadata"] == nil,
                  let result = (itemContent["tweet_results"] as? [String: Any])?["result"] as? [String: Any],
                  let post = post(XPostShape.unwrap(result), me: me, now: now),
                  seen.insert(post.restID).inserted
            else { continue }
            out.append(post)
        }
        return out
    }

    static func post(_ result: [String: Any], me: String?, now: Date) -> Post? {
        guard let legacy = result["legacy"] as? [String: Any],
              let at = date(legacy["created_at"] as? String),
              at <= now.addingTimeInterval(300),
              now.timeIntervalSince(at) <= keepDays
        else { return nil }
        if let me, legacy["user_id_str"] as? String == me { return nil }

        var body = result
        var repostedBy: String?
        if let inner = (legacy["retweeted_status_result"] as? [String: Any])?["result"] as? [String: Any] {
            body = XPostShape.unwrap(inner)
            repostedBy = XPostShape.author(result).handle
        }
        guard let restID = body["rest_id"] as? String, !restID.isEmpty else { return nil }
        let (handle, avatar) = XPostShape.author(body)
        guard let handle else { return nil }
        let quote = quoted(body)
        // The quoted post's id is on the quoting post itself, so its address
        // is dropped even when the quoted post is a picture with no words
        // (no card) or did not come back at all.
        let quotedID = quote?.restID
            ?? ((body["legacy"] as? [String: Any])?["quoted_status_id_str"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let text = XPostShape.words(body).map { XPostShape.expandLinks($0, result: body) }
            .map { words in quotedID.map { dropping($0, from: words) } ?? words }
            .flatMap { $0.isEmpty ? nil : $0 }
        let images = XPostShape.imageURLs(body)
        guard text != nil || !images.isEmpty || quotedID != nil else { return nil }
        let counts = body["legacy"] as? [String: Any]
        return Post(
            restID: restID, handle: handle, avatarURL: avatar, text: text, imageURLs: images,
            likes: counts?["favorite_count"] as? Int,
            reposts: counts?["retweet_count"] as? Int,
            replies: counts?["reply_count"] as? Int,
            at: at,
            permalink: XPostShape.permalink(restID: restID, handle: handle),
            repostedBy: repostedBy,
            quoted: quote,
            altText: altText(body),
            quotedHandle: quote?.handle ?? quotedResult(body).flatMap { XPostShape.author($0).handle })
    }

    /// X ends a quote post's words with the quoted post's own address; the
    /// card draws that post, so the address goes (as x.com's own page does).
    static func dropping(_ quotedID: String, from words: String) -> String {
        let pattern = #"https?://(www\.)?(x|twitter)\.com/[^\s]+/status/"# + quotedID + #"[^\s]*"#
        return words.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func altText(_ result: [String: Any]) -> String? {
        let legacy = result["legacy"] as? [String: Any]
        let media = ((legacy?["extended_entities"] as? [String: Any])?["media"] as? [[String: Any]]) ?? []
        return (media.first?["ext_alt_text"] as? String)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    private static func quotedResult(_ result: [String: Any]) -> [String: Any]? {
        ((result["quoted_status_result"] as? [String: Any])?["result"] as? [String: Any]).map(XPostShape.unwrap)
    }

    /// The post it quotes, as a card; nil when it has no words to show.
    private static func quoted(_ result: [String: Any]) -> Quoted? {
        guard let body = quotedResult(result) else { return nil }
        guard let restID = body["rest_id"] as? String, !restID.isEmpty,
              let handle = XPostShape.author(body).handle,
              let text = XPostShape.words(body).map({ XPostShape.expandLinks($0, result: body) }),
              !text.isEmpty
        else { return nil }
        return Quoted(restID: restID, handle: handle, text: text,
                      avatarURL: XPostShape.author(body).avatar,
                      permalink: XPostShape.permalink(restID: restID, handle: handle))
    }

    /// X's `created_at`: "Wed Oct 10 20:19:24 +0000 2018" (format MEASURED).
    static func date(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        return formatter.date(from: raw)
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE MMM dd HH:mm:ss Z yyyy"
        return f
    }()
}
