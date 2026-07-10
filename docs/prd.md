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

Same-day companion fixes (user, 2026-07-06): the treemap header is now "What's going on" (it was "This week / What your things are about" — a timeframe claim the data never made; the map draws from all things); the cover dateline got a 36pt reserved band, 13pt semibold at 92% white (it crowded the eyebrow and was too quiet); the two nav doors sit TOGETHER top-right as one management cluster (they were split left/right for no reason — the left edge now stays clear for cover text); Feed pins align on one trailing edge via a shared PinButton — every row ends [tag pill · time · pin], and rows that lacked a pin seat (mail, transaction, note, voice, thumb) gained one; FEED PINS SURFACE ON HOME (a "Pinned" card, newest first, cap 3 — user-chosen, so it passes the no-obligations voice rule); TAG MANAGEMENT shipped in the thing sheet: active chips wear a visible ×, tap removes from the thing, press-and-hold offers Remove / Rename everywhere / Delete everywhere (rename carries a project's pin to the new name; both fix typos and merge duplicates). Quiet-cover hue (same day, user: "i thought we added some color bleed"): the photo bleed only exists on the IMAGE cover, and the quiet cover's themed gradient was black-into-black on the default theme — no color at all. The quiet cover is a SOLID bright field of the lead thing's kind color (user re-ruling after two iterations, reference: Fantastical's red header): the whole band is the primary hue, +12% white at the top to -8% black at the bottom, hard edge into the page, identical in dark and light — never a tint, never fading into dark. Cover text is white over a photo or a color field, page ink before the color lands. Streaming fix (same day, user: "top is blue then turns red"): the wash paints ONLY once the kind arg has streamed in — nil arg = neutral page, no fallback color (the blue flash was the fallback firing on a half-streamed line); the color eases in (Motion.standard keyed to the arg). Quiet-day, empty, and weekend covers name their wash explicitly (arg = "quiet" → Casberi blue), so blue is always deliberate (a first darkened-toward-black version was corrected the same hour; user: "same color red that the icon is"). Cover gained a 6th arg naming the kind; a quiet day with no lead kind washes Casberi blue; the image cover keeps extracting from the photo. Companion fix: the cover's text ink is white ONLY over a photo (scrims guarantee contrast) and the page's own text ramp on the quiet cover — it was hard-coded white, unreadable in light mode. Same day: RE-TAPPING A TAB POPS ITS STACK — tapping Home while on Home (e.g. inside Apps/Settings/a project) clears pushes and sheets back to the root; same for Feed (ShellChrome.popHome/popFeed bumped by GlassTabBar on re-tap).

REDDIT + SPOTIFY — NO-SERVER OAUTH, GATED ON A FREE CLIENT ID (2026-07-08): both run OAuth entirely on the phone (Reddit's "installed app" type has no client secret; Spotify uses PKCE), so no server. Built and ready; each stays a Soon card until its free client id is pasted in (RedditAuth.clientID from reddit.com/prefs/apps type "installed app" redirect casberi://reddit-auth; SpotifyAuth.clientID from developer.spotify.com). Reddit lands your saved posts as links; Spotify your liked songs. APPLE MUSIC shipped via native MusicKit (no key — MusicKit .p8 is only for the web API). PARKED by user (2026-07-08): Strava + Slack (need the $5-20/mo OAuth-secret server — deferred to focus on testing/polish); X (paid API), YouTube (Google restricted-scope verification), Telegram (MTProto) — all server+platform-wall; Zerion (needs a Zerion API key, or reframe onto a free onchain API later). So the no-server bridge set is COMPLETE once the user supplies the Spotify + Reddit client ids.

MAIL BRIDGES — iCLOUD MAIL + GMAIL, over IMAP (2026-07-08): Apple has no modern mail API, so both connect read-only over IMAP with an APP-SPECIFIC PASSWORD (the real password never enters the app; it lives in the Keychain). One hand-written IMAP client (Model/IMAPClient.swift, Network framework NWConnection + TLS:993, LOGIN/SELECT/FETCH ENVELOPE, tolerant envelope+RFC2047 parser) serves both; MailProvider enum (.icloud imap.mail.me.com / .gmail imap.gmail.com) carries the host + app-password steps, MailIngest lands recent inbox as .mail things (dedupe mail:<provider>:<uid>), MailScreen is the shared address+password setup. Gmail needs 2-Step Verification. STATUS: VERIFIED LIVE against both servers (2026-07-08, real app-specific passwords via the `-mailBridge` probe): login, envelope fetch, parse, land, and dedupe all confirmed on imap.mail.me.com and imap.gmail.com. Two live-test fixes landed: a continuation double-resume in Session.open crashed on every post-fetch disconnect (state handler now clears itself after firing once), and RFC 2047 decoding rebuilt — encoded-words now decode to bytes, adjacent words merge before the charset decode (an emoji straddling the word boundary shattered), and Q-encoding no longer reads UTF-8 bytes as Latin-1 scalars (the "â€™" mojibake); 6-case decoder test passed. Known limits, unhit so far: no IMAP literal-string ({N}) handling in the envelope parser (affected messages skip, never crash) and no network timeout. Debug: `-mailBridge "<icloud|gmail>:<address>:<app-password>"`. Next coming-soon buildable-now: Apple Music (MusicKit, needs a MusicKit .p8 key), Spotify (built, needs client ID).

STORE RULINGS BATCH (2026-07-08, user checkpoint): (1) DISCOVER LEADS WITH THE TRACK-ANYTHING BRIDGES — Dexscreener ("Track any token"), Wallet ("Track any wallet's activity"), Farcaster ("Track any Farcaster account") head the story carousel in that order; the pair-a-client card and other connectable bridges backfill (cap 4). Taglines were corrected from "your own" framing — these bridges watch ANY public token/address/account. (2) CATALOG = CATEGORY SHELVES, not a flat top list: one labeled shelf per category (Your life, Onchain, Social, …), App Store style; the chip strip and ranked "Top apps" chart are gone; connected apps stay in the strip so nothing repeats. (3) CONNECT SHEETS READ LIKE PRODUCT PAGES: every setup screen opens with BridgeSetupHeader (icon 60 + the catalog offer's own summary — one source of words), fields/steps at body17, real 36pt Connect buttons, no hairlines. (4) HOME STARTER STATE: an empty or sparse corpus (<8 things, no tag clusters) previews the real modules — TagMapPreview (muted fill, kind names, NO tap targets; renderer case "TagMapPreview") and the Threads widget with Skeleton rows — so a new user sees the shape home takes instead of a bare screen. Preview ≠ fake data: kind names and skeletons only, per the honesty rule. (5) The pair story card names Claude only (Raycast had no catalog presence; the sheet's "any MCP client" covers it). Also fixed this session: the Discover story cards' Connect was DEAD for needsSetup bridges (BridgeConnect.connect no-ops outside the five system bridges) — story cards and the app-detail Fix button now route needsSetup offers to their setup screen, the same split the chart rows use. TAB RE-RULING (2026-07-08, user: "should our tab bar icons be casberi blue? we have the app icon like that"): the selection LOZENGE is now Casberi blue with a WHITE icon+label — the active tab echoes the app icon (white marks on blue field). The 2026-07-06 ruling against blue ICONS stands; this is its inverse and keeps contrast in both themes.

COMPOSER SMARTS (2026-07-08, user: "yes do all"): five upgrades, all honoring typed-text-never-saves. (a) LLM ORGANIZE FALLBACK — wording the strict parser misses ("put everything about lisbon under Trip") goes through the on-device model (OrganizeLLM, file-scope @Generable) which fills the SAME OrganizeCommand → proposal card; the write still waits for Apply. Gated on organize-ish verbs so questions never pay extraction latency. VERIFIED live via -composerType. (b) TAG AUTOCOMPLETE — the draft's last token (2+ chars) prefix-matches real tags; chips complete the word. (c) DATE-AWARE ASKS — "today/yesterday/this week/last week/this month/<weekday>" become a capturedAt range filter in retrieve() (DateQuery), date words leave term scoring; a bare date ask lists the day. VERIFIED: "what landed today" returns only today. (d) ASK CHIPS ON EMPTY — re-ruling: the 2026-07-06 "chips died" ruling covered GENERIC canned chips; these are asks DERIVED from the live corpus ("What landed today?" only when something did, "Show <top tag>"), tap = send. VERIFIED rendering. (e) LINK TITLE ENRICHMENT — a pasted/dropped URL saves instantly, then LinkTitle fetches the page <title> (5s cap, 64KB) and renames the thing when its face is still the URL; offline keeps the URL. VERIFIED live (apple.com → "Apple"). New hooks: -openComposer, -linkTitleProbe. ADDENDUM (same session): NAVIGATION ASKS — "show/open/see <place>" jumps straight there instead of answering ABOUT it: a real tag → its tag view, a connected source → its filtered feed, a kind word → the type-filtered feed (NavigateCommand; leading verb only so questions stay asks; reads only, no proposal needed). VERIFIED live: "show my work stuff" typed → Work tag view. SUMMARIZE cues widened (synthesize/digest/tl;dr) — synthesis mode already existed and VERIFIED ("summarize my week" → streamed prose). CATALOG JUMP CHIPS — the category chips return ABOVE the shelves as NAVIGATION, not filters (the filter version died with the flat chart): tap scrolls to that shelf; only categories with something to add render a chip.

STEAM + OBSIDIAN + TWITCH (2026-07-08, user: "lets do all three"): STEAM — free Web API key (steamcommunity.com/dev/apikey) + public profile name/SteamID64; recently played games land ONCE per game as links to store pages (ref steam:<appid>); two-field screen like Mail; vanity names resolve via ResolveVanityURL and cache; failed fresh keys don't stay. UNTESTED live (needs the user's key) — debug `-steamBridge "<key>:<profile>"`. OBSIDIAN — a vault is a folder of Markdown, so it connects by POINTING AT THE FOLDER (fileImporter → security-scoped bookmark); .md files land as note things (ref obsidian:<relative-path>, newest 100 per sync so big vaults arrive in waves), read-only enumeration, fully local. VERIFIED LIVE in-sandbox: 3 files (incl. nested) landed, dedupe holds — debug `-obsidianVault <path>`. TWITCH — device-code flow scaffold (public client, no secret, refresh tokens; polls until the person enters the code at twitch.tv/activate); followed channels' LIVE streams land as links (ref twitch:<stream-id>). GATED on TwitchAuth.clientID from dev.twitch.tv/console/apps (client type PUBLIC) — stays a Soon card with a store preview; the device-code setup screen arrives with activation. NO email allowlisting anywhere — the user asked; it's just a client id, same as Spotify/Reddit. New group "Your games" folds into the "Your media" category. RULED OUT same session: LinkedIn (partner-gated API), WhatsApp live (no personal API — chat-export import via the share extension is the honest future path), Etherscan (redundant with Alchemy), Apple/Google Maps (no saved-places APIs), Bear/Craft (no read APIs). UPDATE (same day): STEAM CONNECTED LIVE by the user (own key + profile via the app). TWITCH ACTIVATED — client id 49rla6akq1thul05u8utbxk013xv0t (public app, not a secret) pasted, catalog flipped connectable, TwitchScreen ships the device-code flow (big code + one-tap twitch.tv/activate link + 5-min poll); VERIFIED LIVE end-to-end in the sim: device flow approved by the user, token stored, follows query returned (0 live at test time), connected UI renders with Disconnect. All three bridges now live or user-connected.

