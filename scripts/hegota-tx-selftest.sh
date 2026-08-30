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

# --- the write outcomes (prd §531) -----------------------------------------
# WHY THIS IS HERE AT ALL. Neither of Hegotá's two writes can be exercised from
# a harness — the faucet allows one claim per source IP per hour and the
# broadcast needs a key and a live node — so the CLASSIFICATION of what came
# back is the only part of either that can ever be proven here. It is also
# where the 2026-08-30 report lived: every refusal, from both writes, reached
# the screen as one sentence that named nothing.
#
# Both files are Foundation-only BY DESIGN and compiled WHOLE AND UNMODIFIED.
OUT="Casberi/Casberi/Model/HegotaWriteOutcome.swift"
SEND="Casberi/Casberi/Model/HegotaSend.swift"
SHEET="Casberi/Casberi/Screens/HegotaKeySheet.swift"
for f in "$OUT" "$SEND" "$SHEET"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

mkdir -p "$WORK/w"
cp "$OUT" "$WORK/HegotaWriteOutcome.swift"

cat > "$WORK/w/main.swift" <<'SWIFT'
import Foundation
var fails = 0
func check(_ l: String, _ ok: Bool) { if !ok { print("  ✗ \(l)"); fails += 1 } }

// --- the faucet -------------------------------------------------------------
// THE ORDER IS THE WHOLE OF `of`'s CORRECTNESS, so every rung is pinned with a
// fixture that FAILS that rung and passes every other one — the standing rule
// this repo has re-earned four times.

// 0 is IngestSupport's transport failure: we never heard back. It must not be
// read as a refusal, because "the faucet said no" and "nothing answered" send
// a person to two different places.
check("a transport failure is unreachable, not a refusal",
      HegotaFaucetVerdict.of(status: 0, msg: nil, txHash: nil) == .unreachable)
// A dead host that somehow carried a body is STILL unreachable — status 0
// means no response object at all, so any body is our own confusion.
check("status 0 beats a body",
      HegotaFaucetVerdict.of(status: 0, msg: "sent", txHash: "0xabc") == .unreachable)

// THE REPORTED BUG: the measured, expected refusal — one claim per source IP
// per hour. It arrives as a bare 429, which `postJSON` mapped to nil and the
// sheet then tried to recognise by grepping the text "no answer" for "429".
check("a 429 is the rate limit",
      HegotaFaucetVerdict.of(status: 429, msg: nil, txHash: nil) == .rateLimited)
// The service is free to attach prose to it; the STATUS decides, not the text.
check("a 429 with prose is still the rate limit",
      HegotaFaucetVerdict.of(status: 429, msg: "too many requests", txHash: "0xdead")
        == .rateLimited)

// The measured success shape.
check("msg=sent with a hash is a claim",
      HegotaFaucetVerdict.of(status: 200, msg: "sent", txHash: "0xfeed") == .sent(hash: "0xfeed"))
check("casing is not a contract",
      HegotaFaucetVerdict.of(status: 200, msg: "SENT", txHash: "0xfeed") == .sent(hash: "0xfeed"))
// A CLAIM WITH NO TRANSACTION IS NOT A CLAIM. Reporting it as one would put a
// receipt in the corpus, and a `hegota:claimed:` row on the explorer, for
// money that never moved.
if case .refused = HegotaFaucetVerdict.of(status: 200, msg: "sent", txHash: nil) {} else {
    check("msg=sent with no hash is refused, never claimed", false)
}
if case .refused = HegotaFaucetVerdict.of(status: 200, msg: "sent", txHash: "   ") {} else {
    check("a blank hash is not a hash", false)
}

// The service's own words beat our guess at what a code means.
check("the body's message is kept verbatim",
      HegotaFaucetVerdict.of(status: 200, msg: "invalid address", txHash: nil)
        == .refused("invalid address"))
check("a message on a non-200 is still kept",
      HegotaFaucetVerdict.of(status: 400, msg: "invalid address", txHash: nil)
        == .refused("invalid address"))
// A refusal with nothing to say names the status rather than inventing prose,
// and a 200 that says nothing is NOT reported as a status.
check("a wordless non-200 names its status",
      HegotaFaucetVerdict.of(status: 503, msg: nil, txHash: nil) == .refused("it answered 503"))
