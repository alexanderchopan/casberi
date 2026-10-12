import Foundation
import SwiftData

/// AZTEC a watched wallet has staked on Aztec mainnet (2026-10-12, prd §1277,
/// §1279): the app half of `AztecStakeWire`. Rides the watched wallets like
/// ether.fi's unstake queue: no account, no key, keyless reads through
/// `WalletApprovals`' mainnet pool, plus each staked sequencer's record from
/// Aztec's public mainnet node.
///
/// Staked AZTEC has left the wallet's balance, so without this a wallet that
/// staked reads as one that spent. The book states each stake in AZTEC, never
/// priced (`WalletComposition` rule 2): its state, its health, what it has
/// earned, the token-sale vaults behind it, and an Aztec vote still to come.
///
/// Discovery walks forward from a cursor per WITHDRAWER — the wallet itself,
/// then each of its vaults' stakers — so a vault found late walks its own
/// stakes from the start without re-walking the wallet's.
enum AztecStaking {
    private static let network = "eth-mainnet"

    /// Aztec's public mainnet node, keyless. One sequencer per request: the
    /// whole set (`node_getValidatorsStats`) times out on dRPC's free plan
    /// (measured 2026-10-12).
    private static let node = "https://aztec-mainnet.drpc.org"

    /// Log chunks walked per withdrawer per pass. Aztec's whole history is
    /// three chunks at the host pool's 900,000-block cap (2026-10-12).
    private static let maxChunksPerPass = 4

    /// Stakes read per wallet per pass. The largest withdrawer measured
    /// queued 260; past this a wallet shows the last ones walked (its
    /// vaults' newest), and the book says it is incomplete.
    private static let maxAttestersPerWallet = 24

    private static let maxVaultsPerWallet = 8

    private static func key(_ kind: String, _ address: String) -> String { "aztec.stake.\(kind).\(address.lowercased())" }

    /// Unwatching takes the walk with it, beside the siblings' (`WalletStore`).
    static func clearState(address: String) {
        let d = UserDefaults.standard
        for entry in d.stringArray(forKey: key("vaults", address)) ?? [] {
            guard let staker = entry.split(separator: "@").last else { continue }
            d.removeObject(forKey: key("cursor", String(staker)))
            d.removeObject(forKey: key("attesters", String(staker)))
        }
        for kind in ["attesters", "cursor", "vaults", "vaultCursor"] { d.removeObject(forKey: key(kind, address)) }
    }

    struct Book: Equatable, Sendable {
        var stakes: [AztecStakeWire.Stake] = []
        var vaults: [AztecStakeWire.Vault] = []
        /// An Aztec vote still to come, read only when there are stakes.
        var proposals: [AztecStakeWire.Proposal] = []
        /// False when some walk has not reached the head yet: what it found
        /// is true, and what it has not found is not yet known.
        var complete = true
        var isEmpty: Bool { stakes.isEmpty && !vaults.contains { $0.held > 0 } }
    }

    private static let cache = CoalescingCache<Book>()

    /// nil when mainnet could not be reached for any wallet. Five minutes
    /// fresh: a stake's state, health and rewards move by the epoch, not the
    /// second, and a full read is a few calls per stake.
    static func book(addresses: [String]) async -> Book? {
        guard !addresses.isEmpty else { return Book() }
        let key = addresses.map { $0.lowercased() }.sorted().joined(separator: ",")
        return await cache.value(key: key, ttl: 300) {
            await fetchBook(addresses: addresses)
        }
    }

