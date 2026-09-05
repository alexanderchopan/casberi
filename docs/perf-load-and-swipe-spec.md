# Perf pass 7 — "laggy on load, and swiping between screens" (2026-09-04)

*Written against the tree at `4a1fdac5` (Build 516) with 25 dirty files from another session. Third spec on this symptom pair; the first two are `docs/perf-spec.md` (2026-09-01) and `docs/perf-swipe-and-rise-spec.md` (2026-08-21). Every claim below either carries a measurement or says it doesn't.*

## The one fact that decides the order

Both prior specs shipped their fixes on build + audits + reasoning, and **not one number has ever been taken on a phone in Release.** The report recurs three days after the last pass. Two readings are consistent with that, and they call for different work:

- The fixes landed and the felt lag is something none of the instruments span (both specs record exactly this blindness happening twice).
- The fixes landed and the phone is simply slower than the simulator in ways Debug-on-sim cannot show (a 6k-row corpus with heavy columns materialising on an A-series chip, CloudKit import traffic on first foreground, the glass bar's backdrop blur on real hardware).

So Phase 0 is not optional and is not "P0 again": it is the only step that can tell those two apart. The prior specs' Phase 0s were written and skipped. This one is sized to fit in one sitting with the phone on the desk.

## What changed since the 09-01 fixes (unmeasured for perf)

§591 series, 2026-09-02/03: the source strip moved to the **bottom** into a glass bar shared with the agent's seat (`MainSurface.bandInset`, `.safeAreaInset(edge: .bottom)`), chips became folders, the chips scroll inside the bar, the tapped chip turns blue. All of it sits **over** the transitioning feed. Nothing was sampled after it landed. It is the newest suspect for the swipe half specifically, because a backdrop blur over a full-screen move transition is a per-frame render-server cost that no main-thread instrument in this repo can see.

## Mechanisms still on the table (read from source at `4a1fdac5`, not measured)

### Load

| | Mechanism | Where | What is known |
|---|---|---|---|
| L1 | **Per-save feed rebuild during the foreground burst.** `refreshAllConnected` starts at +800ms on first activation; ~190 save sites across the bridges each re-emit the All room's `@Query`, and each emission is a body pass that reads `things` (`Corpus.hasSurfaced`, `safetyNetKey`'s `things.isEmpty`, `liveVisible`) and so re-materialises the 1200-row window. The debounce bounds the derivations, never the fetch. | `RootShell.swift:1877`, `FeedScreen.swift` roomBody / `safetyNetKey` | 08-06 measured 28 rebuilds ≈ 2.9s at 6k rows before the bounds; post-bound cost per rebuild unmeasured. Backfill saves were bounded to 8/activation on 09-01; bridge saves never were. |
| L2 | **`newestPerSource()` on the launch frame.** `freezeChips` runs ~70 indexed reads on the main actor from `onAppear`, before first paint settles. | `MainSurface.swift:931, 1089` | 0.5–0.9s cold in Debug on 08-11, before `#Index`. The index landed 09-01 and its effect is **unmeasured**. |
| L3 | The +400ms housekeeping block (Spotlight reindex, dedupe, migrations) — chunked with yields on 09-01. | `RootShell.swift:357` | Chunked, unmeasured. Yields make it interruptible, not cheaper. |
| L4 | Model prewarm at +2.5s and the on-device embedding backfill (8 batch saves) — both land while the person is scrolling. | `RootShell.swift:1720` | Each backfill save is one more L1 rebuild. |
| L5 | **Debug vs Release.** Every recorded number is Debug on a simulator. | — | Release ≈ 0.7× Debug on a 40-row corpus (07-29). Ratio at 6k rows unknown. |

### Swipe

