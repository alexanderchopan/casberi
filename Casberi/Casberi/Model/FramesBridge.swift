import Foundation

/// THE FRAMES DEVNET (prd §548, 2026-09-01) — chain 81410, the reference
/// devnet for EIP-8141 frame transactions, and the only chain this app reaches
/// where a transaction is a SEQUENCE rather than one opaque outcome.
///
/// ## WHY A SEAT, WHEN THE CHAIN IS NEARLY EMPTY
///
/// Measured 2026-09-01, walking every log on the chain rather than sampling
/// blocks (§500's rule): **25 logs, 20 value-moving transactions, 5 of type
/// `0x06`, 18 distinct addresses, in 56,503 blocks.** Most of the early
/// traffic is genesis fixtures — `0x…dead`, `0x…42`, `deadbe01` — and the
/// recent traffic is faucet drips of exactly 1 ETH.
///
/// That is a real census, not a sampling artefact. It is also a census of a
/// chain that **opened on 2026-08-28**, four days before it was taken, so it
/// is a floor rather than a verdict. Hegotá earned its seat on volume (254
/// transactions, 164 addresses); this one cannot, and does not try to. It
/// earns one on the faucet's own sentence:
///
/// > "EIP-8141 is a draft, so no wallet and no released version of the common
/// > libraries can encode or sign one; a wallet asked to send one simply has
/// > no representation for it."
///
/// `FramesTransaction` is that representation, proven against every
/// transaction on the chain. **The subject of this seat is the transaction
/// type, not the chain's population** (user, 2026-09-01: *"this one is for
/// Frames specifically"*).
///
/// ## WHAT IT PUBLISHES THAT ORDINARY CHAINS HIDE
///
/// The same three §500 named for Hegotá, all three confirmed here:
/// every ETH movement is an EIP-7708 log at `0x…fe`, so a balance line is
/// EXACT rather than sampled; every receipt names its `payer`, so gas
/// sponsorship is a visible fact; and every transaction decomposes into
/// `frameReceipts` with per-frame status, so a row can say what a transaction
/// DID. It is the purer testbed of the two — "that is the only addition.
/// Everything else is Amsterdam, so a failure here is a frame-transaction
/// failure."
///
/// ## AND TWO THINGS IT DOES NOT PUBLISH
///
/// **No keyed nonces.** EIP-8250's `nonceKeys`/`nonceSeq` appear on no
/// transaction here, so Hegotá's Nonces scope has nothing to read and this
/// seat does not offer one. That is a property of the chain, not a choice.
/// **No `recentRootReferences`.** Both absences are pinned by the harness, so
/// a future chain upgrade that adds them shows up as a failing guard rather
/// than as a scope nobody thought to build.
enum FramesIdentity {
    /// **"Frames Devnet", not "Frames".** The bare word is one of the most
    /// ordinary nouns in this app's own vocabulary — `FeedScreen` frames, a
    /// video frame, the `frames` array inside every transaction here — and a
    /// catalog seat, a `Thing.source` and a §308 facet all share one namespace
    /// with search. `BridgeIcon` folds it to `brand-frames-devnet`.
    static let source = "Frames Devnet"
    static let seatID = "frames"

    /// The block explorer and the faucet's own page — opened in the person's
    /// OWN browser on a tap, never reached by us for a page. They are in the
    /// reach audit's non-reach denylist for exactly that reason; the faucet's
    /// `/api/claim` endpoint IS reached and is declared in `NetworkReach`.
    static let explorer = "https://dora.frames.ethrex.xyz"
    static let faucet = "https://faucet.frames.ethrex.xyz"
}

// MARK: - RPC (keyless)

enum FramesRPC {
    /// **Three hosts, tried in order.** Measured 2026-09-01: all three answer
    /// `eth_chainId` with `0x13e02`, so a host being down is a retry rather
    /// than an outage.
    static let hosts = [
        "https://rpc1.frames.ethrex.xyz",
        "https://rpc2.frames.ethrex.xyz",
        "https://rpc3.frames.ethrex.xyz",
    ]

