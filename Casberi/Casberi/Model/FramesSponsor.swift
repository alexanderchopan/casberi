import Foundation

/// ASKING SOMEBODY ELSE TO PAY (prd §728c) — the transaction shape, the request
/// one phone hands another, and the rules a sponsor's phone applies before it
/// will sign. Foundation-only BY DESIGN so `scripts/frames-tx-selftest.sh`
/// compiles it whole.
///
/// ## THE SHAPE, AND WHY THE SPONSOR IS CHOSEN FIRST
///
/// EIP-8141's "Canonical Paymaster / Basic Transaction" prefix: the sender's
/// VERIFY frame approves EXECUTION only (`flags 0x2`), then the sponsor's
/// VERIFY frame approves PAYMENT only (`flags 0x1`), then the payload. For an
/// ordinary account both are the default code, which checks a secp256k1
/// signature at a FIXED index — index 0 for execution, index 1 for payment —
/// whose signer is the frame's target. So `signatures` is always
/// `[sender, sponsor]`, both over the same canonical hash.
///
/// That hash commits to every frame, the sponsor's frame included, so **the
/// sponsor has to be named before the sender signs.** There is no "anyone may
/// pay" for an ordinary account: a request is addressed to one person.
///
/// **Proven by the node before this file was written** (2026-09-13): a
/// sponsored transfer under a deadline, built by an independent encoder and
/// signed by both keys, was refused with "Nonce mismatch", a check made only
/// after both signatures validate. The harness pins that preimage.
///
/// ## WHAT A SPONSOR CAN BE ASKED TO PAY FOR, AND WHAT IT CANNOT
///
/// **Coin transfers and ERC-20 `transfer` calls, and nothing else.** A request
/// carrying any other calldata is refused as malformed: the sponsor's phone
/// must be able to say in words what it is paying for, and a call it cannot
/// read is a request to sign blind. It also bounds the gas at stake.
extension FramesTransaction {
    static func sponsored(sender: Data,
                          sponsor: Data,
                          legs: [Leg],
                          atomic: Bool,
                          nonce: UInt64,
                          maxPriorityFeePerGas: UInt64,
                          maxFeePerGas: UInt64,
                          executionGas: UInt64 = 100_000,
                          stateGas: UInt64 = 250_000,
                          deadline: UInt64?) -> Fields {
        let last = legs.count - 1
        return Fields(
            chainID: chainID, nonce: nonce, sender: sender,
            frames: expiryPrefix(deadline)
                // The sender approves running as it — and nothing about paying.
                + [Frame(mode: 1, flags: 0x02, target: sender,
                         executionGas: executionGas, stateGas: 0,
                         value: Data(), data: Data()),
                   // The sponsor approves paying. **It carries the state
                   // budget**: approving payment for a sender that does not
                   // exist yet creates it, and EIP-8141 charges that creation
                   // to the frame approving payment. A sender with no coin is
                   // exactly who asks for a sponsor.
                   Frame(mode: 1, flags: 0x01, target: sponsor,
                         executionGas: executionGas, stateGas: stateGas,
                         value: Data(), data: Data())]
                + legs.enumerated().map { index, leg in
                    Frame(mode: 2, flags: atomic && index < last ? atomicFlag : 0x00,
                          target: leg.recipient,
                          executionGas: executionGas, stateGas: stateGas,
                          value: leg.value, data: leg.data)
                },
            signatures: [Signature(scheme: 1, signer: sender, msg: Data(), signature: Data()),
                         Signature(scheme: 1, signer: sponsor, msg: Data(), signature: Data())],
            maxPriorityFeePerGas: maxPriorityFeePerGas,
            maxFeePerGas: maxFeePerGas,
            maxFeePerBlobGas: 0,
            blobVersionedHashes: [])
    }

