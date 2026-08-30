#!/bin/zsh
# Casberi Hegotá frame-transaction self-test — the SHIPPED encoder for the one
# chain in this app whose transactions are not ordinary transactions
# (2026-08-29, prd §525):
#
#   Casberi/Casberi/Model/HegotaTransaction.swift  — the 11-field envelope
#   Casberi/Casberi/Model/RLP.swift                — shared with vibenet
#
# Both are Foundation-only BY DESIGN and compiled WHOLE AND UNMODIFIED here.
#
# WHY A HARNESS, AND WHY THE FIXTURES ARE REAL TRANSACTIONS. A wrong field
# order, a stray leading zero, the wrong `limits` shape or a mis-applied
# elision rule produces a signature that is well-formed and authorises a
# DIFFERENT transaction. Nothing else here can see that: the build is happy,
# and this chain cannot be reached from a harness. So the fixtures are two real
# transactions taken off the wire, and the assertions are the three a wrong
# encoder cannot pass — the raw bytes match byte for byte, their keccak IS the
# transaction hash the RPC reports, and the signing hash matches the one
# computed independently from the chain's own data.
#
# Pure, local, deterministic — no network, no simulator, no key.
set -euo pipefail
cd "$(dirname "$0")/.."

TX="Casberi/Casberi/Model/HegotaTransaction.swift"
RLPF="Casberi/Casberi/Model/RLP.swift"
KEY="Casberi/Casberi/Model/HegotaKey.swift"
BRIDGE="Casberi/Casberi/Model/HegotaBridge.swift"
for f in "$TX" "$RLPF" "$KEY" "$BRIDGE"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

strip_comments() { sed -E 's://.*$::' "$1" | sed -E 's:/\*.*\*/::'; }
strip_comments "$KEY" > "$WORK/key.nc"

# --- drift guards -----------------------------------------------------------
# Read from a COMMENT-STRIPPED copy: these files DOCUMENT the rules by naming
# what they must not do, so a raw grep fires on the prose explaining them.

# The key is device-only and non-syncing. Worthless money is not a reason to
# let a signing key ride a backup onto another device.
# `WhenUnlockedThisDeviceOnly`, not `WhenPasscodeSet` — deliberately looser
# than vibenet's Enclave key, and MEASURED rather than guessed: this file's
# first cut used WhenPasscodeSet and failed `-25308` on a real signed Catalyst
# run, because that protection class needs an interactive/authenticated
# session to ESTABLISH and this key's flow never touches biometry at write
# time (unlike VibenetDeviceKey, whose Enclave key generation with
# `.biometryCurrentSet` provides that interaction for free). `SignerKey` — the
# proven, shipped key of this exact shape — uses this same constant.
grep -qF 'kSecAttrAccessibleWhenUnlockedThisDeviceOnly' "$WORK/key.nc" \
  || { echo "✗ HegotaKey no longer pins a ThisDeviceOnly accessibility"; exit 1; }
grep -qF 'kSecAttrSynchronizable' "$WORK/key.nc" \
  || { echo "✗ HegotaKey no longer names kSecAttrSynchronizable"; exit 1; }
# ITS OWN SERVICE, never the Safe signer's. That key is one owner of a Safe
# holding real funds; sharing would let a devnet bug reach it.
grep -qF 'casberi-hegota-signer' "$WORK/key.nc" \
  || { echo "✗ HegotaKey no longer uses its own keychain service"; exit 1; }
if grep -qF 'casberi-dev-signer' "$WORK/key.nc"; then
  echo "✗ HegotaKey is reaching for the Safe signer's service"; exit 1
fi
# The self-check: every signature recovers back to this phone before it is
# returned. One curve operation proving the digest, the recovery id and the
# stored scalar all agree.
grep -qF 'Failure.selfCheck' "$WORK/key.nc" \
  || { echo "✗ HegotaKey no longer verifies its own signature before returning it"; exit 1; }

cp "$TX" "$WORK/HegotaTransaction.swift"
cp "$RLPF" "$WORK/RLP.swift"
cp Casberi/Casberi/Model/Keccak256.swift "$WORK/Keccak256.swift"
mkdir -p "$WORK/m"

cat > "$WORK/m/main.swift" <<'SWIFT'
import Foundation
var fails = 0
func check(_ l: String, _ ok: Bool) { if !ok { print("  ✗ \(l)"); fails += 1 } }
func hx(_ s: String) -> Data { RLP.data(fromHex: s) ?? Data() }

