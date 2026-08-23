#!/bin/zsh
# Casberi figure-voice self-test — the SHIPPED sentences a DRAWING says out
# loud (2026-08-23, prd §299):
#
#   Casberi/Shared/FigureVoice.swift
#     — heatmap       (a calendar grid of daily counts)
#     — runway        (dots on a time rail, and how many are late)
#     — ranking       (a board, a treemap, a source mix)
#     — distribution  (a split bar's shares)
#     — trend         (a curve whose units the drawing does not know)
#
# That file is Foundation-only BY DESIGN, so it is compiled WHOLE AND
# UNMODIFIED here — no extraction, no copy. Every assertion below is about the
# bytes the app runs.
#
# WHY A HARNESS, and it is a stronger reason than for any other reading in this
# app. A wrong number on a card is checkable by the person looking at the card.
# A wrong number in an accessibility label is heard by somebody who by
# definition CANNOT see the drawing it claims to describe — so there is no
# second opinion anywhere in the loop. Every failure here is also invisible to
# every other check in the repo: the build is green, the screen is pixel-
# identical, the screen sweep photographs the same card, and `verify.sh` has
# nothing to say. The only witness is a listener who has no way to know.
#
# The failures this catches, each of which renders perfectly:
#
#   • a heatmap that says how MUCH and not over how many DAYS — 300 things on
#     four days and 300 across three hundred are then the same sentence, which
#     is precisely the reading the grid exists to give;
#   • a peak count with no date, a number floating free of the calendar it
#     claims to describe;
#   • an empty window described as though it held something;
#   • A RUNWAY THAT DOES NOT SAY HOW MANY ARE LATE. This is the load-bearing
#     one: `GenRunway` and the widget's `HeroRunway` both colour a late dot and
#     say nothing else about it, and on iOS there is no tooltip — so lateness
#     was carried by hue and by nothing else, the one place the 2026-07-16
#     colour law was genuinely broken rather than merely unenforced;
#   • "next" chosen from every dot rather than the ones still ahead, which
#     names a date in the past as the thing coming up;
#   • a ranked figure that drops its folded tail — a chart that silently
#     truncates looks exactly like a chart with nothing to truncate (§307);
#   • a share computed against the wrong denominator;
#   • a move that rounds away being called "up", which reintroduces the exact
#     claim `TokenChartStyle.isFlat` refuses to make in ink and in sign.
#
# WHAT THIS CANNOT PROVE, stated rather than implied: that the sentence is
# ATTACHED to the drawing. A composer with no caller is a perfect, silent
# figure. `scripts/accessibility-audit.py` check 4 is what holds the wiring;
# these two are a pair and neither is sufficient alone.
#
# Dates are asserted by SUBSTRING, never by their formatted month name — the
# formatter is locale-dependent and pinning "Nov" here would make this harness
# fail in Madrid while the app was working correctly.
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on
# failure.
set -euo pipefail
cd "$(dirname "$0")/.."

VOICE="Casberi/Shared/FigureVoice.swift"
[[ -f "$VOICE" ]] || { echo "✗ missing $VOICE"; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ name: String, _ ok: Bool) {
    if ok { print("  ok  \(name)") }
    else { print("  ✗   \(name)"); failures += 1 }
}

// A fixed instant so nothing here depends on when it is run.
let t0 = Date(timeIntervalSince1970: 1_700_000_000)
func day(_ n: Int) -> Date { t0.addingTimeInterval(Double(n) * 86_400) }

// --- heatmap ----------------------------------------------------------------
let full = FigureVoice.heatmap(total: 347, activeDays: 210, spanDays: 371,
                               busiest: 9, busiestDate: t0)
check("heatmap states the total", full.contains("347"))
// THE discriminating one: a spread must be named, or the figure's whole
// subject (consistency over time) is missing from its own description.
check("heatmap states the active days", full.contains("210"))
check("heatmap states the span", full.contains("371"))
check("heatmap names the peak count", full.contains("9"))

// One lit day must not be described as "1 of N days" — the plural branch.
let single = FigureVoice.heatmap(total: 4, activeDays: 1, spanDays: 371,
                                 busiest: 4, busiestDate: t0)
check("a single active day gets its own clause", single.contains("one day"))
check("...and does not print the span", !single.contains("371"))

// A peak with no date is a number floating free of the calendar.
let undated = FigureVoice.heatmap(total: 30, activeDays: 10, spanDays: 90,
                                  busiest: 7, busiestDate: nil)
