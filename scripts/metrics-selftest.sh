#!/bin/zsh
# Casberi MetricKit self-test — verifies the SHIPPED logic that turns a
# MetricKit payload into the lines a person reads (2026-09-05):
#
#   Casberi/Casberi/Model/AppMetricsDigest.swift
#     — quantileBucketEnd   (which bucket a launch/hang time is reported as)
#     — histogramLine       (the rendered summary, and its empty case)
#     — frames              (the attributed thread's stack, leaf first)
#
# WHY A HARNESS AND NOT A LIVE PROBE, and this is the strongest instance of
# that argument in the tree — stronger than bridge-health's, which at least
# COULD run against a real account. **Nothing in this repository, on any
# machine, can produce a MetricKit payload.** MetricKit delivers on real
# hardware only, only from a shipped build, and at most once every 24 hours;
# the Simulator never delivers one, so `-metricsProbe` on the sim reports an
# empty read forever and a green run there proves only that the read path
# executes. This harness needs no device, no build, no network and no
# simulator, and it is the ONLY proof these rules hold.
#
# `AppMetricsDigest.swift` is compiled VERBATIM — not extracted, not copied.
# That is why it is Foundation-only and split from `AppMetrics.swift`: the file
# the app ships is the file this tests, so the two cannot drift at all.
#
# Every failure mode is a SILENT WRONG ANSWER on a screen whose entire purpose
# is to be screenshotted and believed:
#
#   • the WRONG THREAD's stack — MetricKit hands over every thread and marks
#     one `threadAttributed`; taking the first yields a thread parked in
#     `mach_msg_trap`, a plausible stack of a thread that did not crash;
#   • a stack rendered ROOT FIRST — the leaf is the line that failed, and a
#     reader taking frame 0 as the cause diagnoses `main`;
#   • a fork followed the wrong way — a HANG stack is sampled and branches;
#     following the first child reports whichever branch the encoder wrote
#     first, so the same hang reads differently run to run;
#   • a quantile off by one bucket — p90 silently reporting the MAXIMUM, which
#     is what a bare ceiling over `0.9 * 10 == 9.000000000000002` does;
#   • an empty histogram rendered anyway — a row of dashes reads as a broken
#     instrument rather than as an untouched one.
#
# Pure, local, deterministic. Exit non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

DIGEST="Casberi/Casberi/Model/AppMetricsDigest.swift"
METRICS="Casberi/Casberi/Model/AppMetrics.swift"
SIGNPOSTS="Casberi/Casberi/Model/AppSignposts.swift"
APPFILE="Casberi/Casberi/CasberiApp.swift"
SCREEN="Casberi/Casberi/Screens/DiagnosticsScreen.swift"
PROBES="Casberi/Casberi/Shell/ProbeHooks.swift"
for f in "$DIGEST" "$METRICS" "$SIGNPOSTS" "$APPFILE" "$SCREEN" "$PROBES"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

# --- drift guards -----------------------------------------------------------
# The logic below can be perfect and worth nothing. Each of these is a wiring
# fact the assertions structurally cannot reach.

# THE SUBSCRIBER. Without `add(subscriber:)` the system keeps NOTHING for this
# app: `pastPayloads` stays empty forever, every surface reads "nothing
# delivered yet", and that is indistinguishable from a healthy app that has not
# crashed. This is the single highest-value line in the feature and the easiest
# one to lose in a launch-path refactor.
grep -q 'AppMetrics.begin()' "$APPFILE" \
  || { echo "✗ CasberiApp no longer registers the MetricKit subscriber — the system keeps"; \
       echo "  nothing, every surface reads empty forever, and that is indistinguishable"; \
       echo "  from an app that has not crashed."; exit 1; }

