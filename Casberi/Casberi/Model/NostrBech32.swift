import Foundation

/// Bech32 (BIP-0173) encode/decode, just enough of NIP-19 for Nostr identities
/// and permalinks: `npub`/`nsec`-shaped (a bare 32-byte payload, no TLV) for a
/// pubkey, and `note` (a bare 32-byte event id) for a permalink. Deliberately
/// NOT the TLV `nprofile`/`nevent` forms — those carry relay hints Casberi
/// doesn't track, and njump.me (the web gateway every permalink here opens on)
/// resolves a bare `npub`/`note` on its own by querying its default relay set.
enum NostrBech32 {
    private static let charset = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"

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

    private static func createChecksum(hrp: String, data: [UInt8]) -> [UInt8] {
        let values = hrpExpand(hrp) + data + [0, 0, 0, 0, 0, 0]
        let mod = polymod(values) ^ 1
        return (0..<6).map { UInt8((mod >> (5 * (5 - $0))) & 31) }
    }

    private static func verifyChecksum(hrp: String, data: [UInt8]) -> Bool {
        polymod(hrpExpand(hrp) + data) == 1
    }

    /// 8-bit bytes <-> 5-bit groups. `pad: false` on decode drops a trailing
    /// incomplete group (bech32's own padding), never rounding UP — a decode
    /// with `pad: true` would fabricate a spurious extra byte.
    private static func convertBits(_ data: [UInt8], from: Int, to: Int, pad: Bool) -> [UInt8]? {
        var acc = 0, bits = 0
        var out: [UInt8] = []
        let maxv = (1 << to) - 1
        let maxAcc = (1 << (from + to - 1)) - 1
        for value in data {
            let v = Int(value)
            guard v >= 0, (v >> from) == 0 else { return nil }
            acc = ((acc << from) | v) & maxAcc
            bits += from
            while bits >= to {
                bits -= to
                out.append(UInt8((acc >> bits) & maxv))
            }
        }
        if pad {
            if bits > 0 { out.append(UInt8((acc << (to - bits)) & maxv)) }
        } else if bits >= from || ((acc << (to - bits)) & maxv) != 0 {
            return nil   // non-zero padding, or too many leftover bits — malformed
        }
        return out
    }

    /// Encodes 32 raw bytes as `<hrp>1<data><checksum>` — "npub1…" / "note1…".
    static func encode(hrp: String, bytes: [UInt8]) -> String? {
        guard let values = convertBits(bytes, from: 8, to: 5, pad: true) else { return nil }
        let checksum = createChecksum(hrp: hrp, data: values)
        let combined = values + checksum
        return hrp + "1" + String(combined.map { charset[charset.index(charset.startIndex, offsetBy: Int($0))] })
    }

    /// Decodes a bech32 string back to its raw bytes, verifying the hrp
    /// matches what the caller expects (so an "nsec1…" can never be read as
    /// an "npub" by accident) and the checksum is valid.
    static func decode(_ s: String, expectHRP: String) -> [UInt8]? {
        let lower = s.lowercased()
        guard lower == s || s.uppercased() == s else { return nil }   // mixed case is invalid bech32
        guard let sep = lower.lastIndex(of: "1") else { return nil }
        let hrp = String(lower[lower.startIndex..<sep])
        guard hrp == expectHRP else { return nil }
        let dataPart = lower[lower.index(after: sep)...]
        guard dataPart.count >= 6 else { return nil }
        var values: [UInt8] = []
        for c in dataPart {
            guard let idx = charset.firstIndex(of: c) else { return nil }
            values.append(UInt8(charset.distance(from: charset.startIndex, to: idx)))
        }
        guard verifyChecksum(hrp: hrp, data: values) else { return nil }
        let payload = Array(values.dropLast(6))
        return convertBits(payload, from: 5, to: 8, pad: false)
    }

    // MARK: - Nostr-specific convenience

    static func npubToHex(_ npub: String) -> String? {
        guard let bytes = decode(npub, expectHRP: "npub"), bytes.count == 32 else { return nil }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    static func hexToNpub(_ hex: String) -> String? {
        guard let bytes = hexBytes(hex) else { return nil }
        return encode(hrp: "npub", bytes: bytes)
    }

    static func noteToHex(_ note: String) -> String? {
        guard let bytes = decode(note, expectHRP: "note"), bytes.count == 32 else { return nil }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    static func hexToNote(_ hex: String) -> String? {
        guard let bytes = hexBytes(hex) else { return nil }
        return encode(hrp: "note", bytes: bytes)
    }

    private static func hexBytes(_ hex: String) -> [UInt8]? {
        guard hex.count == 64 else { return nil }
        var bytes: [UInt8] = []
        var idx = hex.startIndex
        while idx < hex.endIndex {
            let next = hex.index(idx, offsetBy: 2)
            guard let b = UInt8(hex[idx..<next], radix: 16) else { return nil }
            bytes.append(b)
            idx = next
        }
        return bytes
    }

    /// "npub1abc…wxyz" — the display form everywhere a full 63-char npub
    /// would overwhelm a row (the roster face, the omnibox subtitle).
    static func shortNpub(_ npub: String) -> String {
        guard npub.count > 20 else { return npub }
        return "\(npub.prefix(12))…\(npub.suffix(6))"
    }
}