    private static func fetchBook(addresses: [String]) async -> Book? {
        guard let head = await blockNumber() else { return nil }
        let rollup = AztecStakeWire.address(reply: await call(AztecStakeWire.registry, AztecStakeWire.getCanonicalRollup))
            ?? AztecStakeWire.rollups[0]
        var book = Book()
        var reached = false
        // Once each: the sweep's list can carry one wallet twice (a name and
        // its hex), which would read every stake twice and land each row twice.
        var seen = Set<String>()
        for address in addresses.map({ $0.lowercased() }) where seen.insert(address).inserted {
            let vaults = await discoverVaults(address: address, head: head, book: &book)
            var withdrawers: [(String, AztecStakeWire.Via)] = [(address, .direct)]
            for (atp, staker) in vaults { withdrawers.append((staker, .vault(atp))) }

            var keys: [(attester: String, withdrawer: String, via: AztecStakeWire.Via)] = []
            for (withdrawer, via) in withdrawers {
                guard let (found, caughtUp) = await discoverStakes(withdrawer: withdrawer, head: head) else {
                    book.complete = false
                    continue
                }
                reached = true
                if !caughtUp { book.complete = false }
                for k in found {
                    let parts = k.split(separator: "@").map(String.init)
                    if parts.count == 2 { keys.append((parts[0], parts[1], via)) }
                }
            }
            // Four stakes at a time: one at a time, nineteen stakes held the
            // Wallet's whole live read for over a minute (measured 2026-10-12).
            if keys.count > maxAttestersPerWallet { book.complete = false }
            let wanted = Array(keys.suffix(maxAttestersPerWallet).reversed())
            await withTaskGroup(of: (Int, AztecStakeWire.Stake?, Bool).self) { group in
                var next = 0
                func start() {
                    guard next < wanted.count else { return }
                    let i = next, k = wanted[i]
                    next += 1
                    group.addTask {
                        let (stake, failed) = await readStake(attester: k.attester, withdrawer: k.withdrawer, via: k.via,
                                                              owner: address, rollup: rollup, head: head)
                        return (i, stake, failed)
                    }
                }
                for _ in 0..<4 { start() }
                var read: [(Int, AztecStakeWire.Stake)] = []
                for await (i, stake, failed) in group {
                    if failed { book.complete = false }
                    if let stake { read.append((i, stake)) }
                    start()
                }
                book.stakes += read.sorted { $0.0 < $1.0 }.map(\.1)
            }
        }
        book.stakes.sort { $0.amount > $1.amount }
        if !book.stakes.isEmpty { book.proposals = await openProposals() }
        return reached ? book : nil
    }

    /// One stake on the canonical Rollup, with its provider's rewards and
    /// its sequencer's record. `failed` when the view itself could not be
    /// read, so the book says it is incomplete rather than empty.
    private static func readStake(attester: String, withdrawer: String, via: AztecStakeWire.Via,
                                  owner: String, rollup: String, head: Int) async -> (AztecStakeWire.Stake?, Bool) {
        guard let view = await call(rollup, AztecStakeWire.viewCall(attester)) else { return (nil, true) }
        guard var stake = AztecStakeWire.stake(view: view, owner: owner, withdrawer: withdrawer,
                                               attester: attester, rollup: rollup) else { return (nil, false) }
        stake.via = via
        // A delegated stake's rewards are the wallet's share of the split, or
        // its vault staker's (measured 2026-10-12: one vault stake's split
        // names the wallet though its event names the staker), both its
        // money. The wallet is asked first.
        if let p = await provider(attester: attester, head: head) {
            if case .direct = via { stake.via = .provider(p.id) }
            stake.rewards = await rewards(coinbase: p.coinbase, recipients: [owner, withdrawer], head: head)
        }
        if stake.status == .validating, let seq = await sequencer(stake.attester) {
            stake.missedStreak = seq.attestations.streak
            stake.lastAttestationSlot = seq.lastAttestation?.slot
        }
        return (stake, false)
    }

    // MARK: - Discovery

