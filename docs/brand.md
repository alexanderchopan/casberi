# Casberi — brand

Settled 2026-08-17, after seven rounds of exploration. This file exists so the
reasoning does not have to be rediscovered — the rejected directions at the
bottom cost far more to find than the accepted ones, and every one of them looks
reasonable until it is drawn.

---

## 1. The three pillars

**Simple · Connected · Organized.** A sequence rather than three parallel
virtues: Connected is what goes in, Organized is what happens to it, Simple is
what it feels like.

- **Simple** — nothing to set up, nothing to manage. Watching a wallet *is*
  consent, most bridges need no account, one gesture per row, the composer never
  saves. Not "few features" — **no administration**.
- **Connected** — sources feed it. Not a pillar of its own (below); the input
  side of this one.
- **Organized** — it arrives in order; **you never file anything**. Rooms derive
  from source, chip order is learned, the librarian passes run themselves.
  Unqualified, "organized" implies *you did the filing*, which is what every PKM
  app claims and the opposite of what this does. The qualifier is load-bearing.

### Two things deliberately not pillars

**Connection is where the three get tested, not a fourth.** Connecting is a cost,
not a benefit — nobody wants to connect things, they want their stuff to be
there — and "works with 60 apps" is the most commoditised claim in software. The
codebase already treats it as a proving ground: `setup-copy-audit` (Simple), the
read-only grading and `keychain-audit` (ownership), and a landed row already
knowing its source and date (Organized). **Corollary: every keyed bridge is
Simple-debt**, and the pillar names the direction to push — keyless >
minted-scoped > pasted key.

**Honesty is law, not a pillar.** §83, enforced by build-time checks rather than
a poster. It is how the product behaves, not something the brand claims.

### The constraint that is not a value

**No server. On-device. Nothing leaves.** Cut from the pillars and recorded here
as a **non-negotiable constraint**, because parts of it are enforced (the
`NetworkReach` ship gate, `keychain-audit`, the receipts screen) while the
architectural decision itself has no lint and never will. Nothing at brand level
should ever make "just a small server" sound reasonable.

---

## 2. The mark — the arm as a c (2026-11-01, prd §1638)

One octopus arm, curled into a lowercase c, leaning −9°. Pink on black, its
suckers punched through in the ground colour. It replaced the leaning octopus
(below, now the illustration) as the in-app mark and the wordmark's c, and was
the app icon until 2026-11-05.

**The app icon is its own drawing since 2026-11-05 (prd §1708): a cursive C.**
On the home screen the c read as a worm: an even body, a round end that read as
a head, spots for suckers. The icon's arm is a cursive C whose exit stroke runs
off the tile's right side, the join into an "a" you never see; its other end
narrows to a fine tip that spirals in, and its suckers are rings that shrink
toward the tip. `tentacle.py`'s `ICON` and `icon_arm()` are its geometry; the
mark below is unchanged.

Why one arm: the octopus's arms are the thesis (each senses on its own, one
animal), and one arm says it with a letter the name already starts with. It is
a monogram and a creature at once, and a mostly empty round shape holds at
20pt better than anything with a face.

**Construction rules — do not break:**

- 100×100 unit space. The arm's centreline is a circle of radius 27 about
  (50, 50), opening right, walked from −48° through 282°; past 73% of the walk
  its radius shrinks by 9 so the tip turns in. The whole arm then leans −9°
  about (50, 50) — the angle the octopus's head leaned, kept as the posture.
- A filled shape, never a stroke: width tapers from root to tip and both ends
  are round. **Mass, not a line** — section 7's lesson still holds.
- Full cut: width 17 → 4, six suckers graduated r 3.0 → 1.3, set toward the
  inside of the curl. Clean cut: width 18 → 7, no suckers.
- **The suckers are the GROUND colour, not an ink.** `CasberiMark` uses
  `Color.adaptive(dark:light:)` for exactly this.

