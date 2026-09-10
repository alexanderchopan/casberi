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
grep -q 'static func agentSeat' "$DOCK" \
  || { echo "✗ DSDock.agentSeat is gone — the shared metric both layers read."; fail=1; }
# The bar's mark is the SAME SIZE as a chip's (§591d). `DSDock.agentSize`
# mirrors `SourceChips.iconSize`, which is private to that view and cannot be
# read from the design layer — so the two are pinned here instead, in both
# states. A 44 among 46s reads as a shrunken chip rather than a distinction,
# and a bar that did not fold would grow relatively larger exactly when the row
# got tighter.
# THE FOLD IS CONTINUOUS (2026-09-05): the strip's mark size is READ off
# DSDock's fold form rather than mirrored as a literal, so the chips and the
# bar cannot be different sizes at any point of the travel.
grep -q 'iconSize: CGFloat { DSDock.agentSize(fold: fold) }' "$TMP/chips.nc" \
  || { echo "✗ SourceChips.iconSize no longer reads DSDock.agentSize(fold:) — the strip's"; \
       echo "  marks and the agent bar beside them can drift apart mid-fold."; fail=1; }
grep -q 'static func agentSize(fold: CGFloat)' "$DOCK" \
  || { echo "✗ DSDock.agentSize lost its fold form — the continuous fold has no metric."; fail=1; }
grep -q 'DSDock.agentSize(fold: chrome.fold)' "$TMP/bar.nc" \
  || { echo "✗ AgentBar no longer sizes itself off ShellChrome.fold — it would jump 46→40"; \
       echo "  while the chips beside it slide, or RootShell would re-render per scroll tick."; fail=1; }
grep -q 'DSDock.SeatInset()' "$TMP/root.nc" \
  || { echo "✗ RootShell no longer seats the bar through DSDock.SeatInset — the bar's"; \
       echo "  bottom inset would stop following the fold, or the shell body would read it."; fail=1; }
grep -q 'DSDock.SlabInset()' "$TMP/main.nc" \
  || { echo "✗ MainSurface no longer pads the slab through DSDock.SlabInset — the slab's air"; \
       echo "  would stop following the fold, or this surface would read it per tick."; fail=1; }
strip_comments "Casberi/Casberi/Shell/ShellChrome.swift" > "$TMP/chrome.nc"
grep -q 'func trackFold' "$TMP/chrome.nc" && grep -q 'func settleFold' "$TMP/chrome.nc" \
  || { echo "✗ ShellChrome lost trackFold/settleFold — the fold is a direction flip again."; fail=1; }
grep -q 'chrome.minimized = down' "$TMP/chrome.nc" \
  && { echo "✗ minimizesChrome writes the boolean from scroll DIRECTION again — the dock"; \
       echo "  would blink on a reversed scroll instead of following the finger."; fail=1; }
grep -q 'onScrollPhaseChange' "$TMP/chrome.nc" \
  || { echo "✗ minimizesChrome no longer settles the fold when the scroll goes idle — a slow"; \
       echo "  drag could leave the dock half-folded forever."; fail=1; }
# THE PAGE FOLLOWS THE FINGER (2026-09-05).
strip_comments "Casberi/Casberi/Shell/PageSwipeCatcher.swift" > "$TMP/pan.nc"
grep -q 'override func touchesMoved' "$TMP/pan.nc" \
  || { echo "✗ PageSwipeCatcher no longer reports the finger's moves — the room fires on"; \
       echo "  release again instead of following the drag."; fail=1; }
grep -q 'struct PagerDrag' "$TMP/main.nc" \
  || { echo "✗ MainSurface lost PagerDrag — the room does not follow the finger, or the"; \
       echo "  offset is read in MainSurface's own body (a re-render per touch move)."; fail=1; }
grep -q 'chrome.pageDragX = 0' "$TMP/main.nc" \
  || { echo "✗ go(to:) no longer resets the drag in the committing transaction — the incoming"; \
       echo "  room would mount offset by the last finger position."; fail=1; }
