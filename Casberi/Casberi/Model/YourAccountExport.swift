import Foundation
import Security
import P256K

/// **A PRIVATE KEY TO TAKE AWAY (prd §1493, user: "i'd rather them have a
/// private key to export and not a phrase").** The account is a Safe, so no
/// key it already has can leave: this phone's lives in the Secure Enclave and
/// the recovery key is a raw P-256 key only Casberi reads (§1421 item 2 was
/// wrong to call it the way out). Export CREATES a secp256k1 key in memory,
/// adds its address as an owner at the network's own threshold (§1456 item 3:
/// never lower), and shows the 64 hex characters once. Any wallet imports it
/// as a private key; Safe's app then opens the account with it.
///
/// Nothing secret is stored: the key's bytes live only in the `Key` handed to
/// the page, and only the ADDRESS is remembered — so this phone can tell an
/// exported key from a Signer, which is also a plain-key owner. The record is
/// this device's: a phone the account was recovered to reads the key as a
/// Signer.
enum YourAccountExport {
    typealias Network = YourAccountOp.Network

    /// Where an exported key goes: every network but Robinhood, which Safe's
    /// own app is not known to open — a key there would own something no
    /// other wallet reaches.
    static func eligible(_ net: Network) -> Bool { net.chainId != YourAccountOp.robinhood.chainId }

    /// The key, held for the one page that shows it.
    struct Key: Equatable {
        let address: String
        /// 64 lowercase hex characters, no `0x` — what "Import private key"
        /// takes in MetaMask, Rabby and Rainbow.
        let hex: String
        /// The same, in four groups of sixteen, for reading off a screen.
        var grouped: String {
            stride(from: 0, to: hex.count, by: 16).map { i in
                let start = hex.index(hex.startIndex, offsetBy: i)
                return String(hex[start..<hex.index(start, offsetBy: 16)])
            }.joined(separator: " ")
        }
    }

    enum Failure: Error { case curve }

    /// A new key from `SecRandomCopyBytes`; a value outside the curve's order
    /// is re-drawn, never clamped (as `SignerKey.create`).
    static func create() throws -> Key {
        for _ in 0..<8 {
            var bytes = [UInt8](repeating: 0, count: 32)
            guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw Failure.curve }
            defer { for i in bytes.indices { bytes[i] = 0 } }
            guard let key = try? P256K.Recovery.PrivateKey(dataRepresentation: bytes, format: .uncompressed) else { continue }
            guard let address = SignerKey.ethereumAddress(uncompressedPublicKey: [UInt8](key.publicKey.dataRepresentation))
            else { throw Failure.curve }
            return Key(address: address, hex: Keccak256.hexString([UInt8](key.dataRepresentation)))
        }
        throw Failure.curve
    }

    // MARK: - Which owners were exported

    private static func defaultsKey(_ account: String) -> String { "yourAccount.exported.\(account.lowercased())" }

    static func exported(for account: String) -> [String] {
        UserDefaults.standard.stringArray(forKey: defaultsKey(account)) ?? []
    }

    static func isExported(_ owner: String, for account: String) -> Bool {
        exported(for: account).contains { $0.caseInsensitiveCompare(owner) == .orderedSame }
    }

    /// Noted BEFORE the key goes on, so a crash between landing and the page
    /// never leaves an exported key read as a Signer.
    static func note(_ address: String, for account: String) {
        guard !isExported(address, for: account) else { return }
        UserDefaults.standard.set(exported(for: account) + [address], forKey: defaultsKey(account))
    }

    static func forget(_ address: String, for account: String) {
        UserDefaults.standard.set(exported(for: account).filter { $0.caseInsensitiveCompare(address) != .orderedSame },
                                  forKey: defaultsKey(account))
    }
}
