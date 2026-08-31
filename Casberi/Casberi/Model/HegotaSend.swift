import Foundation
import SwiftData

/// SENDING ON HEGOTÁ (prd §525, 2026-08-29) — the one place this app writes
/// to the frame-transaction devnet, and the only caller of `HegotaKey.sign`.
///
/// ## WHY THIS IS SIMPLER THAN VIBENET'S SEND, AND WHY THAT IS NOT LUCK
///
/// Vibenet's write needs a round trip to a payer SERVICE, because sponsorship
/// there is a second signature (`payerAuth`) that only the faucet can produce
/// and the transaction is invalid without it in the right shape. Hegotá's
/// sponsorship is a PROTOCOL MECHANISM, not a second signer: a frame executing
/// `APPROVE` (opcode `0xAA`) with a payment scope sets the payer AT RUNTIME,
/// and the nonce increment and balance deduction happen during execution
/// (§525). There is no `payerAuth` field to fill and no service call to make
/// to get one — which also means this file cannot construct a sponsored
/// transaction at all, because building the APPROVE frame requires knowing the
/// sponsor CONTRACT's calling convention, and none has been read. Every
/// transaction this file sends is unsponsored: `payer == sender`, exactly what
/// was measured on all 356 real transactions on this chain.
///
/// ## THE FAUCET IS A SEPARATE, KEYLESS WRITE
///
/// `POST faucet.hegota.ethrex.xyz/api/claim` needs no signature and no key —
/// it is the network handing an address free test ETH, not an account acting.
/// It is rate-limited to one claim per SOURCE IP per hour (measured), which is
/// stated in the failure rather than guessed at.
enum HegotaSend {

    private static let faucetClaimEndpoint = "https://faucet.hegota.ethrex.xyz/api/claim"

    enum Failure: Error, Equatable {
        case noKey
        /// The faucet's own verdict, carried whole rather than flattened to a
        /// string (prd §531). The rate limit is the refusal this service was
        /// MEASURED to make on an ordinary day, and it is not a fault — a
        /// screen has to be able to tell it apart from a real one, which a
        /// sentence it has to grep cannot do.
        case faucet(HegotaFaucetVerdict)
        /// The chain refused it, **in the node's own words** (prd §530). Ours
        /// were a placeholder that named none of the causes: `insufficient
        /// funds`, `nonce too low` and a malformed frame are three different
        /// next steps and were one dead end.
        case broadcastRefused(String)
        /// No host answered at all. Never reported as a refusal — see
        /// `broadcast`, and §515a for the read-path version of this mistake.
        case chainUnreachable
        case signingRefused
    }

    struct Claimed: Equatable {
        let transactionHash: String
    }

    // MARK: - The faucet

    /// Ask the faucet to fund `address`. No key, no signature — this is the
    /// network's own gift, not an act this phone's key performs.
    /// **`postJSONBody`, NOT `postJSON`** (prd §531, 2026-08-30) — the same
    /// helper §530 added for the broadcast below, and here for the same reason
    /// one step further: this service's refusals are the thing worth reading.
    ///
    /// `postJSON` returns nil for ANY non-200, so the measured rate limit (one
    /// claim per source IP per hour, §525) arrived here indistinguishable from
    /// a dead host and was reported as `"no answer"`. The key sheet then tested
    /// that text for `"429"` to decide whether to say "already claimed this
    /// hour" — **a branch that could never once have been true**, over the one
    /// refusal this faucet is known to make on an ordinary day. `postJSONStatus`
    /// would separate those two and is still not enough: it drops the BODY on a
    /// non-200, so the faucet's own `{"msg":"invalid address"}` survives only if
    /// it happens to arrive with a 200.
    static func claimFaucet(for address: String) async throws -> Claimed {
        let body: [String: Any] = ["address": address]
        let answered = await IngestSupport.postJSONBody(faucetClaimEndpoint, body: body,
                                                        service: HegotaIdentity.source)
        let root = answered.json as? [String: Any]
        // Measured shapes: 200 with {"msg":"sent","txhash":"0x…"}, 200 with
        // {"msg":"invalid address"}, and a bare 429 for the hourly limit.
        let verdict = HegotaFaucetVerdict.of(status: answered.status,
                                             msg: root?["msg"] as? String,
                                             txHash: root?["txhash"] as? String)
        if case .sent(let hash) = verdict { return Claimed(transactionHash: hash) }
        throw Failure.faucet(verdict)
    }