# A TAP LANDS NOW; ONLY A SWIPE FLIES (prd §671, 2026-09-10, user: "tapping
# icons has a lag"). §651 pass 2 sent every route through deal(to:), so a chip
# tap showed its room ~530ms after the touch. The swipe's step is the one call
# that passes fly: true; the strip's tap path reaches go(to: label) bare and
# lands on the slide through cut(to:).
[ "$(grep -c 'go(to: target, fly: true)' "$TMP/main.nc")" -eq 1 ] \
  || { echo "✗ step(_:) no longer flies alone — either a second route deals a card again"; \
       echo "  (a tap would lag ~530ms, prd §671) or the swipe lost its flight (prd §651)."; fail=1; }
grep -q 'if fly { deal(to: target) } else { cut(to: target) }' "$TMP/main.nc" \
  || { echo "✗ go(to:) no longer forks on fly — a tap and a swipe take the same landing (prd §671)."; fail=1; }
[ "$(grep -c 'deal(to: ' "$TMP/main.nc")" -eq 1 ] \
  || { echo "✗ deal(to:) is reached from somewhere other than go(to:)'s fly branch (prd §671)."; fail=1; }
awk '/private func cut\(to target/,/^    }$/' "$TMP/main.nc" | grep -q 'swipeCommit = false' \
  || { echo "✗ cut(to:) no longer clears swipeCommit — the tap's room would insert as .identity,"; \
       echo "  a cut with no cover, instead of the slide (prd §671)."; fail=1; }
# THE CARD IS KEYED TO THE TURN, NOT TO THE SCREEN (prd §648, 2026-09-08).
# Every card signal in `PagerDrag` — corner, lit edge, scale, tilt, shadow —
# used to be scaled by `abs(x) / pagerFrame.width`, the fraction of the SCREEN
# crossed. A turn commits at 60pt, which on a 393pt screen is 0.153, so at the
# moment the page turned the tilt was 0.61° and the shadow was black at 0.076
# on a black page: the whole vocabulary was there and keyed to a distance the
# gesture never reaches. Reported as "the rooms don't seem to be moving like a
# card when you swipe". `pageDragProgress` reaches 1 at 66pt and `PagerCover`
# already read it, so the two halves of one carousel were on two ramps — that
# disagreement is the finding, and this is what stops it recurring. Nothing
# else can see it: the build is clean, the app turns pages perfectly, and a
# screenshot cannot photograph a ramp.
grep -q 'let lift = reduceMotion ? 0 : min(1, abs(chrome.pageDragProgress))' "$TMP/main.nc" \
  || { echo "✗ PagerDrag no longer keys the card to the drag's COMMIT PROGRESS — if it is"; \
       echo "  back on a fraction of the screen width, the card reaches 15% of every signal"; \
       echo "  at the moment the page turns and reads as a plain slide (§648)."; fail=1; }
grep -q 'heading \* 4 \* lift' "$TMP/main.nc" \
  || { echo "✗ the tilt is no longer on the same ramp as the rest of the card — §632's 4° is"; \
       echo "  the ruling, and it is only reached if it rides the turn."; fail=1; }
grep -q 'abs(x) / width' "$TMP/main.nc" \
  && { echo "✗ the screen-width share is back in PagerDrag — that is the §648 defect itself."; fail=1; }
grep -q 'let p = min(1, abs(chrome.pageDragProgress))' "$TMP/main.nc" \
  || { echo "✗ PagerCover no longer runs on the drag's progress — the two halves of the"; \
       echo "  carousel would disagree about when a turn is a turn, which is §648's cause."; fail=1; }
# THE BAND'S SCRIM RAMPS OVER A FIXED LENGTH, NOT A FRACTION OF ITSELF (prd
# §649 amendment, 2026-09-08). The mask was `location: 0.25` — a quarter of the
# band's OWN height — so the softness grew with the number of rows stacked in
# it. Measured off the report's screenshot: a three-row Social band is 218pt, so
# the quarter was a 54pt ramp that covered the whole first control row and let a
# line of feed text read between the strips. `DS.Space.s6` is not a chosen
# number — it is what the fraction already yields for the 96pt dock-only band,
# so the case the old rule got right is unchanged. A fraction coming back is the
# defect itself, and nothing else here can see it: the band paints, the app
# works, and only a screenshot of a THREE-row room shows it.
grep -q 'location: 0.25' "$TMP/main.nc" \
  && { echo "✗ the band's scrim is back on a FRACTION of its own height — a stacked band"; \
       echo "  goes see-through in proportion to how much it holds (§649 amendment)."; fail=1; }