    /// **AN UPPER BOUND ON THE GAS THE PAYER IS CHARGED UP FRONT** — the
    /// quantity EIP-8141 debits at `APPROVE`, refunding what goes unused.
    ///
    /// Built to over-state, never under-state, because it is shown to a person
    /// as "at most": the larger of the two published intrinsic costs (15,000
    /// in ethrex's notes, 12,000 in the pinned EIP), every signature at its
    /// scheme's verification cost, every frame's two budgets, and the larger
    /// of the standard data cost and a 64-per-byte floor.
    static func maxGas(_ f: Fields) -> UInt64 {
        let intrinsic: UInt64 = 15_000 + 475 * UInt64(f.frames.count)
        let verification = f.signatures.reduce(UInt64(0)) { total, s in
            total + (s.scheme == 2 ? 6_700 : s.scheme == 1 ? 2_800 : 100)
        }
        var bytes: [Data] = f.frames.map(\.data)
        for s in f.signatures {
            bytes.append(s.signer)
            bytes.append(s.msg)
            bytes.append(Data(count: s.scheme == 2 ? 128 : 65))
        }
        let all = bytes.reduce(Data(), +)
        let standardData = all.reduce(UInt64(0)) { $0 + ($1 == 0 ? 4 : 16) }
        let floorData = UInt64(all.count) * 64
        let limits = f.frames.reduce(UInt64(0)) { $0 + $1.executionGas + $1.stateGas }
        return intrinsic + verification + max(standardData + limits, floorData)
    }
}

/// One request, as it travels from the sender's phone to the sponsor's.
///
/// **Parameters, not bytes.** The sponsor's phone rebuilds the transaction
/// with `FramesTransaction.sponsored` from these fields, so it can only ever be
/// asked to sign the shape above — never an arbitrary envelope that happens
/// to carry its address — and what it shows is derived from what it signs.
/// The price is a format version: a sender and sponsor on builds that disagree
/// about the shape produce a request the sponsor refuses as malformed rather
/// than a signature over something else.
struct FramesSponsorRequest: Codable, Equatable, Identifiable, Sendable {
    static let currentFormat = 1

    var format: Int
    var sender: String
    var sponsor: String
    var nonce: UInt64
    var deadline: UInt64
    var atomic: Bool
    var legs: [Leg]
    var maxPriorityFeePerGas: UInt64
    var maxFeePerGas: UInt64
    /// The sender's `v ‖ r ‖ s` over the canonical hash, as hex.
    var senderSignature: String

    struct Leg: Codable, Equatable, Sendable {
        /// The frame's target: the person for a coin leg, the contract for a
        /// token leg.
        var target: String
        /// Wei as minimal hex, "0x" for none.
        var value: String
        /// Calldata as hex, "0x" for none.
        var data: String

        enum CodingKeys: String, CodingKey { case target = "t", value = "v", data = "d" }
    }

    var id: String { "\(sender.lowercased()):\(nonce):\(deadline)" }

    /// Short keys, because the whole request rides in a link.
    enum CodingKeys: String, CodingKey {
        case format = "f", sender = "s", sponsor = "p", nonce = "n", deadline = "d",
             atomic = "a", legs = "l", maxPriorityFeePerGas = "tip", maxFeePerGas = "max",
             senderSignature = "sig"
    }
}

enum FramesSponsor {

    /// **THIRTY MINUTES, not a send's five.** A request crosses between two
    /// people by message, and somebody has to notice it and open it; five
    /// minutes would expire most of them in transit. The deadline is still in
    /// the transaction, so a request nobody paid for cannot be paid for later.
    static let requestWindow: TimeInterval = 30 * 60

    /// A batch a sponsor can read at a glance — the stitch sheet's own ceiling.
    static let maxLegs = 8

    // MARK: - The transaction

    /// Hex to bytes, where `"0x"` is EMPTY bytes rather than a failure —
    /// `RLP.data(fromHex:)` refuses an empty body, which is right for an address
    /// and wrong for a leg's value or calldata, where empty is the common case.
    static func bytes(_ hex: String) -> Data? {
        let body = hex.hasPrefix("0x") || hex.hasPrefix("0X") ? String(hex.dropFirst(2)) : hex
        return body.isEmpty ? Data() : RLP.data(fromHex: hex)
    }

    static func legs(_ request: FramesSponsorRequest) -> [FramesTransaction.Leg]? {
        guard !request.legs.isEmpty, request.legs.count <= maxLegs else { return nil }
        var out: [FramesTransaction.Leg] = []
        for leg in request.legs {
            guard let target = RLP.data(fromHex: leg.target), target.count == 20,
                  let value = bytes(leg.value),
                  let data = bytes(leg.data) else { return nil }
            // **ONLY WHAT A SPONSOR CAN READ** — a coin transfer, or an ERC-20
            // `transfer` with no coin beside it. See the type doc.
            if data.isEmpty {
                guard value.contains(where: { $0 != 0 }) else { return nil }
            } else {
                guard data.count == 68, data.starts(with: FramesTransaction.erc20TransferSelector),
                      data[4..<16].allSatisfy({ $0 == 0 }),
                      !value.contains(where: { $0 != 0 }) else { return nil }
            }
            out.append(FramesTransaction.Leg(recipient: target, value: RLP.minimal(value), data: data))
        }
        return out
    }

