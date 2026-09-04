#!/bin/zsh
# Casberi Ethrex Privacy transaction self-test — the SHIPPED encoder for the
# one chain in this app whose envelope is neither of its siblings' (2026-09-04,
# prd §593a):
#
#   Casberi/Casberi/Model/PrivacyDevnetTransaction.swift  — the 8-field envelope
#   Casberi/Casberi/Model/RLP.swift                       — shared
#   Casberi/Casberi/Model/Keccak256.swift                 — shared
#
# All Foundation-only BY DESIGN and compiled WHOLE AND UNMODIFIED here.
#
# WHY A HARNESS, AND WHY THE FIXTURES ARE REAL TRANSACTIONS. A wrong field
# order, a flattened fee triple, a stray leading zero or an elision rule applied
# to the wrong entry produces a signature that is well-formed, recovers to a
# real address, and AUTHORISES A DIFFERENT TRANSACTION. Nothing else here can
# see that: the build is happy, and this chain cannot be reached from a harness
# or from CI. So the fixtures are two real transactions taken off the wire, and
# the assertion is the one a wrong encoder cannot pass — their keccak IS the
# transaction hash the RPC reports.
#
# THE ENVELOPE WAS FOUND BY ASKING THE NODE. `eth_sendRawTransaction` here
# answers a malformed envelope by NAMING the field it was decoding and its Rust
# type, so feeding it progressively longer RLP lists walks the structure with no
# guessing. An earlier pass enumerated three plausible ambiguities, reproduced
# Hegotá byte-exactly as a control, matched nothing here, and concluded the
# layout was unreadable. It was readable; the search was wrong.
set -uo pipefail
cd "${0:A:h}/.."

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
fail() { print -u2 "✗ $1"; exit 1 }

TX="Casberi/Casberi/Model/PrivacyDevnetTransaction.swift"
VERIFY="scripts/verify.sh"
[[ -f "$TX" ]] || fail "$TX not found"

cat > "$work/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ c: Bool, _ what: String) { if !c { print("  ✗ \(what)"); failures += 1 } }
func hx(_ s: String) -> Data {
    var out = Data(); var t = Substring(s)
    while t.count >= 2 { out.append(UInt8(t.prefix(2), radix: 16)!); t = t.dropFirst(2) }
    return out
}
func hex(_ d: Data) -> String { d.map { String(format: "%02x", $0) }.joined() }
typealias F = PrivacyDevnetTransaction.Frame
typealias S = PrivacyDevnetTransaction.Signature
typealias R = PrivacyDevnetTransaction.RootReference

SWIFT
# The fixtures live in the REPO, not in a directory passed as an argument: a
# harness that needs `$1` is one `verify.sh` runs without fixtures and that
# still prints green.
FIX="scripts/support/privacy-tx-fixtures.swift"
[[ -f "$FIX" ]] || fail "$FIX not found — the two real transactions this proves against"
cat "$FIX" >> "$work/main.swift"
cat >> "$work/main.swift" <<'SWIFT'

// THE ONE ASSERTION A WRONG ENCODER CANNOT PASS: the keccak of what we would
// broadcast IS the hash the chain reports.
for (label, fx) in [("simple", fx_simple), ("rich", fx_rich)] {
    let enc = PrivacyDevnetTransaction.encoded(fx.f)
    let h = "0x" + hex(Data(Keccak256.hash([UInt8](enc))))
    check(h == fx.hash, "\(label): keccak of the encoding IS the transaction hash — got \(h)")
    check(enc.first == 0x06, "\(label): leads with the type byte")
}

// The rich fixture is what makes the set discriminating: two 32-byte nonce
// keys and a recent-root reference, so a field swap or a dropped trailing list
// cannot reproduce it. A set that both fixtures pass for the wrong reason is
// no set at all.
check(fx_rich.f.nonceKeys.count == 2, "the rich fixture really carries two keys")
check(fx_rich.f.nonceKeys.allSatisfy { $0.count >= 31 },
      "and they are full-width, not the small named channels")
