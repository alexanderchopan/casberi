# Casberi

Native iOS app — a personal corpus of "things" (links, screenshots, events, chats, voice notes, agent outputs). Solo project, live on the App Store (iOS and Mac); betas ship via TestFlight. Growth plan: `docs/marketing/growth.md` (local).

**How this file is organised.** It is a RULE SHEET, loaded into every session — rules,
build commands, gotchas, and a one-line index of every DEBUG hook. The long-form record
of how each thing was built and what it cost lives in `docs/`:
`docs/verify.md` (the verification pipeline), `docs/hooks/*.md` (per-area feature and
probe entries, verbatim; `design.md` holds the design-law long form), `docs/gotchas.md`
(the SwiftUI/UIKit gotchas in full), `docs/website.md` (the website rules in full),
`docs/prd.md` (the append-only ruling ledger, reached by `§N`).
Every index line below names the file to open. **Keep this file under 100KB** —
`verify.sh` fails the pass above that; new long-form entries go to `docs/`, not here.

## Repository & working directory (RULE)

- **The canonical working copy is `~/Developer/casberi` — NOT iCloud Drive.** Always work here. The old iCloud copy (`.../myStuff/product/casberi`) is deprecated; do not edit it.
- Backed by a **PUBLIC** GitHub remote `origin` → https://github.com/alexanderchopan/casberi. **Every commit is world-readable the moment it lands**, so nothing secret may ever be committed: real keys live in the login Keychain via `scripts/dev-keys.sh`, and the only in-tree credentials are public ids (Reown, Dropbox) and the shared read-only Alchemy and Zerion keys. Actions minutes are free for public repos. A `post-commit` hook auto-pushes to `origin` in the background (`.git/last-autopush.log`). Solo, straight to `main`, no branches or PRs. Committing is NOT a release — releasing is `scripts/testflight.sh`.

## Layout

- `Casberi/Casberi.xcodeproj` — the Xcode project. Targets: **Casberi** (app), **ShareExtension** (appex), **CasberiWidgets** (widget bundle). Bundle id `com.casberi.app`; app group `group.com.casberi.app`.
- `Casberi/Casberi/` — app sources (`Design/`, `GenUI/`, `Model/`, `Screens/`, `Shell/`).
- `Casberi/Shared/` — sources compiled into both app and extension targets.
- `docs/` — **build-brief.md §8 (design system) is law**; prd.md carries product rulings; map: `docs/README.md`.
- `design/app-icon/` — icon SVG sources.
- The pbxproj is **hand-authored** (objectVersion 77, file-system-synchronized groups). New source files in synced folders are picked up automatically; Info.plist keys and target settings are edited directly in the pbxproj.

## Xcode MCP and Apple docs (RULE)

- **Xcode's MCP server is registered at user scope** (`claude mcp add --scope user --transport stdio xcode -- xcrun mcpbridge`, Xcode 27). It only connects while Xcode is running with the project open and *Xcode > Settings > Intelligence > "Allow external agents to use Xcode tools"* is on. Prefer its build/test/diagnostic tools over a raw `xcodebuild` when the session has it.
- **Read Apple developer docs as Markdown, never the HTML page** (it is a JS app and fetches as an empty title). For `/documentation` pages append `.md` (`https://developer.apple.com/documentation/swiftui/view.md`); for `/design` and `/tutorials` pages also insert `/tutorials/data` before the path (`https://developer.apple.com/tutorials/data/design/human-interface-guidelines/buttons.md`); the few pages with no Markdown version take `.json` in place of `.md`.

## Building (critical)

From the canonical `~/Developer/casberi` copy, a plain build codesigns cleanly — no workaround needed:

```sh
scripts/xcb.sh -project Casberi/Casberi.xcodeproj -scheme Casberi \
  -destination "id=$(scripts/sim-device.py)" build
```

**RULE: build through `scripts/xcb.sh`, never bare `xcodebuild`** — same arguments and exit, behind one machine-wide lock, so builds queue instead of running 3× over the cores (load 66 on 8, 2026-10-07). It says who holds the lock while it waits; `XCB_NO_LOCK=1` for a cheap `-showBuildSettings`. verify, verify-mac and both ship archives use it.

Or just run `scripts/verify.sh` (build + install + screen sweep + answer probe).

**The pass, in the rules a session needs before opening anything.** Full record:
`docs/verify.md`.

- **Run `scripts/verify.sh`, not the audits you happen to remember.** That is mechanical,
  not moral: a build shipped an undisclosed host because two audits were run by hand and
  green, and the third was never invoked.
- It **compiles Mac Catalyst and hard-fails** (step 1b), and **launches `verify-mac.sh` in
  parallel and gates on it** — so one green means both platforms, and a Catalyst break is
  reported where the Mac leg is waited on, at the end.
- Audits and self-tests are **discovered (`scripts/*-audit.{py,sh}`) or hand-listed and
  proven complete**; every check must have a `--self-test`, because a check that cannot
  demonstrate it catches anything certifies nothing.
- The ~93 pure-logic harnesses run **concurrently, longest-first, through a skip cache**
  keyed on the harness plus every input it names. A failing harness is never stamped.
- The **nightly ledger is read back and REPORTED, never gated on** — its verdict describes
  a different commit, and staleness is reported apart from failure.
- `scripts/live-integrations.sh` stays **separate and warn-only** (keyless third-party
  liveness, always `exit 0`). Do not fold it in and do not add a keyed check to it.
