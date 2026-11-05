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
        // **BOTH KEYS WHERE THE ACCOUNT ASKS FOR BOTH (prd §1700e, user: "cosigner
        // is good b/c that's what user has chosen to be on").** At threshold 2
        // one key's signature is refused by the account itself (seen on the
        // phone, Human Passport's sign-in, 2026-11-04), so the Signer signs the
        // same SafeMessage, asked through its wallet as a send asks it.
        var signature: [UInt8]
        if try await Chain.threshold(net, account) >= 2 {
            guard let coSigner = await Chain.defaultCoSigner(net, account) else {
                throw Failure(message: String(localized: "Your account needs your Signer too, and none is set on \(net.name)"))
            }
            guard let typed = safeMessageTypedData(hash: hash, chainId: net.chainId, account: account),
                  let messageHash = SafeMessageEncoder.safeMessageHash(chainId: net.chainId, safe: account, message: hash),
                  YourAccountSignerProof.digest(typed) == messageHash else {
                throw Failure(message: "The message could not be wrapped")
            }
            let ecdsa = try await coSigner.sign(messageHash, typed)
            // `bothSignatures` is a SafeOp's: its 12 bytes of time bounds are
            // the 4337 module's and no part of an ERC-1271 signature.
            guard let both = YourAccountOp.bothSignatures(r: r, s: s, owner: signer.owner, signer: coSigner.owner, ecdsa: ecdsa) else {
                throw Failure(message: "The signature could not be written")
            }
            signature = Array(both.dropFirst(12))
        } else {
            guard let one = envelope(r: r, s: s, owner: signer.owner) else {
                throw Failure(message: "The signature could not be written")
            }
            signature = one
        }
        // **THROUGH THE 7579 ADAPTER, A VALIDATOR FIRST (prd §1700e).** Once the
        // adapter is the account's fallback handler (the spend limit, §1447
        // item 11) its `isValidSignature` reads the first 20 bytes as a
        // validator module; zero is none, and the rest goes to Safe's own
        // `checkSignatures` over the same SafeMessage (Safe7579.sol, read
        // 2026-11-04). Without them every signature was read 20 bytes off:
        // GS026 on the phone, Human Passport's sign-in.
        if try await Chain.knownEntry(net, account) == .adapter {
            signature = [UInt8](repeating: 0, count: 20) + signature
        }
        guard let check = isValidSignatureCalldata(hash: hash, signature: signature) else {
            throw Failure(message: "The signature could not be written")
        }
        let answer: String
        do {
            answer = try await Chain.ethCall(net, to: account, data: check)
        } catch {
            // What the account refused, for replaying it off the phone: the
            // hash and the signature are public, and this one is void.
            NSLog("yourAccountMessage| refused | %@ | chain %d | hash %@ | sig %@", AztecEngine.words(error), net.chainId,
                  hash.map { String(format: "%02x", $0) }.joined(), signature.map { String(format: "%02x", $0) }.joined())
            throw error
        }
        guard SafeWebAuthn.isMagic(answer) else {
            throw Failure(message: String(localized: "Your account on \(net.name) did not accept its own signature, so nothing was signed"))
        }
        return signature
    }

    /// The SafeMessage the Signer's wallet signs for `hash` (Safe's
    /// CompatibilityFallbackHandler: `SafeMessage(bytes message)` with the
    /// 32-byte hash as the message, under the Safe's domain), as
    /// `eth_signTypedData_v4` takes it. Its digest is the SafeMessage hash
    /// the passkey signs too; `sign` checks the two agree before asking.
    static func safeMessageTypedData(hash: [UInt8], chainId: Int, account: String) -> String? {
        guard hash.count == 32 else { return nil }
        func field(_ name: String, _ type: String) -> [String: String] { ["name": name, "type": type] }
        let typed: [String: Any] = [
            "types": [
                "EIP712Domain": [field("chainId", "uint256"), field("verifyingContract", "address")],
                "SafeMessage": [field("message", "bytes")],
            ],
            "primaryType": "SafeMessage",
            "domain": ["chainId": chainId, "verifyingContract": account],
            "message": ["message": "0x" + hash.map { String(format: "%02x", $0) }.joined()],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: typed, options: [.sortedKeys]) else { return nil }
        return String(data: data, encoding: .utf8)
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
