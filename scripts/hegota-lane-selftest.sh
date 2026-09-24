#!/bin/zsh
# Keyed-nonce LANES on Hegotá (EIP-8250) — the send path's lane, and where a
# lane's counter is read from (2026-09-24).
#
# WHY. `HegotaSend.sendValue` hardcoded `nonceKeys: [0]` since §525, so every
# send this app has made occupied one lane and queued behind the last. That is
# the opposite of what a keyed nonce is for: two sends on disjoint keys are
# valid in either order, so a slow one must not hold up the next. The lane is
# the caller's now, and a named lane's counter comes out of the manager
# predeploy's STORAGE, because that contract is five bytes of REVERT and
# answers no call (§509).
#
# WHAT A WRONG ANSWER LOOKS LIKE, which is why each assertion exists:
#   • A lane that silently falls back to 0 sends on the wrong sequence — the
#     chain refuses it, so the cost is a send that never happens, invisible to
#     the build and to every static audit.
#   • A slot derived key-first, or unpadded, reads a legitimate ZERO from an
#     unrelated slot: "never sent on this lane" about a lane that has moved.
#
# EVERYTHING RUNS ON COPIES IN $WORK. This harness mutates source to prove its
# own guards, and an interrupted run that left a tracked file mutated would be
# committed by whoever commits next — which happened once here, when a run
# piped through `tail` took SIGPIPE mid-mutation. The tracked tree is never
# written to.
#
# Pure and local: no network, no simulator, no key.
set -euo pipefail
cd "$(dirname "$0")/.."

SEND_SRC="Casberi/Casberi/Model/HegotaSend.swift"
COINS_SRC="Casberi/Casberi/Model/HegotaCoins.swift"
LANE_SRC="Casberi/Casberi/Model/HegotaLane.swift"
DEPS=(Casberi/Casberi/Model/HegotaAccount.swift
      Casberi/Casberi/Model/DevnetTokens.swift
      Casberi/Casberi/Model/RoomFrames.swift
      Casberi/Casberi/Model/Keccak256.swift)
for f in "$SEND_SRC" "$COINS_SRC" "$LANE_SRC" $DEPS; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/m"
cp "$SEND_SRC" "$COINS_SRC" "$LANE_SRC" $DEPS "$WORK/"
SEND="$WORK/HegotaSend.swift"
COINS="$WORK/HegotaCoins.swift"
LANE="$WORK/HegotaLane.swift"

fails=0
say() { echo "  ✓ $1"; }
bad() { echo "  ✗ $1"; fails=$((fails+1)); }

run_checks() {   # every assertion, against whatever is in $WORK right now
  local f=0 VERBOSE="$1"
  # Read a COMMENT-STRIPPED copy: this file documents the rule by naming the
  # shape it must no longer have, so a guard on raw source fires on the prose.
  local nc="$WORK/send.nc"
  sed -E 's://.*$::' "$SEND" > "$nc"

  # A guard that passes in silence is indistinguishable from one that did not
  # run, so each states its own outcome on the way through.
  want() {   # pattern, pass-words, fail-words
    if grep -q "$1" "$nc"; then $VERBOSE && say "$2"; else $VERBOSE && bad "$3"; f=1; fi
  }
  reject() { # pattern, pass-words, fail-words
    if grep -q "$1" "$nc"; then $VERBOSE && bad "$3"; f=1; else $VERBOSE && say "$2"; fi
  }
  want 'nonceKeys: \[nonceKey\]' \
       "the send takes its lane from the caller" "the lane is hardcoded again"
  reject 'nonceKeys: \[0\]' \
       "no hardcoded lane remains" "a hardcoded lane 0 remains"
  want 'nonceKey: UInt64 = 0' \
       "lane 0 stays the default, so every existing caller is unchanged" \
       "nonceKey lost its default — existing callers break"
  want 'if nonceKey == 0 { return await currentNonceSequence(for: address) }' \
       "lane 0 still reads eth_getTransactionCount (§504)" \
       "lane 0 no longer short-circuits to the count read (§504)"
  want 'guard !body.isEmpty, body.allSatisfy' \
       "an unreadable storage body is nil, never a zero" \
       "an empty storage body reads as \"never sent on this lane\""
  want 'HegotaNonceStorage.slot(address: address' \
       "a named lane reads the measured slot (§509)" \
       "a named lane no longer derives its slot (§509)"

  swiftc -Onone -o "$WORK/run" "$COINS" "$LANE" "$WORK/HegotaAccount.swift" \
    "$WORK/DevnetTokens.swift" "$WORK/RoomFrames.swift" "$WORK/Keccak256.swift" \
    "$WORK/m/main.swift" 2>"$WORK/build.log" || {
      $VERBOSE && { bad "HegotaCoins.swift did not compile standalone"; head -12 "$WORK/build.log"; }; return 1; }
  "$WORK/run" > "$WORK/out.txt" 2>&1 || f=1
  $VERBOSE && grep -v '^OUTCOMES=' "$WORK/out.txt"
  return $f
}

