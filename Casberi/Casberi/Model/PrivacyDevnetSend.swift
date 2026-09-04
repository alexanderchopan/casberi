import Foundation

/// SENDING ON ETHREX PRIVACY (prd §593a, 2026-09-04) — the second thing this
/// app writes to chain 8141, and the only caller of `PrivacyDevnetKey.sign`.
///
/// **This seat was watch-only until the envelope was reproduced, and the order
/// mattered.** §593a recorded that sending was blocked because the type-`0x6`
/// layout could not be reproduced; signing a guessed layout yields a signature
/// that is well-formed, recovers to a real address, and authorises something
/// other than what the screen said. That is now settled —
/// `PrivacyDevnetTransaction` re-encodes 14 of 14 real transactions
/// byte-exactly with its keccak matching the chain's own hash, and
/// `privacy-tx-selftest.sh` holds it there through nine mutations. Nothing here
/// signs anything the encoder underneath it has not proven.
///
/// **PROVEN AGAINST THE CHAIN (2026-09-04).** A key was made, the faucet funded
/// it, and a two-frame transfer of 0.001 ETH was signed and broadcast: the node
/// returned OUR OWN PREDICTED HASH
/// (`0x3b87ac12…`), which is the proof — the bytes we hashed are the bytes it
/// hashed — and it mined in block 16399 with status 1, the recipient holding
/// 0.001 ETH. Two bugs in this file were found by that run and by nothing else,
/// each recorded at its line: an empty `nonceKeys` list is refused outright, and
/// mode 2 is SENDER where the first cut used 0.
///
/// **The faucet is byte-identical to Hegotá's** — `POST /api/claim` with
/// `{"address"}`, and an invalid address answers `400 {"msg":"invalid
/// address"}` on both, measured — so `HegotaFaucetVerdict` is REUSED rather
/// than forked. Two classifiers of one wire drift, and then two seats disagree
/// about whether the same answer was a refusal.
enum PrivacyDevnetSend {

    /// `POST /api/claim`, no key and no signature — which is what lets it fund
    /// an address the chain has never seen.
    private static let faucetClaimEndpoint = "https://faucet.privacy.ethrex.xyz/api/claim"

    enum Failure: Error {
        case noKey
        case chainUnreachable
        /// The node refused the bytes, IN ITS OWN WORDS.
        ///
        /// Never a placeholder: this chain answers a rejected send with a
        /// reason that names the cause — `Nonce mismatch: expected 1, got 0`,
        /// `Error decoding field 'fees'` — and §530's ruling is that the
        /// person sees the node's sentence rather than ours. The same property
        /// is what made the envelope findable at all.
        case refused(String)
        case signingRefused
        case faucet(HegotaFaucetVerdict)
    }

    // MARK: - The faucet

    /// Ask the faucet to fund `address`. No key, no signature.
    ///
    /// A non-200 carries the reason in the BODY, so `postJSONBody` is the
    /// helper rather than one that gates on a 200 — §530's lesson, and the
    /// reason the refusal below can be the faucet's own words.
    static func claim(address: String) async throws -> String {
        let body: [String: Any] = ["address": address]
        let answered = await IngestSupport.postJSONBody(
            faucetClaimEndpoint, body: body, service: PrivacyDevnetIdentity.source)
        let root = answered.json as? [String: Any]
        // The SAME classifier Hegotá uses, on a wire measured identical: an
        // invalid address answers `400 {"msg":"invalid address"}` on both.
        let verdict = HegotaFaucetVerdict.of(status: answered.status,
                                             msg: root?["msg"] as? String,
                                             txHash: root?["txhash"] as? String)
        if case .sent(let hash) = verdict { return hash }
        throw Failure.faucet(verdict)
    }

    // MARK: - Sending

