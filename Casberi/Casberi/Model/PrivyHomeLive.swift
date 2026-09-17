import Foundation
import Observation
import SwiftData

/// Privy's live door (prd §803c) — the half that touches the Keychain, the
/// network and the corpus. The parse, the URLs and everything measured are in
/// `PrivyHomeFeed`.
///
/// Read-only by construction: one GET (`privy_home/me`) and the session
/// refresh Privy's own page makes. There is no path here that could export a
/// key, add funds, or change anything at Privy — the two buttons Privy Home
/// draws for those are left out on purpose (user, 2026-09-17).
enum PrivyHomeAuth {
    private static let accessKey = "privy.home.access"
    private static let refreshKey = "privy.home.refresh"

    static var access: String? { TokenVault.get(accessKey).flatMap { $0.isEmpty ? nil : $0 } }
    static var refresh: String? { TokenVault.get(refreshKey).flatMap { $0.isEmpty ? nil : $0 } }

    /// A refresh token is what keeps the session alive; an access token alone
    /// expires within the hour and cannot be renewed.
    static var connected: Bool { refresh != nil }

    static func store(access: String?, refresh: String?) {
        if let access, !access.isEmpty { TokenVault.set(access, for: accessKey) }
        if let refresh, !refresh.isEmpty { TokenVault.set(refresh, for: refreshKey) }
    }

    /// Clears the session only. The apps already landed are the person's
    /// record, not the session's.
    static func clear() {
        TokenVault.delete(accessKey)
        TokenVault.delete(refreshKey)
    }
}

/// What the last read knew — the app list and each wallet's balance. Not a
/// secret (names and public addresses), kept in `UserDefaults` beside the
/// wallet store's own state, and observed by the room head.
@MainActor @Observable
final class PrivyHomeStore {
    static let shared = PrivyHomeStore()

    private static let appsKey = "privy.home.apps.v1"
    private static let balancesKey = "privy.home.balances.v1"

    private(set) var apps: [PrivyHomeFeed.App] = []
    private(set) var balances: [String: PrivyHomeFeed.Balance] = [:]
    /// Moves whenever either changes — the room head's memo key, because a
    /// balance landing lands no row (the Hegotá note in `FeedScreen`).
    private(set) var revision = 0

    private init() {
        let d = UserDefaults.standard
        if let data = d.data(forKey: Self.appsKey),
           let apps = try? JSONDecoder().decode([PrivyHomeFeed.App].self, from: data) {
            self.apps = apps
        }
        if let data = d.data(forKey: Self.balancesKey),
           let balances = try? JSONDecoder().decode([String: PrivyHomeFeed.Balance].self, from: data) {
            self.balances = balances
        }
    }

    static var identity: String { String(shared.revision) }

    func setApps(_ apps: [PrivyHomeFeed.App]) {
        guard apps != self.apps else { return }
        self.apps = apps
        revision &+= 1
        if let data = try? JSONEncoder().encode(apps) { DefaultsWrite.set(data, forKey: Self.appsKey) }
    }

    func setBalances(_ updates: [String: PrivyHomeFeed.Balance]) {
        guard !updates.isEmpty else { return }
        balances.merge(updates) { _, new in new }
        revision &+= 1
        if let data = try? JSONEncoder().encode(balances) {
            DefaultsWrite.set(data, forKey: Self.balancesKey)
        }
    }

    /// Signing out forgets what the session read; the landed rows stay.
    func forget() {
        apps = []
        balances = [:]
        revision &+= 1
        DefaultsWrite.remove(Self.appsKey)
        DefaultsWrite.remove(Self.balancesKey)
    }

    var room: PrivyHomeFeed.Room { PrivyHomeFeed.room(apps, balances: balances, now: .now) }
}

enum PrivyHomeLive {
    @MainActor private static var running = false
    @MainActor private(set) static var lastFailure: PrivyHomeFeed.Failure?