grep -q 'frame(height: DS.Space.s6)' "$TMP/main.nc" \
  || { echo "✗ the band's scrim lost its fixed-length ramp — either it is a fraction again"; \
       echo "  or the soft edge where the band meets the feed is gone entirely, and that"; \
       echo "  edge is the whole of the 2026-08-23 airiness ruling."; fail=1; }
# THE LEAN MOVED INTO ITS OWN LEAF (2026-09-06, prd §632 second amendment) —
# THE SELECTION TRAVELS ON A GLIDE AND NEVER LEANS (prd §667). `ChipLean` —
# the fill drifting toward the neighbour under a drag and snapping back on
# landing, its travel on whatever bouncy spring the change came in — is
# DELETED. One object (`SelectionTravel`) carries both the word chips' fill and
# the mark chips' ring, pins its transaction to `DS.Motion.glide` (bounce 0),
# and reads NO drag state, so nothing in the strip rebuilds per touch move.
grep -q 'struct SelectionTravel' "$TMP/chips.nc" \
  || { echo "✗ SelectionTravel is gone — the selection has no single object to travel as."; fail=1; }
[ "$(grep -c 'SelectionTravel(ns: ' "$TMP/chips.nc")" -ge 2 ] \
  || { echo "✗ the fill and the ring no longer both travel through SelectionTravel."; fail=1; }
grep -q 't.animation = DS.Motion.glide' "$TMP/chips.nc" \
  || { echo "✗ the selection's travel is no longer pinned to DS.Motion.glide — it would ride a"; \
       echo "  tap's folder spring or a landing's standard spring and overshoot the tile (prd §667)."; fail=1; }
# …AND ONLY AN ANIMATED CHANGE IS RE-PINNED (prd §670). §667's first cut rewrote
# EVERY transaction reaching the shape, the fold's un-animated per-frame write
# included, so the fill and the ring were re-sprung on every scroll frame and
# trailed their tile by up to 0.28s while the dock folded. A nil animation
# must stay nil.
grep -q 'if t.animation != nil { t.animation = DS.Motion.glide }' "$TMP/chips.nc" \
  || { echo "✗ SelectionTravel no longer guards its glide on t.animation != nil — the fold's"; \
       echo "  un-animated per-frame write would re-spring the selection every frame (prd §670)."; fail=1; }
grep -q '\$0.animation = DS.Motion.glide' "$TMP/chips.nc" \
  && { echo "✗ the unconditional transaction rewrite is back on the selection (prd §670)."; fail=1; }
# THE STRIP'S BODY DOES NOT READ THE BRIDGE STORE (prd §670). `bridges.bridges`
# is written twice per landing sync; a read in `chip(_:)` rebuilt all eleven
# chips per write. The broken-seat ring and the spoken label are leaves.
awk '/private func chip\(_ label:/,/fileprivate static func chipAccessibilityLabel/' "$TMP/chips.nc" \
  | grep -q 'bridges\.bridges' \
  && { echo "✗ chip(_:) reads bridges.bridges again — every bridge write rebuilds the strip (prd §670)."; fail=1; }
grep -q 'struct ChipAttentionRing' "$TMP/chips.nc" && grep -q 'struct ChipSpokenLabel' "$TMP/chips.nc" \
  || { echo "✗ the broken-seat ring or the spoken label is no longer a leaf (prd §670)."; fail=1; }
[ "$(grep -c 'chipAccessibilityLabel(' "$TMP/chips.nc")" -eq 2 ] \
  || { echo "✗ chipAccessibilityLabel is called from more than one place — it was built twice"; \
       echo "  per chip per body, once for a modifier that is inert on a phone (prd §670)."; fail=1; }
grep -qE 'ChipLean|leanPitch|pageDragProgress' "$TMP/chips.nc" \
  && { echo "✗ the lean is back in the strip — the indicator moves forward under a drag and"; \
       echo "  swings back on landing (prd §667), and every chip rebuilds per touch move."; fail=1; }
# SCRUB TO PICK (2026-09-05; SwiftUI's own sequence since 2026-09-09, prd §660).
# The UIKit catcher is DELETED and must stay deleted: it was attached to
# SwiftUI's private hosting scroll view by walking superviews and delivered
# from an overridden `state` setter, and it never once began on the user's
# phone ("i've never been able to scrub it on my device").
[ -f "Casberi/Casberi/Shell/DockScrubCatcher.swift" ] \
  && { echo "✗ the UIKit scrub catcher is back — it never fired on a device (prd §660)."; fail=1; }
