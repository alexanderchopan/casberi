import CryptoKit
import Foundation

/// A request to sign for an Aztec TESTNET account, read and checked before
/// anyone is asked (2026-10-11, user: "lets do as much as we can including
/// even signing", then "we can't yet create an account that can move funds
/// and i don't think we can create our own contract", then "Testnet only").
/// Foundation + CryptoKit, pure, so `scripts/aztec-sign-selftest.sh`
/// compiles it whole.
///
/// **Who does what.** A computer runs the account (Aztec's own
/// `EcdsaRAccount`, never a contract of ours) and its PXE — the private
/// execution, the proof, the send; Aztec has no Swift client. When the
/// account must authorise a transaction, the computer hands this phone the
/// REQUEST — the calls, the nonce, the chain, the account and the hash it
/// wants signed — as `casberi://aztec/sign#<base64url JSON>`. The phone holds
/// the only key the account accepts, in the Secure Enclave.
///
/// **No blind signing.** The phone rebuilds the hash from the calls itself
/// (`AztecPoseidon2`, the recipe measured off aztec.js and a mined
/// transaction) and refuses a request whose hash does not match: what the
/// sheet shows is what the signature commits to. A function's NAME is not
/// in the hash, its SELECTOR is: when the computer also sends the call's
/// signature (`mint_to_public((Field),u128)`), the phone derives the
/// selector from it (`selector(of:)`, Aztec's `FunctionSelector
/// .fromSignature`) and refuses a request whose name does not match what it
/// runs (prd §1446). Without one the name stays the computer's word.
///
/// **Testnet only, enforced here.** A request on any chain but Sepolia, or on
/// a rollup that is not one of Aztec's testnets, is refused before the sheet
/// can offer Face ID. Test money has no value, Logos' Send precedent (prd
/// §1084); nothing here can authorise real funds.
enum AztecSignRequest {

    struct Call: Codable, Equatable {
        let name: String
        /// The call's full signature, when the computer sends it; checked
        /// against `selector` before anything is drawn (prd §1446).
        var signature: String? = nil
        let to: String
        let selector: String
        let type: String
        let hideMsgSender: Bool
        let isStatic: Bool
        let args: [String]
    }

    struct Request: Codable, Equatable {
        let account: String
        let chainId: String
        let version: String
        let txNonce: String
        let messageHash: String
        let calls: [Call]
    }

    /// The only chains a request may name: Sepolia (11155111), and the
    /// rollup versions of Aztec's testnets whose nodes still answer — v6
    /// (6.0.0, `aztec-testnet.drpc.org`) and v5 (5.0.0,
    /// `v5.testnet.rpc.aztec-labs.com`), both read 2026-10-26 and both in the
    /// testnet Registry on Sepolia (prd §1565). v6's release candidates
    /// (2914217885, 3409706519) are dropped: no node answers them.
    static let l1ChainID = 11_155_111
    static let testnetRollups: [Int: String] = [679_261_766: "Aztec testnet (v6)",
                                                1_821_665_230: "Aztec testnet (v5)"]

    /// Aztec mainnet's rollup version: refused even if a node calls it a
    /// testnet (a lie, or a misconfigured host), because it is real money.
    ///
    /// Every version mainnet's Registry lists: the first Alpha rollup, Alpha
    /// V5, and V6, the rollup governance proposal 5 ("V6UpgradePayload")
    /// added (`getVersion()` on 0xe37a…402f, read 2026-10-20, prd §1446; V6
    /// is canonical since, and the Registry's four versions were read again
    /// 2026-10-26, prd §1565).
    static let mainnetRollups: Set<Int> = [4_248_422_647, 2_070_860_440, 2_934_756_905]

    /// What Aztec's testnet node reports right now (`node_getNodeInfo`,
    /// 2026-10-18, prd §1419): the testnet is reset onto a new rollup version
    /// several times a season (rc.3 moved it to 3409706519 between two
    /// sessions), and a fixed list refused every request after each one.
    struct LiveTestnet: Equatable {
        let rollupVersion: Int
        let l1ChainID: Int
    }

    // MARK: - The link

    static let scheme = "casberi"
    static let host = "aztec"
    static let path = "/sign"
    /// What the phone hands back: the computer's tool waits for this prefix.
    static let signaturePrefix = "casberi-aztec-sig:"

    static func link(_ request: Request) -> String? {
        guard let json = try? JSONEncoder().encode(request) else { return nil }
        let b64 = json.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "\(scheme)://\(host)\(path)#\(b64)"
    }