- Knobs: `--build-only`, `LAUNCH_CYCLES=0`, `SKIP_CATALYST=1`, `SKIP_MAC=1`, `SKIP_LIVE=1`,
  `VERIFY_NO_CACHE=1`. (`SKIP_LOGIC=1` is verify-mac.sh's; verify.sh always runs the harnesses.)
- **Read `$OUT/step-times.tsv` (slowest ten, printed by the EXIT trap) before aiming any
  work at this suite.** Three separate passes have found that "verifying is slow" was not
  the standard cost of good tests.

**The checks themselves** — one line each; what each catches, why it exists and what it
deliberately does not check are in `docs/verify.md`.

- **Mac parity audit (scripts/mac-parity-audit.py)** → docs/verify.md
- **Account-detail sheet gate (verify-mac.sh step 2d, 2026-09-21) — a Catalyst sheet does NOT inherit the presenter's environment, and the shipped Mac build died on every Accounts → Settings row that raises one** → docs/verify.md · prd §872
- **Both verify scripts are provably complete** → docs/verify.md
- **The pure-logic harnesses run at once, and an unchanged one is not re-run (PERF, 2026-08-19)** → docs/verify.md
- **PERF: the pass ran every harness TWICE for eleven days (2026-09-01), and was mostly IDLE CORES — time every step before optimising it** → docs/verify.md · prd §612

- `-refusedForget YES` — clear every learned Alchemy chain refusal and drop the holdings window, so the next read asks every selected chain again (prd §827b). A refusal stands a WEEK: right in the field, a trap at a desk → prd §827b
- **Every `seeded` key is `.v2`, because the `.v1` flags are POISONED (prd §827a).** The old loop recorded the flag BEFORE the guard that adds the chain, and the add could not persist from `init`. → docs/hooks/wallet.md · prd §827a
- **`WalletChainStore.effectiveIDs` is the ONE rule for which chains are on, and the static `activeNetworkIDs()` (which EVERY ingest reads) resolves through it (prd §827).** → docs/hooks/wallet.md · prd §827 · §83
- **Tempo (Stripe's L1, 4217) is ON by default and read through Zerion ONLY (`onAlchemy: false`, prd §810).** No native coin: never read a native balance there. `network-reach-audit.sh` honours `onAlchemy: false`, so such a row discloses no Alchemy host → prd §810 · §828
- **Robinhood reads through Zerion (Alchemy prices none of it, §828) and on Alchemy too (`WalletIngest.zerionOmits`); a DEX-only token is priced by `DexPrices` only off a pool ≥$10K holding ≤25% of it, a native coin takes the cent floor (prd §968)** → docs/hooks/wallet.md · prd §828 · §968
- **Zerion is THREE in flight, 0.4s between starts, holdings `ahead` of transactions, and the day's pool read off the headers (`ZerionLane`, prd §934 · §1722; Developer tier since 2026-10-20). The holdings window (10 min) is DATED when a hit is older than a minute and THROWN OUT for a wallet a transfer landed at (`WalletStore.holdingsRevision` re-reads the room)** → docs/hooks/wallet.md · prd §934 · §1722
- **The wallet crown counts YOUR accounts, and Zerion answering does not end the read (prd §826).** → docs/hooks/wallet.md · prd §826
- **One Wallet (prd §1048): the money rooms merge into one room (Markets, Logos stay apart); its total adds cash (`WalletCash`: Wise + Apple Wallet assets, Kraken's six fiat pairs, the rest left out and named) and Privy's apps, never Privy alone, both on the combined page only (`wallet-total-audit.py` rule 6)** → prd §1048
- **One chain may not empty every wallet's balances, and a wallet we could not reach stands on its LAST READING, stamped (prd §825) — the room showed a Privy app wallet's stored figure and none of the person's own.** → docs/hooks/wallet.md · prd §825
- **The address book's delight pass** → docs/hooks/wallet.md · prd §441
- **Address-book shape self-test (scripts/address-book-selftest.sh)** → docs/verify.md · prd §440
- **Sheet sweep (`journeys.sh sheets`, nightly): every sheet opened and closed; `sheet-sweep-audit.py` fails one missing from `sheet-sweep.json`** → docs/verify.md · prd §1308
- **SwiftData liveness audit (scripts/swiftdata-liveness-audit.py)** → docs/verify.md
- **Info.plist strings audit (scripts/infoplist-strings-audit.py, ITMS-90738)** → docs/verify.md
- **Keychain policy audit (scripts/keychain-audit.py)** → docs/verify.md · prd §277
- **Receipts coverage audit (scripts/receipts-coverage-audit.py)** → docs/verify.md · prd §277
- **CloudKit schema audit (scripts/cloudkit-schema-audit.py)** → docs/verify.md
- **Redaction coverage audit (scripts/redaction-coverage-audit.py)** → docs/verify.md · prd §277
- **Ref-shape audit (scripts/ref-shape-audit.py)** → docs/verify.md
- **Delete-guard audit (scripts/delete-guard-audit.py)** → docs/verify.md
- **Clear-signing self-test (scripts/clearsign-selftest.sh) — the registry's OWN test vectors through `ClearSign` (528/530, one reasoned allowance), plus hostile calldata, `mustMatch`, a shared selector and the Safe reader's priority** → docs/verify.md · prd §834
- **Safe signer §913 self-test (scripts/safe-signer-selftest.sh) — EIP-712 pinned to the spec's vector, the SafeMessage, recovery and WebAuthn preimages, the peer's allowlist; 33 mutations** → docs/verify.md · prd §913
- **Wallet-total audit (scripts/wallet-total-audit.py, was `chain-filter-audit.py`)** → docs/verify.md · prd §825 · §826
- **Card-spend audit (scripts/card-spend-audit.py) — the three onchain-card seats, and four failures that compile and look right** → docs/verify.md · prd §857
- **The demo's mark: on the phone "Exit demo" ends the title row (`demoTagOnTitle()`), none on a pushed page; iPad/Mac keep the top pill** → prd §919 · §1389
- **The demo is one person's life (prd §1026): a topic (`ocrTopics`) in at most two rooms, no room leading three topic rows with one word, and the person's app is Quillmark, never Casberi (`CasberiTests/DemoSpreadTests`); pictures are drawn by `scripts/demo-art/render.py`, one generator per imageset** → prd §1026 · §890
- **Dead-closure audit (scripts/dead-closure-audit.py) — a control calling a closure property nothing ever supplies** → docs/verify.md · prd §669
- **Way-back audit (scripts/way-back-audit.py) — every screen has a way back: a full-screen cover shows a close control on every branch, no sheet switches its swipe off unlisted, a hidden back button keeps `DSSwipeBack()`** → docs/verify.md
- **Defaults-lock audit (scripts/defaults-lock-audit.py) — a lock held across a `UserDefaults` write deadlocks with every view body (build 570)** → docs/verify.md · prd §721
- **ShareLink style audit (scripts/sharelink-style-audit.py) — an unstyled share control in a `List` row becomes the row's action; give it `.buttonStyle(.plain)`** → docs/verify.md · prd §693
- **Day-divider audit (scripts/day-divider-audit.py) — the day header wears `DS.headInk` (white words, prd §1252); a group named by something other than time passes `dated: false` and keeps the primary ramp** → docs/verify.md · prd §740
- **A mark PACKS, a word TILES (prd §917): the source maps are circle packs (`Design/DSCirclePack.swift`, `circle-pack-selftest.sh`); the Wallet's and the devnets' holdings are a true-area treemap (`Design/HoldingsTreemap.swift`, §939, §949); words keep `UnitTreemap`** → docs/hooks/design.md · prd §917 · §939 · §949
- **Design-template audit (scripts/ds-template-audit.py) — reach for `DSSpinner`, `dsReadSheet`, `DSPushRow`/`DSChevron`/`DSMoreLink`, `DSToggleRow`, `DSEmptyState`, `DSCopyRow` and `Chip` before drawing one by hand** → prd §715
- **Secret-scan self-test (scripts/secret-scan-selftest.py)** → docs/verify.md · prd §277
- **On-device self-test (scripts/ondevice-selftest.sh)** → docs/verify.md · prd §282
- **CI, at last (.github/workflows/static-checks.yml)** → docs/verify.md
- **The logic self-tests could never pass on a hosted runner, three causes deep (2026-09-16)** → docs/verify.md
- **verify.sh's audit list is provably complete now** → docs/verify.md
- **Live-integrations heartbeat (scripts/live-integrations.sh)** → docs/verify.md
- **Demo census — every other surface, one launch (Shell/DemoCensus.swift + verify.sh "Demo census"; `DEMO_SHOTS=1` for room screenshots)** → docs/verify.md · prd §617
- **Row-window self-test (scripts/row-window-selftest.sh)** → docs/verify.md · prd §657
- **Every account page is a `List` inside a draggable sheet, and its roster is bounded through `RowWindow` (`row-window-selftest.sh`, `row-cost-audit.py`)** → docs/hooks/system.md · prd §710
- **RULE: a feature deleted from the surface is deleted from the model**, or it is §83's dead control one layer down where no screen sweep sees it (the ranked board and `roomScoped`) → docs/hooks/system.md · prd §723
- **RULE: name every column a `propertiesToFetch` read touches** (the RSS page's sync) → docs/hooks/system.md · prd §722
- **Feed-walk self-test (scripts/feed-walk-selftest.sh) — next/previous follows the list you opened from; `FeedSheetRoute.thing` carries a `WalkScope` value, never a `[Thing]`** → docs/verify.md · prd §645
- **Duolingo self-test (scripts/duolingo-selftest.sh) — a JWT payload read as plain base64 is nil for every token carrying a `-`** → docs/hooks/bridges.md · prd §776
- **Mail-location self-test (scripts/mail-location-selftest.sh) — the message door: a `Message-ID` fence, and an unencoded `/` that turns Gmail's one search into a PATH** → docs/hooks/bridges.md · prd §735
- **Readable-body self-test (scripts/readable-body-selftest.sh) — the page extractor: one 200-paragraph / 8,000-character bound across app and appex, and which hosts a scrape is fair on** → docs/verify.md · prd §645
- **Reading-draw self-test (scripts/reading-draw-selftest.sh) — the sheet's `.link` arm: *has a body* draws, *could get one* fetches; an article draws the art, the words, then the door** → docs/verify.md · prd §645 · §709
- **Health-riders self-test (scripts/health-riders-selftest.sh) — the Strava/Garmin seats and the activity dedupe** → docs/verify.md
- **MetricKit self-test (scripts/metrics-selftest.sh) — the one check for logic no machine here can exercise, because no machine here can make a payload** → docs/verify.md · prd §622

- **live-integrations.sh covers YouTube and RUNS NIGHTLY (nightly-live.sh)** → docs/verify.md · prd §312 · §654
- **Hero-tint audit (scripts/hero-tint-audit.py)** → docs/verify.md · prd §563
- **Design-motion audit (scripts/design-motion-audit.py)** → docs/verify.md · prd §299
- **Design-ramp audit (scripts/design-ramp-audit.py; check 5 added 2026-09-06 — every `widget*` rung must declare `macScales: false`)** → docs/verify.md · prd §631
- **App Store Connect self-test (scripts/appstoreconnect-selftest.sh)** → docs/verify.md · prd §323
- **PRD index audit (scripts/prd-index-audit.py)** → docs/verify.md
- **Setup-copy audit (scripts/setup-copy-audit.py)** → docs/verify.md · prd §315
- **Figure self-test (scripts/agent-panel-selftest.sh) — the answer dial's floor and the one money formatter; the chip peek and its per-room figures are deleted (prd §836)** → docs/verify.md · prd §334 · §836
- **Room-head self-test (scripts/room-heads-selftest.sh)** → docs/verify.md · prd §298
- **The social rooms became ONE room (Model/SocialRoom.swift + SocialRoomSource.swift, scripts/social-room-selftest.sh, 2026-08-26)** → docs/hooks/social.md · prd §489
- **The Nostr seat is removed (prd §1109): Social's one live network is Bluesky since Farcaster went too (§1110); `SourceRename.sweepRetiredSeats` drops its rows and `nostr.` defaults; `NostrRelay` is deleted with the Lightning seat (2026-11-09), which the same sweep drops** → prd §1109
- **Retriever self-test (scripts/retriever-selftest.sh)** → docs/verify.md · prd §318
- **One row per object in Work and Reading (`Model/ObjectFold.swift`, `object-fold-selftest.sh`): Work folds only on a per-service object URL, never a dashboard; the keys read `content` off the main actor; the sheet lists what folded. Social's faces are people across networks (`FollowedPeople`, `followed-people-selftest.sh`)** → prd §1079
- **Work's Coming up leads with "Needs you" (`Model/WorkAsk.swift`, `work-ask-selftest.sh`): asks and breakages by stable signal, never the to-do mark, a week at most; `WorkStage.Row(thing)` is the one row builder** → prd §1080
- **The Wallet's Subscriptions tile replaced Cards (prd §1105): a subscription is a merchant-named charge recurring ≥25 days at ONE price (`Subscriptions.believes`), plus Rocket Money's bills and hand-added ones (`SubscriptionStore`), merged by name; it reads its own fetch (`SubscriptionsReading`); Coming up and Subscriptions share `WalletCalendar` (five weeks, a face takes its day); a repeating bill is on one tile only; Follow is Watch (`subscriptions-selftest.sh`)** → prd §1105
- **Fees is Spending's third row (prd §1476): Zerion's fee on the sent leg as a rowless `.fee` fact, one per transaction, by network, apart from the total; "Fees · from <day>" while a window holds an unstamped send (`spending-selftest.sh`)** → prd §1476
- **Swap to another network is Across's: the phone writes the deposit, ETH via its handler, one Activity row (`WalletAcross`, `across-swap-selftest.sh`, `-acrossSample`)** → docs/hooks/wallet.md · prd §1555
- **Swap asks Uniswap v4 on all three networks: standard keys for every pair, measured keys for their own (`scripts/uniswap-v4-pools.py`; `--check` nightly in `live-integrations.sh`, `--self-test` in verify); a swap moving the price ≥1% says "Moves the price N%" in the foot (`-swapImpactSample 0.064` on the demo)** → prd §1678 · §1680 · §1682
- **Wallet (prd §1480, supersedes §1107/§1232/§1468's tiles): Home · Holdings · Activity · Spending, drawn in that order, not A–Z (`keepsOrder`, §1686); Home is the balance and six doors (Your account, Following, Needs you, Permissions, Risks, Markets), every list behind a door, Security, Cards and the category index dissolved; `-openSection home|activity|holdings|spending`** → prd §1480
- **Holdings is Public · Private, lines network · fact · place (`walletPlaceRow`, `-moveToAztec YES`)** → prd §1718
- **Your private balance is one place, told apart by network; no Private switch (`MoveAztecReceive`)** → prd §1719
- **Railgun, every build: your account sends only to you, a broadcaster to anyone else (`railgun-selftest.sh`, `-moveRailgun in|back|send`); Move says dollars and one cost, the wallet syncs on the Wallet's open (`-railgunDemoUnder YES`: under $10)** → prd §1721 · §1723 · §1728
- **Wallet accounts: Overview leads with Accounts and its count, the list under it, its + and the Feed's one menu (Follow an account, Connect an app)** → prd §1410
- **Subscriptions get a place (prd §1111): Apps is a You-row door again (one A–Z list, `Added · N` beside the search, no Casberi row) and Settings is Casberi's alone (`.casberi`); the Wallet's Coming up is Subscriptions; Day's Subscriptions tile lists mailing lists by `List-Id`/`List-Unsubscribe` (`MailSubscriptions`, rowless `.list`/`.unsubscribe` facts, new mail only, no open counts, `mail-subscriptions-selftest.sh`)** → prd §1111
- **The two Subscriptions tiles are one tile with two measures (prd §1117): the verb is Track, never Add (`SubscriptionWords.track`); the category map is `SubscriptionCategories.read(measured:)`; Day's tray offers headerless senders (`MailSubscriptions.candidates`)** → prd §1117
- **Track a subscription is one tap (prd §1161): the Wallet's tray offers what a card charged twice at one price (`Subscriptions.suggestions`, never three: those are the tile's), a typed name finds a catalogue app, a pick asks only the price and Month/Year, the rest under More (`subscriptions-selftest.sh`)** → prd §1161
- **Track without a card (prd §1164): the tray opens on Your apps then Popular (`SubscriptionPlans`, 28 services, no prices), stays open with rows ticked, Free is a price (`amount >= 0`, drawn "Free"); an app in `SubscriptionPlans.apps` offers Track on its page and once after its first connect (`shouldAsk`); Settings › Subscriptions leads with the verb; service marks are App Store artwork, "+" spelled "plus"** → prd §1164
- **Library has no box (prd §1612, retiring §1166's counts, §1314, §1317): its title and the folders; Contacts is Social's, and a tap on Contacts or Calendar opens its page (`ContactsPage`, `CalendarsPage`), yours or not; Search's person and calendar hits land there (`SettingsLanding`); the Mac pane is empty at rest** → prd §1612
- **Markets is DELETED (prd §1529, user: "i do want to cut it"): the Wallet's tile, the seat (`tokens`), the watchlist, company index, price alerts, market search, gas head, the Watchlist widget and the pinned price; its rows and `markets.`/`tokens.watch.` defaults go through `SourceRename.sweepRetiredSeats` (`.v7`). The app-to-company map (`CompanyPacks`) stays for Subscriptions; `TokenWatch` stays for GitHub/ENS/PostHog** → prd §1529
- **An empty Feed draws no preview (prd §1426, §1428): the start box, or a quiet day's date alone; every room's All tile is `square.stack`, the inbox tray is Today's alone (`ScopeTileGlyph.feed`)** → prd §1169 · §1426
- **Billers are addresses (prd §1106): a card series a month apart or longer is `biller:<merchant>` in Addresses (`Billers.compose`, `BillersSource.category(ofMerchant:)`); stopped means stopped (`Subscriptions.hasStopped`); the page never draws money (`billers-selftest.sh`)** → prd §1106 · §1106a · §1106b
- **Ranking sweep (-rankSweep "q1|q2|…")** (`-rankSweep` `-semanticFloor` `-expandDistance`) → docs/verify.md · prd §318
- **Perf pass (scripts/perf.sh)** (`-Onone`) → docs/verify.md · prd §257
- **Mac verify (scripts/verify-mac.sh)** → docs/verify.md
- **The Mac verify's cleanup is BOUNDED — a fix, not a precaution** → docs/verify.md
- **iCloud sync on the Mac, and the four things no check could see** → docs/verify.md · prd §607
- **Mac nightly (scripts/nightly-mac.sh), a step of the nightly audit task** → docs/verify.md

- Test device: **iPhone 17 Pro** sim, BY UDID — `scripts/sim-device.py`, never `name=` → docs/verify.md
- FoundationModels (on-device LLM) is iOS 26-only at **runtime** — `#if canImport` is not enough, use `if #available(iOS 26.0, *)`. `@Generable` schema types MUST be file-scope (nesting one in a private enum emits broken keypaths → heap corruption crashing on unrelated threads).
- **There IS a test target, `CasberiTests`, and `verify.sh` runs it.** It is the pass's only door to `@testable import`: every `swiftc` harness in `scripts/` compiles Foundation-only files against stubs, so anything needing a real `ModelContext` belongs in this target → docs/verify.md
- **Schema versioning (RULE):** `Casberi/Shared/ThingSchemaVersioning.swift`. An additive `Thing` change (a new optional property or attribute) needs nothing. A breaking change (rename, type change, removed property) needs a new `ThingSchemaVN` and a `.lightweight` stage; CloudKit supports lightweight migration only, so anything else is a new field plus a backfill. `SharedStore.containerWithFallback()` is a safety net, not a substitute.
- **CloudKit Production is a SEPARATE ship (RULE) — see docs/cloudkit-deploy.md.** Development auto-creates new fields; Production never does, and TestFlight/App Store builds mirror to Production. An undeployed field fails silently, because only non-nil attributes export. A new `Thing` property isn't shipped until `xcrun cktool import-schema` updates Development and the CloudKit Console promotes it.

## Simulator gotchas

- Typing via computer-use `type` triggers the macOS accent-picker. Instead: `printf "text" | xcrun simctl pbcopy booted`, then cmd+a, Delete, cmd+v.
- Sim switches don't respond to computer-use clicks — drag across the knob.
- Dynamic Type: `xcrun simctl ui booted content_size` (underscore).
- Launch args do NOT trigger `onOpenURL` — use the `-deeplink` hook below, or `xcrun simctl openurl booted casberi://...`.
- Computer-use approval is blocked in scheduled/non-interactive runs — drive the app via launch-arg hooks + `simctl` there.
- Installing for probes: pick the NEWEST DerivedData (`ls -dt`, never alphabetical `ls -d`). → docs/gotchas.md
- **`booted` is ambiguous with two simulators up.** A second session's device can take your `simctl … booted` calls and simulator taps, and it reads as a stale build. Pin the udid on every call (`xcrun simctl list devices booted`) → docs/gotchas.md
- **Verify the INSTALLED binary, not just the newest one.** `ls -dt` globs every `Casberi-*` DerivedData, so a concurrent session can serve you their app without your hooks. → docs/gotchas.md
- On a fresh sim install the demo seeds re-ask Photos/Calendar/Health permission at launch, and the queued sheets block everything (probes still run, but the UI is unusable and Health's ask stalls its probe). → docs/gotchas.md

## Dev keys (real secrets for keyed probes)

- Real test keys for keyed probes (`-byokKey`, `-tokenBridge`, …) live in the macOS login Keychain under service `casberi-dev.<name>`, managed by `scripts/dev-keys.sh` (`set` prompts silently or reads stdin — the user stores once; `get`/`list`/`delete`). **RULE (user, 2026-07-16): fetch a key ONLY inline via command substitution** — e.g. `xcrun simctl launch booted com.casberi.app -byokKey "venice:$(scripts/dev-keys.sh get venice)"` — never `get` into echo/cat/a variable you print, so values never enter assistant context or session transcripts. `scripts/dev-keys.sh list` shows what's available (names only). This replaces asking the user to paste keys per session; if a needed key isn't stored, ask them to run `dev-keys.sh set <name>` once.

## DEBUG launch-arg hooks

@../docs/hooks/index.md

## SwiftUI/UIKit gotchas already paid for

- **A quick action is registered on the app delegate and DELIVERED to the scene delegate** (none ships since 2026-10-01; the lesson stands for the next one). → docs/gotchas.md · prd §377
- A background layer BEHIND a NavigationStack never shows through (opaque UIKit backing). Page backgrounds paint INSIDE each screen: `.dsPageBackground()` on the scroll container; List also needs `.scrollContentBackground(.hidden)`.
- **A feed row never carries a presentation of its own — one screen, one `.sheet`.** → docs/gotchas.md
- **Decorative motion during a refresh must be CoreAnimation, not SwiftUI** (`Design/TileRain.swift`): ingests are `@MainActor`, so SwiftUI motion stutters exactly when it runs. One gesture deals one shower → docs/gotchas.md
- `UIGraphicsImageRenderer` defaults to device scale (3×) — pin `format.scale = 1` for downscale renders.
- A bare `Image().resizable().scaledToFill()` in a ZStack expands the ZStack to image size — pin in GeometryReader + `.clipped()`.
- A child `.gesture(DragGesture)` beats ScrollView vertical scroll entirely on device — use native `swipeActions`, never custom swipe DragGestures in scroll content.
- Silent `try?` on EventKit (and similar) writes swallows denials — surface outcomes via `ShellChrome.flash()`.
- **A SwiftData `#Predicate` using `.contains` on the `tags` array compiles and crashes at runtime.** Filter tag membership in Swift after the fetch; plain string-equality predicates are fine → docs/gotchas.md
- **Never key a `ForEach` on a persistent `@Model` property from a DERIVED array — the perpetual "crashes on different screens after an update/first sync" class.** → docs/liveness.md · enforced by scripts/swiftdata-liveness-audit.py
- **`HomeRoute` is ONE ordered array bound to `NavigationStack(path:)` and resolved by one `navigationDestination(for: HomeRoute.Node.self)`.** → docs/gotchas.md
- **The first frame walks a deep SwiftUI tree and has overflowed the main stack three times.** → docs/gotchas.md

- **A value-copy crash in a `some View` builder after a view's type changed is a stale Debug build until a clean one says otherwise** → docs/gotchas.md
- **Any `async` function handed the main `ModelContext` is `@MainActor`.** Walking it off main is a SIGSEGV that looks like the liveness class, so read the faulting thread's queue name first → docs/gotchas.md · prd §617
- **Nothing writes root-view `@State` on a scene-phase change, and the app-switcher cover is `Shell/PrivacyCover.swift`'s own `UIWindow`.** A backgrounded render is a watchdog kill (`privacy-cover-audit.py` check D) → docs/gotchas.md · prd §614
- **A background launch still connects the scene.** `BackgroundLaunch` asks the scene's `activationState`, never `applicationState` at launch, and the shell never unmounts (`background-launch-audit.py`) → docs/gotchas.md · prd §642 · §642b
- **Bind a room's `@Query` array ONCE per body pass.** Each read is a fetch plus a per-model snapshot, so never re-read it for a yes/no, an animation or a `.task(id:)` key (`query-read-audit.py`) → docs/gotchas.md · prd §646
- **A `List` behind a draggable sheet draws a BOUNDED number of rows (`Model/RowWindow.swift`)** — a sheet drag lays out its host on every offset → docs/gotchas.md · prd §657
- **Nothing inside a lock the main thread can contend may call out to observers.** A `UserDefaults` write posts its notification synchronously into SwiftUI's update lock, so persist through `Model/DefaultsWrite.swift` (`defaults-lock-audit.py`) → docs/gotchas.md · prd §721
- **The Safe room, six passes deep (2026-09-07) — the sign block READS the batch, the head NAMES who it waits on, "ready to execute" respects the queue, the guard is stated, Gnosis becomes signable** → docs/hooks/wallet.md · prd §652
- **The Safe sign block reads a call its reader cannot name in its protocol's own ERC-7730 words (`Model/ClearSign.swift`, `.described`), from the Ethereum Foundation's registry BUNDLED as `Resources/ClearSignRegistry.json`** → docs/hooks/wallet.md · prd §834
- **Safe's keyless quota is ONE shared pool, it is empty, and a REAL KEY IS SERVED AS ANONYMOUS (prd §789 · §789a, measured twice)** → docs/hooks/wallet.md · prd §789 · §789a · §789b
- **Launch, swipe, dock: work sat INSIDE the frames (2026-09-08) — strip walk off-main, room swap after the flight, no state per touch** → prd §651
- **A control that persists across a room change mounts on the shell (`MainSurface.roomControls`), never inside the `.id()` subtree it commands** → docs/gotchas.md · prd §357
- **`.fontWeight()` after `.dsText()` does override the weight — measured, not assumed** → docs/gotchas.md

- **Every `NLEmbedding` compute call goes through `EmbeddingIndex.serialized { }` — one serial queue for every model, never an `NSLock`** (`ondevice-selftest.sh`, build 281) → docs/gotchas.md · prd §282

- **Two surfaces on one card reading DIFFERENT STORES is a contradiction no render can show (prd §837).** → docs/hooks/devnets.md · prd §837 · §606 · §610 · §83
- **A `private` nested type reached from another file only through a signature crashes swift-frontend.** Open every nested type a moved signature mentions → docs/gotchas.md · prd §718
- **A container that has not been sized proposes a PLACEHOLDER, not zero, and a `List` cell born there keeps it (the ~0.3s narrow feed at launch).** → docs/gotchas.md · prd §805

## Design law (read docs/build-brief.md §8 before UI work)

- Trays are NEVER hand-rolled — use `DSTray(title:height:)` (`Design/DSTray.swift`).
- Liquid Glass on the floating layer only (composer/FAB/toasts) — never on content. The tab bar (Feed · Wallet · Apps, Move the circle, prd §1715 amending §1422's five, §1741; the Mac's rail, §1402) retired §100's "no tab bar" → docs/hooks/design.md
- No letter-spacing, no ALL-CAPS eyebrows — headers are words in sentence case ("Getting started", never "G E T T I N G  S T A R T E D" or "GETTING STARTED"). `.kerning()` is banned; the type ramp carries hierarchy by size/weight alone (ruling 2026-07-08).
- **Every text rung is named for the size it draws, and a glyph takes a `DSGlyph` rung, never a number (prd §762).**
- **One section rung (prd §1496): every section name and Wallet door is `heading24` with its glyph in the head column; a door has no line, its state is the figure's ink or one amber word; Your account is Keys and Spending in one-word rows; the second key is the Co-signer; `heading28` is the lede's alone** → prd §1496 → docs/hooks/design.md · prd §762
- **Every row in every room is one anatomy (prd §764, amended by §902)** Weight carries a fact (the next event, a state word), never a row's title. → docs/hooks/design.md · prd §764
- No hairlines — zero exceptions; nothing draws a line. Widget/tile radius = `DS.Radius.widget`. **The catalog is rows (what you could add) and the sources tray is tiles (what you have); keep that split** → docs/hooks/design.md · prd §518
- **White words, pink glyphs (prd §1252): the day divider takes `DS.headInk`; `DS.brandInk` is a glyph's.** → docs/hooks/design.md · prd §1252 · §740
- **The elevated card has ONE caller left, and it is a control (prd §759).** `dsWidgetSurface` is off every block in the app. → docs/hooks/design.md · prd §759
- **No plates under ANY spelling (prd §782, user: "these plates").** `dsInkFill` is the floating layer's only. → docs/hooks/design.md · prd §782
- **A room head draws NO PLATE (prd §758, supersedes §745's "one surface" and §757's "the head keeps its card").** `dsRoomHeadCard()` is `dsRoomHeadBlock()` and applies no `dsWidgetSurface`. → docs/hooks/design.md · prd §758
- **The wallet family's rows stand on NOTHING (prd §757).** → docs/hooks/design.md · prd §757
- **Wallet and Logos take every room's anatomy: box · tiles · account menu · list (prd §1039, amends §750); the Wallet's tiles are §1480's Home · Activity · Holdings · Spending, doors on Home.** The Overview rows and the Actions block are deleted; verbs are rows (§1107, §1108) → prd §1480 · §1039 · §750
- **The room's faces ride the dock folder's capsule, after the venues, and draw no words (prd §753).** → docs/hooks/design.md · prd §753
- **That capsule always LEADS with the room you are standing in (prd §754).** Shut, the folder draws one seat. → docs/hooks/design.md · prd §754
- **Every room's lead is `DSRoomChassis.leadHeight`, the wallet head's card, and nothing in it is air it could honestly fill (prd §760).** → docs/hooks/design.md · prd §760
- **Every room's lead is one well (prd §766): a statement and a body, sitting at the top of the box; the count foot (`LeadFooter`, "N things since <month>") is deleted from view and model (§914).** → docs/hooks/design.md · prd §766 · §914
- **A lead's BODY is a ladder (§772), EVERY cover holds the box (§904), the ladder GROWS (§905), and each CATEGORY has a face (§907, §908).** → docs/hooks/design.md · prd §772 · §904 · §905 · §907 · §908
- **The rooms tray is DELETED (prd §1714), and Search with it (prd §1715): `Shell/LibrarySearch.swift` is Apps' field — recent searches when focused, grouped results when typed; the rail's face goes to the Feed; rooms are Apps' and the Feed's sections** → prd §1714 · §1715 · §1418 · §1741
- **Notes is a room in You (prd §969; Pin deleted §1175): tiles All · Folders · Voice · New, one plain list, `Pinboard.room` is `"Your notes"` never the drawn word (§975); a note of yours deletes from its long press, no swipe (the pager owns horizontal drags)** → docs/hooks/system.md · prd §969 · §978 · §979 · §980 · §981 · §995
- **The wallet-family visualization pass (prd §920–§929, reviewed §931, §936)** → docs/hooks/design.md · prd §920 · §931 · §936 · §954
- **Every room opens on the box (prd §911); the kind tiles §815–§911 drew are deleted with the rooms that wore them (§1059). Instagram, X and TikTok get NO tiles** → docs/hooks/design.md · prd §911 · §821 · §1059
- **One glyph, one meaning, for every tile (`tile-glyph-audit.py`, prd §831, §1059): a `DSTileScope` case wears the constant of its own NAME or a declared alias, no conformance spells a literal, and no `ScopeTileGlyph` constant outlives the tile that wore it** → docs/verify.md · prd §815 · §831 · §1059
- **Every lead stands in the rows' column (`DSRoomChassis.leadInset`) and ends at `leadGap`** → docs/hooks/design.md · prd §763 · §906
- **The X room leads with its NEWEST NOTIFICATION, never a year grid (prd §817).** `FeedHeatmap` has no `X` entry. → docs/hooks/design.md · prd §817
- **One explaining sentence per screen, at most, through `DSFootnote` (prd §748).** A line stays only if it says what the controls cannot; honesty, money, signing, privacy and fix-it lines are kept on purpose. `footnote-audit.py` counts per file, with reasoned allowances → prd §748
- **A shortened address is its tail, `...e07a`, through `AddressTail.short` only (prd §1553, `address-tail-audit.py`)**
- **Two pills, no more (prd §746): `Chip` is a choice, `DSStamp` is a fact, and a verb is a row (`DSDoorRow`, `DSCopyRow`, `RowVerb`).** `ds-template-audit.py` check C fails a capsule drawn behind content outside `Design/` → prd §746
- **Every room head composes `DSRoomChassis.Head` (prd §745): a lead, notes, blocks, footnotes, one surface and one door.** → docs/hooks/design.md · prd §745
- **Every chart head draws into `DSRoomChassis.figureHeight` (56pt) and caps at `headRowCap` (8, raised from 3 by §760: `LeadFit` draws as many rows as the box holds); a head with no chart is deleted and the room leads with its newest thing (prd §749, §751).** The models spell the cap literally, and `room-heads-selftest.sh` holds them to it → prd §751 · §760
- **Every feed row composes ONE anatomy, `DSFeedRow` (prd §744): a 30pt lead in a 44pt head (§1071), one line; every Wallet list row at that pitch through `walletListRow()`/`walletStackRow()`/`walletRowPitch()` (`wallet-row-audit.py`, §1482)** → docs/hooks/design.md · prd §744 · §1482
- **No controls at the top of the screen, anywhere (user, prd §752).** A picker, a scope or a back control sits in the content (under the head or figure) or in the bottom band. → docs/hooks/design.md · prd §752 · §752b
- **The wallet family has NO BAR (prd §747, supersedes §547); the account is picked from the menu under the tiles (§936), and the acts are tiles on every page (§774, §1039).** → docs/hooks/design.md · prd §747 · §774 · §1039
- **The dock's face opens APPS (was Accounts) — search, then the one catalogue; Manage is deleted, a connected row with a room is a status (no chevron) whose tap LANDS IN ITS ROOM (prd §1040, amends §1033/§1036), and a room's own sliders disc beside its name raises its account page (prd §1033; §796, §863).** → docs/hooks/design.md · prd §796 · §933 · §1033
- **SETTINGS HOLDS NO KEY (prd §871).** "Your key", `AccountDetail.key` and `AgentKeyPicker` are deleted. → docs/hooks/design.md · prd §871
- **The face's rooms tray is deleted (prd §1714, retiring §930's door); a room's sliders disc beside its name raises that room's account page (§1033). The dock's catalogue tile is deleted (§798).** → docs/hooks/design.md · prd §798 · §1033 · §1714
- **The dock's leading seat is the back door on every pushed screen, and nothing stands at the top edge (prd §767).** → docs/hooks/design.md · prd §767
- **A pushed screen leaves the back door's column clear (`DSDock.seatClearance`, `.dsSeatClearance()`, prd §829).** → docs/hooks/design.md · prd §829
- **The keyboard COVERS the dock; it never lifts it (prd §865, and §865a is the half that shipped broken).** → docs/hooks/design.md · prd §865 · §865a
- **Every empty state draws what would fill it, empty (prd §769, §771).** `DSEmptyState` is `.room(figure)`. → docs/hooks/design.md · prd §769 · §771
- **An empty scope's `words:` is ONE CLAUSE, and a string with no reader is deleted (prd §799).** → docs/hooks/design.md · prd §799
- **Feed rows are bare — no plate, no card, anatomy cards included (prd §749, supersedes §743).** A room without a visualization leads with its newest thing as `FeedLedeCard`, which has no backing: no deck, pour or shadow → prd §749
- **A post yields its card to the cover, and the cover draws it AS a post (prd §756, supersedes §732's option A).** → docs/hooks/design.md · prd §756
- **A term that SUPPRESSES a head is not a head (prd §755).** `heroShown` means a head card is drawn. → docs/hooks/design.md · prd §755
- **Every pour is ink — `DS.pourInk`, one token.** Colour that says what is happening stays; colour that says where it came from goes → docs/hooks/design.md · prd §524
- **Seven categories** (`BridgeCatalog`, mirrored on the website); Day (a Feed section) and Notes are built from apps, not categories → prd §1235 · §1239
- Typed text in the composer NEVER saves — things enter only via capture paths (paste chip, mic, share, screenshots, drop, bridges). Saving is an outcome the toast reports, never a verb.
- Swipe verbs are reads only (writes live in the sheet, with consent). Feed chips only when they differentiate.
- **A row that names a place is a BUTTON, or it is deleted — the “From” row is gone from every sheet (prd §736).** → docs/hooks/design.md · prd §736
- **Every disc on the dial PRESSES (`PressSpring`), a glyph that changes MORPHS (`dsSymbolSwap(icon)` inside `disc`), and a copy marks its own disc for 1.2s (prd §867).** → docs/hooks/design.md · prd §867 · §693
- **Every `Button` answers the hand (prd §965): a row or a word wears `RowPress`, a disc, chip, face, tile or slab wears `PressSpring`, never `.plain` — `ds-template-audit.py` check D fails a plain Button, the dock, the face door, the tray scrim and the keypad excepted by ratchet** → docs/hooks/design.md · prd §965
- **A room's tiles read A–Z, All/Home first (known by glyph) and the verbs last, A–Z among themselves (§1039), enforced in `DSScopeTiles.alphabetical` (prd §995, user: "that's a rule for any room"); the strip keeps the dock's order. The music shelf's orders are deleted with the music rooms (Media, prd §1050d)** → prd §995
- **Becoming the pick is a crossfade on `DS.Motion.standard`, inside the template (prd §966): `DSScopeTiles`, `DSRangeChips`, `FaceScopeRail` and `Chip` animate their own fill and ink, so a room whose pick handler forgets `withAnimation` still slides the tint in** → docs/hooks/design.md · prd §966
- **Honesty rule: no dead controls, no fake status (prd §83).** A hand-painted button swaps its background when disabled; never quote a price off a stale trade; a change that rounds to zero has no sign or colour. "End-to-end encrypted" requires Advanced Data Protection — don't overclaim → docs/hooks/design.md
- **A status WORD takes the ink (`DS.attentionInk`/`confirmInk`/`destructiveInk`), a glyph or fill keeps the hue (§1004, `status-ink-audit.py`); the PICK is `DS.pickInk` (pink: state, verb), a door grey, `DS.tint` charts and links (`ds-template-audit.py` E)** → §1385
- **The Mac takes its own point scale — `DSTextStyle.macScale = 0.76` (§1406, was 0.88), one lever.** `DS.Face`/`DS.Mark` and the `widget*` rungs opt out (`design-ramp-audit.py` check 5) → docs/hooks/design.md · prd §631
- **A walked row on the Mac can be taken with ⌘C, Space and drag-out, through one resolver (`Shell/MacRowHandoff.swift`)** → docs/hooks/design.md · prd §631
- Product rulings live in docs/prd.md — check it before re-litigating a design decision; record new rulings there.
- **Current law is `docs/law.md`** — the live rulings by area, each citing the § in force, over a generated index of every live ruling and its amendments; read it before the ledger. `docs/prd.md` stays the record: a new ruling goes there first, then run `python3 scripts/law-digest.py` (`--check` fails when law.md is stale or cites a dead ruling).

## Mac (Catalyst)

- **The pane is the room's second column (prd §1742): Wallet activity under the box (`walletPaneActivity`), a 620pt measure (`PadLayout.paneMeasure`), an 11pt floor (`macFloor`), the start box in the list on a first run; `-firstRunPreview YES`**
- **Every shell ruling names its Mac half before it ships (RULE, prd §1402).** The rail is the tab bar — Feed · Wallet · Apps (`.library` in code, §1741), Move wearing your face once you pick one (`Shell/PlaceRail.swift`, `MoveMark`); ⌘1–⌘4 open them, ⌘F focuses Apps' field (§1715); never a sidebar (§875).

## Website (casberi.app)

- **RULE: every app added to the catalog also lands on the website in the same session** — a hero marquee tile, a `#catalog` shelf cell and an `.ai-<name>` background — then bump the `?v=` cache-busters and commit: a push to main that touches `website/` publishes it to casberi.app through GitHub Pages (`.github/workflows/pages.yml`, since 2026-11-10; cPanel and the deploy zip are retired) → docs/website.md
- **RULE: `BridgeCatalog.offers` is the single source of truth for the app catalog, the website catalog and both marquees**, enforced by `scripts/catalog-sync.sh`; a marquee name must equal its offer name exactly → docs/website.md
- **RULE: a new bridge is not done until its API hosts are in `Model/NetworkReach.swift`** (prd §205). `network-reach-audit.sh` is a ship gate. A host built at runtime names a declared family; a host the person types names its service through `NetworkLedger.record(host:as:)`. Its `.whenConnected(bridge:)` is the CATALOG NAME, never the seat id, and a keyless rider says `credentialed: false` (prd §1163, `bridge-health-selftest.sh`) → docs/verify.md
- **RULE: website icons are inlined as base64 data URIs — never hot-link a remote image** → docs/website.md

## Working mode

Goal-by-goal with user review checkpoints. Build + verify on simulator before presenting. The user rules on design; run `/code-review` on the diff before their checkpoint so mechanical findings don't consume it.
