import Foundation

/// The web sign-ins that replaced a pasted key (prd §1584): Notion, Raindrop
/// and Steam. Each signs in on the service's own page in a `WKWebView`
/// (`WebSessionSignInSheet`), keeps the cookies that page leaves as one
/// `Cookie:` header, and reads the endpoints the service's own web app reads.
/// The key each seat used to ask for is still taken, behind the Your key
/// sheet, for anyone who already has one.
///
/// **Device-only.** A session is a signed-in browser, and two devices
/// presenting one is the shape a service flags (`TokenVault.syncs`'s first
/// reason), so these slots are never on its allowlist.
///
/// **UNMEASURED** (prd §780b: a seat that ships ahead of its evidence says
/// so). No account here has signed in through any of the three. What each
/// reads is what its web app calls: Raindrop's bundle sends
/// `credentials: "include"` to `api.raindrop.io/v1/` (read 2026-10-28);
/// Notion's `/api/v3` and Steam's `ajaxgetasyncconfig` answer 401 and an empty
/// `data` signed out (measured 2026-10-28), and their signed-in shapes are the
/// well-known ones. How long a session lasts is not known for any of them;
/// Steam's access token is the likeliest to be short. `-webSessionProbe`
/// logs what each answers.
enum WebSession {
    /// Safari's own string. Google refuses its sign-in inside a web view that
    /// announces itself as one, and several of these pages offer it.
    static let safariUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    enum Seat: String, CaseIterable {
        /// Muse, ChatGPT and Claude are agents, not token bridges (prd
        /// §1619, §1623, §1624): their sessions are used by their own pages
        /// (`MuseWeb`, `AgentChatPage`), never sent as a header.
        case notion, raindrop, steam, muse, chatgpt, claude, grok, gemini

        /// The catalogue name, for the sheet's title.
        var name: String {
            switch self {
            case .notion: "Notion"
            case .raindrop: "Raindrop"
            case .steam: "Steam"
            case .muse: "Muse"
            case .chatgpt: "ChatGPT"
            case .claude: "Claude"
            case .grok: "Grok"
            case .gemini: "Gemini"
            }
        }

        /// The service's own sign-in page.
        var loginURL: URL {
            switch self {
            case .notion: URL(string: "https://www.notion.so/login")!
            case .raindrop: URL(string: "https://app.raindrop.io/account/login")!
            case .steam: URL(string: "https://store.steampowered.com/login/")!
            case .muse: MuseWeb.home
            // OpenAI's own sign-in (auth.openai.com), back to chatgpt.com.
            case .chatgpt: URL(string: "https://chatgpt.com/auth/login")!
            case .claude: URL(string: "https://claude.ai/login")!
            // xAI's own sign-in, back to grok.com (prd §1626).
            case .grok: URL(string: "https://accounts.x.ai/sign-in?redirect=grok-com")!
            // Google's own sign-in, back to Gemini (prd §1627).
            case .gemini: URL(string: "https://accounts.google.com/ServiceLogin?continue=https%3A%2F%2Fgemini.google.com%2Fapp")!
            }
        }

        /// The registrable domain whose cookies the sheet clears and watches.
        var domain: String {
            switch self {
            case .notion: "notion.so"
            case .raindrop: "raindrop.io"
            case .steam: "steampowered.com"
            case .muse: MuseWeb.domain
            case .chatgpt: ChatGPTWeb.domain
            case .claude: ClaudeWeb.domain
            case .grok: GrokWeb.domain
            case .gemini: GeminiWeb.domain
            }
        }

        /// The host every read goes to — a cookie is kept only if it would be
        /// sent there, so the header is the one the web app itself sends.
        var apiHost: String {
            switch self {
            case .notion: "www.notion.so"
            case .raindrop: "api.raindrop.io"
            case .steam: "store.steampowered.com"
            case .muse: "muse.ai"
            case .chatgpt: "chatgpt.com"
            case .claude: "claude.ai"
            case .grok: "grok.com"
            case .gemini: "gemini.google.com"
            }
        }

        /// A cookie the signed-in jar must hold before the service is asked —
        /// a signed-out visit writes cookies too. Raindrop's session cookie is
        /// not named anywhere it publishes, so it is asked on any jar.
        var gateCookie: String? {
            switch self {
            case .notion: "token_v2"
            case .raindrop: nil
            case .steam: "steamLoginSecure"
            // Muse's session cookies are HttpOnly and named nowhere it
            // publishes; its own check is asked on any jar.
            case .muse, .chatgpt, .claude, .grok, .gemini: nil
            }
        }

        /// Whether the sheet clears the domain's old cookies before the page
        /// loads (`InstagramLoginWebView`'s lesson: a refused session is never
        /// captured back). Not Google's: its cookies are every Google sign-in
        /// in the app, and a Google sign-in can cost a backup code — clearing
        /// them threw away a session that had just answered (prd §1627). A
        /// Google jar that is already signed in closes the sheet instead.
        var clearsFirst: Bool { self != .gemini }

        fileprivate var vaultKey: String { "\(rawValue).web.session" }
    }

