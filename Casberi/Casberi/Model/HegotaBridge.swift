import Foundation
import Observation

/// Ethrex Hegotá (2026-08-27) — an experimental devnet testing frame
/// transactions (EIP-8141 and its family). Chain id 3151908, keyless RPC on
/// three hosts. Genuinely read-only in every sense: no key of this app's own
/// touches it, no funds move, and nothing in this file can write to the chain.
///
/// ## WHY THIS CHAIN EARNS A SEAT
///
/// It publishes three things every other chain hides, and each is readable with
/// no indexer, no API key and no credits:
///   • **every ETH movement is a log** (EIP-7708 from `0xff…fe`), so an
///     address's whole value history is one `eth_getLogs` — the line this room
///     draws is EXACT, not sampled the way `WalletStore.ValueSample` has to be
///   • **every transaction says who paid it** (`payer` on a type-`0x6`
///     receipt), so gas sponsorship is a first-class visible fact
///   • **every transaction decomposes into frames** with per-frame status and
///     both gas dimensions, so a row can say what a transaction DID rather than
///     one opaque success
///
/// ## THE READS ARE BOUNDED, AND THE BOUNDS ARE STATED
///
/// A sweep is six requests plus one batch: balance, two transfer-log reads (out
/// and in), the coin log read, one batched `eth_getStorageAt` per 256 coins,
/// the vault's balance for reconciliation, and one batch of transaction reads
/// for the newest `frameDepth` moves. Frame detail past that depth is fetched
/// ON TAP, never per scroll.
///
/// ## THE CONDUCT PROMISE
///
/// **This file issues `eth_call`-class READS and nothing else.** Hegotá has a
/// faucet that mints test ETH on a POST and an `eth_sendRawTransaction` that
/// takes signed bytes, and this seat touches neither: there is no key here to
/// sign with and no path that would use one. `scripts/hegota-selftest.sh` fails
/// the build if this file ever names a write method, because the promise is
/// worth more than the memory of having made it — the `CursorFetch` rule, in a
/// file one method call away from moving money on a chain.
enum HegotaIdentity {
    static let source = "Ethrex Hegotá"
    static let seatID = "hegota"

    /// The block explorer and the faucet — opened in the person's OWN browser
    /// on a tap, never reached by us. They are in the reach audit's non-reach
    /// denylist for exactly that reason.
    static let explorer = "https://dora.hegota.ethrex.xyz"
    static let faucet = "https://faucet.hegota.ethrex.xyz"
}

// MARK: - RPC (keyless)

enum HegotaRPC {
    /// **Three hosts, tried in order.** Measured 2026-08-27: all three answer
    /// `eth_chainId` with `0x301824` in about half a second, so a host being
    /// down is a retry rather than an outage — the one piece of redundancy this
    /// devnet hands us for free, and it costs nothing to use.
    static let hosts = [
        "https://rpc1.hegota.ethrex.xyz",
        "https://rpc2.hegota.ethrex.xyz",
        "https://rpc3.hegota.ethrex.xyz",
    ]

    /// The newest transactions whose frames are read during a sweep. Frame
    /// detail for anything older is fetched when a row is OPENED — a bound on
    /// requests, not on what a person can see.
    static let frameDepth = 20
    /// How many distinct blocks get their header read for a timestamp. Higher
    /// than `frameDepth` because a header is far cheaper than a receipt and
    /// this is the only read that dates the COINS list too.
    static let timeDepth = 60

    /// One JSON-RPC call, walking the hosts until one answers.
    ///
    /// Returns nil when NO host answered, which the callers must keep distinct
    /// from a host answering with nothing: an unreached read is not evidence of
    /// an empty account, and the room says "couldn't reach the chain" rather
    /// than drawing a zero.
    static func call(method: String, params: [Any]) async -> Any? {
        let body: [String: Any] = ["id": 1, "jsonrpc": "2.0", "method": method, "params": params]
        for host in hosts {
            guard let root = await IngestSupport.postJSON(host, body: body,
                                                          service: HegotaIdentity.source)
                    as? [String: Any] else { continue }
            if let result = root["result"], !(result is NSNull) { return result }
            // A host that answered with an ERROR has answered — walking on
            // would ask two more hosts the same malformed question and report
            // "unreachable" for what is really our own bad request.
            if root["error"] != nil { return nil }
        }
        return nil
    }

