import Foundation
import P256K

/// The one curve operation Fileverse's read needs (prd §1346): the compressed
/// ECDH point of a portal's key and a lock's ephemeral public key, which
/// `FileverseCrypto.openLock` hashes into the lock's AES key. Kept apart from
/// `FileverseCrypto` because it needs libsecp256k1, which the shell harness
/// cannot link; `CasberiTests/FileverseKeyTests` holds it to Fileverse's
/// own vector.
enum FileverseKey {
    /// `appDecryptionKey` is the 32-byte scalar itself (measured: its public
    /// key equals the page's `appEncryptionKey`). Nil for anything else.
    static func sharedPoint(scalar: Data) -> (Data) -> Data? {
        let secret = [UInt8](scalar)
        return { eph in
            guard secret.count == 32,
                  let pub = try? P256K.Signing.PublicKey(dataRepresentation: [UInt8](eph), format: .compressed),
                  let product = try? pub.multiply(secret, format: .compressed) else { return nil }
            return Data(product.dataRepresentation)
        }
    }

    /// Whether a scalar's compressed public key is `publicKey` — the check
    /// the connect runs before keeping a key it read off the page.
    static func matches(scalar: Data, publicKey: Data) -> Bool {
        guard let key = try? P256K.Signing.PrivateKey(dataRepresentation: [UInt8](scalar), format: .compressed) else {
            return false
        }
        return Data(key.publicKey.dataRepresentation) == publicKey
    }
}