# THE SURFACE. Without this the payloads arrive and nobody can ever see one.
# Comment-stripped: BOTH these files explain the call in a comment directly
# above it, so a raw grep stays green after the real call is deleted — proven
# by mutation, not assumed (the Obsidian lesson, which this repo keeps paying).
#
# `grep >/dev/null` AND NOT `grep -q` ON A PIPE. Under `set -o pipefail`,
# `grep -q` exits at the first match and the writer upstream takes SIGPIPE, so
# the PIPELINE reports failure for a file that matched. It depends on size:
# `DiagnosticsScreen` is ~15KB and fits the 64KB pipe buffer, so `echo`
# finishes before grep exits and it passed; `ProbeHooks` is 284KB and did not.
# The failure was a violation reported against correct code, in the same words
# as the real bug — the exact shape `docs/perf-spec.md` records as worse than
# staying silent. Without `-q`, grep drains its input and there is no SIGPIPE.
SCREEN_CODE=$(sed 's://.*::' "$SCREEN")
PROBES_CODE=$(sed 's://.*::' "$PROBES")
echo "$SCREEN_CODE" | grep 'AppMetrics.report()' >/dev/null \
  || { echo "✗ the Diagnostics screen no longer prints the MetricKit read"; exit 1; }

# ONE RENDERER. The probe must go through the same `report()` the screen draws,
# or it stops being evidence ABOUT the screen and becomes a second opinion
# beside it — `NetworkLedger.resolvedService`'s lesson, which this codebase has
# now paid for on the receipts door and the `-todayProbe` truncation.
echo "$PROBES_CODE" | grep 'AppMetrics.report()' >/dev/null \
  || { echo "✗ -metricsProbe no longer reads through AppMetrics.report() — the probe and the"; \
       echo "  screen can now disagree, and nothing would notice."; exit 1; }

# THE HONEST EMPTY (the honesty law: no fake status). An empty read must SAY it
# is empty and say why. Deleting this branch leaves "0 daily payload(s) · 0
# diagnostic event(s)", which reads as an instrument reporting zero crashes.
grep -q 'nothing delivered yet' "$METRICS" \
  || { echo "✗ the empty read no longer says it is empty — '0 payloads' reads as"; \
       echo "  'zero crashes', which is a fake status on a diagnostics screen."; exit 1; }
grep -q 'Simulator' "$METRICS" \
  || { echo "✗ the empty read no longer names the Simulator as the reason it is empty"; exit 1; }

# NOTHING LEAVES THE DEVICE. The privacy claim for this feature is that it
# reads a store the OS already keeps and renders it locally — so there is no
# host to declare in `NetworkReach` (prd §205) and no receipt to record. The
# day this file makes a request, that claim is false and the reach audit cannot
# see it, because a crash-report uploader is exactly the kind of thing somebody
# adds "just to a private endpoint". Comment-stripped: the file argues this
# rule at length and a raw grep fires on the prose (the Obsidian lesson).
STRIPPED=$(sed 's://.*::' "$METRICS")
for banned in 'URLSession' 'URLRequest' 'URL(string:'; do
  echo "$STRIPPED" | grep "$banned" >/dev/null \
    && { echo "✗ AppMetrics now makes a network call ($banned). Crash payloads carry call"; \
         echo "  stacks and device metadata; sending them makes the privacy screen wrong,"; \
         echo "  and NOTHING in verify.sh could see it. If this is deliberate it is a"; \
         echo "  ruling, a NetworkReach entry and a NetworkLedger.record — not a diff."; exit 1; }
done

# ── The signposts (docs/perf-spec.md P0) ───────────────────────────────────
#
# EVERY SPAN IS PAIRED. An unmatched `.begin` overlaps two intervals on the
# `.exclusive` signpost id and the samples that come back are nonsense — and
# nonsense is worse than absence here, because the whole point of this feature
# is a number somebody will trust without being able to check it.
SP_STRIPPED=$(sed 's://.*::' "$SIGNPOSTS")
for span in Launch ForegroundSweep AskSettled AskFirstPaint; do
  begins=$(echo "$SP_STRIPPED" | grep -c "mxSignpost(.begin, log: log, name: \"$span\")" || true)
  ends=$(echo "$SP_STRIPPED" | grep -c "mxSignpost(.end, log: log, name: \"$span\")" || true)
  [[ "$begins" == "1" && "$ends" == "1" ]] \
    || { echo "✗ signpost span '$span' is not exactly one begin and one end ($begins/$ends)."; \
         echo "  An unmatched begin overlaps two intervals on the .exclusive id and the"; \
         echo "  histogram that comes back is nonsense — worse than no measurement."; exit 1; }