    /// A batch of calls in ONE request. Measured working on this chain, and it
    /// is what makes the spent-bitmap read a single round trip rather than one
    /// per 256 coins.
    ///
    /// Results are matched by the `id` each call was sent with, NEVER by array
    /// position — JSON-RPC permits a server to answer a batch in any order, and
    /// a positional read would silently attribute one coin's spent bits to
    /// another coin's word.
    static func batch(_ calls: [(method: String, params: [Any])]) async -> [Int: Any]? {
        guard !calls.isEmpty else { return [:] }
        let body: [[String: Any]] = calls.enumerated().map { i, c in
            ["id": i, "jsonrpc": "2.0", "method": c.method, "params": c.params]
        }
        for host in hosts {
            guard let rows = await IngestSupport.postJSONArray(host, body: body,
                                                               service: HegotaIdentity.source)
            else { continue }
            var out: [Int: Any] = [:]
            for row in rows {
                guard let id = row["id"] as? Int,
                      let result = row["result"], !(result is NSNull) else { continue }
                out[id] = result
            }
            return out
        }
        return nil
    }

    static func getBalance(_ address: String) async -> String? {
        await call(method: "eth_getBalance", params: [address, "latest"]) as? String
    }

    static func getStorageAt(_ address: String, slot: String) async -> String? {
        await call(method: "eth_getStorageAt", params: [address, slot, "latest"]) as? String
    }

    /// `eth_getLogs` over the whole chain.
    ///
    /// Unbounded from block 0 DELIBERATELY, and measured: this chain serves the
    /// full history in one call (the vault's 49 logs, the transfer source's 254)
    /// with no block-range ceiling — unlike vibenet, whose RPC enforces 100,000
    /// blocks and whose from-zero read fails outright. If that ever changes here
    /// the symptom is the one vibenet already paid for: an established account
    /// reading as unreached, so the caller must keep nil meaning "we could not
    /// look" rather than "there is nothing".
    static func getLogs(address: String, topics: [Any]) async -> [[String: Any]]? {
        let filter: [String: Any] = [
            "fromBlock": "0x0", "toBlock": "latest", "address": address, "topics": topics,
        ]
        return await call(method: "eth_getLogs", params: [filter]) as? [[String: Any]]
    }

    /// A 32-byte topic for an address — left-padded, lowercased, which is the
    /// only form a log filter matches.
    static func topic(_ address: String) -> String {
        let body = address.lowercased().hasPrefix("0x")
            ? String(address.lowercased().dropFirst(2)) : address.lowercased()
        return "0x" + String(repeating: "0", count: max(0, 64 - body.count)) + body
    }
}

// MARK: - The read

enum HegotaRead {
    /// Everything the room needs about one address, in one bounded sweep.
    static func account(_ address: String) async -> HegotaAccount {
        var out = HegotaAccount(address: address)
        let addressTopic = HegotaRPC.topic(address)

        // 1. The balance, and 2/3. the value history — every ETH movement on
        //    this chain is a log, so both directions are one read each.
        async let balance = HegotaRPC.getBalance(address)
        async let outgoing = HegotaRPC.getLogs(
            address: HegotaChain.transferLogSource,
            topics: [HegotaChain.transferTopic, addressTopic])
        async let incoming = HegotaRPC.getLogs(
            address: HegotaChain.transferLogSource,
            topics: [HegotaChain.transferTopic, NSNull(), addressTopic])
        // 4. The coins this address owns — the recipient is topic 2.
        async let coinLogs = HegotaRPC.getLogs(
            address: HegotaChain.vault,
            topics: [HegotaChain.utxoCreatedTopic, NSNull(), addressTopic])

        let (bal, outs, ins, coins) = await (balance, outgoing, incoming, coinLogs)

        // Reached means a host answered SOMETHING. A single successful read is
        // enough to know the chain is there; the others answering nil then
        // means those reads failed rather than that the account is empty.
        out.reached = bal != nil || outs != nil || ins != nil || coins != nil
        guard out.reached else { return out }

        if let bal, let wei = HegotaWord.integer(padded(bal)) { out.balanceWei = wei }

        var moves: [HegotaMove] = []
        for (logs, incomingSide) in [(outs, false), (ins, true)] {
            for log in logs ?? [] {
                guard let m = move(log: log, incoming: incomingSide) else { continue }
                moves.append(m)
            }
        }
        out.moves = moves.sorted { $0.block > $1.block }

        out.coins = (coins ?? []).compactMap { log in
            guard let topics = log["topics"] as? [String],
                  let data = log["data"] as? String,
                  let blockHex = log["blockNumber"] as? String
            else { return nil }
            return HegotaCoins.coin(topics: topics, data: data,
                                    block: UInt64(WalletIngest.hexToInt(blockHex)),
                                    tx: log["transactionHash"] as? String)
        }

        await readCoinState(&out)
        await readFrames(&out)
        await readTimes(&out)
        out.lanes = lanes(from: out.moves)
        return out
    }

