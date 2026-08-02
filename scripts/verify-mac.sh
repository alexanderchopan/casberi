#!/bin/zsh
# Casberi Mac Catalyst verify — the macOS sibling of verify.sh, and the only
# pass that exercises the Mac build as a RUNNING APP rather than a compile.
#
#   build → cold-launch survival → screen sweep → on-device probes →
#   live-integration probes (warn-only) → perf metrics
#
# Exit 0 = every deterministic check green. Screenshots, logs and perf.txt land
# in scripts/output/mac-<timestamp>/.
#
# Usage: scripts/verify-mac.sh [--build-only]
#   LAUNCH_CYCLES=<n>  cold-launch cycles (default 5, 0 skips)
#   SKIP_LIVE=1        skip the network section entirely (offline runs)
#
# ── Why this can't just be verify.sh with a different -destination ──────────
# verify.sh is `xcrun simctl` end to end: boot, install, launch, screenshot,
# log stream. NONE of that exists for Mac Catalyst — it's a real macOS process,
# not a simulator guest. Everything below is the Mac equivalent, and each
# substitution was measured on 2026-08-01 rather than assumed:
#
#   install        → none. The .app in DerivedData IS the artifact; `open` it.
#   simctl launch  → `open -n` (LaunchServices). Launching the binary directly
#                    (`Casberi.app/Contents/MacOS/Casberi &`) DOES run, and its
#                    NSLog reaches stderr — but the UI never mounts: no
#                    `launchTimer`, no first frame, process alive and idle
#                    forever. A Catalyst app needs the LaunchServices session.
#   log stream     → `open --stderr <path>`. `log stream`/`log show` filtered on
#                    process == "Casberi" captured NOTHING from an `open`-ed
#                    Catalyst app (tried both, twice, zero lines) while the same
#                    NSLog calls landed fine on stderr. So the harness redirects
#                    the process's own stderr and never touches unified logging.
#   simctl io ...  → the app screenshots ITSELF (`-macSnapshot`, RootShell).
#     screenshot     `screencapture` needs a Screen Recording grant, which a
#                    headless nightly cannot click through; a window rendering
#                    its own hierarchy needs no permission at all.
#
# ── Hermetic by construction ───────────────────────────────────────────────
# Every launch passes `-storeScratch YES`. On the simulator the guest sandbox
# isolates a test run for free; on the Mac a DEBUG build shares the REAL app
# group container with the person's installed Casberi. Without scratch, a
# nightly whose schema is ahead of the installed build would forward-migrate
# the daily driver's corpus, and every probe would read (and heal, and delete
# from) real things. Scratch is a throwaway on-disk store per process — a real
# open, so the container-open span stays honest, but nothing shared.
#
# For the same reason the kill pattern below is scoped to THIS DerivedData
# path: a bare `pkill Casberi` would quit the app the person has open.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DD="$HOME/Library/Developer/CasberiMacDD"       # Mac-only, never shared with verify.sh's iOS DD
APP="$DD/Build/Products/Debug-maccatalyst/Casberi.app"
BIN="$APP/Contents/MacOS/Casberi"
# Snapshots land in the APP GROUP container, not the app container. Measured
# from a real LaunchAgent on 2026-08-01: a launchd job reading
# ~/Library/Containers/com.casberi.app/Data is DENIED by TCC ("Operation not
# permitted"), while the group container reads fine. An interactive terminal
# usually holds the app-data grant, which is exactly why the first version of
# this passed by hand every time and failed on the first real nightly.
# The team prefix is required — the unprefixed path simply doesn't exist.
SNAPDIR="$HOME/Library/Group Containers/35428TQK3S.group.com.casberi.app/HarnessSnapshots"
OUT="$ROOT/scripts/output/mac-$(date +%Y%m%d-%H%M%S)"
HIST="$ROOT/scripts/output/perf-history-mac.csv"
CRASHDIR="$HOME/Library/Logs/DiagnosticReports"

