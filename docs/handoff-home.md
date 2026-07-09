# Handoff — Home screen (cover story, H7)

For Claude Code. Companion to `handoff-shaped-feeds.md` and `handoff-apps-page.md`.
Applies to `Screens/HomeScreen.swift`, `GenUI/HomeComposition.swift`,
`GenUI/GenRenderer.swift`. The mock is approved; this doc is the source of truth.

## What changes (and what doesn't)

Home keeps its engine, voice, and most of its grammar. Three changes:

1. A full-bleed COVER replaces the sheet-card Hero.
2. The KindBar is replaced by kind-colored glyph PILLS ("What landed today").
3. Nothing else moves: the projects treemap stays EXACTLY as shipped
   (magnitude tint fills, plain labels, no sublines, no images in cells),
   Insight stays one proven line, Threads ("Worth returning to") stays,
   Signals stay two StatTiles max.

VOICE GUARDRAILS (unchanged, re-affirmed): themes and content, no obligations.
No "waiting on you", no task counts, no countdowns, no "next up" blocks on Home.
Agent approvals live in Feed. The cover states what LANDED, never what's due.

## 1. The cover (new Gen element: `Cover`)

GEN-UI RULE (this page streams like OpenUI): the composition document stays
dumb — `cover = Cover(eyebrow, title, subline, thingId)` — and ALL smart
behavior lives in the renderer's Cover element: image lookup by thingId,
color extraction, theme fallbacks, height selection. The doc (local author
today, /compose server in M2) can never produce a broken cover because it
only names facts. The renderer decides its height BEFORE first paint (from
locally-known data: does thingId resolve to an image?) so the streamed
skeleton never jumps: image → 250pt skeleton, no image → 140pt skeleton.

Full-bleed header, minHeight 250 (image) / 140 (no image), ignores top safe
area; nav buttons (avatar, apps grid + attention dot) overlay it with the
vivid-background text ramp.

Top edge earns its space: centered between avatar and grid button, a date
eyebrow — "MONDAY · 14 THINGS" (label12 kerning 1.2, white 85%). The count is
today's landed count; on a quiet day it reads "MONDAY · QUIET SO FAR". This
line is authored in the doc (the server knows the date and count), rendered
by the Cover element. The 34pt nav title "Home" stays gone — the cover is
the title.

Content: the day's newest image thing (kind .screenshot or an image .file).
- Eyebrow: "JUST LANDED · <SOURCE>" (label12 kerning 1, white 70%).
- Title: the thing's title, 26pt weight .heavy, lineLimit(2), minimumScaleFactor(0.7).
- Subline: project · shortTime (subhead13, white 85%).
- Tap → the thing sheet. The image fills the header under the gradient.
- NO fixed content heights inside — the 250pt is the image canvas (minHeight),
  text is bottom-anchored with padding; test at accessibility type sizes.

### Cover color — the theme question (decided)

The bleed color is EXTRACTED FROM THE IMAGE, not themed. Content owns the
cover; the theme owns everything below. Precedence: image color > theme color
> black, always resolving into `DS.page`.

- Image cover: dominant color via CIAreaAverage (or CIKMeans for a 2-stop
  radial bleed), then desaturate ~20% and cap brightness so the white text
  ramp passes contrast. The vertical gradient's bottom stop is `DS.page`
  (NEVER hardcoded black) so on Purple/Teal/etc. themes the cover dissolves
  into the themed page with no seam.
- No image landed today: fall back to the newest image thing this WEEK; if
  none, the cover SHRINKS to minHeight 140 with its text block vertically
  centered (never bottom-anchored under a tall flat gradient — that top edge
  read as waste) over a quiet gradient of `ThemeStore.background` darkHex
  washed toward `DS.page`. Text: the shipped Hero content (Just landed /
  quiet-day lines from HomeComposition, same priority rules).
- Photo theme background in force: skip the extracted bleed, strengthen the
  scrim (two competing photos — the cover's content photo wins; the wallpaper
  stays behind the rest of the page).
- Cover text always uses the vivid-background ramp DS already has.
- Cache the extracted color per thing id; extraction runs off-main.

## 2. Kind chips — on the cover (ruling 2026-07-09; supersedes the bottom pills section)

Today's kind counts ride the COVER as a chip row (Cover arg 7, "[Tag N, ...]"),
replacing the cover subline — the counts ARE the subline. The standalone
"What landed today" section at the bottom of Home is gone; its story moved up.

- Composed by `coverChips` (HomeComposition): today-only, count-ordered, max 5.
  Approvals never count (same guardrail as the cover lead). Nil when nothing
  landed today — the quiet cover states that in words, and the word subline
  returns ("project · time" on the image cover, "Kind · Source" otherwise).
- The weekend cover carries NO chips: it is a week recap and its subline
  already tells that story; today-only counts would misread as the week.
- Rendered by `KindCountRow` (GenRenderer): 34pt capsule, kind hue at ~0.15
  fill, the kind's SF Symbol at 14pt, count in 13pt semibold cover ink.
  Kind colors come from KindGlyph — identity color, legal under the color rule.
- Tap a chip → Feed filtered to that kind (FeedFilter.tag + casberi://feed).
- `KindPills` stays in the Gen vocabulary (rendered by KindCountRow); no Home
  composition emits it anymore.
- The banner cover reserves 178pt (vs 250pt live capture) regardless of chips —
  height must never depend on the chips arg, which streams in last.

## 3. Composition order (HomeComposition.compose)

Morning / evening / weekend all keep their existing branching and data rules;
only the element lineup changes:

  cover (or fallback hero) → insight (when proven) → map (unchanged TagMap) →
  kindPills → themes/threads (unchanged Widget+Rows) → signals (unchanged Bento)

Weekend keeps its recap voice in the cover's eyebrow ("WEEKEND") with the
week's newest image.

## Non-negotiables

- Treemap untouched: `GenTagMap` as-is — magnitude tint, plain labels. Do not
  add sublines, counts, or images to cells.
- Tokens only; the only new color logic is the image-extracted cover bleed.
- No obligations voice (see guardrails above).
- Everything still streams through GenStream with skeletons; the cover's
  skeleton is a `fillFaint` block whose height (250/140) is decided before
  first paint — the header never jumps as the stream resolves.
- Existing navigation intact: avatar → Settings, grid → Apps (attention dot
  grammar unchanged), genProjectTap → ProjectDetail, zoom transitions kept.
- No fixed heights except the cover's minHeight: 250.

## Implementation order

1. `Cover` Gen element + color extraction (behind the existing Hero data rules).
2. Swap HomeComposition lineups (cover replaces hero; kindPills replaces kinds).
3. Kind pills element + Feed-filter tap route.
4. Theme fallbacks (no-image gradient, photo-wallpaper scrim case).