done

# EVERY SPAN IS GUARDED. Without the in-flight flags a path that stops being
# single-flight silently starts producing wrong durations instead of none.
# BOTH SIDES, per flag. `grep "guard.*$flag"` was satisfied by either one, so
# deleting the begin-side guard left the end-side one standing and the check
# passed — found by mutation. The begin must refuse to RE-OPEN an interval
# (`guard !x`), the end must refuse to close one never opened (`guard x`);
# only the first prevents the overlapping-interval nonsense.
for flag in launchOpen sweepOpen askOpen; do
  echo "$SP_STRIPPED" | grep "guard !$flag else { return }" >/dev/null \
    || { echo "✗ the begin-side '$flag' guard is gone — a second begin now overlaps two"; \
         echo "  intervals on the .exclusive id, and the histogram becomes nonsense."; exit 1; }
  echo "$SP_STRIPPED" | grep "guard $flag else { return }" >/dev/null \
    || { echo "✗ the end-side '$flag' guard is gone — an unmatched end now closes an"; \
         echo "  interval that was never opened."; exit 1; }
done
echo "$SP_STRIPPED" | grep "guard askPaintOpen else { return }" >/dev/null \
  || { echo "✗ askFirstPaint lost its first-writer-wins guard — a later paint is the"; \
       echo "  document being refined, not the wait ending (AskClock's rule)."; exit 1; }

# SPARINGLY — APPLE'S OWN WORD, and the rule this repo has already paid for
# once in the other direction (`LaunchPerf.accumulate` cost ~700ms to report
# 87ms). MXSignpost snapshots process-level metrics per call; MXSignpost.h says
# in capitals that bulk use causes "potentially large performance regressions".
# So the call sites are a CLOSED SET, checked here, and every one of them must
# be a once-per-user-event path. A signpost that reached a view body or a
# per-row path would be an instrument that costs what it measures — and it
# would do it inside the exact spans this feature exists to protect.
ALLOWED_SIGNPOST_SITES="Casberi/Casberi/CasberiApp.swift Casberi/Casberi/Shell/RootShell.swift"
while IFS= read -r hit; do
  file="${hit%%:*}"
  [[ "$file" == "$SIGNPOSTS" ]] && continue
  [[ " $ALLOWED_SIGNPOST_SITES " == *" $file "* ]] \
    || { echo "✗ AppSignposts is called from $file, which is not one of the two allowed"; \
         echo "  call sites. MXSignpost snapshots process metrics on EVERY call and Apple's"; \
         echo "  own header warns in capitals against bulk use. A span belongs on a"; \
         echo "  once-per-user-event path (launch, activation, ask) — never in a view body,"; \
         echo "  a loop, or anything per-row. If this is a new user-event span, add the file"; \
         echo "  here deliberately."; exit 1; }
done < <(grep -rn "AppSignposts\." --include="*.swift" Casberi | grep -v "^Casberi/Casberi/Model/AppSignposts.swift")

# NOT BEHIND THE LOGGING GATE. `LaunchClock.reports` exists so a shipped build
# never NSLogs for a real person; a signpost is not a log, and putting it under
# that gate would silently restore the exact "no number has ever been taken on
# real hardware" state this feature was built to end.
python3 - "Casberi/Casberi/Shell/RootShell.swift" <<'PY2' || exit 1
import sys, re
src = open(sys.argv[1]).read()
i = src.find("AppSignposts.endLaunch()")
if i < 0:
    sys.exit("✗ RootShell no longer closes the Launch signpost")
# Walk back to the enclosing `if !LaunchClock.didLog` block and check the call
# is not inside its braces.
gate = src.rfind("if !LaunchClock.didLog", 0, i)
if gate < 0:
    sys.exit(0)
depth, k = 0, src.find("{", gate)
while k < i:
    if src[k] == "{": depth += 1
    elif src[k] == "}":
        depth -= 1
        if depth == 0: break
    k += 1