# Perf ceilings. Separate history + ceilings from iOS on purpose: these are
# different silicon running a different binary, so a shared baseline would
# make every comparison meaningless in both directions.
#
# The RATIOS are deliberately looser than verify.sh's, from four back-to-back
# runs of identical code on 2026-08-01: launch 190/400/237/378ms and answer
# 1332/2178/3194ms. That is ~2x and ~2.4x of pure run-to-run noise — the
# answer metric ends in an on-device model inference, which is the least
# repeatable thing this app does, and launch varies with whatever else the Mac
# is doing at 03:20. At verify.sh's 140/160 every single night flags a
# REGRESSION, and a nightly that always warns is a nightly nobody reads.
# Memory is the stable one (104–126MB) and keeps a tight ratio.
# Tighten these when there is enough history to know the real distribution;
# the absolute ceilings are what catch a genuine blow-up in the meantime.
LAUNCH_CEIL=900;   LAUNCH_RATIO=200
MEM_CEIL=600;      MEM_RATIO=150
ANSWER_CEIL=12000; ANSWER_RATIO=250

step() { print -P "%F{cyan}▶ $1%f"; }
ok()   { print -P "%F{green}✓ $1%f"; }
warn() { print -P "%F{yellow}⚠ $1%f"; }
fail() { print -P "%F{red}✗ $1%f"; exit 1; }

mkdir -p "$OUT"
# Announced up front, not only in the closing line: a run that FAILS never
# reaches the closing line, so nightly-mac.sh had no run dir to record for
# exactly the nights whose artifacts someone would want to open.
print -r -- "OUTPUT_DIR $OUT"
typeset -a WARNINGS

# ── Launch helpers ─────────────────────────────────────────────────────────
# quit_app: only ever kills a process running from THIS harness's build path,
# so a nightly can't quit the Casberi the person is using.
quit_app() { pkill -f "$DD/Build/Products/Debug-maccatalyst/Casberi.app" 2>/dev/null; sleep 1; }

# launch <logfile> <args...> — cold-launch the Mac app with stderr captured.
# Always scratch-stored and past onboarding; callers add their own probe args.
launch() {
  local logfile="$1"; shift
  quit_app
  : > "$logfile"
  open -n "$APP" --stderr "$logfile" --stdout /dev/null \
    --args -storeScratch YES -onboarded YES "$@" 2>/dev/null
}

# wait_for <logfile> <extended-regex> <seconds> — poll the captured stderr.
wait_for() {
  local logfile="$1" pattern="$2" limit="$3" i
  for (( i=0; i<limit; i++ )); do
    sleep 1
    grep -Eq "$pattern" "$logfile" 2>/dev/null && return 0
  done
  return 1
}

app_pid() { pgrep -f "$DD/Build/Products/Debug-maccatalyst/Casberi.app" | head -1; }

# ── 0. Static audits (shared with verify.sh, seconds, no build) ────────────
# Run here too so a Mac-only nightly still certifies the whole tree — these
# are the three checks that were each made mechanical after a real regression
# shipped (see CLAUDE.md). Cheap enough that duplication beats a gap.
step "Static audits"
"$ROOT/scripts/catalog-sync.sh" >/dev/null || fail "catalog surfaces drifted — run scripts/catalog-sync.sh"
"$ROOT/scripts/network-reach-audit.sh" >/dev/null || fail "a network host isn't disclosed — run scripts/network-reach-audit.sh"
"$ROOT/scripts/swiftdata-liveness-audit.py" --self-test >/dev/null \
  || fail "the liveness audit's own self-test failed — the check is broken, not the code"
"$ROOT/scripts/swiftdata-liveness-audit.py" >/dev/null || fail "a Thing is read without a liveness guard — run scripts/swiftdata-liveness-audit.py"
ok "catalog sync · network reach · swiftdata liveness"

# ── 1. Build ───────────────────────────────────────────────────────────────
step "Building Casberi (Mac Catalyst, derivedData: $DD)"
xcodebuild -project "$ROOT/Casberi/Casberi.xcodeproj" -scheme Casberi \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  -derivedDataPath "$DD" build -quiet 2>&1 | grep -E "error:" | head -20
# Gate on xcodebuild's OWN exit, not just the bundle's existence (2026-08-01):
# an incremental dir keeps yesterday's bundle around, so a broken build would
# otherwise sail through and every later step would certify a STALE binary.
(( pipestatus[1] == 0 )) || fail "xcodebuild failed (errors above) — the bundle at $APP is stale, not current"
[[ -d "$APP" ]] || fail "build produced no app bundle at $APP"
ok "build"

