#!/bin/zsh
# THE MOVE-DECK SWEEP (prd §1992, user 2026-11-26: "how do we make sure ALL
# of our move confirmations, receipts, etc follow same template. it seems
# like they drift"). Every Move deck opened over the poured demo, each in the
# states a launch hook reaches, shot, and laid side by side on ONE sheet
# (`sheet.png`) so a page that drifted from the rest is seen in one look.
# `move-deck-audit.py` keeps the code on the template; this is the eye's half.
#
# Shots only: it judges nothing and fails only when a deck did not open (its
# raise line never logged). Report-only in the nightly.
#
# Usage: scripts/move-deck-sweep.sh [--self-test]
#   MOVE_DECKS="pools-send,earn"   narrows the run to those targets.
#   MOVE_DECKS_DEVICE=<udid>       runs on that simulator (default: verify's).
# Output: scripts/output/move-decks-<ts>/ — one png and log per target,
#   sheet.png, report.txt.
#
# STATED CEILINGS: every deck is shot at its first screen only, never
# failed or going (no hook reaches those on the demo: Privacy Pools' send
# cannot be held there); Tacit's two sheets have no launch hook.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# name · the line its raise logs · launch args
TARGETS=(
  "send|openMove: raised|-openMove YES -moveSendDraft 20|0x8ba1f109551bd432803012645ac136ddd64dba72|USDC@Base"
  "pools-in|movePrivately: raised deposit|-moveToPrivate YES"
  "pools-send|movePrivately: raised send|-movePrivateSend YES -privateMoneySample YES -movePrivateTo 0x8ba1f109551bd432803012645ac136ddd64dba72"
  "railgun-in|moveRailgun: raised in|-moveRailgun in"
  "railgun-send|moveRailgun: raised send|-moveRailgun send"
  "railgun-swap|moveRailgun: raised swap|-moveRailgun swap"
  "aztec-in|moveAztec: raised deposit|-moveToAztec YES"
  "aztec-send|moveAztec: raised send|-moveToAztec send"
  "earn|moveLend: raised lend|-moveLend lend"
  "earn-olla|ollaOpen: lend|-ollaSample YES -ollaOpen lend"
)

