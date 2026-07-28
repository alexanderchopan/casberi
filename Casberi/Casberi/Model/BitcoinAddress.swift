import Foundation
import CryptoKit

/// Bitcoin address recognition (2026-07-27) — validates the CHECKSUM, not
/// just the shape. `ENS.isHexAddress`/`SNS.isAddress` are the two existing
/// family tests, and both are shape-only; a Bitcoin legacy/P2SH address is
/// base58 in the same 25–34-char band Solana pubkeys occupy, so a bare BTC
/// paste was silently swallowed by `SNS.isAddress` — accepted as a watch,
/// flipped `solana-mainnet` on, and asked Solana about a Bitcoin address
/// forever (caught 2026-07-27 auditing the watch flow, never landed a thing).
/// Base58Check's own checksum is the fix: a real Solana pubkey satisfying
/// Bitcoin's version-byte-plus-double-SHA256 check by chance is
/// astronomically unlikely, so checking HERE first and routing to Bitcoin on
/// a match is safe — every call site that used to branch on `SNS.isAddress`
/// alone now checks this first.
///
/// Covers the four address kinds actually in use today (mainnet only — this
/// app names no other network): Base58Check legacy (version 0x00, "1…") and
/// P2SH (version 0x05, "3…"), and bech32/bech32m native SegWit (BIP173,
/// witness v0, "bc1q…") and Taproot (BIP350, witness v1, "bc1p…"). The
/// bech32 core (polymod/hrpExpand/convertBits) is NOT shared with
/// `NostrBech32` even though the algorithm is identical — that file encodes
/// a bare 32-byte payload with a fixed hrp and a fixed (bech32-only)
/// checksum; a Bitcoin address carries a witness VERSION as its first data
/// byte, which selects between two different checksum constants (BIP350),
/// so the payload shape and the verification rule both differ. Same
/// reasoning `SNS.swift` already gives for not folding into `ENS`: different
/// resolvers, different pipelines downstream, stay separable by shape.
///
/// Checksum verification MEASURED against a live address 2026-07-27
/// (`bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh`, confirmed via
/// mempool.space) and against BIP173/BIP350's own published test vectors for
/// witness v0 and v1 — decode, don't guess.
enum BitcoinAddress {

    // MARK: - Base58Check (legacy, P2SH)

    private static let base58Alphabet =
        Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")

    /// Base58 → raw bytes, leading `1`s (base58's zero digit) restored as
    /// leading zero bytes. nil on any character outside the alphabet.
    private static func base58Decode(_ s: String) -> [UInt8]? {
        var bytes: [UInt8] = []
        for char in s {
            guard let idx = base58Alphabet.firstIndex(of: char) else { return nil }
            var carry = base58Alphabet.distance(from: base58Alphabet.startIndex, to: idx)
            for i in 0..<bytes.count {
                carry += Int(bytes[i]) * 58
                bytes[i] = UInt8(carry & 0xff)
                carry >>= 8
            }
            while carry > 0 {
                bytes.append(UInt8(carry & 0xff))
                carry >>= 8
            }
        }
        let leadingZeros = s.prefix { $0 == "1" }.count
        return Array(repeating: 0, count: leadingZeros) + bytes.reversed()
    }

    /// The version byte and 20-byte hash, once the double-SHA256 checksum
    /// (the last 4 of 25 decoded bytes) is verified against the first 21 —
    /// the check a shape-only base58 test can't make. nil on anything that
    /// doesn't decode to exactly 25 bytes with a matching checksum.
    private static func base58CheckPayload(_ s: String) -> (version: UInt8, hash: [UInt8])? {
        guard let decoded = base58Decode(s), decoded.count == 25 else { return nil }
        let payload = Array(decoded.prefix(21))
        let checksum = Array(decoded.suffix(4))
        let round1 = SHA256.hash(data: Data(payload))
        let round2 = SHA256.hash(data: Data(round1))
        guard Array(round2.prefix(4)) == checksum else { return nil }
        return (version: payload[0], hash: Array(payload.dropFirst()))
    }

    // MARK: - Bech32 / Bech32m (BIP173 / BIP350)

    private static let charset = Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l")

