# Spec: the dock stutters when switching between category chips (not to All)

Written 2026-09-10 for a separate session to implement. Read CLAUDE.md first; the
rulings this touches are prd §660, §662–§663, §666, §667. Record the result as
prd §668 and ship as the next build (1.0.16, next CURRENT_PROJECT_VERSION).

## Symptom (user, phone, build 550)

Tapping a category chip while standing in another category stutters and lags.
Tapping **All** is fast. Swiping rooms is fine since §651/§662g.

## What differs, from the code

A tap on **All** does one thing: closes any open folder and lands (`MainSurface`,
the chip `onTap` closure ~line 1583–1610). A tap on **another category** (§663)
does three things in the same frame:

1. `withAnimation(DS.Motion.folder) { chrome.openFolder = .category(label) }` —
   springs up `DockFolderRow` (`Shell/DockFolderRow.swift`).
2. `go(to: label)` → `deal(to:)` (~line 2050): the room card's flight on
   `DS.Motion.standard`, then the new room's `FeedScreen` remounts 280ms later
   (`flightMs`), then the row-budget lift ~250ms after that.
3. `ChipMemory.visited`, `CategoryFold.remember` (cheap defaults writes).

The folder row is the prime suspect, and it is exactly the class §660 removed
from the strip a day earlier — glass inside glass, N elements, animated:

- `DockFolderRow.swift:128` — `DSGlassContainer(spacing: 2)` holding the venues,
  inside a row that is itself `.dsGlass(cornerRadius: DS.Radius.pill)` (line 154).
- `:170–187` — every venue is a `BridgeIcon` + `VenueGlass`, and `VenueGlass`
  (line 213–222) applies `dsGlass(... glassID: "venueSelection")` **per venue**.
  Work has ~20 venues in the demo; that is twenty Liquid Glass elements
  mounting inside a glass row while a room swaps underneath.
- `:143` — each venue animates on `DS.Motion.folder.delay(i * stagger)`: a
  bouncy spring per venue, staggered, so the row is animating for
  0.42s + 20 × stagger while the flight and the remount are also running.
- `:93` — the row's own `.transition`.

Apple's guidance §660 cites: no glass on glass, no glass on scrolling content,
and animate transforms, not layout. The folder breaks the first two, twenty
times per tap.

## Step 1 — measure before changing anything (non-negotiable, CLAUDE.md rule)

Every perf pass in this ledger that guessed first was wrong (§651, §658, §660,
§662g). `Model/GestureGate.swift` now holds `HitchMeter`, a `CADisplayLink`
frame meter that records worst frame and missed frames per gesture.

1. Add `HitchMeter.Kind.tap`. Begin it in the chip `onTap` closure before the
   `withAnimation` (MainSurface ~1583); end it when the room has landed AND the
   folder spring has settled — simplest: `Task { try? await Task.sleep(for:
   .milliseconds(flightMs + 450)); HitchMeter.shared.end(.tap) }`, guarded by a
   generation counter so a second tap does not end the first's sample early.
   Diagnostics already prints `HitchMeter.shared.lines()`.
2. Build to the user's phone (TestFlight), have them tap Work → Agents → Life a
   few times and All a few times, and read Settings › Diagnostics. Expect the
   category taps to show a worst frame well over 17ms and All under it. Put the
   numbers in the prd entry. If All is ALSO over budget, the folder is not the
   whole story and step 3 ranks second.
3. Optional, more precise: run the app from Xcode on the phone with the
   "Animation Hitches" Instruments template; the `Gestures` signposter in
   `HitchMeter` marks each gesture, and the new `.tap` interval will bracket the
   switch.

## Step 2 — the likely fix: flat venues on one glass slab

Apply §660's own remedy to the folder row:

- Delete `VenueGlass`. A venue is a flat mark on the row's glass: the lit venue
  gets a flat tint ring or fill (`DS.tint`), drawn with the same `chipShape`
  idea the strip uses (§662: one shape, `RoundedRectangle` / circle), not a
  glass capsule. Keep the ONE `.dsGlass` on the row (line 154). Remove the
  inner `DSGlassContainer` (line 128) — it exists only to morph glass between
  venues, and there is no glass to morph.
- The lit-venue ring travels with `matchedGeometryEffect` in its own namespace
  (`selectionNS` in the row, id `ChipSelection.venueID`), pinned to
  `DS.Motion.glide` via `.transaction` exactly as `SelectionTravel` does in
  `SourceChips.swift` (§667). No bounce on an indicator.
- Keep the per-venue stagger if it survives measurement, but cap the total: the
  stagger is decorative; ten venues should not take 0.4s longer than three.
  Suggest `min(i, 6) * stagger`, the same shape §661 used for row entrances.

Guards to amend in `scripts/category-fold-selftest.sh` (lines ~412–431): they
currently REQUIRE `VenueGlass(on: lit`, `glassID: reduceMotion ? nil :
"venueSelection"` and `DSGlassContainer(spacing: 2)`. Invert them: no `dsGlass(`
inside `folderVenue`, no `DSGlassContainer` in the row, the ring rides
`DS.Motion.glide`. Keep the other properties they pin (attention resolved via
the catalog, a VoiceOver name per venue, a `DS.Hit.min` seat, full-bleed mark).

## Step 3 — one animation at a time

Even with flat venues, the tap starts the folder spring and the room flight in
the same transaction. Sequence them: land the room first (the flight is 280ms),
then spring the folder when `deal`'s landing task fires (the same `Task` at
MainSurface ~2067 that swaps the room). The eye reads "arrive, then the folder
opens" as intentional; two springs at once read as a stutter even when no frame
is missed. If measurement shows the folder alone is cheap after Step 2, this
step is optional — decide from the numbers, and say so in the entry.

## Step 4 — check the icon path

`folderVenue` draws `BridgeIcon(name: venue, size: markSize, circular: true)`
per venue. Confirm `BridgeIcon` (`Design/BridgeIcon.swift`) resolves from the
asset catalog or a cached `UIImage` and never decodes or renders on the tap's
frame (`StoredPixels` / `AssetMark` are the existing off-main paths). If it
renders SVG or builds an `ImageRenderer` per appearance, cache it.

## Acceptance

- On the user's phone, Diagnostics shows category→category taps with a worst
  frame under 17ms (one 60Hz frame; the app runs at 120Hz since §666 so aim for
  under 9) and zero missed frames on most taps. Put the before/after in the prd.
- `dock-selftest.sh`, `category-fold-selftest.sh`, `room-perf-selftest.sh`,
  `design-motion-audit.py` green; `scripts/verify.sh` green on both platforms.
- The folder still: springs from the tapped chip's x (`chrome.folderAnchorX`),
  closes on retap / feed tap / room swipe out of its category / a pick, lights
  the venue you are standing in, speaks its VoiceOver names, and the Wallet
  folder's face rail still sits above it (§649).
- No `dsGlass`/`glassEffect` inside the folder's venues; one glass, the row.

## Ship

Commit through a temp index (other sessions may be live — see the memory rules
in CLAUDE.md's Building section), bump CURRENT_PROJECT_VERSION, archive from a
pinned worktree, `testflight-public-beta.sh`, then `appstore-swap-build.sh
--version 1.0.16 --platform IOS --build <n>` (the user has authorized burning
the review queue slot for this fix). Run `scripts/verify.sh` after the upload,
not before — the user's standing instruction today — and reship only if red.
