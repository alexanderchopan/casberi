import Foundation
import SwiftData

/// Threads' Activity feed, read with the person's OWN web-session cookies
/// (prd §1130, §1131) — §726's Instagram door, one site over. Threads signs in
/// through Instagram but keeps its own session on threads.com, so this is its
/// own seat with its own sign-in (`ThreadsLiveLoginSheet`). The pure parse and
/// everything measured about it are in `ThreadsLiveFeed`.
///
/// Nothing is extracted from Meta's app, nothing signs a request, and nothing
/// marks the inbox seen. One pass is two requests: the Activity page (for its
/// `fb_dtsg` token and the signed-in handle) and the feed query. A query id
/// Threads no longer knows costs the page's scripts once, then the id is kept.
enum ThreadsLiveAuth {
    private static let cookieVaultKey = "threads.live.cookies"
    /// Not secrets — the signed-in handle, and the query id last found.
    private static let usernameKey = "threads.live.username"
    private static let docIDKey = "threads.live.docID"

    static var cookieHeader: String? {
        TokenVault.get(cookieVaultKey).flatMap { $0.isEmpty ? nil : $0 }
    }

    static var connected: Bool { cookieHeader != nil }

    static func store(cookieHeader: String) {
        // A new sign-in may be a different account: its name is learnt again.
        UserDefaults.standard.removeObject(forKey: usernameKey)
        TokenVault.set(cookieHeader, for: cookieVaultKey)
    }

    /// Clears the session only — every notice already landed stays
    /// (2026-07-13's two verbs).
    static func clear() {
        TokenVault.delete(cookieVaultKey)
        UserDefaults.standard.removeObject(forKey: usernameKey)
    }

    static var username: String? {
        UserDefaults.standard.string(forKey: usernameKey).flatMap { $0.isEmpty ? nil : $0 }
    }

    static func remember(username: String) {
        guard !username.isEmpty, username != self.username else { return }
        UserDefaults.standard.set(username, forKey: usernameKey)
    }

    static var docID: String {
        UserDefaults.standard.string(forKey: docIDKey).flatMap { $0.isEmpty ? nil : $0 }
            ?? ThreadsLiveFeed.pinnedDocID
    }

    static func remember(docID: String) {
        UserDefaults.standard.set(docID, forKey: docIDKey)
    }
}

enum ThreadsLive {
    @MainActor private static var running = false

    /// Why the last pass read nothing, for the account page — nil after a
    /// pass that read.
    @MainActor private(set) static var lastFailure: ThreadsLiveFeed.Failure?

    /// Lands new notices. nil = couldn't run (not signed in, or the read
    /// failed); 0 or more = a real read, however many were new. A refusal —
    /// and only a refusal — clears the session (§711).
    @MainActor
    @discardableResult
    static func refresh(context: ModelContext) async -> Int? {
        guard let cookies = ThreadsLiveAuth.cookieHeader else {
            lastFailure = .noSession
            return nil
        }
        guard !running else { return 0 }
        running = true
        defer { running = false }

        switch await read(cookies: cookies) {
        case .success(let feed):
            lastFailure = nil
            return land(ThreadsLiveFeed.notices(feed), context: context)
        case .failure(let failure):
            lastFailure = failure
            if case .refused = failure { ThreadsLiveAuth.clear() }
            return nil
        }
    }

    /// The page, then the query; a stale query id is found again from the
    /// page's own scripts and asked once more.
    private static func read(cookies: String) async -> Result<[String: Any], ThreadsLiveFeed.Failure> {
        let page = await getPage(ThreadsLiveFeed.activityURL, cookies: cookies)
        if page.status == 0 { return .failure(.unreachable) }
        if page.status == 401 || page.status == 403 { return .failure(.refused(page.status)) }
        if ThreadsLiveFeed.isLoginPage(path: page.finalPath) { return .failure(.refused(page.status)) }
        if page.status == 429 { return .failure(.throttled) }
        guard page.status == 200, let html = page.body else { return .failure(.drifted) }
        if let name = ThreadsLiveFeed.viewerUsername(inPage: html) { ThreadsLiveAuth.remember(username: name) }
        guard let dtsg = ThreadsLiveFeed.dtsg(inPage: html) else { return .failure(.tokenRejected) }

        let first = await query(docID: ThreadsLiveAuth.docID, dtsg: dtsg, cookies: cookies)
        guard case .failure(.staleQuery) = first else { return first }
        guard let found = await findDocID(inPage: html) else { return first }
        ThreadsLiveAuth.remember(docID: found)
        return await query(docID: found, dtsg: dtsg, cookies: cookies)
    }