    /// What a token bridge's credential carries when it is a session rather
    /// than a key, so one `String` still flows through `TokenIngest.refresh`.
    private static let marker = "web-session:"

    static func cookieHeader(_ seat: Seat) -> String? {
        TokenVault.get(seat.vaultKey).flatMap { $0.isEmpty ? nil : $0 }
    }

    static func signedIn(_ seat: Seat) -> Bool { cookieHeader(seat) != nil }

    /// The session as a token bridge's credential.
    static func credential(_ seat: Seat) -> String? {
        cookieHeader(seat).map { marker + $0 }
    }

    /// The `Cookie:` header inside a credential, or nil for a pasted key.
    static func cookie(inCredential credential: String) -> String? {
        credential.hasPrefix(marker) ? String(credential.dropFirst(marker.count)) : nil
    }

    static func store(_ header: String, for seat: Seat) {
        TokenVault.set(header, for: seat.vaultKey)
    }

    static func clear(_ seat: Seat) {
        TokenVault.delete(seat.vaultKey)
    }

    /// The cookies a browser would send to `host`, as one header. A cookie
    /// set for `.steampowered.com` reaches the store; one set for
    /// `login.steampowered.com` does not, and neither is sent twice.
    static func header(from cookies: [HTTPCookie], for host: String) -> String {
        var seen = Set<String>()
        var parts: [String] = []
        // The most specific domain first, so its value wins a shared name.
        let applicable = cookies.filter { cookie in
            let domain = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
            return host == domain || host.hasSuffix("." + domain)
        }.sorted { $0.domain.count > $1.domain.count }
        for cookie in applicable where !seen.contains(cookie.name) {
            seen.insert(cookie.name)
            parts.append("\(cookie.name)=\(cookie.value)")
        }
        return parts.joined(separator: "; ")
    }

    /// Whether `header` is a signed-in session, asked of the service itself —
    /// the gate the sheet closes on. A guess at a cookie's name alone would
    /// close the sheet on a signed-out jar.
    static func verify(_ seat: Seat, header: String) async -> Bool {
        switch seat {
        case .raindrop:
            let me = await IngestSupport.getJSON("https://api.raindrop.io/v1/user",
                                                 headers: ["Cookie": header]) as? [String: Any]
            return (me?["result"] as? Bool) == true && me?["user"] != nil
        case .notion:
            return !(await NotionWeb.spaces(cookie: header)).isEmpty
        case .steam:
            return await SteamWeb.token(cookie: header) != nil
        case .muse:
            // Asked by muse.ai's own page over WebKit's jar, which holds what
            // the sheet's page just wrote (prd §1619).
            return await MuseWeb.shared.signedIn()
        case .chatgpt:
            return await ChatGPTWeb.shared.signedIn()
        case .claude:
            return await ClaudeWeb.shared.signedIn()
        case .grok:
            return await GrokWeb.shared.signedIn()
        case .gemini:
            return await GeminiWeb.signedIn()
        }
    }

