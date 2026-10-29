import CryptoKit
import Foundation
import Security

/// A payment app's signed-in session, sealed so only Peer's enclave can read
/// it (prd §1598 item 2). The enclave proves the payment from the session and
/// signs a receipt Peer's contract accepts; nothing on this phone or between
/// it and the enclave can read the cookies once they are sealed here.
///
/// The format is RFC 7516 compact JWE, exactly as `@zkp2p/zkp2p-attestation`
/// 3.1.0's `jwe/encrypt.ts` writes it:
///   protected  {"alg":"RSA-OAEP-256","enc":"A256GCM"}, a constant
///   key        a fresh 32-byte AES key, RSA-OAEP with SHA-256 and MGF1-SHA-256
///   iv         12 fresh bytes
///   aad        the ASCII of the base64url protected header
///   output     header.key.iv.ciphertext.tag, unpadded base64url
///
/// The plaintext names the platform, the action, the session (every captured
/// header, `Cookie`, and `body` when the request had one; never the URL —
/// the enclave rebuilds the request from the template) and the SHA-256 of the
/// enclave key it was sealed to. It carries no nonce and no id: the enclave's
/// schema refuses extra fields, so a sealed session is good for as long as
/// the payment app's session is, and is sent once, to the verify call, and
/// never stored (docs/peer-spec.md "Measured, 2026-10-28").
enum PeerSessionEnvelope {

    static let protectedHeader = "eyJhbGciOiJSU0EtT0FFUC0yNTYiLCJlbmMiOiJBMjU2R0NNIn0"

    struct Failure: Error {}

    static func plaintext(platform: String, actionType: String,
                          session: [String: String], boundKeyHex: String) throws -> Data {
        let object: [String: Any] = ["platform": platform,
                                     "actionType": actionType,
                                     "sessionMaterial": session,
                                     "boundPubKeySha256": boundKeyHex]
        return try JSONSerialization.data(withJSONObject: object,
                                          options: [.sortedKeys, .withoutEscapingSlashes])
    }

    /// Seal `plaintext` to `key`. `contentKey` and `iv` are for the
    /// self-test only; a real seal always draws both fresh.
    static func seal(_ plaintext: Data, to key: SecKey,
                     contentKey: SymmetricKey = SymmetricKey(size: .bits256),
                     iv: AES.GCM.Nonce = AES.GCM.Nonce()) throws -> String {
        guard SecKeyIsAlgorithmSupported(key, .encrypt, .rsaEncryptionOAEPSHA256) else { throw Failure() }
        let cek = contentKey.withUnsafeBytes { Data($0) }
        guard cek.count == 32,
              let wrapped = SecKeyCreateEncryptedData(key, .rsaEncryptionOAEPSHA256, cek as CFData, nil) as Data?
        else { throw Failure() }
        let box = try AES.GCM.seal(plaintext, using: contentKey, nonce: iv,
                                   authenticating: Data(protectedHeader.utf8))
        return [protectedHeader, base64url(wrapped), base64url(Data(iv)),
                base64url(box.ciphertext), base64url(box.tag)].joined(separator: ".")
    }

    /// A session sealed to a key the enclave just proved, in one call.
    static func seal(platform: String, actionType: String,
                     session: [String: String], to key: PeerAttestation.Key) throws -> String {
        try seal(plaintext(platform: platform, actionType: actionType,
                           session: session, boundKeyHex: key.boundKeyHex),
                 to: key.publicKey)
    }

    static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
