import Foundation

/// The Safe co-signer's arithmetic (prd §425, `docs/signer-spec.md`) — the
/// EIP-712 preimage of a Safe transaction, and the 65 bytes a signature is
/// serialized into. Foundation-only and pure by design, so
/// `scripts/safetx-selftest.sh` compiles this file WHOLE and unmodified and
/// pins the fixtures `scripts/support/safetx-vectors.py` derives.
///
/// **Why this file exists at all, given §5's cross-check.** Before signing,
/// `SafeSigner` asks the Safe contract itself for `getTransactionHash(...)`
/// and refuses on any disagreement — so a wrong constant here can never
/// produce a signature over the wrong transaction, only a decline. The local
/// encoder is what that remote answer is compared *against*: a lone number
/// handed back by whichever public RPC host answered is not evidence, and
/// signing it unchecked would make the co-signer trust the network for the
/// one value the whole feature rests on.
///
/// **The failure this guards is invisible.** A wrong domain separator, a
/// wrong type hash, a mispadded word or an INLINED `data` field all produce a
/// signature that is well-formed and recovers to a real address — it is
/// simply valid over a different transaction than the one previewed. No
/// build, screen sweep or UI test can see that, which is why the constants
/// below are computed rather than recalled and why every one of them is
/// mutation-tested.
///
/// Nothing here reaches the network, the Keychain or a curve. Key generation
/// and signing live in `SignerKey.swift`; the chain reads and the refusals
/// live in `SafeSigner.swift`.

// MARK: - Big-endian 32-byte words

/// The ABI word arithmetic SafeTx needs, and no more: `abi.encode` of a
/// SafeTx is only the STATIC head — ten 32-byte words, addresses
/// left-padded with twelve zero bytes, `uint8 operation` padded to a full
/// word like any other integer.
///
/// A uint256 does not fit in `UInt64` (1 ETH is 1e18, which does; 100 ETH is
/// 1e20, which does not), and Safe's transaction service sends `value` as a
/// DECIMAL STRING for exactly that reason. So the conversion is done by hand
/// on a 32-byte accumulator, and **an overflow REFUSES rather than wrapping**
/// — a wrapped amount is a number we would then ask somebody to approve.
enum SafeABI {

    /// One 32-byte word from a uint256 written as a decimal string, or as
    /// `0x`-prefixed hex. Nil for anything unparseable or wider than 256
    /// bits.
    ///
    /// Both spellings are accepted because both arrive: Safe's transaction
    /// service sends decimal, a pasted or deep-linked proposal (tier 0) may
    /// carry either, and the `eth_call` cross-check answers in hex.
    static func word(uint256 text: String) -> [UInt8]? {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if s.lowercased().hasPrefix("0x") {
            let body = String(s.dropFirst(2))
            guard !body.isEmpty, body.count <= 64, body.allSatisfy(\.isHexDigit),
                  let bytes = hexBytes(body.count % 2 == 0 ? body : "0" + body)
            else { return nil }
            return [UInt8](repeating: 0, count: 32 - bytes.count) + bytes
        }
        guard s.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        var acc = [UInt8](repeating: 0, count: 32)
        for ch in s {
            guard let digit = ch.wholeNumberValue else { return nil }
            // acc = acc * 10 + digit, big-endian, refusing on carry out of
            // the top byte rather than silently truncating to 256 bits.
            var carry = UInt32(digit)
            for i in stride(from: 31, through: 0, by: -1) {
                let product = UInt32(acc[i]) * 10 + carry
                acc[i] = UInt8(product & 0xFF)
                carry = product >> 8
            }
            if carry != 0 { return nil }
        }
        return acc
    }

    /// One 32-byte word from a small non-negative integer (`operation`, the
    /// nonce, a chain id). Negative refuses — there is no signed field in a
    /// SafeTx and a negative would encode as a colossal uint256.
    static func word(uint n: Int) -> [UInt8]? {
        guard n >= 0 else { return nil }
        var out = [UInt8](repeating: 0, count: 32)
        var v = UInt64(n)
        var i = 31
        while v > 0 { out[i] = UInt8(v & 0xFF); v >>= 8; i -= 1 }
        return out
    }

