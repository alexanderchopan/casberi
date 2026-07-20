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
11. **The agent replaces the Pinned board** (added by user ruling, same day).
    The "Pinned" chip and its board die; the app opens on the **All feed**
    (the landing heuristic in `RootShell` simplifies to just that), and
    `casberi://home` repoints to the feed so widgets/App Intents keep working.
    The why is the division law applied: the board's glance job (per-app
    signals) moves to the agent's chips; its scroll job was always the feed's
    (the source-chip header already gives per-app views). Keeping the board
    would rebuild Home beside the agent. **No migration** of pins or
    arrangement — `HomePinnedSources`/`HomeBoardOrder` data is deleted with
    the board (TestFlight-scale user base; the kept-ask set starts fresh and
    user-authored).
12. **"Pin to Home" becomes "Keep the ask."** Pinning is no longer an action
    anywhere. On the ~23 connection/setup screens carrying `PinToHomeButton`
    (BridgeDetailScreen, PeerScreen, WalletScreen, RSSScreen, the import
    screens, …), the button is replaced by keeping that surface's standing
    ask in the agent — e.g. Peer → keep "What's new in Peer?", Wallet → keep
    "How's my money?", a token page → keep that token's ask. Per the
    vocabulary law the action mints a **chip, never a row**, and the button
    states what it does ("Keep the ask" / kept state shows it's kept —
    honesty rule, no dead controls).

## Explicitly NOT ruled — do not build, do not touch

- **The Deck** (multi-card sessions) — shelved as a someday-iPad idea.
- **Ember persistence** (retained past answers) — rejected for now.
- **New GenRenderer components** (value-weighted treemap, Hero-as-block, Row
  delta pills — the "answer anatomy" spec). Real work, separate later goal.
  Phase 1 uses existing components and accepts their Home-shaped flaws.
- Anything touching the shipping app: schema, catalog, website, verify.sh.
- **Executing rulings 11–12.** They are settled, but their execution is
  Phase 2: in Phase 1 do NOT touch the board, `HomeComposition`,
  `PinToHomeButton`, landing logic, or any real screen.

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

Productionizing. Each block below is its own goal with its own user
checkpoint — do not run them together.

**The shell.** Bar replaces the FAB in the real shell; the agent replaces
the composer sheet (the composer's answer path, `lastAnswerHits`, Organize,
byok routing all fold in); a last-seen store for signal diffs; the
Noticed/away intelligence moves from `HomeComposition` into kept-ask
composers.

**Dismantling the Pinned board (executes rulings 11–12).** The inventory,
measured 2026-07-19 — sweep again before cutting (`grep -rn "Pinned\|
HomePinnedSources\|HomeBoardOrder\|PinToHome\|boardRefs\|pinSource\|
pinWallet"`):

1. Landing: `RootShell`'s board-vs-feed heuristic → always the All feed;
   `casberi://home` → the feed (widgets/App Intents route through it).
   Remove the "Pinned" chip from the source-chip header.
2. Delete the board render path: `Screens/HomeScreen.swift`'s board,
   `HomeComposition`'s board composition (cover, appRows, walletRow,
   boardRefs/boardKeys), `Design/BoardDragDriver.swift`,
   `Design/ReorderableBoard.swift`, `Model/HomePinnedSources.swift`,
   `Model/HomeBoardOrder.swift`, and the board-only branches in
   `GenUI/GenRenderer.swift` (GenAppRow etc. — check nothing else renders
   them first).
3. Replace `Screens/PinToHomeButton.swift` with the keep-the-ask button and
   update all ~23 call sites (BridgeDetailScreen, PeerScreen, WalletScreen,
   RSSScreen, TokenWatchScreen/TokenSetupScreen, OpenSeaScreen,
   GeckoTerminalScreen, StocktwitsScreen, KalshiScreen, DealsScreen,
   MailScreen, SpotifyScreen, SteamScreen, TwitchScreen, ShopifyScreen,
   HandleSetupScreen, ObsidianScreen, KindleImportScreen, the
   ChatGPT/Claude/Gemini/Notes import screens). Wallet's pin →
   "How's my money?"; a source's pin → its context ask
   ("What's new in <App>?"); a token's pin → that token's ask.
4. Hooks: retire `-pinSource`/`-pinWallet` (Shell/ProbeHooks.swift); add
   `-keepAsk "<key>"` + a probe that NSLogs the kept-ask set, so the button
   verifies headlessly.
5. Home-only furniture: the banner/cover wallpaper (`HomeBackgroundStore`,
   `-setHomeBanner`, the Banner tray in Settings) retires with the board —
   remove the tray (no dead controls). Flag at the checkpoint: the user may
   later want wallpaper on the agent's rest greeting instead.
6. Docs: record rulings 11–12 (and the rest of this brief's set) in
   docs/prd.md; update CLAUDE.md's Home/pinning hook docs; retire the
   `-comingUpProbe`/board references there.

**Then** the answer-anatomy components (the spec artifact), as their own
goal.
