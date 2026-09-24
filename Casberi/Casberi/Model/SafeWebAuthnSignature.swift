import Foundation

/// The Secure Enclave owner's arithmetic — a P-256 key as a Safe owner
/// through Safe's own `SafeWebAuthnSignerFactory` (prd §913). Foundation-only
/// and pure; `scripts/safe-signer-selftest.sh` compiles it whole, and the
/// SHA-256 here is pinned to the FIPS vectors before anything trusts it.
///
/// **Why a Safe can take an Enclave key at all.** A Safe's `ecrecover` speaks
/// secp256k1 and the Enclave speaks P-256, which is why §425's key is raw
/// scalar bytes in a Keychain item rather than hardware. Safe's passkey
/// module closes that gap with a CONTRACT owner: a proxy deployed at an
/// address derived from the public key, whose `isValidSignature` verifies a
/// WebAuthn assertion. The Safe sees a contract signature (`v = 0`); the
/// contract sees `sha256(authenticatorData ‖ sha256(clientDataJSON))` signed
/// on P-256; the key never leaves the chip.
///
/// **This phone is its own authenticator.** No browser, no passkey API, no
/// relying party: `authenticatorData` and `clientDataFields` are built HERE
/// (WebAuthn.sol checks the flags byte and rebuilds the JSON from the
/// challenge; it verifies nothing about the rpIdHash or the origin), and the
/// Enclave signs the digest directly through the pre-hashed overload.
///
/// **The rail is stronger here than for the K1 key.** Before a signature
/// leaves, `SafeEnclaveSigner` asks the factory's own
/// `isValidSignatureForSigner(message, signature, x, y, verifiers)` and
/// requires the ERC-1271 magic value back — so the chain verifies the exact
/// bytes about to be posted, and every possible encoding mistake in this
/// file is a decline rather than a wrong signature.
enum SafeWebAuthn {

    /// `SafeWebAuthnSignerFactory` 0.2.1, deployed through Safe's singleton
    /// factory — one address on every chain it reached. Never TRUSTED: the
    /// signer reads code at it before offering the route, and reads the
    /// signer address back from the factory rather than deriving it (the
    /// derivation needs the proxy's creation code, which only the compiler
    /// has).
    static let factory = "0x1d31F259eE307358a26dFb23EB365939E8641195"
    /// RIP-7212's P-256 precompile, tried first where the chain has it.
    static let precompile = 0x100
    /// Daimo's audited Solidity verifier, the fallback everywhere else.
    static let fallbackVerifier = "0xc2b78104907F722DABAc4C69f826a522B2754De4"

    /// `P256.Verifiers`, a `uint176`: the precompile's two bytes above the
    /// fallback's twenty. As a full word for calldata.
    static var verifiersWord: [UInt8]? {
        guard var word = SafeABI.word(address: fallbackVerifier) else { return nil }
        word[10] = UInt8((precompile >> 8) & 0xFF)
        word[11] = UInt8(precompile & 0xFF)
        return word
    }

    static let rpID = "casberi.app"
    static let clientDataFields = "\"origin\":\"https://casberi.app\",\"crossOrigin\":false"
    /// ERC-1271's `isValidSignature(bytes32,bytes)` selector, the magic value.
    static let magicValue = "0x1626ba7e"

    /// `sha256(rpID) ‖ flags ‖ signCount`: 37 bytes, UP and UV set (0x05).
    /// The singleton demands `USER_VERIFICATION`; a Face ID IS one.
    static var authenticatorData: [UInt8] {
        SHA256Digest.hash(Array(rpID.utf8)) + [0x05] + [0, 0, 0, 0]
    }

    // MARK: - The message the key signs

