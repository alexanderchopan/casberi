import Foundation

/// What one watched Bitcoin entry reads as in a pass — a single address, or a
/// whole wallet discovered from its public key (prd §1097). Everything
/// `BitcoinBridge.sync` lands is computed against `owned`, so a send's change
/// to another of the wallet's addresses is the wallet's own money, never a
/// payment out.
struct BitcoinUnit {
    /// The spelling in `WalletStore` — what a landed thing's `walletAddress` carries.
    let watched: String
    /// `BitcoinBridge.unitKey(watched)`: refs and defaults keys.
    let key: String
    /// Every address this entry owns, normalised (`BitcoinBridge.norm`). For a
    /// wallet, every derived address up to the gap window past the last used.
    let owned: Set<String>
    /// The recent transactions touching any owned address, newest first, deduped.
    let txs: [[String: Any]]
    let balanceSats: Int
    /// The most times any one owned address has received coins.
    let mostReceipts: Int
    /// The owned addresses holding coins, for the UTXO read.
    let funded: [String]
    var isWallet: Bool { key.hasPrefix("hd-") }
}

/// Discovering a wallet's addresses from its key, and keeping that cheap.
///
/// **Discovery** is the BIP44 gap-limit walk every wallet does: derive
/// addresses in order, ask each one's stats, stop after `BitcoinHD.gapLimit`
/// unused in a row. A bare `xpub` names no script, so the first receive
/// address of each of the four scripts is asked first and the ones with
/// history are kept (a key nobody has used yet is asked again next pass).
///
/// **Steady state** costs a handful of requests, not the whole walk: only the
/// addresses holding coins and the next five past the last used one on each
/// branch are asked, and only an address whose transaction count moved has its
/// transactions fetched. The full walk runs once a day, which is what catches
/// a coin arriving at an old, emptied address. An address that could not be
/// reached is never counted as unused — the walk stops there and the day's
/// full walk is not stamped done.
extension BitcoinBridge {

    struct WalletScanState: Codable {
        struct Seen: Codable { var txCount: Int; var balance: Int; var receipts: Int }
        var scripts: [BitcoinHD.Script]?
        var seen: [String: Seen] = [:]
        /// Each address's transaction count when its transactions were last
        /// FETCHED — apart from `seen`, because the holdings read refreshes the
        /// counts without fetching, and a moved count it had already absorbed
        /// would leave the sync with nothing to fetch.
        var fetched: [String: Int] = [:]
        /// "script|branch" → the highest index with history (absent: none).
        var highest: [String: Int] = [:]
        var lastFull: Date?
        var updated: Date?
    }

    private static let lookahead = 5
    /// Addresses asked at once during the full walk.
    private static let walkWidth = 10
    private static let fullScanEvery: TimeInterval = 86_400
    /// How long a scan's balance serves the holdings read before it asks again.
    private static let balanceFresh: TimeInterval = 600
    /// Transaction pages fetched on a wallet's FIRST read — newest addresses
    /// first, because a wallet uses its addresses in order. The feed gets the
    /// recent history, never a backfill of every year.
    private static let firstReadPages = 12

    private static func scanKey(_ fingerprint: String) -> String { "bitcoin.hd.\(fingerprint)" }

    static func loadScan(_ fingerprint: String) -> WalletScanState {
        guard let data = UserDefaults.standard.data(forKey: scanKey(fingerprint)),
              let state = try? JSONDecoder().decode(WalletScanState.self, from: data)
        else { return WalletScanState() }
        return state
    }

