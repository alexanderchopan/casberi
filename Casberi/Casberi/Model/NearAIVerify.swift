import CryptoKit
import Foundation

/// **Did the machine that wrote this answer actually sign it?**
///
/// NEAR AI runs its open-weight models inside hardware enclaves. Each enclave
/// publishes a signing address, and signs a short line naming the model and the
/// SHA-256 of the exact request and response bytes. This recovers the signer
/// from that line and compares it to the address the attestation report
/// published — on the phone, with no server and nobody's word for it.
///
/// **What this proves, exactly:** the bytes we received are the bytes some key
/// signed, and that key is the one the attestation report named. That is the
/// whole claim, and the badge says no more than that.
///
/// **What it does NOT prove** (and why the badge is worded the way it is): that
/// the enclave is genuine silicon. Proving THAT means verifying an Intel TDX
/// quote against Intel's provisioning service and an NVIDIA GPU payload against
/// NVIDIA's attestation service — a 98KB upload and two more hosts, neither of
/// which a phone should do per answer. Those reports are fetched and carried
/// (`NearAIAttestation`) so the claim can be raised later without a new shape,
/// but nothing here reads them. An unproven enclave is not a broken one: see
/// `Outcome`, which keeps "could not check" apart from "check failed" for the
/// same reason `SafeServiceGate` does (prd §789).
///
/// Measured against NEAR AI's own reference verifier, 2026-09-20:
/// `near-examples/nearai-cloud-verification-example`.
enum NearAIVerify {

    // MARK: - What a phone can say about one answer

    /// Who the signature claims to come from.
    ///
    /// This is NOT decoration. The two kinds are checked against DIFFERENT
    /// addresses — the model enclave's, or the gateway's — so reading the kind
    /// wrong means checking a signature against a key that was never supposed
    /// to have signed it.
    enum Kind: String, Equatable {
        /// The model enclave itself signed, and its line names the model.
        case providerTEE = "provider_tee"
        /// The gateway enclave signed the bytes it handed us. It happens
        /// whenever the gateway rewrote what the model produced — every stream,
        /// and some plain requests. Real, and weaker: it attests the bytes came
        /// through an attested gateway, not that a named model produced them.
        case gateway
    }

    /// Why a check could not run, or did not pass.
    ///
    /// Each case is a sentence a person could be shown. None of them is
    /// "something went wrong".
    enum Reason: Equatable {
        /// No signature was served for this answer. A model runs on several
        /// enclave nodes and the signature lives on the one that answered, so a
        /// lookup can land elsewhere and find nothing. Not a failure.
        case noSignature
        /// The attestation report did not answer, so there is no address to
        /// check against. Not a failure.
        case noAttestation
        /// The signed line was not in either shape we know.
        case unreadableText(String)
        /// The signature was not 65 bytes of `r ‖ s ‖ v`.
        case unreadableSignature
        /// Recovery ran and produced no key.
        case couldNotRecover
        /// A real key signed, and it is not the attested one. Loud.
        case wrongSigner(recovered: String, expected: [String])
        /// The signature is good and covers bytes that are not ours.
        case wrongBytes(field: String)
        /// The line claims the model enclave signed but its own shape says
        /// otherwise — a gateway signature wearing the stronger kind's clothes.
        case kindDisagrees(claimed: String, text: String)
        /// A valid signature whose line names a model that is neither the one
        /// we asked for nor the one the answer said wrote it.
        ///
        /// Kept apart from `kindDisagrees` because it is a different claim and
        /// would want different words. **UNMEASURED against a real signature:**
        /// no NEAR AI signature has been observed here, so whether the enclave
        /// signs the id we sent (`Qwen/Qwen3.8-27B`) or the weights it loaded
        /// (`Qwen/Qwen3.8-27B-FP8`, its own `hugging_face_id`) is not known.
        /// Both the asked-for id and the ANSWER's own reported id are therefore
        /// accepted, case-insensitively — a normalization difference must not
        /// show somebody a tamper warning on a sound answer.
        case wrongModel(signed: String, expected: [String])
    }

    /// The result. `verified` and `mismatch` both mean the check RAN.
    /// `unchecked` means it did not, and a surface may never draw it as a
    /// failure (prd §83).
    enum Outcome: Equatable {
        case verified(signer: String, kind: Kind)
        case mismatch(Reason)
        case unchecked(Reason)

        var isVerified: Bool { if case .verified = self { return true }; return false }

        /// True only when a check ran and something was wrong. A surface that
        /// warns reads THIS, never `!isVerified`.
        var isMismatch: Bool { if case .mismatch = self { return true }; return false }
    }

    // MARK: - The bytes

    /// SHA-256, lowercase hex — of the exact bytes, never of a re-encoding.
    ///
    /// The enclave hashes the literal body it received and the literal body it
    /// sent. Re-serializing a decoded JSON object here would produce a
    /// different string (key order, spacing, escaping) and every check would
    /// fail for a reason that looks like tampering. Callers hold the `Data`
    /// they actually put on the wire and pass it here unchanged.
    static func hashHex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - The signed line

    /// The line the enclave signed, taken apart.
    struct SignedText: Equatable {
        /// Present only on a model-enclave signature.
        let modelID: String?
        let requestHash: String
        let responseHash: String

        /// The kind the SHAPE implies, independent of what the response claimed.
        var impliedKind: Kind { modelID == nil ? .gateway : .providerTEE }
    }

