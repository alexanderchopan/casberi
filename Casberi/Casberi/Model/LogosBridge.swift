import Foundation
import Observation
import SwiftData

/// The Logos seat (prd §988, 2026-09-29) — the Logos network, the rebrand of
/// Nomos/Codex/Waku, whose desktop suite is Basecamp. Four doors, in the order
/// the Logos team proposed them: watch a public LEZ account (this file's
/// first half), connect Field Wallet read-only, watch your own node, and node
/// rewards once their read API settles.
///
/// **Watch is keyless and forward-only.** The sequencer answers an account's
/// balance to anyone, and serves blocks by range; there is no public history
/// by account (the indexer's RPC is not exposed, and the explorer only
/// server-renders it into a page). So the bridge WALKS BLOCKS from the moment
/// you start watching, picks out the transactions that touch a watched
/// account, and dates each from its block's own millisecond stamp — never
/// from when this phone happened to see it. Nothing before the watch began
/// is claimed, because nothing here can see it.
///
/// **Test coins, never money.** LEZ is a testnet (v0.1.x, mainnet planned for
/// 2027) that has been reset from genesis (last on 2026-08-05). Its balances
/// never join the wallet total, and a reset is detected — the stored cursor
/// is past the node's head — rather than read as every account emptying.
///
/// **No unit.** LEZ has no symbol and no decimals anywhere (measured): a
/// native balance is a raw integer and a token carries only a name, so every
/// amount is drawn bare (`LogosWire.amount`). "LGO" is the L1's unit.
@Observable
final class LogosStore {
    static let shared = LogosStore()

    private static let accountsKey = "logos.accounts.v1"
    private static let balancesKey = "logos.balances.v1"
    private static let cursorKey = "logos.cursor.v1"
    private static let readAtKey = "logos.readAt.v1"

    /// Watched public LEZ account ids, base58.
    private(set) var accounts: [String] {
        didSet { persist(accounts, Self.accountsKey) }
    }

    /// id → the last balance the sequencer answered, as a decimal string (a
    /// u128 does not fit `Int`; see `LogosWire.decimal`).
    private(set) var balances: [String: String] {
        didSet {
            if let data = try? JSONEncoder().encode(balances) {
                UserDefaults.standard.set(data, forKey: Self.balancesKey)
            }
        }
    }

    /// The last block the walk has read through. nil until the first pass,
    /// which starts it at the head: a watch is forward-only.
    private(set) var cursor: Int? {
        didSet {
            if let cursor { UserDefaults.standard.set(cursor, forKey: Self.cursorKey) }
            else { UserDefaults.standard.removeObject(forKey: Self.cursorKey) }
        }
    }

