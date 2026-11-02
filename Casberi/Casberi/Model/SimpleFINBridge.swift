import Foundation
import ImageIO
import SwiftData
import UIKit

/// SIMPLEFIN (2026-11-02, prd §1663) — the person's banks and cards, through
/// SimpleFIN Bridge, a service THEY subscribe to (about $1.50 a month, billed
/// to them) and connect their banks at.
///
/// ## Why this passes §278 when Plaid does not
///
/// The credential is issued to the PERSON: they make a one-time Setup Token on
/// the bridge, the phone claims it for an Access URL, and every read after
/// that goes from this iPhone to the bridge with that URL's own credentials.
/// Nothing authenticates as Casberi and no server of ours is in the chain —
/// §278 named it the one aggregator shape that passes, and §778 built it once
/// and removed it for the subscription's cost alone. The person decides that
/// now (user, 2026-11-02: "user can pay if they want and at least we have it").
///
/// ## What it reads
///
/// One request per pass: `GET <access>/accounts?version=2&start-date=…`.
/// Balances are a STATE (§216): they compose into `SimpleFINStanding` and the
/// Wallet's cash (`WalletCash`), never a row. Posted transactions land as
/// rows; a pending one is not asked for, because nothing promises it keeps
/// its id when it posts, and a row landed twice is a purchase counted twice.
///
/// ## The bridge's rate is a hard ceiling
///
/// It expects about 24 reads a day per token and DISABLES a token that keeps
/// going past it, so no pass asks within `SimpleFINShape.readGap` of the last
/// one, on any door. The Access URL stays on this device
/// (`TokenVault.localTokenBridges`): two devices reading one token would
/// spend one quota twice, and a Mac makes its own token in a minute.
///
/// ## Nothing here can move money
///
/// The protocol has no write at all. Do not add one.
enum SimpleFINAuth {

    static var tokenVaultKey: String { TokenBridge.simplefin.tokenKey }

    /// The Access URL, credentials and all. Never logged, never shown.
    static var storedAccess: SimpleFINShape.Access? {
        TokenVault.get(tokenVaultKey).flatMap(SimpleFINShape.access)
    }

    static var configured: Bool { storedAccess != nil }

    static func clear() {
        TokenVault.delete(tokenVaultKey)
        SimpleFINState.clear()
        SimpleFINLogos.clear()
    }
}

// MARK: - The reads

enum SimpleFINFetch {

    enum Claim: Equatable {
        case access(String)
        /// 403: already claimed, or never existed. The spec asks that the
        /// person hear it may have been claimed by someone else.
        case used
        case refused(Int)
        case unreachable
    }

    /// The one POST this seat makes — the claim, which is the protocol's own
    /// exchange of a token for an address, never a write to an account.
    static func claim(_ url: URL) async -> Claim {
        let (text, status) = await IngestSupport.postText(url, service: SimpleFINShape.source)
        switch status {
        case 200:
            guard let text, SimpleFINShape.isAccessURL(text) else { return .refused(status) }
            return .access(text.trimmingCharacters(in: .whitespacesAndNewlines))
        case 0:   return .unreachable
        case 403: return .used
        default:  return .refused(status)
        }
    }

    static func accounts(_ access: SimpleFINShape.Access, startDate: Int? = nil,
                         balancesOnly: Bool = false) async -> (set: SimpleFINShape.AccountSet?, status: Int) {
        var url = "\(access.base)/accounts?version=2"
        if let startDate { url += "&start-date=\(startDate)" }
        if balancesOnly { url += "&balances-only=1" }
        let (json, status) = await IngestSupport.getJSONStatus(
            url, auth: access.authorization, service: SimpleFINShape.source)
        guard status == 200 else { return (nil, status) }
        return (SimpleFINShape.accountSet(json), status)
    }
}

// MARK: - The banks' marks

