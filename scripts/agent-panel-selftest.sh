#!/bin/zsh
# Casberi agent-panel self-test — what is left of the agent's instrument panel
# (prd §334) after the chip peek went in §836 and took every per-room figure
# and the ranking between them with it:
#
#   Casberi/Casberi/Model/AgentPanel.swift
#     — Figure.isEmpty   (the dial's floor: a rhythm, not a few dots)
#     — compactUSD       (the one money formatter, forwarding to MoneyFormat)
#
# `AgentPanel.swift` is Foundation-only BY DESIGN, so this compiles it WHOLE
# and UNMODIFIED with no stubs. There is no extraction step that can drift.
#
# Pure, local, deterministic — no network, no simulator, no corpus.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="Casberi/Casberi/Model/AgentPanel.swift"
# `compactUSD`'s table moved to Shared/ on 2026-08-14 so the wallet WIDGET,
# which runs in another process, draws the identical figure — `AgentPanel`
# forwards to it. Foundation-only, so it compiles beside the file under test
# with no stub; without it the whole harness stops compiling, which is exactly
# the coupling being made visible rather than hidden.
MONEY="Casberi/Shared/MoneyFormat.swift"
GRID="Casberi/Casberi/Screens/AgentPanelGrid.swift"
for f in "$SRC" "$MONEY" "$GRID"; do
  [[ -f "$f" ]] || { print -u2 "missing $f"; exit 1; }
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if ok { print("  ✓ \(what)") } else { print("  ✗ \(what)"); failures += 1 }
}

func marks(_ n: Int) -> [AgentPanel.DialMark] {
    (0..<n).map { AgentPanel.DialMark(hour: Double($0 % 24), recency: 0.5, source: "s\($0)") }
}

// ─────────────────── which readings are too thin to draw ───────────────────
print("isEmpty")
let floor = AgentPanel.Figure.dialFloor
check(AgentPanel.Figure.dial([]).isEmpty, "an empty dial draws nothing")
check(AgentPanel.Figure.dial(marks(floor - 1)).isEmpty,
      "one mark short of the floor is dots on a circle, not a rhythm")
check(!AgentPanel.Figure.dial(marks(floor)).isEmpty, "the floor itself draws")
// The composer (`KeptAskComposers.dialLine`) declines on this same constant,
// so a floor that drifts low draws a dial the ladder never meant to emit.
check(floor >= 12, "the dial floor has not drifted below a rhythm's worth of marks")

print("money")
// §341, reported live: a watched wallet holding $7.26M rendered "$7258k" on the
// hero while the Wallet room three taps away said "$7.0M". Two surfaces, one
// number, two answers — and the panel is a WINDOW onto that room.
check(AgentPanel.compactUSD(7_258_000) == "$7.3M", "millions render as millions")
check(AgentPanel.compactUSD(7_000_000) == "$7.0M", "…matching the Wallet room's own tiering")
check(AgentPanel.compactUSD(2_400_000_000) == "$2.4B", "billions have a tier too")
check(AgentPanel.compactUSD(12_480) == "$12K", "tens of thousands stay whole")
check(AgentPanel.compactUSD(1_500) == "$1.5K", "thousands keep one decimal")
check(AgentPanel.compactUSD(640) == "$640", "under a thousand is plain")
// A negative must not lose its tier — `abs` picks the tier, the sign rides the
// value, and getting that backwards prints "$-7258065" for a drawdown.
check(AgentPanel.compactUSD(-7_258_000) == "$-7.3M", "a negative keeps its tier")

print("")
if failures > 0 { print("\(failures) failure(s)"); exit(1) }
print("agent-panel self-test passed")
SWIFT

print "AgentPanel self-test — the shipped file, compiled whole"
# `-Onone`, not `-O`: 97% of a pure-logic harness's wall time is the optimizer,
# and it buys nothing an assertion can see. NOT a blanket rule — `-O` can change
# a harness's OBSERVABLE behaviour (a trapping one prints NOTHING under `-O`) —
# so this file was proven equivalent run-for-run by
# `scripts/support/harness-opt-probe.sh` before the swap (2026-09-05, 2.3x faster).
# Re-probe before trusting it again after adding mutations.
xcrun swiftc -Onone -o "$WORK/run" "$SRC" "$MONEY" "$WORK/main.swift" 2>&1 | grep -v "^$" || true
[[ -x "$WORK/run" ]] || { print -u2 "✗ compile failed"; exit 1; }
"$WORK/run" || exit 1

print ""
print "Mutations — each must FAIL the suite"
mutate() {
  local name="$1" from="$2" to="$3"
  local dir="$WORK/mut"; rm -rf "$dir"; mkdir -p "$dir"
  python3 - "$SRC" "$dir/AgentPanel.swift" "$from" "$to" <<'PY'
import sys
src, dst, a, b = sys.argv[1:5]
s = open(src).read()
if a not in s:
    sys.stderr.write("MUTATION ANCHOR MISSING: %r\n" % a); sys.exit(3)
open(dst, "w").write(s.replace(a, b, 1))
PY
  if [[ $? -eq 3 ]]; then print "  ✗ $name — anchor missing (harness is stale)"; return 1; fi
  if xcrun swiftc -Onone -o "$dir/run" "$dir/AgentPanel.swift" "$MONEY" "$WORK/main.swift" >/dev/null 2>&1 \
       && "$dir/run" >/dev/null 2>&1; then
    print "  ✗ $name — SURVIVED"; return 1
  fi
  print "  ✓ $name caught"
}

rc=0
mutate "a dial of a few marks draws" \
  'case .dial(let m):    return m.count < Self.dialFloor' \
  'case .dial(let m):    return m.count < 1' || rc=1
