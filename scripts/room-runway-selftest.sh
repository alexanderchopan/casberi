#!/bin/zsh
# Casberi room-runway self-test — verifies the SHIPPED arithmetic behind every
# deadline runway in the app (2026-09-04):
#
#   Casberi/Casberi/Model/RoomRunway.swift
#
# Four rooms draw a runway — Stripe's disputes, Polar's, Dodo Payments' retries
# and Cloudflare's expiries — and until this landed each carried its own
# byte-identical copy of `position`, three of them of `span` and `spanLabel`
# besides, and each of the four harnesses asserted the SAME six properties of
# its own copy. One question, four answers, four sets of tests: the shape
# `ToolScore.rank` was folded into `AgentCorpusTools.rank` to end.
#
# Every failure here is a SILENT WRONG ANSWER THAT DRAWS BEAUTIFULLY —
#
#   · an unclamped position puts the one deadline you have already missed off
#     the left edge, where it does not look wrong, it looks absent
#   · a span that no longer floors puts a "3 days" mark off the end of its own
#     axis
#   · a span taking the NEAREST day instead of the furthest draws every later
#     deadline piled on the last pixel
#   · a label that disagrees with the span draws a correct axis under a wrong
#     number
#
# `RoomRunway.swift` is Foundation-only BY DESIGN, so it is compiled WHOLE AND
# UNMODIFIED — the strongest form of "the harness ran the shipped logic".
#
# The four room harnesses keep a DRIFT GUARD that their own `position` still
# forwards here rather than growing a second copy; the properties themselves
# are asserted once, in this file.
#
# Pure, local, deterministic — no network, no token, no simulator. Exit
# non-zero on failure. Accepts an optional `--self-test` argument (ignored —
# every assertion and mutation below already runs on every invocation).
set -euo pipefail
cd "$(dirname "$0")/.."

RUNWAY="Casberi/Casberi/Model/RoomRunway.swift"
RAIL="Casberi/Casberi/Design/DSRunwayRail.swift"
[[ -f "$RUNWAY" ]] || { echo "✗ $RUNWAY not found"; exit 1; }
[[ -f "$RAIL" ]] || { echo "✗ $RAIL not found"; exit 1; }

# --- drift guards -------------------------------------------------------------
# Wiring the compiled functions cannot prove about themselves.

# Every room must FORWARD, never re-implement. A second copy of the clamp is
# exactly what this file exists to end, and it would pass every assertion below
# while drifting the day one copy is edited.
for pair in \
  "Casberi/Casberi/Model/StripeRoom.swift:StripeRoom" \
  "Casberi/Casberi/Model/PolarRoom.swift:PolarRoom" \
  "Casberi/Casberi/Model/DodoPaymentsRoom.swift:DodoPaymentsRoom" \
  "Casberi/Casberi/Model/CloudflareRunway.swift:CloudflareRunway"; do
  f="${pair%%:*}"; n="${pair##*:}"
  grep -q 'RoomRunway.position(days: days, span: span)' "$f" \
    || { echo "✗ $n.position no longer forwards to RoomRunway — a second copy of the clamp is the drift this file exists to end"; exit 1; }
  # The clamp must live in ONE place: no room may carry the arithmetic itself.
  if grep -q 'min(max(Double(days) / Double(span), 0), 1)' "$f"; then
    echo "✗ $n re-implements the position clamp instead of forwarding"; exit 1
  fi
done

# The three rooms that share the ladder and the label (Cloudflare deliberately
# does not — its span is floored at its own fetch window and rounded to 30-day
# boundaries, and its label stays days-only so the window reads as the window).
for pair in \
  "Casberi/Casberi/Model/StripeRoom.swift:StripeRoom" \
  "Casberi/Casberi/Model/PolarRoom.swift:PolarRoom" \
  "Casberi/Casberi/Model/DodoPaymentsRoom.swift:DodoPaymentsRoom"; do
  f="${pair%%:*}"; n="${pair##*:}"
  grep -q 'RoomRunway.span(days: days)' "$f" \
    || { echo "✗ $n.span no longer forwards to RoomRunway"; exit 1; }
  grep -q 'RoomRunway.spanLabel(span: span)' "$f" \
    || { echo "✗ $n.spanLabel no longer forwards to RoomRunway"; exit 1; }
