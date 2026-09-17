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

    /// The two halves of a session out of a cookie jar, or nil while the jar
    /// does not hold a signed-in session yet. A signed-out visit writes
    /// `privy-session` and analytics cookies, never these.
    static func session(_ jar: [(name: String, value: String)]) -> (access: String, refresh: String)? {
        func value(_ name: String) -> String? {
            jar.first { $0.name == name && !$0.value.isEmpty }?.value
        }
        guard let refresh = value(refreshCookie),
              let access = accessCookies.lazy.compactMap(value).first else { return nil }
        return (access, refresh)
    }

    /// What a refresh handed back. Privy's cookie mode answers
    /// `refresh_token: "deprecated"` in the body and sets the real one as a
    /// cookie, so the cookie wins and the body's word is never stored.
    static func rotated(body: Any?, cookies: [(name: String, value: String)])
        -> (access: String?, refresh: String?) {
        let object = body as? [String: Any]
        func usable(_ s: String?) -> String? {
            guard let s, !s.isEmpty, s != "deprecated" else { return nil }
            return s
        }
        let jar = Dictionary(cookies.map { ($0.name, $0.value) }, uniquingKeysWith: { a, _ in a })
        let access = accessCookies.lazy.compactMap { usable(jar[$0]) }.first
            ?? usable(object?["token"] as? String)
        let refresh = usable(jar[refreshCookie]) ?? usable(object?["refresh_token"] as? String)
        return (access, refresh)
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

    static func shortAddress(_ address: String) -> String {
        guard address.count > 12 else { return address }
        let head = address.hasPrefix("0x") ? 5 : 4
        return "\(address.prefix(head))…\(address.suffix(4))"
    }

    static func ref(_ app: App) -> String { refPrefix + app.id }

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

    /// The room's head, as values (no `Thing`): the total, the funded apps by
    /// value, and how many are empty or unused.
    struct Room: Equatable {
        struct Entry: Equatable, Identifiable {
            var id: String { ref }
            var ref: String
            var name: String
            var usd: Double
            var line: String
        }
        var appCount: Int
        /// The funded apps by value, capped at the head's eight.
        var funded: [Entry]
        /// Every funded app, before the cap.
        var fundedCount: Int
        var totalUSD: Double
        /// Apps whose balance has been read at least once.
        var readCount: Int
        var recentCount: Int
    }

    static func room(_ apps: [App], balances: [String: Balance], now: Date) -> Room {
        var funded: [Room.Entry] = []
        var total = 0.0
        var read = 0
        var recent = 0
        for app in apps {
            if isRecent(app, now: now) { recent += 1 }
            guard let usd = appUSD(app, balances: balances) else { continue }
            read += 1
            total += usd
            if usd >= fundedFloor {
                funded.append(.init(ref: ref(app), name: app.name, usd: usd, line: line(app)))
            }
        }
        funded.sort { $0.usd == $1.usd ? $0.name < $1.name : $0.usd > $1.usd }
        return Room(appCount: apps.count, funded: Array(funded.prefix(8)),
                    fundedCount: funded.count,
                    totalUSD: total, readCount: read, recentCount: recent)
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

    /// What the head left off, and what has not been read yet.
    static func footnote(_ room: Room) -> String? {
        let unread = room.appCount - room.readCount
        if unread > 0 {
            return String(localized: "\(unread) wallets not read yet — they fill in over the next syncs")
        }
        let empty = room.appCount - room.fundedCount
        return empty > 0 ? String(localized: "\(empty) apps hold nothing") : nil
    }
}
