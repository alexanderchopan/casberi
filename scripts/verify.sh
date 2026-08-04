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
"$ROOT/scripts/network-reach-audit.sh" --self-test >/dev/null \
  || fail "the network-reach audit's own self-test failed — the check is broken, not the code"
"$ROOT/scripts/network-reach-audit.sh" || fail "a network host isn't disclosed — see scripts/network-reach-audit.sh"
print -P "%F{green}✓ network-reach audit%f"

# Keeps every Keychain write device-only and non-syncing (prd §277). Static,
# no build. The failure it catches is invisible at runtime — a key stored with
# the wrong accessibility works perfectly and also rides an encrypted backup
# onto another device — so it can only ever be caught mechanically.
step "Keychain policy audit"
"$ROOT/scripts/keychain-audit.py" --self-test >/dev/null \
  || fail "the keychain audit's own self-test failed — the check is broken, not the code"
"$ROOT/scripts/keychain-audit.py" || fail "a keychain write isn't device-only — see the output above"
print -P "%F{green}✓ keychain audit%f"

# Keeps the receipts screen's coverage claim true (prd §277). A new bridge
# written with its own URLSession is invisible to the ledger, and the screen
# goes on implying it saw everything — which is exactly how the first version
# of this feature shipped.
step "Receipts coverage audit"
"$ROOT/scripts/receipts-coverage-audit.py" --self-test >/dev/null \
  || fail "the receipts audit's own self-test failed — the check is broken, not the code"
"$ROOT/scripts/receipts-coverage-audit.py" || fail "a network call isn't recorded — see the output above"
print -P "%F{green}✓ receipts coverage audit%f"

# Every stored `Thing` property has a CloudKit field (docs/cloudkit-deploy.md).
# A TestFlight/App Store build mirrors to PRODUCTION and CloudKit never
# auto-creates schema there, so an undeployed field doesn't fail loudly — plain
# notes keep syncing while every voice note, social post and screenshot fails
# its export forever. Found 25 fields behind on 2026-08-01, invisible for
# months. Static: it proves the model matches the checked-in snapshot, which
# makes the deploy impossible to FORGET; `--live production` is what proves it
# HAPPENED, and stays out of here because it needs network.
step "CloudKit schema audit"
"$ROOT/scripts/cloudkit-schema-audit.py" --self-test >/dev/null \
  || fail "the CloudKit schema audit's own self-test failed — the check is broken, not the code"
"$ROOT/scripts/cloudkit-schema-audit.py" || fail "a Thing property has no CloudKit field — see the output above"
print -P "%F{green}✓ cloudkit schema audit%f"

# The credential tripwire's fixtures (prd §277) — that the shipped patterns and
# thresholds still hide a recovery phrase and still leave an ordinary shopping
# list alone. Reads both out of the Swift source, so re-tuning a number here
# fails rather than silently changing what the app hides.
step "Secret-scan self-test"
"$ROOT/scripts/secret-scan-selftest.py" || fail "the credential tripwire changed behaviour — see the output above"
print -P "%F{green}✓ secret-scan self-test%f"

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

# Pure-logic self-test for the X work (prd §280). Static, no build, no
# network: the archive importer was authored against no real X archive, and
# its failure mode is a silent wrong answer — a misdated like, a file that
# parses to zero rows and reads as an empty account. Runs here with the rest
# of the static head so it's part of `verify.sh` rather than something to
# remember (the reach-audit lesson, 2026-07-31).
step "X pure-logic self-test"
"$ROOT/scripts/x-selftest.sh" >/dev/null \
  || fail "the X logic self-test failed — run scripts/x-selftest.sh"
print -P "%F{green}✓ x self-test%f"

# Pure-logic self-test for the Cloudflare DNS change detector (prd §296). Same
# reasoning as the X harness above: the bridge was authored against Cloudflare's
# published API reference with no token and no authenticated access, and every
# failure in `diffDNS` is a silent wrong answer that renders perfectly — a
# partial read reporting live records as deleted, a proxy flag flipped off
# passing as no change, a second change to a record deduping into the first.
step "Cloudflare pure-logic self-test"
"$ROOT/scripts/cloudflare-selftest.sh" >/dev/null \
  || fail "the Cloudflare logic self-test failed — run scripts/cloudflare-selftest.sh"
print -P "%F{green}✓ cloudflare self-test%f"

# Pure-logic self-test for the Stripe and PostHog room heads (prd §298). Neither
# bridge has ever run against a live account from this host, and every failure
# here is a silent wrong answer: a dispute due tomorrow placed at the far end of
# the rail, an overdue window sorted last, a metric that stopped firing ranked
# below a busy one.
step "Room-head pure-logic self-test"
"$ROOT/scripts/room-heads-selftest.sh" >/dev/null \
  || fail "the room-head logic self-test failed — run scripts/room-heads-selftest.sh"
print -P "%F{green}✓ room-head self-test%f"

# The design system's first mechanical check (prd §299). Every other rule in
# this file is enforced by a script; the design system was enforced by memory,
# which is how fourteen data drawings shipped with no entrance and how the
# app's two most-used entrances (`SettleIn`, `RowEntrance`) ignored Reduce
# Motion from the day they shipped. Neither is visible in a build or a
# screenshot.
step "Design-motion audit"
python3 "$ROOT/scripts/design-motion-audit.py" >/dev/null \
  || fail "the design-motion audit failed — run python3 scripts/design-motion-audit.py"
print -P "%F{green}✓ design-motion audit%f"

# Pure-logic self-test for the on-device-intelligence pass (prd §282). Static,
# no build, no network — and the ONLY automated check that pass can have: the
# simulator ships no on-device language model, so every model path there runs
# its unavailable branch and a sim sweep exercises none of them. What it covers
# is the deterministic logic around the model, where every failure is a silent
# wrong answer: a vector header off by a byte makes every cosine 0 (which reads
# as "no related things" forever), an accepted status-bar clock puts "9:41
# today" on nearly every screenshot's calendar hand-off, and a permissive
# grounding check turns §218's honesty rail off while still logging that it ran.
step "On-device pure-logic self-test"
"$ROOT/scripts/ondevice-selftest.sh" >/dev/null \
  || fail "the on-device logic self-test failed — run scripts/ondevice-selftest.sh"
print -P "%F{green}✓ on-device self-test%f"

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
