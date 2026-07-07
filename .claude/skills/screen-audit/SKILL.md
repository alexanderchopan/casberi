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
   - Thing sheet: `-deeplink casberi://thing/<id>` (grab an id from the demo corpus via the answer probe log)
   - Synthesis answer: `-uiAnswerProbe "what's my week"`
   - Lookup answer: `-uiAnswerProbe "what did I save about work"`
   - Light mode: `xcrun simctl ui booted appearance light`, re-sweep home/feed/apps, then restore `dark`
   - Dynamic Type XXL: `xcrun simctl ui booted content_size extra-extra-large`, re-sweep, then restore `medium` (note the underscore in `content_size`)

3. **Review each screenshot against the law**:
   - `docs/build-brief.md` §8 + CLAUDE.md "Design law" (no hairlines, no glass on content, tray grammar, no dead controls, no fake status)
   - `docs/prd-draft-v3.md` rulings — flag any screen contradicting a recorded ruling
   - Empty/denied/unavailable states render honestly (no blank panes, no lying copy)

4. **Report**: a short findings list ordered by severity — regressions first, then honesty violations, then polish. Each finding names the screenshot file and the doc/ruling it violates. No findings = say so plainly. Do NOT fix anything during an audit run unless asked; findings go to the user (or the session report) for triage.

## Notes

- Screenshots land in `scripts/output/<timestamp>/` (gitignored).
- The sim inherits the host Mac's Apple Intelligence state — "model unavailable" on a fresh host is environment, not regression.
- Schema changes wipe the sim install (theme resets to Blue/dark, demo corpus reseeds) — note it in the report so theme drift isn't misread as a bug.
