import Foundation

/// **A Signer is a key that answered, not an address a wallet named (prd
/// §1516).** A WalletConnect session's account list is the wallet's word: a
/// watch-only address, the wrong one of several, or a smart wallet not
/// deployed yet (no code, so `isContract` passes) all connect, and none can
/// sign for the account. Added anyway, the Signer exists on paper, and once
/// Require both is on every operation waits on a key nobody holds.
///
/// So before an address becomes a key, its wallet signs this typed data
/// once, and the signature must recover to that address — plain ECDSA, the
/// form the account's `checkSignatures` will later need from it. A
/// contract's ERC-1271 or ERC-6492 answer is not 65 bytes, and is refused.
///
/// Foundation-only and pure, compiled WHOLE by
/// `scripts/signer-proof-selftest.sh`; the digest is `EIP712.digest` of the
/// very JSON the wallet is shown (the encoder pinned to the spec's vector by
/// `safe-signer-selftest.sh`), so what is checked is what was signed.
enum YourAccountSignerProof {
    /// What the wallet shows above the fields.
    static let statement = "Add this wallet as a key to your Casberi account"

    /// The request `eth_signTypedData_v4` carries: the account, the key, a
    /// fresh 32-byte challenge, under Casberi's own domain on `chainId` (no
    /// verifying contract: nothing on chain ever reads it).
    static func typedData(account: String, signer: String, chainId: Int, challenge: [UInt8]) -> String? {
        guard challenge.count == 32,
              SafeABI.word(address: account) != nil, SafeABI.word(address: signer) != nil else { return nil }
        func field(_ name: String, _ type: String) -> [String: String] { ["name": name, "type": type] }
        let typed: [String: Any] = [
            "types": [
                "EIP712Domain": [field("name", "string"), field("version", "string"), field("chainId", "uint256")],
                "AddKey": [field("statement", "string"), field("account", "address"),
                           field("key", "address"), field("challenge", "bytes32")],
            ],
            "primaryType": "AddKey",
            "domain": ["name": "Casberi", "version": "1", "chainId": chainId],
            "message": ["statement": statement, "account": account, "key": signer,
                        "challenge": SafeABI.hex(challenge)],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: typed, options: [.sortedKeys]) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// The 32 bytes the wallet signed for `typedData`.
    static func digest(_ typedData: String) -> [UInt8]? {
        EIP712.parse(typedData).flatMap(EIP712.digest)
    }

    enum Verdict: Equatable {
        case holds
        /// Recovered, to another address: the wallet signed with a key that
        /// is not the Signer's.
        case otherKey(String)
        /// Not a plain signature by any key (a contract's answer, or bytes).
        case unreadable
    }

    /// Whether `recovered` (nil when nothing recovered) is `signer`.
    static func verdict(signer: String, recovered: String?) -> Verdict {
        guard let recovered else { return .unreadable }
        return recovered.caseInsensitiveCompare(signer) == .orderedSame ? .holds : .otherKey(recovered)
    }

    /// The network the proof is asked on: Base when the wallet agreed to it,
    /// else the lowest it did. An EOA's key is the same on every chain.
    static func chain(of agreed: Set<Int>, preferring base: Int) -> Int? {
        agreed.contains(base) ? base : agreed.min()
    }
}