**Size behaviour.** The full cut down to 16pt (`CasberiMark.smallCutBelow`, the
octopus's evidence: punched detail at @3x holds), the clean cut under it. The
wordmark's c is always the clean cut.

Sources: `design/app-icon/tentacle.py` writes `casberi-mark.svg`,
`casberi-mark-small.svg`, `casberi-wordmark-c.svg` and the dark and tinted icon
PNGs. In-app the same geometry is `Casberi/Casberi/Design/CasberiMark.swift`, a
line-for-line port, which also holds `CasberiWordmark`.

---

## 2b. The octopus — the illustration (was the mark, "7b", until 2026-11-01)

**Where it lives now:** the website's hero, where its arms catch the feed's
rows — the product's story, which needs the whole animal. Nowhere in the app.
Sources kept as `design/app-icon/casberi-octopus.svg` and
`casberi-octopus-small.svg`.

A filled octopus seen front-on, head tilted −9°, arms swept trailing the tilt,
graduated ring suckers. Hot pink on black.

Why an octopus: two-thirds of its neurons are in its arms, so each arm senses and
decides on its own while belonging to one animal. That is the product — many
sources reaching independently, one corpus, one mind. It is also the canonical
alien intelligence, which is what the exploration was reaching for before the
subject was found.

**Construction rules — do not break:**

- Canvas is a 100×100 viewBox. The head group is rotated `rotate(-9 50 46)`; the
  arms are drawn **already swept** and are never rotated. Rotating the arms with
  the head is the one change that quietly kills this mark — the sweep is what
  makes the lean read as a lean rather than a tilted picture.
- Head: solid filled mantle, flat base at y=46. Eyes are circles on the tilt
  axis at (44,33) and (58.5,36.5), r=3.7.
- Arms: **five** strokes, width 8, round cap, never filled. The outer two end in
  back-curls; the inner three taper straight. Five is deliberate — an
  eight-armed version was drawn and rejected, because at any size the icon
  actually appears the extra arms close into a single skirt and the count stops
  being countable anyway.
- Suckers: hollow rings, `stroke-width` 1.4, graduated big→small per arm
  (r 2.6 → 1.9 → 1.3), two or three per arm.
- **The eyes and suckers are the GROUND colour, not an ink.** They punch through
  the creature rather than printing on it. `CasberiMark` uses
  `Color.adaptive(dark:light:)` for exactly this.

**Size behaviour.** At and above 60pt, the full cut. Below 60pt, the small cut:
three arms, no rings, stroke 8→9, eyes r 3.7→5. The rings are 1.4 units wide,
which at 20pt is a quarter of a point — grey haze, not a ring. Suckers and
back-curls are the first details to drop; **the lean and the silhouette are the
identity, and the head is never straightened.**

(As the mark it drove `CasberiMark` until 2026-11-01; that geometry is in
git history.)

---

## 3. Colour

| use | value |
| --- | --- |
| mark, wordmark | `#FA2D48` (prd §1252; `#FF2D87` until 2026-10-11) |
| ground | `#000000` |

One hue and one ground. No gradients, no second hue. Mono: replace the pink with
`#FFFFFF` on a dark ground or `#000000` on a light one; the suckers stay the
ground colour.

**Not blue** — the iOS system accent makes the mark read as the platform's rather
than ours. **Not red** — the most crowded icon colour there is, and a red-orange
octopus is the visual language of Japanese seafood signage.

---

## 4. The app icon

**Black tile, pink arm** (the octopus until 2026-11-01). The zip's own `casberi-app-icon.svg` inverts this
(pink tile, black creature); the inversion was considered and rejected — the
black plate is what makes the icon findable on a home screen, where nothing else
is a bright mark on near-black.

Three 1024 PNGs, all opaque, in `AppIcon.appiconset`:

- `casberi-octopus-1024-light.png` — the default: the dark art, byte for byte
  (prd §1639; the arm on a white tile was mostly empty space)
- `casberi-octopus-1024-dark.png` — the same file
- `casberi-octopus-1024-tinted.png` — white arm, black ground

The filenames keep "octopus" so the asset catalog and pbxproj did not change
with the art. `tentacle.py` writes all three from `icon_arm()`, the cursive C
at 1.3× about the tile's centre with its join leaving the right side (prd
§1708); `scripts/app-icon-audit.py` holds light to a copy of dark.

