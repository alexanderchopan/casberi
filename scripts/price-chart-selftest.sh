#!/bin/zsh
# Casberi price-chart self-test — the honesty rails on the token/stock price
# surface (2026-08-16):
#
#   Casberi/Casberi/Design/TokenChartView.swift   (TokenChartStyle)
#   Casberi/Casberi/Model/StockChart.swift
#   Casberi/Casberi/Model/TokenChart.swift
#
# WHY A HARNESS. Every failure here renders as a perfectly good-looking chart.
# `xcodebuild` is happy, a screen sweep photographs a plausible curve, and the
# numbers are all real numbers — they are just about something other than what
# the label beside them says:
#
#   · a breathing "live" endpoint over a price read an hour ago (§83 — the Home
#     row was denied this exact mark for overclaiming, and the sheet kept it on
#     a premise that was false)
#   · a 40pt figure and the pill beneath it describing different moves, because
#     one came from the live tick and the other from the last candle
#   · a change that rounds to zero given a direction and a colour
#   · "Site dexscreener.com" under a GeckoTerminal row
#   · a range tap that deletes the chips you tapped
#
# The pure style functions are EXTRACTED (TokenChartView.swift imports SwiftUI
# and Charts, so it cannot be compiled here) — never copied: the extractor pulls
# them out of the shipped source at run time, so a drifted threshold fails.
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on
# failure.
set -euo pipefail
cd "$(dirname "$0")/.."

CHART="Casberi/Casberi/Design/TokenChartView.swift"
STOCK="Casberi/Casberi/Model/StockChart.swift"
MODEL="Casberi/Casberi/Model/TokenChart.swift"
SHEET="Casberi/Casberi/Screens/ThingSheetView.swift"
for f in "$CHART" "$STOCK" "$MODEL" "$SHEET"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# --- drift guards -----------------------------------------------------------

# 1. The curve carries a clock. Without it nothing downstream can say when the
#    number was true, which is the state the whole surface was in until now.
grep -q 'var fetchedAt: Date' "$MODEL" \
  || { echo "✗ TokenChart has no fetchedAt — the price can no longer say when it was read"; exit 1; }

# 2. The breathing endpoint is EARNED. A literal `pulses: true` here is the
#    overclaim reverting, and it looks identical on screen.
grep -q 'pulses: fresh' "$CHART" \
  || { echo "✗ the live endpoint halo is no longer gated on freshness (§83)"; exit 1; }
grep -q 'TokenChartStyle.isFresh(chart.fetchedAt)' "$CHART" \
  || { echo "✗ the freshness test is gone"; exit 1; }

# 3. The read line is UNCONDITIONAL. A freshness line that appears only when
#    something is stale teaches people to read its absence as "current".
grep -q 'readLine(chart)' "$CHART" \
  || { echo "✗ the sheet no longer states when the price was read"; exit 1; }
grep -q 'onChange(of: scenePhase)' "$CHART" \
  || { echo "✗ the chart no longer refetches on foreground — it would go stale in silence"; exit 1; }

# 4. Reduce Motion (prd §299). `design-motion-audit.py` structurally cannot see
#    this one: it reads onAppear-triggered animations and carves out
#    `withAnimation` inside an `async` func, and `replayReveal` is called from
#    `load()` via `.task(id:)`.
grep -q 'guard !reduceMotion else { revealed = true; return }' "$CHART" \
  || { echo "✗ the draw-on reveal no longer honours Reduce Motion (prd §299)"; exit 1; }

# 5. A range tap must not delete its own controls.
grep -q 'private var shown: TokenChart?' "$CHART" \
  || { echo "✗ a range switch no longer stands in with the last curve — the chips vanish mid-fetch"; exit 1; }
grep -q 'awaitingRange' "$CHART" \
  || { echo "✗ the stand-in state is gone; a stale curve would be labelled with the new window"; exit 1; }

# 6. The Site row is gated on whether a CHART drew, never on one source's name.
grep -q 'ThingChart.kind(for: thing) == nil' "$SHEET" \
  || { echo "✗ the Site row is gated by source name again — it leaks dexscreener.com under GeckoTerminal"; exit 1; }

