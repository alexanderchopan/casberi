# The panel paints itself on — motion spec (prd §342, 2026-08-07)

This is an IMPLEMENTATION SPEC, written to be executed by a model other than
the one that designed it. Every value is explicit. Where a step has a known
trap, the trap is named inline — most of them were already paid for once in
§336–§340 and none of them are visible to the build, the harness, or any
audit. **The acceptance test for this whole document is a simulator
screenshot and a screen recording, not a green build.**

## The idea, in one paragraph

Today every figure enters competently but identically-ish: one `@State grown`
Bool flips in `onAppear`, one spring interpolates, and each figure reads a
shared `t`. World-class is not more motion — it is CHOREOGRAPHY: the panel
should assemble the way a person would draw it. One timebase for the whole
surface, top to bottom; within each tile, structure first (the well, the
axis), then data (the stroke, the bars, the dots), then meaning (labels,
readings) — always in that order, because that is the order a hand draws a
chart. Nothing loops, nothing shimmers, everything settles to perfect
stillness. Apple-class restraint: if a motion doesn't explain where something
came from or what it's made of, it doesn't exist.

## Hard laws (do not violate; each has a mechanical enforcer)

1. **No `repeatForever`, no idle loops.** `design-motion-audit.py` flagged
   `GenTagMap`'s breathe for exactly this. Everything settles and goes still.
2. **Reduce Motion collapses EVERYTHING to the settled state instantly.**
   Every animation below must be written as
   `reduceMotion ? nil : <animation>` — the audit greps for `reduceMotion \? nil`
   and the harness guards it. A `t` that is `1` under Reduce Motion is already
   wired in `FigureView`; keep that pattern.
3. **No Liquid Glass on tiles** (floating layer only — design law §8).
4. **No hairlines.** Structure enters by TONE (the well fading up), never by
   an outline drawing itself.
5. **New child views that draw from data need `KNOWN_EXEMPT` entries** in
   `scripts/design-motion-audit.py` when their entrance clock lives in the
   parent — the existing entries for `FlowFigure`/`DialFigure`/`RiverFigure`
   show the exact wording. Add one per new struct, with the same reason.
6. **The panel holds no `Thing`.** Nothing in this spec requires touching the
   model layer or the composer. If an implementation step seems to need a
   `Thing`, the step has been misread.

## Architecture: one clock, three phases

Replace the per-figure `grown` Bool with a phased timebase, still a single
`@State`:

```swift
/// In FigureView. 0 → 1 over the tile's whole entrance.
@State private var paint: Double = 0

var body: some View {
    Group { /* switch unchanged */ }
        .onAppear {
            guard !reduceMotion else { paint = 1; return }
            withAnimation(.easeOut(duration: 1.1)) { paint = 1 }
        }
}
```

