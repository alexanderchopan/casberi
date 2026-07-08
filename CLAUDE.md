# Casberi

Native iOS app — a personal corpus of "things" (links, screenshots, events, chats, voice notes, agent outputs) with on-device generative UI synthesis. Solo project, pre-App Store (Developer Program enrollment pending).

## Layout

- `Casberi/Casberi.xcodeproj` — the Xcode project. Targets: **Casberi** (app), **ShareExtension** (appex), **CasberiWidgets** (widget bundle). Bundle id `com.casberi.app`; app group `group.com.casberi.app`.
- `Casberi/Casberi/` — app sources (`Design/`, `GenUI/`, `Model/`, `Screens/`, `Shell/`).
- `Casberi/Shared/` — sources compiled into both app and extension targets.
- `docs/` — **build-brief.md §8 (design system) is law**; prd.md carries product rulings; name-ledger.md.
- `prototype/` — visual spec. `design/app-icon/` — icon SVG sources.
- The pbxproj is **hand-authored** (objectVersion 77, file-system-synchronized groups). New source files in synced folders are picked up automatically; Info.plist keys and target settings are edited directly in the pbxproj.

## Building (critical)

The repo lives in iCloud Drive — building inside it **fails codesign** ("resource fork, Finder information, or similar detritus not allowed"; `com.apple.provenance` xattrs are SIP-protected). Always:

```sh
xcodebuild -project Casberi/Casberi.xcodeproj -scheme Casberi \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath "$HOME/Library/Developer/CasberiDD" build
```

Or just run `scripts/verify.sh` (build + install + screen sweep + answer probe).

- Test device: **iPhone 17 Pro** simulator, iOS 26 runtime.
- FoundationModels (on-device LLM) is iOS 26-only at **runtime** — `#if canImport` is not enough, use `if #available(iOS 26.0, *)`. `@Generable` schema types MUST be file-scope (nesting one in a private enum emits broken keypaths → heap corruption crashing on unrelated threads).
- There is currently **no test target** — the GenParser tests from early sessions were never persisted. If adding tests, create a proper unit-test target.

## Simulator gotchas

- Typing via computer-use `type` triggers the macOS accent-picker. Instead: `printf "text" | xcrun simctl pbcopy booted`, then cmd+a, Delete, cmd+v.
- Sim switches don't respond to computer-use clicks — drag across the knob.
- Dynamic Type: `xcrun simctl ui booted content_size` (underscore).
- Launch args do NOT trigger `onOpenURL` — use the `-deeplink` hook below, or `xcrun simctl openurl booted casberi://...`.
- Computer-use approval is blocked in scheduled/non-interactive runs — drive the app via launch-arg hooks + `simctl` there.

## DEBUG launch-arg hooks

All read via UserDefaults in `Shell/RootShell.swift` unless noted:

