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
    /// The session: every cookie a browser would send to Privy Home's API
    /// host, by name (`PrivyHomeFeed.apiCookies`), as one JSON object in the
    /// device-only Keychain.
    private static let cookiesKey = "privy.home.cookies"

    static var cookies: [String: String] {
        guard let raw = TokenVault.get(cookiesKey), let data = raw.data(using: .utf8),
              let map = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        // A session stored before trackers were filtered out still sends only
        // what the API needs.
        return map.filter { PrivyHomeFeed.isSessionCookie($0.key) }
    }

    /// A refresh token is what keeps the session alive; an access token alone
    /// expires within minutes and cannot be renewed.
    static var connected: Bool { cookies[PrivyHomeFeed.refreshCookie] != nil }

    static func store(_ cookies: [String: String]) {
        guard let data = try? JSONEncoder().encode(cookies),
              let raw = String(data: data, encoding: .utf8) else { return }
        TokenVault.set(raw, for: cookiesKey)
    }

    /// Clears the session only. The apps already landed are the person's
    /// record, not the session's.
    static func clear() {
        TokenVault.delete(cookiesKey)
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
    private static let hiddenKey = "privy.home.hidden.v1"
    private static let showEmptyKey = "privy.home.showEmpty"

    private(set) var apps: [PrivyHomeFeed.App] = []
    private(set) var balances: [String: PrivyHomeFeed.Balance] = [:]
    /// Apps the person hid, by row ref. Only hides them here.
    private(set) var hidden: Set<String> = []
    /// Off by default: an app holding nothing and not used in 90 days is one
    /// count in the head, not a row in the feed.
    private(set) var showEmpty = false
    /// The rows the feed draws — recomputed when any input moves, so a row's
    /// filter is a set lookup, never a walk of the apps.
    private(set) var shownRefs: Set<String> = []
    private(set) var byRef: [String: PrivyHomeFeed.App] = [:]
    /// Moves whenever the head's inputs change — its memo key, because a
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
        if let data = d.data(forKey: Self.hiddenKey),
           let hidden = try? JSONDecoder().decode(Set<String>.self, from: data) {
            self.hidden = hidden
        }
        showEmpty = d.data(forKey: Self.showEmptyKey) == Data("1".utf8)
        recompute()
    }

    static var identity: String { String(shared.revision) }

    private func recompute() {
        byRef = Dictionary(apps.map { (PrivyHomeFeed.ref($0), $0) }, uniquingKeysWith: { a, _ in a })
        shownRefs = PrivyHomeFeed.shown(apps, balances: balances, hidden: hidden,
                                        showEmpty: showEmpty, now: .now)
        revision &+= 1
    }

    func setApps(_ apps: [PrivyHomeFeed.App]) {
        guard apps != self.apps else { return }
        self.apps = apps
        recompute()
        if let data = try? JSONEncoder().encode(apps) { DefaultsWrite.set(data, forKey: Self.appsKey) }
    }

    func setBalances(_ updates: [String: PrivyHomeFeed.Balance]) {
        guard !updates.isEmpty else { return }
        balances.merge(updates) { _, new in new }
        recompute()
        if let data = try? JSONEncoder().encode(balances) {
            DefaultsWrite.set(data, forKey: Self.balancesKey)
        }
    }

    func setShowEmpty(_ on: Bool) {
        guard on != showEmpty else { return }
        showEmpty = on
        recompute()
        DefaultsWrite.set(Data((on ? "1" : "0").utf8), forKey: Self.showEmptyKey)
    }

    func setHidden(_ ref: String, _ isHidden: Bool) {
        if isHidden { hidden.insert(ref) } else { hidden.remove(ref) }
        recompute()
        if let data = try? JSONEncoder().encode(hidden) { DefaultsWrite.set(data, forKey: Self.hiddenKey) }
    }

    /// Whether the feed draws this row. Not a Privy app row: always.
    func shows(_ thing: Thing) -> Bool {
        guard let ref = thing.sourceRef, ref.hasPrefix(PrivyHomeFeed.refPrefix) else { return true }
        // Before the first read in this install there is nothing to judge by.
        return apps.isEmpty || shownRefs.contains(ref)
    }

    func usd(_ ref: String) -> Double? {
        byRef[ref].flatMap { PrivyHomeFeed.appUSD($0, balances: balances) }
    }

    /// Signing out forgets what the session read; the landed rows stay, and
    /// so do the person's own hide choices.
    func forget() {
        apps = []
        balances = [:]
        recompute()
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

    /// What the last session read tried, as SHAPE: each attempt's status and
    /// Privy's error `code` — never a token. Shown by `-privyProbe` and in the
    /// DEBUG log, because a refusal right after a good sign-in has more than
    /// one cause and each wants a different fix.
    @MainActor private(set) static var lastTrace: [String] = []

    /// `privy_home/me` with the whole session, renewed once when refused.
    /// The refusal that clears the session is the renewal's.
    @MainActor
    private static func readMe() async -> (json: Any?, status: Int) {
        lastTrace = []
        let session = PrivyHomeAuth.cookies
        trace("session cookies=\(session.keys.sorted().joined(separator: ","))")
        if let bearer = PrivyHomeFeed.bearer(session) {
            trace("access \(PrivyHomeFeed.describe(jwt: bearer, now: .now))")
        }
        let first = await get(PrivyHomeFeed.meURL)
        guard first.status == 401 || first.status == 403 else { return first }
        let renewed = await renew()
        guard renewed == 200 else { return (nil, renewed) }
        return await get(PrivyHomeFeed.meURL)
    }

    @MainActor
    private static func trace(_ line: String) {
        lastTrace.append(line)
        #if DEBUG
        NSLog("[Casberi] privy| %@", line)
        #endif
    }

    @MainActor
    private static func get(_ url: String) async -> (json: Any?, status: Int) {
        let session = PrivyHomeAuth.cookies
        var headers = PrivyHomeFeed.headers
        headers["Cookie"] = PrivyHomeFeed.cookieHeader(session)
        let (json, status) = await IngestSupport.getJSONBody(
            url, auth: PrivyHomeFeed.bearer(session).map { "Bearer \($0)" },
            headers: headers, service: PrivyHomeFeed.source)
        trace("me → \(status)\(PrivyHomeFeed.errorCode(json).map { " " + $0 } ?? "")")
        return (status == 200 ? json : nil, status)
    }

    /// The page's own renewal: `POST /sessions` with the whole session — the
    /// cookie mode's body word first, then the refresh token in the body,
    /// because which one Privy Home wants was not measured. Every `Set-Cookie`
    /// is merged into the stored session by name. Cookies are handled by hand
    /// so the rotated session never lands in the shared cookie store.
    @MainActor
    private static func renew() async -> Int {
        guard let refresh = PrivyHomeAuth.cookies[PrivyHomeFeed.refreshCookie] else { return 401 }
        var last = 401
        for bodyToken in ["deprecated", refresh] {
            let status = await renew(bodyToken: bodyToken, label: bodyToken == refresh ? "body" : "cookie")
            if status == 200 { return 200 }
            last = status
            guard status == 401 || status == 403 || status == 400 else { return status }
        }
        return last
    }

    @MainActor
    private static func renew(bodyToken: String, label: String) async -> Int {
        let session = PrivyHomeAuth.cookies
        guard let url = URL(string: PrivyHomeFeed.sessionsURL),
              let body = try? JSONSerialization.data(withJSONObject: ["refresh_token": bodyToken])
        else { return 0 }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (field, value) in PrivyHomeFeed.headers { request.setValue(value, forHTTPHeaderField: field) }
        request.setValue(PrivyHomeFeed.cookieHeader(session), forHTTPHeaderField: "Cookie")
        if let bearer = PrivyHomeFeed.bearer(session) {
            request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        }
        guard let (data, http) = await IngestSupport.sendRequest(request, service: PrivyHomeFeed.source)
        else { trace("renew \(label) → no response"); return 0 }
        let json = try? JSONSerialization.jsonObject(with: data)
        trace("renew \(label) → \(http.statusCode)\(PrivyHomeFeed.errorCode(json).map { " " + $0 } ?? "")")
        guard http.statusCode == 200 else { return http.statusCode }
        let fields = http.allHeaderFields.reduce(into: [String: String]()) { out, pair in
            if let k = pair.key as? String, let v = pair.value as? String { out[k] = v }
        }
        let setCookies = HTTPCookie.cookies(withResponseHeaderFields: fields, for: url)
            .map { (name: $0.name, value: $0.value) }
        let rotated = PrivyHomeFeed.rotated(session, body: json, setCookies: setCookies)
        trace("renew set=\(setCookies.map(\.name).sorted().joined(separator: ","))")
        guard PrivyHomeFeed.isSession(rotated) else { return 0 }
        PrivyHomeAuth.store(rotated)
        return 200
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
        NSLog("[Casberi] privy| session: %@",
              PrivyHomeAuth.cookies.keys.sorted().joined(separator: ","))
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