    /// `-webSessionProbe`: what each stored session answers, as counts.
    @MainActor
    static func probe() async {
        for seat in Seat.allCases {
            guard let cookie = cookieHeader(seat) else {
                NSLog("webSession| %@ | stored=no", seat.rawValue)
                continue
            }
            let verified = await verify(seat, header: cookie)
            var read = "-"
            switch seat {
            case .notion:
                read = (await NotionWeb.pages(cookie: cookie)).map { "pages=\($0.count)" } ?? "pages=nil"
            case .raindrop:
                let root = await IngestSupport.getJSON("https://api.raindrop.io/v1/raindrops/0?perpage=30",
                                                       headers: ["Cookie": cookie]) as? [String: Any]
                read = (root?["items"] as? [Any]).map { "items=\($0.count)" } ?? "items=nil"
            case .steam:
                if let id = SteamWeb.steamID(cookie: cookie), let token = await SteamWeb.token(cookie: cookie) {
                    let root = await IngestSupport.getJSON(
                        "https://api.steampowered.com/IPlayerService/GetRecentlyPlayedGames/v1/?access_token=\(token)&steamid=\(id)"
                    ) as? [String: Any]
                    let response = root?["response"] as? [String: Any]
                    read = response.map { "games=\(($0["games"] as? [Any])?.count ?? 0)" } ?? "games=nil"
                } else {
                    read = "token=nil"
                }
            case .muse, .chatgpt, .claude, .grok, .gemini:
                read = "-"
            }
            NSLog("webSession| %@ | stored=yes | verified=%@ | %@", seat.rawValue,
                  verified ? "yes" : "no", read)
        }
    }

    /// Whose account the session reads, for the account page (prd §1162).
    static func who(_ seat: Seat, cookie: String) async -> String? {
        switch seat {
        case .raindrop:
            let me = await IngestSupport.getJSON("https://api.raindrop.io/v1/user",
                                                 headers: ["Cookie": cookie]) as? [String: Any]
            let user = me?["user"] as? [String: Any]
            return (user?["fullName"] as? String) ?? (user?["email"] as? String)
        case .notion:
            return await NotionWeb.spaces(cookie: cookie).first?.name
        case .steam, .muse, .chatgpt, .claude, .grok, .gemini:
            return nil
        }
    }
}

/// Steam, read with the person's own store session (prd §1584). The store
/// hands its signed-in pages a Web API access token at `ajaxgetasyncconfig`;
/// the same `IPlayerService` read the key path makes takes it as
/// `access_token`, and the SteamID is the first half of `steamLoginSecure`.
/// Nothing here needs the profile to be public or $5 spent.
enum SteamWeb {
    /// The SteamID64 a `steamLoginSecure` value names (`<id>||<jwt>`, its
    /// separator URL-encoded in the jar).
    static func steamID(cookie: String) -> String? {
        for part in cookie.split(separator: ";") {
            let pair = part.trimmingCharacters(in: .whitespaces)
            guard pair.hasPrefix("steamLoginSecure=") else { continue }
            let value = pair.dropFirst("steamLoginSecure=".count)
            let decoded = value.removingPercentEncoding ?? String(value)
            let id = decoded.prefix { $0.isNumber }
            return id.count == 17 ? String(id) : nil
        }
        return nil
    }

    /// The store's Web API token for this session, or nil when the store
    /// answers signed out (its `data` is then an empty array).
    static func token(cookie: String) async -> String? {
        guard steamID(cookie: cookie) != nil,
              let root = await IngestSupport.getJSON(
                "https://store.steampowered.com/pointssummary/ajaxgetasyncconfig",
                headers: ["Cookie": cookie]) as? [String: Any],
              let data = root["data"] as? [String: Any],
              let token = data["webapi_token"] as? String, !token.isEmpty else { return nil }
        return token
    }
}

/// Notion, read with the person's own web session (prd §1584) — the
/// `/api/v3` endpoints notion.so itself calls, which reach every page the
/// person can open rather than only the pages shared with an integration.
/// Pages only, newest edits first, the key path's ruling.
///
/// A record arrives as `{ value: { … } }` or, in the newer record map,
/// `{ value: { value: { … }, role } }`; `record` reads either.
enum NotionWeb {
    struct Space { let id: String; let name: String? }
    struct Page { let id: String; let title: String; let edited: Date? }