    /// The wallet's vaults as (atp, staker), walking `ATPCreated` forward and
    /// asking each new vault its staker once. Each vault's balance and
    /// claimable part is read fresh into `book`, and only while the vault
    /// still names this wallet its beneficiary.
    private static func discoverVaults(address: String, head: Int, book: inout Book) async -> [(String, String)] {
        let d = UserDefaults.standard
        var known = d.stringArray(forKey: key("vaults", address)) ?? []
        var from = max((d.object(forKey: key("vaultCursor", address)) as? Int) ?? AztecStakeWire.atpFirstBlock,
                       AztecStakeWire.atpFirstBlock)
        let range = WalletApprovals.maxLogRange(forNetwork: network) ?? 900_000
        var chunks = 0
        while from <= head, chunks < maxChunksPerPass {
            let to = min(head, from + range - 1)
            guard let logs = await read("eth_getLogs", [AztecStakeWire.vaultFilter(beneficiary: address, from: from, to: to)])
                    as? [[String: Any]] else { break }
            var complete = true
            for atp in AztecStakeWire.vaults(fromLogs: logs, beneficiary: address)
            where !known.contains(where: { $0.hasPrefix(atp + "@") }) {
                guard let staker = AztecStakeWire.address(reply: await call(atp, AztecStakeWire.getStaker)) else {
                    complete = false
                    continue
                }
                known.append(atp + "@" + staker)
            }
            // A vault whose staker could not be read is asked again next
            // pass: the cursor stays on this chunk.
            guard complete else { break }
            from = to + 1
            chunks += 1
        }
        if from <= head { book.complete = false }
        d.set(known, forKey: key("vaults", address))
        d.set(rewound(from, head: head, floor: AztecStakeWire.atpFirstBlock), forKey: key("vaultCursor", address))

        if known.count > maxVaultsPerWallet { book.complete = false }
        var out: [(String, String)] = []
        for entry in known.prefix(maxVaultsPerWallet) {
            let parts = entry.split(separator: "@").map(String.init)
            guard parts.count == 2 else { continue }
            // A vault whose beneficiary moved on is no longer this wallet's:
            // only another ADDRESS says so. A failed read keeps it, and the
            // book says it is incomplete.
            let beneficiary = await call(parts[0], AztecStakeWire.getBeneficiary)
            if beneficiary == nil { book.complete = false }
            if let b = beneficiary, AztecStakeWire.address(reply: b) != address { continue }
            out.append((parts[0], parts[1]))
            guard let held = AztecStakeWire.amount(reply: await call(
                AztecStakeWire.token, AztecStakeWire.balanceOf + AztecStakeWire.topic(parts[0]).dropFirst(2))) else {
                book.complete = false
                continue
            }
            let claimable = AztecStakeWire.amount(reply: await call(parts[0], AztecStakeWire.getClaimable))
            if claimable == nil { book.complete = false }
            book.vaults.append(AztecStakeWire.Vault(owner: address, atp: parts[0], staker: parts[1],
                                                    held: held, claimable: claimable.map { min($0, held) }))
        }
        return out
    }

    /// Every "attester@withdrawer" `withdrawer` can take out, oldest first,
    /// walking forward from where its last pass stopped, and whether the walk
    /// reached the head. nil when no chunk could be read and nothing is known.
    private static func discoverStakes(withdrawer: String, head: Int) async -> ([String], Bool)? {
        let d = UserDefaults.standard
        var known = d.stringArray(forKey: key("attesters", withdrawer)) ?? []
        var from = max((d.object(forKey: key("cursor", withdrawer)) as? Int) ?? AztecStakeWire.firstBlock,
                       AztecStakeWire.firstBlock)
        let range = WalletApprovals.maxLogRange(forNetwork: network) ?? 900_000
        var chunks = 0
        var readAny = from > head
        while from <= head, chunks < maxChunksPerPass {
            let to = min(head, from + range - 1)
            guard let logs = await read("eth_getLogs",
                    [AztecStakeWire.logFilter(withdrawers: [withdrawer], from: from, to: to)]) as? [[String: Any]]
            else { break }
            readAny = true
            for key in AztecStakeWire.attesters(fromLogs: logs, withdrawers: [withdrawer]) where !known.contains(key) {
                known.append(key)
            }
            from = to + 1
            chunks += 1
        }
        guard readAny || !known.isEmpty else { return nil }
        d.set(known, forKey: key("attesters", withdrawer))
        d.set(rewound(from, head: head, floor: AztecStakeWire.firstBlock), forKey: key("cursor", withdrawer))
        return (known, from > head)
    }

    /// Where the next pass starts: a few blocks back from the head reached,
    /// because the head came from one host and the logs may have come from
    /// another a few blocks behind it. The overlap is free: a stake already
    /// known is not added twice.
    private static func rewound(_ from: Int, head: Int, floor: Int) -> Int {
        from > head ? max(floor, head - 12) : from
    }

    // MARK: - Rewards