    /// One 32-byte word from a 20-byte address, left-padded with twelve zero
    /// bytes. Case-insensitive and `0x`-optional; nil for anything that is
    /// not exactly 40 hex digits — an ENS name, a Solana address, a typo.
    static func word(address: String) -> [UInt8]? {
        var a = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if a.lowercased().hasPrefix("0x") { a.removeFirst(2) }
        guard a.count == 40, a.allSatisfy(\.isHexDigit), let bytes = hexBytes(a)
        else { return nil }
        return [UInt8](repeating: 0, count: 12) + bytes
    }

    /// Raw bytes from a hex string, `0x`-optional. Nil on an odd length or a
    /// non-hex digit — never a partial read, since a silently truncated
    /// calldata hashes to a plausible wrong word.
    static func hexBytes(_ hex: String) -> [UInt8]? {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.lowercased().hasPrefix("0x") { s.removeFirst(2) }
        if s.isEmpty { return [] }
        guard s.count % 2 == 0 else { return nil }
        var out = [UInt8]()
        out.reserveCapacity(s.count / 2)
        var index = s.startIndex
        while index < s.endIndex {
            let next = s.index(index, offsetBy: 2)
            guard let byte = UInt8(s[index..<next], radix: 16) else { return nil }
            out.append(byte)
            index = next
        }
        return out
    }

    /// Lowercase hex, `0x`-prefixed — the form every wire here speaks.
    static func hex(_ bytes: [UInt8]) -> String {
        "0x" + Keccak256.hexString(bytes)
    }
}

// MARK: - The transaction

/// The ten fields a Safe signs over, exactly as `execTransaction` takes them.
///
/// Amounts are held as STRINGS rather than numbers on purpose: they are
/// uint256 on the wire, `Double` loses precision above 2^53 (a wei figure
/// crosses that at 0.009 ETH), and the encoder above is the only thing that
/// should be deciding whether a value fits.
struct SafeTransaction: Equatable {
    let to: String
    /// uint256, decimal or `0x`-hex.
    let value: String
    /// Calldata, hex, possibly empty.
    let data: String
    /// 0 = CALL, 1 = DELEGATECALL. Never inferred — see `SafeCalldata`.
    let operation: Int
    let safeTxGas: String
    let baseGas: String
    let gasPrice: String
    let gasToken: String
    let refundReceiver: String
    let nonce: Int

    static let zeroAddress = "0x0000000000000000000000000000000000000000"

    init(to: String, value: String, data: String, operation: Int,
         safeTxGas: String = "0", baseGas: String = "0", gasPrice: String = "0",
         gasToken: String = SafeTransaction.zeroAddress,
         refundReceiver: String = SafeTransaction.zeroAddress,
         nonce: Int) {
        self.to = to
        self.value = value
        self.data = data
        self.operation = operation
        self.safeTxGas = safeTxGas
        self.baseGas = baseGas
        self.gasPrice = gasPrice
        self.gasToken = gasToken
        self.refundReceiver = refundReceiver
        self.nonce = nonce
    }
}

// MARK: - The hash

enum SafeTxEncoder {

    /// `keccak256("EIP712Domain(uint256 chainId,address verifyingContract)")`
    /// — Safe >= 1.3.0. Computed from the type string, never pasted, so a
    /// mistyped constant is impossible rather than merely unlikely.
    static let domainTypeString = "EIP712Domain(uint256 chainId,address verifyingContract)"

    /// The ten-field SafeTx type, verbatim from Safe's own contract source.
    static let safeTxTypeString =
        "SafeTx(address to,uint256 value,bytes data,uint8 operation,"
        + "uint256 safeTxGas,uint256 baseGas,uint256 gasPrice,address gasToken,"
        + "address refundReceiver,uint256 nonce)"

    /// Safe < 1.3.0's domain — `(address verifyingContract)` alone, with no
    /// chainId. Held here for ONE reason: so `docs/signer-spec.md` §3's claim
    /// that an old Safe is refused rather than mis-signed has a name in the
    /// code. Nothing signs against it. The refusal itself is free and
    /// automatic — an old Safe's own `getTransactionHash` disagrees with the
    /// modern separator, and §5's cross-check declines — so there is
    /// deliberately no version table here to maintain.
    static let legacyDomainTypeString = "EIP712Domain(address verifyingContract)"

