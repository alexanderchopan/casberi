import Foundation

/// SENDING ON THE FRAMES DEVNET (prd §548, 2026-09-01) — the one place this
/// app writes to chain 81410, and the only caller of `FramesKey.sign`.
///
/// ## THE FAUCET'S CLASSIFIER IS SHARED, NOT FORKED
///
/// `POST faucet.frames.ethrex.xyz/api/claim` takes `{"address": "0x…"}` and
/// answers `{"msg": …, "txhash": "0x…"}` — **byte-for-byte the shape Hegotá's
/// faucet uses**, including the bare 429 for its hourly limit (measured
/// 2026-09-01). So `HegotaFaucetVerdict` classifies this one correctly with no
/// change, and it is used rather than copied: two classifiers of one wire
/// shape drift, and then two seats disagree about what "already claimed this
/// hour" looks like. That type carries §531's whole reasoning — the ordering
/// of its checks is the whole of its correctness — and none of it is
/// chain-specific.
///
/// The name is Hegotá's because renaming it would churn a passing harness's
/// seventeen assertions for no behavioural gain; `DevnetFaucetVerdict` below
/// is what this file calls it, and a later pass may make that the real name.
///
/// ## TWO DIVERGENCES FROM `HegotaSend`, BOTH MEASURED, BOTH SILENT IF WRONG
///
/// 1. **The signature entry's `signer` is written LITERALLY here, where
///    Hegotá writes it EMPTY.** Hegotá's empty field means "the sender" and
///    its transactions are signed that way. On this chain the convention has
///    never been used: all 5 type-`0x06` transactions write the address in
///    full, and re-encoding proves it — literal matches 5/5, empty matches
///    **0/5**. An empty signer here produces a hash the node recomputes
///    differently and refuses as an invalid signature.
/// 2. **A real state budget, where Hegotá sends `stateGas: 0`.** Execution
///    gas cannot pay for state growth, and a transfer to an address that does
///    not exist yet grows state — which on a four-day-old devnet is the common
///    case, not an edge one. With `state: 0` the frame halts on that write and
///    burns its whole execution budget, reporting what reads as an execution
///    failure. `FramesTransaction.transfer` defaults to the 250,000 the
///    faucet's own guidance names.
///
/// ## THE TRAP HEGOTÁ ALREADY PAID FOR, CARRIED HERE
///
/// **The signature entry must be PRESENT when the digest is taken** — only its
/// `signature` bytes are elided. Leaving the array empty and appending the
/// entry after signing hashes a different list (`.list([])` versus a one-entry
/// list whose signature field is blank), so the node's recomputed sigHash
/// never matches and every send comes back "invalid frame transaction
/// signature". Asserted in the harness rather than left to this comment.
enum FramesSend {

    /// One classifier for both devnets' faucets — see the type doc.
    typealias DevnetFaucetVerdict = HegotaFaucetVerdict

    private static let faucetClaimEndpoint = "https://faucet.frames.ethrex.xyz/api/claim"

    enum Failure: Error, Equatable {
        case noKey
        /// The faucet's own verdict, carried whole rather than flattened to a
        /// string (§531). The rate limit is not a fault and a screen has to be
        /// able to tell it apart from one.
        case faucet(DevnetFaucetVerdict)
        /// The chain refused it, **in the node's own words** (§530).
        case broadcastRefused(String)
        /// No host answered at all. Never reported as a refusal — not knowing
        /// is not the same as being told no (§515a).
        case chainUnreachable
        case signingRefused
        /// The validation prefix exceeds this chain's `MAX_VERIFY_GAS`.
        /// Refused HERE rather than by the node, because the node's own
        /// sentence for it names no remedy.
        case prefixTooLarge
    }

    struct Claimed: Equatable { let transactionHash: String }

    // MARK: - The faucet

    /// Ask the faucet to fund `address`. No key, no signature — this is the
    /// network's own gift, not an act this phone's key performs.
    ///
    /// **`postJSONBody`, NOT `postJSON`** (§531): `postJSON` returns nil for
    /// ANY non-200, so the hourly rate limit arrives indistinguishable from a
    /// dead host. `postJSONStatus` is not enough either — it drops the BODY on
    /// a non-200, and this service's own `{"msg": "…"}` is the thing worth
    /// reading.
    static func claimFaucet(for address: String) async throws -> Claimed {
        let body: [String: Any] = ["address": address]
        let answered = await IngestSupport.postJSONBody(faucetClaimEndpoint, body: body,
                                                        service: FramesIdentity.source)
        let root = answered.json as? [String: Any]
        let verdict = DevnetFaucetVerdict.of(status: answered.status,
                                             msg: root?["msg"] as? String,
                                             txHash: root?["txhash"] as? String)
        if case .sent(let hash) = verdict { return Claimed(transactionHash: hash) }
        throw Failure.faucet(verdict)
    }

    // MARK: - Reading what a send needs

    /// This chain has no keyed nonces, so the top-level count IS the nonce
    /// that gets hashed — unlike Hegotá, where the reported `nonce` is a lossy
    /// projection of a keyed set.
    static func currentNonce(for address: String) async -> UInt64? {
        guard let hex = await FramesRPC.call(method: "eth_getTransactionCount",
                                             params: [address, "latest"]) as? String
        else { return nil }
        return FramesRead.hexInt(hex)
    }

