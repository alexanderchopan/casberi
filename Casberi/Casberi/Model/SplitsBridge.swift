import Foundation
import SwiftData

/// SPLITS (2026-09-18, prd §820) — a team's self-custodied accounts on
/// Splits Treasury / Personal, read with a Read-scoped API key the person
/// mints in their own settings.
///
/// ## Why a key and not a sign-in
///
/// Splits publishes a versioned REST API (`api.splits.org/public/v1`) and
/// issues keys in three scopes: Read, Write and Owner. A Read key is
/// read-only on SPLITS' side — it cannot propose a transfer — which is a
/// stronger promise than any cookie session could make, and the connect
/// screen refuses a key whose `whoami` scopes are anything but `read`
/// (`SplitsShape.isReadOnly`). The web app's own sign-in is an emailed magic
/// link or a passkey bound to splits.org; neither reaches an in-app web view.
///
/// ## What lands, and what is a state
///
/// - **Accounts** land as rows (`splits:account:<address>`), one per
///   unarchived account, dated when it was made — Privy's app rows' shape
///   and reason: a first sync files them into the past, and a new account
///   arrives at the top on the day it is made.
/// - **Transactions** land as `.transaction` rows (`splits:tx:<id>`), and are
///   HEALED as their status moves: a proposal is `CREATED`/`QUEUED` until its
///   signers meet the threshold, and dedupe never revisits a known ref
///   (Wise's and Linear's reason). Inbound dust is not landed
///   (`SplitsShape.isDust`) — both transactions measured on a brand-new team
///   were address-poisoning sends under a cent.
/// - **Balances** are a STATE (§216): `SplitsStanding`, written by the pass
///   that reads them, drawn on the account page behind the balance mask.
/// - **Contacts** are the team's names for outside addresses. They carry no
///   date, so they are not a feed: they join the address book as a
///   population (`AddressBookPeople.splits`), the Twitch roster's shape.
///
/// **`walletAddress` is never stamped** (Privy's rule, §803f): it would
/// enrol an unwatched account in the watched wallets' scope and verbs.
///
/// ## Nothing here can move money
///
/// Every write Splits offers — `POST /v1/proposals/*`, `PUT
/// /v1/transactions/{id}/sign` — is absent from this file, and a Read key
/// could not issue one. Do not add a POST: it would make the page's promise
/// false.
enum SplitsAuth {
    static var tokenVaultKey: String { TokenBridge.splits.tokenKey }

    static var storedToken: String? {
        TokenVault.get(tokenVaultKey).flatMap { $0.isEmpty ? nil : $0 }
    }

    static var configured: Bool { storedToken != nil }

    static func clear() {
        TokenVault.delete(tokenVaultKey)
        SplitsState.clear()
    }
}

// MARK: - The reads

enum SplitsFetch {
    static let api = "https://api.splits.org/public"

    /// Accounts whose balances one pass reads. A team with more is read
    /// newest-made first and the page says how many were read.
    static let balanceCap = 12
    /// Rows per transactions page; `pages` bounds a first sync.
    static let pageLimit = 50
    static let firstSyncPages = 4

    private static func auth(_ token: String) -> String { "Bearer \(token)" }

    static func get(_ path: String, token: String) async -> (json: Any?, status: Int) {
        await IngestSupport.getJSONStatus(api + path, auth: auth(token), service: SplitsShape.source)
    }

    /// The key's own description, WITH the status — so the connect screen can
    /// tell a refused key (401) from a Splits it could not reach (0).
    static func whoami(token: String) async -> (SplitsShape.Whoami?, Int) {
        let (json, status) = await get("/v1/auth/whoami", token: token)
        return (SplitsShape.whoami(json), status)
    }

    static func balances(token: String, address: String) async -> [SplitsShape.Balance]? {
        let (json, status) = await get("/v1/org/accounts/\(address)/balances", token: token)
        guard status == 200 else { return nil }
        return SplitsShape.balances(json)
    }
}

// MARK: - Standing (a STATE, §216 — never a row)

struct SplitsStanding: Codable, Equatable {
    struct Account: Codable, Equatable {
        var address: String
        var name: String?
        var usd: Double?
    }

    var orgName: String?
    var accounts: [Account] = []
    var totalUSD: Double?
    /// How many accounts the team has beyond the ones whose balances were read.
    var unread: Int = 0
    /// How many balance reads failed this pass — left out of `totalUSD`, and
    /// said on the page. Optional so a standing saved before it decodes.
    var failedReads: Int?
    var contacts: [SplitsShape.Contact] = []
    /// A read that answered 200 with a body this seat could not parse, with the
    /// key names it saw (§780b) — never "Synced" over a body it did not
    /// understand.
    var unreadable: [String] = []
    var lastRead: Date?

