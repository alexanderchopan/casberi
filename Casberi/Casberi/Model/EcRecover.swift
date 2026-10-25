import Foundation
import P256K

/// **Ethereum's `ecrecover`, the one curve call every check shares.** Split
/// out so the files that decide what to do with an address stay
/// Foundation-only and their harnesses compile them whole; each harness
/// stubs what it reaches here with a refusal. The recovery itself is
/// exercised against a real key in `CasberiTests`.
enum EcRecover {
    /// The address whose key made `signature` (Ethereum's `r ‖ s ‖ v`, `v`
    /// 27/28 or a bare 0/1) over the 32-byte `digest`, lowercase, or nil.
    static func address(digest: [UInt8], signature: [UInt8]) -> String? {
        guard digest.count == 32, signature.count == 65 else { return nil }
        let recoveryID = signature[64] >= 27 ? Int32(signature[64]) - 27 : Int32(signature[64])
        guard recoveryID == 0 || recoveryID == 1 else { return nil }
        guard let compact = try? P256K.Recovery.ECDSASignature(
                  compactRepresentation: Data(signature[0..<64]), recoveryId: recoveryID),
              let key = try? P256K.Recovery.PublicKey(HashDigest(digest), signature: compact,
                                                      format: .uncompressed)
        else { return nil }
        let bytes = [UInt8](key.dataRepresentation)
        guard bytes.count == 65, bytes[0] == 0x04 else { return nil }
        let hash = Keccak256.hash(Array(bytes.dropFirst()))
        return "0x" + Keccak256.hexString(Array(hash.suffix(20)))
    }
}