    /// Parse `{model}:{req}:{resp}` or `{req}:{resp}`.
    ///
    /// Exactly two or three colon-separated parts, matching NEAR AI's own
    /// verifier. No model id in the catalogue contains a colon; parsing from
    /// the right would tolerate one that did, but tolerance here buys nothing
    /// (the hashes still have to be ours) and costs a rule that is harder to
    /// state, so this stays strict and will fail loudly if that ever changes.
    static func parse(_ text: String) -> SignedText? {
        let parts = text.components(separatedBy: ":")
        switch parts.count {
        case 2: return SignedText(modelID: nil, requestHash: parts[0], responseHash: parts[1])
        case 3: return SignedText(modelID: parts[0], requestHash: parts[1], responseHash: parts[2])
        default: return nil
        }
    }

    // MARK: - The digest

    /// EIP-191 `personal_sign`: `keccak256("\u{19}Ethereum Signed Message:\n" + <byte count> + message)`.
    ///
    /// The count is the message's UTF-8 BYTE length, not its character count.
    /// A model id is ASCII today, so the two agree — which is exactly why this
    /// would ship broken and stay broken until the first non-ASCII line.
    static func personalSignDigest(_ message: String) -> [UInt8] {
        let body = Array(message.utf8)
        let prefix = Array("\u{19}Ethereum Signed Message:\n\(body.count)".utf8)
        return Keccak256.hash(prefix + body)
    }

    // MARK: - The recovery
    //
    // `recoverSigner(message:signatureHex:)` lives in `NearAIRecover.swift`,
    // which is the only file here that imports `P256K`. The split is not
    // tidiness: it keeps THIS file Foundation-only, so
    // `scripts/nearai-verify-selftest.sh` can compile the decision logic whole
    // and unmodified against its own refusing stub. A check that can only be
    // exercised by launching the app is a check nobody runs.

    /// Hex to bytes, with or without `0x`. Rejects anything that is not an even
    /// run of hex digits rather than dropping what it cannot read.
    static func hexBytes(_ hex: String) -> [UInt8]? {
        var s = Substring(hex)
        if s.hasPrefix("0x") || s.hasPrefix("0X") { s = s.dropFirst(2) }
        guard s.count % 2 == 0, !s.isEmpty else { return nil }
        var out: [UInt8] = []
        out.reserveCapacity(s.count / 2)
        var index = s.startIndex
        while index < s.endIndex {
            let next = s.index(index, offsetBy: 2)
            guard let byte = UInt8(s[index..<next], radix: 16) else { return nil }
            out.append(byte)
            index = next
        }
        return out
    }

    // MARK: - The check

    /// Everything the phone needs to judge one answer.
    struct Claim: Equatable {
        /// The signed line, verbatim.
        let text: String
        /// `r ‖ s ‖ v`, hex.
        let signature: String
        /// The kind the response declared, if it declared one. Older
        /// signatures omit it and the shape decides.
        let declaredKind: String?
        /// The addresses from the attestation report's `model_attestations`.
        let modelSigners: [String]
        /// The address from the report's `gateway_attestation`.
        let gatewaySigners: [String]
        /// The model we asked for.
        let requestedModelID: String
        /// The model the RESPONSE said actually wrote it (its `model` field),
        /// when it said. Accepted alongside the asked-for id — see
        /// `Reason.wrongModel`.
        let answeredModelID: String?
        /// SHA-256 of the exact bytes we sent.
        let requestHash: String
        /// SHA-256 of the exact bytes we received.
        let responseHash: String
    }

    /// Run the check. Pure — no network, no clock, no store.
    static func check(_ claim: Claim) -> Outcome {
        guard let parsed = parse(claim.text) else {
            return .mismatch(.unreadableText(claim.text))
        }

        // The kind decides WHICH addresses may have signed, so a claimed kind
        // that the line's own shape contradicts is refused before any curve
        // work. Otherwise a gateway signature could be presented as the
        // model enclave's — the stronger claim — and pass against the wrong
        // address set.
        let kind: Kind
        if let declared = claim.declaredKind, !declared.isEmpty {
            guard let named = Kind(rawValue: declared), named == parsed.impliedKind else {
                return .mismatch(.kindDisagrees(claimed: declared, text: claim.text))
            }
            kind = named
        } else {
            kind = parsed.impliedKind
        }

        // The model enclave's line must name a model we recognize. Without
        // this, a signature over somebody else's model answers our question.
        //
        // Both the id we ASKED for and the one the answer REPORTED are
        // accepted: a provider that normalizes or suffixes the name it signs
        // has not tampered with anything, and a red "signature did not match"
        // on a sound answer is the same dishonesty as a green badge on a bad
        // one, pointed the other way (prd §83).
        if kind == .providerTEE {
            let signed = parsed.modelID ?? ""
            let accepted = [claim.requestedModelID, claim.answeredModelID]
                .compactMap { $0 }.filter { !$0.isEmpty }
            guard accepted.contains(where: { $0.lowercased() == signed.lowercased() }) else {
                return .mismatch(.wrongModel(signed: signed, expected: accepted))
            }
        }

        guard parsed.requestHash.lowercased() == claim.requestHash.lowercased() else {
            return .mismatch(.wrongBytes(field: "request"))
        }
        guard parsed.responseHash.lowercased() == claim.responseHash.lowercased() else {
            return .mismatch(.wrongBytes(field: "response"))
        }

        let expected = kind == .providerTEE ? claim.modelSigners : claim.gatewaySigners
        guard !expected.isEmpty else { return .unchecked(.noAttestation) }

        guard hexBytes(claim.signature)?.count == 65 else {
            return .mismatch(.unreadableSignature)
        }
        guard let recovered = recoverSigner(message: claim.text, signatureHex: claim.signature) else {
            return .mismatch(.couldNotRecover)
        }
        guard expected.contains(where: { $0.lowercased() == recovered.lowercased() }) else {
            return .mismatch(.wrongSigner(recovered: recovered, expected: expected))
        }

        return .verified(signer: recovered, kind: kind)
    }
}