# A target's fields: the args are everything after the second "|", and may
# hold "|" themselves (Send's draft).
split() { print -r -- "${1%%|*}"; local rest=${1#*|}; print -r -- "${rest%%|*}"; print -r -- "${rest#*|}"; }

if [[ "${1:-}" == --self-test ]]; then
  bad=0
  parts=("${(@f)$(split "send|openMove: raised|-openMove YES -moveSendDraft 20|0xabc|USDC@Base")}")
  [[ ${parts[1]} == send && ${parts[2]} == "openMove: raised" && ${parts[3]} == "-openMove YES -moveSendDraft 20|0xabc|USDC@Base" ]] \
    && print "  ✓ a target's args keep their own bars" || { print "  ✗ split: ${parts[*]}"; bad=1; }
  # Every hook a target names is one the app reads.
  for t in "${TARGETS[@]}"; do
    a=("${(@f)$(split "$t")}")
    for flag in ${(z)a[3]}; do
      [[ $flag == -* ]] || continue
      k=${flag#-}
      grep -rqE "\"$k\"" "$ROOT/Casberi/Casberi" || { print "  ✗ ${a[1]}: the app reads no -$k"; bad=1; }
    done
  done
  (( bad == 0 )) && print "  ✓ every target's hooks are read by the app"
  print "move-deck-sweep self-test: $([[ $bad == 0 ]] && print OK || print FAILED)"
  exit $bad
fi

zsh "$0" --self-test >/dev/null || { print -P "%F{red}✗ the sweep's own self-test failed — the check is broken, not the app%f"; exit 1; }

OUT="$ROOT/scripts/output/move-decks-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"
BUNDLE="com.casberi.app"
DD="$HOME/Library/Developer/Xcode/DerivedData/CasberiMoveDecks"
DEV="${MOVE_DECKS_DEVICE:-$(python3 "$ROOT/scripts/sim-device.py" "iPhone 17 Pro")}" || {
  print -P "%F{red}✗ could not resolve a simulator%f"; exit 1; }
WAIT="${MOVE_DECKS_WAIT:-12}"

if [[ -n "${MOVE_DECKS:-}" ]]; then
  typeset -a keep; keep=("${(@s:,:)MOVE_DECKS}")
  TARGETS=(${(M)TARGETS:#(${(j:|:)~keep})\|*})
fi
print -r -- "move-decks: ${#TARGETS} decks on $DEV"

"$ROOT/scripts/xcb.sh" -project "$ROOT/Casberi/Casberi.xcodeproj" -scheme Casberi \
  -destination "id=$DEV" -derivedDataPath "$DD" build > "$OUT/xcodebuild.log" 2>&1
print -r -- "XCODEBUILD_EXIT=$?" >> "$OUT/xcodebuild.log"
grep -q "XCODEBUILD_EXIT=0" "$OUT/xcodebuild.log" || { print -P "%F{red}✗ build failed — $OUT/xcodebuild.log%f"; exit 1; }
APP="$DD/Build/Products/Debug-iphonesimulator/Casberi.app"

xcrun simctl boot "$DEV" 2>/dev/null; xcrun simctl bootstatus "$DEV" -b >/dev/null
xcrun simctl terminate "$DEV" "$BUNDLE" 2>/dev/null
xcrun simctl install "$DEV" "$APP" || { print -P "%F{red}✗ install failed%f"; exit 1; }
for p in photos calendar reminders contacts; do xcrun simctl privacy "$DEV" grant "$p" "$BUNDLE" 2>/dev/null; done
# A fresh pour: the decks draw the demo's money.
xcrun simctl launch "$DEV" "$BUNDLE" -onboarded YES -demoExit 4 >/dev/null; sleep 10
xcrun simctl terminate "$DEV" "$BUNDLE" 2>/dev/null
xcrun simctl launch "$DEV" "$BUNDLE" -onboarded YES -demoEnter YES -demo.corpusAllowed NO >/dev/null; sleep 30
xcrun simctl terminate "$DEV" "$BUNDLE" 2>/dev/null

: > "$OUT/results.tsv"
for t in "${TARGETS[@]}"; do
  a=("${(@f)$(split "$t")}")
  name=${a[1]}; raised=${a[2]}
  args=(${(z)a[3]})
  xcrun simctl terminate "$DEV" "$BUNDLE" 2>/dev/null
  xcrun simctl launch --console-pty "$DEV" "$BUNDLE" -onboarded YES -hideDemoBanner YES -theme.light NO \
    "${args[@]}" > "$OUT/$name.log" 2>&1 &
  pid=$!
  sleep "$WAIT"
  xcrun simctl io "$DEV" screenshot "$OUT/$name.png" >/dev/null 2>&1
  xcrun simctl terminate "$DEV" "$BUNDLE" 2>/dev/null
  kill $pid 2>/dev/null; wait $pid 2>/dev/null
  if grep -aq -- "$raised" "$OUT/$name.log"; then
    print -r -- "$name	ok" >> "$OUT/results.tsv"
  else
    print -r -- "$name	fail	its raise line ($raised) never logged" >> "$OUT/results.tsv"
  fi
done

# One sheet, the decks in a row, each named under its shot.
python3 - "$OUT" <<'EOF'
import sys
from pathlib import Path
from PIL import Image, ImageDraw
out = Path(sys.argv[1])
rows = [l.split("\t") for l in (out / "results.tsv").read_text().splitlines() if l]
shots = [(r[0], out / f"{r[0]}.png") for r in rows if (out / f"{r[0]}.png").exists()]
if not shots:
    sys.exit("move-decks: no shots")
w = 390
imgs = []
for name, p in shots:
    im = Image.open(p).convert("RGB")
    imgs.append((name, im.resize((w, int(im.height * w / im.width)))))
h = max(i.height for _, i in imgs)
per = 6
lines = (len(imgs) + per - 1) // per
sheet = Image.new("RGB", (per * (w + 16) + 16, lines * (h + 48) + 16), (24, 24, 24))
d = ImageDraw.Draw(sheet)
for n, (name, im) in enumerate(imgs):
    x = 16 + (n % per) * (w + 16)
    y = 16 + (n // per) * (h + 48)
    sheet.paste(im, (x, y))
    d.text((x, y + h + 8), name, fill=(230, 230, 230))
sheet.save(out / "sheet.png")
EOF

FAILS=$(awk -F'\t' '$2=="fail"' "$OUT/results.tsv" | wc -l | tr -d ' ')
{
  print -r -- "${#TARGETS} decks · $FAILS did not open · sheet: ${OUT#$ROOT/}/sheet.png"
  awk -F'\t' '$2=="fail" { printf "✗ %s — %s\n", $1, $3 }' "$OUT/results.tsv"
} > "$OUT/report.txt"
cat "$OUT/report.txt"
xcrun simctl terminate "$DEV" "$BUNDLE" 2>/dev/null
(( FAILS == 0 ))