check("an undated peak is omitted, not guessed", !undated.contains("7"))
check("...while the rest still speaks", undated.contains("30") && undated.contains("10"))

let empty = FigureVoice.heatmap(total: 0, activeDays: 0, spanDays: 371,
                                busiest: 0, busiestDate: nil)
check("an empty window says so", empty.lowercased().contains("nothing"))
check("...and never prints its span as content", !empty.contains("371"))

// --- runway -----------------------------------------------------------------
// Two late, one still ahead.
let rw = FigureVoice.runway(dates: [day(-3), day(-2), day(5)], now: t0, overdue: 2)
check("runway states how many dots", rw.contains("3"))
// THE load-bearing assertion: lateness is drawn in hue alone.
check("runway states how many are overdue", rw.contains("2 overdue"))
check("runway names the next one still ahead", rw.contains("Next"))

let onLate = FigureVoice.runway(dates: [day(-1), day(4)], now: t0, overdue: 1)
check("one overdue reads as a word, not a digit", onLate.contains("One overdue"))

// Everything in the past: there is no "next", and inventing one would name a
// date that has already gone by as the thing coming up.
let allPast = FigureVoice.runway(dates: [day(-9), day(-2)], now: t0, overdue: 2)
check("nothing ahead means no next", !allPast.contains("Next"))

let none = FigureVoice.runway(dates: [], now: t0, overdue: 0)
check("an empty rail says so", none.lowercased().contains("nothing"))

let clean = FigureVoice.runway(dates: [day(2), day(6)], now: t0, overdue: 0)
check("no overdue clause when nothing is late", !clean.lowercased().contains("overdue"))

// --- ranking ----------------------------------------------------------------
let rows = [FigureVoice.Row(label: "Swift", detail: "23 posts"),
            FigureVoice.Row(label: "Apple", detail: "18 posts"),
            FigureVoice.Row(label: "Rust",  detail: "4 posts")]
let rank = FigureVoice.ranking(rows: rows, shown: 6)
check("ranking names the leader", rank.contains("Swift") && rank.contains("23 posts"))
check("ranking names the runner-up", rank.contains("Apple"))
// A folded tail must be admitted: silent truncation looks like nothing to
// truncate. `shown` is 6 and two were named, so four remain.
check("ranking admits the folded tail", rank.contains("4 more"))
// Discriminating: the tail counts what was DRAWN, not what was passed. With
// shown == rows.count this must be one, not three.
let three = FigureVoice.ranking(rows: rows, shown: 3)
check("the tail counts what was drawn", three.contains("one more"))
let pair = FigureVoice.ranking(rows: Array(rows.prefix(2)), shown: 2)
check("no tail clause when nothing was folded", !pair.contains("more"))
check("an empty board says so", FigureVoice.ranking(rows: []).lowercased().contains("nothing"))
// A detail-less row states RANK and no number — what §213 requires of the
// widget cells that are forbidden to print a count. Discriminating both ways:
// the names must survive AND no stray punctuation may stand in for the number.
let bare = FigureVoice.ranking(rows: [FigureVoice.Row(label: "Photos", detail: ""),
                                      FigureVoice.Row(label: "Mail", detail: "")], shown: 2)
check("a countless row still names its leader", bare.contains("Photos leads."))
check("...and its runner-up", bare.contains("Then Mail."))
check("...with no orphaned comma where a number would be", !bare.contains(", ."))

// --- distribution -----------------------------------------------------------
let seg = [FigureVoice.Row(label: "Bullish", detail: ""),
           FigureVoice.Row(label: "Bearish", detail: "")]
let dist = FigureVoice.distribution(segments: seg, counts: [3, 1])
check("distribution names each segment", dist.contains("Bullish") && dist.contains("Bearish"))
// The share, against the TOTAL — the one thing the legend beneath does not say.
check("distribution states shares of the whole", dist.contains("75") && dist.contains("25"))
check("mismatched counts refuse rather than crash",
      FigureVoice.distribution(segments: seg, counts: [1]).lowercased().contains("nothing"))
check("an all-zero split refuses",
      FigureVoice.distribution(segments: seg, counts: [0, 0]).lowercased().contains("nothing"))

// --- trend ------------------------------------------------------------------
check("a rise carries its size",
      FigureVoice.trend(direction: .of(change: 0.042), move: "+4.2%").contains("4.2%"))
