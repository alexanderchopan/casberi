#!/bin/zsh
# NEAR AI verification self-test (prd §848, 2026-09-20) — the one seat whose
# answer carries a proof, and the logic that decides whether that proof holds:
#
#   Casberi/Casberi/Model/NearAIVerify.swift   compiled WHOLE and unmodified
#   Casberi/Casberi/Model/Keccak256.swift      compiled WHOLE and unmodified
#
# WHY A HARNESS. This is the only place in the app where the UI makes a
# cryptographic claim about somebody else's machine, and every way of getting it
# wrong is silent — a badge that says "checked" is indistinguishable from one
# that says "checked" for the wrong reason. The failure modes:
#
#   • A DOWNGRADE. The gateway signs `{req}:{resp}`; the model enclave signs
#     `{model}:{req}:{resp}` and is the stronger claim. A response that DECLARES
#     `provider_tee` over a 2-part line must be refused, or a gateway signature
#     gets checked against the model's address set and the badge overstates what
#     is known.
#   • THE WRONG MODEL. A 3-part line naming a model we did not ask for would
#     verify perfectly and answer a different question.
#   • THE WRONG BYTES. A signature that is real, over hashes that are not ours.
#   • "COULD NOT CHECK" DRAWN AS "FAILED". A signature the node did not serve
#     says NOTHING about the answer (prd §83). `.unchecked` must never satisfy
#     `isMismatch`, and `.mismatch` must never satisfy `isVerified`.
#   • THE EIP-191 PREAMBLE MIS-BUILT. The byte count, not the character count —
#     ASCII hides the difference until the first non-ASCII line, and then every
#     check fails looking exactly like tampering. Checked against an INDEPENDENT
#     keccak (`scripts/support/keccak.py`), never against our own.
#   • HEX READ LOOSELY. An odd-length or non-hex signature must be refused, not
#     silently truncated into a valid-looking 65 bytes.
#
# Pure, local, deterministic — no network, no simulator, no key.
set -euo pipefail
cd "$(dirname "$0")/.."

VERIFY="Casberi/Casberi/Model/NearAIVerify.swift"
KECCAK="Casberi/Casberi/Model/Keccak256.swift"
for f in "$VERIFY" "$KECCAK"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

TMP=$(mktemp -d /tmp/nearai-verify-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------------------
# The EIP-191 digest, computed by somebody else.
#
# `scripts/support/keccak.py` is the vendored, self-proving keccak the repo
# already keeps for exactly this purpose — it is NOT the app's implementation,
# which is the entire point: a digest checked against its own code proves only
# that the code is consistent with itself.
# ---------------------------------------------------------------------------
python3 - "$TMP" <<'PY'
import sys, os
sys.path.insert(0, os.path.join(os.getcwd(), "scripts", "support"))
from keccak import keccak256  # vendored, self-proving

def eip191(message: str) -> str:
    body = message.encode("utf-8")
    prefix = b"\x19Ethereum Signed Message:\n" + str(len(body)).encode()
    return keccak256(prefix + body).hex()

cases = [
    "Qwen/Qwen3.8-27B:aa:bb",
    "aa:bb",
    # Non-ASCII on purpose: the byte count and the character count differ here
    # (the em dash is 3 bytes), which is the one input that tells a correct
    # preamble from a plausible one.
    "modèle—x:aa:bb",
]
with open(os.path.join(sys.argv[1], "digests.txt"), "w") as out:
    for c in cases:
        out.write(f"{c}\t{eip191(c)}\n")
print("  · independent digests computed for", len(cases), "lines")
PY

# ---------------------------------------------------------------------------
# The logic, compiled whole.
# ---------------------------------------------------------------------------
cat > "$TMP/stubs.swift" <<'SWIFT'
import Foundation

// The real `recoverSigner` lives in `NearAIRecover.swift`, the only file that
// imports libsecp256k1 — which is why `NearAIVerify.swift` stays
// Foundation-only and can be compiled here WHOLE and unmodified. The real
// recovery is exercised against a real signature in `CasberiTests`.
//
// This stub is deliberately a REFUSAL, not a forgery. It returns nil, so any
// case below that reaches the curve lands on `.couldNotRecover` and shows up as
// such — a stub that returned a convenient address would make every test below
// pass for the wrong reason.
extension NearAIVerify {
    static func recoverSigner(message: String, signatureHex: String) -> String? { nil }
}
SWIFT

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if !ok { print("  ✗ \(what)"); failures += 1 }
}

let MODEL = "Qwen/Qwen3.8-27B"
let REQ = String(repeating: "a", count: 64)
let RESP = String(repeating: "b", count: 64)
let MODEL_SIGNER = "0xdae35b28350786f88afe07019aee6cef513886a8"
let GATEWAY_SIGNER = "0x37c6b13afc369e41c6f99533fc5513546ef2bc5b"
let SIG = "0x" + String(repeating: "11", count: 65)

