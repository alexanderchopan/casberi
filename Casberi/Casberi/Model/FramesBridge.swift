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

// MARK: - Reading a frame transaction back

/// THE READ SIDE, and the trap that makes it a separate type from Hegotá's.
///
/// **A frame's execution budget is reported as `gasLimit` here and
/// `executionGasLimit` on Hegotá.** A reader written for one gets `nil` on the
/// other, and a frame drawn with a nil budget is a frame that looks like it
/// had none — the two-bar figure's whole subject, wrong, silently. Both
/// spellings are read here with this chain's own first, so a reader pointed at
/// the wrong chain degrades to correct rather than to empty.
enum FramesRead {

    /// One frame as the RPC reports it.
    struct Frame: Equatable {
        var mode: UInt64
        var flags: UInt64
        var target: String?
        var executionGas: UInt64?
        var stateGas: UInt64?
        var value: String?
        var data: String?

        /// `0` DEFAULT, `1` VERIFY, `2` SENDER. Named rather than numbered
        /// wherever a person sees it: "mode 2" says nothing and "Sender" says
        /// what ran.
        var modeName: String {
            switch mode {
            case 0: String(localized: "Default")
            case 1: String(localized: "Verify")
            case 2: String(localized: "Sender")
            default: String(localized: "Mode \(String(mode))")
            }
        }

        /// Bits 0 and 1 are the `APPROVE` scope — execution and payment. A
        /// VERIFY frame without them leaves the transaction with no payer.
        var approvesExecution: Bool { flags & 0x1 != 0 }
        var approvesPayment: Bool { flags & 0x2 != 0 }
        /// Bit 2 marks an atomic batch, terminated by a following non-batch
        /// frame.
        var startsBatch: Bool { flags & 0x4 != 0 }
    }

    /// One frame's outcome.
    struct FrameOutcome: Equatable {
        var succeeded: Bool
        var gasUsed: UInt64?
        /// **OPTIONAL, AND NEVER DEFAULTED TO ZERO.** Measured 2026-09-01:
        /// absent from all 5 transactions on this chain (10 frames), while
        /// Hegotá's receipts carry it. All five are plain transfers that grow
        /// no state, so this is not proof the field does not exist — the
        /// faucet's own error guide tells implementers to "check
        /// `stateGasUsed` on the receipt", which means it is meant to be
        /// there.
        ///
        /// Nil means **the chain did not say**, which is a different fact from
        /// zero and is the whole point: `0x0` is the discriminator that tells
        /// a missing STATE budget apart from a too-small EXECUTION budget, and
        /// reading an absent field as zero would assert that diagnosis every
        /// time. A figure draws the state bar only when this is non-nil.
        var stateGasUsed: UInt64?
        var logCount: Int
    }

    static func hexInt(_ any: Any?) -> UInt64? {
        guard let s = any as? String else { return nil }
        let body = s.hasPrefix("0x") ? String(s.dropFirst(2)) : s
        guard !body.isEmpty else { return nil }
        return UInt64(body, radix: 16)
    }

    /// Frames off an `eth_getTransactionByHash` result.
    static func frames(inTransaction tx: [String: Any]) -> [Frame] {
        guard let raw = tx["frames"] as? [[String: Any]] else { return [] }
        return raw.map { f in
            Frame(mode: hexInt(f["mode"]) ?? 0,
                  flags: hexInt(f["flags"]) ?? 0,
                  target: f["to"] as? String,
                  // This chain's spelling FIRST; Hegotá's accepted so a reader
                  // pointed at the wrong chain is wrong-but-drawn rather than
                  // silently empty.
                  executionGas: hexInt(f["gasLimit"]) ?? hexInt(f["executionGasLimit"]),
                  stateGas: hexInt(f["stateGasLimit"]),
                  value: f["value"] as? String,
                  data: f["data"] as? String)
        }
    }

    /// Outcomes off an `eth_getTransactionReceipt` result.
    static func outcomes(inReceipt receipt: [String: Any]) -> [FrameOutcome] {
        guard let raw = receipt["frameReceipts"] as? [[String: Any]] else { return [] }
        return raw.map { r in
            FrameOutcome(succeeded: (r["status"] as? String) == "0x1",
                         gasUsed: hexInt(r["gasUsed"]),
                         stateGasUsed: hexInt(r["stateGasUsed"]),
                         logCount: (r["logs"] as? [[String: Any]])?.count ?? 0)
        }
    }

    /// **WHY A FRAME FAILED, when the chain can tell us.**
    ///
    /// The faucet's own error guide: *"A frame reverts having used exactly its
    /// `execution` budget, with `stateGasUsed: 0x0` — missing state budget,
    /// not execution. Raising `--frame-gas-limit` will not help."* Two
    /// failures that render identically, and the chain publishes the
    /// discriminator.
    ///
    /// Returns nil when the frame succeeded, or when the reading cannot be
    /// made — an absent `stateGasUsed` is **not** evidence of a state
    /// starvation, and saying so would send somebody to raise a budget that
    /// was never the problem (§83, on the one line a developer would act on).
    enum Starvation: Equatable { case state, execution }