- **Do NOT use `PhaseAnimator` or `KeyframeAnimator`.** They re-run on state
  identity changes and both have replay-on-scroll traps inside `List`/
  `LazyVGrid` recycling — the exact bug that got the row sparkline's
  draw-on reverted (see `Sparkline`'s own doc). A monotonic `Double` driven
  once from `onAppear` cannot replay.
- Figures derive three sub-clocks from `paint` with this helper (add to
  `FigureView`):

```swift
/// Maps the master clock onto a sub-interval, clamped 0…1.
/// phase(0.0, 0.3) is done at 30% of the entrance; phase(0.7, 1.0) hasn't
/// started until 70%.
private func phase(_ from: Double, _ to: Double) -> Double {
    min(1, max(0, (paint - from) / max(0.001, to - from)))
}
```

- **Phase grammar, identical for every figure:**
  - `phase(0.00, 0.25)` — STRUCTURE: the well's contents fade/scale in
    (axis line, dial ring, spine, empty grid cells at `DS.fillLine`).
  - `phase(0.15, 0.80)` — DATA: strokes trim, bars grow, dots land, cells
    fill with hue. Overlaps structure by design; a strict sequence reads
    mechanical.
  - `phase(0.70, 1.00)` — MEANING: labels, numbers, legends, captions fade
    up 4pt. Words come last because a hand labels a chart last.

- **Tile stagger stays as-is** (`TileEntrance`, 0.04s per index). The master
  `paint` starts when the tile appears, so the cascade is already top-to-
  bottom for free.

## Per-figure choreography (exact values)

All in `Casberi/Casberi/Screens/AgentPanelGrid.swift`. Current code already
routes a `t: Double` into the child structs — REPLACE that `t` with the
phased sub-clocks below. Durations are fractions of the 1.1s master.

### Curve (the hero)
1. Structure: nothing to draw — the well itself is the structure.
2. Data: `line.trim(from: 0, to: phase(0.10, 0.75))`, unchanged concept —
   but add the **pen tip**: a second copy of the path,
   `.trim(from: max(0, tipT - 0.03), to: tipT)` where
   `tipT = phase(0.10, 0.75)`, stroked at `lineWidth + 1.5` in the same
   colour at full opacity. It reads as the bright nib of a pen and costs one
   path. Remove it when `paint == 1` (`.opacity(paint < 1 ? 1 : 0)`), so the
   settled frame is byte-identical to today's.
3. The gradient fill blooms on `phase(0.72, 1.0)` (today it's a delayed
   opacity — keep, retimed).
4. The hero READING counts up: apply
   `.contentTransition(.numericText(value: last))` to the reading `Text` and
   drive it by animating a `@State displayedValue` from `first` to `last`
   over the same 0.10–0.75 window. **Trap:** `numericText` animates only if
   the string change is animated — wrap the state change in
   `withAnimation(.easeOut(duration: 0.72))`.

### Bars
1. Structure `phase(0, 0.25)`: each row's TRACK appears first — a full-width
   capsule at `DS.fillLine`, which does not exist today. Add it UNDER the
   hue capsule. It is what makes the grow read as filling-a-track instead of
   a line getting longer.
2. Data: each bar grows on its own window, staggered
   `phase(0.15 + 0.08 * i, 0.55 + 0.08 * i)`, with the spring already in
   `DS.Motion.standard`. The leader (i == 0) additionally overshoots:
   animate its width with
   `.spring(response: 0.5, dampingFraction: 0.68)` — only the leader, or
   the overshoots collide visually.
3. Meaning: label + detail per row on `phase(0.6 + 0.06 * i, 0.9)`.

### Treemap rows
1. Structure: nothing (rows ARE data).
2. Data: row `i` wipes on `phase(0.10 + 0.10 * i, 0.45 + 0.10 * i)` —
   today's width×t, retimed per row. `scaleX` anchors leading (already true
   via `alignment: .leading` frame).
3. Meaning: the leader's count fades in LAST, `phase(0.8, 1.0)` — a number
   appearing before its bar has landed reads as a typo.

### Pulse (contribution wall)
1. Structure `phase(0, 0.3)`: ALL cells appear at `DS.fillLine` (the empty
   grid) — today the whole wall fades as one.
2. Data: live cells take their hue in a **diagonal sweep**: cell at
   (week w, day d) fills on
   `phase(0.2 + 0.5 * Double(w + d) / Double(weeksShown + 6), …+0.12)`.
   Deterministic, no randomness (a seeded scatter re-rolls identically but
   reads as noise; the diagonal reads as a hand shading a grid).

### Dial
1. Structure `phase(0, 0.25)`: the ring strokes itself —
   `Circle().trim(from: 0, to: phase(0, 0.25))`, starting at 12 o'clock
   (`.rotationEffect(.degrees(-90))`). Hour anchors fade in at the end of
   this phase.
2. Data: the radar sweep, retimed to `phase(0.2, 0.85)` — a mark shows when
   `phase(0.2, 0.85) >= mark.hour / 24`. ADD a fade: each mark's opacity
   ramps over 0.15s after its gate rather than popping (wrap the mark in
   `.animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: shown)`).
3. Meaning: the "busiest 9a–1p" caption on `phase(0.85, 1.0)`.

### River
1. Structure: nothing.
2. Data: the existing leading-edge mask, retimed `phase(0.05, 0.8)` — and
   give the mask a **soft edge**: a 24pt `LinearGradient` from opaque to
   clear at the leading edge of the mask rectangle, so the river's front is
   a wet edge, not a guillotine.
3. Meaning: legend dots+labels stagger `phase(0.75 + 0.06 * i, 1.0)`.

