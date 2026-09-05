#!/bin/zsh
# Casberi Polar self-test — verifies the SHIPPED pure judgement behind the
# Polar feed-room head (2026-08-30):
#
#   Casberi/Casberi/Model/PolarRoom.swift
#
# `StripeRoom`'s exact shape and reason, applied to a second bridge: neither
# has ever been measured against a live account (no Polar token is stored, no
# Stripe key either), and every failure mode in this file is a SILENT WRONG
# ANSWER that renders perfectly —
#
#   · a dispute due tomorrow placed at the far end of the rail
#   · an overdue evidence window sorted last, or off the left edge entirely
#   · a headline claiming "3 days" for a deadline that passed yesterday
#   · an MRR reading hours old presented with no staleness clause
#   · a genuinely zero MRR (no subscribers, one-time sales only) reading as
#     "never read yet" — the two are different facts and only one apologises
#
# `PolarRoom.swift` is Foundation-only BY DESIGN, so it is compiled WHOLE AND
# UNMODIFIED — the strongest form of "the harness ran the shipped logic". No
# extraction is needed the way AWS's SigV4/Cost/Action pieces need one: this
# file touches nothing that isn't already Foundation. Everything that touches
# `Thing` or UserDefaults lives in `PolarRoomSource.swift`, which no harness
# can compile and which contains no judgement to test.
#
# Pure, local, deterministic — no network, no token, no simulator. Exit
# non-zero on failure. Accepts an optional `--self-test` argument (ignored —
# every assertion and mutation below already runs on every invocation).
set -euo pipefail
cd "$(dirname "$0")/.."

ROOM="Casberi/Casberi/Model/PolarRoom.swift"
# The runway arithmetic the room now forwards to. Compiled alongside, so every
# `position`/`span`/`spanLabel` assertion below lands on the SHIPPED
# implementation rather than on a copy of it.
SHARED_RUNWAY="Casberi/Casberi/Model/RoomRunway.swift"
SOURCE="Casberi/Casberi/Model/PolarRoomSource.swift"
BRIDGE="Casberi/Casberi/Model/PolarBridge.swift"
CARD="Casberi/Casberi/Screens/PolarRoomCard.swift"
BRIDGES="Casberi/Casberi/Model/TokenBridges.swift"
ROUTING="Casberi/Casberi/Model/BridgeRouting.swift"
REACH="Casberi/Casberi/Model/NetworkReach.swift"
FEED="Casberi/Casberi/Screens/FeedScreen.swift"
PROBES="Casberi/Casberi/Shell/ProbeHooks.swift"
for f in "$ROOM" "$SOURCE" "$BRIDGE" "$CARD" "$BRIDGES" "$ROUTING" "$REACH" "$FEED" "$PROBES"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

# --- drift guards ------------------------------------------------------------
# Wiring facts the compiled functions cannot prove about themselves. A perfect
# `ranked` order is worthless if the card draws its own, and a perfect
# `position` is worthless if the source never filters the window.
grep -q 'items.sort { $0.days < $1.days }' "$SOURCE" \
  || { echo "✗ Polar deadlines no longer sort soonest-first — the rail and the rows would disagree about the lead"; exit 1; }
grep -q 'things.live' "$SOURCE" \
  || { echo "✗ PolarRoomSource no longer filters live at the boundary (corollary 4)"; exit 1; }
grep -q 'PolarRoom.position(days: item.days, span: span)' "$CARD" \
  || { echo "✗ the Polar rail no longer places marks through the shipped position()"; exit 1; }
grep -q 'case .polar(let room)' "$FEED" \
  || { echo "✗ the Polar head is no longer rendered from the sourceHead chain"; exit 1; }
grep -q 'PolarRoomSource.compose(things: visible)' "$FEED" \
  || { echo "✗ the Polar head is not wired into sourceHead — it can never draw"; exit 1; }
grep -q 'PolarIngest.refresh(context: context)' "$BRIDGES" \
  || { echo "✗ TokenBridge.refresh no longer routes Polar to PolarIngest — the bridge lands nothing"; exit 1; }
grep -q 'api.polar.sh' "$REACH" \
  || { echo "✗ api.polar.sh is not in the reach registry — the privacy screen is wrong"; exit 1; }
grep -q 'case .polar:          PolarScreen()' "$ROUTING" \
  || { echo "✗ BridgeDestinationView no longer renders PolarScreen for .polar"; exit 1; }
