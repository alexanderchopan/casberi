#!/bin/zsh
# Casberi deterministic verify: build → install → screen sweep → answer probe.
# Exit 0 = everything green. Screenshots land in scripts/output/<timestamp>/.
#
# Usage: scripts/verify.sh [--build-only]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DD="$HOME/Library/Developer/CasberiDD"          # NEVER build inside iCloud Drive (codesign xattr failure)
DEVICE="iPhone 17 Pro"
BUNDLE="com.casberi.app"
OUT="$ROOT/scripts/output/$(date +%Y%m%d-%H%M%S)"

step() { print -P "%F{cyan}▶ $1%f"; }
fail() { print -P "%F{red}✗ $1%f"; exit 1; }

# ── 0. Catalog sync (static, fast — fails before the slow build) ────
# Enforces BridgeCatalog.offers as the single source of truth for the app
# catalog, the website #catalog shelf, and the onboarding tiles. See the
# catalog-sync RULE in CLAUDE.md.
step "Catalog sync"
"$ROOT/scripts/catalog-sync.sh" || fail "catalog surfaces drifted — run scripts/catalog-sync.sh"
print -P "%F{green}✓ catalog sync%f"

# Keeps the "What this app reaches" registry complete (prd §205): every host
# the app calls must be disclosed in NetworkReach.swift or the explicit
# non-reach denylist — an undisclosed fetch host fails here.
step "Network-reach audit"
"$ROOT/scripts/network-reach-audit.sh" || fail "a network host isn't disclosed — see scripts/network-reach-audit.sh"
print -P "%F{green}✓ network-reach audit%f"

# The recurring "reads a dead Thing" crash class (builds 137/138/139/142/150 —
# five TestFlight-found crashes, one defect). The rule was written down and
# re-broken twice because memory was enforcing it; this makes it mechanical.
# `--self-test` runs first on purpose: a check that cannot fail proves nothing,
# so the audit demonstrates it catches each shape before it certifies the tree.
step "SwiftData liveness audit"
"$ROOT/scripts/swiftdata-liveness-audit.py" --self-test >/dev/null \
  || fail "the liveness audit's own self-test failed — the check is broken, not the code"
"$ROOT/scripts/swiftdata-liveness-audit.py" || fail "a Thing is read without a liveness guard — see the output above"
print -P "%F{green}✓ swiftdata liveness audit%f"

# ── 1. Build ────────────────────────────────────────────────────────
step "Building Casberi (derivedData: $DD)"
xcodebuild -project "$ROOT/Casberi/Casberi.xcodeproj" -scheme Casberi \
  -destination "platform=iOS Simulator,name=$DEVICE" \
  -derivedDataPath "$DD" build -quiet || fail "build failed"
print -P "%F{green}✓ build%f"

[[ "${1:-}" == "--build-only" ]] && exit 0

# ── 2. Boot sim + install ──────────────────────────────────────────
step "Booting $DEVICE"
xcrun simctl bootstatus "$DEVICE" -b >/dev/null 2>&1 || xcrun simctl boot "$DEVICE" 2>/dev/null || true
xcrun simctl bootstatus "$DEVICE" -b >/dev/null

APP="$DD/Build/Products/Debug-iphonesimulator/Casberi.app"
[[ -d "$APP" ]] || fail "app bundle not found at $APP"
xcrun simctl install "$DEVICE" "$APP" || fail "install failed"
print -P "%F{green}✓ installed%f"

mkdir -p "$OUT"