    static var domainTypeHash: [UInt8] { Keccak256.hash(Array(domainTypeString.utf8)) }
    static var safeTxTypeHash: [UInt8] { Keccak256.hash(Array(safeTxTypeString.utf8)) }
    static var legacyDomainTypeHash: [UInt8] { Keccak256.hash(Array(legacyDomainTypeString.utf8)) }

    /// `keccak256(abi.encode(DOMAIN_TYPEHASH, chainId, verifyingContract))`.
    static func domainSeparator(chainId: Int, safe: String) -> [UInt8]? {
        guard let chain = SafeABI.word(uint: chainId),
              let verifying = SafeABI.word(address: safe) else { return nil }
        return Keccak256.hash(domainTypeHash + chain + verifying)
    }

    /// `keccak256(abi.encode(SAFE_TX_TYPEHASH, …))`.
    ///
    /// **`data` is a dynamic `bytes`, so its KECCAK goes in the word, never
    /// the bytes themselves.** Inlining it is the classic way to produce a
    /// plausible wrong hash: the result is still 32 bytes, still hashes, and
    /// is wrong for every transaction that carries calldata — i.e. every
    /// token transfer, which is most of them.
    static func structHash(_ tx: SafeTransaction) -> [UInt8]? {
        guard let to = SafeABI.word(address: tx.to),
              let value = SafeABI.word(uint256: tx.value),
              let dataBytes = SafeABI.hexBytes(tx.data),
              let operation = SafeABI.word(uint: tx.operation),
              let safeTxGas = SafeABI.word(uint256: tx.safeTxGas),
              let baseGas = SafeABI.word(uint256: tx.baseGas),
              let gasPrice = SafeABI.word(uint256: tx.gasPrice),
              let gasToken = SafeABI.word(address: tx.gasToken),
              let refundReceiver = SafeABI.word(address: tx.refundReceiver),
              let nonce = SafeABI.word(uint: tx.nonce)
        else { return nil }
        let dataHash = Keccak256.hash(dataBytes)
        return Keccak256.hash(
            safeTxTypeHash + to + value + dataHash + operation
            + safeTxGas + baseGas + gasPrice + gasToken + refundReceiver + nonce)
    }

    /// `keccak256(0x19 ‖ 0x01 ‖ domainSeparator ‖ structHash)` — the 32 bytes
    /// a Safe owner signs. Nil when any field failed to encode, which is a
    /// decline, never a guess.
    static func safeTxHash(chainId: Int, safe: String, tx: SafeTransaction) -> [UInt8]? {
        guard let separator = domainSeparator(chainId: chainId, safe: safe),
              let structure = structHash(tx) else { return nil }
        return Keccak256.hash([0x19, 0x01] + separator + structure)
    }
}

// MARK: - Asking the Safe itself

/// The calldata for the reads §5's rail makes on the Safe contract. Kept here
/// beside the encoder they check, and pure, so `scripts/safetx-selftest.sh`
/// pins them.
///
/// **`getTransactionHash` is a FULL abi.encode, not the static head.** The
/// struct hash above encodes `data` as its keccak, which is one word; a
/// contract CALL has to send the bytes themselves, so the head carries an
/// OFFSET and the tail carries length-then-padded-data. Getting that wrong
/// does not produce a wrong answer — the node reverts, the rail reads as a
/// network failure, and the co-signer refuses every transaction forever while
/// looking like it is offline. That is the failure this file's tests exist to
/// make impossible.
enum SafeCall {

    static var getTransactionHashSelector: String {
        SafeCalldata.selector(
            "getTransactionHash(address,uint256,bytes,uint8,uint256,uint256,uint256,address,address,uint256)")
    }
    static var getOwnersSelector: String { SafeCalldata.selector("getOwners()") }
    static var getThresholdSelector: String { SafeCalldata.selector("getThreshold()") }
    static var nonceSelector: String { SafeCalldata.selector("nonce()") }