done

# Cloudflare keeps its OWN span and label, and that divergence is deliberate.
# Guarded so a later tidy-up cannot quietly fold it in: its rail would then be
# labelled in months and hide that the window is exactly the fetch window.
grep -q 'guard furthest > 60 else { return 60 }' "Casberi/Casberi/Model/CloudflareRunway.swift" \
  || { echo "✗ Cloudflare's span no longer floors at its own fetch window"; exit 1; }

# THE RAIL IS SIZED FROM DATA, SO IT ARRIVES (design-motion law), and it is
# hidden from VoiceOver because every mark is a row below it that speaks.
grep -q 'chartWipe(reduceMotion:' "$RAIL" \
  || { echo "✗ DSRunwayRail no longer arrives — a rail that simply IS reads as chrome"; exit 1; }
grep -q 'accessibilityHidden(true)' "$RAIL" \
  || { echo "✗ DSRunwayRail no longer hides from VoiceOver — the rows below already speak these facts"; exit 1; }
# A rail with no handler must attach NO gesture: an always-on contentShape over
# an inert rail swallows taps meant for whatever sits behind it.
grep -q 'if let onPick' "$RAIL" \
  || { echo "✗ DSRunwayRail's pick is no longer conditional — an inert rail would swallow taps"; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ name: String, _ ok: Bool) {
    if ok { print("  ✓ \(name)") } else { print("  ✗ \(name)"); failures += 1 }
}
func print(_ s: String) { Swift.print(s) }

Swift.print("RoomRunway.position — where a mark sits, 0…1")
check("today sits at the start", RoomRunway.position(days: 0, span: 30) == 0)
check("the far end sits at one", RoomRunway.position(days: 30, span: 30) == 1)
check("halfway is halfway", abs(RoomRunway.position(days: 15, span: 30) - 0.5) < 0.0001)
// The one deadline you most need to see is the one you have already missed.
check("an overdue deadline pins to the start", RoomRunway.position(days: -9, span: 30) == 0)
check("a deadline far past pins to the start, never off the axis",
      RoomRunway.position(days: -9999, span: 30) == 0)
check("a deadline past the span clamps to the end", RoomRunway.position(days: 99, span: 30) == 1)
check("a zero span can't divide by zero", RoomRunway.position(days: 5, span: 0) == 0)
check("a negative span can't place anything", RoomRunway.position(days: 5, span: -30) == 0)
// Cloudflare's case: a row that has already come true belongs at "now".
check("an already-true row pins to now", RoomRunway.position(days: nil, span: 60) == 0)
check("a nil day on a zero span is still zero", RoomRunway.position(days: nil, span: 0) == 0)

Swift.print("")
Swift.print("RoomRunway.span — how far ahead the axis reaches")
check("a two-day horizon still floors at a week", RoomRunway.span(days: [2]) == 7)
check("no deadlines at all still floors at a week", RoomRunway.span(days: []) == 7)
check("the ladder climbs to the first bound that fits", RoomRunway.span(days: [8]) == 14)
check("a bound exactly met is not exceeded", RoomRunway.span(days: [30]) == 30)
check("the FURTHEST day sets the span, not the nearest",
      RoomRunway.span(days: [1, 2, 45]) == 60)
check("past the top of the ladder the span is the furthest itself",
      RoomRunway.span(days: [120]) == 120)
// An all-overdue room: every day is negative, so the ladder floors.
check("an all-overdue room floors at a week", RoomRunway.span(days: [-3, -20]) == 7)

Swift.print("")
Swift.print("RoomRunway.spanLabel — the axis can never be labelled a length it isn't")
check("a whole number of months reads in months", RoomRunway.spanLabel(span: 60) == "2 mo")
check("thirty days is one month", RoomRunway.spanLabel(span: 30) == "1 mo")
check("a span that doesn't divide reads in days", RoomRunway.spanLabel(span: 14) == "14 days")
// PAST THE LADDER the span is the furthest day itself, so it can be any number
// — and this is the ONLY fixture that separates "divides exactly" from "is at
// least thirty". Without it, dropping the modulo entirely leaves every
// assertion green while a 45-day rail is labelled "1 mo".
check("a long span that doesn't divide still reads in days",
      RoomRunway.spanLabel(span: 45) == "45 days")
