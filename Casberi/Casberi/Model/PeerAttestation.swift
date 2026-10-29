import CryptoKit
import Foundation
import Security

/// The key Peer's enclave will read a payment app's session with, and the
/// proof that it IS the enclave's (prd §1598 item 2, docs/peer-spec.md
/// "Measured, 2026-10-28"). Deposit's proof runs in the app: the session a
/// person signs into in our web view is sealed to this key and only to it, so
/// everything here exists to refuse a key that is not provably inside Peer's
/// signed Nitro image.
///
/// The checks, in the order `@zkp2p/zkp2p-attestation` 3.1.0 makes them, but
/// stricter where it is loose:
///   1. the document is COSE_Sign1 with ES384 (`alg` -35) and a 96-byte r‖s;
///   2. `user_data` is our own fresh nonce;
///   3. the timestamp is within five minutes of now;
///   4. PCR8 — the hash of the certificate that signs Peer's enclave image —
///      equals the pin for THE host we asked, never one the service
///      advertises (the React Native SDK's Railway fallback accepts the
///      advertised one; we never do);
///   5. the chain runs from the leaf to AWS's Nitro root, which the app
///      carries and checks by fingerprint, in date at `now`;
///   6. the COSE signature verifies with the leaf's key;
///   7. `public_key` is an RSA key of at least 2048 bits.
///
/// Pure: `verify` takes the document, the nonce and the clock, so
/// `peer-attest-selftest.sh` runs it over a recorded document at that
/// document's own time. `fetch` is the one network door, DEBUG only until
/// Deposit ships (`-peerAttestProbe`).
enum PeerAttestation {

    static let host = "attestation-service.zkp2p.xyz"

    /// Peer's production pin, from `trust/pins.ts` in the published package,
    /// and the value the service advertised every time we asked (2026-10-28,
    /// 2026-10-29). A new image signed with a new certificate changes it, and
    /// then every check refuses until the app carries the new one: we fail
    /// closed rather than trust a measurement nobody told us about.
    static let pcr8Pin = hex("41a4ae0b9b96752cab5addb7d22689b3070e564e29f90a54316fa33fa38ea51387a6e887ea4f5a4b0cc34f69cea3f40e")!

    /// AWS's Nitro Enclaves root (CN=aws.nitro-enclaves, until 2049), fetched
    /// from AWS and compared with the fingerprint AWS publishes. The pin is
    /// checked again on every use so a mangled constant refuses, never trusts.
    static let awsRootSHA256 = "641a0321a3e244efe456463195d606317ed7cdcc3c1756e09893f3c68f79bb5b"
    static let awsRootDER = Data(base64Encoded: "MIICETCCAZagAwIBAgIRAPkxdWgbkK/hHUbMtOTn+FYwCgYIKoZIzj0EAwMwSTELMAkGA1UEBhMCVVMxDzANBgNVBAoMBkFtYXpvbjEMMAoGA1UECwwDQVdTMRswGQYDVQQDDBJhd3Mubml0cm8tZW5jbGF2ZXMwHhcNMTkxMDI4MTMyODA1WhcNNDkxMDI4MTQyODA1WjBJMQswCQYDVQQGEwJVUzEPMA0GA1UECgwGQW1hem9uMQwwCgYDVQQLDANBV1MxGzAZBgNVBAMMEmF3cy5uaXRyby1lbmNsYXZlczB2MBAGByqGSM49AgEGBSuBBAAiA2IABPwCVOumCMHzaHDimtqQvkY4MpJzbolL//Zy2YlES1BR5TSksfbb48C8WBoyt7F2Bw7eEtaaP+ohG2bnUs990d0JX28TcPQXCEPZ3BABIeTPYwEoCWZEh8l5YoQwTcU/9KNCMEAwDwYDVR0TAQH/BAUwAwEB/zAdBgNVHQ4EFgQUkCW1DdkFR+eWw5b6cp3PmanfS5YwDgYDVR0PAQH/BAQDAgGGMAoGCCqGSM49BAMDA2kAMGYCMQCjfy+Rocm9Xue4YnwWmNJVA44fA0P5W2OpYow9OYCVRaEevL8uO1XYru5xtMPWrfMCMQCi85sWBbJwKKXdS6BptQFuZbT73o/gBh1qUxl/nNr12UO8Yfwr6wPLb+6NIwLz3/Y=")!

    static let maxSkew: TimeInterval = 300

    /// The enclave's key, proven. `spki` is what the session is sealed to;
    /// `boundKeyHex` is what the sealed plaintext names, so the enclave can
    /// refuse a session sealed to anyone else.
    struct Key {
        let spki: Data
        let publicKey: SecKey
        let boundKeyHex: String
        let timestamp: Date
    }

