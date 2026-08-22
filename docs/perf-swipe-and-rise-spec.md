# Perf pass 5 — room swipes, and the agent rise (2026-08-21)

> **STATUS: BUILT.** What shipped is recorded at the bottom under "What was
> built"; the spec below is kept as written so the reasoning that chose each
> fix stays legible next to what it became. **No number has been taken** — per
> the standing user ruling this shipped on build + audits + code reasoning, and
> every change is structural (work removed or reordered), not tuned. The two
> instruments exist precisely so the next person can measure rather than guess.


Two reported symptoms, spec'd against the code as it stands at `99d6bf48`:

1. **"Lag swiping between screens."**
2. **"The agent launching is still janky — for a split second it tries to launch the
   composer only, and you see a greeting glitch on top of the composer before the
   brief shows."**

Standing method from the four prior passes (see memory `foreground-sweep-jank.md`,
whose filename is wrong and whose body is the record): **build the cheap instrument
before the plausible fix; the `sample` profile is the truth and accumulators lie;
interleave A/B arms on a drained synthetic corpus; a metric measuring the wrong
span reads clean.** Both symptoms here are OUTSIDE every span `perf.sh` times —
which is why four green nightlies coexist with this report.

Already fixed — do not re-propose: `allRoomFetchLimit` (08-06), `newestPerSource`
(08-06), the source-rail memoisation (08-11), the chip-tap corpus scoping (08-13),
the typewriter budget (08-16), the cached-doc yield + 250ms hold + paged chip scan
(08-18), `handingOff` (08-16) and the rest-greeting's `!handingOff` gate (08-17).

---

## Symptom A — room swipes

### Mechanism (read from source, not yet measured)

A swipe is a discrete step (`MainSurface.step` → `go(to:)` → `filter.source`),
and the surface renders ONE `FeedScreen` under `.id(filter.source)` with an
asymmetric move transition (`MainSurface` ~1608–1616). Three costs land inside
the slide animation's own frames, all on the main actor:

1. **A fresh, unbounded materialisation per swipe.** Every swipe destroys and
   rebuilds `FeedScreen`, whose source-room `@Query` is deliberately
   **unbounded** (`FeedScreen` ~207–228, ruled 2026-08-14: `sourceHead`/treemap/
   leaderboard must see the full room, so `fetchLimit` was written and taken
   back out; only `propertiesToFetch` bounds it). Materialising SwiftData models
   at scale is the measured 52%-of-main-thread class from 08-06. This cost
   **grows with every import** — an X archive (10k cap), Instagram, the journals
   — and is paid mid-gesture, which is exactly when the main actor is also
   supposed to be animating a full-screen move.
2. **Head/derivation composition is synchronous in the body.**
   `shapedSections` (~2405–2513, called from `feedList` at ~2135) computes
   `sourceHead(visible)`, topicMap, leaderboard, distribution, mosaic inline —
   `XRoom`'s whole-span scan, treemap cell assignment, etc., over the full room,
   on the first body evaluation of the incoming screen.
3. **Two live screens during the transition.** The move transition keeps the
   outgoing `FeedScreen` mounted (with its live `@Query`) while the incoming one
   mounts. Any corpus write landing in that window re-renders both.

### Phase 0 — instrument (do this before any fix)

- **`swipePerf|`** (DEBUG, the `askPerf|` shape): one NSLog trace per step —
  `step()` fired → incoming `FeedScreen.init` → first body complete →
  `shapedSections` duration → first row frame (`onAppear` of the first row).
  Reported line in `perf.sh`'s section, **never a CSV column** (field-position
  parsing, the 08-16 lesson) and never gating.
- **Interleaved `sample` A/B** on the established harness: dedicated sim device,
  synthetic 6k-row X archive, two drain launches, then swipe into the X room
  repeatedly while sampling the main thread. This tells us the split between
  materialisation (cost 1) and composition (cost 2) — the fixes for each are
  different, so the split decides the order.

### Phase 1 — fixes, ranked (each behind its own measurement)

1. **Two-phase query mount — bound the transition, not the room.** The incoming
   `FeedScreen` mounts with a bounded descriptor (~120 rows ≈ 4 render windows;
   rows are windowed at 30/step anyway, so the first paint is pixel-identical),
   then swaps to the unbounded descriptor in a `.task` once the transition has
   settled (~350ms, measured not guessed). **The 08-14 ruling stands untouched**:
   heads and derivations are *gated on the full set being present* (nil head for
   ~1 frame-batch, exactly like a head that declines) — never composed over the
   slice, so no §83 exposure and no new user ruling needed. This converts the
   swipe-blocking cost into a just-after-swipe cost.
