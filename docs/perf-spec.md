# Lightning-fast spec

*2026-09-01. Grounded in the six measured passes recorded in the perf memory (2026-08-06 → 2026-09-01) and a fresh survey of the tree at `076d9f6a`. Every claim below either carries a measurement or says it doesn't.*

## Where we are

The dominant cost class — `@Query` materialising the whole corpus on the main actor — was found by sampling (not by any accumulator) and fixed where it was measured: All room bounded at 1200, `MainSurface` at 400 + `newestPerSource()`, the chip strip's five redundant walks collapsed to one memoised snapshot, the ask path's kept-chip kinds scoped via `corpusNeed`, the typewriter's per-line reveal budget, the agent-open scan chunked, and (today, `78299dd0`) the swipe-budget/safety-net interaction, body-publish loops, `headIdentity` over-observation, and `previewImageData` short-circuits. Launch on the 6k-row reference corpus went 4.4s → ~1.4s (Debug, simulator).

**The single most important open fact: no number has ever been taken on real hardware in Release.** Every measurement above is Debug on a simulator. "Lightning fast" is a claim about a phone.

## Method (non-negotiable, each rule paid for)

1. **Sample first.** `sample` on the main thread against the sim process is the truth; `perfAccum` wall-clocks span work attributed elsewhere and has misrouted three sessions. `scripts/main-thread-profile.sh` works on the iOS sim build (the "Catalyst only" limit is retired).
2. **Interleaved A/B on a drained corpus** (A,B,A,B). Successive launches drain sweeps, so control-then-fix is partly order effect. Reference corpus: the synthetic 6,000-row X archive (`-xArchiveImport`), on a dedicated sim device with the udid pinned.
3. **Structural over tuned.** Every fix that held removed or reordered work; every tuning guess died. If a fix can't be stated as "this work no longer runs / runs later / runs once," don't ship it as a perf fix.
4. **Any fetch hoisted earlier is a liveness change** (corollary 6). Re-check `.live` at the last await, by hand — the audit's check 6 has two known blind spots here.

### Dead fixes — do not re-propose

