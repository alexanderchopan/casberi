# Casberi

Native iOS app — a personal corpus of "things" (links, screenshots, events, chats, voice notes, agent outputs). Solo project, live on the App Store (iOS and Mac); betas ship via TestFlight. Growth plan: `docs/growth.md`.

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
- Backed by a **PUBLIC** GitHub remote `origin` → https://github.com/alexanderchopan/casberi. **Every commit is world-readable the moment it lands**, so nothing secret may ever be committed: real keys live in the login Keychain via `scripts/dev-keys.sh`, and the only in-tree credentials are public identifiers (the Reown/WalletConnect project id, a Dropbox app key). Actions minutes are free for public repos. A `post-commit` hook auto-pushes to `origin` in the background (`.git/last-autopush.log`). Solo, straight to `main`, no branches or PRs. Committing is NOT a release — releasing is `scripts/testflight.sh`.

## Layout

- `Casberi/Casberi.xcodeproj` — the Xcode project. Targets: **Casberi** (app), **ShareExtension** (appex), **CasberiWidgets** (widget bundle). Bundle id `com.casberi.app`; app group `group.com.casberi.app`.
- `Casberi/Casberi/` — app sources (`Design/`, `GenUI/`, `Model/`, `Screens/`, `Shell/`).
- `Casberi/Shared/` — sources compiled into both app and extension targets.
- `docs/` — **build-brief.md §8 (design system) is law**; prd.md carries product rulings; name-ledger.md.
- `prototype/` — visual spec. `design/app-icon/` — icon SVG sources.
- The pbxproj is **hand-authored** (objectVersion 77, file-system-synchronized groups). New source files in synced folders are picked up automatically; Info.plist keys and target settings are edited directly in the pbxproj.

## Xcode MCP and Apple docs (RULE)

- **Xcode's MCP server is registered at user scope** (`claude mcp add --scope user --transport stdio xcode -- xcrun mcpbridge`, Xcode 27). It only connects while Xcode is running with the project open and *Xcode > Settings > Intelligence > "Allow external agents to use Xcode tools"* is on. Prefer its build/test/diagnostic tools over a raw `xcodebuild` when the session has it.
- **Read Apple developer docs as Markdown, never the HTML page** (it is a JS app and fetches as an empty title). For `/documentation` pages append `.md` (`https://developer.apple.com/documentation/swiftui/view.md`); for `/design` and `/tutorials` pages also insert `/tutorials/data` before the path (`https://developer.apple.com/tutorials/data/design/human-interface-guidelines/buttons.md`); the few pages with no Markdown version take `.json` in place of `.md`.

## Building (critical)

From the canonical `~/Developer/casberi` copy, a plain build codesigns cleanly — no workaround needed:

```sh
xcodebuild -project Casberi/Casberi.xcodeproj -scheme Casberi \
  -destination "id=$(scripts/sim-device.py)" build
```

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
  `SKIP_LOGIC=1`, `VERIFY_NO_CACHE=1`.
- **Read `$OUT/step-times.tsv` (slowest ten, printed by the EXIT trap) before aiming any
  work at this suite.** Three separate passes have found that "verifying is slow" was not
  the standard cost of good tests.

**The checks themselves** — one line each; what each catches, why it exists and what it
deliberately does not check are in `docs/verify.md`.

- **Mac parity gate (verify.sh step 1b)** → docs/verify.md
- **verify.sh runs verify-mac.sh IN PARALLEL and gates on it (user rule, 2026-08-21 — the split was discovered, not chosen)** → docs/verify.md
- **Mac parity audit (scripts/mac-parity-audit.py)** → docs/verify.md
- **Account-detail sheet gate (verify-mac.sh step 2d, 2026-09-21) — a Catalyst sheet does NOT inherit the presenter's environment, and the shipped Mac build died on every Accounts → Settings row that raises one** → docs/verify.md · prd §872
- **The two verify scripts each ran checks the other didn't, and both are now provably complete** → docs/verify.md
- **The pure-logic harnesses run at once, and an unchanged one is not re-run (PERF, 2026-08-19). Full green passes: 32.8min → 15.2min → 3.6min** → docs/verify.md
- **The pass ran every harness TWICE for eleven days (PERF, 2026-09-01). Measured 08-31: 38–57min green, 154 and 161min for two overlapping sessions, against the 3.6min above** → docs/verify.md

- **The pass was mostly IDLE CORES — time every step before optimising it (PERF)** → docs/verify.md · prd §612

