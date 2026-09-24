import Foundation

/// The Enclave owner on the chain: its address, whether a chain can take it,
/// and the assertion it makes — verified by the factory BEFORE it leaves
/// (prd §913). `SafeEnclaveKey` holds the key and `SafeWebAuthnSignature`
/// does the arithmetic; this file is where the two meet the network.
///
/// **The address is read, never derived.** `SafeWebAuthnSignerFactory.getSigner`
/// is a CREATE2 over the proxy's creation code, which only the compiler has.
/// One `eth_call` per chain answers it (the factory and singleton sit at one
/// address on every chain they reached, so the answer is the same
/// everywhere — but a cache is per chain anyway, because a chain the factory
/// never reached answers nothing and must not inherit its neighbour's).
///
/// **The route is offered only where it can be checked.** Before the setup
/// screen says "move the key into the vault chip", both the factory and the
/// P-256 fallback verifier must have code on the chain — a Safe naming a
/// proxy whose verifier is absent would reject every signature, which the
/// rail below would catch one signature too late.
///
/// **The rail.** Every assertion goes to `isValidSignatureForSigner` on the
/// factory with the exact bytes about to be handed over, and only the
/// ERC-1271 magic value back lets them leave. A wrong digest, a wrong flag
/// byte, a wrong offset — each is a decline, never a wrong signature.
enum SafeEnclaveSigner {

    private static let addressKeyPrefix = "signer.enclave.address."

    /// The proxy's address on this chain, cached after one read. Nil when
    /// there is no Enclave key or the chain did not answer.
    static func signerAddress(chainId: Int) async -> String? {
        guard let x = SafeEnclaveKey.publicKeyX(), let y = SafeEnclaveKey.publicKeyY() else { return nil }
        let key = addressKeyPrefix + String(chainId)
        if let cached = UserDefaults.standard.string(forKey: key) { return cached }
        guard let calldata = SafeWebAuthn.getSignerCalldata(x: x, y: y),
              let answer = await SafeSigner.ethCall(chainId: chainId, to: SafeWebAuthn.factory, data: calldata),
              let address = SafeWebAuthn.decodeAddress(answer)
        else { return nil }
        UserDefaults.standard.set(address, forKey: key)
        return address
    }

    /// The cached address alone — for a screen, which may not fetch.
    static func cachedAddress(chainId: Int) -> String? {
        UserDefaults.standard.string(forKey: addressKeyPrefix + String(chainId))
    }

    /// Any cached address, for the address book and the "This phone" rows.
    static func anyCachedAddress() -> String? {
        for rail in SafeSigner.chainIDs {
            if let a = cachedAddress(chainId: rail) { return a }
        }
        return nil
    }

    static func forgetAddresses() {
        for chainId in SafeSigner.chainIDs {
            UserDefaults.standard.removeObject(forKey: addressKeyPrefix + String(chainId))
        }
    }

    /// Whether the factory and the fallback verifier both have code on this
    /// chain. `nil` when the chain did not answer — not knowing is not "no".
    static func routeAvailable(chainId: Int) async -> Bool? {
        async let factory = SafeSigner.ethGetCode(chainId: chainId, address: SafeWebAuthn.factory)
        async let verifier = SafeSigner.ethGetCode(chainId: chainId, address: SafeWebAuthn.fallbackVerifier)
        guard let f = await factory, let v = await verifier else { return nil }
        return f.count > 4 && v.count > 4
    }

    /// Whether the proxy itself is deployed — the one step the desktop must
    /// take (`createSigner`) before Safe's service will accept a signature
    /// from it. The Safe contract itself verifies through the proxy too, so
    /// an undeployed proxy is an owner that cannot sign yet.
    static func proxyDeployed(chainId: Int, address: String) async -> Bool? {
        guard let code = await SafeSigner.ethGetCode(chainId: chainId, address: address) else { return nil }
        return code.count > 4
    }

    enum Failure: Error, Equatable {
        case noKey
        case keyRefused(SafeEnclaveKey.Failure)
        case encoding
        /// The factory did not answer the verification read.
        case chainUnreadable
        /// The factory answered and did NOT return the magic value. The
        /// signature is discarded; nothing about it can be trusted.
        case notAccepted
    }

    /// The WebAuthn assertion over `challenge` (a 32-byte hash), verified by
    /// the factory. Returns the ABI-encoded `Signature` bytes — what a
    /// recovery module takes raw, and what `contractSignature` wraps for a
    /// Safe's own `checkNSignatures`.
    static func assert(challenge: [UInt8], chainId: Int, reason: String) async -> Result<[UInt8], Failure> {
        guard let x = SafeEnclaveKey.publicKeyX(), let y = SafeEnclaveKey.publicKeyY() else {
            return .failure(.noKey)
        }
        guard let digest = SafeWebAuthn.signingDigest(challenge: challenge) else { return .failure(.encoding) }
        let rs: (r: [UInt8], s: [UInt8])
        do {
            // Off the main actor: the Keychain read blocks on the Face ID
            // prompt (`SafeSigner.sign`'s reason).
            rs = try await Task.detached(priority: .userInitiated) {
                try SafeEnclaveKey.sign(digest: digest, reason: reason)
            }.value
        } catch let failure as SafeEnclaveKey.Failure {
            return .failure(.keyRefused(failure))
        } catch {
            return .failure(.keyRefused(.signingRefused))
        }
        guard let bytes = SafeWebAuthn.signatureBytes(r: rs.r, s: rs.s),
              let calldata = SafeWebAuthn.isValidSignatureForSignerCalldata(
                message: challenge, signature: bytes, x: x, y: y)
        else { return .failure(.encoding) }
        guard let answer = await SafeSigner.ethCall(chainId: chainId, to: SafeWebAuthn.factory, data: calldata)
        else { return .failure(.chainUnreadable) }
        guard SafeWebAuthn.isMagic(answer) else { return .failure(.notAccepted) }
        return .success(bytes)
    }
}