    static func base64url(_ bytes: [UInt8]) -> String {
        Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Byte for byte what `WebAuthn.encodeClientDataJson` rebuilds on chain.
    static func clientDataJSON(challenge: [UInt8]) -> String {
        "{\"type\":\"webauthn.get\",\"challenge\":\"" + base64url(challenge) + "\"," + clientDataFields + "}"
    }

    /// `sha256(authenticatorData ‖ sha256(clientDataJSON))` — the 32 bytes the
    /// Enclave signs, pre-hashed, so nothing hashes them again.
    static func signingDigest(challenge: [UInt8]) -> [UInt8]? {
        guard challenge.count == 32 else { return nil }
        let clientHash = SHA256Digest.hash(Array(clientDataJSON(challenge: challenge).utf8))
        return SHA256Digest.hash(authenticatorData + clientHash)
    }

    // MARK: - The bytes the chain reads

    private static func dynamic(_ bytes: [UInt8]) -> [UInt8]? {
        guard let length = SafeABI.word(uint: bytes.count) else { return nil }
        let padding = (32 - bytes.count % 32) % 32
        return length + bytes + [UInt8](repeating: 0, count: padding)
    }

    /// `abi.encode(bytes authenticatorData, string clientDataFields, uint256 r, uint256 s)`.
    static func signatureBytes(r: [UInt8], s: [UInt8]) -> [UInt8]? {
        guard r.count == 32, s.count == 32,
              let auth = dynamic(authenticatorData),
              let fields = dynamic(Array(clientDataFields.utf8)),
              let authOffset = SafeABI.word(uint: 4 * 32),
              let fieldsOffset = SafeABI.word(uint: 4 * 32 + auth.count)
        else { return nil }
        return authOffset + fieldsOffset + r + s + auth + fields
    }

    /// Safe's envelope for a CONTRACT owner's signature: `r` is the owner,
    /// `s` the offset of the dynamic part (65, right after the static
    /// triple), `v` is 0, then `uint256 length ‖ data`.
    static func contractSignature(signer: String, data: [UInt8]) -> [UInt8]? {
        guard let owner = SafeABI.word(address: signer),
              let offset = SafeABI.word(uint: 65),
              let length = SafeABI.word(uint: data.count)
        else { return nil }
        return owner + offset + [0] + length + data
    }

    // MARK: - Calldata

    static func getSignerCalldata(x: [UInt8], y: [UInt8]) -> String? {
        guard x.count == 32, y.count == 32,
              let selector = SafeABI.hexBytes(SafeCalldata.selector("getSigner(uint256,uint256,uint176)")),
              let verifiers = verifiersWord
        else { return nil }
        return SafeABI.hex(selector + x + y + verifiers)
    }

    /// The rail: the factory verifies the exact signature without the proxy
    /// having to exist yet.
    static func isValidSignatureForSignerCalldata(message: [UInt8], signature: [UInt8],
                                                  x: [UInt8], y: [UInt8]) -> String? {
        guard message.count == 32, x.count == 32, y.count == 32,
              let selector = SafeABI.hexBytes(SafeCalldata.selector(
                "isValidSignatureForSigner(bytes32,bytes,uint256,uint256,uint176)")),
              let offset = SafeABI.word(uint: 5 * 32),
              let verifiers = verifiersWord,
              let tail = dynamic(signature)
        else { return nil }
        return SafeABI.hex(selector + message + offset + x + y + verifiers + tail)
    }

    /// The signer's address out of `getSigner`'s answer — one word, the
    /// address in its low twenty bytes and nothing above them.
    static func decodeAddress(_ hex: String) -> String? {
        guard let bytes = SafeABI.hexBytes(hex), bytes.count == 32,
              bytes.prefix(12).allSatisfy({ $0 == 0 }) else { return nil }
        return EIP55.checksum("0x" + Keccak256.hexString(Array(bytes.suffix(20))))
    }

    /// True when an `eth_call` answered with the ERC-1271 magic value in the
    /// high four bytes of one word.
    static func isMagic(_ hex: String) -> Bool {
        guard let bytes = SafeABI.hexBytes(hex), bytes.count >= 4 else { return false }
        return SafeABI.hex(Array(bytes.prefix(4))) == magicValue
    }

    // MARK: - P-256 low-s

    /// The P-256 group order and its floor half, big-endian (NIST).
    static let curveOrder: [UInt8] = [
        0xff, 0xff, 0xff, 0xff, 0x00, 0x00, 0x00, 0x00, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xbc, 0xe6, 0xfa, 0xad, 0xa7, 0x17, 0x9e, 0x84, 0xf3, 0xb9, 0xca, 0xc2, 0xfc, 0x63, 0x25, 0x51,
    ]
    static let curveHalfOrder: [UInt8] = [
        0x7f, 0xff, 0xff, 0xff, 0x80, 0x00, 0x00, 0x00, 0x7f, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xde, 0x73, 0x7d, 0x56, 0xd3, 0x8b, 0xcf, 0x42, 0x79, 0xdc, 0xe5, 0x61, 0x7e, 0x31, 0x92, 0xa8,
    ]

    /// `s` folded to `n - s` when it sits above `n / 2`. The verifier accepts
    /// either; folding keeps every signature this phone makes canonical.
    static func lowS(_ s: [UInt8]) -> [UInt8] {
        guard s.count == 32 else { return s }
        var high = false
        for i in 0..<32 where s[i] != curveHalfOrder[i] {
            high = s[i] > curveHalfOrder[i]
            break
        }
        guard high else { return s }
        var folded = [UInt8](repeating: 0, count: 32)
        var borrow = 0
        for i in stride(from: 31, through: 0, by: -1) {
            let diff = Int(curveOrder[i]) - Int(s[i]) - borrow
            folded[i] = UInt8((diff + 256) % 256)
            borrow = diff < 0 ? 1 : 0
        }
        return folded
    }
}

/// SHA-256 (FIPS 180-4), written here so the WebAuthn file stays
/// Foundation-only and the harness can compile it whole on any host. Pinned
/// to the three published vectors the harness checks first; a wrong digest
/// is caught there and, failing that, by the on-chain rail — which verifies
/// the finished signature and declines it.
enum SHA256Digest {
    private static let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ]