# 7. The chart plays as an Audio Graph.
grep -q 'accessibilityChartDescriptor(PriceChartDescriptor' "$CHART" \
  || { echo "✗ the price curve is silent to VoiceOver again (168 per-mark stops)"; exit 1; }

# 8. The stock delta is measured against the number on screen.
grep -q 'change: (price - first) / first' "$STOCK" \
  || { echo "✗ the stock delta no longer describes the price it is drawn under"; exit 1; }

# --- the price OBJECT (prd §369 amendment) ----------------------------------
OBJ="Casberi/Casberi/Model/PriceObject.swift"
OBJSRC="Casberi/Casberi/Model/PriceObjectSource.swift"
CARD="Casberi/Casberi/Screens/PriceObjectCard.swift"
CONTENT="Casberi/Casberi/Screens/ThingContent.swift"
for f in "$OBJ" "$OBJSRC" "$CARD"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

# The object is actually the hero, for BOTH families. Without this the whole
# thing is invisible while every assertion below still passes — the same way
# eleven money families had no hero for months.
grep -q 'PriceObjectCard(object: priceObject(' "$CHART" \
  || { echo "✗ the chart no longer draws the price object as its hero"; exit 1; }
[[ $(grep -c 'object: PriceObjectSource.identity(' "$CONTENT") -eq 2 ]] \
  || { echo "✗ token and stock no longer BOTH draw the object (they diverged by accident once already)"; exit 1; }

# The title stands down, or the sheet prints the asset's name twice.
grep -q 'ThingChart.kind(for: thing) != nil' "$SHEET" \
  || { echo "✗ the sheet's title no longer stands down for a charted row"; exit 1; }

# The symbol is a STAMPED field. Falling back to splitting the title is
# allowed and documented; making it the only path is not.
grep -q 'thing.authorHandle = token.symbol' "Casberi/Casberi/Model/TokenWatch.swift" \
  || { echo "✗ a watched token no longer stamps its symbol — the object would have to parse prose"; exit 1; }
grep -q 'thing.authorHandle = stock.symbol' "Casberi/Casberi/Model/StocktwitsBridge.swift" \
  || { echo "✗ a watched stock no longer stamps its symbol"; exit 1; }

# The chip label is NOT the persistence key. Collapsing them orphans every
# stored range preference silently — no crash, everyone just quietly back on
# 24h.
grep -q 'var label: String { get }' "$MODEL" \
  || { echo "✗ PriceRange.label is gone — the chip label and the storage key would be one string again"; exit 1; }
grep -q 'UserDefaults.standard.set(range.rawValue, forKey: key)' "$CHART" \
  || { echo "✗ the remembered range no longer persists the RAW value"; exit 1; }
if grep -qE 'Text\(r\.rawValue\)' "$CHART"; then
  echo "✗ the chips render the raw value again (they must read 1D/1W/1M)"; exit 1
fi

# --- extract the pure style functions ---------------------------------------
python3 - "$CHART" > "$TMP/Style.swift" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
out = ["import Foundation\n"]
# TokenChartStyle's pure half — everything that does not touch Color.
for name in ["isFlat", "isFresh", "readLine", "priceText", "changeText"]:
    m = re.search(r"\n    static (?:let|func) " + name + r"\b", src)
    if not m:
        sys.stderr.write("could not extract %s\n" % name)
        sys.exit(1)
    start = m.start() + 1
    # brace-match from the first { after the signature, or take the line for a `let`
    head = src[start:start + 400]
    if head.lstrip().startswith("static let"):
        end = src.index("\n", start)
        out.append(src[start:end + 1])
        continue
    i = src.index("{", start)
    depth, j = 0, i
    while True:
        if src[j] == "{": depth += 1
        elif src[j] == "}":
            depth -= 1
            if depth == 0: break
        j += 1
    out.append(src[start:j + 1] + "\n")
# freshWindow is a `let` the functions above read.
m = re.search(r"\n    static let freshWindow[^\n]*\n", src)
if not m:
    sys.stderr.write("could not extract freshWindow\n"); sys.exit(1)
body = "".join(out[1:]) + m.group(0)
sys.stdout.write("import Foundation\n\nenum TokenChartStyle {\n" + body + "}\n")
PY

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if !ok { print("  ✗ \(what)"); failures += 1 }
}

