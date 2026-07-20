# Agent shell — ruling record & build brief (2026-07-19)

Product-design session output (Opus 4.8 / Fable 5, 2026-07-19). This is the
durable record of the rulings and the staged directions to build them. If you
are a model picking this up fresh: read this whole file before writing code,
and treat the rulings as settled — do not re-litigate them, and do not build
anything listed under "Explicitly not ruled."

## The settlement, in one paragraph

The app stays **content-first**: it opens on the feeds/board as today, because
glancing beats asking for browse-shaped needs (a Peer fill or 1Claw grant is
one scroll away and must stay that way). The **agent** is the composer's seat,
grown up: an ask **bar** rides the floating layer of every screen (where the
FAB was); tapping it raises a **full-screen** agent surface; lowering it
returns you exactly where you were — the "now-playing bar" pattern everyone
already knows. The Home-vs-composer duplication this session started from is
resolved by **division, not deletion**: Home's intelligence (the Noticed card,
the away line) moves into the agent as *signals on chips*; content rows stay on
content surfaces. Vocabulary law: **chips are agent-language, rows/cards are
app-language** — that visual split is load-bearing.

Canonical mockups (visual reference, in ruling order):

- The loop (app ↔ agent, exits): https://claude.ai/code/artifact/6c4d5bb3-06d1-4bf3-8ec1-cf5584ae90f3
- Signal-chip treatments (B1 pills ruled): https://claude.ai/code/artifact/d081fb31-3b9b-457e-bf68-6ffca41976ef
- Session models (Stack ruled): https://claude.ai/code/artifact/f8da0d77-e863-4219-b1bf-ef048ff27e88
- Answer-anatomy spec (later goal): https://claude.ai/code/artifact/d23a35ae-c23d-420e-8979-07ae4b25c88f

## Rulings (settled — the why is part of the ruling)

1. **The agent inherits direction F's core.** Chips are *kept asks*; each is a
   saved question plus a **deterministic composer** (a hand-authored GenUI doc
   path, exactly how `HomeComposition` composes today — no LLM in the kept-ask
   path). Only free-text asks route through the model. The spine must never
   depend on on-device AI being clever.