/// Each bank's own icon (user, 2026-11-02: "logo is good too"). SimpleFIN
/// sends a bank's NAME and its website, never a logo, so the icon is asked of
/// the bank's own site at the addresses a browser asks
/// (`SimpleFINShape.iconCandidates`) — no logo service learns which bank you
/// use. Measured 2026-11-02 on eight US banks: six serve one 32px or larger
/// (Capital One, Amex and Discover a 150px+ touch icon, Chase 60px, Wells
/// Fargo 48px, Ally 32px); Bank of America and Schwab serve 16px only, which
/// is refused, so they keep SimpleFIN's mark rather than a blur.
enum SimpleFINLogos {

    /// Posted with the connection id when its icon lands, so a mark already
    /// on screen trades SimpleFIN's for the bank's.
    static let arrived = Notification.Name("SimpleFINLogos.arrived")

    /// Smaller than this draws as a smear at a row's size.
    static let minimumSide = 32
    /// A bank whose site had none is asked again after this.
    static let retryAfter: TimeInterval = 7 * 86_400

    private static let triedKey = "simplefin.logoTried"
    private static var memory: [String: UIImage] = [:]
    private static let lock = NSLock()

    private static func forgetMemory() {
        lock.lock(); defer { lock.unlock() }
        memory = [:]
    }

    private static var directory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("SimpleFINMarks", isDirectory: true)
    }

    private static func file(_ connID: String) -> URL? {
        let name = connID.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? connID
        return directory?.appendingPathComponent(name + ".png")
    }

    /// The bank's icon, or nil. Reads a small file once, then memory; call it
    /// from a `.task`, never a body.
    static func image(connID: String) -> UIImage? {
        lock.lock(); defer { lock.unlock() }
        if let held = memory[connID] { return held }
        guard let url = file(connID), let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else { return nil }
        memory[connID] = image
        return image
    }

    static func fetchMissing(_ connections: [SimpleFINShape.Connection]) async {
        var tried = UserDefaults.standard.dictionary(forKey: triedKey) as? [String: Double] ?? [:]
        let now = Date().timeIntervalSince1970
        for connection in connections {
            guard let url = file(connection.id),
                  !FileManager.default.fileExists(atPath: url.path),
                  now - (tried[connection.id] ?? 0) >= retryAfter else { continue }
            tried[connection.id] = now
            for candidate in SimpleFINShape.iconCandidates(orgURL: connection.url) {
                guard let data = await IngestSupport.getData(candidate, service: SimpleFINShape.source),
                      let png = largestFrame(data) else { continue }
                if let dir = directory {
                    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                }
                try? png.write(to: url, options: .atomic)
                await MainActor.run {
                    NotificationCenter.default.post(name: SimpleFINLogos.arrived, object: connection.id)
                }
                break
            }
        }
        UserDefaults.standard.set(tried, forKey: triedKey)
    }

    /// The largest frame an icon file holds (an `.ico` carries several), as
    /// PNG, or nil when it is no image or none reaches `minimumSide` — a 200
    /// that is an HTML page included.
    static func largestFrame(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        var best: CGImage?
        for i in 0..<CGImageSourceGetCount(source) {
            guard let frame = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            if frame.width > (best?.width ?? 0) { best = frame }
        }
        guard let best, min(best.width, best.height) >= minimumSide else { return nil }
        return UIImage(cgImage: best).pngData()
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: triedKey)
        forgetMemory()
        if let dir = directory { try? FileManager.default.removeItem(at: dir) }
    }
}

// MARK: - Connecting

enum SimpleFINConnect {

    enum Outcome: Equatable {
        case connected
        case notAToken
        case used
        case refused
        case unreachable
    }