    private static let base = "https://www.notion.so/api/v3/"

    private static func post(_ path: String, cookie: String, body: [String: Any]) async -> [String: Any]? {
        guard let root = await IngestSupport.postJSON(base + path, body: body,
                                                      headers: ["Cookie": cookie]) as? [String: Any],
              root["isNotionError"] == nil else { return nil }
        return root
    }

    static func record(_ raw: Any?) -> [String: Any]? {
        guard let outer = (raw as? [String: Any])?["value"] as? [String: Any] else { return nil }
        if let inner = outer["value"] as? [String: Any], outer["role"] != nil { return inner }
        return outer
    }

    /// A title property's plain text: Notion's rich text is an array of runs,
    /// each run an array whose first element is the words.
    static func plainText(_ raw: Any?) -> String {
        guard let runs = raw as? [[Any]] else { return "" }
        return runs.compactMap { $0.first as? String }.joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The workspaces this session can read.
    static func spaces(cookie: String) async -> [Space] {
        guard let root = await post("getSpaces", cookie: cookie, body: [:]) else { return [] }
        var out: [Space] = []
        for case let user as [String: Any] in root.values {
            for (id, raw) in (user["space"] as? [String: Any]) ?? [:] {
                out.append(Space(id: id, name: record(raw)?["name"] as? String))
            }
        }
        return out.sorted { $0.id < $1.id }
    }

    /// The thirty most recently edited pages across every workspace.
    static func pages(cookie: String) async -> [Page]? {
        let spaces = await spaces(cookie: cookie)
        guard !spaces.isEmpty else { return nil }
        var pages: [Page] = []
        for space in spaces {
            guard let root = await post("search", cookie: cookie, body: [
                "type": "BlocksInSpace", "query": "", "spaceId": space.id, "limit": 30,
                "filters": ["isDeletedOnly": false, "excludeTemplates": true,
                            "isNavigableOnly": true, "requireEditPermissions": false,
                            "ancestors": [], "createdBy": [], "editedBy": [],
                            "lastEditedTime": [:], "createdTime": [:]],
                "sort": ["field": "lastEdited", "direction": "desc"],
                "source": "quick_find_filters",
            ]) else { continue }
            let blocks = ((root["recordMap"] as? [String: Any])?["block"] as? [String: Any]) ?? [:]
            for case let hit as [String: Any] in (root["results"] as? [Any]) ?? [] {
                guard let id = hit["id"] as? String, let block = record(blocks[id]),
                      block["type"] as? String == "page",
                      (block["alive"] as? Bool) != false else { continue }
                let title = plainText((block["properties"] as? [String: Any])?["title"])
                guard !title.isEmpty else { continue }
                let edited = (block["last_edited_time"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
                pages.append(Page(id: id, title: title, edited: edited))
            }
        }
        return Array(pages.sorted { ($0.edited ?? .distantPast) > ($1.edited ?? .distantPast) }.prefix(30))
    }

    /// One page's top-level blocks as plain text — the key path's
    /// `notionPageText`, read from the page's own chunk.
    static func pageText(_ id: String, cookie: String) async -> (answered: Bool, text: String) {
        guard let root = await post("loadCachedPageChunk", cookie: cookie, body: [
            "page": ["id": id], "limit": 100, "cursor": ["stack": []],
            "chunkNumber": 0, "verticalColumns": false,
        ]) else { return (false, "") }
        let blocks = ((root["recordMap"] as? [String: Any])?["block"] as? [String: Any]) ?? [:]
        let order = (record(blocks[id])?["content"] as? [String]) ?? []
        let lines = order.compactMap { child -> String? in
            let line = plainText((record(blocks[child])?["properties"] as? [String: Any])?["title"])
            return line.isEmpty ? nil : line
        }
        return (true, lines.joined(separator: "\n"))
    }

    /// A page's address: notion.so resolves a bare id, dashes dropped.
    static func url(_ id: String) -> String {
        "https://www.notion.so/" + id.replacingOccurrences(of: "-", with: "")
    }
}