    enum Failure: Error, Equatable {
        case malformed(String)
        case algorithm
        case nonce
        case stale
        case pcr8
        case root
        case chain
        case signature
        case key
        case unreachable
    }

    // MARK: - Verify

    static func verify(document: Data, nonce: String, now: Date,
                       pin: Data = pcr8Pin, root: Data = awsRootDER) throws -> Key {
        guard case .array(let sign1)? = try? PeerCBOR.decode(document), sign1.count == 4,
              case .bytes(let protected) = sign1[0],
              case .bytes(let payloadBytes) = sign1[2],
              case .bytes(let signature) = sign1[3]
        else { throw Failure.malformed("COSE_Sign1") }
        guard case .map(let header)? = try? PeerCBOR.decode(protected),
              header.value(.int(1)) == .int(-35), signature.count == 96
        else { throw Failure.algorithm }
        guard case .map(let payload)? = try? PeerCBOR.decode(payloadBytes) else {
            throw Failure.malformed("payload")
        }

        guard case .bytes(let userData)? = payload.value(.text("user_data")),
              userData == Data(nonce.utf8)
        else { throw Failure.nonce }

        guard case .int(let ms)? = payload.value(.text("timestamp")) else {
            throw Failure.malformed("timestamp")
        }
        let stamped = Date(timeIntervalSince1970: Double(ms) / 1000)
        guard abs(stamped.timeIntervalSince(now)) <= maxSkew else { throw Failure.stale }

        guard case .map(let pcrs)? = payload.value(.text("pcrs")),
              case .bytes(let pcr8)? = pcrs.value(.int(8)), pcr8 == pin
        else { throw Failure.pcr8 }

        guard hexString(SHA256.hash(data: root)) == awsRootSHA256 else { throw Failure.root }
        guard case .bytes(let leafDER)? = payload.value(.text("certificate")),
              case .array(let bundleItems)? = payload.value(.text("cabundle"))
        else { throw Failure.malformed("certificates") }
        let bundle = bundleItems.compactMap { item -> Data? in
            if case .bytes(let d) = item { return d } else { return nil }
        }
        guard bundle.count == bundleItems.count,
              let leaf = SecCertificateCreateWithData(nil, leafDER as CFData),
              chainVerifies(leaf: leaf, bundle: bundle, root: root, at: now)
        else { throw Failure.chain }

        let toSign = PeerCBOR.encodeArrayHead(4) + PeerCBOR.encodeText("Signature1")
            + PeerCBOR.encodeBytes(protected) + PeerCBOR.encodeBytes(Data()) + PeerCBOR.encodeBytes(payloadBytes)
        guard let leafKey = SecCertificateCopyKey(leaf),
              let x963 = SecKeyCopyExternalRepresentation(leafKey, nil) as Data?,
              let signer = try? P384.Signing.PublicKey(x963Representation: x963),
              let sig = try? P384.Signing.ECDSASignature(rawRepresentation: signature),
              signer.isValidSignature(sig, for: toSign)
        else { throw Failure.signature }

        guard case .bytes(let spki)? = payload.value(.text("public_key")),
              let publicKey = rsaPublicKey(spki: spki)
        else { throw Failure.key }

        return Key(spki: spki, publicKey: publicKey,
                   boundKeyHex: hexString(SHA256.hash(data: spki)),
                   timestamp: stamped)
    }

    /// The leaf chains to `root` through `bundle`, every certificate in date
    /// at `date`, and `root` is the ONLY anchor — the system's own roots are
    /// never consulted. `bundle` arrives root first; order does not matter to
    /// SecTrust, which builds the path itself.
    static func chainVerifies(leaf: SecCertificate, bundle: [Data], root: Data, at date: Date) -> Bool {
        guard let anchor = SecCertificateCreateWithData(nil, root as CFData) else { return false }
        let intermediates = bundle.compactMap { SecCertificateCreateWithData(nil, $0 as CFData) }
        guard intermediates.count == bundle.count else { return false }
        var trust: SecTrust?
        guard SecTrustCreateWithCertificates([leaf] + intermediates as CFArray,
                                             SecPolicyCreateBasicX509(), &trust) == errSecSuccess,
              let trust,
              SecTrustSetAnchorCertificates(trust, [anchor] as CFArray) == errSecSuccess,
              SecTrustSetAnchorCertificatesOnly(trust, true) == errSecSuccess,
              SecTrustSetVerifyDate(trust, date as CFDate) == errSecSuccess,
              SecTrustSetNetworkFetchAllowed(trust, false) == errSecSuccess
        else { return false }
        return SecTrustEvaluateWithError(trust, nil)
    }

    // MARK: - Fetch (DEBUG until Deposit ships)