let now = Date(timeIntervalSince1970: 1_754_000_000)

// MARK: freshness — the halo's own gate

check(TokenChartStyle.isFresh(now.addingTimeInterval(-5), now: now),
      "a read five seconds ago is fresh")
check(TokenChartStyle.isFresh(now.addingTimeInterval(-119), now: now),
      "just inside the window is fresh")
check(!TokenChartStyle.isFresh(now.addingTimeInterval(-121), now: now),
      "just outside the window is NOT fresh")
// The case the whole rail exists for: the sheet left open.
check(!TokenChartStyle.isFresh(now.addingTimeInterval(-3600), now: now),
      "an hour-old price never wears the live mark")

// MARK: the read line — always says something

check(TokenChartStyle.readLine(now.addingTimeInterval(-5), now: now)
        .contains("just now"),
      "a moments-old read says so plainly")
check(!TokenChartStyle.readLine(now.addingTimeInterval(-7200), now: now)
        .contains("just now"),
      "a two-hour-old read does not claim to be recent")
check(!TokenChartStyle.readLine(now.addingTimeInterval(-7200), now: now).isEmpty,
      "the line is never empty — an absent line reads as 'current'")

// MARK: flat — a change that rounds away has no direction (§83)

check(TokenChartStyle.isFlat(0.0004), "0.04% is flat")
check(!TokenChartStyle.isFlat(0.0006), "0.06% is a real move")
check(TokenChartStyle.changeText(0.0004) == "0.0%",
      "a flat change prints without a sign")
check(TokenChartStyle.changeText(0.042).hasPrefix("+"),
      "a real gain keeps its sign")

// MARK: price precision by magnitude

check(TokenChartStyle.priceText(12.3456) == "$12.35", "dollars get cents")
check(TokenChartStyle.priceText(0.031234) == "$0.0312", "sub-dollar gets four places")
check(TokenChartStyle.priceText(0.00000123) == "$0.00000123",
      "a micro-cap keeps eight, rather than rounding to $0.00")

// MARK: the price object's sentence — what it may and may not claim

// A steady climb that ENDS at its high.
let rising = (1...20).map { 50.0 + Double($0) }
// A run that gave most of it back.
let retrace = [50.0, 56, 62, 68, 74, 80, 76, 70, 64, 58, 55, 54, 53, 52.5]
// Nothing happened.
let quiet = (1...20).map { _ in 62.0 } .enumerated().map { $0.offset % 2 == 0 ? 62.0 : 62.2 }
// Ends where it started, having DIPPED and recovered — not a run that gave
// itself back, which is a retrace and outranks this by design.
let roundTrip = [60.0, 56, 53, 54, 55, 57, 58, 59.99]