// --- VECTOR 1: a real modern-form transaction, 2 frames, 1 elided signature.
// Chosen because frame 1 carries a NON-ZERO state gas, so it exercises the
// two-element limits list properly rather than [x, 0].
let me = hx("0x8943545177806ed17b9f23f0a21ee5948ecaa776")
let v1 = HegotaTransaction.Fields(
    chainID: 0x301824, nonceKeys: [0], nonceSequence: 4, sender: me,
    frames: [
        .init(mode: 1, flags: 0x03, target: me,
              executionGas: 80_000, stateGas: 0, value: Data(), data: Data()),
        .init(mode: 2, flags: 0x00, target: hx("0x000000000000000000000000000000000000beef"),
              executionGas: 30_000, stateGas: 196_608, value: hx("0x64"), data: Data()),
    ],
    signatures: [
        .init(scheme: 1, signer: me, msg: Data(),
              signature: hx("0x0143e8142de20dc818de9216f98ddf9d3680d6088872f3974c695353c57b8d700f791148767c0ad102f874525fcd6e15476c2a82f6967725f14e9f61d8495dbd08")),
    ],
    maxPriorityFeePerGas: 1_000_000_000, maxFeePerGas: 30_000_000_000,
    maxFeePerBlobGas: 0, blobVersionedHashes: [], recentRootReferences: [])

let RAW1 = "06f8cc83301824c18004948943545177806ed17b9f23f0a21ee5948ecaa776f842df0103948943545177806ed17b9f23f0a21ee5948ecaa776c583013880808080e1028094000000000000000000000000000000000000beefc7827530830300006480f85cf85a01948943545177806ed17b9f23f0a21ee5948ecaa77680b8410143e8142de20dc818de9216f98ddf9d3680d6088872f3974c695353c57b8d700f791148767c0ad102f874525fcd6e15476c2a82f6967725f14e9f61d8495dbd08843b9aca008506fc23ac0080c0c0"
check("vector 1 re-encodes byte for byte", RLP.hex(HegotaTransaction.encoded(v1)) == RAW1)
check("the type byte is the measured 0x06", HegotaTransaction.txType == 0x06)

// THE ELISION RULE, both directions. An empty msg means "sign the sigHash",
// and that entry's own bytes leave the hash; a 32-byte msg signs itself and
// its bytes STAY. Getting this backwards is a signature over the wrong thing.
check("an empty-msg entry is elided", v1.signatures[0].isElided)
check("elision actually changes the bytes",
      HegotaTransaction.signingPreimage(v1) != HegotaTransaction.encoded(v1))
var withMsg = v1
withMsg.signatures[0].msg = Data(repeating: 0xAB, count: 32)
check("a 32-byte-msg entry is NOT elided", !withMsg.signatures[0].isElided)
check("a non-elided entry keeps its bytes in the hash",
      HegotaTransaction.signingPreimage(withMsg) == HegotaTransaction.encoded(withMsg))
// PER ENTRY, not per transaction — one real transaction carries both kinds.
var mixed = v1
mixed.signatures.append(.init(scheme: 1, signer: hx("0x4fc28b54955dad982c625ca572e9db55c6348ea8"),
                              msg: hx("0x6425da1a0ecc4c4f2863b5a288e169c1e6cff37bc68e94bcc5870d101a064fcc"),
                              signature: Data(repeating: 0xCD, count: 65)))
let mixedSig = HegotaTransaction.signingPreimage(mixed)
check("a mixed transaction keeps the un-elided entry's bytes",
      mixedSig.range(of: Data(repeating: 0xCD, count: 65)) != nil)
check("a mixed transaction drops the elided entry's bytes",
      mixedSig.range(of: hx("0x0143e8142de20dc818de9216f98ddf9d3680d608")) == nil)

// EMPTY MEANS "THE SENDER", and must stay empty in the bytes — writing the
// address in changes the hash. 3 of 324 signer fields and 22 of 957 frame
// targets are empty on chain.
var emptySigner = v1
emptySigner.signatures[0].signer = Data()
check("an empty signer changes the bytes", HegotaTransaction.encoded(emptySigner) != HegotaTransaction.encoded(v1))
var emptyTarget = v1
emptyTarget.frames[0].target = Data()
check("an empty target changes the bytes", HegotaTransaction.encoded(emptyTarget) != HegotaTransaction.encoded(v1))

// The 2-element limits form is written even when state gas is zero — the
// scalar form is a different fork and a different hash.
check("limits stays a two-element list at zero state gas",
      RLP.hex(HegotaTransaction.encoded(v1)).contains("c58301388080"))

print("PRE=" + RLP.hex(HegotaTransaction.signingPreimage(v1)))
if fails == 0 { print("  ok") } else { exit(1) }
SWIFT

swiftc -O -o "$WORK/run" "$WORK/HegotaTransaction.swift" "$WORK/RLP.swift" \
  "$WORK/Keccak256.swift" "$WORK/m/main.swift" 2>"$WORK/build.log" || {
  echo "✗ HegotaTransaction.swift did not compile standalone (it must stay Foundation-only)"
  head -20 "$WORK/build.log"; exit 1; }