# THE SCRUB IS DELETED (prd §662h, user: "kill it"). A hold-then-slide on a
# screen with no pointer was a hidden gesture nobody would find; in its
# sequenced form it FROZE THE STRIP'S SCROLL DEAD (§662g, measured on build
# 543), and its UIKit form cost the day. NOTHING in the strip may claim a
# touch: no SwiftUI drag or press, no UIKit recognizer, no scroll freeze. The
# wave stays for the POINTER (iPad, Mac) — the Mac dock's own case.
grep -qE 'DragGesture\(|LongPressGesture\(|sequenced\(before|UIGestureRecognizerRepresentable|UILongPressGestureRecognizer|scrollDisabled\(' "$TMP/chips.nc" \
  && { echo "✗ a finger gesture or a scroll freeze is back inside the dock's strip — the scrub is"; \
       echo "  DELETED (prd §662h); a drag on scroll content freezes the scroll (§662g)."; fail=1; }
grep -qE 'scrubbing|scrubX|scrubBegan|DockHold' "$TMP/chips.nc" \
  && { echo "✗ scrub state is back in SourceChips — deleted with the gesture (prd §662h)."; fail=1; }
grep -q 'guard let x = hoverX else { return 1 }' "$TMP/chips.nc" \
  || { echo "✗ the wave no longer rides the POINTER alone — it is the Mac dock's magnification"; \
       echo "  under a cursor, kept when the finger's scrub went (prd §662h)."; fail=1; }
# THE WAVE IS A TRANSFORM, AND IT DOES NOT RIDE A SCROLL (prd §660).
# Layout magnification changed the scroll's content size under a decelerating
# flick, which is the "doesn't scroll properly" half of the report; and a wave
# parked in viewport space rebuilt the strip once per frame for the length of
# every flick while magnifying nothing a finger could see.
grep -q 'scaleEffect(m, anchor: .bottom)' "$TMP/chips.nc" \
  || { echo "✗ the dock's magnification is layout again — it would resize the scroll's content"; \
       echo "  under a running deceleration (prd §660)."; fail=1; }
grep -qE 'waveViewportX|waveTick|waveReaches' "$TMP/chips.nc" \
  && { echo "✗ the parked magnifier is back — a strip rebuild per frame for the length of"; \
       echo "  every flick, magnifying nothing the finger is over (prd §660)."; fail=1; }
# FLAT CHIPS ON THE SLAB'S GLASS (prd §660). Eleven interactive glass elements
# in a GlassEffectContainer, inside the dock's own glass slab, inside a scroll
# view — glass on glass on scrolling content, which is what the strip cost.
awk '/private func chip\(_ label:/,/private func chipAccessibilityLabel/' "$TMP/chips.nc" \
  | grep -q 'dsGlass(' \
  && { echo "✗ a dock chip wears its own glass again — the SLAB is the glass and the chips"; \
       echo "  are ink on it (prd §660)."; fail=1; }
grep -q 'DSGlassContainer(spacing: Self.chipGap)' "$TMP/chips.nc" \
  && { echo "✗ the chip run is back inside a GlassEffectContainer — glass on glass."; fail=1; }
grep -q 'mask { stripMelt }' "$TMP/chips.nc" \
  && { echo "✗ the melt is a viewport mask again — it exists only to reach hoisted glass,"; \
       echo "  which flat chips do not have, and it renders the strip offscreen."; fail=1; }
grep -q 'visualEffect { content, proxy in' "$TMP/chips.nc" \
  || { echo "✗ the melt is gone — chips would hit the agent bar as a hard line."; fail=1; }
grep -q 'enabled: axis == .vertical && label != "All"' "$TMP/chips.nc" \
  || { echo "✗ the chip peek is back on the phone strip, where the scrub's press cancels it"; \
       echo "  before it can fire — a modifier that never fires, left claiming."; fail=1; }