if k >= i:
    sys.exit("✗ the Launch signpost sits INSIDE the LaunchClock.reports gate — that gate\n"
             "  exists so a shipped build never logs for a real person, and it would now\n"
             "  also suppress the device measurement this feature exists to take.")
PY2

# THE HARNESS'S OWN PRECONDITION. `AppMetricsDigest` is Foundation-only so this
# script can compile the shipped file verbatim. An import here would not fail
# quietly — it would fail with a confusing linker error three checks later.
grep -q 'import MetricKit' "$DIGEST" \
  && { echo "✗ AppMetricsDigest imports MetricKit — it is Foundation-only ON PURPOSE so this"; \
       echo "  harness compiles the SHIPPED file rather than a copy. Put MetricKit code in"; \
       echo "  AppMetrics.swift, where the boundary conversions already live."; exit 1; }

# NO CATALYST GUARD IS CHECKED, deliberately. `appLaunchDiagnostics` reads as
# iOS-only in the header (`API_UNAVAILABLE(macos, tvos, watchos)`) and that was
# asserted here as a Catalyst compile break — wrongly. Mac Catalyst inherits
# iOS availability unless a symbol says `API_UNAVAILABLE(macCatalyst)`, and
# `swiftc -typecheck -target arm64-apple-ios18.0-macabi` against the macOS SDK
# compiles the unguarded block clean. A guard for it would have been one that
# cannot fail, and it would have cost the Mac a diagnostic for nothing.
# Recorded so the header does not send the next reader the same way.

TMP=$(mktemp -d /tmp/metrics-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# --- the assertions ---------------------------------------------------------
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ label: String, _ ok: Bool) {
    if !ok { print("  ✗ \(label)"); failures += 1 }
}

typealias D = AppMetricsDigest
typealias B = AppMetricsDigest.Bucket

// ── Histograms ──────────────────────────────────────────────────────────────

check("an empty histogram has no total", D.total([]) == 0)
check("an empty histogram has no quantile", D.quantileBucketEnd([], q: 0.5) == nil)
check("a histogram of empty buckets has no quantile",
      D.quantileBucketEnd([B(0, 100, 0), B(100, 200, 0)], q: 0.5) == nil)
check("an empty histogram renders NOTHING, not dashes",
      D.histogramLine("Launch", [], unit: "ms", noun: "launches") == nil)

// Ten samples, one per bucket, ends at 100, 200, … 1000.
let ten = (0..<10).map { B(Double($0) * 100, Double($0 + 1) * 100, 1) }
check("total counts SAMPLES, not buckets", D.total(ten) == 10)
check("median of ten is the 5th bucket's end", D.quantileBucketEnd(ten, q: 0.5) == 500)
check("p90 of ten is the 9th bucket's end, NOT the max",
      D.quantileBucketEnd(ten, q: 0.9) == 900)

// CEILING, NOT FLOOR. Needs q*n to be non-integer or the two agree: over three
// samples the median is the 2nd (1.5 → 2), and a floor would report the 1st —
// every duration on the screen one bucket faster than the device measured.
let three = [B(0, 100, 1), B(100, 200, 1), B(200, 300, 1)]
check("median of three ceilings to the 2nd bucket",
      D.quantileBucketEnd(three, q: 0.5) == 200)

// THE FLOAT TRAP, at a MEASURED input rather than a plausible one. `0.9 * 10`
// is exactly 9.0 — the obvious-looking example does not reproduce it, and
// asserting it would have left this untested. Over q in 0.01…1.00 and n in
// 1…5000, 702 pairs disagree; this is the smallest: 0.28 * 25 is
// 7.000000000000001, which a bare ceiling turns into 8.
let twentyFive = (0..<25).map { B(Double($0) * 100, Double($0 + 1) * 100, 1) }
check("a product that overshot by one ulp does not name the next bucket",
      D.quantileBucketEnd(twentyFive, q: 0.28) == 700)