check(fx_rich.f.recentRootReferences.count == 1, "and a recent-root reference")
check(fx_rich.f.recentRootReferences[0].sourceID.count == 32,
      "whose sourceID is 32 BYTES — the width Hegotá's UInt64 cannot hold")
check(fx_simple.f.recentRootReferences.isEmpty, "the simple fixture carries none")

// The elision rule: an empty-msg entry drops its signature from the SIGNING
// bytes and keeps it in the BROADCAST bytes. If those two were identical the
// signature would commit to itself, which cannot be satisfied.
let signing = PrivacyDevnetTransaction.signingPreimage(fx_rich.f)
let sent = PrivacyDevnetTransaction.encoded(fx_rich.f)
check(signing != sent, "the signed bytes differ from the sent bytes")
check(signing.count < sent.count, "and are SHORTER — the signature is elided, not replaced")

if failures != 0 { exit(1) }
print("  ok   \(0) failures")
SWIFT

print "  building…"
xcrun swiftc -Onone -o "$work/pv" "$TX" \
  "Casberi/Casberi/Model/RLP.swift" "Casberi/Casberi/Model/Keccak256.swift" \
  "$work/main.swift" 2>"$work/log" \
  || { cat "$work/log"; fail "the encoder did not compile — it must stay Foundation-only" }
"$work/pv" || fail "assertions failed"
print "  ok   2 real transactions re-encode byte-exactly"

# ── mutations ──────────────────────────────────────────────────────────
# Each is a silent wrong signature: well-formed, recovers to a real address,
# authorising something other than what the screen said.
mutate() {
  local name="$1" from="$2" to="$3"
  local dir="$work/m"; rm -rf "$dir"; mkdir -p "$dir"
  cp "$TX" "$dir/tx.swift"
  grep -qF -- "$from" "$dir/tx.swift" || fail "mutation '$name' matches nothing — it is stale and tests the shipped code"
  python3 - "$dir/tx.swift" "$from" "$to" <<'PY'
import sys, io
p,a,b = sys.argv[1], sys.argv[2], sys.argv[3]
s = io.open(p, encoding="utf-8").read()
io.open(p,"w",encoding="utf-8").write(s.replace(a,b,1))
PY
  if xcrun swiftc -Onone -o "$dir/pv" "$dir/tx.swift" \
       "Casberi/Casberi/Model/RLP.swift" "Casberi/Casberi/Model/Keccak256.swift" \
       "$work/main.swift" 2>/dev/null && "$dir/pv" >/dev/null 2>&1; then
    fail "mutation SURVIVED: $name"
  fi
  print "  ok   caught: $name"
}

mutate "the fee triple FLATTENED (Frames' own recorded trap)" \
  ".list([.bytes(RLP.quantity(f.maxPriorityFeePerGas)),
                .bytes(RLP.quantity(f.maxFeePerGas)),
                .bytes(RLP.quantity(f.maxFeePerBlobGas))])," \
  ".bytes(RLP.quantity(f.maxPriorityFeePerGas)),
         .bytes(RLP.quantity(f.maxFeePerGas)),
         .bytes(RLP.quantity(f.maxFeePerBlobGas)),"
mutate "recent roots moved BEFORE the blob hashes" \
  ".list(f.blobVersionedHashes.map { .bytes(\$0) }),
         // LAST — see trap 2.
         .list(f.recentRootReferences.map(\\.item))" \
  ".list(f.recentRootReferences.map(\\.item)),
         .list(f.blobVersionedHashes.map { .bytes(\$0) })"
mutate "the frame budgets flattened out of their pair" \
  ".list([.bytes(RLP.quantity(gasLimit)),
                          .bytes(RLP.quantity(stateLimit))])," \
  ".bytes(RLP.quantity(gasLimit)),
                   .bytes(RLP.quantity(stateLimit)),"
mutate "nonce keys written PADDED rather than minimal" \
  '.list(f.nonceKeys.map { .bytes(RLP.minimal($0)) })' '.list(f.nonceKeys.map { .bytes($0) })'
mutate "a frame value written raw — 0x0 as one zero byte, not empty" \
  ".bytes(RLP.minimal(value))," ".bytes(value),"
