import Foundation

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
        guard let raw = hexBytes(signatureHex) else { return nil }
        return EcRecover.address(digest: personalSignDigest(message), signature: raw)
    }

}
