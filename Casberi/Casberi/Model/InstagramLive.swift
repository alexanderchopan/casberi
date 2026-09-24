import Foundation
import SwiftData

/// Instagram's own INTERNAL web API, read with the person's OWN browser-session
/// cookies (prd §726) — §701's X door, one seat over. §245 stands: a personal
/// account has no API, the export is the only bulk door, and nothing here
/// changes that. What this asks is §701's narrower question — can this app
/// read *your own* activity the way your own browser already does, with the
/// session your own sign-in already holds? Yes, for the one account signed in.
///
/// **What this is, precisely.** `sessionid`, `csrftoken` and `ds_user_id` are
/// the cookies instagram.com's own web app sets on an ordinary sign-in.
/// `InstagramLiveLoginSheet` harvests them from an in-app `WKWebView` the
/// person signs into directly; every request below carries them back the way
/// a browser tab would, under the web app's own PUBLIC app id (`X-IG-App-ID`,
/// embedded in every page load for every visitor — an identifier, not a
/// secret). Nothing is extracted from Meta's app binary and nothing signs a
/// request the way the official app would — §701's own line between "your
/// browser's cookies" and "an impersonated client" holds here exactly.
///
/// **Meta flags harder than X or Spotify, and that is stated before the tap.**
/// A read Meta dislikes can put a "suspicious login" checkpoint on the
/// person's REAL account until they re-verify in the Instagram app — a cost
/// to them, not to this app. Two rules follow: the sweep reads on
/// `BridgeRefresh.dueForHeal`'s ten-minute throttle rather than every
/// foreground, and a checkpoint or a throttle NEVER clears the cookies
/// (§711's lesson: only a refusal is grounds to demand the whole sign-in
/// again, and Instagram's checkpoint is a 400 with a `checkpoint_url`, not a
/// 401).
///
/// **Two reads, one session.** Notifications (`/api/v1/news/inbox/`) land
/// under their own ref namespace, `ig-live:notif:`, X's `x-live:notif:`
/// reasoning verbatim. Saved posts (`/api/v1/feed/saved/posts/`) land under
/// the IMPORT's namespace, `instagram:saved:<permalink>`, and that is the
/// opposite decision for the opposite reason: a saved post read live and the
/// same post read out of the export are ONE object, and §245's whole finding
/// was that the export hands over a pointer where this read hands over the
/// post — so a live save dedupes against an imported one by shortcode, and an
/// imported pointer already here is FILLED with the words and the picture the
/// live read carries. `InstagramCaptions` never re-fetches a row this fills:
/// `enrichedText` is its cursor and this stamps it.
///
/// **UNMEASURED, in this codebase's own sense of the word** (`TrelloAuth`,
/// `XLiveNotifications`): authored against the publicly documented shape of
/// Instagram's web-app responses, with no live session reachable from this
/// build host. Every parse fails to nil/empty rather than guessing, so a shape
/// drift lands nothing rather than something wrong, and `diagnose()` names
/// which link broke in one launch.
enum InstagramLiveAuth {
    private static let sessionVaultKey = "instagram.live.sessionid"
    private static let csrfVaultKey = "instagram.live.csrftoken"
    private static let userVaultKey = "instagram.live.dsUserID"
    /// Not a secret — the signed-in account's own handle, learnt once from
    /// `/api/v1/users/<ds_user_id>/info/` so a like on "your post" can name
    /// whose post it is. Keyed on the user id, so a different account signing
    /// in never inherits the last one's name.
    private static let usernameKey = "instagram.live.username"

    struct Session: Equatable {
        var sessionID: String
        var csrfToken: String
        var userID: String
    }

    /// All three or none — `TrelloAuth`'s shape, three wide: `sessionid` alone
    /// is refused by the CSRF check every web call enforces (`X-CSRFToken`
    /// must equal the `csrftoken` cookie), and `ds_user_id` is the only way to
    /// ask who is signed in without a request that guesses.
    static var stored: Session? {
        guard let s = TokenVault.get(sessionVaultKey), !s.isEmpty,
              let c = TokenVault.get(csrfVaultKey), !c.isEmpty,
              let u = TokenVault.get(userVaultKey), !u.isEmpty
        else { return nil }
        return Session(sessionID: s, csrfToken: c, userID: u)
    }

    static var connected: Bool { stored != nil }