    /// One JSON-RPC call, walking the hosts until one answers.
    ///
    /// Returns nil when NO host answered, which callers must keep distinct
    /// from a host answering with nothing: an unreached read is not evidence
    /// of an empty account, and the room says "couldn't reach the chain"
    /// rather than drawing a zero (§515a).
    static func call(method: String, params: [Any]) async -> Any? {
        let body: [String: Any] = ["id": 1, "jsonrpc": "2.0", "method": method, "params": params]
        for host in hosts {
            guard let root = await IngestSupport.postJSON(host, body: body,
                                                          service: FramesIdentity.source)
                    as? [String: Any] else { continue }
            if let result = root["result"], !(result is NSNull) { return result }
            // A host that ANSWERED with an error has answered — walking on
            // would ask two more hosts the same malformed question and report
            // "unreachable" for what is really our own bad request.
            if root["error"] != nil { return nil }
        }
        return nil
    }

    /// A batch of calls in ONE request.
    ///
    /// Results are matched by the `id` each call was sent with, NEVER by array
    /// position — JSON-RPC permits a server to answer a batch in any order,
    /// and a positional read silently attributes one transaction's frames to
    /// another transaction.
    static func batch(_ calls: [(method: String, params: [Any])]) async -> [Int: Any]? {
        guard !calls.isEmpty else { return [:] }
        let body: [[String: Any]] = calls.enumerated().map { i, c in
            ["id": i, "jsonrpc": "2.0", "method": c.method, "params": c.params]
        }
        for host in hosts {
            guard let rows = await IngestSupport.postJSONArray(host, body: body,
                                                               service: FramesIdentity.source)
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
}

// MARK: - The watch list

/// The addresses being watched, as a plain UserDefaults list rather than a
/// `Thing` per address — `HegotaWatch`/`VibenetWatch`'s shape, and for their
/// reason: a devnet address has no product page, no news to arrive under it
/// and nothing to search for.
@Observable
final class FramesWatch {
    static let shared = FramesWatch()
    private static let key = "frames.watch.addresses.v1"

    private var addressList: [String] { didSet { persist() } }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([String].self, from: data) {
            addressList = saved
        } else {
            addressList = []
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(addressList) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
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
                         networks: [AddressBook.Network.frames])
        } else {
            book.addNetwork(AddressBook.Network.frames, for: address)
        }
        return true
    }

    func remove(_ address: String) {
        addressList.removeAll { $0.caseInsensitiveCompare(address) == .orderedSame }
    }

    func removeAll() { addressList = [] }

    func name(for address: String) -> String? { AddressBook.shared.name(for: address) }
}

// MARK: - Bridge registration

enum FramesBridge {
    /// The seat registers itself off the watch list AND off this phone's key,
    /// which is the divergence from Hegotá worth knowing: **on this chain the
    /// account you MAKE is the common case**, because the chain is days old
    /// and there is almost nothing to watch. Registering on the watch list
    /// alone would leave somebody who created an account and claimed from the
    /// faucet looking at a seat that says it is not connected.
    static func registerBridge(store: BridgeStore) {
        let addresses = FramesWatch.shared.addresses
        let hasKey = FramesKey.address() != nil
        guard !addresses.isEmpty || hasKey else { store.remove(FramesIdentity.seatID); return }

        let proof: String = {
            if addresses.isEmpty { return String(localized: "An account on this phone") }
            if hasKey {
                return addresses.count == 1
                    ? String(localized: "Your account and 1 address watched")
                    : String(localized: "Your account and \(addresses.count) addresses watched")
            }
            return addresses.count == 1
                ? String(localized: "1 address watched")
                : String(localized: "\(addresses.count) addresses watched")
        }()

        store.registerConnected(
            id: FramesIdentity.seatID,
            name: FramesIdentity.source,
            proof: proof,
            can: [
                String(localized: "Reads a watched address's balance and its frame transactions — what each frame did, what it spent of its gas budget, and who paid for it — on the Frames devnet, the public test network for EIP-8141 frame transactions."),
                String(localized: "Reading needs no key. Sending signs with a key held on this device — a plain scalar, not the Secure Enclave, because the money here has no value and the network says it may be reset without notice."),
            ])
    }

    static func disconnect(store: BridgeStore) {
        FramesWatch.shared.removeAll()
        store.remove(FramesIdentity.seatID)
    }
}

