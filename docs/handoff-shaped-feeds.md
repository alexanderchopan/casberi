# Handoff — Shaped Feeds (Feed screen, per-source compositions + kind-aware All)

For Claude Code. Read alongside `docs/build-brief.md` and `docs/prd.md`.
Decisions below were made against rendered mockups (A/P/Z/C/G variants reviewed);
this doc is the source of truth for the Feed screen and the PATTERN for deriving
sources not specified here (Safari, Notes, You, OpenClaw, Bankr).

## The problem being solved

Feed's source chips only change WHICH rows show (`FeedFilter.source`), never HOW
they show. Every source renders the identical `FeedRow`. Filtering to Photos gives
a text list of photo titles. The chips change the query, not the shape.

## The rules (add to the feed's doc comments)

> 1. When one source is in force, the feed takes that source's native shape.
> 2. "All" renders KIND-AWARE ROWS: each thing borrows a whisper of its
>    source's shape (time-led events, verb-led txs, thumb-led photos,
>    snippet mail) while keeping row height and rhythm. Only `.approval`
>    things break row rhythm — they render as consent cards.
> 3. One engine: shapes are GenUI compositions (the grammar Home and Zerion
>    already paint), composed by a per-source recipe. No new rendering system.

## Architecture

- New file `GenUI/SourceComposition.swift` — mirror of `HomeComposition`:
  `static func compose(source: String, things: [Thing]) -> [String]` returning
  gen-doc lines. `FeedScreen` streams it through a `GenStream` when
  `filter.source != "All"`; for "All" it swaps `FeedRow` for `KindRow` (below).
- Day grouping, pinned section, swipe verbs, the thing sheet, and the
  write-confirm ruling ALL survive inside shaped feeds. A shape changes row
  rendering and adds at most ONE synthesis block; it never invents new verbs.
- New Gen elements (add to `GenRenderer.swift` switch): `PhotoGrid`, `AgendaRow`,
  `TxRow`, `MailRow`, `CheckRow`, `TakeawayCard`, `ApprovalCard`, `KindRow`.
  Reuse `TagMap` for Zerion holdings. All styled like existing Gen views
  (surfaceSheet cards, `DS.Radius.widget`, the text ramp, `DS.tint(magnitude:)`).

## DECISION — Feed "All" (mock A2: kind-aware rows)

- Rows keep their rhythm within a TIGHT height set — titles wrap to at most
  two lines, never one, never unbounded (amended 2026-07-09: a one-line
  headline/caption hid the very content the row exists to show; unbounded
  wrapping let a pasted paragraph eat the screen). Two lines completes almost
  every real title; the rest lives a tap away in the sheet. Optional 13pt
  subline unchanged. Per kind:
  - event → right-aligned tabular time (58pt) + 3pt rail bar (past gray300 +
    strikethrough/tertiary, next `tint` + bold + "in N min" trailing, later gray200)
  - transaction → verb leads in a fixed column ("Swapped"/"Received"/…);
    amounts are the title; `Received` verb wears `DS.confirm`
  - screenshot/photo → 44pt thumbnail well replaces the kind glyph;
    source · project as subline
  - mail → kind glyph; subject title; one-line snippet subline; handled mail
    dims to secondary
  - everything else → today's universal FeedRow unchanged
- `.approval` things are the ONE exception to row rhythm: a consent card —
  provenance eyebrow (`APP · AGENT · MACHINE`, label12 kerning 1), bold title,
  the ask as subline, Approve (confirm green, black text) + Deny (fillFaint)
  pills. Approve/Deny = the existing S10 verbs; tap commits, no extra dialog
  (the card IS the consent surface).
- Machine-presence line (S11) stays above the chips as today.
- Discipline: no other kind may grow a card in All. If it wants a card, it
  belongs in its source shape.

## DECISION — Photos (mock P1: continuous grid)

- One unbroken 2-up grid (3-up past 12 items) — never per-day sections.
- Day labels are overlay pills (`#00000080` capsule, 12pt semibold) on the
  FIRST photo of each day only.
- A day with exactly one photo renders it full-width (~170pt).
- Title + project pill ride the image's bottom edge over a black gradient scrim.
- Tap opens the same thing sheet.

## DECISION — Zerion (mock Z1: treemap-first)

- The holdings treemap leads EVERY visit to the chip — exact `GenTagMap` from
  ZerionScreen (magnitude = `DS.tint(magnitude:)`, 6-frame grid, ~168-200pt).
  Eyebrow "HOLDINGS". No collapse behavior (Z2 was considered and rejected).
- Demo-gated like ZerionScreen: holdings block only when `DemoState.seedsDemoData`
  until live sync lands. No management copy in the feed (addresses live on
  ZerionScreen).