    static func request(fromLink raw: String) -> Request? {
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == scheme, url.host()?.lowercased() == host,
              url.path() == path, let fragment = url.fragment, fragment.count <= 16_384 else { return nil }
        var b64 = fragment.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64) else { return nil }
        return try? JSONDecoder().decode(Request.self, from: data)
    }

    // MARK: - The check

    enum Verdict: Equatable {
        case sign(network: String)
        case refused(String)
    }

    /// Whether this request may be offered for signing: on an Aztec testnet,
    /// at most five calls (the entrypoint's limit), and its hash rebuilt from
    /// its own calls equals the hash it asks for.
    static func check(_ r: Request, live: LiveTestnet? = nil) -> Verdict {
        guard int(r.chainId) == l1ChainID else {
            return .refused("This request is not for an Aztec testnet. Casberi signs for test money only.")
        }
        guard let version = int(r.version), !mainnetRollups.contains(version),
              let network = testnetRollups[version]
                ?? live.flatMap({ $0.rollupVersion == version && $0.l1ChainID == l1ChainID ? "Aztec testnet" : nil })
        else {
            return .refused("This request names a rollup that is not one of Aztec's testnets.")
        }
        guard !r.calls.isEmpty, r.calls.count <= 5 else {
            return .refused("A request carries one to five calls.")
        }
        let values = [r.account, r.chainId, r.version, r.txNonce] + r.calls.flatMap { [$0.to, $0.selector] + $0.args }
        guard values.allSatisfy({ AztecPoseidon2.field($0).map(AztecPoseidon2.isCanonical) == true }) else {
            return .refused("This request carries a value that is not a valid Aztec field. Nothing was signed.")
        }
        guard let rebuilt = outerHash(r), rebuilt == normalized(r.messageHash) else {
            return .refused("The calls do not match the hash this request asks to sign. Nothing was signed.")
        }
        guard r.calls.allSatisfy({ $0.signature == nil || nameChecked($0) }) else {
            return .refused("A call's name does not match the function it runs. Nothing was signed.")
        }
        return .sign(network: network)
    }

    // MARK: - The name, checked

    /// Aztec's `FunctionSelector.fromSignature`: the signature's bytes packed
    /// 31 to a field, each chunk zero-padded and read little-endian, then
    /// `poseidon2Hash`, and the selector is its last four bytes. MEASURED
    /// 2026-10-20 against a mined request: `sponsor_unconditionally()` →
    /// 0x23d77f89, `mint_to_public((Field),u128)` → 0x451b5fae.
    static func selector(of signature: String) -> UInt32? {
        guard !signature.isEmpty, !signature.contains(where: \.isWhitespace) else { return nil }
        let bytes = [UInt8](signature.utf8)
        var fields: [Data] = []
        var i = 0
        while i < bytes.count {
            var chunk = [UInt8](repeating: 0, count: 32)
            for (k, b) in bytes[i..<min(i + 31, bytes.count)].enumerated() { chunk[k] = b }
            fields.append(Data(chunk.reversed()))
            i += 31
        }
        return AztecPoseidon2.hash(fields).suffix(4).reduce(0) { $0 << 8 | UInt32($1) }
    }

    /// Whether the call's signature names THIS function: its name is the
    /// signature's, and the selector derived from it is the one the hash
    /// covers.
    static func nameChecked(_ c: Call) -> Bool {
        guard let sig = c.signature, sig.hasPrefix(c.name + "("),
              let derived = selector(of: sig), let field = AztecPoseidon2.field(c.selector),
              field.prefix(28).allSatisfy({ $0 == 0 }) else { return false }
        return field.suffix(4).reduce(0) { $0 << 8 | UInt32($1) } == derived
    }

    // MARK: - The hash, rebuilt

    // DomainSeparator values (identical in v5.2.0, v6.0.0-rc.1 and v6.0.0:
    // `@aztec-labs/constants` 6.0.0, read 2026-10-26).
    static let functionArgs: UInt32 = 3_576_554_347
    static let publicCalldata: UInt32 = 2_760_353_947
    static let signaturePayload: UInt32 = 463_525_807
    static let authwitOuter: UInt32 = 3_283_595_782

    /// `P(AUTHWIT_OUTER, account, chainId, version, P(SIGNATURE_PAYLOAD,
    /// 5 × [argsHash, selector, to, isPublic, hideMsgSender, isStatic], nonce))`;
    /// a private call's argsHash is `P(FUNCTION_ARGS, args)` (zero when it has
    /// none), a public call's `P(PUBLIC_CALLDATA, selector, args)`; padding is
    /// `FunctionCall.empty()`, a PUBLIC call to zero.
    static func outerHash(_ r: Request) -> String? {
        let zero = Data(count: 32)
        let one = AztecPoseidon2.field("1")!
        var payload: [Data] = []
        for i in 0..<5 {
            guard i < r.calls.count else {
                payload += [AztecPoseidon2.hash([zero], separator: publicCalldata), zero, zero, one, zero, zero]
                continue
            }
            let c = r.calls[i]
            guard let selector = AztecPoseidon2.field(c.selector), let to = AztecPoseidon2.field(c.to) else { return nil }
            var args: [Data] = []
            for a in c.args {
                guard let f = AztecPoseidon2.field(a) else { return nil }
                args.append(f)
            }
            let isPublic = c.type == "public"
            let argsHash = isPublic ? AztecPoseidon2.hash([selector] + args, separator: publicCalldata)
                                    : (args.isEmpty ? zero : AztecPoseidon2.hash(args, separator: functionArgs))
            payload += [argsHash, selector, to, isPublic ? one : zero,
                        c.hideMsgSender ? one : zero, c.isStatic ? one : zero]
        }
        guard let nonce = AztecPoseidon2.field(r.txNonce), let account = AztecPoseidon2.field(r.account),
              let chain = AztecPoseidon2.field(r.chainId), let version = AztecPoseidon2.field(r.version) else { return nil }
        payload.append(nonce)
        let inner = AztecPoseidon2.hash(payload, separator: signaturePayload)
        return AztecPoseidon2.hex(AztecPoseidon2.hash([account, chain, version, inner], separator: authwitOuter))
    }

    /// What the account contract verifies: P-256 over `sha256(outer_hash)`.
    static func digest(_ messageHash: String) -> [UInt8]? {
        guard let bytes = AztecPoseidon2.field(messageHash) else { return nil }
        return Array(SHA256.hash(data: bytes))
    }

    static func signatureLine(r: [UInt8], s: [UInt8]) -> String {
        signaturePrefix + (r + s).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Words

    /// One call as the sheet draws it: the computer's name for it and every
    /// argument WHOLE — an amount (anything below 2^128, Aztec's u128) in
    /// decimal digits, anything wider in full hex. Nothing is shortened, so
    /// one token and a million never read alike.
    static func line(_ c: Call, account: String? = nil) -> String {
        if nameChecked(c), let plain = plainWords[c.signature ?? ""] { return plain }
        let own = account.flatMap(AztecPoseidon2.field)
        let args = c.args.map { a -> String in
            guard let data = AztecPoseidon2.field(a) else { return a }
            if let own, data == own { return String(localized: "your account") }
            return decimal(data) ?? AztecPoseidon2.hex(data)
        }
        return "\(c.name.isEmpty ? "call" : c.name)(\(args.joined(separator: ", ")))"
    }

    /// Plain words for a call whose name the phone CHECKED, keyed by its
    /// signature: only a function whose whole effect the words can state.
    static let plainWords: [String: String] = [
        "sponsor_unconditionally()": String(localized: "The sponsored fee payer pays the fee"),
    ]

    /// Where a call goes, as the sheet's second line says it: the account
    /// itself, else the address shortened.
    static func target(_ c: Call, account: String) -> String {
        if let to = AztecPoseidon2.field(c.to), to == AztecPoseidon2.field(account) {
            return String(localized: "your account")
        }
        return short(c.to)
    }

    /// 32 bytes as decimal digits when the value is below 2^128, else nil.
    static func decimal(_ data: Data) -> String? {
        let bytes = [UInt8](data)
        guard bytes.count == 32, bytes.prefix(16).allSatisfy({ $0 == 0 }) else { return nil }
        // Base-2^32 limbs, most significant first, divided by ten until zero.
        var limbs: [UInt64] = stride(from: 16, to: 32, by: 4).map { i in
            bytes[i..<(i + 4)].reduce(0) { $0 << 8 | UInt64($1) }
        }
        var digits: [Character] = []
        repeat {
            var rem: UInt64 = 0
            for k in limbs.indices {
                let cur = rem << 32 | limbs[k]
                limbs[k] = cur / 10
                rem = cur % 10
            }
            digits.append(Character(String(rem)))
        } while limbs.contains { $0 != 0 }
        return String(digits.reversed())
    }

    /// An address as written (leading zeros kept — they are part of it),
    /// shortened to its tail (prd §1553); the whole of it is the tray's to show.
    static func short(_ hex: String) -> String { AddressTail.short(normalized(hex), wholeUpTo: 20) }

    static func normalized(_ hex: String) -> String { hex.lowercased() }

    static func int(_ hex: String) -> Int? {
        let body = hex.lowercased().hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
        let digits = body.drop { $0 == "0" }
        return digits.count > 15 ? nil : Int(digits.isEmpty ? "0" : String(digits), radix: 16)
    }
}