[[ "${1:-}" == "--build-only" ]] && { print -P "%F{green}✓ build-only → $APP%f"; exit 0; }

# ── 2. Cold-launch survival ────────────────────────────────────────────────
# The first-frame stack-overflow class (CLAUDE.md: 2026-07-10 / 07-13 / 07-15)
# is intermittent, so one green launch proves nothing. Mac Catalyst runs the
# same deep SwiftUI tree under the same 8MB `-stack_size` flag, and the eager
# head is if anything DEEPER here (the pane layout adds a level), so the class
# applies — it has simply never been checked on this platform until now.
CYCLES=${LAUNCH_CYCLES:-5}
if (( CYCLES > 0 )); then
  step "Cold-launch survival ($CYCLES cycles)"
  IPS_BEFORE=$(find "$CRASHDIR" -maxdepth 1 -name 'Casberi-*.ips' 2>/dev/null | wc -l | tr -d ' ')
  for (( i=1; i<=CYCLES; i++ )); do
    launch "$OUT/launch-$i.log"
    if ! wait_for "$OUT/launch-$i.log" 'launchTimer init→ready [0-9]+ms' 20; then
      if [[ -n "$(app_pid)" ]]; then
        quit_app
        fail "cold-launch cycle $i: no first frame in 20s, process alive — frozen at launch (see $OUT/launch-$i.log)"
      else
        fail "cold-launch cycle $i: process died before first frame — the launch-crash class (check $CRASHDIR)"
      fi
    fi
  done
  quit_app
  IPS_AFTER=$(find "$CRASHDIR" -maxdepth 1 -name 'Casberi-*.ips' 2>/dev/null | wc -l | tr -d ' ')
  (( IPS_AFTER > IPS_BEFORE )) && fail "launch loop passed but $((IPS_AFTER - IPS_BEFORE)) new crash report(s) in $CRASHDIR"
  ok "cold-launch survival ($CYCLES/$CYCLES)"
fi

# ── 3. Screen sweep ────────────────────────────────────────────────────────
# The app renders its own key window (see the `-macSnapshot` rationale above)
# into its container tmp; we copy each PNG out and prove it's a real frame.
# A window that mounted but painted nothing still writes a valid PNG, so the
# size floor is the actual check — a blank 1024pt window compresses tiny.
sweep() {  # sweep <name> <launch-args...>
  # Split across two `local` lines on purpose: zsh expands every word on a
  # `local` line before it assigns any of them, so a same-line `log=…$name…`
  # reads an unset `name` and trips `set -u`.
  local name="$1"; shift
  local log="$OUT/sweep-$name.log"
  # No pre-clear of the destination: the harness has READ but not WRITE access
  # to the group container, so `rm` there fails. Freshness comes from waiting
  # on THIS run's own "wrote" line below — the app overwrites in place.
  launch "$log" "$@" -macSnapshot "$name" -snapshotDelay 4
  if ! wait_for "$log" "macSnapshot: wrote" 20; then
    quit_app
    fail "screen sweep '$name': no snapshot in 20s (see $log)"
  fi
  quit_app
  [[ -f "$SNAPDIR/$name.png" ]] || fail "screen sweep '$name': snapshot logged but no file at $SNAPDIR"
  cp "$SNAPDIR/$name.png" "$OUT/$name.png" \
    || fail "screen sweep '$name': cannot read the snapshot (TCC? see $SNAPDIR)"
  local bytes=$(stat -f%z "$OUT/$name.png" 2>/dev/null)
  : ${bytes:=0}
  (( bytes > 20000 )) || fail "screen sweep '$name': ${bytes}B PNG — window mounted but painted nothing"
  ok "$name (${bytes}B)"
}
# `casberi://home` and `casberi://feed` land on the SAME screen — the tab bar
# died in 0764ee3 and the app opens on the All feed, so sweeping both produced
# two byte-identical PNGs (verified by md5, 2026-08-01) and flattered the
# coverage count. These four are distinct surfaces, and the feed is seeded so
# its shot proves ROWS render rather than only the empty state that `home`
# already covers.
step "Screen sweep"
sweep home     -deeplink "casberi://home"
sweep feed     -seedThing "Bluesky:0" -deeplink "casberi://feed"
sweep composer -openComposer YES
sweep apps     -deeplink "casberi://account"
sweep settings -deeplink "casberi://settings"