| | Mechanism | Where | What is known |
|---|---|---|---|
| S1 | **The budget release is one unbounded heavy fetch on the main actor, 360ms after the slide.** A source room's query has no `fetchLimit` (08-14 ruling) and no `propertiesToFetch` (55235f80, the 18.6 defect), so a bulk-import room (X 10k, journals, Instagram) materialises every row WITH `content`/`enrichedText`/`postText` right as the slide settles. That is felt as "the swipe finishes, then the app stutters". | `MainSurface.releaseSwipeBudget`, `FeedScreen.swift:240–300` | 08-06 measured this class at 26.6% of main thread for the All room before its bound; source rooms never measured. Both obvious fixes are ruled dead (see below). |
| S2 | **`recomputeHeads()` is `@MainActor` and synchronous** over the full room once the budget lifts — `XRoom`'s whole-span scan, treemap assignment, leaderboards. The memo makes a REVISIT free; a first visit and every corpus change pay it on main. | `FeedScreen.swift:2425` | Unmeasured; `swipePerf\|heads rows=N` prints it. |
| S3 | **Two live screens mid-slide.** The outgoing `FeedScreen` stays mounted with its own `@Query` under the move transition. Spec A3 (snapshot the outgoing room) was deliberately not built pending a sample that was never taken. | `MainSurface.swift:2020–2031` | Unmeasured. |
| S4 | **A staggered entrance on every swipe.** A fresh mount plays `RowEntrance` on the first 13 rows (`withAnimation(.delay(index × step))`) concurrently with the page move. Two motions on one row, and 13 animation transactions started inside the slide's frames. | `FeedScreen.swift:1966, 11941` | Unmeasured. Also a design question: a row sliding in with its page and then lifting again is double motion. |
| S5 | **The glass bar over the transition.** The bottom bar is a `safeAreaInset` with a backdrop material; during a slide the content beneath it moves every frame. On iOS 26 hardware that is Liquid Glass sampling a moving layer. | `MainSurface.bandInset`, `SourceChips.swift` | Not a main-thread cost; invisible to `sample`. Only Instruments (GPU / Animation Hitches) can see it. |

### Fixes already ruled out — do not re-propose

From `docs/perf-spec.md`: bridge-sweep pacing (noise), `propertiesToFetch` on a predicated fetch (18.6 empties the room), a permanent `fetchLimit` on a source room *where the head reads the bounded set* (§83), offset-paging on `capturedAt`, concurrent `refreshDigests`. The iOS 18 simulator runtime that would unblock the projection fix is **still not installed** (`simctl list runtimes`: 26.5 only).

## Phase 0 — measure, one sitting, then re-rank

**0a. Make the swipe clock Release-capable.** `SwipeClock` compiles to nothing outside DEBUG, so the phone cannot report a swipe at all. Gate it the way `LaunchClock.reports` and `SweepClock.isOn` are gated — a `UserDefaults` bool (`-swipeTimer YES`) read from `NSArgumentDomain` — with the NSLog sites left in place. Ten lines, no behaviour change, free when off. This is the only code in Phase 0.

**0b. Phone, Release, real corpus.** Xcode scheme → Release, arguments `-launchTimer YES -sweepTimer YES -swipeTimer YES`. Record:

- `launchTimer init→ready` (three cold launches, read the second and third).
- `sweepPerf|` hitch count and worst stall over the first 20s.
- `swipePerf|` for five swipes into the largest room and five into a small one: `step→init`, `init→body`, `body→rows`, and the `heads rows=N` line's arrival time. The gap between `rows` (slide done) and `heads` is S1+S2 on the phone.
- One Instruments **Animation Hitches** trace over the same five swipes. This is the only instrument that sees S5, and it reports hitch duration per frame with the thread that missed the commit.

**0c. Simulator, the sample that was never taken.** Pinned device, 6k-row X archive, two drain launches, then `sample` on the main thread while swiping into the X room repeatedly (`scripts/main-thread-profile.sh`, interleaved with a control arm). It splits S1 (materialisation frames) from S2 (head composition frames) from S3 (two `FeedScreen.body` entries per swipe). Run it from a pinned worktree at HEAD, not the dirty tree (25 files belong to another session).

**Decision table.** Write the numbers into this file, then:

