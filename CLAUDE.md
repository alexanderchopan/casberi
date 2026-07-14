# Casberi

Native iOS app — a personal corpus of "things" (links, screenshots, events, chats, voice notes, agent outputs) with on-device generative UI synthesis. Solo project, pre-App Store (Developer Program enrollment pending).

## Repository & working directory (RULE)

- **The canonical working copy is `~/Developer/casberi` — NOT iCloud Drive.** Always work here. The old iCloud copy (`.../myStuff/product/casberi`) is deprecated; do not edit it.
- Backed by a private GitHub remote `origin` → https://github.com/alexanderchopan/casberi. A `post-commit` hook auto-pushes to `origin` in the background on every commit (off-site backup) — so `git commit` alone keeps the backup current; a manual `git push` is only needed if a push failed while offline (see `.git/last-autopush.log`). Commit workflow is unchanged otherwise: solo, straight to `main`, no branches/PRs required. Note: committing/pushing to `main` is NOT a release — releasing is the separate archive+upload step (`scripts/testflight.sh`).

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

- **iCloud copy only (deprecated):** building inside the iCloud folder **fails codesign** ("resource fork, Finder information, or similar detritus not allowed"; `com.apple.provenance` xattrs are SIP-protected). There, add `-derivedDataPath "$HOME/Library/Developer/CasberiDD"`. Not needed from `~/Developer/casberi`.

- Test device: **iPhone 17 Pro** simulator, iOS 26 runtime.
- FoundationModels (on-device LLM) is iOS 26-only at **runtime** — `#if canImport` is not enough, use `if #available(iOS 26.0, *)`. `@Generable` schema types MUST be file-scope (nesting one in a private enum emits broken keypaths → heap corruption crashing on unrelated threads).
- There is currently **no test target** — the GenParser tests from early sessions were never persisted. If adding tests, create a proper unit-test target.

## Simulator gotchas