### Sankey
1. Structure `phase(0, 0.2)`: the spine scales up vertically from its
   centre (`scaleEffect(y: phase(0, 0.2), anchor: .center)`).
2. Data: ribbons flow OUTWARD from the spine — **reverse the trim**: draw
   the path from spine to label edge (swap `move`/`addCurve` endpoints) so
   `.trim(from: 0, to: …)` grows away from the spine. Inflows on
   `phase(0.2, 0.6)`, outflows on `phase(0.35, 0.75)` — money in before
   money out, always, because that's the story a flow tells.
3. Meaning: lane labels `phase(0.7, 1.0)`.

### Runway
1. Structure `phase(0, 0.25)`: the axis draws left-to-right (today's
   width×t, retimed), the "now" tick pops at the END of this phase with
   `.spring(response: 0.3, dampingFraction: 0.5)` scale from 0.
2. Data: dots LAND — each dot on `phase(0.25 + 0.07 * i, 0.5 + 0.07 * i)`,
   scaling from 1.6 → 1.0 with opacity 0 → 1 (falling onto the axis, not
   rising out of it — deadlines arrive).
3. Meaning: span label `phase(0.8, 1.0)`.

### Scatter (semantic map)
Keep the drift-home concept, retime to `phase(0.1, 0.7)`, and add:
1. Halos fade in FIRST `phase(0, 0.2)` — the neighbourhoods exist before
   their members arrive.
2. Labels' capsules on `phase(0.75, 1.0)`, rising 4pt.

### Wall (thumbnails)
Cells fade+rise 6pt in reading order, `phase(0.1 + 0.12 * i, 0.4 + 0.12 * i)`.
`AsyncImage` loads race the entrance; that is fine — the placeholder
participates in the motion and the image swaps in place.

## Known traps for the implementer (each already cost a debugging round)

- **A nested `func` inside any ViewBuilder closure will not compile**, and
  the error ("generic parameter 'Content' could not be inferred") points
  nowhere near it. Use `let f: (Args) -> T = { }` closures. (§337.)
- **Long expression chains on Dictionary blow up the type-checker** with
  "unable to type-check in reasonable time". Break into `for` loops. (§337.)
- **Inline `max()/CGFloat` arithmetic inside `.frame` inside `ForEach`
  inside `GeometryReader`** — same type-checker failure. Precompute in a
  `static func`. (§337, `ScatterFigure.halo`.)
- **`.id()` + `.transition(.opacity)` inserts a NEW view while removing the
  old** — both on screen mid-crossfade. Use `contentTransition`. (§339,
  the placeholder bug.)
- **Per-element `.animation(_:value:)` must ride the element, not the
  container** — a container-level animation gives one interpolation for
  everything and the stagger silently vanishes.
- **`onAppear` fires again when a LazyVGrid recycles.** The tiles sit in a
  plain VStack today, so this is latent — guard anyway:
  `guard paint == 0 else { return }` at the top of the `onAppear`.
- **The settled frame must be byte-identical to today's.** Any element added
  for motion (the pen tip, the track capsules under bars, the mask
  gradient) must either vanish at `paint == 1` or be visually identical to
  the current settled render. Diff a settled screenshot against a
  pre-change one to prove it.

## Acceptance (in order; do not skip 4 — it is the §339 lesson)

1. `xcodebuild … build` succeeds.
2. `scripts/agent-panel-selftest.sh` passes untouched (this spec changes no
   model code; if the harness fails, the implementation strayed).
3. `python3 scripts/design-motion-audit.py` — 0 findings after adding
   `KNOWN_EXEMPT` entries for any NEW child structs.
4. **Simulator:** install, launch with
   `-onboarded YES -openComposer YES`, and capture BOTH:
   - a screenshot at ~0.4s after open (mid-paint — structure visible, data
     partially drawn, no labels yet), and
   - a screenshot at 3s (settled — must match the pre-change settled frame).
   Then `xcrun simctl io booted recordVideo` one full open. Watch it.
5. Reduce Motion on (`xcrun simctl ui booted reduce_motion on` if available,
   else the Settings app): one screenshot proving the panel renders settled
   with zero motion.
6. `LAUNCH_CYCLES=0 scripts/verify.sh --build-only` — all 48.
7. prd §342 records what shipped and any deviation from this spec, with the
   reason.