mutate "signer written EMPTY, as Hegota does (measured 0/5 there, 9/9 literal here)" \
  ".bytes(signer)," ".bytes(Data())," 
mutate "the type byte changed" "static let txType: UInt8 = 0x06" "static let txType: UInt8 = 0x02"
mutate "the elision inverted — the SENT bytes lose their signature" \
  "elided && isElided ? Data() : signature" "!(elided && isElided) ? Data() : signature"
mutate "nonce and sender transposed" \
  ".bytes(RLP.quantity(f.nonce)),
         .bytes(f.sender)," \
  ".bytes(f.sender),
         .bytes(RLP.quantity(f.nonce)),"

# ── drift guards ───────────────────────────────────────────────────────
strip_comments() {
  python3 - "$1" <<'PY'
import sys
s=open(sys.argv[1],encoding="utf-8").read()
out=[];i=0;n=len(s);instr=False;esc=False
while i<n:
    c=s[i]
    if instr:
        out.append(c)
        if esc: esc=False
        elif c=='\\': esc=True
        elif c=='"': instr=False
        i+=1; continue
    if c=='"': instr=True; out.append(c); i+=1; continue
    if c=='/' and i+1<n and s[i+1]=='/':
        while i<n and s[i]!='\n': i+=1
        continue
    if c=='/' and i+1<n and s[i+1]=='*':
        i+=2
        while i+1<n and not (s[i]=='*' and s[i+1]=='/'): i+=1
        i+=2; continue
    out.append(c); i+=1
sys.stdout.write(''.join(out))
PY
}
strip_comments "$TX" > "$work/tx.bare"

# ONE encoder for both bytes. Two functions differing by a flag is how a
# transaction gets signed in one shape and broadcast in another.
[[ "$(grep -c 'RLP.encode(.list(body(' "$work/tx.bare")" -eq 2 ]] \
  || fail "signingPreimage and encoded no longer share one body function"
# Foundation-only, so the harness can compile it whole.
grep -qE '^import (SwiftUI|UIKit|SwiftData)' "$work/tx.bare" \
  && fail "PrivacyDevnetTransaction is no longer Foundation-only"
# The sourceID must stay Data. A UInt64 cannot hold this chain's 32 bytes, and
# that is precisely the width Hegota shipped because no chain could disprove it.
grep -qE 'var sourceID: Data' "$work/tx.bare" \
  || fail "RootReference.sourceID is no longer Data — a UInt64 cannot hold this chain's 32-byte value"

# THE TWO RULES THE CHAIN ITSELF TAUGHT US (2026-09-04), each found by a real
# broadcast and by nothing else. Both are REFUSALS rather than wrong sends, so
# the cost is a send that never happens — invisible to the build, the harness's
# own fixtures (which are real transactions and therefore already correct), and
# every static audit.
SEND="Casberi/Casberi/Model/PrivacyDevnetSend.swift"
[[ -f "$SEND" ]] || fail "$SEND not found"
strip_comments "$SEND" > "$work/send.bare"
# `nonce_keys count must be between 1 and 16` — an empty list is refused.
grep -qF 'nonceKeys.isEmpty ? [Data([0])] : nonceKeys' "$work/send.bare" \
  || fail "the transfer no longer guarantees at least one nonce key — the node refuses an empty list outright"
# `non-zero value only allowed in SENDER mode` — mode 2, not 0.
grep -qE 'mode: 2, flags: 0' "$work/send.bare" \
  || fail "the transfer frame is no longer SENDER mode — mode 2 carries value on this chain and 0 is refused"
# The verify frame that gives the transaction a payer.
grep -qE 'mode: 1, flags: 3' "$work/send.bare" \
  || fail "the verify frame is gone — without it the transaction has no payer and is invalid"

grep -q "privacy-tx-selftest.sh" "$VERIFY" \
  || fail "not wired into verify.sh — the completeness guard requires it, with its reason"

print "  ok   drift guards: one body function, Foundation-only, 32-byte sourceID"
print "✓ privacy-tx: 2 real transactions byte-exact, keccak == the chain's own hash, 8 mutations, 4 drift guards"