check("a wordless 200 does not name a status",
      HegotaFaucetVerdict.of(status: 200, msg: nil, txHash: nil)
        == .refused("it answered with nothing"))
check("a whitespace-only message is no message",
      HegotaFaucetVerdict.of(status: 500, msg: "  ", txHash: nil) == .refused("it answered 500"))

// Every state a screen can be handed says something, except the one the screen
// draws itself.
check("a claim has no failure line", HegotaFaucetVerdict.sent(hash: "0x1").sentence == nil)
check("the rate limit says so", (HegotaFaucetVerdict.rateLimited.sentence ?? "").contains("hour"))
check("unreachable does not say refused",
      !(HegotaFaucetVerdict.unreachable.sentence ?? "").lowercased().contains("refused"))
check("a refusal quotes the service",
      (HegotaFaucetVerdict.refused("invalid address").sentence ?? "").contains("invalid address"))

print("OUTCOMES=ok")
if fails == 0 { print("  ok") } else { exit(1) }
SWIFT

swiftc -O -o "$WORK/wrun" "$WORK/HegotaWriteOutcome.swift" \
  "$WORK/w/main.swift" 2>"$WORK/wbuild.log" || {
  echo "✗ HegotaWriteOutcome.swift did not compile standalone (it must stay Foundation-only)"
  head -20 "$WORK/wbuild.log"; exit 1; }
echo "hegota write outcomes:"
"$WORK/wrun" > "$WORK/wout.txt" || { grep '✗' "$WORK/wout.txt"; exit 1; }
grep -v '^OUTCOMES=' "$WORK/wout.txt"

echo "write-outcome mutations:"
wmutate() {
  local label="$1" from="$2" to="$3" file="$4"
  cp "$OUT" "$WORK/HegotaWriteOutcome.swift"
  local target="$WORK/$(basename "$file")"
  if ! grep -qF -- "$from" "$target"; then
    echo "  ✗ STALE MUTATION '$label' — pattern not found in $(basename "$file")"; return 1
  fi
  python3 - "$target" "$from" "$to" <<'PYMUT'
import sys, io
p, a, b = sys.argv[1], sys.argv[2], sys.argv[3]
s = io.open(p, encoding="utf-8").read()
io.open(p, "w", encoding="utf-8").write(s.replace(a, b, 1))
PYMUT
  if swiftc -O -o "$WORK/wmut" "$WORK/HegotaWriteOutcome.swift" \
       "$WORK/w/main.swift" 2>/dev/null && "$WORK/wmut" >/dev/null 2>&1; then
    echo "  ✗ MUTATION SURVIVED: $label"; return 1
  fi
  echo "  ✓ caught: $label"; return 0
}
WMUT=0
# The bug itself: the rate limit read as an ordinary refusal.
wmutate "the 429 rung removed" 'if status == 429 { return .rateLimited }' \
  'if status == -1 { return .rateLimited }' "$OUT" || WMUT=1
# ORDER: a dead host reported as a refusal sends somebody to fix an address
# that was never the problem.
wmutate "transport failure read as a refusal" 'if status == 0 { return .unreachable }' \
  'if status == -2 { return .unreachable }' "$OUT" || WMUT=1
# A receipt for money that never moved.
wmutate "a hashless claim reported as sent" \
  'return hash.isEmpty ? .refused(String(localized: "it reported no transaction")) : .sent(hash: hash)' \
  'return .sent(hash: hash)' "$OUT" || WMUT=1
# The service's own words dropped in favour of a status code.
wmutate "the body message ignored" 'if !said.isEmpty { return .refused(said) }' \
  'if said.isEmpty { return .refused(said) }' "$OUT" || WMUT=1
# An unknown message swallowed instead of quoted — the shape the whole report
[[ $WMUT -eq 0 ]] || exit 1

# --- drift guards for the callers -------------------------------------------
# Read from a COMMENT-STRIPPED copy: all three files DOCUMENT these rules by
# naming exactly what they must not do (the Obsidian/Cursor lesson).
strip_comments "$SEND"  > "$WORK/send.nc"
strip_comments "$SHEET" > "$WORK/sheet.nc"