    /// `getTransactionHash(...)` over the same ten fields the local encoder
    /// hashed. Nil when any field fails to encode — the same decline.
    static func getTransactionHash(_ tx: SafeTransaction) -> String? {
        guard let to = SafeABI.word(address: tx.to),
              let value = SafeABI.word(uint256: tx.value),
              let dataBytes = SafeABI.hexBytes(tx.data),
              let operation = SafeABI.word(uint: tx.operation),
              let safeTxGas = SafeABI.word(uint256: tx.safeTxGas),
              let baseGas = SafeABI.word(uint256: tx.baseGas),
              let gasPrice = SafeABI.word(uint256: tx.gasPrice),
              let gasToken = SafeABI.word(address: tx.gasToken),
              let refundReceiver = SafeABI.word(address: tx.refundReceiver),
              let nonce = SafeABI.word(uint: tx.nonce),
              // Ten words of head; `data`'s offset is measured from the start
              // of the argument block, i.e. AFTER the four-byte selector.
              let offset = SafeABI.word(uint: 10 * 32),
              let length = SafeABI.word(uint: dataBytes.count),
              let selector = SafeABI.hexBytes(getTransactionHashSelector)
        else { return nil }
        let padding = (32 - dataBytes.count % 32) % 32
        let tail = length + dataBytes + [UInt8](repeating: 0, count: padding)
        return SafeABI.hex(selector + to + value + offset + operation
                           + safeTxGas + baseGas + gasPrice + gasToken + refundReceiver
                           + nonce + tail)
    }

    /// The `address[]` an `eth_call` to `getOwners()` answers with, lowercased
    /// for comparison. Nil — never an empty list — when the answer does not
    /// decode: an empty owner set would read as "you are not an owner", which
    /// is the same refusal a real answer gives, so the two must not be
    /// confused. A Safe always has at least one owner.
    static func decodeAddressArray(_ hex: String) -> [String]? {
        guard let bytes = SafeABI.hexBytes(hex), bytes.count >= 64 else { return nil }
        // head: one word of offset. Anything other than 0x20 is a shape this
        // decoder does not claim to read.
        let offsetWord = Array(bytes[0..<32])
        guard offsetWord.prefix(31).allSatisfy({ $0 == 0 }), offsetWord[31] == 32 else { return nil }
        let countWord = Array(bytes[32..<64])
        guard countWord.prefix(30).allSatisfy({ $0 == 0 }) else { return nil }
        let count = Int(countWord[30]) << 8 | Int(countWord[31])
        guard bytes.count >= 64 + count * 32 else { return nil }
        var out: [String] = []
        for i in 0..<count {
            let start = 64 + i * 32
            let word = Array(bytes[start..<(start + 32)])
            guard word.prefix(12).allSatisfy({ $0 == 0 }) else { return nil }
            out.append(SafeABI.hex(Array(word.suffix(20))))
        }
        return out
    }

    /// A single uint256 answer (`getThreshold`, `nonce`) as an Int. Nil when
    /// the answer is malformed OR larger than an Int can hold — a threshold we
    /// cannot read is a threshold we must not compare against 2.
    ///
    /// **Accumulated in `UInt64` and range-checked, not shifted into an
    /// `Int`.** The obvious `value = value << 8 | Int(byte)` over eight bytes
    /// TRAPS in Swift the moment the top bit of the eighth byte is set — so a
    /// Safe (or an RPC host, or a spoofed contract) answering `getThreshold()`
    /// with a large word crashed the app rather than returning nil. Caught by
    /// reading, not by a test: the harness's own "absurdly large answer"
    /// fixture had a non-zero HIGH word, so it was rejected by the guard above
    /// and never reached the loop — a fixture that passed for the wrong
    /// reason, third time in this session.
    static func decodeUInt(_ hex: String) -> Int? {
        guard let bytes = SafeABI.hexBytes(hex), bytes.count == 32,
              bytes.prefix(24).allSatisfy({ $0 == 0 }) else { return nil }
        var value: UInt64 = 0
        for byte in bytes.suffix(8) { value = value << 8 | UInt64(byte) }
        guard value <= UInt64(Int.max) else { return nil }
        return Int(value)
    }
}

// MARK: - The signature's 65 bytes