do {
    // 1. The extreme, and ONLY when the last close really is the extreme.
    let high = PriceCommentary.shape(closes: rising, window: "1W")
    check(high?.contains("highest") == true, "a curve ending at its peak says so")
    // The peak three closes ago is a DIFFERENT sentence, and we don't make it.
    let pastPeak = rising + [69.0, 68, 67]
    check(PriceCommentary.shape(closes: pastPeak, window: "1W")?
            .contains("highest") != true,
          "a peak that has passed is not called 'its highest'")

    // 2. The retrace outranks the extreme — it is the shape the figure hides.
    let gave = PriceCommentary.shape(closes: retrace, window: "1D")
    check(gave?.contains("gave most of it back") == true,
          "a run that retraced says so")

    // 3. Quiet is a real reading.
    check(PriceCommentary.shape(closes: quiet, window: "1W")?
            .contains("Quiet") == true,
          "a week inside a percent reads as quiet")
    // …and a curve that moved is never called quiet.
    check(PriceCommentary.shape(closes: rising, window: "1W")?
            .contains("Quiet") != true,
          "a curve that climbed 40% is not quiet")

    // 4. Round trip, last of the four.
    check(PriceCommentary.shape(closes: roundTrip, window: "1M")?
            .contains("Back where it started") == true,
          "a dip that recovered says it is back where it started")
    // And a RUN that gave itself back is the retrace sentence, not this one —
    // the stronger reading wins, which is the ranking working.
    check(PriceCommentary.shape(closes: [60.0, 64, 68, 71, 69, 65, 62, 60.01],
                                window: "1M")?.contains("gave most of it back") == true,
          "a run that round-tripped is reported as the retrace, not the round trip")
    // The quiet band must beat the extremes: in a window that moved a third of
    // a percent, the last close is the high about half the time by coincidence.
    check(PriceCommentary.shape(closes: quiet, window: "1W")?
            .contains("highest") != true,
          "a flat week is never called 'its highest' on a coincidence")

    // 5. THE COARSE REFUSAL. Five back-solved points cannot support a claim
    //    about shape, and the whole danger of this type is fluency.
    check(PriceCommentary.shape(closes: [50, 52, 51, 53, 54], window: "1D") == nil,
          "too few closes makes no claim at all")

    // 6. The watch anchor — the one reading no market site can show.
    let anchored = PriceCommentary.anchor(
        closes: rising,
        watched: (price: 50.0, date: Date(timeIntervalSince1970: 1_750_000_000)))
    check(anchored?.contains("You watched at") == true, "the anchor clause fires")
    check(anchored?.contains("up") == true, "and names its direction")
    // A move that rounds away is not worth a clause.
    check(PriceCommentary.anchor(closes: [50.0, 50.0],
                                 watched: (price: 50.0, date: .now)) == nil,
          "a flat move since watching says nothing")
    // A nonsense anchor is refused rather than divided by.
    check(PriceCommentary.anchor(closes: rising,
                                 watched: (price: 0, date: .now)) == nil,
          "a zero watch price is refused, never divided by")

    // 7. The percent formatter: no direction for a change that rounds away.
    check(PriceObject.percent(0.0004) == "0.0%", "a flat change prints no sign")
    check(PriceObject.percent(0.042) == "+4.2%", "a gain keeps its sign")
    check(PriceObject.percent(-0.018) == "−1.8%", "a loss uses the minus GLYPH")

    // 8. The two price ramps must agree, or the object and the curve beneath it
    //    print one number two ways.
    for value in [0.00000123, 0.0312, 12.3456, 1840.0] {
        check(PriceCommentary.money(value) == TokenChartStyle.priceText(value),
              "the object and the chart format \(value) identically")
    }

    // 9. Spoken: the window rides WITH the move, and freshness is the value.
    let object = PriceObject(
        subject: .asset("AERO"), name: "Aerodrome", symbol: "$AERO",
        price: "$0.9184",
        move: PriceObject.Move(change: 0.042, window: "1D"),
        freshness: .live, sentence: "Its highest across this 1D window.")
    check(object.spokenLabel.contains("over 1D"),
          "a percentage is never spoken without its window")
    check(object.spokenValue.contains("just now"),
          "freshness is the spoken VALUE — the state slot")
    let flat = PriceObject(
        subject: .none, name: nil, symbol: "$X", price: "$1.00",
        move: PriceObject.Move(change: 0.0001, window: "1W"),
        freshness: .live, sentence: nil)
    check(flat.spokenLabel.contains("unchanged"),
          "a flat move is spoken as unchanged, not as plus nothing")
}

if failures > 0 {
    print("\(failures) assertion(s) failed")
    exit(1)
}
print("all assertions passed")
SWIFT

cp "$OBJ" "$TMP/PriceObject.swift"
swiftc -O -o "$TMP/run" "$TMP/Style.swift" "$TMP/PriceObject.swift" "$TMP/main.swift" 2>&1 | grep -E "error:" && exit 1
"$TMP/run" || exit 1

# --- mutations (each must be caught) ----------------------------------------
echo
echo "mutations (each must be caught):"
mutate() {
  local name="$1" frm="$2" to="$3"
  cp "$TMP/Style.swift" "$TMP/Mut.swift"
  FRM="$frm" TO="$to" python3 - "$TMP/Mut.swift" <<'PY'
import os, sys
path = sys.argv[1]
src = open(path).read()
frm, to = os.environ["FRM"], os.environ["TO"]
if frm not in src: sys.exit(1)
open(path, "w").write(src.replace(frm, to, 1))
PY
  if [[ $? -ne 0 ]] || ! grep -qF -- "$to" "$TMP/Mut.swift"; then
    echo "  ✗ $name — the mutation did not apply (the shipped source moved)"; exit 1
  fi
  if ! swiftc -O -o "$TMP/mut" "$TMP/Mut.swift" "$TMP/PriceObject.swift" "$TMP/main.swift" 2>/dev/null; then
    echo "  ✓ $name (rejected at compile)"; return
  fi
  if "$TMP/mut" > /dev/null 2>&1; then
    echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}