check("a very long span that doesn't divide still reads in days",
      RoomRunway.spanLabel(span: 100) == "100 days")
check("the floor reads in days", RoomRunway.spanLabel(span: 7) == "7 days")
// 0 % 30 == 0, so a bare modulo test would print "0 mo".
check("a zero span is not zero months", RoomRunway.spanLabel(span: 0) == "0 days")

Swift.print("")
if failures == 0 {
    Swift.print("✓ room-runway self-test: all assertions passed")
} else {
    Swift.print("✗ room-runway self-test: \(failures) assertion(s) failed")
    exit(1)
}
SWIFT

if ! swiftc -Onone -o "$TMP/run" "$RUNWAY" "$TMP/main.swift" 2>"$TMP/build.log"; then
  echo "✗ RoomRunway.swift did not compile"
  grep -E 'error:' "$TMP/build.log" | head -20
  exit 1
fi
"$TMP/run"

# --- mutations ----------------------------------------------------------------
# Each is a real defect that renders perfectly. These moved here from the four
# room harnesses along with the code they test.
echo
echo "mutations (each must be caught)"

WORK="$TMP/work"
mutate() {
  local name="$1" from="$2" to="$3"
  rm -rf "$WORK"; mkdir -p "$WORK"
  cp "$RUNWAY" "$WORK/RoomRunway.swift"
  MUT_FROM="$from" MUT_TO="$to" python3 - "$WORK/RoomRunway.swift" <<'PY'
import os, sys
path = sys.argv[1]
src = open(path).read()
frm, to = os.environ["MUT_FROM"], os.environ["MUT_TO"]
if frm not in src:
    sys.stderr.write("ANCHOR-MISSING\n"); sys.exit(2)
open(path, "w").write(src.replace(frm, to, 1))
PY
  if [[ $? -ne 0 ]] || ! grep -qF -- "$to" "$WORK/RoomRunway.swift"; then
    echo "  ✗ $name — the mutation did not apply (the shipped source moved)"; exit 1
  fi
  if ! swiftc -Onone -o "$TMP/mut" "$WORK/RoomRunway.swift" "$TMP/main.swift" 2>/dev/null; then
    echo "  ✓ $name (rejected at compile)"; return
  fi
  if "$TMP/mut" > /dev/null 2>&1; then
    echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}

# An overdue deadline runs off the left edge and simply vanishes.
mutate "an unclamped rail position is caught" \
  'return min(max(Double(days) / Double(span), 0), 1)' \
  'return Double(days) / Double(span)'

# Clamped at the top but not the bottom — the overdue half of the same bug.
mutate "a position clamped only at the far end is caught" \
  'return min(max(Double(days) / Double(span), 0), 1)' \
  'return min(Double(days) / Double(span), 1)'

# A nil day is "already true", which is now, not the far end.
mutate "an already-true row placed at the end instead of now" \
  'guard let days else { return 0 }' \
  'guard let days else { return 1 }'

# Divides by zero, or places everything at the far end.
mutate "a zero span no longer guarded" \
  'guard span > 0 else { return 0 }' \
  'guard span >= 0 else { return 0 }'

# Every later deadline piles onto the rail's last pixel.
mutate "span no longer takes the FURTHEST day" \
  'let furthest = days.max() ?? 0' \
  'let furthest = days.min() ?? 0'

# A rail spanning two days puts a "3 days" mark off the end of its own axis.
mutate "the span no longer floors at a week" \
  'for bound in [7, 14, 30, 60, 90] where furthest <= bound { return bound }' \
  'for bound in [1, 14, 30, 60, 90] where furthest <= bound { return bound }'

# The axis reads "1 mo" over a 45-day rail.
mutate "the span label rounds instead of dividing exactly" \
  'span % 30 == 0 && span >= 30' \
  'span >= 30'

echo
echo "✓ room-runway self-test: all assertions and mutations passed"
