#!/bin/zsh
# Casberi bridge-health self-test — verifies the SHIPPED state machine behind
# "is this bridge still letting us in" (2026-08-10):
#
#   Casberi/Casberi/Model/BridgeHealth.swift
#     — Record   (the three facts kept per seat)
#     — folded   (one response folded into one record — the whole machine)
#
# WHY A HARNESS AND NOT A LIVE PROBE, and this is the strongest version of that
# argument in the tree. Most seats in this catalog have never been measured
# against a live account, and no key for them is stored on any machine this is
# built on — so there is NO path, here or on a device, that can produce the
# 401 this feature exists to notice. `-bridgeHealthProbe` can only ever report
# an empty book. This harness needs no key, no account, no network and no
# simulator, and it is the only proof these rules hold.
#
# Every failure mode is a SILENT WRONG ANSWER that renders as an ordinary tile:
#
#   • a 401 that does NOT stick — the seat flickers to "needs reconnecting" and
#     back on the next transient failure, which is exactly the badge-that-comes
#     -and-goes this feature was asked not to be;
#   • a 401 RESTAMPED every pass — a bridge shut out for a month reports it
#     started just now, so the one fact that says how bad it is reads backwards;
#   • a 429 or 5xx that DOES flag — every seat goes orange the first time a
#     train enters a tunnel, and a wall of false alarms gets ignored, which
#     costs more than the silence it replaced;
#   • a 2xx that does NOT clear — a bridge that let us back in stays flagged
#     forever, and the person re-pastes a working key to no effect.
#
# `folded` is pure and Foundation-only BY DESIGN — that is why it is split from
# the `record(host:status:named:)` plumbing, which reaches `NetworkReach` and
# `UserDefaults`. It is EXTRACTED from the shipped source by name, never copied
# here, so this cannot pass against logic the app does not run.
#
# Pure, local, deterministic. Exit non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

HEALTH="Casberi/Casberi/Model/BridgeHealth.swift"
SUPPORT="Casberi/Casberi/Model/IngestSupport.swift"
STORE="Casberi/Casberi/Model/BridgeStore.swift"
REFRESH="Casberi/Casberi/Model/BridgeRefresh.swift"
REACH="Casberi/Casberi/Model/NetworkReach.swift"
for f in "$HEALTH" "$SUPPORT" "$STORE" "$REFRESH" "$REACH"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

# --- drift guards -----------------------------------------------------------
# Wiring the extracted function cannot prove. A perfect state machine is worth
# nothing if nothing ever feeds it, or if what it decides never reaches a tile.

# THE FEED. `IngestSupport.send` is the single transport funnel for ~167 bridge
# call sites, and it is the ONLY place the HTTP status is in hand before the
# caller maps it to nil and loses it. If this call goes, the book stays empty
# forever and every probe and tile reads "everything is fine".
grep -q 'BridgeHealth.record(host:' "$SUPPORT" \
  || { echo "✗ IngestSupport.send no longer records health — the book can never fill"; exit 1; }

# THE SURFACE. Without the reconcile nothing a 401 teaches ever reaches a seat.
grep -q 'BridgeHealth.reconcile(store:' "$REFRESH" \
  || { echo "✗ the sweep no longer reconciles health onto seat status — nothing is ever shown"; exit 1; }

# A FRESH CREDENTIAL MUST NOT INHERIT THE OLD REFUSAL. Without these, pasting a
# new key leaves the stale flag and the next sweep re-flags the seat — telling
# someone their brand-new key is broken before it has been used once, which is
# worse than the silence this replaced.
grep -q 'BridgeHealth.forget' "$STORE" \
  || { echo "✗ connect/disconnect no longer clears the health record — a new key inherits the old refusal"; exit 1; }