grep -q 'Hook(key: "polarProbe")' "$PROBES" \
  || { echo "✗ -polarProbe is gone — an UNMEASURED API would have no measure tool"; exit 1; }
grep -q 'Hook(key: "polarRoomProbe")' "$PROBES" \
  || { echo "✗ -polarRoomProbe is gone — the head would have no headless verification"; exit 1; }

# THE DOCTRINE GUARD: no individual order may ever be read for landing — the
# whole point of following Stripe's rule rather than Dodo Payments'. Reads a
# COMMENT-STRIPPED copy, since the type doc documents this rule by naming the
# thing it must not do (the Obsidian/Cursor lesson).
TMP=$(mktemp -d /tmp/polar-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
CODE="$TMP/code-only.swift"
python3 - "$BRIDGE" "$CODE" <<'PY'
import sys
src = open(sys.argv[1]).read()
out, i, n = [], 0, len(src)
in_string = in_line = False
block = 0
while i < n:
    two = src[i:i+2]
    if in_line:
        if src[i] == "\n": in_line = False; out.append("\n")
        i += 1; continue
    if block:
        if two == "/*": block += 1; i += 2; continue
        if two == "*/": block -= 1; i += 2; continue
        if src[i] == "\n": out.append("\n")
        i += 1; continue
    if in_string:
        if src[i] == "\\": out.append(src[i:i+2]); i += 2; continue
        if src[i] == '"': in_string = False
        out.append(src[i]); i += 1; continue
    if two == "//": in_line = True; i += 2; continue
    if two == "/*": block = 1; i += 2; continue
    if src[i] == '"': in_string = True
    out.append(src[i]); i += 1
open(sys.argv[2], "w").write("".join(out))
PY
# AMENDED 2026-08-31 (prd §537, user ruling): sales DO land now, so the old
# guards — no `polar:order:` ref, no `/v1/orders` read — are gone with the
# rule they enforced. What survives is the half of the doctrine that is still
# true, and it is the half that would fail INVISIBLY: a `subscription_cycle`
# renewal is the highest-volume order shape on any healthy account, so
# admitting one buries every real sale under the machine working, and the
# room looks busier rather than broken. Guarded as a positive assertion about
# the set itself, not a grep for the absent word, so a renewal cannot be let
# in by any spelling.
grep -qE 'landableBillingReasons: Set<String> = \["purchase", "subscription_create"\]' "$CODE" \
  || { echo "✗ PolarShape.landableBillingReasons is not exactly [purchase, subscription_create] — a renewal or a proration may now land as a sale (prd §537)"; exit 1; }
grep -qE 'subscription_cycle' "$CODE" \
  && { echo "✗ PolarBridge.swift now names subscription_cycle in CODE — a renewal is a tally, never a sale (prd §537)"; exit 1; }

# A sale must never reach the lock screen: Polar emails you on every one, so
# a notification fails §306's "did you already know?" test outright. Polar has
# never appeared in NotifySweep and this keeps it that way, since landing rows
# is exactly what makes it newly possible.
grep -q 'Polar' "$(dirname "$0")/../Casberi/Casberi/Model/NotifySweep.swift" \
  && { echo "✗ NotifySweep now names Polar — a sale must never notify (prd §537: Polar already emails on every one)"; exit 1; }

# The customer is never read. The setup screen promises in as many words that
# nothing here reads a customer's name or card, and the sales shape is the
# first read that is even handed one.
grep -qE '\["customer"\]' "$CODE" \
  && { echo "✗ PolarBridge.swift now reads the customer object — the setup screen promises it never does"; exit 1; }

# THE CONDUCT GUARD, PostHog's/Stripe's shape: no write verb, ever.
for verb in '"PUT"' '"DELETE"' '"PATCH"' 'postJSON' 'deleteJSON'; do
  grep -qF -- "$verb" "$CODE" \
    && { echo "✗ PolarBridge.swift now sends a write verb ($verb) — the read-only promise is now a lie"; exit 1; }
done

# --- compile PolarRoom.swift WHOLE, unmodified -------------------------------
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ name: String, _ ok: Bool) {
    if ok { print("  ✓ \(name)") } else { print("  ✗ \(name)"); failures += 1 }
}

let cal = Calendar.current
let t0 = cal.startOfDay(for: Date(timeIntervalSince1970: 1_780_000_000))
func day(_ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: t0)! }