func claim(text: String, kind: String? = nil,
           model: [String] = [MODEL_SIGNER], gateway: [String] = [GATEWAY_SIGNER],
           requested: String = MODEL, answered: String? = nil,
           req: String = REQ, resp: String = RESP,
           signature: String = SIG) -> NearAIVerify.Claim {
    .init(text: text, signature: signature, declaredKind: kind,
          modelSigners: model, gatewaySigners: gateway,
          requestedModelID: requested, answeredModelID: answered,
          requestHash: req, responseHash: resp)
}

// --- the signed line, taken apart --------------------------------------------
check(NearAIVerify.parse("m:r:s") == .init(modelID: "m", requestHash: "r", responseHash: "s"),
      "a 3-part line is the model enclave's")
check(NearAIVerify.parse("r:s") == .init(modelID: nil, requestHash: "r", responseHash: "s"),
      "a 2-part line is the gateway's")
check(NearAIVerify.parse("a:b:c:d") == nil, "4 parts is not a shape we know")
check(NearAIVerify.parse("nocolons") == nil, "1 part is not a shape we know")
check(NearAIVerify.parse("m:r:s")?.impliedKind == .providerTEE, "3 parts imply the model enclave")
check(NearAIVerify.parse("r:s")?.impliedKind == .gateway, "2 parts imply the gateway")

// --- the downgrade ------------------------------------------------------------
// The attack this check exists for: a gateway signature presented as the model
// enclave's. It must be refused on SHAPE, before any address is consulted.
if case .mismatch(.kindDisagrees) = NearAIVerify.check(
    claim(text: "\(REQ):\(RESP)", kind: "provider_tee")) {} else {
    check(false, "a 2-part line DECLARED provider_tee is refused")
}
if case .mismatch(.kindDisagrees) = NearAIVerify.check(
    claim(text: "\(MODEL):\(REQ):\(RESP)", kind: "gateway")) {} else {
    check(false, "a 3-part line DECLARED gateway is refused")
}

// --- the wrong model ----------------------------------------------------------
if case .mismatch(.wrongModel(let signed, _)) = NearAIVerify.check(
    claim(text: "some/other-model:\(REQ):\(RESP)")) {
    check(signed == "some/other-model", "the refusal names what WAS signed — got \(signed)")
} else {
    check(false, "a line naming a model we neither asked for nor got is refused")
}
// ...and it is its OWN reason, not the kind's. Folding the two together would
// word a naming problem as a downgrade attack.
if case .mismatch(.kindDisagrees) = NearAIVerify.check(
    claim(text: "some/other-model:\(REQ):\(RESP)")) {
    check(false, "a wrong model is NOT reported as a kind disagreement")
}

// --- a naming difference is not tampering ------------------------------------
// The false-alarm guard (prd §848): a provider that normalizes or suffixes the
// model name it signs has not touched the answer, and a red "signature did not
// match" on a sound answer is the same dishonesty as a green badge on a bad
// one. Both the asked-for id and the ANSWER's own id are accepted, and case is
// not a difference.
// (These assert the model gate specifically, not the whole outcome: the
// refusing stub above makes every claim that REACHES the curve land on
// `.couldNotRecover`, which is also a mismatch. What matters here is that the
// name never produced `.wrongModel`.)
if case .mismatch(.wrongModel) = NearAIVerify.check(
    claim(text: "\(MODEL.lowercased()):\(REQ):\(RESP)")) {
    check(false, "a case-different model name is NOT a wrong model")
}
if case .mismatch(.wrongModel) = NearAIVerify.check(
    claim(text: "Qwen/Qwen3.8-27B-FP8:\(REQ):\(RESP)", answered: "Qwen/Qwen3.8-27B-FP8")) {
    check(false, "the model the ANSWER reported is accepted alongside the one we asked for")
}
// The acceptance is bounded: an answer reporting one model does not license a
// line naming a third.
if case .mismatch(.wrongModel) = NearAIVerify.check(
    claim(text: "a/third-model:\(REQ):\(RESP)", answered: "Qwen/Qwen3.8-27B-FP8")) {} else {
    check(false, "a third model is still refused when the answer named a second")
}
// A gateway line carries no model name and must not be judged on one.
if case .mismatch(.wrongModel) = NearAIVerify.check(claim(text: "\(REQ):\(RESP)")) {
    check(false, "a gateway line is not judged on a model name it never carries")
}