    // MARK: - The receipt

    /// WHAT YOU DID LANDS IN THE CORPUS (prd §525, the same ruling §523 made
    /// for vibenet, extended here rather than re-derived). `HegotaBridge`
    /// lands NO `Thing` at all for anything it watches — a devnet test account
    /// has nothing worth a corpus row — and that stays true for reads. A write
    /// is the other thing: you asked for it, it changed the chain, and it
    /// should be searchable and keepable like anything else you did.
    ///
    /// Covers BOTH acts this file can perform: a signed send (`kind: .sent`)
    /// and a faucet claim (`kind: .claimed`) — the claim carries no signature
    /// of yours, but it is still something you asked for and it still landed
    /// money in an account you hold, which is the same "you are its source"
    /// reasoning §523 used, not a weaker one.
    enum ReceiptKind {
        case sent(to: String)
        case claimed

        var refTag: String {
            switch self {
            case .sent:    "sent"
            case .claimed: "claimed"
            }
        }
    }

    @MainActor
    static func landReceipt(txHash: String, kind: ReceiptKind, in context: ModelContext) {
        let ref = "hegota:\(kind.refTag):\(txHash)"
        let existing = FetchDescriptor<Thing>(predicate: #Predicate { $0.sourceRef == ref })
        if let found = try? context.fetch(existing), !found.isEmpty { return }

        let account = HegotaKey.address()
        let title: String
        let summary: String
        switch kind {
        case .sent(let to):
            title = String(localized: "Sent test ETH on Hegotá")
            summary = String(localized: "Signed by this phone's key, to \(WalletStore.shortAddress(to)).")
        case .claimed:
            title = String(localized: "Claimed test ETH from the Hegotá faucet")
            summary = String(localized: "Requested for this phone's account. No signature was needed \u{2014} the faucet gives it freely.")
        }

        let thing = Thing(
            kind: .transaction,
            title: title,
            content: "\(HegotaIdentity.explorer)/tx/\(txHash)",
            source: HegotaIdentity.source,
            capturedAt: .now,
            tags: kind.refTag == "sent" ? ["Sent"] : ["Faucet"],
            sourceRef: ref)
        thing.walletAddress = account
        thing.summary = summary
        context.insert(thing)
        try? context.save()
    }

    // MARK: - The nonce

    /// This address's key-0 sequence, straight off the chain — the same read
    /// `HegotaBridge` already does for the room (`eth_getTransactionCount`).
    /// A caller composing a send reads this first rather than guessing: a
    /// wrong sequence is a transaction the chain refuses, not a wrong one it
    /// accepts.
    static func currentNonceSequence(for address: String) async -> UInt64? {
        guard let hex = await HegotaRPC.call(method: "eth_getTransactionCount",
                                             params: [address, "latest"]) as? String,
              let value = UInt64(hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex, radix: 16)
        else { return nil }
        return value
    }

    // MARK: - The one write that signs

    /// Broadcast. The only write verb in this app's Hegotá code that follows a
    /// signature — the method literal appearing exactly once, so the conduct
    /// guard has one thing to count.
    ///
    /// ## THE NODE'S OWN WORDS (prd §530), and the same fix vibenet took
    ///
    /// This rode `HegotaRPC.call`, which maps a transport failure, a non-200
    /// and a JSON-RPC `error` object all to nil — so every refusal arrived as
    /// one placeholder sentence naming none of them. Sending is the path where
    /// that costs most: a read that goes quiet is annoying, a write refused
    /// with no reason cannot be acted on.
    ///
    /// `postJSONBody`, not `postJSON`: a node commonly answers a rejected send
    /// with **HTTP 400 and the reason in the body**, and every other helper in
    /// `IngestSupport` gates the body on a 200 — throwing away the one thing
    /// worth having before any parse could reach it.
    ///
    /// **A host that REFUSED has answered**, so the walk stops there rather
    /// than asking two more nodes the same rejected transaction and reporting
    /// the last one's silence instead of the first one's reason — `HegotaRPC.
    /// call`'s own rule, which matters more here than on any read.
    static func broadcast(rawTransaction raw: String) async throws -> String {
        let body: [String: Any] = ["id": 1, "jsonrpc": "2.0",
                                   "method": "eth_sendRawTransaction", "params": [raw]]
        var answeredWithStatus = 0
        for host in HegotaRPC.hosts {
            let answered = await IngestSupport.postJSONBody(host, body: body,
                                                            service: HegotaIdentity.source)
            guard let root = answered.json as? [String: Any] else {
                // Nothing readable from this host — the next one may be up.
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

    // MARK: - Send a simple value transfer

    /// The two-frame shape measured on chain: a `self_verify` prefix (mode 1,
    /// flags `0x03`, targeting the sender) proving the sender's own signature,
    /// followed by a mode-2 SENDER frame doing the actual transfer. This is
    /// the canonical minimal shape (§525) — not invented here, read off the
    /// simplest real transaction on the chain.
    ///
    /// `nonceSequence` and `chainID` are the caller's: this file does not read
    /// the chain, so it does not guess a nonce. A caller composing a real send
    /// reads the account's current sequence first.
    static func sendValue(to target: Data,
                          valueWei: Data,
                          nonceSequence: UInt64,
                          executionGas: UInt64 = 80_000,
                          maxPriorityFeePerGas: UInt64 = 1_000_000_000,
                          maxFeePerGas: UInt64 = 30_000_000_000) async throws -> String {
        guard let address = HegotaKey.address(),
              let sender = RLP.data(fromHex: address) else { throw Failure.noKey }

        var fields = HegotaTransaction.Fields(
            chainID: 0x30_1824,
            nonceKeys: [0],
            nonceSequence: nonceSequence,
            sender: sender,
            frames: [
                .init(mode: 1, flags: 0x03, target: sender,
                      executionGas: executionGas, stateGas: 0, value: Data(), data: Data()),
                .init(mode: 2, flags: 0x00, target: target,
                      executionGas: executionGas, stateGas: 0, value: valueWei, data: Data()),
            ],
            // The entry itself must be PRESENT when the digest is taken —
            // only its `signature` bytes are elided (trap 2 in
            // `HegotaTransaction`'s own doc). Leaving the whole array empty
            // here and appending the entry only after signing hashes a
            // DIFFERENT list than the one that gets broadcast — an empty
            // `.list([])` versus a one-entry list whose signature field
            // happens to be blank — so the node's own recomputed sigHash
            // never matched what this phone signed, and every send came
            // back "invalid frame transaction signature".
            signatures: [.init(scheme: 1, signer: Data(), msg: Data(), signature: Data())],
            maxPriorityFeePerGas: maxPriorityFeePerGas,
            maxFeePerGas: maxFeePerGas,
            maxFeePerBlobGas: 0,
            blobVersionedHashes: [],
            recentRootReferences: [])

        let preimage = HegotaTransaction.signingPreimage(fields)
        let digest = [UInt8](Keccak256.hash([UInt8](preimage)))
        let signature: [UInt8]
        do {
            signature = try HegotaKey.sign(hash: digest,
                                           reason: String(localized: "Sign this transaction on Hegotá"))
        } catch { throw Failure.signingRefused }

        // `v || r || s` — measured layout (§525). The signature entry's
        // `signer` stays EMPTY, meaning "the sender" (trap 4 in
        // HegotaTransaction's own doc): writing the address in would change
        // the hash we just signed.
        fields.signatures = [.init(scheme: 1, signer: Data(), msg: Data(),
                                   signature: Data(signature))]

        let raw = "0x" + RLP.hex(HegotaTransaction.encoded(fields))
        return try await broadcast(rawTransaction: raw)
    }
}
