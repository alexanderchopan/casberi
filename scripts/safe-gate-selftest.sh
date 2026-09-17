#!/bin/zsh
# Casberi Safe service-gate self-test — a refused read is never an empty answer
# (prd §789):
#
#   Casberi/Casberi/Model/SafeServiceLedger.swift   (compiled whole)
#   Casberi/Casberi/Model/SafeServiceGate.swift
#   Casberi/Casberi/Model/SafeBridge.swift
#   Casberi/Casberi/Model/SafeSigner.swift
#   Casberi/Casberi/Model/SafeAsk.swift
#   Casberi/Casberi/Model/AddressKind.swift
#   Casberi/Casberi/Screens/SafeScreen.swift
#
# WHY. On 2026-09-16 Safe's Transaction Service answered every keyless call
# `429 Monthly quota exceeded` — one pool shared by every keyless caller. Each
# reader mapped a non-200 to nil and folded nil into "nothing": the Safe page
# said "Up to date", the ask said "No Safe wallets detected", and the address
# book filed a Safe as a smart account for thirty days. None of that is
# reachable from a simulator on demand (the quota is somebody else's), so what
# is proven here is the fold and the wiring.
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

LEDGER="Casberi/Casberi/Model/SafeServiceLedger.swift"
GATE="Casberi/Casberi/Model/SafeServiceGate.swift"
BRIDGE="Casberi/Casberi/Model/SafeBridge.swift"
SIGNER="Casberi/Casberi/Model/SafeSigner.swift"
ASK="Casberi/Casberi/Model/SafeAsk.swift"
KIND="Casberi/Casberi/Model/AddressKind.swift"
SCREEN="Casberi/Casberi/Screens/SafeScreen.swift"
for f in "$LEDGER" "$GATE" "$BRIDGE" "$SIGNER" "$ASK" "$KIND" "$SCREEN"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# --- wiring -------------------------------------------------------------------
# Comment-stripped copies, because these files explain the old shape in prose.
# Written to files first: under `pipefail`, `grep -q` closing a pipe early
# SIGPIPEs the `sed` feeding it and fails a check that matched.
strip() { local out="$TMP/${1:t}"; [[ -f "$out" ]] || sed -E 's://.*$::' "$1" > "$out"; print -r -- "$out"; }

B=$(strip "$BRIDGE"); S=$(strip "$SIGNER"); A=$(strip "$ASK"); K=$(strip "$KIND"); P=$(strip "$SCREEN")

# Every tx-service GET goes through the gate. A direct `IngestSupport.getJSON`
# against `baseURL(` is a read whose 429 becomes nil again.
grep -A1 'IngestSupport\.getJSON' "$B" > "$TMP/b-direct" || true
! grep -qF 'baseURL(' "$TMP/b-direct" \
  || { echo "✗ SafeBridge reads the tx service around SafeServiceGate — a 429 is an empty answer again"; exit 1; }
grep -A1 'IngestSupport\.getJSON' "$S" > "$TMP/s-direct" || true
! grep -qF 'baseURL(' "$TMP/s-direct" \
  || { echo "✗ SafeSigner reads the proposal around SafeServiceGate"; exit 1; }
[[ $(grep -cF 'SafeServiceGate.get(' "$B") -ge 6 ]] \
  || { echo "✗ SafeBridge has fewer than six gated reads (isSafe, queue, owners, detail, recheck, resolve)"; exit 1; }

# The page never turns a refused pass into `landed(0)` ("Up to date").
grep -qF 'case .throttled(let until, _):' "$P" \
  || { echo "✗ SafeScreen no longer handles a throttled sync"; exit 1; }
grep -qF 'lastResult = .says(Self.throttledLine' "$P" \
  || { echo "✗ a throttled Safe sync no longer draws as .says (§711b)"; exit 1; }
grep -qF 'case .answered: return .landed(added)' "$B" \
  || { echo "✗ syncNow no longer asks the gate whether the pass answered before reporting landed"; exit 1; }

# The ask checks the pass before saying "none" or "nothing pending".
grep -qF 'if total == 0, let refused = Self.refusedSentence(health)' "$A" \
  || { echo "✗ SafeAsk can say 'No Safe wallets detected' over a refused pass"; exit 1; }

# The address book does not file a contract while Safe's answer is unknown.
grep -qF 'guard isSafe != nil else { return }' "$K" \
  || { echo "✗ AddressKind files a possible Safe as a contract while Safe's service is refusing reads"; exit 1; }