check("a rise says up", FigureVoice.trend(direction: .of(change: 0.042), move: nil).contains("up"))
check("a fall says down", FigureVoice.trend(direction: .of(change: -0.042), move: nil).contains("down"))
// The flat law: a move that rounds away has NO direction, in ink, in sign, and
// here. Asserting the absence of both words is what makes this discriminating.
let flat = FigureVoice.trend(direction: .of(change: 0.00001), move: "0.0%")
check("a rounded-away move is flat", flat.lowercased().contains("flat"))
check("...and claims no direction",
      !flat.lowercased().contains(" up") && !flat.lowercased().contains("down"))
check("flat is decided by size, not by sign",
      FigureVoice.Direction.of(change: -0.00001) == .flat)

print(failures == 0 ? "\nAll assertions passed." : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
SWIFT

if ! swiftc -O -o "$TMP/run" "$VOICE" "$TMP/main.swift" 2>"$TMP/build.log"; then
  echo "✗ the shipped FigureVoice.swift did not compile against the harness"
  grep -E 'error:' "$TMP/build.log" | head -20
  exit 1
fi
"$TMP/run"

# --- mutations --------------------------------------------------------------
# A check that cannot fail proves nothing. Each mutation is a plausible
# "simplification" of the shipped source, and each must break the run.
echo
echo "mutations (each must be caught)"

WORK="$TMP/work"
mutate() {
  local name="$1" from="$2" to="$3"
  rm -rf "$WORK"; mkdir -p "$WORK"
  cp "$VOICE" "$WORK/FigureVoice.swift"
  MUT_FROM="$from" MUT_TO="$to" python3 - "$WORK/FigureVoice.swift" <<'PY'
import os, sys
path = sys.argv[1]
src = open(path).read()
frm, to = os.environ["MUT_FROM"], os.environ["MUT_TO"]
if frm not in src:
    sys.stderr.write("ANCHOR-MISSING\n"); sys.exit(2)
open(path, "w").write(src.replace(frm, to, 1))
PY
  if [[ $? -ne 0 ]] || ! grep -qF -- "$to" "$WORK/FigureVoice.swift"; then
    echo "  ✗ $name — the mutation did not apply (the shipped source moved)"; exit 1
  fi
  if ! swiftc -O -o "$TMP/mut" "$WORK/FigureVoice.swift" "$TMP/main.swift" 2>/dev/null; then
    echo "  ✓ $name (rejected at compile)"; return
  fi
  if "$TMP/mut" > /dev/null 2>&1; then
    echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}

# 1. The spread dropped — the grid's whole subject missing from its sentence.
mutate "heatmap stops naming the active days" \
  'String(localized: "\(total) across \(activeDays) days of \(spanDays).")' \
  'String(localized: "\(total) in this window.")'

# 2. A peak count with no date printed anyway.
mutate "heatmap names an undated peak" \
  'if busiest > 0, let date = busiestDate {' \
  'if busiest > 0, let date = Optional(busiestDate ?? Date()) {'

# 3. An empty window described as content.
mutate "heatmap describes an empty window" \
  'guard total > 0, spanDays > 0 else {' \
  'guard spanDays < 0 else {'

# 4. THE ONE: lateness spoken nowhere, so it is hue and hue alone.
mutate "runway stops saying how many are overdue" \
  'if overdue == 1 {' \
  'if overdue == -1 {'

# 5. "Next" taken from every dot, so a past date is announced as upcoming.
mutate "runway picks next from dots already gone" \
  'if let next = dates.filter({ $0 > now }).min() {' \
  'if let next = dates.min() {'

# 6. The folded tail dropped — silent truncation (§307).
mutate "ranking drops its folded tail" \
  'let rest = drawn - min(2, rows.count)' \
  'let rest = 0'

# 7. The tail counted off what was PASSED rather than what was DRAWN.
mutate "ranking counts the tail off the wrong set" \
  'let drawn = shown ?? rows.count' \
  'let drawn = rows.count'

# 8. The share taken against the segment rather than the whole.
mutate "distribution divides by the wrong denominator" \
  'let pct = Int((Double(count) / Double(total) * 100).rounded())' \
  'let pct = Int((Double(count) / Double(max(count, 1)) * 100).rounded())'

# 9. The flat law removed — a rounded-away move claims a direction.
mutate "a rounded-away move claims a direction" \
  'if abs(change) < flatBelow { return .flat }' \
  'if abs(change) < -1 { return .flat }'

echo
echo "✓ figure-voice self-test: assertions and mutations all passed"