- `-deeplink <casberi://url>` — open a deep link on launch.
- `-answerProbe "<query>"` — run the answer path headless, NSLog the result (`-probeDelay <s>` to wait first).
- `-uiAnswerProbe "<query>"` — auto-open the composer and send through the real UI path (also read in `Shell/Composer.swift`).
- `-mcpProbe "<query>"` — MCP probe.
- `-noPrewarm` — skip model session prewarm.
- `-fresh YES|NO` — sticky new-user mode (persists until flipped or reinstall); re-shows onboarding.
- `-accountDetail <case>` — open a settings detail sheet (`Screens/AccountScreen.swift`).
- `-openSettings YES` — push the settings screen.
- `-icloud.sync YES` — AppStorage override for the sync toggle copy.
- `-onboarded YES` — AppStorage override that skips first-launch onboarding (fresh installs otherwise land on it, hiding the screen you deep-linked to).
- `-openApp "<Offer name>"` — open a store product page; `-openSetup "<Offer name>"` — push a bridge's setup screen (both need `casberi://account` opened after launch); `-openProject "<Tag>"` — push a project detail (`Screens/AccountScreen.swift` / `HomeScreen.swift`).
- `-theme.light 0|1` — AppStorage theme override; always pass explicitly for light/dark screenshots (the sim's stored value sticks).
- `-demoPick "Photos,Calendar"` — onboarding: mark those offers connected and continue (`Screens/OnboardingView.swift`).
- `-rssFeed <url>` — follow a feed and sync headlessly; `-chatgptImport <path>` — import a conversations.json; `-bskyHandle <handle>` — connect Bluesky; `-tokenBridge "<Name>:<token>"` — connect a token bridge (Readwise/GitHub/Todoist/Raindrop/Cal.com/Calendly/Notion/Linear). Each NSLogs a probe result.

Deep links: `casberi://home`, `casberi://feed`, `casberi://feed/type/<Tag>`, `casberi://account` (→ apps tab), `casberi://thing/<id>`.

## SwiftUI/UIKit gotchas already paid for

- A background layer BEHIND a NavigationStack never shows through (opaque UIKit backing). Page backgrounds paint INSIDE each screen: `.dsPageBackground()` on the scroll container; List also needs `.scrollContentBackground(.hidden)`.
- `UIGraphicsImageRenderer` defaults to device scale (3×) — pin `format.scale = 1` for downscale renders.
- A bare `Image().resizable().scaledToFill()` in a ZStack expands the ZStack to image size — pin in GeometryReader + `.clipped()`.
- A child `.gesture(DragGesture)` beats ScrollView vertical scroll entirely on device — use native `swipeActions`, never custom swipe DragGestures in scroll content.
- Silent `try?` on EventKit (and similar) writes swallows denials — surface outcomes via `ShellChrome.flash()`.

## Design law (read docs/build-brief.md §8 before UI work)

- Trays are NEVER hand-rolled — use `DSTray(title:height:)` (`Design/DSTray.swift`).
- Liquid Glass on the floating layer only (composer/tab bar/toasts) — never on content.
- No hairlines — one exception: the Apps page draws a single `fillLine` divider between the CONNECTED strip (management) and Discover (store), per docs/prd.md:491. Nothing else draws a line. Widget/tile radius = `DS.Radius.widget`.
- Typed text in the composer NEVER saves — things enter only via capture paths (paste chip, mic, share, screenshots, drop, bridges). Saving is an outcome the toast reports, never a verb.
- Swipe verbs are reads only (writes live in the sheet, with consent). Feed chips only when they differentiate.
- Honesty rule: no dead controls, no fake status. The iCloud-sync ship gate is MET (2026-07-07): CloudKit capability is in the build, voice audio rides the store (externalStorage → CKAsset), Delete everything purges the CloudKit zone, and only the app process mirrors (extensions use `SharedStore.extensionContainer()`). "End-to-end encrypted" claims still require Advanced Data Protection — don't overclaim.
- Product rulings live in docs/prd.md — check it before re-litigating a design decision; record new rulings there.

## Website (casberi.app)

- RULE (user, 2026-07-08): every app added to the catalog ALSO lands on the website in the same session — (1) a tile in the hero marquee (`website/index.html`, the `.rain` div; continue the animation-delay sequence and keep `ai-more` last), (2) a cell in the bottom catalog section (the matching `<h3>` group), (3) an `.ai-<name>` brand background in `website/styles.css`. Icons come from `cdn.simpleicons.org/<name>/ffffff` when available. Then deploy: zip `website/` and push via Namecheap cPanel (File Manager → upload to the site root → Extract; see the web-deploy memory). If the deploy can't be run from the session, prepare the zip and hand the user the exact steps — never leave the site trailing the app catalog.

## Working mode

Goal-by-goal with user review checkpoints. Build + verify on simulator before presenting. The user rules on design; run `/code-review` on the diff before their checkpoint so mechanical findings don't consume it.