- `-refusedForget YES` — clear every learned Alchemy chain refusal and drop the holdings window, so the next read asks every selected chain again (prd §827b). A refusal stands a WEEK: right in the field, a trap at a desk → prd §827b
- **Every `seeded` key is `.v2`, because the `.v1` flags are POISONED (prd §827a).** The old loop recorded the flag BEFORE the guard that adds the chain, and the add could not persist from `init`. → docs/hooks/wallet.md · prd §827a
- **`WalletChainStore.effectiveIDs` is the ONE rule for which chains are on, and the static `activeNetworkIDs()` (which EVERY ingest reads) resolves through it (prd §827).** → docs/hooks/wallet.md · prd §827 · §83
- **Tempo (Stripe's L1, 4217) is ON by default and read through Zerion ONLY (`onAlchemy: false`, prd §810).** No native coin: never read a native balance there. `network-reach-audit.sh` honours `onAlchemy: false`, so such a row discloses no Alchemy host → prd §810 · §828
- **Alchemy serves Robinhood with NO PRICES (measured: 25 rows, 0 priced, the native ETH included), so Robinhood reads through Zerion (`robinhood`, 4663) since prd §828.** → docs/hooks/wallet.md · prd §828
- **Robinhood is read on Alchemy BESIDE Zerion (`WalletIngest.zerionOmits`), and a DEX-only token is priced by `DexPrices` (GeckoTerminal) only off a pool ≥$10K holding ≤25% of it; a native coin takes the cent floor on either arm (prd §968)** → prd §968
- **Zerion is ONE request a second and 300 a day for EVERY install (`ratelimit-org-tier: demo`, measured 2026-09-26, prd §934)** → docs/hooks/wallet.md · prd §934
- **The wallet crown counts YOUR accounts, and Zerion answering does not end the read (prd §826).** → docs/hooks/wallet.md · prd §826
- **One Wallet (prd §1048): the money rooms merge into one room (Markets, Frames, Logos stay apart); its total adds cash (`WalletCash`: Wise + Apple Wallet assets, Kraken's six fiat pairs, the rest left out and named) and Privy's apps, never Privy alone, both on the combined page only (`wallet-total-audit.py` rule 6)** → prd §1048
- **One chain may not empty every wallet's balances, and a wallet we could not reach stands on its LAST READING, stamped (prd §825) — the room showed a Privy app wallet's stored figure and none of the person's own.** → docs/hooks/wallet.md · prd §825
- **The address book's delight pass** → docs/hooks/wallet.md · prd §441
- **Address-book shape self-test (scripts/address-book-selftest.sh)** → docs/verify.md · prd §440
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
- **The demo's mark is ONE BLUE PILL that floats over every demo screen, All included (prd §919, §946 — the All feed's `DemoLead` is deleted as the demo said twice)** → docs/verify.md · prd §864 · §919 · §946
- **The demo is one person's life (prd §1026): a topic (`ocrTopics`) in at most two rooms, no room leading three topic rows with one word, and the person's app is Quillmark, never Casberi (`CasberiTests/DemoSpreadTests`); pictures are drawn by `scripts/demo-art/render.py`, one generator per imageset** → prd §1026 · §890
- **Dead-closure audit (scripts/dead-closure-audit.py) — a control calling a closure property nothing ever supplies** → docs/verify.md · prd §669
- **Defaults-lock audit (scripts/defaults-lock-audit.py) — a lock held across a `UserDefaults` write deadlocks with every view body (build 570)** → docs/verify.md · prd §721
- **ShareLink style audit (scripts/sharelink-style-audit.py) — an unstyled share control in a `List` row becomes the row's action; give it `.buttonStyle(.plain)`** → docs/verify.md · prd §693
- **Day-divider audit (scripts/day-divider-audit.py) — the day header wears `DS.brandInk` (the mark's hue, one notch softer, prd §742); a group named by something other than time passes `dated: false` and keeps the primary ramp** → docs/verify.md · prd §740
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
- **Web-session capture (Model/WebSessionCapture.swift + Screens/WebSessionCaptureView.swift, Diagnostics, DEBUG, 2026-09-16)** → docs/verify.md · prd §777
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
- **Retriever self-test (scripts/retriever-selftest.sh)** → docs/verify.md · prd §318
- **Ranking sweep (-rankSweep "q1|q2|…")** (`-rankSweep` `-semanticFloor` `-expandDistance`) → docs/verify.md · prd §318
- **Perf pass (scripts/perf.sh)** (`-Onone`) → docs/verify.md · prd §257
- **Mac verify (scripts/verify-mac.sh)** → docs/verify.md
- **The Mac verify's cleanup is BOUNDED — a fix, not a precaution** → docs/verify.md
- **iCloud sync on the Mac, and the four things no check could see** → docs/verify.md · prd §607
- **The Mac nightly was red ELEVEN of TWELVE nights, and every one resolves green on today's tree** → docs/verify.md
- **Mac nightly (scripts/nightly-mac.sh + scripts/com.casberi.nightly-mac.plist)** → docs/verify.md

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
- Installing for probes: pick the NEWEST DerivedData (`ls -dt ~/Library/Developer/Xcode/DerivedData/Casberi-*` — plain `ls -d` is alphabetical and served a day-old binary for 30 minutes on 2026-07-14). → docs/gotchas.md
- **`booted` is ambiguous with two simulators up.** A second session's device can take your `simctl … booted` calls and simulator taps, and it reads as a stale build. Pin the udid on every call (`xcrun simctl list devices booted`) → docs/gotchas.md
- **Verify the INSTALLED binary, not just the newest one.** `ls -dt` globs every `Casberi-*` DerivedData, so a concurrent session can serve you their app without your hooks. → docs/gotchas.md
- On a fresh sim install the demo seeds re-ask Photos/Calendar/Health permission at launch, and the queued sheets block everything (probes still run, but the UI is unusable and Health's ask stalls its probe). → docs/gotchas.md

## Dev keys (real secrets for keyed probes)

- Real test keys for keyed probes (`-byokKey`, `-tokenBridge`, …) live in the macOS login Keychain under service `casberi-dev.<name>`, managed by `scripts/dev-keys.sh` (`set` prompts silently or reads stdin — the user stores once; `get`/`list`/`delete`). **RULE (user, 2026-07-16): fetch a key ONLY inline via command substitution** — e.g. `xcrun simctl launch booted com.casberi.app -byokKey "venice:$(scripts/dev-keys.sh get venice)"` — never `get` into echo/cat/a variable you print, so values never enter assistant context or session transcripts. `scripts/dev-keys.sh list` shows what's available (names only). This replaces asking the user to paste keys per session; if a needed key isn't stored, ask them to run `dev-keys.sh set <name>` once.

## DEBUG launch-arg hooks

All read via UserDefaults in `Shell/RootShell.swift` unless noted. **The flag stays here; the long entry moved to `docs/hooks/`** — open the named file for the measured quirks, the decisions with reasons, and what each probe exists to separate:

- `-deeplink <casberi://url>` — open a deep link on launch.
- `-demoCensus YES` — over a poured demo (`-demoEnter YES` first), compose every surface in one process and NSLog `demoCensus| <surface> | … | ok|empty|skipped`; a new surface is one row in `DemoCensus.registry` (`Shell/DemoCensus.swift`, prd §617).
- `-chipStats "<source:n[,…]>"|clear` — seed the source strip's tap-learning counters (`Model/ChipMemory.swift`); every mount NSLogs `chipLabels:`.
- `-openRoom "<seat name>"` — land in a source's room headlessly at mount (`RootShell.openRoomIfRequested`; NSLogs `openRoom:`). Pair with `-demoEnter YES` on a prior launch for a furnished room.
- `-walletScope <address | seat:Name>` — pick an account in the Wallet's menu at launch, an app the Wallet folded in included (`RoomAccounts`, prd §1048b; NSLogs `walletScope:`)
- `-openSection <raw>` — with `-openRoom`, land on a wallet-family tile (or the Reminders room's `today`, a mail room's `attachments`, or a Markets company pack by its category name, `Work`) at launch, no tap (DEBUG) → docs/hooks/system.md · prd §953 · §1019
- **The mail rooms carry All · Attachments · New (prd §1019, `Model/MailScope.swift`, `mail-scope-selftest.sh`)**: one scope for Gmail and iCloud Mail, Attachments reading the `Attached` fact the ingest writes under `MailScope.attachedLabel`, New composing through `SourceActions`, the compose row gone from the top of the screen (§752) → prd §1019
- `-connectReminders YES` — the real Reminders connect, seat included (relaunch to see it; `simctl privacy … grant reminders` first, `-demo.corpusAllowed NO` on a fresh install or the dev seed pours four) → prd §993
- `-openThing "<title prefix>"` — open the newest thing whose title starts with the prefix (NSLogs `openThing:`). It runs at mount, before ingest hooks land anything, so land first and relaunch.
- `-answerProbe "<query>"` — run the answer path headless, NSLog the result (`-probeDelay <s>` to wait first). Deterministic unless the Apple Intelligence seat answers (prd §833).
- `-uiAnswerProbe "<query>"` — auto-open the composer and send through the real UI path (also read in `Shell/Composer.swift`).
- `-forceBackgroundLaunch YES` — stamp this launch as a background launch so `RootShell`'s gate stays closed (NSLogs `backgroundLaunch: yes`, prd §642). The simulator cannot background-launch, so a pass proves the branch renders, never that the watchdog is beaten.
- `-fresh YES|NO` — sticky new-user mode (persists until flipped or reinstall); re-shows onboarding.
- `-accountDetail <case>` — open a settings detail sheet (`Screens/AccountScreen.swift`, `SettingsRows`' own onAppear, so pair it with `-openSettings YES`).
- `-openAddresses YES` — present the Addresses screen (`HomeRoute.Node.addresses`, its own pushed screen since prd §933; `Screens/SettingsScreen.swift` holds `AddressesScreen`, the list is `Screens/AddressesScreen.swift`; §916: a directory under the face, never a room; Contacts is `chiplessSources` since the same ruling).
- `-openAddressCard <0x…>` — raise the address card for a book entry when the Wallet page appears (`Screens/WalletScreen.swift`; pair with `-openSetup "Wallet"` and `casberi://account`; NSLogs `openAddressCard:`).
- `-openReach YES` `-seedReceipts YES` `-reachScope "<Category>"` — present What this app reaches (`HomeRoute.Node.reach`, the registry and the ledger on one screen since prd §967; its door is the Data tray's one row); `-seedReceipts` records five hosts through `NetworkLedger`, one undeclared, and `-reachScope` picks a dock category. `simctl spawn defaults write` does not reach the ledger reliably; seed through this hook → prd §967
- `-openTray YES` — raise the rooms tray at mount, no tap (`Shell/RoomsTray.swift`; NSLogs `openTray:`), prd §1008.
- `-trayQuery "<text>"` — with `-openTray YES`, type into the tray's search headlessly (NSLogs `trayQuery:`), prd §1015.
- `-openSettings YES` — present the Settings screen (`route.present(.settings)` in RootShell's onAppear, prd §933; a section of Accounts from §796 until then). `-deeplink casberi://settings` works equally.
- `-icloud.sync YES` — AppStorage override for the sync toggle copy.
- `-onboarded YES` — AppStorage override that skips first-launch onboarding (fresh installs otherwise land on it, hiding the screen you deep-linked to).
- `-pileTap "<Offer name>"` — fire an empty-feed pile tile's tap after the fall (NSLogs `pileTap:`). Stage it with `-fresh YES -onboarded YES`, terminate, then `-onboarded YES`.
- `-openSetup "<Offer name>"` — push a bridge's setup screen (needs `casberi://account` opened after launch).
- `-theme.light` — AppStorage theme override; always pass explicitly for light/dark screenshots (the sim's stored value sticks) → docs/hooks/system.md · prd §204
- `-howItWorksCTA <s>` — lift the first-launch cover after a delay (`Screens/IntroCover.swift`) → docs/hooks/system.md · prd §620
- **The dock is CONTINUOUS — the fold tracks the scroll, folders open in place, the page follows the finger, press-and-slide picks (2026-09-05)** → docs/hooks/system.md · prd §621
- **The dock is flat chips on one glass slab, and nothing in the strip claims a touch.** → docs/hooks/design.md · prd §660 · §662h
- **A category tap lands first, then springs its folder** → docs/hooks/design.md · prd §668
- **The dock's selection GLIDES and never leans (prd §667, 2026-09-10).** `SelectionTravel` pins the fill's and ring's travel to `DS.Motion.glide` (bounce 0); nothing in the strip reads the drag. An indicator that names a position takes `glide`, never a bouncy spring → prd §667
- **`.transaction { $0.animation = … }` rewrites EVERY transaction reaching a shape — guard on `t.animation != nil`** → docs/hooks/design.md · prd §673
- **`GestureGate` is the one fact about the hand (prd §666, 2026-09-09).** Any deferrable main-actor work. → docs/hooks/system.md · prd §666
- **The Apple polish pass (prd §915): a notice's sentence is its name (`SocialRoom.rowSentence`), a screen's name is `heading34` and its switcher `heading17`, a title's ONE seam is ` — ` (`TitleSeam.join/split`, `title-seam-audit.py` — a money title's dot is `titleMoney`'s, allowed by file), the media well stacks art over words, the feed's closing sentences are deleted (the fetch-ceiling door stays), and `fillFaint` is 10% in dark** → docs/hooks/design.md · prd §915
- **The All feed's Apple pass (prd §902, §1017): `DSFeedRow` draws one 60pt HEAD with the 46pt lead centred, one-line titles, no ages, no fold counts, no source name in the line, the day divider alone** → docs/hooks/design.md · prd §902
- **A fold's lead is the BARE MARK (prd §903): `DSFoldLead`'s stacked plate is deleted — it read as an error, and a source landing three a day wore it every day, so it said nothing (§902's case against "N more")** → docs/hooks/design.md · prd §903
- **The All feed's days are FELT, and the floor draws the mark (prd §866, §866a).** `FeedSeam` ticks once as a day divider passes the viewport top. → docs/hooks/design.md · prd §866 · §866a
- **The picture grid stands UNDER the day (prd §910): `daySection` tiles its own pictures under its header, three to a `List` row, in the room's shape (`PhotoCell.Shape`, a screenshot cropped from the top), caption under the picture, no pill, no scrim; `photoGridSection` is deleted** → docs/hooks/design.md · prd §910
- **A row lead turns to its dock CATEGORY's glyph and back, once — on landing while you look, or a title moving in place (`Design/LeadCycle.swift`, `lead-cycle-audit.py`, prd §901).** → docs/hooks/design.md · prd §901 · §901b
- **Feed-seam self-test (scripts/feed-seam-selftest.sh) — those guards over a counting `DSHaptic` stub, plus the drift nothing else sees: a counter bumped with no `.sensoryFeedback` mapping compiles, runs and is never felt. **A guard asserts the USE, not the declaration** → prd §866 · §866a
- **A crown's line pays for its own range chips through `DSRoomChassis.crownChart(box:chips:)`.** The class: a fix applied to a shared template reaches only what goes through it, so check what still draws that shape by hand → docs/hooks/design.md · prd §720 · §688
- **Room figures derive EVERY dimension from `DSRoomChassis.figureSlot`, padding included (prd §665; the `gearColumn` clearance went with the gear, §937).** → docs/hooks/system.md · prd §665
- **A chip tap lands in the category's room and springs its folder; a swipe walks individual rooms in dock order** → docs/hooks/design.md · prd §663
- **A category chip is a 52pt tile, glyph over word; a new category needs a row in `CategoryFold.glyphs`** → docs/hooks/design.md · prd §662
- **A room swipe: TRAVEL follows the finger, CARDNESS follows the TURN (§648), and the card is dealt on the BRAND GROUND (§898)** → docs/hooks/design.md · prd §648 · §898
- **The page is not clipped at rest and the bottom band paints no plate** (`dock-selftest.sh`) → docs/hooks/design.md · prd §677
- **The dock's folder touches the dock, a face rail sits above it, and the band's scrim ramps over a fixed 24pt** → docs/hooks/design.md · prd §649
- **The furnished demo is a MODE you enter and leave, not a dev-only seed** → docs/hooks/system.md · prd §217
- `-findProbe` — fill the composer and fire Find (prd §215, the composer's deterministic door): runs KeptAskComposers.search → docs/hooks/agent.md · prd §215
- `-openComposer` `-composerDraft` — open the composer empty (its field and foot); -composerDraft "<text>" → docs/hooks/agent.md
- `-openNote YES` — raise the note sheet at mount (prd §969, `Shell/NoteCaptureSheet.swift`; NSLogs `openNote:`); pair with `-openRoom "Your notes"` for the room (`Pinboard.room`, NOT the drawn word — "Notes" is a catalog category). Dismiss KEEPS a non-empty note under `You` → docs/hooks/system.md · prd §969
- `-noteVoice YES` — land the note sheet RECORDING (prd §971–§973; pair with `-openNote YES`; NSLogs `noteVoice:`). Dictation is Apple's keyboard mic over the focused field; the sheet's ONE wide key morphs Record (waveform) → Stop → check (keeping) or Done; Stop SETTLES the recognizer (≤1s) and keeps a `.voice` thing under `You` (audio in `Thing.audio` only); a call or a sheet closed another way keeps it; the `audio` background mode keeps a locked phone recording. The band draws `VoiceCapture.levels` in the player's bar anatomy. Held New arms (the plus morphs to the waveform) and lands here recording (`DSScopeTiles.Hold`, `DSHaptic.lift`). The sim has no mic: a pass shows the band, never a transcript or a level → docs/hooks/system.md · prd §973 · §972 · §971
- `-notePicture YES` — land the note sheet with a PICTURE attached (prd §974; pair with `-openNote YES`; NSLogs `notePicture:`). The band's photo disc opens the system picker; the picture is stored on the note in `previewImageData` at the app's one 480pt size (`ImportMedia.thumbnail(data:)`), so the row, the lede and the sheet draw it with nothing new. A picture alone keeps a note titled "Photo"; a picture and a recording never share a sheet → docs/hooks/system.md · prd §974
- `-noteDraft "<text>"` — land the note sheet with words already written, `\n` for a new line and `○ ` for a checklist item (prd §982; pair with `-openNote YES`; NSLogs `noteDraft:`), because a `simctl`-booted simulator draws no keyboard
- **The note takes a checklist you tick, a scan, a link to anything you keep, a Quick Note and a lock (prd §982).** A tick is the one write the sheet makes (`NoteChecklist.toggled`, `note-checklist-selftest.sh`); a lock SEALS the words into `audio` under a key in iCloud Keychain — the one synchronizable Keychain item, exempt in `keychain-audit.py` — so nothing downstream can show them; the Quick Note is `NoteControl`, `NewNoteIntent` and `casberi://note` → prd §982
- **Notes, toward Apple (prd §983): the room previews a note of yours (`NotePreview`), Pinned leads All, the long press holds five (Pin, Move, Lock, Share, Delete), a written note of yours is a page with Share · Lock · Edit at its foot and no dial, and writing is a page — title over words, four tools on one glass capsule over the keyboard.** Copy and Translate are the system's on selected words → prd §983
- `-voiceNoteFile <audio path>` `-voiceHealProbe YES` — keep a voice note from a file (the sim has no mic) and read it back; a `<path>.timeline.json` beside it (a `VoiceTimeline` built on a Mac) stands in for the read, because the SIMULATOR CANNOT INSTALL the iOS 26 speech model (measured). The player's length, playhead, speeds and lit words are §987 → docs/hooks/system.md · prd §987
- **Highlights (prd §1020): Keep stands in the selection menu of every reading body (`KeepableText`, a `UITextView` in the rung, through `\.keepPassage`), and a highlight is a note of yours whose `sourceRef` is `highlight:<origin id>`, its origin's title in `wikilinks`, its link in `externalLink` (`Model/Highlight.swift`).** The page says "from <the page> ›", the row's line names the page, Share is the quote card → docs/hooks/system.md · prd §1020
- **A Notes folder shares as one card (prd §1021): Share leads the folder's long press; `FolderShareCard` draws five rows under the name, the true count in the eyebrow, the list as the share's words** → prd §1021
- **A checklist item rings (prd §1022): hold it for Remind me (`NoteRemindTray`), the reminder is the app's own in a list named Casberi (`NoteReminders`, a `.reminder` fact on the note), a tick completes it; the 2026-07-25 "we don't write" ruling is amended for THIS reminder only, and the Reminders usage string says so** → prd §1022
- **A sketch is a picture (prd §1023): Attach's Sketch opens Apple's canvas and picker (`Shell/NoteSketch.swift`); pulling down keeps the drawing flattened over the page's black as the note's one picture, strokes not kept, drawing again draws over it** → prd §1023
- **A voice note's card carries the player's 32 bars and its length, and the recording rides the share as a second item (`ShareCardPart.audio`, `VoiceEnvelope`, prd §1024)** → prd §1024
- **"Voice" is not a source, a seat or a room (prd §972).** Every voice note is `You`; `SourceRename.sweepVoice` converges stragglers at every launch (never a migration, §647), and `category-fold-selftest.sh`/`category-order-selftest.sh`/`note-sheet-selftest.sh` fail if the name returns → prd §972
- `-oembedProbe` — ask an allowlisted host what a saved link IS, keylessly (prd §244, Model/OEmbed.swift), and NSLog every field → docs/hooks/bridges.md · prd §244
- `-byokKey` — store (or clear ALL) an agent key headlessly (Keychain via TokenVault) → docs/hooks/agent.md
- **The keyed agent got tools, a receipt, a model choice and a librarian** → docs/hooks/agent.md
- **The keyed agent stopped re-paying for its own prompt, learned to read a saved page, and got a ceiling** → docs/hooks/agent.md · prd §415
- **The agent rooms, past §367 — and the fold that already existed** → docs/hooks/agent.md · prd §418
- **The ask is DELETED (2026-10-01, user: "re the ask side, we don't need it"): the on-device model answers nothing (it reads — screenshot naming, digests, the Addresses verdict); the composer stays as Find and the door for the keyed agents and Apple Intelligence (§833). Gone: kept asks, the Today brief and its ledger, "While I was away?", the hint capsule, the ask chips, the MCP door (and the Mac's `network.server` entitlement), "Ask/Search Casberi" and "What's my week" intents, the Today widget, the Daily Brief quick action, `casberi://ask` and `://brief`. `SourceRename.sweepRetiredAsk` clears what they stored** → docs/hooks/agent.md · prd §1047
- `-ghWatchPerson "<login|@login|profile URL>"` `-ghPeopleProbe` — watch a PERSON on GitHub → docs/hooks/bridges.md · prd §519
- `-framesProbe` `-framesTxProbe` `-framesKeyProbe` `-framesPendingProbe` `-framesPasskeyProbe` — The Frames devnet, which chain is `FramesNetwork` → docs/hooks/devnets.md · prd §548 · §728 · §962
- **A wallet-family room's verbs ride EVERY page as its LAST TILES (prd §1039 over §774's rows): All acts for the current account, your own account's page for itself, a stranger's page keeps only the room verb (Frames' `Create`; the Wallet's `Follow` is on every page) — `FramesActs.verbs(for:)`** → docs/hooks/devnets.md · prd §774 · §1039
- `-ghClientID <id>` — override the GitHub device-flow client id; `-ghDeviceProbe YES` — start the device flow, NSLog the user code (`Model/GitHubDeviceFlow.swift`).
- `-viProbe` — run the Visual Intelligence label→corpus matcher headlessly (VisualCorpusMatch → docs/hooks/system.md
- `-awayGap <hours>` — fake the away window (`Model/AppVisit.swift`) the All feed's "new since you were away" marks against ("While I was away?" went with the ask, 2026-10-01).
- `-secretScanProbe` — run the credential tripwire (prd §277, Model/SecretScan.swift) and NSLog what it found: the KINDS plus → docs/hooks/system.md · prd §277
- `-keychainProbe YES` — NSLog the vault's storage-policy census, force `TokenVault.migrateToDeviceOnly`, then census again (counts only, never a value; prd §277).
- `-receiptsProbe` — dump the network receipts ledger (prd §277, Model/NetworkLedger.swift): one receipt| line per host actually → docs/hooks/system.md · prd §277
- `-metricsProbe` `-metricsForget` — what MetricKit has handed this app, one `metricKit|` line per Diagnostics line (`Model/AppMetrics.swift`). Always EMPTY on the simulator; delivery is a device check → docs/verify.md · prd §622
- **The phone's own perf numbers, on the phone — the same spans MetricKit histograms, read seconds after they happen (`-perfReadingsProbe` `-perfMeasure` `-perfForget`)** → docs/hooks/system.md · prd §623
- **The source room's light columns, behind an OS gate (`-sourceRoomLightColumns`, DEBUG) — the projection on iOS 26+ only, because a predicated partial fetch drops rows on 18.6** → docs/hooks/system.md · prd §623
- **Perf-readings self-test (scripts/perf-readings-selftest.sh)** → docs/verify.md · prd §623
- **Lead-body audit (scripts/lead-body-audit.py) — a lead face that never reaches the body ladder, a `ForEach` inside `ViewThatFits` (one subview, so the fit silently stops working), the cast drawn as an overlapping pile, a well inside the lead's well** → docs/verify.md · prd §772
- **Harness-exists audit (scripts/harness-exists-audit.py) — a check the pass runs that is not in the repo** → docs/verify.md
- **Rain-tiles audit (scripts/rain-tiles-audit.py) — rain when sources were asked or something arrived; call `refreshRooms()` when a list changed** → docs/verify.md · prd §655
- **Source-alias audit (scripts/source-alias-audit.py) — a renamed seat's old rows must still resolve to the seat** → docs/verify.md · prd §647 · §650
- **Background-launch audit (scripts/background-launch-audit.py) — the shell is not built for a scene connected in the background** → docs/verify.md · prd §642 · §642b
- **Every setup door opens the in-app Safari sheet; a slab that opens a page passes `url:`, never a closure calling the screen's `openURL`** (`catalog-mode-audit.py`) → docs/hooks/system.md · prd §653
- **Every bridge setup screen is ONE account page (`Screens/AccountPage.swift`, `account-page-selftest.sh`)** → docs/hooks/system.md · prd §639
- **Nothing on an account page is boxed but the entry well.** A row states a fact, a footer explains it, anything you change opens, and Notes stays inline. A line stays only if the door and the fields don't already say it (`setup-copy-audit.py` check 8) → docs/hooks/system.md · prd §708 · §729
- **"What it reaches" is DELETED from every account page (2026-09-11) — row, sheet, lookup and fact. The app's hosts are stated ONCE, in settings; `NetworkReach` and `network-reach-audit.sh` are untouched, so a new bridge's hosts are still a ship gate** → prd §702
- **Every connect screen is on `AccountPage`, and the connect-family audits discover screens by `AccountPage(`** → docs/hooks/system.md · prd §639b
- **The trip to the provider's site is ONE `BridgeSetupCard` (door + steps), drawn only where there is a door; a step fits one line (`MAX_STEP_CHARS` in `setup-copy-audit.py`)** → docs/hooks/system.md · prd §640b · §729
- **An account page's act draws rows, not slabs, through one environment flag (`Design/DSAccountAct.swift`); `dsAccountAct()` is set in two places only** → docs/hooks/system.md · prd §640
- **One destination per catalogue row: both halves run `AppsScreen.rowAction`** (the product page is deleted) → docs/hooks/system.md · prd §641 · §641b
- **Six costs that ran PER ROW PER RENDER, one of them quadratic — and the row bodies' first sweep (Design/StoredPixels.swift, scripts/row-cost-audit.py, 2026-09-06)** → docs/verify.md · prd §626
- **A bridge sweep's saves go through `SaveCoalescer`, `StoredPixels` decodes off main, and deferred work waits for a still hand (`ShellChrome.scrolling`, `dockBusy`)** → docs/verify.md · prd §658
- **A `GestureGate` cap is for a stuck flag (8s), not a hand; a landing's scheduled save waits for a still hand** → docs/hooks/system.md · prd §725
- **Row bodies stay cheap while scrolling: `RowVerbMenu` builds verbs when the press raises it, and a row met by scrolling shows at rest (`RowEntrance.cascadeWindow`)** → docs/verify.md · prd §661
- **A mutation that changed nothing is not a passing mutation — it is one that did not run (scripts/mutation-liveness-audit.py)** → docs/verify.md · prd §627
- **A fetch or a Keychain read belongs in `onAppear`/`.task`, never in a body or a computed property a body reads (build 525)** → docs/verify.md · prd §628
- `-notifyProbe` — what would notify, WITHOUT notifying (prd §306, 2026-08-05, Model/NotifySweep.swift + Model/NotifyPlan.swift) → docs/hooks/system.md · prd §306
- **Notifications are one digest per category, once a day at 18:00, one switch per category; only a dispute, a deadline, a liquidation or a Safe signature stands alone (`NotifyKind.standsAlone`)** → docs/hooks/system.md · prd §770 · §706
- **A digest is the PLACE and one line (prd §883): `Social` / `25 new`, `Wallet` / `+$1,240`, `Work` / `App Review said no · 3 more`.** → docs/hooks/system.md · prd §809 · §809a · §881 · §883
- **L2BEAT — the rails your money sits on, reviewed by somebody independent** → docs/hooks/bridges.md · prd §428
- **The Safe CO-SIGNER — a key that can sign and can never spend** (`-signerProbe`) → docs/hooks/wallet.md · prd §425
- **The signer's four doors, no funded wallet (prd §913)** → docs/hooks/wallet.md · prd §913
- `-wipeAccessProbe YES` — run the Data tray's Delete access internals and log before/after credential counts.
- `-fcRecasts` `-bskyReposts` — Social grew an INBOUND half (2026-07-31, prd §239) → docs/hooks/social.md · prd §239
- **An account marked `mine` lands its OWN replies (2026-09-17)** → docs/hooks/social.md · prd §804
- `-fcName` `-fcLikes` `-fcMentions` — Farcaster grew likes/mentions/channels/replies (2026-07-14, same keyless Snapchain node): -fcName → docs/hooks/social.md
- Social enrichment (2026-07-16, prd 81) — both networks, one pass through Model/SocialBridge.swift. → docs/hooks/social.md
- `-likersProbe` — Who liked your post (2026-08-07, prd §330, Model/SocialLikers.swift, -likersProbe YES) → docs/hooks/social.md · prd §330
- `-followsProbe` — Follow import (2026-07-16, prd 87) → docs/hooks/social.md
- `-bskyMentions` `-bskyReplies` — Bluesky mirrored the keyless parity set (2026-07-14, AT Protocol AppView): profiles + replies + mentions → docs/hooks/social.md
- **Screenshot OCR reads STRUCTURE on iOS 26, and SEES the shot on iOS 27 (`-visionProbe YES`)** → docs/hooks/system.md · prd §282 · §889
- `-photoHealProbe` `-reingestPhotos` — run the Photos HEAL directly (the pass that OCRs, thumbnails, RETITLES and prunes) and NSLog photoHeal → docs/hooks/system.md
- `-photoVerbProbe` — what a screenshot's thing sheet OFFERS, and whether each offer can LAND (prd §275, 2026-08-02) → docs/hooks/system.md · prd §275
- **On-device intelligence, the librarian half** (`-embeddingProbe`) → docs/hooks/system.md · prd §282
- `-relatedProbe` — what the thing sheet shows UNDER a thing: relatedKept| (the earlier copy). The embedding neighbours are NOT drawn since prd §632 and are logged as a diagnostic count only → docs/hooks/system.md
- **The sheet draws the words the app holds (`enrichedText`), never what a model wrote** → docs/reading-spec.md · prd §645
- `-topicMapProbe` — the text treemap, headless (bare `YES` = Obsidian). **Photos, Files and RSS draw no figure since prd §832: the newest thing leads, above the grid** → docs/hooks/rooms.md · prd §230 · §832
- `-roomInsightProbe` — what a source's room LEADS with (prd §247, 2026-07-31) → docs/hooks/rooms.md · prd §247
- `-stripeRoomProbe` `-posthogRoomProbe` — the two room heads' readings line by line (prd §298, 2026-08-04; one NSLog per line, the -todayProbe truncation → docs/hooks/rooms.md · prd §298
- **The note THING SHEETS, past §366** → docs/hooks/rooms.md · prd §399
- **The journals' three shipped defects, fixed in the same pass** → docs/hooks/imports.md · prd §398
- `-peerRoomProbe` `-privacyPoolsRoomProbe` `-gnosisPayRoomProbe` — the three WALLET-RIDING room heads, line by line (prd §349, 2026-08-10; one NSLog per fill/row/spend → docs/hooks/wallet.md · prd §349
- **The onchain card head is SHARED (prd §858, 2026-09-20): `CardSpendRoom` — was `GnosisPayRoom` — serves Gnosis Pay AND MetaMask Card, drawn by one `CardSpendRoomCard(room:seat:)` behind one `FeedScreen` case `.cardSpend(_, seat:)`.** → docs/hooks/wallet.md · prd §858
- **`CardSpendSeat` is the ONE rule for which rows in a card's room are SPENDS (prd §868, `-etherfiCashRoomProbe`), read by all three sources and the door under the card** → docs/hooks/wallet.md · prd §868 · §858
- `-instagramImport` — import an UNZIPPED Instagram export folder (prd §245, Model/InstagramImport.swift; screen → docs/hooks/imports.md · prd §245
- `-tiktokImport` `-tiktokFaces` — import a TikTok export (the user_data_tiktok.json file itself, or a folder holding it), -tiktokFaces <limit|YES> → docs/hooks/imports.md · prd §279
- `-xArchiveImport` — import an UNZIPPED X archive folder (prd §280, 2026-08-02, Model/XArchiveImport.swift; screen → docs/hooks/imports.md · prd §280
- **X joined OEmbed.endpoints the same day, and it is the inverse of the Instagram entry removed alongside it** → docs/hooks/imports.md · prd §280
- `-xLiveProbe YES` — X's live-notifications door, read with the person's own browser-session cookies via an in-app sign-in, not the paid public API §280 declined → docs/hooks/bridges.md · prd §701 · §737 · §772
- `-igLiveProbe YES` `-igLiveSession` — Instagram's live door: notifications and saved posts with the person's own web-session cookies, and a live save FILLS the export's pointer by shortcode. Only a refusal clears the session; a checkpoint keeps it → docs/hooks/bridges.md · prd §726
- `-tiktokLiveProbe YES` `-tiktokLiveSession` — TikTok's live door: the Activity inbox with the person's own cookies, no signatures (measured). A dead session is a 200 with `status_code` 8; a read never marks anything read (`tiktok-live-selftest.sh`) → docs/hooks/bridges.md · prd §731
- **An X notice's post rides `quote`, NEVER `postText` (prd §704).** Row and sheet both LEAD with `postText`, so stamping it drops the news. `SocialSheet.Shape.notice`: after the words test, before the save fallback, gated on the RECORD → prd §704
- **Feeds (RSS + the three feed-follow bridges)** (`-feedFollow` `-feedHealthProbe`) → docs/hooks/bridges.md · prd §312
- **The reading rooms, past §312** → docs/hooks/rooms.md · prd §455
- **The vault (Obsidian)** (`-obsidianVault` `-obsidianProbe`) → docs/hooks/imports.md · prd §320
- **The folder a file is saved in (user feedback: "would be great to be able to press here and it takes you to folder where the file is saved") — the disc says the FOLDER since §736 (`Show in Receipts`), and the From row that carried it is deleted** (`-filesRevealProbe`) → docs/hooks/imports.md · prd §408 · §736
- **The email a mail row came from (user: "see how this says from your inbox? Can we make it so that if you tap it, it takes the user to the email in the inbox")** → docs/hooks/bridges.md · prd §735 · §736
- **A connected folder's images could not be read at all, and iCloud was never why** (`-filesHealProbe`) → docs/hooks/imports.md · prd §604
- **Telegram, through the two doors §57 never weighed** → docs/hooks/bridges.md · prd §456
- `-rssFeed` `-chatgptImport` `-claudeImport` — follow a feed and sync headlessly; -chatgptImport <path> → docs/hooks/imports.md
- `-trelloKey` `-trelloProbe` `-tokenBridge` — Trello (2026-08-03, prd §291, Model/TokenBridges.swift's TrelloAuth + trello(); seat id trello, group Work) → docs/hooks/bridges.md · prd §291
- Dropbox (2026-07-27, Model/DropboxBridge.swift, Screens/DropboxScreen.swift) — a first-class → docs/hooks/bridges.md
- PostHog (2026-07-27, prd §223, Model/PostHogBridge.swift, Screens/PostHogScreen.swift) → docs/hooks/bridges.md · prd §223
- `-for` — Stripe (2026-07-31, prd §250, Model/StripeBridge.swift, Screens/StripeScreen.swift) → docs/hooks/bridges.md · prd §250
- Cursor (2026-08-04, prd §303, Model/CursorBridge.swift) — the cloud agents you launched, landing → docs/hooks/bridges.md · prd §303
- **The GitHub room is ONE FEED: row types are tags (`Model/GitHubRowTag.swift`), watched repos and people scope it from a face rail (`github-rowtag-selftest.sh`)** → docs/hooks/bridges.md · prd §699
- **A GitHub events row names its OBJECT, opens it and carries its words — a PR's title and body, a push's commit, a branch named — off the payload, no request (`GitHubEventShape`, `github-event-selftest.sh`); a notification reads its subject's body, capped at 10** → docs/hooks/bridges.md · prd §909 · §912
- **A connect LANDS in its room (prd §1029): `AccountPage` routes when its seat registers on screen, armed on the seat, never on `state` alone (adopters load `connected` late); GitHub then raises its watch tray once (`ShellChrome.connectLanding`), and its room's tiles end in a Watch verb, as Reminders' end in New (`RoomKindTile.watch`, `GitHubWatchTray`, `GitHubWatchAdd`, prd §1030 · §1031)** → prd §1029 · §1030 · §1031
- **Empty-door audit (scripts/empty-door-audit.py) — a landed row with no door; §909 applied to every bridge** → docs/verify.md · prd §912
- App Store Connect (2026-08-06, prd §323, Model/AppStoreConnectBridge.swift, screen → docs/hooks/bridges.md · prd §323
- Apple Wallet (2026-08-06, prd §313 + §317, Model/AppleWalletBridge.swift / AppleWalletRoom.swift / → docs/hooks/bridges.md · prd §313
- Peer (2026-07-17, prd 113; connect model superseded by §207, 2026-07-25) — the fiat↔crypto onramp → docs/hooks/wallet.md · prd §207
- Privacy Pools (2026-07-21, prd §162) — 0xBow's compliant-privacy pools, the second seat → docs/hooks/wallet.md · prd §162
- `-gnosisPayProbe` — Gnosis Pay (2026-07-26, prd §222) → docs/hooks/wallet.md · prd §222
- `-metamaskCardProbe` — MetaMask Card, the THIRD seat on Gnosis Pay's shape (prd §857/§857b, 2026-09-20) → docs/hooks/wallet.md · prd §857 · §857b · §222 · §860 · §83
- `-solNameProbe` `-solActivityProbe` — Wallet/Solana (2026-07-16, prd §85/§86) → docs/hooks/wallet.md · prd §85
- **Wei / Gwei names, and the router the six copies became** (`-weiNameProbe`) → docs/hooks/wallet.md · prd §597
- `-addressesProbe YES` `-addressesForget YES` — the Addresses index rebuilt over the stores and the link ledger (prd §916 step 2, `Model/ContactIndex.swift` pure + `ContactIndexSources.swift`) → docs/hooks/wallet.md · prd §916
- **Addresses suggests from profile links, bios, book provenance and mail senders; a name you gave names the post's author; the receipt says the first transfer; a named book address anchors poisoning; `ThingsWithContactIntent` (prd §1025).** `-addressesProbe fill` reads web3.bio `/profile` first. Never "Waiting on you" from the to-do mark: bridges set it to mean "open" → prd §1025
- **web3.bio is the resolver behind ENS, and the card gains Base/Linea/Farcaster/Lens rows (prd §916).** → docs/hooks/wallet.md · prd §916
- **Whether an address belongs to a VERIFIED HUMAN, keylessly** → docs/hooks/wallet.md · prd §785 · §785a
- **World Chain is ON by default, MEASURED (prd §788; §785 landed it off)** → docs/hooks/wallet.md · prd §785 · §788
- **Alchemy's `getAssetTransfers` returns NO timestamp on HyperEVM and World Chain; a missing time is read off the block (`TransferTimes`, cached) and a transfer whose block cannot be read is DROPPED, never dated now (prd §790, `transfer-times-selftest.sh`)** → docs/hooks/wallet.md · prd §790
- **World App money is named from World's OWN chain state ("World ID grants" = `RecurringGrantDrop.holder()`, "WLD Vault"), and a World Chain transfer's sheet shows `World ID · Verified human` for a verified counterparty, read on open** → docs/hooks/wallet.md · prd §791
- **Stored HyperEVM/World Chain transfer dates are re-timed by a bounded, ledgered heal (never a done flag), and a World ID grant row's dial opens `worldapp://grants` only when World App answers its scheme** → docs/hooks/wallet.md · prd §792
- **World App money is complete: forward-verified World App usernames and faces, the WLD Vault in the total, Morpho on chain 480, and the next grant as a dated row read off World's contract (`-worldAppProbe YES`).** → docs/hooks/wallet.md · prd §795
- **World Chain approvals read off Blockscout (public RPCs cap logs at 100 blocks; Blockscout pads `topics` with `null`, which must be stripped or every ERC-20 grant reads as ERC-721)** → docs/hooks/wallet.md · prd §797
- **This phone as a World ID AUTHENTICATOR is BLOCKED in World's app, not the protocol (prd §787)** → docs/hooks/wallet.md · docs/worldid-authenticator-spec.md · prd §785 · §787
- **The World ID SEAT is ruled (§786) and NOT BUILDABLE (§787, MEASURED)** — `getPackedAccountData` is zero for a World App wallet and its owner key (the real authenticator is a hidden relayer-made key), and public World Chain RPCs cap `eth_getLogs` at 100 blocks. Do not build from `docs/worldid-seat-spec.md` → prd §786 · §787
- **AgentKit is NOT BUILT (prd §801, user-declined after measuring)** — World App answered our own 3.0 bridge request and refused it (`verification_rejected`, "Visit an Orb"). → docs/hooks/wallet.md · prd §801
- **A World App username is a name ONLY in the follow field (`NameResolve.followTarget`, prd §802), never a `NameResolve.Family`** → docs/hooks/wallet.md · prd §801b · §802
- `-wcProjectID` `-wcConnectProbe` `-wcTimeout` — Wallet/WalletConnect (2026-07-16, prd 84) → docs/hooks/wallet.md
- `-prepareProbe` `-approvalProbe` — run the approval PREPARE path (prd 112, the preparing-surface ruling: reads and previews in-app, signatures → docs/hooks/wallet.md
- **A spam NFT mint is one you didn't sign, not one that's cheap** (`-nftOriginProbe`) → docs/hooks/wallet.md · prd §481
- `-exposureProbe` — the approvals card's whole reading (2026-08-03, prd §292, Model/WalletApprovalExposure.swift + …Source.swift → docs/hooks/wallet.md · prd §292
- `-userOpProbe` `-actingPartiesProbe` — account abstraction (2026-08-03, prd §293, Model/WalletUserOps.swift + Model/WalletActingParties.swift) → docs/hooks/wallet.md · prd §293
- Smart accounts have their own KIND (2026-08-03, prd §294, AddressBook.Kind.smartAccount + → docs/hooks/wallet.md · prd §294
- Morpho (2026-07-21, prd §157) — the second lending protocol the Wallet seat reads, riding watched → docs/hooks/wallet.md · prd §157
- Hyperliquid (2026-07-30) — perp positions, spot, and staked HYPE for the Wallet seat, riding → docs/hooks/wallet.md
- Aerodrome (2026-07-30) — veAERO locks (Base) for the Wallet seat, riding watched wallets (no → docs/hooks/wallet.md
- `-seedWalletHistory` — writes a synthetic WalletStore.ValueSample line for a watched wallet (the first, or the named one), spaced 4h+ → docs/hooks/wallet.md
- `-compositionProbe` — the balance card's "In protocols" strip (prd §240, 2026-07-31, Model/WalletComposition.swift), headless: what's → docs/hooks/wallet.md · prd §240
- `-addressBook "<Name>:<address>[,…]"|clear` — seed the address book headlessly (prd §169); `-addressBookProbe YES` reports every entry's kind, which are watched, and the cap → docs/hooks/wallet.md
- `-watchCapProbe <address>` — attempt one more watch and NSLog `added`/`alreadyWatching`/`limitReached`/`invalid` (prd §170); one add per launch.
- `-holdingsWindowProbe` `-holdingsWindow` — the holdings freshness window (prd §216, HoldingsCache in Model/WalletIngest.swift) → docs/hooks/wallet.md · prd §216
- `-portfolioProbe YES|<watched address>` — the combined portfolio read headless (prd §155): merged total, token count and treemap shape. Spends Alchemy credits → docs/hooks/wallet.md
- `-openDiagnostics YES` — open the Diagnostics sheet (pair with `-openSettings YES`); it runs the cover-photo and token-chart paths on-device and prints each step.
- `-connectPhotos YES` — runs the real Photos connect+ingest headlessly; `-reingestPhotos YES` — calls the bare re-scan (no permission request) that `BridgeRefresh` now runs each foreground.
- `-connectStrava YES` / `-connectGarmin YES` — run a rider's connect: Health workouts filtered by `sourceRevision` through `HealthIngest.riders`, one row per rider. On the sim expect "connected, 0 in" → docs/hooks/system.md
- **ONE ACTIVITY, ONE ROW — and Strava never wins (RULE, `Model/HealthRiders.swift`).** → docs/hooks/system.md
- `-hideDemoBanner YES` — leave the demo banner unmounted for App Store stills (DEBUG only; pair with `-demoEnter YES`).
- `-leadCycleProbe <s>` — land one Trello thing after the delay, then retitle it 3s later (NSLogs `leadCycle:`), so both lead cycles show → prd §901
- `-rainPulse <s>` — bump `ShellChrome.refreshPulse` after a delay (NSLogs `rainPulse: dealt N tiles`); deal rain only through `ShellChrome.rain(sources:)` → docs/verify.md · prd §655
- `-hfWatch` `-hfPapers` `-hfProbe` — the Hugging Face bridge (2026-08-03, prd §290, Model/HuggingFaceBridge.swift; screen → docs/hooks/bridges.md · prd §290
- `-wiseProbe` — Wise (2026-09-16, prd §778): a personal API token, read-only, the Bitrefill/Privacy.com pattern → docs/hooks/system.md · prd §778
- `-splitsProbe` — Splits (2026-09-18, prd §820): a Read-scoped API key, refused on save unless `whoami` scopes are exactly `read` → docs/hooks/system.md · prd §820
- **Apple Wallet is TWO regions, and `Card` is a fact it reads (prd §779).** FinanceKit is the US on 17.4+ (Apple Card/Cash/Savings) and the UK on 18.4+. → docs/hooks/wallet.md · prd §779
- `-spotifySession "<sp_dc>"` `-spotifyProbe` — the Spotify seat's session, and its chain link by link (prd §703, 2026-09-12) → docs/hooks/bridges.md · prd §703
- `-duolingoSession "<jwt_token>"` `-duolingoProbe` — Duolingo's live door, the fifth seat on the session-cookie pattern → docs/hooks/bridges.md · prd §776
- **A 200 from `open.spotify.com/api/token` is not a signed-in session (`isAnonymous`); only `.refused` clears the credential, and a 429 is `.throttled`** → docs/hooks/bridges.md · prd §711 · §711b
- **Acorns and Rocket Money are REAL SEATS (Wallet group, `.signIn`, prd §780b)** → docs/hooks/bridges.md · prd §780b
- **A seat may ship ahead of its evidence only if it SAYS what it doesn't know (RULE, prd §780b).** → docs/hooks/system.md · prd §780b
- **Rocket Money's queries come from the live page, so "signed in" is not "connected" (prd §780b).** An empty catalogue lands nothing; the page carries a DOOR ("Teach it your pages"), never a sentence telling you to act with no way to act → prd §780b
- **"Don't ship it yet" says where a feature may NOT go, and nothing about where its DOOR belongs (RULE, prd §780b).** The staged seats' only door went in Diagnostics because it was the nearest screen that compiled; that is not an answer, it is a default. Ask → prd §780b
- **All three finance seats are on the WALLET shelf (prd §780c)** — app catalogue, website shelf and docs list. NerdWallet moved off Reading (user); the honesty half is its TAGLINE ("news"), which `nerdwallet-selftest.sh` guards instead of the group → prd §780c
- **A seat never asks you to do its own work (RULE, prd §780c).** Rocket Money's sign-in view WALKS the account's pages itself to learn its queries. → docs/hooks/system.md · prd §780c
- **The app count is a ROUNDED claim, "100+", derived and rounded DOWN (prd §780c).** It read 97 over a 101-cell shelf. `app.js` derives it; `catalog-sync.sh` asserts the stated ten is the shelf's floor, so it fails in either direction → prd §780c
- **The website shelf's ROW placement is unchecked** — `catalog-sync.sh` compares name sets and is blind to which category row a cell sits in; two seats landed in Reading because the insertion anchor was Substack → prd §780c
- **The website's app COUNT is derived, and its docs list is gated (prd §780b).** The home page said 97 over a 101-cell shelf and `docs.html` had been missing Spotify for weeks. → docs/hooks/system.md · prd §780b
- `-privyProbe YES` `-privyForget YES` — Privy, a sign-in seat on Privy Home (Wallet group) → docs/hooks/bridges.md · prd §803c
- `-rocketLoginProbe YES` — open Rocket Money's sign-in headlessly (with `-openSetup "Rocket Money"`) and NSLog what the page drew; the site walls anything 450px wide or narrower, so the view pins a 520px desktop viewport → docs/hooks/bridges.md · prd §781
- **Apple Intelligence is a seat (prd §833): Apple's model on Private Cloud Compute answers the composer, one tap in the Agents catalogue, no key.** → docs/hooks/system.md · prd §833
- `-logosWatch "<id[,id]>"` `-logosProbe YES|<from>-<to>` `-logosRewind <block>` `-logosNode "<address>"|forget` — Logos: watch public LEZ accounts, keyless, forward from the watch; a range decodes blocks WHOLE, a rewind re-walks real history (a quiet testnet otherwise lands nothing); your own node is read at the address you give, five GETs (mining since §1016), rows only on change → docs/hooks/bridges.md · prd §988 · §989 · §1016
- `-stockWatch` — resolves each query on Stocktwits' keyless symbol search and watches the top match in Markets (the Stocktwits seat is retired, its takes dropped) → docs/hooks/bridges.md
- **Markets is ONE app (prd §1000): the Tokens seat renamed, Stocktwits' watched stocks moved in by `SourceRename.sweepStockWatches` (takes deleted, seat retired), and every catalogue category is a company pack (`CompanyPacks`) — Nasdaq for a stock, CoinPaprika for a coin, n/a for anything unlisted, never a valuation**

Deep links: `casberi://home`, `casberi://feed`, `casberi://feed/type/<Tag>` (internal, no UI produces it, prd §269), `casberi://account`, `casberi://settings`, `casberi://note` (a new note, prd §982), `casberi://thing/<id>`, `casberi://person/<Bluesky|Farcaster>/<handle>`, `casberi://frames/sponsor?r=` (a payment request, prd §728c).

- **The widget is Wallet (prd §877; Today went with the ask, 2026-10-01).** `WidgetPublish` clears the retired tiles' payloads from the app group. → docs/hooks/system.md · prd §382 · §877

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
- **The Safe room, six passes deep (2026-09-07) — the sign block READS the batch (`multiSend` is 96% of real Safe traffic and the co-signer refused every one), the head NAMES who it waits on, "ready to execute" respects the queue, the guard is stated, Gnosis becomes signable** → docs/hooks/wallet.md · prd §652
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
- Liquid Glass on the floating layer only (composer/FAB/toasts) — never on content. There is no tab bar (prd §100); older rulings that narrate one are historical → docs/hooks/design.md
- No letter-spacing, no ALL-CAPS eyebrows — headers are words in sentence case ("Getting started", never "G E T T I N G  S T A R T E D" or "GETTING STARTED"). `.kerning()` is banned; the type ramp carries hierarchy by size/weight alone (ruling 2026-07-08).
- **Every text rung is named for the size it draws, and a glyph takes a `DSGlyph` rung, never a number (prd §762).** → docs/hooks/design.md · prd §762
- **Every row in every room is one anatomy (prd §764, amended by §902)** Weight carries a fact (the next event, a state word), never a row's title. → docs/hooks/design.md · prd §764
- No hairlines — zero exceptions; nothing draws a line. Widget/tile radius = `DS.Radius.widget`. **The catalog is rows (what you could add) and the sources tray is tiles (what you have); keep that split** → docs/hooks/design.md · prd §518
- **The day divider is the one line of type in the brand pink (`DS.brandInk`), and the cover card is not.** → docs/hooks/design.md · prd §740 · §742
- **The elevated card has ONE caller left, and it is a control (prd §759).** `dsWidgetSurface` is off every block in the app. → docs/hooks/design.md · prd §759
- **No plates under ANY spelling (prd §782, user: "these plates").** `dsInkFill` is the floating layer's only. → docs/hooks/design.md · prd §782
- **A room head draws NO PLATE (prd §758, supersedes §745's "one surface" and §757's "the head keeps its card").** `dsRoomHeadCard()` is `dsRoomHeadBlock()` and applies no `dsWidgetSurface`. → docs/hooks/design.md · prd §758
- **The wallet family's rows stand on NOTHING (prd §757).** → docs/hooks/design.md · prd §757
- **Wallet, Frames and Logos take every room's anatomy: box · tiles · account menu · list (prd §1039, amends §750).** The Overview rows (`DSScopeRows`) and the Actions block are deleted; the verbs are the LAST tiles (Wallet `Follow`; Frames `Create · Send · Top up`; Logos `Explorer`); the Activity and Accounts tiles are gone — Home's list IS the activity, only what happened; what's ahead is the Wallet's Coming up tile, soonest first (`walletComingUpSections`, §1041) → prd §1039 · §1041 · §750
- **The room's faces ride the dock folder's capsule, after the venues, and draw no words (prd §753).** → docs/hooks/design.md · prd §753
- **That capsule always LEADS with the room you are standing in (prd §754).** Shut, the folder draws one seat. → docs/hooks/design.md · prd §754
- **Every room's lead is `DSRoomChassis.leadHeight`, the wallet head's card, and nothing in it is air it could honestly fill (prd §760).** → docs/hooks/design.md · prd §760
- **Every room's lead is one well (prd §766): a statement and a body, sitting at the top of the box; the count foot (`LeadFooter`, "N things since <month>") is deleted from view and model (§914).** → docs/hooks/design.md · prd §766 · §914
- **A lead's BODY is a ladder (§772), EVERY cover holds the box (§904), the ladder GROWS (§905), and each CATEGORY has a face (§907, §908).** → docs/hooks/design.md · prd §772 · §904 · §905 · §907 · §908
- **The dock is a TRAY behind the face (prd §930): the phone's one navigation button opens `Shell/RoomsTray.swift`, a layer under the seat** → docs/hooks/design.md · prd §930 · §932 · §935 · §937 · §958
- **Notes is a room in You, and Pinned folds into it (prd §969): one always-drawn door, tiles All · Folders · Pinned · New (A–Z, §995; folders built §980: `Thing.folder` by name, the list in `NoteFolderStore` over `KeyValueMirror`, a row files from its long press, one folder at most, `CD_folder` must deploy), one plain list with no day dividers and the time at the row's trailing edge, `Pinboard.room` is `"Your notes"` — never the drawn word, because "Notes" is also a catalog category and the Apple Notes alias, which swallowed the door's tap and the pager's page (prd §975).** Membership is a pin or a note of yours (`Pinboard.inRoom`); the note sheet is the composer's shape and its dismiss keeps; swipe-to-delete is NOT built because the pager owns every horizontal drag (measured 2026-07-16), so a note of yours deletes from its long press, confirmed, and wears `note.text`/`waveform` instead of `You`'s person (`BridgeIcon.noteSymbol`). Its cover never declines, so a pinned token pulse fills the well and the tiles never rise. A note of yours EDITS: its sheet's first disc is `Edit` (Reminders' seat), which reopens the note sheet on the same thing (`ShellChrome.editNote`), and its sheet draws no "That day" shelf (§981) → docs/hooks/system.md · prd §969 · §978 · §979 · §980 · §981 · §995
- **The wallet-family visualization pass (prd §920–§929, reviewed §931, §936)** → docs/hooks/design.md · prd §920 · §931 · §936 · §954
- **Every room opens on the box, and twelve more rooms carry kind tiles; a room's tiles never depend on its head (`standaloneLead`)** → docs/hooks/design.md · prd §911
- **Kind tiles (prd §815, §816): Safe, GitHub, Stripe, App Store Connect, Hugging Face, PostHog, L2BEAT and Walletbeat; a `DSTileScope` case wears the constant of its own NAME; Instagram, X and TikTok get NO tiles** → docs/hooks/design.md · prd §815 · §816 · §904 · §821 · §831
- **Every lead stands in the rows' column (`DSRoomChassis.leadInset`) and ends at `leadGap`** → docs/hooks/design.md · prd §763 · §906
- **The X room leads with its NEWEST NOTIFICATION, never a year grid (prd §817).** `FeedHeatmap` has no `X` entry. → docs/hooks/design.md · prd §817
- **One explaining sentence per screen, at most, through `DSFootnote` (prd §748).** A line stays only if it says what the controls cannot; honesty, money, signing, privacy and fix-it lines are kept on purpose. `footnote-audit.py` counts per file, with reasoned allowances → prd §748
- **Two pills, no more (prd §746): `Chip` is a choice, `DSStamp` is a fact, and a verb is a row (`DSDoorRow`, `DSCopyRow`, `RowVerb`).** `ds-template-audit.py` check C fails a capsule drawn behind content outside `Design/` → prd §746
- **Every room head composes `DSRoomChassis.Head` (prd §745): a lead, notes, blocks, footnotes, one surface and one door.** → docs/hooks/design.md · prd §745
- **Every chart head draws into `DSRoomChassis.figureHeight` (56pt) and caps at `headRowCap` (8, raised from 3 by §760: `LeadFit` draws as many rows as the box holds); a head with no chart is deleted and the room leads with its newest thing (prd §749, §751).** The models spell the cap literally, and `room-heads-selftest.sh` holds them to it → prd §751 · §760
- **Every feed row composes ONE anatomy, `DSFeedRow` (prd §744): a 46pt lead (`DS.Face.seat`) centred in a 60pt head (§1017), the name and its trailing slot (money, or a clock still ahead, §902), one line, then its content.** → docs/hooks/design.md · prd §744 · §1017
- **No controls at the top of the screen, anywhere (user, prd §752).** A picker, a scope or a back control sits in the content (under the head or figure) or in the bottom band. → docs/hooks/design.md · prd §752 · §752b
- **The wallet family has NO BAR (prd §747, supersedes §547); the account is picked from the menu under the tiles (§936), and the acts are tiles on every page (§774, §1039).** → docs/hooks/design.md · prd §747 · §774 · §1039
- **The dock's face opens APPS (was Accounts) — search, then the one catalogue; Manage is deleted, a connected row with a room is a status (no chevron) whose tap LANDS IN ITS ROOM (prd §1040, amends §1033/§1036), and a room's own sliders disc beside its name raises its account page (prd §1033; §796, §863).** → docs/hooks/design.md · prd §796 · §933 · §1033
- **SETTINGS HOLDS NO KEY (prd §871).** "Your key", `AccountDetail.key` and `AgentKeyPicker` are deleted. → docs/hooks/design.md · prd §871
- **The face opens the rooms tray (prd §930); Apps (was Accounts) is a door in its You row, and a room's sliders disc beside its name raises that room's account page (§1033). The dock's catalogue tile is deleted (§798).** → docs/hooks/design.md · prd §798 · §930 · §1033
- **The dock's leading seat is the back door on every pushed screen, and nothing stands at the top edge (prd §767).** → docs/hooks/design.md · prd §767
- **A pushed screen leaves the back door's column clear (`DSDock.seatClearance`, `.dsSeatClearance()`, prd §829).** → docs/hooks/design.md · prd §829
- **The keyboard COVERS the dock; it never lifts it (prd §865, and §865a is the half that shipped broken).** → docs/hooks/design.md · prd §865 · §865a
- **Every empty state draws what would fill it, empty (prd §769, §771).** `DSEmptyState` is `.room(figure)`. → docs/hooks/design.md · prd §769 · §771
- **An empty scope's `words:` is ONE CLAUSE, and a string with no reader is deleted (prd §799).** → docs/hooks/design.md · prd §799
- **Feed rows are bare — no plate, no card, anatomy cards included (prd §749, supersedes §743).** A room without a visualization leads with its newest thing as `FeedLedeCard`, which has no backing: no deck, pour or shadow → prd §749
- **A post yields its card to the cover, and the cover draws it AS a post (prd §756, supersedes §732's option A).** → docs/hooks/design.md · prd §756
- **A term that SUPPRESSES a head is not a head (prd §755).** `heroShown` means a head card is drawn. → docs/hooks/design.md · prd §755
- **Every pour is ink — `DS.pourInk`, one token.** Colour that says what is happening stays; colour that says where it came from goes → docs/hooks/design.md · prd §524
- Apps Browse categories follow prd §59 (X under Social, Slack under Work, Notes its own category); the taxonomy is `Model/BridgeCatalog.swift`, mirrored on the website.
- Typed text in the composer NEVER saves — things enter only via capture paths (paste chip, mic, share, screenshots, drop, bridges). Saving is an outcome the toast reports, never a verb.
- Swipe verbs are reads only (writes live in the sheet, with consent). Feed chips only when they differentiate.
- **A row that names a place is a BUTTON, or it is deleted — the “From” row is gone from every sheet (prd §736).** → docs/hooks/design.md · prd §736
- **Every disc on the dial PRESSES (`PressSpring`), a glyph that changes MORPHS (`dsSymbolSwap(icon)` inside `disc`), and a copy marks its own disc for 1.2s (prd §867).** → docs/hooks/design.md · prd §867 · §693
- **Every `Button` answers the hand (prd §965): a row or a word wears `RowPress`, a disc, chip, face, tile or slab wears `PressSpring`, never `.plain` — `ds-template-audit.py` check D fails a plain Button, the dock, the face door, the tray scrim and the keypad excepted by ratchet** → docs/hooks/design.md · prd §965
- **A room's tiles read A–Z, All/Home first (known by glyph) and the verbs last, A–Z among themselves (§1039), enforced in `DSScopeTiles.alphabetical` (prd §995, user: "that's a rule for any room"); the strip keeps the dock's order. The music rooms scope Activity · Albums · Artists · Songs, orders not filters (`Model/MusicShelf.swift`, `music-shelf-selftest.sh`)** → prd §995
- **Becoming the pick is a crossfade on `DS.Motion.standard`, inside the template (prd §966): `DSScopeTiles`, `DSRangeChips`, `FaceScopeRail` and `Chip` animate their own fill and ink, so a room whose pick handler forgets `withAnimation` still slides the tint in** → docs/hooks/design.md · prd §966
- **Honesty rule: no dead controls, no fake status (prd §83).** A hand-painted button swaps its background when disabled; never quote a price off a stale trade; a change that rounds to zero has no sign or colour. "End-to-end encrypted" requires Advanced Data Protection — don't overclaim → docs/hooks/design.md
- **A status WORD takes the ink (`DS.attentionInk`/`confirmInk`/`destructiveInk`), a glyph or fill keeps the hue (prd §1004).** The vivid hues are 2.2:1 and 3.6:1 as text on the light page (`status-ink-audit.py`) → prd §1004
- **The Mac takes its own point scale — `DSTextStyle.macScale = 0.88`, one lever.** `DS.Face`/`DS.Mark` and the `widget*` rungs opt out (`design-ramp-audit.py` check 5) → docs/hooks/design.md · prd §631
- **A walked row on the Mac can be taken with ⌘C, Space and drag-out, through one resolver (`Shell/MacRowHandoff.swift`)** → docs/hooks/design.md · prd §631
- Product rulings live in docs/prd.md — check it before re-litigating a design decision; record new rulings there.
- **Current law is `docs/law.md`** — the live rulings by area, each citing the § in force, over a generated index of every live ruling and its amendments; read it before the ledger. `docs/prd.md` stays the record: a new ruling goes there first, then run `python3 scripts/law-digest.py` (`--check` fails when law.md is stale or cites a dead ruling).

## Website (casberi.app)

- **RULE: every app added to the catalog also lands on the website in the same session** — a hero marquee tile, a `#catalog` shelf cell and an `.ai-<name>` background — then bump the `?v=` cache-busters, zip `website/`, deploy through cPanel, and `rm` then `cp` the zip to `~/Downloads/website-deploy.zip` → docs/website.md
- **RULE: `BridgeCatalog.offers` is the single source of truth for the app catalog, the website catalog and both marquees**, enforced by `scripts/catalog-sync.sh`; a marquee name must equal its offer name exactly → docs/website.md
- **RULE: a new bridge is not done until its API hosts are in `Model/NetworkReach.swift`** (prd §205). `network-reach-audit.sh` is a ship gate. A host built at runtime names a declared family; a host the person types names its service through `NetworkLedger.record(host:as:)` → docs/verify.md
- **RULE: website icons are inlined as base64 data URIs — never hot-link a remote image** → docs/website.md

## Working mode

Goal-by-goal with user review checkpoints. Build + verify on simulator before presenting. The user rules on design; run `/code-review` on the diff before their checkpoint so mechanical findings don't consume it.
