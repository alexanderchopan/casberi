import Foundation
import CryptoKit
import P256K

/// A whole Bitcoin WALLET, watched from its public key (prd §1097).
///
/// §226 read Bitcoin one address at a time, and a modern wallet (Sparrow,
/// BlueWallet, Ledger, Trezor) never reuses one: every receive takes a fresh
/// address, and a send's change goes to another fresh one. Watching a single
/// address of such a wallet read every spend as its WHOLE coin — 0.01 BTC sent
/// out of a 0.5 BTC piece landed as "Sent 0.5 BTC", the balance fell to zero,
/// and the change address was named as the recipient. The only fix is to know
/// every address the wallet owns, which its extended public key states.
///
/// Read-only by construction: an xpub derives addresses and can never sign.
/// A pasted PRIVATE extended key (`xprv`, `yprv`, `zprv`) is refused with a
/// sentence saying why (`refusal`), and is never stored.
///
/// Accepted spellings, mainnet only, single-key only:
/// - a bare `xpub` (script unknown — `BitcoinBridge` asks the first receive
///   address of each of the four scripts and keeps the ones with history),
/// - `ypub` (P2SH-wrapped SegWit, BIP49) and `zpub` (native SegWit, BIP84),
/// - an output descriptor: `pkh(…)`, `sh(wpkh(…))`, `wpkh(…)`, `tr(…)`, with
///   an optional `[fingerprint/path]` origin, an optional `/0/*`, `/1/*` or
///   `/<0;1>/*` tail and an optional `#checksum`.
/// Multisig (`wsh(multi(…))`, `Zpub`) and testnet keys are refused with a
/// sentence (`refusal`), never accepted and left reading nothing.
enum BitcoinHD {

    /// The four single-key scripts in use today.
    enum Script: String, Codable, CaseIterable {
        case pkh, shWpkh, wpkh, tr

        /// The word `BitcoinAddress.scriptKind` gives an address of this script.
        var kind: String {
            switch self {
            case .pkh:    return String(localized: "Legacy")
            case .shWpkh: return String(localized: "P2SH")
            case .wpkh:   return String(localized: "Native SegWit")
            case .tr:     return String(localized: "Taproot")
            }
        }
    }

    /// The public half of a BIP32 node: a compressed point and its chain code.
    struct Node: Equatable {
        let key: [UInt8]        // 33 bytes, compressed
        let chainCode: [UInt8]  // 32 bytes
    }

    struct Wallet: Equatable {
        let node: Node
        /// The scripts this key is read as. One when the spelling says
        /// (`zpub`, a descriptor); all four for a bare `xpub`.
        let scripts: [Script]
        /// The non-hardened steps between the key and an address index:
        /// `[[0], [1]]` (receive and change) unless a descriptor names one.
        let branches: [[UInt32]]
        var scriptKnown: Bool { scripts.count == 1 }
    }

    /// Addresses past the last used one a wallet may have handed out — BIP44's
    /// gap limit, the number every wallet named above scans to.
    static let gapLimit = 20

    // MARK: - Recognising a key

    static func isWallet(_ raw: String) -> Bool { parse(raw) != nil }

