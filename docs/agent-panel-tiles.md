# Agent panel tiles — identity, density, honesty (2026-08-07)

Written by Fable for Sonnet to execute. Baseline: commit `e2c7d42` (the §342
motion pass) — everything here builds ON the paint-clock choreography, never
around it. Read `docs/agent-panel-motion.md` §"Architecture" first: its one-
clock contract is a constraint on every item below.

**Files you will touch:**

- `Casberi/Casberi/Screens/AgentPanelGrid.swift` — the tiles (badge, well,
  figure renderers, captions).
- `Casberi/Casberi/Model/AgentPanel.swift` — the `Figure` enum and pure logic.
  **Foundation-only, compiled WHOLE by `scripts/agent-panel-selftest.sh`** —
  no SwiftUI/UIKit types may enter this file, and every pure change gets a
  fixture plus a mutation there.
- `Casberi/Casberi/Shell/Composer.swift` — `buildPanel`/`roomFigure`/
  `walletCurve`/`crossSourceCards` (compose-time data).
- `Casberi/Casberi/Design/KindGlyph.swift` — `BridgeGlyph.symbol(for:)`.
- `scripts/agent-panel-selftest.sh` — fixtures, mutations, one new static
  coverage check.

**Ground rules, all load-bearing:**

1. Every new visual element joins the EXISTING `paint` clock via `phase(from:
   to:)` — no second `withAnimation`, no own `@State`. Structure 0–0.25, data
   0.15–0.80, meaning 0.70–1.0. Reduce Motion already collapses `paint` to 1
   instantly; anything you add must look correct in that settled state with
   zero animation.
2. `scripts/verify.sh --build-only` green before calling anything done — the
   design-motion audit and agent-panel selftest both run in its static head.
3. `docs/prd.md`: another session may have an uncommitted §327 block in the
   working tree. Before committing, check `git diff docs/prd.md` — if §327 is
   there uncommitted, park it (extract to /tmp, remove, commit yours, restore
   uncommitted). Your entry takes the next free § number at the file's end.
4. Do NOT touch the demo-mode session's in-flight files (`DemoMode.swift`,
   `DemoSeedAll.swift`, `AppVisit.swift`, `AskMemory.swift`,
   `BriefLedger.swift`, `WalletStore.swift`, `AccountScreen.swift`,
   `RootShell.swift`, `docs/demo-spec.md`) — stage only your own.
5. The simulator already holds the seeded demo corpus. Verify visually ONCE at
   the end: `xcrun simctl launch <udid> com.casberi.app -openComposer YES`,
   screenshot, compare against the acceptance list. (Pin the udid —
   `xcrun simctl list devices booted`.)

---

## 1 · A real mark on every source tile (P0 — the user's explicit ask)

**The defect.** The corner badge draws `BridgeGlyph.symbol(for: card.source)`
(`AgentPanelGrid.swift` ~line 181), and that table's `default:` returns
`"app"` — a generic grid glyph that says nothing. Two classes of card land on
it today:

- **Sources missing from the table.** At minimum: Stripe, PostHog,
  Cloudflare, Cursor, Stocktwits, Hugging Face, Circle x402, Messages,
  WhatsApp, Telegram. Do not trust this list — run the coverage check you
  will build (below) and fix everything it reports.
- **Cross-source cards** (`crossSourceCards` in Composer.swift, ~line 1083)
  carry `source: "All"` — the Day Dial, Theme River, Semantic Map. They wear
  the generic badge in a hue that means nothing.

**The fix, three layers:**

(a) **Fill the table** in `KindGlyph.swift`, following its own conventions
(one glyph per seat, no two Work seats sharing, comments only where the
choice needs defending). Decisive picks — use these, don't re-litigate:

```
case "stripe":       return "banknote"            // money moving
case "posthog":      return "chart.bar.xaxis"     // readings over time
case "cloudflare":   return "cloud.fill"          // the name is the mark
case "cursor":       return "cursorarrow"
case "stocktwits":   return "bubble.left.and.bubble.right"
case "hugging face": return "face.smiling"        // the name is the mark
case "circle x402":  return "dollarsign.circle"   // pay-per-call
case "messages":     return "message.fill"
case "whatsapp":     return "phone.and.waveform"
case "telegram":     return "paperplane.fill"
```