    private static func polymod(_ values: [UInt8]) -> UInt32 {
        let gen: [UInt32] = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3]
        var chk: UInt32 = 1
        for v in values {
            let b = chk >> 25
            chk = ((chk & 0x1ffffff) << 5) ^ UInt32(v)
            for i in 0..<5 where (b >> i) & 1 == 1 { chk ^= gen[i] }
        }
        return chk
    }

    private static func hrpExpand(_ hrp: String) -> [UInt8] {
        var out = hrp.unicodeScalars.map { UInt8($0.value >> 5) }
        out.append(0)
        out.append(contentsOf: hrp.unicodeScalars.map { UInt8($0.value & 31) })
        return out
    }

    /// 5-bit groups → 8-bit bytes, `pad: false` so a malformed trailing
    /// group (non-zero padding, or too many leftover bits) fails rather than
    /// fabricating a spurious byte — same rule `NostrBech32.convertBits` uses.
    private static func convertBits(_ data: [UInt8], from: Int, to: Int) -> [UInt8]? {
        var acc = 0, bits = 0
        var out: [UInt8] = []
        let maxv = (1 << to) - 1
        let maxAcc = (1 << (from + to - 1)) - 1
        for value in data {
            let v = Int(value)
            guard (v >> from) == 0 else { return nil }
            acc = ((acc << from) | v) & maxAcc
            bits += from
            while bits >= to {
                bits -= to
                out.append(UInt8((acc >> bits) & maxv))
            }
        }
        guard bits < from, ((acc << (to - bits)) & maxv) == 0 else { return nil }
        return out
    }

    /// The witness version (0–16) and program, once the checksum verifies —
    /// v0 (P2WPKH/P2WSH) checksums as plain bech32 (const `1`); v1+
    /// (Taproot is v1) checksums as bech32m (const `0x2bc830a3`, BIP350). A
    /// v0 program encoded with the bech32m const, or vice versa, fails here —
    /// the spec makes that combination invalid, not just unconventional.
    private static func segwitProgram(_ address: String) -> (version: Int, program: [UInt8])? {
        let s = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count >= 14, s.count <= 74 else { return nil }
        let lower = s.lowercased()
        guard lower == s || s.uppercased() == s else { return nil }   // mixed case is invalid bech32
        guard let sep = lower.lastIndex(of: "1"),
              lower[lower.startIndex..<sep] == "bc"   // mainnet only
        else { return nil }
        let dataPart = lower[lower.index(after: sep)...]
        guard dataPart.count >= 7 else { return nil }   // version + 6-char checksum, minimum
        var values: [UInt8] = []
        for c in dataPart {
            guard let idx = charset.firstIndex(of: c) else { return nil }
            values.append(UInt8(charset.distance(from: charset.startIndex, to: idx)))
        }
        let payload = Array(values.dropLast(6))
        guard let version = payload.first, version <= 16 else { return nil }
        let const: UInt32 = version == 0 ? 1 : 0x2bc830a3
        guard polymod(hrpExpand("bc") + values) == const,
              let program = convertBits(Array(payload.dropFirst()), from: 5, to: 8),
              program.count >= 2, program.count <= 40
        else { return nil }
        if version == 0, program.count != 20, program.count != 32 { return nil }   // BIP141
        return (Int(version), program)
    }

    // MARK: - Public surface

    /// True for a mainnet Bitcoin address of any of the four kinds below,
    /// checksum-verified. The one gate every call site that used to branch
    /// on `SNS.isAddress` alone now checks FIRST.
    static func isAddress(_ address: String) -> Bool {
        base58CheckPayload(address) != nil || segwitProgram(address) != nil
    }

    /// What kind of address this is — free (no network call: the chain
    /// supplies the kind, the same doctrine `AddressKind` states for EVM,
    /// just readable straight off the encoding here instead of an
    /// `eth_getCode` round trip). nil for anything that isn't a valid
    /// Bitcoin address.
    static func scriptKind(_ address: String) -> String? {
        if let payload = base58CheckPayload(address) {
            switch payload.version {
            case 0x00: return String(localized: "Legacy")
            case 0x05: return String(localized: "P2SH")
            default: return nil
            }
        }
        if let (version, _) = segwitProgram(address) {
            switch version {
            case 0: return String(localized: "Native SegWit")
            case 1: return String(localized: "Taproot")
            default: return String(localized: "SegWit")   // a future witness version, named generically
            }
        }
        return nil
    }
}