    /// "Bitcoin wallet · Native SegWit" — the kind a row shows for a watched
    /// key, read off its spelling alone (no decode, no curve check: this is
    /// read per row per render). nil for anything that isn't key-length.
    static func kindWord(_ raw: String) -> String? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count > 90, s.contains("pub") else { return nil }
        let wallet = String(localized: "Bitcoin wallet")
        let script: Script? =
            s.hasPrefix("sh(wpkh(") || s.hasPrefix("ypub") ? .shWpkh
            : s.hasPrefix("wpkh(") || s.hasPrefix("zpub") ? .wpkh
            : s.hasPrefix("pkh(") ? .pkh
            : s.hasPrefix("tr(") ? .tr
            : nil
        return script.map { "\(wallet) · \($0.kind)" } ?? wallet
    }

    /// The wallet a pasted string describes, or nil.
    static func parse(_ raw: String) -> Wallet? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let hash = s.lastIndex(of: "#"), s.distance(from: hash, to: s.endIndex) == 9 {
            s = String(s[..<hash])
        }
        // A descriptor names its script; a bare key leaves it to its prefix.
        let wrappers: [(String, String, Script)] = [
            ("sh(wpkh(", "))", .shWpkh), ("wpkh(", ")", .wpkh),
            ("pkh(", ")", .pkh), ("tr(", ")", .tr),
        ]
        for (open, close, script) in wrappers where s.hasPrefix(open) {
            guard s.hasSuffix(close) else { return nil }
            let inner = String(s.dropFirst(open.count).dropLast(close.count))
            guard let (node, prefixScript, branches) = keyExpression(inner) else { return nil }
            // A ypub inside `wpkh(…)` contradicts itself; refuse rather than guess.
            if let prefixScript, prefixScript != script { return nil }
            return Wallet(node: node, scripts: [script], branches: branches)
        }
        guard let (node, prefixScript, branches) = keyExpression(s),
              branches == [[0], [1]] else { return nil }
        return Wallet(node: node, scripts: prefixScript.map { [$0] } ?? Script.allCases,
                      branches: branches)
    }

    /// The sentence a near-miss earns instead of silence: a private key, a
    /// multisig wallet, a testnet key. nil for anything else, including a
    /// key `parse` accepts.
    static func refusal(_ raw: String) -> String? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = s.lowercased()
        for prefix in ["xprv", "yprv", "zprv", "tprv", "uprv", "vprv"] where s.contains(prefix) {
            if let payload = firstExtendedKey(in: s, prefix: prefix), payload.count == 78 {
                return String(localized: "That's a private key, and it can spend. Paste the public one, starting xpub, ypub or zpub.")
            }
        }
        if lower.contains("multi(") || s.hasPrefix("Ypub") || s.hasPrefix("Zpub")
            || lower.hasPrefix("wsh(") {
            if parse(s) == nil {
                return String(localized: "Multisig wallets aren't read yet. Paste one of its addresses instead.")
            }
        }
        for prefix in ["tpub", "upub", "vpub"] where s.contains(prefix) {
            if firstExtendedKey(in: s, prefix: prefix) != nil {
                return String(localized: "That's a testnet key. Only mainnet Bitcoin is read.")
            }
        }
        return nil
    }

    /// `[origin]KEY/tail` → the node, the script its prefix implies, and the
    /// branches the tail names.
    private static func keyExpression(_ expr: String) -> (Node, Script?, [[UInt32]])? {
        var rest = Substring(expr)
        if rest.hasPrefix("[") {
            guard let close = rest.firstIndex(of: "]") else { return nil }
            rest = rest[rest.index(after: close)...]
        }
        let key: Substring
        let tail: Substring
        if let slash = rest.firstIndex(of: "/") {
            key = rest[..<slash]
            tail = rest[slash...]
        } else {
            key = rest
            tail = ""
        }
        guard let (node, script) = decodeKey(String(key)),
              let branches = branches(String(tail)) else { return nil }
        return (node, script, branches)
    }

    /// `""` → receive and change; `/0/*` → one branch; `/<0;1>/*` → both;
    /// `/*` → children of the key itself. A hardened step cannot be derived
    /// from a public key, and a tail with no wildcard is ONE address (paste
    /// the address instead) — both nil.
    private static func branches(_ tail: String) -> [[UInt32]]? {
        if tail.isEmpty { return [[0], [1]] }
        var steps = tail.split(separator: "/", omittingEmptySubsequences: false).dropFirst()
        guard steps.last == "*" else { return nil }
        steps = steps.dropLast()
        var out: [[UInt32]] = [[]]
        for step in steps {
            if step.hasPrefix("<"), step.hasSuffix(">") {
                let choices = step.dropFirst().dropLast().split(separator: ";").compactMap { UInt32($0) }
                guard choices.count >= 2, choices.allSatisfy({ $0 < 0x8000_0000 }) else { return nil }
                out = out.flatMap { path in choices.map { path + [$0] } }
            } else {
                guard let n = UInt32(step), n < 0x8000_0000 else { return nil }
                out = out.map { $0 + [n] }
            }
        }
        return out
    }

    private static let versions: [UInt32: Script?] = [
        0x0488_B21E: nil,       // xpub — any script
        0x049D_7CB2: .shWpkh,   // ypub
        0x04B2_4746: .wpkh,     // zpub
    ]

    /// A mainnet single-key extended PUBLIC key → its node and implied script.
    private static func decodeKey(_ key: String) -> (Node, Script?)? {
        guard key.count >= 100, key.count <= 120,
              let payload = BitcoinAddress.base58CheckDecode(key), payload.count == 78 else { return nil }
        let version = payload[0..<4].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        guard let implied = versions[version] else { return nil }
        let chainCode = Array(payload[13..<45])
        let point = Array(payload[45..<78])
        guard point[0] == 0x02 || point[0] == 0x03,
              (try? P256K.Signing.PublicKey(dataRepresentation: point, format: .compressed)) != nil
        else { return nil }
        return (Node(key: point, chainCode: chainCode), implied)
    }

    /// The 78-byte payload of the first token in `s` that starts with `prefix`.
    private static func firstExtendedKey(in s: String, prefix: String) -> [UInt8]? {
        guard let start = s.range(of: prefix)?.lowerBound else { return nil }
        let token = s[start...].prefix { $0.isLetter || $0.isNumber }
        return BitcoinAddress.base58CheckDecode(String(token))
    }

    // MARK: - Deriving addresses (BIP32 public derivation)

    /// CKDpub: the non-hardened child `index` of `node`.
    static func child(_ node: Node, _ index: UInt32) -> Node? {
        guard index < 0x8000_0000 else { return nil }
        var data = node.key
        data += [UInt8(index >> 24 & 0xff), UInt8(index >> 16 & 0xff),
                 UInt8(index >> 8 & 0xff), UInt8(index & 0xff)]
        let mac = Array(HMAC<SHA512>.authenticationCode(for: Data(data),
                                                        using: SymmetricKey(data: node.chainCode)))
        guard let parent = try? P256K.Signing.PublicKey(dataRepresentation: node.key, format: .compressed),
              let tweaked = try? parent.add(Array(mac[0..<32]), format: .compressed)
        else { return nil }
        return Node(key: Array(tweaked.dataRepresentation), chainCode: Array(mac[32..<64]))
    }

    /// The address at `branch`/`index` under the wallet's key, as `script`.
    static func address(_ wallet: Wallet, script: Script, branch: [UInt32], index: UInt32) -> String? {
        guard let node = branchNode(wallet, branch) else { return nil }
        return address(node, script: script, index: index)
    }

    /// The node a branch's addresses are children of — derived once per walk,
    /// so each address costs one step rather than the whole path.
    static func branchNode(_ wallet: Wallet, _ branch: [UInt32]) -> Node? {
        var node = wallet.node
        for step in branch {
            guard let next = child(node, step) else { return nil }
            node = next
        }
        return node
    }

    /// The address of `branchNode`'s child `index`, as `script`.
    static func address(_ branchNode: Node, script: Script, index: UInt32) -> String? {
        guard let leaf = child(branchNode, index) else { return nil }
        return address(of: leaf.key, script: script)
    }

    /// A compressed public key's address as `script`.
    static func address(of key: [UInt8], script: Script) -> String? {
        switch script {
        case .pkh:
            return BitcoinAddress.base58Check([0x00] + hash160(key))
        case .shWpkh:
            let redeem: [UInt8] = [0x00, 0x14] + hash160(key)
            return BitcoinAddress.base58Check([0x05] + hash160(redeem))
        case .wpkh:
            return BitcoinAddress.segwitAddress(version: 0, program: hash160(key))
        case .tr:
            // BIP86: the key-path-only output key, Q = P + H_TapTweak(P)·G.
            let internalKey = Array(key.dropFirst())
            let tweak = taggedHash("TapTweak", internalKey)
            guard let output = try? P256K.Schnorr.XonlyKey(dataRepresentation: internalKey).add(tweak)
            else { return nil }
            return BitcoinAddress.segwitAddress(version: 1, program: output.bytes)
        }
    }

    /// A short, stable name for a wallet in refs and defaults keys — never the
    /// key itself, which would otherwise ride every landed thing's ref.
    static func fingerprint(_ raw: String) -> String {
        let digest = SHA256.hash(data: Data(raw.trimmingCharacters(in: .whitespacesAndNewlines).utf8))
        return "hd-" + digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Hashes

    static func hash160(_ data: [UInt8]) -> [UInt8] {
        RIPEMD160.hash(Array(SHA256.hash(data: Data(data))))
    }

    static func taggedHash(_ tag: String, _ data: [UInt8]) -> [UInt8] {
        let tagHash = Array(SHA256.hash(data: Data(tag.utf8)))
        return Array(SHA256.hash(data: Data(tagHash + tagHash + data)))
    }
}

