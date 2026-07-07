# PRD — Casberi Personal Assistant

## Contents

1. [Thesis](#1-thesis)

**Users and goals**

2. [Users](#2-users)
3. [Goals (shared, verb-noun)](#3-goals-shared-verb-noun)
4. [Persona variables](#4-persona-variables)

**The world today**

5. [How it works today — Bob](#5-how-it-works-today--bob)
6. [How it works today — Alice](#6-how-it-works-today--alice)
7. [Outcomes — Bob (evidence)](#7-outcomes--bob-evidence)
8. [Outcomes — Alice (evidence)](#8-outcomes--alice-evidence)

**Problems and solutions**

9. [Problems](#9-problems)
10. [Solutions](#10-solutions)
11. [Bob vs Alice, per feature](#11-bob-vs-alice-per-feature)
12. [Run 2 synthesis](#12-run-2-synthesis)

**The build**

13. [Features](#13-features)
14. [Platform](#14-platform)
15. [Write model](#15-write-model)

**Surface specs**

16. [Shell](#16-shell)
17. [Home spec](#17-home-spec)
18. [Feed spec](#18-feed-spec)
19. [Thing sheet](#19-thing-sheet)
20. [Tags](#20-tags)
21. [Projects](#21-projects)
22. [Marks](#22-marks)
23. [Generative UI](#23-generative-ui)
24. [Composer](#24-composer)
25. [Apps spec](#25-apps-spec)
26. [Account tab](#26-account-tab)

**Product principles**

27. [Analytics](#27-analytics)
28. [Do, distributed](#28-do-distributed)
29. [Automations](#29-automations)
30. [Voice](#30-voice)
31. [Hero rule](#31-hero-rule)
32. [Design principles](#32-design-principles)

**Status**

33. [Open items](#33-open-items)

## 1. Thesis

Doing creates things. Things land in apps. Apps multiply with the doing. Boundaries multiply with apps. Friction grows with boundaries — the producer pays for producing, and productivity funds its own decay. The market answers with agents, and each agent ships as an app: another container, another memory, another settings panel. The remedy repeats the disease.

The answer is one assistant that works across your apps instead of adding another one. It gathers what you make — notes, links, screenshots, bookings — into one place, and you find each thing by what it is, not by remembering which app you left it in. A quick capture doesn't stall as a capture; the assistant helps carry it through to done. Work from agents lands in the same place as everything else, so it stops mattering how many you run. And it gets better as you use it: related things group together on their own, and search has more to find. It's yours in the ordinary sense: things live on your phone, work without a connection, and leave only when you choose to send them.

## 2. Users

**Target: Bob.** The product is built for Bob first. Alice gets served later on the same app — not with new screens, but by extending what already exists: more kinds of things (jobs, runs, skills), more kinds of connections (agents, gateways, machines), plus the two features only she needs — approvals (S10) and machine status in Feed (S11). Her turn starts once connected apps have proven they can write reliably.

**Bob.** Young professional consumer. iPhone is his computer. Many apps — Notes, Calendar, Reminders, Messages among them. One agent app: ChatGPT on iPhone, Gemini on Android. Not Claude Code, Codex, or other developer agents. No tolerance for setup.

**Alice.** Power user. Runs agents as labor: Claude Code in a terminal, an OpenClaw-class gateway (software that runs and supervises agents across her machines), ChatGPT on the phone. Work spans machines — laptop, server, phone. She writes prompts, sets scopes, picks models. She tolerates setup when setup buys leverage. Her phone is a remote, not her computer. Bob consumes agent output; Alice operates agent labor.

## 3. Goals (shared, verb-noun)

1. Stay mobile — the phone completes the job.
2. Capture things — any thought, image, link, in the moment.
3. Organize things — order among the things.
4. Find things — retrieve by what a thing is.
5. Do things — finish tasks: plan, book, draft, schedule.
6. Own things — privacy as the default. Things live on the device, work offline, leave only by choice.

**Operate** is not a goal. Configure, direct, track, review — work on the machinery, not on things. Goals name outcomes; operate names what the person spends to get them. Every persona carries the six goals plus an operate budget. Tolerance is not desire: the product minimizes operate at every budget.

## 4. Persona variables

| Variable | Bob | Alice |
|---|---|---|
| Operate budget | Zero. Configure enters as cost | Large. Spends for leverage. Spend must accrue |
| Thing kinds | What he makes in apps | Plus what her machines make: jobs, runs, skills |
| Phone role | His computer | Her remote |
| Agent count | One | Many. Count stops mattering |
| New screens added | The baseline app is built for him | None. New data kinds and two features (S10, S11), no new screens |

## 5. How it works today — Bob

Bob runs two worlds on one phone.

**Apple world.** Capture: screenshots, Notes, Reminders via Siri, Messages to self, camera. Organization per app: folders, lists, albums. Retrieval: per-app search, Spotlight, Photos text recognition. Action by hand: copy, switch, paste, book in Safari.

**ChatGPT world.** Input: text, voice, photo, file, share sheet. Organization: threads, Projects, Library, Archived chats, Memory, GPTs. Retrieval: chat search, scroll, File Library. Action: drafting, web search, Deep Research, image generation, Tasks, apps directory behind OAuth. No connector for Apple Notes, Calendar, or Reminders.

**Onboarding.** ChatGPT opens to a composer and explains nothing after. Personalization, Memory, Apps, Data controls sit in Settings. Reaching goals 3–5 requires configuration the app never walks through.

## 6. How it works today — Alice

Alice runs four worlds across three machines.

**Apple world.** Same as Bob's — capture, per-app organization, Spotlight. Her phone adds a role: remote. She checks work from it; she starts work at a desk.

**Agent-app world.** ChatGPT or Claude on the phone. Same as Bob's, plus: she maintains prompts and projects with intent. Memory panels, custom instructions — she uses them.

**Terminal world.** Claude Code, Codex on laptop and server. Input: prompts, files, repos. Organization: directories, git, session logs. Retrieval: grep, scrollback, log files. Action: the agent edits, runs, commits. Output lands in the filesystem — none of it reaches the phone. A run finishes at 11pm; she learns the result at the desk, or she SSHes from the phone and reads a terminal at 390 points wide.

**Gateway world.** An OpenClaw-class layer: sessions, skills, instances, cron, approvals. Organization: its panels. Retrieval: its dashboards. Action: jobs run behind approvals. The gateway logs the system — device events, session state — not what she made. Approvals arrive wherever the gateway pushes them; if the notification is missed, the moment is gone.

**The seams.** Each world holds its own record of her labor. A job's prompt sits in the terminal, its output in a repo, its approval in the gateway, its writeup in a chat. Reconstructing one job means visiting four records. No search spans them. Her operate spend goes to the seams, not the leverage.

**Onboarding.** She does her own. Keys, scopes, configs — paid per machine, per agent, per update.

## 7. Outcomes — Bob (evidence)

1. Recipe in Notes, untitled. Not found. Not cooked.
2. Trip across three chats. Itinerary 40 messages deep. At the airport: scroll, give up, re-ask; new version drops the hotel address.
3. Workout plan screenshotted. At the gym: week one only.
4. Dentist reminder fires. Booking takes a call. Snoozed six times.
5. Dinner planned in ChatGPT. Date copied to Calendar, guests texted, booking in Safari. Guest list never leaves the chat.
6. ChatGPT Settings opened once. Nothing connected. Closed.
7. Book recommendation in a screenshot. In the bookstore: not surfaced.
8. Second agent downloaded. Two histories, two memories, two settings panels. Deleted in a week.

## 8. Outcomes — Alice (evidence)

1. Run finishes at 11pm on the server. She learns at 8am. The result sat nine hours; the follow-up job starts a day late.
2. Approval lands as a push. The diff exceeds the notification. She opens the gateway on the phone, reads a table built for a desktop, approves on trust. The write breaks a config; she reverts from the desk.
3. Three agents touch one repo in a week. She asks which one introduced the regression. The answer spans two session logs and a chat. Forty minutes to reconstruct.
4. She writes a skill for invoice parsing in March. In June a job needs it. She rebuilds it — the March version sits in a directory she forgot on a machine she retired.
5. A cron job dies. Nothing tells her. She notices the missing output a week on, from its absence, not from a record.
6. Job output: a report in the repo, a summary in the chat, a log in the gateway. She sends the client the chat version. It lacks the correction she made in the repo.
7. New laptop. Two days to restore keys, configs, scopes across agents. One scope stays wrong for a month; the agent reads and never writes; she blames the model.
8. Her phone holds ChatGPT. Her labor runs elsewhere. On the train she can prompt a chat and check nothing — the machines work; she waits for a desk.

## 9. Problems

One problem set, two rungs of the same ladder: Bob hits each problem at app scale, Alice hits the same one at machine-and-agent scale. The rest of the doc uses "rung" for a problem or feature at one persona's scale.

P1. **Mobile gets hard.** Bob: one app at a time, one screen. Tasks cross apps in series; content moves by copy → switch → paste. A five-step job costs four boundary crossings. Alice: the phone reaches nothing — she can't act on the machines from it. *(Alice 8)*

P2. **Capture betrays them.** Bob: each capture surface writes to its own container. The moment picks the container; the container is permanent. Alice: the machinery picks it. A job's output lands where the run happened — repo, log, chat. The seam chose. *(Alice 6)*

P3. **They can't organize.** Bob: order costs labor per container. Nothing spans containers. The agent adds containers of its own. Alice: one job scatters across four records — prompt, output, approval, writeup. No unit of "job" exists anywhere. *(Alice 6)*

P4. **They can't find.** Bob: retrieval starts with "which app." No search spans phone plus agent. Failure lands at the moment of use; he re-makes what he made. Alice: retrieval starts with "which world, which machine, which session." Provenance — which agent, which run — lives nowhere. Reconstruction is her labor. *(Bob 1, 2; Alice 3)*

P5. **They can't finish.** Bob: the agent writes nothing to Calendar, Reminders, or Notes. Output leaves the chat only by hand — copy, switch, paste — and those trips stall. Alice: writes block on her judgment. The approval arrives where she is; the context stays where the work is. She approves on trust or stalls the pipeline. *(Bob 4, 5; Alice 2)*

P6. **They won't configure — or the spend evaporates.** Bob: the agent's power sits behind unexplained settings in builder vocabulary. He opens the panel once, connects nothing, closes it. Alice: she configures and loses it. Keys, scopes, skills, configs — paid per machine, per agent, per update. Nothing accrues; March's skill holds no address in June. Same problem: operate spend against a product that banks none of it. *(Bob 6; Alice 4, 7)*

P7. **They won't add another agent — or pay for five.** Bob declines the second agent: another account, history, memory, settings. Alice runs five; she pays what he refused. Agents share nothing — each addition re-levies P3, P4, P6. Her stack is P7 as a bill. *(Bob 8)*

P8. **They aren't aware.** Push, where P4 is pull: the state exists and never arrives. Bob: what he keeps stays mute. The book rec sits in a screenshot as he stands in the bookstore; the workout plan holds week two. His corpus waits for a query he won't think to ask. Alice: her machines finish, fail, die — no signal reaches her. She learns by polling or by absence. The monitoring tax is P8 paid by hand. *(Bob 3, 7; Alice 1, 5, 8)*

## 10. Solutions

Features. Each names a mechanism; each shows both rungs where the mechanism differs.

**S1. One home for their things.** One container joins the containers. Bob: notes, screenshots, chats, events, links land as things. Alice: jobs, runs, outputs, skills join — a job is one thing: prompt, output, approval, writeup under one record. *(P2, P3)*

**S2. Find by what it is.** One search over the home. Bob: query by content, get the thing, not the thread. Alice: provenance as fields — source, agent, run, machine. "Which agent broke the build" is a query. *(P4)*

**S3. Capture in one gesture.** Bob: every capture surface routes here; no destination decision, no title, no folder. Alice: her machines capture for her — once connected, their output flows in on its own. *(P2)*

**S4. Captures become outcomes.** The thing carries its next action. Bob: writes exit through bridges; the connected app finishes the job. Alice: output lands in Feed; the follow-up job leaves from the sheet. The phone directs what the machines run. *(P1, P5)*

**S5. Setup accrues.** Bob's rung: zero setup — the app is useful before it asks for anything, permission requests arrive at the moment they unlock something, and onboarding never routes through settings. Alice's rung: pay once, keep it — keys, scopes, and skills are saved as things, so a new machine restores from what she already has. Ruling on secrets: the THING records that a credential exists (name, endpoint, scope, added-date) so setup is remembered and restorable; the secret itself lives only in the Keychain (iCloud Keychain carries it across devices). The thing is the address; the Keychain is the vault. Key rows render masked with Replace/Revoke; plaintext never renders anywhere. One bridge per credentialed endpoint; multiple agents behind a gateway are provenance fields on things, never extra rows. *(P6)*

**S6. Not another agent.** Presents as an organizer. No model picker, no memory panel, no persona. Agents are rows in Apps, labor in Feed. The sixth agent adds a row. *(P7)*

**S7.** Killed. It was web portability; the move to native made it moot, and its intent — the phone reaches the work — lives on in S4. The number stays so the list records the decision.

**S8. Feels like an Apple product.** iOS grammar in type, motion, touch targets, safe areas. Alice lives in terminals; the phone surface owes her nothing terminal. The polish is how S5 and S6 land: promises felt, not announced. *(rides P6, P7)*

**S9. Apps are bridges.** Adding an app builds the bridge: OAuth for web services, App Intents for Apple apps, a key or endpoint for agents, gateways, machines. Mechanism hidden, vocabulary theirs. Bridges come in three grades and each detail page states its grade truthfully: framework (live, on-device — Calendar, Reminders, Photos), account (live via OAuth — Gmail, Google Calendar), import (batch via official export — ChatGPT, Claude). Apps with no API (Apple Mail's app, Notes, Messages) are never listed as bridges; they reach Casberi through capture. *(P5, P6)*

**S10. Approvals carry context.** The ask arrives with what judgment needs — diff, scope, agent, target — rendered for the phone through the gen UI. Approve or block from the sheet. Bob: dormant; he grants no write that needs judgment. *(P5)*

**S11. State lands as things.** Run finished, run failed, cron died — each a Feed thing. An expected thing that fails to arrive is itself a thing. Bob's rung is parked: surfacing the right saved thing at the right moment (the book rec, in the bookstore) needs context signals the build doesn't have yet. *(P8)*

## 11. Bob vs Alice, per feature

| Feature | Bob | Alice |
|---|---|---|
| S1. One home | Notes, screenshots, chats, events, links land as things | Jobs, runs, outputs, skills join. A job is one thing |
| S2. Find by what it is | Query by content. The thing, not the thread | Provenance as fields: source, agent, run, machine |
| S3. Capture in one gesture | Every capture surface routes here | Machinery captures for her. The bridge is the gesture |
| S4. Captures become outcomes | The thing carries its next action. Writes exit through bridges | Output lands in Feed. The follow-up job leaves from the sheet |
| S5. Setup accrues | Zero setup. Value before permission | Pay once, bank it. A machine restores from the corpus |
| S6. Not another agent | Declines agent two. One history, one world | Runs five. Agent six adds a row |
| S8. Apple feel | His grammar — the phone is his computer | Her phone owes her nothing terminal |
| S9. Apps are bridges | OAuth for services, App Intents for Apple apps | Adds keys and endpoints: agents, gateways, machines |
| S10. Approvals carry context | — (grants no write that needs judgment) | Diff, scope, agent, target on the sheet |
| S11. State lands as things | Parked. Waits on context signals | Run finished, failed, died — Feed things. An absence is a thing |

## 12. Run 2 synthesis

The problems are one set at two magnitudes, so the features are one set at two loads. Bob and Alice differ in degree — count of agents, writes, records — not in kind. The primitives (thing, bridge, feed, sheet) absorb magnitude as data: more thing kinds, more bridge kinds, more rows. Surface count holds at zero.

"Works for Bob, therefore works for Alice" does not follow by itself. Magnitude breaks what kind does not. Three logged risks:

1. **Feed load.** Her machines emit state at volume. Feed at Bob's scale is a register; at hers it can become a firehose. Reversal trigger: if approvals pile up past what Feed can carry, the call reverses and a queue gets its own screen.
2. **Approval latency.** S10 puts judgment on a phone sheet. At five agents writing, the sheet may become her job. Same trigger.
3. **Thing granularity.** A run emits steps. If steps become things, S1 drowns. The job-as-one-thing rule is the guard, untested.

Bob proves the primitives; Alice stress-tests them. Build order stays Bob-first: his rung carries no load risk.

**Seed pool verdicts** — candidate screens surfaced by the OpenClaw audit, judged against Alice's needs:

- **Workboard — no screen of its own; the need rides existing surfaces.** Jobs are things; state lives in Feed; direction leaves from sheets. A work queue earns a tab only at the reversal trigger.
- **Skill Workshop — no screen of its own.** Skills are things (S5). Review is a Feed suggest-row: admit, dismiss. No panel.
- **Instances — cut entirely.** Machines connect like apps: a bridge with a state ring. No separate "node" concept ever appears in the UI.

Pool closes at zero surfaces.

## 13. Features

What ships, by surface. Specs for each live in the sections below.

### Shell
- Three tabs in a glass capsule: **Home**, **Feed**, **Account**. Landing tab: Home.
- **Composer** spans full width above the tab bar on every screen.

### Composer
- One field for search, ask, and capture. At rest: action chips (Ask, Open app, Open shortcut), search glyph, mic.
- **Parse card** — assembles under the words as you type; shows what will be saved, with editable fields and tags.
- **Ask** — a question streams an answer composed from your things (AnswerStream).
- **Voice capture** — mic routes speech through the parse; what you say becomes a thing.
- Save writes locally. Close clears the draft.

Answer path ruling (2026-07-05, built + verified on the iPhone 17 Pro sim): Ask is now two layers. A scoring engine always runs first — it fetches the corpus and ranks it (title 3× / tags 2× / content 1× + a freshness float), returning the top ~10 as the grounding set. This is the retriever AND the universal fallback: on any iPhone without Apple Intelligence, or if the model declines, those hits paint through the engine exactly as before — zero regression. On Apple-Intelligence iPhones the free on-device model (iOS 26 Foundation Models) then composes over the SAME retrieved things via guided generation: it returns a typed layout — one plain sentence plus the *indices* of the things that answer, most relevant first — which we render through the existing gen-UI engine (Insight + Widget + Rows). Two rails hold the honesty rule: the model may only choose among the retrieved things and summarize them, never invent one; and every row is painted from the real Thing (the model picks indices, never content), so a displayed record is always true. Verified end-to-end: "what did I save about work" → *"You saved about work related to design and invoice parsing."* + three real things picked from the corpus. Grounding stays strictly on-device — nothing leaves the phone, nothing is billed. Engineering note: the `@Generable` schema type must live at file scope; nesting it in a private type made the macro emit broken keypaths that corrupted the heap and crashed the process (the crash surfaced on unrelated threads, so it read as a SwiftData assertion — it wasn't).

Intent-routing + prose ruling (2026-07-05, built + verified in-app on the sim): the on-device answer now forks by intent, because a lookup and a reflection want different shapes. A lightweight router reads the query: a retrieval verb (find, search, show, save/saved, where, which, list) means LOOKUP and wins outright — even over a temporal cue, so "what did I save this week" stays a lookup; otherwise a reflection cue (what's my…, how was…, summar…, recap, overview, my week/day/month, catch me up, lately, highlights) means SYNTHESIS; unmatched defaults to lookup, because structure is the safer shape and it carries the strong honesty rail. LOOKUP keeps guided generation → the typed Insight+Widget+Rows above. SYNTHESIS uses `streamResponse`: a short plain summary that types itself into an Insight as tokens arrive (the composer paints each growing snapshot; no widget — prose is the answer). Grounding rail for prose is prompt-enforced, not structural — the model is handed only the retrieved things and told to use only them, never invent — which is a softer rail than the lookup's indices, and the reason lookups (where a wrong record would be a lie) stay on guided generation while synthesis (where the words are the point) may stream. The prompt forbids preamble and markdown so the prose reads as one plain paragraph. Fallback unchanged: no Apple Intelligence, empty set, or a model that declines → the scoring doc paints (zero regression). Verified in-app by driving the real composer: "what's my week" streamed a plain summary of the week's meal-prep, workout, and weekend things; "find what I saved about work" rendered the Insight+Widget+Row of the real mail thing. (Incidental fix found during this work: launch Spotlight reconcile was running on a detached background task with the main-actor `ModelContext`, which races the screens' own reads and crash-faults SwiftData intermittently — moved onto the main actor, where the fetch belongs and the CoreSpotlight calls are non-blocking anyway.)

Prewarm + session-lifecycle ruling (2026-07-05, built + verified on the sim): the first Ask otherwise pays a one-time model load. So on Apple-Intelligence iPhones we `prewarm()` the model at launch (and on every foreground) — non-blocking, idempotent, and only when the model is available, so it never delays launch or the reindex reconcile. What we prewarm is the MODEL, not a conversation: a single warm `LanguageModelSession` is held only to keep the model resident, and each Ask still runs on a FRESH session. That is the deliberate lifecycle call — Asks are independent, so reusing one session's transcript across them would leak one answer into the next as context and eventually overflow the context window; a fresh per-Ask session stays correct and, with the model already resident, is fast anyway. On background we tear the warm session down so the model's memory is reclaimed; the next foreground reloads it. Measured rough on the sim: ~1.8s cold vs ~1.5s warm for a lookup in the one run where the model was genuinely cold, and identical once warm — because the system's model daemon caches weights across app launches, so the sim understates the win; the real payoff is the true cold start (post-boot / after eviction) on device, where the load is seconds and prewarm moves it off the person's first question. Debug levers for this: `-noPrewarm` skips warming and `-probeDelay <s>` + the logged answer latency let the cold and warm paths be A/B'd.

### Capture
- **Share extension** — share from any app; the thing lands with no folder or title step.
- **Screenshot ingest** — connect Photos and screenshots flow in, permission asked in context.
- **Siri and App Intents** — capture by voice from anywhere on the phone.

### Home
- **Composition per moment** — the screen is authored fresh each open and streams in.
- **Hero** — one synthesis statement, facts provable from your things, linked things one tap away.
- **Insight** — one cross-source connection, under a "Noticed" eyebrow.
- **Projects treemap** (amendment: the tile bento died) — one interactive treemap, magnitude fill scaled by count, name-only cells; tap opens project detail. Home's map is projects (what you're doing); Feed's map is types (what things are).
- **Threads widget** — links the system found across apps.
- **TagMap** — evening composition leads with a map of what your things are about.

### Feed
- **The record** — every new thing paints instantly from the local store, newest on top; pull to refresh syncs.
- **Swipe marks** — swipe a row left for To do / Doing.
- **Pin** — toggle on the row; pinned rows hold a section above Today.
- **Filter chips** by source; **tag treemap** computed live — tap a tag to filter in place.
- **Status rows** — run finished, run failed, cron died land as rows; a bridge breaking sorts to top with the fix one tap away.

### Thing sheet
- **Verbs card** — Open in {source app}, Open shortcut, or a type-specific action (Add Event, Add Reminder), gated by ask-before-acting.
- **Tags field** — active tags lit, candidates dim, tap toggles; add-to-project rides the same field.

### Organization (no filing)
- **Projects** — computed clusters with a name, synthesis line, and sources; rename or pin, never file.
- **Tags** — type tags at ingestion, project tags from clustering, user tags from the sheet or parse card. No tag management screen.
- **Marks** — to do, doing, done, saved; set by swipe or tag, proposed by suggestion rows (one tap admits or dismisses).

### Search
- One search over everything, by what a thing is. Alice's rung adds provenance fields: source, agent, run, machine.

### Apps page (behind the Apps row in Account)
- **App rows** — icon in a state ring (green connected, orange fix, gray paused); broken sorts first; swipe to Reconnect or Remove.
- **App detail** — capabilities as sentences, ask-before-acting toggle, recent things, Pause/Resume, Remove with keep-or-purge.
- **Catalog** — apps grouped by value with verb taglines; agent, gateway, and machine kinds join for Alice.
- Every connect ends in proof: things land in Home.

### Approvals (Alice)
- The ask arrives as a phone-sized sheet with diff, scope, agent, and target; approve or block from the sheet.

### Account
- One fact per row, subline states the setting in force: Apps, Avatar, Connection, Data, Privacy, Subscription, Theme (5 tints, dark/light), Updates, Usage.

### Ownership
- Things live on device (SwiftData), sync through iCloud (CloudKit), no server holds them; reads and capture work offline. Telemetry default off.

## 14. Platform

Native iOS. The ownership goal decides it. Swift, SwiftUI, SwiftData, CloudKit: things on device, sync through iCloud, no server holds them. EventKit, PhotoKit, Contacts, Reminders through frameworks — the old Shortcuts-based workaround pack is no longer needed. Share extension, Siri, App Intents, widgets carry capture. A thin server remains for Google bridges, agent calls, and the composition model. TestFlight validates; the store launches. Costs logged: review gates releases, store cut on subscriptions, desktop waits for a Mac build, the prototype becomes spec.

## 15. Write model

Writes sit on a gradient — reworked for native.

Rung 1 — **writes to us:** tags, marks, pins, projects. Shipped.
Rung 2 — **hand-off writes:** the thing detail opens the source app to the item, or runs an App Intent (Add Event, Add Reminder) directly, gated by ask-before-acting. Going native merged the web era's two-step hand-off with the Apple half of bridge writes: opening the app or running the App Intent is itself the write.
Rung 3 — **bridge writes:** Google services over OAuth; agents, gateways, machines over keys and endpoints. Per capability, behind ask-before-acting.
Rung 4 — **agent labor:** jobs behind approvals (S10).

v1 ships rungs 1 and 2. Rung 3 ships per bridge as proven. Rung 4 waits on 3.

The composer is the query surface. A question returns a composition through the gen UI engine. Chips over the composer state capability. The parse card carries chip label plus fields; intent switch parked — the chip stays a label until the parse earns correction. Save writes to us. The product states what it does by showing it.

## 16. Shell

The composer rests as a glass button on the tab bar's axis (amendment: the full-width rest pill died — simpler shell, more reading room). Tap and the same glass morphs into the full composer bubble; placeholder: "Ask anything. Organize everything." Engaged, the composer still takes the surface (principle 4 holds). Tab bar: glass capsule — Account, Home, Feed — sharing the axis with the composer button. Landing: Home. The old "No FAB" rule meant a Material-style + stacked above the bar; the composer-at-rest button on the bar axis replaces the rest pill, not the composer. Liquid glass: translucent fills, backdrop blur, hairline highlight, content scrolls under. The phone frame seen in the prototype is demo chrome, not product.

Apps has no tab. The page lives behind a row in Account: the row leads the A–Z list, subline states the state in force ("6 connected · 1 needs attention"), tap opens the page. Bridge breakage surfaces in the Apps tile subline, in words ("1 needs attention", attention-colored) — the tab badge died on review (2026-07-04): a tab is navigation and carries no indicator; the state exists once and renders where the person manages it (P8).

## 17. Home spec

Composition per moment, authored by the model, streamed. Hero: one synthesis statement (see hero rule). Voice constraint: it speaks to themes and content, never obligations — nothing reads as "you should." Tile sublines read content, not status. Insight: one cross-source connection, "Noticed" eyebrow. Projects: an interactive treemap — magnitude fill, tap opens project detail (amendment: the tile bento died). Threads: a widget of links the system found across apps. Evening composition leads with a TagMap of topics ("What your things are about"). No task lists, no notification mirrors. Filters live in Feed. Empty state streams the same choreography with skeleton tiles. StatTile carries usage synthesis. Open question: topic blocks currently route to the Feed tag filter; they should open project detail.

## 18. Feed spec

Load rule: generated surfaces (Home, answers) stream in; record surfaces paint instantly. Feed is a record — it paints from the local store at once. New rows land at top with a mount rise. Pull to refresh runs sync. No stream ticker.

Row: kind glyph, title, project pill when the thing has one (type pills died — the glyph carries the kind), pin toggle, time. Rows carry no subtext; the verb line lives in the thing sheet only. Verb rule: place words, not system activity — "in your inbox", "on your calendar", "saved by you". One home per taxonomy (amendment): sources filter via the one chip row — text-only, ordered by thing count (importance decides position), never a dropdown (menus die); types filter via the treemap itself — tap a cell filters, the cell lights, tap again clears; projects live on Home (the project map → detail IS the project view); custom tags ride search and the thing sheet. No second chip row, ever. Treemap fill: tint at opacity scaled by count. Swipe left: the thing's derived OUTCOME verbs, cap two (reads pass, writes confirm); utilities like Copy never ride the swipe — they live in the sheet. Marks left the swipe (amendment): to-do/doing read ambiguous — pin is the MVP triage. Marks resolved (amendment): the taxonomy (todo/doing/saved) leaves the UI entirely for MVP — pin is the triage, Done survives as an outcome verb (completion is an event, not a category). The schema keeps the enum for future inference via suggest rows. Pin: toggle on the row; pinned rows hold a Pinned section above Today. No read state. Tap opens the thing. Approvals ship per bridge capability with the do-verb build.

Bridge breakage does not land in Feed (cut on review): it surfaces in the Apps tile subline only (tab badge cut — tabs carry no indicators); the broken bridge sorts first on the Apps page.

**Raycast (graded 2026-07-05):** no public user-data API — chats and notes are not readable, so Raycast is NOT a feed bridge (closed reads, same grade as ChatGPT/Claude live access). The integration runs the other way: Raycast is an MCP client on Mac and iOS (HTTP servers supported), so Casberi's Goal-3 server ships an MCP surface (save_thing / search_things / week_synthesis) and Raycast — and every other MCP client — connects to us. Their feature set also settled two design questions: AI Commands on content (Summarize, Improve, Change Tone) validate verbs-on-things as Goal-3 candidates; their embedded multi-model chat presets are the "another container" disease and are refused.

**Feed re-ruling (2026-07-04): a feed is a feed.** The type treemap left Feed for Home, reborn as the kind bar (one stacked strip — what your things ARE — segments and legend tap through to the filtered Feed; FeedFilter carries the state, casberi://feed/type/<Tag> routes it). Feed keeps exactly: the machine-presence line (S11 — one line when a gateway listens, never a screen), the source chip row (plus a clear chip when a type filter arrived from Home), then rows. Calendar and Reminders are LIVE read bridges (EventKit, local): events from the past week through today and open reminders land as things, deduped on sourceRef — connect ends in proof. Approvals ship as things (S10, demo grade): kind `approval`, the agent's exact command in a monospaced card, provenance in the header, Approve/Deny as the thing's verbs — no confirm dialog rides them because they ARE the consent; they ride the swipe too for the same reason. Gateway pairing spec (M5): OpenClaw-class connect = scan the QR from `/pair qr`, token to Keychain (S5 secrets ruling), proof = the agents' recent things stream in.

## 19. Thing sheet

Verbs card: Open in {source} / Open shortcut / type verb — rung 2 lives here. One Tags field: active chips lit in tint, candidates dim, projects included; tap toggles. Add-to rides the tag field. Open question: the detail view needs a native rethink — App Intents replace web-era staged hand-offs; the content spec beyond tags and verbs is pending.

## 20. Tags

Three sources. Type tags: assigned at ingestion. Project tags: assigned through clustering; the person renames. User tags: created in the thing detail and the composer parse card. Tags act as Feed filters and search terms. Project membership rides a tag. No tag management screen; a tag with zero things dies.

## 21. Projects

A project is a computed cluster. The system groups things by theme across sources and names the group. The person renames or pins; the person never files. A project carries: name, sources, synthesis line, thing count, tint fill at opacity scaled by count, stable across sessions. Project detail: header paints from the tile, doc streams under.

## 22. Marks

Things enter the corpus unmarked. Marks from Feed or detail by swipe or tag: to do, doing, saved, done. Home renders marks inside projects. Inference proposes marks through suggestion rows; one tap admits, one dismisses. Status set: todo, doing, done, saved, suggested, none.

## 23. Generative UI

Declarative. Component library: Stack, Hero, Insight, Bento, ProjectTile, Tile, PhotoTile, VoiceTile, Widget, Row, Chip, Shelf, Suggest, Skeleton, StatTile, TagMap, AnswerStream. The model authors compositions per moment in a line-oriented document. The renderer mounts a component when its line parses; string props fill as tokens arrive; declared children render as skeletons until their lines resolve; unresolved references drop. Engine: parser + stream hook + renderer, shared by Home, composer answers, S10 approval sheets. Any prefix of any document renders.

## 24. Composer

Rest pill: chips (Ask tint, Open app, Open shortcut) + search glyph + mic. Bubble expands from bottom right (origin 100% 100%, radius 24/24/10/24). Action chips show at open and hold while typing. Parse card: chip label + fields. Search intent streams AnswerStream through the engine. Close clears draft. Mic routes voice through the parse — speech becomes a thing. No voice panel, no talk tab.

## 25. Apps spec

A page, not a tab: it lives behind the Apps row in Account. Rows: 44px app icon inside a state ring — green connected, orange fix, gray paused. Broken sorts first. Sort control: Recent / A–Z, attention pinned. Swipe left: Reconnect (tint), Remove (red). Tap: detail — Reconnect button when broken, capabilities as sentences, ask-before-acting toggle per app (writes default on), recent things, Pause/Resume, Remove with keep-or-purge choice. Catalog grouped by value with verb taglines; agent and gateway kinds join for Alice. Every connect ends in proof: things land in Home.

## 26. Account tab

The Apps row leads the list: subline states bridge state in force ("6 connected · 1 needs attention"), tap opens the Apps page. Then rows A–Z: Avatar, Connection (state ring: wifi/cell/off), Data ("On device · iCloud sync on"), Privacy ("End-to-end encrypted" — ships when the build proves it; leaving the app redacts content, so the app-switcher snapshot shows choreography, not things; a manual "Hide previews" toggle is an M7 Privacy-sheet option), Subscription ("Free plan"; pricing parked), Theme (Appearance — ruled and shipped, see below), Updates ("Version 0.1"). Usage tile cut on review: usage renders as synthesis where it lives (Home StatTiles), not as a static Account fact.

Appearance (user ruling, 2026-07-04): four global knobs, nothing per-element — mode (dark/light), tint (one accent: Blue/Pink/Purple/Green/Amber), background color (five curated pairs, each legibility-safe in both modes: Black/Slate/Night/Forest/Plum), background photo (the person's own, under the prototype's 0.5→0.72 scrim). Explicitly NOT project colors — "that's just an extra setting," identity stays with the system. A chosen photo implies the dark treatment (light-mode-over-photo legibility is the parked §9.3 gap). Theme tile subline states the palette in force ("Dark · Pink · Plum", "Photo" when one is set). Sheet legibility ruling (2026-07-04): every control cluster wears an eyebrow label (Mode / Accent color / Background / Photo — "Color" alone said nothing next to a background row that is also colors; Apple's own term explains itself), and background swatches never wear the value they apply — near-blacks are indistinguishable — they wear the hue at full voice gradiented down to the actual dark, with the name under each; a settings row you have to explain is a failed row. Implementation law: the page field paints INSIDE each screen (`dsPageBackground`) — a layer behind a NavigationStack can never show through its opaque backing; picked images are downscaled (≤1600px, renderer scale pinned to 1) and stored as a file, never in UserDefaults or the render tree at full size.

Appearance re-ruling (2026-07-05): the tray wears the tile surface (`DS.surfaceSheet`), not a material — the sheet is family with the cards it rises over. Swatches are SOLID, no wash, and Black is true black (the gray stand-in lied); a hairline edge keeps dark swatches visible on the dark tray. Photo is a background, so it lives in the Background row as the sixth seat (thumbnail once set, tap always opens the picker, picking any solid takes the photo off) — a lone photo pill read as choosing an avatar. Accent ruling (2026-07-05, resolved): the accent row is GONE. The five options were hex-identical to five kind hues (blue=link, pink=voice, purple=chat, green=screenshot, amber=reminder) — a picked accent made one kind look pressable everywhere. One fixed Casberi blue (#1673e6, off the logo berry's gradient, deliberately not the link kind's #0a84ff) is the app's interaction ink: buttons, active tab, chips, small marks, and project-tile magnitude fills. Accent does not drive project tiles as a knob — that's a second knob sneaking back in. Appearance is two knobs: mode and background (color or photo). Grammar: kind hue = what it is; Casberi blue = you can press it; orange = needs you; green = done.

Background re-ruling (2026-07-05): choosing a color gives THAT color, solid — the applied page is a real color (Slate #2c3844, Night #182050, Forest #16301f, Plum #2c1631 in dark; matching pastels in light), not a tinted black wash, and the swatch wears exactly the value it applies in the current mode. Every pair keeps the text ramp ≥10:1. "Black" renamed "Default": the system's own pair — true black in dark, Apple's grouped gray #f2f2f7 in light.

Updates rule (2026-07-05): one changelog entry per day — a day's later batches fold into that day's line, retroactively. The tile wears the newest line; the sheet holds the days. Voice: plain words, "you can now…" — say what a person can do or see; no metaphors, no app-speak (user: "speak more human").

Title rule (2026-07-05): titles are left-aligned. Everywhere — screens, tiles, sheets, cards, rows. No centered headers; the two tray sheets were the only deviants and were corrected. One template: title left, content below, controls where the hand is.

Detail sheets ruling (2026-07-04): every fact the system can answer is answered live, and every control that is real today ships today — nothing waits for enrollment that doesn't need it. Data: live thing count and on-disk store size (SQLite + sidecars), Export your things (one JSON file via the share sheet), Delete everything (destructive confirm, states the count, "no undo"). Privacy: Hide previews toggle (drives the app-switcher redaction, default ON — privacy is the default, opting out is the choice), App-permissions link into iOS Settings (the sanctioned route; grants themselves live with their apps in Apps), telemetry/trackers stated as none. Connection: live network path from the system monitor (Wi-Fi/Cellular/Offline, Low Data Mode when constrained) — the tile subline reads it too. Subscription stays an honest placeholder — it genuinely blocks on App Store. Support removed (2026-07-05): the tile and its sheet case are cut. The tile did two things — state the version and open a mailto — and both are hollow now. The version already lives on the Updates tile (and its sheet leads with it), so Support only duplicated it; and there is no support desk behind support@casberi.app, so "Email us" pointed at a mailbox no one reads — a dead control, which the honesty rule forbids. Support returns when a real channel exists (a monitored inbox, or an in-app report that files somewhere). Until then the version is Updates' job and Account carries no help surface. Balance removed (2026-07-05): the tile, sheet case, credit ledger, and Products.storekit are cut. A balance meters a cost, and today there is no cost — no server agent runs, and the agent brain we're betting on is Apple's on-device Foundation Models (iOS 26), which is free and private (a build probe confirms it reports Available on the iPhone 17 Pro simulator). Answers run on the person's own silicon; nothing to bill. Metering was a demo of a business that doesn't exist yet — selling credits for free compute is dishonest, and the honesty rule ("every fact the system can answer is answered live") makes a placeholder ledger a failed row. The strategy: Apple's free on-device model first, MCP connectors (push in) later; a paid server tier — and only then a Balance — returns if and when a server feature exists that actually costs money to run. Until then, Account carries no money surface but Subscription's honest "Free plan" placeholder.

Data ruling (2026-07-05, supersedes §373's Data clause — built + verified on the sim): Data now doubles as the on-device agent's TRUST surface. The agent reads the person's things to answer, entirely on-device (Answer-path ruling), and that guarantee was invisible — Data said nothing about it. Rows now state it plainly: "Your things — N on this iPhone"; "Answers — Written on this iPhone" on Apple-Intelligence devices / "Built-in search on this iPhone" on the fallback (live on `OnDeviceModel.isAvailable`); "What the agent sees — Only your things, only when you ask" (the grounding rail made visible); "Leaves the phone — Nothing" (this replaces the old "Server — Never holds your things"; it is the stronger, future-proof guarantee — it stays true even when a thin Goal-3 server exists for bridges, because the person's things still never leave the device); "Storage — <total>". The fake "iCloud sync — Arrives with your account" row is CUT (Balance/Support precedent — CloudKit isn't built, so it stated a non-fact). Three honesty fixes shipped with it, because "everything" must be literally true: (1) Delete everything now also purges the sidecars the SwiftData store doesn't own — voice `.m4a` recordings and the background photo (app's own Application Support) and the avatar (UserDefaults); before, "Delete everything" left the person's actual audio on disk, a real privacy leak. (2) Storage now sums those sidecars too, not just the group-container SQLite — the number is the real footprint the label claims (this is what §373's "SQLite + sidecars" always intended; the code had only ever counted the DB). (3) Export/Import round-trip `provenance` (app/agent/run/machine), `sourceRef`, and `mark`, so a backup is genuinely everything and agent provenance survives — the whole point of the Alice load. The three controls (Export / Import / Delete everything) stay; they are all real. The delete-test note in the tile-rule paragraph still holds: removing this tab loses ownership/identity facts and controls only — no product function lives here.

Data design ruling (2026-07-05, built + verified on the sim): Data must not read as a plist of label/value rows — it is the trust surface, so it wears the Apps page's alive language. Each tray row is a colored glyph badge (SF Symbol in a squircle, `Radius.appIcon`) + title + live value, exactly the BridgeRow grammar. Color is the tell, and green (`DS.confirm`) is the confident one: the three trust guarantees wear green badges (Answers = `sparkles`, What the agent sees = `eye.fill`, Leaves the phone = `lock.iphone`), the corpus wears the tint (`tray.full.fill`), the raw number stays neutral (Storage = `internaldrive.fill`, gray). The Data TILE earns a signature mark like Avatar earns its photo: a green `lock.iphone` badge, top-right, sized like the avatar seat — a glance says "private, on-device." This is the pattern for the screen-by-screen pass: a sheet that carries a guarantee should show it in color and iconography, not state it in gray text. (Export pill relabeled "Export" — "Export your things" truncated in the three-control row.)

Data design — refined to stat-led (2026-07-05, built + verified): three mockup directions were explored to channel a more confident, Cash-App energy. A hero "banner" in the header was rejected — no other tray or page carries one, and consistency wins; the tray keeps a plain "Data" title like every sibling. Chosen form: STAT-LED, because it is data and the numbers tell the story. The two facts (thing count, storage) lead as two big bold `heading22` monospaced-digit number cards; the three privacy guarantees follow, each on a SOLID green (`DS.confirm`) badge with a white glyph (the earlier 16%-opacity tint was too timid). "Your things" and "Storage" stopped being badge-rows and became the number cards; only the guarantees keep badges now. Values still resolve through shared helpers (`answersValue`, `leavesValue`) so the fact card, tray, and tile never drift. The Data TILE echoes the tray: it keeps its green `lock.iphone` trust mark and its subline became the mini-story "N things · on device" (live count leads, guarantee follows, `·`-separated like the Apps tile). Sheet detent tightened 600→520 to hug the shorter content. Account-sheet title bumped `heading17`→`heading22` (all five trays + the Appearance sheet, together for consistency): the old 17pt title read as fine over small fact rows but looked weak/subordinate once the stat-led numbers (22pt) sat right beneath it — a proper 22pt header restores the hierarchy.

Account cleanup + Connection/Privacy alive (2026-07-05, built + verified): the screen-by-screen pass continued. SUBSCRIPTION tile removed (the app is TestFlight-bound; there's no paid tier to state — same honesty logic as Balance/Support: a tile that meters a thing that doesn't exist is a failed row; it returns when a real paid feature does). CONNECTION and PRIVACY restyled into the alive language (a shared `aliveRow(glyph, tone, title, value)` — solid colored badge, white glyph, the Apps-page grammar), with a `switch` in the body routing data/connection/privacy to their own cards and Updates keeping the plain fact card. Honesty calls made explicit: (a) Connection is a READ-ONLY status tray — the network is the system's to manage, not the app's, so it has no in-app control by nature; its real value is the live path + the "capture and reads work offline" reassurance (green). (b) Privacy KEPT because it carries real controls — the Hide-previews toggle is genuinely functional, plus the real iOS-permissions link and the honest "no analytics, no trackers" fact (green shield); its E2E question belongs to Data, not here. SIGN OUT deliberately NOT added: there is no account, login, or session anywhere in the app (on-device; iCloud is the system Apple ID, signed out only in iOS Settings) — a Sign-out tile would be a pure dead control. It arrives when accounts/CloudKit land (M1+). E2E CAVEAT recorded for M1 sync: "all iCloud is end-to-end encrypted" is a common misconception — iCloud is E2E only with Advanced Data Protection enabled; standard iCloud/CloudKit private DB is encrypted but Apple-key-accessible, so the Data tray's "end-to-end encrypted" sync copy must be qualified (ADP-dependent) when the engine actually ships. Account is now: You = Apps/Avatar/Connection/Data/Privacy; App = Theme/Updates.

Account simplification pass (2026-07-05, user-driven, built + verified): (1) DATA copy cut down — stat labels to one word ("things" / "storage"), row values shortened ("On this iPhone", "Only your things"), footnote to one line ("Export saves it all to one file. Delete clears everything — no undo."); the "end-to-end encrypted" phrase dropped entirely (it was an overclaim without Advanced Data Protection, and shorter is truer). (2) iCloud sync is now VISIBLE in the iconography: on → the "Leaves the phone" badge and the Data tile badge both become a blue cloud ("Your iCloud"); off → green lock ("Nothing"). (3) GROUPS RETIRED — the "You"/"App" headers are gone; every tile sits in one A–Z grid (Theme joined the rest). (4) PRIVACY tile + tray REMOVED (user: "looks like shit, get rid of it") — its one real control, Hide previews (app-switcher redaction), MOVED into Data as a second toggle so the feature survived; the no-tracking fact and the iOS-permissions link were dropped (permissions already live per-app in Apps). (5) UPDATES tile + tray REMOVED — the changelog was the wordiest surface in the app and the user cut it; `AppUpdates.swift` is now dormant (unreferenced, kept as a record, no longer surfaced — so the "fold changes into the changelog" habit is paused until/unless Updates returns). Account is now just: Apps · Avatar · Connection · Data · Theme, and `AccountDetail` is down to {data, connection}. Dead code removed with the trays (factCard, rows, version/build/displayDate, privacyCard, the openURL/UIKit imports).

Tray template + Data simplification (2026-07-05, §8 addition — built + verified): (1) TRAY TEMPLATE `DSTray(title:height:){ content }` added to the design system (Design/DSTray.swift). RULE: trays are never hand-rolled — `DSTray` owns the grabber, a left-aligned `heading22` title with top clearance (`padding(.top, s6)`) so it never crowds/"flows over" the top edge (the bug that prompted this), uniform horizontal + bottom padding, the sheet surface, the height detent, and the color scheme. Every tray (Data, Connection, the Appearance/Theme sheet) now goes through it; callers attach their own `.onAppear`/`.fileImporter`/`.confirmationDialog`. (2) DATA copy/rows simplified hard: the three abstract "trust" rows (Answers / What the agent sees / Leaves the phone) confused users and were redundant — collapsed to ONE plain row "Private / Answers run on this iPhone"; the leaves-the-phone state folded into the iCloud-sync row (its badge is the tell: green lock = on device, blue cloud = synced); Hide previews became a matching toggle row. Stat labels are one word ("things"/"storage"). The footnote is GONE (Delete's confirm dialog already carries "no undo"). Two shared row helpers now: `aliveRow` (badge + title + value) and `toggleRow` (adds a switch), both over one `badge(glyph,tone)`. Result: Data reads as stats + one guarantee + two toggles + three action buttons, no wall of text.

Connection removed (2026-07-05): it was a READ-ONLY status tray with no control — the network isn't the app's to set (that's Control Center / iOS), there's no useful per-app link (network is global; the lone per-app "Cellular Data" toggle is too niche for a tile), and the Wi-Fi readout just duplicates the status bar. Its only semi-unique bit — "works offline" — is a one-time reassurance, not a permanent tile. Same test as Balance/Support/Subscription/Privacy: no real control, no real job → cut. It earns a comeback when iCloud sync is real, where "offline" means "sync paused" and folds into Data's sync row, not a standalone tile. `NetMonitor.swift` kept but dormant for that day. `AccountDetail` is now a single case {data}; `AccountDetailSheet` is effectively the Data sheet. Account is now just Apps · Avatar · Data · Theme — four tiles, each with a real job.

Third tab becomes Apps (2026-07-06, supersedes the 2026-07-03 "Account/Home/Feed" shell amendment): once Account was pared to Apps + three settings tiles (Avatar/Data/Theme), an "Account" tab was a wasted tab — a drawer of rarely-touched settings, not a workspace. So the tabs are now Home · Feed · APPS — three real destinations (synthesis, record, connections). The third tab's root IS `AppsScreen` (bridge list, AVAILABLE offers, catalog); it stopped hiding behind a tile. SETTINGS (photo, Data, Theme) tuck behind the AVATAR in the Apps nav bar (top-left) → a pushed `SettingsScreen` (the old `AccountScreen`, renamed, Apps tile removed, NavigationStack unwrapped). This supersedes the avatar-as-tab-icon ruling: the avatar is now the settings-entry button (the universal "your face → account settings" pattern), and the Apps tab wears a `square.grid.2x2` glyph. Honesty checks that drove it, in order: Data stays (data OWNERSHIP — export/import/delete your things + Hide previews; iOS Settings can't touch your Casberi things, so this is NOT reducible to iOS privacy permissions — it's the app's "your things are yours" promise made operable); Theme stays (real personalization, the one cuttable-for-minimalism candidate); the settings sheet is kept because Data is real TODAY, never as a container for hypothetical future settings. Deep link `casberi://account` still resolves (→ Apps tab) for back-compat. Companion change same day: the Apps tile now lights CONNECTED seats in their own brand color (fill 0.15→0.30, glyph semibold), available stay dim — color-as-signal, all 16 kept for the universe + graceful empty state (connected-only-bigger was rejected: loses the catalog, goes sparse for new users).

Shell settles to two tabs (2026-07-06, late — supersedes "Third tab becomes Apps", built + verified on the sim): the same thread that killed Account as a tab kills Apps as a tab — management is not a workspace. You connect an app occasionally; you don't live in Apps. So the shell settles at its true shape: TWO tabs, Home (synthesis) and Feed (record), plus the composer FAB — think / browse / capture. Apps and Settings are now DOORS in Home's nav bar: the avatar (top-left) pushes Settings; a `square.grid.2x2` glyph (top-right) pushes Apps, both onto Home's own NavigationStack (`HomeRoute` carries deep-link and debug pushes so `casberi://apps` and `-openSettings` drive the same route). Breakage surfaces where it's earned and nowhere else: the Apps glyph wears an orange attention dot only when a bridge needs reconnecting (`bridges.attentionCount > 0`) — and this does NOT reopen the killed tab-badge, because it is a nav BUTTON, not a tab (the ruling banned indicators on tabs; a bell-with-a-dot nav button is standard). No standing "add apps" banner: the new-user invitation stays in the Apps empty state, not as chrome that survives onboarding — restraint holds. `AppsScreen` lost its own leading avatar/Settings item (Home owns that door now) and is pushed rather than tab-rooted; `AccountScreen` stays `SettingsScreen`. This is the third shell change in three days, all peeling management off the bar — not thrash but convergence on the fact that Casberi has exactly two workspaces. Verified: home_2tab (two tabs + FAB, avatar left, grid-with-attention-dot right) and feed.

Polish, motion & delight pass (2026-07-06, from the handoff of the same name — built, all §§ except two flagged): §1 capture choreography (proxy card KindGlyph+title flies from the capture point to the Feed tab, tab icon pulses once via ShellChrome.landedPulse; skipped when already on Feed — the row insertion is the statement there); §2 streaming presence (a 6pt tint dot breathes after the Insight's last character while prose streams; genProseStreaming env flag set by the composer); §3 TagMap settle-in (cells scale 0.92→1.0 staggered 35ms, once per appearance, @State-guarded); §4 cover physicality (overscroll stretch via a fixed layout slot + bottom-aligned overlay canvas — no measurement feedback loop; dateline fades over the first 60pt of scroll); §5 Quiet element (CasberiBerryShape trim-path draw-on 900ms → color settle; Home quiet day says "Quiet so far today.", Feed empty state "Things you capture land here." — the skeleton empty card died); §6 weekend recap (TagMap fill sweeps left-to-right 600ms replacing §3's entrance on weekends; ShareLink renders the map + eyebrow + small mark to an image via ImageRenderer); §8 first-thing moment ("Your first thing" toast with the mark, flight plays even on Feed, @AppStorage-once); §9 live relative times (LiveTimeText, TimelineView 60s — every row time stays true); §10 numeric rolls (contentTransition(.numericText()) on Widget counts, StatTile, KindPills, KindBar legend); §11 pin lift (scale 1.02 + shadow while the row glides to Pinned); §12 toast upgrade (replacement crossfades by identity; drop-captures get "Saved · Undo" for 4s — undo deletes + de-indexes Spotlight; composer saves stay plain, the parse card was consent); §14 redaction return crossfade (0.2s easeOut on return, instant on exit); §15 voice Live Activity (VoiceRecordingAttributes in Shared/, waveform + timer on lock screen and Dynamic Island, recording state only — no transcript, ends on commit); §16 sensory-feedback migration (HapticBus counters + one dsSensoryFeedback() at the shell root; DSHaptic stays as the call-site grammar). FLAGGED, not built: §7 (icon follows background theme) and §13 (glass tuned to vivid backgrounds) both assume the color-background picker, which the same-day light/dark-only ruling made dormant — they revive if backgrounds do.

Same-day companion fixes (user, 2026-07-06): the treemap header is now "What's going on" (it was "This week / What your things are about" — a timeframe claim the data never made; the map draws from all things); the cover dateline got a 36pt reserved band, 13pt semibold at 92% white (it crowded the eyebrow and was too quiet); the two nav doors sit TOGETHER top-right as one management cluster (they were split left/right for no reason — the left edge now stays clear for cover text); Feed pins align on one trailing edge via a shared PinButton — every row ends [tag pill · time · pin], and rows that lacked a pin seat (mail, transaction, note, voice, thumb) gained one; FEED PINS SURFACE ON HOME (a "Pinned" card, newest first, cap 3 — user-chosen, so it passes the no-obligations voice rule); TAG MANAGEMENT shipped in the thing sheet: active chips wear a visible ×, tap removes from the thing, press-and-hold offers Remove / Rename everywhere / Delete everywhere (rename carries a project's pin to the new name; both fix typos and merge duplicates).

Doors ride every tab root (2026-07-06, extends the two-tab ruling — built + verified on the sim): the avatar and Apps doors are worn by EVERY tab root, not just Home — with only two tabs, Feed otherwise had no path to Apps or Settings without bouncing through Home, which made the doors read as Home furniture instead of shell chrome. They are shell chrome. One shared component (`Shell/TopDoors.swift` — `TopDoors: ToolbarContent` + `AvatarDoor` + `AppsDoor`) so the two roots can't drift: same avatar, same grid glyph, same attention-dot rule (`bridges.attentionCount > 0`, now owned by `AppsDoor` itself). Home still routes through `HomeRoute` (deep links and `-openSettings` keep working); Feed carries its own local `doorPush` state and `navigationDestination` — each stack pushes its own copy of Apps/Settings, which is correct NavigationStack behavior (state lives in the stores, not the screens). Pushed screens keep their back button — doors are for roots only. Verified: Feed shows avatar + grid-with-dot over its large title; Home unchanged.

MCP tool core built (2026-07-06, ahead of the blocked transport — §34; built + verified on the sim): with the design spec settled, the DURABLE half is real. `Model/MCPTools.swift` implements the three tools over the local store — `searchThings` (the composer's scoring, returns real things), `weekSynthesis` (a deterministic, model-free plain-text week summary — a tool must answer on any device and never invent), and `saveThing` (creates a pending approval-thing carrying the payload, inserted into Feed; it does NOT commit). Feed's Approve verb now reads the `mcp.save` `sourceRef` marker and commits the carried thing via the normal capture path (`Capture.thing(from:source:)` + Spotlight index) — the consent → write loop the strategy pivot KEPT, now real end to end. A demo MCP client (`Claude`, "Connected · reads on ask / Saves only what you approve") joins the seed bridges so the surface exists. Verified via `-mcpProbe "work"`: search → 9 things; week_synthesis → "36 things this week; Work led with 8; across 9 apps"; save_thing → the approval "Save: Ship the MCP spec review" landed in Feed's Today, next to the OpenClaw deploy approval. What is NOT built and is honestly gated: the transport/server, CloudKit-synced read path, and QR pairing — all Goal-3, enrollment- and sync-blocked. The tools are the thin shell's contents; the wire slots in later.

MCP pairing screen (2026-07-06, built + verified on the sim — final UI ahead of the server, same standing as the iCloud-sync setting): the one piece of the MCP flow that can be designed real now, because it doesn't need the wire to be honest. `PairClientSheet` (via `DSTray`) shows a real QR the person presents to a client — "Scan this in Claude, Raycast, or any MCP client to connect it to your things" — with the consent rail stated in the alive language (a green `hand.raised.fill` badge: "Yours to allow / Reads when you ask · saves only what you approve"). The token behind the code is real and Keychain-backed today (`MCPPairing`, a generic-password item; `reset()` mints a fresh one to revoke); the endpoint the payload names is the one placeholder, gated by a quiet honest footnote ("Connecting goes live when your things sync. Code: <short>") — the same discipline as the sync toggle: build the final surface, never claim the part that isn't wired. It lives under a "Connect a client" row in Apps, above the pull-in bridges, because MCP is the opposite direction (a client reaching IN to your things, not an app's data pulled in). Verified: pair_sheet.

Apple Developer Program — enrolled (2026-07-06): the standing blocker on the whole server/sync/entitlement chain is cleared. What this unblocks to BUILD: M1 CloudKit sync (the SwiftData `cloudKitDatabase` config + the Thing-model rework it needs + voice audio into external storage/CKAsset + dedupe-on-merge + the iCloud entitlement), on-device model entitlements (already Available on the sim), TestFlight, and MusicKit (the Apple Music bridge). The remaining gates are no longer enrollment — they are DECISIONS: where the Goal-3 server is hosted (for `/compose`, `/parse`, and the MCP transport) and which cloud model(s) fill the opt-in brain layer (Anthropic API and/or Gemini, per the strategy pivot). The likely first build is M1 CloudKit sync, because it is the substrate everything else now waits on: it is the read path the MCP server reads from, and it is what turns the iCloud-sync toggle and the pairing screen from final-UI-behind-a-gate into live features. Several ship gates come due the day their engine lands (each recorded in its own ruling): the sync toggle must move real bytes, the pairing endpoint must accept a real connection, the "nothing leaves the phone" copy must go conditional when the cloud brain ships, and Balance returns with the per-token cost.

M1 CloudKit sync substrate (2026-07-06, built + verified on the sim — the code half; the capability is a one-toggle Xcode step left to the user): the model and container are now CloudKit-ready, decoupled from the account work. Three changes: (1) THE THING MODEL is CloudKit-compatible — every stored property carries a default value and none is `@Attribute(.unique)` (SwiftData's CloudKit mirroring requires both; the custom `init` still sets everything, the defaults exist only for the schema). (2) THE CONTAINER (`SharedStore`) engages CloudKit (`ModelConfiguration(groupContainer:cloudKitDatabase: .private("iCloud.com.casberi.app"))`) only when the person opted in AND the build is CloudKit-ready; otherwise it stays local. (3) A `dedupeBySourceRef` reconcile (`SyncReconcile`) runs after the launch Spotlight pass and collapses CloudKit-merge duplicates by `sourceRef`, keeping the earliest — inert until sync is on. THE SHIP GATE is now a real mechanism, not just a note: `SharedStore.cloudKitReady` (a `Bool`, `false` today) is flipped to `true` only once the iCloud+CloudKit capability is added in Xcode. This matters because — found the hard way — attempting a CloudKit-backed store WITHOUT the entitlement doesn't throw where `try?` can catch it; CloudKit sets up on a background queue and *traps* (`EXC_BREAKPOINT` on `com.apple.coredata.cloudkit.queue`, inside `PFCloudKitContainerProvider`), and iOS has no reliable runtime entitlement read (`SecTaskCreateFromSelf` is macOS-only). So the gate is a hard compile-time switch, verified: with `cloudKitReady = false` and the sync toggle FORCED on (`-icloud.sync YES`), the app launches and renders normally instead of crashing. Still open within M1 (each independent, none blocking the substrate): voice `.m4a` into `@Attribute(.externalStorage)`/CKAsset, `deleteEverything` propagating deletes through CloudKit, aligning the widget/extension container config with the app's when sync is live, and flipping `cloudKitReady` the day the capability lands.

Capability added, sync live-capable (2026-07-06): the iCloud + CloudKit capability is now in the build. Added in Xcode (target → Signing & Capabilities → iCloud → CloudKit, container `iCloud.com.casberi.app`, plus Background Modes → Remote notifications); `Casberi.entitlements` now carries `com.apple.developer.icloud-container-identifiers`, `com.apple.developer.icloud-services = CloudKit`, and `aps-environment`. The one snag on the way was a target with no development team set — the capability picker reports "Error Loading Capabilities" until a Team is selected, which is the first thing to check if capabilities won't add. With the entitlement present, `cloudKitReady` is flipped to `true` and the forced-sync-on launch that used to trap now runs clean — the corpus mirrors into CloudKit. Sync is live-capable; the in-app toggle stays default-off, so nothing syncs until the person opts in. True cross-device verification still needs a physical device signed into iCloud (the simulator has no iCloud account, so CloudKit simply no-ops there — gracefully, no crash — which is the correct behavior).

Five-fix batch (2026-07-06 evening, user-driven — built + verified on the sim): (1) The FOR-YOU chart is now SMART: it never repeats the connected strip. Connected apps — healthy or broken — live in the strip (breakage keeps the attention-dot grammar; Fix lives on the product page); paused bridges moved out of the strip and into the chart as Connect; the chart is only what you can ADD. (2) STORIES got their App-Store presence: min-height cards with the headline high, the footer low, and air between (minHeight, never fixed); the eyebrow is just "NEW". (3) The phrase "land as things" is RETIRED from user-facing copy (it read strangely and collides with the Things 3 app) — the feed carries the language now: "Screenshots, straight to your feed" / "Your onchain life, in your feed" / "PRs and issues, in your feed"; "things" as a noun survives, the verb-phrase died. (4) The COMPOSER's suggestion chips are gone ("no need") — the open composer is just the field; paste capture survives without its chip via an insertion heuristic (a paste-sized change flags the draft as a capture, so the parse card and save-on-send behave exactly as before). (5) APPEARANCE is ONE KNOB: light or dark. The background-color and photo pickers are retired (they complicated the theme and multiplied variation); stored choices migrate to the default and the photo file is cleaned up. The bright-primary palette from earlier today goes dormant in the token layer rather than deleted — the machinery stays, the UI doesn't reach it. Also: the Bankr icon re-rendered full-bleed (its SVG's own width/height attributes had beaten the render scale — strip them and the viewBox drives).

Home — cover story (2026-07-06, applied from docs/handoff-home.md, mock H7 — built + verified on the sim): the sheet-card Hero became a full-bleed COVER and the KindBar became kind-colored glyph PILLS; nothing else moved (treemap untouched, Insight one proven line, Threads and Signals as shipped). The gen-UI rule holds: the composition stays dumb — `Cover(eyebrow, title, subline, thingId, dateline)` only names facts — and every smart behavior lives in the renderer's Cover element: thing lookup, PHAsset load, dominant-color extraction (CIAreaAverage, desaturated ~20%, brightness-capped for the ramp, cached per thing id, off-main), theme fallbacks, and height decided before first paint (image → 250pt canvas, none → 140pt quiet cover) so the streamed skeleton never jumps. The bleed is EXTRACTED FROM THE IMAGE, never themed — content owns the cover, the theme owns everything below — and the bottom gradient stop is the themed page (never hardcoded black), so on Purple/Teal the cover dissolves into the page with no seam; a photo wallpaper skips the bleed and strengthens the scrim (the cover's content photo wins). The date eyebrow ("MONDAY · 24 THINGS" / "QUIET SO FAR") rides the top edge between the nav buttons, authored in the doc; the 34pt "Home" nav title is gone — the cover is the title. Kind pills: one per kind, count-ordered, max five, identity color at 0.15 fill + the kind's glyph + count, "WHAT LANDED TODAY" (whole-corpus fallback keeps the old eyebrow), tap → the same Feed type-filter route; KindBar stays in the vocabulary. Author-side honesty added during verification: the doc only names a thingId when the image can actually resolve (screenshots with a sourceRef — demo things honestly fall to the quiet cover), and APPROVALS NEVER LEAD the cover (the voice guardrail: agent asks live in Feed; the cover states what landed, never what's waiting). One inset lesson: a full-bleed element must reserve the measured safe-area inset INSIDE its canvas — the first quiet-cover render put text under the status bar. Extraction runs verified in code; the live image cover renders on device once real screenshots carry assets (the sim demo has none — the fallback IS the verified path).

Apps page — store anatomy (2026-07-06, applied from docs/handoff-apps-page.md, mock M4 — built + verified on the sim): the Apps page became a real store. One scroll: the CONNECTED strip (management — paused bridges dim to 50% and read "Paused"; it never merchandises), then a `fillLine` hairline and the "Discover" heading with a quiet "N to connect" count — management above the line, store below. A swipeable STORY CAROUSEL replaces both the hardcoded Zerion hero and the pair row (one door, richer): 2-3 brand-gradient editorial cards (the one brand-gradient license), eyebrow / 24pt-heavy pitch / icon + name + white capsule, chosen by rule — connectable-not-connected bridges first, Pair-a-client when no client is paired, never a "Soon" app, never a connected one. The LAYOUT LAW holds: no fixed heights anywhere on the screen — every card and row sizes to content + token padding (minHeight only for hit targets), equal carousel heights via top-aligned HStack + fixedSize. A BROWSE shelf of category pills (a merge map over the offer groups: Your life / agents / mail / work / media — categories exist ONLY here and as the chart filter, never as section headers) filters the one ranked FOR-YOU chart: rank number · icon · name + honest subline · capsule verb, ordered broken→Fix (attention), ready→Connect / Claude→Pair (tint), healthy→Open (confirm-dim, statusLine as the subline), coming→Soon (dimmed row). Capsule verbs are honest and shared with the product page via `VerbCapsule` — Connect / Pair / Fix / Open / Soon, never "GET". CatalogScreen is DELETED (the page is the catalog; its debug probe folded into AppsScreen). Deviations, noted: "Soon" rows desaturate the real brand icon rather than reverting to the gray-glyph well (the real-icon ruling post-dates the mock; recessive either way); connected sublines carry the bridge's own statusLine (the proof line is the honest state); stories have no dismiss affordance (the doc names dismissal without designing it — nothing invented).

Shaped feeds (2026-07-06, applied from docs/handoff-shaped-feeds.md — built + verified on the sim): the Feed's chips now change SHAPE, not just the query. "All" renders kind-aware rows (time-led events with rail bars, verb-led transactions, thumb-led photos, snippet mail) with `.approval` as the one rhythm-breaker — the consent card (provenance eyebrow, the ask, live Approve/Deny pills; the card IS the consent, no dialog). Per-source shapes verified: ZERION leads with the holdings treemap through the engine then verb-led rows ("Received" wears confirm); CALENDAR reads as an agenda (tabular times, rails, past dims, the next event's ROW carries the emphasis — bold time, tint rail, "in N min" countdown; no redundant hero); REMINDERS groups by state (Doing/To do/Done-today, stale todos collapse) with the check circle as the lightest write — tap completes the REAL reminder through EventKit (`ScheduleIngest.setCompleted`), tap again is the undo; GMAIL surfaces a capped "Waiting on you" cluster then subject+snippet rows (handled mail dims, no unread badges ever); CHATGPT/CLAUDE chats earn takeaway cards only when pinned or in motion; PHOTOS becomes one continuous grid with day-pill overlays on the first photo of each day (real PHAsset thumbs when present, honest hue fallback in the demo); SAFARI/NOTES/YOU/OPENCLAW/BANKR derive from the pattern (link rows, content rows, waveform rows, approvals-first + status ticks). Day groups, pins, swipes (reads-only), the sheet, and write-confirm all survive inside every shape. IMPLEMENTATION DIVISION (deliberate, recorded): the interactive rows are the LIST's — native swipes/taps stay native because the custom-gesture feed died on device (2026-07-04 ruling); the ENGINE paints each shape's one synthesis block (`SourceComposition`) and carries the shaped-row GRAMMAR as display elements (TxRow/AgendaRow/MailRow/TakeawayCard/ApprovalCard join the gen switch) so compositions can paint them. Deviations from the handoff, noted: the Photos single-photo-day full-width case ships as the uniform grid + day pills; the Reminders undo is the circle itself (tap again) rather than a toast action — the flash says so.

Agents, wallet UI, icons batch (2026-07-06, built + verified on the sim): five rulings in one pass. (1) REAL BRAND ICONS — official third-party glyphs (Simple Icons distribution) composited onto brand-color tiles and bundled as `brand-<name>` assets; ten landed (GitHub, Notion, Spotify, Linear, Reddit, Telegram, X, YouTube, Claude, Gmail). ChatGPT deliberately keeps the SF fallback — OpenAI had its marks removed from the icon set, so the fallback IS the compliant rendering; Apple's own apps stay SF by rule. (2) VIVID TEXT RAMP — the 60/30 text ramp that works on black washes out on bright primaries, so `textSecondary`/`textTertiary` are now computed: on a vivid background (or photo) they brighten to 85/60; the quiet page keeps §8's ramp untouched. One token, every screen inherits. (3) BANKR joins the catalog as an AGENT, not a trading surface: its asks arrive as approval-things through the gateway ("Swap 0.3 ETH → USDC?" — the tap is the gate), its trades show through the wallet read, and Casberi itself never trades — the refusal recorded in the Zerion ruling stands. (4) VENICE joins the catalog honestly graded: chats live on the person's own device by design, so there is nothing to read IN — its value is the other direction, a private zero-retention API that is now a named CANDIDATE for the opt-in cloud-brain layer alongside Anthropic/Gemini (strategy pivot). (5) ZERION CONNECTED UI ships: a wallet home reached from the connected strip — watched addresses (paste to add, swipe to remove, drag to reorder; the first address leads), what's landed (recent onchain things), and the read-only guarantee stated plainly; live sync stays honestly gated to the account/server. `WalletStore` persists the list; the demo seeds the "Main" address the bridge's status line names. BASE (docs.base.org mini-apps) assessed and REFUSED for now: MiniKit mini-apps are React web apps living inside the Base App/Farcaster feed — a distribution platform, not a data bridge; Base-the-chain already lands via Zerion. Revisit as a distribution surface only after Goal-3 if the crypto vertical proves out.

Bright-primary backgrounds + polish (2026-07-06, user-driven, built + verified on the sim): the background palette flips from muted dark tints to BRIGHT primaries — Purple/Pink/Red/Orange/Teal/Green (+ Default black), the dark treatment at full voice with white text, the light treatment a paler wash. Blue is deliberately absent: the fixed accent is blue, so a blue page collides with the blue-tinted treemap and eyebrows (blue-on-blue). Companion fixes from the same pass: (a) the gen-UI eyebrows (Hero, "Noticed", "Projects", "What they are") were the accent blue and clashed on colored pages — now neutral (`textSecondary`), reading white on any bright background; the treemap magnitude fills stay accent-based (they encode count). (b) The Home hero stopped leading with "X fills your week" — it read as naggy/pressuring — and now leads with the most recent thing ("Just landed: <title>"), specific and current, with the treemap below still showing what fills the week. (c) Onboarding reframed to the three real jobs — "Add your apps" → "See it all in one feed" → "Take action." (d) The catalog is now icon-ready via `BridgeIcon`: a bundled `brand-<name>` asset renders as the real app icon, else the SF-symbol + brand-color fallback — third-party logos are permitted in an integration directory under each brand's guidelines (Apple's own app icons stay SF Symbols, being restricted). (e) Zerion's connect copy corrected: there is no user "read key" — you paste the wallet address; the Zerion developer key is Casberi's, server-side.

Zerion — onchain life as a read bridge (2026-07-06, built + verified on the sim): crypto joins the corpus the honest way — a wallet's activity *lands as things*, not a watchlist. Zerion's API is read-only (positions, transactions, portfolio, NFTs across EVM + Solana), so it can never trade or move funds; a swap/send/receive becomes a `Thing` of the new `.transaction` kind (amber `arrow.left.arrow.right` glyph, a vertical kind that may share the warm family), lands in Feed like anything else, and clusters under whatever tag it carries (`Onchain`). Portfolio value and holdings are synthesis, not things — they surface as Home signals, never per-balance feed spam. The bridge is graded honestly: `connectable: false` in the catalog (a live read needs the person's address + a read key, which is the Goal-3 server or bring-your-own-key), but a demo Zerion bridge + demo transactions ship in the DEBUG corpus so the shape is visible. Deliberately NOT built: watching arbitrary addresses or hand-built token watchlists — that's the curated-home pattern the product already refused (synthesis > curation); "watch tokens" is just tags + projects. And no trading surface: reads only, and the money-movement path (e.g. an agent like Bankr) is refused here — if it ever arrives it rides the OpenClaw + approvals grammar, not a Casberi trade button. Verified: the four onchain things render in Feed under the Transactions filter with the amber glyph.

App Store catalog (2026-07-06, built + verified on the sim): the "Add an app" catalog became the App-Store surface, per the ruling that discovery earns richer presentation while the connected-apps list stays plain management. Three parts: a **featured hero** (a full-width brand-gradient cover card — Zerion leads), **category sections** whose rows are cards in each app's own brand color (44px icon, name, tagline, connected-check or chevron), and a **product page** (`AppDetailScreen`) reached by tapping any card — big brand icon, "What it does" (a per-offer `summary` added to `BridgeCatalog.Offer`), "What lands in your feed", and an honest action button: Connect where wired, Connected once it is, plain "Soon" where the path doesn't exist yet. Connect moved from the list to the product page (the App-Store tap-through), sharing one path via `BridgeConnect`. The honest availability line only shows when a bridge is neither connectable nor connected (no "not available yet" under a Connected badge). Verified: featured hero + brand-color category cards + the Zerion product page.

Strategy pivot — functionality over on-device purism (2026-07-06, user ruling; amends the "Balance removed" strategy clause and qualifies the Answer-path / Data guarantee rulings): the bet flips from "private and on-device first" to "as much capability as we can give." The trigger was a premise the user pressed and we sharpened: connecting apps is data coming IN (ingest — Calendar, Photos, an MCP client), which never spent the egress guarantee; the guarantee "nothing leaves the phone" was only ever about COMPUTE and EGRESS. So the guarantee is not already gone — but we are now choosing to spend it, deliberately, to buy reach and power. Three layers were separated so the pivot spends the right one: (1) COMPUTE/EGRESS — spent. (2) The on-device BRAIN — kept as the DEFAULT and the free tier; a cloud brain (Anthropic API `claude-opus-4-8` and/or the Gemini Developer API) is added as an OPT-IN power layer ON TOP, so devices without Apple Intelligence finally get a real brain and power users can flip to a stronger model. Not a purge — a layer you turn up. (3) CONSENT/CONTROL — KEPT, explicitly not traded: requiring the person's tap before a connected app WRITES or ACTS is a safety rail, not privacy theatre (the approvals-as-things surface already built is exactly this). "Privacy has to go" means the egress claim, never the approval gate. Consequences recorded as honest bills, both accepted: (a) COPY — the day cloud compute or a cloud MCP read-path ships, "Leaves the phone — Nothing" and the on-device marketing must be RETIRED or made conditional on the active mode (Data's guarantee rows already switch on `OnDeviceModel.isAvailable`; they now also switch on which brain the person chose — green-absolute only while the on-device default is in force). (b) MONEY — a cloud brain costs per token, so BALANCE RETURNS with it (the "Balance removed" ruling said exactly this: a paid tier and a meter come back when a server feature actually costs money to run; this is that moment). WEDGE restated: "on-device, private, free" was a FEATURE, not the thesis — the last month of building (agents, approvals, presence, MCP-as-hub) points at a power-user command centre, so the differentiator becomes "the hub where your apps, agents, and answers all land — and you approve what acts." Direct consequence for MCP: the read-path fork is RESOLVED — external MCP clients read the CloudKit-SYNCED copy of the corpus, not the phone directly (reliable, live, and it ties MCP to M1 sync rather than to on-device hosting). Sequencing is unchanged (enrollment → M1 sync → Goal-3 server + pairing → MCP server on top), but the design fork is now decided, which unblocks writing the MCP spec ahead of the build.

iCloud-sync setting ruling (2026-07-05, built as the FINAL UI; engine gated to M1): sync is a real user choice — keep things on this iPhone, or mirror them through the person's own iCloud — so unlike Balance/Support it earns a real setting, not a cut. Built now, in Data, as it will ship: a real `@AppStorage("icloud.sync")` toggle, DEFAULT OFF (privacy-first — off keeps today's "Leaves the phone — Nothing" guarantee true). It is a live setting, not a placeholder: flipping it persists the choice and re-words the guarantee across the sheet — the "Leaves the phone" row (Nothing ↔ "Only your iCloud, end-to-end encrypted") and the footnote — while the AGENT rows ("Answers written on this iPhone", "What the agent sees") stay green-absolute, because sync moves where the corpus is stored, never where answers are computed. Two honesty lines held so this isn't the dead/lying control the rule forbids: (1) NO fake status — there is no "Synced ✓ / Last synced" claim, because that specific present-tense assertion is where the lie would live; the toggle records intent and describes the option, nothing more. (2) SHIP GATE — this must NOT reach real users until the CloudKit engine actually moves bytes (M1: model rework for CloudKit + voice-audio into external-storage/CKAsset + dedupe-on-merge + entitlement, all gated on Developer Program enrollment). A live toggle that a real user flips ON while nothing syncs would mislead — acceptable in this pre-M1 design build (DEBUG corpus, no real users), a violation the day it ships. The same `icloud.sync` flag the copy reads today is the flag the sync config reads at M1; the UI is done, the engine slots in behind it. Changelog deliberately does NOT announce sync as available — announcing a feature that doesn't move data yet would be the lie in another place.

Rule: subline states the setting in force; detail holds the control; one fact per row. Account is a tile workspace (re-ruled on review): two labeled groups in a two-column grid — "You" (Apps, Avatar, Connection, Data, Privacy: your things and their state) and "App" (Subscription, Theme, Updates: housekeeping). Eyebrow headers name the groups. A–Z within each group, rows filling left to right; uniform tile size, no exceptions, odd counts fine. One fact per tile — title plus the setting in force; the detail holds the control. Tiles press with a settle. Avatar: once set, the photo becomes the Account tab icon (circle-cropped; active state = tint ring — a photo can't take the tint). Avatar ruling (2026-07-05): the empty seat wears the app's own face — the Casberi berry (vector `CasberiMark`, the icon's real colors, both ramps) in a circle on the icon's field, sitting exactly where the photo lands. Set, the subline goes silent (the photo is the fact; "You" said nothing). Tap when set asks Change or Remove — every setting can be undone. Grants live per app in Apps detail. Offline is behavior, not a setting: reads and capture work without a network. The delete test holds: remove this tab and the person loses identity and ownership facts only — no product function lives here.

## 27. Analytics

Two kinds, split. Usage shown to the user: content stats as synthesis — StatTile in the gen UI library. Facts only: no streaks, no goals, no guilt mechanics. Telemetry: default off, consent in Privacy detail, no third-party trackers.

## 28. Do, distributed

No Actions tab. Do lives where its object lives: the composer creates, Feed triages, bridges export, sheets consent. Reversal trigger: if bridges prove writes at volume and approvals pile past what Feed carries, a queue earns a surface.

Every verb answers back (2026-07-04): no write ends in silence. One toast surface (the glass pill above the bar, owned by the shell, callable from any screen) carries the outcome — "Saved", "Copied", "On your calendar", "On your list" — and failure states the honest route: a system permission denial says "allow Casberi in iOS Settings", never "try again" (iOS never re-asks after a denial). Light mode audited end-to-end (all tabs, thing sheet, composer, Apps, catalog, onboarding — token layer is fully adaptive so screens inherit it). Widget carries the person's accent color across the app group and has placeholder/empty/one-thing states.

## 29. Automations

Parked. The product takes no alert away from the app that owns it. Automations wait on the do-verb build. Feed carries an "Add to" through the thing sheet tag field.

## 30. Voice

The agent is infrastructure. No persona, no "I", no thinking indicators. Agency renders as results. Insights state facts the corpus proves.

## 31. Hero rule

One synthesis statement per render. Facts only, provable from the corpus. Linked things one tap away. Priority: project movement > pending decision > imminent event > bridge arrival. Synthesis always renders; priority orders what it leads with.

## 32. Design principles

### 1. Apple grammar, token discipline
One surface token `--ds-surface-sheet` (#111113 dark, #fff light) for cards, tiles, trays. Tinted background washes are banned. Text ramp: white / 60% / 30%. Hairline separators died by amendment: rows separate by spacing and press fills, groups by their card surfaces; nothing draws a line. SF ramp: 34/22/17/15/13/12/10. Squircle radii: cards 10, sheets 16, app icons 22.37%. Motion: 250ms, Apple sheet curve, one animation per moment. Every value routes through a token; components hold zero raw hex.

### 2. One tint
iOS systemBlue dark `#0A84FF`, token `--ds-tint`, one-line swap. Tint marks the interactive and the primary. Orange attention, red destructive, green confirmation, nowhere else.

### 3. Color rule
Color carries identity, state, or magnitude. Decoration banned. Magnitude: tint at opacity scaled by count (treemaps, project fills). Theme tint drives the family.

### 4. The composer is the hero
Search, ask, capture in one field. Engaged, it takes the surface: the parse card assembles under the words as pieces resolve.

### 5. Bob's words
Copy names what people control. "Apps," not connectors. Sentence case, plain verbs, numerals, no "successfully." Buttons say what happens. Errors say the fix. Empty states point to the first action.

### 6. Rows carry status
Status on the row, in words, in semantic color. Broken sorts to top. No sections for one row, no chips on short lists, no dashboards.

### 7. Settings hold nothing
Delete Account and the person loses account hygiene only. Permissions arrive in context.

### 8. Restraint
One signature moment per screen. No decoration without information. Before shipping a screen, remove one thing.

### Anti-patterns
Borders on cards. Filter chips on short lists. Permission matrices. Developer vocabulary where Bob sees it. Two accents on one screen. Letter-initial stand-in tiles anywhere (they read half-made). Rows and chips wear KIND glyphs — one SF Symbol system, one weight, one quiet fill; a row's icon says what the thing is, the tag and place words say where it came from. Brand identity appears only where real assets are licensed and legal: the Apps catalog. Thread lists. Modes and model pickers. Glass on content — cards, tiles, rows never wear glass; glass is the floating layer only (bars, composer, toasts, transient chrome). Glass stacked on glass.

## 33. Open items

(Cleared 2026-07-03 — new list pending.)

## 34. MCP — Casberi is the server (design spec, 2026-07-06; build is Goal-3, enrollment- and sync-blocked)

The protocol is a commodity; every load-bearing choice here is product and honesty, so it is specced ahead of the build. This pulls together the rulings already made (Raycast-inverse, OpenClaw "refuse the console", approvals-as-things, QR pairing) and closes the one open fork (read path) that the 2026-07-06 strategy pivot decided.

**Direction — server-first, and we are a provider, not a console.** Casberi ships an MCP server. Outside clients — Claude Desktop, Claude Code, Raycast, the Anthropic API's remote-MCP connector — connect TO us and read or add the person's things from wherever they already work. This is the inverse of a bridge: a bridge pulls another app's data IN; MCP exposes the person's own corpus OUT to a client that asks. We expose the person's THINGS and nothing else — we refuse to become an operator surface (no Sessions, Cron, Usage, or a command console; those belong to the gateway per the OpenClaw ruling). The Casberi-as-client direction (we reach out to other people's MCP servers) is deferred; server-first is the bet.

**The three tools (locked).** A small, honest surface:
- `search_things(query, limit?)` — runs the same scoring retriever the composer uses (title 3× / tags 2× / content 1× + recency). Returns real things (`id`, `title`, `kind`, `source`, `time`) — never invented, same honesty rail as Ask. A READ: allowed whenever the connection is live; no approval, because reading your own things when a tool you connected asks is the point.
- `week_synthesis()` — returns the current synthesis (the Home hero, as prose plus the ids it stands on). A READ, same rule.
- `save_thing(text, source?, tags?)` — creates a thing. A WRITE, so it never lands silently: it surfaces as an approval-thing in Feed (the approvals-as-things surface already built — `ThingKind.approval`, the CommandCard shows the exact ask, Approve / Deny ride the swipe). The tool returns the created `id` only after the person taps Approve; a Deny returns a refusal the client can read. This is the consent rail the strategy pivot explicitly KEPT — writes and actions from any connected client wait for the tap.

**Read path (decided by the strategy pivot).** Clients read the CloudKit-SYNCED copy of the corpus, keyed to the person's identity — not the phone directly. Reliable and live (the synced store is always online), and it ties MCP to M1 sync rather than to fragile on-device hosting. This is only honest once egress is spent and sync is real, which the pivot and M1 provide; the "your things live in your iCloud" fact must be stated plainly at pairing, not hidden.

**Consent guarantee (the copy).** One plain promise, in Data's voice, true to what the code does: "Connected apps see your things only while this is on, and can't save anything without your tap." Reads are gated by the connection being live (revoke = unpair); writes are gated by the per-write approval. No standing background access, no silent writes.

**Pairing / auth.** QR pairing → Keychain (already specced): the person scans a code from the client, the client receives a scoped token stored in Keychain, and the connection appears as a bridge-shaped row with presence ("● Claude · connected") — same grammar as every other app. Unpairing revokes the token and the reads stop. A connected client that breaks or expires surfaces like any broken bridge (Feed absence + its row's state line), not a badge.

**In-app surface.** A connected MCP client is just another entry in Apps — bridge-shaped, with presence — and its writes are just approvals in Feed. No new surface is invented; MCP reuses the bridge + approval grammar already shipped, which is the whole reason those were built agent-first.

**Sequencing (unchanged, now with the fork closed).** Enrollment → M1 CloudKit sync → Goal-3 server + pairing → MCP server on top. It is deliberately one of the last things built, because everything it stands on is enrollment- and sync-blocked — but the design leads the build by a wide margin, which is correct for the one milestone where the thinking is the hard part.
