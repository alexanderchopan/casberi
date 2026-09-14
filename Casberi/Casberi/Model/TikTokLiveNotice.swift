import Foundation

/// TikTok's Activity inbox, read the way tiktok.com's own page reads it (prd
/// §731) — the pure half, Foundation-only so `tiktok-live-selftest.sh` compiles
/// it WHOLE. Everything that touches `Thing` or the Keychain is `TikTokLive`.
///
/// **What was measured, 2026-09-14, from a signed-in tiktok.com page:**
///   · `/api/notice/multi/` and `/api/inbox/notice_list/` answer an UNSIGNED
///     request exactly as a signed one. The page sends `X-Gnarly`,
///     `X-Dynosaur` and `msToken` (and `X-Bogus=1`, now a placeholder), and
///     removing all of them changed nothing — so §726's reason for passing on
///     TikTok (signatures computed by obfuscated JS) does not hold for these
///     two reads. Nothing here computes a signature.
///   · The session cookie is what authorises it: the same request with no
///     cookies answers 200 with `status_code` 8, `"Login expired"`. A dead
///     session is a 200, never a 401, which is why `classify` reads the body.
///   · `group_list` is the only parameter the read needs.
///   · Opening the Activity panel re-asks with `is_mark_read: 1`, which clears
///     the person's unread badge. This file sends 0, always.
///   · The panel's own list request is group 500. The measuring account had
///     no likes, comments or follows, so group 500 answered an empty list, and
///     every group scanned (0–15, 20, 33, 36, 50, 60, 100–1000, 660–662) held
///     only TikTok's own system notices (`template_notice`, `text`,
///     `announcement`).
///
/// **UNMEASURED, and read defensively because of it:** the shape of a like, a
/// comment, a follow or a mention. They are read by the payload key TikTok's
/// notice model uses across its clients (`digg`, `comment`, `follow`, `at`),
/// every field optional, and a notice whose payload names nothing this file
/// knows lands only if it carries TikTok's own words. `-tiktokLiveProbe`
/// prints the keys and one raw notice, so the first real like is a one-launch
/// correction rather than a guess.
enum TikTokLiveFeed {
    /// Starts with `tiktok:` on purpose: `ImportRemoval.hasLiveHalf` asks
    /// whether a live prefix begins with the SOURCE's own name, and that is
    /// what keeps "Remove import" from deleting the notices. Distinct from
    /// every `tiktok:video:` / `tiktok:post:` / `tiktok:comment:` the export
    /// writes, so a notice about a video never shares a row with the video.
    static let refPrefix = "tiktok:live:notif:"

    /// The Activity panel's own list — see the header for what is and is not
    /// known about it.
    static let activityGroup = 500
    static let pageSize = 20

    /// The body's code for a session TikTok no longer honours (measured: the
    /// same read with no cookies).
    static let expiredStatusCode = 8

    /// A desktop Safari agent, for the sign-in sheet AND every request. The
    /// desktop site is the one measured; the phone site steers a sign-in
    /// toward the app. One constant, so the cookies and the reads always
    /// claim the same browser.
    static let desktopUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"

    static let loginURL = "https://www.tiktok.com/login"
    static let accountInfoURL = "https://www.tiktok.com/passport/web/account/info/?aid=1988"

    /// `is_mark_read` is 0 and is never a parameter: a read that marked the
    /// inbox read would clear the badge on the person's own phone.
    static func inboxURL(group: Int = activityGroup, count: Int = pageSize,
                         path: String = "/api/notice/multi/") -> String {
        let groups = "[{\"count\":\(count),\"is_mark_read\":0,\"group\":\(group),\"max_time\":0,\"min_time\":0}]"
        var parts = URLComponents()
        parts.scheme = "https"
        parts.host = "www.tiktok.com"
        parts.path = path
        parts.queryItems = [
            URLQueryItem(name: "aid", value: "1988"),
            URLQueryItem(name: "app_name", value: "tiktok_web"),
            URLQueryItem(name: "device_platform", value: "web_pc"),
            URLQueryItem(name: "group_list", value: groups),
        ]
        // `URLComponents` leaves `,` and `:` bare inside a query value, and
        // TikTok's own page encodes them; match the page.
        let encoded = parts.percentEncodedQuery?
            .replacingOccurrences(of: ",", with: "%2C")
            .replacingOccurrences(of: ":", with: "%3A")
        parts.percentEncodedQuery = encoded
        return parts.string ?? ""
    }