    /// A fresh document for a fresh nonce, verified. Never cached: the leaf
    /// lives a few hours, and a key fetched for one proof is used for that
    /// proof alone. The host is fixed — there is no fallback to follow, which
    /// is the whole of the Railway lesson.
    static func fetch(now: @escaping () -> Date = Date.init) async throws -> Key {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw Failure.unreachable
        }
        let nonce = hexString(bytes)
        guard let root = await IngestSupport.getJSON("https://\(host)/attestation?nonce=\(nonce)",
                                                     headers: ["Accept": "application/json"]) as? [String: Any],
              let object = root["responseObject"] as? [String: Any],
              let encoded = object["attestationDocument"] as? String,
              let document = Data(base64Encoded: encoded)
        else { throw Failure.unreachable }
        guard object["nonce"] as? String == nonce else { throw Failure.nonce }
        return try verify(document: document, nonce: nonce, now: now())
    }

    // MARK: - Keys

    /// The enclave's SubjectPublicKeyInfo as a SecKey. Security takes an RSA
    /// public key as PKCS#1, so the SPKI's algorithm is checked
    /// (rsaEncryption, 1.2.840.113549.1.1.1) and its BIT STRING unwrapped.
    static func rsaPublicKey(spki: Data) -> SecKey? {
        var outer = PeerDER(spki)
        guard var info = outer.enter(0x30), outer.atEnd,
              var algorithm = info.enter(0x30),
              algorithm.take(0x06) == Data([0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01]),
              let bits = info.take(0x03), info.atEnd,
              bits.first == 0x00
        else { return nil }
        let attributes: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA,
                                           kSecAttrKeyClass: kSecAttrKeyClassPublic]
        guard let key = SecKeyCreateWithData(bits.dropFirst() as CFData, attributes as CFDictionary, nil),
              SecKeyGetBlockSize(key) >= 256
        else { return nil }
        return key
    }

    static func hexString<S: Sequence>(_ bytes: S) -> String where S.Element == UInt8 {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    static func hex(_ s: String) -> Data? {
        guard s.count % 2 == 0 else { return nil }
        var out = Data(capacity: s.count / 2)
        var i = s.startIndex
        while i < s.endIndex {
            let j = s.index(i, offsetBy: 2)
            guard let b = UInt8(s[i..<j], radix: 16) else { return nil }
            out.append(b)
            i = j
        }
        return out
    }
}

// MARK: - CBOR, as much as a Nitro document uses