| If Phase 0 shows | Then |
|---|---|
| `init→ready` on the phone ≤ 600ms and `sweepPerf` worst stall < 100ms | Load is fine; "laggy on load" is the burst (L1) or the prewarm (L4) — go to 1.1. |
| `init→ready` > 1s on the phone | L2 first (1.2), then re-measure. |
| `rows→heads` gap dominates the swipe trace | S1/S2 — go to 2.1. |
| Hitches trace shows GPU-bound frames with the main thread idle | S5 — go to 2.4, and the design ruling in it. |
| `sample` shows two `FeedScreen.body` entries per swipe with the outgoing room's `things.getter` hot | S3 — build A3 (2.3). |
| Everything reads fast on the phone | Stop optimising. The spend is regression-proofing and the device pass becomes a standing pre-ship step (P4's unfinished item). |

## Phase 1 — load

**1.1 The All room stops reading `things` while a sweep is in flight.** `@Query` fetches in its getter, so an emission nobody reads costs nothing. The All body has three read sites; during the burst it already has `debouncedAllSnapshot`. Route all three through the snapshot while `chrome.sweepInFlight` (a flag `refreshAllConnected` already knows how to set) and re-read `things` once when the sweep ends. Structural: the same work runs once at the end of the burst instead of once per save. `safetyNetKey`'s `things.isEmpty` term moves to the snapshot's emptiness for the same window; the net's own `guard rowBudget == nil` shape applies (put the flag in the key, or the net is disabled rather than deferred — `headKey`'s documented trap). Guard: extend `room-perf-selftest.sh` — no `things` read in the All room's body while the flag is set, mutation-proven.

**1.2 The chip strip paints from its last frozen order.** `freezeChips` persists the resolved order (it is a `[String]`; `ChipMemory` already lives in UserDefaults), the surface mounts with that order on frame one, and `newestPerSource()` runs in the +400ms deferred block and reconciles. Honest by construction — it is literally what the strip showed last time — and a source that landed since is a chip appearing a few hundred ms later, which the arrival watcher already animates. A fresh install has no order and walks as today. Guard: `markets-fold-selftest.sh` pins the derivation, not the timing; add one check that the persisted order is never written from a walk that ran with `rowBudget` set.

**1.3 Measure `#Index`.** `LaunchPerf.time("newestPerSource")` exists; compare against the 08-11 figure on the same corpus. If the index took effect, 1.2 may be unnecessary — do 1.2 only if 1.3 still reads in the hundreds of ms.

**1.4 Bridge save coalescing — explicitly deferred.** A shared save scheduler across ~190 sites is the bigger version of 1.1 and carries a liveness surface this repo has paid for six times. 1.1 removes the cost from the screen that pays it; revisit coalescing only if a sample after 1.1 still shows save-driven rebuilds elsewhere (the wallet room, the source rail).

## Phase 2 — swipe