The set is `"platform": "ios"` and **Catalyst inherits it**, so Mac and iOS share
one artwork. Consequence worth knowing: changing it changes both, so a Mac build
must not be archived while a Mac review is open unless that review is meant to be
replaced.

Export square at 1024 — iOS masks its own corners.

---

## 5. The wordmark

**The arm as the c, then "asberi" in Figtree SemiBold (600), lowercase,
letter-spacing −0.01em** (prd §1638). The c is the mark's clean cut, its box
0.56 of the type's size, dropped 0.035em under the baseline as a round letter
overshoots. No suckers in the wordmark: at the header's 19px the c is ten pixels
tall, and the letters beside it are solid.

Reasoning, in order:

1. **It is a marketing asset, not a product one.** Website header (~19px), hero,
   App Store, social. In the app it appears once, the Settings colophon
   (`CasberiWordmark`); the name under the Home Screen icon is drawn by iOS. So it is judged small,
   because that is where it lives.
2. **The mark carries the personality; the word carries the clarity.** A
   characterful custom wordmark beside a characterful creature makes them
   compete. Bespoke letterforms were drawn and rejected as over-built.
3. **The name is invented.** Nobody knows how it is spelled and people have to
   type it into a search box. Legibility matters more here than for a real word.
4. **§8 already bans decorative type in the product.** A loud wordmark would do
   in marketing exactly what the UI forbids.

Weight 600 because Regular reads thinner than the mark's stroke-8 arms and Bold
overtakes them; SemiBold matches optically.

Figtree is SIL OFL, which permits logo and trademark use. On the website it is
embedded in `styles.css` as a base64 `@font-face` — self-contained, per the
no-remote-assets rule. In the app Figtree has been the UI face since prd §532,
so the colophon's wordmark is the real one, at `heading24` with `.semibold`.

Apple's SF licence restricts using SF in a logo, which is why "just use the
system font" was never available for the real wordmark.

---

## 6. Lockups

Horizontal (mark left of word) and stacked (mark above word). The mark's stroke
steps with the text weight so a bold word never sits beside a hairline creature.
Clear space: roughly the mark's width on all sides.

In-app there is one lockup only — the **Settings colophon**: the wordmark, build,
centred at the foot of the list below the last row. It is deliberately not a
control and carries no affordance; see the comment on `SettingsScreen.colophon`.

---

## 7. What was tried and rejected

Each looks reasonable until it is drawn.

- **The dot cluster** (the previous mark). Correct but inert — it carried
  aggregation and quietness and nothing else. Its opacity ramp was the only
  property in it governed by no rule, and at 40px the pale cells fell below
  threshold, so the silhouette changed with size.
- **Rosettes and forbidden symmetry.** Seven-fold reads as a **flower**. Nature
  is full of rotational symmetry, so any clean centre with evenly spaced arms is
  filed as botanical. **Symmetry is the enemy of "alien"** — alien is ordered but
  *unpredictable*.
- **The bent lattice.** The minimal form of "a square from lines that overshoot"
  is literally the `#` glyph.
- **Ensemble traces / torus bundles.** Genuinely good large, and the strongest
  non-octopus direction. Still in the drawer.
- **One-line (Picasso) octopuses.** The unbroken-line constraint costs more than
  it buys: it forces the arm count down and reads as craft rather than identity.
- **Line octopuses generally.** Taper is what makes an octopus literal, and line
  cannot taper — round-trip strokes that fake it double the line count and tangle
  at icon size. **Literal needs mass.**
- **Poppins, Quicksand, Nunito.** Pure-circle geometrics; the naive quality that
  made an earlier hand-drawn wordmark look like a child's drawing.

---

## 8. Open

- Outline the wordmark to SVG for the marketing lockups (`fontTools` is not
  installed on this machine; until then the website sets it live in the embedded
  face, with `casberi-wordmark-c.svg` as the c).
- The website still draws the octopus in the nav and as the favicon. The nav
  becomes the wordmark alone, the favicon and share image the arm; the hero
  keeps the octopus (section 2b).
- The arm icon is shared by iOS and Mac (§4): it ships on each platform with
  that platform's next build.
