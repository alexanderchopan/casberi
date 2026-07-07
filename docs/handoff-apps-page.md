# Handoff — Apps page (store anatomy, M4)

For Claude Code. Companion to `handoff-shaped-feeds.md`. Applies to
`Screens/AppsScreen.swift`; `Screens/CatalogScreen.swift` gets DELETED (it
duplicates the directory and is only reachable from a debug probe — fold its
debug hook into AppsScreen).

## The problems being solved

1. 20 apps across ~12 groups → section headers for singletons ("YOUR WALLET", 1 row).
2. 17 of 20 offers are "Soon" — the directory is a wall of promises with three doors.
3. The featured hero is hardcoded Zerion forever and features a non-connectable app.
4. Brand color confined to 44pt icons; the one marketing surface reads as a settings list.

## The new anatomy (mock M4 — approved)

Top to bottom, one scroll:

1. **Large title** "Apps".
2. **CONNECTED strip** — unchanged from today (44-56pt `BridgeIcon` chips,
   status dot, name below; tap → BridgeDetail / ZerionScreen). Paused bridges
   render at 50% opacity with "Paused" as the label. This strip is the
   management door; it never merchandises.
   Below it, a `fillLine` hairline divider and a "Discover" heading
   (heading22, with a quiet "N to connect" count trailing) — management above
   the line, store below it. The strip and the stories must never read as one
   section.
3. **Story carousel** — swipeable full-width editorial cards (page dots below).
   2-3 stories max. Card: brand-gradient background (the ONE place brand
   gradients are legal — same license as today's featuredHero), eyebrow
   (label12 kerning 1, e.g. "NEW BRIDGE" / "PAIR A CLIENT"), a 24-28pt
   two-line pitch headline in Bob's words ("Your wallet, in your week."),
   footer row: icon well + name + white capsule action (Connect/Pair).
   - LAYOUT LAW — no fixed heights anywhere in the card. The card is a
     VStack(alignment: .leading, spacing: DS.Space.s3) with .padding(DS.Space.s4)
     on all sides: eyebrow → headline → footer row, nothing absolutely
     positioned, no .frame(height:), no .clipped() on content. The padding
     defines the bottom edge, so the footer can never be cut off.
   - Equal heights across the carousel: give every card
     .frame(maxHeight: .infinity, alignment: .topLeading) inside an
     HStack(alignment: .top) + .fixedSize(horizontal: false, vertical: true)
     on the HStack — all cards stretch to the tallest one's intrinsic height.
   - Headline: .dsText style at 24pt weight .heavy, .lineLimit(2),
     .minimumScaleFactor(0.7) — long copy scales, never wraps to a third line
     or clips. Verify at the largest accessibility Dynamic Type size.
   - Card width: screen width minus DS.Space.s4 * 2, next card peeking ~12pt.
   - Story selection rules, in order: (1) newly connectable bridge not yet
     connected; (2) Pair-a-client if no client paired; (3) highest-value
     unconnected connectable. Never feature a "Soon" app. Never repeat a
     dismissed/connected story.
   - The Pair-a-client story REPLACES today's pairEntryRow (one door, richer).
4. **Browse shelf** — horizontally scrolling category pills: 44pt height,
   radius `DS.Radius.control`, `surfaceSheet` fill, leading glyph in the
   category's exemplar brand color, name (callout15 medium), count
   (subhead13 tertiary). Tap → the For-you chart filtered to that category
   (same list, scrolled/filtered — not a new screen).
   - Categories are a MERGE MAP over `BridgeCatalog.Offer.group` (add
     `category` or a static map): Your life = photos+schedule+wallet ·
     Your agents = agent+machines · Your mail = mail · Your work = work ·
     Your media = saves+watching+listening+messages.
5. **"For you" chart** — one ranked list, App-Store-charts grammar:
   rank number (17pt bold tertiary, 20pt column) · 44pt BridgeIcon ·
   name (17pt semibold) + one-line subline · trailing capsule.
   - Rank order: (1) connected-but-broken → "Fix" (attention capsule);
     (2) connectable not connected → "Connect" / Claude → "Pair" (tint capsule,
     white text); (3) connected healthy → "Open" (confirm-dim capsule);
     (4) coming → "Soon" (fillFaint, tertiary text; row title dims to secondary,
     icon well goes fillFaint/gray glyph).
   - Sublines are honest states or the offer tagline, never marketing fluff:
     "Needs reconnecting" / "Connected · working" / tagline for the rest.
6. Row tap (anywhere but the capsule) → `AppDetailScreen` unchanged.

## Non-negotiables

- Tokens only; the story-card gradient is the sole brand-gradient license,
  identical in kind to the existing featuredHero gradient.
- Capsule verbs are honest: Connect / Pair / Fix / Open / Soon — never "GET".
- No counters or badges beyond the existing attention dot grammar.
- Categories never render as vertical section headers — the merge exists only
  in the Browse shelf and as a chart filter.
- Text ramp: title 34, story headline 24/heavy, rows 17/13, eyebrows label12
  kerning 1. Hit targets ≥ 44pt.
- NO fixed heights on any card, tile, or row in this screen — every container
  sizes to its content plus token padding. If a design height is wanted, use
  minHeight only. This is what prevents clipped footers at any type size.

## Implementation order

1. Merge-map + ranked "For you" chart replacing the grouped directory (biggest win).
2. Capsule verb component (Connect/Pair/Fix/Open/Soon) shared with AppDetailScreen.
3. Story carousel (replace featuredHero + pairEntryRow) with selection rules.
4. Browse shelf + chart filtering.
5. Delete CatalogScreen; move its debug probe to AppsScreen.