    /// The cookie jar a sign-in left, as one header. Nil until `sessionid` is
    /// in it: the jar holds a dozen cookies for a signed-OUT visitor too, and
    /// only a completed sign-in writes the session.
    static func cookieHeader(_ cookies: [(name: String, value: String)]) -> String? {
        var seen = Set<String>()
        var pairs: [String] = []
        for cookie in cookies where !cookie.value.isEmpty && !seen.contains(cookie.name) {
            seen.insert(cookie.name)
            pairs.append("\(cookie.name)=\(cookie.value)")
        }
        guard seen.contains("sessionid") else { return nil }
        return pairs.joined(separator: "; ")
    }

    enum Failure: Equatable {
        case noSession
        /// 401/403, or a 200 whose `status_code` is 8. The ONLY case that may
        /// clear the stored cookies (§711).
        case refused(Int)
        /// 429 — asked too often. Not a refusal (§711b).
        case throttled
        /// No HTTP response at all.
        case unreachable
        /// A body this file does not know — including a non-zero code other
        /// than 8, because nothing measured says what those mean.
        case drifted
    }

    static func classify(status: Int, json: Any?) -> Failure? {
        switch status {
        case 0: return .unreachable
        case 401, 403: return .refused(status)
        case 429: return .throttled
        case 200:
            guard let root = json as? [String: Any] else { return .drifted }
            let code = (root["status_code"] as? Int) ?? (root["statusCode"] as? Int)
            if code == expiredStatusCode { return .refused(200) }
            guard code == 0, root["notice_lists"] is [[String: Any]] else { return .drifted }
            return nil
        default: return .drifted
        }
    }

    static func describe(_ failure: Failure) -> String {
        switch failure {
        case .noSession: return "not signed in"
        case .refused(let s): return "refused (\(s)) — the session is gone, sign in again"
        case .throttled: return "throttled — asked too often, try later"
        case .unreachable: return "unreachable — check the connection"
        case .drifted: return "unexpected shape — the web app's response changed"
        }
    }

    /// The signed-in handle, from the passport's account read (measured:
    /// `message: "success"` and a `data.username` when signed in; `"error"`
    /// with `error_code` 13 when not).
    static func username(_ json: Any?) -> String? {
        guard let root = json as? [String: Any], root["message"] as? String == "success",
              let data = root["data"] as? [String: Any],
              let name = data["username"] as? String, !name.isEmpty else { return nil }
        return name
    }

    // MARK: - Notices

    struct Notice: Equatable {
        var id: String
        var type: Int?
        /// Which payload the notice carried — `digg`, `comment`, `follow`,
        /// `at`, `text`, `announcement`, `template_notice`, or something new.
        var kind: String
        var text: String
        var at: Date
        var actorHandle: String?
        var actorName: String?
        var actorAvatar: String?
        var videoID: String?
        var videoAuthor: String?
        var videoCaption: String?
        var videoCover: String?
        /// A payload's own `https` link, when it has one.
        var link: String?

        var isFollow: Bool { kind == "follow" }

        /// The video, when the notice names one and its maker; the actor's
        /// page for a follow; the payload's own link; TikTok itself — never a
        /// guessed video.
        var permalink: String {
            if let id = videoID, let author = videoAuthor {
                return "https://www.tiktok.com/@\(author)/video/\(id)"
            }
            if isFollow, let handle = actorHandle { return "https://www.tiktok.com/@\(handle)" }
            if let link { return link }
            if let handle = actorHandle { return "https://www.tiktok.com/@\(handle)" }
            return "https://www.tiktok.com/"
        }
    }

    static func notices(_ json: Any?) -> [Notice]? {
        guard let root = json as? [String: Any],
              let lists = root["notice_lists"] as? [[String: Any]] else { return nil }
        return lists.flatMap { ($0["notice_list"] as? [[String: Any]]) ?? [] }.compactMap(notice(from:))
    }