    /// When each block was mined — the room's only clock.
    ///
    /// **Every row in this room was undated before this**, alone among the
    /// app's lists, because a log carries a block NUMBER and nothing else. One
    /// batched header read per unique block fixes it for both moves and coins
    /// at once, and headers are the cheapest thing this chain serves (`false`
    /// asks for the header alone, never the transaction bodies).
    ///
    /// Bounded at `timeDepth` blocks like every other read here: an address
    /// with a long history would otherwise buy a growing read forever. Past
    /// the window a row simply carries no time, which is why `timestamp` is
    /// Optional and why nothing downstream substitutes `.now` for a miss — a
    /// row stamped with the moment we looked is the fake status §83 bans, and
    /// `PeerRoom` already paid for that lesson.
    private static func readTimes(_ out: inout HegotaAccount) async {
        var blocks: [UInt64] = []
        for move in out.moves where !blocks.contains(move.block) { blocks.append(move.block) }
        for coin in out.coins where !blocks.contains(coin.block) { blocks.append(coin.block) }
        // Newest first, so a bounded read spends its budget on the rows
        // somebody is actually looking at.
        blocks.sort(by: >)
        let wanted = Array(blocks.prefix(HegotaRPC.timeDepth))
        guard !wanted.isEmpty else { return }

        let calls = wanted.map { block -> (method: String, params: [Any]) in
            ("eth_getBlockByNumber", [String(format: "0x%llx", block), false])
        }
        guard let answers = await HegotaRPC.batch(calls) else { return }

        var times: [UInt64: Date] = [:]
        for (i, block) in wanted.enumerated() {
            guard let header = answers[i] as? [String: Any],
                  let stamp = header["timestamp"] as? String else { continue }
            let seconds = WalletIngest.hexToInt(stamp)
            guard seconds > 0 else { continue }
            times[block] = Date(timeIntervalSince1970: TimeInterval(seconds))
        }
        guard !times.isEmpty else { return }

        out.moves = out.moves.map { var m = $0; m.timestamp = times[$0.block]; return m }
        out.coins = out.coins.map { var c = $0; c.timestamp = times[$0.block]; return c }
        // `unspent` is a FILTERED COPY of `coins`, not a view of it, so it has
        // to be restamped too — leaving it means the Coins list, which draws
        // from `unspent`, stays the one undated list in a now-dated room.
        if let held = out.unspent {
            out.unspent = held.map { var c = $0; c.timestamp = times[$0.block]; return c }
        }
    }

    /// The spent bitmap and the reconciliation.
    ///
    /// **Both halves read the WHOLE chain's coins, not this address's slice**,
    /// and that is what makes the gate meaningful: conservation holds across
    /// every owner together, so the vault's balance can only be checked against
    /// every unspent coin there is. The address's own coins are then filtered
    /// out of a set already proven complete.
    private static func readCoinState(_ out: inout HegotaAccount) async {
        guard let all = await HegotaRPC.getLogs(address: HegotaChain.vault,
                                                topics: [HegotaChain.utxoCreatedTopic])
        else { return }
        let every: [HegotaCoin] = all.compactMap { log in
            guard let topics = log["topics"] as? [String],
                  let data = log["data"] as? String,
                  let blockHex = log["blockNumber"] as? String
            else { return nil }
            return HegotaCoins.coin(topics: topics, data: data,
                                    block: UInt64(WalletIngest.hexToInt(blockHex)),
                                    tx: log["transactionHash"] as? String)
        }
        guard !every.isEmpty else { return }

        let words = Set(every.map { HegotaVaultStorage.word(index: $0.index) }).sorted()
        let calls = words.map { word -> (method: String, params: [Any]) in
            let anyIndex = every.first { HegotaVaultStorage.word(index: $0.index) == word }!.index
            return ("eth_getStorageAt",
                    [HegotaChain.vault, HegotaVaultStorage.spentSlot(index: anyIndex), "latest"])
        }
        guard let answers = await HegotaRPC.batch(calls) else { return }
        var bitmap: [UInt64: String] = [:]
        for (i, word) in words.enumerated() {
            if let hex = answers[i] as? String { bitmap[word] = padded(hex) }
        }

        guard let unspentEverywhere = HegotaCoins.unspent(every, words: bitmap),
              let vaultHex = await HegotaRPC.getBalance(HegotaChain.vault),
              let vaultWei = HegotaWord.integer(padded(vaultHex))
        else { return }

        out.reconciled = HegotaCoins.reconciles(unspent: unspentEverywhere, vaultWei: vaultWei)
        let mine = Set(out.coins.map(\.index))
        out.unspent = unspentEverywhere.filter { mine.contains($0.index) }
    }