    private static func rotr(_ x: UInt32, _ n: UInt32) -> UInt32 { (x >> n) | (x << (32 - n)) }

    static func hash(_ message: [UInt8]) -> [UInt8] {
        var h: [UInt32] = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
                           0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
        var padded = message
        let bitLength = UInt64(message.count) * 8
        padded.append(0x80)
        while padded.count % 64 != 56 { padded.append(0) }
        for shift in stride(from: 56, through: 0, by: -8) {
            padded.append(UInt8((bitLength >> UInt64(shift)) & 0xFF))
        }
        var w = [UInt32](repeating: 0, count: 64)
        var offset = 0
        while offset < padded.count {
            for i in 0..<16 {
                let j = offset + i * 4
                w[i] = UInt32(padded[j]) << 24 | UInt32(padded[j + 1]) << 16
                     | UInt32(padded[j + 2]) << 8 | UInt32(padded[j + 3])
            }
            for i in 16..<64 {
                let s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3)
                let s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10)
                w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
            }
            var a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7]
            for i in 0..<64 {
                let s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
                let ch = (e & f) ^ (~e & g)
                let t1 = hh &+ s1 &+ ch &+ k[i] &+ w[i]
                let s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
                let maj = (a & b) ^ (a & c) ^ (b & c)
                let t2 = s0 &+ maj
                hh = g; g = f; f = e; e = d &+ t1; d = c; c = b; b = a; a = t1 &+ t2
            }
            h[0] = h[0] &+ a; h[1] = h[1] &+ b; h[2] = h[2] &+ c; h[3] = h[3] &+ d
            h[4] = h[4] &+ e; h[5] = h[5] &+ f; h[6] = h[6] &+ g; h[7] = h[7] &+ hh
            offset += 64
        }
        var out: [UInt8] = []
        out.reserveCapacity(32)
        for word in h {
            out.append(UInt8(word >> 24)); out.append(UInt8((word >> 16) & 0xFF))
            out.append(UInt8((word >> 8) & 0xFF)); out.append(UInt8(word & 0xFF))
        }
        return out
    }
}
