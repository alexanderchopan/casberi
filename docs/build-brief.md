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

Tab bar: glass capsule — Account, Home, Feed — sharing one axis with the composer's rest button (amendment: the full-width rest pill died). Tap morphs the button's glass into the composer bubble. Landing: Home. Phone frame in the prototype is demo chrome; drop it.

Apps lost its tab (amendment). The page moves behind a row in Account: the row leads the A–Z list, subline states the state in force ("6 connected · 1 needs attention"), tap opens the page. The page keeps its spec — rings, attention sorts first, swipe Reconnect/Remove, catalog, connect ends in proof. Bridge breakage surfaces as a badge on the Account tab icon and the Apps row subline (the Feed row was cut on review).

Screens with specs in the PRD: Home (composition per moment; hero rule; evening TagMap), Feed (day groups; row = source icon, title, tag, pin, time; verb lines live in the thing sheet; tag treemap; swipe marks; Pinned section), Apps (page behind the Account row: state rings; broken sorts first; swipe Reconnect/Remove; detail with capabilities as sentences; catalog by value; connect ends in proof), Account (tile workspace: two labeled tile groups, "You" then "App" — A–Z within each, uniform tiles; subline states the setting in force; detail holds the control; one fact per row), Composer (rest pill chips; bubble expand origin 100% 100%, radius 24/24/10/24; parse card; AnswerStream for search intent; mic routes voice through the parse; close clears draft), Thing sheet (header morph; content by kind; verbs card — derivation ranks, cap three; mark control; one Tags field; Related shelf streams last).

**Screens as derivations** — each names its pattern and content; no mockups:
- Account details (Data, Privacy, Subscription, Theme, Usage, Support, Updates): pattern = sheet with one control cluster; content per PRD Account section.
- Empty states (Home, Feed, Apps): pattern = the surface's own choreography with skeletons; content points to the first action.
- Permission asks (calendar, photos, contacts, notifications, mic): pattern = in-context sheet at the moment of unlock; copy names what the person controls; never a settings route.
- Onboarding: three value cards, each one tap, each skippable; skip-all leaves the composer working.
- Remove app: sheet with keep-or-purge choice.
- Approval sheet (post-v1, S10): gen UI composition — diff, scope, agent, target; approve or block.

## 8. Design system

Tokens port from `src/index.css` to a Swift token layer. Components hold zero raw hex. Surfaces: #000 page, one sheet token `--ds-surface-sheet` (#111113 dark, #fff light) for cards, tiles, trays; washes dead. Tint: systemBlue dark #0A84FF, one-line swap; pink one line away. Color rule: identity, state, or magnitude; decoration banned; magnitude = tint at opacity scaled by count. Text ramp: white / 60% / 30%. SF ramp: 34/22/17/15/13/12/10. Radii: cards 10, sheets 16, app icons 22.37%. Motion: 250ms, Apple sheet curve, one animation per moment; hero morph tile→detail uses matchedGeometryEffect. Copy: Bob's words — no sync, scope, token, connector, OAuth where he sees it.

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