    static let empty = SplitsStanding()
}

enum SplitsState {
    private static let standingKey = "splits.standing"
    private static let seenKey = "splits.txSeen"

    static var standing: SplitsStanding {
        get {
            guard let data = UserDefaults.standard.data(forKey: standingKey),
                  let value = try? JSONDecoder().decode(SplitsStanding.self, from: data)
            else { return .empty }
            return value
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            DefaultsWrite.set(data, forKey: standingKey)
        }
    }

    /// Whether a first sync has run — after it, one page a pass is enough.
    static var backfilled: Bool {
        get { UserDefaults.standard.bool(forKey: seenKey) }
        set { UserDefaults.standard.set(newValue, forKey: seenKey) }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: standingKey)
        UserDefaults.standard.removeObject(forKey: seenKey)
    }
}

// MARK: - The pass

enum SplitsIngest {
    @MainActor private static var running = false
    @MainActor private(set) static var lastPassFailure: String?

    /// One pass. Returns rows landed, or nil when the read could not run at
    /// all — the two are different and the page says so.
    @MainActor
    @discardableResult
    static func refresh(context: ModelContext) async -> Int? {
        guard !running else { return 0 }
        guard let token = SplitsAuth.storedToken else { return nil }
        running = true
        defer { running = false }

        let (accountsJSON, accountsStatus) = await SplitsFetch.get("/v1/org/accounts", token: token)
        guard accountsStatus == 200 else {
            lastPassFailure = accountsStatus == 0
                ? String(localized: "Couldn't reach Splits — check your connection.")
                : String(localized: "Splits refused the key. It may have been deleted — paste a new one.")
            return nil
        }
        lastPassFailure = nil

        var standing = SplitsState.standing
        standing.unreadable = []
        standing.lastRead = .now
        if let who = await SplitsFetch.whoami(token: token).0 { standing.orgName = who.orgName }

        // Accounts: rows, then the balances of the newest-made few.
        var accounts: [SplitsShape.Account] = []
        if let parsed = SplitsShape.accounts(accountsJSON) {
            accounts = parsed.filter { !$0.isArchived }
                .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        } else {
            standing.unreadable.append(unreadableLine("accounts", accountsJSON))
        }
        let read = Array(accounts.prefix(SplitsFetch.balanceCap))
        let balances = await IngestSupport.boundedGather(read, maxConcurrent: 4) { account in
            await SplitsFetch.balances(token: token, address: account.address)
        }
        standing.accounts = zip(read, balances).map { account, held in
            .init(address: account.address, name: account.name,
                  usd: held.flatMap { SplitsShape.total([$0]) })
        }
        standing.totalUSD = SplitsShape.total(balances.compactMap { $0 })
        // A read that failed is SAID, never folded into the total as nothing
        // (§83): the page names how many accounts the total leaves out.
        let failed = balances.filter { $0 == nil }.count
        standing.failedReads = failed > 0 ? failed : nil
        standing.unread = accounts.count - read.count

        // Contacts: a roster for the address book, never rows.
        let (contactsJSON, contactsStatus) = await SplitsFetch.get("/v1/contacts", token: token)
        if contactsStatus == 200 {
            if let contacts = SplitsShape.contacts(contactsJSON) {
                standing.contacts = contacts
            } else {
                standing.unreadable.append(unreadableLine("contacts", contactsJSON))
            }
        }

        // Transactions: the newest pages, healed in place.
        var transactions: [SplitsShape.Transaction] = []
        var cursor: String?
        let pages = SplitsState.backfilled ? 1 : SplitsFetch.firstSyncPages
        var transactionsRead = false
        for _ in 0..<pages {
            var path = "/v1/transactions?limit=\(SplitsFetch.pageLimit)"
            if let cursor { path += "&cursor=\(SplitsShape.queryValue(cursor))" }
            let (json, status) = await SplitsFetch.get(path, token: token)
            guard status == 200 else { break }
            guard let page = SplitsShape.transactions(json) else {
                standing.unreadable.append(unreadableLine("transactions", json))
                break
            }
            transactionsRead = true
            transactions += page.rows
            cursor = page.cursor
            if cursor == nil { break }
        }
        if transactionsRead { SplitsState.backfilled = true }
        SplitsState.standing = standing

        let landed = land(accounts: accounts, transactions: transactions, context: context)
        await healWaiting(beyond: transactions, token: token, context: context)
        return landed
    }

    /// How many stored proposals one pass re-reads by id.
    static let waitingHealCap = 10

