#!/bin/zsh
# Casberi Signer-proof self-test (prd §1516) — a key is added only once its
# wallet has signed for it.
#
#   Casberi/Casberi/Model/YourAccountSignerProof.swift   the typed data, digest, verdict
#
# compiled WHOLE with `SafeTypedData.swift` (the EIP-712 encoder) and what it
# leans on, and its digest pinned to `scripts/support/safe-signer-vectors.py`'s
# INDEPENDENT encoder over the very JSON the Swift side builds — which proves
# itself on the spec's "Ether Mail" vector first. A digest that disagrees with
# what a wallet hashes refuses every Signer, so this is the check that matters.
#
# Then the order, by source: the proof runs BEFORE an address is handed back
# at Create and before a typed address is added under Security.
#
# Pure, local, deterministic. Exit non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

PROOF="Casberi/Casberi/Model/YourAccountSignerProof.swift"
LINK="Casberi/Casberi/Model/YourAccountSignerLink.swift"
SHEET="Casberi/Casberi/Screens/SignerRequestSheet.swift"
SECURITY="Casberi/Casberi/Screens/MoveSecurity.swift"
WALK="Casberi/Casberi/Screens/MoveKeysWalk.swift"
VECTORS="scripts/support/safe-signer-vectors.py"
SOURCES=(Casberi/Casberi/Model/SafeTransaction.swift Casberi/Casberi/Model/Keccak256.swift
         Casberi/Casberi/Model/ClearSign.swift Casberi/Casberi/Model/SafeTypedData.swift "$PROOF")
for f in "${SOURCES[@]}" "$LINK" "$SHEET" "$SECURITY" "$WALK" "$VECTORS"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

python3 "$VECTORS" --self-test >/dev/null \
  || { echo "✗ safe-signer-vectors.py failed its own self-test — its encoder is not evidence"; exit 1; }

TMP=$(mktemp -d /tmp/signer-proof-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if ok { print("  ✓ \(what)") } else { print("  ✗ \(what)"); failures += 1 }
}

let account = "0x1111111111111111111111111111111111111111"
let signer = "0xCD2a3d9F938E13CD947Ec05AbC7FE734Df8DD826"
let challenge = [UInt8](0..<32)
guard let typed = YourAccountSignerProof.typedData(account: account, signer: signer, chainId: 8453, challenge: challenge),
      let digest = YourAccountSignerProof.digest(typed) else {
    print("  ✗ the proof's typed data did not build or hash"); exit(1)
}
// Handed to the independent encoder below.
try typed.write(toFile: CommandLine.arguments[1], atomically: true, encoding: .utf8)
try SafeABI.hex(digest).write(toFile: CommandLine.arguments[2], atomically: true, encoding: .utf8)

check(typed.contains(YourAccountSignerProof.statement), "the wallet is shown what it is agreeing to")
let other = [UInt8](repeating: 7, count: 32)
check(YourAccountSignerProof.typedData(account: account, signer: signer, chainId: 8453, challenge: other)
        .flatMap(YourAccountSignerProof.digest) != digest, "a fresh challenge is a fresh digest (no replayed proof)")
check(YourAccountSignerProof.typedData(account: account, signer: signer, chainId: 1, challenge: challenge)
        .flatMap(YourAccountSignerProof.digest) != digest, "the chain is in the domain")
check(YourAccountSignerProof.typedData(account: account, signer: signer, chainId: 8453, challenge: [1, 2]) == nil,
      "a short challenge builds nothing")
check(YourAccountSignerProof.typedData(account: account, signer: "0x12", chainId: 8453, challenge: challenge) == nil,
      "a malformed key builds nothing")

check(YourAccountSignerProof.verdict(signer: signer, recovered: signer.lowercased()) == .holds,
      "the Signer's own key holds, whatever the case")
check(YourAccountSignerProof.verdict(signer: signer, recovered: account) == .otherKey(account),
      "another key's signature does not hold")