func item(_ name: String, days: Int) -> PolarRoom.Item {
    PolarRoom.Item(id: name, name: name, due: day(days), days: days)
}
func room(mrr: String? = "$482.00", activeSubscriptions: Int? = 12,
          asOf: Date? = t0, items: [PolarRoom.Item] = [], total: Int? = nil) -> PolarRoom {
    PolarRoom(mrr: mrr, activeSubscriptions: activeSubscriptions, asOf: asOf,
              items: items, total: total ?? items.count)
}

print("Polar — days")
check("a deadline later today is zero days out", PolarRoom.days(from: t0, to: t0.addingTimeInterval(3600)) == 0)
check("11pm the night before is one day out, not a fraction",
      PolarRoom.days(from: t0.addingTimeInterval(23 * 3600), to: day(1)) == 1)
check("yesterday is negative", PolarRoom.days(from: t0, to: day(-1)) == -1)
check("a week out is seven", PolarRoom.days(from: t0, to: day(7)) == 7)

print("")
print("Polar — the rail")
check("a span floors at a week", PolarRoom.span(days: [1, 2]) == 7)
check("a span steps to the next familiar horizon", PolarRoom.span(days: [9]) == 14)
check("a month spans thirty", PolarRoom.span(days: [21]) == 30)
check("beyond ninety it uses the real furthest", PolarRoom.span(days: [200]) == 200)
// Distinguishes max() from min() explicitly — every OTHER span assertion
// here uses a single-element array, where the two are identical and a
// max()→min() mutation would pass unnoticed (a fixture only tests the rule
// it names if it fails that rule and passes every other one).
check("span reflects the FURTHEST day among several, not the nearest",
      PolarRoom.span(days: [1, 90]) == 90)
check("an empty set still spans a week", PolarRoom.span(days: []) == 7)
check("today sits at the start", PolarRoom.position(days: 0, span: 30) == 0)
check("the far end sits at one", PolarRoom.position(days: 30, span: 30) == 1)
check("halfway is halfway", abs(PolarRoom.position(days: 15, span: 30) - 0.5) < 0.0001)
check("an overdue deadline pins to the start", PolarRoom.position(days: -9, span: 30) == 0)
check("a deadline past the span clamps to the end", PolarRoom.position(days: 99, span: 30) == 1)
check("a zero span can't divide by zero", PolarRoom.position(days: 5, span: 0) == 0)
check("a span label reads in months where it divides", PolarRoom.spanLabel(span: 60) == "2 mo")
check("a span label reads in days otherwise", PolarRoom.spanLabel(span: 14) == "14 days")

print("")
print("Polar — words")
check("overdue says so", PolarRoom.value(days: -3) == "overdue")
check("today is named", PolarRoom.value(days: 0) == "today")
check("tomorrow is named", PolarRoom.value(days: 1) == "tomorrow")
check("further out counts days", PolarRoom.value(days: 5) == "5 days")
check("every item wears a chip — only shape here carries one", PolarRoom.chip(item("a", days: 3)) == "Needs you")
check("a missed dispute says Missed", PolarRoom.chip(item("a", days: -1)) == "Missed")
check("an upcoming dispute says Needs you", PolarRoom.chip(item("a", days: 2)) == "Needs you")

print("")
print("Polar — the headline ranking")
check("an overdue window outranks everything",
      PolarRoom.headline(room(items: [item("a", days: -2)]))
        == "Evidence was due 2 days ago")
check("one day overdue reads as yesterday",
      PolarRoom.headline(room(items: [item("a", days: -1)])) == "Evidence was due yesterday")
check("a lone dispute names its window",
      PolarRoom.headline(room(items: [item("a", days: 4)])) == "Evidence due 4 days")
check("several deadlines are counted",
      PolarRoom.headline(room(items: [item("a", days: 1), item("b", days: 4)]))
        == "2 deadlines ahead")
check("with nothing due, MRR leads",
      PolarRoom.headline(room()) == "$482.00/mo recurring")
check("with nothing read at all, the quiet card still says something",
      PolarRoom.headline(room(mrr: nil, activeSubscriptions: nil, asOf: nil)) == "Nothing needs you")
// A genuinely zero MRR (read, and really zero) is a real fact — never
// confused with "never read yet".
check("a read reading with no MRR says so honestly, not as an absence",
      PolarRoom.headline(room(mrr: nil, activeSubscriptions: nil, asOf: t0))
        == "No recurring revenue right now")

print("")
print("Polar — the note line never restates the headline")
check("when a deadline leads, the note carries the revenue figure",
      PolarRoom.note(room(items: [item("a", days: 4)])).contains("482"))
check("when revenue leads, the note carries active subscribers",
      PolarRoom.note(room()).contains("12"))
