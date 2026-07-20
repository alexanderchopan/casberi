# Build brief — Casberi (working name)

Handoff target: Claude Code. Source of truth: prd.md. Visual spec: composer-rest-chips-v94.html / .tsx — the prototype is spec, not codebase. This brief tells the builder what to build, in what order, and where the decisions live.

## 1. Product

One home for a person's things. Notes, screenshots, chats, events, links land as things; the system clusters them into projects, synthesizes state on Home, records events in Feed, and hands writes to the apps that own them. Target: Bob (consumer, iPhone, one agent app, zero operate budget). Alice (power user) ships later as load — thing kinds, bridge kinds, S10, S11 — on this build. No persona, no "I", no thinking indicators: agency renders as results.

## 2. Stack

- Swift, SwiftUI, SwiftData. Things live on device.
- CloudKit for sync. No server holds things.
- EventKit, PhotoKit, Contacts, Reminders through frameworks. The Shortcut pack died with the platform call; App Intents replace staged hand-offs.
- Share extension, Siri, App Intents, widgets carry capture.
- Thin server: Google bridges (OAuth), agent calls, the composition model. Server sees queries and bridge traffic, never the corpus.
- TestFlight validates; the store launches. Apple Developer Program: $99/yr.

## 3. Data model

**Thing.** id, kind, title, content, source, createdAt, capturedAt, mark, tags[], pinned, provenance { app, agent?, run?, machine? }. Kinds at v1: note, screenshot, chat, event, link, reminder, mail, file, voice. Schema leaves room for Alice kinds: job, run, output, skill. Rule from run 2: a job is one thing — prompt, output, approval, writeup under one record. Granularity guard: steps never become things.

**Mark.** todo, doing, done, saved, suggested, none. Things enter unmarked. Inference proposes through suggest rows; one tap admits, one dismisses.

**Tag.** Three sources: type tags (system, at ingestion), project tags (system, through clustering; person renames), user tags (thing detail + composer parse card). Project membership rides a tag. A tag with zero things dies. No tag management screen.

**Project.** Computed cluster: name, sources, synthesis line, thing count, tint fill at opacity scaled by count, stable across sessions. The person renames or pins; the person never files.

**App (bridge).** id, name, kind (apple | google | agent), status (ok | attention | paused), capabilities as sentences, askBeforeActing (default on), recent things.

**Composition.** Line-oriented document authored by the model per moment; cached last-good per surface for offline paint.

## 4. Server API surface

- `POST /compose` — moment context in, composition document out as a stream. Serves Home, composer answers, approval sheets.
- `POST /parse` — composer input in, parse card out: chip label + fields + candidate tags.
- `GET/POST /bridges/google/*` — OAuth flow, calendar + gmail reads, writes per proven capability.
- `POST /agent/*` — agent labor calls. v1: ChatGPT import path.
- No `/things`. The corpus stays on device and iCloud.

## 5. Gen UI engine (port)

Port `src/genui/engine.tsx` to Swift: parser + stream + renderer. Component library: Stack, Hero, Insight, Bento, ProjectTile, Tile, PhotoTile, VoiceTile, Widget, Row, Chip, Shelf, Suggest, Skeleton, StatTile, TagMap, AnswerStream. Laws: the renderer mounts a component when its line parses; string props fill as tokens arrive; declared children render as skeletons until their lines resolve; unresolved references drop from arrays; any prefix of any document renders. Load rule: generated surfaces stream; records paint.

## 6. Write model (v1 = rungs 1–2)

- Rung 1 — writes to us: tags, marks, pins, projects.
- Rung 2 — hand-off writes: thing detail opens the source app to the item, or runs an App Intent (Add Event, Add Reminder), gated by ask-before-acting. The hand-off is the write.
- Rung 3 (per bridge, as proven) — Google over OAuth; agents over keys.
- Rung 4 (waits on 3) — agent labor behind approvals.

## 7. Shell and screens

**Superseded (kept below only for the derivation-pattern bullets that still hold; the tab bar, the Account-row Apps door, and the composer-as-rest-pill this section originally described are all gone).** The tab bar died first (prd §100, `0764ee3`, 2026-07-13) — one surface, a source-chip header, no tabs. The board that survived the tab-bar drop as Home's replacement then died itself (prd §131, docs/agent-brief.md rulings 11–12, 2026-07-20) — there is no "Home" screen anymore, in any form.

**The shell today:** one `NavigationStack` (`Shell/MainSurface.swift`) under a fixed `SourceChips` header — a catalogue-door chip (opens Apps), then **All** leading, then one chip per connected source, most-recent-first. Tapping a chip pages the one scrolling feed (`FeedScreen`) to that source via `TabView`; re-tapping the active chip pops to root. The avatar (top-right, `TopDoors`) is the only other door, opening Settings. Apps and Settings both push onto the same stack — no separate tab roots to reconcile.

The **agent** rides above all of this, on the floating glass layer (`Shell/AgentBar.swift`, `Shell/Composer.swift`), not inside `MainSurface`'s stack — it survives every push (Apps, Settings, a bridge setup screen). A tap raises it to a full-screen surface: a greeting, then the kept-ask chips (each a saved question with a deterministic composer and a changed-signal dot), then the ask bar. Tapping into an answer pushes a generative thing-view *inside* the agent (the Stack session model, docs/agent-brief.md ruling 8); ✕ or the bar's own ⌄ lowers it back to exactly where you were. This is the board's old per-app glance job, carried by chips instead of a scrollable arrangement — see docs/agent-brief.md for the full ruling record.