# ── 4. On-device end-to-end (deterministic — these gate the run) ───────────
# Everything here is local: no network, no keys, no credits. A failure is a
# real regression, so these hard-fail. `-seedThing` lands a real Thing through
# the real ingest path first, so the answer/find probes retrieve against a
# non-empty corpus instead of exercising only the empty branch.
step "On-device probes"

probe() {  # probe <name> <success-regex> <timeout> <args...>
  local name="$1" pattern="$2" limit="$3"; shift 3
  local log="$OUT/probe-$name.log"
  launch "$log" "$@"
  if wait_for "$log" "$pattern" "$limit"; then
    quit_app; ok "$name"
  else
    quit_app; fail "$name probe produced no result in ${limit}s (see $log)"
  fi
}

# Answer path: retrieve → on-device compose → doc. Seeded first so the
# retriever has something to find; the model is cold, hence the wide window.
probe answer 'answerProbe\(.+\) [0-9]+ms' 60 \
  -seedThing "Bluesky:0" -answerProbe "what did I save" -probeDelay 6

# The Mac activation door (2026-08-01). Catalyst never delivers the launch
# scenePhase transition, so RootShell routes activation through
# `didBecomeActiveNotification` (+ a `.task` fallback). Before that fix, NO
# Mac process ever ran the foreground block — no bridge refresh, no whisper,
# no pane brief — and every sweep still passed, because nothing asserted the
# block ran. This does: the span only logs from inside the block itself, and
# the answer probe's process lives long past the 800ms deferral, so absence
# is a regression, not a race.
grep -q 'timed=refreshAllConnected' "$OUT/probe-answer.log" \
  || fail "activation work never ran — RootShell's Mac activation door (handleActivation) is dead again, so bridge refresh and the pane brief are too"
ok "activation door (refreshAllConnected span present)"

# Find: the composer's deterministic door (prd §215) — no model is reached,
# so a slow/absent model can't mask a retrieval regression here. Two details
# make this a real assertion rather than a smoke test: the hook is gated on
# `isOpen`, so it needs `-openComposer YES` or it silently never fires; and
# the query matches the seeded thing's own title ("Ring demo"), so the
# success pattern can demand a populated `Row(...)`. Searching a word the
# corpus doesn't contain would pass on "Nothing matches anymore." forever.
probe find 'findDoc\|.*Row\(' 30 \
  -seedThing "Bluesky:0" -openComposer YES -findProbe "Ring"

# Today brief: the whisper's landing screen, fully deterministic composition.
probe today 'todayProbe: landed=' 40 -todayProbe YES -probeDelay 4

# The Shortcuts/Siri grounding matcher — pure, local, and the one path a UI
# sweep can never reach. This asserts the matcher RUNS, not that it hits:
# `ProbeHooks` dispatches in list order and `intentProbe` sits above
# `seedThing` in that table, so the corpus is still empty when it fires and
# a hit count is not ours to demand from the script side.
probe intent 'Intent probe: [0-9]+ hits' 25 -intentProbe "Ring"