check("singular subscriber reads naturally",
      PolarRoom.note(room(activeSubscriptions: 1)).contains("1 active subscriber")
        && !PolarRoom.note(room(activeSubscriptions: 1)).contains("subscribers"))
check("zero active subscribers is not stated as a clause",
      !PolarRoom.note(room(activeSubscriptions: 0)).contains("active"))

print("")
print("Polar — coverage and staleness")
check("coverage says nothing when everything drawn is everything there is",
      PolarRoom.coverageNote(room(items: [item("a", days: 1)], total: 1)) == nil)
check("coverage names what's hidden",
      PolarRoom.coverageNote(room(items: [item("a", days: 1)], total: 3))!.contains("2"))
check("a fresh reading needs no apology",
      PolarRoom.staleNote(asOf: t0, now: t0.addingTimeInterval(1800)) == nil)
check("an hour-old reading is dated in hours",
      PolarRoom.staleNote(asOf: t0, now: t0.addingTimeInterval(3 * 3600))!.contains("3h"))
check("a day-old reading says yesterday",
      PolarRoom.staleNote(asOf: t0, now: t0.addingTimeInterval(30 * 3600)) == "Read yesterday")
check("no reading at all has no staleness clause", PolarRoom.staleNote(asOf: nil) == nil)

print("")
print("Polar — isEmpty and readingRead are independent facts")
check("never read and nothing due is genuinely empty", room(mrr: nil, activeSubscriptions: nil, asOf: nil).isEmpty)
check("read-and-zero is NOT empty — it's a real reading",
      !room(mrr: nil, activeSubscriptions: nil, asOf: t0).isEmpty)
check("a due item alone keeps the card alive",
      !room(mrr: nil, activeSubscriptions: nil, asOf: nil, items: [item("a", days: 1)]).isEmpty)

print("")
if failures == 0 {
    print("✓ polar self-test: all assertions passed")
} else {
    print("✗ polar self-test: \(failures) assertion(s) failed")
    exit(1)
}
SWIFT

if ! swiftc -O -o "$TMP/run" "$ROOM" "$SHARED_RUNWAY" "$TMP/main.swift" 2>"$TMP/build.log"; then
  echo "✗ PolarRoom.swift did not compile"
  grep -E 'error:' "$TMP/build.log" | head -20
  exit 1
fi
"$TMP/run"

# --- mutations ----------------------------------------------------------------
echo
echo "mutations (each must be caught)"

WORK="$TMP/work"
mutate() {
  local name="$1" from="$2" to="$3"
  rm -rf "$WORK"; mkdir -p "$WORK"
  cp "$ROOM" "$WORK/PolarRoom.swift"
  MUT_FROM="$from" MUT_TO="$to" python3 - "$WORK/PolarRoom.swift" <<'PY'
import os, sys
path = sys.argv[1]
src = open(path).read()
frm, to = os.environ["MUT_FROM"], os.environ["MUT_TO"]
if frm not in src:
    sys.stderr.write("ANCHOR-MISSING\n"); sys.exit(2)
open(path, "w").write(src.replace(frm, to, 1))
PY
  if [[ $? -ne 0 ]] || ! grep -qF -- "$to" "$WORK/PolarRoom.swift"; then
    echo "  ✗ $name — the mutation did not apply (the shipped source moved)"; exit 1
  fi
  if ! swiftc -O -o "$TMP/mut" "$WORK/PolarRoom.swift" "$SHARED_RUNWAY" "$TMP/main.swift" 2>/dev/null; then
    echo "  ✓ $name (rejected at compile)"; return
  fi
  if "$TMP/mut" > /dev/null 2>&1; then
    echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}

# 1. Overdue no longer pins to the ranking's front — a dispute you already
#    missed would stop leading the card.
mutate "overdue no longer outranks an upcoming deadline in the headline" \
  'if let overdue = room.overdue {' \
  'if let overdue = room.overdue, false {'

# Moved to `scripts/room-runway-selftest.sh` with the code it tests: the
# runway arithmetic is now shared, and this file's drift guard proves this room
# FORWARDS to it rather than carrying a second copy.

# 4. readingRead collapses into mrr != nil — a genuinely zero MRR would then
#    read as "never read yet" rather than as the real, honest zero it is.
mutate "readingRead becomes mrr != nil instead of asOf != nil" \
  'var readingRead: Bool { asOf != nil }' \
  'var readingRead: Bool { mrr != nil }'

echo
echo "✓ polar self-test: assertions and mutations all passed"
