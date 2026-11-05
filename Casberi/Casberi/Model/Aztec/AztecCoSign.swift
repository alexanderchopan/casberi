import Foundation

/// **THE CO-SIGNER APPROVES AZTEC TOO (prd §1700f item 4).** With the
/// co-signer on (your Safe at two keys), every transaction your Aztec account
/// makes — a private send, the exit's Aztec half, an Aztec app's — first asks
/// the Signer to sign a readable statement of it, through its wallet as a send
/// asks it, and Casberi checks the signature is the Signer's before proving.
/// Aztec does not enforce it: Casberi does, and the key it guards lives in
/// iCloud Keychain under Casberi's own group and leaves only through Reveal
/// key, which asks the same. A claim of your own deposit is not asked: it only
/// brings your own money in.
enum AztecCoSign {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// What the Signer's wallet shows above the fields.
    static let statement = "Approve this Aztec transaction from your Casberi account"

    /// The statement as `eth_signTypedData_v4` takes it: what it does, the
    /// Aztec account, a fresh challenge, under Casberi's domain on Ethereum.
    static func typedData(action: String, aztec: String, challenge: [UInt8]) -> String? {
        guard challenge.count == 32 else { return nil }
        func field(_ name: String, _ type: String) -> [String: String] { ["name": name, "type": type] }
        let typed: [String: Any] = [
            "types": [
                "EIP712Domain": [field("name", "string"), field("version", "string"), field("chainId", "uint256")],
                "AztecApproval": [field("statement", "string"), field("action", "string"),
                                  field("aztecAccount", "bytes32"), field("challenge", "bytes32")],
            ],
            "primaryType": "AztecApproval",
            "domain": ["name": "Casberi", "version": "1", "chainId": 1],
            "message": ["statement": statement, "action": action, "aztecAccount": aztec.lowercased(),
                        "challenge": "0x" + challenge.map { String(format: "%02x", $0) }.joined()],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: typed, options: [.sortedKeys]) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Asks the Signer to approve `action` when the co-signer is on; returns
    /// at once when it is off. Fails closed: an unread threshold, no Signer,
    /// a refusal or a signature by any other key stops the transaction.
    @MainActor
    static func approve(_ action: String) async throws {
        guard let safe = YourAccountKey.address else { return }
        let net = YourAccountOp.ethereum
        let threshold: Int
        do { threshold = try await YourAccountChain.threshold(net, safe) } catch {
            throw Failure(message: String(localized: "Could not read whether your co-signer is on, so nothing was sent"))
        }
        guard threshold >= 2 else { return }
        guard let coSigner = await YourAccountChain.defaultCoSigner(net, safe) else {
            throw Failure(message: String(localized: "Your co-signer approves this, and none is set"))
        }
        var challenge = [UInt8](repeating: 0, count: 32)
        var aztec = AztecAccountStore.shared.snapshot.address
        if aztec == nil { aztec = try? await AztecEngine.shared.accountAddress() }
        guard SecRandomCopyBytes(kSecRandomDefault, 32, &challenge) == errSecSuccess,
              let aztec,
              let typed = typedData(action: action, aztec: aztec, challenge: challenge),
              let digest = YourAccountSignerProof.digest(typed) else {
            throw Failure(message: String(localized: "This could not be written"))
        }
        let signature = try await coSigner.sign(digest, typed)
        guard EcRecover.address(digest: digest, signature: signature)?.caseInsensitiveCompare(coSigner.owner) == .orderedSame else {
            throw Failure(message: String(localized: "That wallet is not your co-signer, so nothing was sent"))
        }
    }
}
