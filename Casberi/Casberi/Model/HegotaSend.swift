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
        /// string (prd §530). The rate limit is the refusal this service was
        /// MEASURED to make on an ordinary day, and it is not a fault — a
        /// screen has to be able to tell it apart from a real one, which a
        /// sentence it has to grep cannot do.
        case faucet(HegotaFaucetVerdict)
        case broadcastRefused(String)
        case signingRefused
    }

    struct Claimed: Equatable {
        let transactionHash: String
    }

    // MARK: - The faucet

    /// Ask the faucet to fund `address`. No key, no signature — this is the
    /// network's own gift, not an act this phone's key performs.
    /// **`postJSONAnyStatus`, NOT `postJSON`** (prd §530, 2026-08-30) — and
    /// the difference is the whole of this function's honesty.
    ///
    /// `postJSON` returns nil for ANY non-200, so the measured rate limit (one
    /// claim per source IP per hour, §525) arrived here indistinguishable from
    /// a dead host and was reported as `"no answer"`. The key sheet then tested
    /// that text for `"429"` to decide whether to say "already claimed this
    /// hour" — a branch that could never once have been true, over the one
    /// refusal this faucet was known to make.
    ///
    /// `postJSONStatus` would separate those two and is still not enough: it
    /// drops the BODY on a non-200, so the faucet's own `{"msg":"invalid
    /// address"}` would survive only if the service happened to send it with a
    /// 200. Reading the refusal is the whole point, so the body comes back at
    /// whatever status.
    static func claimFaucet(for address: String) async throws -> Claimed {
        let body: [String: Any] = ["address": address]
        let answer = await IngestSupport.postJSONAnyStatus(faucetClaimEndpoint, body: body,
                                                           service: HegotaIdentity.source)
        let root = answer.json as? [String: Any]
        // Measured shapes: 200 with {"msg":"sent","txhash":"0x…"}, 200 with
        // {"msg":"invalid address"}, and a bare 429 for the hourly limit.
        let verdict = HegotaFaucetVerdict.of(status: answer.status,
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
    /// signature — appearing exactly once, so the conduct guard has one thing
    /// to count.
    /// **THE NODE'S OWN WORDS SURVIVE** (prd §530, 2026-08-30). This used to
    /// read `HegotaRPC.call`, which maps a JSON-RPC `error` object onto the
    /// same nil as a dead host — so every possible cause reached the screen as
    /// the single sentence "the node refused the transaction", which names
    /// nothing and can be acted on in no way. `callOutcome` keeps the message;
    /// `NodeRefusal` explains it where it can and quotes it where it cannot.
    static func broadcast(rawTransaction raw: String) async throws -> String {
        switch await HegotaRPC.callOutcome(method: "eth_sendRawTransaction", params: [raw]) {
        case .value(let result):
            guard let hash = result as? String else {
                throw Failure.broadcastRefused(NodeRefusal.sentence(nil))
            }
            return hash
        case .refused(let message):
            throw Failure.broadcastRefused(NodeRefusal.sentence(message))
        case .unreachable:
            throw Failure.broadcastRefused(NodeRefusal.sentence(nil))
        }
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
            signatures: [],
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