- Bridge-sweep pacing as a lag fix (measured ~5%, noise).
- Concurrent `refreshDigests` (composers are `@MainActor`; overlaps network, not CPU; widens liveness windows).
- Offset-paging a fetch sorted on `capturedAt` (no index → every page re-sorts; see `AgentOpenCache.swift:227`).
- `propertiesToFetch` on a **predicated** fetch (SwiftData defect: empty results on iOS 18.6, `55235f80`).
- A permanent `fetchLimit` on a source room (ruled: a head over a truncated slice is §83 fake status).
- `propertiesToFetch` on the composer board fetch (A/B'd *slower*, `Composer.swift:983`).

## Workstreams, ranked

### P0 — Baseline the phone — NEEDS NO CODE, and here is the exact procedure

*Checked 2026-09-01: both instruments already work in a Release build, so this is a scheme change and nothing else. It is the one item in this spec that cannot be done from this session — it needs the physical device.*

`LaunchClock.reports` is deliberately not `#if DEBUG` (`CasberiApp.swift:11–29`) — in Release it reports when `UserDefaults.standard.bool(forKey: "launchTimer")` is true. `SweepClock.isOn` reads `sweepTimer` the same way (`SweepClock.swift:49–61`). **Launch arguments land in `NSArgumentDomain`, which every `UserDefaults` instance searches**, so passing them is all that is required — the same trick already used for `-notify.alarms NO`.

1. Xcode → Edit Scheme → Run → **Build Configuration: Release**.
2. Same sheet → Arguments Passed On Launch: `-launchTimer YES` and `-sweepTimer YES`.
3. Run on the phone, over the real corpus. Read the console.
4. Record `launchTimer init→ready`, and the `sweepPerf|` hitch count and worst stall.
5. Repeat once on the 6,000-row fixture for a number comparable to every simulator figure in the perf memory.

Then walk the three felt checkpoints by hand and time them roughly: cold open → first scroll, chip tap → answer paints, room swipe → settled.

**Everything below re-ranks against this**, and it may well de-rank most of it: every number in the record is Debug-on-simulator, and Release measured ~350ms against Debug's ~477ms on the same day (`CLAUDE.md`, perf pass notes).

### P0 (original framing, kept for the record)

Release build on real hardware, `-launchTimer YES` (works in Release) + `-sweepTimer YES` (SweepClock is Release-capable), over (a) the owner's real corpus and (b) the 6k fixture. Record: launch init→ready, hitch count/worst from the heartbeat, and felt checkpoints (cold open → first scroll, chip tap → paint, swipe → settle). **Everything below re-ranks against this.** If the phone says the app is already fast, the remaining spend is regression-proofing (P4), not optimisation.

### P1 — The source room's heavy hydration — RESOLVED TO ONE OPTION, needs a validation step

*Updated 2026-09-01 after working the three candidate shapes. Two of the three are now dead with evidence; the third is the only fix, and it is blocked on a measurement this host cannot make.*

**Shape 3 (move the heavy columns to lazy storage) is DEAD, and the reason is a type rule, not a risk judgement.** `@Attribute(.externalStorage)` applies to `Data`, not `String` — the `embedding` precedent (`Thing.swift:641`, moved 2026-07-15 for exactly this reason) is `Data?` and mirrors as CloudKit **BYTES**. `content`, `enrichedText` and `postText` are `String` and mirror as **STRING** (`docs/cloudkit-schema.ckdb:9/20/37`, all `QUERYABLE SEARCHABLE SORTABLE`). Making them lazy means changing the Swift type, which changes the deployed CloudKit field type — and a field's type in Production is permanent. So this is not "a migration with a hazard", it is a **new field + backfill + dual-read + the old field retired from writes but never removable**. Price it that way or not at all.

**Shape 2 (two-phase fetch) is DEAD on its own arithmetic.** The only defect-free projection is unpredicated (the All room's configuration), so phase one would fetch the whole corpus light and filter to the source in Swift — re-introducing exactly the whole-corpus materialisation the 2026-08-06 measurement identified as 26.6% of the main thread. Trading a heavy fetch of one room for a light fetch of every room is not a fix, and on the small-room-in-a-large-corpus case it is a regression.

**Shape 1 (version-gate `propertiesToFetch`) is the only remaining fix — and it is NOT ready to ship.** iOS 26 is known correct (this project's simulator, months of ship). iOS 18.6 is known wrong (the 2026-08-31 report). Gating the projection on `#available(iOS 26, *)` restores light columns for most devices and leaves 18.x on today's known-good heavy path, with FeedScreen's existing COUNT-vs-`things.count` safety net as the backstop for a mis-gate.

**Why it is not shipped here:** only an iOS 26.5 runtime is installed on this machine and the app deploys to 18.0, so the gate's boundary cannot be tested. The risk is asymmetric — being wrong reproduces "the room says connected and shows nothing", the worst bug this app has shipped recently, on its main screen; being right buys an unmeasured win. This codebase's own rule is that a check which cannot fail proves nothing, and the same applies to a gate that cannot be tested.

**What unblocks it, either is sufficient:**
1. Install an iOS 18.x simulator runtime (Xcode → Settings → Components), open a source room with a bulk import in it, confirm rows appear with the projection on. ~1 hour, mostly download.
2. Ship it to TestFlight behind the gate and check the 18.6 device that filed the original report.

Until one of those happens the accepted cost stands, and it is documented in the source at `FeedScreen.swift:310`.

### P1 (original framing, kept for the record)

`FeedScreen.swift:318`: since `55235f80` every source-room open materialises every row **with** `content`/`enrichedText`/`postText`. The comment at `:310` accepts the cost and sets the bar: any fix "must come back as something that cannot silently drop rows."

Three candidate shapes, in order of preference — **measure the defect before choosing**:

1. **Version-gate the old fix.** The defect is `propertiesToFetch` + `#Predicate` returning empty on iOS 18.6 while iOS 26 is correct (same binary). Write a 20-line repro, run it on 18.x and 26 sims, and pin the boundary. If 26+ is clean, `if #available(iOS 26, *)` restores light columns for the OS most devices will be on, and 18.x keeps today's correct-but-heavy behaviour. Failure mode is the silent empty room, so the existing safety net (COUNT vs `things.count`) is the guard — it already exists and would catch a mis-gated OS.
2. **Two-phase fetch:** predicated fetch of IDs only (no `propertiesToFetch`, so no defect), then an unpredicated light-columned fetch filtered to those IDs in Swift. Costs a second read; safe by construction. Only if (1)'s boundary is messy.
3. **Move `enrichedText` off the hot row** — see P5; it is retrieval-only by ruling (nothing draws it), yet it hydrates per row. Longest fuse, biggest structural win.

Acceptance: sampled share of `FeedScreen.things.getter` on a source-room open at 6k rows, before/after, interleaved.

### P2 — The typed-ask path (the kept-chip fix, finished)

`corpusNeed`/`keptCorpus` scoped the **kept-chip** kinds; the typed path still runs `allThings()` → `fullCorpus()` — unbounded, unprojected, main actor — for `TagsAsk`, `AggregateAsk`, `StatusAsk.pulse`, `answerNamedAsk`, `matchedTag`/`retrievalDoc`, and the `today` compose (`RootShell.swift:2925–3409`). Every typed question pays it; `askPerf| fullCorpus=` already logs it, so the before-number is one launch away.

Extend the same pattern: derive scope from what each branch filters on (never a second list), fail safe to whole-corpus on an empty scoped read, keep `showtag:` whole (transformable-tags predicate trap). `retrievalDoc` should ride `retrieve`'s existing source-scoped window rather than a fresh full fetch. Guard in `ask-scope-selftest.sh` (extend, don't fork).

### P3 — Per-row body costs (scroll, unmeasured)

No instrument covers scroll; these are the two known per-row-per-render costs. Sample a scroll first (method rule 1), then:

- **Verb derivation in the context menu** (`FeedScreen.swift:10006`): `contextMenu(menuItems:)` is non-escaping, so `VerbDerivation.verbs(for:)` — which reads `thing.content` and runs `NSDataDetector` — executes per row per body build. Cache per thing id in `DerivationMemo` keyed by `corpusRevision` (the memo exists and is the right shape: plain class, written during body eval).
- **`previewImageData != nil` is a disk read** (externalStorage). Today's fix reordered the `&&` chains; the remaining reads can be memoised as a `hasPreview: Set<UUID>` in the same memo. A stored `Bool` column would need a CloudKit deploy — the memo costs nothing, do that.

### P4 — Regression-proofing: the class keeps re-entering

The unbounded-main-actor-fetch class has re-entered at least four times by four routes (kept asks, Composer settle, safety nets, room state-writes). Two of today's guards (`body-publish-audit.py`, `room-perf-selftest.sh`) cover the newest routes. Close the class:

- **`scripts/fetch-bound-audit.py`** (new, the repo's audit shape): every `FetchDescriptor<Thing>` in ship code (non-DEBUG) on a main-actor path must set `fetchLimit` **or** appear in `KNOWN_UNBOUNDED` with the reason comment beside it (the survey found ~14 legitimate entries: pinned room, wallet history, source rooms, safety nets, `scanPaged`, `reindexAll`'s cold pass, `SyncReconcile`, settings flows). Self-tested, mutation-proven against `fullCorpus` losing its logging and against a new naked fetch in `RootShell`. This turns the file-by-file archaeology this spec required into a one-second check.
- **Keep `perf.sh` report-only** (a gating perf number is the flaky-gate class this repo refuses), but add the **hitch heartbeat** as a fourth *reported* line so the nightly at least sees stall shape, not just launch/RSS/answer — the three numbers that have read clean through every real regression.
- **A device pass is a standing pre-ship step** the way demo parity is: one Release install, the P0 checkpoints, eyeballed. Cheap, and the only reading that is the product.

### P5 — Structural (long fuse, biggest ceiling)

1. **`#Index` on `Thing`** (`capturedAt`, `source`). Local-only (no CloudKit field, no deploy), additive. It makes every sorted+limited fetch and all ~70 `newestPerSource` reads cheaper, and retroactively legalises the paging `AgentOpenCache` refused for want of it. Measure `containerWithFallback` and launch before/after — an index also costs writes; the bridges insert in bursts.
2. **`enrichedText` → external storage or a sibling model.** It is retrieval-only (no screen draws it) and can run to 8KB per row, hydrated on every source-room fetch. Changing the deployed CloudKit field type is the hazard (`CD_enrichedText` is a string in Production; externalStorage mirrors as CKAsset) — so the safe shape is a **new** optional external field + one-time migration + dual-read, with the old field retired from writes. Gate on P1's outcome: if version-gated `propertiesToFetch` lands, this drops to "nice"; if not, it's the real fix.
3. **Backfill save-batching.** `indexPending` loops 32-row batches *to drain* with a `saveHonestly()` per batch — each save re-emits every live `@Query` while the person is looking at the feed. Bound per activation (N batches) or coalesce saves; the sweep already re-arms every foreground, so a bound costs nothing but latency-to-indexed.
4. **Launch +400ms block hygiene.** `SpotlightIndex.reindexAll` with no watermark and `SyncReconcile`'s two passes walk the corpus on the main actor right as the person starts scrolling. Chunk with yields (`ImportCommit`'s shape) and/or move behind first-scroll-idle. Only after P0 shows they're felt — they may not be.

### Explicitly not worth it (per current evidence)

- Splitting `FeedScreen` (11,396 lines) *for perf*: sampling shows ~0% self time in our code; the cost is materialisation, not our functions. Split for maintainability if ever, not speed.
- Debug-build tuning beyond what's ranked: perceived speed ships in Release, which nothing has measured yet — hence P0 first.

## Status — what landed 2026-09-01

| Item | State |
|---|---|
| P0 device baseline | **Procedure written, needs the phone.** No code required — both instruments already report in Release. |
| P1 source-room hydration | **Narrowed to one option, blocked on a validation step.** Two of three shapes killed with evidence. |
| P2 typed-ask path | **Done.** `fullCorpus()` is light-columned. |
| P3 per-row costs | **Instrumented, deliberately not optimised.** |
| P4 fetch-bound audit | **Done**, wired into `verify.sh` and discovered by CI. |
| P5.1 `#Index` | **Done.** |
| P5.2 heavy columns lazy | **Dead** — see P1. |
| P5.3 backfill batching | **Done.** |
| P5.4 launch block | **Done.** |

**P2** — `RootShell.fullCorpus()` now sets `propertiesToFetch`. Every consumer was checked one by one rather than assumed: the tag doc, `matchedTag`, `tagTile`, `knownSources`, `AggregateAsk`, `StatusAsk` and the evidence filter read only light columns, and the retrieval branch never ranked over this array at all (`hits` come from `retrieve`, which has its own window). This fetch carries **no predicate**, so it is the All room's proven-safe configuration and not the 18.6 defect. `FeedScreen.lightColumns` dropped `private` rather than gaining a second list, because the drift symptom here is a fault storm.

**P3** — the row's `.contextMenu` verb derivation is now wrapped in `perfAccum("rowVerbs[<source>]")`, labelled per source so the All room (which faults `content`) is distinguishable from a source room (which has it hydrated). **No cache was added, on purpose:** there is still no scroll instrument, and this spec's own rule is to sample before fixing.

**And this item was smaller than this spec claimed.** The source comment asserting that `VerbDerivation.verbs` "runs an `NSDataDetector` pass" per row is **stale** — §260/§262 moved all three scans out, so `placeURL`/`telURL`/`mailtoURL` are stamped once by `VerbDetection.backfill` off the main actor and merely read here as pre-fetched columns. What survives is the `content` fault, and only in the All room. The comment has been amended in place rather than deleted, because the rest of it is still why the derivation is one call. Worth generalising: **a comment describing a cost outlives the cost**, and this spec inherited the claim from it without checking.

**P5.1** — `#Index<Thing>([\.capturedAt], [\.source, \.capturedAt], [\.sourceRef], [\.pinnedAt])`. Availability read out of the SDK's own `.swiftinterface` (iOS 18+, deployment target is 18.0, no gate needed). Proven not to be a schema change by diffing the stored-property set the CloudKit audit parses: 60 before, 60 after — no `CD_*` field, no `.ckdb` row, no Production deploy, no `ThingSchemaVN` stage. No standalone `[\.source]` index: a B-tree already serves equality on its leading column, so `[source, capturedAt]` covers it and a second index would be paid on every insert for nothing. Write cost and read win are both **unmeasured**.

**P5.3** — the embedding backfill takes a per-activation budget of 8 batches (256 things). The bound lives on `backfill`, not on `indexPending`, because two headless probes call the primitive directly and rely on it draining. Arithmetic: unbounded on a 13k corpus is ~419 batches ≈ 50 seconds of continuous feed rebuilding; 8 batches is ~1 second, which fits inside the burst `runForegroundWork` already pays, so it adds no new window of jank rather than a shorter one. In steady state the bound never binds.

**P5.4** — `SpotlightIndex.reindexAll`, `SyncReconcile.dedupeBySourceRef` and `DemoSeedAll.sweepEscapedRows` walk in chunks with a yield between them. Same rows, same work, same single save — only the **walk** is sliced, never the fetch (`AgentOpenCache`'s ruling: no index on the sort key, so paging re-sorts per page). Each chunk re-checks `.isLive` per row and the delete pass filters again after the last await, because a yield puts a held `[Thing]` across a suspension — corollary 6, the crash class.

## Findings that came out of doing the work

**The measurement itself was broken, and had been all along.** `scripts/perf.sh` re-greps each accumulator label as a regex, so `feedList[All]` is read as a character class `[All]` and never matches — the line prints `accum=feedList[All]  ms over  calls`, a blank where the number should be. It is in **every recorded run on disk** (`scripts/output/perf-*/perf.txt`). This is the single most-cited accumulator in the entire perf record, and the same `-F` lesson CLAUDE.md already records for `verify-mac.sh`'s span breakdown — that fix was never carried to this copy. Fixed, and proven both ways against a fixture. Generalise: **when a lesson is recorded for one script, grep the tree for the same shape** — the record said this bug was fixed, and it was, in one of the two places it lived.

**A comment describing a cost outlived the cost.** `FeedScreen`'s context-menu comment claimed `VerbDerivation.verbs` runs an `NSDataDetector` pass per row. §260/§262 moved all three scans off the main actor, so it reads stamped columns instead. This spec inherited the claim from the comment without checking, and would have sent the next session optimising something already optimised.

**What is really left there:** `verbs(for:)` reads `thing.content` ungated for `.link`, `.product`, `.transaction`, `.note`, `.chat`, `.mail`, `.voice` and `.file` — i.e. nearly every row. The All room's query omits `content`, so that is **a per-row external fault on the All room and not on a source room** (which hydrates it since the 2026-08-31 fix). That asymmetry is exactly what the new per-room label will show, and it is the first concrete hypothesis P3 has ever had.

**Dead code, not a perf cost:** `FeedScreen.openVerb(for:)` has zero callers — residue of the both-edge swipe retired 2026-07-16. Left alone; noted so it can be deleted deliberately rather than found again.

**The audit refused its own brief, correctly.** Taken literally, "every `FetchDescriptor<Thing>`" needed 163 registry entries, 133 of them predicated bridge-dedupe reads off the render path. That is `ref-shape-audit.py`'s refused reverse direction wearing a registry's clothes, and a check firing on a healthy tree gets turned off within a week. It holds the whole-corpus class plus the `@Query`-backed render-path cases, and says so in its docstring.

**A comment we added to explain a perf change broke a different audit, in the worst possible shape.** One of the new comments cited a run-directory glob, `scripts/output/*/perf.txt`. That contains the two characters `/` `*`, and `privacy-cover-audit.py`'s comment-stripper looked for a block opener **before** a line comment — so it read the glob as an unterminated `/*` and blanked every line after it to the end of the file. All three of its checks then failed at once, reporting that the app-switcher privacy cover had been removed from a file where all five of its symbols were present and correct. **A guard that accuses the code, in language identical to the real bug it exists to catch**, is worse than one that stays silent: the obvious response is to go looking for a regression that was never there. Fixed properly — whichever delimiter opens first wins, since testing either one first is wrong in the other direction — with two fixtures (the glob, and a `//` inside a one-line `/* */`) and mutation-proven by reverting the order. Generalise: **a comment-stripper is parsing, and a naive one fails open in the direction of blaming your code.**

**Sixth instance of the comment-matching lesson.** The audit's own first cut of check 3 was a file-wide grep and **survived its mutation**, because `RootShell` names the instrumentation string in a comment two lines above the log line it guards. Comment-stripping is not fussiness in this repo; it is the default.

## Order of execution

P0 (one session, re-ranks everything) → P2 (small, pattern exists, guard exists) → P1 measurement then chosen shape → P3 behind a scroll sample → P4 audit alongside any of it → P5 as its gates open.
