import Foundation
import SwiftData

/// TikTok's Activity inbox, read with the person's OWN web-session cookies
/// (prd §731) — §726's Instagram door, one seat over, and simpler: the reads
/// need no signature and no app id, only the cookies a sign-in left. The pure
/// parse and everything measured about it are in `TikTokLiveFeed`.
///
/// Nothing is extracted from TikTok's app or its page scripts, and nothing
/// signs a request. The cookies come from an in-app `WKWebView` the person
/// signs into (`TikTokLiveLoginSheet`) and go back to the same two paths the
/// page itself calls.
enum TikTokLiveAuth {
    private static let cookieVaultKey = "tiktok.live.cookies"
    /// Not a secret — the signed-in handle, learnt from the passport read.
    private static let usernameKey = "tiktok.live.username"

    static var cookieHeader: String? {
        TokenVault.get(cookieVaultKey).flatMap { $0.isEmpty ? nil : $0 }
    }

    static var connected: Bool { cookieHeader != nil }

    static func store(cookieHeader: String) {
        // A new sign-in may be a different account: its name is learnt again.
        UserDefaults.standard.removeObject(forKey: usernameKey)
        TokenVault.set(cookieHeader, for: cookieVaultKey)
    }

    /// Clears the live session only — an imported export's rows and every
    /// notice already landed are untouched (2026-07-13's two verbs).
    static func clear() {
        TokenVault.delete(cookieVaultKey)
        UserDefaults.standard.removeObject(forKey: usernameKey)
    }

    static var username: String? {
        UserDefaults.standard.string(forKey: usernameKey).flatMap { $0.isEmpty ? nil : $0 }
    }

    static func remember(username: String) {
        guard !username.isEmpty else { return }
        UserDefaults.standard.set(username, forKey: usernameKey)
    }
}

enum TikTokLive {
    @MainActor private static var running = false

    /// Lands new notices. nil = couldn't run (not signed in, or the read
    /// failed); 0 or more = a real read, however many were new. A refusal —
    /// and only a refusal — clears the session, so the page falls back to
    /// Connect instead of saying "signed in" over a dead cookie (§711).
    @MainActor
    @discardableResult
    static func refresh(context: ModelContext) async -> Int? {
        guard let cookies = TikTokLiveAuth.cookieHeader else { return nil }
        guard !running else { return 0 }
        running = true
        defer { running = false }

        await learnUsernameIfNeeded(cookies: cookies)
        let reply = await get(TikTokLiveFeed.inboxURL(), cookies: cookies)
        if let failure = TikTokLiveFeed.classify(status: reply.status, json: reply.json) {
            if case .refused = failure { TikTokLiveAuth.clear() }
            return nil
        }
        guard let notices = TikTokLiveFeed.notices(reply.json) else { return nil }
        return land(notices, context: context)
    }

    @MainActor
    private static func land(_ notices: [TikTokLiveFeed.Notice], context: ModelContext) -> Int {
        let landed = landedNotices(context: context)
        var added = 0
        var healed = 0
        for notice in notices {
            let ref = TikTokLiveFeed.refPrefix + notice.id
            if let existing = landed[ref] {
                // A notice is never re-sent, so this page is the only chance a
                // row landed by an earlier build gets its face and its picture
                // (§704/§707's backfills, the same reason).
                var touched = false
                if existing.authorAvatarURL == nil, let avatar = notice.actorAvatar {
                    existing.authorAvatarURL = avatar
                    if existing.authorHandle == nil { existing.authorHandle = notice.actorHandle }
                    touched = true
                }
                if existing.previewImageURL == nil, let cover = notice.videoCover {
                    existing.previewImageURL = cover
                    existing.imageURLs = [cover]
                    touched = true
                }
                if touched { healed += 1 }
                continue
            }
            let thing = thing(from: notice, ref: ref)
            context.insert(thing)
            SpotlightIndex.index([thing])
            added += 1
        }
        if added > 0 || healed > 0 { context.saveHonestly() }
        return added
    }

