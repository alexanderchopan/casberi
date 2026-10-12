import Foundation

/// AZTEC a watched wallet has staked on Aztec mainnet (2026-10-12, prd §1277):
/// the app half of `AztecStakeWire`. Rides the watched wallets like ether.fi's
/// unstake queue: no account, no key, keyless `eth-mainnet` reads through
/// `WalletApprovals`' host pool, already disclosed under the Wallet.
///
/// Staked AZTEC has left the wallet's balance, so without this a wallet that
/// staked reads as one that spent. The book states each stake in AZTEC, never
/// priced (`WalletComposition` rule 2), and whether it is validating, stopped,
/// or on its way out and from when.
///
/// Discovery is a forward walk of the three Rollups' `ValidatorQueued` logs
/// filtered on the wallet as withdrawer, from `AztecStakeWire.firstBlock`, a
/// cursor kept per wallet so a pass after the first asks only for new blocks.
enum AztecStaking {
    private static let network = "eth-mainnet"

    /// Log chunks walked per wallet per pass. Aztec's whole history is three
    /// chunks at the host pool's 900,000-block cap (2026-10-12).
    private static let maxChunksPerPass = 4

    /// Attesters read per wallet per pass. The largest withdrawer measured
    /// queued 260; past this a wallet shows its newest stakes, never a guess.
    private static let maxAttestersPerWallet = 24

    private static func attestersKey(_ address: String) -> String { "aztec.stake.attesters.\(address.lowercased())" }
    private static func cursorKey(_ address: String) -> String { "aztec.stake.cursor.\(address.lowercased())" }

    /// Unwatching takes the walk with it, beside the siblings' (`WalletStore`).
    static func clearState(address: String) {
        UserDefaults.standard.removeObject(forKey: attestersKey(address))
        UserDefaults.standard.removeObject(forKey: cursorKey(address))
    }

    struct Book: Equatable, Sendable {
        var stakes: [AztecStakeWire.Stake] = []
        /// False when some wallet's walk has not reached the head yet: what
        /// it found is true, and what it has not found is not yet known.
        var complete = true
        var isEmpty: Bool { stakes.isEmpty }
    }

    private static let cache = CoalescingCache<Book>()

    /// nil when mainnet could not be reached for any wallet.
    static func book(addresses: [String]) async -> Book? {
        guard !addresses.isEmpty else { return Book() }
        let key = addresses.map { $0.lowercased() }.sorted().joined(separator: ",")
        return await cache.value(key: key, ttl: 60) {
            await fetchBook(addresses: addresses)
        }
    }

    private static func fetchBook(addresses: [String]) async -> Book? {
        guard let head = await blockNumber() else { return nil }
        var book = Book()
        var reached = false
        for address in addresses {
            guard let attesters = await discover(address: address, head: head) else {
                book.complete = false
                continue
            }
            reached = true
            if (UserDefaults.standard.object(forKey: cursorKey(address)) as? Int ?? 0) <= head { book.complete = false }
            for key in attesters.suffix(maxAttestersPerWallet).reversed() {
                let parts = key.split(separator: "@").map(String.init)
                guard parts.count == 2 else { continue }
                let view = await read("eth_call",
                    [["to": parts[1], "data": AztecStakeWire.viewCall(parts[0])], "latest"]) as? String
                guard let view else { book.complete = false; continue }
                if let stake = AztecStakeWire.stake(view: view, owner: address, attester: parts[0], rollup: parts[1]) {
                    book.stakes.append(stake)
                }
            }
        }
        book.stakes.sort { $0.amount > $1.amount }
        return reached ? book : nil
    }

    /// Every attester this wallet can withdraw, oldest first, walking forward
    /// from where the last pass stopped. nil when no chunk could be read.
    private static func discover(address: String, head: Int) async -> [String]? {
        let defaults = UserDefaults.standard
        var known = defaults.stringArray(forKey: attestersKey(address)) ?? []
        var from = max((defaults.object(forKey: cursorKey(address)) as? Int) ?? AztecStakeWire.firstBlock,
                       AztecStakeWire.firstBlock)
        let range = WalletApprovals.maxLogRange(forNetwork: network) ?? 900_000
        var chunks = 0
        var readAny = from > head
        while from <= head, chunks < maxChunksPerPass {
            let to = min(head, from + range - 1)
            guard let logs = await read("eth_getLogs",
                [AztecStakeWire.logFilter(withdrawer: address, from: from, to: to)]) as? [[String: Any]]
            else { break }
            readAny = true
            for key in AztecStakeWire.attesters(fromLogs: logs, withdrawer: address) where !known.contains(key) {
                known.append(key)
            }
            from = to + 1
            chunks += 1
        }
        guard readAny || !known.isEmpty else { return nil }
        defaults.set(known, forKey: attestersKey(address))
        defaults.set(from, forKey: cursorKey(address))
        return known
    }

    private static func blockNumber() async -> Int? {
        guard let hex = await read("eth_blockNumber", []) as? String else { return nil }
        return WalletIngest.hexToInt(hex)
    }

    /// One read through the Wallet's mainnet pool, asked up to five times
    /// over about six seconds. MEASURED 2026-10-12: `rpc.mevblocker.io`
    /// answers a log query "service temporarily unavailable" a third to a
    /// half of the time, in STREAKS of up to five on one connection, and the
    /// pool's second host rate-limits keyless callers. Three tries 300ms
    /// apart fell inside one streak on four passes running.
    private static func read(_ method: String, _ params: [Any]) async -> Any? {
        let pauses: [Int] = [400, 800, 1_600, 3_200]
        for attempt in 0...pauses.count {
            if let result = await WalletApprovals.rpcRead(network: network, method: method, params: params) {
                return result
            }
            if attempt < pauses.count { try? await Task.sleep(for: .milliseconds(pauses[attempt])) }
        }
        return nil
    }

    #if DEBUG
    /// `-aztecStakeProbe <address>` — one wallet's stakes, read without
    /// watching it, one NSLog line per stake (the `-todayProbe` lesson).
    static func probe(address: String) async -> [String] {
        clearState(address: address)
        guard let book = await book(addresses: [address.lowercased()]) else { return ["book UNREACHABLE"] }
        var lines = book.stakes.map {
            "\($0.attester) | \($0.status) | \(WalletIngest.format($0.amount)) AZTEC | \(AztecStakeWire.state($0))"
        }
        if lines.isEmpty {
            lines = [book.complete ? "no stakes (a real empty answer, not a miss)"
                                   : "none found YET: the walk has not reached the head"]
        }
        lines.append("walked to \(UserDefaults.standard.integer(forKey: cursorKey(address)))")
        return lines
    }
    #endif
}