2. **Content-first open.** The root-inversion (agent as the app's front door)
   is dead. Users open into their things.
3. **The agent surface is a FULL SCREEN, not a sheet/tray.** One transition,
   at engage. (The prototype's `-summonMode` sheet variant is dead — delete
   the flag.)
4. **Rest state of the risen agent** (approved): greeting ("Saturday
   morning." / "2,481 things, across 14 apps."), then the kept asks as **B1
   pill chips**, then the glass bar. The ledger treatment was rejected —
   chips are the more familiar pattern and differentiate the agent from the
   app's rows.
5. **Signals.** Each chip wears one line of state in secondary ink
   ("While I was away? · 12 new", "How's my money? · $12,480"). The blue dot
   appears **only when the answer changed** since last seen (a deterministic
   diff of the composer's facts against a stored last-seen — never a model
   judgment). Changed chips sort first; ignored asks decay dim (AskMemory's
   counters, later). Tripwire, record verbatim: *the day a chip wants a
   thumbnail is the day the discipline broke.*
6. **The bar.** Rides the floating layer on every app screen. **No number
   badges — ever** (ruled annoying). While an unseen changed signal exists,
   the bar's ✦ **pulses** (slow two-breath glow); it stops once the agent is
   raised. Optional, flag-gated: one glass *whisper* capsule above the bar
   with the top changed signal ("● Base airdrop · snapshot Fri"), only when
   genuinely changed, tap = open agent with that ask summoned.
7. **Exits — both on trial.** ✕ top corner (familiar) AND a ⌄ button leading
   in the bar (thumb-reach; the thing that raised it lowers it). Both return
   to the exact prior context. Usage decides which survives.
8. **Session model: the Stack.** Every answer is a sovereign screen. Tapping
   content inside an answer **pushes a generative thing-view** (still inside
   the agent); back-swipe/‹ pops the trail. A new ask pushes a fresh answer.
   When a doc is up the bar reads "Ask about this…" (follow-ups ground in the
   current answer — `lastAnswerHits` machinery exists in RootShell). Stolen
   from the thread model, v2: long-press ⌄ fans out the session trail.
9. **Staying is the default; leaving is a verb.** A bare tap NEVER ejects the
   user from the agent. "Open in app ↗" is written on content as an explicit
   verb; it lowers the agent and opens the thing in the app.
10. **Design law applies untouched** (docs/build-brief.md §8): Liquid Glass on
    the floating layer only (bar, whisper, ✕ — never on content panels; a
    results panel wearing glass was explicitly caught and killed this
    session), no hairlines, no dead controls, honesty everywhere (pulse only
    when true; deltas only real diffs; a stale answer states "as of" rather
    than pretending freshness).

## Explicitly NOT ruled — do not build, do not touch

- **Home/board's fate.** Whether the board merges into the feed is deferred.
  Do not modify `HomeComposition`, the board, landing logic, or the real shell.
- **The Deck** (multi-card sessions) — shelved as a someday-iPad idea.
- **Ember persistence** (retained past answers) — rejected for now.
- **New GenRenderer components** (value-weighted treemap, Hero-as-block, Row
  delta pills — the "answer anatomy" spec). Real work, separate later goal.
  Phase 1 uses existing components and accepts their Home-shaped flaws.
- Anything touching the shipping app: schema, catalog, website, verify.sh.

## Phase 1 — build the full loop as a throwaway prototype (the deliverable)

Everything stays behind `-summonProto YES`, isolated from the shipping app
(build 91 is in App Store review — the real shell must not change). Extend
`Casberi/Casberi/Screens/SummonPrototype.swift` (exists, working: rest state,
chip narrowing, streaming compose via `GenStream`/`GenRender`, `-summonQuery`
hook) and the one branch in `Shell/RootShell.swift` (exists; keeps
`.dsColorScheme()` — without it adaptive tokens resolve light-on-dark and
text vanishes; already learned the hard way).

Build, in order:

1. **Delete sheet mode.** Remove `-summonMode`, `sheetMode`, `restBar`; full
   is ruled.
2. **A stand-in content screen** inside the prototype: a static fake feed
   (source-chip header + ~6 hardcoded rows — include Peer "Bought 25 USDC
   with Venmo on Peer" and 1Claw "Vault grant: agent read · expires Fri" rows;
   they're the user's own scroll-beats-ask examples). This is scenery, not the
   real MainSurface — do not wire the real feed.
3. **The bar over content**: glass pill at bottom of the stand-in feed,
   "Ask your things…" + ✦. The ✦ **pulses** (repeatForever opacity/scale
   breath, ~2s cycle; respect Reduce Motion) while any `KeptAsk.changed` is
   unseen; seeing = the agent has been raised this launch. No badge.
4. **Rise/lower**: bar tap raises the agent full screen (one animated
   transition — cover-style, `DS.Motion.standard`); ⌄ in the bar and ✕ top
   corner both lower it, restoring the feed exactly (scroll position
   preserved). This transition is the thing the user most needs to FEEL —
   spend the effort here, not on features.
5. **Signals on chips**: extend `KeptAsk` with `delta: String` (already has
   `changed`); render B1 pills — dot + title + "· delta" in secondary ink,
   changed-first sort, one decayed-dim example.
6. **The Stack**: wrap the agent's content in a `NavigationStack`. Composing
   an answer = the root; tapping the dwr row in the "While I was away?"
   answer pushes a hand-built generative thing-view (avatar, full cast text,
   meta, two replies, verbs "Profile" / "Open in app ↗") — plain SwiftUI in
   the prototype file, NOT a new GenRenderer component. "Open in app ↗"
   lowers the agent (stand-in feed reappears; log it). Bar placeholder
   becomes "Ask about this…" while a doc is up.
7. **Headless hooks** for verification: keep `-summonQuery`; add
   `-summonStage rest|risen|answer|thing` to jump the UI to each state so
   every stage screenshots without typing (computer-use typing trips the sim
   accent picker — CLAUDE.md). NSLog each stage change.

Verification (per CLAUDE.md's gotchas): plain `xcodebuild` on iPhone 17 Pro
sim; install the NEWEST DerivedData and verify the installed binary actually
contains the hooks (`strings … | grep -c '^summonStage$'`); screenshot rest /
risen / answer / thing-view / lowered; `database is locked` → retry.

**Stop after Phase 1.** Present the screenshots and the launch command. The
user rules on feel (especially the rise/lower and the pulse) before anything
touches the real shell.

## Phase 2 — gated on the user's Phase-1 ruling (do not start)

Productionizing, roughly: bar replaces the FAB in the real shell; the agent
replaces the composer sheet (the composer's answer path, `lastAnswerHits`,
Organize, byok routing all fold in); a last-seen store for signal diffs; the
Noticed/away intelligence moves from `HomeComposition` into kept-ask
composers; record the ruling set in docs/prd.md; then the answer-anatomy
components. Each of those is its own goal with its own checkpoint.
