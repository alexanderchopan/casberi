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
    /// v2 (§803j): every v1 balance was read under the Wallet seat's $1.99
    /// floor and says $0 for a wallet holding $1.37, so none of it is kept —
    /// a new key means every wallet is read again, 30 a pass.
    /// v3: v2 could hold the demo's zeros, stored as real reads.
    private static let balancesKey = "privy.home.balances.v3"
    private static let hiddenKey = "privy.home.hidden.v1"
    private static let showEmptyKey = "privy.home.showEmpty"
    private static let activityReadKey = "privy.home.activityRead.v1"
    private static let activityCountKey = "privy.home.activityCount"

    private(set) var apps: [PrivyHomeFeed.App] = []
    private(set) var balances: [String: PrivyHomeFeed.Balance] = [:]
    /// Apps the person hid, by row ref. Only hides them here.
    private(set) var hidden: Set<String> = []
    /// Off by default: an app holding nothing and not used in 90 days is one
    /// count in the head, not a row in the feed.
    private(set) var showEmpty = false
    /// On by default (user, 2026-09-17: "oh, ofc do it"): the Wallet room's
    /// combined total counts what your app wallets hold. Display only.
    /// The rows the feed draws — recomputed when any input moves, so a row's
    /// filter is a set lookup, never a walk of the apps.
    private(set) var shownRefs: Set<String> = []
    private(set) var byRef: [String: PrivyHomeFeed.App] = [:]
    private(set) var byID: [String: PrivyHomeFeed.App] = [:]
    /// When each wallet's activity was last read.
    private(set) var activityReadAt: [String: Date] = [:]
    /// How many activity rows have ever landed — whether the Activity tile
    /// has anything behind it.
    private(set) var activityCount = 0
    /// The room's picked section. Not persisted: the room opens on Apps.
    var section: PrivyHomeFeed.Section = .apps {
        didSet { if section != oldValue { revision &+= 1 } }
    }
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
        if let data = d.data(forKey: Self.activityReadKey),
           let read = try? JSONDecoder().decode([String: Date].self, from: data) {
            activityReadAt = read
        }
        activityCount = d.data(forKey: Self.activityCountKey)
            .flatMap { Int(String(decoding: $0, as: UTF8.self)) } ?? 0
        recompute()
    }

    static var identity: String { String(shared.revision) }

    private func recompute() {
        byRef = Dictionary(apps.map { (PrivyHomeFeed.ref($0), $0) }, uniquingKeysWith: { a, _ in a })
        byID = Dictionary(apps.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
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

    // `walletHoldings` and the "Count in Wallet total" toggle are DELETED
    // (prd §826, user: "do not combine privy with the regular wallet balance
    // leave privy separate"). They were the only readers of `countsInWallet`,
    // so the flag, its default and its stored key go with them — a feature off
    // the surface is deleted from the model (§723), or it is a dead control one
    // layer down. An app's money is stated in THIS room, beside the app that
    // holds it; `PrivyHomeStore.room` is where that total lives.

    func setHidden(_ ref: String, _ isHidden: Bool) {
        if isHidden { hidden.insert(ref) } else { hidden.remove(ref) }
        recompute()
        if let data = try? JSONEncoder().encode(hidden) { DefaultsWrite.set(data, forKey: Self.hiddenKey) }
    }

    func forgetActivityReads(_ addresses: [String], cleared: Int) {
        for address in addresses { activityReadAt.removeValue(forKey: PrivyHomeFeed.key(address)) }
        if let data = try? JSONEncoder().encode(activityReadAt) {
            DefaultsWrite.set(data, forKey: Self.activityReadKey)
        }
        activityCount = max(0, activityCount - cleared)
        revision &+= 1
        DefaultsWrite.set(Data(String(activityCount).utf8), forKey: Self.activityCountKey)
    }

    func noteActivity(read addresses: [String], landed: Int, at now: Date) {
        for address in addresses { activityReadAt[PrivyHomeFeed.key(address)] = now }
        if let data = try? JSONEncoder().encode(activityReadAt) {
            DefaultsWrite.set(data, forKey: Self.activityReadKey)
        }
        guard landed > 0 else { return }
        activityCount += landed
        revision &+= 1
        DefaultsWrite.set(Data(String(activityCount).utf8), forKey: Self.activityCountKey)
    }

    /// Whether the feed draws this row: the picked section, then — for an app
    /// row — the hide and show-empty choices. In All the section never applies.
    func shows(_ thing: Thing, inRoom: Bool) -> Bool {
        let ref = thing.sourceRef
        if inRoom, !section.allows(ref: ref) { return false }
        guard let ref, ref.hasPrefix(PrivyHomeFeed.refPrefix) else { return true }
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
        activityReadAt = [:]
        DefaultsWrite.remove(Self.activityReadKey)
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
        // The demo reaches nothing (§483): no Privy read, no chain read.
        guard !DemoMode.isActive else {
            lastFailure = .unreachable
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
        let losing = PrivyHomeFeed.appsLosingWallets(old: PrivyHomeStore.shared.apps, new: apps)
        PrivyHomeStore.shared.setApps(apps)
        if !losing.isEmpty { clearActivity(of: losing, apps: apps, context: context) }
        let added = land(apps, context: context, now: now)
        await readBalances(apps, now: now)
        let moved = await readActivity(apps, context: context, now: now)
        return added + moved
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

    // MARK: - Activity

    /// Clears the activity landed for apps whose wallet list shrank, and marks
    /// their remaining wallets unread so the next pass reads them again from
    /// the app's own wallet (§803j). Only `privy:tx:<appID>:` rows — never an
    /// app row, and never another app's.
    @MainActor
    private static func clearActivity(of appIDs: [String], apps: [PrivyHomeFeed.App],
                                      context: ModelContext) {
        let source = PrivyHomeFeed.source
        var cleared = 0
        for appID in appIDs {
            let prefix = PrivyHomeFeed.txPrefix(appID: appID)
            let descriptor = FetchDescriptor<Thing>(
                predicate: #Predicate { $0.source == source && ($0.sourceRef?.starts(with: prefix) ?? false) })
            for thing in (try? context.fetch(descriptor)) ?? [] where thing.isLive {
                context.delete(thing)
                cleared += 1
            }
        }
        let addresses = apps.filter { appIDs.contains($0.id) }.flatMap(\.wallets).map(\.address)
        PrivyHomeStore.shared.forgetActivityReads(addresses, cleared: cleared)
        if cleared > 0 { context.saveHonestly() }
        #if DEBUG
        NSLog("[Casberi] privy| cleared %d activity rows from %d app(s) whose wallets changed", cleared, appIDs.count)
        #endif
    }

    /// What moved in the wallets `PrivyHomeFeed.activityTargets` picks, off the
    /// Wallet seat's own Zerion transfer read. One row per leg, dated when it
    /// was mined, so money arriving notifies through the Wallet digest's own
    /// `moneyIn` rule (§770) and old history files into the past. A leg Zerion
    /// could not price, or worth under a cent, is not landed: on an embedded
    /// wallet nobody watches, an unpriced token is almost always a spam drop.
    @MainActor
    private static func readActivity(_ apps: [PrivyHomeFeed.App], context: ModelContext,
                                     now: Date) async -> Int {
        let store = PrivyHomeStore.shared
        let targets = PrivyHomeFeed.activityTargets(apps, balances: store.balances,
                                                    readAt: store.activityReadAt, now: now)
        guard !targets.isEmpty else { return 0 }
        let results = await IngestSupport.boundedGather(targets, maxConcurrent: 3) { target in
            await ZerionAPI.transactions(address: target.address)
        }
        var existing = IngestSupport.existingSourceRefs(context, source: PrivyHomeFeed.source)
        var landed = 0
        var readAddresses: [String] = []
        var indexed: [Thing] = []
        for (target, transfers) in zip(targets, results) {
            guard let transfers else { continue }
            readAddresses.append(target.address)
            let app = store.byID[target.appID]
            for transfer in transfers {
                guard let usd = transfer.valueUSD, usd >= PrivyHomeFeed.fundedFloor else { continue }
                let ref = PrivyHomeFeed.txRef(appID: target.appID, hash: transfer.hash,
                                              received: transfer.received, symbol: transfer.symbol)
                guard !existing.contains(ref) else { continue }
                let thing = Thing(kind: .transaction,
                                  title: PrivyHomeFeed.txTitle(received: transfer.received,
                                                               value: transfer.amount,
                                                               symbol: transfer.symbol),
                                  content: "",
                                  source: PrivyHomeFeed.source,
                                  capturedAt: transfer.when,
                                  sourceRef: ref)
                // NOT `walletAddress`: that field enrols a row in the watched
                // wallets' scope and verbs, and these wallets are not watched.
                thing.authorHandle = app?.name
                thing.previewImageURL = app?.logoURL
                thing.counterpartyAddress = transfer.counterparty
                thing.transferDirection = transfer.received ? "received" : "sent"
                thing.transferAmount = PrivyHomeFeed.amount(transfer.amount, symbol: transfer.symbol)
                thing.transferUSD = usd
                context.insert(thing)
                existing.insert(ref)
                indexed.append(thing)
                landed += 1
            }
        }
        if landed > 0 {
            SpotlightIndex.index(indexed.filter(\.isLive))
            context.saveHonestly()
        }
        store.noteActivity(read: readAddresses, landed: landed, at: now)
        return landed
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
            // Which accounts are the app's OWN wallet and which are a wallet
            // the person brought (§803j): every account's `type` and key set,
            // tallied; how many apps share one address; and how many of the
            // addresses are watched in Wallet. Counts and machine words only.
            if let user = (json as? [String: Any])?["user"] as? [String: Any],
               let list = user["apps"] as? [Any] {
                var types: [String: Int] = [:]
                var keySets: [String: Int] = [:]
                var appsPerAddress: [String: Set<String>] = [:]
                var fieldValues: [String: [String: Int]] = [:]
                for case let app as [String: Any] in list {
                    let appID = (app["id"] as? String) ?? ""
                    for case let account as [String: Any] in (app["accounts"] as? [Any]) ?? [] {
                        let type = (account["type"] as? String) ?? "none"
                        types[type, default: 0] += 1
                        keySets[account.keys.sorted().joined(separator: ","), default: 0] += 1
                        for field in ["wallet_client_type", "connector_type", "chain_type", "wallet_index", "imported"] {
                            if let v = account[field] { fieldValues[field, default: [:]]["\(v)", default: 0] += 1 }
                        }
                        if let address = account["address"] as? String, PrivyHomeFeed.isWalletAddress(address) {
                            appsPerAddress[PrivyHomeFeed.key(address), default: []].insert(appID)
                        }
                    }
                }
                NSLog("[Casberi] privy| account types: %@", types.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " "))
                for (keys, n) in keySets.sorted(by: { $0.value > $1.value }) {
                    NSLog("[Casberi] privy| account shape x%d: %@", n, keys)
                }
                for (field, values) in fieldValues {
                    NSLog("[Casberi] privy| field %@: %@", field, values.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " "))
                }
                let spread = appsPerAddress.values.map(\.count).sorted(by: >)
                NSLog("[Casberi] privy| addresses=%d, apps per address (top): %@", spread.count,
                      spread.prefix(8).map(String.init).joined(separator: ","))
                let watched = Set(WalletStore.shared.addresses.map { PrivyHomeFeed.key($0.address) })
                let shared = appsPerAddress.filter { watched.contains($0.key) }
                NSLog("[Casberi] privy| watched in Wallet: %d address(es), in %@ app(s)", shared.count,
                      shared.values.map { String($0.count) }.joined(separator: ","))
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
