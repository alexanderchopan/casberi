# Handoff: Casberi App Icon

## Overview
The Casberi app icon: a berry built from seven opaque drupelets in one hue. It carries the name (cache + berry) and the product thesis — many things, one container. Chosen mark: **"Falloff, opaque"** — light enters from the top-left and fades across the cluster; every drupelet is a solid pre-mixed tone; front drupelets occlude back ones the way a real berry does.

## About the Design Files
The PNG/SVG files in this bundle are **final icon art**, generated from a single geometry source (`icon-svg.js`). They are ready to place in the Xcode asset catalog as-is. The HTML exploration board (in the parent project) is a design reference only.

## Fidelity
**High-fidelity, final.** Use the 1024 PNGs directly. Do not re-draw, recolor, add gradients, or bake a corner radius.

## The Mark

### Geometry (1024 × 1024 canvas)
Seven circles, radius **108**, on a hex-packed cluster:

| Drupelet | cx, cy | Tone level |
|----------|--------|-----------|
| Center | 512, 548 | 0.45 |
| Top-left | 426, 388 | 1.00 |
| Top-right | 598, 388 | 0.60 |
| Right | 684, 548 | 0.32 |
| Bottom-right | 598, 708 | 0.20 |
| Bottom-left | 426, 708 | 0.32 |
| Left | 340, 548 | 0.60 |

**Draw order: dimmest first, brightest last** (front drupelets occlude back ones). Fills are opaque — each tone is the brand hue pre-mixed toward the ground at the level above: `tone = mix(#0A84FF, ground, 1 − level)`. No alpha, no compounding overlaps.

### Color rules
- One hue only: iOS systemBlue dark **#0A84FF**.
- Magnitude renders as tone steps of that hue (the levels above). No second hue, no gradient.
- Orange, red, green are reserved for state elsewhere in the product — never in the mark.
- No wordmark, no mascot, no face, no glyph clichés.

### Canvas rules
- Square art, **no baked corner radius** — iOS applies the superellipse mask.
- Verified legible at 60px and 29px.

## iOS 18 icon modes (Asset Catalog)
Xcode 16+: one `AppIcon` asset with three appearances (Any, Dark, Tinted):
- **Any/Light** → `casberi-final-berry-opaque-1024-light.png` (white ground, blue mark).
- **Dark** → `casberi-final-berry-opaque-1024-dark.png` (black #000 ground, blue mark).
- **Tinted** → `casberi-final-berry-opaque-1024-tinted.png` (grayscale luminance master on black; the system applies the user's tint).

## Assets
- `casberi-final-berry-opaque-1024-{dark,light,tinted}.png` — 1024×1024 masters.
- `casberi-final-berry-opaque-{dark,light,tinted}.svg` — vector source per mode.
- `icon-svg.js` — the generator (single source of truth for geometry; `CasberiIconSVG(dir, mode)`, final mark is `dir: '1D'`).

## Provenance
Explored 2026-07-03 on the exploration board (`Casberi App Icons.dc.html`): eight directions → berry-as-vessel chosen → opacity arrangements iterated → opaque falloff selected. Runner-up (treemap / bento cut) masters also exist in the project's `icons/` folder if ever needed for marketing surfaces.