- Typing via computer-use `type` triggers the macOS accent-picker. Instead: `printf "text" | xcrun simctl pbcopy booted`, then cmd+a, Delete, cmd+v.
- Sim switches don't respond to computer-use clicks — drag across the knob.
- Dynamic Type: `xcrun simctl ui booted content_size` (underscore).
- Launch args do NOT trigger `onOpenURL` — use the `-deeplink` hook below, or `xcrun simctl openurl booted casberi://...`.
- Computer-use approval is blocked in scheduled/non-interactive runs — drive the app via launch-arg hooks + `simctl` there.
- Installing for probes: pick the NEWEST DerivedData (`ls -dt ~/Library/Developer/Xcode/DerivedData/Casberi-*` — plain `ls -d` is alphabetical and served a day-old binary for 30 minutes on 2026-07-14). `runAll` NSLogs `probeArgs:` with the launch args it saw — if that line is missing or stale, you're running the wrong binary.
- On a fresh sim install the demo seeds re-ask Photos/Calendar/Health permission at launch, and the queued sheets block everything (probes still run, but the UI is unusable and Health's ask stalls its probe). Pre-grant what simctl can (`xcrun simctl privacy booted grant photos com.casberi.app` — AFTER install; uninstall wipes grants) and tap the Health sheet once via computer-use; grants then persist for every later headless run.

## DEBUG launch-arg hooks

All read via UserDefaults in `Shell/RootShell.swift` unless noted:

- `-deeplink <casberi://url>` — open a deep link on launch.
- `-answerProbe "<query>"` — run the answer path headless, NSLog the result (`-probeDelay <s>` to wait first).
- `-uiAnswerProbe "<query>"` — auto-open the composer and send through the real UI path (also read in `Shell/Composer.swift`).
- `-mcpProbe "<query>"` — MCP probe.
- `-noPrewarm` — skip model session prewarm.
- `-fresh YES|NO` — sticky new-user mode (persists until flipped or reinstall); re-shows onboarding.
- `-accountDetail <case>` — open a settings detail sheet (`Screens/AccountScreen.swift`).
- `-openSettings YES` — pushes the settings screen. **Unreliable since the tab-bar-drop shell redesign (`0764ee3`, 2026-07-13):** it sets `route.push=.settings` in Home's onAppear, which gets dropped during launch (lands on Home). Use `-deeplink casberi://settings` instead (the post-mount deep link navigates reliably). Same for anything that pairs with it (`-openDiagnostics`, `-accountDetail`, `-openBanner`).
- `-icloud.sync YES` — AppStorage override for the sync toggle copy.
- `-onboarded YES` — AppStorage override that skips first-launch onboarding (fresh installs otherwise land on it, hiding the screen you deep-linked to).
- `-openApp "<Offer name>"` — open a store product page; `-openSetup "<Offer name>"` — push a bridge's setup screen (both need `casberi://account` opened after launch); `-openProject "<Tag>"` — push a project detail (`Screens/AccountScreen.swift` / `HomeScreen.swift`).
- `-theme.light 0|1` — AppStorage theme override; always pass explicitly for light/dark screenshots (the sim's stored value sticks).
- `-demoPick "Photos,Calendar"` — onboarding: mark those offers connected and continue (`Screens/OnboardingView.swift`).
- `-openComposer YES` — open the composer empty (screenshots the ask chips); `-linkTitleProbe <url>` — NSLog the fetched page title; `-forceTools YES` — show probe-gated composer tool tiles in the sim, where their apps can't be installed (also read in `Shell/Composer.swift`; screenshot/video staging only).
- `-byokKey <[provider:]key|clear>` — store (or clear ALL) an agent key headlessly (Keychain via TokenVault). The key is an AGENT key now (ruling 2026-07-14): providers `anthropic` (default for bare keys), `openai`, `google`, `venice` — e.g. `-byokKey "venice:vk-…"`; the last saved becomes the active provider. `-byokProbe "<query>"` — run the keyed answer path (retrieve → device→provider API → doc) on the ACTIVE provider and NSLog the result — with a bogus key it verifies the honest-failure path (HTTP 401 → nil) without spending anything. All four providers live in `Model/AgentAnswer.swift` (AgentProvider/AgentKey/AgentAnswer; ClaudeKey/ClaudeAnswer are gone). Settings detail: `-accountDetail key` (segmented Claude/ChatGPT/Gemini/Venice picker). Venice ALSO connects as a store bridge (`Screens/VeniceSetupScreen.swift`) — same vault key, seat id `venice`.
- `-ghClientID <id>` — override the GitHub device-flow OAuth client id (empty shipped id = the GitHub setup screen shows paste-only); `-ghDeviceProbe YES` — run the device-flow start request and NSLog the user code (or the honest unavailable line). The GitHub sign-in UI lives in `Screens/TokenSetupScreen.swift`; the flow in `Model/GitHubDeviceFlow.swift`.
- `-writeProbe "todoist:<id>"` or `-writeProbe "<github issue/PR url>"` — perform a bridge write-back (`Model/BridgeWrites.swift`) with the stored token and NSLog the honest outcome (no token → the not-connected line; bad token → the API's no). Write verbs surface only in the thing sheet, behind the confirm.
- `-intentProbe "<query>"` — run the Shortcuts intents' shared matcher (`IntentCorpus.match` in `Model/CasberiIntents.swift`, grounding Search Casberi / Ask Casberi) and NSLog the hits.
- `-awayGap <hours>` — fake the librarian's frozen away window (`Model/AppVisit.swift`) so the "While I was away?" chip and answer verify headlessly (pair with `-answerProbe "while I was away"` or `-openComposer YES`). The real window freezes at foreground: last background → this open, minimum 1h.
- `-wipeAccessProbe YES` — run the Data tray's "Delete access" internals (TokenVault.deleteAll + MCPPairing.reset) and log sampled before/after credential counts. (Ruling 2026-07-13: delete THINGS and delete ACCESS are two verbs — the Data tray carries both, each stating what goes and what stays.)
- `-rssFeed <url>` — follow a feed and sync headlessly; `-chatgptImport <path>` — import a ChatGPT conversations.json; `-claudeImport <path>` — import a Claude conversations.json; `-geminiImport <path>` — import a Google Takeout MyActivity.json (Gemini Apps; one chat thing per prompt); `-dayoneImport <path>` — import a Day One export .json; `-journalImport <path>` — import an unzipped Apple Journal export folder; `-healPhotos YES|seed-dangling` — run the screenshot heal sweep (seed-dangling plants a dangling ref first); `-seedThing "Source:delay"` — land a link thing for a source after a delay (flips the chip's new-ring live); `-bskyHandle <handle>` — connect Bluesky; `-tokenBridge "<Name>:<token>"` — connect a token bridge (Readwise/GitHub/Todoist/Raindrop/Cal.com/Calendly/Notion/Linear); `-watchToken <address|symbol|link>` — watch a crypto token via Dexscreener; `-walletAddress <0x…>` — watch a wallet; `-userSearch "<bluesky|farcaster>:<query>"` — log people-search hits; `-tokenSearch <query>` — log token-search hits. Each NSLogs a probe result.
- `-pinSource <source>` — pins that APP to Home (waits up to 5s for an async ingest hook to land the source's first thing first) — headless test of the pinned app tile. Pinning is per-app now (prd 58k): the tile shows the source's recent things in its shape, not a single pinned item.
- `-pinWallet YES` — pins the wallet's holdings treemap to Home (pair with `-walletAddress`).
- `-openDiagnostics YES` — open the Diagnostics sheet (pair with `-openSettings YES`); it runs the cover-photo and token-chart paths on-device and prints each step.
- `-connectPhotos YES` — runs the real Photos connect+ingest headlessly; `-reingestPhotos YES` — calls the bare re-scan (no permission request) that `BridgeRefresh` now runs each foreground.
- `-connectStrava YES` — runs the Strava connect: the Health-store read filtered to workouts whose `sourceRevision` names Strava (no Strava account/OAuth anywhere — its seat rides Apple Health, 2026-07-14). On the sim expect "connected, 0 in" (empty Health store; a Strava-written workout can't be seeded there — end-to-end needs a real device).
- `-berryPulse <s>` — bumps `ShellChrome.refreshPulse` after a delay: plays the pull-to-refresh delight (avatar-door spin + `BerryRain`) without a gesture, for headless verification and recordings. NSLogs "berryPulse: dealt".
- `-setHomeBanner <swatch-name|photo>` — sets the Home banner headlessly (e.g. `Teal`, or `photo` for a synthetic photo); `-openBanner YES` — open the Banner tray (pair with `-openSettings YES`).

Deep links: `casberi://home`, `casberi://feed`, `casberi://feed/type/<Tag>`, `casberi://account` (→ apps; the tab bar is gone — this pushes the Apps door), `casberi://settings` (→ settings; the reliable route since `-openSettings` broke), `casberi://thing/<id>`.

## SwiftUI/UIKit gotchas already paid for

- A background layer BEHIND a NavigationStack never shows through (opaque UIKit backing). Page backgrounds paint INSIDE each screen: `.dsPageBackground()` on the scroll container; List also needs `.scrollContentBackground(.hidden)`.
- `UIGraphicsImageRenderer` defaults to device scale (3×) — pin `format.scale = 1` for downscale renders.
- A bare `Image().resizable().scaledToFill()` in a ZStack expands the ZStack to image size — pin in GeometryReader + `.clipped()`.
- A child `.gesture(DragGesture)` beats ScrollView vertical scroll entirely on device — use native `swipeActions`, never custom swipe DragGestures in scroll content.
- Silent `try?` on EventKit (and similar) writes swallows denials — surface outcomes via `ShellChrome.flash()`.
- The Home board's drag-to-reorder input layer is UIKit (`Design/BoardDragDriver.swift`, 2026-07-13) — one custom recognizer on the enclosing UIScrollView, NOT SwiftUI gestures. Three lessons paid for if touching it: (1) per-card SwiftUI gestures can't fix scroll-vs-drag arbitration — the pan eats drags and a CANCELLED drag fires no `.onEnded`, leaking state (four failed repair commits: 9ab40ac, 7cb10a9, 9dc5ead, 7932d0c); (2) target-action on a recognizer attached to SwiftUI's UIScrollView fires only INTERMITTENTLY — the custom subclass must deliver its own callbacks from its touch handlers/lift timer; (3) SwiftUI Buttons carry a touch-down recognizer that force-fails an exclusive ancestor recognizer ~40ms into a hold — the driver holds a failure requirement over everything but the scroll pan (`shouldBeRequiredToFailBy`) so a hold on a button-backed tile survives to lift. Also: Home defers `streamComposition` while `boardEditing` (a recompose mid-drag replaces the modules under the lifted card).
- The first frame walks a deep SwiftUI tree (~200 stacked ForEach/preference/modifier internals); on the default 1MB main-thread stack it intermittently overflowed AT LAUNCH — EXC_BAD_ACCESS, "excessive recursion" in `swift_getGenericMetadata`, worst on the first launch after `simctl install`. It LOOKS like infinite recursion; it isn't (the trace bottoms out at `CasberiApp.$main` with no repeating cycle). Fixed 2026-07-10 at 4MB; RECURRED 2026-07-13 (the board's tree deepened past the 4MB margin — crash report `Casberi-2026-07-13-223557.ips`, stack-guard hit mid GenWidget render, user saw it as "crashes loading Home at the recent items step"). Now `OTHER_LDFLAGS -Wl,-stack_size,0x800000` (8MB main stack) + `ENABLE_DEBUG_DYLIB = NO` (the flag only applies to main executables; Xcode's debug-dylib stub isn't one). Don't remove either without re-running ~10 install+cold-launch cycles; if it recurs AGAIN, the real fix is flattening the composition tree, not more stack.

## Design law (read docs/build-brief.md §8 before UI work)

- Trays are NEVER hand-rolled — use `DSTray(title:height:)` (`Design/DSTray.swift`).
- Liquid Glass on the floating layer only (composer/FAB/toasts) — never on content. (The tab bar was dropped in `0764ee3` (2026-07-13): one surface now, a Pinned-first source-chip header + a FAB, no tabs. prd §61/§63 text still says "tab bar" — stale.)
- No letter-spacing, no ALL-CAPS eyebrows — headers are words in sentence case ("Getting started", never "G E T T I N G  S T A R T E D" or "GETTING STARTED"). `.kerning()` is banned; the type ramp carries hierarchy by size/weight alone (ruling 2026-07-08).
- No hairlines — zero exceptions (2026-07-10: the Apps page's CONNECTED strip and its divider died; the catalog is one grid where connected tiles wear state and open management). Nothing draws a line. Widget/tile radius = `DS.Radius.widget`.
- Apps Browse categories follow prd §59 (2026-07-11): X browses under **Social** (with Bluesky, Farcaster, Telegram) — a social account first, not a saves source; Slack browses under **Work** (with GitHub, Linear, Notion) — a workplace tool, not a messenger; and **Notes** is its own category (Apple Notes, Day One, Apple Journal, Obsidian) — the vault is notes, not project tracking. Taxonomy lives in `Model/BridgeCatalog.swift`; website Browse sections mirror it in the same session.
- Typed text in the composer NEVER saves — things enter only via capture paths (paste chip, mic, share, screenshots, drop, bridges). Saving is an outcome the toast reports, never a verb.
- Swipe verbs are reads only (writes live in the sheet, with consent). Feed chips only when they differentiate.
- Honesty rule: no dead controls, no fake status. The iCloud-sync ship gate is MET (2026-07-07): CloudKit capability is in the build, voice audio rides the store (externalStorage → CKAsset), Delete everything purges the CloudKit zone, and only the app process mirrors (extensions use `SharedStore.extensionContainer()`). "End-to-end encrypted" claims still require Advanced Data Protection — don't overclaim.
- Product rulings live in docs/prd.md — check it before re-litigating a design decision; record new rulings there.

## Website (casberi.app)

- RULE (user, 2026-07-08): every app added to the catalog ALSO lands on the website in the same session — (1) a tile in the hero marquee (`website/index.html`, the `.rain` div; continue the animation-delay sequence and keep `ai-more` last), (2) a `.mini-cell` in the `#catalog` section's matching shelf (rebuilt 2026-07-14 as packed shelf cards mirroring `AppsScreen.categories`, Markets last; ruling 2026-07-14: the website lists NO "Soon" apps — an offer the app can't connect simply isn't on the site), (3) an `.ai-<name>` brand background in `website/styles.css`. Then deploy: FIRST bump the `?v=` cache-busters on every page that links `styles.css`/`app.js` (index/features/docs) whenever those files changed — shipping new CSS/JS under an old `?v=` serves returning browsers yesterday's files against new markup (bare single-column catalog, invisible hero cards; paid for 2026-07-14). Then zip `website/` (exclude `mock-*.html` and any stray `.zip`) and push via Namecheap cPanel (File Manager → upload to the site root → Extract; see the web-deploy memory). If the deploy can't be run from the session, prepare the zip and hand the user the exact steps — never leave the site trailing the app catalog.
- RULE (user, 2026-07-08): website icons are ALWAYS inlined as base64 data URIs in `website/index.html` — NEVER hot-link an external `<img src="https://cdn.simpleicons.org/…">` (or any remote image host). External icon hotlinks intermittently render as blank slots when the CDN hiccups / is rate-limited / is ad-blocked. To add an icon: fetch it from `cdn.simpleicons.org/<name>/ffffff` (or wherever), then inline the bytes as `data:image/svg+xml;base64,…` (or PNG base64). Every `<img>` on the site must be self-contained; there should be zero remote image requests.

## Working mode

Goal-by-goal with user review checkpoints. Build + verify on simulator before presenting. The user rules on design; run `/code-review` on the diff before their checkpoint so mechanical findings don't consume it.
