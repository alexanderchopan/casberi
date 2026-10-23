import Foundation

/// **YOUR ACCOUNT SIGNS A MESSAGE (prd §1473).** A sign-in and an x402
/// payment are not operations: a site asks the account to prove it holds
/// its key over a hash, and a token's `transferWithAuthorization` takes a
/// signature instead of a transaction. A Safe answers both through ERC-1271
/// (`isValidSignature(bytes32,bytes)` on its fallback handler, Safe's 4337
/// module included): the hash is wrapped as a `SafeMessage` under the Safe's
/// own domain, and the owner's signature over THAT is checked by
/// `checkSignatures` — for this account, Safe's shared passkey signer
/// verifying a WebAuthn assertion by this phone's Enclave key.
///
/// So the bytes are the ones a send already makes (`YourAccountOp.signature`)
/// without the 4337 module's twelve bytes of time bounds, over
/// `SafeStatement.safeMessageHash` instead of a SafeOp. The chain is asked
/// whether the account accepts them before they leave the phone, so a
/// wrong wrapping is a refusal here, never a signature a site holds.
///
/// Only an account that EXISTS on the network can answer: `eth_call` reaches
/// no code at a counterfactual address, and USDC's own check
/// (`SignatureChecker`) wraps nothing in EIP-6492. The first send creates it.
enum YourAccountMessage {
    typealias Chain = YourAccountChain
    typealias Op = YourAccountOp
    typealias Failure = Chain.Failure

    static let magic = SafeWebAuthn.magicValue

    /// `isValidSignature(bytes32,bytes)` calldata over `hash` and `signature`.
    static func isValidSignatureCalldata(hash: [UInt8], signature: [UInt8]) -> [UInt8]? {
        guard hash.count == 32, let offset = SafeABI.word(uint: 64), let length = SafeABI.word(uint: signature.count) else { return nil }
        let padding = (32 - signature.count % 32) % 32
        return YourAccount.sel("isValidSignature(bytes32,bytes)") + hash + offset + length + signature + [UInt8](repeating: 0, count: padding)
    }

    /// The contract signature the Safe's handler accepts for `hash`: the
    /// shared signer's envelope around a WebAuthn assertion whose challenge
    /// is the SafeMessage hash of `hash`.
    static func envelope(r: [UInt8], s: [UInt8], owner: String = YourAccount.sharedSigner) -> [UInt8]? {
        guard let assertion = SafeWebAuthn.signatureBytes(r: r, s: s) else { return nil }
        return SafeWebAuthn.contractSignature(signer: owner, data: assertion)
    }

    /// What the Enclave signs for `hash`: the WebAuthn digest over the
    /// SafeMessage hash of it, under the Safe's domain on `chainId`.
    static func digest(hash: [UInt8], chainId: Int, account: String) -> [UInt8]? {
        guard let message = SafeMessageEncoder.safeMessageHash(chainId: chainId, safe: account, message: hash) else { return nil }
        return SafeWebAuthn.signingDigest(challenge: message)
    }

    /// Signs `hash` for the account on `net` behind Face ID, and hands back
    /// the signature only once the account itself has said it is valid.
    static func sign(hash: [UInt8], on net: Op.Network, account: String, reason: String) async throws -> [UInt8] {
        guard hash.count == 32 else { throw Failure(message: "Not a 32-byte hash") }
        guard try await Chain.isDeployed(net, account) else {
            throw Failure(message: String(localized: "Your account is not on \(net.name) yet. Send something once first"))
        }
        let (_, signer) = try await Chain.deviceSigner(net, account, deployed: true)
        guard let digest = digest(hash: hash, chainId: net.chainId, account: account) else {
            throw Failure(message: "The message could not be wrapped")
        }
        let (r, s) = try await signer.sign(digest, reason)
        guard let signature = envelope(r: r, s: s, owner: signer.owner),
              let check = isValidSignatureCalldata(hash: hash, signature: signature) else {
            throw Failure(message: "The signature could not be written")
        }
        let answer = try await Chain.ethCall(net, to: account, data: check)
        guard SafeWebAuthn.isMagic(answer) else {
            throw Failure(message: String(localized: "Your account on \(net.name) did not accept its own signature, so nothing was signed"))
        }
        return signature
    }

    /// A personal message (EIP-191), signed as above.
    static func signText(_ text: String, on net: Op.Network, account: String, reason: String) async throws -> [UInt8] {
        try await sign(hash: EIP191.hash(text: text), on: net, account: account, reason: reason)
    }

    /// Typed data (EIP-712), as `eth_signTypedData_v4` takes it, signed as above.
    static func signTypedData(_ typedData: Any, on net: Op.Network, account: String, reason: String) async throws -> [UInt8] {
        guard let td = EIP712.parse(typedData), let digest = EIP712.digest(td) else {
            throw Failure(message: "The typed data could not be read")
        }
        return try await sign(hash: digest, on: net, account: account, reason: reason)
    }
}
