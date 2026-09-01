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
    static let source = "Frames"
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
