import Foundation
import CryptoKit

/// A TACIT ACCOUNT'S KEY, FROM THE WALLET THAT OPENED IT.
///
/// Every Tacit app makes an account's key the same way (`dapp/evm-wallet.js`,
/// pinned by Tacit's own `tests/identity-message.test.mjs`): the wallet signs
/// one fixed message with `personal_sign`, and the key is SHA-256 of that
/// 65-byte signature. So the same wallet opens the same account anywhere,
/// and Casberi opens the account a person ALREADY has: it never makes one.
///
/// The signature is the key. Whoever holds it controls the account's money,
/// which is what Tacit's message tells the person signing. Casberi asks for
/// it only to read: nothing here, and nothing in the engine, can send.
///
/// Pure (Foundation + CryptoKit + `Keccak256`).
enum TacitIdentity {

    /// Tacit's identity message for mainnet, byte for byte. Changing a
    /// character opens a different, empty account.
    static let message = [
        "Tacit identity",
        "",
        "Signing this creates your Tacit private key. Anyone who has this signature controls all of your Tacit funds.",
        "",
        "Sign it only in a Tacit app you trust. Every Tacit app asks for exactly this message.",
        "",
        "network: mainnet",
        "version: 1",
    ].joined(separator: "\n")

    /// `personal_sign`'s first parameter: the message's bytes, 0x-hex.
    static var messageHex: String {
        "0x" + Array(message.utf8).map { String(format: "%02x", $0) }.joined()
    }

    /// What the wallet signs (EIP-191): the digest a signature must recover
    /// the wallet's address from.
    static var digest: [UInt8] {
        let body = Array(message.utf8)
        return Keccak256.hash(Array("\u{19}Ethereum Signed Message:\n\(body.count)".utf8) + body)
    }

    enum Failure: Error, Equatable {
        /// Not 65 bytes, or `v` is not 27 or 28.
        case malformed
        /// A high-s signature: Tacit refuses it (hashing it would open a
        /// different, empty account), and so does Casberi.
        case notCanonical
    }

    private static let order: [UInt8] = [
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xfe,
        0xba, 0xae, 0xdc, 0xe6, 0xaf, 0x48, 0xa0, 0x3b, 0xbf, 0xd2, 0x5e, 0x8c, 0xd0, 0x36, 0x41, 0x41,
    ]
    /// Half the curve's order: an `s` above it is the high form.
    private static let halfOrder: [UInt8] = [
        0x7f, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0x5d, 0x57, 0x6e, 0x73, 0x57, 0xa4, 0x50, 0x1d, 0xdf, 0xe9, 0x2f, 0x46, 0x68, 0x1b, 0x20, 0xa0,
    ]

    /// Big-endian a > b, both 32 bytes.
    private static func greater(_ a: [UInt8], _ b: [UInt8]) -> Bool {
        for (x, y) in zip(a, b) where x != y { return x > y }
        return false
    }

    /// The account's 32-byte key from the wallet's signature (`r ‖ s ‖ v`,
    /// `v` 27 or 28 as `YourAccountSignerLink.normalized` leaves it).
    static func key(fromSignature signature: [UInt8]) throws -> [UInt8] {
        guard signature.count == 65, signature[64] == 27 || signature[64] == 28 else { throw Failure.malformed }
        guard !greater(Array(signature[32..<64]), halfOrder) else { throw Failure.notCanonical }
        return scalar(Array(SHA256.hash(data: signature)))
    }

    /// Tacit's `prfBytesToScalar`: the bytes themselves when they are a
    /// valid secp256k1 scalar, else SHA-256 of them with its label, again.
    static func scalar(_ raw: [UInt8]) -> [UInt8] {
        var bytes = raw
        while bytes.allSatisfy({ $0 == 0 }) || !greater(order, bytes) {
            bytes = Array(SHA256.hash(data: bytes + Array("tacit-prf-recovery".utf8)))
        }
        return bytes
    }
}
