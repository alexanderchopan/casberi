import Foundation

/// Keccak-256 (2026-07-28) — the ORIGINAL Keccak padding (domain separator
/// 0x01), NOT NIST SHA3-256 (0x06) — a different hash despite the "SHA3"
/// branding collision, and `CryptoKit` only ships the NIST one. Needed for
/// exactly one thing: EIP-55 checksum formatting, so `api.safe.global`
/// accepts a Safe-detection address (measured 2026-07-28: it 422s BOTH an
/// all-lowercase and an all-uppercase address as "Checksum address
/// validation failed" — only the mixed-case checksum form gets an honest
/// 200/404).
///
/// This is NOT `WalletConnectBridge.UnusedCryptoProvider.keccak256`, which
/// stays a deliberate `preconditionFailure` — that one backs the
/// WalletConnect SDK's signature-RECOVERY path (unreachable on our
/// read-only proposal, and recovering a signer needs `secp256k1` on top,
/// sitting on the custody boundary that ruling exists to guard). Formatting
/// a public address's letter case is a pure, deterministic, keyless string
/// transform with no bearing on custody — it belongs beside
/// `BitcoinAddress`'s own encoding/checksum work, not behind that one.
///
/// Verified against pycryptodome ground truth (raw hash) and the EIP-55
/// spec's own four published test vectors (checksum) before landing here —
/// `scripts/keccak256-selftest.sh` runs the actual source below, not a
/// duplicate, so it can't silently drift out of sync with what ships. A
/// wrong rotation-offset table produces a wrong-but-valid-looking checksum
/// with no crash, so this is verified, not trusted from memory.
enum Keccak256 {
    private static let roundConstants: [UInt64] = [
        0x0000000000000001, 0x0000000000008082, 0x800000000000808A, 0x8000000080008000,
        0x000000000000808B, 0x0000000080000001, 0x8000000080008081, 0x8000000000008009,
        0x000000000000008A, 0x0000000000000088, 0x0000000080008009, 0x000000008000000A,
        0x000000008000808B, 0x800000000000008B, 0x8000000000008089, 0x8000000000008003,
        0x8000000000008002, 0x8000000000000080, 0x000000000000800A, 0x800000008000000A,
        0x8000000080008081, 0x8000000000008080, 0x0000000080000001, 0x8000000080008008,
    ]

    /// r[x][y] — the standard Keccak rotation-offset table, indexed x outer, y inner.
    private static let rotationOffsets: [[Int]] = [
        [0, 36, 3, 41, 18],
        [1, 44, 10, 45, 2],
        [62, 6, 43, 15, 61],
        [28, 55, 25, 21, 56],
        [27, 20, 39, 8, 14],
    ]

    private static func rotl(_ x: UInt64, _ n: Int) -> UInt64 {
        n == 0 ? x : (x << n) | (x >> (64 - n))
    }

    private static func permute(_ state: inout [UInt64]) {
        for round in 0..<24 {
            // theta
            var c = [UInt64](repeating: 0, count: 5)
            for x in 0..<5 { c[x] = state[x] ^ state[x + 5] ^ state[x + 10] ^ state[x + 15] ^ state[x + 20] }
            var d = [UInt64](repeating: 0, count: 5)
            for x in 0..<5 { d[x] = c[(x + 4) % 5] ^ rotl(c[(x + 1) % 5], 1) }
            for x in 0..<5 { for y in 0..<5 { state[x + 5 * y] ^= d[x] } }

            // rho + pi
            var b = [UInt64](repeating: 0, count: 25)
            for x in 0..<5 {
                for y in 0..<5 {
                    let newX = y
                    let newY = (2 * x + 3 * y) % 5
                    b[newX + 5 * newY] = rotl(state[x + 5 * y], rotationOffsets[x][y])
                }
            }

            // chi
            for x in 0..<5 {
                for y in 0..<5 {
                    state[x + 5 * y] = b[x + 5 * y] ^ (~b[(x + 1) % 5 + 5 * y] & b[(x + 2) % 5 + 5 * y])
                }
            }

            // iota
            state[0] ^= roundConstants[round]
        }
    }

    /// The rate for Keccak-256 (capacity 512 bits → 256-bit output): 1088
    /// bits / 8 = 136 bytes. Every address we ever hash is far under one
    /// block, so this never needs more than a single permutation to absorb.
    private static let rateBytes = 136

    static func hash(_ message: [UInt8]) -> [UInt8] {
        var state = [UInt64](repeating: 0, count: 25)

        var input = message
        let padLen = rateBytes - (input.count % rateBytes)
        if padLen == 1 {
            input.append(0x81)
        } else {
            input.append(0x01)
            input.append(contentsOf: [UInt8](repeating: 0, count: padLen - 2))
            input.append(0x80)
        }

        var offset = 0
        while offset < input.count {
            for i in 0..<(rateBytes / 8) {
                var lane: UInt64 = 0
                for byte in 0..<8 {
                    lane |= UInt64(input[offset + i * 8 + byte]) << (8 * byte)
                }
                state[i] ^= lane
            }
            permute(&state)
            offset += rateBytes
        }

        var output = [UInt8]()
        outer: for i in 0..<(rateBytes / 8) {
            let lane = state[i]
            for byte in 0..<8 {
                output.append(UInt8((lane >> (8 * byte)) & 0xFF))
                if output.count == 32 { break outer }
            }
        }
        return output
    }

    static func hexString(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }
}

/// EIP-55 mixed-case checksum formatting — see `Keccak256`'s doc comment
/// for why this exists and what it's deliberately NOT (signature recovery).
enum EIP55 {
    /// The checksummed form of a hex address. Pass-through for anything
    /// that isn't exactly 40 hex chars after stripping an optional `0x` —
    /// a Solana/Bitcoin address, an unresolved ENS name, or already-mangled
    /// input — this only ever tightens a hex address, never reshapes a
    /// non-hex one, so it's safe to call on any address-shaped string.
    static func checksum(_ address: String) -> String {
        var addr = address
        let hasPrefix = addr.lowercased().hasPrefix("0x")
        if hasPrefix { addr.removeFirst(2) }
        addr = addr.lowercased()
        guard addr.count == 40, addr.allSatisfy(\.isHexDigit) else { return address }

        let hashHex = Keccak256.hexString(Keccak256.hash(Array(addr.utf8)))
        var out = ""
        for (i, ch) in addr.enumerated() {
            if ch.isNumber {
                out.append(ch)
                continue
            }
            let digitIndex = hashHex.index(hashHex.startIndex, offsetBy: i)
            let hashDigit = UInt8(String(hashHex[digitIndex]), radix: 16) ?? 0
            out.append(hashDigit >= 8 ? Character(ch.uppercased()) : ch)
        }
        return hasPrefix ? "0x" + out : out
    }
}