check(YourAccountSignerProof.verdict(signer: signer, recovered: nil) == .unreadable,
      "nothing recovered does not hold")

check(YourAccountSignerProof.chain(of: [1, 8453, 10], preferring: 8453) == 8453, "Base when the wallet agreed to it")
check(YourAccountSignerProof.chain(of: [42161, 10], preferring: 8453) == 10, "else the lowest it agreed to")
check(YourAccountSignerProof.chain(of: [], preferring: 8453) == nil, "none when it agreed to none")

exit(failures == 0 ? 0 : 1)
SWIFT

swiftc -Onone -o "$TMP/run" "${SOURCES[@]}" "$TMP/main.swift" 2>"$TMP/build.log" \
  || { cat "$TMP/build.log"; echo "✗ the harness did not compile"; exit 1; }
"$TMP/run" "$TMP/typed.json" "$TMP/digest.txt" || { echo "✗ signer-proof self-test failed"; exit 1; }

EXPECTED=$(python3 - "$VECTORS" "$TMP/typed.json" <<'PY'
import importlib.util, json, sys
spec = importlib.util.spec_from_file_location("vectors", sys.argv[1])
v = importlib.util.module_from_spec(spec); spec.loader.exec_module(v)
print("0x" + v.typed_data_hash(json.load(open(sys.argv[2]))).hex())
PY
)
GOT=$(cat "$TMP/digest.txt")
if [[ "${GOT:l}" == "${EXPECTED:l}" ]]; then
  echo "  ✓ the digest is the one an independent EIP-712 encoder takes from the same JSON"
else
  echo "  ✗ the digest drifted from EIP-712: Swift $GOT, reference $EXPECTED"; exit 1
fi

# --- the order, by source ----------------------------------------------------
strip() { grep -v '^[[:space:]]*//' "$1"; }

# Create: `choose` proves before it hands the address back.
CHOOSE=$(strip "$SHEET" | awk '/static func choose\(on/,/^    }/')
print -r -- "$CHOOSE" | grep -q 'YourAccountSignerLink.prove(pairing' \
  || { echo "✗ choosing a Signer at Create no longer asks for the proof"; exit 1; }
[[ $(print -r -- "$CHOOSE" | grep -n 'SignerLink.prove(' | cut -d: -f1) -lt $(print -r -- "$CHOOSE" | grep -n 'return pairing.signer' | cut -d: -f1) ]] \
  || { echo "✗ Create hands the address back before the proof"; exit 1; }
strip "$WALK" | grep -q 'SignerRequestSheet.choose(on:' \
  || { echo "✗ the keys walk no longer chooses through the proving sheet"; exit 1; }
echo "  ✓ Create proves the wallet before it becomes the Signer"

# Security: a typed address is proven before the first addOutsideKey.
ADD=$(strip "$SECURITY" | awk '/private func addOutside\(\)/,/^    }/')
PROVE_AT=$(print -r -- "$ADD" | grep -n 'SignerRequestSheet.prove(signer:' | head -1 | cut -d: -f1)
ADD_AT=$(print -r -- "$ADD" | grep -n 'Chain.addOutsideKey(' | head -1 | cut -d: -f1)
[[ -n "$PROVE_AT" && -n "$ADD_AT" && "$PROVE_AT" -lt "$ADD_AT" ]] \
  || { echo "✗ a typed Signer is added without (or before) its proof"; exit 1; }
print -r -- "$ADD" | grep -q 'return$' \
  || { echo "✗ a failed proof no longer stops the add"; exit 1; }
echo "  ✓ a typed address is proven before it is added"

# The link: a 65-byte answer by another key, or a contract's longer one, is refused.
strip "$LINK" | awk '/static func prove\(/,/^    }/' | grep -q 'guard verdict == .holds else { throw Failure.notProven }' \
  || { echo "✗ the proof no longer refuses an answer that is not the Signer's key"; exit 1; }
echo "  ✓ only the Signer's own signature passes"

echo "✓ signer-proof self-test"