    /// The notices already here, scoped by PREFIX: an export is thousands of
    /// rows and the inbox is twenty.
    @MainActor
    private static func landedNotices(context: ModelContext) -> [String: Thing] {
        let prefix = TikTokLiveFeed.refPrefix
        let descriptor = FetchDescriptor<Thing>(predicate: #Predicate {
            $0.source == "TikTok" && ($0.sourceRef?.starts(with: prefix) ?? false)
        })
        var map: [String: Thing] = [:]
        for thing in (try? context.fetch(descriptor)) ?? [] {
            if let ref = thing.sourceRef { map[ref] = thing }
        }
        return map
    }

    private static func thing(from notice: TikTokLiveFeed.Notice, ref: String) -> Thing {
        let thing = Thing(
            kind: .link,
            title: IngestSupport.titleLine(IngestSupport.decodeHTMLEntities(notice.text)),
            content: notice.permalink,
            source: TikTokImport.source,
            capturedAt: notice.at,
            sourceRef: ref)
        // WHO ACTED (§707): the face is the person who liked, commented or
        // followed — never the source mark, never you.
        if let handle = notice.actorHandle { thing.authorHandle = handle }
        if let avatar = notice.actorAvatar { thing.authorAvatarURL = avatar }
        if notice.isFollow { thing.socialContext = "follow" }
        if let cover = notice.videoCover {
            thing.imageURLs = [cover]
            thing.previewImageURL = cover
        }
        // THE VIDEO THE NOTICE IS ABOUT, as a card — only when the notice
        // names its maker and there is something under the name (§704: a card
        // that is a handle over nothing claims a preview that isn't there).
        if let author = notice.videoAuthor, notice.videoCaption != nil || notice.videoCover != nil {
            thing.quote = SocialCard(handle: author, text: notice.videoCaption ?? "",
                                     avatarURL: nil, url: notice.permalink)
        }
        return thing
    }

    // MARK: - The request

    private static func learnUsernameIfNeeded(cookies: String) async {
        guard TikTokLiveAuth.username == nil else { return }
        let reply = await get(TikTokLiveFeed.accountInfoURL, cookies: cookies)
        if let name = TikTokLiveFeed.username(reply.json) { TikTokLiveAuth.remember(username: name) }
    }

    /// `getJSONBody`: a dead session is a 200 whose BODY says so, and the
    /// status alone would read it as an empty inbox.
    private static func get(_ url: String, cookies: String) async -> (json: Any?, status: Int) {
        await IngestSupport.getJSONBody(url, headers: headers(cookies), service: "TikTok")
    }

    /// What the page sends and nothing it doesn't — minus the signatures,
    /// which the reads were measured not to need.
    static func headers(_ cookies: String) -> [String: String] {
        [
            "Cookie": cookies,
            "User-Agent": TikTokLiveFeed.desktopUserAgent,
            "Referer": "https://www.tiktok.com/",
            "Accept": "application/json, text/plain, */*",
        ]
    }

    // MARK: - Diagnose

    /// The chain, link by link: stored / signed in as / inbox status and code
    /// / notices parsed / first three / one raw notice / every group's count.
    /// The group scan is here because group 500 is the panel's own request
    /// and nothing more is known — the first account with likes answers which
    /// group holds them. Never prints a cookie.
    @MainActor
    static func diagnose() async {
        guard let cookies = TikTokLiveAuth.cookieHeader else {
            NSLog("[Casberi] tiktokLive| not signed in — connect from the TikTok account page first")
            return
        }
        let names = cookies.split(separator: ";").compactMap {
            $0.split(separator: "=").first.map { $0.trimmingCharacters(in: .whitespaces) }
        }
        NSLog("[Casberi] tiktokLive| session stored — cookie names: %@", names.joined(separator: ", "))
        await learnUsernameIfNeeded(cookies: cookies)
        NSLog("[Casberi] tiktokLive| signed in as %@", TikTokLiveAuth.username ?? "(unknown — the passport read gave no username)")

        let reply = await get(TikTokLiveFeed.inboxURL(), cookies: cookies)
        let root = reply.json as? [String: Any]
        NSLog("[Casberi] tiktokLive| inbox HTTP %d code=%@ msg=%@%@", reply.status,
              root.flatMap { $0["status_code"] }.map { "\($0)" } ?? "—",
              (root?["status_msg"] as? String) ?? "—",
              TikTokLiveFeed.classify(status: reply.status, json: reply.json)
                .map { " — \(TikTokLiveFeed.describe($0))" } ?? "")
        let items = ((root?["notice_lists"] as? [[String: Any]]) ?? [])
            .flatMap { ($0["notice_list"] as? [[String: Any]]) ?? [] }
        NSLog("[Casberi] tiktokLive| %d notices on the page, %d parsed", items.count,
              TikTokLiveFeed.notices(reply.json)?.count ?? 0)
        for item in items.prefix(3) {
            if let n = TikTokLiveFeed.notice(from: item) {
                NSLog("[Casberi] tiktokLiveNotice| id=%@ kind=%@ type=%@ text=%@ actor=%@ face=%@ video=%@ cover=%@",
                      n.id, n.kind, n.type.map { "\($0)" } ?? "—", String(n.text.prefix(80)),
                      n.actorHandle ?? "MISSING", n.actorAvatar == nil ? "no" : "yes",
                      n.videoID ?? "none", n.videoCover == nil ? "no" : "yes")
            } else {
                NSLog("[Casberi] tiktokLiveNotice| unparsed — keys %@", item.keys.sorted().joined(separator: ", "))
            }
        }
        if let first = items.first,
           let data = try? JSONSerialization.data(withJSONObject: first),
           let body = String(data: data.prefix(1500), encoding: .utf8) {
            NSLog("[Casberi] tiktokLiveNoticeRaw| %@", body)
        }
        for group in [0, 1, 20, 36, 500, 661] {
            for path in ["/api/notice/multi/", "/api/inbox/notice_list/"] {
                let r = await get(TikTokLiveFeed.inboxURL(group: group, path: path), cookies: cookies)
                let lists = ((r.json as? [String: Any])?["notice_lists"] as? [[String: Any]]) ?? []
                let shape = lists.map { l -> String in
                    let kinds = Set(((l["notice_list"] as? [[String: Any]]) ?? []).compactMap {
                        TikTokLiveFeed.notice(from: $0)?.kind
                    })
                    return "\(l["group"].map { "\($0)" } ?? "?"):\((l["notice_list"] as? [Any])?.count ?? 0)[\(kinds.sorted().joined(separator: "/"))]"
                }
                NSLog("[Casberi] tiktokLiveGroup| %@ g%d HTTP %d %@", path, group, r.status,
                      shape.isEmpty ? "(none)" : shape.joined(separator: " "))
            }
        }
    }
}