Anything else the coverage check reports: pick by the table's conventions and
comment only the non-obvious ones.

(b) **Cross-source cards stop wearing a brand badge.** In `tile()`, when
`card.source == "All"`, the badge shows a FIGURE glyph on `DS.tint` (the
person's accent — the corpus is theirs, not a brand's):

```
.dial → "clock"    .river → "water.waves"    .scatter → "sparkles"
.treemap → "square.grid.2x2"    anything else → "circle.grid.2x2"
```

Implement as a small private func in AgentPanelGrid (view-layer choice, stays
out of the model).

(c) **Monogram backstop.** In the panel ONLY (leave `BridgeGlyph`'s default
alone — settings chips use it too): if `symbol(for:)` returns `"app"` for a
non-"All" source, render the source's first character (uppercased, `.system(
size: 9, weight: .bold)`, white) on the hue disc instead of the generic
glyph. Precedent: App Store Connect's mark is deliberately a letter
(KindGlyph.swift ~line 231). A letter is a mark; a generic grid is an
apology.

**The mechanical guard** (this is what makes "always present" true next year,
not just today): add a static coverage block to
`scripts/agent-panel-selftest.sh` that extracts every offer NAME from
`BridgeCatalog.offers` (`Model/BridgeCatalog.swift` — grep the `name:` string
literals) and every `case` string from `BridgeGlyph.symbol`, lowercases both,
and fails listing any offer with no case. Empty allowlist to start — if an
offer genuinely can't panel, add it WITH a reason comment. Self-test the
check: inject a fake offer name into the extracted set and prove it fails.

Also extend `-agentOpenProbe`'s per-card line with `mark=<symbol|MONOGRAM>`
so a fallthrough is visible in one launch.

---

## 2 · The wallet hero earns its height (user: "a lot of space for a simple
sparkline", then "treemap of holdings is useful there i think no?")

The hero is a double-height cell showing one line and one sparkline over a
big empty gradient. The wallet already KNOWS more: the holdings composition
the Wallet room's own treemap draws. Put worth and what-it's-made-of on one
card.

**Model** (`AgentPanel.swift`): new case

```swift
/// The wallet's own hero — worth beside what it's made of. The one
/// composite figure, and hero-only: at any smaller slot it collapses to
/// two crushed halves.
case worth(curve: [Double], cells: [Cell])
```

- `fit(.worth)` → `.large`. `isEmpty` → `curve.count < 3 || cells.count < 2`.
- Selftest: fixtures asserting both, plus a mutation flipping `fit(.worth)`
  to `.any` that a fixture must catch (assert on `fit` directly — the §340
  lesson: assert on the function that changed, not through `rank`).

**Compose** (`Composer.swift`, `walletCurve()`): keep everything §341 built
(24h window, honest label, `AgentPanel.compactUSD`). Then read the SAME
cached holdings snapshot the Wallet room's treemap draws — cache only, and
NEVER trigger the metered read (`HoldingsCache` is §216's window; the panel
spends nothing). Top 4 tokens by USD value → `Cell(label: symbol, weight:
Int(usd))`. With ≥2 cells emit `.worth(curve:cells:)`; otherwise fall back to
today's `.curve` exactly as-is — a hero with less data degrades to the
smaller true figure, never pads.

**Render** (`FigureView`): inline, reusing the two existing renderers — no
new struct, no new clock:

```swift
case .worth(let values, let cells):
    HStack(spacing: DS.Space.s2) {
        curve(values).frame(maxWidth: .infinity)
        treemap(cells).frame(width: /* 42% of available */)
    }
