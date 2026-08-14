#!/bin/zsh
# Mac App Store screen capture — the SAME eight screens the iPhone set shows,
# taken from the real Mac Catalyst app (2026-08-14).
#
# Why a script and not `screencapture`: the app renders its own key window via
# the DEBUG `-macSnapshot` hook, which needs no Screen Recording grant — the
# same reasoning `verify-mac.sh` records, and the launch/wait/copy plumbing
# here is deliberately that script's, not a second invention.
#
# Every launch passes `-storeScratch YES`. On the Mac a DEBUG build otherwise
# shares the REAL app-group container with the installed app, so without it a
# capture run pours the demo into your daily driver's corpus.
#
#   scripts/mac-appstore-capture.sh [outDir]
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${1:-design/launch-video/mac-shots-raw}"
DD="$HOME/Library/Developer/CasberiMacDD"
APP="$DD/Build/Products/Debug-maccatalyst/Casberi.app"
SNAPDIR="$HOME/Library/Group Containers/35428TQK3S.group.com.casberi.app/HarnessSnapshots"
LOGDIR="$(mktemp -d)"
mkdir -p "$OUT"

[[ -d "$APP" ]] || { echo "✗ no Mac app at $APP — build it first"; exit 1; }

quit_app() { osascript -e 'tell application "Casberi" to quit' >/dev/null 2>&1 || true; sleep 1; }

launch() {
  local logfile="$1"; shift
  quit_app
  : > "$logfile"
  open -n "$APP" --stderr "$logfile" --stdout /dev/null \
    --args -storeScratch YES -onboarded YES "$@" 2>/dev/null
}

wait_for() {
  local logfile="$1" pattern="$2" limit="$3" i
  for (( i=0; i<limit; i++ )); do
    sleep 1
    grep -Eq "$pattern" "$logfile" 2>/dev/null && return 0
  done
  return 1
}

# shot <name> <launch-args...> — capture one screen.
# The demo is entered on EVERY launch: `-storeScratch` gives each run a fresh
# empty store, so a screen shot without it photographs an empty room.
shot() {
  local name="$1"; shift
  local log="$LOGDIR/$name.log"
  launch "$log" -demoEnter YES "$@" -macSnapshot "$name" -snapshotDelay 16
  if ! wait_for "$log" "macSnapshot: wrote" 50; then
    quit_app; echo "  ✗ $name: no snapshot in 50s (see $log)"; return 1
  fi
  quit_app
  # A source room whose detail pane shows the newest thing in the WHOLE corpus
  # — a calendar event beside the Wallet balance — reads as a mismatch in a
  # store screenshot. Say so loudly rather than shipping it silently.
  if grep -q "openThing: no match" "$log" 2>/dev/null; then
    echo "  ⚠ $name: pane fell back to the newest thing (openThing prefix missed)"
  fi
  [[ -f "$SNAPDIR/$name.png" ]] || { echo "  ✗ $name: logged but no file"; return 1; }
  cp "$SNAPDIR/$name.png" "$OUT/$name.png"
  local bytes=$(stat -f%z "$OUT/$name.png" 2>/dev/null); : ${bytes:=0}
  (( bytes > 20000 )) || { echo "  ✗ $name: ${bytes}B — window painted nothing"; return 1; }
  echo "  ok $name (${bytes}B)"
}

# The eight the iPhone set shows, in its order.
#
# Every source room also names a thing for the detail pane. On the Mac the
# pane is always open, and left to itself it shows the newest thing in the
# whole corpus — which put a calendar event beside the Wallet balance in the
# first pass. `-openThingDelay` re-fetches after the demo has poured (the
# mount-time fetch runs before any of it lands).
#
# The catalog and the brief take no thing: both are full-window surfaces that
# own the pane themselves.
D=10
shot 0-catalog  -deeplink "casberi://account"
shot 1-brief    -deeplink "casberi://brief"
shot 2-wallet   -deeplink "casberi://feed/source/Wallet"   -openThing "Uniswap can spend" -openThingDelay $D
shot 3-photos   -deeplink "casberi://feed/source/Photos"   -openThing "Figma — spacing tokens" -openThingDelay $D
shot 4-social   -deeplink "casberi://feed/source/Snapchat" -openThing "Sam" -openThingDelay $D
shot 5-work     -deeplink "casberi://feed/source/Linear"   -openThing "CAS-412" -openThingDelay $D
shot 6-chats    -deeplink "casberi://feed/source/Claude"   -openThing "Reviewing" -openThingDelay $D
shot 7-posthog  -deeplink "casberi://feed/source/PostHog"  -openThing "signed_up" -openThingDelay $D

echo ""
echo "-> $OUT"