    /// The payloads this file reads by name, in the order a notice carrying
    /// two is read. Anything else falls to the first dictionary it holds.
    static let knownPayloads = ["comment", "digg", "follow", "at", "text", "announcement", "template_notice"]
    private static let metaKeys: Set<String> = ["nid", "nid_str", "type", "create_time", "has_read",
                                                "display_type", "user_id", "extra", "log_pb"]

    static func notice(from item: [String: Any]) -> Notice? {
        guard let id = string(item["nid_str"]) ?? string(item["nid"]) else { return nil }
        let payloadKey = knownPayloads.first { item[$0] is [String: Any] }
            ?? item.keys.sorted().first { !metaKeys.contains($0) && item[$0] is [String: Any] }
        guard let payloadKey, let payload = item[payloadKey] as? [String: Any] else { return nil }

        let comment = payload["comment"] as? [String: Any]
        let actor = user(in: payload) ?? comment.flatMap { $0["user"] as? [String: Any] }
        let video = (payload["aweme"] as? [String: Any]) ?? (payload["aweme_info"] as? [String: Any])
            ?? (comment?["aweme"] as? [String: Any])
        let handle = actor.flatMap { string($0["unique_id"]) }
        let name = actor.flatMap { string($0["nickname"]) }

        let inner = payload["notice"] as? [String: Any]
        let own = [payload["content"], inner?["content"], payload["title"], inner?["title"]]
            .lazy.compactMap { string($0)?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        let who = name ?? handle.map { "@\($0)" }
        // TikTok's own words where it gave any. Where it gave none, the one
        // sentence the payload's NAME states — never an invented detail.
        let text: String? = own ?? {
            let said = comment.flatMap { string($0["text"]) }
            switch payloadKey {
            case "digg": return who.map { "\($0) liked your video" } ?? "Liked your video"
            case "follow": return who.map { "\($0) followed you" } ?? "New follower"
            case "at": return who.map { "\($0) mentioned you" } ?? "Mentioned you"
            case "comment":
                guard let said else { return who.map { "\($0) commented" } }
                return who.map { "\($0): \(said)" } ?? said
            default: return nil
            }
        }()
        guard let text, !text.isEmpty else { return nil }

        let stamp = (item["create_time"] as? Double) ?? (item["create_time"] as? Int).map(Double.init)
        let link = [payload["schema_url"], payload["web_url"], payload["url"]]
            .lazy.compactMap(string).first { $0.hasPrefix("https://") }
        return Notice(
            id: id,
            type: item["type"] as? Int,
            kind: payloadKey,
            text: text,
            at: stamp.map { Date(timeIntervalSince1970: $0) } ?? .now,
            actorHandle: handle,
            actorName: name,
            actorAvatar: actor.flatMap(avatar(of:)),
            videoID: video.flatMap { string($0["aweme_id"]) },
            videoAuthor: video.flatMap { ($0["author"] as? [String: Any]).flatMap { string($0["unique_id"]) } },
            videoCaption: video.flatMap { string($0["desc"]) },
            videoCover: video.flatMap { firstURL(($0["video"] as? [String: Any])?["cover"]) },
            link: link)
    }

    /// The person who acted: a lone user, or the first of a list (a like
    /// notice groups several likers under one id).
    private static func user(in payload: [String: Any]) -> [String: Any]? {
        for key in ["from_user", "user", "user_info", "from_users", "users"] {
            if let one = payload[key] as? [String: Any] { return one }
            if let many = payload[key] as? [[String: Any]], let first = many.first { return first }
        }
        return nil
    }

    private static func avatar(of user: [String: Any]) -> String? {
        for key in ["avatar_thumb", "avatar_168x168", "avatar_medium", "avatar_larger"] {
            if let url = firstURL(user[key]) { return url }
        }
        return nil
    }

    /// TikTok's image object: `{ "url_list": ["https://…", …] }`.
    private static func firstURL(_ any: Any?) -> String? {
        ((any as? [String: Any])?["url_list"] as? [String])?.first { $0.hasPrefix("https://") }
    }

    private static func string(_ any: Any?) -> String? {
        if let s = any as? String { return s.isEmpty ? nil : s }
        if let n = any as? NSNumber { return n.stringValue }
        return nil
    }
}