    /// The frames, the payer and the nonce keys for the newest moves.
    ///
    /// Bounded at `frameDepth` — this is the only read here whose cost grows
    /// with history, and a room that fetches every transaction an address ever
    /// made is one that gets slower forever.
    private static func readFrames(_ out: inout HegotaAccount) async {
        let hashes = Array(NSOrderedSet(array: out.moves.map(\.hash)).array as! [String])
            .prefix(HegotaRPC.frameDepth)
        guard !hashes.isEmpty else { return }

        var calls: [(method: String, params: [Any])] = []
        for h in hashes { calls.append(("eth_getTransactionByHash", [h])) }
        for h in hashes { calls.append(("eth_getTransactionReceipt", [h])) }
        guard let answers = await HegotaRPC.batch(calls) else { return }

        var byHash: [String: (tx: [String: Any], receipt: [String: Any]?)] = [:]
        for (i, h) in hashes.enumerated() {
            guard let tx = answers[i] as? [String: Any] else { continue }
            byHash[h] = (tx, answers[i + hashes.count] as? [String: Any])
        }

        out.moves = out.moves.map { move in
            guard let pair = byHash[move.hash] else { return move }
            var m = move
            m.isFrameTransaction = (pair.tx["type"] as? String)?.lowercased() == "0x6"
            m.sender = (pair.tx["sender"] as? String ?? pair.tx["from"] as? String)?.lowercased()
            m.payer = (pair.receipt?["payer"] as? String)?.lowercased()
            m.nonceSeq = pair.tx["nonceSeq"] as? String
            m.nonceKeys = (pair.tx["nonceKeys"] as? [String] ?? [])
                .filter { WalletIngest.hexToInt($0) != 0 }
            // **THE FEE COSTS NO READ** — both halves are on the receipt this
            // sweep already fetched, and multiplying them is what turns "gas
            // was sponsored" from a sentence into an amount somebody gave you.
            // Both must be present: half of a product is not a fee, and a
            // missing one leaves nil rather than a zero that would read as a
            // free transaction.
            if let used = pair.receipt?["gasUsed"] as? String,
               let price = pair.receipt?["effectiveGasPrice"] as? String,
               let usedWei = HegotaWord.integer(padded(used)),
               let priceWei = HegotaWord.integer(padded(price)) {
                m.feeWei = usedWei * priceWei
            }
            if m.isFrameTransaction {
                m.frames = frames(tx: pair.tx, receipt: pair.receipt)
            }
            return m
        }
    }

    private static func frames(tx: [String: Any], receipt: [String: Any]?) -> [HegotaFrame] {
        let wire = tx["frames"] as? [[String: Any]] ?? []
        let receipts = receipt?["frameReceipts"] as? [[String: Any]] ?? []
        return wire.enumerated().map { i, f in
            // A frame's receipt is paired BY POSITION, which is the pairing the
            // spec defines — but only when the counts agree. A mismatch means
            // we have misread one of the two, and a pip claiming success it
            // cannot support is worse than a hollow one.
            let r = receipts.count == wire.count ? receipts[i] : nil
            return HegotaFrame(
                mode: HegotaFrame.Mode(wire: WalletIngest.hexToInt(f["mode"] as? String ?? "")),
                target: (f["to"] as? String)?.lowercased(),
                wei: HegotaWord.integer(padded(f["value"] as? String ?? "0x0")) ?? 0,
                succeeded: (r?["status"] as? String).map { WalletIngest.hexToInt($0) == 1 },
                gasUsed: (r?["gasUsed"] as? String).map { UInt64(WalletIngest.hexToInt($0)) },
                stateGasUsed: (r?["stateGasUsed"] as? String).map { UInt64(WalletIngest.hexToInt($0)) })
        }
    }

    /// The nonce lanes, folded out of the moves whose transactions were read.
    ///
    /// **Only the newest `frameDepth` transactions carry keys**, so this is a
    /// floor rather than a census, and the card says "at least" for that
    /// reason. Reading every transaction to be exhaustive is the unbounded
    /// walk the depth cap exists to prevent.
    static func lanes(from moves: [HegotaMove]) -> [HegotaNonceLane] {
        var seen: [String: (seq: String?, block: UInt64, count: Int)] = [:]
        for move in moves {
            for key in move.nonceKeys {
                let k = key.lowercased()
                if let prior = seen[k] {
                    seen[k] = (move.block > prior.block ? move.nonceSeq : prior.seq,
                               max(prior.block, move.block), prior.count + 1)
                } else {
                    seen[k] = (move.nonceSeq, move.block, 1)
                }
            }
        }
        return seen.map { HegotaNonceLane(key: $0.key, seq: $0.value.seq,
                                          lastBlock: $0.value.block, sends: $0.value.count) }
            .sorted { $0.lastBlock > $1.lastBlock }
    }

