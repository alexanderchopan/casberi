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
/// **Test coins, never money.** LEZ is a testnet (v0.3 since its reset on
/// 2026-09-30, prd §1007; mainnet planned for 2027) that is reset from
/// genesis when it upgrades. Its balances
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
    private static let nodeKey = "logos.node.v1"
    private static let genesisKey = "logos.genesis.v1"
    private static let chainStartKey = "logos.chainStart.v1"
    private static let systemKey = "logos.systemAccounts.v1"
    private static let tokenNamesKey = "logos.tokenNames.v1"
    private static let holdingsKey = "logos.holdings.v1"
    private static let resetSeenKey = "logos.resetSeen.v1"

    /// A token definition's id → the name its own account carries (prd
    /// §1084). Names never change once a definition exists, so a name is
    /// read once and kept until the chain resets.
    private(set) var tokenNames: [String: String] {
        didSet { UserDefaults.standard.set(tokenNames, forKey: Self.tokenNamesKey) }
    }

    func tokenNamesByID() -> [Data: String] {
        var out: [Data: String] = [:]
        for (id, name) in tokenNames {
            if let bytes = LogosWire.base58Decode(id) { out[Data(bytes)] = name }
        }
        return out
    }

    func rememberTokenName(_ name: String, for definition: String) {
        if tokenNames[definition] != name { tokenNames[definition] = name }
    }

    /// What one watched account holds besides its native coins (prd §1084):
    /// the one token its token shard carries. LEZ v0.3 keeps one shard per
    /// program on an account, so an account holds one token at most.
    struct Holding: Codable, Equatable {
        let definition: String
        /// "fungible", "nftMaster" or "nftCopy".
        let kind: String
        /// A decimal string; nil for a printed NFT copy (it is one NFT).
        let amount: String?
    }

    private(set) var holdings: [String: Holding] {
        didSet {
            if let data = try? JSONEncoder().encode(holdings) {
                UserDefaults.standard.set(data, forKey: Self.holdingsKey)
            }
        }
    }

    func holding(for id: String) -> Holding? { holdings[id] }

    /// Replaces what the accounts in `read` hold; an account missing from
    /// `read` (its read failed) keeps its last answer (prd §825).
    func rememberHoldings(_ read: [String: Holding?]) {
        for (id, holding) in read {
            if holdings[id] != holding { holdings[id] = holding }
        }
    }

    /// The reset this phone last OBSERVED (prd §1084): the new chain's block-1
    /// hash and when this phone saw it. What `DevnetNotify` announces, once.
    private(set) var resetSeen: (key: String, at: Date)? {
        didSet {
            if let resetSeen {
                UserDefaults.standard.set(["key": resetSeen.key, "at": resetSeen.at.timeIntervalSince1970],
                                          forKey: Self.resetSeenKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.resetSeenKey)
            }
        }
    }

    /// The hash of the chain's block 1 (prd §1035). A reset is a NEW chain, so
    /// a different block 1 is the one sure sign of it — the cursor test
    /// below only works while the new chain is still shorter than the old.
    private(set) var genesis: String? {
        didSet { UserDefaults.standard.set(genesis, forKey: Self.genesisKey) }
    }

    /// When the current chain began: block 2's time (block 1, genesis, is
    /// stamped 0). What the page names when an account reads empty after it.
    private(set) var chainStart: Date? {
        didSet { UserDefaults.standard.set(chainStart, forKey: Self.chainStartKey) }
    }

    /// Watched accounts the network's own transactions touch (prd §1035):
    /// network accounts, which no person moves. Learned from the walk.
    private(set) var systemAccounts: Set<String> {
        didSet { UserDefaults.standard.set(Array(systemAccounts), forKey: Self.systemKey) }
    }

    func isSystem(_ id: String) -> Bool { systemAccounts.contains(id) }
    func markSystem(_ ids: Set<String>) {
        let new = ids.subtracting(systemAccounts)
        if !new.isEmpty { systemAccounts.formUnion(new) }
    }

    /// Records the chain's identity. Returns true when it CHANGED from a
    /// known one — a reset; first sight is not.
    @discardableResult
    func rememberChain(genesis hash: String, start: Date?) -> Bool {
        let reset = genesis != nil && genesis != hash
        if genesis != hash { genesis = hash }
        if reset { resetSeen = (hash, .now) }
        if let start, chainStart != start { chainStart = start }
        return reset
    }

    /// The page's and the room's reset line applies (prd §1035).
    func showsResetNote(now: Date = .now) -> Bool {
        LogosWire.showsResetNote(chainStart: chainStart, now: now,
                                 balances: accounts.map { balance(for: $0) })
    }
    private static let nodeSnapshotKey = "logos.nodeSnapshot.v1"

    /// Your own node's base URL (prd §989), or nil when none is watched.
    private(set) var node: String? {
        didSet { UserDefaults.standard.set(node, forKey: Self.nodeKey) }
    }

    /// The node's last reading — what the next one is diffed against, and the
    /// roster's line. nil until the first read, which lands nothing.
    private(set) var nodeSnapshot: LogosWire.NodeSnapshot? {
        didSet {
            if let data = nodeSnapshot.flatMap({ try? JSONEncoder().encode($0) }) {
                UserDefaults.standard.set(data, forKey: Self.nodeSnapshotKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.nodeSnapshotKey)
            }
        }
    }

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

    /// When EVERY watched balance was last read — the roster's staleness
    /// stamp. A pass that could not read one leaves it where it was, so a
    /// stored figure is never drawn as fresher than it is (prd §825, §1007).
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
        // v0.2 kept each account's owning program; v0.3 accounts have none.
        UserDefaults.standard.removeObject(forKey: "logos.owners.v1")
        node = UserDefaults.standard.string(forKey: Self.nodeKey)
        genesis = UserDefaults.standard.string(forKey: Self.genesisKey)
        chainStart = UserDefaults.standard.object(forKey: Self.chainStartKey) as? Date
        systemAccounts = Set(UserDefaults.standard.stringArray(forKey: Self.systemKey) ?? [])
        tokenNames = UserDefaults.standard.dictionary(forKey: Self.tokenNamesKey) as? [String: String] ?? [:]
        holdings = UserDefaults.standard.data(forKey: Self.holdingsKey)
            .flatMap { try? JSONDecoder().decode([String: Holding].self, from: $0) } ?? [:]
        if let seen = UserDefaults.standard.dictionary(forKey: Self.resetSeenKey),
           let key = seen["key"] as? String, let at = seen["at"] as? Double {
            resetSeen = (key, Date(timeIntervalSince1970: at))
        } else { resetSeen = nil }
        nodeSnapshot = UserDefaults.standard.data(forKey: Self.nodeSnapshotKey)
            .flatMap { try? JSONDecoder().decode(LogosWire.NodeSnapshot.self, from: $0) }
    }

    /// Watching an account OR a node connects the seat.
    var connected: Bool { !accounts.isEmpty || node != nil }

    /// Points the seat at a node. A different address starts a fresh history:
    /// diffing one node's reading against another's would report every
    /// difference between two machines as news.
    func useNode(_ base: String?) {
        guard base != node else { return }
        node = base
        nodeSnapshot = nil
    }

    func rememberNode(_ snap: LogosWire.NodeSnapshot) { nodeSnapshot = snap }

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
        holdings.removeValue(forKey: id)
        systemAccounts.remove(id)
        if accounts.isEmpty { cursor = nil }
    }

    func balance(for id: String) -> Decimal? { balances[id].flatMap { Decimal(string: $0) } }

    func rememberBalances(_ read: [String: Decimal], at date: Date) {
        for (id, value) in read { balances[id] = "\(value)" }
        if !accounts.isEmpty, accounts.allSatisfy({ read[$0] != nil }) { readAt = date }
    }

    func advance(to block: Int) { cursor = block }

    /// The node's head is BEHIND where we walked to: the testnet was reset
    /// from genesis. The walk restarts at the new head, and balances are
    /// re-read rather than diffed — every account emptying at once is a reset,
    /// not news.
    func resetDetected(head: Int) {
        cursor = head
        balances = [:]
        holdings = [:]
        tokenNames = [:]
        readAt = nil
        systemAccounts = []
    }

    func disconnect() {
        node = nil
        nodeSnapshot = nil
        accounts = []
        balances = [:]
        cursor = nil
        readAt = nil
        systemAccounts = []
        holdings = [:]
        tokenNames = [:]
        resetSeen = nil
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

    static func balance(_ id: String) async -> Decimal? {
        LogosWire.balance(await call("getAccountBalance", [id]))
    }

    /// The token an account's token shard holds, named (prd §1084). nil
    /// when it holds none — or when the shard is a token DEFINITION (a
    /// token's own account), which is not a holding.
    @MainActor
    static func holding(in shards: [String: [UInt8]]) async -> LogosStore.Holding? {
        guard let shard = shards[LogosWire.tokenShardKey],
              let h = LogosWire.tokenHolding(shard) else { return nil }
        let definition = LogosWire.base58Encode(h.definition)
        await name(definition)
        let kind: String
        switch h.kind {
        case .fungible:  kind = "fungible"
        case .nftMaster: kind = "nftMaster"
        case .nftCopy:   kind = "nftCopy"
        }
        // A printed copy that is not owned holds nothing.
        guard h.owned else { return nil }
        return LogosStore.Holding(definition: definition, kind: kind, amount: h.amount.map { "\($0)" })
    }

    /// Reads a token definition's name once, from its own account.
    @MainActor
    static func name(_ definition: String) async {
        guard LogosStore.shared.tokenNames[definition] == nil,
              let shards = LogosWire.shards(await call("getAccount", [definition])),
              let shard = shards[LogosWire.tokenShardKey],
              let name = LogosWire.tokenName(definitionShard: shard) else { return }
        LogosStore.shared.rememberTokenName(name, for: definition)
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
    /// testnet moving past LEZ v0.3's layout is the expected cause).
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

        var outcome = Outcome(added: 0, skipped: 0)
        var reached = false
        if let base = store.node {
            outcome.added += await readNode(base, context: context)
            reached = true
        }
        guard !store.accounts.isEmpty else {
            if outcome.added > 0 { context.saveHonestly() }
            return outcome
        }
        guard let tip = await head() else {
            if outcome.added > 0 { context.saveHonestly() }
            return reached ? outcome : nil
        }

        var read: [String: Decimal] = [:]
        var held: [String: LogosStore.Holding?] = [:]
        for id in store.accounts {
            if let balance = await balance(id) { read[id] = balance }
            if let shards = LogosWire.shards(await call("getAccount", [id])) {
                held[id] = await holding(in: shards)
            }
        }

        // Which chain this is (prd §1035): block 1's hash names it, block 2's
        // time says when it began. One small read a pass; a failed one
        // leaves the last answer standing.
        var newChain = false
        if let first = await blocks(from: 1, to: 2), let genesis = first.first.flatMap(LogosWire.header) {
            newChain = store.rememberChain(genesis: genesis.hashHex,
                                           start: first.dropFirst().first.flatMap(LogosWire.header)?.timestamp)
        }
        if newChain || (store.cursor.map { $0 > tip } ?? false) {
            store.resetDetected(head: tip)
        } else if let cursor = store.cursor, cursor < tip {
            let walked = await walk(from: cursor + 1, to: tip, context: context)
            outcome.added += walked.added
            outcome.skipped = walked.skipped
            outcome.stalled = walked.stalled
        } else if store.cursor == nil {
            // First pass: forward-only, from here.
            store.advance(to: tip)
        }
        store.rememberBalances(read, at: .now)
        store.rememberHoldings(held)
        // The Home crown's line (prd §991): one sample per account per pass,
        // the devnets' `RoomValueHistory`, so the line is what this phone saw
        // rather than a reconstruction.
        RoomValueHistory.note(room: LogosRoom.source, values: read.map {
            (address: $0.key, value: NSDecimalNumber(decimal: $0.value).doubleValue)
        })
        return outcome
    }

    // MARK: - Your node (prd §989)

    /// One reading of the node: five GETs, never a write. The vouchers read
    /// needs the tip the info read returned; the two mining reads (prd §1016)
    /// fail soft, so a node without them still reads as a node.
    static func nodeReading(_ base: String) async -> LogosWire.NodeSnapshot {
        guard let info = LogosWire.nodeInfo(
            await IngestSupport.getJSON(base + LogosWire.nodeInfoPath, service: service))
        else { return .unreachable }
        var snap = LogosWire.NodeSnapshot(reachable: true, phase: info.phase,
                                          height: info.height, tip: info.tip)
        snap.peers = LogosWire.nodePeers(
            await IngestSupport.getJSON(base + LogosWire.nodePeersPath, service: service))
        if let tip = info.tip,
           let v = LogosWire.nodeVouchers(await IngestSupport.getJSON(
               base + LogosWire.nodeVouchersPath + "?tip=" + tip, service: service)) {
            snap.vouchers = v.count
            snap.claimable = v.claimable
        }
        if let m = LogosWire.nodeMining(
            await IngestSupport.getJSON(base + LogosWire.nodeMiningPath, service: service)) {
            snap.mining = m.mining
            snap.miningPays = m.pays
        }
        snap.tickets = LogosWire.nodeTickets(
            await IngestSupport.getJSON(base + LogosWire.nodeTicketsPath, service: service))
        return snap
    }

    /// Reads the node, lands what CHANGED since the last reading (nothing on
    /// the first), and keeps the reading. Rows are stamped when observed —
    /// a node's state carries no date of its own, so "now" is true to within
    /// one refresh, and it is the only honest stamp there is.
    @MainActor
    static func readNode(_ base: String, context: ModelContext) async -> Int {
        let store = LogosStore.shared
        let snap = await nodeReading(base)
        // The address changed while this read was in flight: drop it.
        guard store.node == base else { return 0 }
        let events = LogosWire.nodeEvents(old: store.nodeSnapshot, new: snap)
        let now = Date()
        for event in events {
            let ref = "logos:node:\(event.kind):\(Int(now.timeIntervalSince1970))"
            let thing = Thing(kind: .note, title: IngestSupport.titleLine(event.title),
                              content: base, source: "Logos", capturedAt: now,
                              tags: event.tags, sourceRef: ref)
            thing.authorHandle = String(localized: "Your node")
            context.insert(thing)
            SpotlightIndex.index([thing])
        }
        store.rememberNode(snap.remembering(store.nodeSnapshot))
        return events.count
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
        var existing = IngestSupport.existingSourceRefs(context, source: "Logos")
        var names = store.tokenNamesByID()
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
                    // A token call naming a watched account: read its
                    // token's name first, so the row says FIELDTEST rather
                    // than "tokens" (prd §1084).
                    if tx.program == LogosWire.tokenProgram,
                       tx.accounts.contains(where: { watched.contains(Data($0)) }),
                       let call = LogosWire.tokenCall(tx.instruction),
                       let definition = LogosWire.tokenDefinition(call, tx: tx) {
                        await name(LogosWire.base58Encode(definition))
                        names = store.tokenNamesByID()
                    }
                    if LogosWire.isSystem(tx) {
                        store.markSystem(Set(tx.accounts.filter { watched.contains(Data($0)) }
                                                .map(LogosWire.base58Encode)))
                    }
                    for event in LogosWire.events(tx, watched: watched, names: names) {
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