# ONLY OUR OWN ATTENTION STATE MAY BE CLEARED. Photos, Obsidian and Files reach
# `.attention` for LOCAL access reasons this file knows nothing about; healing
# those would be a lie told by the wrong file. The guard is that `reconcile`
# compares the status line before reconnecting.
grep -q 'bridge.statusLine == attentionLine' "$HEALTH" \
  || { echo "✗ reconcile no longer checks whose attention state it is — it can now clear Photos/Files/Obsidian"; exit 1; }

# THE SCOPE RULING (health = did we REACH it, never did it have NEWS). A landed
# count or a last-arrival date appearing in this file means somebody started
# flagging quiet rooms, which is the lint-that-cries-wolf this deliberately is
# not. Comment-stripped, because the file's own doc argues the point at length
# and a raw grep would fire on the prose explaining it (the Obsidian lesson).
STRIPPED=$(sed 's://.*::' "$HEALTH")
for banned in 'lastLanded' 'landedCount' 'quietSince' 'daysSinceLanded'; do
  echo "$STRIPPED" | grep -q "$banned" \
    && { echo "✗ BridgeHealth now tracks LANDING ($banned) — it is scoped to reachability on purpose."; \
         echo "  A quiet room is usually a correct room; per-bridge silence lives in StripeSilence,"; \
         echo "  TokenBridge.emptyReadNote and FeedFreshness. Re-read this file's own doc."; exit 1; }
done

TMP=$(mktemp -d /tmp/bridge-health-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# --- extract the shipped logic ----------------------------------------------
python3 - "$HEALTH" "$TMP/extracted.swift" <<'PY'
import sys, re
src_path, out = sys.argv[1:3]
src = open(src_path).read()

def grab(signature):
    """The whole declaration whose line contains `signature`, brace-matched
    from the first `{` on that line. Fails loudly rather than silently
    yielding nothing, so a rename breaks the compile instead of the test."""
    i = src.find(signature)
    if i < 0:
        sys.exit(f"✗ could not find `{signature}` in {src_path} — extraction is stale")
    start = src.rfind("\n", 0, i) + 1
    j = src.find("{", i)
    depth, k = 0, j
    while k < len(src):
        if src[k] == "{": depth += 1
        elif src[k] == "}":
            depth -= 1
            if depth == 0: break
        k += 1
    return src[start:k + 1]

parts = [grab("struct Record: Codable"),
         grab("static func folded(")]
open(out, "w").write(
    "import Foundation\n\nenum BridgeHealth {\n"
    + "\n\n".join(p.replace("private ", "") for p in parts)
    + "\n}\n")
PY

# --- the assertions ---------------------------------------------------------
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ label: String, _ ok: Bool) {
    if !ok { print("  ✗ \(label)"); failures += 1 }
}

let t0 = Date(timeIntervalSince1970: 1_000_000)
let t1 = t0.addingTimeInterval(3600)
let t2 = t1.addingTimeInterval(86_400)

typealias R = BridgeHealth.Record
func fold(_ r: R, _ s: Int, _ at: Date) -> R { BridgeHealth.folded(r, status: s, now: at) }

// 1. A clean read records success and flags nothing.
let ok200 = fold(R(), 200, t0)
check("200 stamps lastOK", ok200.lastOK == t0)
check("200 flags nothing", ok200.authFailedAt == nil)
check("200 records its status", ok200.lastStatus == 200)

// 2. Auth refusal sticks.
let refused = fold(ok200, 401, t1)
check("401 flags", refused.authFailedAt == t1)
check("401 leaves lastOK alone", refused.lastOK == t0)
let refused403 = fold(R(), 403, t1)
check("403 flags too", refused403.authFailedAt == t1)

// 3. FIRST SIGHTING WINS — the fact that says how bad it is.
let stillRefused = fold(refused, 401, t2)
check("a second 401 does not restamp", stillRefused.authFailedAt == t1)

// 4. Transient failures never flag, and never clear.
for transient in [429, 500, 502, 503, 0, 404] {
    check("\(transient) does not flag", fold(R(), transient, t1).authFailedAt == nil)
    check("\(transient) does not clear an existing flag",
          fold(refused, transient, t2).authFailedAt == t1)
}