grep -q 'minimized ? 40 : 46' "$DOCK" \
  || { echo "✗ DSDock.agentSize no longer matches SourceChips.iconSize (46 at rest, 40"; \
       echo "  folded) — the bar and the chip marks beside it are different sizes."; fail=1; }

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
# THE FOLDER SPRINGS UP (2026-09-05, the Mac-dock folder): the doors rise out
# of the octopus as a row ABOVE the dock (`DockSpringRow` in MainSurface's
# band), anchored to the bar, and the strip draws no folder of its own.
grep -q 'chrome.openFolder == .doors' "$TMP/main.nc" \
  || { echo "✗ MainSurface no longer springs the doors from the open folder — the octopus"; \
       echo "  must open a row out of the bar like every other chip, not a raised tray."; fail=1; }
grep -q 'DockSpringRow(' "$TMP/main.nc" \
  || { echo "✗ MainSurface no longer uses DockSpringRow — the folder does not spring out of"; \
       echo "  its chip, which is the whole of the Mac-dock ruling."; fail=1; }
[ -f "Casberi/Casberi/Shell/DockFolderRow.swift" ] \
  || { echo "✗ DockFolderRow.swift is gone — the springing folder has no row."; fail=1; }
grep -q 'chrome.openFolder == .doors' "$TMP/chips.nc" \
  && { echo "✗ SourceChips draws the doors IN the strip again — the folder opens above the"; \
       echo "  dock now, out of its chip; in-place spent width the row does not have."; fail=1; }
grep -q 'onAgent:' "$PANEL" \
  || { echo "✗ DoorsStrip lost its agent door — with the hold deleted this is the bar's"; \
       echo "  ONLY route to the agent."; fail=1; }
for gone in SourcesTray SourcesOverlay DoorsPanel; do
  [ -f "Casberi/Casberi/Shell/$gone.swift" ] \
    && { echo "✗ $gone is back — the octopus opens a strip in the band, never a tray."; fail=1; }
done

# --- 7. a folder tap LANDS and opens; the standing chip only toggles ---------
# prd §663 (2026-09-09) overturned the §591 amendment this guard used to pin
# ("a folder tap doesn't switch what is on your screen"): a tap that changes
# nothing on screen is a two-tap navigation, and the strip is the app's tab
# bar. So the folder branch MUST reach go(to:) — but only for ANOTHER
# category's chip; the chip of the category you are standing in toggles its
# folder and moves nothing, or a re-tap would re-land you where you are.
grep -q 'if CategoryFold.isCategory(label)' "$TMP/main.nc" \
  || { echo "✗ a category chip tap no longer branches on isCategory — the folder would"; \
       echo "  never spring, and the landing (prd §663) would be a bare source switch."; fail=1; }
python3 - <<'GATE' || fail=1
import sys
src = open("Casberi/Casberi/Shell/MainSurface.swift", encoding="utf-8").read()
i = src.find("if CategoryFold.isCategory(label)")
if i < 0:
    sys.exit(0)
branch = src[i:i + 1400]
end = branch.find("return")
body = branch[:end] if end > 0 else branch
if "chrome.openFolder = opening ? .category(label) : nil" not in body:
    print("✗ the folder no longer springs on a category tap (prd §663 keeps the folder).")
    sys.exit(1)
if "if !standingHere" not in body or "go(to: label)" not in body:
    print("✗ a category tap no longer LANDS in the room behind `if !standingHere` —")
    print("  prd §663: another category's chip goes there; the standing chip only toggles.")
    sys.exit(1)
if body.find("go(to: label)") < body.find("if !standingHere"):
    print("✗ go(to:) runs before the standing-here guard — re-tapping the chip of the")
    print("  room you are in would re-land you there (prd §663).")
    sys.exit(1)
GATE

# --- 8. the inclusion pass (2026-09-06, prd §630) ------------------------------
# Every glass surface honours Reduce Transparency, through the token — so a raw
# material anywhere else is a surface the setting cannot reach.
strip_comments "Casberi/Casberi/Design/Glass.swift" > "$TMP/glass.nc"
strip_comments "Casberi/Casberi/Design/DSTray.swift" > "$TMP/tray.nc"
[ "$(grep -c 'accessibilityReduceTransparency' "$TMP/glass.nc")" -ge 3 ] \
  || { echo "✗ Glass.swift no longer reads accessibilityReduceTransparency on each of"; \
       echo "  dsGlass / dsGlassProminent / dsGlassBlob — a glass surface the setting can't reach."; fail=1; }