mutate "the dial floor drifts low" \
  'static let dialFloor = 12' \
  'static let dialFloor = 3' || rc=1
mutate "the panel grows its own money table back" \
  'static func compactUSD(_ usd: Double) -> String { MoneyFormat.compactUSD(usd) }' \
  'static func compactUSD(_ usd: Double) -> String { "$\(Int(usd / 1000))k" }' || rc=1

print ""
print "Drift guards"
guard_has() {
  local what="$1" file="$2" pat="$3"
  # A here-string, NOT a pipe into `grep -q`: under `pipefail` a matching
  # `grep -q` exits early, `sed` dies on SIGPIPE, and the PIPELINE reports
  # failure — so a guard reads as broken exactly when it succeeds. It is
  # size-dependent, which is what made it vicious in §332's harness.
  local body; body="$(sed 's|//.*||' "$file")"
  if grep -qE "$pat" <<< "$body"; then print "  ✓ $what"
  else print "  ✗ $what"; return 1; fi
}

# The chip peek is gone (prd §836), and nothing may quietly rebuild a per-room
# figure chain on the model it read: those cases were deleted with it.
src_nc="$(sed 's|//.*||' "$SRC")"
revived=0
for gone in 'case treemap' 'case bars' 'case rail' 'case pulse' 'case curve' \
            'case wall' 'case flow' 'case runway' 'case worth' 'func rank'; do
  if grep -qE "$gone\b" <<< "$src_nc"; then
    print "  ✗ \`$gone\` is back on AgentPanel — the peek that drew it was deleted (§836)"
    revived=1; rc=1
  fi
done
(( revived )) || print "  ✓ no per-room figure or ranking survives the peek"
# §334's tripwire: the moment a figure can be words, the panel is a list again.
if sed 's|//.*||' "$SRC" | grep -qE 'case text\('; then
  print "  ✗ a Figure case may never be text (§334's tripwire)"; rc=1
else
  print "  ✓ no text figure — a figure only ever draws"
fi
# The entrance must honour Reduce Motion.
guard_has "the dial's entrance honours Reduce Motion" "$GRID" 'reduceMotion \? nil' || rc=1

print ""
print "Glyph coverage — every catalog offer has a real mark"
# Every source tile draws BridgeGlyph.symbol(for: card.source), and that
# table's `default:` returns "app" — the generic grid glyph the user singled
# out as reading like nothing. This proves EVERY connectable catalog offer
# has its own case, so a new offer can't silently wear the generic glyph on
# the panel just because nobody remembered to add one (prd §"Agent panel
# tiles" item 1, 2026-08-07). `KNOWN_EXEMPT` is a conscious ruling, not a
# snooze — empty by design; an entry needs a reason comment beside it.
GLYPH="Casberi/Casberi/Design/KindGlyph.swift"
CATALOG="Casberi/Casberi/Model/BridgeCatalog.swift"
glyph_coverage() {
  local catalog_file="$1" glyph_file="$2"
  python3 - "$catalog_file" "$glyph_file" <<'PY'
import re, sys
catalog_path, glyph_path = sys.argv[1], sys.argv[2]
KNOWN_EXEMPT = set()

catalog = open(catalog_path).read()
# Comments stripped FIRST — this file's own doc comment on the offers array
# reads `Offer(name: "…"` as prose describing this exact check, and an
# unstripped regex would "discover" a phantom offer named "…" (caught
# exactly this way on the first run of this check).
catalog_code = re.sub(r'//.*', '', catalog)
offers = set(m.lower() for m in re.findall(r'Offer\(name:\s*"([^"]+)"', catalog_code))
if not offers:
    print("  ✗ extracted zero offers — the harness is stale"); sys.exit(1)

glyph = open(glyph_path).read()
start = glyph.index('static func symbol(for name: String) -> String {')
end = glyph.index('\n    }\n}', start)
body = glyph[start:end]
cases = set()
for c in re.findall(r'case ((?:"[^"]+",?\s*)+):', body):
    for m in re.findall(r'"([^"]+)"', c):
        cases.add(m.strip().lower())

missing = sorted((offers - cases) - KNOWN_EXEMPT)
if missing:
    print(f"  ✗ {len(missing)} offer(s) with no glyph case: {', '.join(missing)}")
    sys.exit(1)
print(f"  ✓ all {len(offers)} catalog offers resolve to a real glyph")
PY
}
if glyph_coverage "$CATALOG" "$GLYPH"; then :; else rc=1; fi

# Self-test the check itself: inject a fake offer name absent from KindGlyph
# and prove the coverage check actually fails on it — a check that can't
# fail proves nothing.
FAKE_CATALOG="$WORK/fake-catalog.swift"
{ cat "$CATALOG"; echo '        Offer(name: "ZzzNotARealOfferXyz", tagline: "t", group: "g", connectable: true,'; } > "$FAKE_CATALOG"
python3 - "$FAKE_CATALOG" >/dev/null 2>&1 <<'PY'
import sys
# quick sanity the fake line actually landed
assert 'ZzzNotARealOfferXyz' in open(sys.argv[1]).read()
PY
if glyph_coverage "$FAKE_CATALOG" "$GLYPH" >/dev/null 2>&1; then
  print "  ✗ glyph coverage self-test — a fake offer with no case SURVIVED"; rc=1
else
  print "  ✓ glyph coverage self-test — a fake unmapped offer is caught"
fi

print ""
if [[ $rc -ne 0 ]]; then print "✗ agent-panel self-test FAILED"; exit 1; fi
print "✓ agent-panel self-test passed"