    /// The provider a stake was delegated to, once per attester: a stake is
    /// delegated when it is queued and never later, so "none" is kept too.
    private static func provider(attester: String, head: Int) async -> (id: Int, coinbase: String, recipient: String)? {
        let d = UserDefaults.standard
        let k = key("provider", attester)
        if let kept = d.string(forKey: k) {
            let p = kept.split(separator: "|").map(String.init)
            return p.count == 3 ? (Int(p[0]) ?? 0, p[1], p[2]) : nil
        }
        guard let logs = await walk(head: head, { AztecStakeWire.providerFilter(attester: attester, from: $0, to: $1) })
        else { return nil }
        guard let p = AztecStakeWire.provider(fromLogs: logs, attester: attester) else {
            d.set("-", forKey: k)
            return nil
        }
        d.set("\(p.id)|\(p.coinbase)|\(p.recipient)", forKey: k)
        return p
    }

    /// The first of `recipients` the split names: its share of what every
    /// Rollup owes the stake's payout address. nil when the split names none
    /// of them or a read failed: a number we could not read is never drawn
    /// as zero.
    private static func rewards(coinbase: String, recipients: [String], head: Int) async -> Double? {
        // A split can be updated, so a share is kept a week, then read again.
        let d = UserDefaults.standard
        let k = key("share", "\(coinbase).\(recipients.joined(separator: "."))")
        var share: Double?
        if let kept = d.array(forKey: k) as? [Double], kept.count == 2,
           Date.now.timeIntervalSince1970 - kept[1] < 7 * 86_400 {
            share = kept[0]
        } else {
            guard let logs = await walk(head: head, { AztecStakeWire.splitFilter(coinbase: coinbase, from: $0, to: $1) })
            else { return nil }
            let found = recipients.lazy.compactMap {
                AztecStakeWire.share(fromLogs: logs, coinbase: coinbase, recipient: $0)
            }.first ?? -1
            d.set([found, Date.now.timeIntervalSince1970], forKey: k)
            share = found
        }
        guard let share, share > 0 else { return nil }
        var owed = 0.0
        for rollup in AztecStakeWire.rollups {
            guard let amount = AztecStakeWire.amount(reply: await call(
                rollup, AztecStakeWire.getSequencerRewards + AztecStakeWire.topic(coinbase).dropFirst(2))) else { return nil }
            owed += amount
        }
        return owed * share
    }

    /// Every log one filter matches from `firstBlock` to `head`, in the host
    /// pool's own range cap. nil when any chunk failed: a lookup that saw
    /// only part of history must not be kept as "none".
    private static func walk(head: Int, _ filter: (Int, Int) -> [String: Any]) async -> [[String: Any]]? {
        let range = WalletApprovals.maxLogRange(forNetwork: network) ?? 900_000
        var out: [[String: Any]] = []
        var from = AztecStakeWire.firstBlock
        while from <= head {
            let to = min(head, from + range - 1)
            guard let logs = await read("eth_getLogs", [filter(from, to)]) as? [[String: Any]] else { return nil }
            out += logs
            from = to + 1
        }
        return out
    }

    // MARK: - Health and governance

    private static func sequencer(_ attester: String) async -> AztecWire.Sequencer? {
        let body: [String: Any] = ["jsonrpc": "2.0", "id": 1, "method": "node_getValidatorStats", "params": [attester]]
        guard let reply = await IngestSupport.postJSON(node, body: body) as? [String: Any] else { return nil }
        return AztecWire.sequencer(reply["result"])
    }

    /// The newest three proposals still pending or open.
    private static func openProposals() async -> [AztecStakeWire.Proposal] {
        guard let count = AztecStakeWire.count(reply: await call(AztecStakeWire.governance, AztecStakeWire.proposalCount)),
              count > 0 else { return [] }
        var out: [AztecStakeWire.Proposal] = []
        for id in max(0, count - 3)..<count {
            let arg = AztecStakeWire.word(id)
            let view = await call(AztecStakeWire.governance, AztecStakeWire.getProposal + arg)
            let state = await call(AztecStakeWire.governance, AztecStakeWire.getProposalState + arg)
            if let p = AztecStakeWire.proposal(id: id, view: view, state: state) { out.append(p) }
        }
        return out
    }