2. **Move head composition out of the body.** `sourceHead`/topicMap/leaderboard
   become a per-source cached value computed in a `.task(id:)` keyed on
   (source, count), painted when ready. The head sources are Foundation-only
   pure functions — safe over a value snapshot. **Liveness corollary 6 applies**:
   the snapshot crosses a suspension, so `.live` re-filter at use (the 08-13
   lesson: any perf move that hoists or defers a fetch is a liveness change).
3. **Kill the double-mount cost** if the sample shows the outgoing screen
   contributing: render the outgoing side of the transition as a bitmap snapshot
   (`UIGraphicsImageRenderer`, `format.scale = 1` per the standing gotcha) or an
   inert copy, so exactly one live `@Query` exists mid-slide.
4. **Per-room render cache** (only if 1–3 leave a felt gap): the shell keeps the
   last-rendered window of surrogate rows per source (`AgentOpenCache` shape,
   in-memory), painted instantly on re-entry while the query loads. Honest — it
   is literally what the room showed last visit — and heals when the query lands.

### Guards that will notice these changes

`markets-fold-selftest.sh` greps `MainSurface` (pin the invariant, not a call
site's spelling — its 08-11 rewrite already covers renames); the SwiftData
liveness audit's checks 3/4/6 will see the new snapshot handoffs — keep new row
wrappers in `KeyedThing` shape so check 3 can see them.

---

## Symptom B — the agent rise

### What the report means against the current code

Three prior fixes each closed part of this, and the report survives them. The
remaining window, read from source: every brief door seeds `chrome.askRequest`
**before** raising (audited: berry tap ~1985, whisper ~1873, `casberi://brief`
~2168, `casberi://ask` ~2187, quick action ~1651 — all seed-then-raise), and
`handingOff` suppresses the rest greeting from frame one. So what's left on
screen during the handoff window (120ms settle + `TodayBrief.compose`, which is
`@MainActor`) is an **empty bubble** — "it tries to launch the composer only" —
and then, when `commit()` flips `answering`, the brief landing's masthead and
its `clockGreeting()` mount all at once with `settleIn` entrances, **before any
document content has painted** (the §386k cached paint covers this only when
`TodayBrief.lastPresentedDoc` exists — verify whether it survives a launch; if
it is memory-only, every first open of a session has no cached doc and hits the
worst case). That masthead-greeting-alone state, followed by the doc arriving
and displacing it, is the most likely "greeting glitch on top of the composer."

Second candidate: `.animation(DS.Motion.standard, value: composerOpen)` sits on
the whole shell (`RootShell` ~1314), so every state flip landing during the rise
window animates implicitly on top of the entrances the views declare —
double-animation reads as a glitch even when the states are right.

Third candidate (cheapest to rule out): a door that raises without seeding —
`chrome.composerRequest` (~1319) and Control Center's `compose.request` (~1598)
raise bare. Both are deliberate ask-only doors, but if the user's tap ever
routes through one, the true rest greeting gets its frames back.

### Phase 0 — instrument

**`risePhase|`** (DEBUG): one NSLog per state flip with ms-since-raise —
`composerOpen`, `handingOff`, `pendingHandoff`, `answering`, `briefLanding`,
masthead mounted, first doc paint (wire into the existing `askPerf|` bracket).
One open produces one readable trace that says which of the three candidates is
on screen during the glitch. Run via `-composerCycles` for warm and cold opens,
and once on a device — the sim has no on-device model, so compose timing there
is not the shipped timing.

### Phase 1 — fixes, by what the trace shows

1. **Rise INTO the brief shell, not into an empty bubble** (fixes the empty
   window and the masthead pop in one move). When the pending request is the
   brief (`TodayBrief.matches`), the composer's first frame renders the brief
   landing's chrome — masthead with title, dock, skeleton — so `commit()`
   changes *content inside a stable frame* instead of mounting new chrome
   mid-rise. The mechanism half-exists: `risingBriefTitle` is the whisper door's
   proxy masthead (~1875, "the real masthead doesn't exist for another 400ms+")
   — generalise it to every brief door instead of whisper-only.
2. **Persist `lastPresentedDoc`** (if Phase 0 confirms it's memory-only): store
   the last presented brief doc on disk so the cached paint is universal,
   stamped and honest ("as of" — the doc already handles staleness for live
   reads). Then the first open of a launch paints yesterday's brief instantly
   and streams the fresh one over it, which is the §386k design finishing.
3. **Scope the implicit shell animation**: replace the shell-wide
   `.animation(value: composerOpen)` with explicit `withAnimation` at the raise
   sites, so mid-rise state flips (handoff, answering) stop inheriting a
   transition they never asked for.
4. **Keep compose off the morph's frames**: the 120ms settle predates the
   measured morph duration — measure the transition, and either extend the
   settle to cover it or chunk `TodayBrief.compose`'s corpus pass with yields
   (the `AgentChipFacts.scanPaged` precedent: same total cost, interruptible).

### Guards

`ask-scope-selftest.sh` pins the settle ordering (fetch below paint,
`askGeneration` re-guard) — any reorder here must keep it green, and if the
settle moves, move the guard's reason with it.

---

## Sequencing

1. Land both instruments + the `perf.sh` reported lines (no behaviour change,
   one commit).
2. Run the A/B harness for A and the trace for B; **write the numbers into this
   file** before choosing fixes.
3. Fix in measured order; one structural change per commit, each with its
   interleaved A/B or trace-diff.
4. Device check at the end — every prior pass shipped sim-measured and the user
   ruling is build+audits+reasoning, but B's felt jank is animation-frame timing
   the sim genuinely distorts; one device trace closes it.

Non-goals: no tuning knobs, no re-litigating the 08-14 no-fetchLimit ruling
(deferred ≠ truncated), no touching the retired pager (§265 removed the class —
the discrete step stays).

---

## What was built (2026-08-21)

Eight changes across six files, plus one new guard and two new instruments.
Every one removes or reorders work; none tunes a threshold.

### Symptom A — the swipe

**A1. The room head is memoised, and the memo survives the remount.**
`FeedScreen.shapedSections` derived the whole head chain inline — `sourceHead`,
then `FeedInsight`'s topicMap / leaderboard / distribution / mosaic — meaning
once per body evaluation, over the room's entire contents. §265 made a room
change a *remount* (`MainSurface` carries `.id(filter.source)`), so every swipe
paid all of it from zero, several times, on the main actor, inside the frames
the slide animation needed.

Now: `FeedScreen.recomputeHeads()` runs in a `.task(id: headKey)` and stores its
answers in `heads`, seeded from a **static** `headMemo` keyed by source. Static
is the invariant, not a style choice — `@State` is destroyed by the very
remount this exists to make cheap, which is why the old code could never
amortise anything. A room you have visited paints its head immediately; a room
you have not shows none until the computation lands, which is the same nothing a
head that *declines* already draws.

Three things this had to get right, each a way it could have been wrong:

- **Nothing cached holds a `Thing`.** `FeedInsight`'s four results are plain
  value types, and `SourceHead`'s cases carry room models whose own contract is
  that they hand back a value and let the view do the lookup. `liveStream` and
  `anniversary` *do* hold models, so they stay computed in the body — which is
  also why the gates stayed there, unchanged.
- **All five are computed unconditionally** where the body short-circuits, and
  that costs nothing: each registry switches on `source` and the registries
  deliberately don't intersect, so at most one does real work per room. Paying
  four switch statements is worth keeping the ranking in exactly one place.
- **The key is a `COUNT`, never `things.count`.** That property is the `@Query`
  getter and materialises every row it counts — paying, in the cache key, the
  exact price the cache exists to avoid. `Corpus.revision(in:source:)` is new
  for this: a scoped SQL count plus the existing `CorpusSignal` term, so an
  in-place retag invalidates too.

**A2. The swipe bounds the incoming query, transiently.**
`MainSurface.swipeRowBudget` is set to 150 rows *before* `filter.source`
changes (after would build the unbounded query once and throw it away — the
whole cost, paid and discarded) and released ~360ms later by a task keyed on the
source. `FeedScreen.rowBudget` applies it to the query in `init`, and is part of
`FeedScreen: Equatable` — without that the bound would never lift.

**This does not reverse the 2026-08-14 "no permanent `fetchLimit`" ruling.**
That ruling refuses a bound because a head computed over a truncated slice is a
claim about the whole room that isn't true. Nothing here is computed over the
slice: the head task declines outright while the budget is set. Deferred, never
truncated. 150 is arithmetic rather than taste — the feed windows at 30 rows, so
the first paint is pixel-identical with four spare windows nobody can open
inside a slide.

### Symptom B — the rise

**B1. The open rises into the answer's own frame.**
Every brief door already seeds `chrome.askRequest` before raising, and
`handingOff` already suppressed the rest greeting — so what was left was an
**empty bubble**, because every band in `openBubble` is gated on either
`restChrome` or `answering` and during the handoff neither holds. Then
`commit()` flipped `answering` and the brief masthead mounted as a *new band in
its own transaction*: a greeting and a date, alone above a skeleton. That is the
reported "greeting glitch" — empty, then a greeting, then the document, three
surfaces for one tap.

The handoff window now renders the same header the live turn will wear
(`turnHeader`) over the same skeleton it will wear (`answerSkeleton`), both
extracted so the rising frame and the real one cannot drift into looking like
two screens. `commit()` then changes only the *content* inside a frame that is
already standing. `risingFramePainted` suppresses the live turn's question lift,
which is the felt hand-off from field to answer — right for a typed ask, wrong
when the header is already standing where it would slide up to.

It stands down when `chrome.risingBriefTitle` is set: the whisper capsule flies
its own proxy title with `matchedGeometryEffect(id: "whisperTitleMorph")` in the
same namespace, two live views sharing one matched id is undefined, and that
choreography is already approved.

**B2. `TodayBrief.lastPresentedDoc` survives the launch.**
§386k shipped it in memory only, which reserved the worst case — nothing to
paint, so scaffolding until the corpus compose returns — for the *first open of
every launch*, i.e. the most common tap. It is now kept for the calendar day.
**The gate is the calendar, not a timeout**: this document is about today, so a
doc composed today describes today at any hour, and one composed on another day
describes a day that is over. No age threshold to re-litigate.

### The instruments

`SwipeClock` (`swipePerf|`: step → mount → heads → rows) and `Composer`'s
`risePhase|` (raise → consumed → commit → firstDoc). Both DEBUG-only. They exist
because both symptoms sit outside every span `perf.sh` times — which is how four
green nightlies coexisted with the report, and is this project's own recurring
lesson: *a metric measuring the wrong span reads clean.* Neither is a
`perf-history.csv` column, deliberately: that file is parsed by field position.

### The guard

`scripts/room-perf-selftest.sh` — 37 checks, 9 mutations, wired into
`verify.sh`. It pins the two conditions that make the removals correct and that
nothing else can see: the cache holds no `Thing`, and the head never computes
while the budget is set. Both failures build green, pass every audit, render
perfectly, and are simply wrong.

### Things found on the way

- **A drift guard pinned to a call site, not an invariant.**
  `chatimport-selftest.sh` demanded the literal
  `FeedInsight.topicMap(source: source, things: visible)` and went red when that
  call moved out of the body — a change to *when* the map is consulted, not
  *whether*. Rewritten to prove both halves (the call exists, and the head chain
  reads its answer) and mutation-checked. Same lesson the 2026-08-11 pass wrote
  down about `markets-fold-selftest`: a guard should pin the invariant, not one
  call site's spelling.
- **The new guard's own comment-stripper ate code.** Spelled the gap before
  `//` as `\s*`, and `\s` matches a newline — so it ran from a code character on
  one line to a `//` several lines below and deleted everything between.
  Thirteen checks reported MISSING against source sitting right there. A
  stripper that eats code is a guard that fails for reasons unrelated to the
  rule it protects.
- **The mutation pass wrote to the tracked tree, and lost a line.** The first
  cut mutated the real `FeedScreen.swift`; `set -e` killed the run mid-mutation
  and the restore never happened, deleting the single most load-bearing line in
  the pass (`guard rowBudget == nil`) from the working tree. On a public remote
  with an auto-pushing post-commit hook and another session live in the same
  tree, that is a genuine hazard, not an inconvenience. The pass mutates
  **copies** now, so the window does not exist rather than being narrow.

### Deliberately not done

- **Snapshotting the outgoing room during the transition** (spec fix A3). It is
  a real cost — two live `@Query`s mid-slide — but the sample was going to
  decide whether it matters, and no sample has been taken. Proposing it without
  one is the "plausible fix before the cheap instrument" mistake this project
  has a standing rule against.
- **A per-room render cache of surrogate rows** (spec fix A4). Only worth it if
  A1+A2 leave a felt gap.
- **Generalising the rising frame to non-brief handoffs.** The same mechanism
  would work for "Ask about this" from a thing sheet, but those are rare, the
  question text is its own header, and the brief is what was reported. One
  screen, one report, one fix.
- **Scoping the shell's `.animation(value: composerOpen)`.** Ruled out by
  reading rather than left open: an implicit `.animation(_:value:)` only
  animates changes in the transaction where `value` itself changes, so the
  mid-rise flips at +120ms are separate transactions and never inherited it.

### What still needs a device

The rise is animation-frame timing, which a simulator distorts. `risePhase|` on
a real device — a cold first open (no cached doc) and a same-day re-open (cached
doc) — is the reading that would close it. `swipePerf|` plus one interleaved
`sample` A/B on the 6k-row synthetic corpus is the reading for the swipe.