    /// The smallest useful transaction: a VERIFY frame, then the transfer.
    ///
    /// **Two frames, not one**, and that is measured rather than copied: every
    /// signed transaction on this chain opens with `mode 1, flags 3` targeting
    /// the sender itself — the two APPROVE scope bits, execution and payment —
    /// which runs the default path, checks the outer signature and approves
    /// both. Without it the transaction has no payer and is invalid.
    static func transfer(to recipient: String, weiHex: String,
                         nonce: UInt64, gasPrice: UInt64,
                         nonceKeys: [Data] = []) throws -> PrivacyDevnetTransaction.Fields {
        guard let sender = PrivacyDevnetKey.address() else { throw Failure.noKey }
        let senderBytes = PrivacyDevnetRPC.hexData(sender)
        let verify = PrivacyDevnetTransaction.Frame(
            mode: 1, flags: 3, target: senderBytes,
            gasLimit: 0x13880, stateLimit: 0, value: Data(), data: Data())
        // **MODE 2 IS SENDER, and mode 0 is not.** The node refuses a
        // non-zero value in any other mode — `non-zero value only allowed in
        // SENDER mode` — which is how this was found: the first cut used 0,
        // which is what a reader of the sibling encoders would assume.
        // Measured off a real transfer on this chain, whose second frame is
        // `mode 0x2, flags 0x0`.
        let move = PrivacyDevnetTransaction.Frame(
            mode: 2, flags: 0, target: PrivacyDevnetRPC.hexData(recipient),
            // A transfer to an address the chain has not seen GROWS STATE, and
            // execution gas cannot pay for state growth — the Frames devnet's
            // own measured lesson (§548), where `stateGas: 0` halts the frame
            // on that write and reports what reads as an execution failure.
            gasLimit: 0x7530, stateLimit: 0x2cd30,
            value: PrivacyDevnetRPC.hexData(weiHex), data: Data())
        return PrivacyDevnetTransaction.Fields(
            chainID: PrivacyDevnetChain.chainID,
            // **AT LEAST ONE KEY, ALWAYS.** The node enforces
            // `nonce_keys count must be between 1 and 16`, so an empty list is
            // refused outright — the first cut passed one and was rejected.
            // `0` is the default channel, which is what every ordinary
            // transaction on this chain uses; a caller wanting a spend that
            // cannot be linked to the last one supplies a fresh 32-byte key
            // instead, which is the unlinkability this chain is for.
            nonceKeys: nonceKeys.isEmpty ? [Data([0])] : nonceKeys,
            nonce: nonce,
            sender: senderBytes,
            frames: [verify, move],
            signatures: [],
            maxPriorityFeePerGas: gasPrice,
            maxFeePerGas: gasPrice,
            maxFeePerBlobGas: 0,
            blobVersionedHashes: [],
            recentRootReferences: [])
    }

    /// Sign and broadcast.
    ///
    /// **The signature entry is present BEFORE the digest is taken**, carrying
    /// its real signer and an EMPTY signature — only the signature bytes are
    /// elided. Adding the entry afterwards signs a transaction with no
    /// signature list, which is a different set of bytes and therefore a
    /// signature over something else.
    static func send(_ fields: PrivacyDevnetTransaction.Fields) async throws -> String {
        var f = fields
        guard let sender = PrivacyDevnetKey.address() else { throw Failure.noKey }
        let senderBytes = PrivacyDevnetRPC.hexData(sender)

        // **`signer` LITERAL.** Measured 9 of 9 on this chain's signed
        // transactions; Hegotá writes it EMPTY (0/5) and the two are not
        // interchangeable — the empty form changes the hash that was signed.
        f.signatures = [.init(scheme: 1, signer: senderBytes, msg: Data(), signature: Data())]

        let preimage = PrivacyDevnetTransaction.signingPreimage(f)
        let digest = [UInt8](Keccak256.hash([UInt8](preimage)))
        let signature: [UInt8]
        do {
            signature = try PrivacyDevnetKey.sign(
                hash: digest,
                reason: String(localized: "Sign this frame transaction"))
        } catch { throw Failure.signingRefused }

        f.signatures = [.init(scheme: 1, signer: senderBytes, msg: Data(),
                              signature: Data(signature))]
        let raw = "0x" + RLP.hex(PrivacyDevnetTransaction.encoded(f))
        return try await broadcast(rawTransaction: raw)
    }

    /// Broadcast, and surface the node's OWN refusal.
    ///
    /// `PrivacyDevnetRPC.call` maps a transport failure, a non-200 and a
    /// JSON-RPC error object all to nil, so it cannot be used here: the reason
    /// is the whole point (§530). This chain's refusals are unusually
    /// informative — they name the field being decoded — which is exactly what
    /// made the envelope findable, and throwing that away would be discarding
    /// the most useful thing the node says.
    static func broadcast(rawTransaction raw: String) async throws -> String {
        let body: [String: Any] = ["id": 1, "jsonrpc": "2.0",
                                   "method": "eth_sendRawTransaction",
                                   "params": [raw]]
        for host in PrivacyDevnetChain.hosts {
            guard let root = await IngestSupport.postJSONBody(
                    host, body: body, service: PrivacyDevnetIdentity.source) as? [String: Any]
            else { continue }
            if let hash = root["result"] as? String { return hash }
            if let err = root["error"] as? [String: Any],
               let message = err["message"] as? String {
                // A node that ANSWERED with an error has answered — walking on
                // would ask two more the same refused question and report
                // "unreachable" for what is really our own bad transaction.
                throw Failure.refused(message)
            }
        }
        throw Failure.chainUnreachable
    }
}