MCP PAIRING GATED BEHIND transportReady (2026-07-08, user: "i really don't want to set up and maintain a server"): the pairing UI shipped as final design (§34) but its endpoint needs the Goal-3 server, which the user does not want to run — and a scannable QR with no wire is both a dead control (our own honesty rule) and an App Review Guideline 2.1 completeness rejection waiting to happen. So every pairing surface is now behind a hard compile-time gate `MCPPairing.transportReady = false` (same pattern as SharedStore.cloudKitReady): Claude drops out of AppsScreen.actionable() to tier 3 (wears the standard Soon capsule in the chart and on its product page), the pair-a-client story leaves the Discover carousel, and PairClientSheet becomes unreachable outside DEBUG (`-openPair YES` still opens it for design work). Nothing was deleted — the Keychain token, the sheet, and §34's design all stand; if a transport ever exists (a server, or something serverless), the flip is one line. Verified on sim: Claude product page shows Soon; Apps page renders with no pair story.

BANKR REPLACED BY DEXSCREENER — WATCH ANY TOKEN (2026-07-07, user: "replace bankr with dexscreener in our catalog"): Bankr's launched-tokens bridge was NICHE (only token creators; overlapped Zerion's onchain reads) while token-WATCHING is the general capability the token chart unlocked. So Bankr is GONE (BankrIngest/BankrScreen deleted; creator-fees, the treemap, the -bankrAddress hook, and the last trade-approval demo thing all removed) and DEXSCREENER takes its catalog slot: paste a token address/symbol/link → Dexscreener's public search (no key) resolves the most-liquid match → it joins YOUR WATCHLIST as a thing (tag "Watchlist", source "Dexscreener") whose sheet draws the native price chart. Model/TokenWatch.swift (resolve+add) + Screens/DexscreenerScreen.swift; wired through the one router/catalog/refresh tables; official eagle icon bundled. HONESTY: this is the user's OWN watchlist from PUBLIC price data — NOT a sync of their Dexscreener account (no watchlist API), and never trading. Verified live: "bankrcoin"→BankrCoin·$BNKR, "degen"→Degen Arena·$DEGEN, both watched. Debug: `-watchToken <query>`. SEVENTEEN bridges still (Bankr out, Dexscreener in).

TOKEN PRICE CHARTS, NATIVE (2026-07-07, user asked "can we show a price chart?"): yes — but Dexscreener's own API gives only a current price, no history, so the CURVE comes from GeckoTerminal's free public OHLCV (no key) and Casberi draws it itself with Swift Charts, not an embedded web chart (native content, per the law). A token thing whose content is a dexscreener link now LEADS its Ink sheet with a price header ($price + 24h% in confirm-green up / destructive-red down) over a native line+area sparkline — the token's "media", like a screenshot leads with its image. Illiquid/dead tokens have no pool → it falls back to the plain link, never an empty chart. Model/TokenChart.swift (route parses chain+address from the dexscreener URL; fetch = geckoterminal tokens→top pool→24h hourly candles) + TokenChartContent in ThingContent.swift. Verified live: DEGEN → $0.00153313, -2.1%, real curve. This is Casberi's token-render answer; Dexscreener stays the destination + the price source, never a catalog bridge (no watchlist API).

OPENCLAW IS REAL — CLEANED, NOT GUTTED (2026-07-07): OpenClaw is a genuine self-hosted agent gateway (docs.openclaw.ai — routes agent requests, exposes conversations over MCP), so its "agents' work + approvals land here" is honest, unlike Bankr's invented trade-approval. Fixes: the demo/preview approval was SELF-REFERENTIAL ("Deploy casberi-api to production · railway up") — changed to a generic agent action ("Deploy the staging build · deploy --env staging"); a ShapedRows eyebrow comment still cited the now-stale "BANKR · VIA OPENCLAW" (Bankr is a direct read bridge now) → "CLAUDE-CODE · VIA OPENCLAW". DEXSCREENER IS NOT A BRIDGE (2026-07-07, user asked): its watchlist is account/local-bound with NO public read API (same wall as Bankr memory), so a "read your Dexscreener watchlist" bridge is impossible. But Dexscreener IS already the destination for token things (Bankr tokens link there), and its public token-data API (api.dexscreener.com, no key) could power a Casberi-NATIVE token watchlist (paste an address → price lands) — a candidate feature, not a catalog app. Parked pending user call.

BANKR MEMORY IS UPLOAD-ONLY → NO MEMORY BRIDGE (2026-07-07, user: "you can only upload to bankr not download its files"): Bankr's agent memory (/.memory/ markdown: user_*/project_*/reference_*, same format Casberi itself uses) IS genuine private user data — but you can only ADD files to Bankr, not export/download them, and there's no read API. So a memory bridge would be a dead control (nothing to read in). A half-built markdown importer was REMOVED for exactly this reason. Lesson reinforced: verify the data can come OUT before building an in-bridge. BANKR LAUNCHES RENDER AS A TOKEN CHART (same turn, user asked): the tokens land as feed things (links) AND the Bankr screen shows a live TagMap treemap of them sized by fees earned (sqrt-scaled so a big earner doesn't slice the rest into slivers — the Zerion lesson), built from the real creator-fees data, no demo gate. The store preview uses the same treemap. Verified live: a creator address → 5 tokens + a rendered MODDS/MTK/AGD treemap.

BANKR IS REAL — AND READ-ONLY (2026-07-07, user, after reading docs.bankr.bot together): the old framing was FICTION — Bankr's API exposes no "asks you before each trade" approval flow; Bankr agents trade directly. What a Bankr user actually CREATES and owns that's publicly readable is the TOKENS THEY LAUNCH (their "files/folders" turned out to be shared developer Skill packages in a public git repo, not personal files — wrong fit). So Bankr is now a READ BRIDGE in the Zerion/Bluesky mold: paste your creator wallet address, and the public creator-fees endpoint (`GET api.bankr.bot/public/doppler/creator-fees/:address` — unauthenticated, no key, per the docs) returns every token that address launched; each lands as a link thing to its dexscreener page. Ref `bankr:<tokenAddress>`. Casberi NEVER trades or moves funds — executing a trade would need Bankr's REST API and violates our law + the prohibited-action rule; reading launches is safe and honest. Verified live: a creator address → 5 tokens in, 0 on re-run, malformed → FAILED. RULING: any bridge to a trading/agent platform is read-only until proven otherwise; check the actual docs before writing catalog copy (the old Bankr summary described a mechanic that didn't exist). Debug: `-bankrAddress <0x…>`. SEVENTEEN REAL BRIDGES.

INK SHEET TYPE SCALE, FULLER (2026-07-07, user: "fill this sheet better and more welcoming. same format, just w/ different font sizes"): same structure, bigger type — the title is now heading34 (display), spec-table values are body17 (was callout15), the TAGS line matches at 17pt, and action rows carry 18pt icons + heading17 labels with roomier vertical padding. The metadata reads substantially instead of whispering, and the rows fill the sheet. The tag-detail toolbar's rename control is now a text "Rename" button (was a bare pencil — a lone icon didn't read as rename; a nav-bar Label collapses to icon-only, so it's a plain text button like iOS "Edit").