    /// The transaction a request describes, with the sender's signature in
    /// place and the sponsor's still empty. Nil for anything malformed.
    static func fields(_ request: FramesSponsorRequest) -> FramesTransaction.Fields? {
        guard request.format == FramesSponsorRequest.currentFormat,
              let sender = RLP.data(fromHex: request.sender), sender.count == 20,
              let sponsor = RLP.data(fromHex: request.sponsor), sponsor.count == 20,
              sender != sponsor,
              let legs = legs(request),
              let signature = RLP.data(fromHex: request.senderSignature), signature.count == 65
        else { return nil }
        var fields = FramesTransaction.sponsored(
            sender: sender, sponsor: sponsor, legs: legs, atomic: request.atomic,
            nonce: request.nonce,
            maxPriorityFeePerGas: request.maxPriorityFeePerGas,
            maxFeePerGas: request.maxFeePerGas,
            deadline: request.deadline)
        fields.signatures[0].signature = signature
        return fields
    }

    /// The request for `fields` once the sender has signed them.
    static func request(for fields: FramesTransaction.Fields, sponsor: Data, legs: [FramesTransaction.Leg],
                        atomic: Bool, deadline: UInt64, senderSignature: Data) -> FramesSponsorRequest {
        FramesSponsorRequest(
            format: FramesSponsorRequest.currentFormat,
            sender: "0x" + RLP.hex(fields.sender),
            sponsor: "0x" + RLP.hex(sponsor),
            nonce: fields.nonce,
            deadline: deadline,
            atomic: atomic,
            legs: legs.map { .init(target: "0x" + RLP.hex($0.recipient),
                                   value: "0x" + RLP.hex($0.value),
                                   data: "0x" + RLP.hex($0.data)) },
            maxPriorityFeePerGas: fields.maxPriorityFeePerGas,
            maxFeePerGas: fields.maxFeePerGas,
            senderSignature: "0x" + RLP.hex(senderSignature))
    }

    // MARK: - The link

    /// `casberi://frames/sponsor?r=<base64url JSON>`.
    static func link(_ request: FramesSponsorRequest) -> URL? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let json = try? encoder.encode(request) else { return nil }
        let token = json.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        var parts = URLComponents()
        parts.scheme = "casberi"
        parts.host = "frames"
        parts.path = "/sponsor"
        parts.queryItems = [URLQueryItem(name: "r", value: token)]
        return parts.url
    }

    /// The request inside a link, or nil for anything that is not one.
    static func request(from url: URL) -> FramesSponsorRequest? {
        guard url.scheme == "casberi", url.host() == "frames",
              url.path() == "/sponsor" || url.path() == "sponsor",
              let token = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "r" })?.value,
              token.count <= 8_000
        else { return nil }
        var base64 = token.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let json = Data(base64Encoded: base64),
              let request = try? JSONDecoder().decode(FramesSponsorRequest.self, from: json)
        else { return nil }
        return request
    }

    // MARK: - What the sponsor's phone refuses

    enum Refusal: Equatable, Sendable {
        case malformed
        case notForThisPhone
        case expired
        /// The sender has sent something else since asking, so this nonce can
        /// never be used again.
        case stale
    }

    /// **The order is the ruling.** Malformed first (nothing else can be said
    /// about a request that cannot be read), then whether it is this phone's
    /// to pay, then time, then the nonce — the one check that needs the chain,
    /// and nil there means "not read yet", which refuses nothing.
    static func refusal(_ request: FramesSponsorRequest, mine: String?, now: Date,
                        senderNonce: UInt64?) -> Refusal? {
        guard fields(request) != nil else { return .malformed }
        guard let mine, mine.caseInsensitiveCompare(request.sponsor) == .orderedSame
        else { return .notForThisPhone }
        if now.timeIntervalSince1970 > TimeInterval(request.deadline) { return .expired }
        if let senderNonce, senderNonce != request.nonce { return .stale }
        return nil
    }

    static func sentence(_ refusal: Refusal) -> String {
        switch refusal {
        case .malformed:
            return String(localized: "This request can't be read, so nothing here will pay for it.")
        case .notForThisPhone:
            return String(localized: "This request asks a different account to pay, not the one on this phone.")
        case .expired:
            return String(localized: "This request has passed its deadline and can't be paid for now.")
        case .stale:
            return String(localized: "They've sent something else since asking, so this request can't be used.")
        }
    }
}