/// RIPEMD-160, the second half of Bitcoin's HASH160 — CryptoKit has no such
/// digest. The reference algorithm (Dobbertin, Bosselaers, Preneel 1996),
/// checked against its published vectors in `BitcoinHDTests`.
enum RIPEMD160 {
    static func hash(_ message: [UInt8]) -> [UInt8] {
        var h: [UInt32] = [0x6745_2301, 0xEFCD_AB89, 0x98BA_DCFE, 0x1032_5476, 0xC3D2_E1F0]
        var msg = message
        let bitLength = UInt64(message.count) * 8
        msg.append(0x80)
        while msg.count % 64 != 56 { msg.append(0) }
        for i in 0..<8 { msg.append(UInt8(bitLength >> (8 * UInt64(i)) & 0xff)) }

        for chunk in stride(from: 0, to: msg.count, by: 64) {
            var x = [UInt32](repeating: 0, count: 16)
            for i in 0..<16 {
                let o = chunk + 4 * i
                x[i] = UInt32(msg[o]) | UInt32(msg[o + 1]) << 8
                    | UInt32(msg[o + 2]) << 16 | UInt32(msg[o + 3]) << 24
            }
            var (al, bl, cl, dl, el) = (h[0], h[1], h[2], h[3], h[4])
            var (ar, br, cr, dr, er) = (h[0], h[1], h[2], h[3], h[4])
            for j in 0..<80 {
                var t = rotl(al &+ f(j, bl, cl, dl) &+ x[r[j]] &+ k[j / 16], s[j]) &+ el
                (al, el, dl, cl, bl) = (el, dl, rotl(cl, 10), bl, t)
                t = rotl(ar &+ f(79 - j, br, cr, dr) &+ x[rp[j]] &+ kp[j / 16], sp[j]) &+ er
                (ar, er, dr, cr, br) = (er, dr, rotl(cr, 10), br, t)
            }
            let t = h[1] &+ cl &+ dr
            h[1] = h[2] &+ dl &+ er
            h[2] = h[3] &+ el &+ ar
            h[3] = h[4] &+ al &+ br
            h[4] = h[0] &+ bl &+ cr
            h[0] = t
        }
        return h.flatMap { word in (0..<4).map { UInt8(word >> (8 * UInt32($0)) & 0xff) } }
    }