check("q=1 is the last non-empty bucket", D.quantileBucketEnd(ten, q: 1) == 1000)
check("q=0 is nil (no zeroth sample)", D.quantileBucketEnd(ten, q: 0) == nil)
check("q>1 is nil", D.quantileBucketEnd(ten, q: 1.5) == nil)

// Trailing empty buckets must not become the answer for q=1.
let trailing = ten + [B(1000, 1100, 0), B(1100, 1200, 0)]
check("q=1 skips trailing empty buckets", D.quantileBucketEnd(trailing, q: 1) == 1000)

// Order is not trusted from the caller.
check("buckets are sorted before the walk",
      D.quantileBucketEnd(ten.reversed(), q: 0.5) == 500)

// Weighted: 90 samples under 200ms, 10 above.
let skewed = [B(0, 200, 90), B(200, 5000, 10)]
check("median follows the weight, not the bucket count",
      D.quantileBucketEnd(skewed, q: 0.5) == 200)
check("p90 of the skewed set is still the fast bucket",
      D.quantileBucketEnd(skewed, q: 0.9) == 200)
check("q=1 of the skewed set is the slow bucket",
      D.quantileBucketEnd(skewed, q: 1) == 5000)

// Two samples: q=0.5 must name the bucket the FIRST sits in.
let two = [B(0, 100, 1), B(100, 200, 1)]
check("median of two is the first bucket", D.quantileBucketEnd(two, q: 0.5) == 100)

let line = D.histogramLine("Time to first draw", ten, unit: "ms", noun: "launches")
check("the line names the sample count", line?.contains("10 launches") == true)
check("the line is stated as an UPPER BOUND", line?.contains("≤") == true)
check("the line carries median, p90 and worst",
      line?.contains("median ≤ 500ms") == true
      && line?.contains("p90 ≤ 900ms") == true
      && line?.contains("worst ≤ 1000ms") == true)

check("whole numbers print whole", D.number(500) == "500")
check("fractions keep one decimal", D.number(12.34) == "12.3")
check("a rounded fraction prints whole", D.number(11.98) == "12")

// ── Call stacks ─────────────────────────────────────────────────────────────

