#!/bin/zsh
# A P-256 key signing a real Hegotá transaction, end to end (grant M2, 2026-09-24).
#
# `hegota-p256-probe.sh` proved scheme 0x2 DECODES here — an undefined scheme is
# named and refused ("unsupported scheme 127") while 0x2 reaches signature
# verification exactly as secp256k1 does. That says the envelope is reachable.
# It does NOT say a correct P-256 signature VERIFIES, which is the fact a
# passkey account on this chain actually rests on. This asks that question the
# only way it can be answered: mint a key, fund it, sign, broadcast, and see
# whether the node returns OUR OWN PREDICTED HASH — §593b's proof standard,
# because the bytes we hashed being the bytes it hashed is the whole claim.
#
# The key here is a SOFTWARE P-256 key, deliberately. The Enclave half is a
# storage question `VibenetDeviceKey` already answers; this is a protocol
# question, and a harness on a Mac has no Enclave. If this passes, the Enclave
# key differs only in where the private half lives.
#
# Spends nothing real: Hegotá's faucet mints worthless test ETH by construction.
set -euo pipefail
cd "$(dirname "$0")/.."

TX="Casberi/Casberi/Model/HegotaTransaction.swift"
RLPF="Casberi/Casberi/Model/RLP.swift"
KECCAK="Casberi/Casberi/Model/Keccak256.swift"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/m"; cp "$TX" "$RLPF" "$KECCAK" "$WORK/"

cat > "$WORK/m/main.swift" <<'SWIFT'
import Foundation
import CryptoKit

func hex(_ d: Data) -> String { d.map { String(format: "%02x", $0) }.joined() }

// A P-256 key. `x963Representation` is 0x04 ‖ qx ‖ qy, so the 64 bytes
// EIP-8141 names a signer by are everything after the prefix byte.
let key = P256.Signing.PrivateKey()
let xy = key.publicKey.x963Representation.dropFirst()          // qx ‖ qy, 64 bytes
let sender = Data(Keccak256.hash([UInt8](xy)).suffix(20))      // FramesPasskeyAccount.owner()

// Step 1 — publish the address so the shell can fund it, then wait to be told
// the nonce and fees to use. Two runs of the same binary would mint a new key.
if CommandLine.arguments.count == 1 {
    print("ADDRESS=0x\(hex(sender))")
    print("SECRET=\(hex(key.rawRepresentation))")
    exit(0)
}

// Step 2 — rebuild the SAME key from its scalar and sign.
let scalar = Data(stride(from: 0, to: CommandLine.arguments[1].count, by: 2).map {
    let i = CommandLine.arguments[1].index(CommandLine.arguments[1].startIndex, offsetBy: $0)
    return UInt8(CommandLine.arguments[1][i...CommandLine.arguments[1].index(i, offsetBy: 1)], radix: 16)!
})
let signer = try! P256.Signing.PrivateKey(rawRepresentation: scalar)
let pub = Data(signer.publicKey.x963Representation.dropFirst())
let from = Data(Keccak256.hash([UInt8](pub)).suffix(20))
let nonce = UInt64(CommandLine.arguments[2])!
let maxFee = UInt64(CommandLine.arguments[3])!

// The canonical minimal shape read off this chain (§525, HegotaSend.sendValue):
// a `self_verify` prefix proving the sender's own signature, then a SENDER
// frame doing the transfer. Mode 0 carries no value — the node says so.
let frames = [
    HegotaTransaction.Frame(mode: 1, flags: 0x03, target: from,
                            executionGas: 80_000, stateGas: 0,
                            value: Data(), data: Data()),
    HegotaTransaction.Frame(mode: 2, flags: 0x00,
                            target: Data(repeating: 0x11, count: 20),
                            executionGas: 80_000, stateGas: 0,
                            value: Data([0x01]), data: Data()),
]

// The signature entry is present-but-blank while the sigHash is computed, or
// the node recomputes a hash over a DIFFERENT list (HegotaSend's own §525 note).
var f = HegotaTransaction.Fields(
    chainID: 3_151_908, nonceKeys: [0], nonceSequence: nonce,
    sender: from, frames: frames,
    signatures: [.init(scheme: 2, signer: Data(), msg: Data(), signature: Data())],
    maxPriorityFeePerGas: 1, maxFeePerGas: maxFee,
    maxFeePerBlobGas: 0, blobVersionedHashes: [], recentRootReferences: [])

