# Wallet performance spec

*2026-11-09. For whoever implements it. Written from a read of the tree at `2cc0dd60f`, not from a profile: every finding below cites the code that does the work, and **none of it has been measured**. Phase 0 takes the numbers; everything after re-ranks against them.*

Read `docs/perf-spec.md` "Method" and "Dead fixes" first. Its four rules apply here unchanged: sample first, interleaved A/B, structural over tuned, and any fetch hoisted earlier is a liveness change.

## What "fast" means here

Three waits a person feels, each with its own span:

| Span | From | To |
|---|---|---|
| **Open** | Wallet tab tapped | Home drawn from the last reading, hand free |
| **Current** | Wallet tab tapped (or pull) | the live total replaces the last reading |
| **Settled** | refresh starts | Activity's new rows landed and Home's doors (Needs you, Permissions, Threats) current |

Open is main-actor work. Current and Settled are almost entirely network waits over Tor (6–45 s per Zerion request by the source's own comments), so the wins there come from taking requests off the path and overlapping the ones that stay, never from tuning timeouts.

## Constraints that bound every item

- **Tor stays (prd §1495, §1546).** No direct fallback, no shorter global timeout. A wallet's reads share one circuit; different wallets already run on different circuits in parallel.
- **Zerion is one shared pool: 2,000 a day, 3 a second, for every install** (`ZerionLane`, prd §1722). An item may lower the request count or reorder requests. It may never raise the count.
- **Honesty (prd §83, §825, §1722).** The last reading is stamped, a windowed figure is dated, a wallet that could not be reached stands on its last reading. No item may draw a partial total as a total.
- **No design change.** Nothing here moves, adds or removes anything on screen. One item would have changed behaviour (C6, relevance gating); it was ruled out.
- **Liveness (`docs/liveness.md`).** Any item that moves a fetch or holds `[Thing]` across an await re-checks `.live` at the last await by hand.

## Phase 0 — instrument and baseline (do this first, ship it alone)

There is no wallet instrument today. `WalletIngest.refresh` has no `SweepClock.measure` label, the `ForegroundSweep` signpost brackets a call that only spawns a task (`Shell/RootShell.swift:2311-2318`), and the views carry only the generic `perfAccum("feedList[Wallet]")`.

Add, behind `-walletPerf YES` (works in Release, like `-launchTimer`):

1. `walletPerf| open` — tab tap → first body pass with a figure → `GestureGate` idle. Record through `PerfReadings.record("WalletOpen", …)`.
2. `walletPerf| current` — `streamBlock` entry → `portfolioReading` returned, split into: Tor ready, holdings (per wallet), each serial extra at `WalletIngest.swift:2319-2337`. `PerfReadings.record("WalletCurrent", …)`.
3. `walletPerf| pass` — `WalletIngest.refresh` entry → transfers inserted → each rider (one line per rider with ms and whether it wrote anything) → return. `PerfReadings.record("WalletPass", …)`.
4. Counters per pass: Zerion requests, Alchemy requests, `valueSamples` decodes, `feedList[Wallet]` builds, `saves=N asked=M`.

Then baseline, **Release on the phone**, the owner's real accounts, five opens cold and five warm. Also one `sample` of the main thread across a Wallet open on the simulator over the demo pour. Write the numbers into this file under "Baseline". On the simulator a DEBUG build reads no chain without `-liveChains YES`, and that spends the shared pool: check `ratelimit-org-day-remaining` with one curl before a probing session.

**Exit:** the three spans and the four counters exist as numbers. If Open is already under ~150 ms and the sample shows no wallet frame above a few percent, drop workstream B to its first two items and spend the time on A and C.

## Workstream A — Current: the live total

**A1. Holdings are read twice when more than one wallet is watched.** The screen asks per wallet (`WalletIngest.swift:2648`); `refresh` asks for all addresses at once (`:618`), and `HoldingsCache` keys on the sorted address set (`:3129-3131`), so the second ask misses and every wallet's `/positions` goes out again. Fix: `refresh` composes its combined answer from the per-wallet entries (ask per wallet through the same cache and in-flight map, then merge). *Work that no longer runs:* N Zerion requests per pass for an N-wallet person. Proof: the Phase 0 Zerion counter reads N, not 2N, on a pull.

**A2. The total waits on five reads in series after holdings return.** `portfolioReading` awaits `ExchangeBridge.pricedBalances`, `EthValidatorRead.totalUSD`, `WalletCash.priced`, three private stores' `walletHolding()` and `LendMove` one after another (`:2319-2337`). None depends on another. Start them as `async let` beside the holdings read and join once. The figure still paints once, whole. *Sum becomes max.*

**A3. Tor starts after the activation sleep.** `TorClient.shared.start()` sits in `runForegroundWork` behind a 250 ms sleep (800 ms on first activation) (`RootShell.swift:2199`). Its own comment says it starts a thread and returns. Move the call to launch, same guard (`addresses` non-empty, not the demo). *Runs earlier;* worth up to the sleep on a cold open, more if bootstrap is the long pole. Phase 0's "Tor ready" split says which.

**A4. A failed chain-filtered read is retried unfiltered** (`Model/ZerionAPI.swift:235`): a second full Tor round trip and a second pool request on the failure path. **Measure only.** Log how often it fires and whether the retry ever succeeds where the first read failed. Remove it only if the log says it never does.

## Workstream B — Open: main-actor work in the room

The Wallet's sections are `FeedScreen` extension functions, not child views, so any invalidation (`walletLive`, `portfolio`, `chrome`, the `@Query`) re-runs all of them. Every item below is "runs once" or "no longer runs".

**B1. The balance history is JSON-decoded from defaults on every body pass, twice.** `walletTilesSection` calls `wallet.combinedValueSamples()` / `valueSamples(forAddress:)` (`Screens/FeedScreen+WalletTiles.swift:225-227`); each call reads `ScratchDefaults` and decodes up to 1,000 samples per address with a holdings dictionary each (`Model/WalletStore.swift:539-544`), then merges them at roughly quadratic cost (`:561-578`). `walletFaceChipEntries` decodes every address again in the same pass (`WalletTiles:612-613`), and `TokenChart.from(samples:)` runs twice (`:232`, `Screens/WalletWindowed.swift:53`). Fix: `WalletStore` holds decoded samples per address in memory, filled off the main actor at first ask and replaced by the one writer that appends a sample; the merged line is memoised on (address set, a samples revision the writer bumps). The memo key is a claim about what the function reads: derive it by reading `combinedValueSamples`, including `only:`. *Expected to be the largest single item on Open.*

**B2. The chrome row remounts on every total change** (`.id("walletChrome:\(totalUSD)")`, `Screens/FeedScreen+WalletRoom.swift:291`), at least twice per open (last reading, then live), replaying B1 each time. The remount is deliberate (prd §1587). **Leave it.** Re-measure after B1; it should then be cheap. If it is not, bring the number back before touching it.

**B3. Derivations over up to 600 rows run unmemoised on every pass, on every tile.** `DerivationMemo` exists (`FeedScreen.swift:709`) and the wallet case does not use it.
- `liveVisible()` calls `walletScopeAllows` per thing, and that re-resolves `selectedSeat`, `connectedSeatNames` (a set over every bridge), a `BridgeCatalog.category` lookup and, on Following, a defaults read (`FeedScreen+Derivations.swift:268-278`, `WalletTiles:107`). Resolve those four once before the filter.
- `walletUpcoming`, `promoted`, `all` (`FeedScreen+ShapedSections.swift:311-325`), `walletMoves` (twice: `WalletRoom.swift:54`, `WalletPages.swift:1042`), `walletAccountRows` (twice), `walletAccountSlots` (three to four times, `WalletRoom:345-378`), `portfolioShown` (about a dozen reads, `WalletTiles:54-69`): compute once per pass and put the row-derived ones behind `DerivationMemo` on its existing O(1) key.
- Only the visible tile's derivations run. Activity's stream is not built while Home is up.

**B4. Home starts two whole-history fetches of full models on the main actor.** `SpendingReading.refresh` fetches two months of Wallet, card and Wise rows (`Model/SpendingSource.swift:67-74`); `SubscriptionsReading.refresh` fetches with no floor and no limit (`Model/SubscriptionsSource.swift:36-40`). Both are keyed on `chrome.refreshPulse`, so both re-run on every refresh (`FeedScreen+Subscriptions.swift:19-22`). Home needs them only for Needs you and Spending's door. Fix, in order:
1. Key them on a revision of the rows they read, not the pulse. *No longer runs when nothing landed.*
2. Start them after the first paint and a still hand (`GestureGate.idle()`).
3. Move the fetch and derivation to a `@ModelActor` on a background context that returns value types. Do **not** reach for `propertiesToFetch`: both fetches are predicated, which is the iOS 18.6 defect in the dead-fix list.

**B5. Opening and re-scoping fetch every flagged Wallet thing, full models, synchronously** (`loadWalletLive` → `WalletWatch.quickState` → `flagged()`, `Model/WalletWarnings.swift:464-468`). Where the caller needs a count, use `fetchCount`; where it needs rows, same actor as B4.

**B6. `transferUSD` is read per row and is not in `lightColumns`** (`FeedScreen.swift:462-485`; read at `WalletRoom.swift:1501`, `:1584`), so on iOS 26+ each drawn row faults. Add the column. `walletSeatHeld` reads `content` (`WalletRoom.swift:974`), a column excluded on purpose: check whether it can read a light column instead, and leave it if not.

**B7. Per-row work in `walletMoveRow`** (`WalletRoom.swift:1562-1696`): `WalletStore.label(forAddress:)` walks the addresses per row, `WalletCards.isSpend` runs three to four times, `parseAmount`/`tokenSymbol` twice. Build one address-to-label dictionary per pass and bind the repeated calls once per row. There is no scroll instrument, so stop at these read-proven ones; do not restructure the row into its own view without a sample that asks for it.

**B8. The treemap squarifies on every body pass** inside its `GeometryReader` (`Design/HoldingsTreemap.swift:193-196`), with a `first(where:)` per tile (`:279`). Memoise the layout on (holdings signature, size). Low priority; do it only if the Holdings sample shows it.

## Workstream C — Settled: Activity and the doors

`WalletIngest.refresh` is one `@MainActor` function (`WalletIngest.swift:402`). Its waits are network; its main-actor work is small. The dead fix "concurrent `refreshDigests`" does not apply here: that one overlapped CPU, this overlaps Tor round trips.

**C1. About thirty riders are awaited one at a time, and the doors come last.** After transfers land, `refresh` awaits approvals, Peer, Privacy Pools, Railgun, the card seats, Aztec staking, ENS, Solana, Bitcoin, delegations, Aave, Morpho, Hyperliquid, Aerodrome, World, Uniswap and finally Safe (`:751-855`). Needs you waits on Safe; Permissions waits on approvals and delegations. Two steps:
1. **Reorder.** Safe, approvals and delegations go first. *Free, no risk.*
2. **Overlap.** Split each rider into a fetch that takes plain values and returns plain values, and a land that takes the context on the main actor. Run the fetches in a bounded group (start at 4), land each as it returns. Riders that loop `chain × address` serially inside (`WalletApprovals.swift:378-380`, `WalletSafety.swift:152`, `WalletDeFi.swift:264`) get the same treatment within the rider. Anything that reads Zerion still goes through `ZerionLane`; Alchemy still through `AlchemyBrake`. Convert the doors' riders first and measure before converting the rest.

**C2. Activity's first insert waits on a serial chain of prerequisites** (`:461-651`): name resolution, Zerion transactions, the Alchemy NFT fan-out (`wallets × chains × 2`, `:1607-1609`), `tacitWithdrawals`, `counterpartyNames`, the holdings read, `ownedNFTContracts`, `verifiedNFTKeys`, `nftSignatures`. The spam filters need most of them before a row may show, so the rows cannot land earlier. The reads can overlap: start the independent ones together and join before the filter. *Sum becomes max.* Do not insert rows before the filters have their inputs; that would draw spam and then remove it.

**C3. Each pass opens with three unbounded Wallet-source fetches, one of them repeated** (`existingSourceRefs`, `existingContent`, `coveredContent` at `:444-454`, `coveredContent` again at `:791`), and indexes Spotlight one row at a time (`:741-744`). Fetch once and keep the sets current as the pass inserts; index the pass's rows in one call at the end.

**C4. The wallet's sweep slot sits behind about 35 others** (`Model/BridgeRefresh.swift:633`; 1,800 ms lead-in plus 120 ms a slot, so up to ~6 s after activation). When the Wallet is the place on screen at activation, give its slot the first position. Nothing else about the sweep's pacing changes.

**C5. `HoldingsCache.store` and `invalidate` re-encode the whole window map to defaults** (`:2984`, `:3010`). Small. Fold it into C3's pass only if Phase 0 shows it.

**C6. DECLINED — relevance gating (user, 2026-11-09: "a missed position would be worse than slower").** Every rider keeps asking every wallet on every pass. A first position in a protocol shows on the next pass, never a day late. Do not re-propose a once-a-day ask for a rider that found nothing; the request count is lowered by A1 and the waits by C1 and C2 instead.

## Workstream D — the private engines

Both engines are main-actor hidden web views (`Model/Aztec/AztecEngine.swift:18`, `Model/RailgunEngine.swift:31`). `MoveWarm.start()` fires on every activation and on Wallet open, and each `warm()` waits 3 s and a still hand before starting (`Model/MoveWarm.swift:16`, `Model/Aztec/AztecAccountStore.swift:304`, `Model/RailgunHoldings.swift:108`). That puts web view and WASM start-up in the same seconds as the holdings read and the sweep. **Unmeasured, and a guess until it is.**

**D1.** Phase 0 adds one span: engine start → ready, with the main-thread stall count across it.
**D2.** If D1 shows stalls inside Open or Current: on the Wallet, start the engines when `portfolioReading` returns (capped at 10 s) rather than at 3 s. prd §1700v and §1728 say the engine starts before it is asked and the wallet syncs on open; "after the balance is current" still honours both.
**D3.** The Private section's `.task` starts a second `RailgunHoldings.refresh` and `PrivateWatch.findNotes` (`Screens/FeedScreen+WalletPrivate.swift:44-55`); `MoveWarm` starts two tasks per network unconditionally (`MoveWarm.swift:20-23`). Coalesce onto the in-flight one.

## Already built — do not re-propose

Last-reading paint with its stamp (`WalletLastReading`); the persisted 10-minute holdings window with in-flight coalescing and transfer-landed invalidation (`HoldingsCache`, `holdingsRevision`); `ZerionLane` (3 in flight, `ahead`, 429 handling) and `AlchemyBrake`; Tor circuit retirement and one retry; `SaveCoalescer`; the sweep's stagger and 45 s floor; `GestureGate`; `MoveWarm`; per-address log cursors; the bounded light-column room query (600, `rowBudget`); `headMemo`; Spending's cached pick/narrow.

Also dead on arrival: BYOK or per-user keys for balances; a direct (non-Tor) fallback; a permanent tighter `fetchLimit` on the room; offset-paging any `capturedAt`-sorted fetch.

## Order, and what done looks like

1. **Phase 0**, alone, then the baseline on the phone.
2. **A1, A2, A3, C1 step 1, B1, B6** — small, structural, independent. One commit each.
3. **B3, B4, B5, C2, C3, C4.**
4. **C1 step 2**, the doors' riders first.
5. **D** and **B7/B8** only where Phase 0 or a sample asks.
6. ~~C6~~ declined.

Per item: the build (`scripts/xcb.sh`), the item's own counter from Phase 0 showing the work gone (interleaved A, B, A, B where it is a timing), the wallet self-tests (`wallet-total-audit.py`, `wallet-row-audit.py`, `row-cost-audit.py`, `spending-selftest.sh`, `subscriptions-selftest.sh`, `swiftdata-liveness-audit.py`), and a look at the Wallet on the simulator. Full `scripts/verify.sh` once, after the last item.

Guards to add as the items land, each with a mutation that proves it bites:
- `row-cost-audit.py`: no `valueSamples(` or `combinedValueSamples(` reachable from a body without the memo (B1); `walletScopeAllows` resolves nothing per thing (B3).
- A harness for A1: two wallets, one pass, the per-wallet cache asked once each.
- A harness for C1: the doors' riders are started before any other rider.

Record the pass as one prd § when it ships, then `python3 scripts/law-digest.py`.

## Status (2026-11-09)

**Built:** Phase 0 (`Model/WalletPerf.swift`: `WalletOpen`, `WalletCurrent`, `WalletPass` in `PerfReadings`, request and decode counters, `-walletPerf YES` logs every rider), A1, A2, A3, B1, B3 (the scope resolved once per filter), B4 (one keyed read per open instead of up to three, after the hand is still), B6, C1 step 1, C2 (the spam filters' three reads start beside the transfer reads), C3 (Spotlight once per pass), C4. Guarded by `scripts/wallet-perf-audit.py` (8 rules, 9 mutations); `wallet-total-audit.py` rules 6–7 follow A2 and A3.

**Not built, and why:**
- **A4** (the unfiltered retry): measure only. `walletPerf| current` now gives the holdings time to compare against.
- **B2** (the chrome row's remount): left, as the spec says, until B1 is measured.
- **B3, the rest** (`walletMoves`, `walletAccountRows`, `walletAccountSlots`, `portfolioShown` computed more than once per pass): these sections live in files with uncommitted work from another session; the scope fix was the per-row part.
- **B4 step 1 and 3** (a row revision for the key, a background actor): no cheap revision of those sources exists, and a price heal changes amounts without changing the row count, so a count-based key would leave Spending stale (§83). Step 2 and the duplicate reads are done.
- **B5**: the fetch is predicated on `securityFlag != nil`, so it returns only flagged rows, and its rows feed a `ForEach`; a count cannot replace it. Measure before moving it.
- **C1 step 2** (overlapping the riders): the spec gates it on a measurement of step 1.
- **C3, the second `coveredContent`**: it reads the seat rows the riders above it just landed, so it is not a repeat.
- **D**: D3 needed nothing (both engines already join a read under way); D1/D2 wait on a phone reading.
- **B7, B8**: only where a sample asks.

## Baseline

*Empty until Phase 0 runs on the phone. With `-walletPerf YES` (or without it, through `-perfReadingsProbe`): five cold opens and five warm, the owner's accounts, Release.*
