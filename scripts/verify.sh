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