let digest = Data(Keccak256.hash([UInt8](HegotaTransaction.signingPreimage(f))))
let raw = try! signer.signature(for: digest)   // CryptoKit pre-hashes; see note below
// `rawRepresentation` is r ‖ s, 64 bytes. EIP-8141 names a P-256 signer by its
// public key, and this entry's `signer` is empty ("the sender"), so the key has
// to travel with the signature: r ‖ s ‖ qx ‖ qy, the layout Frames measured.
f.signatures = [.init(scheme: 2, signer: Data(), msg: Data(),
                      signature: raw.rawRepresentation + pub)]

let encoded = HegotaTransaction.encoded(f)
print("RAW=0x\(hex(encoded))")
print("PREDICTED=0x\(hex(Data(Keccak256.hash([UInt8](encoded)))))")
SWIFT

swiftc -Onone -o "$WORK/run" "$WORK/HegotaTransaction.swift" "$WORK/RLP.swift" \
  "$WORK/Keccak256.swift" "$WORK/m/main.swift" 2>"$WORK/build.log" || {
  echo "✗ did not compile"; head -30 "$WORK/build.log"; exit 1; }

H="https://rpc1.hegota.ethrex.xyz"
rpc() { curl -s -m 25 -X POST "$H" -H 'content-type: application/json' \
          -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"$1\",\"params\":$2}"; }

# THE KEY IS KEPT. The faucet is rate-limited per IP for an hour, so a run that
# mints a fresh key each time can strand a funded address behind a closed
# window — which is exactly what happened the first time this was run.
KEYFILE="${HEGOTA_P256_KEY:-$HOME/.casberi-hegota-p256.key}"
if [[ -s "$KEYFILE" ]]; then
  eval "$(cat "$KEYFILE")"
  echo "key      $ADDRESS (kept)"
else
  eval "$("$WORK/run")"
  printf 'ADDRESS=%s\nSECRET=%s\n' "$ADDRESS" "$SECRET" > "$KEYFILE"
  chmod 600 "$KEYFILE"
  echo "key      $ADDRESS (new)"
fi

BAL=$(rpc eth_getBalance "[\"$ADDRESS\",\"latest\"]" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("result","0x0"))')
if [[ "$BAL" != "0x0" && -n "$BAL" ]]; then
  echo "balance  $BAL (already funded — faucet not asked)"
else
echo "faucet   claiming…"
curl -s -m 30 -X POST "https://faucet.hegota.ethrex.xyz/api/claim" \
  -H 'content-type: application/json' -d "{\"address\":\"$ADDRESS\"}" | head -c 300; echo

for i in 1 2 3 4 5 6 7 8 9 10; do
  BAL=$(rpc eth_getBalance "[\"$ADDRESS\",\"latest\"]" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("result","0x0"))')
  [[ "$BAL" != "0x0" && -n "$BAL" ]] && break
  sleep 3
done
echo "balance  $BAL"
fi
[[ "$BAL" == "0x0" || -z "$BAL" ]] && {
  echo "✗ not funded — the faucet is rate-limited per IP for an hour."
  echo "  The key is kept at $KEYFILE, so re-running once the window opens"
  echo "  funds THIS address rather than minting another one."
  exit 1; }

NONCE=$(rpc eth_getTransactionCount "[\"$ADDRESS\",\"latest\"]" | python3 -c 'import sys,json;print(int(json.load(sys.stdin).get("result","0x0"),16))')
FEE=$(rpc eth_gasPrice '[]' | python3 -c 'import sys,json;print(max(int(json.load(sys.stdin).get("result","0x3b9aca00"),16)*2, 1000000000))')
echo "nonce    $NONCE   maxFee $FEE"

eval "$("$WORK/run" "$SECRET" "$NONCE" "$FEE")"
echo "predicted $PREDICTED"
echo "sending…"
rpc eth_sendRawTransaction "[\"$RAW\"]" | python3 -c '
import sys,json
r=json.load(sys.stdin)
if "result" in r: print("   node returned", r["result"])
else: print("   refused:", json.dumps(r.get("error"))[:400])
'