cat > "$WORK/m/main.swift" <<'SWIFT'
import Foundation
var fails = 0
func ok(_ l: String) { print("  ✓ \(l)") }
func no(_ l: String) { print("  ✗ \(l)"); fails += 1 }

let addr = "0x8943545177806ed17b9f23f0a21ee5948ecaa776"
let bytes = (0..<20).map { UInt8(addr.dropFirst(2 + $0*2).prefix(2), radix: 16)! }
let pad12 = [UInt8](repeating: 0, count: 12)
let pad29 = [UInt8](repeating: 0, count: 29)
let key: [UInt8] = [0xbe, 0xef, 0x01]

// Address-first, BOTH halves padded to a full word — the layout §509 pinned
// with one positive and four negatives against the live chain.
let want    = "0x" + Keccak256.hexString(Keccak256.hash(pad12 + bytes + pad29 + key))
let wrongWay = "0x" + Keccak256.hexString(Keccak256.hash(pad29 + key + pad12 + bytes))
let got = HegotaNonceStorage.slot(address: addr, key: "0xbeef01")
got == want ? ok("slot(0xbeef01) is address-first and both halves padded")
            : no("slot(0xbeef01) is wrong: \(got ?? "nil")")
got != wrongWay ? ok("the derivation is not key-first")
                : no("the derivation is key-first — it reads an unrelated slot as zero")

// A malformed key must yield nil, never a guessed slot.
for (what, k) in [("a non-hex", "zz"),
                  ("an over-wide", "0x" + String(repeating: "a", count: 66)),
                  ("an empty", "0x")] {
    HegotaNonceStorage.slot(address: addr, key: k) == nil
        ? ok("\(what) key yields no slot")
        : no("\(what) key yielded a slot — a wrong slot reads as a legitimate zero")
}
// --- which lane a send takes, and the sequence it signs with ---------------
var lanes = HegotaLane()
let me = "0xAbC0000000000000000000000000000000000001"

// Consecutive sends never share a lane — the whole point of the mechanism.
let first = (0..<4).map { _ in lanes.nextLane(for: me) }
Set(first).count == 4 ? ok("four consecutive sends take four different lanes")
                      : no("consecutive sends shared a lane: \(first)")
lanes.nextLane(for: me) == first[0] ? ok("the fifth wraps back to the first lane")
                                    : no("the rotation does not wrap")

// Address is matched case-insensitively: the Keychain returns whatever case it
// stored, and two spellings of one address must not get two rotations.
var cased = HegotaLane()
let a = cased.nextLane(for: "0xABCD"), b = cased.nextLane(for: "0xabcd")
a != b ? ok("one address in two cases shares one rotation")
       : no("a differently-cased address restarted the rotation")

// The chain's counter is a FLOOR. Two sends on one lane inside a block read the
// same number; the second must still advance or the chain refuses it.
var seqs = HegotaLane()
let s1 = seqs.sequence(for: me, lane: 1, chainSequence: 7)
let s2 = seqs.sequence(for: me, lane: 1, chainSequence: 7)
(s1 == 7 && s2 == 8) ? ok("a second send on one lane advances past a stale counter")
                     : no("two sends on one lane got \(s1.map(String.init) ?? "nil") and \(s2.map(String.init) ?? "nil")")

// A lane that has moved on chain past what we issued must take the chain's.
var caught = HegotaLane()
_ = caught.sequence(for: me, lane: 2, chainSequence: 1)
caught.sequence(for: me, lane: 2, chainSequence: 9) == 9
    ? ok("a chain counter ahead of our memory wins")
    : no("our memory overrode a higher chain counter")