# ── 5. Live integrations (network — WARN-ONLY, never gates) ───────────────
# Same contract as scripts/live-integrations.sh: a third-party hiccup must
# never fail a build, and nothing here spends a metered credit. Every probe
# below is keyless by construction — the Alchemy-backed ones (-holdingsProbe,
# -portfolioProbe, -peerProbe, -approvalProbe, -prepareProbe) are deliberately
# absent, and adding one would put a bill on the nightly.
LIVE_SKIPPED=0
if [[ "${SKIP_LIVE:-0}" == "1" ]]; then
  # Recorded, not just printed. A skip is an operator's choice rather than a
  # failure, so it isn't a warning — but a ledger row that reads exactly like
  # a full pass while three checks never ran is the silent-coverage-gap this
  # repo bans everywhere else.
  LIVE_SKIPPED=1
  warn "live integrations skipped (SKIP_LIVE=1)"
else
  step "Live integrations (warn-only, keyless)"
  # A probe that ANSWERED is not a probe that SUCCEEDED: every hook here logs
  # its own honest miss ("FAILED", "handled=NO") rather than staying silent,
  # so matching the line alone would score an outage as green. Wait for the
  # line, then read it.
  live() {  # live <name> <line-regex> <timeout> <args...>
    local name="$1" pattern="$2" limit="$3"; shift 3
    local log="$OUT/live-$name.log"
    launch "$log" "$@"
    if ! wait_for "$log" "$pattern" "$limit"; then
      quit_app; warn "$name did not answer in ${limit}s (see $log)"
      WARNINGS+=("live: $name (no answer)"); return
    fi
    quit_app
    if grep -E "$pattern" "$log" | grep -Eq 'FAILED|handled=NO'; then
      warn "$name answered with an honest failure (see $log)"
      WARNINGS+=("live: $name (failed)")
    else
      ok "$name reachable"
    fi
  }
  # A real feed sync end to end: fetch → parse → land Things.
  live rss       'RSS probe:'      40 -rssFeed "https://hnrss.org/frontpage"
  # Link enrichment reading a page's own <head>.
  live linktitle 'LinkTitle probe:' 30 -linkTitleProbe "https://apple.com"
  # oEmbed: the allowlisted-host path that gives a saved link a real face.
  live oembed    'oembedProbe'      30 -oembedProbe "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
fi

# ── 6. Perf ────────────────────────────────────────────────────────────────
# One cold launch drives all three metrics, mirroring perf.sh's shape so the
# two platforms' numbers are gathered the same way. REPORTS, never gates.
# Seeded on purpose: against the empty scratch corpus the answer path
# short-circuits with nothing to retrieve and logged a meaningless 15ms
# (measured 2026-08-01) — a number that would have "improved" on any
# regression that broke retrieval. One seeded Thing makes the probe actually
# compose.
step "Perf pass"
PERFLOG="$OUT/perf-stream.log"
launch "$PERFLOG" -seedThing "Bluesky:0" -deeplink casberi://home \
  -answerProbe "what did I save about Ring" -probeDelay 5
sleep 3
MEM_MB="n/a"
PID=$(app_pid)
if [[ -n "$PID" ]]; then
  RSS_KB=$(ps -o rss= -p "$PID" 2>/dev/null | tr -d ' ')
  [[ "$RSS_KB" == <-> ]] && MEM_MB=$(( RSS_KB / 1024 ))
fi
wait_for "$PERFLOG" 'answerProbe\(.+\) [0-9]+ms' 60
quit_app

num() { grep -o '[0-9]\+ms' | grep -o '[0-9]\+' | head -1; }
LAUNCH_MS=$(grep 'launchTimer' "$PERFLOG" 2>/dev/null | num); : ${LAUNCH_MS:=n/a}
ANSWER_MS=$(grep 'answerProbe(' "$PERFLOG" 2>/dev/null | num); : ${ANSWER_MS:=n/a}

PREV_LAUNCH=n/a; PREV_MEM=n/a; PREV_ANSWER=n/a
if [[ -f "$HIST" ]]; then
  LAST=$(grep -v '^timestamp' "$HIST" | tail -1)
  if [[ -n "$LAST" ]]; then
    PREV_LAUNCH=$(echo "$LAST" | cut -d, -f2)
    PREV_MEM=$(echo "$LAST" | cut -d, -f3)
    PREV_ANSWER=$(echo "$LAST" | cut -d, -f4)
  fi
fi