```

Use a GeometryReader for the 58/42 split. The curve keeps its pen-tip
phases; the treemap rows keep their stagger — both already read `phase()`,
so the composite choreographs itself.

---

## 3 · Chips read as data, not buttons

The proportional treemap rows (`treemap()` in FigureView, ~line 316) are the
"Focus 4 / Orthogonal 310" chips. Two problems: saturated fills + bold white
text read as tappable buttons (honesty: they're not — the TILE is the
button), and the count renders inside the pill on the leader only, so
"Orthogonal 310" reads as one token and the second row looks countless.

- Fills drop a step: leader `hue.opacity(0.32)`, step `−0.07` per rank (was
  0.44/−0.09). Ranked tone survives; the button read doesn't.
- **The count moves OUTSIDE the pill, on every row**: label inside, count in
  `DS.textTertiary` + `.monospacedDigit()` just past the pill's trailing
  edge. The pill's width already says the proportion; the number beside it
  says it precisely, and they can no longer fuse into "Orthogonal 310".
- Leader stays `.callout15` semibold, tail `.subhead13` regular — unchanged.

---

## 4 · A wall is never four gray boxes (the "6 pins" tile)

`wall()` renders 2×2 `AsyncImage`s whose placeholder is a bare `DS.fillLine`
rect — so a room whose images are remote and slow (Pinterest) draws four
blank boxes that read as broken.

- **Model**: `.wall([String])` becomes `.wall([WallTile])`, `struct WallTile:
  Equatable { var url: String; var label: String }`. Composer's call site
  (~line 1191, `wall.tiles.prefix(4).map(...)`) passes each tile's title
  through too (the mosaic tiles carry one — check `FeedInsight`'s mosaic
  struct and use its title field; empty string if it truly has none).
- **Render**: the placeholder shows the tile's label — `.subhead13`,
  `DS.textSecondary`, centered, `lineLimit(2)`, padding 4 — so the loading
  state is content, not absence. The image replaces it on arrival.
- **Gate** (pure, in `isEmpty`): a wall qualifies only if ≥2 tiles have a
  non-empty label or url. Fixture + mutation in the selftest (feed a wall of
  empty labels → must be empty; delete the gate → fixture fails).

---

## 5 · The rail's leading word carries its count

The status figures ("• Pending", "• Bullish") say the word and hide the
number. `rail()`'s leading-segment line becomes "Pending · 3" — the
segment's own count, `monospacedDigit`, the count in `DS.textTertiary`.
`AgentPanel.Segment` already carries the value; if its field is a weight
rather than a count, thread the count through at compose (check the struct
first, don't guess).

## 6 · A bare count names its window

"8 posts" is a count; "8 posts · 7d" is a rate — §341's window-label ruling
applied to captions. In `roomFigure`/`crossSourceCards`, where the caption is
a bare count AND the figure composed over a named constant window (the dial's
`days`, the river's `weeks`, the pulse's day span), append ` · <n>d`. Where
the window isn't a named constant, leave the caption alone — never guess a
span (§83).

## 7 · The badge never covers figure text

The leaderboard's trailing numbers run under the corner badge ("4,820"
clipped on the demo corpus). In `barsView`, the FIRST row's trailing detail
gets `.padding(.trailing, 22)` when `slot != .band` (bands hide the corner
badge already). Don't blanket-inset the whole figure — bars and curves may
run under the badge (shapes survive overlap; text doesn't).

## 8 · One vertical alignment for row figures

`treemap()` top-aligns (dead space below the chips), `barsView` bottom-aligns
(leading `Spacer`). Pick CENTER for both: wrap each in a VStack with
`Spacer(minLength: 0)` at both ends. Symmetric margin reads designed;
asymmetric reads accidental.

---

## Acceptance (run in order)

1. `scripts/agent-panel-selftest.sh` — new fixtures green, every new mutation
   caught, the glyph-coverage check passes AND fails when self-tested.
2. `scripts/design-motion-audit.py` — 0 findings.
3. `scripts/verify.sh --build-only` — green end to end.
4. Simulator, demo corpus, `-openComposer YES`, one screenshot: every tile's
   badge is a real mark (no generic grid glyph anywhere); the hero shows
   curve + holdings side by side with the §341 reading; chips show counts
   beside pills; the pins tile shows words while images load; no text under
   any badge.
5. `-agentOpenProbe YES` — every card logs `mark=`, none say the generic.
6. prd entry (next free §), park/restore §327 if present, commit + push ONLY
   (no TestFlight without a separate explicit instruction).