THE INK SHEET (2026-07-07, user picked "Ink with Gallery grafted in" from three mockups, then "i like it"): the thing sheet is INK-BLACK IN BOTH MODES (like a photo viewer; the sheet forces dark controls), no cards, no hairlines — spacing separates. Structure: eyebrow (6px source-colored dot · KIND · AGE), title large, the thing's media (a screenshot leads with its image — sample refs now load their bundled photos here too), then Gallery's spec table with per-kind labels (WHEN for events — replacing the old ScheduleCard; SITE for links; BY for agent provenance; FROM; TAGS). Tags read as a text line — type tags gray, your tags in their hue — and tapping the row opens the full chip editor in place (add, remove, rename everywhere, delete everywhere: nothing lost). Verbs are quiet text rows (derived, cap three; writes still confirm), plus Pin (new to the sheet) and Share as rows. The Related shelf still streams last.

THE GLASS (2026-07-07, user; amended same day — NO POUR): onboarding's sixteen icons fall as BIG 84pt cubes, one after another with real bounce, stacking bottom-up until they fill the BOTTOM HALF of the screen — ice filling a glass — and they STAY at full size. The feed card lives in the top half from the start; nothing shrinks. APPLE HEALTH LEAVES ONBOARDING (same turn): health data reads as sensitive before trust exists — minute zero offers Photos, Calendar, Reminders ("Start with three"); Health waits in the store one tap away.

HANDLE FIELDS CARRY THEIR FIXED PARTS (2026-07-07, user): the person types only what's theirs — Farcaster's field shows a gray "farcaster.xyz/" before the name; Bluesky shows a gray ".bsky.social" after it (stepping aside when the input carries its own domain, so custom handles still work). Pasted profile URLs normalize too: https://farcaster.xyz/dwr, warpcast.com/, bsky.app/profile/ prefixes all strip to the bare name (verified live: the full URL resolved and synced). New hook: `-openSetup "<Offer name>"` pushes a setup screen directly.