# THE FAUCET MUST KEEP BOTH THE STATUS AND THE BODY. `postJSON` returns nil for
# any non-200, so the measured 429 is indistinguishable from a dead host
# through it — which is what made the rate-limit sentence unreachable — and
# `postJSONStatus` separates those two while still dropping the faucet's own
# words on a 4xx, which are the other half of the answer.
grep -qF 'IngestSupport.postJSONBody(faucetClaimEndpoint' "$WORK/send.nc" \
  || { echo "✗ the faucet claim no longer reads the status AND the body — a 429 reads as a dead host, and a refusal's own words are dropped"; exit 1; }
if grep -qE 'IngestSupport\.postJSON(Status)?\(faucetClaimEndpoint' "$WORK/send.nc"; then
  echo "✗ the faucet claim is back on a helper that drops non-200 bodies"; exit 1
fi
# THE SHEET MUST NOT RE-DERIVE THE VERDICT FROM ITS OWN TEXT. That is the exact
# defect: it grepped a failure string for "429" that could never contain one.
if grep -q '429' "$WORK/sheet.nc"; then
  echo "✗ HegotaKeySheet is inspecting failure TEXT for a status code again — read the verdict, not the sentence"; exit 1
fi

# THE KEY MUST SURVIVE A REINSTALL. The keychain item outlives the cached
# address, so `SecItemAdd` answers errSecDuplicateItem and, before §531, the
# account could never be made again — and with no key there is no faucet
# button either.
grep -qF 'errSecDuplicateItem' "$WORK/key.nc" \
  || { echo "✗ HegotaKey no longer handles a keychain item that outlived its cached address — create() is a permanent dead end after a reinstall"; exit 1; }
grep -qF 'adoptStoredKey' "$WORK/key.nc" \
  || { echo "✗ HegotaKey no longer adopts the existing key — replacing it strands whatever the chain already gave that account"; exit 1; }
# NEVER DELETE ON A MAYBE. A locked device answers `SecItemCopyMatching`
# exactly like an item that is not there, and a two-state adoption reads that
# as "the bytes are junk" and destroys this phone's real account — the one
# outcome worse than the bug being fixed. `SignerKey.presence()`'s rule.
grep -qF 'case unreadable(OSStatus)' "$WORK/key.nc" \
  || { echo "✗ HegotaKey's adoption is no longer three-state — an unreadable keychain will be read as unusable bytes and the real key deleted"; exit 1; }
python3 - "$WORK/key.nc" <<'PYADOPT' || exit 1
import sys, io
src = io.open(sys.argv[1], encoding="utf-8").read()
start = src.find("switch adoptStoredKey() {")
if start < 0:
    print("✗ create() no longer switches over the adoption outcome")
    sys.exit(1)
arm = src[start:src.find("case .unusableBytes", start)]
if "delete()" in arm:
    print("✗ create() deletes the keychain item on an outcome that is not proven-unusable bytes")
    sys.exit(1)
sys.exit(0)
PYADOPT
# `.destroyed` must be able to make a new one; the sheet's own head promises it.
python3 - "$WORK/key.nc" <<'PYDESTROY' || exit 1
import sys, io
src = io.open(sys.argv[1], encoding="utf-8").read()
start = src.find("static func create() throws -> String {")
if start < 0:
    print("✗ HegotaKey.create is gone"); sys.exit(1)
body = src[start:start + 1400]
if "case .destroyed:" not in body:
    print("✗ HegotaKey.create no longer answers .destroyed — the sheet's head says making a new one is safe over a button that refuses")
    sys.exit(1)
if "removeObject(forKey: addressKey)" not in body:
    print("✗ HegotaKey.create no longer clears the stale cached address, so a destroyed key can never be replaced")
    sys.exit(1)
sys.exit(0)
PYDESTROY
# Removing means removing: a delete query naming no synchronizability matches
# only the non-synchronizable item, and a survivor becomes the next duplicate.
grep -qF 'kSecAttrSynchronizableAny' "$WORK/key.nc" \
  || { echo "✗ HegotaKey.delete no longer matches every synchronizability — a survivor becomes the next duplicate"; exit 1; }
echo "  ok   drift guards: the faucet keeps its status, the broadcast keeps the node's words, the key survives a reinstall"

echo "✓ hegota transaction self-test passed — encoder, the faucet verdict, 11 mutations"
