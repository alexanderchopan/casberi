import Foundation

/// RLP, once (prd §525, 2026-08-29).
///
/// Extracted from `VibenetTransaction` the day a SECOND chain needed it.
/// Hegotá's frame transactions are RLP too, and the alternative was a second
/// encoder — which is the drift this codebase has paid for repeatedly (the
/// §418 duplicate-parser lesson, the `ToolScore`→`AgentCorpusTools.rank` fold).
/// Two encoders of one format eventually disagree, and here a disagreement is
/// a signature over a different transaction.
///
/// Foundation-only BY DESIGN so both seats' harnesses can compile it WHOLE.
/// **Its correctness is not asserted in the abstract**: `vibenet-signer-selftest`
/// pins a 613-byte preimage and a signing hash proven against real
/// transactions, so a change here that alters a single byte fails that harness
/// immediately. That is the guard, not this comment.
enum RLP {

    /// The two shapes, and nothing else. An enum rather than `Any` so a caller
    /// cannot hand in a type this encoder would have to guess about.
    indirect enum Item {
        case bytes(Data)
        case list([Item])
    }

    /// Canonical big-endian with **no leading zeros, and ZERO IS EMPTY**. The
    /// rule most easily got wrong and the one that changes the hash: RLP
    /// quantity encoding has exactly one representation per value, and `0x00`
    /// is not it — a zero field must contribute `0x80`, never `0x00`.
    static func quantity(_ value: UInt64) -> Data {
        guard value != 0 else { return Data() }
        var v = value
        var out = [UInt8]()
        while v > 0 { out.insert(UInt8(v & 0xff), at: 0); v >>= 8 }
        return Data(out)
    }

    /// The same rule for a value too WIDE for `UInt64` — a `U256` on the wire.
    ///
    /// Added for ethrex Privacy's `nonce_keys`, which the node types
    /// `Vec<U256>`: a real key beginning `0x0c…` rides the wire as 31 bytes,
    /// and writing the padded 32 changes the hash. Shared here rather than
    /// copied into that encoder, because two spellings of the minimal-integer
    /// rule is exactly how one of them drifts.
    ///
    /// Zero is EMPTY, as above — a field of zero bytes and a field of one zero
    /// byte are different encodings and only the first is canonical.
    static func minimal(_ value: Data) -> Data {
        var out = value
        while out.first == 0 { out.removeFirst() }
        return out
    }

    static func encode(_ item: Item) -> Data {
        switch item {
        case .bytes(let d):
            // A single byte below 0x80 is its own encoding — the one case with
            // no prefix at all.
            if d.count == 1, d[0] < 0x80 { return d }
            return header(d.count, offset: 0x80) + d
        case .list(let items):
            let body = items.reduce(into: Data()) { $0 += encode($1) }
            return header(body.count, offset: 0xc0) + body
        }
    }

    private static func header(_ length: Int, offset: UInt8) -> Data {
        if length < 56 { return Data([offset + UInt8(length)]) }
        let lenBytes = quantity(UInt64(length))
        return Data([offset + 55 + UInt8(lenBytes.count)]) + lenBytes
    }

    // MARK: - Hex

    static func hex(_ data: some Sequence<UInt8>) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    static func data(fromHex hex: String) -> Data? {
        var s = Substring(hex)
        if s.hasPrefix("0x") || s.hasPrefix("0X") { s = s.dropFirst(2) }
        guard s.count % 2 == 0, !s.isEmpty else { return nil }
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