    /// The chain's own suggestion, so a send is not priced off a constant that
    /// ages. Measured 2026-09-01: `0x3b9aca07`, and `baseFeePerGas` is `0x7`.
    static func suggestedGasPrice() async -> UInt64? {
        FramesRead.hexInt(await FramesRPC.call(method: "eth_gasPrice", params: []))
    }

    // MARK: - The one write that signs

    /// Broadcast. The only write verb in this app's Frames code that follows a
    /// signature — the method literal appears exactly once, so the conduct
    /// guard has one thing to count.
    ///
    /// **A host that REFUSED has answered**, so the walk stops there rather
    /// than handing two more nodes the same rejected transaction and reporting
    /// the last one's silence instead of the first one's reason.
    ///
    /// `postJSONBody` because a node commonly answers a rejected send with
    /// **HTTP 400 and the reason in the body**, which every other helper in
    /// `IngestSupport` gates on a 200 and therefore throws away (§530).
    static func broadcast(rawTransaction raw: String) async throws -> String {
        let body: [String: Any] = ["id": 1, "jsonrpc": "2.0",
                                   "method": "eth_sendRawTransaction", "params": [raw]]
        var answeredWithStatus = 0
        for host in FramesRPC.hosts {
            let answered = await IngestSupport.postJSONBody(host, body: body,
                                                            service: FramesIdentity.source)
            guard let root = answered.json as? [String: Any] else {
                answeredWithStatus = max(answeredWithStatus, answered.status)
                continue
            }
            if let hash = root["result"] as? String, !hash.isEmpty { return hash }
            if let error = root["error"] as? [String: Any] {
                let words = (error["message"] as? String) ?? (error["data"] as? String) ?? ""
                throw Failure.broadcastRefused(words.isEmpty
                    ? String(localized: "the node refused it and gave no reason")
                    : words)
            }
            answeredWithStatus = max(answeredWithStatus, answered.status)
        }
        if answeredWithStatus > 0 {
            throw Failure.broadcastRefused(
                String(localized: "every node answered \(String(answeredWithStatus)) and nothing readable"))
        }
        throw Failure.chainUnreachable
    }

    // MARK: - What a send BECOMES

    /// The transaction a send will be, built and returned unsigned.
    ///
    /// **This exists so the console can PREVIEW the frames, and the preview is
    /// the transaction rather than a description of one.** `sendValue` below
    /// calls this and signs what it returns, so the two cannot disagree — a
    /// preview drawn from a parallel description is how a screen ends up
    /// promising two frames and sending three. It is also the only honest way
    /// to show what makes this chain different: a send here is not one act, it
    /// is a VERIFY frame that authorises and a SENDER frame that moves, and
    /// nothing about a to-and-amount form says so.
    static func plan(sender: Data, to target: Data, valueWei: Data, nonce: UInt64,
                     maxPriorityFeePerGas: UInt64 = 1_000_000_000,
                     maxFeePerGas: UInt64 = 10_000_000_000) -> FramesTransaction.Fields {
        FramesTransaction.transfer(
            sender: sender, to: target, value: valueWei, nonce: nonce,
            maxPriorityFeePerGas: maxPriorityFeePerGas, maxFeePerGas: maxFeePerGas)
    }

    // MARK: - Send a value transfer

    /// Sign and broadcast the smallest useful frame transaction: a VERIFY
    /// frame approving execution and payment, then a SENDER frame that moves
    /// the value.
    ///
    /// The caller supplies the nonce and the fees — this function does not
    /// guess a nonce, and reads nothing it was not asked to.
    static func sendValue(to target: Data,
                          valueWei: Data,
                          nonce: UInt64,
                          maxPriorityFeePerGas: UInt64 = 1_000_000_000,
                          maxFeePerGas: UInt64 = 10_000_000_000) async throws -> String {
        guard let address = FramesKey.address(),
              let sender = RLP.data(fromHex: address) else { throw Failure.noKey }

        var fields = plan(sender: sender, to: target, valueWei: valueWei, nonce: nonce,
                          maxPriorityFeePerGas: maxPriorityFeePerGas,
                          maxFeePerGas: maxFeePerGas)

        // Refuse before the Face ID, not after it (§530's ruling: a refusal
        // that could have been made before the prompt should be).
        guard FramesTransaction.prefixWithinBudget(fields) else { throw Failure.prefixTooLarge }

        // **The entry is present BEFORE the digest is taken**, carrying its
        // real signer and an empty signature — only the signature bytes are
        // elided. See the trap in the type doc.
        fields.signatures = [.init(scheme: 1, signer: sender, msg: Data(), signature: Data())]

        let preimage = FramesTransaction.signingPreimage(fields)
        let digest = [UInt8](Keccak256.hash([UInt8](preimage)))
        let signature: [UInt8]
        do {
            signature = try FramesKey.sign(
                hash: digest,
                reason: String(localized: "Sign this frame transaction"))
        } catch { throw Failure.signingRefused }

        // `v || r || s`, `v` a bare 0/1 — proven by recovering all 5 of this
        // chain's own signatures. The signer stays LITERAL: empty means "the
        // sender" on Hegotá and has never been used here, and it changes the
        // hash that was just signed.
        fields.signatures = [.init(scheme: 1, signer: sender, msg: Data(),
                                   signature: Data(signature))]

        let raw = "0x" + RLP.hex(FramesTransaction.encoded(fields))
        return try await broadcast(rawTransaction: raw)
    }
}
