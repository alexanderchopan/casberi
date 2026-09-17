import Foundation

/// Privy Home — every app a person has made a wallet in through Privy, read
/// with their own signed-in session (prd §803b, §803c). The pure half,
/// Foundation only, so `privy-selftest.sh` compiles it whole.
///
/// ## WHAT WAS MEASURED (2026-09-17)
///
/// On a real sign-in through the web-session capture (§803b):
///
///   · `GET privy.home.privy.io/api/v1/privy_home/me` with `Authorization:
///     Bearer`, `privy-app-id` and `privy-client` returns
///     `{user: {id, apps: [{id, name, logo_url, accounts, created_at,
///     last_active_at, status, …}]}}` — every app, and the wallet it made;
///   · `POST /api/v1/sessions {refresh_token}` hands back a fresh `token`
///     and `refresh_token`; the sign-in leaves both as HttpOnly cookies
///     (`privy-token`/`privy-access-token`, `privy-refresh-token`);
///   · balances and transactions are NOT on any Privy host — the page reads
///     them from the chain. So this seat reads WHICH wallets, and the Wallet
///     seat's own holdings read says what is in them.
///
/// And keylessly, the same day: a request without `Origin` is refused
/// (`403 missing_origin`), one with `Origin: https://home.privy.io` and the
/// app id reaches the auth check (`401 Missing auth token`), and nothing
/// answers with a bot challenge — so a sync is a plain request, not a hidden
/// web view.
///
/// **The inner shape of `accounts` was past the capture's depth.** It is read
/// tolerantly (`wallets(in:)`): any object carrying an address-shaped
/// `address` is a wallet, and an email or phone account is not.
enum PrivyHomeFeed {

    static let source = "Privy"
    static let seatID = "privy"
    static let refPrefix = "privy:app:"

    static let loginURL = "https://home.privy.io/login"
    static let origin = "https://home.privy.io"
    static let apiHost = "privy.home.privy.io"
    static let meURL = "https://privy.home.privy.io/api/v1/privy_home/me"
    static let sessionsURL = "https://privy.home.privy.io/api/v1/sessions"

    /// Privy Home's OWN app id — public, shipped in home.privy.io's bundle as
    /// `NEXT_PUBLIC_PRIVY_APP_ID`. Not a credential: it names which Privy app
    /// is asking, exactly as the page's own requests do.
    static let appID = "cmdhkgaka00qyl40muremakwx"
    /// The client string the page sends (`react-auth:3.43.0`, from the same
    /// bundle). Privy reads it for analytics and compatibility, not auth.
    static let client = "react-auth:3.43.0"

    /// The headers every read carries. `Origin` is load-bearing (measured:
    /// without it, `403 missing_origin`).
    static var headers: [String: String] {
        ["Origin": origin, "privy-app-id": appID, "privy-client": client]
    }

    // MARK: - The session

    static let accessCookies = ["privy-token", "privy-access-token"]
    static let refreshCookie = "privy-refresh-token"

    /// MEASURED on the simulator, 2026-09-17: `privy_home/me` answers
    /// "Missing auth token" to a valid bearer ALONE and "Invalid auth token" to
    /// one token's value sent under both cookie names. Privy Home runs Privy's
    /// HttpOnly-cookie mode, and the sign-in leaves two DIFFERENT tokens —
    /// `privy-token` on `.home.privy.io` and `privy-access-token` on
    /// `.privy.home.privy.io`. So the session is every cookie a browser would
    /// send to the API host, each with its own value, and a read carries all of
    /// them plus the bearer, as the page's own `credentials: include` does.
    static func apiCookies(_ jar: [(name: String, value: String, domain: String)]) -> [String: String] {
        var out: [String: String] = [:]
        for cookie in jar where !cookie.value.isEmpty && domainMatches(apiHost, cookie.domain)
            && isSessionCookie(cookie.name) {
            out[cookie.name] = cookie.value
        }
        return out
    }