echo "hegota transaction:"
"$WORK/run" > "$WORK/out.txt" || { grep '✗' "$WORK/out.txt"; exit 1; }
grep -v '^PRE=' "$WORK/out.txt"

# The two hashes, checked by a DIFFERENT keccak than the app's — and against
# values taken off the chain rather than produced by us.
python3 - "$WORK/out.txt" <<'HASH' || exit 1
import sys, sha3
pre = [l for l in open(sys.argv[1]) if l.startswith("PRE=")][0].strip()[4:]
raw = "06f8cc83301824c18004948943545177806ed17b9f23f0a21ee5948ecaa776f842df0103948943545177806ed17b9f23f0a21ee5948ecaa776c583013880808080e1028094000000000000000000000000000000000000beefc7827530830300006480f85cf85a01948943545177806ed17b9f23f0a21ee5948ecaa77680b8410143e8142de20dc818de9216f98ddf9d3680d6088872f3974c695353c57b8d700f791148767c0ad102f874525fcd6e15476c2a82f6967725f14e9f61d8495dbd08843b9aca008506fc23ac0080c0c0"
def kec(h):
    k = sha3.keccak_256(); k.update(bytes.fromhex(h)); return "0x" + k.hexdigest()
ok = True
if kec(raw) != "0x960dfe6178034daddc45810b7286c72232becb9a015a851b22160f95413d89d4":
    print("  ✗ the pinned raw bytes no longer hash to the real transaction hash"); ok = False
if kec(pre) != "0xc86b2c1869937384eadd3623c07dc93d1cf95fab46b2101291133c7a4f2af449":
    print(f"  ✗ signing hash is {kec(pre)}, the chain's is 0xc86b2c18…"); ok = False
if ok: print("  ✓ raw bytes hash to the real transaction hash, and the signing hash matches the chain")
sys.exit(0 if ok else 1)
HASH

# --- mutations --------------------------------------------------------------
echo "mutations:"
MUT=0
mutate() {
  local label="$1" from="$2" to="$3" file="$4"
  cp "$TX" "$WORK/HegotaTransaction.swift"; cp "$RLPF" "$WORK/RLP.swift"
  local target="$WORK/$(basename "$file")"
  if ! grep -qF -- "$from" "$target"; then
    echo "  ✗ STALE MUTATION '$label' — pattern not found in $(basename "$file")"; return 1
  fi
  python3 - "$target" "$from" "$to" <<'PY'
import sys, io
p, a, b = sys.argv[1], sys.argv[2], sys.argv[3]
s = io.open(p, encoding="utf-8").read()
io.open(p, "w", encoding="utf-8").write(s.replace(a, b, 1))
PY
  if swiftc -O -o "$WORK/mut" "$WORK/HegotaTransaction.swift" "$WORK/RLP.swift" \
       "$WORK/Keccak256.swift" "$WORK/m/main.swift" 2>/dev/null \
     && "$WORK/mut" >/dev/null 2>&1; then
    echo "  ✗ MUTATION SURVIVED: $label"; return 1
  fi
  echo "  ✓ caught: $label"; return 0
}
mutate "type byte changed" 'static let txType: UInt8 = 0x06' 'static let txType: UInt8 = 0x07' "$TX" || MUT=1
mutate "limits collapsed to a scalar" '.list([.bytes(RLP.quantity(executionGas)),
                          .bytes(RLP.quantity(stateGas))])' '.bytes(RLP.quantity(executionGas))' "$TX" || MUT=1
mutate "elision inverted" 'var isElided: Bool { msg.isEmpty }' 'var isElided: Bool { !msg.isEmpty }' "$TX" || MUT=1
mutate "elision applied to every entry" 'elided && isElided ? Data() : signature' 'elided ? Data() : signature' "$TX" || MUT=1
mutate "nonce fields swapped" '.list(f.nonceKeys.map { .bytes(RLP.quantity($0)) }),
         .bytes(RLP.quantity(f.nonceSequence)),' '.bytes(RLP.quantity(f.nonceSequence)),
         .list(f.nonceKeys.map { .bytes(RLP.quantity($0)) }),' "$TX" || MUT=1
mutate "fee fields swapped" '.bytes(RLP.quantity(f.maxPriorityFeePerGas)),
         .bytes(RLP.quantity(f.maxFeePerGas)),' '.bytes(RLP.quantity(f.maxFeePerGas)),
         .bytes(RLP.quantity(f.maxPriorityFeePerGas)),' "$TX" || MUT=1
mutate "frame mode and flags swapped" '.list([.bytes(RLP.quantity(mode)),
                   .bytes(RLP.quantity(flags)),' '.list([.bytes(RLP.quantity(flags)),
                   .bytes(RLP.quantity(mode)),' "$TX" || MUT=1
[[ $MUT -eq 0 ]] || exit 1
echo "✓ hegota transaction self-test passed"