Screens with specs in the PRD: the **All feed** (day groups; row = source icon, title, tag, time; verb lines live in the thing sheet; the Themes treemap leads when the chip is All; swipe marks), a **source feed** (the same day-grouped rows, shaped to that source — Calendar reads like an agenda, Photos a grid, a wallet leads with its balance/treemap/NFTs), Apps (pushed from the header's catalogue door: state rings; broken sorts first; swipe Reconnect/Remove; detail with capabilities as sentences; catalog by value; connect ends in proof), Settings (tile workspace: two labeled tile groups, "You" then "App" — A–Z within each, uniform tiles; subline states the setting in force; detail holds the control; one fact per row), the **agent surface** (greeting; kept-ask B1 pill chips with signal lines; the ask bar; AnswerStream for free-text asks; a kept ask never routes through the model — prd/agent-brief ruling 1), Thing sheet (header morph; content by kind; verbs card — derivation ranks, cap three; one Tags field; Related shelf streams last).

**Screens as derivations** — each names its pattern and content; no mockups:
- Settings details (Data, Theme, Language, Diagnostics, agent key, GitHub, How it works): pattern = sheet with one control cluster; content per the Settings tile it opens from.
- Empty states (the All feed, a source feed, Apps): pattern = the surface's own choreography with skeletons; content points to the first action.
- Permission asks (calendar, photos, contacts, notifications, mic): pattern = in-context sheet at the moment of unlock; copy names what the person controls; never a settings route.
- Onboarding: ONE screen (prd §96, 2026-07-16 — supersedes the original three value cards and the later connect screen): the "How it works" greeting wearing the icon rain, its one door landing in the Apps catalog, where connecting happens for real.
- Remove app: sheet with keep-or-purge choice.
- Approval sheet (post-v1, S10): gen UI composition — diff, scope, agent, target; approve or block.

## 8. Design system

Tokens port from `src/index.css` to a Swift token layer. Components hold zero raw hex. Surfaces: #000 page, one sheet token `--ds-surface-sheet` (#111113 dark, #fff light) for cards, tiles, trays; washes dead. Tint: systemBlue dark #0A84FF, one-line swap; pink one line away. Color rule: identity, state, or magnitude; decoration banned; magnitude = tint at opacity scaled by count. Text ramp: white / 60% / 30%. No hairlines: rows separate by spacing and press fills, groups by their card surfaces; nothing draws a line — zero exceptions (prd §39, 2026-07-10: the Apps page's connected strip and its `fillLine` divider died; the catalog is one grid). Elevation is carried by tone AND a soft ambient shadow — never by a line (prd §61, 2026-07-12, the elevation ladder): cards lift off the page (`DS.cardShadow` via `dsWidgetSurface`/`dsCard`), inset-grouped sections lift as one card (`dsListCardRow` — gapless rows hide interior shadows), and nested backings recess by tone (`DS.surfaceWell`). A shadow is not a hairline; the no-line rule stands. Headers are sentence case — no ALL-CAPS eyebrows, no `.kerning()`. SF ramp: 34/22/17/15/13/12/10 (display tier is SF Rounded, functional text SF Pro — 2026-07-09). Radii: cards 10, sheets 16, app icons 22.37%. Motion: 250ms, Apple sheet curve, one animation per moment; hero morph tile→detail uses matchedGeometryEffect. Copy: Bob's words — no sync, scope, token, connector, OAuth where he sees it (the token-bridge setup screens name "token" deliberately — an Alice-facing power surface, not where Bob sees it).

## 9. Gap list (carry from prototype)

1. Home topic blocks route to Feed tag filter; they must open project detail.
2. A widget whose children all drop must drop itself (connection filtering).
3. Light mode: photo-background legibility unchecked.
4. Mic: icon present; capture unwired. Native: speech framework through the parse.
5. Hero morph approximated in web; native uses matchedGeometryEffect.
6. App icons: letter tiles stand in; real assets per store guidelines.

## 10. Analytics

Usage renders to the person as synthesis (StatTile); facts only — no streaks, no goals, no guilt mechanics. Telemetry: default off, consent in Privacy detail, no third-party trackers. The Privacy row's "End-to-end encrypted" line ships when the build proves it.

## 11. Milestones

- M0 — project scaffold, token layer, tab shell, demo corpus.
- M1 — SwiftData model, CloudKit sync, capture paths (share extension, screenshots, paste).
- M2 — gen UI engine port; Home streams from cached compositions; server /compose.
- M3 — Feed: paint from store, filters, treemap, marks, pins.
- M4 — Thing sheet: content by kind, verbs card with App Intents, tags field. Rung 2 proves here.
- M5 — Apps: EventKit connect end-to-end (connect ends in proof), Google OAuth through server, ChatGPT import.
- M6 — Composer: parse card, save, AnswerStream, mic.
- M7 — Account, empty states, permission asks, polish pass against the anti-pattern list.
- TestFlight at M5; store after M7.

## 12. Rules the build keeps

Every value routes through a token. One signature moment per screen; before shipping a screen, remove one thing. Rows carry status. Settings hold nothing. Reads pass, writes confirm. Verbs derive; menus die. The record paints; synthesis streams. Offline: reads and capture work without a network.