// Two threads. The first is NOT attributed and is parked in a system frame —
// the plausible-looking wrong answer. The second crashed in our own code.
let twoThreads = #"""
{
  "callStackPerThread": true,
  "callStacks": [
    {
      "threadAttributed": false,
      "callStackRootFrames": [
        { "binaryName": "libsystem_kernel.dylib", "offsetIntoBinaryTextSegment": 4096,
          "sampleCount": 1, "address": 1 }
      ]
    },
    {
      "threadAttributed": true,
      "callStackRootFrames": [
        { "binaryName": "Casberi", "offsetIntoBinaryTextSegment": 2592912, "sampleCount": 1,
          "address": 3,
          "subFrames": [
            { "binaryName": "SwiftUI", "offsetIntoBinaryTextSegment": 200, "sampleCount": 1,
              "address": 2,
              "subFrames": [
                { "binaryName": "Casberi", "offsetIntoBinaryTextSegment": 100,
                  "sampleCount": 1, "address": 1 }
              ]
            }
          ]
        }
      ]
    }
  ]
}
"""#.data(using: .utf8)!

let frames = D.frames(callStackTreeJSON: twoThreads)
check("the ATTRIBUTED thread is the one read",
      !frames.contains { $0.binary == "libsystem_kernel.dylib" })
check("three frames come back", frames.count == 3)
check("LEAF FIRST — the line that crashed is on top",
      frames.first == D.Frame(binary: "Casberi", offset: 2592912, sampleCount: 1))
check("the root is last", frames.last?.offset == 100)
check("frames render in the form atos takes",
      D.frameLines(frames).first == "Casberi +2592912")
check("ownFrame finds the deepest frame in OUR binary",
      D.ownFrame(frames, binary: "Casberi") == "Casberi +2592912")
check("ownFrame is nil when nothing is ours",
      D.ownFrame(frames, binary: "SomeOtherApp") == nil)

// A sampled HANG stack that forks. The heavy branch is the hot path; the light
// one is the plausible wrong answer, and it is written FIRST on purpose.
let forked = #"""
{
  "callStacks": [
    {
      "threadAttributed": true,
      "callStackRootFrames": [
        { "binaryName": "Casberi", "offsetIntoBinaryTextSegment": 1, "sampleCount": 100,
          "subFrames": [
            { "binaryName": "Casberi", "offsetIntoBinaryTextSegment": 2, "sampleCount": 3 },
            { "binaryName": "Casberi", "offsetIntoBinaryTextSegment": 3, "sampleCount": 97 }
          ]
        }
      ]
    }
  ]
}
"""#.data(using: .utf8)!
let hot = D.frames(callStackTreeJSON: forked)
check("the root frame is the LEAF and comes first", hot.first?.offset == 1)
check("a fork follows the HEAVIEST branch, not the first written",
      hot.contains { $0.offset == 3 })
check("the light branch is not reported", !hot.contains { $0.offset == 2 })

// THE POLARITY, from a real report (prd §628). Build 525's watchdog kill, as
// MetricKit handed it over: the root frame is the CRASH POINT and every
// subFrames step is the caller, down to dyld's `start`. Fourteen deep, so a
// twelve-frame cap has to choose an end — and the old `reversed().prefix()`
// chose `start`'s end, printing the run loop's scaffolding and cutting off the
// only frame that said where ten seconds went. This fixture is that stack.
func caller(_ binary: String, _ offset: Int, _ sub: String) -> String {
    #"{ "binaryName": "\#(binary)", "offsetIntoBinaryTextSegment": \#(offset), "sampleCount": 1, "subFrames": [ \#(sub) ] }"#
}
var real525 = #"{ "binaryName": "dyld", "offsetIntoBinaryTextSegment": 19484, "sampleCount": 1 }"#
for (b, o) in [("Casberi", 22494064), ("SwiftUI", 183368), ("SwiftUI", 184564), ("SwiftUI", 198000),
               ("UIKitCore", 573784), ("UIKitCore", 1185392), ("GraphicsServices", 5272),
               ("CoreFoundation", 189772), ("CoreFoundation", 192928), ("CoreFoundation", 415192),
               ("CoreFoundation", 656132), ("Casberi", 4242), ("libsystem_kernel.dylib", 8)] {
    real525 = caller(b, o, real525)
}
let realTree = #"{ "callStacks": [ { "threadAttributed": true, "callStackRootFrames": [ \#(real525) ] } ] }"#
    .data(using: .utf8)!
let realFrames = D.frames(callStackTreeJSON: realTree)
check("the real report's LEAF is on top", realFrames.first == D.Frame(binary: "libsystem_kernel.dylib", offset: 8, sampleCount: 1))
check("the cap drops `start`, not the leaf", !realFrames.contains { $0.binary == "dyld" })
check("our own deepest frame is the one nearest the crash, not `main`",
      D.ownFrame(realFrames, binary: "Casberi") == "Casberi +4242")

// Multiple ROOT frames fork the same way.
let twoRoots = #"""
{
  "callStacks": [
    { "threadAttributed": true,
      "callStackRootFrames": [
        { "binaryName": "Casberi", "offsetIntoBinaryTextSegment": 10, "sampleCount": 1 },
        { "binaryName": "Casberi", "offsetIntoBinaryTextSegment": 20, "sampleCount": 9 }
      ]
    }
  ]
}
"""#.data(using: .utf8)!
check("the heaviest ROOT frame wins too",
      D.frames(callStackTreeJSON: twoRoots).first?.offset == 20)

// Nothing marked attributed — fall back to the first rather than returning
// nothing, since a stack of the wrong thread still beats no stack at all.
let noneAttributed = #"""
{ "callStacks": [ { "callStackRootFrames": [
  { "binaryName": "Casberi", "offsetIntoBinaryTextSegment": 7, "sampleCount": 1 } ] } ] }