    /// A pasted Setup Token, claimed; or a pasted Access URL, checked. Either
    /// way the Access URL is stored only once the bridge has ANSWERED with it
    /// (a read that comes back 200), so a seat never reads connected on a
    /// credential nothing has accepted (§83). The page and `-simplefinConnect`
    /// share this, so the probe drives the path the person does.
    @MainActor
    static func connect(_ raw: String) async -> Outcome {
        let pasted = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let accessText: String
        let claimed: Bool
        if SimpleFINShape.isAccessURL(pasted) {
            accessText = pasted
            claimed = false
        } else if let claimURL = SimpleFINShape.claimURL(fromSetupToken: pasted) {
            switch await SimpleFINFetch.claim(claimURL) {
            case .access(let text): accessText = text
            case .used:             return .used
            case .refused:          return .refused
            case .unreachable:      return .unreachable
            }
            claimed = true
        } else {
            return .notAToken
        }
        guard let access = SimpleFINShape.access(accessText) else { return .notAToken }
        // The check reads balances only: the one request that proves the
        // credential, and the forced first pass reads the rest.
        let (set, status) = await SimpleFINFetch.accounts(access, balancesOnly: true)
        if set == nil {
            // A refused credential is never kept. A CLAIMED one the check
            // could not otherwise finish is: its token is spent, so dropping
            // the URL would lose the connection for good, and the first pass
            // says what went wrong in its own words.
            if status == 403 { return .refused }
            if !claimed { return status == 0 ? .unreachable : .refused }
        }
        SimpleFINState.clear()
        TokenVault.set(accessText, for: SimpleFINAuth.tokenVaultKey)
        return .connected
    }

    /// What the page says for each outcome but the good one.
    static func sentence(_ outcome: Outcome) -> String? {
        switch outcome {
        case .connected:   nil
        case .notAToken:   String(localized: "That isn't a SimpleFIN Setup Token. Copy the whole token from SimpleFIN Bridge.")
        case .used:        String(localized: "That token was already claimed. If you didn't claim it, turn it off at SimpleFIN Bridge, then make a new one.")
        case .refused:     String(localized: "SimpleFIN refused that connection. Make a new Setup Token and paste it here.")
        case .unreachable: String(localized: "Couldn't reach SimpleFIN — check your connection.")
        }
    }
}

// MARK: - Standing (a STATE, §216 — never a row)

struct SimpleFINStanding: Codable, Equatable {
    struct Account: Codable, Equatable {
        var id: String
        var name: String
        var institution: String?
        var connID: String?
        var currency: String?
        var balance: Double?

        /// "Chase · Total Checking" (`SimpleFINShape.accountLabel`).
        var label: String { SimpleFINShape.accountLabel(name: name, institution: institution) }
    }

    var accounts: [Account] = []
    var lastRead: Date?
    /// What the bridge said on the last read (`errlist`), shown as it said it.
    var messages: [String] = []

    static let empty = SimpleFINStanding()

    /// "Chase · 3 accounts": the institutions read, for the seat's proof.
    var institutions: [String] {
        var seen: [String] = []
        for name in accounts.compactMap(\.institution) where !seen.contains(name) { seen.append(name) }
        return seen
    }
}

enum SimpleFINState {
    private static let standingKey = "simplefin.standing"
    private static let cursorKey = "simplefin.cursor"
    private static let askedKey = "simplefin.asked"

    static var standing: SimpleFINStanding {
        get {
            guard let data = UserDefaults.standard.data(forKey: standingKey),
                  let value = try? JSONDecoder().decode(SimpleFINStanding.self, from: data)
            else { return .empty }
            return value
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            UserDefaults.standard.set(data, forKey: standingKey)
        }
    }

    /// The newest posted date landed; the next window reaches back from it.
    static var cursor: Date? {
        get { date(cursorKey) }
        set { UserDefaults.standard.set(newValue?.timeIntervalSince1970 ?? 0, forKey: cursorKey) }
    }

    /// When the bridge was last asked, answered or not — the rate's clock.
    static var lastAsked: Date? {
        get { date(askedKey) }
        set { UserDefaults.standard.set(newValue?.timeIntervalSince1970 ?? 0, forKey: askedKey) }
    }

    private static func date(_ key: String) -> Date? {
        let t = UserDefaults.standard.double(forKey: key)
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    /// Everything but the rate's clock: a fresh token is a fresh quota, but
    /// a Remove and a paste a second later must not read twice in a minute
    /// on one that may be the same.
    static func clear() {
        UserDefaults.standard.removeObject(forKey: standingKey)
        UserDefaults.standard.removeObject(forKey: cursorKey)
    }
}

// MARK: - The pass

enum SimpleFINIngest {

