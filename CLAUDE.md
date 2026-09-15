# Casberi

Native iOS app — a personal corpus of "things" (links, screenshots, events, chats, voice notes, agent outputs) with on-device generative UI synthesis. Solo project, pre-App Store (Developer Program enrollment active; shipping via TestFlight, App Store v1 not yet submitted).

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

## Building (critical)

From the canonical `~/Developer/casberi` copy, a plain build codesigns cleanly — no workaround needed:

```sh
xcodebuild -project Casberi/Casberi.xcodeproj -scheme Casberi \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
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

- **Mac parity gate (verify.sh step 1b, 2026-08-12)** → docs/verify.md
- **verify.sh runs verify-mac.sh IN PARALLEL and gates on it (user rule, 2026-08-21 — the two passes being separate was discovered, not chosen)** → docs/verify.md
- **Mac parity audit (scripts/mac-parity-audit.py, 2026-08-12)** → docs/verify.md
- **The two verify scripts each ran checks the other didn't, and both are now provably complete** → docs/verify.md
- **The pure-logic harnesses run at once, and an unchanged one is not re-run (PERF, 2026-08-19). Measured on full green passes: 32.8min → 15.2min → 3.6min** → docs/verify.md
- **The pass ran every harness TWICE for eleven days (PERF, 2026-09-01). Measured on the 08-31 runs: 38–57min for a green pass, 154 and 161min for two overlapping sessions, against the 3.6min recorded above** → docs/verify.md

- **The pass was mostly IDLE CORES — time every step before optimising it (PERF)** → docs/verify.md · prd §612

- **The address book's delight pass** → docs/hooks/wallet.md · prd §441
- **Address-book shape self-test (scripts/address-book-selftest.sh, 2026-08-22)** → docs/verify.md · prd §440
- **SwiftData liveness audit (scripts/swiftdata-liveness-audit.py, 2026-07-25)** → docs/verify.md
- **Info.plist strings audit (scripts/infoplist-strings-audit.py, 2026-08-04, ITMS-90738)** → docs/verify.md
- **Keychain policy audit (scripts/keychain-audit.py, 2026-08-02)** → docs/verify.md · prd §277
- **Receipts coverage audit (scripts/receipts-coverage-audit.py, 2026-08-02)** → docs/verify.md · prd §277
- **CloudKit schema audit (scripts/cloudkit-schema-audit.py, 2026-08-02)** → docs/verify.md
- **Redaction coverage audit (scripts/redaction-coverage-audit.py, 2026-08-19)** → docs/verify.md · prd §277
- **Ref-shape audit (scripts/ref-shape-audit.py, 2026-08-19)** → docs/verify.md
- **Delete-guard audit (scripts/delete-guard-audit.py, 2026-08-19)** → docs/verify.md
- **Dead-closure audit (scripts/dead-closure-audit.py, 2026-09-10) — a control calling a closure property nothing ever supplies** → docs/verify.md · prd §669
- **Defaults-lock audit (scripts/defaults-lock-audit.py, 2026-09-14) — a lock held across a `UserDefaults` write deadlocks with every view body (build 570)** → docs/verify.md · prd §721
- **ShareLink style audit (scripts/sharelink-style-audit.py, 2026-09-11) — an unstyled share control in a `List` row becomes the row's action; give it `.buttonStyle(.plain)`** → docs/verify.md · prd §693
- **Day-divider audit (scripts/day-divider-audit.py, 2026-09-15) — the day header wears `DS.brandInk` (the mark's pink); a group named by something other than time passes `dated: false` and keeps the primary ramp** → docs/verify.md · prd §740
- **Design-template audit (scripts/ds-template-audit.py, 2026-09-13) — reach for `DSSpinner`, `dsReadSheet`, `DSPushRow`/`DSChevron`/`DSMoreLink`, `DSToggleRow`, `DSEmptyState`, `DSCopyCapsule` and `Chip` before drawing one by hand** → prd §715
- **Secret-scan self-test (scripts/secret-scan-selftest.py, 2026-08-02)** → docs/verify.md · prd §277
- **On-device self-test (scripts/ondevice-selftest.sh, 2026-08-02)** → docs/verify.md · prd §282
- **CI, at last (.github/workflows/static-checks.yml, 2026-08-19)** → docs/verify.md
- **verify.sh's audit list is provably complete now** → docs/verify.md
- **Live-integrations heartbeat (scripts/live-integrations.sh, 2026-07-17)** → docs/verify.md
- **Demo census — every other surface, one launch (Shell/DemoCensus.swift + verify.sh "Demo census", 2026-09-05; `DEMO_SHOTS=1` for the room screenshots)** → docs/verify.md · prd §617
- **Row-window self-test (scripts/row-window-selftest.sh, 2026-09-08)** → docs/verify.md · prd §657
- **Every account page is a `List` inside a draggable sheet, and its roster is bounded through `RowWindow` (`row-window-selftest.sh`, `row-cost-audit.py`)** → docs/hooks/system.md · prd §710
- **RULE: a feature deleted from the surface is deleted from the model**, or it is §83's dead control one layer down where no screen sweep sees it (the ranked board and `roomScoped`) → docs/hooks/system.md · prd §723
- **RULE: name every column a `propertiesToFetch` read touches** (the RSS page's sync) → docs/hooks/system.md · prd §722
- **Feed-walk self-test (scripts/feed-walk-selftest.sh, 2026-09-08) — next/previous follows the list you opened from; `FeedSheetRoute.thing` carries a `WalkScope` value, never a `[Thing]`** → docs/verify.md · prd §645
- **Mail-location self-test (scripts/mail-location-selftest.sh, 2026-09-15) — the message door: a `Message-ID` fence, and an unencoded `/` that turns Gmail's one search into a PATH** → docs/hooks/bridges.md · prd §735
- **Readable-body self-test (scripts/readable-body-selftest.sh, 2026-09-08) — the page extractor: one 200-paragraph / 8,000-character bound across app and appex, and which hosts a scrape is fair on** → docs/verify.md · prd §645
- **Reading-draw self-test (scripts/reading-draw-selftest.sh, 2026-09-08) — the sheet's `.link` arm: *has a body* draws, *could get one* fetches; an article draws the art, the words, then the door** → docs/verify.md · prd §645 · §709
- **Health-riders self-test (scripts/health-riders-selftest.sh, 2026-09-06) — the Strava/Garmin seats and the activity dedupe** → docs/verify.md
- **MetricKit self-test (scripts/metrics-selftest.sh, 2026-09-05) — the one check for logic no machine here can exercise, because no machine here can make a payload** → docs/verify.md · prd §622

- **live-integrations.sh covers YouTube since 2026-08-06, and RUNS NIGHTLY (nightly-live.sh)** → docs/verify.md · prd §312 · §654
- **Hero-tint audit (scripts/hero-tint-audit.py, 2026-09-02)** → docs/verify.md · prd §563
- **Design-motion audit (scripts/design-motion-audit.py, 2026-08-04)** → docs/verify.md · prd §299
- **Design-ramp audit (scripts/design-ramp-audit.py, 2026-08-11; check 5 added 2026-09-06 — every `widget*` rung must declare `macScales: false`)** → docs/verify.md · prd §631
- **App Store Connect self-test (scripts/appstoreconnect-selftest.sh, 2026-08-06)** → docs/verify.md · prd §323
- **PRD index audit (scripts/prd-index-audit.py, 2026-08-11)** → docs/verify.md
- **Setup-copy audit (scripts/setup-copy-audit.py, 2026-08-06)** → docs/verify.md · prd §315
- **Figure self-test (scripts/agent-panel-selftest.sh, 2026-08-07) — the figure grammar behind the chip peek and the cluster map** → docs/verify.md · prd §334
- **Room-head self-test (scripts/room-heads-selftest.sh, 2026-08-04)** → docs/verify.md · prd §298
- **The social rooms became ONE room (Model/SocialRoom.swift + SocialRoomSource.swift, scripts/social-room-selftest.sh, 2026-08-26)** → docs/hooks/social.md · prd §489
- **Retriever self-test (scripts/retriever-selftest.sh, 2026-08-06)** → docs/verify.md · prd §318
- **Ranking sweep (-rankSweep "q1|q2|…", 2026-08-06 amendment)** (`-rankSweep` `-semanticFloor` `-expandDistance`) → docs/verify.md · prd §318
- **Perf pass (scripts/perf.sh)** (`-Onone`) → docs/verify.md · prd §257
- **Mac verify (scripts/verify-mac.sh, 2026-08-01)** → docs/verify.md
- **The Mac verify's cleanup is BOUNDED, and that bound is a fix not a precaution** → docs/verify.md
- **iCloud sync on the Mac, and the four things no check could see** → docs/verify.md · prd §607
- **The Mac nightly was red on ELEVEN of the last TWELVE nights, and every one resolves green on today's tree** → docs/verify.md
- **Mac nightly (scripts/nightly-mac.sh + scripts/com.casberi.nightly-mac.plist)** → docs/verify.md

- Test device: **iPhone 17 Pro** simulator, iOS 26 runtime.
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
- Installing for probes: pick the NEWEST DerivedData (`ls -dt ~/Library/Developer/Xcode/DerivedData/Casberi-*` — plain `ls -d` is alphabetical and served a day-old binary for 30 minutes on 2026-07-14). `runAll` NSLogs `probeArgs:` with the launch args it saw — if that line is missing or stale, you're running the wrong binary.
- **`booted` is ambiguous with two simulators up.** A second session's device can take your `simctl … booted` calls and simulator taps, and it reads as a stale build. Pin the udid on every call (`xcrun simctl list devices booted`) → docs/gotchas.md
- **Verify the INSTALLED binary, not just the newest one.** `ls -dt` globs every `Casberi-*` DerivedData, so a concurrent session can serve you their app without your hooks. Check with `strings "$(xcrun simctl get_app_container booted com.casberi.app app)/Casberi" | grep -c '^myHookKey$'`. A `database is locked` build error clears on retry → docs/gotchas.md
- On a fresh sim install the demo seeds re-ask Photos/Calendar/Health permission at launch, and the queued sheets block everything (probes still run, but the UI is unusable and Health's ask stalls its probe). Pre-grant what simctl can (`xcrun simctl privacy booted grant photos com.casberi.app` — AFTER install; uninstall wipes grants) and tap the Health sheet once via computer-use; grants then persist for every later headless run.

## Dev keys (real secrets for keyed probes)

- Real test keys for keyed probes (`-byokKey`, `-tokenBridge`, `-openSeaKey`, …) live in the macOS login Keychain under service `casberi-dev.<name>`, managed by `scripts/dev-keys.sh` (`set` prompts silently or reads stdin — the user stores once; `get`/`list`/`delete`). **RULE (user, 2026-07-16): fetch a key ONLY inline via command substitution** — e.g. `xcrun simctl launch booted com.casberi.app -byokKey "venice:$(scripts/dev-keys.sh get venice)"` — never `get` into echo/cat/a variable you print, so values never enter assistant context or session transcripts. `scripts/dev-keys.sh list` shows what's available (names only). This replaces asking the user to paste keys per session; if a needed key isn't stored, ask them to run `dev-keys.sh set <name>` once.

## DEBUG launch-arg hooks

All read via UserDefaults in `Shell/RootShell.swift` unless noted. **The flag stays here; the long entry moved to `docs/hooks/`** — open the named file for the measured quirks, the decisions with reasons, and what each probe exists to separate:

- `-deeplink <casberi://url>` — open a deep link on launch.
- `-demoCensus YES` — over a poured demo (`-demoEnter YES` first), compose every surface in one process and NSLog `demoCensus| <surface> | … | ok|empty|skipped`; a new surface is one row in `DemoCensus.registry` (`Shell/DemoCensus.swift`, prd §617).
- `-quickActionProbe YES` — fire the Daily Brief quick action's warm landing after launch (NSLogs `quickAction:` then `briefRequest:`). A pass is not evidence the quick action works: it cannot reach `SceneDelegate` delivery (prd §377).
- `-chipStats "<source:n[,…]>"|clear` — seed the source strip's tap-learning counters (`Model/ChipMemory.swift`); every mount NSLogs `chipLabels:`.
- `-openRoom "<seat name>"` — land in a source's room headlessly at mount (`RootShell.openRoomIfRequested`; NSLogs `openRoom:`). Pair with `-demoEnter YES` on a prior launch for a furnished room.
- `-openThing "<title prefix>"` — open the newest thing whose title starts with the prefix (NSLogs `openThing:`). It runs at mount, before ingest hooks land anything, so land first and relaunch.
- `-answerProbe "<query>"` — run the answer path headless, NSLog the result (`-probeDelay <s>` to wait first).
- `-uiAnswerProbe "<query>"` — auto-open the composer and send through the real UI path (also read in `Shell/Composer.swift`).
- `-mcpProbe "<query>"` — MCP probe.
- `-noPrewarm` — skip model session prewarm.
- `-forceBackgroundLaunch YES` — stamp this launch as a background launch so `RootShell`'s gate stays closed (NSLogs `backgroundLaunch: yes`, prd §642). The simulator cannot background-launch, so a pass proves the branch renders, never that the watchdog is beaten.
- `-fresh YES|NO` — sticky new-user mode (persists until flipped or reinstall); re-shows onboarding.
- `-accountDetail <case>` — open a settings detail sheet (`Screens/AccountScreen.swift`).
- `-openSettings YES` — pushes the settings screen (`HomeRoute.shared.present(.settings)` in Home's onAppear); reliable since the `HomeRoute.path`-array rewrite (2026-07-22). `-deeplink casberi://settings` works equally.
- `-icloud.sync YES` — AppStorage override for the sync toggle copy.
- `-onboarded YES` — AppStorage override that skips first-launch onboarding (fresh installs otherwise land on it, hiding the screen you deep-linked to).
- `-pileTap "<Offer name>"` — fire an empty-feed pile tile's tap after the fall (NSLogs `pileTap:`). Stage it with `-fresh YES -onboarded YES`, terminate, then `-onboarded YES`.
- `-openSetup "<Offer name>"` — push a bridge's setup screen; `-openProject "<Tag>"` — push a project detail (both need `casberi://account` opened after launch).
- `-theme.light` — AppStorage theme override; always pass explicitly for light/dark screenshots (the sim's stored value sticks) → docs/hooks/system.md · prd §204
- `-howItWorksCTA <s>` — lift the first-launch cover after a delay (`Screens/IntroCover.swift`) → docs/hooks/system.md · prd §620
- **The dock is CONTINUOUS — the fold tracks the scroll, folders open in place, the page follows the finger, press-and-slide picks (2026-09-05)** → docs/hooks/system.md · prd §621
- **The dock is flat chips on one glass slab, and nothing in the strip claims a touch.** A SwiftUI drag or long press on scroll content froze the strip's scroll (build 543), and `dock-selftest.sh` refuses one. The magnification wave rides the pointer on iPad/Mac only → docs/hooks/design.md · prd §660 · §662h
- **A category tap lands first, then springs its folder** → docs/hooks/design.md · prd §668
- **The dock's selection GLIDES and never leans (prd §667, 2026-09-10).** `SelectionTravel` pins the fill's and ring's travel to `DS.Motion.glide` (bounce 0); nothing in the strip reads the drag. An indicator that names a position takes `glide`, never a bouncy spring → prd §667
- **`.transaction { $0.animation = … }` rewrites EVERY transaction reaching a shape — guard on `t.animation != nil`** → docs/hooks/design.md · prd §673
- **`GestureGate` is the one fact about the hand (prd §666, 2026-09-09).** Any deferrable main-actor work — a sweep, a backfill, a reindex — `await GestureGate.idle()` first; `HitchMeter` measures every gesture's worst frame (Diagnostics + `hitch:` NSLog), read it before aiming a perf pass. The app opts into 120Hz via `CADisableMinimumFrameDurationOnPhone` → prd §666
- **A crown's line pays for its own range chips through `DSRoomChassis.crownChart(box:chips:)`.** The class: a fix applied to a shared template reaches only what goes through it, so check what still draws that shape by hand → docs/hooks/design.md · prd §720 · §688
- **Room figures derive EVERY dimension from `DSRoomChassis.figureSlot`, padding included, and every slot's content clears `gearColumn` (prd §665).** The vibenet census derived the inner height and padded outside it; two rows clipped. A devnet live state persists its last read and publishes once → prd §665
- **A chip tap lands in the category's room and springs its folder; a swipe walks individual rooms in dock order** → docs/hooks/design.md · prd §663
- **A category chip is a 52pt tile, glyph over word; a new category needs a row in `CategoryFold.glyphs`** → docs/hooks/design.md · prd §662
- **A room swipe: TRAVEL follows the finger, CARDNESS follows the TURN (2026-09-08). The card's corner/edge/scale/tilt/shadow rode `abs(x)/screenWidth` while a turn commits at 60pt, so the tilt shipped at 0.61° of its ruled 4°** → prd §648
- **The page is not clipped at rest and the bottom band paints no plate** (`dock-selftest.sh`) → docs/hooks/design.md · prd §677
- **The dock's folder touches the dock, a face rail sits above it, and the band's scrim ramps over a fixed 24pt** → docs/hooks/design.md · prd §649
- **The furnished demo is a MODE you enter and leave, not a dev-only seed** → docs/hooks/system.md · prd §217
- `-findProbe` — fill the composer and fire Find (prd §215, the composer's deterministic door): runs KeptAskComposers.search → docs/hooks/agent.md · prd §215
- `-openComposer` `-composerDraft` — open the composer empty (screenshots the ask chips); -composerDraft "<text>" → docs/hooks/agent.md
- `-oembedProbe` — ask an allowlisted host what a saved link IS, keylessly (prd §244, Model/OEmbed.swift), and NSLog every field → docs/hooks/bridges.md · prd §244
- `-keepAskProbe` — Kept asks (docs/agent-brief.md rulings 1/4/5/13, Model/KeptAskStore.swift, Model/KeptAskComposers.swift) → docs/hooks/agent.md
- `-byokKey` — store (or clear ALL) an agent key headlessly (Keychain via TokenVault) → docs/hooks/agent.md
- **The keyed agent got tools, a receipt, a model choice and a librarian** → docs/hooks/agent.md
- **The keyed agent stopped re-paying for its own prompt, learned to read a saved page, and got a ceiling** → docs/hooks/agent.md · prd §415
- **The agent rooms, past §367 — and the fold that already existed** → docs/hooks/agent.md · prd §418
- **External agents got two doors, and neither is a server** → docs/hooks/agent.md · prd §34
- `-ghWatchPerson` `-ghPeopleProbe` — Watching a PERSON on GitHub (prd §519, 2026-08-29): -ghWatchPerson "<username|@username|profile URL>" watches → docs/hooks/bridges.md · prd §519
- `-framesProbe` `-framesTxProbe` `-framesKeyProbe` `-framesPendingProbe` `-framesPasskeyProbe` — The Frames devnet (prd §548) → docs/hooks/devnets.md · prd §548 · §728 · §728d
- `-ghClientID <id>` — override the GitHub device-flow client id; `-ghDeviceProbe YES` — run the device-flow start and NSLog the user code (`Model/GitHubDeviceFlow.swift`).
- `-intentProbe "<query>"` — run the Shortcuts intents' shared matcher (`IntentCorpus.match` in `Model/CasberiIntents.swift`, grounding Search Casberi / Ask Casberi) and NSLog the hits.
- `-viProbe` — run the Visual Intelligence label→corpus matcher headlessly (VisualCorpusMatch → docs/hooks/system.md
- `-awayGap <hours>` — fake the librarian's away window (`Model/AppVisit.swift`); pair with `-answerProbe "while I was away"`.
- `-todayProbe` `-seedWalletHistory` — compose the Today brief (prd §166: the whisper's landing screen, and a keepable ask, kind == "today") over → docs/hooks/agent.md · prd §166
- `-briefLedger` — plant prior windows in the brief's memory (prd §214, Model/BriefLedger.swift: the 14-window record of what each → docs/hooks/agent.md · prd §214
- `-agentHintProbe` — force the agent HINT capsule past its spent flag (prd §550: one glass capsule above the agent bar, ONCE EVER → docs/hooks/agent.md · prd §550
- `-secretScanProbe` — run the credential tripwire (prd §277, Model/SecretScan.swift) and NSLog what it found: the KINDS plus → docs/hooks/system.md · prd §277
- `-keychainProbe YES` — NSLog the vault's storage-policy census, force `TokenVault.migrateToDeviceOnly`, then census again (counts only, never a value; prd §277).
- `-receiptsProbe` — dump the network receipts ledger (prd §277, Model/NetworkLedger.swift): one receipt| line per host actually → docs/hooks/system.md · prd §277
- `-metricsProbe` `-metricsForget` — what MetricKit has handed this app, one `metricKit|` line per Diagnostics line (`Model/AppMetrics.swift`). Always EMPTY on the simulator; delivery is a device check → docs/verify.md · prd §622
- **The phone's own perf numbers, on the phone — the same spans MetricKit histograms, read seconds after they happen (`-perfReadingsProbe` `-perfMeasure` `-perfForget`)** → docs/hooks/system.md · prd §623
- **The source room's light columns, behind an OS gate (`-sourceRoomLightColumns`, DEBUG) — the projection on iOS 26+ only, because a predicated partial fetch drops rows on 18.6** → docs/hooks/system.md · prd §623
- **Perf-readings self-test (scripts/perf-readings-selftest.sh, 2026-09-06)** → docs/verify.md · prd §623
- **Harness-exists audit (scripts/harness-exists-audit.py, 2026-09-08) — a check the pass runs that is not in the repo** → docs/verify.md
- **Rain-tiles audit (scripts/rain-tiles-audit.py, 2026-09-08) — rain when sources were asked or something arrived; call `refreshRooms()` when a list changed** → docs/verify.md · prd §655
- **Source-alias audit (scripts/source-alias-audit.py, 2026-09-08) — a renamed seat's old rows must still resolve to the seat** → docs/verify.md · prd §647 · §650
- **Background-launch audit (scripts/background-launch-audit.py, 2026-09-07) — the shell is not built for a scene connected in the background** → docs/verify.md · prd §642 · §642b
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
- **A mutation that changed nothing is not a passing mutation — it is one that did not run (scripts/mutation-liveness-audit.py, 2026-09-06)** → docs/verify.md · prd §627
- **A fetch or a Keychain read belongs in `onAppear`/`.task`, never in a body or a computed property a body reads (build 525)** → docs/verify.md · prd §628
- `-notifyProbe` — what would notify, WITHOUT notifying (prd §306, 2026-08-05, Model/NotifySweep.swift + Model/NotifyPlan.swift) → docs/hooks/system.md · prd §306
- **Notifications: `arrivals` defaults off and `alarms` on; the daily whisper is cut** → docs/hooks/system.md · prd §644 · §706
- `-vibenetCreateProbe` `-signerProbe` — what making a vibenet account WOULD do, without doing it (prd §530, 2026-08-30) → docs/hooks/devnets.md · prd §530
- **The vibenet top up claims IN THE APP** (`-vibenetFaucetProbe`) → docs/hooks/devnets.md · prd §553b
- **L2BEAT — the rails your money sits on, reviewed by somebody independent** → docs/hooks/bridges.md · prd §428
- **The Safe CO-SIGNER — a key that can sign and can never spend** (`-signerProbe`) → docs/hooks/wallet.md · prd §425
- `-wipeAccessProbe YES` — run the Data tray's Delete access internals and log before/after credential counts.
- `-fcRecasts` `-bskyReposts` — Social grew an INBOUND half (2026-07-31, prd §239) → docs/hooks/social.md · prd §239
- `-fcName` `-fcLikes` `-fcMentions` — Farcaster grew likes/mentions/channels/replies (2026-07-14, same keyless Snapchain node): -fcName → docs/hooks/social.md
- Social enrichment (2026-07-16, prd 81) — both networks, one pass through Model/SocialBridge.swift. → docs/hooks/social.md
- `-likersProbe` — Who liked your post (2026-08-07, prd §330, Model/SocialLikers.swift, -likersProbe YES) → docs/hooks/social.md · prd §330
- `-followsProbe` — Follow import (2026-07-16, prd 87) → docs/hooks/social.md
- `-bskyMentions` `-bskyReplies` — Bluesky mirrored the keyless parity set (2026-07-14, AT Protocol AppView): profiles + replies + mentions → docs/hooks/social.md
- **Screenshot OCR reads STRUCTURE on iOS 26** → docs/hooks/system.md · prd §282
- `-photoHealProbe` `-reingestPhotos` — run the Photos HEAL directly (the pass that OCRs, thumbnails, RETITLES and prunes) and NSLog photoHeal → docs/hooks/system.md
- `-photoVerbProbe` — what a screenshot's thing sheet OFFERS, and whether each offer can LAND (prd §275, 2026-08-02) → docs/hooks/system.md · prd §275
- **On-device intelligence, the librarian half** (`-embeddingProbe`) → docs/hooks/system.md · prd §282
- `-relatedProbe` — what the thing sheet shows UNDER a thing: relatedKept| (the earlier copy). The embedding neighbours are NOT drawn since prd §632 and are logged as a diagnostic count only → docs/hooks/system.md
- **The sheet draws the words the app holds (`enrichedText`), never what a model wrote** → docs/reading-spec.md · prd §645
- `-topicMapProbe` — the text treemap (prd §230, 2026-07-30; §247 widened it past Photos; §283 added Files), headless → docs/hooks/rooms.md · prd §230
- `-roomInsightProbe` — what a source's room LEADS with (prd §247, 2026-07-31) → docs/hooks/rooms.md · prd §247
- `-stripeRoomProbe` `-posthogRoomProbe` — the two room heads' readings line by line (prd §298, 2026-08-04; one NSLog per line, the -todayProbe truncation → docs/hooks/rooms.md · prd §298
- **The note THING SHEETS, past §366** → docs/hooks/rooms.md · prd §399
- `-journalRoomProbe` — the two JOURNAL room heads, year by year (prd §398, 2026-08-17, Model/JournalRoom.swift + → docs/hooks/rooms.md · prd §398
- **The journals' three shipped defects, fixed in the same pass** → docs/hooks/imports.md · prd §398
- `-peerRoomProbe` `-privacyPoolsRoomProbe` `-gnosisPayRoomProbe` — the three WALLET-RIDING room heads, line by line (prd §349, 2026-08-10; one NSLog per fill/row/spend → docs/hooks/wallet.md · prd §349
- `-instagramImport` — import an UNZIPPED Instagram export folder (prd §245, Model/InstagramImport.swift; screen → docs/hooks/imports.md · prd §245
- `-tiktokImport` `-tiktokFaces` — import a TikTok export (the user_data_tiktok.json file itself, or a folder holding it), -tiktokFaces <limit|YES> → docs/hooks/imports.md · prd §279
- `-xArchiveImport` — import an UNZIPPED X archive folder (prd §280, 2026-08-02, Model/XArchiveImport.swift; screen → docs/hooks/imports.md · prd §280
- **X joined OEmbed.endpoints the same day, and it is the inverse of the Instagram entry removed alongside it** → docs/hooks/imports.md · prd §280
- `-xLiveProbe YES` — X's live-notifications door, read with the person's own browser-session cookies via an in-app sign-in, not the paid public API §280 declined; swept from the foreground on `dueForHeal`'s ten-minute throttle since §737 (it had ONE caller, the page's button) → docs/hooks/bridges.md · prd §701 · §737
- `-igLiveProbe YES` `-igLiveSession` — Instagram's live door: notifications and saved posts with the person's own web-session cookies, and a live save FILLS the export's pointer by shortcode. Only a refusal clears the session; a checkpoint keeps it → docs/hooks/bridges.md · prd §726
- `-tiktokLiveProbe YES` `-tiktokLiveSession` — TikTok's live door: the Activity inbox with the person's own cookies, no signatures (measured). A dead session is a 200 with `status_code` 8; a read never marks anything read (`tiktok-live-selftest.sh`) → docs/hooks/bridges.md · prd §731
- **An X notice's post rides `quote`, NEVER `postText` (prd §704).** Row and sheet both LEAD with `postText`, so stamping it drops the news. `SocialSheet.Shape.notice`: after the words test, before the save fallback, gated on the RECORD → prd §704
- **Feeds (RSS + the four feed-follow bridges)** (`-feedFollow` `-feedHealthProbe`) → docs/hooks/bridges.md · prd §312
- **The reading rooms, past §312** → docs/hooks/rooms.md · prd §455
- **The vault (Obsidian)** (`-obsidianVault` `-obsidianProbe`) → docs/hooks/imports.md · prd §320
- **The folder a file is saved in (user feedback: "would be great to be able to press here and it takes you to folder where the file is saved") — the disc says the FOLDER since §736 (`Show in Receipts`), and the From row that carried it is deleted** (`-filesRevealProbe`) → docs/hooks/imports.md · prd §408 · §736
- **The email a mail row came from (user: "see how this says from your inbox? Can we make it so that if you tap it, it takes the user to the email in the inbox") — `message:` for Apple Mail (gated, unmeasured), `rfc822msgid:` for Gmail (ungated — an `https` URL cannot silently do nothing). The door is the DIAL's since §736; the From row §735 also wired is deleted** (`-mailOpenProbe`) → docs/hooks/bridges.md · prd §735 · §736
- **A connected folder's images could not be read at all, and iCloud was never why** (`-filesHealProbe`) → docs/hooks/imports.md · prd §604
- **Telegram, through the two doors §57 never weighed** → docs/hooks/bridges.md · prd §456
- `-rssFeed` `-chatgptImport` `-claudeImport` — follow a feed and sync headlessly; -chatgptImport <path> → docs/hooks/imports.md
- `-trelloKey` `-trelloProbe` `-tokenBridge` — Trello (2026-08-03, prd §291, Model/TokenBridges.swift's TrelloAuth + trello(); seat id trello, group Work) → docs/hooks/bridges.md · prd §291
- `-kalshiBookProbe` — the Kalshi browse room's read, PHASE BY PHASE (prd §287, 2026-08-03, KalshiWatch.diagnose) → docs/hooks/bridges.md · prd §287
- Dropbox (2026-07-27, Model/DropboxBridge.swift, Screens/DropboxScreen.swift) — a first-class → docs/hooks/bridges.md
- PostHog (2026-07-27, prd §223, Model/PostHogBridge.swift, Screens/PostHogScreen.swift) → docs/hooks/bridges.md · prd §223
- `-for` — Stripe (2026-07-31, prd §250, Model/StripeBridge.swift, Screens/StripeScreen.swift) → docs/hooks/bridges.md · prd §250
- Cursor (2026-08-04, prd §303, Model/CursorBridge.swift) — the cloud agents you launched, landing → docs/hooks/bridges.md · prd §303
- **The GitHub room is ONE FEED: row types are tags (`Model/GitHubRowTag.swift`), and watched repos and people scope it from a face rail (`github-rowtag-selftest.sh`)** → docs/hooks/bridges.md · prd §699
- **The App Store Connect ROOM** → docs/hooks/bridges.md · prd §324
- App Store Connect (2026-08-06, prd §323, Model/AppStoreConnectBridge.swift, screen → docs/hooks/bridges.md · prd §323
- Apple Wallet (2026-08-06, prd §313 + §317, Model/AppleWalletBridge.swift / AppleWalletRoom.swift / → docs/hooks/bridges.md · prd §313
- Peer (2026-07-17, prd 113; connect model superseded by §207, 2026-07-25) — the fiat↔crypto onramp → docs/hooks/wallet.md · prd §207
- Privacy Pools (2026-07-21, prd §162) — 0xBow's compliant-privacy pools, the second seat → docs/hooks/wallet.md · prd §162
- `-gnosisPayProbe` — Gnosis Pay (2026-07-26, prd §222) → docs/hooks/wallet.md · prd §222
- `-solNameProbe` `-solActivityProbe` — Wallet/Solana (2026-07-16, prd §85/§86) → docs/hooks/wallet.md · prd §85
- **Wei / Gwei names, and the router the six copies became** (`-weiNameProbe`) → docs/hooks/wallet.md · prd §597
- `-wcProjectID` `-wcConnectProbe` `-wcTimeout` — Wallet/WalletConnect (2026-07-16, prd 84) → docs/hooks/wallet.md
- `-prepareProbe` `-approvalProbe` — run the approval PREPARE path (prd 112, the preparing-surface ruling: reads and previews in-app, signatures → docs/hooks/wallet.md
- **A spam NFT mint is one you didn't sign, not one that's cheap** (`-nftOriginProbe`) → docs/hooks/wallet.md · prd §481
- `-exposureProbe` — the approvals card's whole reading (2026-08-03, prd §292, Model/WalletApprovalExposure.swift + …Source.swift → docs/hooks/wallet.md · prd §292
- `-connectionsProbe` — the address book's connections card (2026-08-03, prd §295, Model/AddressConnections.swift + …Source.swift, card → docs/hooks/wallet.md · prd §295
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
- **ONE ACTIVITY, ONE ROW — and Strava never wins (RULE, `Model/HealthRiders.swift`).** Records from different writers that start and run within 120s are one activity, and the survivor is whoever measured it (Garmin 2, other recorders 1, Strava 0). `health-riders-selftest.sh` drives it → docs/hooks/system.md
- `-hideDemoBanner YES` — leave the demo banner unmounted for App Store stills (DEBUG only; pair with `-demoEnter YES`).
- `-rainPulse <s>` — bump `ShellChrome.refreshPulse` after a delay (NSLogs `rainPulse: dealt N tiles`); deal rain only through `ShellChrome.rain(sources:)` → docs/verify.md · prd §655
- `-openSeaFeed` `-openSeaKey` — connects OpenSea (a comma-separated chain list like ethereum,base,optimism, or YES/empty for the defaults → docs/hooks/bridges.md
- `-geckoTrending` — connects GeckoTerminal (a comma-separated chain list like ethereum,base,solana, or YES/empty for the defaults → docs/hooks/bridges.md
- `-x402Lane` `-x402Probe` — the Circle x402 bridge (2026-08-06, prd §319, Model/CircleX402Bridge.swift; screen → docs/hooks/bridges.md · prd §319
- `-hfWatch` `-hfPapers` `-hfProbe` — the Hugging Face bridge (2026-08-03, prd §290, Model/HuggingFaceBridge.swift; screen → docs/hooks/bridges.md · prd §290
- `-spotifySession "<sp_dc>"` `-spotifyProbe` — the Spotify seat's session, and its chain link by link (prd §703, 2026-09-12) → docs/hooks/bridges.md · prd §703
- **A 200 from `open.spotify.com/api/token` is not a signed-in session (`isAnonymous`); only `.refused` clears the credential, and a 429 is `.throttled`** → docs/hooks/bridges.md · prd §711 · §711b
- `-stockWatch` — resolves each query on Stocktwits (keyless symbol search), watches the top match, and syncs → docs/hooks/bridges.md

Deep links: `casberi://home`, `casberi://feed`, `casberi://feed/type/<Tag>` (internal, no UI produces it, prd §269), `casberi://account`, `casberi://settings`, `casberi://thing/<id>`, `casberi://person/<Bluesky|Farcaster>/<handle>`, `casberi://ask?q=<question>` (the widgets' door, prd §382), `casberi://frames/sponsor?r=` (a payment request, prd §728c).

- **The widgets** → docs/hooks/system.md · prd §382

## SwiftUI/UIKit gotchas already paid for

- **A quick action is registered on the app delegate and DELIVERED to the scene delegate.** RULE: for any UIKit hook about the scene (quick actions, state restoration, cold-launch URL or activity), check which delegate the lifecycle delivers it to; getting it wrong fails silently → docs/gotchas.md · prd §377
- A background layer BEHIND a NavigationStack never shows through (opaque UIKit backing). Page backgrounds paint INSIDE each screen: `.dsPageBackground()` on the scroll container; List also needs `.scrollContentBackground(.hidden)`.
- **A feed row never carries a presentation of its own — one screen, one `.sheet`.** A `.sheet` inside a `List` row resolves to the same presenter and tears the thing sheet down mid-rise. Anything walkable in a row renders as context (`allowsHitTesting(false)`), and the walk lives in the sheet (`ThingSheetView.walkingTo`) → docs/gotchas.md
- **Decorative motion during a refresh must be CoreAnimation, not SwiftUI** (`Design/TileRain.swift`): ingests are `@MainActor`, so SwiftUI motion stutters exactly when it runs. One gesture deals one shower → docs/gotchas.md
- `UIGraphicsImageRenderer` defaults to device scale (3×) — pin `format.scale = 1` for downscale renders.
- A bare `Image().resizable().scaledToFill()` in a ZStack expands the ZStack to image size — pin in GeometryReader + `.clipped()`.
- A child `.gesture(DragGesture)` beats ScrollView vertical scroll entirely on device — use native `swipeActions`, never custom swipe DragGestures in scroll content.
- Silent `try?` on EventKit (and similar) writes swallows denials — surface outcomes via `ShellChrome.flash()`.
- **A SwiftData `#Predicate` using `.contains` on the `tags` array compiles and crashes at runtime.** Filter tag membership in Swift after the fetch; plain string-equality predicates are fine → docs/gotchas.md
- **Never key a `ForEach` on a persistent `@Model` property from a DERIVED array — the perpetual "crashes on different screens after an update/first sync" class.** Reading any stored property of a deleted/invalidated `Thing` traps inside SwiftData. A `ForEach` directly over a `@Query` is safe; one over a `.filter`/`.map`/`@State`-held array is NOT. **Six corollaries, each a shipped crash (builds 142, 150, 176, 177, 188, 250) — read them before touching a view or an `async` func that holds a `[Thing]`; the last two leave the view layer entirely** → docs/liveness.md · enforced by scripts/swiftdata-liveness-audit.py
- **`HomeRoute` is ONE ordered array bound to `NavigationStack(path:)` and resolved by one `navigationDestination(for: HomeRoute.Node.self)`.** Sibling `navigationDestination(item:)` bindings don't nest. A plain valueless `NavigationLink` pushes a frame `path` doesn't track, so a screen that may have something pushed on it enters through `route.path` → docs/gotchas.md
- **The first frame walks a deep SwiftUI tree and has overflowed the main stack three times.** `OTHER_LDFLAGS -Wl,-stack_size,0x800000` and `ENABLE_DEBUG_DYLIB = NO` are load-bearing. If it recurs, FLATTEN the composition tree, not more stack — a card at an eager screen head renders flat → docs/gotchas.md

- **Any `async` function handed the main `ModelContext` is `@MainActor`.** Walking it off main is a SIGSEGV that looks like the liveness class, so read the faulting thread's queue name first → docs/gotchas.md · prd §617
- **Nothing writes root-view `@State` on a scene-phase change, and the app-switcher cover is `Shell/PrivacyCover.swift`'s own `UIWindow`.** A backgrounded render is a watchdog kill (`privacy-cover-audit.py` check D) → docs/gotchas.md · prd §614
- **A background launch still connects the scene.** `BackgroundLaunch` asks the scene's `activationState`, never `applicationState` at launch, and the shell never unmounts (`background-launch-audit.py`) → docs/gotchas.md · prd §642 · §642b
- **Bind a room's `@Query` array ONCE per body pass.** Each read is a fetch plus a per-model snapshot, so never re-read it for a yes/no, an animation or a `.task(id:)` key (`query-read-audit.py`) → docs/gotchas.md · prd §646
- **A `List` behind a draggable sheet draws a BOUNDED number of rows (`Model/RowWindow.swift`)** — a sheet drag lays out its host on every offset → docs/gotchas.md · prd §657
- **Nothing inside a lock the main thread can contend may call out to observers.** A `UserDefaults` write posts its notification synchronously into SwiftUI's update lock, so persist through `Model/DefaultsWrite.swift` (`defaults-lock-audit.py`) → docs/gotchas.md · prd §721
- **The Safe room, six passes deep (2026-09-07) — the sign block READS the batch (`multiSend` is 96% of real Safe traffic and the co-signer refused every one), the head NAMES who it waits on, "ready to execute" respects the queue, the guard is stated, Gnosis becomes signable** → docs/hooks/wallet.md · prd §652
- **Launch, swipe, dock: work sat INSIDE the frames (2026-09-08) — strip walk off-main, room swap after the flight, no state per touch** → prd §651
- **A control that persists across a room change mounts on the shell (`MainSurface.roomControls`), never inside the `.id()` subtree it commands** → docs/gotchas.md · prd §357
- **`.fontWeight()` after `.dsText()` does override the weight — measured, not assumed** → docs/gotchas.md

- **Every `NLEmbedding` compute call goes through `EmbeddingIndex.serialized { }` — one serial queue for every model, never an `NSLock`** (`ondevice-selftest.sh`, build 281) → docs/gotchas.md · prd §282

- **A `private` nested type reached from another file only through a signature crashes swift-frontend.** Open every nested type a moved signature mentions → docs/gotchas.md · prd §718

## Design law (read docs/build-brief.md §8 before UI work)

- Trays are NEVER hand-rolled — use `DSTray(title:height:)` (`Design/DSTray.swift`).
- Liquid Glass on the floating layer only (composer/FAB/toasts) — never on content. There is no tab bar (prd §100); older rulings that narrate one are historical → docs/hooks/design.md
- No letter-spacing, no ALL-CAPS eyebrows — headers are words in sentence case ("Getting started", never "G E T T I N G  S T A R T E D" or "GETTING STARTED"). `.kerning()` is banned; the type ramp carries hierarchy by size/weight alone (ruling 2026-07-08).
- No hairlines — zero exceptions; nothing draws a line. Widget/tile radius = `DS.Radius.widget`. **The catalog is rows (what you could add) and the sources tray is tiles (what you have); keep that split** → docs/hooks/design.md · prd §518
- **The day divider is the one line of type in the brand pink (`DS.brandInk`), and the cover card is not.** The hue is the app's own voice, so it never lands on a thing's title, a figure, or a `deckFill` ground (~1.8:1) → docs/hooks/design.md · prd §740
- **Every pour is ink — `DS.pourInk`, one token.** Colour that says what is happening stays; colour that says where it came from goes → docs/hooks/design.md · prd §524
- Apps Browse categories follow prd §59 (X under Social, Slack under Work, Notes its own category); the taxonomy is `Model/BridgeCatalog.swift`, mirrored on the website.
- Typed text in the composer NEVER saves — things enter only via capture paths (paste chip, mic, share, screenshots, drop, bridges). Saving is an outcome the toast reports, never a verb.
- Swipe verbs are reads only (writes live in the sheet, with consent). Feed chips only when they differentiate.
- **A row that names a place is a BUTTON, or it is deleted — the “From” row is gone from every sheet (prd §736).** The dial already carried a door for every kind it named a place for, so the row was the same fact twice with the weaker half on top. The two facts it alone held are the words on those doors: `Show in Receipts`, and the wallet’s own name on `Verb.Action.openAddress`. A disc’s glyph says it opens something; its word says where you land (`dialLabel` strips `“Show in ”`) → docs/hooks/design.md · prd §736
- **Honesty rule: no dead controls, no fake status (prd §83).** A hand-painted button swaps its background when disabled; never quote a price off a stale trade; a change that rounds to zero has no sign or colour. "End-to-end encrypted" requires Advanced Data Protection — don't overclaim → docs/hooks/design.md
- **The Mac takes its own point scale — `DSTextStyle.macScale = 0.88`, one lever.** `DS.Face`/`DS.Mark` and the `widget*` rungs opt out (`design-ramp-audit.py` check 5) → docs/hooks/design.md · prd §631
- **A walked row on the Mac can be taken with ⌘C, Space and drag-out, through one resolver (`Shell/MacRowHandoff.swift`)** → docs/hooks/design.md · prd §631
- Product rulings live in docs/prd.md — check it before re-litigating a design decision; record new rulings there.

## Website (casberi.app)

- **RULE: every app added to the catalog also lands on the website in the same session** — a hero marquee tile, a `#catalog` shelf cell and an `.ai-<name>` background — then bump the `?v=` cache-busters, zip `website/`, deploy through cPanel, and `rm` then `cp` the zip to `~/Downloads/website-deploy.zip` → docs/website.md
- **RULE: `BridgeCatalog.offers` is the single source of truth for the app catalog, the website catalog and both marquees**, enforced by `scripts/catalog-sync.sh`; a marquee name must equal its offer name exactly → docs/website.md
- **RULE: a new bridge is not done until its API hosts are in `Model/NetworkReach.swift`** (prd §205). `network-reach-audit.sh` is a ship gate. A host built at runtime names a declared family; a host the person types names its service through `NetworkLedger.record(host:as:)` → docs/verify.md
- **RULE: website icons are inlined as base64 data URIs — never hot-link a remote image** → docs/website.md

## Working mode

Goal-by-goal with user review checkpoints. Build + verify on simulator before presenting. The user rules on design; run `/code-review` on the diff before their checkpoint so mechanical findings don't consume it.