    private static func query(docID: String, dtsg: String,
                              cookies: String) async -> Result<[String: Any], ThreadsLiveFeed.Failure> {
        let reply = await post(ThreadsLiveFeed.graphqlURL,
                               form: ThreadsLiveFeed.formBody(docID: docID, dtsg: dtsg), cookies: cookies)
        return ThreadsLiveFeed.classify(status: reply.status, body: reply.body)
    }

    /// The page's scripts, in order, until one names the query. The measured
    /// page lists nine and the third held it.
    private static func findDocID(inPage html: String) async -> String? {
        for url in ThreadsLiveFeed.scriptURLs(inPage: html).prefix(16) {
            let script = await getPage(url, cookies: nil)
            if let body = script.body, let id = ThreadsLiveFeed.docID(inScript: body) { return id }
        }
        return nil
    }

    @MainActor
    private static func land(_ notices: [ThreadsLiveFeed.Notice], context: ModelContext) -> Int {
        let landed = landedNotices(context: context)
        var added = 0
        var healed = 0
        for notice in notices {
            let ref = ThreadsLiveFeed.refPrefix + notice.id
            if let existing = landed[ref] {
                // A notice is never re-sent, so this page is the only chance a
                // row landed earlier gets its face and its picture (§704/§707).
                var touched = false
                if existing.authorAvatarURL == nil, let avatar = notice.actorAvatar {
                    existing.authorAvatarURL = avatar
                    if existing.authorHandle == nil { existing.authorHandle = notice.actorHandle }
                    touched = true
                }
                if existing.previewImageURL == nil, let image = notice.image {
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

    @MainActor
    private static func landedNotices(context: ModelContext) -> [String: Thing] {
        let source = ThreadsLiveFeed.source
        let prefix = ThreadsLiveFeed.refPrefix
        let descriptor = FetchDescriptor<Thing>(predicate: #Predicate {
            $0.source == source && ($0.sourceRef?.starts(with: prefix) ?? false)
        })
        var map: [String: Thing] = [:]
        for thing in (try? context.fetch(descriptor)) ?? [] {
            if let ref = thing.sourceRef { map[ref] = thing }
        }
        return map
    }

    private static func thing(from notice: ThreadsLiveFeed.Notice, ref: String) -> Thing {
        let words = IngestSupport.decodeHTMLEntities(notice.text)
        let title = IngestSupport.titleLine(words)
        let thing = Thing(
            kind: .link,
            title: title,
            content: notice.permalink,
            source: ThreadsLiveFeed.source,
            capturedAt: notice.at,
            sourceRef: ref)
        // The words the title line did not carry (prd §912): what Threads put
        // under its line, else the line itself where the clamp cut it.
        if let detail = notice.detail {
            thing.summary = IngestSupport.decodeHTMLEntities(detail)
        } else if words != title {
            thing.summary = words
        }
        // WHO ACTED (§707): the face is the person who liked, replied or
        // followed — never the source mark, never you.
        if let handle = notice.actorHandle { thing.authorHandle = handle }
        if let avatar = notice.actorAvatar { thing.authorAvatarURL = avatar }
        if notice.isFollow { thing.socialContext = "follow" }
        // A recommendation is not to you (`SocialScope.isToYou` reads this).
        if notice.isSuggestion { thing.socialContext = "suggested" }
        // The post's picture, and NO `quote` card: the feed carries the post's
        // code and author but never its words, and a card would be a handle
        // over nothing (§726's Instagram reason).
        if let image = notice.image {
            thing.imageURLs = [image]
            thing.previewImageURL = image
        }
        return thing
    }

    // MARK: - The requests

    /// Our own `Cookie` header and nothing from the shared jar, which is a
    /// plain file rather than the device-only Keychain (Privy's reason) — so
    /// a rotated cookie never lands outside the vault.
    private static func request(_ url: URL, cookies: String?) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpShouldHandleCookies = false
        if let cookies { request.setValue(cookies, forHTTPHeaderField: "Cookie") }
        request.setValue(ThreadsLiveFeed.desktopUserAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    private static func getPage(_ url: String, cookies: String?) async
        -> (body: String?, status: Int, finalPath: String?) {
        guard let u = URL(string: url) else { return (nil, 0, nil) }
        var request = request(u, cookies: cookies)
        request.setValue("text/html,application/xhtml+xml,*/*", forHTTPHeaderField: "Accept")
        guard let (data, http) = await IngestSupport.sendRequest(request, service: "Threads live")
        else { return (nil, 0, nil) }
        return (String(data: data, encoding: .utf8), http.statusCode, http.url?.path)
    }

    /// The three `Sec-Fetch-*` headers a browser adds to the page's own query
    /// are REQUIRED from a native client (measured 2026-10-05 on the
    /// simulator: without them the query answers with an HTML page; with them,
    /// the feed; `lsd`, `X-IG-App-ID` and `X-CSRFToken` changed nothing).
    static let fetchMetadata = ["Sec-Fetch-Site": "same-origin", "Sec-Fetch-Mode": "cors", "Sec-Fetch-Dest": "empty"]

    private static func post(_ url: String, form: String, cookies: String) async -> (body: String?, status: Int) {
        guard let u = URL(string: url) else { return (nil, 0) }
        var request = request(u, cookies: cookies)
        for (field, value) in fetchMetadata { request.setValue(value, forHTTPHeaderField: field) }
        request.httpMethod = "POST"
        request.httpBody = Data(form.utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("https://www.threads.com", forHTTPHeaderField: "Origin")
        request.setValue(ThreadsLiveFeed.activityURL, forHTTPHeaderField: "Referer")
        request.setValue(ThreadsLiveFeed.queryName, forHTTPHeaderField: "X-FB-Friendly-Name")
        guard let (data, http) = await IngestSupport.sendRequest(request, service: "Threads live")
        else { return (nil, 0) }
        return (String(data: data, encoding: .utf8), http.statusCode)
    }

    // MARK: - Diagnose

    /// The chain, link by link: cookie names / page status and where it ended
    /// / token / signed in as / query status and outcome / rows parsed / first
    /// three / one raw row. Never prints a cookie or the token.
    @MainActor
    static func diagnose() async {
        guard let cookies = ThreadsLiveAuth.cookieHeader else {
            NSLog("[Casberi] threadsLive| not signed in — connect from the Threads account page first")
            return
        }
        let names = cookies.split(separator: ";").compactMap {
            $0.split(separator: "=").first.map { $0.trimmingCharacters(in: .whitespaces) }
        }
        NSLog("[Casberi] threadsLive| session stored — cookie names: %@", names.joined(separator: ", "))
        let page = await getPage(ThreadsLiveFeed.activityURL, cookies: cookies)
        let html = page.body ?? ""
        NSLog("[Casberi] threadsLive| page HTTP %d ended at %@ (%d bytes) token=%@ viewer=%@",
              page.status, page.finalPath ?? "—", html.utf8.count,
              ThreadsLiveFeed.dtsg(inPage: html) == nil ? "MISSING" : "yes",
              ThreadsLiveFeed.viewerUsername(inPage: html) ?? "MISSING")
        guard let dtsg = ThreadsLiveFeed.dtsg(inPage: html) else { return }
        let docID = ThreadsLiveAuth.docID
        let reply = await post(ThreadsLiveFeed.graphqlURL,
                               form: ThreadsLiveFeed.formBody(docID: docID, dtsg: dtsg), cookies: cookies)
        let outcome = ThreadsLiveFeed.classify(status: reply.status, body: reply.body)
        switch outcome {
        case .failure(let failure):
            NSLog("[Casberi] threadsLive| query %@ HTTP %d — %@; body: %@", docID, reply.status,
                  ThreadsLiveFeed.describe(failure), String((reply.body ?? "").prefix(300)))
            if failure == .staleQuery {
                let found = await findDocID(inPage: html)
                NSLog("[Casberi] threadsLive| scripts on the page: %d, query id found: %@",
                      ThreadsLiveFeed.scriptURLs(inPage: html).count, found ?? "NONE")
            }
        case .success(let feed):
            let edges = (feed["edges"] as? [[String: Any]]) ?? []
            let notices = ThreadsLiveFeed.notices(feed)
            NSLog("[Casberi] threadsLive| query %@ HTTP 200 — %d rows, %d notices", docID, edges.count, notices.count)
            for n in notices.prefix(3) {
                NSLog("[Casberi] threadsLiveNotice| id=%@ name=%@ text=%@ detail=%@ actor=%@ face=%@ post=%@ by=%@ img=%@ follow=%d suggested=%d",
                      n.id, n.notifName ?? "—", String(n.text.prefix(80)), String((n.detail ?? "—").prefix(60)),
                      n.actorHandle ?? "none", n.actorAvatar == nil ? "no" : "yes", n.postCode ?? "none",
                      n.postAuthor ?? "—", n.image == nil ? "no" : "yes", n.isFollow ? 1 : 0, n.isSuggestion ? 1 : 0)
            }
            if let row = edges.lazy.compactMap({ $0["node"] as? [String: Any] })
                .first(where: { ($0["__typename"] as? String) == "XTHNotificationFeedRow" }),
               let data = try? JSONSerialization.data(withJSONObject: row),
               let body = String(data: data.prefix(1500), encoding: .utf8) {
                NSLog("[Casberi] threadsLiveRowRaw| %@", body)
            }
        }
    }
}