grep -qF 'static func isSafeAnywhere(_ address: String) async -> Bool?' "$B" \
  || { echo "✗ isSafeAnywhere collapsed 'unknown' back into false"; exit 1; }

# The signer names a throttle as a throttle.
grep -qF 'return .failure(.serviceThrottled(until: until))' "$S" \
  || { echo "✗ SafeSigner reports Safe's quota as an unreadable proposal"; exit 1; }

# --- the fold -----------------------------------------------------------------
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if ok { print("  ok   \(what)") } else { print("  FAIL \(what)"); failures += 1 }
}

let now = Date(timeIntervalSince1970: 1_800_000_000)

// Reopening time.
check(SafeServiceLedger.reopensAt(resetHeader: "196279", now: now) == now.addingTimeInterval(196_279),
      "a measured x-ratelimit-reset (196279s) is believed")
// ONE MINUTE, not fifteen, since 2026-09-17 (prd §789b). The reads moved to
// Safe's Client Gateway, which sends no rate-limit header at all and whose 429
// is a per-IP burst refilling in ~20s — so the headerless default stopped being
// "a malformed header from a monthly pool" and became the normal case for a
// two-second blip. Fifteen minutes there is a quarter hour of a room unable to
// say what is in the queue. Sixty seconds is 3x the measured recovery.
check(SafeServiceLedger.reopensAt(resetHeader: nil, now: now) == now.addingTimeInterval(60),
      "no header closes for one minute (the gateway's burst, not a monthly pool)")
check(SafeServiceLedger.reopensAt(resetHeader: "garbage", now: now) == now.addingTimeInterval(60),
      "an unreadable header closes for one minute")
check(SafeServiceLedger.reopensAt(resetHeader: "999999999", now: now) == now.addingTimeInterval(32 * 86_400),
      "a header claiming years is capped at 32 days")
check(SafeServiceLedger.reopensAt(resetHeader: "0", now: now) > now,
      "a zero reset still closes the gate past now")

// Health of a pass.
var l = SafeServiceLedger()
var mark = l.seq
check(l.health(since: mark) == .answered, "a pass with no reads (all cached) is answered")

l.recordAnswer(now: now)
check(l.health(since: mark) == .answered, "an answered read is answered")

mark = l.seq
let until = now.addingTimeInterval(3600)
l.recordAnswer(now: now)
l.recordThrottle(until: until)
check(l.health(since: mark) == .throttled(until: until),
      "ONE throttled read makes the pass throttled, whatever else answered")
check(l.isClosed(now: now), "a 429 closes the gate")
check(!l.isClosed(now: until.addingTimeInterval(1)), "the gate reopens at the reset")

mark = l.seq
l.recordThrottle(until: nil)
check(l.throttledUntil == until, "a gated (unsent) read keeps the reset it was refused under")
check(l.health(since: mark) == .throttled(until: until), "a gated read still marks the pass throttled")

mark = l.seq
l.recordFailure()
check(l.health(since: mark) == .unreachable, "only failures is unreachable")
l.recordAnswer(now: now)
check(l.health(since: mark) == .answered, "a failure beside an answer is not unreachable")
check(l.throttledUntil == nil, "an answer reopens the gate")

// Marks are per pass: an old throttle never taints a later pass.
var m = SafeServiceLedger()
m.recordThrottle(until: until)
let later = m.seq
m.recordAnswer(now: now)
check(m.health(since: later) == .answered, "a throttle before the mark is not this pass's")

// Round trip, as persisted.
if let data = try? JSONEncoder().encode(l),
   let back = try? JSONDecoder().decode(SafeServiceLedger.self, from: data) {
    check(back == l, "the ledger survives a relaunch byte for byte")
} else {
    check(false, "the ledger encodes")
}

if failures > 0 { print("✗ \(failures) failure(s)"); exit(1) }
print("\n✓ safe gate: a refused read is never an empty answer")
SWIFT

xcrun swiftc -O -o "$TMP/safegate" "$LEDGER" "$TMP/main.swift" 2>&1 | grep -v '^ *$' || true
[[ -x "$TMP/safegate" ]] || { echo "✗ the harness did not compile — SafeServiceLedger.swift is no longer Foundation-only"; exit 1; }
"$TMP/safegate"