- Rows: verb leads in a fixed 66-74pt column ("Swapped" / "Received" / "Bought" /
  "Sent"); amounts are the title; chain · venue · detail as subline. `Received`
  wears `DS.confirm`; all other verbs textPrimary (color rule: state, never
  decoration). Day groups as usual.

## DECISION — Calendar (mock C2: no hero, emphasized next row)

- NO "Next up" hero card — it stated the same fact as the row below it
  (redundant-ink amendment). The next upcoming event's ROW carries the emphasis:
  bold tabular time, `tint` rail bar (34pt vs 26pt), semibold title, and a
  tint "in N min" countdown at the trailing edge.
- Rows: right-aligned tabular time (58pt) · 3pt rail · title + location subline
  · project pill / pin. Past events: gray300 rail, tertiary + strikethrough.
- Groups stay day groups ordered by EVENT time within the day; upcoming days
  ascending (Today, Thursday, Friday) — an agenda reads forward.

## DECISION — Gmail (mock G1: waiting cluster + subject rows)

- "WAITING ON YOU" cluster card at top: things marked `.doing` OR whose content
  asks a question / names a due date. Cap at 2; the rest stay in day groups.
- Rows: kind glyph well (mail glyph tinted; `.file` kind gets the file glyph),
  subject title, one-line snippet (content), project pill, short time.
- When real Gmail data carries senders, sender leads and subject drops to the
  second line — corpus has no senders, so subject-first ships first.
- Read/handled mail dims title to secondary. No unread badges, ever.

## DECISION — ChatGPT / Claude (earned cards)

- Pinned or `.doing` chats: takeaway card — project EYEBROW (label12 kerning 1),
  bold title, the saved synthesis line (content) at callout15. NO buttons on
  cards — verbs live in the sheet and swipes (existing ruling). Pin glyph
  trailing the eyebrow.
- All other chats: the standard compact FeedRow. Cards are earned, not default —
  20 saved chats must not render as a wall of paragraphs.

## DECISION — Reminders (state groups, time-sorted, stale collapsed)

- Groups: Doing, then To do — time-sorted within each. Todos older than 7 days
  collapse into one "Older · N" row that expands on tap.
- Leading 24pt circle is the verb: tap = mark done. Completing writes into
  Reminders → consent is inline: tap fills the circle, success haptic, chrome
  flash with Undo (5s). No modal for the lightest write.
- Done items strike and sink to a Done group showing same-day items only.
- Project pills keep cluster context.

## Deriving the remaining sources (the pattern)

Ask three questions per source:
1. What does the person actually want at a glance from this source? (the shape)
2. What is the ONE synthesis block it earns, if any? (most earn none)
3. What does a row lead with? (image / verb / time / subject / takeaway / circle)

Applying it:
- **Safari** → link rows: title bold, domain subline, saved/read dims. No block.
- **Notes** → the content is the row: title + first line, no glyph ceremony. No block.
- **You** → voice things get the waveform row (GenVoiceTile grammar) + duration;
  file things get a small thumbnail well. No block.
- **OpenClaw** → pending `.approval` things pinned first as the SAME consent card
  as All; then runs/jobs with a status tick (confirm green / destructive red),
  subline `machine · agent · run`. No other block — approvals ARE the lead.
- **Bankr** → rides the OpenClaw approval shape unchanged (same ask grammar).

## Non-negotiables (brief §8 / PRD, verified against the mocks)

- Tokens only: `DS.surfaceSheet` sheets, `DS.Radius.widget` cards, text ramp
  34/22/17/15/13/12, one tint via `DS.tint` (`#1673e6` accent).
- Chips stay text-only (ruling: no glyphs on chips). No counters on chips.
- Color carries identity, state, or magnitude — never decoration.
- Shapes render through GenUI so they stream with skeletons like Home.
- Swipe verbs remain reads-only; writes confirm (Reminders inline-undo is the
  approved lightest form; approval cards are their own consent surface).
- Keep `daySection` accessibility labels and existing zoom transitions.

## Suggested implementation order

1. `KindRow` + `ApprovalCard` in Feed "All" (highest-frequency win, no recipes needed).
2. `SourceComposition.swift` + FeedScreen branch; Photos `PhotoGrid` (proves the pipe).
3. Zerion (`TxRow` + embedded `TagMap`), Calendar (`AgendaRow`).
4. Gmail (`MailRow` + waiting-cluster derivation).
5. ChatGPT (`TakeawayCard`, pinned/doing only).
6. Reminders (`CheckRow` + inline-undo write).
7. Derive Safari / Notes / You / OpenClaw / Bankr from the pattern section.