    private static func rotl(_ x: UInt32, _ n: Int) -> UInt32 { x << UInt32(n) | x >> UInt32(32 - n) }

    private static func f(_ j: Int, _ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 {
        switch j {
        case 0..<16:  return x ^ y ^ z
        case 16..<32: return (x & y) | (~x & z)
        case 32..<48: return (x | ~y) ^ z
        case 48..<64: return (x & z) | (y & ~z)
        default:      return x ^ (y | ~z)
        }
    }

    private static let k: [UInt32] = [0x0000_0000, 0x5A82_7999, 0x6ED9_EBA1, 0x8F1B_BCDC, 0xA953_FD4E]
    private static let kp: [UInt32] = [0x50A2_8BE6, 0x5C4D_D124, 0x6D70_3EF3, 0x7A6D_76E9, 0x0000_0000]
    private static let r: [Int] = [
        0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
        7, 4, 13, 1, 10, 6, 15, 3, 12, 0, 9, 5, 2, 14, 11, 8,
        3, 10, 14, 4, 9, 15, 8, 1, 2, 7, 0, 6, 13, 11, 5, 12,
        1, 9, 11, 10, 0, 8, 12, 4, 13, 3, 7, 15, 14, 5, 6, 2,
        4, 0, 5, 9, 7, 12, 2, 10, 14, 1, 3, 8, 11, 6, 15, 13]
    private static let rp: [Int] = [
        5, 14, 7, 0, 9, 2, 11, 4, 13, 6, 15, 8, 1, 10, 3, 12,
        6, 11, 3, 7, 0, 13, 5, 10, 14, 15, 8, 12, 4, 9, 1, 2,
        15, 5, 1, 3, 7, 14, 6, 9, 11, 8, 12, 2, 10, 0, 4, 13,
        8, 6, 4, 1, 3, 11, 15, 0, 5, 12, 2, 13, 9, 7, 10, 14,
        12, 15, 10, 4, 1, 5, 8, 7, 6, 2, 13, 14, 0, 3, 9, 11]
    private static let s: [Int] = [
        11, 14, 15, 12, 5, 8, 7, 9, 11, 13, 14, 15, 6, 7, 9, 8,
        7, 6, 8, 13, 11, 9, 7, 15, 7, 12, 15, 9, 11, 7, 13, 12,
        11, 13, 6, 7, 14, 9, 13, 15, 14, 8, 13, 6, 5, 12, 7, 5,
        11, 12, 14, 15, 14, 15, 9, 8, 9, 14, 5, 6, 8, 6, 5, 12,
        9, 15, 5, 11, 6, 8, 13, 12, 5, 12, 13, 14, 11, 8, 5, 6]
    private static let sp: [Int] = [
        8, 9, 9, 11, 13, 15, 15, 5, 7, 7, 8, 11, 14, 14, 12, 6,
        9, 13, 15, 7, 12, 8, 9, 11, 7, 7, 12, 7, 6, 15, 13, 11,
        9, 7, 15, 11, 8, 6, 6, 14, 12, 13, 5, 14, 13, 13, 7, 5,
        15, 5, 8, 11, 14, 14, 6, 14, 6, 9, 12, 9, 12, 5, 15, 8,
        8, 5, 12, 9, 12, 5, 14, 6, 8, 13, 6, 5, 15, 13, 11, 11]
}