# The window widened to an hour: a price from breakfast wears the live halo.
mutate "the freshness window is widened past a glance" \
  "static let freshWindow: TimeInterval = 120" \
  "static let freshWindow: TimeInterval = 3600"

# Freshness inverted — the halo appears exactly when the read is old.
mutate "the freshness test is inverted" \
  "now.timeIntervalSince(fetchedAt) < freshWindow" \
  "now.timeIntervalSince(fetchedAt) > freshWindow"

# Everything claims to be current.
mutate "every read claims to be just now" \
  'if age < 60 { return String(localized: "read just now") }' \
  'return String(localized: "read just now")'

# The flat rule dropped: "-0.0%" in red, a loss the number itself denies.
mutate "a change that rounds to zero is given a direction" \
  "abs(c * 100) < 0.05" \
  "abs(c * 100) < 0"

# A micro-cap rounded to two places prints $0.00 for a real holding.
mutate "sub-cent prices lose their precision" \
  'return String(format: "$%.8f", p)' \
  'return String(format: "$%.2f", p)'


# --- the object's own mutations ---------------------------------------------
# Same contract, mutating PriceObject.swift instead of the extracted style.
mutateObj() {
  local name="$1" frm="$2" to="$3"
  cp "$OBJ" "$TMP/ObjMut.swift"
  FRM="$frm" TO="$to" python3 - "$TMP/ObjMut.swift" <<'PY2'
import os, sys
path = sys.argv[1]
src = open(path).read()
frm, to = os.environ["FRM"], os.environ["TO"]
if frm not in src: sys.exit(1)
open(path, "w").write(src.replace(frm, to, 1))
PY2
  if [[ $? -ne 0 ]] || ! grep -qF -- "$to" "$TMP/ObjMut.swift"; then
    echo "  ✗ $name — the mutation did not apply (the shipped source moved)"; exit 1
  fi
  if ! swiftc -O -o "$TMP/omut" "$TMP/Style.swift" "$TMP/ObjMut.swift" "$TMP/main.swift" 2>/dev/null; then
    echo "  ✓ $name (rejected at compile)"; return
  fi
  if "$TMP/omut" > /dev/null 2>&1; then
    echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}

# The ranking bug this pass actually shipped and the harness caught: with the
# extremes checked first, a flat week whose last close happens to be its high
# is announced as "Its highest". True, and materially misleading.
mutateObj "the extremes are ranked above the quiet band again" \
  'if (high - low) / low < quietBand {
            return String(localized: "Quiet — it hasn'"'"'t moved more than a percent across this \(window) window.")
        }' \
  'if false {
            return String(localized: "Quiet")
        }'

# "Its highest" said about a peak that has already passed.
mutateObj "an extreme no longer has to be the LAST close" \
  'if last == high, high > low {' \
  'if high > low, high > low {'

# The coarse floor dropped: five back-solved points get a claim about shape.
mutateObj "the minimum-closes floor is dropped" \
  'static let minimumCloses = 8' \
  'static let minimumCloses = 2'

# A zero watch price divided by — a confident infinity on the one clause that
# is about the person's own record.
mutateObj "a nonsense watch anchor is divided by instead of refused" \
  'guard let watched, watched.price > 0, let last = closes.last, last > 0' \
  'guard let watched, let last = closes.last, last > 0'

# The window dropped from the spoken move: a percentage about nothing.
mutateObj "the spoken percentage loses its window" \
  'String(localized: "\(PriceObject.percent(move.change)) over \(move.window)")' \
  'String(localized: "\(PriceObject.percent(move.change))")'

# The two price ramps drift, so the object and its own curve print one number
# two different ways.
mutateObj "the object's price ramp drifts from the chart's" \
  'if p >= 0.01 { return String(format: "$%.4f", p) }' \
  'if p >= 0.01 { return String(format: "$%.3f", p) }'

echo
echo "price-chart-selftest: OK"