/// RFC 8949, read: integers, byte and text strings, arrays, maps, tags
/// (skipped: COSE_Sign1 is tag 18), the three simple values, and
/// INDEFINITE lengths — the Nitro payload's map is indefinite (measured
/// 2026-10-28), which is what a first decoder gets wrong.
indirect enum PeerCBOR: Equatable {
    case int(Int64)
    case bytes(Data)
    case text(String)
    case array([PeerCBOR])
    case map([(PeerCBOR, PeerCBOR)])
    case bool(Bool)
    case null

    static func == (a: PeerCBOR, b: PeerCBOR) -> Bool {
        switch (a, b) {
        case let (.int(x), .int(y)): return x == y
        case let (.bytes(x), .bytes(y)): return x == y
        case let (.text(x), .text(y)): return x == y
        case let (.array(x), .array(y)): return x == y
        case let (.map(x), .map(y)):
            return x.count == y.count && zip(x, y).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
        case let (.bool(x), .bool(y)): return x == y
        case (.null, .null): return true
        default: return false
        }
    }

    struct Malformed: Error {}

    static func decode(_ data: Data) throws -> PeerCBOR {
        var reader = Reader(bytes: [UInt8](data))
        let value = try reader.item(depth: 0)
        guard reader.at == reader.bytes.count else { throw Malformed() }
        return value
    }

    private struct Reader {
        let bytes: [UInt8]
        var at = 0

        mutating func byte() throws -> UInt8 {
            guard at < bytes.count else { throw Malformed() }
            defer { at += 1 }
            return bytes[at]
        }

        mutating func take(_ n: Int) throws -> Data {
            guard n >= 0, at + n <= bytes.count else { throw Malformed() }
            defer { at += n }
            return Data(bytes[at..<at + n])
        }

        mutating func argument(_ info: UInt8) throws -> UInt64 {
            switch info {
            case 0..<24: return UInt64(info)
            case 24: return UInt64(try byte())
            case 25, 26, 27:
                var n: UInt64 = 0
                for _ in 0..<(1 << (info - 24)) { n = n << 8 | UInt64(try byte()) }
                return n
            default: throw Malformed()
            }
        }

        mutating func breakAhead() throws -> Bool {
            guard at < bytes.count else { throw Malformed() }
            if bytes[at] == 0xff { at += 1; return true }
            return false
        }

        mutating func item(depth: Int) throws -> PeerCBOR {
            guard depth < 32 else { throw Malformed() }
            let head = try byte()
            let major = head >> 5, info = head & 0x1f
            if info == 31 {
                switch major {
                case 2, 3:
                    var chunks = Data()
                    while try !breakAhead() {
                        switch try item(depth: depth + 1) {
                        case .bytes(let d) where major == 2: chunks += d
                        case .text(let s) where major == 3: chunks += Data(s.utf8)
                        default: throw Malformed()
                        }
                    }
                    if major == 2 { return .bytes(chunks) }
                    guard let s = String(data: chunks, encoding: .utf8) else { throw Malformed() }
                    return .text(s)
                case 4:
                    var out: [PeerCBOR] = []
                    while try !breakAhead() { out.append(try item(depth: depth + 1)) }
                    return .array(out)
                case 5:
                    var out: [(PeerCBOR, PeerCBOR)] = []
                    while try !breakAhead() {
                        out.append((try item(depth: depth + 1), try item(depth: depth + 1)))
                    }
                    return .map(out)
                default: throw Malformed()
                }
            }
            switch major {
            case 0:
                let n = try argument(info)
                guard n <= UInt64(Int64.max) else { throw Malformed() }
                return .int(Int64(n))
            case 1:
                let n = try argument(info)
                guard n <= UInt64(Int64.max) else { throw Malformed() }
                return .int(-1 - Int64(n))
            case 2: return .bytes(try take(Int(clamping: try argument(info))))
            case 3:
                guard let s = String(data: try take(Int(clamping: try argument(info))), encoding: .utf8) else {
                    throw Malformed()
                }
                return .text(s)
            case 4:
                let n = try argument(info)
                guard n <= UInt64(bytes.count) else { throw Malformed() }
                return .array(try (0..<n).map { _ in try item(depth: depth + 1) })
            case 5:
                let n = try argument(info)
                guard n <= UInt64(bytes.count) else { throw Malformed() }
                return .map(try (0..<n).map { _ in (try item(depth: depth + 1), try item(depth: depth + 1)) })
            case 6:
                _ = try argument(info)
                return try item(depth: depth + 1)
            default:
                switch info {
                case 20: return .bool(false)
                case 21: return .bool(true)
                case 22: return .null
                default: throw Malformed()
                }
            }
        }
    }

    // The three heads `Sig_structure1` needs, definite length only.
    static func encodeHead(_ major: UInt8, _ n: Int) -> Data {
        let m = major << 5
        switch n {
        case 0..<24: return Data([m | UInt8(n)])
        case 24..<0x100: return Data([m | 24, UInt8(n)])
        case 0x100..<0x10000: return Data([m | 25, UInt8(n >> 8), UInt8(n & 0xff)])
        default:
            return Data([m | 26, UInt8(n >> 24 & 0xff), UInt8(n >> 16 & 0xff),
                         UInt8(n >> 8 & 0xff), UInt8(n & 0xff)])
        }
    }
    static func encodeArrayHead(_ n: Int) -> Data { encodeHead(4, n) }
    static func encodeBytes(_ d: Data) -> Data { encodeHead(2, d.count) + d }
    static func encodeText(_ s: String) -> Data { encodeHead(3, s.utf8.count) + Data(s.utf8) }
}

private extension Array where Element == (PeerCBOR, PeerCBOR) {
    func value(_ key: PeerCBOR) -> PeerCBOR? { first { $0.0 == key }?.1 }
}

// MARK: - DER, as much as an SPKI uses

/// A cursor over DER: `take(tag)` returns the next element's contents if its
/// tag matches and moves past it; `enter(tag)` returns them as a cursor. Definite lengths only, as PeerDER requires.
struct PeerDER {
    private let bytes: [UInt8]
    private var at = 0
    init(_ data: Data) { bytes = [UInt8](data) }
    var atEnd: Bool { at == bytes.count }

    mutating func enter(_ tag: UInt8) -> PeerDER? { take(tag).map(PeerDER.init) }

    mutating func take(_ tag: UInt8) -> Data? {
        guard at + 2 <= bytes.count, bytes[at] == tag else { return nil }
        var i = at + 1
        var length = Int(bytes[i]); i += 1
        if length & 0x80 != 0 {
            let count = length & 0x7f
            guard (1...4).contains(count), i + count <= bytes.count else { return nil }
            length = bytes[i..<i + count].reduce(0) { $0 << 8 | Int($1) }
            i += count
        }
        guard i + length <= bytes.count else { return nil }
        defer { at = i + length }
        return Data(bytes[i..<i + length])
    }
}