    /// Lands one row per app and reads the wallets' balances. nil = couldn't
    /// run; otherwise how many apps are new. Only a refusal clears the
    /// session (§711).
    @MainActor
    @discardableResult
    static func refresh(context: ModelContext, now: Date = .now) async -> Int? {
        guard PrivyHomeAuth.connected else {
            lastFailure = .noSession
            return nil
        }
        guard !running else { return 0 }
        running = true
        defer { running = false }
        lastFailure = nil

        let (json, status) = await readMe()
        if let failure = PrivyHomeFeed.classify(status: status) {
            if case .refused = failure { PrivyHomeAuth.clear() }
            lastFailure = failure
            return nil
        }
        guard let apps = PrivyHomeFeed.apps(json) else {
            lastFailure = .drifted
            return nil
        }
        PrivyHomeStore.shared.setApps(apps)
        let added = land(apps, context: context, now: now)
        await readBalances(apps, now: now)
        return added
    }

    // MARK: - The session

    /// `privy_home/me`, renewing the session once if the access token has
    /// expired. The refresh's own refusal is the session's.
    @MainActor
    private static func readMe() async -> (json: Any?, status: Int) {
        if PrivyHomeAuth.access != nil {
            let first = await get(PrivyHomeFeed.meURL)
            guard first.status == 401 else { return first }
        }
        let renewed = await renew()
        guard renewed == 200 else { return (nil, renewed) }
        return await get(PrivyHomeFeed.meURL)
    }

    @MainActor
    private static func get(_ url: String) async -> (json: Any?, status: Int) {
        var headers = PrivyHomeFeed.headers
        headers["Cookie"] = cookieHeader()
        return await IngestSupport.getJSONStatus(
            url, auth: PrivyHomeAuth.access.map { "Bearer \($0)" },
            headers: headers, service: PrivyHomeFeed.source)
    }