// MARK: - The live read

/// A transaction this phone broadcast and has not yet seen on chain.
///
/// Its own type rather than a bare hash so a row can say something true about
/// it — how many legs were sent — without going back to the chain for a
/// transaction the chain has not got yet.
struct FramesPending: Identifiable, Equatable {
    var hash: String
    var legs: Int
    var at: Date = .now
    var id: String { hash }
}

@MainActor
@Observable
final class FramesLiveState {
    static let shared = FramesLiveState()
    private init() {
        // Restored BEFORE any read, so the room draws what it last knew rather
        // than a blank. `try?` with an empty fallback: a cache that cannot be
        // decoded is a cache that is not there, never a crash on launch.
        if let data = UserDefaults.standard.data(forKey: Self.cacheKey),
           let saved = try? JSONDecoder().decode([FramesAccount].self, from: data) {
            accounts = saved
            reached = !saved.isEmpty
        }
        if let at = UserDefaults.standard.object(forKey: Self.readAtKey) as? Date {
            readAt = at
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(accounts) else { return }
        UserDefaults.standard.set(data, forKey: Self.cacheKey)
        UserDefaults.standard.set(readAt, forKey: Self.readAtKey)
    }

    private(set) var accounts: [FramesAccount] = []
    private(set) var readAt: Date?

    /// **THE LAST READ SURVIVES A LAUNCH** (`HegotaLiveState`'s cache, and it
    /// was missing here). Two things were broken without it, one of them
    /// invisible until a simulator showed it.
    ///
    /// The demo installs its fixture in MEMORY on entry, so a relaunch found
    /// an empty room and drew "Reading the chain…" forever — a sentence that
    /// is not merely unhelpful in a demo but false, since `refresh` returns
    /// early there and the read will never come. And the live room went blank
    /// on every cold launch until the sweep returned, which on a slow network
    /// is seconds of a room saying it knows nothing about an account it knew
    /// about a moment ago.
    private static let cacheKey = "frames.live.accounts.v1"
    private static let readAtKey = "frames.live.readAt.v1"
    /// A host answered SOMETHING. Kept apart from "the accounts are empty",
    /// because an unreached read is not evidence of an empty account and the
    /// room must say "couldn't reach the chain" rather than draw a zero.
    private(set) var reached = false

    /// **WHAT THIS PHONE JUST SENT AND HAS NOT YET SEEN LAND.**
    ///
    /// `sendStitched` returns the moment the node ACCEPTS the bytes, which is
    /// before any block carries them — so the sheet dismissed onto a room that
    /// still showed the world as it was, and the transaction appeared whenever
    /// the next sweep happened to run. From outside, a send that worked and a
    /// send that vanished look identical for as long as that takes.
    ///
    /// **In memory only, deliberately.** It is not persisted with the accounts
    /// because a hash that is pending is pending for seconds; surviving a
    /// launch would mean a row saying "Sending…" about a transaction that
    /// settled while the app was closed, which is worse than not showing it at
    /// all. A relaunch simply reads the chain, which is the authority.
    private(set) var pending: [FramesPending] = []

    /// Record a broadcast. Called by the send path, never by a read.
    func notePending(hash: String, legs: Int) {
        guard !pending.contains(where: { $0.hash.lowercased() == hash.lowercased() }) else { return }
        pending.append(FramesPending(hash: hash, legs: legs))
    }

    /// Drop anything the chain has now told us about, and anything old enough
    /// that we are no longer entitled to claim it is in flight.
    ///
    /// **A stuck transaction stops being narrated rather than being called
    /// failed.** We cannot tell "still queued" from "dropped by the node" from
    /// here, and a row asserting either would be a claim this app cannot
    /// support (§83) — going quiet says only what is true, which is that we
    /// stopped being able to say.
    private func reconcilePending(against accounts: [FramesAccount]) {
        let landed = Set(accounts.flatMap(\.moves).map { $0.hash.lowercased() })
        let cutoff = Date().addingTimeInterval(-Self.pendingWindow)
        pending.removeAll { landed.contains($0.hash.lowercased()) || $0.at < cutoff }
    }

    /// Two minutes. Blocks here land in seconds, so this is a ceiling on how
    /// long a claim may stand unverified, not an expectation.
    private static let pendingWindow: TimeInterval = 120

    /// How many of an address's newest transactions get their frames read.
    /// A bound on REQUESTS, not on what a person can see.
    private static let moveDepth = 12

    func clear() {
        accounts = []
        readAt = nil
        reached = false
        UserDefaults.standard.removeObject(forKey: Self.cacheKey)
        UserDefaults.standard.removeObject(forKey: Self.readAtKey)
    }

    /// The demo's door. `DemoMode` reaches no network, so this is the only way
    /// accounts exist there — and it must never be reachable from a real
    /// sweep, or a fixture would overwrite a live read.
    func installDemo(_ fixture: [FramesAccount]) {
        accounts = fixture
        readAt = .now
        reached = true
        // Persisted like a real read, so the demo survives the relaunch it is
        // usually seen across. `DemoMode.exit` clears it by name.
        persist()
    }

    /// Read every watched address, plus this phone's own account.
    ///
    /// **This phone's account is included whether or not it is "watched"**,
    /// which is the divergence from Hegotá worth knowing: on a chain this
    /// young the account you made is usually the only interesting one, and
    /// making somebody watch their own address to see it is a step with no
    /// meaning.
    func refresh() async {
        guard !DemoMode.isActive else { return }

        var wanted = FramesWatch.shared.addresses
        if let mine = FramesKey.address(),
           !wanted.contains(where: { $0.caseInsensitiveCompare(mine) == .orderedSame }) {
            wanted.insert(mine, at: 0)
        }
        guard !wanted.isEmpty else { clear(); return }

        var read: [FramesAccount] = []
        var anyAnswered = false
        for address in wanted {
            async let balCall = FramesRPC.call(method: "eth_getBalance", params: [address, "latest"])
            async let nonceCall = FramesRPC.call(method: "eth_getTransactionCount", params: [address, "latest"])
            let (rawBal, rawNonce) = await (balCall, nonceCall)
            if rawBal != nil || rawNonce != nil { anyAnswered = true }
            let moves = await self.moves(for: address)
            read.append(FramesAccount(address: address,
                                      balanceWeiHex: rawBal as? String,
                                      nonce: FramesRead.hexInt(rawNonce),
                                      moves: moves))
        }
        // A pass where NOTHING answered leaves the last good read standing
        // rather than blanking the room — §515a's rule.
        guard anyAnswered else { reached = false; return }
        reconcilePending(against: read)
        accounts = read
        readAt = .now
        reached = true
        persist()
    }

    /// Movement minus the fee, and **the fee only when this address paid it**.
    ///
    /// The `payer` is the receipt's own field, never `from`: on this chain
    /// somebody else can pay, and charging a sponsored transaction's gas to
    /// the sender is a curve that drifts downward for money it never spent.
    /// Nil when the receipt did not read — not knowing is not zero (§515a).
    private static func delta(moved: Decimal?, receipt: [String: Any]?, address: String) -> Decimal? {
        guard let moved, let receipt else { return moved }
        guard let gas = FramesRead.hexInt(receipt["gasUsed"]),
              let price = FramesRead.hexInt(receipt["effectiveGasPrice"]) else { return moved }
        let payer = (receipt["payer"] as? String)?.lowercased()
        guard payer == address.lowercased() else { return moved }
        return moved - Decimal(gas) * Decimal(price)
    }

    /// The transactions that moved this address's ETH, newest first.
    ///
    /// **Read off the EIP-7708 transfer logs, which is the whole reason this
    /// chain earns a seat**: every ETH movement is a log at `0x…fe`, so an
    /// address's history is two filtered `eth_getLogs` calls rather than a
    /// walk over every block — and no indexer exists for this chain, so there
    /// is no other way to get it.
    private func moves(for address: String) async -> [FramesMove] {
        let padded = "0x000000000000000000000000" + address.lowercased()
            .replacingOccurrences(of: "0x", with: "")
        let transferTopic = "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"
        let logAddress = "0xfffffffffffffffffffffffffffffffffffffffe"

        // Two reads: sent (topic 1) and received (topic 2). A single read with
        // both positions is not expressible — a topic filter is positional.
        async let outCall = FramesRPC.call(method: "eth_getLogs", params: [[
            "fromBlock": "0x0", "toBlock": "latest", "address": logAddress,
            "topics": [transferTopic, padded],
        ]])
        async let inCall = FramesRPC.call(method: "eth_getLogs", params: [[
            "fromBlock": "0x0", "toBlock": "latest", "address": logAddress,
            "topics": [transferTopic, NSNull(), padded],
        ]])
        let (rawOut, rawIn) = await (outCall, inCall)

        var byHash: [String: UInt64] = [:]
        // Signed movement per transaction, accumulated from the two filtered
        // reads: an OUT log leaves, an IN log arrives. The fee is added below,
        // where the receipt says who paid it.
        var moved: [String: Decimal] = [:]
        for (side, sign) in [(rawOut, Decimal(-1)), (rawIn, Decimal(1))] {
            for log in (side as? [[String: Any]]) ?? [] {
                guard let hash = log["transactionHash"] as? String else { continue }
                byHash[hash] = FramesRead.hexInt(log["blockNumber"]) ?? 0
                if let amount = (log["data"] as? String).flatMap(FramesMoney.decimal(fromHex:)) {
                    moved[hash, default: 0] += sign * amount
                }
            }
        }
        let newest = byHash.sorted { $0.value > $1.value }.prefix(Self.moveDepth)
        guard !newest.isEmpty else { return [] }

        var out: [FramesMove] = []
        for (hash, block) in newest {
            async let txCall = FramesRPC.call(method: "eth_getTransactionByHash", params: [hash])
            async let rcCall = FramesRPC.call(method: "eth_getTransactionReceipt", params: [hash])
            let (rawTx, rawRc) = await (txCall, rcCall)
            guard let tx = rawTx as? [String: Any] else { continue }
            let receipt = rawRc as? [String: Any]
            let frames = FramesRead.frames(inTransaction: tx)
            let outcomes = receipt.map { FramesRead.outcomes(inReceipt: $0) } ?? []
            let from = (tx["sender"] as? String) ?? (tx["from"] as? String) ?? ""
            out.append(FramesMove(
                hash: hash,
                blockNumber: block,
                sender: from,
                // The payer is the RECEIPT's, never guessed from the sender —
                // that field is the sponsorship reading.
                payer: (receipt?["payer"] as? String) ?? from,
                succeeded: (receipt?["status"] as? String) == "0x1",
                gasUsed: FramesRead.hexInt(receipt?["gasUsed"]),
                // The other half of the fee. Already read one function over
                // for the balance curve; kept on the move so a row can state
                // what the transaction cost in money rather than in a unit
                // nobody holds.
                effectiveGasPriceWei: FramesRead.hexInt(receipt?["effectiveGasPrice"]),
                rows: frames.enumerated().map { i, f in
                    FramesFrameRow(frame: f, outcome: i < outcomes.count ? outcomes[i] : nil)
                },
                deltaWei: Self.delta(moved: moved[hash], receipt: receipt, address: address)))
        }
        return out.sorted { $0.blockNumber > $1.blockNumber }
    }
}

// MARK: - The demo

extension FramesLiveState {
    /// **EVERY FIGURE BELOW IS REAL**, read off rpc1.frames.ethrex.xyz on
    /// 2026-09-01 (`HegotaLiveState.seedDemo`'s rule, and it earned itself the
    /// same way here). Asked for a fixture, the honest answer is the chain's
    /// own numbers — and they immediately showed two things no invented
    /// fixture would have.
    ///
    /// **One: the balance overflows the obvious type.** This address holds
    /// 99,999.999762 ETH, a genesis-funded dev account, which as wei does not
    /// fit a `UInt64` — the reason `FramesMoney` exists and the reason
    /// `balanceWeiHex` is a string.
    ///
    /// **Two: the frames' gas does not add up to the transaction's.** 100 and
    /// 3,000 against a receipt of 210,790. A fixture with tidy numbers would
    /// have let a room ship that adds its frames up and calls the total the
    /// cost.
    ///
    /// `stateGasUsed` is nil on both frames because **this chain does not
    /// report it** — measured on a transaction sent to a freshly generated
    /// address, which grows state, so this is the field's absence rather than
    /// a fixture's omission. A demo that filled it in would show a bar the
    /// real room can never draw.
    nonisolated static func seedDemo() {
        let me   = "0x1647a6abaf35cacf94dc450f8474d15b524b7d5f"
        let peer = "0x80cfe5da326d0ab7a1d2ffc61745c57885dc2e32"
        let dead = "0x00000000000000000000000000000000deadbe02"
        let eth  = Decimal(string: "1000000000000000000")!

        func frame(_ mode: UInt64, _ flags: UInt64, to: String, value: String) -> FramesRead.Frame {
            .init(mode: mode, flags: flags, target: to, executionGas: 100_000,
                  stateGas: 250_000, value: value, data: "0x")
        }
        func outcome(_ ok: Bool, _ used: UInt64, logs: Int) -> FramesRead.FrameOutcome {
            .init(succeeded: ok, gasUsed: used, stateGasUsed: nil, logCount: logs)
        }

        // 1. THE FAUCET. An ordinary type-0x2 transfer — no frames — which is
        //    how every account on this chain actually begins.
        let funded = FramesMove(
            hash: "0x46619c8ef349691b6c647e742436816d1c282c6b7479d36e72ed5894ee9320e4",
            blockNumber: 59_100, sender: "0xf0667e65e0e5281a39d95d84770b6e2065740466",
            payer: "0xf0667e65e0e5281a39d95d84770b6e2065740466",
            succeeded: true, gasUsed: 21_000, rows: [], deltaWei: eth)

        // 2. A FRAME TRANSACTION — verify, then send. Lights the Frames scope.
        let sent = FramesMove(
            hash: "0x9d12f7722ab15d93ff377f19f923458cae8d6009b0a2b11eb2cd1ca006748674",
            blockNumber: 59_180, sender: me, payer: me, succeeded: true, gasUsed: 210_790,
            // MEASURED: the 0.001 send cost 1,210,790,000,000,000 wei against a
            // 210,790 gas receipt, so this chain quoted exactly 1 gwei.
            effectiveGasPriceWei: 1_000_000_000,
            rows: [
                .init(frame: frame(1, 0x03, to: me,   value: "0x0"), outcome: outcome(true, 100, logs: 0)),
                .init(frame: frame(2, 0x00, to: dead, value: "0x38d7ea4c68000"), outcome: outcome(true, 3_000, logs: 1)),
            ],
            deltaWei: -(Decimal(string: "1210790000000000")!))

        // 3. **A TRANSACTION THAT FAILED AND MOVED MONEY ANYWAY.** Not
        //    invented: this is the shape measured on chain (§548's second
        //    follow-up) — frames are not atomic by default, so an earlier
        //    frame's transfer persists under a `status: 0x0`. It is the whole
        //    reason this room draws frames rather than outcomes, and a demo
        //    that never shows it teaches the opposite.
        let partial = FramesMove(
            hash: "0x9bb9cfef1c41c97b101ce20e934e13f3a7e3d5662c2e0352b26b9998f9f8c58d",
            blockNumber: 59_240, sender: me, payer: me, succeeded: false, gasUsed: 316_273, effectiveGasPriceWei: 1_000_000_000,
            rows: [
                .init(frame: frame(1, 0x03, to: me,   value: "0x0"), outcome: outcome(true, 100, logs: 0)),
                .init(frame: frame(2, 0x00, to: dead, value: "0x38d7ea4c68000"), outcome: outcome(true, 3_000, logs: 1)),
                .init(frame: frame(2, 0x00, to: peer, value: "0x38d7ea4c68000"), outcome: outcome(false, 100_000, logs: 0)),
            ],
            deltaWei: -(Decimal(string: "1316273000000000")!))

        // 4. **A ROLLED-BACK BATCH.** The frame reports `status: 0x1` and
        //    emitted no log, because the batch it was in reverted — the trap
        //    that makes `valueLanded` read effects rather than status.
        let rolled = FramesMove(
            hash: "0x2642331b604d901b59d8f3d6ff5dea314c57ab090d2bf661bbc287b79fefeb63",
            blockNumber: 59_300, sender: me, payer: me, succeeded: false, gasUsed: 240_100, effectiveGasPriceWei: 1_000_000_000,
            rows: [
                .init(frame: frame(1, 0x03, to: me,   value: "0x0"), outcome: outcome(true, 100, logs: 0)),
                .init(frame: frame(2, 0x04, to: peer, value: "0x38d7ea4c68000"), outcome: outcome(true, 3_000, logs: 0)),
                .init(frame: frame(2, 0x00, to: dead, value: "0x38d7ea4c68000"), outcome: outcome(false, 100_000, logs: 0)),
            ],
            deltaWei: -(Decimal(string: "240100000000000")!))

        // 4b. **A THREE-LEG STITCH THAT WORKED** — the capability this chain
        //     exists for, and the shape the send now builds (prd §548 sixth
        //     follow-up). Every number below is MEASURED off the transaction
        //     this app really sent: 595,948 gas at 1,000,000,007 wei, three
        //     legs of 0.001 / 0.002 / 0.003 to three addresses that did not
        //     exist before it.
        //
        //     It earns its place because it is the only fixture where the
        //     strip's cells have DIFFERENT widths — value-sized, so a batch
        //     reads as ascending — and the only one where a row says
        //     "3 addresses". A demo that only ever shows two-frame
        //     transactions teaches that this chain does two-frame
        //     transactions.
        let stitched = FramesMove(
            hash: "0x31e7311acfbc2280df90c46b009eba7f4d45fa698a42de0e86a8eb1771bb72d8",
            blockNumber: 60_258, sender: me, payer: me, succeeded: true,
            gasUsed: 595_948, effectiveGasPriceWei: 1_000_000_007,
            rows: [
                .init(frame: frame(1, 0x03, to: me,   value: "0x0"), outcome: outcome(true, 100, logs: 0)),
                .init(frame: frame(2, 0x00, to: dead, value: "0x38d7ea4c68000"), outcome: outcome(true, 3_000, logs: 1)),
                .init(frame: frame(2, 0x00, to: peer, value: "0x71afd498d0000"), outcome: outcome(true, 3_000, logs: 1)),
                .init(frame: frame(2, 0x00, to: "0xc3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3",
                                   value: "0xaa87bee538000"), outcome: outcome(true, 3_000, logs: 1)),
            ],
            // 0.006 out plus the measured fee, to the wei.
            deltaWei: -(Decimal(string: "6595948004171636")!))

        // 5. **SOMEBODY ELSE PAID.** `payer` differs from `sender`, which
        //    lights the Sponsors scope — the reading this chain publishes that
        //    ordinary chains hide. No transaction on the real chain has been
        //    sponsored yet, so this is the one shape here the chain has not
        //    itself produced; it is the scope's only way to be seen.
        let sponsored = FramesMove(
            hash: "0x5b131baf9e0b9635a0fd58a6410f50e66c6450736999cace47826982de1cf026",
            blockNumber: 59_340, sender: me, payer: peer, succeeded: true, gasUsed: 402_873, effectiveGasPriceWei: 1_000_000_000,
            rows: [
                .init(frame: frame(1, 0x03, to: me,   value: "0x0"), outcome: outcome(true, 100, logs: 0)),
                .init(frame: frame(2, 0x00, to: dead, value: "0x38d7ea4c68000"), outcome: outcome(true, 3_000, logs: 1)),
            ],
            // The fee is NOT subtracted: somebody else paid it. That is the
            // whole point of the scope, and of `delta`'s payer check.
            deltaWei: -(Decimal(string: "1000000000000000")!))

        let fixture = [FramesAccount(
            address: me,
            balanceWeiHex: "0xd7cf8d9b06f5b8",
            nonce: 4,
            moves: [sponsored, stitched, rolled, partial, sent, funded])]
        Task { @MainActor in FramesLiveState.shared.installDemo(fixture) }
    }

    /// Undone BY NAME, never a blanket wipe — a dev install may hold a real
    /// watch list and a real key under the same seat.
    nonisolated static func teardownDemo() {
        Task { @MainActor in FramesLiveState.shared.clear() }
    }
}