/// Serializing one owner's signature for Safe's `signatures` blob.
///
/// **`v` is a discriminator, not just a parity bit**, and getting it wrong is
/// the difference between a signature that verifies and one that recovers a
/// stranger. Safe reads it as:
///
///   * `0`  — a contract (EIP-1271) signature
///   * `1`  — a pre-approved hash
///   * `> 30` — `eth_sign`, i.e. verify against the hash wrapped in
///     `"\x19Ethereum Signed Message:\n32"`
///   * `27` / `28` — a plain EIP-712 signature over the hash itself
///
/// Casberi signs the `safeTxHash` DIRECTLY, so 27/28 is the only correct
/// answer. Emitting 31/32 makes the Safe verify against a *prefixed* hash and
/// recover the wrong address — a well-formed signature that silently fails,
/// or worse, attributes to somebody else.
enum SafeSignature {

    /// secp256k1's half order. A signature with `s` above this is malleable:
    /// `(r, n − s)` is an equally valid signature over the same message, so
    /// the same approval exists twice under two different byte strings.
    /// libsecp256k1 normalizes by default — this asserts it rather than
    /// trusting it, because a default is a thing that can change.
    static let halfOrder: [UInt8] = [
        0x7f, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0x5d, 0x57, 0x6e, 0x73, 0x57, 0xa4, 0x50, 0x1d,
        0xdf, 0xe9, 0x2f, 0x46, 0x68, 0x1b, 0x20, 0xa0,
    ]

    /// True when `s` (32 big-endian bytes) is at or below the half order.
    static func isLowS(_ s: [UInt8]) -> Bool {
        guard s.count == 32 else { return false }
        for (a, b) in zip(s, halfOrder) {
            if a != b { return a < b }
        }
        return true
    }

    /// `r ‖ s ‖ v` from libsecp256k1's 64-byte compact form and its recovery
    /// id. Nil — a refusal to hand out bytes at all — when:
    ///
    ///   * the compact form is not 64 bytes;
    ///   * the recovery id is not 0 or 1 (2 and 3 exist in the curve but
    ///     never occur in practice, and Ethereum's `v` has nowhere to put
    ///     them, so emitting 29/30 would be a signature no Safe can read);
    ///   * `s` is high (see `isLowS`).
    static func serialize(compact: [UInt8], recoveryId: Int) -> [UInt8]? {
        guard compact.count == 64, recoveryId == 0 || recoveryId == 1 else { return nil }
        let s = Array(compact[32..<64])
        guard isLowS(s) else { return nil }
        return compact + [UInt8(27 + recoveryId)]
    }
}

// MARK: - What the calldata says

/// A plain-words reading of a Safe transaction's own calldata (spec §8.5).
///
/// It reads the RAW bytes rather than the transaction service's `dataDecoded`
/// — a decode handed to us by a service is a claim about the transaction we
/// are being asked to authorize, made by a party that is not the chain.
/// `SafeBridge.describe` still uses `dataDecoded` for FEED rows, which is the
/// right trade there; on the signing screen it is not.
///
/// **The refusal is the point.** An unrecognised selector returns
/// `.undecoded`, and the surface must then show the selector and the calldata
/// hash and say plainly that it could not read it (§83, in the one place a
/// fluent wrong summary costs real money). A decoder that guesses is worse
/// than no decoder.
enum SafeCalldata: Equatable {
    /// No calldata at all — a plain native-coin send.
    case send
    /// Safe's own reject shape: zero value, no data, addressed to the Safe
    /// itself, proposed only to burn a nonce.
    case rejection
    case erc20Transfer(recipient: String, amount: String)
    case erc20Approve(spender: String, amount: String)
    case erc20TransferFrom(from: String, recipient: String, amount: String)
    case addOwner(owner: String, threshold: String)
    case removeOwner(owner: String)
    case swapOwner(old: String, new: String)
    case changeThreshold(threshold: String)
    case enableModule(module: String)
    case setGuard(guardAddress: String)
    /// A batch. Deliberately NOT itemised: `multiSend`'s payload is a packed
    /// concatenation of sub-calls, and half-decoding a batch is exactly the
    /// fluent-wrong-summary this enum exists to refuse.
    case batch
    /// The selector is real, the meaning is not known. Carries the four bytes
    /// so the surface can show them.
    case undecoded(selector: String)

