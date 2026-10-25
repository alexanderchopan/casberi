import Foundation

/// **THE CO-SIGNER'S CHECKS (prd §1509 item 3, Phase 3 of
/// `docs/signing-safety-spec.md`).** Signing for someone else's Safe gains
/// three things: pairing asks Reown Verify where the request really came
/// from (a site's own metadata can claim any name), an unlimited approval is
/// a red line in words, and the sign block's Details carries the nonce and
/// the EIP-712 hashes Safe's app and hardware wallets show.
///
/// Pure (Foundation and the Safe encoders), held by
/// `safe-sign-checks-selftest.sh`; `SafePeer` and `SafeSignBlock` draw it.
enum SafeSignChecks {

    // MARK: - Pairing (Reown Verify)

    /// What Verify said about a pairing, in the words the pair block draws.
    enum Pairing: Equatable, Sendable {
        /// The request came from the site it names: nothing new is drawn.
        case confirmed
        /// Verify could not say (no attestation, a mismatch, no answer).
        case unconfirmed(claimed: String)
        /// Reported as a scam by Verify: what it says it is, and where it
        /// really came from when Verify knows.
        case scam(claimed: String, says: String, really: String?)

        var red: Bool { if case .scam = self { true } else { false } }
    }

    /// Verify's `validation` (reown-swift 2.3.0's `VerifyContext`: valid,
    /// invalid, unknown, scam), spelled as text so this file needs no SDK. A
    /// missing context reads as unknown (the spec's rule).
    static func pairing(validation: String?, origin: String?, claimedURL: String, claimedName: String) -> Pairing {
        let claimed = host(claimedURL) ?? claimedURL
        switch validation {
        case "valid": return .confirmed
        case "scam": return .scam(claimed: claimed, says: claimedName.isEmpty ? claimed : claimedName,
                                  really: origin.flatMap(host))
        default: return .unconfirmed(claimed: claimed)
        }
    }

    /// The host of a URL or a bare domain, lowercased, without `www.`.
    static func host(_ text: String) -> String? {
        let withScheme = text.contains("://") ? text : "https://" + text
        guard var h = URL(string: withScheme)?.host?.lowercased(), !h.isEmpty else { return nil }
        if h.hasPrefix("www.") { h.removeFirst(4) }
        return h
    }

    /// The line the pair block draws (canvas figure 10); nil when confirmed.
    static func line(_ p: Pairing) -> String? {
        switch p {
        case .confirmed: nil
        case .unconfirmed(let claimed): String(localized: "Couldn't confirm it's \(claimed)")
        case .scam(let claimed, _, _): String(localized: "Reported as a scam site. It isn't \(claimed).")
        }
    }

    // MARK: - Unlimited approvals

    /// A call that lets `spender` take everything of `token`, with no end:
    /// an ERC-20 `approve` or `increaseAllowance` for an amount no supply
    /// reaches, Permit2's `approve` for the most a uint160 holds, or
    /// `setApprovalForAll(…, true)` on a collection.
    struct Unlimited: Equatable, Sendable {
        let spender: String
        let token: String
        let collection: Bool
    }

    static let permit2 = "0x000000000022d473030f116ddee9f6b43ac78ba3"

    /// Selectors, by signature: approve(address,uint256), increaseAllowance(
    /// address,uint256), setApprovalForAll(address,bool), Permit2's
    /// approve(address,address,uint160,uint48).
    static let approve = "095ea7b3", increase = "39509351", forAll = "a22cb465", permit2Approve = "87517c45"

    /// An amount is "all of it" at 2^128 or more: no token's supply in base
    /// units comes near (1e38; Shiba Inu's is about 1e33), and every
    /// "unlimited" a dapp asks for, `type(uint256).max` included, is far above.
    static func isUnbounded(_ word: ArraySlice<UInt8>) -> Bool {
        word.count == 32 && word.prefix(16).contains { $0 != 0 }
    }

    static func unlimited(to: String, data: [UInt8]) -> Unlimited? {
        guard data.count >= 4 else { return nil }
        let selector = Keccak256.hexString(Array(data.prefix(4)))
        let args = Array(data.dropFirst(4))
        func word(_ i: Int) -> ArraySlice<UInt8>? { args.count >= (i + 1) * 32 ? args[(i * 32)..<((i + 1) * 32)] : nil }
        func address(_ i: Int) -> String? {
            guard let w = word(i), w.prefix(12).allSatisfy({ $0 == 0 }) else { return nil }
            return "0x" + Keccak256.hexString(Array(w.suffix(20)))
        }
        switch selector {
        case approve, increase:
            guard let spender = address(0), let amount = word(1), isUnbounded(amount) else { return nil }
            return Unlimited(spender: spender, token: to.lowercased(), collection: false)
        case forAll:
            guard let spender = address(0), let on = word(1), on.last == 1, on.dropLast().allSatisfy({ $0 == 0 }) else { return nil }
            return Unlimited(spender: spender, token: to.lowercased(), collection: true)
        case permit2Approve where to.lowercased() == permit2:
            // uint160 max: twelve zero bytes then twenty 0xff.
            guard let token = address(0), let spender = address(1), let amount = word(2),
                  amount.prefix(12).allSatisfy({ $0 == 0 }), amount.suffix(20).allSatisfy({ $0 == 0xff }) else { return nil }
            return Unlimited(spender: spender, token: token, collection: false)
        default:
            return nil
        }
    }

    /// "Lets 0xdef1…c0de spend all of this Safe's USDC, with no end."
    static func line(_ u: Unlimited, spender: String, token: String) -> String {
        u.collection
            ? String(localized: "Lets \(spender) move all of this Safe's \(token), with no end.")
            : String(localized: "Lets \(spender) spend all of this Safe's \(token), with no end.")
    }

    // MARK: - The hashes (ERC-8213's terms)

    /// The three hashes Safe's app and a hardware wallet show: the EIP-712
    /// Digest (what Safe calls the safeTxHash), the Domain Hash and the
    /// Message Hash. ERC-8213 forbids showing either of the last two alone;
    /// the digest leads.
    struct Hashes: Equatable, Sendable {
        let digest: [UInt8]
        let domain: [UInt8]
        let message: [UInt8]
    }

    static func hashes(chainId: Int, safe: String, tx: SafeTransaction) -> Hashes? {
        guard let domain = SafeTxEncoder.domainSeparator(chainId: chainId, safe: safe),
              let message = SafeTxEncoder.structHash(tx),
              let digest = SafeTxEncoder.safeTxHash(chainId: chainId, safe: safe, tx: tx) else { return nil }
        return Hashes(digest: digest, domain: domain, message: message)
    }
}
