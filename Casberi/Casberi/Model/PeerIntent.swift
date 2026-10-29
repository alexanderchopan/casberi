import Foundation

/// Deposit's on-chain half (prd §1598, §1604): reserve a seller's USDC for
/// the person, then release it to them with the enclave's receipt. Two calls
/// to Peer's OrchestratorV3 on Base, both sent from the person's own account;
/// nothing here signs or sends — it builds the requests and the calldata, and
/// reads the answers.
///
///   1. `/v3/sign` — the curator (Peer's gating service) signs the intent for
///      THIS caller. A Safe is a caller like any other (measured 2026-10-29:
///      signed for a Safe, and the same signature from another sender reverts
///      `InvalidSignature`). Peer's 0.95% comes back as a referral fee the
///      curator adds itself; it is passed to the chain exactly as returned.
///   2. `signalIntent(SignalIntentParams)` — the reservation. The intent's
///      hash is read back off the `IntentSignaled` log, never computed here.
///   3. `/buyer/verify/<platform>/<action>` on the enclave — the sealed
///      session (`PeerSessionEnvelope`) and the intent go in, a signed
///      payment attestation comes out.
///   4. `fulfillIntent(FulfillIntentParams)` — `paymentProof` is the
///      attestation as `(bytes32,uint256,bytes32,bytes[],bytes,bytes)`, and
///      `verificationData` is `(intentHash, paymentProof, abi.encode(signer))`,
///      as `@zkp2p/sdk` 0.14.11's `utils/encode.ts` writes them; three real
///      fulfils on Base decode to exactly that (`peer-intent-selftest.sh`).
///
/// Peer's own SDK appends an ERC-8021 attribution tag to its calldata; we
/// append none.
enum PeerIntent {

    static let chainId = 8453
    static let orchestrator = "0x014025fde093f8701d86e9f38e2c3a9b779cb5c7"
    static let escrow = "0x777777779d229cdf3110e9de47943791c26300ef"
    /// The enclave's address that signs payment attestations, as the
    /// attestation service advertises it (`expectedSigner`) and as every
    /// fulfil read on Base carries it. A verify answer signed by anyone else
    /// is refused before it reaches the chain.
    static let attestationSigner = "0xe078d93bfdd87a8c5c5cca5905dcba0dd7a1f0bd"

    static let signalSignature = "signalIntent((address,uint256,uint256,address,bytes32,bytes32,uint256,(address,uint256)[],bytes,uint256,address,bytes,bytes))"
    static let fulfillSignature = "fulfillIntent((bytes,bytes32,bytes,bytes))"
    /// `IntentSignaled(bytes32 indexed intentHash, address indexed escrow, uint256 indexed depositId, …)`
    static let intentSignaledTopic = "0xf8c114f83581b2cf0b9f130782a93024aa8933e7d188901156bd68bdd558a20a"

    // MARK: - The order

    /// One order, as a quote names it (`/v3/quote/exact-fiat`'s `intent`).
    struct Order: Equatable {
        var processorName: String       // "revolut"
        var paymentMethod: String       // bytes32, the method's hash
        var payeeDetails: String        // bytes32, the seller's payee hash
        var depositId: String           // decimal
        var amount: String              // USDC, 6 decimals, decimal
        var fiatCurrency: String        // bytes32
        var conversionRate: String      // 18 decimals, decimal
        var to: String                  // who receives the USDC
    }

    struct ReferralFee: Equatable {
        var recipient: String
        var fee: String
    }

    /// What the curator signed, echoed back: only what `signalIntent` takes.
    struct Signed: Equatable {
        var order: Order
        var caller: String
        var referralFees: [ReferralFee]
        var gatingSignature: String
        var expiration: String
        var preIntentHookData: String
        var postIntentHook: String
        var data: String
    }

    enum SignAnswer: Equatable {
        case signed(Signed)
        /// The deposit gates on chain and wants no curator signature (409
        /// "enforced on-chain"); the intent is signalled with an empty one.
        case enforcedOnChain
        case refused(String)
    }

    static func signRequest(_ order: Order, caller: String) -> [String: Any] {
        ["processorName": order.processorName,
         "payeeDetails": order.payeeDetails,
         "depositId": order.depositId,
         "amount": order.amount,
         "toAddress": order.to,
         "paymentMethod": order.paymentMethod,
         "fiatCurrency": order.fiatCurrency,
         "conversionRate": order.conversionRate,
         "chainId": String(chainId),
         "orchestratorAddress": orchestrator,
         "escrowAddress": escrow,
         "callerAddress": caller,
         "referralFees": [[String: String]](),
         "postIntentHook": "0x0000000000000000000000000000000000000000",
         "data": "0x"]
    }