    /// The four-byte selectors, DERIVED from their signatures at first use
    /// rather than pasted as magic hex — the same rule
    /// `scripts/support/safetx-vectors.py` follows for the type hashes, and
    /// for the same reason: a mistyped constant here names a different
    /// function and the reading would be confidently wrong.
    static func selector(_ signature: String) -> String {
        SafeABI.hex(Array(Keccak256.hash(Array(signature.utf8)).prefix(4)))
    }

    /// Reads `data`. `to`/`value`/`safe` are needed only to recognise the
    /// rejection shape, which is defined by its destination rather than its
    /// (absent) calldata.
    static func read(data: String, to: String, value: String, safe: String) -> SafeCalldata {
        let bytes = SafeABI.hexBytes(data) ?? []
        let isZeroValue = (SafeABI.word(uint256: value) ?? [1]).allSatisfy { $0 == 0 }
        if bytes.isEmpty {
            if isZeroValue, to.lowercased() == safe.lowercased() { return .rejection }
            return .send
        }
        guard bytes.count >= 4 else { return .undecoded(selector: SafeABI.hex(bytes)) }
        let sel = SafeABI.hex(Array(bytes.prefix(4)))
        let args = Array(bytes.dropFirst(4))

        func address(_ index: Int) -> String? {
            let start = index * 32
            guard args.count >= start + 32 else { return nil }
            let word = Array(args[start..<(start + 32)])
            guard word.prefix(12).allSatisfy({ $0 == 0 }) else { return nil }
            return EIP55.checksum(SafeABI.hex(Array(word.suffix(20))))
        }
        func number(_ index: Int) -> String? {
            let start = index * 32
            guard args.count >= start + 32 else { return nil }
            return decimal(Array(args[start..<(start + 32)]))
        }

        switch sel {
        case selector("transfer(address,uint256)"):
            if let a = address(0), let n = number(1) { return .erc20Transfer(recipient: a, amount: n) }
        case selector("approve(address,uint256)"):
            if let a = address(0), let n = number(1) { return .erc20Approve(spender: a, amount: n) }
        case selector("transferFrom(address,address,uint256)"):
            if let f = address(0), let a = address(1), let n = number(2) {
                return .erc20TransferFrom(from: f, recipient: a, amount: n)
            }
        case selector("addOwnerWithThreshold(address,uint256)"):
            if let a = address(0), let n = number(1) { return .addOwner(owner: a, threshold: n) }
        case selector("removeOwner(address,address,uint256)"):
            // (prevOwner, owner, threshold) — the owner being removed is the
            // SECOND argument; the first is a linked-list cursor Safe needs
            // and a person does not.
            if let a = address(1) { return .removeOwner(owner: a) }
        case selector("swapOwner(address,address,address)"):
            if let old = address(1), let new = address(2) { return .swapOwner(old: old, new: new) }
        case selector("changeThreshold(uint256)"):
            if let n = number(0) { return .changeThreshold(threshold: n) }
        case selector("enableModule(address)"):
            if let a = address(0) { return .enableModule(module: a) }
        case selector("setGuard(address)"):
            if let a = address(0) { return .setGuard(guardAddress: a) }
        case selector("multiSend(bytes)"):
            return .batch
        default:
            break
        }
        // A KNOWN selector whose arguments did not read is still undecoded —
        // a truncated `transfer` must not be summarised as a transfer of an
        // amount we had to invent.
        return .undecoded(selector: sel)
    }

    /// A 32-byte word as a decimal string. Long division by 10 on the bytes,
    /// because uint256 has no Swift integer to land in.
    static func decimal(_ word: [UInt8]) -> String {
        var digits = word
        var out = ""
        while digits.contains(where: { $0 != 0 }) {
            var remainder = 0
            for i in digits.indices {
                let current = remainder * 256 + Int(digits[i])
                digits[i] = UInt8(current / 10)
                remainder = current % 10
            }
            out = String(remainder) + out
        }
        return out.isEmpty ? "0" : out
    }

    /// Whether this reading is one the surface may state as fact. False for
    /// `.undecoded`, which must be shown as a selector and a hash instead.
    var isDecoded: Bool {
        if case .undecoded = self { return false }
        return true
    }
}