// 5. Only being LET BACK IN clears it.
let healed = fold(refused, 200, t2)
check("2xx clears the flag", healed.authFailedAt == nil)
check("2xx restamps lastOK", healed.lastOK == t2)

// 6. The whole 2xx range counts as success, and nothing outside it does.
check("204 clears", fold(refused, 204, t2).authFailedAt == nil)
check("299 clears", fold(refused, 299, t2).authFailedAt == nil)
check("300 does not clear", fold(refused, 300, t2).authFailedAt == t1)
check("199 does not clear", fold(refused, 199, t2).authFailedAt == t1)

// 7. A realistic arc: fine, a tunnel, still fine, revoked, revoked, re-keyed.
var arc = R()
for (status, at) in [(200, t0), (0, t0), (200, t0), (401, t1), (429, t1), (401, t2)] as [(Int, Date)] {
    arc = fold(arc, status, at)
}
check("arc ends shut out, dated to the FIRST refusal", arc.authFailedAt == t1)
check("arc remembers the last good read", arc.lastOK == t0)
arc = fold(arc, 200, t2)
check("arc heals on a good read", arc.authFailedAt == nil)

if failures > 0 { print("✗ bridge-health self-test: \(failures) failure(s)"); exit(1) }
print("✓ bridge-health self-test: state machine verified")
SWIFT

swiftc -O -o "$TMP/run" "$TMP/extracted.swift" "$TMP/main.swift" 2>&1 \
  | grep -E "error:" && { echo "✗ harness failed to compile"; exit 1; }
"$TMP/run"

# --- mutation pass ----------------------------------------------------------
# A test that cannot fail proves nothing. Each mutation is one of the silent
# wrong answers named at the top of this file; every one MUST be caught.
mutate() {
  local label="$1" from="$2" to="$3"
  local dir="$TMP/mut"; rm -rf "$dir"; mkdir -p "$dir"
  python3 - "$TMP/extracted.swift" "$dir/extracted.swift" "$from" "$to" <<'PY'
import sys
src, dst, a, b = sys.argv[1:5]
text = open(src).read()
if a not in text:
    sys.exit(f"✗ mutation target not found (stale harness): {a!r}")
open(dst, "w").write(text.replace(a, b, 1))
PY
  cp "$TMP/main.swift" "$dir/main.swift"
  if swiftc -O -o "$dir/run" "$dir/extracted.swift" "$dir/main.swift" 2>/dev/null \
     && "$dir/run" >/dev/null 2>&1; then
    echo "  ✗ SURVIVED: $label"; return 1
  fi
  return 0
}

mut_fail=0
# The 401 stops sticking — the flicker.
mutate "401 no longer flags" \
  "if next.authFailedAt == nil { next.authFailedAt = now }" "break" || mut_fail=1
# First-sighting lost — a month-old breakage reads as brand new.
mutate "401 restamps every pass" \
  "if next.authFailedAt == nil { next.authFailedAt = now }" "next.authFailedAt = now" || mut_fail=1
# Transient failures start flagging — the wall of false alarms.
mutate "any failure flags" "case 401, 403:" "case 400...599:" || mut_fail=1
# A good read stops clearing — a working key stays flagged forever.
mutate "2xx no longer clears" "next.authFailedAt = nil" "next.lastStatus = status" || mut_fail=1
# The success range narrows — a 204 (a legitimate empty read) stops healing.
mutate "success range narrowed" "case 200...299:" "case 200...200:" || mut_fail=1
# lastOK stops moving, so "when did this last work" is frozen at the first read.
mutate "lastOK frozen" "next.lastOK = now" "next.lastOK = next.lastOK ?? now" || mut_fail=1

[[ $mut_fail -eq 0 ]] || { echo "✗ bridge-health self-test: a mutation survived"; exit 1; }
echo "✓ bridge-health self-test: 6 mutations caught, drift guards green"