    private static func move(log: [String: Any], incoming: Bool) -> HegotaMove? {
        guard let topics = log["topics"] as? [String], topics.count == 3,
              let data = log["data"] as? String,
              let hash = log["transactionHash"] as? String,
              let blockHex = log["blockNumber"] as? String,
              let wei = HegotaWord.integer(padded(data)),
              let other = HegotaWord.address(topic: incoming ? topics[1] : topics[2])
        else { return nil }
        return HegotaMove(hash: hash, counterparty: other, wei: wei, incoming: incoming,
                          block: UInt64(WalletIngest.hexToInt(blockHex)))
    }

    /// The RPC returns quantities in their MINIMAL hex form (`0xf8c2…`), while
    /// every word parser here expects a full 32-byte word. Padding at the read
    /// boundary keeps that difference in one place instead of making each
    /// parser tolerant, which is how a parser stops noticing a word that is
    /// genuinely the wrong size.
    static func padded(_ hex: String) -> String {
        let body = hex.lowercased().hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
        guard body.count < 64 else { return "0x" + body }
        return "0x" + String(repeating: "0", count: 64 - body.count) + body
    }
}

// MARK: - The watch list

/// The addresses being watched, as a plain UserDefaults list rather than a
/// `Thing` per address — the `VibenetWatch` shape. A devnet address has no
/// product page, no news to arrive under it and nothing to search for.
@Observable
final class HegotaWatch {
    static let shared = HegotaWatch()
    private static let key = "hegota.watch.addresses.v1"

    private var addressList: [String] { didSet { persist() } }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([String].self, from: data) {
            addressList = saved
        } else {
            addressList = []
        }
    }

    var addresses: [String] { addressList }
    var connected: Bool { !addressList.isEmpty }

    func isWatching(_ address: String) -> Bool {
        addressList.contains { $0.caseInsensitiveCompare(address) == .orderedSame }
    }

    static func isValidAddress(_ raw: String) -> Bool {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count == 42, s.hasPrefix("0x") else { return false }
        return s.dropFirst(2).allSatisfy(\.isHexDigit)
    }

    @discardableResult
    func add(_ raw: String) -> Bool {
        let address = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidAddress(address), !isWatching(address) else { return false }
        addressList.append(address)
        let book = AddressBook.shared
        if book.entry(for: address) == nil {
            book.setName(WalletStore.shortAddress(address), for: address,
                         networks: [AddressBook.Network.hegota])
        } else {
            book.addNetwork(AddressBook.Network.hegota, for: address)
        }
        return true
    }

    func remove(_ address: String) {
        addressList.removeAll { $0.caseInsensitiveCompare(address) == .orderedSame }
    }

    func removeAll() { addressList = [] }

    func name(for address: String) -> String? { AddressBook.shared.name(for: address) }

    private func persist() {
        guard let data = try? JSONEncoder().encode(addressList) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}

// MARK: - Live state for the room

@Observable
@MainActor
final class HegotaLiveState {
    static let shared = HegotaLiveState()

    /// The last sweep is PERSISTED, and the demo's fixture is why.
    ///
    /// This started as in-memory state, which is right for a live read — and
    /// wrong for the demo, whose whole furnishing for this seat IS the fixture.
    /// It died on the next launch, and since the seat lands no rows the room
    /// then had nothing at all to draw: reported from a device as "it's a plain
    /// black screen". Persisting also means a cold launch shows the last known
    /// reading while the fresh sweep runs, rather than an empty room for a
    /// second — the same reason every other bridge here keeps a snapshot.
    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.cacheKey),
           let saved = try? JSONDecoder().decode([HegotaAccount].self, from: data) {
            accounts = saved
            readAt = UserDefaults.standard.object(forKey: Self.cacheKey + ".at") as? Date
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(accounts) else { return }
        UserDefaults.standard.set(data, forKey: Self.cacheKey)
        UserDefaults.standard.set(readAt, forKey: Self.cacheKey + ".at")
    }

    private static let cacheKey = "hegota.accounts.v1"

    private(set) var accounts: [HegotaAccount] = [] { didSet { persist() } }
    private(set) var loading = false
    /// When the last sweep finished. Nil means none has, which the room says
    /// rather than drawing an empty account as an answer.
    private(set) var readAt: Date?

    private var inFlight = false

    func refresh() async {
        // **THE DEMO REACHES NOTHING.** Not a nicety — a live sweep here reads
        // the demo's EMPTY watch list, sets `accounts` to nothing and wipes the
        // fixture, so the furnished room empties itself the moment it is
        // scrolled into. `BridgeRefresh.refreshAllConnected` already returns
        // early in demo mode, which is why this only became reachable when the
        // room gained a `.task` of its own — the same class as the seeded
        // wallet whose balance a real sweep would overwrite with zero.
        guard !DemoMode.isActive else { return }
        guard !inFlight else { return }
        inFlight = true
        loading = accounts.isEmpty
        defer { inFlight = false; loading = false }

        var out: [HegotaAccount] = []
        for address in HegotaWatch.shared.addresses {
            out.append(await HegotaRead.account(address))
        }
        // **`readAt` FIRST.** `persist()` fires from `accounts`'s `didSet`, so
        // assigning the timestamp afterwards wrote a snapshot whose read date
        // was still nil — and the next launch restored the accounts, saw no
        // date, and drew "Reading the chain…" above a fully populated list.
        readAt = .now
        accounts = out
    }

    /// Read only when there is a reason to.
    ///
    /// The room calls this on appear. A sweep is six requests, so re-running it
    /// every time somebody scrolls back into the room is waste — but NOT
    /// running it at all is worse, and was the reported bug: watching an
    /// address and landing in its room showed nothing, because the only sweep
    /// was the foreground pass that had already happened.
    func refreshIfStale(maxAge: TimeInterval = 120) async {
        // In the demo the "read" is the fixture, and re-installing it is how a
        // relaunched demo gets its room back. Idempotent and in-memory — it
        // reaches nothing, which is the rule this seat inherits.
        if DemoMode.isActive {
            if accounts.isEmpty { HegotaLiveState.seedDemo() }
            return
        }
        if let readAt, Date.now.timeIntervalSince(readAt) < maxAge,
           accounts.count == HegotaWatch.shared.addresses.count { return }
        await refresh()
    }

    func account(_ address: String) -> HegotaAccount? {
        accounts.first { $0.address.caseInsensitiveCompare(address) == .orderedSame }
    }

    func clear() {
        accounts = []
        readAt = nil
        UserDefaults.standard.removeObject(forKey: Self.cacheKey)
        UserDefaults.standard.removeObject(forKey: Self.cacheKey + ".at")
    }

    /// Install a fixture. The one door that writes `accounts` without a read —
    /// used by the demo alone, and `internal` rather than private for exactly
    /// that reason.
    func installDemo(_ fixture: [HegotaAccount]) {
        accounts = fixture
        readAt = .now
    }
}

