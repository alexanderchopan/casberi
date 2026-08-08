# Demo state — improvement spec (2026-08-07)

Written by the session that built the demo mode (commit `c4f0d22`), for a
fresh session to execute. Everything here assumes that commit is on `main`.
Read `docs/prd.md` §217/§83 and the CLAUDE.md sections on the liveness
corollaries and the design-motion audit before starting — several items below
cite them as constraints, not decoration.

**What exists today (the baseline you're editing):**

- `Model/DemoMode.swift` — enter (`begin` → `pourIfNeeded`), exit
  (`exit` → `DemoSeedAll.teardown`), `isActive`, `hasSeen`. The pour lands
  ~422 rows in chunks of 12 every 55ms so the feed is watched filling.
- `Model/DemoSeedAll.swift` — the rows (66 seats, every room), the bridge
  state three heads read (wallet curve / PostHog metrics / x402 sellers),
  `demoVisits` (ChipMemory affinity), `teardown` (the mirror of everything
  `seed` plants; keep it that way).
- `Screens/DemoBanner.swift` — the §83 marking. Never dismissible, always
  carries Exit, rides `MainSurface.topInset` (NOT RootShell — measured twice,
  see the comment on `topInset` before "fixing" its placement).
- `Screens/StartHereScreen.swift` — the fork, now the EXIT landing. Its demo
  card hides on `DemoMode.hasSeen`. Card figures are `StartFigureMark`.
- `Screens/HowItWorksSheet.swift` — greeting CTA "Try the demo" →
  `enterDemo()`; secondary link "Start with my own things" → the fork.
- Gates: `BridgeRefresh.refreshAllConnected` returns early when
  `DemoMode.isActive` (the demo REACHES NOTHING — a sweep would read the
  fake wallet and write a zero over the seeded curve); `Notifications.submit`
  returns `[]` in demo unless `dryRun`.

**Ground rules for every item:**

- Run `scripts/verify.sh --build-only` AND a Release build
  (`-configuration Release`) before calling anything done — Release breakage
  in this exact feature area shipped once already (`ChipMemory.seedDemo`
  inside `#if DEBUG`, called from a file with no `#if`).
- The one sim exception applies: anything that ADDS or MOVES shell chrome
  gets one simulator screenshot (`-fresh YES -howItWorksCTA 2`, wait ~16s).
  Logic-only items need build + audits + reading, per the standing rule.
- Do not stage `docs/prd.md` blindly — check whether another session has
  uncommitted WIP in it first (`git diff docs/prd.md`).
- Nothing in the demo may fire a network request or a notification, ever.
  Every item below preserves the two gates; if you touch them, extend them.

---

## P0 · Fix the stranded pour (a real bug, shipped in c4f0d22)

`DemoMode.pourIfNeeded` has exactly ONE call site: the onboarding cover's
`onDismiss` in `RootShell` (~line 1036). The pour was designed to resume — a
kill mid-pour leaves `demo.mode.pourPending` set and the next launch is
supposed to finish the job (`seed` dedupes on `sourceRef`, so it's safe).
But on that next launch `onboarded` is already true, the cover never
presents, `onDismiss` never fires, and the flag sits forever: the person is
IN demo mode (banner up, seats connected) over a half-poured corpus.

**Fix:** call `pourIfNeeded` from RootShell's activation path (wherever
`runForegroundWork`/scene-activation already runs) in addition to the cover's
`onDismiss`. It's self-gating on the pending flag and returns immediately
when there's nothing to do, so an unconditional call is correct. Keep the
`onDismiss` call — it's what makes the first pour start the instant the
cover lifts rather than on the next activation tick.

**Verify:** launch with `-fresh YES -howItWorksCTA 2`, kill the app
(`xcrun simctl terminate`) ~1s after `demoMode: began` appears in the log
(mid-pour), relaunch plain, and confirm the log prints a second
`demoMode: poured N rows` with N > 0 and the final corpus count matches a
clean run's (422 at time of writing; recount, P4 changes it).

---

## P1 · Seed the agent's memory, not just its corpus

The user's stated goal for the demo is that "the agent populates with
density and richness." The corpus and the panel affinity are seeded; the
agent's MEMORY is not, so three flagship surfaces read as day-one:

1. **`BriefLedger`** (`Model/BriefLedger.swift`) — the Today brief's
   14-window record of what prior briefs showed. Unseeded, the brief has no
   streak lede ("ETH has done the lifting seven days running"), no themes
   continuity subline, no absence note. The DEBUG hook `-briefLedger
   "days=6;symbol=ETH;themes=…"` already proves the shape works — write the
   equivalent entries directly from `DemoMode.begin` (or a
   `DemoSeedAll.seedAgentMemory()` called beside `seedBridgeStateForDemo`).
   Seed ~6 prior days with `symbol=ETH` and two themes that exist in the
   seeded corpus's tags. IMPORTANT: use `BriefLedger`'s own entry shape and
   respect its `windowStart` vs `day` split (CLAUDE.md records a real bug
   from collapsing them).
2. **`AskMemory`** (`Model/AskMemory.swift`) — seed `asksMade` counts ≥ 3
   for one or two kinds so the "You ask this a lot — keep it?" upgrade path
   is visible in a demo walkthrough, and shown-counts that demote one stale
   suggestion (proves the tiles are learned, not static).
3. **More kept asks — but only ones that provably compose non-empty.** Today
   the demo keeps `today` and `wallet`. Add `showtag:<tag>` for a tag the
   seed actually lands with ≥ 5 rows, and `context:<source>` for a busy
   seeded source (X or Photos). Before adding ANY kind, run its composer
   over the seeded corpus and confirm the result is non-empty — a kept chip
   that answers nothing is worse than its absence (this is why the original
   list stopped at two; the comment in `DemoMode.keptAsks` says so).
4. **The away window** — `AppVisit`'s window is process-frozen and minimum
   1h, so a fresh demo can never show "While I was away". Do NOT fake it via
   the `-awayGap` UserDefaults key from production code (that's a DEBUG
   hook). Instead, seed the persisted last-background stamp that
   `AppVisit.markOpened` reads (find the UserDefaults key it uses) to ~3h
   before `begin` runs, so the FIRST demo open composes a real away window
   over the freshly poured rows.

**Teardown symmetry is the acceptance bar:** every key written here must be
removed in `DemoSeedAll.teardown` / `DemoMode.exit`, by name, never by
blanket wipe (the teardown doc comment explains why — a dev install has real
state under the same keys). Extend the teardown in the same commit.

---

## P2 · A way back in (re-entry door)

`hasSeen` hides the fork's demo card forever after one entry, and the fork
is only reachable during onboarding or after a demo exit. So on a TestFlight
build the demo is enterable EXACTLY ONCE per install. For the demo's stated
audience — the founder showing investors, repeatedly, on a real phone —
that's a one-shot flare.

**Build:** a Settings row (in `Screens/AccountScreen.swift`'s detail list,
grouped with the existing Data/About rows): "See the demo" → calls
`DemoMode.begin` + triggers the pour, exactly the fork card's path.

**Gate it on a demo-clean corpus:** show the row only when no NON-demo
source has landed rows and no real wallet is watched (a cheap test:
`BridgeStore.bridges` empty or all-demo, `WalletStore.addresses` empty).
Reason, spelled out because it's tempting to skip: `seedBridgeState`
replaces PostHog metrics named `signed_up`/`answer_asked` and teardown
FORGETS them — on a lived-in install with a real PostHog those names would
be destroyed by exit. The banner would also read "none of this is yours"
over a feed that's 90% theirs. The gate makes both impossible. If the gate
hides the row, that's correct — a person with a real corpus doesn't need
the demo.

**Also:** re-entry means `enteringDemo`-style double-tap protection and the
same pour path (P0's activation call covers resume). Exit still lands on the
fork; from a re-entered demo, the fork's "See all N apps" and three cards
are exactly right.

---

## P3 · Freshness — a demo that doesn't rot

Rows are dated relative to `.now` at pour time (`at(daysAgo:hour:)`). A
demo left alive for a week shows "Standup · 9:33 AM" seven days stale, the
whisper never fires, and the seat lines still say "Synced 4m ago". For a
demo whose one job is showing the app ALIVE, aging is decay.

**Build:** on activation while `DemoMode.isActive`, if the newest demo row
(`sourceRef` prefix `demo:`) is older than ~20h, re-stamp: shift every
demo-owned row's `createdAt`/`capturedAt` forward by whole days so the
newest lands today (whole days, so the day-dial hour spread and the
heatmap's weekday pattern survive), and refresh the wallet curve's sample
dates the same way. Chunk the writes with a yield (`ImportCommit`'s reason)
and guard liveness per row. Re-stamp `dueAt` the same shift so deadlines
stay in the future. Do NOT touch non-demo rows — filter by
`DemoSeedAll.refPrefixes`, and note `import:receipt:` is in that list but on
a demo-clean install (P2's gate) every receipt is demo-owned, so it's safe.

This replaces any temptation to hand-refresh seat `statusLine` strings —
after a re-stamp, "Synced 4m ago" is once again roughly true. Skip the
string surgery.

---

## P4 · No dead doors: demo permalink policy

8 demo rows carry `https://example.com/...` permalinks (the infra rooms)
and several carry fabricated real-host URLs (`github.com/demo/casberi` —
a 404). A thing sheet's Open disc on those is a door that opens onto a dead
page — §83's dead-control corollary, hit in the exact minute an investor is
poking around.

**Ruling to apply (record it in the PRD entry, P5):** a demo row either
carries a REAL, stable, brand-neutral public URL that genuinely matches its
title, or NO permalink at all. In practice: strip `content` URLs from the
fabricated rows (the row then renders as its kind's plain form — title,
excerpt, time — and the sheet offers no Open disc; verify the `.link` kind
renders acceptably with an empty/absent link, and if a bare `.link` with no
URL renders wrong, switch those rows to `.note`). Keep real URLs only where
they're already real (e.g. `revoke.cash`, `dexscreener.com` pattern URLs
that resolve). Do not invent URLs on real hosts. Recount the poured-row
total afterwards and update the P0 verification number.

---

## P5 · Instrumentation, guards, and the ledger

1. **`-demoEnter YES`** (DEBUG hook, `RootShell`/`ProbeHooks` per the house
   pattern): enter demo mode headlessly without walking onboarding — the
   screenshot pipeline and the screen-audit skill need one launch, not the
   `-fresh`/`-howItWorksCTA` two-step. **`-demoProbe YES`**: NSLog one line
   per fact — mode active, hasSeen, pending-pour flag, demo row count,
   seat count, kept-ask kinds, and (after P1) whether the ledger/askMemory
   seeds are present. One NSLog per line (the `-todayProbe` truncation
   lesson). Document both in CLAUDE.md's hook list.
2. **Seed/teardown symmetry guard** (`scripts/demo-selftest.sh`, wired into
   `verify.sh`, self-tested like every sibling): mechanical checks that
   (a) every UserDefaults key literal written in `seedBridgeState`/
   `seedAgentMemory`/`DemoMode.begin` has a matching removal in
   `teardown`/`exit`; (b) `DemoSeedAll.swift` and `DemoMode.swift` contain
   no `#if DEBUG` (the Release-break class); (c) neither file contains a
   network verb (`URLSession`, `dataTask`, `postJSON` …) — the
   reaches-nothing promise as a tripwire, the `cursor-selftest` conduct
   pattern. Follow the house rules: self-test first, comment-stripped copy
   for negative guards (the Obsidian lesson), fail loud.
3. **PRD + CLAUDE.md:** write the ruling — demo as first tap, exit lands on
   the fork not the catalog (partially amends §217), the reaches-nothing
   gate, the banner's three placement attempts, the P4 permalink rule, and
   P2's gate. Add the demo hooks to CLAUDE.md. Check for another session's
   `docs/prd.md` WIP before staging.
4. **Mac:** `verify-mac.sh` gains a demo line — enter via `-demoEnter YES`
   (with `-storeScratch YES`, which is load-bearing on Mac; see CLAUDE.md)
   and screenshot via `-macSnapshot demo`. The banner's Catalyst padding
   branch has never been rendered anywhere.

---

## Non-goals (decided, don't reopen without the user)

- **No forced demo.** "Start with my own things" stays (user ruling
  2026-08-07: escape route, not forced). Consider renaming to "I'll connect
  my own" — proposed, not yet ruled on; ask, don't assume.
- **No separate store/container for the demo.** Considered and declined —
  one container is a design invariant (`SharedStore.live`'s comment); the
  cost (demo rows mirroring to CloudKit, then deleting) is accepted and
  documented in `DemoMode`'s header. Do not "fix" this.
- **No rain-becomes-rooms animation** — superseded by the pour, which IS the
  arrival moment (this session's ruling).
- **No per-row exit animation.** Exit is one fade then one delete
  transaction; animating 400+ deletions through a live `@Query` is the
  liveness crash class. `ShellChrome.demoLeaving`'s comment is the contract.
- **No numbers or plausible data in `StartFigureMark` figures** — generic
  shape only (§83; the doc comment explains).

## Done means

- `scripts/verify.sh --build-only` green, `demo-selftest.sh` green and
  wired in, **Release** builds.
- The sim arc, driven once end to end: enter (both doors after P2), kill
  mid-pour + relaunch (P0), a stale-dated demo re-stamps (P3, fake by
  setting the pending rows' dates back — or re-launch with the device clock
  unchanged and the seed dates shifted), exit → fork, and `-demoProbe`
  reporting clean state after exit (every seeded key gone).
- Screenshot of the banner + strip after any chrome change.
- PRD entry written; CLAUDE.md hooks documented; commit message in the
  house style (what broke, why invisible, what's mechanical now).