    private static func saveScan(_ state: WalletScanState, _ fingerprint: String) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: scanKey(fingerprint))
    }

    static func clearScan(_ fingerprint: String) {
        UserDefaults.standard.removeObject(forKey: scanKey(fingerprint))
    }

    /// One read per wallet at a time: the holdings read and the activity sync
    /// both ask, and the second waits for the first instead of walking twice.
    @MainActor private static var inFlight: [String: Task<BitcoinUnit?, Never>] = [:]

    /// The unit `watched` reads as this pass — nil when nothing could be reached.
    @MainActor
    static func readUnit(_ watched: String, transactions: Bool) async -> BitcoinUnit? {
        guard let wallet = BitcoinHD.parse(watched) else {
            return await addressUnit(watched, transactions: transactions)
        }
        let fp = BitcoinHD.fingerprint(watched)
        if let running = inFlight[fp] { return await running.value }
        let task = Task { @MainActor in
            await scanWallet(watched, wallet: wallet, fingerprint: fp, transactions: transactions)
        }
        inFlight[fp] = task
        defer { inFlight[fp] = nil }
        return await task.value
    }

    private static func addressUnit(_ address: String, transactions: Bool) async -> BitcoinUnit? {
        guard let stats = await addressStats(address) else { return nil }
        var txs: [[String: Any]] = []
        if transactions {
            guard let page = await fetchTxs(address) else { return nil }
            txs = page
        }
        return BitcoinUnit(watched: address, key: unitKey(address), owned: [norm(address)],
                           txs: txs, balanceSats: stats.balanceSats,
                           mostReceipts: stats.receipts,
                           funded: stats.balanceSats > 0 ? [address] : [])
    }

    /// The wallet's balance in sats for the holdings read: the last scan's when
    /// it is fresh, a stats-only scan otherwise.
    @MainActor
    static func walletBalanceSats(_ watched: String) async -> Int? {
        let fp = BitcoinHD.fingerprint(watched)
        let state = loadScan(fp)
        if let updated = state.updated, Date.now.timeIntervalSince(updated) < balanceFresh {
            return state.seen.values.reduce(0) { $0 + $1.balance }
        }
        return await readUnit(watched, transactions: false)?.balanceSats
    }

    @MainActor
    private static func scanWallet(_ watched: String, wallet: BitcoinHD.Wallet,
                                   fingerprint fp: String, transactions: Bool) async -> BitcoinUnit? {
        var state = loadScan(fp)
        var reachedAny = false

        // 1. Which scripts this key is read as.
        var scripts = wallet.scriptKnown ? wallet.scripts : (state.scripts ?? [])
        if scripts.isEmpty, let first = wallet.branches.first {
            for script in wallet.scripts {
                guard let node = BitcoinHD.branchNode(wallet, first),
                      let probe = BitcoinHD.address(node, script: script, index: 0) else { continue }
                guard let stats = await addressStats(probe) else { continue }
                reachedAny = true
                if stats.txCount > 0 { scripts.append(script) }
            }
            guard reachedAny else { return nil }
            if scripts.isEmpty {
                // A key nobody has used yet: nothing to read, asked again next pass.
                return BitcoinUnit(watched: watched, key: fp, owned: [], txs: [],
                                   balanceSats: 0, mostReceipts: 0, funded: [])
            }
            state.scripts = scripts
        }

        // 2. Walk each branch — the whole gap window once a day, the edges otherwise.
        let full = state.lastFull.map { Date.now.timeIntervalSince($0) >= fullScanEvery } ?? true
        var complete = true
        var owned = Set<String>()
        var positions: [String: Int] = [:]   // address → index, for newest-first paging
        for script in scripts {
            for branch in wallet.branches {
                guard let node = BitcoinHD.branchNode(wallet, branch) else { complete = false; continue }
                let slot = "\(script.rawValue)|\(branch.map(String.init).joined(separator: "/"))"
                var highest = state.highest[slot] ?? -1
                func derive(_ i: Int) -> String? { BitcoinHD.address(node, script: script, index: UInt32(i)) }

                if full {
                    var index = 0, gap = 0
                    walk: while gap < BitcoinHD.gapLimit {
                        let window = (index..<(index + walkWidth)).compactMap { i in derive(i).map { (i, $0) } }
                        let answers = await withTaskGroup(of: (Int, String, Stats?).self) { group in
                            for (i, a) in window { group.addTask { (i, a, await addressStats(a)) } }
                            var out: [(Int, String, Stats?)] = []
                            for await answer in group { out.append(answer) }
                            return out.sorted { $0.0 < $1.0 }
                        }
                        for (i, address, stats) in answers {
                            guard let stats else { complete = false; break walk }
                            reachedAny = true
                            positions[address] = i
                            owned.insert(norm(address))
                            state.seen[address] = .init(txCount: stats.txCount, balance: stats.balanceSats,
                                                        receipts: stats.receipts)
                            if stats.txCount > 0 { highest = i; gap = 0 } else { gap += 1 }
                            if gap >= BitcoinHD.gapLimit { break walk }
                        }
                        index += walkWidth
                    }
                } else {
                    // Ask what holds coins and the next few past the last used; the
                    // rest of the window is derived (no request) so change sent to
                    // it is still recognised as the wallet's own.
                    var ask: [(Int, String)] = []
                    for i in 0...(highest + BitcoinHD.gapLimit) {
                        guard let address = derive(i) else { continue }
                        owned.insert(norm(address))
                        positions[address] = i
                        let holds = (state.seen[address]?.balance ?? 0) > 0
                        if holds || (i > highest && i <= highest + lookahead) { ask.append((i, address)) }
                    }
                    let answers = await withTaskGroup(of: (Int, String, Stats?).self) { group in
                        for (i, a) in ask { group.addTask { (i, a, await addressStats(a)) } }
                        var out: [(Int, String, Stats?)] = []
                        for await answer in group { out.append(answer) }
                        return out
                    }
                    for (i, address, stats) in answers {
                        guard let stats else { complete = false; continue }
                        reachedAny = true
                        state.seen[address] = .init(txCount: stats.txCount, balance: stats.balanceSats,
                                                    receipts: stats.receipts)
                        if stats.txCount > 0 { highest = max(highest, i) }
                    }
                    // The window grew past what was derived: own the new edge too.
                    for i in 0...(highest + BitcoinHD.gapLimit) {
                        if let address = derive(i) { owned.insert(norm(address)); positions[address] = i }
                    }
                }
                if highest >= 0 { state.highest[slot] = highest }
            }
        }
        guard reachedAny else { return nil }
        if full && complete { state.lastFull = .now }
        state.updated = .now

        // 3. Transactions: only addresses whose count moved, newest addresses first.
        var txs: [[String: Any]] = []
        if transactions {
            let firstRead = state.fetched.isEmpty
            var moved = state.seen.filter { address, seen in
                seen.txCount > 0 && seen.txCount != state.fetched[address]
            }.map(\.key)
            moved.sort { (positions[$0] ?? 0) > (positions[$1] ?? 0) }
            if firstRead, moved.count > firstReadPages {
                // The older addresses' history is skipped on purpose, not left
                // for the next pass to backfill: their counts are taken as read.
                for address in moved.dropFirst(firstReadPages) {
                    state.fetched[address] = state.seen[address]?.txCount
                }
                moved = Array(moved.prefix(firstReadPages))
            }
            var byID: [String: [String: Any]] = [:]
            // Five pages at a time; an unread page keeps its old `fetched`
            // count, so the next pass asks again.
            var start = 0
            while start < moved.count {
                let batch = Array(moved[start..<min(start + 5, moved.count)])
                start += 5
                let pages = await withTaskGroup(of: (String, [[String: Any]]?).self) { group in
                    for address in batch { group.addTask { (address, await fetchTxs(address)) } }
                    var out: [(String, [[String: Any]]?)] = []
                    for await page in group { out.append(page) }
                    return out
                }
                for (address, page) in pages {
                    guard let page else { continue }
                    state.fetched[address] = state.seen[address]?.txCount
                    for tx in page { if let id = tx["txid"] as? String { byID[id] = tx } }
                }
            }
            txs = byID.values.sorted(by: newestFirst)
            if txs.count > 50 { txs = Array(txs.prefix(50)) }
        }
        saveScan(state, fp)

        let ownedSeen = state.seen.filter { owned.contains(norm($0.key)) }
        let balance = ownedSeen.values.reduce(0) { $0 + $1.balance }
        UserDefaults.standard.set(balance, forKey: balanceKey(watched))
        return BitcoinUnit(watched: watched, key: fp, owned: owned, txs: txs,
                           balanceSats: balance,
                           mostReceipts: ownedSeen.values.map(\.receipts).max() ?? 0,
                           funded: ownedSeen.filter { $0.value.balance > 0 }.map(\.key).sorted())
    }

    /// Unconfirmed first (they are the newest), then by block time, newest first.
    static func newestFirst(_ a: [String: Any], _ b: [String: Any]) -> Bool {
        func time(_ tx: [String: Any]) -> Double {
            let status = tx["status"] as? [String: Any]
            guard (status?["confirmed"] as? Bool) == true else { return .infinity }
            return status?["block_time"] as? Double ?? 0
        }
        return time(a) > time(b)
    }
}