// MARK: - Bridge registration

enum HegotaBridge {
    /// The seat registers itself off the watch list, so the catalog can never
    /// show a connected seat that reads nothing.
    static func registerBridge(store: BridgeStore) {
        let addresses = HegotaWatch.shared.addresses
        guard !addresses.isEmpty else { store.remove(HegotaIdentity.seatID); return }
        store.registerConnected(
            id: HegotaIdentity.seatID,
            name: HegotaIdentity.source,
            proof: addresses.count == 1
                ? String(localized: "1 address watched")
                : String(localized: "\(addresses.count) addresses watched"),
            can: [
                String(localized: "Reads a watched address's balance, its transfers, the coins it holds in the chain's vault and who paid for its transactions, on Hegotá — a public devnet testing frame transactions."),
                String(localized: "Read-only — this app never signs or sends anything against it."),
            ])
    }

    static func disconnect(store: BridgeStore) {
        HegotaWatch.shared.removeAll()
        // Or the room keeps drawing accounts nobody watches any more — the
        // snapshot outlives the watch list otherwise (vibenet's own lesson).
        Task { @MainActor in HegotaLiveState.shared.clear() }
        store.remove(HegotaIdentity.seatID)
    }
}

// MARK: - Demo

extension HegotaLiveState {
    /// The demo's Hegotá account.
    ///
    /// **A FIXTURE, never a read** — `DemoMode` reaches no network by ruling,
    /// and a live sweep here would answer with an empty account and draw the
    /// seat as a room with nothing in it. It is also why this seat is ROWLESS
    /// in `DemoSeedAll`: it lands no `Thing`, so there is nothing to seed into
    /// the corpus and the whole furnishing is this one account.
    ///
    /// The numbers are the shape of a real address on the chain rather than
    /// round ones: coins that do not divide evenly, a change output smaller
    /// than what went out, and one sponsored move — the reading this seat
    /// exists for, which no address on the live chain has yet.
    /// **`nonisolated`, and the install hops.** `DemoSeedAll.infra()` is a
    /// synchronous nonisolated context, so a `@MainActor` seed cannot be called
    /// from it — the fixture is built out of plain value types off the actor
    /// and only the install crosses. Caught by the build, which is the one
    /// check that can see it.
    nonisolated static func seedDemo() {
        // **EVERY FIGURE BELOW IS REAL**, read off rpc1.hegota.ethrex.xyz on
        // 2026-08-27. Asked why the demo used invented numbers when the chain
        // has real ones, the answer was that it shouldn't — and the real data
        // immediately showed something no invented fixture would have: this
        // address holds coins of 1 and 2 WEI beside coins of 0.005 ETH. That is
        // the UTXO reading in its strongest form (a balance really is unequal
        // pieces, and some of them are dust), and it is what caught
        // `HegotaFormat.eth` rendering a real coin as "0 ETH".
        //
        // TWO accounts, because no single address on this chain has both halves
        // of the room: coin owners and keyed-nonce senders are disjoint
        // populations (measured), so one account would furnish one scope and
        // leave the other permanently empty in the demo.
        let coinsAddr = "0x8b54b45663b4af65d51d7f98c20f533965e0a013"
        let nonceAddr = "0x8943545177806ed17b9f23f0a21ee5948ecaa776"
        let vault = HegotaChain.vault
        let payer = "0x5bf9cea0c445c13bc5b2a5f1a2347f47a9c27a51"
        let peerAddr = "0x2353e650094cdae828ed2a3bc2503de9123be5e1"

        // **THE DEMO'S CLOCK.** The fixture's block numbers are real and its
        // times are derived from them at the chain's real 6-second cadence,
        // anchored so the newest move is now — which keeps the demo FRESH the
        // way `DemoMode.restampIfStale` keeps the seeded corpus fresh, and it
        // has to be done here because this seat lands no `Thing` for that pass
        // to reach. The SPACING is therefore real (those two nonce sends
        // really are a week older than the coin activity); only the anchor
        // moves, which is the same trade every demo in this app makes.
        let tip: UInt64 = 113_128
        func stamp(_ block: UInt64) -> Date {
            Date().addingTimeInterval(-Double(tip &- min(block, tip)) * 6)
        }

        var owner = HegotaAccount(address: coinsAddr)
        owner.reached = true
        owner.balanceWei = Decimal(string: "1128827347981991436")
        owner.reconciled = true
        // The real unspent set, by index. Five are CHANGE coming back to this
        // address and two are dust somebody else sent it.
        // Each coin carries the REAL hash of the transaction that created it,
        // read off the chain — which is what joins a coin to its siblings in
        // the coin sheet and a deposit row to "became N UTXOs".
        let coins = [
            HegotaCoin(index: 5,  wei: Decimal(string: "5936937999558566")!,
                       source: coinsAddr, owner: coinsAddr, block: 96_706,
                       createdBy: "0x577384fda862d9f2b215ce2fd20f20f1bd706df2576f1f99e8159c0b9472bb03"),
            HegotaCoin(index: 21, wei: Decimal(2),
                       source: peerAddr, owner: coinsAddr, block: 101_569,
                       createdBy: "0x3fdc4027f42d8050dd35fe8c9e42e4d556987566a94d5e970ff4e45e2e2c9d29"),
            HegotaCoin(index: 22, wei: Decimal(1),
                       source: peerAddr, owner: coinsAddr, block: 101_580,
                       createdBy: "0xa237a8e7f350fa8996e24873a4aeb7e206248f423f1f293dd73dc797510be9e6"),
            HegotaCoin(index: 33, wei: Decimal(string: "736914005158398")!,
                       source: coinsAddr, owner: coinsAddr, block: 102_662,
                       createdBy: "0x881c56a0626bd3b80ebed50ba78581ae1430a05deaacd8521bba4cbcfcddf661"),
            HegotaCoin(index: 34, wei: Decimal(string: "736926005158482")!,
                       source: coinsAddr, owner: coinsAddr, block: 102_664,
                       createdBy: "0x9efc11e411338e219278cd0906c4330b8d2b811ed3d6a11994658b903d402bdd"),
            HegotaCoin(index: 38, wei: Decimal(string: "4926558999485913")!,
                       source: coinsAddr, owner: coinsAddr, block: 111_106,
                       createdBy: "0x3de0305cde059b95a498f5029806c1eb1cd9fc788baa3c7efbbaf1494d21b3c9"),
            HegotaCoin(index: 45, wei: Decimal(string: "736882005158174")!,
                       source: coinsAddr, owner: coinsAddr, block: 113_128,
                       createdBy: "0x46bd544999bbc3295b774a88e450e33030e27ccc37128e3e2e1b2346e36612ee"),
        ]
        let dated = coins.map { coin -> HegotaCoin in
            var c = coin; c.timestamp = stamp(coin.block); return c
        }
        owner.coins = dated
        owner.unspent = dated

        func move(_ hash: String, _ other: String, _ wei: String,
                  incoming: Bool, block: UInt64) -> HegotaMove {
            var m = HegotaMove(hash: hash, counterparty: other,
                               wei: Decimal(string: wei) ?? 0,
                               incoming: incoming, block: block)
            m.sender = incoming ? other : coinsAddr
            m.payer = m.sender
            m.timestamp = stamp(block)
            return m
        }
        var deposit = move("0x62dceb36abb9", vault, "10000000000000000",
                           incoming: false, block: 111_368)
        deposit.isFrameTransaction = true
        deposit.frames = [
            HegotaFrame(mode: .verify, target: coinsAddr, wei: 0,
                        succeeded: true, gasUsed: 0, stateGasUsed: 0),
            HegotaFrame(mode: .utxo, target: vault,
                        wei: Decimal(string: "10000000000000000")!,
                        succeeded: true, gasUsed: 36_334, stateGasUsed: 0),
        ]
        // The gas this spend really cost, measured on the chain the same day.
        // Only the frame transaction carries one: the receipt read is bounded,
        // so an unstamped fee is the ORDINARY case and the demo shows it
        // rather than filling every row with a plausible number.
        deposit.feeWei = Decimal(string: "59000000000000")
        // **The withdrawals are SPONSORED, and that is measured, not invented.**
        // Every UTXO spend on this chain carries `payer = the vault itself` on
        // its receipt — the fee comes out of the consumed coins rather than
        // the sender's balance — so the Sponsors scope has a real subject and
        // the demo shows the payer mechanism with the chain's own example.
        func vaultSpend(_ hash: String, _ wei: String, block: UInt64,
                        gas: String) -> HegotaMove {
            var m = move(hash, vault, wei, incoming: true, block: block)
            m.isFrameTransaction = true
            m.payer = vault
            m.feeWei = Decimal(string: gas)
            m.frames = [
                HegotaFrame(mode: .utxo, target: nil, wei: 0,
                            succeeded: true, gasUsed: 224_043, stateGasUsed: 0),
            ]
            return m
        }
        owner.moves = [
            deposit,
            vaultSpend("0x9efc11e411338e219278cd0906c4330b8d2b811ed3d6a11994658b903d402bdd",
                       "22199999994400000", block: 102_664, gas: "63074000441518"),
            vaultSpend("0x881c56a0626bd3b80ebed50ba78581ae1430a05deaacd8521bba4cbcfcddf661",
                       "4136925993958482", block: 102_662, gas: "63086000441602"),
            move("0x44f63828fc6f", vault, "10000000000000000", incoming: false, block: 102_265),
            move("0x4d12e06f40d1", vault, "5000000000000000", incoming: true, block: 101_767),
            move("0xdc83ae22490f", payer, "1000000000000000000", incoming: true, block: 87_073),
        ]

        // The keyed-nonce half — the only address on this chain that has sent
        // on two different non-zero keys, and both are names somebody typed.
        var sender = HegotaAccount(address: nonceAddr)
        sender.reached = true
        sender.balanceWei = Decimal(string: "999999898309733516199984155")
        var beef = HegotaMove(hash: "0x530f4989ad", counterparty: peerAddr,
                              wei: Decimal(string: "1000000000000000")!,
                              incoming: false, block: 2_395)
        beef.isFrameTransaction = true
        beef.timestamp = stamp(2_395)
        beef.sender = nonceAddr; beef.payer = nonceAddr
        beef.nonceKeys = ["0xbeef01"]; beef.nonceSeq = "0x0"
        beef.frames = [
            HegotaFrame(mode: .verify, target: nonceAddr, wei: 0,
                        succeeded: true, gasUsed: 0, stateGasUsed: 0),
            HegotaFrame(mode: .sender, target: peerAddr,
                        wei: Decimal(string: "1000000000000000")!,
                        succeeded: true, gasUsed: 0, stateGasUsed: 0),
        ]
        var twelve = beef
        twelve = HegotaMove(hash: "0x57dcf2c36c", counterparty: peerAddr,
                            wei: Decimal(string: "1000000000000000")!,
                            incoming: false, block: 2_375)
        twelve.isFrameTransaction = true
        twelve.timestamp = stamp(2_375)
        twelve.sender = nonceAddr; twelve.payer = nonceAddr
        twelve.nonceKeys = ["0x1234"]; twelve.nonceSeq = "0x0"
        twelve.frames = beef.frames
        sender.moves = [beef, twelve]
        sender.lanes = HegotaRead.lanes(from: sender.moves)

        // The sponsored moves are the vault spends above — measured, not
        // invented: this chain's UTXO withdrawals really do carry the vault as
        // payer, which is the payer mechanism demonstrated by the chain's own
        // example. (An earlier comment here claimed no sponsored move existed;
        // reading the receipts overturned it.)
        let fixture = [owner, sender]
        Task { @MainActor in HegotaLiveState.shared.installDemo(fixture) }
    }

    nonisolated static func forgetDemo() {
        // The watch list is not actor-isolated, so it is cleared right here —
        // synchronously, because `DemoMode.exit` must not leave a demo address
        // behind if the hop below is cancelled.
        HegotaWatch.shared.remove("0x8b54b45663b4af65d51d7f98c20f533965e0a013")
        HegotaWatch.shared.remove("0x8943545177806ed17b9f23f0a21ee5948ecaa776")
        Task { @MainActor in HegotaLiveState.shared.clear() }
    }
}