    /// When the balances were last read — the roster's staleness stamp.
    private(set) var readAt: Date? {
        didSet { UserDefaults.standard.set(readAt, forKey: Self.readAtKey) }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.accountsKey),
           let saved = try? JSONDecoder().decode([String].self, from: data) {
            accounts = saved
        } else { accounts = [] }
        if let data = UserDefaults.standard.data(forKey: Self.balancesKey),
           let saved = try? JSONDecoder().decode([String: String].self, from: data) {
            balances = saved
        } else { balances = [:] }
        cursor = UserDefaults.standard.object(forKey: Self.cursorKey) as? Int
        readAt = UserDefaults.standard.object(forKey: Self.readAtKey) as? Date
    }

    var connected: Bool { !accounts.isEmpty }

    func isWatching(_ raw: String) -> Bool {
        guard let id = LogosWire.watchableID(raw) else { return false }
        return accounts.contains(id)
    }

    enum AddResult: Equatable { case added, alreadyWatching, privateAccount, invalid }

    /// Adds a public account. Says WHICH refusal, so the screen can: a private
    /// id is a real account this door cannot read, not a typo.
    @discardableResult
    func add(_ raw: String) -> AddResult {
        guard let parsed = LogosWire.parseAccountID(raw) else { return .invalid }
        guard parsed.visibility != .privateAccount else { return .privateAccount }
        guard !accounts.contains(parsed.base58) else { return .alreadyWatching }
        accounts.append(parsed.base58)
        return .added
    }

    func remove(_ id: String) {
        accounts.removeAll { $0 == id }
        balances.removeValue(forKey: id)
        if accounts.isEmpty { cursor = nil }
    }

    func balance(for id: String) -> Decimal? { balances[id].flatMap { Decimal(string: $0) } }

    func rememberBalances(_ read: [String: Decimal], at date: Date) {
        for (id, value) in read { balances[id] = "\(value)" }
        readAt = date
    }

    func advance(to block: Int) { cursor = block }

    /// The node's head is BEHIND where we walked to: the testnet was reset
    /// from genesis. The walk restarts at the new head, and balances are
    /// re-read rather than diffed — every account emptying at once is a reset,
    /// not news.
    func resetDetected(head: Int) {
        cursor = head
        balances = [:]
    }

    func disconnect() {
        accounts = []
        balances = [:]
        cursor = nil
        readAt = nil
    }

    private func persist(_ list: [String], _ key: String) {
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

// MARK: - Ingest

enum LogosIngest {

    /// The service name every request declares to `NetworkLedger`.
    static let service = "Logos"

    /// The LEZ testnet sequencer. Keyless, POST-only JSON-RPC.
    static let sequencer = "https://testnet.lez.logos.co"

    /// The explorer a row opens on tap. Never fetched.
    static let explorer = "https://explorer.testnet.lez.logos.co"

    @MainActor private static var running = false

    /// The most blocks one pass reads: a WEEK. LEZ makes a block a minute
    /// (measured), and a 1,000-block page reads in ~1.4s, so a week away is
    /// ~15s of background reads. Past this the walk jumps to the head and
    /// SAYS it skipped (`skipped`, drawn on the page) rather than spend a
    /// foreground pass reading a month.
    static let walkCap = 10_080
    /// Blocks per `getBlockRange` call. The node refuses a reply over 10 MB
    /// (`-32008`, measured at 5,000 blocks; one program deployment is ~0.5 MB),
    /// so a refused page is HALVED and re-asked rather than given up on.
    static let pageSize = 200

    // MARK: - Reads

    static func call(_ method: String, _ params: [Any]) async -> Any? {
        let reply = await IngestSupport.postJSON(sequencer, body: LogosWire.request(method, params),
                                                 service: service)
        return LogosWire.result(reply)
    }

    static func head() async -> Int? {
        (await call("getLastBlockId", []) as? NSNumber)?.intValue
    }

    static func account(_ id: String) async -> LogosWire.Account? {
        LogosWire.account(await call("getAccount", [id]))
    }

    static func programIDs() async -> [String: [UInt32]] {
        LogosWire.programIDs(await call("getProgramIds", []))
    }

    /// Raw blocks, base64 Borsh, `[from, to]` inclusive.
    static func blocks(from: Int, to: Int) async -> [Data]? {
        guard let rows = await call("getBlockRange", [from, to]) as? [Any] else { return nil }
        return rows.compactMap { ($0 as? String).flatMap { Data(base64Encoded: $0) } }
    }

    // MARK: - Land

    /// `skipped`: blocks jumped past the `walkCap`. `stalled`: a block that
    /// would not decode stopped the walk at it — the cursor stays put, so
    /// nothing is skipped, and the page can say activity is paused (the
    /// testnet moving to LEZ v0.3's layout is the expected cause).
    struct Outcome { var added: Int; var skipped: Int; var stalled = false }

    /// Reads every watched account's balance, walks the blocks since the
    /// cursor and lands what touched a watched account. nil when the
    /// sequencer could not be reached.
    @MainActor
    static func refresh(context: ModelContext) async -> Outcome? {
        let store = LogosStore.shared
        guard store.connected, !running else { return running ? Outcome(added: 0, skipped: 0) : nil }
        running = true
        defer { running = false }

        guard let tip = await head() else { return nil }

        var read: [String: Decimal] = [:]
        for id in store.accounts {
            if let account = await account(id) { read[id] = account.balance }
        }

        var outcome = Outcome(added: 0, skipped: 0)
        if let cursor = store.cursor, cursor > tip {
            store.resetDetected(head: tip)
        } else if let cursor = store.cursor, cursor < tip {
            outcome = await walk(from: cursor + 1, to: tip, context: context)
        } else if store.cursor == nil {
            // First pass: forward-only, from here.
            store.advance(to: tip)
        }
        store.rememberBalances(read, at: .now)
        return outcome
    }

    @MainActor
    private static func walk(from start: Int, to tip: Int, context: ModelContext) async -> Outcome {
        let store = LogosStore.shared
        var from = start
        var skipped = 0
        if tip - from + 1 > walkCap {
            skipped = tip - walkCap + 1 - from
            from = tip - walkCap + 1
        }
        let watched = Set(store.accounts.compactMap(LogosWire.base58Decode).map { Data($0) })
        let programs = await programIDs()
        var existing = IngestSupport.existingSourceRefs(context, source: "Logos")
        var added = 0
        var at = from
        var size = pageSize
        var stalled = false
        walking: while at <= tip {
            let end = min(at + size - 1, tip)
            guard let page = await blocks(from: at, to: end), page.count == end - at + 1 else {
                if size > 1 { size /= 2; continue }
                break
            }
            for raw in page {
                guard let block = LogosWire.block(raw) else {
                    // Refused whole, never skipped: advance only through the
                    // blocks before it, and stop.
                    stalled = true
                    if added > 0 { context.saveHonestly() }
                    break walking
                }
                for tx in block.transactions {
                    for event in LogosWire.events(tx, watched: watched, programs: programs) {
                        let ref = "logos:lez:\(event.account):\(tx.hashHex)"
                        guard !existing.contains(ref) else { continue }
                        land(event, tx: tx, block: block, ref: ref, context: context)
                        existing.insert(ref)
                        added += 1
                    }
                }
                // The cursor moves only after the block's rows are in the
                // context (StripeBridge's rule): a crash re-reads a block,
                // never skips one.
                store.advance(to: block.id)
            }
            at = end + 1
            size = pageSize
        }
        if added > 0 && !stalled { context.saveHonestly() }
        return Outcome(added: added, skipped: skipped, stalled: stalled)
    }

    @MainActor
    private static func land(_ event: LogosWire.Event, tx: LogosWire.Transaction,
                             block: LogosWire.Block, ref: String, context: ModelContext) {
        let thing = Thing(
            kind: .link,
            title: IngestSupport.titleLine(event.title),
            content: "\(explorer)/transaction/\(tx.hashHex)",
            source: "Logos",
            capturedAt: block.timestamp,
            tags: event.tags,
            sourceRef: ref
        )
        thing.authorHandle = LogosWire.short(event.account)
        context.insert(thing)
        SpotlightIndex.index([thing])
    }
}