grep -q 'accessibilityReduceTransparency' "$TMP/tray.nc" \
  || { echo "✗ DSTray's pane no longer goes opaque under Reduce Transparency."; fail=1; }
grep -q 'func dsOpaqueGlass' "$TMP/glass.nc" \
  || { echo "✗ dsOpaqueGlass is gone — the opaque form of glass has no one recipe."; fail=1; }
# Comment-stripped, because two files DOCUMENT a material they no longer draw.
raw=""
for f in $(grep -rl 'Material' Casberi/Casberi Casberi/Shared --include='*.swift' 2>/dev/null \
           | grep -v 'Design/Glass.swift\|Design/DSTray.swift'); do
  strip_comments "$f" | grep -q '\.regularMaterial\|\.ultraThinMaterial\|\.thinMaterial\|\.thickMaterial' \
    && raw="$raw $f"
done
[ -z "$raw" ] \
  || { echo "✗ a raw material outside Glass.swift/DSTray.swift — route it through dsGlass so"; \
       echo "  Reduce Transparency reaches it: $raw"; fail=1; }
# Money says its direction without colour: the pill's glyph and the down line's dash.
strip_comments "Casberi/Casberi/Design/TokenChartView.swift" > "$TMP/chart.nc"
grep -q 'static func directionGlyph' "$TMP/chart.nc" && grep -q 'static func lineDash' "$TMP/chart.nc" \
  || { echo "✗ TokenChartStyle lost directionGlyph/lineDash — Differentiate Without Colour has no form."; fail=1; }
[ "$(grep -c 'accessibilityDifferentiateWithoutColor' "$TMP/chart.nc")" -ge 2 ] \
  || { echo "✗ the delta pill or the price line no longer reads Differentiate Without Colour."; fail=1; }
# The dock's four feels, each fired from the moment it names.
strip_comments "Casberi/Casberi/Design/Haptics.swift" > "$TMP/haptics.nc"
for h in snap spring fly pour; do
  grep -q "static func $h()" "$TMP/haptics.nc" \
    || { echo "✗ DSHaptic.$h is gone — the dock's grammar lost a feel."; fail=1; }
  grep -q "trigger: HapticBus.shared.$h" "$TMP/haptics.nc" \
    || { echo "✗ HapticBus.$h has no sensoryFeedback mapping — a bump into silence."; fail=1; }
done
grep -q 'DSHaptic.snap()' "$TMP/chrome.nc" \
  || { echo "✗ the fold's hysteresis crossing no longer snaps."; fail=1; }
grep -q 'DSHaptic.spring()' "$TMP/main.nc" && grep -q 'DSHaptic.fly()' "$TMP/main.nc" \
  || { echo "✗ MainSurface lost the folder's spring or the card's fly."; fail=1; }
grep -q 'DSHaptic.pour()' "Casberi/Casberi/Design/TileRain.swift" \
  || { echo "✗ the rain no longer pours in the hand."; fail=1; }
# A pointer magnifies the strip; a trackpad turns the page.
grep -q 'onContinuousHover' "$TMP/chips.nc" && grep -q 'guard let x = hoverX else { return 1 }' "$TMP/chips.nc" \
  || { echo "✗ the strip's hover no longer feeds the magnification wave — the Mac dock read is gone."; fail=1; }
strip_comments "Casberi/Casberi/Shell/PageSwipeCatcher.swift" > "$TMP/pager.nc"
grep -q 'allowedScrollTypesMask = .continuous' "$TMP/pager.nc" \
  || { echo "✗ the pager's pan no longer accepts trackpad scrolls."; fail=1; }
grep -q 'guard !touchDriven' "$TMP/pager.nc" \
  || { echo "✗ the pager's scroll-event path lost its touchDriven guard — a finger's move"; \
       echo "  would arrive twice (touches override + target-action)."; fail=1; }
# No coach capsule for the dock (user, 2026-09-06: "we don't need that coach
# tip about the bar, apple would never have that") — a tip above the dock is
# the chrome explaining itself, which the Mac dock never does.
grep -q 'DockCoach' "$TMP/root.nc" \
  && { echo "✗ RootShell mounts a dock coach again — ruled out 2026-09-06 (prd §630)."; fail=1; }

if [ $fail -eq 0 ]; then
  echo "✓ dock self-test"
else
  exit 1
fi
