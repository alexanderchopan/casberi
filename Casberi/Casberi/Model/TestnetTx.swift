import Foundation

/// **A TESTNET TRANSACTION'S BYTES (prd §1554).** EIP-1559 (type 2): the
/// payload a key signs, and the raw transaction a node takes once signed.
/// Used by the DEBUG Sepolia sender (`PrivacyTestnetSender`) alone, which is
/// how Move to private reaches the pool before your account can.
///
/// **Testnet only, by construction:** `Tx` cannot be made for a chain that
/// is not in `testnets`, so no signature over a mainnet transaction can come
/// out of this file.
///
/// Pure (Foundation + `Keccak256`): `private-money-selftest.sh` pins its
/// bytes against viem's.
enum TestnetTx {

    static let testnets: Set<Int> = [11_155_111]

    indirect enum RLP: Equatable {
        case bytes([UInt8])
        case list([RLP])

        var encoded: [UInt8] {
            switch self {
            case .bytes(let b):
                if b.count == 1, b[0] < 0x80 { return b }
                return Self.head(b.count, short: 0x80) + b
            case .list(let items):
                let body = items.flatMap(\.encoded)
                return Self.head(body.count, short: 0xc0) + body
            }
        }

        private static func head(_ length: Int, short: UInt8) -> [UInt8] {
            if length < 56 { return [short + UInt8(length)] }
            let len = TestnetTx.minimal(UInt64(length))
            return [short + 55 + UInt8(len.count)] + len
        }
    }

    struct Tx: Equatable {
        let chainId: Int
        /// Every quantity is 0x-hex, as a node answers it.
        let nonce: String
        let maxPriorityFeePerGas: String
        let maxFeePerGas: String
        let gas: String
        /// 0x + 40 hex.
        let to: String
        let value: String
        let data: String

        /// Nil for a chain that is not a testnet, or a field that is not hex.
        init?(chainId: Int, nonce: String, maxPriorityFeePerGas: String, maxFeePerGas: String,
              gas: String, to: String, value: String, data: String) {
            guard TestnetTx.testnets.contains(chainId) else { return nil }
            for q in [nonce, maxPriorityFeePerGas, maxFeePerGas, gas, value] where TestnetTx.quantity(q) == nil { return nil }
            guard let address = TestnetTx.bytes(to), address.count == 20, TestnetTx.bytes(data) != nil else { return nil }
            self.chainId = chainId; self.nonce = nonce; self.maxPriorityFeePerGas = maxPriorityFeePerGas
            self.maxFeePerGas = maxFeePerGas; self.gas = gas; self.to = to; self.value = value; self.data = data
        }

        private var fields: [RLP] {
            [.bytes(TestnetTx.minimal(UInt64(chainId))),
             .bytes(TestnetTx.quantity(nonce)!),
             .bytes(TestnetTx.quantity(maxPriorityFeePerGas)!),
             .bytes(TestnetTx.quantity(maxFeePerGas)!),
             .bytes(TestnetTx.quantity(gas)!),
             .bytes(TestnetTx.bytes(to)!),
             .bytes(TestnetTx.quantity(value)!),
             .bytes(TestnetTx.bytes(data)!),
             .list([])]
        }

        /// `0x02 ‖ rlp([chainId, nonce, tip, maxFee, gas, to, value, data, []])`.
        var unsigned: [UInt8] { [0x02] + RLP.list(fields).encoded }

        /// What the key signs: keccak256 of the unsigned payload.
        var signingHash: [UInt8] { Keccak256.hash(unsigned) }

        /// The raw transaction `eth_sendRawTransaction` takes.
        func signed(yParity: Int, r: [UInt8], s: [UInt8]) -> [UInt8]? {
            guard yParity == 0 || yParity == 1, r.count == 32, s.count == 32 else { return nil }
            return [0x02] + RLP.list(fields + [.bytes(yParity == 0 ? [] : [1]),
                                               .bytes(TestnetTx.stripped(r)), .bytes(TestnetTx.stripped(s))]).encoded
        }
    }

    // MARK: - Bytes

    static func minimal(_ n: UInt64) -> [UInt8] {
        var out: [UInt8] = []
        var v = n
        while v > 0 { out.insert(UInt8(v & 0xff), at: 0); v >>= 8 }
        return out
    }

    static func stripped(_ b: [UInt8]) -> [UInt8] { Array(b.drop { $0 == 0 }) }

    /// 0x-hex to bytes ("0x" is empty); nil for anything else.
    static func bytes(_ hex: String) -> [UInt8]? {
        guard hex.hasPrefix("0x") else { return nil }
        var s = String(hex.dropFirst(2))
        guard s.allSatisfy(\.isHexDigit) else { return nil }
        if s.count % 2 == 1 { s = "0" + s }
        var out: [UInt8] = []
        out.reserveCapacity(s.count / 2)
        var i = s.startIndex
        while i < s.endIndex {
            let j = s.index(i, offsetBy: 2)
            guard let b = UInt8(s[i..<j], radix: 16) else { return nil }
            out.append(b)
            i = j
        }
        return out
    }

    /// A 0x-hex quantity as its minimal big-endian bytes (zero is empty).
    static func quantity(_ hex: String) -> [UInt8]? {
        guard hex.count > 2, let b = bytes(hex), b.count <= 32 else { return nil }
        return stripped(b)
    }

    static func hex(_ bytes: [UInt8]) -> String {
        "0x" + bytes.map { String(format: "%02x", $0) }.joined()
    }
}