    /// A proposal stored as waiting that this pass's pages did not reach is
    /// re-read by id, so one that was signed after 50 newer transactions
    /// arrived does not sit in Queue forever.
    @MainActor
    private static func healWaiting(beyond read: [SplitsShape.Transaction],
                                    token: String, context: ModelContext) async {
        let seen = Set(read.map { SplitsShape.ref(transaction: $0.id) })
        let stale: [(ref: String, id: String)] = IngestSupport.thingsByRef(context, source: SplitsShape.source)
            .compactMap { ref, row in
                // A demo row (`splits:tx:demo…`) is not Splits' to answer for.
                guard row.isLive, !seen.contains(ref), row.tags.contains(SplitsShape.waitingTag),
                      ref.hasPrefix(SplitsShape.txPrefix),
                      !ref.hasPrefix(SplitsShape.txPrefix + "demo") else { return nil }
                return (ref, String(ref.dropFirst(SplitsShape.txPrefix.count)))
            }
            .sorted { $0.ref < $1.ref }
        guard !stale.isEmpty else { return }
        let targets = Array(stale.prefix(waitingHealCap))
        let fetched = await IngestSupport.boundedGather(targets, maxConcurrent: 4) { target in
            let (json, status) = await SplitsFetch.get(
                "/v1/transactions/\(SplitsShape.queryValue(target.id))", token: token)
            return status == 200 ? SplitsShape.transaction(json) : nil
        }
        // Re-fetched after the awaits: the models read before them may have
        // been deleted meanwhile (liveness corollary 6).
        let stored = IngestSupport.thingsByRef(context, source: SplitsShape.source)
        var changed = false
        for tx in fetched.compactMap({ $0 }) {
            guard let row = stored[SplitsShape.ref(transaction: tx.id)] else { continue }
            if heal(row, tx) { changed = true }
        }
        if changed { context.saveHonestly() }
    }

    private static func unreadableLine(_ what: String, _ json: Any?) -> String {
        let keys = SplitsShape.keyNames(json)
        return keys.isEmpty
            ? String(localized: "Splits answered \(what) in a shape this app couldn't read.")
            : String(localized: "Splits answered \(what) in a shape this app couldn't read (fields: \(keys.joined(separator: ", "))).")
    }

    @MainActor
    private static func land(accounts: [SplitsShape.Account],
                             transactions: [SplitsShape.Transaction],
                             context: ModelContext) -> Int {
        var stored = IngestSupport.thingsByRef(context, source: SplitsShape.source)
        var landed = 0
        var changed = false
        var indexed: [Thing] = []

        for account in accounts {
            let ref = SplitsShape.ref(account: account.address)
            let title = account.name ?? WalletStore.shortAddress(account.address)
            let line = SplitsShape.accountLine(account)
            if let row = stored[ref] {
                guard row.isLive, row.title != title || row.content != line else { continue }
                row.title = title
                row.content = line
                indexed.append(row)
                changed = true
                continue
            }
            let thing = Thing(kind: .event, title: title, content: line,
                              source: SplitsShape.source,
                              capturedAt: account.createdAt ?? .now,
                              sourceRef: ref)
            context.insert(thing)
            stored[ref] = thing
            indexed.append(thing)
            landed += 1
            changed = true
        }

        for tx in transactions where !SplitsShape.isDust(tx) {
            let ref = SplitsShape.ref(transaction: tx.id)
            if let row = stored[ref] {
                if heal(row, tx) { indexed.append(row); changed = true }
                continue
            }
            let thing = Thing(kind: .transaction,
                              title: IngestSupport.titleLine(SplitsShape.rowTitle(tx)),
                              content: explorerURL(tx) ?? "",   // the door (§912); `apply` keeps it
                              source: SplitsShape.source,
                              capturedAt: tx.at ?? .now,
                              tags: SplitsShape.tags(tx),
                              sourceRef: ref)
            apply(tx, to: thing)
            context.insert(thing)
            stored[ref] = thing
            indexed.append(thing)
            landed += 1
            changed = true
        }

        SpotlightIndex.index(indexed.filter(\.isLive))
        if changed { context.saveHonestly() }
        return landed
    }

    /// Everything a transaction row carries beyond its title, in one place so
    /// the landing and the heal can never disagree.
    @MainActor
    private static func apply(_ tx: SplitsShape.Transaction, to thing: Thing) {
        thing.transferDirection = SplitsShape.direction(tx)
        if let usd = tx.usd, usd > 0 { thing.transferUSD = usd }
        // The ACCOUNT's name, which `BandRow.project` draws on the line — the
        // one fact the title does not carry. Never `walletAddress`.
        thing.authorHandle = tx.accountName
        // The door is the transaction's own explorer page (prd §912) — Splits
        // publishes no per-transaction web route, and the hash is the one id
        // every reader of this chain shares. A row with no hash yet (a proposal
        // still waiting on signatures) has no page and keeps no door.
        thing.content = explorerURL(tx) ?? ""
        // The memo is DISPLAY copy (prd §912): a person typed it to say what
        // the payment was for, and on the retrieval-only `enrichedText` it was
        // invisible on every screen. The hash stays where a search can find it.
        thing.summary = tx.memo.map(IngestSupport.titleLine)
        thing.enrichedText = tx.hash
    }