    // MARK: - Rows

    /// Lands what the book says once: an exit that can be taken out (it
    /// notifies), a sequencer that stopped attesting (it notifies), and an
    /// Aztec vote still to come (quiet, retitled in place when it opens).
    /// Returns the landed count, nil when mainnet couldn't be reached.
    @MainActor
    static func syncEvents(context: ModelContext, addresses: [String], existing: Set<String>) async -> Int? {
        guard !addresses.isEmpty else { return 0 }
        guard let book = await book(addresses: addresses) else { return nil }
        var added = 0
        var landedNow = Set<String>()
        func land(ref: String, title: String, url: String, due: Date?, wallet: String) {
            guard landedNow.insert(ref).inserted else { return }
            if existing.contains(ref) {
                guard let landed = try? context.fetch(FetchDescriptor<Thing>(
                    predicate: #Predicate { $0.sourceRef == ref })).first else { return }
                if landed.title != title { landed.title = title }
                if landed.dueAt != due { landed.dueAt = due }
                return
            }
            let thing = Thing(kind: .link, title: title, content: url, source: "Wallet",
                              capturedAt: .now, sourceRef: ref)
            thing.dueAt = due
            thing.walletAddress = wallet
            context.insert(thing)
            SpotlightIndex.index([thing])
            added += 1
        }
        for stake in book.stakes {
            if stake.status == .exiting, let at = stake.exitableAt, at <= .now {
                land(ref: "aztec:exit:\(stake.attester):\(stake.withdrawalID)", title: AztecStakeWire.readyTitle(stake),
                     url: "https://stake.aztec.network", due: at, wallet: stake.owner)
            }
            if stake.isStopped {
                land(ref: "aztec:stake:\(stake.attester):stopped:\(stake.lastAttestationSlot ?? 0)",
                     title: AztecStakeWire.stoppedTitle(stake),
                     url: "https://aztecscan.xyz/validators/\(stake.attester)", due: nil, wallet: stake.owner)
            }
        }
        if let wallet = book.stakes.first?.owner {
            for p in book.proposals {
                land(ref: "aztec:vote:\(p.id)", title: AztecStakeWire.voteTitle(p),
                     url: "https://aztecgov.nethermind.io/\(p.id)", due: p.closes, wallet: wallet)
            }
        }
        if added > 0 { _ = context.saveHonestly() }
        return added
    }

    // MARK: - Reads

    private static func call(_ to: String, _ data: String) async -> String? {
        await read("eth_call", [["to": to, "data": data], "latest"]) as? String
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
    /// `-aztecStakeProbe <0x wallet>` — one wallet's AZTEC stakes, vaults and
    /// open votes, read without watching it (its walk is cleared first, so
    /// every run walks from scratch), one NSLog line each.
    static func probe(address: String) async -> [String] {
        clearState(address: address)
        guard let book = await book(addresses: [address.lowercased()]) else { return ["book UNREACHABLE"] }
        var lines = book.stakes.map { s -> String in
            let via: String
            switch s.via {
            case .direct: via = "direct"
            case .provider(let id): via = "provider \(id)"
            case .vault(let atp): via = "vault \(AztecStakeWire.shortAddress(atp))"
            }
            return "\(s.attester) | \(s.status) | \(WalletIngest.format(s.amount)) AZTEC | \(via) | "
                + "\(AztecStakeWire.state(s)) | earned \(s.rewards.map { AztecStakeWire.plain($0) } ?? "unread") | "
                + "missed \(s.missedStreak.map(String.init) ?? "unread")"
        }
        for v in book.vaults {
            lines.append("vault \(v.atp) | held \(AztecStakeWire.plain(v.held)) | claimable \(v.claimable.map { AztecStakeWire.plain($0) } ?? "unread")")
        }
        for p in book.proposals { lines.append("vote | \(AztecStakeWire.voteTitle(p))") }
        if book.stakes.isEmpty && book.vaults.isEmpty {
            lines.append(book.complete ? "no stakes (a real empty answer, not a miss)"
                                       : "none found YET: a walk has not reached the head")
        }
        lines.append("complete=\(book.complete)")
        return lines
    }
    #endif
}