// Unreadable chain → nil, never a remembered number we cannot stand behind.
var blind = HegotaLane()
_ = blind.sequence(for: me, lane: 3, chainSequence: 4)
blind.sequence(for: me, lane: 3, chainSequence: nil) == nil
    ? ok("an unreadable chain yields no sequence, not a remembered one")
    : no("a remembered sequence was used with no chain reading behind it")

// A refused send never spent its sequence; forgetting must reopen the lane.
var reset = HegotaLane()
_ = reset.sequence(for: me, lane: 0, chainSequence: 3)
reset.forget(address: me)
reset.sequence(for: me, lane: 0, chainSequence: 3) == 3
    ? ok("forgetting reopens a lane after a refused send")
    : no("a refused send left a hole later sends sit behind")

if fails > 0 { exit(1) }
print("OUTCOMES=ok")
SWIFT

echo "hegota lanes:"
run_checks true || fails=$((fails+1))

# --- mutations --------------------------------------------------------------
# A guard that cannot demonstrate it catches anything certifies nothing, and a
# mutation that changes NOTHING passes and reports SURVIVED. Each is applied to
# the COPY, and `run_checks false` must go red.
echo "  mutations:"
mutate() {  # label, from, to, file
  local label="$1" from="$2" to="$3" file="$4"
  cp "$file" "$file.pre"
  python3 -c 'import io,sys
p,a,b=sys.argv[1],sys.argv[2],sys.argv[3]
s=io.open(p,encoding="utf-8").read()
if a not in s: sys.exit(1)
io.open(p,"w",encoding="utf-8").write(s.replace(a,b,1))' "$file" "$from" "$to" \
    || { mv "$file.pre" "$file"; echo "    ✗ anchor not found: $label"; return 1; }
  local caught=1
  if run_checks false >/dev/null 2>&1; then caught=0; fi
  mv "$file.pre" "$file"
  (( caught )) && { echo "    ✓ caught: $label"; return 0; }
  echo "    ✗ MUTATION SURVIVED: $label"; return 1
}
MUT=0
mutate "the lane goes back to a hardcoded 0" \
  'nonceKeys: [nonceKey],' 'nonceKeys: [0],' "$SEND" || MUT=1
mutate "the nonceKey default is dropped (every existing caller breaks)" \
  'nonceKey: UInt64 = 0,' 'nonceKey: UInt64,' "$SEND" || MUT=1
mutate "lane 0 stops short-circuiting to the count read" \
  'if nonceKey == 0 { return await currentNonceSequence(for: address) }' \
  'if nonceKey == 99 { return await currentNonceSequence(for: address) }' "$SEND" || MUT=1
mutate "the slot derivation goes key-first" \
  'Keccak256.hash(a + k)' 'Keccak256.hash(k + a)' "$COINS" || MUT=1
mutate "an empty storage body reads as a zero sequence" \
  'guard !body.isEmpty, body.allSatisfy(\.isHexDigit) else { return nil }' '' "$SEND" || MUT=1
mutate "the lane rotation stops rotating" \
  'let position = ((lastLane[key] ?? -1) + 1) % Self.all.count' \
  'let position = 0' "$LANE" || MUT=1
mutate "the chain counter is taken as the answer, not a floor" \
  'let next = max(chainSequence, issued ?? chainSequence)' \
  'let next = chainSequence' "$LANE" || MUT=1
mutate "an unreadable chain falls back to a remembered sequence" \
  'guard let chainSequence else { return nil }' \
  'let chainSequence = chainSequence ?? 0' "$LANE" || MUT=1
mutate "the address case is no longer folded" \
  'let key = address.lowercased()' 'let key = address' "$LANE" || MUT=1
mutate "a malformed key yields a guessed slot instead of nil" \
  'guard let a = word(address), let k = word(key) else { return nil }' \
  'let a = word(address) ?? [], k = word(key) ?? []' "$COINS" || MUT=1
[[ $MUT -eq 0 ]] || fails=$((fails+1))

[[ $fails -eq 0 ]] && { echo "  ok"; exit 0; } || { echo "✗ $fails failed"; exit 1; }
