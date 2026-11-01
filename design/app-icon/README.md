# Handoff: Casberi App Icon

## Overview
**Since 2026-11-01 (prd §1638) the icon is one octopus arm curled into a lowercase c**, leaning −9°, in Apple Music's pink (`#FA2D48`, prd §1252) on a plain ground, its suckers punched through in the ground colour. The geometry, and every file it writes, is `tentacle.py`; `docs/brand.md` section 2 has the construction rules. `Design/CasberiMark.swift` is a line-for-line port of it.

**Everything below this section describes the OCTOPUS** — the five-armed leaning creature that was the mark until 2026-11-01 and is now the website's illustration. Its sources are kept as `casberi-octopus.svg` and `casberi-octopus-small.svg`; `casberi-mark.svg` and `casberi-mark-small.svg` are the arm now.

### The octopus (until 2026-11-01)
The Casberi app icon was **an octopus** — a rounded mantle with two eyes and five suckered arms, in Apple Music's pink (`#FA2D48`, prd §1252; `#FF2D87` until 2026-10-11) on a plain ground. Many arms, one animal: the product thesis (many things, one container) said as a creature rather than as a diagram.

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
| Mark | `#FA2D48` |
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
| light | `#FA2D48` | `#FFFFFF` | derived from the dark art — see below |
| dark | `#FA2D48` | `#000000` | the drawing everything else comes from |
| tinted | `#FFFFFF` | `#000000` | greyscale; the system maps luminance to the person's tint |

**The light PNG was a byte-for-byte copy of the dark one until 2026-09-22** (prd §869), so every person on the light or default appearance saw the dark drawing — pink on black — on a light home screen. The two files had the same md5.

`make-light-icon.py` derives the light variant by recovering the mark's per-pixel coverage out of the dark art and compositing it over white instead of black. It reads the SHIPPED dark PNG, which is the point: the berry-era generator was deleted for emitting art the app had stopped shipping, and a script whose input is the shipped art cannot drift that way. It has a `--self-test` (the ground inverts, the mark holds, coverage round-trips, a knocked-out eye lands on white, and the transform is not the identity).

```sh
python3 design/app-icon/make-light-icon.py --self-test
python3 design/app-icon/make-light-icon.py
```

Because the eyes and suckers are GROUND, they turn white for free — there is no second drawing to keep in step.

## Files
- `tentacle.py` — the arm: writes `casberi-mark.svg` (full cut), `casberi-mark-small.svg` (clean cut), `casberi-wordmark-c.svg` (the clean cut cropped, for the wordmark) and the dark and tinted icon PNGs. Then run `make-light-icon.py`.
- `casberi-octopus.svg`, `casberi-octopus-small.svg` — the octopus, now the illustration.
- `casberi-mark.svg`, `casberi-mark-small.svg` — the arm's full and clean cuts (written by `tentacle.py`).
- `make-light-icon.py` — derives the light PNG from the dark one; pure stdlib, `--self-test`.
- Shipped art lives in `Casberi/Casberi/Assets.xcassets/AppIcon.appiconset/` — `casberi-octopus-1024-{light,dark,tinted}.png`, wired in `Contents.json` as the universal iOS icon plus its dark and tinted luminosity variants.

## Unverified
All three PNGs have now been decoded and read (2026-09-22): the dark art is exactly the mark composited over black with a clean 101-step alpha ramp, the tinted art is the same mask in white on black, and the light art is that mask over white. **None of the three has been seen on a physical device** — they were read as pixels and rendered to a contact sheet, not installed. The squircle in any preview is an approximation; iOS applies its own.