**2.1 Bound the LIST, not the head — needs one user ruling.** The 08-14 ruling refuses a `fetchLimit` because `sourceHead` composes from `visible`. Split them: the room's `@Query` is bounded at a render ceiling (600 rows = 20 "Show older" windows; the All room's `reachedFetchCeiling` footer already says "open a source to go further back", and the same honest footer applies), and `recomputeHeads()` makes its **own** unbounded fetch of the room inside its task, memoised per `Corpus.revision`. The head still sees the whole room, so §83 is untouched; the per-swipe cost drops from "every row with heavy text, on main, inside the settle" to "600 rows, then a head fetch once per revision". **The ruling to ask:** a source room's *list* may be windowed at N rows with the ceiling footer, while its head reads the full room. This is the single change with the largest ceiling on the swipe half, and it is the one that needs a yes before it is built. Guard: `room-perf-selftest.sh` — the head's fetch carries no `fetchLimit` and no `propertiesToFetch` (the 18.6 defect is predicated+projected; this is predicated+heavy, today's known-good shape).

**2.2 Suppress the row entrance on a swipe mount.** The page is already moving; the rows should arrive with it. `RowEntrance` keeps its stagger for a scroll-into-view and for a chip tap from a standing room, and reads a `chrome.swipeInFlight` (the budget's own lifetime) to skip the transaction on a swipe. Reduce Motion path unchanged; `design-motion-audit.py` must stay green (an appear-triggered animation must still honour it — this only adds a second reason to skip).

**2.3 Snapshot the outgoing room (A3), only on evidence.** If 0c shows the outgoing `FeedScreen` hot mid-slide: render it to a `UIImage` (`UIGraphicsImageRenderer`, `format.scale = 1`) on `step()` and transition the bitmap out, so exactly one live `@Query` exists during the slide. Deliberately unbuilt twice already; build it when the sample says so, not before.

**2.4 The glass bar during a slide — measure, then a design ruling.** If the hitches trace is GPU-bound: the cheapest structural move is to freeze the bar's backdrop during the transition (a snapshot of the material for the slide's 350ms, restored on settle), which keeps the glass at rest and pays nothing while things move. That is a design call — the user rules on design — so it is a proposal with a mockup, not a change. If the trace is clean, S5 is closed and this line is deleted.

**2.5 Head composition off the main actor — Phase 3.** The head sources are Foundation-only and pure, but they take `[Thing]`. Moving them off-main needs a value projection of the row (a `RowSnapshot` struct) first. That is the same projection that would end the SwiftData liveness class (six corollaries) by having views hold values, not models. Biggest ceiling in the file; longest fuse; not this pass.

## Phase 3 — structural, unblocked by other work

- **Install the iOS 18 simulator runtime** (Xcode → Settings → Components, ~1h). It unblocks `docs/perf-spec.md` P1 (version-gated `propertiesToFetch` on source rooms), which would make S1 cheaper without any ruling.
- **`RowSnapshot` projection** (2.5). Spec separately; it touches every row view.

## Status — what landed 2026-09-04 (prd §600)

| Item | State |
|---|---|
| 0a `SwipeClock` in Release | **Done.** Runtime gate on `-swipeTimer YES`, `LaunchClock.reports`' shape. Every call site un-`#if DEBUG`'d. |
| 0a+ the chip walk is timed | **Done, and it was not one launch away as this spec claimed.** `newestPerSource()` had no instrument at all, and `LaunchPerf.time` could not be one (that whole file is `#if DEBUG`). `SwipeClock.span` now times it in Release. |
| 0b phone baseline | **Needs the phone.** No code left to write. |
| 0c simulator `sample` A/B | **Not run.** |
| 1.1 All room stops re-reading during a burst | **Superseded, smaller than specified.** `visible` and `roomBody` already short-circuit on a non-empty snapshot, so the burst cost was not where this spec put it. What was left is `safetyNetKey`'s `things.isEmpty` — added 2026-09-03, the newest per-body-pass materialisation on the screen — now short-circuited the same one-directional way. |
| 1.2 persist the chip order | **Deliberately not built.** Gated on 1.3, per this spec's own ordering. A strip that reshuffles on every launch is worse than a slower one. |
| 1.3 measure `#Index` | **Instrumented, unread.** One launch under `-swipeTimer YES`. |
| 2.1 bound the list, not the head | **Done.** `sourceRoomFetchLimit` 600 + `fullRoomRows`. The ruling is recorded as prd §600. |
| 2.2 suppress the row entrance on a swipe | **Done.** Twenty call sites collapsed to one helper first. |
| 2.3 snapshot the outgoing room | **Not built** — gated on 0c, as specified. Third deferral on the same ground. |
| 2.4 freeze the glass backdrop | **Not built** — gated on the hitches trace, and a design ruling besides. |
| 2.5 head composition off-main | **Phase 3.** Needs the row value projection. |
| Phase 3 iOS 18 runtime | **Not installed.** ~1h download; unblocks `perf-spec.md` P1. |

**Three findings from doing the work.**

The 2.1 ruling was cheaper than this spec priced it. The 2026-08-14 refusal reads as an argument against bounding a source room and is actually an argument about one reader of it — so the fix was to separate the head from the list, not to trade honesty for speed. Read a refusal for what it refuses.

**A bound obliges every reader that compares against the thing it bounds.** Bounding the query made the per-source staleness net a permanent mismatch, which would have run the unbounded recovery fetch on every foreground of every bulk-import room — the exact cost removed, arriving through the safety net, invisibly. This is the 2026-09-01 lesson ("when you add a transient bound to a shared input, grep every consumer that compares against it") re-earned for a permanent one, and the footer (`reachedFetchCeiling`) is the same shape of debt in the copy.

**Two audits refused the change until it was finished, and one of them proved the change worked.** `fetch-bound-audit.py` reported that the `init` exemption now matches nothing — because the fetch it defended is the one that got bounded. An exemption going unreachable is how that audit says a ruling has moved.

## Sequencing

0a (ten lines) → 0b on the phone → 0c on the sim → numbers into this file → the decision table picks from Phase 1/2 → one structural change per commit, each with its own interleaved A/B → the device pass becomes a standing pre-ship step.

Non-goals: no tuning knobs, no re-litigating the dead fixes, no `FeedScreen` split for speed (sampling has shown ~0% self time in our code), no sim screenshots (user rule).