    /// Privy's own cookies and Cloudflare's, and nothing else: the jar also
    /// holds Google Analytics and HubSpot trackers, which the API never needs
    /// and which have no business in the Keychain or on a request we send.
    static func isSessionCookie(_ name: String) -> Bool {
        name.hasPrefix("privy-") || ["cf_clearance", "__cf_bm", "_cfuvid"].contains(name)
    }

    /// RFC 6265 domain-match: `privy.home.privy.io` receives cookies set for
    /// `.home.privy.io` and `.privy.io`, never `home.privy.io.evil`.
    static func domainMatches(_ host: String, _ domain: String) -> Bool {
        let d = domain.hasPrefix(".") ? String(domain.dropFirst()) : domain
        return host == d || host.hasSuffix("." + d)
    }

    /// A jar holds a signed-in session when it carries a refresh token and an
    /// access token for the API host. A signed-out visit writes `privy-session`
    /// and analytics cookies, never these.
    static func isSession(_ cookies: [String: String]) -> Bool {
        cookies[refreshCookie] != nil && accessCookies.contains { cookies[$0] != nil }
    }

    static func bearer(_ cookies: [String: String]) -> String? {
        accessCookies.lazy.compactMap { cookies[$0] }.first
    }

    static func cookieHeader(_ cookies: [String: String]) -> String {
        cookies.keys.sorted().map { "\($0)=\(cookies[$0]!)" }.joined(separator: "; ")
    }

    /// A renewal's answer merged into the stored session: every `Set-Cookie`
    /// by name, and the body's `token` only where no cookie carried an access
    /// token. Privy's cookie mode answers `refresh_token: "deprecated"` in the
    /// body; that word is never stored.
    static func rotated(_ cookies: [String: String], body: Any?,
                        setCookies: [(name: String, value: String)]) -> [String: String] {
        var out = cookies
        for cookie in setCookies {
            if cookie.value.isEmpty { out.removeValue(forKey: cookie.name) } else { out[cookie.name] = cookie.value }
        }
        let object = body as? [String: Any]
        func usable(_ s: String?) -> String? {
            guard let s, !s.isEmpty, s != "deprecated" else { return nil }
            return s
        }
        let setNames = Set(setCookies.map(\.name))
        if !accessCookies.contains(where: setNames.contains), let token = usable(object?["token"] as? String) {
            out["privy-token"] = token
        }
        if !setNames.contains(refreshCookie), let refresh = usable(object?["refresh_token"] as? String) {
            out[refreshCookie] = refresh
        }
        return out
    }

    /// Privy's error `code` (or `error`) out of a refusal body — a machine
    /// word like `missing_or_invalid_token`, never a value.
    static func errorCode(_ json: Any?) -> String? {
        guard let object = json as? [String: Any] else { return nil }
        if let code = object["code"] as? String, !code.isEmpty { return code }
        if let error = object["error"] as? String, !error.isEmpty { return String(error.prefix(60)) }
        return nil
    }

