import CryptoKit
import Foundation

/// The account's only key: a P-256 key in this phone's Secure Enclave.
///
/// Aztec's P-256 account checks the signature over sha256(message hash), which
/// is what the Enclave signs when handed the 32 hash bytes. The account
/// circuit accepts low-S signatures only (measured, prd §1276), so a high S is
/// flipped to n − S.
enum EnclaveKey {
    private static let storeKey = "aztec-spike.enclave-key"
    private static let softwareKey = "aztec-spike.software-key"

    /// False in the simulator, which has no Secure Enclave: there the key is an
    /// ordinary P-256 key, so the page can still be checked end to end.
    static var inEnclave: Bool { SecureEnclave.isAvailable }

    static func enclaveKey() throws -> SecureEnclave.P256.Signing.PrivateKey {
        if let blob = UserDefaults.standard.data(forKey: storeKey) {
            return try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: blob)
        }
        let made = try SecureEnclave.P256.Signing.PrivateKey()
        UserDefaults.standard.set(made.dataRepresentation, forKey: storeKey)
        return made
    }

    static func software() throws -> P256.Signing.PrivateKey {
        if let raw = UserDefaults.standard.data(forKey: softwareKey) {
            return try P256.Signing.PrivateKey(rawRepresentation: raw)
        }
        let made = P256.Signing.PrivateKey()
        UserDefaults.standard.set(made.rawRepresentation, forKey: softwareKey)
        return made
    }

    /// x ‖ y, 128 hex characters.
    static func publicKeyHex() throws -> String {
        let raw = inEnclave ? try enclaveKey().publicKey.rawRepresentation : try software().publicKey.rawRepresentation
        return raw.map { String(format: "%02x", $0) }.joined()
    }

    static func sign(_ messageHash: Data) throws -> Data {
        let raw = inEnclave ? try enclaveKey().signature(for: messageHash).rawRepresentation
                            : try software().signature(for: messageHash).rawRepresentation
        return raw.prefix(32) + lowS(raw.suffix(32))
    }

    private static let n: [UInt8] = [
        0xff, 0xff, 0xff, 0xff, 0x00, 0x00, 0x00, 0x00, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xbc, 0xe6, 0xfa, 0xad, 0xa7, 0x17, 0x9e, 0x84, 0xf3, 0xb9, 0xca, 0xc2, 0xfc, 0x63, 0x25, 0x51,
    ]

    /// S when S ≤ n/2, else n − S; always 32 bytes.
    private static func lowS(_ s: Data) -> Data {
        let s = [UInt8](s)
        var half = [UInt8](repeating: 0, count: 32)
        var carry: UInt8 = 0
        for i in 0..<32 { // n >> 1
            half[i] = (n[i] >> 1) | carry
            carry = (n[i] & 1) << 7
        }
        if !s.lexicographicallyPrecedes(half) && s != half {
            var out = [UInt8](repeating: 0, count: 32)
            var borrow = 0
            for i in stride(from: 31, through: 0, by: -1) {
                var d = Int(n[i]) - Int(s[i]) - borrow
                borrow = d < 0 ? 1 : 0
                if d < 0 { d += 256 }
                out[i] = UInt8(d)
            }
            return Data(out)
        }
        return Data(s)
    }
}
