#!/bin/zsh
# Does Hegotá accept a P-256 signature entry (scheme 0x2)?  (grant M2, 2026-09-24)
#
# WHY THIS EXISTS. `HegotaKey.swift` records that this chain has only ever seen
# scheme 0x1 (secp256k1) — 324 of 324 — and that scheme 0x2 "is defined by the
# spec and has never been used on that chain, so its wire encoding is unproven"
# (prd §525). A Secure Enclave key speaks P-256 and nothing else, so whether an
# Enclave key can EVER sign here is that one unknown. Frames earned its passkey
# account only because EIP-8141 verifies P-256 at the protocol level there and
# it was proven on chain (§728d); Hegotá has no such proof, and porting the
# account without one would ship a key that cannot sign.
#
# HOW IT ASKS. §593b's technique, on this chain's own sibling: this node answers
# a malformed envelope by NAMING the field it was decoding and its Rust type, so
# a scheme byte it does not know is reported as a decode refusal that names the
# scheme, while one it DOES know gets past decoding and fails later, on
# verification or on the sender's balance. Those two outcomes are the answer.
#
# It never broadcasts anything that can land: every envelope carries a garbage
# signature over a zero-value frame from an unfunded address, so the best case
# is a verification refusal. Read-only in effect, one submission per scheme.
set -euo pipefail
cd "$(dirname "$0")/.."

TX="Casberi/Casberi/Model/HegotaTransaction.swift"
RLPF="Casberi/Casberi/Model/RLP.swift"
KECCAK="Casberi/Casberi/Model/Keccak256.swift"
for f in "$TX" "$RLPF" "$KECCAK"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/m"
cp "$TX" "$RLPF" "$KECCAK" "$WORK/"

# The envelope is built by the SHIPPED encoder, unmodified — a probe that
# hand-rolled its own bytes would be asking about itself, not about the chain.
cat > "$WORK/m/main.swift" <<'SWIFT'
import Foundation

// One envelope per scheme, identical in every other byte, so the only thing
// that can change the node's answer is the scheme number itself.
func envelope(scheme: UInt64) -> String {
    let frame = HegotaTransaction.Frame(
        mode: 0, flags: 0,
        target: Data(repeating: 0x11, count: 20),
        executionGas: 21_000, stateGas: 0,
        value: Data(), data: Data())
    let sig = HegotaTransaction.Signature(
        scheme: scheme,
        signer: Data(),                       // empty = the sender (trap 4)
        msg: Data(),                          // empty = sign the sigHash
        signature: Data(repeating: 0xAB, count: scheme == 2 ? 128 : 65))
    let f = HegotaTransaction.Fields(
        chainID: 3_151_908,
        nonceKeys: [0], nonceSequence: 0,
        sender: Data(repeating: 0x22, count: 20),
        frames: [frame], signatures: [sig],
        maxPriorityFeePerGas: 1, maxFeePerGas: 1_000_000_000,
        maxFeePerBlobGas: 0, blobVersionedHashes: [], recentRootReferences: [])
    return "0x" + HegotaTransaction.encoded(f).map { String(format: "%02x", $0) }.joined()
}
// 0x7f is the CONTROL: a scheme the spec does not define. If it fails the
// same way as 1 and 2, the message is generic and this probe discriminates
// nothing — the whole reading below depends on the control failing apart.
for s: UInt64 in [1, 2, 0x7f] { print("SCHEME\(s)=\(envelope(scheme: s))") }
SWIFT

swiftc -Onone -o "$WORK/run" "$WORK/HegotaTransaction.swift" "$WORK/RLP.swift" \
  "$WORK/Keccak256.swift" "$WORK/m/main.swift" 2>"$WORK/build.log" || {
  echo "✗ the shipped encoder did not compile standalone"; head -20 "$WORK/build.log"; exit 1; }
"$WORK/run" > "$WORK/env.txt"

H="https://rpc1.hegota.ethrex.xyz"
ask() {  # $1 = scheme label, $2 = raw hex
  local body
  body=$(printf '{"jsonrpc":"2.0","id":1,"method":"eth_sendRawTransaction","params":["%s"]}' "$2")
  echo "── scheme $1"
  curl -s -m 25 -X POST "$H" -H 'content-type: application/json' -d "$body" \
    | python3 -c 'import sys,json;r=json.load(sys.stdin);print("   ", json.dumps(r.get("error") or r.get("result"))[:400])'
}
ask 1 "$(grep '^SCHEME1=' "$WORK/env.txt" | cut -d= -f2)"
ask 2 "$(grep '^SCHEME2=' "$WORK/env.txt" | cut -d= -f2)"
ask "127 (control — undefined scheme)" "$(grep '^SCHEME127=' "$WORK/env.txt" | cut -d= -f2)"

cat <<'NOTE'

Reading the answers:
  • Both refused the SAME way (signature/sender/funds)  → scheme 0x2 DECODES.
    The wire encoding is reachable; a passkey account on Hegotá is buildable.
  • Scheme 2 refused while naming the scheme or the field → scheme 0x2 is NOT
    decoded on this chain. An Enclave key cannot sign here, and M2's passkey
    item must be dropped or moved to Frames.
NOTE