    /// A token's CLAIMS as shape, for the trace: whether its audience is Privy
    /// Home's app id, and how long until it expires. Never the token, never a
    /// subject. "opaque" when it is not a JWT at all.
    static func describe(jwt: String, now: Date) -> String {
        let parts = jwt.split(separator: ".")
        guard parts.count == 3 else { return "opaque len=\(jwt.count)" }
        var b64 = String(parts[1]).replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64),
              let claims = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return "jwt unreadable" }
        let aud: String
        switch claims["aud"] {
        case let s as String: aud = s == appID ? "home" : "other"
        case let a as [String]: aud = a.contains(appID) ? "home" : "other"
        default: aud = "none"
        }
        let exp = (claims["exp"] as? NSNumber).map { Int($0.doubleValue - now.timeIntervalSince1970) }
        return "jwt aud=\(aud) exp=\(exp.map { "\($0)s" } ?? "none") iss=\((claims["iss"] as? String) ?? "none")"
    }

    enum Failure: Equatable {
        case noSession
        /// The session is dead. The ONLY outcome that clears it (§711).
        case refused(Int)
        case throttled
        case unreachable
        /// A 200 that is not the shape measured.
        case drifted
    }

    static func classify(status: Int) -> Failure? {
        switch status {
        case 200: return nil
        case 401, 403: return .refused(status)
        case 429: return .throttled
        default: return .unreachable
        }
    }

    // MARK: - The apps

    struct Wallet: Codable, Equatable, Hashable {
        var address: String
        /// Privy's `chain_type` when present ("ethereum", "solana").
        var chain: String?
    }

    struct App: Codable, Equatable, Identifiable {
        var id: String
        var name: String
        var logoURL: String?
        /// Privy's `custom_origin` — where the app lives, when it says. Read
        /// as an https URL or a bare host; anything else is nil.
        var origin: String?
        var createdAt: Date?
        var lastActiveAt: Date?
        var wallets: [Wallet]
    }

    /// Every app with at least one wallet, or nil when the body is not the
    /// measured shape (§83: an unreadable body is not "no apps"). An app with
    /// no wallet is dropped — there is nothing of it to show.
    static func apps(_ json: Any?) -> [App]? {
        guard let root = json as? [String: Any],
              let user = root["user"] as? [String: Any],
              let list = user["apps"] as? [Any] else { return nil }
        var out: [App] = []
        var seen = Set<String>()
        for case let record as [String: Any] in list {
            guard let id = string(record["id"]), !seen.contains(id) else { continue }
            let wallets = wallets(in: record["accounts"])
            guard !wallets.isEmpty else { continue }
            seen.insert(id)
            let name = string(record["name"])?.trimmingCharacters(in: .whitespacesAndNewlines)
            out.append(App(id: id,
                           name: (name?.isEmpty == false ? name : nil) ?? shortAddress(wallets[0].address),
                           logoURL: string(record["logo_url"]),
                           origin: webOrigin(record["custom_origin"]),
                           createdAt: date(record["created_at"]),
                           lastActiveAt: date(record["last_active_at"]),
                           wallets: wallets))
        }
        return out
    }

    /// Wallets anywhere under an app's `accounts`, deduplicated by address.
    /// Tolerant on purpose (see the type doc): an object is a wallet when its
    /// `address` is shaped like one and its `type` is not a contact method.
    static func wallets(in json: Any?) -> [Wallet] {
        var out: [Wallet] = []
        var seen = Set<String>()
        func walk(_ node: Any?, depth: Int) {
            guard depth < 5 else { return }
            if let array = node as? [Any] {
                array.forEach { walk($0, depth: depth + 1) }
                return
            }
            guard let object = node as? [String: Any] else { return }
            let type = (string(object["type"]) ?? "").lowercased()
            if let address = string(object["address"]),
               !["email", "phone", "sms"].contains(type),
               isWalletAddress(address) {
                let key = address.hasPrefix("0x") ? address.lowercased() : address
                if seen.insert(key).inserted {
                    out.append(Wallet(address: address,
                                      chain: string(object["chain_type"]) ?? string(object["chainType"])))
                }
            }
            for (key, value) in object where key != "address" {
                if value is [Any] || value is [String: Any] { walk(value, depth: depth + 1) }
            }
        }
        walk(json, depth: 0)
        return out
    }

    /// An EVM address (0x + 40 hex) or a Solana one (32–44 base58).
    static func isWalletAddress(_ s: String) -> Bool {
        if s.hasPrefix("0x") {
            return s.count == 42 && s.dropFirst(2).allSatisfy(\.isHexDigit)
        }
        let base58 = Set("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
        return (32...44).contains(s.count) && s.allSatisfy { base58.contains($0) }
    }

    /// An https origin out of whatever `custom_origin` holds.
    static func webOrigin(_ any: Any?) -> String? {
        guard var raw = (any as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }
        if !raw.contains("://") { raw = "https://" + raw }
        guard let url = URL(string: raw), url.scheme == "https",
              let host = url.host, host.contains(".") else { return nil }
        return "https://\(host)"
    }

    /// Where a wallet can be looked at. An EVM embedded wallet has one address
    /// on every chain, so it opens Blockscan's cross-chain page; Solana opens
    /// Solscan. Doors, never fetched.
    static func explorerURL(_ wallet: Wallet) -> String {
        wallet.address.hasPrefix("0x")
            ? "https://blockscan.com/address/\(wallet.address)"
            : "https://solscan.io/account/\(wallet.address)"
    }

    /// Which app rows the feed shows (user, 2026-09-17: "Show empty apps",
    /// "Hide an app"): a hidden app never; otherwise a funded app, an app used
    /// lately, an app not read yet, and — only when asked — the rest.
    static func shown(_ apps: [App], balances: [String: Balance], hidden: Set<String>,
                      showEmpty: Bool, now: Date) -> Set<String> {
        var out = Set<String>()
        for app in apps {
            let r = ref(app)
            guard !hidden.contains(r) else { continue }
            let usd = appUSD(app, balances: balances)
            if showEmpty || usd == nil || (usd ?? 0) >= fundedFloor || isRecent(app, now: now) {
                out.insert(r)
            }
        }
        return out
    }

    static func shortAddress(_ address: String) -> String {
        guard address.count > 12 else { return address }
        let head = address.hasPrefix("0x") ? 5 : 4
        return "\(address.prefix(head))…\(address.suffix(4))"
    }

    static func ref(_ app: App) -> String { refPrefix + app.id }

    // MARK: - Activity (prd §803f)

    static let txPrefix = "privy:tx:"

    /// One leg of one transaction in one app's wallet. The app id rides the
    /// ref so an app's page can find its own activity by prefix.
    static func txRef(appID: String, hash: String, received: Bool, symbol: String) -> String {
        "\(txPrefix)\(appID):\(hash.lowercased()):\(received ? "in" : "out"):\(symbol.lowercased())"
    }

    static func txPrefix(appID: String) -> String { "\(txPrefix)\(appID):" }

    /// A funded or recently used app's EVM wallets whose activity is due —
    /// every six hours at most, ten a pass. An empty wallet nobody uses has no
    /// activity worth a Zerion call; Solana is not in Zerion's transfer read.
    static let activityReadEvery: TimeInterval = 6 * 3_600
    static let activityReadsPerPass = 10

    static func activityTargets(_ apps: [App], balances: [String: Balance],
                                readAt: [String: Date], now: Date) -> [(appID: String, address: String)] {
        var out: [(appID: String, address: String)] = []
        var seen = Set<String>()
        let ranked = apps.sorted { (appUSD($0, balances: balances) ?? 0) > (appUSD($1, balances: balances) ?? 0) }
        for app in ranked {
            let funded = (appUSD(app, balances: balances) ?? 0) >= fundedFloor
            guard funded || isRecent(app, now: now) else { continue }
            for wallet in app.wallets where wallet.address.hasPrefix("0x") {
                let k = key(wallet.address)
                guard seen.insert(k).inserted else { continue }
                if let last = readAt[k], now.timeIntervalSince(last) < activityReadEvery { continue }
                out.append((app.id, wallet.address))
            }
        }
        return Array(out.prefix(activityReadsPerPass))
    }

    /// "0.0021 ETH" — at most four significant digits.
    static func amount(_ value: Double, symbol: String) -> String {
        "\(value.formatted(.number.precision(.significantDigits(1...4)))) \(symbol)"
    }

    static func txTitle(received: Bool, value: Double, symbol: String) -> String {
        received
            ? String(localized: "Received \(amount(value, symbol: symbol))")
            : String(localized: "Sent \(amount(value, symbol: symbol))")
    }

    // MARK: - The room's sections (prd §803f)

    /// Each tile holds what its word says: Apps the app wallets, Activity what
    /// moved in them (user, 2026-09-17: "when i click apps vs activity, it is
    /// the same"). Apps carried the deleted Home tile's meaning — the whole
    /// room — so with transfers newest it drew the same list Activity did.
    /// Activity is offered only once something has moved: a tile over nothing
    /// is §83's dead control.
    enum Section: String, CaseIterable, Identifiable, Sendable {
        case apps, activity
        var id: String { rawValue }

        var label: String {
            switch self {
            case .apps: return String(localized: "Apps")
            case .activity: return String(localized: "Activity")
            }
        }

        var summary: String {
            switch self {
            case .apps: return String(localized: "Every app that made you a wallet")
            case .activity: return String(localized: "What moved in your app wallets")
            }
        }

        static func present(hasActivity: Bool) -> [Section] {
            hasActivity ? [.apps, .activity] : [.apps]
        }

        /// Whether a row of this room belongs to the section.
        func allows(ref: String?) -> Bool {
            switch self {
            case .apps: return ref?.hasPrefix(PrivyHomeFeed.refPrefix) == true
            case .activity: return ref?.hasPrefix(PrivyHomeFeed.txPrefix) == true
            }
        }
    }

    /// The row's line: the wallet, short. Two wallets say so.
    static func line(_ app: App) -> String {
        guard let first = app.wallets.first else { return "" }
        let short = shortAddress(first.address)
        return app.wallets.count > 1 ? "\(short) +\(app.wallets.count - 1)" : short
    }

    private static func string(_ any: Any?) -> String? {
        if let s = any as? String, !s.isEmpty { return s }
        if let n = any as? NSNumber { return n.stringValue }
        return nil
    }

    /// Unix seconds, milliseconds, or ISO 8601 — whichever Privy sends.
    static func date(_ any: Any?) -> Date? {
        if let n = any as? NSNumber {
            let v = n.doubleValue
            guard v > 0 else { return nil }
            return Date(timeIntervalSince1970: v > 1e12 ? v / 1000 : v)
        }
        if let s = any as? String {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = f.date(from: s) { return d }
            f.formatOptions = [.withInternetDateTime]
            return f.date(from: s)
        }
        return nil
    }

    // MARK: - Balances: what to read, and what the room lists

    struct Balance: Codable, Equatable {
        var usd: Double
        /// Every counted position summed by symbol — the Wallet seat's own
        /// `bySymbolAll`, so its floor and spam filter already applied.
        var bySymbol: [String: Double]
        var readAt: Date
    }

    /// Below this an app is not "funded" — the Wallet seat's own dust line.
    static let fundedFloor = 0.01
    /// "Recently used" in the room, and in what gets re-read.
    static let recentWindow: TimeInterval = 90 * 86_400
    /// A funded or recent app's balance is re-read at most this often.
    static let activeReadEvery: TimeInterval = 6 * 3_600
    /// Everything else: once a week. 117 empty wallets must not cost 117
    /// Zerion calls a window (§216's shared allowance).
    static let quietReadEvery: TimeInterval = 7 * 86_400
    /// The most balance reads one sweep spends, so a first sync spreads.
    static let readsPerPass = 30

    static func isRecent(_ app: App, now: Date) -> Bool {
        guard let last = app.lastActiveAt else { return false }
        return now.timeIntervalSince(last) < recentWindow
    }

    static func appUSD(_ app: App, balances: [String: Balance]) -> Double? {
        let read = app.wallets.compactMap { balances[key($0.address)] }
        guard !read.isEmpty else { return nil }
        return read.reduce(0) { $0 + $1.usd }
    }

    static func key(_ address: String) -> String {
        address.hasPrefix("0x") ? address.lowercased() : address
    }

    /// The addresses worth reading this pass, most useful first: never read,
    /// then funded, then recent, then the weekly re-read of the rest.
    static func toRead(_ apps: [App], balances: [String: Balance], now: Date) -> [String] {
        var never: [String] = [], funded: [String] = [], recent: [String] = [], quiet: [String] = []
        var seen = Set<String>()
        for app in apps {
            let isRecentApp = isRecent(app, now: now)
            for wallet in app.wallets {
                let k = key(wallet.address)
                guard seen.insert(k).inserted else { continue }
                guard let b = balances[k] else { never.append(wallet.address); continue }
                let age = now.timeIntervalSince(b.readAt)
                if b.usd >= fundedFloor {
                    if age >= activeReadEvery { funded.append(wallet.address) }
                } else if isRecentApp {
                    if age >= activeReadEvery { recent.append(wallet.address) }
                } else if age >= quietReadEvery {
                    quiet.append(wallet.address)
                }
            }
        }
        return Array((funded + recent + never + quiet).prefix(readsPerPass))
    }

    /// The room's head, as values (no `Thing`) — the mockup's order (user,
    /// 2026-09-17): the apps holding money by value, then the apps used
    /// recently, then ONE count for the rest rather than a row each.
    struct Room: Equatable {
        struct Entry: Equatable, Identifiable {
            var id: String { ref }
            var ref: String
            var name: String
            var logoURL: String?
            /// nil = not read yet.
            var usd: Double?
            var lastActiveAt: Date?
            var line: String
        }
        var appCount: Int
        /// The funded apps by value.
        var funded: [Entry]
        /// Used inside `recentWindow` and holding nothing, newest use first.
        var recent: [Entry]
        /// Every funded app, before any cap.
        var fundedCount: Int
        var totalUSD: Double
        /// Apps whose balance has been read at least once.
        var readCount: Int
        var recentCount: Int
        /// Neither funded nor recently used.
        var quietCount: Int { appCount - fundedCount - recent.count }
    }

    static func room(_ apps: [App], balances: [String: Balance], now: Date) -> Room {
        var funded: [Room.Entry] = []
        var recent: [Room.Entry] = []
        var total = 0.0
        var read = 0
        var recentCount = 0
        for app in apps {
            let usd = appUSD(app, balances: balances)
            let isRecentApp = isRecent(app, now: now)
            if isRecentApp { recentCount += 1 }
            if usd != nil { read += 1 }
            total += usd ?? 0
            let entry = Room.Entry(ref: ref(app), name: app.name, logoURL: app.logoURL, usd: usd,
                                   lastActiveAt: app.lastActiveAt,
                                   line: lastUsed(app.lastActiveAt, now: now) ?? line(app))
            if let usd, usd >= fundedFloor {
                funded.append(entry)
            } else if isRecentApp {
                recent.append(entry)
            }
        }
        funded.sort { ($0.usd ?? 0) == ($1.usd ?? 0) ? $0.name < $1.name : ($0.usd ?? 0) > ($1.usd ?? 0) }
        recent.sort { ($0.lastActiveAt ?? .distantPast) > ($1.lastActiveAt ?? .distantPast) }
        return Room(appCount: apps.count, funded: funded, recent: recent,
                    fundedCount: funded.count, totalUSD: total, readCount: read,
                    recentCount: recentCount)
    }

    /// "Used today", "Used 3 days ago", "Used Mar 2025" — a row's line.
    static func lastUsed(_ date: Date?, now: Date) -> String? {
        guard let date else { return nil }
        let days = Int(now.timeIntervalSince(date) / 86_400)
        if days <= 0 { return String(localized: "Used today") }
        if days == 1 { return String(localized: "Used yesterday") }
        if days < 30 { return String(localized: "Used \(days) days ago") }
        return String(localized: "Used \(date.formatted(.dateTime.month(.abbreviated).year()))")
    }

    static func usd(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(2)))
    }

    /// The head's sentence when there is no figure to lead with yet.
    static func headline(_ room: Room) -> String {
        room.appCount == 1
            ? String(localized: "One app made you a wallet with Privy")
            : String(localized: "\(room.appCount) apps made you a wallet with Privy")
    }

    /// Under the figure.
    static func caption(_ room: Room) -> String {
        room.fundedCount == 1
            ? String(localized: "in one app, of \(room.appCount)")
            : String(localized: "across \(room.fundedCount) apps, of \(room.appCount)")
    }

    /// The one line for everything the head does not list, and what has not
    /// been read yet.
    static func footnote(_ room: Room) -> String? {
        let unread = room.appCount - room.readCount
        let quiet = room.quietCount
        switch (quiet > 0, unread > 0) {
        case (true, true):
            return String(localized: "\(quiet) more apps, empty or not used lately · \(unread) not read yet")
        case (true, false):
            return String(localized: "\(quiet) more apps, empty and not used lately")
        case (false, true):
            return String(localized: "\(unread) apps not read yet — they fill in over the next syncs")
        case (false, false):
            return nil
        }
    }
}