    /// The curator's answer, refused unless it signed THE order we asked for,
    /// for the caller we named, on this orchestrator and escrow: a signature
    /// over anything else is one the chain would honour for a different trade.
    static func readSign(status: Int, json: [String: Any], asked order: Order, caller: String) -> SignAnswer {
        let message = json["message"] as? String ?? ""
        if status == 409 {
            return message.range(of: "enforced on-chain", options: .caseInsensitive) != nil
                ? .enforcedOnChain : .refused(message)
        }
        guard status == 200, json["success"] as? Bool == true,
              let object = json["responseObject"] as? [String: Any],
              let d = object["intentData"] as? [String: Any],
              let signature = (d["gatingServiceSignature"] as? String) ?? (object["signedIntent"] as? String),
              let expiration = d["signatureExpiration"] as? String
        else { return .refused(message.isEmpty ? "unreadable" : message) }
        func same(_ key: String, _ value: String) -> Bool {
            (d[key] as? String)?.lowercased() == value.lowercased()
        }
        guard same("orchestratorAddress", orchestrator), same("escrowAddress", escrow),
              same("depositId", order.depositId), same("amount", order.amount),
              same("recipientAddress", order.to), same("paymentMethod", order.paymentMethod),
              same("fiatCurrency", order.fiatCurrency), same("conversionRate", order.conversionRate),
              same("callerAddress", caller), same("chainId", String(chainId))
        else { return .refused("signed a different order") }
        var fees: [ReferralFee] = []
        for raw in d["referralFees"] as? [[String: Any]] ?? [] {
            guard let recipient = raw["recipient"] as? String, SafeABI.word(address: recipient) != nil,
                  let fee = raw["fee"] as? String, SafeABI.word(uint256: fee) != nil
            else { return .refused("unreadable fee") }
            fees.append(ReferralFee(recipient: recipient, fee: fee))
        }
        return .signed(Signed(order: order, caller: caller, referralFees: fees,
                              gatingSignature: signature, expiration: expiration,
                              preIntentHookData: d["preIntentHookData"] as? String ?? "0x",
                              postIntentHook: d["postIntentHook"] as? String ?? "0x0000000000000000000000000000000000000000",
                              data: d["data"] as? String ?? "0x"))
    }

    // MARK: - signalIntent

    static func signalCalldata(_ s: Signed) -> [UInt8]? {
        guard let escrowW = SafeABI.word(address: escrow),
              let deposit = SafeABI.word(uint256: s.order.depositId),
              let amount = SafeABI.word(uint256: s.order.amount),
              let to = SafeABI.word(address: s.order.to),
              let method = bytes32(s.order.paymentMethod),
              let fiat = bytes32(s.order.fiatCurrency),
              let rate = SafeABI.word(uint256: s.order.conversionRate),
              let gating = SafeABI.hexBytes(s.gatingSignature),
              let expiration = SafeABI.word(uint256: s.expiration),
              let hook = SafeABI.word(address: s.postIntentHook),
              let pre = SafeABI.hexBytes(s.preIntentHookData),
              let data = SafeABI.hexBytes(s.data)
        else { return nil }
        var fees: [Arg] = []
        for f in s.referralFees {
            guard let r = SafeABI.word(address: f.recipient), let v = SafeABI.word(uint256: f.fee) else { return nil }
            fees.append(.tuple([.word(r), .word(v)]))
        }
        let params: Arg = .tuple([.word(escrowW), .word(deposit), .word(amount), .word(to),
                                  .word(method), .word(fiat), .word(rate), .array(fees),
                                  .bytes(gating), .word(expiration), .word(hook),
                                  .bytes(pre), .bytes(data)])
        return selector(signalSignature) + Arg.encode([params])
    }

    /// The intent's hash, off the `IntentSignaled` log a signal's receipt
    /// carries from the orchestrator. Nil when there is not exactly one.
    static func intentHash(fromLogs logs: [[String: Any]]) -> String? {
        let hits = logs.filter {
            ($0["address"] as? String)?.lowercased() == orchestrator
                && ($0["topics"] as? [String])?.first?.lowercased() == intentSignaledTopic
        }
        guard hits.count == 1, let topics = hits[0]["topics"] as? [String], topics.count > 1,
              bytes32(topics[1]) != nil else { return nil }
        return topics[1].lowercased()
    }

    // MARK: - /buyer/verify and fulfillIntent

    /// What `fulfillIntent` needs from the chain's record of the intent
    /// (OrchestratorV3's `getIntent`, or the indexer) to ask the enclave.
    struct Signaled: Equatable {
        var intentHash: String
        var amount: String
        var timestamp: Int            // seconds, as the chain stamped it
        var paymentMethod: String
        var fiatCurrency: String
        var conversionRate: String
        var payeeDetails: String
    }

    static func verifyPath(platform: String, actionType: String) -> String {
        "/buyer/verify/\(platform)/\(actionType)"
    }

    static func verifyRequest(sealed: String, params: [String: String], intent: Signaled) -> [String: Any] {
        ["encryptedSessionMaterial": sealed,
         "params": params,
         "chainId": chainId,
         "intent": ["intentHash": intent.intentHash,
                    "amount": intent.amount,
                    "timestampMs": String(intent.timestamp * 1000),
                    "paymentMethod": intent.paymentMethod,
                    "fiatCurrency": intent.fiatCurrency,
                    "conversionRate": intent.conversionRate,
                    "payeeDetails": intent.payeeDetails,
                    "timestampBufferMs": "300000"]]
    }