# ── 2.5 Cold-launch survival loop ───────────────────────────────────
# The first-frame stack-overflow class (CLAUDE.md: recurred 2026-07-10 /
# 07-13 / 07-15) is INTERMITTENT and worst on the first launch after
# `simctl install` — one green launch proves nothing. Reinstall + cold
# launch LAUNCH_CYCLES times (default 10, the confidence bar from the
# 07-10 fix) and require the first-frame marker (launchTimer, the same
# line perf.sh times) on every cycle. A cycle with no marker fails the
# run: pid dead = the crash class; pid alive = frozen before first frame
# (the 07-15 symptom). LAUNCH_CYCLES=0 skips (e.g. quick doc-only runs).
CYCLES=${LAUNCH_CYCLES:-10}
if (( CYCLES > 0 )); then
  step "Cold-launch survival ($CYCLES cycles)"
  SURV="$OUT/launch-survival.log"
  CRASHDIR="$HOME/Library/Logs/DiagnosticReports"
  IPS_BEFORE=$(find "$CRASHDIR" -maxdepth 1 -name 'Casberi-*.ips' 2>/dev/null | wc -l | tr -d ' ')
  # One stream for the whole loop; cycle i waits for the i-th marker line.
  xcrun simctl spawn "$DEVICE" log stream \
    --predicate 'process == "Casberi" AND eventMessage CONTAINS "launchTimer"' \
    --style compact > "$SURV" 2>/dev/null &
  SURVPID=$!
  sleep 1
  for (( i=1; i<=CYCLES; i++ )); do
    xcrun simctl terminate "$DEVICE" "$BUNDLE" 2>/dev/null || true
    xcrun simctl install "$DEVICE" "$APP" || { kill $SURVPID 2>/dev/null; fail "reinstall failed (cycle $i)"; }
    PID=$(xcrun simctl launch "$DEVICE" "$BUNDLE" -onboarded YES 2>/dev/null | awk -F': ' '{print $NF}')
    READY=""
    for (( t=0; t<15; t++ )); do
      sleep 1
      # Match the timing line, not log stream's predicate-echo header.
      (( $(grep -Ec 'launchTimer.*[0-9]+ms' "$SURV" 2>/dev/null || true) >= i )) && { READY=1; break; }
    done
    if [[ -z "$READY" ]]; then
      kill $SURVPID 2>/dev/null || true
      if [[ -n "${PID:-}" ]] && kill -0 "$PID" 2>/dev/null; then
        fail "cold-launch cycle $i: no first frame in 15s, pid $PID still alive — frozen at launch"
      else
        fail "cold-launch cycle $i: process died before first frame — the launch-crash class (check $CRASHDIR)"
      fi
    fi
  done
  kill $SURVPID 2>/dev/null || true
  IPS_AFTER=$(find "$CRASHDIR" -maxdepth 1 -name 'Casberi-*.ips' 2>/dev/null | wc -l | tr -d ' ')
  if (( IPS_AFTER > IPS_BEFORE )); then
    fail "cold-launch loop passed but $((IPS_AFTER - IPS_BEFORE)) new Casberi crash report(s) in $CRASHDIR"
  fi
  print -P "%F{green}✓ cold-launch survival ($CYCLES/$CYCLES)%f"
fi

# ── 3. Screen sweep via deeplink hook ───────────────────────────────
sweep() {  # sweep <name> <casberi-url>
  xcrun simctl terminate "$DEVICE" "$BUNDLE" 2>/dev/null || true
  # -onboarded YES skips first-launch onboarding so the sweep sees the real screens
  xcrun simctl launch "$DEVICE" "$BUNDLE" -onboarded YES -deeplink "$2" >/dev/null || fail "launch failed ($1)"
  sleep 4
  xcrun simctl io "$DEVICE" screenshot "$OUT/$1.png" >/dev/null || fail "screenshot failed ($1)"
  print -P "%F{green}✓ $1%f"
}
step "Screen sweep"
sweep home    "casberi://home"
sweep feed    "casberi://feed"
sweep apps    "casberi://account"

# ── 4. Answer-path probe (headless, logs to console) ────────────────
step "Answer probe"
xcrun simctl terminate "$DEVICE" "$BUNDLE" 2>/dev/null || true
# Stream the app's log DURING the probe (log show --last is unreliable for
# fresh lines); on-device inference can take ~15s cold, so give it 25.
xcrun simctl spawn "$DEVICE" log stream --predicate 'process == "Casberi" AND eventMessage CONTAINS "answerProbe"' \
  --style compact > "$OUT/answer-probe.log" 2>/dev/null &
LOGPID=$!
xcrun simctl launch "$DEVICE" "$BUNDLE" -onboarded YES -answerProbe "what did I save about work" -probeDelay 2 >/dev/null
for i in {1..25}; do
  sleep 1
  grep -q "answerProbe(" "$OUT/answer-probe.log" 2>/dev/null && break
done
xcrun simctl io "$DEVICE" screenshot "$OUT/answer-probe.png" >/dev/null
kill $LOGPID 2>/dev/null || true
if [[ -s "$OUT/answer-probe.log" ]]; then
  print -P "%F{green}✓ answer probe logged%f"
else
  print -P "%F{yellow}⚠ no probe log lines captured (model may be unavailable on this host) — check $OUT/answer-probe.png%f"
fi

xcrun simctl terminate "$DEVICE" "$BUNDLE" 2>/dev/null || true
print -P "%F{green}✓ verify complete → $OUT%f"