    @MainActor private static var running = false
    @MainActor private(set) static var lastPassFailure: String?

    /// One pass. Returns rows landed (0 when the rate says not yet), or nil
    /// when the read could not run — the screen says which.
    @MainActor
    @discardableResult
    static func refresh(context: ModelContext, force: Bool = false) async -> Int? {
        guard !running else { return 0 }
        guard let access = SimpleFINAuth.storedAccess else { return nil }
        guard SimpleFINShape.mayRead(lastAsked: SimpleFINState.lastAsked, now: .now, force: force)
        else { return 0 }
        running = true
        defer { running = false }

        SimpleFINState.lastAsked = .now
        let start = SimpleFINShape.startDate(cursor: SimpleFINState.cursor, now: .now)
        let (set, status) = await SimpleFINFetch.accounts(access, startDate: start)
        guard let set else {
            lastPassFailure = failure(status)
            return nil
        }
        lastPassFailure = nil

        let institutions = Dictionary(set.connections.map { ($0.id, $0) },
                                      uniquingKeysWith: { a, _ in a })
        var standing = SimpleFINStanding()
        standing.lastRead = .now
        standing.messages = set.messages
        standing.accounts = set.accounts.map {
            .init(id: $0.id, name: $0.name,
                  institution: $0.connID.flatMap { institutions[$0]?.name },
                  connID: $0.connID, currency: $0.currency, balance: $0.balance)
        }
        SimpleFINState.standing = standing

        let stored = IngestSupport.thingsByRef(context, source: SimpleFINShape.source)
        var seen = Set(stored.keys)
        var landed = 0
        var newest = SimpleFINState.cursor

        for account in set.accounts {
            let institution = account.connID.flatMap { institutions[$0] }
            for t in account.transactions where !t.pending {
                // A zero is no money moving (the demo sends "00.00"): never
                // a "Refunded · $0.00" row (§83).
                guard let posted = t.posted, let amount = t.amount, amount != 0,
                      let currency = account.currency else { continue }
                let ref = SimpleFINShape.ref(conn: account.connID, account: account.id, transaction: t.id)
                guard seen.insert(ref).inserted else { continue }
                let money = AppleWalletRoom.money(abs(amount), currency)
                let thing = Thing(kind: .transaction,
                                  title: IngestSupport.titleLine(SimpleFINShape.rowTitle(t, money: money)),
                                  content: institution?.url ?? "",
                                  source: SimpleFINShape.source,
                                  capturedAt: posted,
                                  tags: SimpleFINShape.tags(t),
                                  sourceRef: ref)
                thing.transferCounterparty = SimpleFINShape.label(t)
                thing.transferDirection = amount < 0 ? "sent" : "received"
                thing.transferAmount = money
                thing.priceValue = abs(amount)
                thing.priceCurrency = currency
                // The account as data (prd §369's reason): the row's line and
                // the receipt's "on <account>" read it on its own.
                thing.authorHandle = SimpleFINShape.accountLabel(name: account.name,
                                                                 institution: institution?.name)
                thing.summary = SimpleFINShape.statementLine(t).map(IngestSupport.titleLine)
                // Retrieval-only (2026-07-15): the bank and the raw lines, so
                // the descriptor on a statement still finds the row.
                let enriched = [institution?.name, t.description, t.memo].compactMap { $0 }
                thing.enrichedText = enriched.isEmpty ? nil : enriched.joined(separator: " · ")
                context.insert(thing)
                SpotlightIndex.index([thing])
                landed += 1
                if newest == nil || posted > newest! { newest = posted }
            }
        }

        if let newest { SimpleFINState.cursor = newest }
        if landed > 0 { context.saveHonestly() }
        // Each bank's icon, once, from the bank's own site — never the
        // bridge's, so it costs none of the day's reads — after the pass, so
        // a slow bank site never holds the page's "Reading".
        let connections = set.connections
        Task { await SimpleFINLogos.fetchMissing(connections) }
        return landed
    }

