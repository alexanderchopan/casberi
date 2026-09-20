import Foundation
import Testing
@testable import Casberi

/// **The curve half of NEAR AI's verification** (prd §848).
///
/// `scripts/nearai-verify-selftest.sh` owns everything that decides whether
/// recovery is reached and what its answer means — it compiles
/// `NearAIVerify.swift` whole against a refusing stub, because a `swiftc`
/// harness has no libsecp256k1. What it cannot do is the one thing that
/// matters most: prove that this app recovers the RIGHT ADDRESS from a real
/// EIP-191 signature. That is here, where `@testable import` reaches the real
/// `P256K`.
///
/// **The vectors are independent.** They were produced with `coincurve` (a
/// separate libsecp256k1 binding) over digests from `scripts/support/keccak.py`
/// (the repo's vendored, self-proving keccak) — neither of which is the code
/// under test. A signature this app made and then verified would prove only
/// that it agrees with itself, which is the failure mode the whole
/// measure-don't-assume rule exists to catch. Reproduce them with:
///
///     from coincurve import PrivateKey
///     pk = PrivateKey(bytes.fromhex("59c6…690d"))
///     pk.sign_recoverable(eip191_digest(message), hasher=None)
///
/// The key is a well-known throwaway test key and holds nothing.
///
/// **What is still NOT proven here, and must be said plainly:** no signature
/// produced by NEAR AI itself has ever been verified. The account this was
/// built against has no credits (`402 no_limit_configured`, measured
/// 2026-09-20), so no completion could be made and `/v1/signature/{id}` has
/// never returned a body. The endpoint's shape is taken from NEAR AI's own
/// reference verifier, and the attestation half IS measured — the addresses
/// below are the real ones this account was served. Until a funded key runs
/// one completion, `NearAICloud.signature`'s parsing is reasoned, not measured.
struct NearAIVerifyTests {

    /// The address the vector key controls.
    static let signer = "0x70997970c51812dc3a010c7d01b50e0d17dc79c8"

    static let modelLine =
        "Qwen/Qwen3.8-27B:" + String(repeating: "a", count: 64)
        + ":" + String(repeating: "b", count: 64)
    static let modelSig =
        "0xc6062501fdb452a0a3b7d67fc7d3f4451ac9bfe8a3fcbd78dd03c4d7322b6d3d"
        + "4d41ff0160d58e1d52c0d8e4a4987ae925b3cd415a7ab5eab24c1468345e5dd91c"

    static let gatewayLine =
        String(repeating: "a", count: 64) + ":" + String(repeating: "b", count: 64)
    static let gatewaySig =
        "0x72ea2103ee12a838a530c8dfb345814a4d23c180a60818d5ac79610b25737ca2"
        + "1a837e7040b9e34b9fec3d44450cbc0ae8ba4fd0479b0780dbb9fedf683c21a91b"

    /// Non-ASCII on purpose: here the UTF-8 byte count and the character count
    /// differ, so a preamble built from `message.count` recovers a different
    /// address entirely. Every ASCII vector passes either way, which is exactly
    /// why this one exists.
    static let unicodeLine =
        "modèle—x:" + String(repeating: "c", count: 64)
        + ":" + String(repeating: "d", count: 64)
    static let unicodeSig =
        "0xc515b0c72c1cd8b1302f47f73cde6cd3e7e641651350e765c31e599bf904b1dc"
        + "1ef1d0575153dabe8edc17b440c915b028785a7344af0fe994ea653b3450dbb51c"

    // MARK: - Recovery

    @Test func recoversTheSignerOfARealSignature() {
        let recovered = NearAIVerify.recoverSigner(message: Self.modelLine,
                                                   signatureHex: Self.modelSig)
        #expect(recovered?.lowercased() == Self.signer)
    }

    @Test func recoversFromAGatewayShapedLine() {
        let recovered = NearAIVerify.recoverSigner(message: Self.gatewayLine,
                                                   signatureHex: Self.gatewaySig)
        #expect(recovered?.lowercased() == Self.signer)
    }

    /// The one vector that fails if the EIP-191 preamble counts characters.
    @Test func recoversWhenTheMessageIsNotASCII() {
        let recovered = NearAIVerify.recoverSigner(message: Self.unicodeLine,
                                                   signatureHex: Self.unicodeSig)
        #expect(recovered?.lowercased() == Self.signer)
    }

