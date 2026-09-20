import Foundation
import P256K

/// **The one curve operation in the verification** — split from
/// `NearAIVerify` so that file stays Foundation-only and its decision logic can
/// be compiled whole by `scripts/nearai-verify-selftest.sh`, which has no
/// libsecp256k1. The harness supplies its own refusing stub of this extension;
/// the real recovery is exercised against a real signature in `CasberiTests`.
extension NearAIVerify {
    /// The address that signed `message`, or nil.
    ///
    /// `signatureHex` is Ethereum's `r ‖ s ‖ v` — the opposite order to the
    /// `v ‖ r ‖ s` the devnet keys serialize, so the `v` is taken off the END
    /// here. It arrives as 27/28 (EIP-191's offset) or as a bare 0/1; both are
    /// normalized to the recovery id libsecp256k1 wants.
    static func recoverSigner(message: String, signatureHex: String) -> String? {
        guard let raw = hexBytes(signatureHex), raw.count == 65 else { return nil }
        let recoveryID = raw[64] >= 27 ? Int32(raw[64]) - 27 : Int32(raw[64])
        guard recoveryID == 0 || recoveryID == 1 else { return nil }

        let digest = personalSignDigest(message)
        guard let signature = try? P256K.Recovery.ECDSASignature(
                  compactRepresentation: Data(raw[0..<64]), recoveryId: recoveryID),
              let key = try? P256K.Recovery.PublicKey(HashDigest(digest), signature: signature,
                                                      format: .uncompressed)
        else { return nil }

        let bytes = [UInt8](key.dataRepresentation)
        guard bytes.count == 65, bytes[0] == 0x04 else { return nil }
        let hash = Keccak256.hash(Array(bytes.dropFirst()))
        return "0x" + Keccak256.hexString(Array(hash.suffix(20)))
    }

}
