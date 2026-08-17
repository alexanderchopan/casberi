#!/bin/zsh
# Casberi performance pass — headless (simctl only), so it runs in the nightly
# audit right after verify.sh. Captures three metrics in ONE cold launch:
#   • launch    — init→ready latency (ms), the app's cold-launch path
#   • memory    — steady-state RSS (MB), read after first frame, before inference
#   • answer    — answer-path latency (ms), the on-device compose round-trip
# Appends one row to scripts/output/perf-history.csv and writes perf.txt to an
# output dir, flagging regressions vs the previous run and absolute ceilings.
# Exits 0 ALWAYS — this REPORTS, it does not gate the build.
#
# Usage: scripts/perf.sh [output-dir]
#   output-dir defaults to scripts/output/perf-<timestamp>.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DD="$HOME/Library/Developer/CasberiDD"          # same derivedData as verify.sh
DEVICE="iPhone 17 Pro"
BUNDLE="com.casberi.app"
OUT="${1:-$ROOT/scripts/output/perf-$(date +%Y%m%d-%H%M%S)}"
HIST="$ROOT/scripts/output/perf-history.csv"

# Ceilings (absolute) and per-run regression ratios (% of previous run).
# Answer latency is noisiest (cold model + reseeded corpus) — looser ratio.
LAUNCH_CEIL=900;   LAUNCH_RATIO=140
MEM_CEIL=450;      MEM_RATIO=140
ANSWER_CEIL=12000; ANSWER_RATIO=160

step() { print -P "%F{cyan}▶ $1%f"; }
mkdir -p "$OUT"

# ── Ensure booted + installed (verify.sh usually did both already) ──────
xcrun simctl bootstatus "$DEVICE" -b >/dev/null 2>&1 || xcrun simctl boot "$DEVICE" 2>/dev/null || true
xcrun simctl bootstatus "$DEVICE" -b >/dev/null 2>&1 || true
if ! xcrun simctl get_app_container "$DEVICE" "$BUNDLE" >/dev/null 2>&1; then
  APP="$DD/Build/Products/Debug-iphonesimulator/Casberi.app"
  [[ -d "$APP" ]] && xcrun simctl install "$DEVICE" "$APP" >/dev/null 2>&1 || true
fi

# ── One cold launch drives all three metrics ────────────────────────────
LOG="$OUT/perf-stream.log"
step "Cold launch + probe"
xcrun simctl terminate "$DEVICE" "$BUNDLE" 2>/dev/null || true
# Stream the timing lines the app emits during THIS launch.
#
# `launchPerf` joined the predicate on 2026-07-31 and is the reason this pass
# can now say WHY a launch got slower rather than only that it did. The app
# has emitted per-span lines (`LaunchPerf.time`/`accumulate`/`buildTick` —
# container open, the dedupe/Spotlight housekeeping, the foreground sweep,
# feed-page assembly counts) since 2026-07-30, and this predicate dropped
# every one of them on the floor — so nine runs recorded a launch climbing
# 293ms → 763ms with no breakdown of what grew, and the spans had to be
# re-measured by hand to act on it. A stream is the cheap half of a perf
# pass; discarding it to keep the log tidy costs the whole diagnosis.
xcrun simctl spawn "$DEVICE" log stream \
  --predicate 'process == "Casberi" AND (eventMessage CONTAINS "launchTimer" OR eventMessage CONTAINS "answerProbe(" OR eventMessage CONTAINS "launchPerf" OR eventMessage CONTAINS "askPerf|")' \
  --style compact > "$LOG" 2>/dev/null &
LOGPID=$!
sleep 1
# launchTimer logs init→ready at first frame; the answer probe fires after
# -probeDelay (past first frame) so memory is sampled with the app at rest.
PID=$(xcrun simctl launch "$DEVICE" "$BUNDLE" \
  -onboarded YES -deeplink casberi://home \
  -answerProbe "what did I save about work" -probeDelay 5 2>/dev/null | awk -F': ' '{print $NF}')

# Steady-state memory: sample RSS ~3s in — past first frame, before inference.
sleep 3
MEM_MB="n/a"
if [[ -n "${PID:-}" ]] && kill -0 "$PID" 2>/dev/null; then
  RSS_KB=$(ps -o rss= -p "$PID" 2>/dev/null | tr -d ' ')
  [[ "$RSS_KB" == <-> ]] && MEM_MB=$(( RSS_KB / 1024 ))
fi

# Wait for the answer probe to log its latency. A cold first inference (no
# prior warm — e.g. perf.sh run standalone, not after verify.sh) can take ~25s
# on top of the 5s probe delay, so give it a wide window.
for i in {1..45}; do
  # Match the latency line specifically — NOT the filter-header line that
  # `log stream` prints, which echoes the predicate text (and thus the bare
  # substring "answerProbe(") before any real event arrives.
  grep -Eq 'answerProbe\(.+\) [0-9]+ms' "$LOG" 2>/dev/null && break
  sleep 1
done
kill $LOGPID 2>/dev/null || true
xcrun simctl terminate "$DEVICE" "$BUNDLE" 2>/dev/null || true

# ── Parse the two logged latencies (empty → n/a) ────────────────────────
num() { grep -o '[0-9]\+ms' | grep -o '[0-9]\+' | head -1; }
LAUNCH_MS=$(grep 'launchTimer' "$LOG" 2>/dev/null | num); : ${LAUNCH_MS:=n/a}
ANSWER_MS=$(grep 'answerProbe(' "$LOG" 2>/dev/null | num); : ${ANSWER_MS:=n/a}