    static func starvation(frame: Frame, outcome: FrameOutcome) -> Starvation? {
        guard !outcome.succeeded else { return nil }
        guard let used = outcome.gasUsed, let budget = frame.executionGas,
              used == budget else { return nil }
        // Only a REPORTED zero is evidence. Nil is "the chain did not say".
        guard let state = outcome.stateGasUsed else { return nil }
        return state == 0 ? .state : .execution
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

// MARK: - What a frame transaction looks like once it has been read

/// One frame paired with what it DID. Two arrays on the wire — `frames` on the
/// transaction, `frameReceipts` on the receipt — and they are zipped exactly
/// once, here, so no view can pair them differently.
struct FramesFrameRow: Equatable {
    var frame: FramesRead.Frame
    var outcome: FramesRead.FrameOutcome?
}

/// A frame transaction, read back.
struct FramesMove: Identifiable, Equatable {
    var hash: String
    var blockNumber: UInt64
    var sender: String
    var payer: String
    var succeeded: Bool
    /// **THE TRANSACTION'S OWN, NEVER THE SUM OF ITS FRAMES.** Measured
    /// 2026-09-01 on a transaction this app sent: the two frames report 100
    /// and 3,000 gas, and the receipt reports **210,790**. Adding the frames
    /// up and presenting the total as what the transaction cost is wrong by
    /// two orders of magnitude, and wrong in the direction that looks
    /// plausible.
    var gasUsed: UInt64?
    var rows: [FramesFrameRow]

    var id: String { hash }

    /// Somebody else paid. The one reading this chain publishes that ordinary
    /// chains hide — and it is a comparison of two fields on the SAME receipt,
    /// never an inference.
    var sponsored: Bool { payer.lowercased() != sender.lowercased() }

    /// Did every frame succeed? A transaction can report `status: 0x1` while a
    /// frame inside it reverted, which is the whole reason this room draws
    /// frames rather than outcomes.
    var everyFrameSucceeded: Bool {
        rows.allSatisfy { $0.outcome?.succeeded ?? true }
    }
}

/// One address, as the chain currently reports it.
struct FramesAccount: Identifiable, Equatable {
    var address: String
    /// **RAW HEX, not a number.** A genesis account on this chain holds
    /// 99,999.999762 ETH, which overflows `UInt64` when expressed in wei —
    /// see `FramesMoney`. Stored as the chain said it so nothing downstream
    /// can narrow it.
    var balanceWeiHex: String?
    var nonce: UInt64?
    var moves: [FramesMove]

    var id: String { address.lowercased() }
}

// MARK: - The live read

@MainActor
@Observable
final class FramesLiveState {
    static let shared = FramesLiveState()
    private init() {}

    private(set) var accounts: [FramesAccount] = []
    private(set) var readAt: Date?
    /// A host answered SOMETHING. Kept apart from "the accounts are empty",
    /// because an unreached read is not evidence of an empty account and the
    /// room must say "couldn't reach the chain" rather than draw a zero.
    private(set) var reached = false

    /// How many of an address's newest transactions get their frames read.
    /// A bound on REQUESTS, not on what a person can see.
    private static let moveDepth = 12

    func clear() {
        accounts = []
        readAt = nil
        reached = false
    }

    /// The demo's door. `DemoMode` reaches no network, so this is the only way
    /// accounts exist there — and it must never be reachable from a real
    /// sweep, or a fixture would overwrite a live read.
    func installDemo(_ fixture: [FramesAccount]) {
        accounts = fixture
        readAt = .now
        reached = true
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
        accounts = read
        readAt = .now
        reached = true
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
        for side in [rawOut, rawIn] {
            for log in (side as? [[String: Any]]) ?? [] {
                guard let hash = log["transactionHash"] as? String else { continue }
                byHash[hash] = FramesRead.hexInt(log["blockNumber"]) ?? 0
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
                rows: frames.enumerated().map { i, f in
                    FramesFrameRow(frame: f, outcome: i < outcomes.count ? outcomes[i] : nil)
                }))
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
        let sender = "0x80cfe5da326d0ab7a1d2ffc61745c57885dc2e32"
        let move = FramesMove(
            hash: "0x70c8c2b7c44ff8f046e1ebb7c925a80724aaad7f65f85d82e97c724cdbfc9bc6",
            blockNumber: 582,
            sender: sender,
            // Self-paid, which is what every transaction on this chain is so
            // far. A sponsored fixture would show a reading the chain has
            // never actually produced.
            payer: sender,
            succeeded: true,
            gasUsed: 210_790,
            rows: [
                FramesFrameRow(
                    frame: .init(mode: 1, flags: 0x03, target: sender,
                                 executionGas: 100_000, stateGas: 250_000,
                                 value: "0x0", data: "0x"),
                    outcome: .init(succeeded: true, gasUsed: 100, stateGasUsed: nil, logCount: 0)),
                FramesFrameRow(
                    frame: .init(mode: 2, flags: 0x00,
                                 target: "0x00000000000000000000000000000000deadbe02",
                                 executionGas: 100_000, stateGas: 250_000,
                                 value: "0x1", data: "0x"),
                    outcome: .init(succeeded: true, gasUsed: 3_000, stateGasUsed: nil, logCount: 1)),
            ])
        let fixture = [FramesAccount(address: sender,
                                     balanceWeiHex: "0x152d02c708d9ed097cba",
                                     nonce: 2,
                                     moves: [move])]
        Task { @MainActor in FramesLiveState.shared.installDemo(fixture) }
    }

    /// Undone BY NAME, never a blanket wipe — a dev install may hold a real
    /// watch list and a real key under the same seat.
    nonisolated static func teardownDemo() {
        Task { @MainActor in FramesLiveState.shared.clear() }
    }
}
