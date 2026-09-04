#!/bin/zsh
# The dock's drift guards (prd §591, 2026-09-03).
#
# The source strip moved from the top of the screen to the bottom edge, the
# agent bar took its leading seat, "All" joined the scrolling run and the bar's
# 0.45s hold was deleted. Every one of those is a two-file arrangement whose
# halves cannot see each other, and every failure renders as an app that works:
#
#   • The band drifting back to `.safeAreaInset(edge: .top)` is one word, and
#     the app is entirely usable afterwards — it is just the arrangement three
#     rulings were spent moving away from.
#   • The agent's seat is reserved by `MainSurface` and stood in by
#     `RootShell`, two files on two layers. Too small and the leading source
#     scrolls under the bar and becomes a room you can see and cannot tap
#     (the 2026-08-16 objection); too large and the dock opens with a hole.
#     A literal in either file drifts silently the moment the other moves.
#   • The bar pinned `.trailing` again puts it on the dock's far end, where it
#     covers the LAST chip instead of standing before the first — which looks
#     deliberate and is the same dead-source bug mirrored.
#   • "All" pinned again on the phone costs a visible chip AND renders twice,
#     since it is in `scrollingLabels` now.
#   • The hold coming back re-opens a three-round argument (§384 → §390 →
#     §550) about which of two destinations an invisible gesture should hide,
#     and a hold that reaches the agent while the panel ALSO offers it is two
#     doors to one room, one of them unmarked.
#
# A build cannot see any of it, no static audit covers it, and the screen sweep
# proves a screen painted rather than that it painted the right anatomy.
#
# Negative guards read a COMMENT-STRIPPED copy: all four files DOCUMENT this
# change by naming the very thing they must no longer do (the Obsidian/Cursor
# lesson, applied again here).
set -uo pipefail
ROOT="${0:A:h:h}"
cd "$ROOT" || exit 1
fail=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

MAIN="Casberi/Casberi/Shell/MainSurface.swift"
ROOTS="Casberi/Casberi/Shell/RootShell.swift"
CHIPS="Casberi/Casberi/Shell/SourceChips.swift"
BAR="Casberi/Casberi/Shell/AgentBar.swift"
DOCK="Casberi/Casberi/Design/DSDock.swift"
PANEL="Casberi/Casberi/Shell/DoorsStrip.swift"

for f in "$MAIN" "$ROOTS" "$CHIPS" "$BAR" "$DOCK" "$PANEL"; do
  [ -f "$f" ] || { echo "✗ $f not found"; exit 1; }
done

strip_comments() {
  # A character scanner, not a regex: a `//` inside a string literal must not
  # open a comment, and a line comment holding a `/*` must not open a block
  # that swallows the rest of the file (the hero-tint audit paid for that one).
  python3 - "$1" <<'PY'
import sys
src = open(sys.argv[1]).read()
out = []; i = 0; n = len(src)
while i < n:
    c = src[i]
    if c == '"':
        out.append(c); i += 1
        while i < n and src[i] != '"':
            if src[i] == '\\': out.append(src[i]); i += 1
            if i < n: out.append(src[i]); i += 1
        if i < n: out.append(src[i]); i += 1
        continue
    if c == '/' and i + 1 < n and src[i+1] == '/':
        while i < n and src[i] != '\n': i += 1
        continue
    if c == '/' and i + 1 < n and src[i+1] == '*':
        i += 2
        while i + 1 < n and not (src[i] == '*' and src[i+1] == '/'): i += 1
        i += 2
        continue
    out.append(c); i += 1
print(''.join(out))
PY
}
strip_comments "$MAIN"  > "$TMP/main.nc"
strip_comments "$ROOTS" > "$TMP/root.nc"
strip_comments "$CHIPS" > "$TMP/chips.nc"
strip_comments "$BAR"   > "$TMP/bar.nc"

# --- 1. the band is a BOTTOM inset -----------------------------------------
grep -q 'safeAreaInset(edge: .bottom, spacing: 0) { bandInset }' "$TMP/main.nc" \
  || { echo "✗ MainSurface no longer applies bandInset to the BOTTOM edge — the whole of §591"; \
       echo "  is that the app's primary navigation sits in the thumb zone."; fail=1; }
grep -q 'safeAreaInset(edge: .top, spacing: 0) { bandInset }' "$TMP/main.nc" \
  && { echo "✗ the band is back on the TOP edge."; fail=1; }