    struct Attestation: Equatable {
        var intentHash: String
        var releaseAmount: String
        var dataHash: String
        var signature: String
        var signer: String
        var encodedPaymentDetails: String
        var metadata: String
    }

    /// The enclave's answer, refused unless it attests THIS intent, is
    /// signed by the enclave's own address, and releases no more than the
    /// intent reserved.
    static func readVerify(json: [String: Any], for intent: Signaled) -> Attestation? {
        guard json["success"] as? Bool == true,
              let o = json["responseObject"] as? [String: Any],
              let td = o["typedDataValue"] as? [String: Any],
              let hash = td["intentHash"] as? String, hash.lowercased() == intent.intentHash.lowercased(),
              let release = (td["releaseAmount"] as? String) ?? (td["releaseAmount"] as? NSNumber)?.stringValue,
              let releaseW = SafeABI.word(uint256: release), let reserved = SafeABI.word(uint256: intent.amount),
              releaseW.lexicographicallyPrecedes(reserved) || releaseW == reserved,
              releaseW != [UInt8](repeating: 0, count: 32),
              let dataHash = td["dataHash"] as? String, bytes32(dataHash) != nil,
              let signature = o["signature"] as? String, SafeABI.hexBytes(signature)?.count == 65,
              let signer = o["signer"] as? String, signer.lowercased() == attestationSigner,
              let details = o["encodedPaymentDetails"] as? String, SafeABI.hexBytes(details)?.isEmpty == false
        else { return nil }
        let metadata = (o["metadata"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "0x"
        guard SafeABI.hexBytes(metadata) != nil else { return nil }
        return Attestation(intentHash: hash.lowercased(), releaseAmount: release, dataHash: dataHash,
                           signature: signature, signer: signer, encodedPaymentDetails: details,
                           metadata: metadata)
    }

    static func paymentProof(_ a: Attestation) -> [UInt8]? {
        guard let hash = bytes32(a.intentHash), let release = SafeABI.word(uint256: a.releaseAmount),
              let dataHash = bytes32(a.dataHash), let sig = SafeABI.hexBytes(a.signature),
              let details = SafeABI.hexBytes(a.encodedPaymentDetails), let metadata = SafeABI.hexBytes(a.metadata)
        else { return nil }
        return Arg.encode([.tuple([.word(hash), .word(release), .word(dataHash),
                                   .array([.bytes(sig)]), .bytes(details), .bytes(metadata)])])
    }

    static func fulfillCalldata(_ a: Attestation) -> [UInt8]? {
        guard let proof = paymentProof(a), let hash = bytes32(a.intentHash),
              let signer = SafeABI.word(address: a.signer) else { return nil }
        let verification = Arg.encode([.tuple([.word(hash), .bytes(proof), .bytes(signer)])])
        return selector(fulfillSignature)
            + Arg.encode([.tuple([.bytes(proof), .word(hash), .bytes(verification), .bytes([])])])
    }

    // MARK: - ABI, as much as these two calls use

    indirect enum Arg {
        case word([UInt8])
        case bytes([UInt8])
        case array([Arg])
        case tuple([Arg])

        var isDynamic: Bool {
            switch self {
            case .word: return false
            case .bytes, .array: return true
            case .tuple(let items): return items.contains { $0.isDynamic }
            }
        }

        /// A static item's in-place encoding; a dynamic item's tail.
        var body: [UInt8] {
            switch self {
            case .word(let w): return w
            case .bytes(let b): return Self.length(b.count) + b + [UInt8](repeating: 0, count: (32 - b.count % 32) % 32)
            case .array(let items): return Self.length(items.count) + Self.encode(items)
            case .tuple(let items): return Self.encode(items)
            }
        }

        /// The head/tail encoding of a sequence of values, as a tuple's
        /// contents and a function's arguments are encoded.
        static func encode(_ items: [Arg]) -> [UInt8] {
            let headSize = items.reduce(0) { $0 + ($1.isDynamic ? 32 : $1.body.count) }
            var head: [UInt8] = [], tail: [UInt8] = []
            for item in items {
                if item.isDynamic {
                    head += length(headSize + tail.count)
                    tail += item.body
                } else {
                    head += item.body
                }
            }
            return head + tail
        }

        private static func length(_ n: Int) -> [UInt8] { SafeABI.word(uint: n) ?? [] }
    }

    static func selector(_ signature: String) -> [UInt8] {
        Array(Keccak256.hash(Array(signature.utf8)).prefix(4))
    }

    private static func bytes32(_ hex: String) -> [UInt8]? {
        guard let b = SafeABI.hexBytes(hex), b.count == 32 else { return nil }
        return b
    }
}
