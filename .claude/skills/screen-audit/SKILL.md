---
name: screen-audit
description: Full state audit of the Casberi app — build, walk every screen via deep-link/probe hooks, screenshot, and report drift against the PRD and design system. Use when asked to audit screens, check app state, or run the recurring sweep; also suitable for scheduled/non-interactive runs (no computer-use needed).
---

# Screen audit

Recurring sweep that catches regressions between working sessions. Everything runs through `simctl` + launch-arg hooks — **never computer-use** (blocked in scheduled runs).

## Procedure

1. **Build + baseline sweep**: run `scripts/verify.sh`. It builds (correct derivedData path), boots the iPhone 17 Pro sim, installs, screenshots home/feed/apps, and runs the headless answer probe. If the build fails, stop and report the error — that IS the finding.

2. **Extended screen walk** — for each, terminate the app, relaunch with the hook plus `-onboarded YES` (skips first-launch onboarding; omit only when auditing onboarding itself), wait ~4s, `xcrun simctl io booted screenshot <name>.png`:
   - Settings: `-openSettings YES`
   - Data tray: `-accountDetail data` (add `-openSettings YES`)
   - Fresh-user onboarding + empty states: `-fresh YES` (then relaunch with `-fresh NO` to restore)
   - Thing sheet: `-deeplink casberi://thing/latest` (opens the newest thing's sheet — no id needed)
   - Project detail: `-openProject "Work" -openProjectDelay 10` (launch on `casberi://home`), then wait ~20s before the shot. The delay pushes the screen after Home has settled — the real "tap into a project" path; pushing at t=0 (no delay) races Home's launch stream + the zoom transition and can catch the composition mid-entrance, which reads as a false regression.
   - Product page: `-openApp "GitHub"`, then `xcrun simctl openurl booted casberi://account` after launch (the hook needs the Apps page mounted)
   - Bridge setup: `-openSetup "Readwise"` (token field), then `xcrun simctl openurl booted casberi://account` — repeat for `"RSS"` (feed URL) and `"Bluesky"` (handle) to cover the three setup-screen shapes
   - Notes import (build 29, prd §55): `-openSetup "Day One"` (`DayOneImportScreen`), `-openSetup "Apple Journal"` (`JournalImportScreen`), `-openSetup "Apple Notes"` (`NotesShareScreen`), each then `xcrun simctl openurl booted casberi://account`. Headless ingest probes: `-dayoneImport <path>`, `-journalImport <path>`.
   - Diagnostics: `-openSettings YES -openDiagnostics YES` (the sheet runs the cover-photo + token-chart paths on-device and prints each step). Grant permissions first (`xcrun simctl privacy booted grant all com.casberi.app`) — Diagnostics requests Photos/Calendar and the ask dialog otherwise overlays the shot.
   - App-shaped screens (visit when the corpus/connection makes them reachable; name any you couldn't reach so the gap is explicit): Wallet (`WalletScreen`), Dexscreener (`DexscreenerScreen`), Steam (`SteamScreen`), Twitch (`TwitchScreen`), Mail (`MailScreen`), Obsidian (`ObsidianScreen`) — reached by tapping their feed/source rows, or watch surfaces headlessly via `-watchToken <addr>` / `-walletAddress <0x…>`; plus the ChatGPT import (`-chatgptImport <path>`) and pair-client (`PairClientSheet`, `-openPair YES`) flows.
   - Synthesis answer: `-uiAnswerProbe "what's my week"`
   - Lookup answer: `-uiAnswerProbe "what did I save about work"` (cold inference can exceed the ~4s wait — the headless probe from step 1 is the source of truth for the result; the screenshot may catch it mid-stream)
   - Light mode: relaunch each of home/feed/apps with `-theme.light 1` (the app themes from its own AppStorage, NOT the system — `simctl ui booted appearance light` does NOT flip it and yields dark shots mislabelled "light"). Restore by relaunching without the flag (or `-theme.light 0`).
   - Dynamic Type XXL: `xcrun simctl ui booted content_size extra-extra-large`, re-sweep, then restore `medium` (note the underscore in `content_size`)

3. **Review each screenshot against the law**:
   - `docs/build-brief.md` §8 + CLAUDE.md "Design law" (no hairlines — zero exceptions since prd §39, 2026-07-10: the Apps CONNECTED strip + `fillLine` divider died, the catalog is one grid; no glass on content, tray grammar, no dead controls, no fake status)
   - `docs/prd.md` rulings — flag any screen contradicting a recorded ruling
   - Empty/denied/unavailable states render honestly (no blank panes, no lying copy)

4. **Doc-drift check** — the docs and this skill can fall out of sync with each other and with the app; drift is a finding like any other:
   - CLAUDE.md "Design law" digest vs `docs/prd.md` rulings: read both, flag any rule the PRD has superseded but the digest still states (or vice versa).
   - Walk-list coverage: compare `Casberi/Casberi/Screens/` and the hook list in CLAUDE.md against step 2's walk list — flag any screen or hook the audit never visits.
   - `git log --oneline -5 -- docs/ CLAUDE.md` — if the law changed recently, say so in the report so findings are read against the right version.

5. **Report**: a short findings list ordered by severity — regressions first, then honesty violations, then polish. Each finding names the screenshot file and the doc/ruling it violates. No findings = say so plainly. Do NOT fix anything during an audit run unless asked; findings go to the user (or the session report) for triage.

## Notes

- Screenshots land in `scripts/output/<timestamp>/` (gitignored).
- The sim inherits the host Mac's Apple Intelligence state — "model unavailable" on a fresh host is environment, not regression.
- Schema changes wipe the sim install (theme resets to Blue/dark, demo corpus reseeds) — note it in the report so theme drift isn't misread as a bug.