typeset -a FLAGS
line() {  # line <name> <unit> <cur> <prev> <ceil> <ratio>
  local name=$1 unit=$2 cur=$3 prev=$4 ceil=$5 ratio=$6 msg
  if [[ "$cur" != <-> ]]; then
    FLAGS+=("$name not captured"); print -r -- "  $name: n/a (not captured)"; return
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
  print -r -- "Casberi Mac perf pass — $TS (build $SHA)"
  print -r -- "host: $(sw_vers -productName) $(sw_vers -productVersion) · $(uname -m)"
  print -r -- ""
  line "launch (init→ready)" "ms" "$LAUNCH_MS" "$PREV_LAUNCH" "$LAUNCH_CEIL" "$LAUNCH_RATIO"
  line "memory (RSS)"        "MB" "$MEM_MB"    "$PREV_MEM"    "$MEM_CEIL"    "$MEM_RATIO"
  line "answer (compose)"    "ms" "$ANSWER_MS" "$PREV_ANSWER" "$ANSWER_CEIL" "$ANSWER_RATIO"
  print -r -- ""
  # The span breakdown — the whole lesson of prd §257: a launch metric with no
  # breakdown tells you to panic, not what to do.
  if grep -q 'launchPerf' "$PERFLOG" 2>/dev/null; then
    print -r -- "launch spans (DEBUG markers, not gated):"
    grep -o 'timed=[^ ]* took=[0-9.]*ms' "$PERFLOG" | sort -u | while read -r span; do
      print -r -- "  ${span/ took=/  }"
    done
    for label in $(grep -o 'accum=[^ ]*' "$PERFLOG" | cut -d= -f2 | sort -u); do
      # -F is load-bearing: labels carry brackets (`feedList[All]`), which a
      # regex read as a character class — so the lookup silently matched
      # nothing and the row printed "  ms over  calls" (2026-08-01).
      last=$(grep -F "accum=$label " "$PERFLOG" | tail -1)
      calls=$(echo "$last" | grep -o 'calls=[0-9]*' | cut -d= -f2)
      total=$(echo "$last" | grep -o 'totalMs=[0-9.]*' | cut -d= -f2)
      print -r -- "  accum=$label  ${total}ms over ${calls} calls"
    done
    BUILDS=$(grep -c 'HEAVYBUILD' "$PERFLOG" 2>/dev/null || echo 0)
    if (( BUILDS > 0 )); then
      PAGES=$(grep -o 'HEAVYBUILD source=[^ ]*' "$PERFLOG" | cut -d= -f2 | sort -u | tr '\n' ' ')
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

[[ -f "$HIST" ]] || echo "timestamp,launch_ms,mem_mb,answer_ms,build_sha" > "$HIST"
echo "$TS,$LAUNCH_MS,$MEM_MB,$ANSWER_MS,$SHA" >> "$HIST"

# ── Cleanup ────────────────────────────────────────────────────────────────
# Scratch stores are per-PID and would otherwise accumulate one dir per launch
# forever inside the container.
# Best-effort only: this path is inside the TCC-protected app container, so
# under launchd the delete is denied and silently skipped. The scratch dirs
# live in the app's own tmp, which macOS reclaims on its own schedule, so an
# unattended run leaving them behind is untidy rather than unbounded.
rm -rf "$HOME/Library/Containers/com.casberi.app/Data/tmp"/casberi-scratch-* 2>/dev/null
quit_app

print -r -- ""
if (( ${#WARNINGS} )); then
  warn "${#WARNINGS} live-integration warning(s) — deterministic checks all passed"
fi
# One machine-readable line for nightly-mac.sh to parse. It exists because the
# wrapper's first cut counted "⚠" characters in the console and scored a clean
# run as PASS(5warn): the perf section prints ⚠ for its own REGRESSION/CEILING
# flags, which are REPORTED BY DESIGN and never gate anything. Conflating those
# with a real third-party outage is how a ledger becomes noise. Two counts,
# kept apart, named.
print -r -- "SUMMARY live_warnings=${#WARNINGS} perf_flags=${#FLAGS} live_skipped=$LIVE_SKIPPED"
ok "mac verify complete → $OUT"
exit 0