    /// The sentence for a read that failed, by its cause.
    static func failure(_ status: Int) -> String {
        switch status {
        case 0:   String(localized: "Couldn't reach SimpleFIN — check your connection.")
        case 402: String(localized: "Your SimpleFIN subscription has lapsed. Renew it at SimpleFIN Bridge and this reads again.")
        case 403: String(localized: "SimpleFIN no longer accepts this connection. It may have been turned off at SimpleFIN Bridge; make a new Setup Token to connect again.")
        default:  String(localized: "SimpleFIN didn't answer as expected (\(status)).")
        }
    }
}

// MARK: - The seat

enum SimpleFINWatch {
    @MainActor
    static func registerBridge(store: BridgeStore) {
        guard SimpleFINAuth.configured else {
            store.remove(TokenBridge.simplefin.bridgeID)
            return
        }
        // No money in the line: it is drawn in Apps, and money is the
        // Wallet's alone (prd §1111). The banks it reads prove the read.
        let standing = SimpleFINState.standing
        let banks = standing.institutions
        let proof = banks.isEmpty
            ? (standing.accounts.isEmpty ? String(localized: "Connected")
                                         : String(localized: "\(standing.accounts.count) accounts"))
            : banks.prefix(2).joined(separator: " · ") + (banks.count > 2 ? " +\(banks.count - 2)" : "")
        store.registerConnected(id: TokenBridge.simplefin.bridgeID,
                                name: SimpleFINShape.source, proof: proof)
    }
}

// MARK: - Probe

extension SimpleFINFetch {

    /// `-simplefinProbe YES` — one read with the STORED Access URL, by shape:
    /// statuses, counts, field names, and how many outflows carry an `mcc`
    /// (the one fact Spending rests on that the demo could not settle). It
    /// never prints the URL, a name, a balance or an amount. It spends one of
    /// the token's ~24 daily reads, and the pass's rate clock is stamped.
    static func probe() async {
        guard let access = SimpleFINAuth.storedAccess else {
            NSLog("[Casberi] simplefinProbe: no stored access (connect via -simplefinConnect \"<setup token>\")")
            return
        }
        SimpleFINState.lastAsked = .now
        let start = SimpleFINShape.startDate(cursor: nil, now: .now)
        let (json, status) = await IngestSupport.getJSONStatus(
            "\(access.base)/accounts?version=2&start-date=\(start)",
            auth: access.authorization, service: SimpleFINShape.source)
        let root = json as? [String: Any]
        let set = SimpleFINShape.accountSet(json)
        NSLog("[Casberi] simplefinProbe: HTTP %d · top={%@} · %d connections · %d accounts · %d messages",
              status, SimpleFINShape.keyNames(root).joined(separator: ","),
              set?.connections.count ?? 0, set?.accounts.count ?? 0, set?.messages.count ?? 0)
        let rows = root?["accounts"] as? [[String: Any]] ?? []
        for (i, row) in rows.enumerated() {
            let account = set?.accounts.first { $0.id == SimpleFINShape.text(row["id"]) }
            let txns = account?.transactions ?? []
            let outs = txns.filter { ($0.amount ?? 0) < 0 }
            NSLog("[Casberi] simplefinAccount| #%d fields={%@} currency=%@ balance=%@ sign=%@ txns=%d out=%d outWithMCC=%d pending=%d",
                  i, SimpleFINShape.keyNames(row).joined(separator: ","),
                  account?.currency ?? "custom",
                  account?.balance == nil ? "unparsed" : "parsed",
                  (account?.balance ?? 0) < 0 ? "negative" : "positive",
                  txns.count, outs.count, outs.filter { $0.mcc != nil }.count,
                  txns.filter(\.pending).count)
            if let first = (row["transactions"] as? [[String: Any]])?.first {
                NSLog("[Casberi] simplefinTxn| fields={%@}", SimpleFINShape.keyNames(first).joined(separator: ","))
            }
        }
    }
}
