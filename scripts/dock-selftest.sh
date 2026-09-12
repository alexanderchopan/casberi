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
# The agent bar and its folder are DELETED (prd §697, 2026-09-11); the
# leading seat is `DockDoors` — the face and the grid.
DOORS="Casberi/Casberi/Shell/DockDoors.swift"
DOCK="Casberi/Casberi/Design/DSDock.swift"

for f in "$MAIN" "$ROOTS" "$CHIPS" "$DOORS" "$DOCK"; do
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
strip_comments "$DOORS" > "$TMP/doors.nc"

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
grep -q 'DSDock.agentSize(fold: chrome.fold)' "$TMP/doors.nc" \
  || { echo "✗ DockDoors no longer sizes itself off ShellChrome.fold — it would jump 46→40"; \
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
# THE PAGE IS NOT CLIPPED AT REST, AND THE BAND PAINTS NO PLATE (prd §677,
# 2026-09-10, user: "why is there a black bar. the shapes and glass bar doesn't
# go over the screen?"). Three layers made that bar: `PagerDrag`'s clip (radius
# 0 at rest still clips to the page's bounds, which stop at the band), §649's
# opaque page-colour plate behind the band, and the soft scroll-edge fade over
# the whole inset. The clip is `PageClip`, a Shape that reaches below the page
# at rest and is the rounded card only while lifted; the plate is gone; the
# bottom edge fade is hidden. Seen on the simulator: rows run under the folder
# and the dock, and the glass refracts them. §649's scrim guards are retired
# with the scrim — a fixed ramp on a plate that no longer exists is not a rule.
grep -q 'clipShape(PageClip(lift: lift))' "$TMP/main.nc" \
  || { echo "✗ PagerDrag no longer clips through PageClip (prd §677) — a plain clipShape cuts"; \
       echo "  every row beneath the bottom band at the band's top edge: the black bar."; fail=1; }
grep -q 'struct PageClip: Shape' "$TMP/main.nc" \
  || { echo "✗ PageClip is gone (prd §677)."; fail=1; }
awk '/private var bandInset: some View/,/private var bandContent: some View/' "$TMP/main.nc" \
  | grep -qE 'DS\.page|DS\.themedPage|Color\.black' \
  && { echo "✗ the bottom band paints an opaque plate again (prd §677 retired §649's scrim) —"; \
       echo "  the glass would float over the page colour with nothing to refract."; fail=1; }
strip_comments "Casberi/Casberi/Design/Glass.swift" > "$TMP/glass677.nc"
grep -q 'scrollEdgeEffectHidden(true, for: .bottom)' "$TMP/glass677.nc" \
  || { echo "✗ the feed's bottom scroll-edge fade is back (prd §677) — over a band that holds"; \
       echo "  a folder or a rail it is ~160pt of page colour, i.e. the plate by another name."; fail=1; }
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
# THE SELECTION DOES NOT TRAVEL, AND THE EFFECT IS GONE (prd §676). §667 pinned
# the travel to a glide, §697 guarded that on an animated transaction, §675 set
# the animation to nil — and the fill STILL deformed between chips, measured at
# 8 frames. `matchedGeometryEffect` is not an animation you switch off; it is a
# travel mechanism. It is removed, and the chip's tap no longer wraps its
# landing in an animation either.
grep -q 'matchedGeometryEffect(id: ChipSelection.id' "$TMP/chips.nc" \
  && { echo "✗ the selection travels again (prd §676) — matchedGeometryEffect interpolates the"; \
       echo "  fill's frame between chips, which is the deform the user called a slide."; fail=1; }
grep -qE 't\.animation = DS\.Motion\.glide|\$0\.animation = DS\.Motion\.glide' "$TMP/chips.nc" \
  && { echo "✗ the selection is pinned to a spring again (prd §676)."; fail=1; }
grep -q 'withAnimation(DS.Motion.folder) { onTap(label) }' "$TMP/chips.nc" \
  && { echo "✗ the chip's tap wraps its landing in an animation again (prd §676) — every state"; \
       echo "  the tap touches would animate, the selection included. The folder springs from"; \
       echo "  MainSurface, after the room's mount (§668)."; fail=1; }
# THE STRIP'S BODY DOES NOT READ THE BRIDGE STORE (prd §697). `bridges.bridges`
# is written twice per landing sync; a read in `chip(_:)` rebuilt all eleven
# chips per write. The broken-seat ring and the spoken label are leaves.
awk '/private func chip\(_ label:/,/fileprivate static func chipAccessibilityLabel/' "$TMP/chips.nc" \
  | grep -q 'bridges\.bridges' \
  && { echo "✗ chip(_:) reads bridges.bridges again — every bridge write rebuilds the strip (prd §697)."; fail=1; }
grep -q 'struct ChipAttentionRing' "$TMP/chips.nc" && grep -q 'struct ChipSpokenLabel' "$TMP/chips.nc" \
  || { echo "✗ the broken-seat ring or the spoken label is no longer a leaf (prd §697)."; fail=1; }
[ "$(grep -c 'chipAccessibilityLabel(' "$TMP/chips.nc")" -eq 2 ] \
  || { echo "✗ chipAccessibilityLabel is called from more than one place — it was built twice"; \
       echo "  per chip per body, once for a modifier that is inert on a phone (prd §697)."; fail=1; }
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

# --- 5. the leading seat is the FACE alone, and the catalogue is the strip's
#        LAST item ---------------------------------------------------------
# THE OCTOPUS IS GONE (prd §697, 2026-09-11), and the grid door that stood
# beside the face for a few hours went to the strip's tail the same day (prd
# §700, user: "have the app icon not be fixed on the tab bar. only make the
# avatar be fixed"). The face is the one mark that is about you and the one
# that must survive into a pushed room; the catalogue is a place, and places
# scroll. The failure this guards is arithmetic and invisible: the melt, the
# reserved padding and the bar's own frame all read `agentSeat`, and a seat
# that counts a mark that is not there leaves 54pt of air before "All".
grep -q 'static func clusterWidth(fold: CGFloat) -> CGFloat { agentSize(fold: fold) }' "$DOCK" \
  || { echo "✗ DSDock.clusterWidth no longer spans exactly ONE mark — the seat holds the"; \
       echo "  face alone (prd §700); a wider cluster leaves air before All, a narrower"; \
       echo "  one runs All under the face."; fail=1; }
grep -q 'clusterInset + clusterWidth(fold: fold) + seam' "$DOCK" \
  || { echo "✗ DSDock.agentSeat no longer spans the door CLUSTER."; fail=1; }
grep -q 'DockDoors(' "$TMP/root.nc" \
  || { echo "✗ RootShell no longer hosts DockDoors — Settings must stand on the shell's"; \
       echo "  own layer, which survives into a pushed room; the strip does not."; fail=1; }
grep -q 'AvatarChip(' "$TMP/doors.nc" \
  || { echo "✗ the face is gone from the dock's leading seat."; fail=1; }
# The face is a TOGGLE (user, 2026-09-12: "if you press your avatar again it
# closes that screen"). It is the one door that stands ON TOP of the screen it
# opens, so a second press that re-presents the same screen is a control that
# looks live and does nothing — §83's dead control. Both seats (the phone's
# fixed dock seat and the iPad rail's own avatar) must route through
# `HomeRoute.toggle`, never `present`.
grep -q 'route.toggle(.settings)' "$TMP/root.nc" \
  || { echo "✗ the dock's face no longer TOGGLES Settings (prd §705) — pressing it a"; \
       echo "  second time must close the screen it opened, not re-present it."; fail=1; }
grep -q 'route.toggle(.settings)' "$TMP/main.nc" \
  || { echo "✗ the iPad rail's avatar no longer toggles Settings — the two seats are"; \
       echo "  one door and must behave identically."; fail=1; }
grep -q 'AppsDoor()' "$TMP/doors.nc" \
  && { echo "✗ the catalogue door is back in the FIXED seat (prd §700: only the avatar is"; \
       echo "  fixed; the catalogue is the strip's last item)."; fail=1; }
# The tail mark: drawn ONCE, after the ForEach, inside the horizontal strip's
# HStack — so it scrolls with the places, melts under the face like a chip,
# and never enters `labels` (it opens a screen, not a room). Counted in the
# cell arithmetic, or three spread tiles cover it and a new person's "add an
# account" rests one scroll past the edge.
python3 - "$TMP/chips.nc" <<'PY3' || fail=1
import sys
src = open(sys.argv[1]).read()
i = src.find("private var horizontalStrip: some View")
j = src.find("private func headDoors", i) if i >= 0 else -1
strip = src[i:j] if i >= 0 and j > i else ""
if not strip:
    sys.exit("✗ horizontalStrip not found in SourceChips — this guard is testing nothing")
fe = strip.find("ForEach(scrollingLabels")
cm = strip.find("catalogueMark")
if fe < 0 or cm < 0:
    sys.exit("✗ the strip no longer draws catalogueMark after its ForEach — the catalogue\n"
             "  has no seat anywhere on the phone (prd §700).")
if cm < fe:
    sys.exit("✗ catalogueMark is drawn BEFORE the categories — it belongs at the strip's\n"
             "  tail (prd §700): leading, it slides under the fixed face on the first\n"
             "  scroll and pushes All off its resting seat.")
if strip.count("ChipMelt(") < 2:
    sys.exit("✗ the tail mark no longer melts under the face like a chip — it would show a\n"
             "  hard edge sliding under the avatar's glass (2026-07-19).")
if "let marks = CGFloat(labels.count - count) + 1" not in src:
    sys.exit("✗ categoryCell no longer counts the tail mark — at three categories the spread\n"
             "  tiles cover it and the catalogue rests one scroll past the edge.")
mark = src[src.find("private var catalogueMark"):src.find("private func openApps")]
if "contentShape(Circle())" not in mark:
    sys.exit("✗ the tail mark lost its hit region — the door is the CIRCLE, not the glyph\n"
             "  (2026-07-26, three user reports deep).")
if "dsGlassDoor" in mark:
    sys.exit("✗ the tail mark wears glass — chips are ink on the slab (2026-09-09); glass\n"
             "  inside the scrolling slab is the arrangement that cost a frame per tick.")
if "frame(width: chipSize, height: chipSize)" not in mark:
    sys.exit("✗ the tail mark no longer stands in a chipSize frame — its pitch from the last\n"
             "  tile would differ from every other pitch in the strip.")
PY3

# --- 6. a CATEGORY still springs its folder out of its own chip -------------
# Unchanged by §697: the octopus's folder is gone, every category's is not.
grep -q 'DockSpringRow(' "$TMP/main.nc" \
  || { echo "✗ MainSurface no longer uses DockSpringRow — a category's folder does not"; \
       echo "  spring out of its chip, which is the whole of the Mac-dock ruling."; fail=1; }
[ -f "Casberi/Casberi/Shell/DockFolderRow.swift" ] \
  || { echo "✗ DockFolderRow.swift is gone — the springing folder has no row."; fail=1; }
grep -q 'openFolder == .doors' "$TMP/main.nc" \
  && { echo "✗ the octopus's folder is back (prd §697): with the ask deprecated it held"; \
       echo "  two doors, and two doors are drawn in the dock now."; fail=1; }
grep -q 'openFolder == .doors' "$TMP/chips.nc" \
  && { echo "✗ SourceChips draws the doors folder again."; fail=1; }

# --- 7. the ask is deprecated, and it is deprecated EVERYWHERE ---------------
# prd §697b. Each line below is a door a person meets BY ACCIDENT if it is left
# on — a Home Screen tile, a Siri phrase, a Control Center button, an icon
# long-press. §377's lesson is that a feature reachable by five doors is a
# feature turned off at four of them, so these are checked one by one.
for gone in AgentBar DoorsStrip SourcesTray SourcesOverlay DoorsPanel; do
  [ -f "Casberi/Casberi/Shell/$gone.swift" ] \
    && { echo "✗ $gone is back — the bar and its folder were deleted with the ask."; fail=1; }
done
grep -q 'static let enabled = false' "Casberi/Shared/AskSurface.swift" \
  || { echo "✗ AskSurface.enabled is not false — the ask is deprecated (2026-09-11)."; fail=1; }
grep -q 'AskSurface.enabled ? \[' "Casberi/Casberi/CasberiApp.swift" \
  || { echo "✗ the Daily Brief quick action is registered unconditionally again."; fail=1; }
grep -q 'AskCasberiIntent()' "Casberi/Casberi/Model/CasberiIntents.swift" \
  && { echo "✗ the \"Ask Casberi\" Shortcuts phrase is advertised again — Siri would offer"; \
       echo "  a feature the app no longer draws."; fail=1; }
grep -q 'KeptAskWidget()' "Casberi/CasberiWidgets/CasberiWidgets.swift" \
  && { echo "✗ the kept-ask widget is back in the bundle — every tile on it opens an ask."; fail=1; }
grep -q 'BriefControl()' "Casberi/CasberiWidgets/CasberiWidgets.swift" \
  && { echo "✗ the brief's Control Center button is back."; fail=1; }
grep -q 'WidgetAskLink.url' "Casberi/CasberiWidgets/NeedsYouWidget.swift" \
  && { echo "✗ the deadlines widget taps through to an ask again — it reads dueAt, which"; \
       echo "  is a corpus field, so it keeps its seat and opens the FEED."; fail=1; }
grep -q 'guard AskSurface.enabled else { return }' "$TMP/root.nc" \
  || { echo "✗ RootShell no longer gates the ask's deep links (casberi://ask, ://brief)"; \
       echo "  and the quick action's landing."; fail=1; }

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
# BOUNDED BY THE BRANCH, NOT BY A CHARACTER COUNT (fixed 2026-09-10, caught by
# this guard's own run): it read a fixed 3400-character window, and a comment
# added to the branch pushed the line below out of it, so `find` returned -1 and
# the ordering check failed on correct code. The comment that follows the branch
# is the real end of it.
tail = src.find('// "All" and any bare source are not folders', i)
branch = src[i:tail if tail > i else i + 6000]
# The branch has TWO arms now (prd §668): standing here toggles the folder and
# returns; anywhere else LANDS first and springs the folder after the flight,
# so nothing overlaps the room's mount. Both arms must survive.
if "let standingHere = BridgeCatalog.category(forSource: filter.source) == label" not in branch:
    print("✗ the category tap no longer asks whether you are standing in it — prd §663:")
    print("  another category's chip goes there; the standing chip only toggles.")
    sys.exit(1)
if "if standingHere {" not in branch or "chrome.openFolder = opening ? .category(label) : nil" not in branch:
    print("✗ the standing chip's tap is no longer the folder's own toggle (prd §663/§668).")
    sys.exit(1)
if "go(to: label, landNow: true)" not in branch:
    print("✗ a category tap no longer LANDS in the room (prd §663).")
    sys.exit(1)
# THE SEQUENCING (prd §668, re-based by §671): the land comes first, the
# folder's spring follows it inside a generation-guarded wait — past the
# ROOM'S MOUNT since §671 (the tap lands on its own frame, so there is no
# flight to wait past), capped at the flight's length. A folder sprung in the
# same frame as the room's build is the stutter §668 fixed.
land_at = branch.find("go(to: label, landNow: true)")
spring_at = branch.find("chrome.openFolder = .category(label)")
if land_at < 0 or spring_at < 0:
    print("✗ the category tap's land or its folder spring is missing from the branch (prd §668).")
    sys.exit(1)
if land_at > spring_at:
    print("✗ the folder springs before the room is dealt (prd §668) — the spring, the card's")
    print("  flight and the room's mount would overlap again, which is the reported stutter.")
    sys.exit(1)
if "roomMounted(after: mountsBefore" not in branch or "flightGeneration == generation" not in branch:
    print("✗ the folder's spring is no longer a generation-guarded wait PAST the room's")
    print("  mount (prd §668/§671) — level with the landing, this task and the landing are")
    print("  both due, this one can run first, and the guard throws the folder away: the")
    print("  tap lands and no folder ever comes up. Measured on the simulator (§668).")
    sys.exit(1)
# §671: a tap LANDS NOW. Every tap route passes `landNow: true`; the swipe's
# `step` does not, because the finger already moved the page there.
src = open("Casberi/Casberi/Shell/MainSurface.swift").read()
if src.count("landNow: true") < 4:
    print("✗ fewer than four tap routes land on their own frame (prd §671): the category")
    print("  chip, the plain chip, a folder's venue pick and a room's own switcher all pass")
    print("  `landNow: true` to `go(to:)`.")
    sys.exit(1)
# §676: a tap CUTS. §671's departing card — a picture of the room being left,
# flown across the screen — was the "sort of scroll when you click the icons"
# the user reported for four builds running; measured at 8 frames of travel on
# a warm snapshot cache, which is why §671's own check (run on a COLD cache,
# where no picture exists) read as a clean cut.
if "cutNow(to: target)" not in src:
    print("✗ a tap no longer cuts (prd §676) — it is flying a card or a cover across the")
    print("  screen again, which is the slide reported through builds 554-557.")
    sys.exit(1)
if "DepartingCard" in src or "departNow" in src:
    print("✗ the departing card is back (prd §676).")
    sys.exit(1)
if "swipeCommit = true" not in src:
    print("✗ cutNow no longer pins the transition to .identity (prd §676) — the rooms would")
    print("  slide past each other on a tap instead of cutting.")
    sys.exit(1)
GATE

# --- 8. the inclusion pass (2026-09-06, prd §630) ------------------------------
# Every glass surface honours Reduce Transparency, through the token — so a raw
# material anywhere else is a surface the setting cannot reach.
strip_comments "Casberi/Casberi/Design/Glass.swift" > "$TMP/glass.nc"
[ "$(grep -c 'accessibilityReduceTransparency' "$TMP/glass.nc")" -ge 3 ] \
  || { echo "✗ Glass.swift no longer reads accessibilityReduceTransparency on each of"; \
       echo "  dsGlass / dsGlassProminent / dsGlassBlob — a glass surface the setting can't reach."; fail=1; }
# DSTray's glass pane and its Reduce Transparency check were deleted (prd §712):
# a tray is `surfaceSheet`, already opaque, so it has nothing to read — and it
# is no longer exempt from the raw-material check below.
grep -q 'func dsOpaqueGlass' "$TMP/glass.nc" \
  || { echo "✗ dsOpaqueGlass is gone — the opaque form of glass has no one recipe."; fail=1; }
# Comment-stripped, because two files DOCUMENT a material they no longer draw.
raw=""
for f in $(grep -rl 'Material' Casberi/Casberi Casberi/Shared --include='*.swift' 2>/dev/null \
           | grep -v 'Design/Glass.swift'); do
  strip_comments "$f" | grep -q '\.regularMaterial\|\.ultraThinMaterial\|\.thinMaterial\|\.thickMaterial' \
    && raw="$raw $f"
done
[ -z "$raw" ] \
  || { echo "✗ a raw material outside Glass.swift — route it through dsGlass so"; \
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
