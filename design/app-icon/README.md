# Handoff: Casberi App Icon

## Overview
The Casberi app icon: **an octopus** — a rounded mantle with two eyes and five suckered arms, in one hot pink on a plain ground. Many arms, one animal: the product thesis (many things, one container) said as a creature rather than as a diagram.

**This file described a BERRY until 2026-09-08, and it was wrong** (user: "the apps' mark is not a berri it is an octopus"). The berry — seven blue drupelets, hex-packed, named for *cache + berry* — was the earlier mark, and its generator (`icon-svg.js`) and three `casberi-icon-*.svg` outputs were deleted with this rewrite, because they emitted art the app has not shipped for some time and nothing else referenced them. Two things had been quietly reading the stale claim: `Design/BerryRain.swift`'s drop palette, commented "the icon's berry blues", and several `design/*/…mocks.html` boards drawing `.berry` confetti. Both are gone (the shower is `TileRain` now — see prd §655).

## About the Design Files
`casberi-mark.svg` is the mark's geometry source. The three 1024 PNGs in the app's asset catalog are the final icon art — they are what ships, and they are not generated from anything in this folder any more.

## Fidelity
**High-fidelity, final.** Use the shipped PNGs directly. Do not re-draw, recolor, add gradients, or bake a corner radius — iOS applies the squircle.

## The Mark

### Geometry (100 × 100 viewBox, scaled to 1024)
The head group is rotated **−9°** about (50, 46), so the animal leans; the arms are drawn upright underneath it.

| Part | Definition |
|------|-----------|
| Mantle | one filled path, `M33,46 C29,42 28,34 31,26 C35,14 48,8 59,13 C70,18 73,31 68,40 C66,43 68,45 68,46 Z` |
| Eyes | two filled circles, (44, 33) and (58.5, 36.5), r **3.7** |
| Arms | five open strokes, width **8**, round caps, no fill |
| Suckers | thirteen open circles, stroke width **1.4**, grouped 2 · 3 · 3 · 3 · 2 along the arms |

The suckers **taper outward** — r 2.6 nearest the mantle, then 1.9, then 1.3 at the arm's tip. That taper is the whole reason the arms read as arms at small sizes rather than as five loose curves, so it is the last thing to simplify.

### Colour
| Role | Value |
|------|-------|
| Mark | `#FF2D87` |
| Eyes and suckers | **the ground** — knocked out of the mark, not painted over it |
| Ground (dark, tinted) | `#000000` |
| Ground (light) | `#FFFFFF` |

The eyes and suckers being the GROUND rather than a colour is what keeps the mark to one ink. It also means the mark cannot be recoloured by swapping a single fill: the negative shapes have to travel with it.

### Small sizes
`casberi-mark-small.svg` (29pt) is a **deliberately different drawing**, not the same file scaled. Five arms and thirteen suckers turn to mud below about 40pt, so the small mark drops to **three arms, no suckers**, with the eyes enlarged to r **5** and the arm stroke thickened to **9**. Reach for it whenever the mark is rendered under ~40pt; scaling the full mark down instead is the failure this file exists to prevent.

## The three variants
iOS picks one of these by the appearance the person chose in the Home Screen editor. All three carry the SAME coverage mask; only the ground changes.

| Variant | Mark | Ground | Note |
|---------|------|--------|------|
| light | `#FF2D87` | `#FFFFFF` | derived from the dark art — see below |
| dark | `#FF2D87` | `#000000` | the drawing everything else comes from |
| tinted | `#FFFFFF` | `#000000` | greyscale; the system maps luminance to the person's tint |

**The light PNG was a byte-for-byte copy of the dark one until 2026-09-22** (prd §869), so every person on the light or default appearance saw the dark drawing — pink on black — on a light home screen. The two files had the same md5.

`make-light-icon.py` derives the light variant by recovering the mark's per-pixel coverage out of the dark art and compositing it over white instead of black. It reads the SHIPPED dark PNG, which is the point: the berry-era generator was deleted for emitting art the app had stopped shipping, and a script whose input is the shipped art cannot drift that way. It has a `--self-test` (the ground inverts, the mark holds, coverage round-trips, a knocked-out eye lands on white, and the transform is not the identity).

```sh
python3 design/app-icon/make-light-icon.py --self-test
python3 design/app-icon/make-light-icon.py
```

Because the eyes and suckers are GROUND, they turn white for free — there is no second drawing to keep in step.

## Files
- `casberi-mark.svg` — the full mark, 1024 (geometry source).
- `casberi-mark-small.svg` — the 29pt mark: three arms, no suckers, heavier stroke.
- `make-light-icon.py` — derives the light PNG from the dark one; pure stdlib, `--self-test`.
- Shipped art lives in `Casberi/Casberi/Assets.xcassets/AppIcon.appiconset/` — `casberi-octopus-1024-{light,dark,tinted}.png`, wired in `Contents.json` as the universal iOS icon plus its dark and tinted luminosity variants.

## Unverified
All three PNGs have now been decoded and read (2026-09-22): the dark art is exactly `#FF2D87` composited over black with a clean 101-step alpha ramp, the tinted art is the same mask in white on black, and the light art is that mask over white. **None of the three has been seen on a physical device** — they were read as pixels and rendered to a contact sheet, not installed. The squircle in any preview is an approximation; iOS applies its own.