// --- the wrong bytes ----------------------------------------------------------
if case .mismatch(.wrongBytes(let field)) = NearAIVerify.check(
    claim(text: "\(MODEL):\(String(repeating: "c", count: 64)):\(RESP)")) {
    check(field == "request", "a foreign REQUEST hash names the request — got \(field)")
} else {
    check(false, "a foreign request hash is refused")
}
if case .mismatch(.wrongBytes(let field)) = NearAIVerify.check(
    claim(text: "\(MODEL):\(REQ):\(String(repeating: "c", count: 64))")) {
    check(field == "response", "a foreign RESPONSE hash names the response — got \(field)")
} else {
    check(false, "a foreign response hash is refused")
}
// Case is not a difference: hashes are hex, and a provider that upcases them
// has not tampered with anything.
if case .mismatch(.wrongBytes) = NearAIVerify.check(
    claim(text: "\(MODEL):\(REQ.uppercased()):\(RESP)")) {
    check(false, "an upper-cased hash is NOT a mismatch")
}

// --- no attestation is not a failure -----------------------------------------
// The §83 line, and the reason `Outcome` has three cases instead of a Bool.
if case .unchecked(.noAttestation) = NearAIVerify.check(
    claim(text: "\(MODEL):\(REQ):\(RESP)", model: [], gateway: [])) {} else {
    check(false, "no attested address means UNCHECKED, never a mismatch")
}
if case .unchecked(.noAttestation) = NearAIVerify.check(
    claim(text: "\(REQ):\(RESP)", gateway: [])) {} else {
    check(false, "a gateway line with no gateway address is UNCHECKED")
}
// A model line must NOT be rescued by the gateway's address, and vice versa —
// the two kinds are checked against different keys on purpose.
if case .unchecked(.noAttestation) = NearAIVerify.check(
    claim(text: "\(MODEL):\(REQ):\(RESP)", model: [])) {} else {
    check(false, "a model line does not fall back to the gateway's address")
}

// --- the outcome's own honesty -----------------------------------------------
check(NearAIVerify.Outcome.unchecked(.noSignature).isMismatch == false,
      "UNCHECKED is not a mismatch — the badge must not warn on it")
check(NearAIVerify.Outcome.unchecked(.noSignature).isVerified == false,
      "UNCHECKED is not verified either")
check(NearAIVerify.Outcome.mismatch(.couldNotRecover).isVerified == false,
      "a mismatch is not verified")
check(NearAIVerify.Outcome.mismatch(.couldNotRecover).isMismatch,
      "a mismatch IS a mismatch")
check(NearAIVerify.Outcome.verified(signer: MODEL_SIGNER, kind: .providerTEE).isVerified,
      "verified is verified")
check(NearAIVerify.Outcome.verified(signer: MODEL_SIGNER, kind: .gateway).isMismatch == false,
      "verified is not a mismatch")

// --- hex, read strictly -------------------------------------------------------
check(NearAIVerify.hexBytes("0x00ff") == [0x00, 0xff], "0x prefix optional")
check(NearAIVerify.hexBytes("00ff") == [0x00, 0xff], "bare hex reads")
check(NearAIVerify.hexBytes("0xfff") == nil, "an odd-length run is refused, never truncated")
check(NearAIVerify.hexBytes("0xzz") == nil, "non-hex is refused")
check(NearAIVerify.hexBytes("") == nil, "empty is refused")
check(NearAIVerify.hexBytes("0x") == nil, "a bare prefix is refused")
// A signature of the wrong length must be REFUSED before recovery, and named
// as unreadable rather than as a failed recovery.
if case .mismatch(.unreadableSignature) = NearAIVerify.check(
    claim(text: "\(MODEL):\(REQ):\(RESP)", signature: "0x1234")) {} else {
    check(false, "a signature that is not 65 bytes is refused as unreadable")
}

// --- the sha256 of the exact bytes -------------------------------------------
check(NearAIVerify.hashHex(Data("abc".utf8))
        == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
      "sha256(\"abc\") is the published vector")
check(NearAIVerify.hashHex(Data())
        == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
      "sha256 of nothing is the published vector")

// --- the EIP-191 preamble, against an independent keccak ----------------------
let digestFile = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ""
if let lines = try? String(contentsOfFile: digestFile, encoding: .utf8) {
    var checked = 0
    for line in lines.split(separator: "\n") {
        let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { continue }
        let ours = Keccak256.hexString(NearAIVerify.personalSignDigest(parts[0]))
        check(ours == parts[1],
              "EIP-191 digest of \"\(parts[0])\" matches an independent keccak — ours \(ours), theirs \(parts[1])")
        checked += 1
    }
    check(checked == 3, "all three independent digests were compared — got \(checked)")
} else {
    check(false, "the independent digest file was readable")
}

if failures == 0 {
    print("✓ nearai-verify-selftest: all checks passed")
    exit(0)
} else {
    print("✗ nearai-verify-selftest: \(failures) check(s) failed")
    exit(1)
}
SWIFT

echo "  · compiling NearAIVerify.swift whole"
swiftc -O -o "$TMP/run" \
  "$VERIFY" "$KECCAK" "$TMP/stubs.swift" "$TMP/main.swift" 2>&1 | grep -v "^$" || true
[[ -x "$TMP/run" ]] || { echo "✗ harness did not compile"; exit 1; }

"$TMP/run" "$TMP/digests.txt"