    static func store(sessionID: String, csrfToken: String, userID: String) {
        // A different account than last time: its name is not this one's.
        if TokenVault.get(userVaultKey) != userID {
            UserDefaults.standard.removeObject(forKey: usernameKey)
        }
        TokenVault.set(sessionID, for: sessionVaultKey)
        TokenVault.set(csrfToken, for: csrfVaultKey)
        TokenVault.set(userID, for: userVaultKey)
    }

    /// Clears the live session only — an imported export's rows, and every
    /// saved post the live read landed, are untouched: "delete things" and
    /// "delete access" are two verbs (2026-07-13).
    static func clear() {
        TokenVault.delete(sessionVaultKey)
        TokenVault.delete(csrfVaultKey)
        TokenVault.delete(userVaultKey)
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

enum InstagramLive {
    /// Distinct from EVERY `instagram:` ref the importer writes, on purpose —
    /// `XLiveNotifications.sourceRefPrefix`'s reasoning: a notice about a post
    /// and the post itself can share an id and must never share a row.
    ///
    /// **Spelled a second time in `Corpus.liveRefPrefixesBySource`, under
    /// "Instagram" (prd §733)**, and the two must match: that entry is what
    /// lets a notice into All, keeps the sheet from calling it an archive row,
    /// and keeps "Remove import" from counting it. `social-sheet-selftest.sh`
    /// holds the two spellings together.
    static let noticeRefPrefix = "ig-live:notif:"
    /// SHARED with `InstagramImport.landSaves` on purpose — see the header. A
    /// live save and an imported save of the same post are one thing.
    static let savedRefPrefix = "instagram:saved:"

    /// The web app's own PUBLIC application id — the value every visitor's
    /// page load carries in `X-IG-App-ID`, unauthenticated and unchanged for
    /// years. An identifier, not a credential; the secret scan is right not to
    /// flag it.
    static let webAppID = "936619743392459"
    /// Its companion header, equally public. Requests without it are answered
    /// with a 400 on some paths, which reads as a shape drift and is not one.
    static let asbdID = "129477"

    static let base = "https://www.instagram.com/api/v1"

    /// How many saved posts one pass asks for. One page, never paged — the
    /// export is the bulk door (§245); this is the live one, and a live door
    /// carries what is recent.
    static let savedPageSize = 24

    /// Which link of the chain broke, for the probe and the page — §711's
    /// `SpotifyAuth.Failure`, because "connected and reading nothing" has five
    /// causes that all render as one silence.
    enum Failure: Equatable {
        /// Not signed in here at all.
        case noSession
        /// 401/403, or a 200/400 whose body says `login_required`: the session
        /// is gone and the sign-in is owed again. The ONLY case that may clear
        /// the stored cookies.
        case refused(Int)
        /// Meta wants the person to re-verify in their own app. The cookies
        /// are still good; clearing them would make a one-tap fix a whole
        /// sign-in.
        case checkpoint
        /// 429 — asked too often. Not a refusal (§711b).
        case throttled
        /// No HTTP response at all.
        case unreachable
        /// A 200 whose body is not the shape this file knows.
        case drifted
    }

    @MainActor private static var running = false

    /// Lands new notifications and new saved posts, and fills any imported
    /// save whose words and picture this read carries. nil = couldn't run
    /// (not signed in, or the inbox read failed outright); 0 or more = a real
    /// read, however many were new. The saved read failing on its own does not
    /// fail the pass: the two are independent endpoints and the notices are
    /// the news.
    @MainActor
    @discardableResult
    static func refresh(context: ModelContext) async -> Int? {
        guard let auth = InstagramLiveAuth.stored else { return nil }
        guard !running else { return 0 }
        running = true
        defer { running = false }

        await learnUsernameIfNeeded(auth: auth)

        let inbox = await get("\(base)/news/inbox/", auth: auth)
        guard inbox.status == 200, let stories = stories(inbox.json) else {
            forgetSessionIfRefused(inbox)
            return nil
        }
        var added = landNotices(stories, context: context)

        let saved = await get("\(base)/feed/saved/posts/?count=\(savedPageSize)", auth: auth)
        if saved.status == 200, let items = savedMedia(saved.json) {
            added += landSaves(items, context: context)
        }
        return added
    }

    /// A refusal, and ONLY a refusal, clears the session — so the account page
    /// says "Needs reconnecting" (through `BridgeHealth`, which the funnel
    /// already stamped on the 401/403) and the next tap is a sign-in, not a
    /// silent hour of nothing (§711). A checkpoint keeps the cookies: the fix
    /// is in the person's Instagram app, and the cookies work again after it.
    private static func forgetSessionIfRefused(_ reply: (json: Any?, status: Int)) {
        guard case .refused = classify(reply) else { return }
        InstagramLiveAuth.clear()
    }

    static func classify(_ reply: (json: Any?, status: Int)) -> Failure? {
        let message = (reply.json as? [String: Any])?["message"] as? String
        switch reply.status {
        case 200:
            return message == "login_required" ? .refused(200) : nil
        case 401, 403:
            return .refused(reply.status)
        case 400:
            if message == "checkpoint_required" { return .checkpoint }
            if message == "login_required" { return .refused(400) }
            return .drifted
        case 429:
            return .throttled
        case 0:
            return .unreachable
        default:
            return .drifted
        }
    }

    // MARK: - Notifications

    @MainActor
    private static func landNotices(_ stories: [[String: Any]], context: ModelContext) -> Int {
        let landed = landedNotices(context: context)
        var added = 0
        var healed = 0
        for story in stories {
            guard let notice = notice(from: story) else { continue }
            let ref = noticeRefPrefix + notice.id
            if let existing = landed[ref] {
                // The same two backfills X's notices take (§704, §707), for
                // the same reason: a notice is never re-sent, so the inbox's
                // own page is the only chance a row landed by an earlier build
                // gets at its face and its picture.
                var touched = false
                if existing.authorAvatarURL == nil, let avatar = notice.actorAvatar {
                    existing.authorAvatarURL = avatar
                    if existing.authorHandle == nil { existing.authorHandle = notice.actorName }
                    touched = true
                }
                if existing.previewImageURL == nil, let image = notice.mediaImage {
                    existing.previewImageURL = image
                    existing.imageURLs = [image]
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

    /// The notices already here, by ref — scoped by PREFIX, not by source:
    /// an Instagram export is thousands of rows and the inbox is a few dozen.
    @MainActor
    private static func landedNotices(context: ModelContext) -> [String: Thing] {
        let prefix = noticeRefPrefix
        let descriptor = FetchDescriptor<Thing>(predicate: #Predicate {
            $0.source == "Instagram" && ($0.sourceRef?.starts(with: prefix) ?? false)
        })
        var map: [String: Thing] = [:]
        for thing in (try? context.fetch(descriptor)) ?? [] {
            if let ref = thing.sourceRef { map[ref] = thing }
        }
        return map
    }

    /// One inbox story, read down to what a row and a sheet draw.
    struct Notice: Equatable {
        var id: String
        var text: String
        var at: Date
        var actorName: String?
        var actorAvatar: String?
        /// The post the notice is about, when the story names one — as the
        /// numeric media id Instagram uses internally and the picture it
        /// hands over beside it.
        var mediaID: String?
        var mediaImage: String?
        /// A follow names a person and no post.
        var isFollow: Bool
    }

    /// `new_stories` then `old_stories` — the two halves Instagram's own
    /// activity page draws as "New" and "Earlier". Both are read; a story that
    /// moved from one to the other between passes is the same story and the
    /// ref dedupe treats it so.
    static func stories(_ json: Any?) -> [[String: Any]]? {
        guard let root = json as? [String: Any] else { return nil }
        let new = root["new_stories"] as? [[String: Any]]
        let old = root["old_stories"] as? [[String: Any]]
        guard new != nil || old != nil else { return nil }
        return (new ?? []) + (old ?? [])
    }

    static func notice(from story: [String: Any]) -> Notice? {
        guard let args = story["args"] as? [String: Any],
              let text = (args["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty
        else { return nil }
        // `pk` is the story's own id and is what Instagram's web app keys the
        // row on; `tuuid` is its fallback there too.
        let id = stringValue(story["pk"]) ?? (args["tuuid"] as? String)
        guard let id, !id.isEmpty else { return nil }
        let stamp = (args["timestamp"] as? Double) ?? (args["timestamp"] as? Int).map(Double.init)
        let media = (args["media"] as? [[String: Any]])?.first
        let storyType = (story["story_type"] as? Int) ?? (story["type"] as? Int)
        // A follow has an `inline_follow` block and no media; the type code
        // (3 on the documented shape) is read only as a second witness.
        let isFollow = args["inline_follow"] != nil || (media == nil && storyType == 3)
        return Notice(
            id: id,
            text: text,
            at: stamp.map { Date(timeIntervalSince1970: $0) } ?? .now,
            actorName: (args["profile_name"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            actorAvatar: (args["profile_image"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            mediaID: media.flatMap { stringValue($0["id"]) },
            mediaImage: (media?["image"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            isFollow: isFollow)
    }

    /// The web permalink for a notice. A post, when the story names one; the
    /// actor's own page when the story names a person and no post (a follow,
    /// and since prd §912 any media-less notice with a `profile_name` — the
    /// activity root said nothing about WHO); the activity page itself when
    /// neither — never a guessed post.
    static func permalink(for notice: Notice) -> String {
        if let code = notice.mediaID.flatMap(shortcode(fromMediaID:)) {
            return "https://www.instagram.com/p/\(code)/"
        }
        if let name = notice.actorName {
            return "https://www.instagram.com/\(name)/"
        }
        return "https://www.instagram.com/accounts/activity/"
    }

    /// Instagram's shortcode IS its media id, written in a 64-symbol alphabet
    /// — the same deterministic mapping every open-source client uses
    /// (`instaloader.mediaid_to_shortcode`). `3123456789012345678_123456` is
    /// `<media>_<owner>`; only the media half encodes.
    static func shortcode(fromMediaID mediaID: String) -> String? {
        let numeric = mediaID.split(separator: "_").first.map(String.init) ?? mediaID
        guard var n = UInt64(numeric), n > 0 else { return nil }
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        var out: [Character] = []
        while n > 0 {
            out.append(alphabet[Int(n % 64)])
            n /= 64
        }
        return String(out.reversed())
    }

    private static func thing(from notice: Notice, ref: String) -> Thing {
        let words = IngestSupport.decodeHTMLEntities(notice.text)
        let title = IngestSupport.titleLine(words)
        let thing = Thing(
            kind: .link,
            title: title,
            content: permalink(for: notice),
            source: "Instagram",
            capturedAt: notice.at,
            sourceRef: ref)
        // The whole notice where the title line cut it (prd §912) — a
        // comment's words past 80 characters were gone from every screen.
        // Compared as strings, not counts: the clamp's ellipsis makes an
        // 81-character text and its cut the same length.
        if words != title { thing.summary = words }
        // WHO ACTED (§707's ruling): the face on the row is the person who
        // liked, commented or followed — never the source mark, never you.
        if let name = notice.actorName { thing.authorHandle = name }
        if let avatar = notice.actorAvatar { thing.authorAvatarURL = avatar }
        if notice.isFollow { thing.socialContext = "follow" }
        // THE POST THE NOTICE IS ABOUT (§704) — its picture, and NO `quote`
        // card. The inbox never hands over the post's caption or its author,
        // so a card would be a handle over nothing (the case
        // `XLiveNotifications.fill` refuses), and the only handle this read
        // knows is yours — which is wrong for "replied to your comment" on
        // somebody else's post. The picture is true; a guessed author is not.
        if let image = notice.mediaImage {
            thing.imageURLs = [image]
            thing.previewImageURL = image
        }
        return thing
    }

    // MARK: - Saved posts

    @MainActor
    private static func landSaves(_ items: [[String: Any]], context: ModelContext) -> Int {
        let stored = landedSaves(context: context)
        var added = 0
        var filled = 0
        for media in items {
            guard let save = save(from: media) else { continue }
            if let existing = stored[save.code] {
                // §245's pointer, filled: an imported save is a handle and a
                // permalink, and this is the post. Every field the caption
                // heal would have scraped for, from the read that already has
                // them — and `enrichedText` is that heal's cursor, so a filled
                // row drops out of its queue. `isLive`: a CloudKit delete can
                // tombstone a row between the fetch and this write.
                if existing.isLive, fill(existing, with: save) { filled += 1 }
                continue
            }
            let thing = thing(from: save)
            context.insert(thing)
            SpotlightIndex.index([thing])
            added += 1
        }
        if added > 0 || filled > 0 { context.saveHonestly() }
        return added
    }

    /// Every save already here, by SHORTCODE — the import writes its ref off
    /// Meta's own href, which spells a reel `/reel/<code>/` and a post
    /// `/p/<code>/`, with and without `www`, so the ref string itself is not a
    /// stable key across the two doors. The code is.
    @MainActor
    private static func landedSaves(context: ModelContext) -> [String: Thing] {
        let prefix = savedRefPrefix
        let descriptor = FetchDescriptor<Thing>(predicate: #Predicate {
            $0.source == "Instagram" && ($0.sourceRef?.starts(with: prefix) ?? false)
        })
        var map: [String: Thing] = [:]
        for thing in (try? context.fetch(descriptor)) ?? [] {
            guard let ref = thing.sourceRef,
                  let code = shortcode(inPermalink: String(ref.dropFirst(prefix.count)))
            else { continue }
            map[code] = thing
        }
        return map
    }

    /// The `<code>` out of any Instagram permalink form the export or the web
    /// app writes — `/p/`, `/reel/`, `/reels/`, `/tv/`.
    static func shortcode(inPermalink link: String) -> String? {
        let parts = link.split(separator: "/").map(String.init)
        for (i, part) in parts.enumerated()
        where ["p", "reel", "reels", "tv"].contains(part.lowercased()) && i + 1 < parts.count {
            let code = parts[i + 1].split(separator: "?").first.map(String.init) ?? parts[i + 1]
            return code.isEmpty ? nil : code
        }
        return nil
    }

    struct Save: Equatable {
        var code: String
        var isReel: Bool
        var caption: String?
        var author: String?
        var avatar: String?
        var imageURLs: [String]
        var likes: Int?
        var comments: Int?
        var takenAt: Date?
        var permalink: String {
            "https://www.instagram.com/\(isReel ? "reel" : "p")/\(code)/"
        }
    }

    /// `items[].media` — the web app's saved feed wraps every post one level
    /// down, unlike the timeline. Only that shape is read.
    static func savedMedia(_ json: Any?) -> [[String: Any]]? {
        guard let root = json as? [String: Any],
              let items = root["items"] as? [[String: Any]] else { return nil }
        return items.compactMap { $0["media"] as? [String: Any] }
    }

    static func save(from media: [String: Any]) -> Save? {
        guard let code = media["code"] as? String, !code.isEmpty else { return nil }
        let user = media["user"] as? [String: Any]
        let caption = ((media["caption"] as? [String: Any])?["text"] as? String)
            .map { IngestSupport.decodeHTMLEntities($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }
        // A carousel's pictures are on its children; a single post's on itself.
        // Video posts carry their poster frame under the same key, so a reel
        // gets a cover without this claiming to play anything.
        let frames = (media["carousel_media"] as? [[String: Any]]) ?? [media]
        let images = frames.compactMap { frame -> String? in
            let candidates = (frame["image_versions2"] as? [String: Any])?["candidates"] as? [[String: Any]]
            return (candidates?.first?["url"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        }
        let taken = (media["taken_at"] as? Double) ?? (media["taken_at"] as? Int).map(Double.init)
        return Save(
            code: code,
            isReel: (media["product_type"] as? String) == "clips",
            caption: caption,
            author: (user?["username"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            avatar: (user?["profile_pic_url"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            imageURLs: images,
            likes: media["like_count"] as? Int,
            comments: media["comment_count"] as? Int,
            takenAt: taken.map { Date(timeIntervalSince1970: $0) })
    }

    private static func thing(from save: Save) -> Thing {
        // The words lead where there are any; the handle is the row's name
        // otherwise — the import's own fallback (`landSaves`), so the two doors
        // draw one shape.
        let name = save.caption ?? save.author.map { "@" + $0 } ?? save.permalink
        var tags = ["Saved"]
        if save.isReel { tags.append("Reel") }
        let thing = Thing(
            kind: .link,
            title: IngestSupport.titleLine(name),
            content: save.permalink,
            source: "Instagram",
            // When it reached this app, not when it was posted: the saved feed
            // does not say when you saved it, and "just arrived" is the truth
            // the row means.
            capturedAt: .now,
            tags: tags,
            sourceRef: savedRefPrefix + save.permalink)
        thing.socialContext = "saved"
        _ = fill(thing, with: save)
        return thing
    }

    /// The post onto the fields the room and the sheet draw — ONE function for
    /// a landing and a backfill, this file's standing rule. Mirrors what
    /// `InstagramCaptions.apply` writes for a scraped caption, field for field,
    /// so a save filled by either path is the same row: `postText` is what the
    /// card reads, `enrichedText` is retrieval and the heal's cursor, the title
    /// is the caption's first line.
    @discardableResult
    private static func fill(_ thing: Thing, with save: Save) -> Bool {
        var changed = false
        if let caption = save.caption {
            if thing.postText != caption { thing.postText = caption; changed = true }
            let retrieval = caption.count > 1200 ? String(caption.prefix(1200)) + "…" : caption
            if thing.enrichedText != retrieval { thing.enrichedText = retrieval; changed = true }
            let face = IngestSupport.titleLine(caption)
            if !face.isEmpty, thing.title != face { thing.title = face; changed = true }
        }
        if let author = save.author, thing.authorHandle != author {
            thing.authorHandle = author; changed = true
        }
        if let avatar = save.avatar, thing.authorAvatarURL != avatar {
            thing.authorAvatarURL = avatar; changed = true
        }
        if !save.imageURLs.isEmpty, thing.imageURLs != save.imageURLs {
            thing.imageURLs = save.imageURLs
            thing.previewImageURL = save.imageURLs.first
            changed = true
        }
        if let likes = save.likes, thing.likeCount != likes { thing.likeCount = likes; changed = true }
        if let comments = save.comments, thing.replyCount != comments {
            thing.replyCount = comments; changed = true
        }
        if changed { thing.embedding = nil }
        return changed
    }

    // MARK: - Who is signed in

    /// One request, once per account: the handle behind `ds_user_id`, so a
    /// notice about "your post" can name whose post it is. A miss costs
    /// nothing but that name — the pass runs without it.
    private static func learnUsernameIfNeeded(auth: InstagramLiveAuth.Session) async {
        guard InstagramLiveAuth.username == nil else { return }
        let reply = await get("\(base)/users/\(auth.userID)/info/", auth: auth)
        if let name = username(reply.json) { InstagramLiveAuth.remember(username: name) }
    }

    static func username(_ json: Any?) -> String? {
        guard let root = json as? [String: Any],
              let user = root["user"] as? [String: Any],
              let name = user["username"] as? String, !name.isEmpty else { return nil }
        return name
    }

    // MARK: - The request

    /// `getJSONBody`, never `getJSONStatus`: the error body IS the
    /// classification here. Instagram says `checkpoint_required` and
    /// `login_required` in a 400's `message`, and a helper that drops a
    /// non-200's body turns both into `.drifted` — so a checkpoint and a dead
    /// session would read alike and neither would ever clear or keep the
    /// cookies on purpose.
    private static func get(_ url: String, auth: InstagramLiveAuth.Session) async -> (json: Any?, status: Int) {
        await IngestSupport.getJSONBody(url, headers: headers(auth), service: "Instagram")
    }

    /// Exactly the headers instagram.com's own web app sends with the same
    /// call, and nothing it does not. The user agent is a browser's because a
    /// `CFNetwork` agent on a session cookie is the one signal that reads as
    /// automation to Meta; every other value is public.
    static func headers(_ auth: InstagramLiveAuth.Session) -> [String: String] {
        [
            "Cookie": "sessionid=\(auth.sessionID); csrftoken=\(auth.csrfToken); ds_user_id=\(auth.userID)",
            "X-CSRFToken": auth.csrfToken,
            "X-IG-App-ID": webAppID,
            "X-ASBD-ID": asbdID,
            "X-IG-WWW-Claim": "0",
            "X-Requested-With": "XMLHttpRequest",
            "Origin": "https://www.instagram.com",
            "Referer": "https://www.instagram.com/",
            "User-Agent": IngestSupport.safariUserAgent,
        ]
    }

    private static func stringValue(_ any: Any?) -> String? {
        if let s = any as? String { return s.isEmpty ? nil : s }
        if let n = any as? NSNumber { return n.stringValue }
        return nil
    }

    // MARK: - Diagnose

    /// The chain, link by link — `XLiveNotifications.diagnose`'s shape with
    /// `SpotifyAuth.Failure`'s naming: stored / who / inbox status and its
    /// `message` / stories parsed / first three / saved status / first three.
    /// Never prints a cookie.
    @MainActor
    static func diagnose() async {
        guard let auth = InstagramLiveAuth.stored else {
            NSLog("[Casberi] igLive| not signed in — connect from the Instagram account page first")
            return
        }
        NSLog("[Casberi] igLive| session stored for user id %@", auth.userID)
        await learnUsernameIfNeeded(auth: auth)
        NSLog("[Casberi] igLive| signed in as %@", InstagramLiveAuth.username ?? "(unknown — /users/<id>/info/ gave no username)")

        let inbox = await get("\(base)/news/inbox/", auth: auth)
        NSLog("[Casberi] igLive| inbox HTTP %d%@", inbox.status,
              classify(inbox).map { " — \(describe($0))" } ?? "")
        if inbox.status != 200 { await printBody("\(base)/news/inbox/", auth: auth, tag: "igLiveInboxBody") }
        if let root = inbox.json as? [String: Any] {
            NSLog("[Casberi] igLive| inbox keys: %@", Array(root.keys).sorted().joined(separator: ", "))
        }
        let stories = stories(inbox.json) ?? []
        NSLog("[Casberi] igLive| %d stories parsed", stories.count)
        for story in stories.prefix(3) {
            if let n = notice(from: story) {
                NSLog("[Casberi] igLiveNotice| id=%@ text=%@ actor=%@ face=%@ media=%@ img=%@ follow=%d",
                      n.id, n.text.prefix(80).description, n.actorName ?? "MISSING",
                      n.actorAvatar == nil ? "no" : "yes",
                      n.mediaID.flatMap(shortcode(fromMediaID:)) ?? "none",
                      n.mediaImage == nil ? "no" : "yes", n.isFollow ? 1 : 0)
            } else {
                NSLog("[Casberi] igLiveNotice| unparsed — keys %@",
                      Array(story.keys).sorted().joined(separator: ", "))
            }
        }
        if let first = stories.first,
           let data = try? JSONSerialization.data(withJSONObject: first),
           let body = String(data: data.prefix(1500), encoding: .utf8) {
            NSLog("[Casberi] igLiveStoryRaw| %@", body)
        }

        let saved = await get("\(base)/feed/saved/posts/?count=\(savedPageSize)", auth: auth)
        NSLog("[Casberi] igLive| saved HTTP %d%@", saved.status,
              classify(saved).map { " — \(describe($0))" } ?? "")
        if saved.status != 200 { await printBody("\(base)/feed/saved/posts/?count=\(savedPageSize)", auth: auth, tag: "igLiveSavedBody") }
        let items = savedMedia(saved.json) ?? []
        NSLog("[Casberi] igLive| %d saved posts parsed", items.count)
        for media in items.prefix(3) {
            if let s = save(from: media) {
                NSLog("[Casberi] igLiveSave| code=%@ by=%@ words=%d imgs=%d likes=%@ reel=%d",
                      s.code, s.author ?? "MISSING", (s.caption ?? "").count, s.imageURLs.count,
                      s.likes.map { "\($0)" } ?? "—", s.isReel ? 1 : 0)
            } else {
                NSLog("[Casberi] igLiveSave| unparsed — keys %@",
                      Array(media.keys).sorted().joined(separator: ", "))
            }
        }
    }

    static func describe(_ failure: Failure) -> String {
        switch failure {
        case .noSession: return "not signed in"
        case .refused(let s): return "refused (\(s)) — the session is gone, sign in again"
        case .checkpoint: return "checkpoint — open Instagram and confirm it was you; the cookies are kept"
        case .throttled: return "throttled — asked too often, try later"
        case .unreachable: return "unreachable — check the connection"
        case .drifted: return "unexpected shape — the web app's response changed"
        }
    }

    /// `getJSONStatus` drops the body on a non-200 by design; this bridge is
    /// UNMEASURED and the body's `message` is the diagnosis. Re-issued
    /// directly, and only the body is printed — never a header.
    private static func printBody(_ url: String, auth: InstagramLiveAuth.Session, tag: String) async {
        guard let u = URL(string: url) else { return }
        var request = URLRequest(url: u)
        for (field, value) in headers(auth) { request.setValue(value, forHTTPHeaderField: field) }
        NetworkLedger.shared.record(request, as: "Instagram")
        if let (data, _) = try? await URLSession.shared.data(for: request) {
            let body = String(data: data.prefix(600), encoding: .utf8) ?? "(non-UTF8 body)"
            NSLog("[Casberi] %@| %@", tag, body)
        }
    }
}