    /// The page's own renewal: `POST /sessions` with the refresh token, both as
    /// the body and as the cookie Privy's cookie mode reads. The rotated pair
    /// replaces the stored one. Cookies are handled by hand so the rotated
    /// session never lands in the shared cookie store.
    @MainActor
    private static func renew() async -> Int {
        guard let refresh = PrivyHomeAuth.refresh,
              let url = URL(string: PrivyHomeFeed.sessionsURL),
              let body = try? JSONSerialization.data(withJSONObject: ["refresh_token": refresh])
        else { return 401 }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (field, value) in PrivyHomeFeed.headers { request.setValue(value, forHTTPHeaderField: field) }
        request.setValue(cookieHeader(), forHTTPHeaderField: "Cookie")
        if let access = PrivyHomeAuth.access {
            request.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
        }
        guard let (data, http) = await IngestSupport.sendRequest(request, service: PrivyHomeFeed.source)
        else { return 0 }
        guard http.statusCode == 200 else { return http.statusCode }
        let fields = http.allHeaderFields.reduce(into: [String: String]()) { out, pair in
            if let k = pair.key as? String, let v = pair.value as? String { out[k] = v }
        }
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: fields, for: url)
            .map { (name: $0.name, value: $0.value) }
        let pair = PrivyHomeFeed.rotated(body: try? JSONSerialization.jsonObject(with: data),
                                         cookies: cookies)
        guard pair.access != nil || pair.refresh != nil else { return 0 }
        PrivyHomeAuth.store(access: pair.access, refresh: pair.refresh)
        return 200
    }

    @MainActor
    private static func cookieHeader() -> String {
        var parts: [String] = []
        if let access = PrivyHomeAuth.access {
            parts.append("privy-token=\(access)")
            parts.append("privy-access-token=\(access)")
        }
        if let refresh = PrivyHomeAuth.refresh { parts.append("\(PrivyHomeFeed.refreshCookie)=\(refresh)") }
        return parts.joined(separator: "; ")
    }

    // MARK: - Landing

    /// One row per app, dated the day the wallet was made — so a first sync
    /// files two years of apps into the past rather than onto today, and a new
    /// app arrives at the top on the day it is made (the notification's
    /// window, `NotifySweep`). A renamed app is rewritten in place.
    @MainActor
    private static func land(_ apps: [PrivyHomeFeed.App], context: ModelContext, now: Date) -> Int {
        var existing = IngestSupport.thingsByRef(context, source: PrivyHomeFeed.source)
        var added = 0
        var touched = false
        var indexed: [Thing] = []
        for app in apps {
            let ref = PrivyHomeFeed.ref(app)
            let line = PrivyHomeFeed.line(app)
            if let thing = existing[ref] {
                guard thing.isLive, thing.title != app.name || thing.content != line else { continue }
                thing.title = app.name
                thing.content = line
                thing.embedding = nil
                indexed.append(thing)
                touched = true
                continue
            }
            let thing = Thing(kind: .event,
                              title: app.name,
                              content: line,
                              source: PrivyHomeFeed.source,
                              capturedAt: app.createdAt ?? now,
                              sourceRef: ref)
            context.insert(thing)
            existing[ref] = thing
            indexed.append(thing)
            added += 1
        }
        SpotlightIndex.index(indexed.filter(\.isLive))
        if added > 0 || touched { context.saveHonestly() }
        return added
    }

    // MARK: - Balances

    /// Reads the wallets `PrivyHomeFeed.toRead` picks, four at a time. A
    /// wallet the chain did not answer for is left as it was — never stored
    /// as empty.
    @MainActor
    private static func readBalances(_ apps: [PrivyHomeFeed.App], now: Date) async {
        let targets = PrivyHomeFeed.toRead(apps, balances: PrivyHomeStore.shared.balances, now: now)
        guard !targets.isEmpty else { return }
        let results = await IngestSupport.boundedGather(targets, maxConcurrent: 4) { address in
            await WalletIngest.unwatchedHoldings(address: address)
        }
        var updates: [String: PrivyHomeFeed.Balance] = [:]
        for (address, result) in zip(targets, results) {
            guard let result else { continue }
            updates[PrivyHomeFeed.key(address)] = .init(usd: result.totalUSD,
                                                        bySymbol: result.bySymbol,
                                                        readAt: now)
        }
        PrivyHomeStore.shared.setBalances(updates)
    }

    // MARK: - Probe

    /// `-privyProbe YES`: the seat end to end, as shape. Counts and key names,
    /// never a token, an address or an amount.
    @MainActor
    static func diagnose(context: ModelContext) async {
        NSLog("[Casberi] privy| session: access=%@ refresh=%@",
              PrivyHomeAuth.access == nil ? "no" : "yes",
              PrivyHomeAuth.refresh == nil ? "no" : "yes")
        guard PrivyHomeAuth.connected else {
            NSLog("[Casberi] privy| NOT CONNECTED — sign in from Privy's account page")
            return
        }
        let (json, status) = await readMe()
        NSLog("[Casberi] privy| me → %d, top keys: %@", status,
              ((json as? [String: Any])?.keys.sorted() ?? []).joined(separator: ","))
        if let apps = PrivyHomeFeed.apps(json) {
            let wallets = apps.reduce(0) { $0 + $1.wallets.count }
            let dated = apps.filter { $0.createdAt != nil }.count
            NSLog("[Casberi] privy| apps=%d wallets=%d dated=%d", apps.count, wallets, dated)
            if let user = (json as? [String: Any])?["user"] as? [String: Any],
               let first = (user["apps"] as? [Any])?.first as? [String: Any] {
                NSLog("[Casberi] privy| app keys: %@", first.keys.sorted().joined(separator: ","))
                if let accounts = first["accounts"] as? [Any],
                   let account = accounts.first as? [String: Any] {
                    NSLog("[Casberi] privy| account keys: %@", account.keys.sorted().joined(separator: ","))
                }
            }
        } else if status == 200 {
            NSLog("[Casberi] privy| DRIFTED — 200 without user.apps")
        }
        let landed = await refresh(context: context)
        NSLog("[Casberi] privy| refresh → %@ failure=%@",
              landed.map(String.init) ?? "nil", String(describing: lastFailure))
        let room = PrivyHomeStore.shared.room
        NSLog("[Casberi] privy| room: apps=%d read=%d funded=%d recent=%d",
              room.appCount, room.readCount, room.fundedCount, room.recentCount)
    }
}