THE RAIN MOVES TO THE BOTTOM (2026-07-07, user; supersedes T2's top marquee): the catalog's sixteen icons now fall the FULL height of the screen and bounce into a two-row shelf just above the CTA — the drop still acts out the headline, and the settled pile sits where the person's thumb is headed. Onboarding is NOT the catalog (ruled same turn): thirty offers at minute zero is choice paralysis, token bridges need out-of-app steps, and the four one-tap connects produce a live feed in seconds — the store is one tap away after landing.

TOKEN ICONS LIVE AT ROW SCALE, NEVER IN THE TREEMAP (2026-07-07, user asked "icons or just the name?"): the holdings treemap stays text-on-color — it's the same TagMap element Home uses, tickers are the recognizable identity in this domain, and small tiles can't afford icon+label. Transaction rows DO open with a token mark: the ARRIVING asset leads (last ticker in a swap), bundled coin marks for majors (ETH/SOL/LINK), a brand-colored monogram coin for everything else (USDC and the long tail — also the plan for live Zerion data). DEMO SCREENSHOTS ARE FOUR NOW, WORLD CUP (user: same image four times looked wrong): four Pexels photos (their license permits bundling) — scarf crowd (the Home cover), ball at dusk, packed bowl, match action — as sample-screenshot-1…4, with the four demo things retitled to match (Saturday's match / Sunday five-a-side / Watch party — Sunday's final / Match day — from Dani's story), cluster tags unchanged.

ONE WORD FOR THE GROUPING: TAG (2026-07-07, user: "i don't think i want to [say project]"): the person-facing word is TAG, everywhere — the app never says "project". What the tag IS: a name on things that belong together — not a folder (a thing carries many tags), not a project (Fitness and Home aren't projects). Two flavors, one internal distinction: type tags the app assigns (Link, Event — structural, unrenameable) and the person's own tags (free names; the first one wears the color and the treemap tile). Code identifiers (ProjectHue, projectTag, ProjectDetailScreen) stay — invisible, and renaming them mid-refactor-sessions invites conflicts. Fixed leaks: empty-Home tile ("Tags appear here"), rename placeholder ("New name"), VoiceOver label ("Rename tag"), website ("your tags as maps").

ORGANIZE BY COMMAND (2026-07-07, user: "yes lets add that"): the composer now understands two typed commands — "tag <things> as <name>" (also label) and "rename <a> to <b>" (also change all … to …). THE RULING HOLDS: typed words never write silently — a command streams a PROPOSAL CARD (the matched things, the exact change, Apply/Cancel); the write happens on Apply, the toast reports it and carries Undo (full tag-state restore). Matching is precise because it gates a write: kind words (links, screenshots…) filter by kind, every remaining word must hit title/content/source/tags. Built-in type tags refuse both verbs. A tag command skips things already carrying the tag ("Nothing new matches" when all do). Verified headless: tag lisbon as Trip → 6 proposed → applied; re-run → nothing new; rename Trip to Travel → 6 renamed. Debug: `-organizeApply YES` auto-applies the `-uiAnswerProbe` command. "Ask anything. Organize everything." is now honest — restored on the website.

WEBSITE CATALOG RULING (2026-07-07, user): every app row on the landing page's catalog says CONNECT — no "Share" chip, no split legend, no coming-soon framing. The user chose the uniform verb knowingly (option "All 'Connect' anyway") after being told 13 of the listed apps have no live bridge yet and reach Casberi only through the share sheet. Any session editing website/ must keep this: one `getbtn` style, one legend row, no "Sixteen connect" split copy.

FARCASTER IS REAL — the sixteenth bridge (2026-07-07, verified live): like Bluesky, a username alone — casts are public on the open protocol, and the Farcaster team's own public Snapchain node (snap.farcaster.xyz:3381) serves name→fid and casts with no key. Your casts (not replies) land as chat things linking to farcaster.xyz permalinks (verified against dwr: 10 in, 0 on re-run). SPOTIFY IS BUILT AND GATED: the full sign-in (OAuth PKCE, run entirely by the phone — no server, no secret) and liked-songs ingest exist in `Model/SpotifyBridge.swift`, but the offer stays a Soon card until a client ID from developer.spotify.com is pasted into `SpotifyAuth.clientID` — no dead controls. AUDIT FIXES LANDED: `-uiAnswerProbe` no longer trips the paste heuristic (probes answer, never save); `casberi://thing/<id>` resolves real ids (verified: opens the thing sheet); treemap tile labels shrink further before truncating at accessibility sizes; onboarding taglines fit their line; CLAUDE.md's hook list and ship-gate line brought current.

M1 LEFTOVERS CLOSED (2026-07-07): (1) VOICE AUDIO LIVES IN THE STORE NOW — `Thing.audio` with externalStorage, so CloudKit mirroring carries recordings as CKAssets; new recordings move in at save, legacy loose files migrate in once at launch and are removed; playback prefers the model's bytes. (2) DELETE EVERYTHING CLEARS ICLOUD TOO — after the local wipe, the CloudKit zone is purged outright (covers things synced before the toggle was last turned off), and the outcome is reported honestly: "Deleted — this iPhone and iCloud." or, on failure, that the iCloud copy remains. (3) ONE MIRROR ONLY — the widget and share extension open the same store through `extensionContainer()`, which never engages CloudKit mirroring; the app is the only process that syncs, and extension writes reach iCloud the next time the app opens. The sync toggle's ship gate is now fully honest end to end.

NOTION AND LINEAR CLOSE THE TOKEN RUN (2026-07-07): the last two paste-token bridges, and a RULING with the first — NOTION BRINGS PAGES ONLY, not databases (user, 2026-07-07: "for notion pages only"). Notion connects with an internal-integration secret and sees only the pages the person explicitly connects to it (the setup steps say so — page ⋯ → Connections); connected pages land as note things carrying their notion.so links, newest edits first, archived and trashed never land. Linear connects with a personal API key against its GraphQL API (the key rides the Authorization header bare); issues assigned to you land as links titled "ENG-123 · Fix the login race". Refs `notion:<id>` / `linear:<uuid>`. Same shared screen, Keychain, foreground refresh; a POST helper joined the GET one for these two. EIGHT TOKEN BRIDGES TOTAL, FIFTEEN REAL BRIDGES. Verified: build + reject paths + Notion store page; happy paths await real tokens like the rest of the run.

CAL.COM AND CALENDLY JOIN THE TOKEN RUN (2026-07-07, user-requested): both scheduling apps hand users a personal token — Cal.com an API key (Settings → Developer → API keys, v2 REST with a dated `cal-api-version` header), Calendly a personal access token (Integrations → API & Webhooks; works on the free plan — only webhooks are paywalled, and we poll instead). Both land bookings/meetings as EVENT things beside Calendar (same feed shape): Cal.com titles link to the app.cal.com booking page, Calendly carries the join URL when there is one; cancelled ones never land. Refs `calcom:<uid>` / `calendly:<uuid>`. Same shared TokenSetupScreen, Keychain, foreground refresh. Brand icons bundled (simpleicons marks on brand color). THIRTEEN REAL BRIDGES. Verified: build + reject paths + both store pages; happy paths await real tokens like the other four.

THE TOKEN BRIDGES — Readwise, GitHub, Todoist, Raindrop (2026-07-07): four apps whose settings hand every user a personal access token, pasted once into ONE shared screen (`TokenSetupScreen`) — numbered steps to find the token, a SecureField that sends it straight to the Keychain (`TokenVault`, generic-password items, never UserDefaults), proof when things land, and a Remove-token row that stops syncing but keeps what landed. Each fetch goes from this iPhone to the app's own API with the token as the only credential — no OAuth server, no secrets of ours. What lands: Readwise highlights as notes (text + book—author line, via the export API), GitHub issues/PRs that involve you as links (search API, newest 30), Todoist open tasks as reminders, Raindrop bookmarks as links. Refs `readwise:/gh:/todoist:/raindrop:`; foreground refresh alongside RSS and Bluesky; a rejected token reads "That token didn't work — check it and paste again." ELEVEN REAL BRIDGES. Verified: build + reject path headless (`-tokenBridge "GitHub:<bogus>"` → graceful FAILED) + Readwise product page live; the four happy paths await real tokens — first hand-test should paste one and confirm parsing.

CHATGPT AND BLUESKY ARE REAL — bridges six and seven (2026-07-07, both verified live): (1) ChatGPT connects by IMPORT, exactly as the offer always said — its screen states the three steps that happen on OpenAI's side, then one button picks `conversations.json` (fileImporter, security-scoped); each conversation lands as ONE chat thing titled as the person titled it, dated when it last moved, its first user message as the content line; capped at the newest 500; re-imports dedupe on the conversation id (verified: 2 in, untitled skipped, re-run 0-in-3-skipped). (2) Bluesky connects with A HANDLE ALONE — the AT Protocol's public AppView serves a person's own posts without auth, so v1 stores nothing but the name: no password, no token, nothing to leak (the offer says so; likes arrive later with app-password sign-in). Posts land as chat things linking to their bsky.app permalinks, refreshed on foreground (verified live against the bsky.app account: 23 in, 0 on re-run). Setup routing generalized: `SetupDestination` switches Connect-needs-input bridges to their screens from both the chart and the product page; the connected strip routes rss/gpt/bsky ids home. SEVEN REAL BRIDGES now: Photos, Calendar, Reminders, Apple Health, RSS, ChatGPT, Bluesky — four local, three reaching out, zero servers. Debug: `-chatgptImport <path>`, `-bskyHandle <handle>`.

RSS IS REAL — the fifth bridge, and the first that leaves the phone (2026-07-07, built + verified live against daringfireball.net: 15 posts ingested, zero duplicates across relaunches): `RSSIngest` fetches every followed feed directly from the app (RSS 2.0 + Atom via one XMLParser delegate), lands the newest 15 posts per feed as link things (title, link as content, the post's own pubDate so history sorts honestly, `rss:` guid sourceRef dedupe, Spotlight), and refreshes on every app foreground and every visit to its screen — no server, no account, no algorithm, exactly as the offer says. `RSSStore` keeps the followed list (paste a URL, scheme-forgiving, learns the feed's own title on first fetch); `RSSScreen` is the Zerion-pattern manager (Following / Add / Recent / the honesty footer). NEW OFFER MECHANIC: `needsSetup` — bridges that need input first (feed URLs; later, pasted tokens) get Connect-opens-their-screen instead of a permission ask, and they SKIP onboarding's mini store (that card is one-tap connects only). Races taught a lesson worth keeping: two concurrent refreshes both read "existing" before either saved and double-inserted — ingest is now serialized with an in-flight guard; every future remote bridge inherits the rule. Debug: `-rssFeed <url>` follows and syncs headlessly.

Apps + Home tidy (2026-07-07, user): (1) two-digit chart ranks were wrapping vertically in a 20pt column — 26pt + lineLimit(1) + minScale now. (2) The browse shelf grew with the catalog: eight chips — Your life, Your fitness (Strava exemplar), Your wallet (wallet + network groups, Zerion exemplar), Your agents, Your mail, Your work, Your reading (reading + saves, Readwise exemplar), Your media. (3) "FOR YOU" renamed "TOP APPS" — it was never personalized, and the store word is the honest one (user: more like the App Store). (4) Home's signals Bento (StatTiles like "Landed this week · 8 things already") DIED — user: "these aren't that helpful"; they were counters wearing a costume, and the no-counters rule finally caught them. Home is now cover · insight · map · pills · pinned · threads.

Landing after onboarding (ruled): FEED. The person just connected apps; the reward is watching their own things arrive — Home needs corpus mass to compose anything worth reading on day one, and the store is what they just finished. Home remains first on the tab bar.

Dev corpus quarantined from onboarding (2026-07-07, user hit it: the DEBUG demo corpus's fake approvals appeared after a hand-tested onboarding run and read as real): `DemoState.seedsDemoData` now decides ONCE, at first launch — if the install starts already-onboarded (the dev flow's `-onboarded YES`), the corpus seeds as always; if it starts at the Connect screen, `demo.corpusAllowed` locks to false and that install stays corpus-free forever, even after onboarding completes. Verified both ways: a no-args fresh run lands on the honest empty feed across relaunches; the dev launch keeps the full corpus. Release builds never seed regardless (unchanged).

APPLE HEALTH IS REAL (2026-07-07): the fourth connectable bridge, and the first added after launch trio. `HealthIngest` asks for workout read access in context (HealthKit entitlement + NSHealthShareUsageDescription added; read-only, on-device — the offer's summary now says "HealthKit never touches a server"), pulls 30 days of workouts (cap 50), and lands each as an event thing — "Run · 5.2 km", "Strength · 45 min" — deduped on the workout UUID (`hkworkout:` sourceRef), Spotlight-indexed. It joins the onboarding mini store automatically (third compact row) and Apps' Connect paths. HealthKit quirk, accepted: read-denials are invisible by design — a denied grant just yields zero workouts, so the bridge reports "Synced just now" rather than an error. Hand-test needed on sim/device: the permission sheet requires a real tap, and the sim's Health store is empty until workouts are added in the Health app.

Connect screen, final form — S3 hero + shelf (2026-07-07, user-picked from mockups): the screen is now App Store anatomy with hierarchy — ONE featured hero card (Casberi blue, "START HERE", Photos with a white Connect capsule), two compact rows (Calendar, Reminders), and a "WAITING INSIDE" shelf of the catalog's real brand tiles trailing off the screen edge (dimmed 85% — coming, not tappable). H3 hero (2026-07-07, user-picked from five hero alternatives — the flat blue card read as a photo slot with no photo): the featured card and the connect rows MERGED into one "YOUR FEED" card that IS the store. Four slots, one per real bridge: waiting, a slot shows the app dimmed and desaturated with its Connect capsule; the moment it connects, the slot fills IN PLACE — icon springs to full color, the line flips to present tense ("Your screenshots, flowing in" · "just now" in confirm green), a green check lands with a scale-pop, height never changes (rhythm law). Each connect also fires a success haptic and the screen's own toast capsule above the CTA ("Photos connected" — the shell's toast is behind the cover and can't be seen). When all four are in, the card's eyebrow flips to "YOUR FEED · FLOWING" and the CTA becomes "See your feed". The hero is a reward the person builds with their own taps. Amended to T2 the same day (user, from a second mockup round — the bottom shelf's icons ghosted over the CTA and showed too few): the MARQUEE moved to the TOP and the rain lands FIRST — 16 icons (Zerion and Farcaster leading, per user) fall across the top edge with spring bounces, staggered 45ms, settling with a deterministic per-icon jitter so the row sits slightly uneven, like things that actually fell; the headline ("All of this lands here. Start with four."), hero, and rows arrive beneath in sequence. A Spacer floor (84pt) keeps the last connect row clear of the docked CTA — the hero absorbs the slack instead. One-shot entrance; the no-idle-motion law holds (continuous wiggle rejected). Real connects unchanged. BLUESKY joined the catalog same day ("Your network", next to Farcaster; AT Protocol's open API is sanctioned by design; official butterfly tile bundled; chat shape; store preview).

Catalog grows by eight (2026-07-07, user-picked from the sanctioned-API shortlist): Apple Health + Strava (new group "Your fitness"), Todoist ("Your schedule"), Slack ("Your messages"), Raindrop ("Your saves"), Readwise + RSS (new group "Your reading"), Farcaster (new group "Your network") — all connectable:false with honest taglines/summaries, each with an engine-streamed store preview. Apple Health's summary states it plainly: HealthKit is on-device, so it is NEXT IN LINE to join Photos/Calendar/Reminders as a real bridge. Real brand tiles bundled for Strava/Todoist/RSS/Farcaster (simpleicons marks on brand fields) and Slack (official multicolor from svgl on white); Apple Health keeps the SF heart tile (Apple restriction); Raindrop and Readwise use SF-fallback tiles until their kits yield assets. Feed shapes: Slack/Farcaster read as chats, Todoist as reminders. Skipped deliberately: Discord (no sanctioned user-message API), Pocket (shut down), Obsidian (local-only — share-sheet, same ruling as Notes). Logo pipeline note: svgl (~550 SVGs, light/dark variants, API) is the source for future icon work.

DEMO MODE IS DEAD — OPTION 4 (2026-07-07, user ruling after the real-vs-fake rethink; supersedes the entire onboarding-demo architecture): the feed is 100% REAL from the first minute, and the dream moved to the store pages. Why: mixing real and sample data forced a dissolve mechanic and copy ("samples fade as your real things arrive") that told a brand-new user some of what they see isn't theirs — poison in an app whose spine is "your things are yours." What shipped: (1) Onboarding = the mini store's three real connects, then the app. No demo shell, no DEMO pill, no Get started, no contract line, no sample things, no dissolve — OnboardingSamples/OnboardingDemo deleted; a launch migration removes any samples earlier builds seeded; Thing.isSample stays in the schema (CloudKit-safe, needed by the cleanup). (2) STORE PREVIEWS: each not-yet-connected app's product page streams a small preview of its shape through the REAL gen-UI engine (StorePreview docs → ApprovalCard/TxRow/MailRow/TakeawayCard/TagMap/Widget display twins), inert, captioned "A preview — this bridge arrives with the connected apps update." Fake content confined to the one surface where preview framing is honest — the App Store screenshot, generated. Connected apps skip the preview and show their real state. (3) First-run teaching survived, re-keyed off demo: the chip coach line and the swipe-hint nudge (first row nudges left once, the pin peeks, it settles) fire once ever, in the real app; the composer's demo ask died with its sample project. (4) The truly-empty feed earns one door: a "Browse apps" chip under the quiet berry. Mini-Home and HomeRoute.project died with the demo.

Connect screen, step 2 — CONNECTIONS ARE REAL (2026-07-07, supersedes demo-only picks; user caught the inconsistency: the demo faked picks while the Apps door one screen later connected for real): screen 1 is now a MINI STORE of exactly the three bridges that work today — Photos, Calendar, Reminders — and Connect runs the real flow; the iOS permission dialog IS the in-context ask, one app at a time (this also satisfies the staged-permissions ruling for these three). One quiet line points at the rest ("More apps wait inside — agents, mail, your wallet."). Samples now seed ONLY for showcase apps that cannot connect yet (sampled minus connected) — real sources bring real things from minute one, so the dissolve never touches them; the exit contract line trims to "Samples fade as your real things arrive." The story carousel, For-you chart, and pick preview left this screen (they live on the real Apps page). APPS DOOR PULSES (same day, user): the attention DOT died — when a bridge needs reconnecting the grid glyph itself pulses (SF symbolEffect .pulse, repeating). One signal, alive instead of stuck on.

Connect screen, step 1 of the screen-by-screen onboarding pass (2026-07-07, user-driven): the subline trimmed to "Connect what you keep tabs on." (the "as many as you like / sample things fill in" tail was space, not information — the pick preview now SHOWS samples filling in). Story cards wear an EDITORIAL palette — Casberi blue #1673e6, deep violet #6d28d9, deep teal #0e8f7e — never the apps' brand colors (Calendar and Gmail are both red-logo apps and painted the carousel red; red is not the brand). The app's identity lives in the card's icon; the card surface is ours. Next onboarding screens iterate one at a time on the user's call.

Sample image + micro-interaction batch (2026-07-07, built + verified): sample and demo screenshot things now carry `sample:` sourceRefs that resolve to a bundled photo (`sample-screenshot` — user-supplied; unique refs because the CloudKit dedupe collapses identical ones), so the demo Photos grid, PhotoWells, and Home's image cover show a REAL photo — the H7 cover with bleed extraction was verified live for the first time. Micro-interactions, all one-animation-per-moment: the Connect screen settles in top-to-bottom (headline → stories → chart, one pass); pick capsules and Home's map tiles and kind pills press with a soft spring (shared `PressSpring` ButtonStyle); Approve/Deny animate the card's exit and speak their outcome ("Approved" toast). NOTES POSITION (ruled, user raised it): Casberi does not author or edit notes — typed composer text never saves (standing ruling), note things enter only via capture (paste, share sheet, voice), and content is never editable in-app (tags/marks/pins are the person's hands; content is the record). We collect and connect; Apple Notes authors. If a real quick-jot itch emerges, it becomes a deliberate capture path later — never an editor.

Onboarding round 2 (2026-07-07, built + verified): (1) STAGED PERMISSIONS — Get started connects NOTHING; each picked app runs its real connect (and iOS permission ask) the first time its chip is tapped in Feed, then leaves the picked set — one ask, in context, never a dialog stack at exit. (2) The exit block states the contract above the button ("Your apps connect when you first open them — samples fade as your real things arrive."), on its own solid field with a content fade above it. (3) COACH LINES RETIRE on first use: the chip line dies at the first chip tap, the composer's seeded ask dies once run (demo.coach.*.done flags). (4) The Connect screen's picks fill a live "IN YOUR FEED" preview card — one sample row slides in per pick, the "sample things fill in" promise made visible before Continue. "Start empty" was offered and REJECTED (user) — the demo is the only path.

PROJECT PIN DIED (2026-07-07, user: "if all projects are on the home page why do we need a pin?"): correct — every project already sits on Home's map, so a pin that only re-sorted it was a second pin system next to thing-pins. The toolbar pin button, ProjectPins.swift, and the pinned-first map sort are deleted (map sorts by magnitude, then name). The pencil (rename across the corpus) stays — it is the tag-rename the user asked for. Thing pins (Feed swipe → Pinned section + Home Pinned card) are untouched and are THE pin system.

SHAPES ARRIVE IN CHARACTER (2026-07-07, user: chip screens "should generate in different ways depending on type"): tapping a source chip replays a per-shape row entrance (RowEntrance modifier, staggered ≤12 rows, DS.Motion.standard): Calendar slides in from the leading edge like a day filling, Photos cells scale in like the grid, Zerion rows rise under the streaming treemap, everything else lifts gently. One animation per moment — the chip tap IS the moment.

Image-cover legibility + screenshot titles (2026-07-07, user report "stuff is messing up... tied to onboarding"): after the demo's Get started connected Photos for real, ScreenshotIngest imported the person's screenshots — screenshots OF Casberi itself — and the newest became Home's cover, so the cover displayed the app's own UI behind the cover text and read as broken layers. Not a rendering bug, but two real fixes shipped: (1) image covers now carry a base dim (black 35%) under the gradients, so busy images — UI screenshots, dense photos — always read as a photo BEHIND text; (2) ScreenshotIngest titles are just "Screenshot" — the timestamp lived in the title AND capturedAt, pure noise.

COLOR BELONGS TO THE PROJECT — V3b (2026-07-07, supersedes the kind-color band feed; user: the wash "just looks blah", kind colors are unlearnable, and a kind-colored tag showed one project in many colors — all three points correct): feed rows are NEUTRAL cards again (the 28% kind wash desaturated into murk over the dark page — translucent washes were the mistake, not color itself). Color moved into MEANING the person already owns: each PROJECT has one stable hue (`ProjectHue` — deterministic djb2 hash of the lowercased name into a 10-hue palette; never Swift's per-launch hashValue), and that hue writes the tag text on every feed row (11pt medium; light mode mixes 35% toward black), fills the project's tile on Home's map (magnitude still rides opacity, 0.30–0.75), and colors its project-screen header. "Lisbon trip" is ONE color everywhere. Kind color survives where it always lived: glyphs, pills, the cover. Known limits, accepted: renaming a project changes its color (the name is the identity), ~10 hues can collide across many projects, and hand-picking a color is a later settings nicety. Time stays gray (the emphasized next event's countdown stays Casberi blue).

Crash fix, load-bearing (2026-07-06/07, user: "the demo gets stuck when i click a project"): intermittent SIGSEGV — "thread stack size exceeded, excessive recursion" — while SwiftUI instantiated generic metadata for a ForEach view list. GenRender's 25-case component switch nests recursively (Stack → Widget → rows), and the combined generic type got deep enough that FIRST-time instantiation of a new branch combination on an already-deep stack (nav push + zoom transition) overflowed; once cached, the same path worked — hence intermittent. Fix: `AnyView` erasure at GenRender.body (every nesting level flattens) + the same insurance on the feed's row dispatch. Verified: project push + tab flips, zero new crash reports; the project screen's rows also stopped sticking as skeletons. RULE: GenRender.body's AnyView is load-bearing — never remove it for "cleanliness".

Demo lands on Feed (2026-07-07, user): after Continue, the demo shell opens on the FEED tab — the record the samples just filled is where tapping starts. Home stays first on the tab bar (that order is about the app, not the tour). The one-screen demo shell stands — no split into separate Feed/Home tour pages.

Source honesty audit (2026-07-06, user: "make sure the sample entries are actually things we can do or have"): the dev demo corpus carried 4 things with source "Safari" and 3 with source "Notes" — sources that CANNOT exist: neither has a bridge (both ruled share-sheet-only long ago, and Safari/Notes aren't even catalog offers), and share-sheet captures land with source "You". All seven re-sourced to "You". The audit of everything else held: Photos = screenshots via PHAsset (the bridge's actual scope), Calendar/Reminders = EventKit (shipped), Zerion = read-only API (planned, matches the samples' swaps/receives), OpenClaw = gateway approvals + runs (the MCP design), Gmail/iCloud Mail = API reads (planned offers), ChatGPT = one-time import (its chat things read as imported history), Bankr = approvals only (its one thing IS an approval), Voice/You = the composer's own paths. Rule going forward: a demo or sample thing may only carry a source that a shipped or designed bridge can actually produce.

ONBOARDING IS THE APP IN DEMO MODE (2026-07-06, handoff-onboarding — built + verified on the sim, both screens): the three-card pager DIED. Screen 1 (Connect) is the Apps page's Discover anatomy under "Your apps, one feed." — story carousel (real story-card anatomy, next card peeking) and the For-you chart, every capsule a TOGGLE (Connect ↔ green Connected; sampled apps Photos/Calendar/Zerion/OpenClaw/Gmail lead the ranking, other pickables follow, the rest show Soon), bottom fade into the one docked CTA ("Connect one to continue" → "Continue with N apps"). Continue seeds SAMPLE THINGS for the picked apps (`Thing.isSample`, new defaulted field — CloudKit-safe) and reveals the REAL shell in demo mode (`demo.active` AppStorage, survives relaunch). Screen 2 chrome is exactly two pieces: a glass DEMO pill top-center (the cover's date line yields its seat until exit) and a docked Get started below the tab bar. Rehearsable: chips appear only for picked apps (samples are the only corpus) with the ONE feed coach line ("Tap a chip — the feed takes that app's shape."); pin → Pinned section + Home's Pinned card with the §11 lift; Home's map tiles push real project screens; the composer carries the ONE suggested ask ("Show me my Lisbon trip" — canned route: close, casberi://home, HomeRoute.project push; the suggestion-chip ban has this single demo-only exception); the OpenClaw deploy approval Approves/Denies for real (locally). Samples never index to Spotlight, never export, never enter MCP search (filters at all three). EXIT is a dissolve, not a reset: Get started drops demo, fires the real connect flows for the picked connectable apps, and each source's samples delete only once a REAL thing from that source exists (OnboardingDemo.dissolve, run at launch). HONEST DEVIATION: `isSample` things technically ride CloudKit if sync is on — SwiftData can't split one model across stores; mitigated by the dissolve and the three read-path filters. Companion fix with teeth: Home now repaints (paint, not re-stream) when the corpus count changes — it used to compose once on appear and go stale. DEBUG: `-demoPick "Photos,Calendar"` auto-picks and continues for screenshots; `-fresh YES` still simulates the new user.

THE FEED BECOMES BANDS — B2b (2026-07-06, evening; user chose it from mockups after rejecting rails as "very AI" — built + verified dark and light): every feed row is now ONE anatomy, the BandRow, a SEPARATE rounded card washed in its kind's color (hue at 28% over the page, air between rows — amended within the hour, user: "each card should be separate... not a wall of color"; the Fantastical family look that also rules the Home cover). The grammar: the leading icon is the SOURCE (BridgeIcon — where it came from), the wash is the KIND (what it is), the title is one full-width line (events carry their clock time inline — the left agenda time column is dead, user hated it), and the right stack is time over project name in the band's own tint. TAGS ARE PLAIN TINTED TEXT, NEVER A CHIP in rows (ruling: a chip means tappable; row tags are labels — chips live in the filter row, the thing sheet, and the tag tray). The list moved insetGrouped → plain; each row's card is drawn by its own listRowBackground (rounded, inset s4/s1). Surviving exceptions: ApprovalCard (neutral sheet — the consent card still breaks rhythm), the reminders CheckRow (keeps its toggle circle, band-styled trailing), the chat TakeawayCard (pinned/doing), the Photos grid, and Zerion's holdings block. RETIRED: AgendaRow, TxRow, MailRow, ThumbRow, LinkRow, NoteRow, VoiceRow, StatusTickRow, FeedRow — deleted, not parked; the per-source row shapes from handoff-shaped-feeds are superseded by the band (source SECTIONS and synthesis blocks survive). Meta ink: hue mixed 65% toward white in dark / 50% toward black in light.

Approval provenance re-ruling (2026-07-06, user: "you are mixing openclaw and bankr somehow"): the ApprovalCard eyebrow led with three flat provenance fields ("OPENCLAW · BANKR · GATEWAY" — brand soup). Now the ASKER leads (agent, falling back to app) and the arrival route reads as a route: "BANKR · VIA OPENCLAW". The machine name left the eyebrow; the sheet keeps full provenance. Approve semantics restated for the record: TODAY the tap only marks the ask handled locally — no transport exists, nothing leaves the phone (demo). The built design: the agent (Bankr) proposes and executes on ITS OWN rails; Casberi is only the consent gate that relays the yes — Casberi never holds keys and never trades (standing ruling).

Feed row + chip legibility batch (2026-07-06, evening, user-driven — built + verified on the sim, dark and light): (1) ROWS ARE TITLE + CHIP-UNDER — the trailing project chip clipped every long title, and the second text line was "not quite as relevant" (user), so the standard rows (FeedRow, MailRow, NoteRow, ThumbRow, VoiceRow, CheckRow) now run: full-width one-line title, project chip underneath, time top-right. Snippet/content sublines are GONE from those rows — the sheet holds the detail. AgendaRow keeps its time-rail shape and content line (an event's time and people are the point) but its chip also moved under; TxRow and LinkRow keep their shapes (the amount and the domain are the identity). (2) NOTHING-MATCHES EMPTY STATE — a filter with zero hits now shows the filtered app's own icon (or kind glyph for a type filter), a plain line ("Nothing from Venice yet." / "No notes yet."), and a "Show everything" pill that clears filters. The bare "Nothing matches." text died. (3) VOICE SOURCE — voice notes now carry source "Voice" (chip label, icon `waveform`, brand color = the voice kind's pink; launch migration renames old "You" voice things). Typed notes and shared items KEEP source "You" — labeling a typed note "Voice" would be false; the You chip only appears when such things exist. (4) LIGHT-MODE GLYPH CONTRAST — KindGlyph and BridgeIcon's SF fallback pull their hue 30–35% toward black, deepen the fill, and go semibold in light mode; Notes yellow and Reminders orange were unreadable on light chips.

Feed swipe re-rulings (2026-07-06, later the same day — built + verified on the sim): (1) Source chips wear ICONS — BridgeIcon at 18pt leads each chip ("All" stays words-only; it has no app). This supersedes the text-only-chips ruling, which predates the real brand assets; now that the actual logos are bundled, the icon IS the identity. (2) PIN LIVES IN THE SWIPE — the standing per-row pin button (added that morning) died the same day; the trailing swipe now leads with Pin/Unpin ahead of the two read verbs, rows carry no pin chrome at all, and the Pinned section header is the state (TakeawayCard and ThingRow keep their small pinned marks — they render outside the sectioned feed). This is the better fix for the misaligned-pins complaint: no pin column to align. (3) LEADING SWIPE = TAG — full swipe or tap opens `QuickTagSheet` (a 320pt tray: the thing's tags as lit chips with ×, corpus candidates dim, one field for a new tag — the thing sheet's Tags grammar without opening the thing). Settled the same day (user, after two iterations): ONE trailing swipe with three FIXED actions — Pin (blue, edge seat, full swipe pins), Tag (green), Open (gray). No More, no verbs on the swipe at all — the derived read verbs live only in the sheet now. The swipe is navigation and organizing, always the same three, on every row. No leading swipe. One-sheet amendment (user: the tag tray duplicated the thing sheet): QuickTagSheet is DELETED — Tag opens the same ThingSheetView landed on its Tags field (focusTags scrolls there on appear), Open opens it at the top. One sheet, two doors. FINAL FORM (2026-07-07, after real-thumb testing — user: the Tag seat kept misfiring the pin, and "tap on event and swipe tag do the same thing don't they" — correct): ONE gesture, ONE meaning. TAP opens the thing sheet (tags, verbs, everything — the sheet is confirmed KEPT as the one detail surface). SWIPE = Pin (blue, edge, full swipe pins) + OPEN IN THE SOURCE APP (gray, only when a real destination exists: calshow://, the link's URL, photos-redirect://, the source hand-off — the first derived .openURL verb). Tag and open-the-sheet left the swipe as tap-in-disguise duplicates; the quick-tag plumbing is deleted; ThingSheetView keeps focusTags for future use.

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
One surface token `--ds-surface-sheet` (#111113 dark, #fff light) for cards, tiles, trays. Tinted background washes are banned. Text ramp: white / 60% / 30%. Hairline separators died by amendment: rows separate by spacing and press fills, groups by their card surfaces; nothing draws a line — the one exception is the Apps page's `fillLine` divider between the CONNECTED strip and Discover (the newer, more specific ruling at line 491, where the line does semantic work: management above, store below). SF ramp: 34/22/17/15/13/12/10. Squircle radii: cards 10, sheets 16, app icons 22.37%. Motion: 250ms, Apple sheet curve, one animation per moment. Every value routes through a token; components hold zero raw hex.

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

## 35. Feed volume rulings (2026-07-09)

Four rulings from the first real-corpus flood (one wallet connect landed 100 transactions over the saved articles and photos):

- **Bundling — volume compresses, never reorders.** In the All shape, 4+ bundleable things from one source in one day collapse into one band row ("Wallet · 14 transactions"); tap opens that source's chip, whose shape is where volume is designed to live. Human capture kinds never bundle (screenshot, voice, approval, anything from You) — each is one deliberate act; machine bulk (transactions, synced articles) is one act producing many rows. The day header keeps the true total. No ranking, no algorithmic feed — the Reminders "Older" collapse, applied to arrival volume. Single-source shapes never bundle (the shape IS the source).
- **New-since divider.** One timestamp (last time the person left Feed), one text row at the boundary — "New since 9:41 PM". No per-thing read state, no drawn line (hairline law). Frozen per visit so it doesn't move while you look.
- **Perishables show their clock everywhere.** The next event's countdown and a Twitch stream's Live state ride their rows in All, not just in their source's shape. Live is read from the source's own current-live set (refreshed each foreground), never inferred from row age — a row must never claim live longer than the source did.
- **Chips order by today first.** Source chips sort by today's count, then total, then name — the apps moving now lead; lifetime volume alone doesn't hold the front. And inactive chips are icon-only (amended 2026-07-09): labels made the row scroll past a handful of connected apps; the brand icon is the identity, and only the active chip names itself. Menus stay dead — everything remains one visible tap.

## 36a. Home cover: an explicit banner outranks the automatic screenshot (2026-07-09)

The automatic cover (day's newest screenshot, full 250pt bleed) had no
way out — a screenshot the person didn't want leading Home just showed
up there. Settings gained a "Header" tile (same shape as Avatar): a tray
offers six curated colors (the retired Theme background palette, bright
primaries) or a photo — a color is a small flat-fill image under the
hood, so it needs no separate rendering path. When set, it always wins over
the day's newest screenshot — an explicit choice outranks an automatic
guess — and renders at 150pt, not 250pt: the two states read
differently on purpose. A tall bleed means "this just happened"; a
banner means "this is what I chose." The overlaid text (dateline,
title, subline) never changes based on which image is showing — a
banner only substitutes the picture, never the words, so Home never
implies a static photo is today's activity.

Considered and set aside: showing the newest THING of any kind instead
of specifically the newest screenshot — doesn't solve the control
problem (the newest thing can still be an unwanted screenshot) and
non-image things have nothing to bleed a full-height photo from. A
prior, broader "background photo" theme setting (app-wide, all
screens) was tried and retired 2026-07-06 for the same reason a
banner stays Home-only and optional: one image, one screen, one clear
purpose — not a return to that retired feature.

## 36f. Home: the default cover is black, not a color (2026-07-09)

The no-image cover (no chosen Banner, no lead screenshot) now paints
black instead of a color. The earlier "Fantastical move" — the quiet
cover wearing the lead thing's kind hue (a link day blue, a note day
yellow) — is retired: with a feed-heavy corpus the newest thing is
almost always a link, so the cover read as permanently Casberi blue.
Black is the calm dark field the content floats on; a chosen Banner
(Settings → Banner, a color or photo) is how color comes back, opt-in.
The Banner tile's unset preview shows black to match.

## 36g. Home: what landed today rides the cover as chips (2026-07-09)

The day's kind counts moved INTO the cover — one tappable chip row under
the title (kind hue capsule, glyph, count; tap → Feed filtered to that
kind) — and the standalone "What landed today" pills section at the
bottom of Home is gone, so Pinned and the maps start right under the
banner. The counts ARE the subline: the word subline ("project · time" /
"Kind · Source") returns only when nothing landed today. Chips count
today only, never approvals (the cover states what landed, never what's
waiting on the person — same guardrail as the cover lead). The weekend
cover carries no chips: it is a week recap and its subline already tells
that story; today-only counts under "your week, banked" would misread as
the week. A set banner reserves a constant 178pt band whether or not
chips arrive — the cover's height never depends on the chips arg, which
streams in last (keying on it made the banner jump mid-stream).

## 36c. Home: the "Noticed" insight line is gone (2026-07-09)

`insightLine()` was a plain deterministic rule (co-occurrence counting
— "a screenshot matches this session's chat", "this project spans 3
apps"), not model-driven synthesis, and it cost real screen space
above things the person already knows they want to see (Pinned).
Removed from Home entirely, function deleted (dead once its one call
site was gone). The `Insight` component itself stays — Ask answers,
project-detail empty states, and the composer's "Thinking…" line all
still use it; only Home's automatic use of it is gone. If a genuinely
synthesized version (the on-device model writing this line, not a
fixed rule) is wanted later, it's a fresh build, not a revival of this.

## 36b. Home order: Pinned leads the map (2026-07-09)

Pinned (and the wallet holdings treemap, when pinned) now compose
right after cover/quiet/insight, ahead of "What's going on" — a
deliberate choice outranks an automatic clustering, and reaching it
shouldn't cost a scroll past a treemap the person didn't ask for.
Applies to morning, evening, and weekend alike.

## 36d. Home recomposes when a banner or the wallet pin changes (2026-07-09)

Home authors its composition imperatively (`streamComposition`) and
only re-runs it on an explicit signal — it does NOT observe every store
by reading it in `body`. So a change to a store the cover/lineup is
composed from has to be wired to a recompose, or it silently no-ops
until an unrelated change (a new thing, a tab switch) happens to
recompose. Two were missing and are now wired: (1) the chosen Banner —
`HomeCoverStore` bumps a `revision` on every set/clear (a UIImage isn't
`Equatable` for `.onChange`, and its tray lives in Settings, pushed
inside Home's own NavigationStack, so popping back never refires Home's
`onAppear`); (2) the wallet pin already had `onChange(of:
wallet.pinnedToHome)`. Rule: any new store Home composes from needs its
own recompose trigger — reason about it when adding one.

## 36e. Wallet: the pin-to-Home toggle leads the holdings (2026-07-09)

"Connect the wallet, pin it to Home" needs a switch you can find at
connect. The toggle sat below the holdings treemap, so on a real wallet
(a tall chart) it fell under the fold and read as absent. It now leads
the holdings — its own row right after Watching, above the treemap —
and still shows the moment an address is watched, before the chart
loads. The leading-edge swipe on an address flips the same
`wallet.pinnedToHome`, so either gesture reaches it.

## 36f. Nav doors: bigger, a sharper breakage signal, and no false tab (2026-07-09)

Follows the two-tab convergence (§§ under 2026-07-06), fixing its rough
edges rather than reopening it — Apps stays a door, not a tab.
- **Bigger doors.** The Apps grid (21pt semibold, was the thin default)
  and the avatar (32/26pt, was 28/22) earn presence — they're the only
  way to Apps/Settings, and the store was easy to miss.
- **A distinct breakage signal.** When a bridge needs reconnecting the
  Apps door goes unmistakable: the glyph fills, turns the attention
  color, and pulses. Still honest — it lights ONLY on real breakage
  (`bridges.attentionCount > 0`), a nav button not a tab, so the killed
  tab-badge ruling holds.
- **The bar stops lying.** The floating tab bar + composer hide while a
  management screen (Apps/Settings, and anything they push — Wallet, a
  bridge setup) covers the tab, so the bar never reads "Home"/"Feed" over
  a place you're only visiting. It slides back when you pop out (the back
  button is the exit; the bar being gone is also why a tab can't be
  switched mid-visit, so the per-tab push state can't go stale). Feed's
  door push moved to a shared `FeedRoute` (mirroring `HomeRoute`) so the
  shell can see it. The Home starter/skeleton preview is untouched.

## 36g. Type: SF Rounded on the display tier only (2026-07-09, user)

The app is all SF Pro (no custom font — the right call for a native,
familiar, scannable personal app). One refinement: the DISPLAY tier now
uses SF Rounded — the Home cover title, the `heading34`/`heading22` ramp
styles (so tray titles, big headings, the empty-state Hero, and the
onboarding headline all follow), and nothing smaller. Functional text —
`heading17` section headers and everything below (body, rows, labels,
sublines, eyebrows) — stays SF Pro Text, which scans crisper at UI sizes
and keeps the native feel. Rounded reads warmer and more personal at
large sizes, which suits a cover that says "this is YOUR week"; the split
keeps that warmth from costing legibility where it matters. Implemented
as a `rounded` flag on `DSTextStyle` (so `dsText` handles it ramp-wide)
plus `design: .rounded` on the two display headings rendered directly
(the cover title, the onboarding hero). Both faces are Apple system
fonts — no bundle, full Dynamic Type — so it's reversible in a line.
Large nav-bar titles stay SF Pro (can't round just the title without a
custom nav title view, and cascading `.rounded` would round the whole
screen).

## 36. Bridge selection ruling: live data only (2026-07-09)

No new import bridges. A bridge whose data arrives via a request-and-wait export (TikTok's 1–4 day JSON, Tinder's 24–48h zip, IMDb's CSV) lands stale and never updates — the person asked for live data or nothing. The ChatGPT import predates this ruling and stays (its framing is explicitly a backfill, and OpenAI offers no live read). Evaluated and declined under this ruling: TikTok, Tinder, IMDb (viable exports, stale), Linktree/Rotten Tomatoes/CardPointers (no surface at all), Duolingo (unofficial API only — ToS-gray breaks the honesty rule), Credit Karma/NerdWallet/Acorns (aggregator-only; needs the post-M2 server), Fileverse (E2EE by design; revisit if they ship a hosted API), Fantastical (already covered — it's a client over the calendars EventKit reads). Pinterest passed: their public per-user RSS feed is live and official-enough (a published feed, not a scraped page).

## 36h. Wallet holdings: one treemap per wallet, leads Feed too, tap-through to Wallet (2026-07-09)

Watching more than one wallet is usually two different purposes (main vs.
cold, personal vs. a DAO) — combining their balances into one total hid
which wallet actually held what. `WalletIngest.topHoldingsByWallet()`
replaces the old combined `topHoldings()`: one TagMap per watched address,
titled with its label (or short address), fetched concurrently (not
sequentially — three watched wallets waiting on three requests in a row
made the pinned module noticeably slower to appear than the old single
request was).

The same module now leads Feed, not just Home: a pinned wallet's holdings
also lead the top of Feed's default view, right after Pinned things, on
every shape except Photos and Wallet itself (Wallet's own chip already
leads with it, showing every watched wallet regardless of pin — that's
its native shape). This replaced a dead demo-only mock
(`SourceComposition.block`, deleted) that showed a real user nothing at
all when they tapped the Wallet chip — a real gap, not by design.

Tapping a wallet-sourced row (an onchain transaction) in Feed now opens
the Wallet screen — holdings and activity together — instead of the
generic thing sheet, which had nothing more to show than an explorer
link.

Also fixed in the same pass: the per-wallet fetch is concurrent
(`withTaskGroup`), not sequential, so separating wallets doesn't cost
load time versus the old combined call.

**Amendment, same day: the pin moved onto each wallet.** `WalletStore
.pinnedToHome` (one switch for the whole watch list) is gone — pin lives
on `WatchedAddress` itself now. Two watched wallets are usually two
different purposes, and a person may only want one of them showing; a
shared switch also had a real bug, where swiping "pin" on a second wallet
silently un-pinned the first (both rows read the same flag). The swipe
gesture and a new inline toggle on each row in WalletScreen both flip
that ONE wallet's pin. Home and Feed's holdings module now composes only
from wallets with `pinnedToHome == true`; the Wallet screen's own view
and its Feed chip still show every watched wallet regardless of pin.
`Thing.walletAddress` (new field) records which watched address a landed
transaction came from, so a row can say which wallet it belongs to
(`BandRow`'s trailing label falls back to it when there's no project
tag) — shown only when more than one wallet is watched, and only for a
raw address match (an ENS-named watch won't retroactively match its
resolved hex, so it simply carries no label rather than a wrong one).

## 36i. TagMap cells: icons where they're always accurate, never a guess (2026-07-09)

Three treemaps share one renderer (`GenTagMap`): Home's "What's going on"
(projects, or a by-app fallback before real projects form), Feed's
holdings-by-wallet module, and the Wallet/Dexscreener screens. A new arg
— `TagMap(eyebrow, subline, [items], iconMode)` — decides whether a cell
earns an icon, per surface, not per item:

- **Project cells** (real tag clusters like "Work," "Onchain") carry no
  icon at all — a project spans sources by nature, so nothing is
  accurate. Name only.
- **"source" mode** (the by-app fallback, before projects form) reads
  `BridgeIcon(name:)` — no fetch, and never wrong, because a source-mode
  cell is always exactly one bridge (Gmail and iCloud Mail stay
  separate cells on purpose — merging them into one "Mail" category
  would need either two icons or a generic one, and neither is honest).
- **"token" mode** (wallet holdings) reads `TokenIcon(symbol:)` — a small
  bundled set (`brand-eth`, `brand-usdc`, `brand-usdt`, `brand-dai`,
  `brand-wbtc`, `brand-weth`, `brand-matic`, `brand-link`, `brand-uni`,
  `brand-aave`), downloaded once from Trust Wallet's public asset repo
  and shipped as static assets — not fetched live. Originally tried
  reading Alchemy's `tokenMetadata.logo` per holding; that came back
  `null` for nearly everything Alchemy returned, including WETH and
  USDC, so it wasn't worth building on (2026-07-09). A symbol outside
  the bundled set renders no icon at all — text-only stays honest,
  never a wrong or generic mark.

Same session: a watched **token** (Dexscreener watchlist) could already
be pinned from Feed — it's a normal Thing there — but not from the
token-watch screen itself, where you're most likely to reach for it
right after adding one. Added the same leading-edge pin swipe
`WalletScreen` already had, verb-for-verb.

## 36j. Home cover is 2-tier now: a set banner, or black (2026-07-10, amends 36a)

36a's "explicit banner outranks the automatic screenshot" ruling still
had a 3rd tier underneath: no banner AND no screenshot fell to black,
but a banner-less day WITH a recent screenshot still auto-led Home
full-bleed with zero action from the person — a real privacy gap
(a capture you didn't mean to see blown up on Home). Collapsed to 2
tiers: a set Banner shows, or the cover is black — a screenshot never
auto-leads Home under any circumstance now. `newestImageThing()` (the
composition-side "pick the day's newest screenshot" function) is
deleted; `HomeComposition.cover()`/`weekend()` only ever pass `"banner"`
or `""` as the cover's image ref. On the renderer side, `GenCover`'s
`hasImage` is now exactly `isBanner` (no third state), so the old
`isBanner ? 178 : 250` height ternary — height for "a live capture
bled full-height" — is now dead in practice; simplified to a constant
178. The word content (eyebrow/title/subline) is unchanged either way,
same as before: a banner only ever substitutes the picture, never the
words.

## 36k. Home: slim data-first hero; Threads removed; the map stays a map (2026-07-10)

The cover leads with the DATA now: today's kind-count chips ride above
the headline, and "Just landed" dropped from a 26pt full-voice display
title to a 19pt title in a compact translucent card — one specific
capture is a detail of the day, not the moment. SF Rounded stays (36g);
the height didn't change, the emphasis did.

"Threads across apps" (3-day-old links resurfacing, plus its weekend
"Worth returning to" variant and the empty-state skeleton preview) is
GONE. For a feed-heavy corpus everything ages into that bucket, so it
read as noise, not a nudge — Home is what you pinned and what's going
on, nothing else. `resurfaceable()` deleted with it.

Projects were briefly chips (same day) and reverted within the hour:
without a pinned wallet, Home would have had no treemap at all, and the
map is the visual anchor of the screen. "What's going on" stays a
treemap. What DID land from that experiment: holdings maps wear ONE hue
family per wallet (teal/purple/orange/pink by watch order —
`WalletIngest.hueName(forWalletIndex:)`, resolved in GenTagMap via
TagMap's new 5th arg), shade by value, so each wallet reads as a
coherent block and money-treemaps stay visually apart from the
multicolored project map. The Pinned token price chart is untouched.

## 36l. Treemap tiles are cards now — color moved into the ink (2026-07-10, user)

The saturated tile fills were the loudest thing on Home while carrying
the least information (size already says magnitude; the icon and name
say identity). Tiles now sit on the same sheet surface as every other
card (Pinned, "Just landed"), with only a wash of their hue — magnitude
rides the wash strength (0.08–0.22) plus size, the treemap's real
voice — and the color moved into the label ink, the same V3b rule the
feed rows already follow ("color lives in the tag text, not the row").
Preview keeps its muted flat wash. Weekend's left-to-right fill sweep
and the share card render unchanged.

## 36m. A pin is a HOME pin (2026-07-10, user)

Pinning a thing used to do two jobs: put it on Home AND lift it into a
"Pinned" section at the top of Feed. The Feed section doubled what Home
already shows and cluttered the record — Feed's whole grammar is one
chronological stream, and a copy of your pins sitting above it broke
that. Pinning now affects Home only; a pinned thing rides Feed in its
natural chronological place like everything else. The swipe verb stays
where it was — the row lifts briefly and a toast says "Pinned to Home",
since nothing on the Feed screen moves anymore. The wallet holdings
module still leads Feed (36h): it's the one pinned element with no row
of its own in the record, so it has nowhere else to live.

## 36n. Holdings never lead the All feed (2026-07-10, user — amends 36h/36m)

The wallet holdings module is a HOME module. Leading Feed's All view
with it doubled what Home already shows — same information twice, one
tab apart. In Feed, holdings render in exactly one place: the Wallet
chip's own shape, where they're that source's native view (everything
watched, regardless of pin). `holdingsChart()` lost its unused
`pinnedOnly` parameter with this; Home's `topHoldingsByWallet(
pinnedOnly: true)` is untouched.

**Amendment (same day, user): no wash at all.** The tiles are LITERALLY
the sheet surface the Settings tiles and Pinned card use — flat
`DS.surfaceSheet`, zero hue in the fill. Magnitude is size alone;
identity is the label ink (wallet hue / project hue) and the icons.
Applies to every TagMap — holdings and "What's going on" alike. The
starter preview breathes the surface's own opacity now instead of a
muted wash.

**Second amendment (same day, user): white ink too.** The colored label
ink ("gross teal") went the way of the colored fills — tile labels are
plain `DS.textPrimary`, exactly like a Settings tile's title. The whole
wallet-hue pipeline (TagMap arg 5, `hueName(forWalletIndex:)`,
walletHues) is deleted; a treemap tile is now surface + white label +
icon, nothing else. Identity rides the name and the icon alone.

## 36o. The Banner is a BACKGROUND now (2026-07-10, user — supersedes 36a/36j)

The banner never settled: as a full-bleed band it flooded the top third
(status bar, date, chips, and the Just-landed card all sat ON it); as a
card it was fine for a photo but odd for a plain color. The resolution:
it isn't an element at all — it's Home's WALLPAPER. Settings → Background
(was Banner) picks a color or a photo for Home's page canvas, Home only,
and the dark cards float on it (the chat-app wallpaper mental model).
This is the retired app-wide theme's post-mortem honored properly: one
image, one screen, one clear purpose.

- A chosen color paints deepened (~45% toward black) so gray section
  labels and white ink always read; the swatch circle still shows the
  bright identity. A photo wears the standard 0.5→0.72 scrim.
- Default = no choice = the standard page, pixel-identical to before.
- The cover element carries no image at all anymore — GenCover is just
  date + chips + the Just-landed card (now on DS.surfaceSheet, opaque,
  same as every other card). CoverBleed, the scrims, the stretch, the
  banner heights, genCoverTap, and the composition's banner ref are all
  deleted. HomeCoverStore → HomeBackgroundStore (same UserDefaults keys,
  so a banner chosen before the pivot survives as the background).
- HomeScreen wears `.homePageBackground()` — the one screen with its
  own wallpaper; everything else keeps `.dsPageBackground()`.

## 36p. The Pinned card leads with a pin, not the word (2026-07-10, user)

Home's Pinned card header is an oversized (28pt), tilted (-35°)
`pin.fill` instead of the word "Pinned" — the pin glyph is one of the
few universally readable icons, and the card earns a little
personality. Accessibility still reads "Pinned". Wired as a Widget
title sentinel ("@pin") so the doc grammar is unchanged.