# --- 2. the seat is one number, read by both sides --------------------------
# The strip runs UNDER the bar and melts its chips out before the bar's edge —
# it does not start beside it. A `.padding(.leading, agentSeat)` drew the scroll
# view's clip as a flat vertical line against the bar's round glass.
grep -q 'DSDock.agentSeat' "$TMP/chips.nc" \
  || { echo "✗ SourceChips no longer measures its melt from DSDock.agentSeat — chips will"; \
       echo "  either collide with the agent bar or be cut off by a hard clip edge."; fail=1; }
grep -q 'padding(.leading, DSDock.agentSeat)' "$TMP/main.nc" \
  && { echo "✗ MainSurface pads the strip past the bar again — that draws the scroll view's"; \
       echo "  clip as a flat line against the bar's round glass instead of melting."; fail=1; }
grep -q 'static var agentSeat' "$DOCK" \
  || { echo "✗ DSDock.agentSeat is gone — the shared metric both layers read."; fail=1; }

# --- 3. the bar stands in the LEADING corner --------------------------------
grep -q 'VStack(alignment: .leading, spacing: DS.Space.s2)' "$TMP/root.nc" \
  || { echo "✗ the floating cluster is no longer leading-aligned — the bar would sit at the"; \
       echo "  dock's far end, covering the LAST chip instead of standing before the first."; fail=1; }
grep -q 'frame(maxWidth: .infinity, alignment: .leading)' "$TMP/root.nc" \
  || { echo "✗ the floating cluster no longer pins to the leading edge."; fail=1; }

# --- 4. "All" scrolls on the phone, and only on the phone -------------------
grep -q 'axis == .vertical ? labels.filter { $0 != "All" } : labels' "$TMP/chips.nc" \
  || { echo "✗ scrollingLabels no longer forks on axis — either \"All\" is pinned on the phone"; \
       echo "  again (costing a visible chip AND rendering it twice), or the RAIL lost its"; \
       echo "  pin, which renders \"All\" twice there instead."; fail=1; }

# --- 5. the hold is gone -----------------------------------------------------
grep -q 'LongPressGesture' "$TMP/bar.nc" \
  && { echo "✗ AgentBar grew a long press again — §591 deleted it because one control with"; \
       echo "  two destinations is what §384/§390/§550 spent three rounds arguing about, and"; \
       echo "  the agent is a labelled row in DoorsPanel now."; fail=1; }
grep -q 'heldForAgent\|consumeHold' "$TMP/bar.nc" \
  && { echo "✗ AgentBar still carries the hold's swallow-the-tap state."; fail=1; }

# --- 6. the panel offers the agent, and the tray is really gone -------------
# --- 6. the octopus is a FOLDER, not a tray ---------------------------------
grep -q 'chrome.openFolder == .doors' "$TMP/main.nc" \
  || { echo "✗ MainSurface no longer draws DoorsStrip from the open folder — the octopus"; \
       echo "  must open a row above the dock like every other chip, not a raised tray."; fail=1; }
grep -q 'onAgent:' "$PANEL" \
  || { echo "✗ DoorsStrip lost its agent door — with the hold deleted this is the bar's"; \
       echo "  ONLY route to the agent."; fail=1; }
for gone in SourcesTray SourcesOverlay DoorsPanel; do
  [ -f "Casberi/Casberi/Shell/$gone.swift" ] \
    && { echo "✗ $gone is back — the octopus opens a strip in the band, never a tray."; fail=1; }
done

# --- 7. a folder tap opens; it never moves the feed -------------------------
grep -q 'if CategoryFold.isCategory(label)' "$TMP/main.nc" \
  || { echo "✗ a category chip tap no longer branches on isCategory — it will call go(to:)"; \
       echo "  and switch the room, which is what a folder must not do."; fail=1; }
python3 - <<'GATE' || fail=1
import re, sys
src = open("Casberi/Casberi/Shell/MainSurface.swift", encoding="utf-8").read()
i = src.find("if CategoryFold.isCategory(label)")
if i < 0:
    sys.exit(0)
# The folder branch must RETURN before anything that writes the filter.
branch = src[i:i + 900]
end = branch.find("return")
if end < 0 or "go(to:" in branch[:end]:
    print("✗ the folder branch reaches go(to:) — tapping a folder would switch the room,")
    print("  which the §591 amendment forbids ('if you tap a folder on mac dock for")
    print("  example it doesn't switch what is on your screen').")
    sys.exit(1)
GATE

if [ $fail -eq 0 ]; then
  echo "✓ dock self-test"
else
  exit 1
fi