# ── Previous run (for regression deltas) ────────────────────────────────
PREV_LAUNCH=n/a; PREV_MEM=n/a; PREV_ANSWER=n/a
if [[ -f "$HIST" ]]; then
  LAST=$(grep -v '^timestamp' "$HIST" | tail -1)
  if [[ -n "$LAST" ]]; then
    PREV_LAUNCH=$(echo "$LAST" | cut -d, -f2)
    PREV_MEM=$(echo "$LAST" | cut -d, -f3)
    PREV_ANSWER=$(echo "$LAST" | cut -d, -f4)
  fi
fi

# ── Report + flag ───────────────────────────────────────────────────────
typeset -a FLAGS
line() {  # line <name> <unit> <cur> <prev> <ceil> <ratio>
  local name=$1 unit=$2 cur=$3 prev=$4 ceil=$5 ratio=$6 msg
  if [[ "$cur" != <-> ]]; then
    FLAGS+=("$name not captured")
    print -r -- "  $name: n/a (not captured)"
    return
  fi
  msg="  $name: ${cur}${unit}"
  if [[ "$prev" == <-> ]]; then
    local pct=$(( cur * 100 / prev ))
    msg+="  (prev ${prev}${unit}, ${pct}%)"
    (( pct > ratio )) && { FLAGS+=("$name +${pct}% vs prev (${prev}→${cur}${unit})"); msg+="  ⚠REGRESSION"; }
  fi
  (( cur > ceil )) && { FLAGS+=("$name over ${ceil}${unit} ceiling (${cur})"); msg+="  ⚠CEILING"; }
  print -r -- "$msg"
}

SHA=$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)
TS=$(date +%Y-%m-%dT%H:%M:%S)
{
  print -r -- "Casberi perf pass — $TS (build $SHA)"
  print -r -- "device: $DEVICE"
  print -r -- ""
  line "launch (init→ready)" "ms" "$LAUNCH_MS" "$PREV_LAUNCH" "$LAUNCH_CEIL" "$LAUNCH_RATIO"
  line "memory (RSS)"        "MB" "$MEM_MB"    "$PREV_MEM"    "$MEM_CEIL"    "$MEM_RATIO"
  line "answer (compose)"    "ms" "$ANSWER_MS" "$PREV_ANSWER" "$ANSWER_CEIL" "$ANSWER_RATIO"
  # ── The ask span the three metrics above cannot see ───────────────────
  # REPORTED, never gated, and deliberately NOT a fourth CSV column: the
  # history's schema is parsed by field position (cut -d, -f2..4), so adding
  # one silently mis-reads every previous row's build_sha as a latency.
  #
  # "answer (compose)" starts inside the answer path and stops when the
  # document is returned. `askPerf|` brackets it — entry to first paint, and
  # entry to settled — which is where both 2026-08-13 ask regressions lived
  # (a corpus fetch upstream of the composer, and another one sitting above
  # the paint). `firstPaint=never` is a finding, not a gap: it means that ask
  # shows nothing at all until it is completely finished.
  if grep -q 'askPerf|' "$LOG" 2>/dev/null; then
    print -r -- ""
    print -r -- "ask spans (DEBUG markers, not gated):"
    grep -o 'askPerf| [^"]*' "$LOG" | sed 's/^askPerf| //' | sort -u | while read -r span; do
      print -r -- "  $span"
    done
  fi
  print -r -- ""
  # ── Span breakdown (the WHY behind the launch number) ─────────────────
  # Reported, never flagged: these are DEBUG-only markers and the three
  # numbers above are what the history tracks. This section exists so a
  # regression run names its own cause instead of sending the next reader
  # back to re-instrument by hand.
  if grep -q 'launchPerf' "$LOG" 2>/dev/null; then
    print -r -- "launch spans (DEBUG markers, not gated):"
    # One-shot timings: `timed=<label> took=<n>ms`.
    grep -o 'timed=[^ ]* took=[0-9.]*ms' "$LOG" | sort -u | while read -r span; do
      print -r -- "  ${span/ took=/  }"
    done
    # Accumulators are cumulative — the LAST line per label is the total.
    for label in $(grep -o 'accum=[^ ]*' "$LOG" | cut -d= -f2 | sort -u); do
      last=$(grep "accum=$label " "$LOG" | tail -1)
      calls=$(echo "$last" | grep -o 'calls=[0-9]*' | cut -d= -f2)
      total=$(echo "$last" | grep -o 'totalMs=[0-9.]*' | cut -d= -f2)
      print -r -- "  accum=$label  ${total}ms over ${calls} calls"
    done
    # Feed-page assembly: the count is the metric (see LaunchPerf.buildTick).
    BUILDS=$(grep -c 'HEAVYBUILD' "$LOG" 2>/dev/null || echo 0)
    if (( BUILDS > 0 )); then
      PAGES=$(grep -o 'HEAVYBUILD source=[^ ]*' "$LOG" | cut -d= -f2 | sort -u | tr '\n' ' ')
      print -r -- "  feed page assemblies: $BUILDS across: $PAGES"
    fi
    print -r -- ""
  fi
  if (( ${#FLAGS} )); then
    print -r -- "FLAGS (${#FLAGS}):"
    for f in "${FLAGS[@]}"; do print -r -- "  ⚠ $f"; done
  else
    print -r -- "No flags — within ceilings and previous-run range."
  fi
} | tee "$OUT/perf.txt"

# ── Append the history row (create header once) ─────────────────────────
[[ -f "$HIST" ]] || echo "timestamp,launch_ms,mem_mb,answer_ms,build_sha" > "$HIST"
echo "$TS,$LAUNCH_MS,$MEM_MB,$ANSWER_MS,$SHA" >> "$HIST"

print -P "%F{green}✓ perf pass → $OUT/perf.txt%f"
exit 0