    /// The chain's own transaction page for a Splits row, resolved through
    /// `WalletIngest`'s ONE explorer table so a chain the wallet cannot name is
    /// a row with no door, never a link built from a guess. Splits names a
    /// chain by EVM id; the table is keyed by Alchemy's network id, hence the
    /// mapping. A chain missing here (a testnet, or one the wallet does not
    /// read) yields nil.
    private static func explorerURL(_ tx: SplitsShape.Transaction) -> String? {
        guard let hash = tx.hash, !hash.isEmpty, let chainId = tx.chainId,
              let network = networkID[chainId],
              let prefix = WalletIngest.explorerURL(forNetwork: network)
        else { return nil }
        return prefix + hash
    }

    private static let networkID: [Int: String] = [
        1: "eth-mainnet", 8453: "base-mainnet", 42161: "arb-mainnet", 10: "opt-mainnet",
        137: "matic-mainnet", 999: "hyperliquid-mainnet", 143: "monad-mainnet",
        480: "worldchain-mainnet", 5042: "arc-mainnet", 4217: "tempo-mainnet",
        4663: "robinhood-mainnet",
    ]

    @MainActor
    private static func heal(_ row: Thing, _ tx: SplitsShape.Transaction) -> Bool {
        guard row.isLive else { return false }
        let title = IngestSupport.titleLine(SplitsShape.rowTitle(tx))
        let tags = SplitsShape.tags(tx)
        // The door counts as a change (prd §912), so a row landed before it
        // existed, or one whose proposal has since executed, gains its page.
        guard row.title != title || row.tags != tags || row.content != (explorerURL(tx) ?? "")
        else { return false }
        row.title = title
        row.tags = tags
        apply(tx, to: row)
        return true
    }
}

// MARK: - The seat

enum SplitsWatch {
    @MainActor
    static func registerBridge(store: BridgeStore) {
        guard SplitsAuth.configured else {
            store.remove(TokenBridge.splits.bridgeID)
            return
        }
        let standing = SplitsState.standing
        store.registerConnected(id: TokenBridge.splits.bridgeID, name: SplitsShape.source,
                                proof: proof(standing))
    }

    /// The seat's proof line: the team's name, and how many accounts. Never
    /// the total — the catalogue row is not behind the balance mask.
    static func proof(_ standing: SplitsStanding) -> String {
        let count = standing.accounts.count + standing.unread
        let accounts = count == 1 ? String(localized: "1 account") : String(localized: "\(count) accounts")
        guard standing.lastRead != nil else { return String(localized: "Connected") }
        if let org = standing.orgName { return "\(org) · \(accounts)" }
        return accounts
    }
}

// MARK: - Probe

extension SplitsFetch {

    /// `-splitsProbe YES` — each read with the STORED key: its status, its
    /// row count and its FIELD NAMES. An empty Splits room has several causes
    /// (no key, a refused key, a quiet team, shape drift) and only the last
    /// is a bug. Never prints the key, a name, an address or an amount.
    static func probe() async {
        guard let token = SplitsAuth.storedToken else {
            NSLog("[Casberi] splitsProbe: no stored key (connect via -tokenBridge \"Splits:<key>\")")
            return
        }
        let (who, whoStatus) = await whoami(token: token)
        NSLog("[Casberi] splitsProbe: whoami HTTP %d · scopes=%@ · readOnly=%@",
              whoStatus, who?.scopes.joined(separator: ",") ?? "—",
              who.map { SplitsShape.isReadOnly($0.scopes) ? "yes" : "NO" } ?? "—")
        for path in ["/v1/org/accounts", "/v1/transactions?limit=10", "/v1/contacts", "/v1/automations"] {
            let (json, status) = await get(path, token: token)
            let rows = (SplitsShape.data(json) as? [Any])?.count ?? -1
            NSLog("[Casberi] splits| %@ HTTP %d · %d rows · fields={%@}",
                  path, status, rows, SplitsShape.keyNames(json).joined(separator: ","))
            if path.hasPrefix("/v1/transactions"), let page = SplitsShape.transactions(json) {
                for tx in page.rows {
                    NSLog("[Casberi] splitsTx| status=%@ stage=%@ direction=%@ dust=%@ usd=%@",
                          tx.status, "\(SplitsShape.stage(tx.status))", tx.direction ?? "—",
                          SplitsShape.isDust(tx) ? "yes" : "no", tx.usd == nil ? "absent" : "present")
                }
            }
        }
    }
}