    /// `v` arrives as 27/28 from anything speaking `personal_sign`, and as a
    /// bare 0/1 from some libraries. Both must land on the same address, or
    /// half of all real signatures silently fail to recover.
    @Test func acceptsBothRecoveryIDConventions() {
        let raw = Self.modelSig.replacingOccurrences(of: "1c", with: "01",
                                                     range: Self.modelSig.range(of: "1c",
                                                                                options: .backwards))
        #expect(NearAIVerify.recoverSigner(message: Self.modelLine, signatureHex: raw)?.lowercased()
                == Self.signer)
    }

    // MARK: - A signature must not survive being tampered with

    @Test func aChangedMessageRecoversSomebodyElse() {
        // Not nil — a different address. That is the property that matters:
        // recovery always produces SOMETHING, which is why the check compares
        // against the attested address rather than merely succeeding.
        let recovered = NearAIVerify.recoverSigner(
            message: Self.modelLine.replacingOccurrences(of: "aaaa", with: "aaab"),
            signatureHex: Self.modelSig)
        #expect(recovered?.lowercased() != Self.signer)
    }

    @Test func aChangedSignatureDoesNotRecoverTheSigner() {
        var flipped = Array(Self.modelSig)
        flipped[10] = flipped[10] == "0" ? "1" : "0"
        let recovered = NearAIVerify.recoverSigner(message: Self.modelLine,
                                                   signatureHex: String(flipped))
        #expect(recovered?.lowercased() != Self.signer)
    }

    @Test func aMalformedSignatureIsRefusedRatherThanGuessed() {
        #expect(NearAIVerify.recoverSigner(message: Self.modelLine, signatureHex: "0x00") == nil)
        #expect(NearAIVerify.recoverSigner(message: Self.modelLine, signatureHex: "") == nil)
        // v = 4 is not a recovery id.
        let badV = String(Self.modelSig.dropLast(2)) + "04"
        #expect(NearAIVerify.recoverSigner(message: Self.modelLine, signatureHex: badV) == nil)
    }

    // MARK: - The whole check, over a real signature

    /// The measured NEAR AI addresses for this account (2026-09-20) — the
    /// model enclave serving `Qwen/Qwen3.8-27B`, and the gateway. They stand in
    /// for "an address that is not ours" below.
    static let realModelSigner = "0xdae35b28350786f88afe07019aee6cef513886a8"
    static let realGatewaySigner = "0x614bc66ff0407dbb70b9c7ca1f5e983e4a02c921"

    private func claim(text: String, signature: String, kind: String?,
                       modelSigners: [String], gatewaySigners: [String]) -> NearAIVerify.Claim {
        .init(text: text, signature: signature, declaredKind: kind,
              modelSigners: modelSigners, gatewaySigners: gatewaySigners,
              requestedModelID: "Qwen/Qwen3.8-27B", answeredModelID: nil,
              requestHash: String(repeating: "a", count: 64),
              responseHash: String(repeating: "b", count: 64))
    }

    @Test func verifiesEndToEndWhenTheSignerIsTheAttestedOne() {
        let outcome = NearAIVerify.check(claim(
            text: Self.modelLine, signature: Self.modelSig, kind: "provider_tee",
            modelSigners: [Self.signer], gatewaySigners: [Self.realGatewaySigner]))
        guard case .verified(let who, let kind) = outcome else {
            Issue.record("expected verified, got \(outcome)"); return
        }
        #expect(who.lowercased() == Self.signer)
        #expect(kind == .providerTEE)
    }

    @Test func aGatewaySignatureVerifiesAgainstTheGatewayAddress() {
        let outcome = NearAIVerify.check(claim(
            text: Self.gatewayLine, signature: Self.gatewaySig, kind: "gateway",
            modelSigners: [Self.realModelSigner], gatewaySigners: [Self.signer]))
        guard case .verified(_, let kind) = outcome else {
            Issue.record("expected verified, got \(outcome)"); return
        }
        #expect(kind == .gateway)
    }

    /// The attack the three-case `Outcome` exists for: a real, perfectly valid
    /// signature from a key that the attestation never named.
    @Test func aValidSignatureFromAnUnattestedKeyIsAMismatch() {
        let outcome = NearAIVerify.check(claim(
            text: Self.modelLine, signature: Self.modelSig, kind: "provider_tee",
            modelSigners: [Self.realModelSigner], gatewaySigners: [Self.realGatewaySigner]))
        guard case .mismatch(.wrongSigner(let recovered, _)) = outcome else {
            Issue.record("expected wrongSigner, got \(outcome)"); return
        }
        #expect(recovered.lowercased() == Self.signer)
        #expect(outcome.isMismatch)
        #expect(!outcome.isVerified)
    }

    /// A gateway signature must not be checkable against the MODEL enclave's
    /// addresses — the downgrade. Here the same real key is attested as the
    /// model signer, and a 2-part line declaring `provider_tee` must still be
    /// refused on shape, before it can be recovered against it.
    @Test func aGatewayLineCannotBorrowTheModelAddress() {
        let outcome = NearAIVerify.check(claim(
            text: Self.gatewayLine, signature: Self.gatewaySig, kind: "provider_tee",
            modelSigners: [Self.signer], gatewaySigners: []))
        guard case .mismatch(.kindDisagrees) = outcome else {
            Issue.record("expected kindDisagrees, got \(outcome)"); return
        }
    }

    /// And undeclared, it is a gateway line — which with no gateway address is
    /// UNCHECKED, never a mismatch. A real signature plus a missing
    /// attestation is not evidence of anything (prd §83).
    @Test func aGatewayLineWithNoGatewayAddressIsUnchecked() {
        let outcome = NearAIVerify.check(claim(
            text: Self.gatewayLine, signature: Self.gatewaySig, kind: nil,
            modelSigners: [Self.signer], gatewaySigners: []))
        guard case .unchecked(.noAttestation) = outcome else {
            Issue.record("expected unchecked, got \(outcome)"); return
        }
        #expect(!outcome.isMismatch)
    }

    // MARK: - The bytes the signature covers

    @Test func aRealSignatureOverForeignBytesIsAMismatch() {
        let outcome = NearAIVerify.check(.init(
            text: Self.modelLine, signature: Self.modelSig, declaredKind: "provider_tee",
            modelSigners: [Self.signer], gatewaySigners: [],
            requestedModelID: "Qwen/Qwen3.8-27B", answeredModelID: nil,
            requestHash: String(repeating: "a", count: 64),
            // What we actually received hashes to something else — the signed
            // line is genuine and covers a response that is not ours.
            responseHash: String(repeating: "f", count: 64)))
        guard case .mismatch(.wrongBytes(let field)) = outcome else {
            Issue.record("expected wrongBytes, got \(outcome)"); return
        }
        #expect(field == "response")
    }
}