"""#.data(using: .utf8)!
check("with no attributed thread, the first is read",
      D.frames(callStackTreeJSON: noneAttributed).first?.offset == 7)

// Malformed input must return empty, never trap. This parses data the OS hands
// us on a device; a diagnostics reader that can crash the app is worse than
// the bug it was opened to explain.
check("garbage returns empty", D.frames(callStackTreeJSON: Data([0x00, 0xff])).isEmpty)
check("an empty object returns empty",
      D.frames(callStackTreeJSON: "{}".data(using: .utf8)!).isEmpty)
check("no callStacks returns empty",
      D.frames(callStackTreeJSON: #"{"callStacks":[]}"#.data(using: .utf8)!).isEmpty)
check("a frame with no binaryName is dropped",
      D.frames(callStackTreeJSON:
        #"{"callStacks":[{"threadAttributed":true,"callStackRootFrames":[{"sampleCount":1}]}]}"#
          .data(using: .utf8)!).isEmpty)

// A frame missing its offset still reports, at 0 — the binary name alone says
// whether the crash was in our code, which is the first thing a reader asks.
check("a frame with no offset still reports its binary",
      D.frames(callStackTreeJSON:
        #"{"callStacks":[{"threadAttributed":true,"callStackRootFrames":[{"binaryName":"Casberi"}]}]}"#
          .data(using: .utf8)!).first == D.Frame(binary: "Casberi", offset: 0, sampleCount: 0))

// The limit caps from the LEAF end — and the leaf is the ROOT frame (prd §628):
// offset 0 here is the crash point, 40 is `start`. This check used to assert
// the opposite, because it was written from the same wrong guess as the code
// it tested, and it passed for the whole time the screen was cutting off the
// leaf. A fixture built on the reader's assumption proves the assumption.
var deep = #"{ "binaryName": "Casberi", "offsetIntoBinaryTextSegment": 40, "sampleCount": 1 }"#
for i in stride(from: 39, through: 0, by: -1) {
    deep = "{ \"binaryName\": \"Casberi\", \"offsetIntoBinaryTextSegment\": \(i), \"sampleCount\": 1, \"subFrames\": [\(deep)] }"
}
let deepData = "{ \"callStacks\": [ { \"threadAttributed\": true, \"callStackRootFrames\": [\(deep)] } ] }"
    .data(using: .utf8)!
let capped = D.frames(callStackTreeJSON: deepData, limit: 5)
check("the limit is honoured", capped.count == 5)
check("the limit keeps the LEAF end, which is the ROOT frame", capped.first?.offset == 0 && capped.last?.offset == 4)

if failures > 0 { print("✗ metrics self-test: \(failures) failure(s)"); exit(1) }
print("✓ metrics self-test: histogram + call-stack reading verified")
SWIFT

# `-Onone` for the reason recorded on every harness here: the optimizer is ~97%
# of a pure-logic harness's wall time and buys nothing an assertion can see.
swiftc -Onone -o "$TMP/run" "$DIGEST" "$TMP/main.swift" 2>&1 \
  | grep -E "error:" && { echo "✗ harness failed to compile"; exit 1; }
"$TMP/run"

# --- mutation pass ----------------------------------------------------------
# A test that cannot fail proves nothing. Each mutation is one of the silent
# wrong answers named at the top of this file; every one MUST be caught.
mutate() {
  local label="$1" from="$2" to="$3"
  local dir="$TMP/mut"; rm -rf "$dir"; mkdir -p "$dir"
  # THE STATUS IS CHECKED, and it was not (prd §628). This function is called
  # as `mutate … || mut_fail=1`, and `set -e` is OFF inside a function on the
  # left of `||` — so when the python below found no anchor it printed its
  # complaint, wrote no mutant, swiftc failed on the missing file, the
  # SURVIVED branch was skipped, and the function returned 0: a mutation that
  # never ran, counted as CAUGHT. Two mutations sat in exactly that state
  # after the polarity fix, and the run still printed "11 mutations caught".
  # The third shape of the §627 class: the detector fired and nobody listened.
  python3 - "$DIGEST" "$dir/digest.swift" "$from" "$to" <<'PY' || { echo "  ✗ STALE MUTATION (anchor not found, nothing tested): $label"; return 1; }
import sys
src, dst, a, b = sys.argv[1:5]
text = open(src).read()
if a not in text:
    sys.exit(f"✗ mutation target not found (stale harness): {a!r}")
open(dst, "w").write(text.replace(a, b, 1))
PY
  cp "$TMP/main.swift" "$dir/main.swift"
  if swiftc -Onone -o "$dir/run" "$dir/digest.swift" "$dir/main.swift" 2>/dev/null \
     && "$dir/run" >/dev/null 2>&1; then
    echo "  ✗ SURVIVED: $label"; return 1
  fi
  return 0
}

mut_fail=0
# The wrong thread — a plausible stack of a thread that did not crash.
mutate "the attributed thread is ignored" \
  'let stack = stacks.first { ($0["threadAttributed"] as? Bool) == true } ?? stacks[0]' \
  'let stack = stacks[0]' || mut_fail=1
# Root first — the reader diagnoses `main`. This IS the shipped bug of build
# 525 (prd §628): reversing a walk that is already leaf-first and then capping
# it kept `start`'s end and cut the crash point off.
mutate "the stack is rendered root-first (build 525's own bug)" \
  'return Array(chain.prefix(limit))' \
  'return Array(chain.reversed().prefix(limit))' || mut_fail=1
# The limit cuts the leaf end off instead of the root end.
mutate "the limit keeps the root end" \
  'return Array(chain.prefix(limit))' \
  'return Array(chain.suffix(limit))' || mut_fail=1
# A fork followed by write order — the same hang reads differently each run.
mutate "a fork follows the first child" \
  'return nodes.max { count(of: $0) < count(of: $1) } ?? nodes[0]' \
  'return nodes[0]' || mut_fail=1
# A frame with no binary is reported anyway — an un-symbolicatable line above
# an actionable one.
mutate "a nameless frame is kept" \
  'guard let binary = node["binaryName"] as? String, !binary.isEmpty else { return nil }' \
  'let binary = (node["binaryName"] as? String) ?? ""' || mut_fail=1
# THE FLOAT TRAP — p90 silently becomes the maximum.
mutate "the quantile ceiling is taken on the raw product" \
  'let exact = ((q * Double(n)) * 1e6).rounded() / 1e6' \
  'let exact = q * Double(n)' || mut_fail=1
# The quantile reports a bucket's START — every duration halves.
mutate "the quantile reports the bucket start" \
  'if seen >= target { return bucket.end }' \
  'if seen >= target { return bucket.start }' || mut_fail=1
# Off by one the other way — p50 becomes p50-minus-a-bucket.
mutate "the quantile floors instead of ceilings" \
  'let target = max(1, Int(exact.rounded(.up)))' \
  'let target = max(1, Int(exact.rounded(.down)))' || mut_fail=1
# Buckets counted instead of samples — every quantile lands in the wrong place.
mutate "total counts buckets, not samples" \
  'buckets.reduce(0) { $0 + max(0, $1.count) }' \
  'buckets.count' || mut_fail=1
# NO MUTATION for the `where bucket.count > 0` filter, deliberately: the walk
# returns at the FIRST bucket whose cumulative count reaches the target, and a
# zero-count bucket never changes that cumulative — so removing the filter is
# provably behaviour-preserving and a mutation for it would be one that cannot
# fail. It stays in the source as a statement of intent, not as a guard, and
# saying so here is cheaper than the next person re-deriving it.
# Unsorted input trusted — a caller change silently reorders the answer.
mutate "buckets are not sorted" \
  'for bucket in buckets.sorted(by: { $0.start < $1.start }) where bucket.count > 0 {' \
  'for bucket in buckets where bucket.count > 0 {' || mut_fail=1
# An empty histogram renders anyway — dashes read as a broken instrument.
# (`guard n > 0 else { return nil }` on its own line is unique to
# `histogramLine`; `quantileBucketEnd`'s guard also tests q.)
mutate "an empty histogram renders a line" \
  'guard n > 0 else { return nil }' \
  'if false { return nil }' || mut_fail=1

[[ $mut_fail -eq 0 ]] || { echo "✗ metrics self-test: a mutation survived"; exit 1; }
echo "✓ metrics self-test: 11 mutations caught, 14 drift guards green"
