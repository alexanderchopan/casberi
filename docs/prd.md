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

Verbs card: Open in {source} / Open shortcut / type verb — rung 2 lives here. Tags row: read-only provenance (§178 retired the editor) — your own tags wear their hue, type tags stay quiet, nothing opens. Open question: the detail view needs a native rethink — App Intents replace web-era staged hand-offs; the content spec beyond tags and verbs is pending.

## 20. Tags

Three sources. Type tags: assigned at ingestion. Project tags: assigned through clustering; the person renames (in project detail). User tags: land via `#hashtag` in captured text only — §178 retired the thing-sheet editor and the composer's tag/rename commands as hand-filing surfaces the app was never meant to have. Tags act as Feed filters and search terms. Project membership rides a tag. No tag management screen; a tag with zero things dies.

RULING — WHAT TAGS ARE FOR (2026-07-10, user): tags are a RETRIEVAL
VOCABULARY, not a management surface. The app assigns (type tags at
ingestion, cluster tags); the person NAMES, and only at the moment they
care. Writes are deliberate and rare — one door per scope: the thing
sheet for one thing, the composer command for many. Reads are where tags
pay off: the Home treemap, tag views, search ranking (tags score 2×),
"show \<tag\>". Tags never grow affordances in feeds — no tag chips in
All (type tags don't differentiate there), no tag controls on a
source-filtered feed (that's QuickTagSheet again, twice killed; bulk
tag-by-source is the composer's job, and "tag farcaster as Crypto"
already matches on source). Low visibility of the WRITE affordance is
correct under this model, not a bug — the real discoverability question
is "how does the person learn the composer organizes," answered by the
derived organize chip (36aa), never by new tag surfaces. Every future
"should tags appear here?" resolves against this paragraph.

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

CLAUDE IS AN IMPORT BRIDGE NOW (2026-07-12, user asked "why is Claude coming soon — isn't its bridge the same as ChatGPT?"): it is. S9 always graded Claude as `import` ("batch via official export — ChatGPT, Claude"), but the catalog tile had been standing in for the *other* Claude direction — the MCP client reaching IN (§34), which is server-blocked and gated behind `transportReady = false`, so the tile read "Soon". Since one offer can't be two things (name is the join key everywhere), the tile is now the import S9 promised: `connectable: true, needsSetup: true`, routing to `ClaudeImportScreen` → `ClaudeImport.run` — a clone of the ChatGPT path over Claude's export schema (title in `name`, id `uuid`, ISO-8601 `updated_at`, flat `chat_messages` with `sender == "human"`; dedupe on `claude:<uuid>`, cap 500, source "Claude"). Debug: `-claudeImport <path>`. The MCP-client pairing is NOT deleted — `MCPPairing`, `PairClientSheet`, and §34's design all stand and `-openPair YES` still opens the sheet — but it is no longer wired to the Claude tile (the three Claude special-cases in AppsScreen/AppDetailScreen were removed, else a future `transportReady` flip would hijack the import tile with a Pair capsule). When a transport ships, MCP pairing resurfaces via the generic "pair a client" surface (PairClientSheet already says "any MCP client"), not by repurposing the Claude catalog tile. NOTE for that day: the dormant pair-story `clientPaired` check keys on a connected bridge *named* "Claude" — which the import now creates — so that check needs revisiting when `transportReady` flips. Website already carries Claude (marquee + catalog), so no site change. Verified on sim (`-claudeImport`): first import 2 in / 1 skipped, re-import 0 in / 3 skipped (dedupe), malformed file failed=1; edge export 3 in / 1 skipped — an untitled chat lands titled by its opening human line (no duplicate subtitle), a `+HH:MM`-offset stamp and a 1-digit fractional stamp both parse (a nil date would wrongly land the chat at `.now`, top of feed), and a title-less, human-turn-less convo is skipped. Product page reads "Import your chats, keep them findable" with a Connect capsule (no Soon, no Pair); the import screen renders Claude's export steps.

BANKR REPLACED BY DEXSCREENER — WATCH ANY TOKEN (2026-07-07, user: "replace bankr with dexscreener in our catalog"): Bankr's launched-tokens bridge was NICHE (only token creators; overlapped Zerion's onchain reads) while token-WATCHING is the general capability the token chart unlocked. So Bankr is GONE (BankrIngest/BankrScreen deleted; creator-fees, the treemap, the -bankrAddress hook, and the last trade-approval demo thing all removed) and DEXSCREENER takes its catalog slot: paste a token address/symbol/link → Dexscreener's public search (no key) resolves the most-liquid match → it joins YOUR WATCHLIST as a thing (tag "Watchlist", source "Dexscreener") whose sheet draws the native price chart. Model/TokenWatch.swift (resolve+add) + Screens/DexscreenerScreen.swift; wired through the one router/catalog/refresh tables; official eagle icon bundled. HONESTY: this is the user's OWN watchlist from PUBLIC price data — NOT a sync of their Dexscreener account (no watchlist API), and never trading. Verified live: "bankrcoin"→BankrCoin·$BNKR, "degen"→Degen Arena·$DEGEN, both watched. Debug: `-watchToken <query>`. SEVENTEEN bridges still (Bankr out, Dexscreener in).

TOKEN PRICE CHARTS, NATIVE (2026-07-07, user asked "can we show a price chart?"): yes — but Dexscreener's own API gives only a current price, no history, so the CURVE comes from GeckoTerminal's free public OHLCV (no key) and Casberi draws it itself with Swift Charts, not an embedded web chart (native content, per the law). A token thing whose content is a dexscreener link now LEADS its Ink sheet with a price header ($price + 24h% in confirm-green up / destructive-red down) over a native line+area sparkline — the token's "media", like a screenshot leads with its image. Illiquid/dead tokens have no pool → it falls back to the plain link, never an empty chart. Model/TokenChart.swift (route parses chain+address from the dexscreener URL; fetch = geckoterminal tokens→top pool→24h hourly candles) + TokenChartContent in ThingContent.swift. Verified live: DEGEN → $0.00153313, -2.1%, real curve. This is Casberi's token-render answer; Dexscreener stays the destination + the price source, never a catalog bridge (no watchlist API).

OPENCLAW IS REAL — CLEANED, NOT GUTTED (2026-07-07): OpenClaw is a genuine self-hosted agent gateway (docs.openclaw.ai — routes agent requests, exposes conversations over MCP), so its "agents' work + approvals land here" is honest, unlike Bankr's invented trade-approval. Fixes: the demo/preview approval was SELF-REFERENTIAL ("Deploy casberi-api to production · railway up") — changed to a generic agent action ("Deploy the staging build · deploy --env staging"); a ShapedRows eyebrow comment still cited the now-stale "BANKR · VIA OPENCLAW" (Bankr is a direct read bridge now) → "CLAUDE-CODE · VIA OPENCLAW". DEXSCREENER IS NOT A BRIDGE (2026-07-07, user asked): its watchlist is account/local-bound with NO public read API (same wall as Bankr memory), so a "read your Dexscreener watchlist" bridge is impossible. But Dexscreener IS already the destination for token things (Bankr tokens link there), and its public token-data API (api.dexscreener.com, no key) could power a Casberi-NATIVE token watchlist (paste an address → price lands) — a candidate feature, not a catalog app. Parked pending user call.

BANKR MEMORY IS UPLOAD-ONLY → NO MEMORY BRIDGE (2026-07-07, user: "you can only upload to bankr not download its files"): Bankr's agent memory (/.memory/ markdown: user_*/project_*/reference_*, same format Casberi itself uses) IS genuine private user data — but you can only ADD files to Bankr, not export/download them, and there's no read API. So a memory bridge would be a dead control (nothing to read in). A half-built markdown importer was REMOVED for exactly this reason. Lesson reinforced: verify the data can come OUT before building an in-bridge. BANKR LAUNCHES RENDER AS A TOKEN CHART (same turn, user asked): the tokens land as feed things (links) AND the Bankr screen shows a live TagMap treemap of them sized by fees earned (sqrt-scaled so a big earner doesn't slice the rest into slivers — the Zerion lesson), built from the real creator-fees data, no demo gate. The store preview uses the same treemap. Verified live: a creator address → 5 tokens + a rendered MODDS/MTK/AGD treemap.

BANKR IS REAL — AND READ-ONLY (2026-07-07, user, after reading docs.bankr.bot together): the old framing was FICTION — Bankr's API exposes no "asks you before each trade" approval flow; Bankr agents trade directly. What a Bankr user actually CREATES and owns that's publicly readable is the TOKENS THEY LAUNCH (their "files/folders" turned out to be shared developer Skill packages in a public git repo, not personal files — wrong fit). So Bankr is now a READ BRIDGE in the Zerion/Bluesky mold: paste your creator wallet address, and the public creator-fees endpoint (`GET api.bankr.bot/public/doppler/creator-fees/:address` — unauthenticated, no key, per the docs) returns every token that address launched; each lands as a link thing to its dexscreener page. Ref `bankr:<tokenAddress>`. Casberi NEVER trades or moves funds — executing a trade would need Bankr's REST API and violates our law + the prohibited-action rule; reading launches is safe and honest. Verified live: a creator address → 5 tokens in, 0 on re-run, malformed → FAILED. RULING: any bridge to a trading/agent platform is read-only until proven otherwise; check the actual docs before writing catalog copy (the old Bankr summary described a mechanic that didn't exist). Debug: `-bankrAddress <0x…>`. SEVENTEEN REAL BRIDGES.

INK SHEET TYPE SCALE, FULLER (2026-07-07, user: "fill this sheet better and more welcoming. same format, just w/ different font sizes"): same structure, bigger type — the title is now heading34 (display), spec-table values are body17 (was callout15), the TAGS line matches at 17pt, and action rows carry 18pt icons + heading17 labels with roomier vertical padding. The metadata reads substantially instead of whispering, and the rows fill the sheet. The tag-detail toolbar's rename control is now a text "Rename" button (was a bare pencil — a lone icon didn't read as rename; a nav-bar Label collapses to icon-only, so it's a plain text button like iOS "Edit").

THE INK SHEET (2026-07-07, user picked "Ink with Gallery grafted in" from three mockups, then "i like it" — the two specifics called out below are SUPERSEDED by §36ab (2026-07-10): the sheet is no longer flat ink-black (the source's brand hue now washes down from the top, fading into black before the media), and the 6px source dot died for an 18pt circular brand icon; everything else here — the Gallery spec table, tags-as-text-line, the verb rows, the Related shelf — still holds): the thing sheet is INK-BLACK IN BOTH MODES (like a photo viewer; the sheet forces dark controls), no cards, no hairlines — spacing separates. Structure: eyebrow (6px source-colored dot · KIND · AGE), title large, the thing's media (a screenshot leads with its image — sample refs now load their bundled photos here too), then Gallery's spec table with per-kind labels (WHEN for events — replacing the old ScheduleCard; SITE for links; BY for agent provenance; FROM; TAGS). Tags read as a text line — type tags gray, your tags in their hue — and tapping the row opens the full chip editor in place (add, remove, rename everywhere, delete everywhere: nothing lost). Verbs are quiet text rows (derived, cap three; writes still confirm), plus Pin (new to the sheet) and Share as rows. The Related shelf still streams last.

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

Apps page — store anatomy (2026-07-06, applied from docs/handoff-apps-page.md, mock M4 — built + verified on the sim; **the CONNECTED strip + `fillLine` divider were later retired by §39, 2026-07-10 — the page is now one grid**): the Apps page became a real store. One scroll: the CONNECTED strip (management — paused bridges dim to 50% and read "Paused"; it never merchandises), then a `fillLine` hairline and the "Discover" heading with a quiet "N to connect" count — management above the line, store below. A swipeable STORY CAROUSEL replaces both the hardcoded Zerion hero and the pair row (one door, richer): 2-3 brand-gradient editorial cards (the one brand-gradient license), eyebrow / 24pt-heavy pitch / icon + name + white capsule, chosen by rule — connectable-not-connected bridges first, Pair-a-client when no client is paired, never a "Soon" app, never a connected one. The LAYOUT LAW holds: no fixed heights anywhere on the screen — every card and row sizes to content + token padding (minHeight only for hit targets), equal carousel heights via top-aligned HStack + fixedSize. A BROWSE shelf of category pills (a merge map over the offer groups: Your life / agents / mail / work / media — categories exist ONLY here and as the chart filter, never as section headers) filters the one ranked FOR-YOU chart: rank number · icon · name + honest subline · capsule verb, ordered broken→Fix (attention), ready→Connect / Claude→Pair (tint), healthy→Open (confirm-dim, statusLine as the subline), coming→Soon (dimmed row). Capsule verbs are honest and shared with the product page via `VerbCapsule` — Connect / Pair / Fix / Open / Soon, never "GET". CatalogScreen is DELETED (the page is the catalog; its debug probe folded into AppsScreen). Deviations, noted: "Soon" rows desaturate the real brand icon rather than reverting to the gray-glyph well (the real-icon ruling post-dates the mock; recessive either way); connected sublines carry the bridge's own statusLine (the proof line is the honest state); stories have no dismiss affordance (the doc names dismissal without designing it — nothing invented).

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
One surface token `--ds-surface-sheet` (#111113 dark, #fff light) for cards, tiles, trays. Tinted background washes are banned. Text ramp: white / 60% / 30%. Hairline separators died by amendment: rows separate by spacing and press fills, groups by their card surfaces; nothing draws a line — zero exceptions (§39, 2026-07-10: the Apps page's Connected strip and its `fillLine` divider died too; the catalog is one grid where connected tiles wear state and open management). Elevation is carried by tone AND a soft ambient shadow, never by a line (§61, 2026-07-12 — the elevation ladder): cards lift off the page, inset-grouped sections lift as one card, wells recess by tone. SF ramp: 34/22/17/15/13/12/10. Squircle radii: cards 10, sheets 16, app icons 22.37%. Motion: 250ms, Apple sheet curve, one animation per moment. Every value routes through a token; components hold zero raw hex.

### 2. One tint
iOS systemBlue dark `#0A84FF`, token `--ds-tint`, one-line swap. Tint marks the interactive and the primary. Orange attention, red destructive, green confirmation, nowhere else.

### 3. Color rule
Color carries identity, state, or magnitude. Decoration banned. Magnitude: tint at opacity scaled by count (treemaps, project fills). Theme tint drives the family.

### 4. The composer is the hero
Search, ask, capture in one field. Engaged, it takes the surface: the parse card assembles under the words as pieces resolve.

### 5. Bob's words
Copy names what people control. "Apps," not connectors. Sentence case, plain verbs, numerals, no "successfully." Buttons say what happens. Errors say the fix. Empty states point to the first action. Headers are sentence case too — no ALL-CAPS eyebrows, no letter-spacing / `.kerning()`; the type ramp carries hierarchy by size and weight alone (2026-07-08). This supersedes the ALL-CAPS eyebrow strings quoted in earlier rulings (e.g. "START HERE", "WHAT LANDED TODAY", "NEW") — those record the words, not the letterforms; the words render in sentence case.

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

- **Bundling — volume compresses, never reorders.** In the All shape, 3+ bundleable things from one source in one day collapse into one band row ("Wallet · 14 transactions"); tap opens that source's chip, whose shape is where volume is designed to live. (Threshold lowered 4 → 3, 2026-07-12, user: the All feed's real clutter was sub-4 same-source runs — 2–3 posts each from several sources — that never compressed. Reordering/grouping-by-source was considered and rejected: it breaks the chronological record and reopens the "no ranking, no algorithmic feed" rule; tuning the existing compression threshold solves the density without either cost.) Human capture kinds never bundle (screenshot, voice, approval, anything from You) — each is one deliberate act; machine bulk (transactions, synced articles) is one act producing many rows. The day header keeps the true total. No ranking, no algorithmic feed — the Reminders "Older" collapse, applied to arrival volume. Single-source shapes never bundle (the shape IS the source).
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

**Amendment (user, 2026-07-18): a person's FIRST watched wallet auto-pins
to Home.** Watching ≠ pinning stays the rule, but a first-time watcher was
landing on a Home board their new wallet never reached — holdings show only
for a pinned wallet, and the pin sat behind a swipe (reported: "I followed a
Wallet, but it didn't show on my home feed"). `WalletStore.add` now sets
`pinnedToHome` on the first wallet only (the list was empty, so nothing is
pinned yet); every wallet after it stays manual, so the "two wallets are two
purposes, pin the one you mean" ruling above is untouched. Applies wherever a
wallet is watched (the Wallet screen, a social profile's "watch their
wallet"). Fully reversible — unpinning is one tap.

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

## 36q. Home juice pass: settle, draw-in, interactive pins (2026-07-10)

Three touches in the pin's spirit — motion that plays ONCE and means
something, never loops:

- **The pin settles.** The Pinned card's oversized pin springs from
  near-upright to its -35° rest on appearance, like being pressed into
  the card.
- **The price chart draws itself.** The sparkline reveals left-to-right
  (0.7s) when its data lands, and the price animates numerically on
  change. A continuously pulsing line was considered and SKIPPED: the
  chart is fetched per visit, not streamed — a pulse would claim a
  liveness the data doesn't have (honesty rule).
- **Pinned rows are interactive.** Tap opens the thing's sheet;
  long-press offers Open / Unpin (unpinning recomposes immediately and
  toasts). Feed-style SWIPE was requested and deliberately not built:
  Home is a ScrollView, native swipeActions only exist in List, and a
  custom DragGesture eats vertical scroll on device — a lesson already
  paid for (2026-07-04). Long-press is the native equivalent here.
  Rows carry their thing id as a trailing doc arg; rows without one
  stay inert.

**Amendment (same day, user): no off-ramp type, tile-grade cells, no
dead-end taps.** Three hand-rolled text fonts died: the dateline is
`label12` (the date is a label), the cover title is `heading22` (the
display-tier token — the ad-hoc 19pt rounded is gone), the cover chips'
counts are `label12`, and the Background tray's preview headline is
`heading17`. Icon/glyph point sizes aren't typography and stay. Treemap
cells press like the Settings tiles (`DSTileButtonStyle` — settle +
dim) since they ARE tiles now. A holdings cell routes to the Wallet
screen — tapping "ETH" used to open an empty project view for a tag
that doesn't exist. A "What's going on" header count was considered
and skipped (naggy).

## 36r. Home: pull-to-refresh + the pin coach (2026-07-10)

- **Pull-to-refresh.** Home carries live modules now (price charts,
  holdings), so a pull re-fetches them — awaited, so the spinner shows
  real work. A recompose alone wasn't enough for the charts (same doc
  line → same fetch task id), so the pull bumps a refresh tick the
  chart fetches key on.
- **The pin coach.** With things in the corpus but zero pins, the
  Pinned slot shows one retiring lesson in Feed's coach grammar
  ("Swipe a thing in Feed to pin it here." — tinted words, no overlay).
  The first real pin retires it forever, even if every pin is later
  removed. New `-unpinAll YES` debug hook clears pins and re-arms it
  for screenshots.

## 36s. Quiet days invite apps; the pin swipe has ONE direction (2026-07-10, user)

- The quiet-day berry ("Quiet so far today." under a cover that already
  said "A quiet day") said quiet twice and did nothing. The slot is a
  DOOR now: an AppsInvite card — a few catalog icons, "Connect another
  app · More of your day lands by itself." — that opens the Apps page.
  Connect more apps and quiet days get rarer, which is the honest
  response to a quiet day. GenQuiet deleted; Feed's empty state keeps
  QuietStateView.
- The pin swipe was LEADING on the Wallet and Dexscreener management
  rows but TRAILING in Feed — one verb, two directions. Standardized
  to trailing (Feed's edge, full-swipe = pin) everywhere. Since an
  explicit trailing group replaces the system swipe-delete, Remove/
  Unwatch ride the same group as the second button — nothing lost.

## 36t. One content line, the cover shows its source, the hand-off is everywhere (2026-07-10, user)

- **Alignment:** every card's inner content starts on ONE line now — the
  cover card's inner padding matches GenWidget's rows (s4), and the
  TagMap eyebrow/subline indent to that same line, so "Just landed",
  the pin, row icons, and "What's going on" all share an x.
- **The cover card leads with its source icon** (BridgeIcon, 28pt) —
  the old banner-ref arg (4) carries the source name now.
- **"Open in app" is never out of reach** (report: moving pins to Home
  cost the hand-off for pinned things). Home's pinned rows offer it in
  the long-press menu — only when the thing has a real destination
  (composition marks openable things, arg 6). Feed rows gain a LEADING
  full-swipe Open too — swipe right to hand off, swipe left keeps
  Pin + Open. Same verb on both edges by design: reach, not redundancy.

## 36u. The composer got smarter — five upgrades (2026-07-10)

- **Counts and aggregates, computed.** "How many links this week",
  "which app sent the most today" — arithmetic over the corpus
  (AggregateAsk), no model, no retrieval, ~1ms, always correct.
- **Out-of-scope redirect.** A no-match ask now says what WOULD work
  ("Casberi answers from what you've captured — try your links,
  events, or screenshots…"), and an empty corpus says to connect an
  app first. No hallucinated answers for out-of-corpus questions.
- **Semantic widening.** Apple's on-device word embedding expands query
  terms to near-synonyms (SemanticExpand, neighbors < 1.0 distance),
  scored below exact matches — "car stuff" can reach "vehicle" titles.
  Fully on-device, deterministic.
- **Pin verbs.** "Pin the last link" / "unpin ethereum" execute
  directly with an Undo toast (PinAsk) — a pin is the app's lightest
  write; the Feed swipe fires it without a confirm, so the composer
  carries the same consent weight. A miss answers honestly ("Nothing
  called 'x' to pin.") instead of closing silently.
- **Follow-ups.** Pronoun-shaped asks ("which ones were from Sam?")
  search the LAST answer's grounding instead of the whole corpus.

Found while verifying: pin flips changed no thing-count, so Home's
Pinned card stayed STALE after every swipe-pin until an unrelated
recompose. Every pin writer (Feed swipe, composer verb, Dexscreener
swipe) now bumps CorpusSignal.

## 36v. The fun pass — six small delights, no widgets (2026-07-10)

Approved batch ("do all of these except 5" — Home Screen widgets
rejected as complexity we don't need now):

- **Chips teach the new powers.** The composer's suggestion chips now
  include "How many links this week?" (when the week has links) and
  "Pin the last link" (when an unpinned link exists) — counting and
  pinning were secret powers until the chips showed them. Chips only
  offer asks the corpus can honestly answer right now.
- **Holdings total in the subline.** The wallet treemap's subline is
  the real number — "$18K across 12 tokens" — never the generic
  "Holdings by value".
- **Milestone toasts.** Crossing 100 / 500 / 1,000 / 5,000 / 10,000
  things flashes "N things banked." once per threshold (persisted in
  milestone.reached). A quiet count-up, not a celebration screen.
- **Haptics finish the motion.** The treemap chart draw-in ends with a
  selection tick; pull-to-refresh ends with a success thud.
- **Share card carries its dates.** The weekend share card shows the
  week's real date range ("Jul 3 – Jul 9") under the eyebrow.
- **Photo grid presses like a tile.** Feed photo cells use the same
  DSTileButtonStyle squish as every other pressable surface.

Found while building: a SwiftData #Predicate cannot compare the
Codable ThingKind enum — it throws at runtime, and `try?` made the
miss silent (the new chips never appeared). Rule: kind filters happen
in memory after a plain fetch; enums never enter a #Predicate.

## 36w. Watchlist rows wear a 24h sparkline (Option A ruling, 2026-07-10)

Recording the ruling the sparkline commit cited but never wrote down:
a watched token's feed row replaces time-over-tag with a 46pt 24h
sparkline plus signed change — the row's "what is it doing right now",
the way a Twitch row wears Live. TokenPulse holds the curves in memory
only (prices are perishable; nothing persists), refreshed per
foreground alongside the bridges.

## 36x. Feed source chips go Stories-sized (Option A, 2026-07-10)

The chip row is 56pt icon-only circles — the brand logo IS the chip.
A DS.confirm ring marks a source with things newer than the last
visit (the same state as the "New since" divider; it quiets when the
visit stamp advances). The active chip wears the ink ring. No labels
(64pt Stories-with-labels was mocked and rejected: ~90pt of height
for words the icons already say); "All" keeps its word — it has no
app. Ruled from three on-sim mockups.

## 36y. Build-19 review fixes (2026-07-10)

Review of the image-rows diff confirmed and fixed:
- Tracker-image filter matched substrings ("google-pixel-10-hero.jpg"
  lost its image forever) — now whole path segments + tracker filenames.
- Twitch live state could outlive the truth: liveRefs now clears on
  disconnect AND on a failed sync (can't verify who's live → claim
  nobody is).
- A live-stream frame is perishable: RemoteThumb skips its decoded
  cache for perishable URLs, so a second broadcast can't wear the
  first one's frame.
- Dead image URLs (delisted Steam headers' 404 pages carry no cache
  headers) are remembered per session — scrolling no longer re-fetches
  them per appearance.
- TokenPulse fans out token fetches (was 3N serial round trips), lands
  them in one repaint, and rate-limits FAILED tokens by the same
  15-minute gate (a dead token cost 3 GETs every foreground, forever).
- Farcaster image detection now checks the URL path, not the raw URL
  (query strings defeated the extension check).

Deferred to a cleanup pass, on record: the save-epilogue belongs on
ArtlessBackfill (copy-pasted across 9 bridges; Steam hand-rolls it);
deltaText/sparkline are third copies of existing formatters/renderers;
GenTokenRow + TokenChartContent should read TokenPulse instead of
fetching their own charts.

## 36aa. The composer invites the first bulk tag (2026-07-10, user)

Companion to the §20 ruling (tags are a retrieval vocabulary; the write
doors stay two). The person's path to learning that the composer
organizes was invisible — the tag command existed but nothing taught it.
Now the empty-composer chip row can carry ONE organize invite, derived
like the ask chips are: the source with the most things still wearing
only their type tag (≥3 untagged is the trigger) earns "Tag your 33
Farcaster things", tag-glyphed and tinted to read as organizing, not
asking. The LABEL counts the source's whole pile — that is what "tag
farcaster as X" actually proposes (review 2026-07-10: the untagged
count understated the match set; honesty rule). Skipped sources: "You"
(as a query word it matches far beyond its own things) and any name the
command grammar can't quote faithfully — "Reminders"/"Voice" are kind
words (the command would match by KIND across every source) and filler
words ("The …") would shrink the query to a bare term
(Organize.faithfulSourceQuery guards both). Count ties break by name so
the invite doesn't change identity between opens. The invite LEADS the
row (the row scrolls; the last seat hid the one chip that teaches —
verified on the sim before the swap); ask chips cap at two so the row
stays three.

Tap PREFILLS, never sends: the field takes "tag farcaster as " and the
person types the name — the name is theirs to choose, tag autocomplete
helps, and the write still waits behind the proposal card's Apply.
Typed-text-never-saves holds at the right altitude (review 2026-07-10):
every programmatic draft-writer (this chip, tag completion, the debug
hooks) routes through one fillDraft() door that suppresses the
paste-capture heuristic — tag completion carried the same latent bug
(a completed long tag read as a paste, and the whole typed command
SAVED as a note) — and at commit a command-shaped draft beats the paste
flag, so pasting the tag name into the prefill still reaches the
proposal card, never the capture path. The proposal card remains the
truth surface for what the command actually matches.

## 36z. Follow more than one Bluesky / Farcaster account (2026-07-10)

The handle bridges watch a LIST now, the way Wallet watches a list of
addresses — a small following feed of people you care about, not just
your own mirror. Because the AppView/Snapchain APIs were always
fetching a public handle's posts (ownership was never verified),
"multiple" is the honest shape of what the code already did.

Behavior, mirroring the Wallet-label rule (identity surfaces only when
there's ambiguity):
- **One account** watched: unchanged. The post keeps its own attached
  image or the source glyph; no author identity shown (every row is
  obviously them).
- **More than one**: the row LEADS with the author's avatar (a circle,
  falling back to the source glyph) and names them in the trailing slot
  (@handle), so two watched people never read as one stream. Posts
  intermingle chronologically under one source chip — no per-account
  chips (a timeline has no per-account aggregate to separate, unlike
  Wallet holdings).

Wallets get the same identity treatment: when more than one is watched,
a transaction row wears a deterministic identicon (a pure function of
the address — no network) beside its existing address label.

Two new Thing fields carry it: authorHandle + authorAvatarURL (both
optional, CloudKit-safe). Farcaster resolves the pfp once per account
via userDataByFid (the endpoint ignores the type filter and returns
every profile field in a `messages` array — scan for USER_DATA_TYPE_PFP).
The connect screen lists watched accounts with swipe-to-remove; the
field becomes "Add". Pinterest stays single (RSS-backed, one board).

## 36ab. The thing sheet wears its source's hue (2026-07-10, user: "ship it. it's gorgeous")

Picked from four live sim mockups (tinted eyebrow ink / brand icon
eyebrow / hue wash / wash + icon — the user chose the combination and
killed the dot: "I HATE the dot bullet"). The Ink sheet stays ink, and
now the source's brand hue washes down from the top, fading into black
before the media begins; the eyebrow leads with the 18pt circular
BridgeIcon in place of the dead 6px dot, so the color always arrives
NAMED — the mark above explains the glow.

Why this wash lives while the treemap fills and the banner died: it
sits UNDER the content as atmosphere, never a surface ink depends on
for contrast, and it follows one fixed recipe — hue at 45% into clear
over 260pt, no per-hue tuning, no scrims. The moment it needs either,
it has become the banner again and should die the same way.

Hueless things stay pure ink: DS.brandColor split into an optional
DS.brandHue (nil for "You" and unknown sources — the gray fallback is
a FILL, not an identity), and the sheet only washes when a real hue
exists. Two moods, both honest: bridged things wear their source; your
own things stay the photo-viewer black. BridgeIcon's glyph fallback
keeps the eyebrow seat filled either way ("person" for You, "waveform"
for Voice). ChatGPT's white and X's black wash faithfully — the recipe
is the brand's own color or nothing.

## 37. Drop the "Ask before acting" writes toggle (2026-07-10)

User caught it on a bridge detail: "what does 'writes wait for your OK'
mean, we don't write." Correct — every bridge is READ-ONLY today, and
the toggle was a dead control on all of them: `askBeforeActing` was
stored when flipped but read nowhere (no write path ever consulted it),
so it asked permission for something that never happens and implied the
app could act on your accounts (a wallet especially — it can't move
funds). Straight against the honesty rule ("no dead controls, no fake
status"). Removed the Writes section from BridgeDetailScreen. It returns
— gated to a genuinely write-capable bridge AND wired to a real write —
when agent writes ship (the Alice job/run/output kinds). The dormant
`askBeforeActing` / `setAsk` scaffolding stays in the model for that.

## 38. Social posts always wear the author's avatar (2026-07-10)

User: "I thought we made it so Farcaster and Bluesky showed the avatar
of the person you follow" — but a single-account feed showed the source
glyph. Two causes, both corrected:

- The avatar was gated to >1 account (mirroring the Wallet-label rule).
  Wrong analogy: a @handle LABEL is redundant with one account, but a
  FACE never is — it's who posted. Dropped the gate; the avatar leads
  every Bluesky/Farcaster row when we have one. The @handle label keeps
  its >1 gate.
- Existing posts never got an avatar — ArtlessBackfill only fills the
  attached image. Each sync now resolves the account's avatar once and
  backfills it onto EVERY existing post of theirs (matched by the handle
  in the permalink), so the whole feed wears faces, not just posts
  landed since the field shipped.

## 39. One catalog — the Connected strip dies (2026-07-10)

User: seeing connected apps in the Apps page AND as feed chips was
redundant and confused navigation. Ruled: connected apps LIVE in the
feed (chips to read, the shape's header door to manage); the Apps page
is ONE grid where every app appears exactly once, and a connected
app's tile wears its state instead of moving to a separate strip:

- tier 0 connected-broken: status dot (orange), "Needs reconnecting",
  Fix → management. Leads its shelf — it needs the person.
- tier 1 ready: Connect (or Pair), as before.
- tier 2 connected-healthy: status dot (green), statusLine subline,
  Open → management. Row tap opens MANAGEMENT, not the store pitch —
  its pitch already worked.
- tier 3 coming: Soon.

The strip's divider dies with it — the app now draws NO lines
anywhere (supersedes the "one exception" hairline law; CLAUDE.md
updated). Connection health also surfaces where the person lives: a
feed chip whose bridge is in .attention wears an ORANGE ring (ink =
active, orange = needs you, green = new since last visit).

## 40. Approve/Deny tell the truth (2026-07-10)

User: "how would a user 'approve' from inside our app?" Audit found
two behaviors behind one button: an MCP save approval really commits
the carried payload (consent → write, kept), but every other agent
ask only marks the thing done locally — and the toast claimed
"Approved — sent to your gateway" / "Denied — your gateway was told"
when NOTHING is sent (no agent transport exists). Fake status,
removed: the toasts now say just "Approved" / "Denied" — the answer
is recorded on the thing, which is all that happens. Real outbound
consent returns with the agent transport.

## 41. Mail rows lead with a sender-initial circle (2026-07-10)

User asked if Gmail/iCloud mail could show sender avatars like the
social bridges. Email carries none (IMAP hands us headers + body;
Gmail-the-app looks photos up in Google's directory, which we don't
have), and the Gravatar workaround was ruled OUT on values: it would
send a fingerprint of everyone who emails you to a third party —
off-brand for "your data stays on your device."

What we honestly have is the sender string, so mail rows lead with an
initial circle — the sender's letter on a hue that's a pure function
of the sender (same trick as the wallet identicons; what Mail apps
themselves draw for unknown senders). No network, nothing stored
beyond the sender. New mail carries the sender in authorHandle;
older rows parse it from their "From …" content at render — no
migration. A row with no sender keeps the brand glyph.

## 42. A shaped feed wears its source's hue (Option B, 2026-07-10)

Same request shape as the thing sheet's wash, ruled from three on-sim
mocks: (A) the sheet's exact 260pt recipe — too quiet at page scale,
read as a smudge; (B) a deeper header — the brand color mixed toward
black owning title/status/chips, fading out where the day groups
begin; (C) a whole-page tint — killed the ink ground and fought the
Home background feature. B won: you're clearly inside that app's
room, reading still happens on black. One recipe, no per-hue tuning;
a source without a brand hue (and the All feed) stays black. The hue
crossfades between shapes (id-keyed transition), never smears.

## 43. Settings inflates out of the avatar (2026-07-10)

User asked for a glass-bubble / water transition into Settings. Two
candidates: (A) the system zoom transition anchored on the avatar —
Settings inflates out of the circle with the system's fluid spring,
zero added latency; (B) a Metal lens-refraction shader — literal
water, but it must delay every push ~300ms while the ripple plays.
Built A (recorded on-sim; the pop deflates back into the avatar).
B stays on the shelf unless A proves not enough — a transition tax
on every Settings visit is a real cost, the bubble is not.
Also: casberi://settings deep link added (recording + parity).

## 43a. Settings is your room (amendment, 2026-07-10)

The bubble transition alone read "fine but not special" (user) — the
harshness was the DESTINATION, not the motion. Settings is where the
personal things live, so it now receives you: your avatar LARGE at
the top (the toolbar door's face, grown — the bubble visually lands
on it; tap = the same change/remove flow), and the page washed in
YOUR color — the Home background you chose (photo backgrounds arrive
blurred + dimmed), the same wash grammar sources get, but in the
person's own hue. No background chosen = no wash: the room stays
black until painted, which quietly teaches what the Background tile
does.

## 43b. The droplet, and the hero dies (amendment, 2026-07-10)

The avatar hero was rejected within the hour: "this is an app for
personalization but it's not trying to lock you into some profile."
The distinction is now doctrine: personalization paints your SPACE
(background, theme, color); the app never builds a shrine to your
identity. The hero is gone; the your-color wash on Settings stays
(it's space, not profile).

And the fun the user actually asked for lives in the TRANSITION,
because it must work for a default-black user with nothing set:
tapping the avatar swells a REAL Liquid Glass droplet (iOS 26
glassEffect — it refracts the Home content it crosses, so black
pages still show the blob's rim and lens) from the door until it
swallows the screen; Settings pushes beneath at full cover and the
glass clarifies away. ~280ms to push. Home only for now; Feed keeps
the plain zoom until this earns its keep on device.

## 43c. The liquid page melt (third draft, 2026-07-10)

The droplet blob was rejected too ("too fast, isn't smooth, weird") —
the ask was never an object crossing the screen but THE SCREEN ITSELF
turning liquid: "the entire screen transitioning to the settings page
but like glass or liquid." Built as a Metal displacement shader
(LiquidDissolve.metal): tap the avatar → the outgoing frame is frozen
(window snapshot), Settings pushes INSTANTLY beneath it (zero added
latency — the earlier delay objection is structurally gone), and the
frozen frame melts — two crossed sine fields whose amplitude rises
from zero, peaks mid-flight, and relaxes — while it thins to reveal
the new page. 0.9s, ease-in-out. Works on default black: it's the
page's own pixels doing the rippling. Home only until it's felt on
device. (Required the Xcode Metal toolchain component — now installed.)

## 43d. The wave carries its own light (fourth draft, 2026-07-10)

The uniform melt failed on sight ("can't even tell it's happening") —
diagnosis: displacement alone is INVISIBLE on an ink-black app; black
pixels bending over a black page show nothing. Water reads by its
light, not its bending. Rebuilt as a single circular wavefront from
the avatar: ahead of the front the old page stands untouched; at the
crest, pixels stretch radially AND the band carries an additive glass
shine (visible on pure black); behind the front, transparent — the
new page is washed in spatially, never crossfaded. 0.85s ease-out.
Doctrine for future liquid work: on this app's ink ground, any glass
effect must EMIT, not just distort.

## 43e. Both pages ride the wave (fifth draft, 2026-07-10)

User: "the whole thing should transition — not dissolve and then a
sheet pops up. It looks good paused partially." Diagnosis confirmed:
the destination sat statically under the melting page (and a capture
bug made the wave play Home-into-Home — the "incoming" snapshot had
photographed the holding frame itself). Fix: freeze BOTH sides around
an animation-less push (UIKit hold covers the window; the incoming
frame is captured from the ROOT VIEW beneath it, afterScreenUpdates),
and give the incoming page its own shader half (liquidSettle): right
behind the front it arrives still gathered toward the origin and
faintly aglow, relaxing to crisp as the front moves on. Ahead: the
old page, untouched. At the front: the lit crest. Behind: the new
page, settling. One substance end to end.

## 43f. The uniform liquid dissolve (sixth draft, 2026-07-10)

The radial wave read as a BURST ("wtf") — an origin point makes an
explosion, not a dissolve. Final shape: no origin anywhere. An organic
ripple field covers the whole page; the outgoing page liquefies and
thins through the middle of the ride while the incoming page ripples
beneath it (same field, phase-shifted — one disturbed surface, not two
copies) and settles to crisp. A faint shimmer rides the ripple crests
(0.10/0.06) so the liquid reads on ink-black without becoming an
effect of its own. 0.95s, ease-in-out, both frames frozen around an
instant push as before.

## 43g. The dissolve slows down and opens the store too (2026-07-10)

Ruled on the sixth draft: "close but too fast, and I love how liquid
it gets." Duration 0.95s → 1.3s (one constant, LiquidPusher.duration).
The same dissolve now opens the STORE — both doors, on both tab roots
(Home and Feed), ride one reusable LiquidPusher; the plain zoom died
with it. Found while re-recording: the overlay's clock was a plain
`let start = Date()`, so any parent re-render mid-ride (live times,
chip staggers) recreated the struct and RESTARTED the liquid — the
snap-back jank that had been polluting every draft's smoothness.
@State now; the ride is monotonic.

## 43h. The liquid system completes (2026-07-10)

Five upgrades, ruled together ("do all of these including scrubbing"):

- **Reduce Motion is law.** A person who asked the system for reduced
  motion gets plain, instant navigation — no snapshots, no shader, no
  ride, in ALL paths (open, pop, scrub; the scrub strip doesn't even
  mount). Code-verified; simctl can't toggle RM headlessly, so the
  on-device check is Settings → Accessibility → Motion.
- **The way back is liquid too.** Settings and the store pop through
  the same dissolve (1.1s — leaving is lighter than arriving), via a
  custom back chevron. The pusher remembers the way back from the
  open; a screen reached WITHOUT the liquid (deep link, probe) keeps
  the system back untouched.
- **Scrubbing.** The leading edge of a liquid-opened screen hands the
  pop to the finger: drag drives the dissolve's progress directly;
  release past 30% (or a flick) completes, otherwise it unwinds and
  re-pushes beneath the veil — no seam either way. Hiding the system
  back button already disabled the native edge swipe, so the edge
  belongs to the scrub alone. Gesture FEEL needs a finger — sim can't
  drag headlessly; the machinery is the same verified pop path.
- **The ripple ends in a touch.** A soft settle haptic exactly when
  the liquid stills (the motion-ends-in-a-touch grammar).
- **Scarcity doctrine.** The dissolve marks exactly one thing:
  crossing from your CONTENT into your ROOMS (Settings, the store).
  Reads — thing sheets, project details, bridge screens — stay
  instant. Do not spread it.

The vestigial zoom transition (43's first draft) is deleted.

## 43i. The end-snap dies (seventh draft, 2026-07-10)

User on device: "it snaps at the end." Two real causes, both structural:

1. The incoming snapshot RACED SwiftUI's commit — afterScreenUpdates
   flushes UIKit, not SwiftUI, so the "incoming" frame sometimes
   photographed the OLD page; the ride played into itself and the
   destination only appeared as a hard cut. Fixed deterministically:
   the destination screen itself reports .onAppear (liquidPoppable on
   pushed screens, liquidPushOverlay on tab roots) and ONLY THEN is
   the incoming frame captured and the clock started; a UIKit hold
   keeps the screen frozen while waiting (250ms fallback for pops
   whose root .onAppear doesn't refire).
2. Even a correct frozen frame diverges from the LIVE page under the
   veil (entrances finish, dots pulse, times tick), so a one-frame
   unmount snapped. Fixed with the LIFT: the crisp final frame fades
   ~0.25s into the live page — drift becomes a soft handoff.

Doctrine learned the hard way (yellow no-entry screen): SwiftUI shader
effects CANNOT run on UIKit-backed views — a NavigationStack is one —
so the live page can never wear the shader; frozen frames + the lift
are the only honest mechanism. Settle haptic now fires when the liquid
stills (lift start), not at unmount.

## 43j. One liquid, both rooms (ruling, 2026-07-10)

Asked and ruled: Settings and the app catalog share the SAME liquid
transition — no per-destination effects. The transition is grammar,
not decoration: it means "you're crossing from your content into a
management room," and both doors are the same class of place in the
same pill. Destinations differentiate by CONTENT (Settings arrives in
your color; the store arrives with its carousel and shelves), never
by transition. The system's one motion distinction stays directional:
arriving 1.5s, leaving 1.1s — entering a room is heavier than
stepping out.

## 43k. Wetter and quicker (2026-07-10)

Ruled after living with 1.5s: "more liquid and faster." Pace: open
1.15s / pop 0.85s (the bracketing holds: 0.95 was too fast bare, but
with the bigger waves the shorter ride reads fuller). Waves: broader
and deeper — frequencies down (~8.5/5.5/7/4.5 from 11/7/9/6), outgoing
amplitude 26→42pt, incoming 22→34pt, shimmer 0.10→0.13, sample offsets
widened to match. The page heaves instead of buzzing.

## 44. Composer invisible over the store — hardened (2026-07-10)

Device report: over the app catalog, tapping the FAB opened the
keyboard but no bubble. Home works; the bubble is truly absent, not
behind the keyboard; the store is only reachable through the liquid
ride. Sim reproduction of the exact flow (liquid open → settle →
composer through the real animation path) renders CORRECTLY — the
state machine is clean, so the failure lives in the device render
layer, prime suspect the real Liquid Glass FAB→bubble morph glitching
on hardware (sim glass and device glass are different engines; the
bubble's ONLY surface was the glass).

Hardening shipped (not a confirmed root-cause fix, said honestly): a
solid surfaceSheet underlay beneath the bubble's glass — a failed
morph can no longer leave the composer invisible, and the look is
unchanged (glass over ink). If the next build still fails on device,
next step is on-device instrumentation of the glass container.

## 43l. Fast and subtle — the liquid settles (2026-07-10)

After living with big waves ("more liquid and faster" lasted one
look), the final register: FELT more than watched. Open 0.65s / pop
0.5s, lift 0.2s; amplitudes down to 16/12pt (broad wave shapes kept —
a gentle heave, not a buzz); shimmer to 0.06/0.04. The liquid should
read as the page taking a breath, not a water show. Full parameter
trail: 0.95→1.3→1.5→1.15→0.65; amplitudes 26→42→16.

## 45. The zoom returns; the liquid retires (2026-07-10, the settling)

After twelve drafts of liquid, the closing critique named the category
error: "it feels like an effect, not a transition." A transition reads
as TRAVEL when it has GEOMETRY — the page itself moving encodes where
the new place came from. The dissolve deliberately had none: two
static pages under rippling pixels, so at every amplitude it read as a
treatment over a swap. No tuning could fix that.

Settled: both rooms open with the system ZOOM, each growing from ITS
door (Settings from the avatar, the store from the grid — sourceIDs
settingsDoor/appsDoor). This is the first draft returned to with
conviction: it is causal, native, and it restores for free everything
the liquid hand-built — real interactive edge-swipe scrubbing, system
back, Reduce Motion handling — with zero shaders, snapshots, or races.
One grammar, both rooms (43j holds). The liquid code is deleted (git
history keeps every draft); its yield stays: the doctrine trail in
43–43l and prd 44's composer hardening, which remains shipped.

## 46. The ledger holds — everywhere (2026-07-10)

The reading tension, mocked and ruled: content sources (RSS, posts)
were candidates for a "reader" shape in their own chip views (bigger
image, wrapping headline, posts-as-posts). The mockup made the case
well and was REJECTED: "it's better they all read the same — easier
to scan and catch up, and it doesn't feel like it's trying to
replicate another app." Doctrine: the feed is a LEDGER in every
shape; Casberi is where things LAND, reading happens one tap away
(sheet, open-in-app). The mockup's one lasting yield: it exposed raw
numeric HTML entities in RSS titles ("&#8217;") — decoding now lives
in IngestSupport.decodeHTMLEntities (named + numeric refs), shared by
RSS titles and LinkTitle.

## 46a. Faces AND pictures (amendment, 2026-07-10)

The one-slot casualty surfaced: since faces always lead (38), a
post's attached photo vanished from the feed entirely — "From my walk
this morning" showed a face and a caption, not the walk. Ruled: "keep
faces always but show pictures too." The avatar keeps the leading
slot (WHO); when a post carries an image it rides at 26pt just before
the timestamp (WHAT). Same scale, same one-line band — the ledger's
rhythm holds, and a photo post finally shows its photo.

## 47. Typography lands where it started (2026-07-10)

The "everyone has their own font" question, explored and ruled. The
list of candidates was surveyed (Söhne, Untitled Sans, ABC Diatype,
GT America, Basel, custom commissions); the one concrete idea worth
testing — SF Mono for data (timestamps, counts, prices, day
numbers) — was mocked in the live app and rejected: at 11–13pt data
sizes the mono texture is invisible, so it would be a cost (a second
family, a new rule to police) with no visible yield. Ruled: "we
stress tested the idea and for now this is where we land." The type
system stays all-SF: SF Rounded for the display tier (heading34,
heading22 — the soft voice, 2026-07-09), SF Pro crisp for everything
functional. The identity carried by type is the soft-display /
crisp-function contrast, not a licensed face. Revisit only if a real
legibility or identity failure shows up, not for novelty.

## 47a. Cabinet Grotesk, tested and passed on (2026-07-10)

The strongest external candidate got the full live test: Cabinet
Grotesk (Fontshare, free ITF license) rendered across the whole ramp
in the real app — Extrabold display, Bold/Medium/Regular below —
side-by-side against SF. Verdict: "looks way better w SF." The
display tier in Cabinet was genuinely distinctive, but the
functional tier — most of the app — went soft: rows lost scan
crispness at 15-17pt and small text (timestamps, sublines) got mushy
at 12-13pt, exactly where SF Pro Text is engineered to win. 47
holds, now stress-tested against both a mono accent and a real
licensed-face swap. The mock (MockFonts/, -fontMock) is deleted.

## 48. Screenshots survive Photos (2026-07-10)

The "green squares" diagnosed and closed: a screenshot thing stored
only its PHAsset identifier, so when the original left Photos the row
fell back to the kind's green hue field forever — honest, but it
reads as a bug. Two changes, both in ScreenshotIngest.heal():
(1) THUMBNAIL — every screenshot thing gets a small JPEG of its
picture saved into the corpus (externalStorage → CKAsset, the voice
audio pattern), at connect and on every foreground refresh, so the
row and its detail sheet outlive the Photos original. (2) RECONCILE —
ruled "if it can't find deleted photos we just don't show them at
all": a thing whose asset is CONFIRMED gone (full library access,
fetch finds nothing, no thumbnail ever saved) is removed — it holds
nothing but a dangling ref. Under limited access nothing is ever
removed (an unselected asset is indistinguishable from a deleted
one). Verified end-to-end on sim: 4/4 things thumbed, a seeded
dangling thing removed. Sim note: `simctl privacy grant photos` does
NOT take on the iOS 26 runtime — the real dialog is the only path.

## 49. The new-things ring becomes an event (2026-07-10)

Two rulings from "could be better". (1) GLASS STAYS OFF THE CHIPS:
Liquid Glass is the floating layer's material (composer, tab bar,
toasts) — the feed chips are content, and content never wears glass;
the chips' identity is their brand color, which a glass film would
mute. (2) The green "new since last visit" ring stops being a state
that blinks and becomes an event that moves: when a source gains new
things mid-visit the arc DRAWS ON clockwise from 12 o'clock (0.55s
spring, one soft 1.06 pulse), and when a return visit acknowledges
them it DRAINS back the same way. A chip scrolling into view with
new things shows the full ring instantly — the sweep never replays
for old news. Reduce Motion gets plain state changes. Ink and orange
rings unchanged: selection travels (43h), attention is steady.
Verified on sim via the -seedThing hook (a live flip drew the ring;
mount-with-news showed it full). Sim note: recordVideo kept
truncating mid-run — screenshots + NSLog probes are the reliable
motion evidence there.

## 49a. Feed keeps the pulse; Diagnostics gets the instrument (2026-07-10)

The tab bar's Feed glyph and the Diagnostics tile both wore
waveform.path.ecg. Candidates for Feed were mocked in the live tab
bar (timeline, tray, stack, plain waveform); ruled: Feed KEEPS the
ECG trace — it's the pulse of your stuff. Diagnostics moves to
"stethoscope": the instrument that listens, not the trace itself.
The -feedSymbol mock hook came and went in the same session.

## 50. Home's Pinned card holds six (user, 2026-07-11)

The Pinned card's cap rises from 3 to 6 (the 2026-07-06 cap predated
token watching — a small watchlist alone filled all three seats and
the fourth pin silently never showed). Still newest first, still
user-chosen only, so the no-obligations voice rule holds; the cap
exists so Home stays a composition, not a scroll of pins.

## 50a. "Just landed" opens (user, 2026-07-11)

The cover's Just-landed card was the one thing-bearing block on Home
you couldn't tap (user: "shouldn't a user be able to tap it and go to
it?"). It now opens its thing's sheet — the same tap the Pinned rows
earned on 2026-07-10, no long-press menu (nothing to unpin). The
composition carries the thing id as the Cover's new trailing arg; the
id streams in last, so a half-streamed card simply isn't tappable yet.

## 51. The token chart grows up (user-approved mock, 2026-07-11)

Ruled on an interactive mock (two passes), then built. One anatomy at
two doses — `TokenChartView` is the sheet's full read, `TokenChartPlot`
the bare plot the Home row reuses; the feed Sparkline is deliberately
untouched. What shipped: (1) range chips 24h/7d/30d in the pill grammar
— GeckoTerminal's hourly candles carry 24h and 7d, daily carry 30d, all
free; the chosen range persists per token. (2) The delta wears a
state-fill pill that names its window ("−1.8% · 24h") so the percent
can't be misread against the wrong period. (3) Scrub, sheet only:
press-then-drag (sequenced after a long-press so the sheet's scroll
still wins a plain swipe); the header rolls to the scrubbed value, the
finger carries only the when ("9h ago"), selection ticks per point.
(4) High/low are the only numbers on the plot, tertiary, each anchored
to its point by a 2.5pt dot — still no axes, no grid (the hairline law
holds on charts). (5) Gradient area fade; the live endpoint pulses
gently (the pulse claims only the endpoint; off under reduce-motion).
(6) Loading is a skeleton of the exact anatomy with one slow shimmer,
never a spinner. (7) The Dexscreener 5-point fallback stops pretending:
straight segments, visible dots, "24h · 5 price points", no range
chips; longer ranges without candles say so and step back rather than
fake a curve. (8) Light mode pulls the state hues 35% toward black
(BridgeIcon's mix). The draw-on reveal replays on range switch — a
range switch is a data arrival. TokenChart.fetch gained a range
parameter (default .day; TokenPulse and Diagnostics unchanged);
`change24h` became range-generic `change`.

## 52. Composer invisible — root-caused; the glass becomes a veneer (2026-07-11)

The prd 44 symptom returned, now on Home (device report: FAB tap →
keyboard up, no bubble). prd 44's underlay couldn't have held: it was
a `.background` on the same view that `glassEffect` wraps, and
glassEffect renders the WHOLE modified view as the glass element's
content — a glitched morph takes the content and its underlay down
together. Restructured so the failure can't reach the content: the
field and chips never enter the glass; the bubble's background is a
ZStack of the solid ink (plain fill, no glass) under a Color.clear
glass VENEER that carries the "composer" morph id. A failed hardware
morph now loses only the veneer's sheen — the composer itself cannot
disappear. Look and morph are unchanged when the glass behaves.

## 53. Shared captures land without a relaunch (2026-07-11)

Device report: a note shared from Apple Notes said "Saved to Casberi"
and never appeared. The write was real (same app-group store, correct
entitlements); the app just never saw it — SwiftData's @Query does not
observe another process's saves (Apple: forums thread 764290; their
pattern is a foreground reconcile). Fix, both sides: the share
extension leaves a `capture.landed` flag in the app-group defaults
after a successful save (the `compose.request` handshake, reused);
RootShell consumes it on foreground and nudges — one no-op dirty-save
on the main context makes every @Query re-fetch, and fresh fetches DO
read cross-process rows; the newest thing also gets the Spotlight pass
the extension process couldn't give it. Honest caveat, prd 44 style:
the dirty-save-as-@Query-kick is the standard workaround, not a
documented contract — if a shared note still doesn't paint, the next
step is consuming SwiftData history (HistoryDescriptor) instead.

## 54. The weekend recap opens the week's synthesis (user, 2026-07-11)

"Your week, banked" was a statement you could only read (user: it
"should be a tappable object that synthesizes the week"). The weekend
cover now carries "@week" in the Cover's id seat (the same seat the
Just-landed card uses for its thing id, prd 50a); tapping the card
opens the composer and sends "What's this week?" through the real
answer path — a new chrome.ask(query) channel: RootShell opens the
bubble on set, the composer consumes the query and commits it. One
synthesis engine: the recap is a door into the ask, not a second
week-renderer. A quiet week answers honestly.

## 55. Your notes — the import group, and Notes tells the truth (user, 2026-07-11)

Ruled after API research (verified live, not from memory): Day One has
no public API and Zapier/IFTTT are write-only, but its iOS app exports
a JSON zip; Apple Journal has no read API (JournalingSuggestions flows
the OTHER way) but exports per-entry HTML from the profile menu; Apple
Notes has nothing — no API, no export, share sheet only. So the
catalog gains a "Your notes" group of three, each saying exactly what
it is: DAY ONE and APPLE JOURNAL are one-time imports (the ChatGPT
pattern — steps stated, one picker, dedupe on stable refs, newest-500
cap, re-runs add only what's new; entries land as note things dated as
written, Day One keeps tags, photos stay in the export for now, said
on-screen). APPLE NOTES is the share-path explainer: its Connect
routes to a screen that teaches open-note → share → Casberi, offers
one real verb (Open Notes), and REGISTERS NO SEAT ever — nothing to
connect, so no connected state to fake; the user's instinct ("then our
whole notes section is some type of import... notes would be just a
share to") became the design. The Journal parse is deliberately
tolerant (filename carries date+title; body strips to text; Apple's
format is undocumented and may drift). Debug: `-dayoneImport <path>`,
`-journalImport <folder>`. Evernote stays OUT: key issuance frozen
since Jan 2026, .enex is desktop-only — recheck later. Website updated
in-session per the standing rule (marquee ×3, "Notes & journals"
section, self-drawn inline icons — no Apple assets hotlinked or
bundled).

## 56. Build-29 review: the import batch, hardened (2026-07-11)

Eight-finder review of the notes/chart/composer batch; confirmed
fixes applied:
- Day One dates parse via IngestSupport.isoDate — a fractional-second
  export previously dropped EVERY entry and reported "Nothing new".
- Zero-yield imports (empty entries, or Journal filenames that don't
  parse) are now FAILED reads — no success haptic, no connected seat.
- The import save is do/catch — a failed save fails the summary
  instead of reporting "N entries in" for things never persisted.
- Journal HTML entities decode via the shared helper (numeric refs
  like &#8217; now decode; the hand map's dictionary order could
  double-decode). Journal dedupe set grows during the run.
- Composer's ask consume re-checks isOpen after the settle sleep —
  closing the bubble inside 400ms no longer fires an empty ask.
- TokenChart: a transient fetch failure no longer permanently
  overwrites the remembered range; the "No 7d prices yet" note
  survives the step-back so the revert explains itself.
- Home token rows pass pulses:false — the pulsing "live" endpoint is
  the sheet's (which refetches); a static row claiming live overclaims.
- Unknown @-sentinels (incl. mid-stream partials) do nothing instead
  of opening a bogus project. "Your notes" maps explicitly to the
  Your life category. Spotlight indexes imports as one batch.

DEFERRED (recorded, not blocking): import-screen triplication (one
parameterized screen incl. ChatGPT), the five parallel source-name
switches (belongs in one per-bridge table), GeckoTerminal pool-address
memoization, regex precompilation in plainText, scrub-path hi/lo
caching, Cover positional-arg padding (keyed args), share-extension
reconcile as a SharedStore pending-list (today: newest-only Spotlight
pass, heals at next launch), Feed header's loss of Pause for routed
bridges (deliberate reroute in 363667c, needs a ruling on where Pause
lives from Feed).

## 52a. The bubble goes solid (2026-07-11)

Third pass on the composer surface, and the ruling that ends it: the
OPEN bubble wears solid ink, no glass. prd 44 put glass ON the
content (device: bubble vanished — a glitched morph loses the glass
element's whole content); prd 52 split a clear glass veneer behind
the content (sim: the whole bubble FROSTED — iOS 26 hoists glass
into its own composited layer above app content, so a veneer is
never truly behind). Same lesson twice: the open composer must not
depend on the glass pipeline. The FAB keeps its glass; the scale
animation carries the open; §8 permits glass on the floating layer,
it does not require it. Verified crisp on sim via -uiAnswerProbe.

## 57. Messages are social, not media (2026-07-11)

Telegram (and Slack with it — the "Your messages" group) moves from
the Your media category to Social in Browse. Telegram's plan stays
as parked 2026-07-08 (prd, no-server ruling): reading Telegram needs
MTProto — a server and a platform wall — so it sits as a Soon card
("Chats join your things", not connectable) alongside X and YouTube
until the server question is answered deliberately.

**Amended — Telegram REMOVED from the catalog (user, 2026-07-14).** With
no server on the table, the three ways in were weighed and all rejected:
the Bot API is server-free but capture-only (a bot sees only what's
forwarded to it and can never speak as the person); TDLib reads real
chats on-device but is a client-grade dependency behind a platform wall;
a Desktop-export import bridge would work with no server — but the user
doesn't believe anyone wants to import their chats. So rather than keep
shipping a Soon card promising a sync only a server/TDLib future could
honestly deliver, the offer is cut entirely. Gone: the `BridgeCatalog`
offer, its `brand-telegram` asset, KindGlyph/StorePreview/HomeComposition
cases, the onboarding marquee tile (Apple-row boundary re-indexed), and
the "Messages" browse group (Telegram was its only member — Social now
browses just "Network"). Slack remains its own offer. Not on the website
(Soon apps were never listed), so this is app-only. If Telegram ever
returns it re-enters this decision from scratch.

## 51a. Ranges speak finance: 1D / 7D / 30D (2026-07-11)

Two fixes from a device report: (1) the range chips read 1D/7D/30D
now — "24h" was both wordier and the odd one out against how every
price app names windows; the Home row's delta pill follows ("−1.8% ·
1D"). (2) The chip label pins to one line (.fixedSize) — squeezed
for width, "24h" folded into a circled "24/h"; under pressure the
row gives, never the label. Remembered ranges stored under the old
raw values fall back to 1D once, then re-persist.

## 58. Home becomes the board (ruled 2026-07-11, build TBD)

The direction that reframes Home, ruled from three mock rounds
("holy shit that is so cool"): Home is a PINBOARD of movable,
richly-drawn pieces.

THE GRAMMAR (mock V1 + V3 synthesis):
- Home below the cover is a single column of module cards — pinned
  things, each wallet's holdings map, the "What's going on" treemap,
  and source modules (music, social, Pinterest, screenshots…).
- The person owns the ORDER: long-press lifts a card (scale, slight
  turn, shadow — the mocked drag state), drag reorders, order
  persists. "What's going on" moves like everything else.
- The person owns the SIZE: any card can be promoted to LARGE, where
  its media becomes the card (the full-bleed album-artwork treatment
  from mock V3). Order and scale, both user-owned — that is the
  personalization story, not themes or fonts.

THE PIN RULE (answers "why does one pin outsize another"): the big
tilted pin belongs to ONE card — the things the person pinned by
hand. Every other piece wears the same small tertiary pin in its
corner: big pin = what I keep close, small pin = a piece I placed.
The pin itself is untouchable (user: "i love the pin").

FORM RULES: "What's going on" is ALWAYS the treemap — it moves and
resizes but never collapses to a text tile (amendment, same session;
the OpenClaw status line is a different creature and not this
module). Rich module interiors: music = album artwork; social
(Bluesky/Farcaster) = avatar + latest post, clean; Pinterest and
screenshots = image tiles (screenshots draw from the corpus's own
stored thumbnails, prd 48).

BUILD PLAN (goals, for a future session): (1) module registry +
persisted order, drag-to-reorder on the GenUI root; (2) card sizes
(regular/large) persisted per module, large = media-led rendering;
(3) rich module renderers — music artwork strip/bleed, social
avatar card, screenshots strip; (4) "pin to Home" verbs from source
screens so the board grows from the catalog. Mocks deleted; the
Desktop comparisons (home-board-ABC, home-rich-board-123) are the
visual record.

## 58a. The pin is the control (amendment, 2026-07-11)

How sizes change, ruled — "why not just tap the pin": TAP THE PIN.
Every pin on the board is a button: tap it and its card blooms to
large (the pin presses in, the media spreads); tap again and it
settles back. No menu, no edit mode, no resize gesture to teach —
one coach line ("Tap a pin to grow its card"), retiring on first
use. The ambiguity with "unpin" is dissolved by placement: removal
NEVER lives on the pin (a wallet unpins from its own screen; the
pinned-things card can't be removed), so the pin is free to mean
"press me". Same rule for the big pin: tapping it grows the
pinned-things card, whose large form is the moodboard-tile interior
(mock B's yield). Long-press still lifts a card to drag; pinch may
arrive later as an unadvertised extra, or never.

## 59. Catalog reshuffle: X is social, Slack is work, notes stand alone (user, 2026-07-11)

Three moves, one ruling: X leaves "Your saves" for "Your network" —
it's a social account first, bookmarks or not, so it browses under
Social beside Bluesky and Farcaster. Slack leaves "Your messages" for
"Your work" — a workplace tool, shelved with GitHub, Linear, and
Notion (this narrows prd 57: Telegram stays the Social messenger;
Slack no longer rides with it). And "Your notes" graduates from a
group inside the Your life category to its OWN Browse category
(supersedes prd 56's Your-life mapping), with Obsidian moving in from
"Your work" to join Apple Notes, Day One, and Apple Journal — the
vault is notes, not project tracking. Website sections mirrored in
the same session per the standing rule: X → "Social & messages",
Slack → "Work & scheduling", Obsidian → "Notes & journals".

## 58b. The board is complete (2026-07-11)

All four goals of prd 58 shipped: Goal 1 (drag-to-reorder, order
persists) and Goals 2-4 (tap-the-pin sizing, rich media modules for
music/Pinterest/screenshots/social, and "pin to home" from the
catalog) both landed same-day. Home is the pinboard the mocks
promised — movable, resizable, richly-drawn, and growing from wherever
a person connects an app. prd 58/58a doctrine is now BUILT, not just
ruled.

## 58c. Large media tiles stay on the page (fix, 2026-07-11)

Bug found in build 32: a screenshot's large-mode moodboard tile
rendered off-page — the image overflowed past the screen edge. Root
cause: `GenMediaTile`'s flexible-size path did
`.aspectRatio(_, contentMode: .fill).frame(maxWidth: .infinity,
maxHeight: .infinity)` with no GeometryReader, so a portrait photo
sized itself to its OWN native pixels instead of the card — the
same SwiftUI trap CLAUDE.md already documents ("a bare
Image().resizable().scaledToFill() ... expands to image size").
Fixed with the pattern HomePageBackground already uses:
GeometryReader pins an explicit width/height, then `.clipped()`.
Verified on sim with live Pinterest content (25 things) rendering a
correctly bounded 2-column grid.

## 58d. Two device reports fixed: wallet loading gap, sticky scroll (2026-07-11)

Both traced to real causes, both fixed:

WALLET "DISAPPEARED" — actually a loading gap, not data loss. A
pinned wallet's balance is a real network round-trip; the slot sat
completely empty for that window (verified via logging: the compose/
board-sync pipeline was always correct, the card lands the moment the
fetch resolves) and read as "my holdings disappeared" instead of
"loading". Fixed the honest way, reusing the app's own starter-
preview idiom (appendStarterPreviews's muted TagMapPreview): a
"Your wallet · Loading your holdings…" placeholder occupies the slot
from the moment a fetch starts until real cells land. Not a board
module — nothing to drag before the real card exists.

SCROLL "STICKY" — the drag-to-reorder gesture (Goal 1) attached a
composed LongPressGesture.sequenced(before: DragGesture) via
.simultaneousGesture to EVERY board card, all the time — the exact
class of bug CLAUDE.md already names ("a child .gesture(DragGesture)
beats ScrollView vertical scroll on device"), reproducible only on
hardware (sim never showed it). Rebuilt on the two-phase pattern real
apps use for reorderable-in-scrollview: `.onLongPressGesture` (Apple's
own well-behaved recognizer) detects the lift on every card with zero
scroll interference; the actual DragGesture is now attached ONLY to
the one card currently lifted (a small `ifTrue` conditional-modifier
helper), so N-1 of N cards carry no competing recognizer at any given
moment instead of all N carrying one permanently. Unverifiable on
simulator by construction (never reproduced there) — needs the
person's own device to confirm.

## 58e. Weekend chips return (as week counts); music art re-heal (2026-07-11)

WEEKEND CHIPS — the "Your week, banked" cover dropped the kind-count
chips entirely; ruled (user) that losing the count row read as the
weekend flattening the screen. The original objection (today-only
counts misread under a week headline) is answered by scoping the
chips to the WEEK on weekends: week counts under "your week, banked"
ARE the week's composition, so they belong. Weekday cover keeps
today's counts; weekend cover shows the week's. Verified on sim.

MUSIC ARTWORK — device report: covers "worked before, broke
recently" (a schema-change reinstall wiped the stored previewImageURL
values, and the id-only catalog lookup couldn't rebuild them because
a LIBRARY play's id can't be resolved via MusicCatalogResourceRequest
matching id). Added a Pass-2 catalog SEARCH by title+artist for every
still-artless music ref — the copy the search finds carries mzstatic
art — so a re-ingested corpus self-heals. Plus a stage-by-stage
NSLog (recent-played / stored-artless / id-lookups / resolved / via-
search / still-artless counts) so the next build tells us exactly
where it fails if search doesn't cover it. Render path confirmed
correct on both surfaces (Home shelf + feed row read previewImageURL);
this was never a display bug.

## 58f. The magazine board (v1, 2026-07-11)

Flipboard elegance, translated to Casberi's law (ink-black, all-SF,
the sacred pin, the ledger). Three ideas ruled from a two-variant
live mock ("variant 1 for real"); v1 ships the LAYOUT:
- MOSAIC RHYTHM: image-media modules (music, Pinterest, screenshots)
  render as art TILES on the board — half-width when two pack into a
  pair row, full-width (one cinematic band) when alone. Structural
  modules (pinned, wallet, "what's going on") and text posts (social)
  stay full-width. The rhythm emerges from the person's own size
  choices, not a fixed template. Tap a tile's pin → it grows to the
  full shelf/grid/hero (all items).
- Built on the SAFE row-based reorder (prd 58d): rows drag as units,
  so the just-fixed scroll gesture is untouched.
- New: genMediaCompact env + GenMediaCompactTile (lead image + eyebrow
  scrim + corner pin); packRows in HomeScreen; isPairable gate.
Verified on sim: Pinterest+Screenshots pair correctly; a lone media
module renders as a full-width art tile.

DEFERRED to v2 (the mock's other two ideas): the AUTO-HERO (one
standout image featured full-bleed automatically, editor-style) and
PARALLAX (images drift within frames on scroll; cover rubber-bands on
overscroll — the motion that makes it feel alive). Drag FEEL and the
music tile need device verification (music art can't render on sim).

## 58g. The magazine hero (v2a, 2026-07-11)

The "one thing dominates" half of the Flipboard translation, made
USER-controlled rather than auto: growing a media tile (tap its pin)
now features its lead image FULL-BLEED as an editorial hero — 300pt,
the item's title over a bottom scrim, the rest a browsable strip
below. Unifies Pinterest/screenshots with how music already grows
(GenMusicHero); replaces the old large-form 2-col grid (the moodboard
grid stays the pinned card's idiom, so the two large forms differ by
purpose). You feature what you grow — no auto-picked hero to get
wrong. Verified on sim: a grown Pinterest tile renders the full-bleed
hero with title scrim.

PARALLAX (v2b, 2026-07-11): BUILT — a media tile's image is overscanned
~14% and drifts vertically as it scrolls through the viewport
(scrollTransition, a RENDER-only transform that can't touch the scroll/
drag gesture; Reduce Motion collapses it to zero). Unverifiable on the
sim (no touch-scroll, a still can't show drift), so the FEEL is a
device pass — but it's safe to ship because it's render-only. Cover
overscroll rubber-band is the one motion piece still deferred. An AUTO-picked hero (feature the newest
image with no tap) was considered and set aside: it duplicates content
that also appears in the media tiles, a redundancy the user-grown
hero avoids entirely.

## 60. Casberi speaks five languages (user, 2026-07-11)

BUILT — localization for English, Spanish, Simplified Chinese, Japanese,
Korean. Rulings:

- SAMPLE CONTENT STAYS ENGLISH (user ruling). Only genuine UI chrome is
  localized; the fake seeded "things" (Dinner with Sam, Trip plan: Lisbon,
  Evening run, Deploy the staging build…) read as a person's real saved
  items, which would never be machine-translated — so they stay as-authored.
  Real captured content (a shared image's default title, the "You" source)
  is likewise left as data.
- IN-APP LANGUAGE SWITCHER, live. A "Language" tile on Settings opens a tray
  (DSTray, one row per language in its own script + English gloss + accent-
  selected checkmark, plus "System"). Picking one repaints the whole app on
  the spot — `RootShell` hands the tree `\.environment(\.locale, LanguageStore
  .shared.locale)`, so every SwiftUI `Text` re-resolves from its `.lproj`
  with no relaunch. The choice also writes `AppleLanguages` so `String(
  localized:)` and the next cold launch agree. This is an override ON TOP of
  the device language — the phone's language is untouched.
- TWO SURFACES, both covered: (1) UI chrome via a String Catalog
  (`Localizable.xcstrings`, source en) — literal `Text("…")` auto-localize;
  variable-fed chrome (tile titles, tab labels, DSTray titles, Feed day
  headers, the HomeComposition generative-doc hero) is localized via
  `Text(LocalizedStringKey(runtimeKey))` or `String(localized:)`. (2) The
  on-device model answers in the reader's language — `LanguageStore
  .llmLanguageDirective` is appended to the grounded-answer and synthesis
  instructions (empty for English, so English prompts are unchanged).
- WIDGETS + SHARE EXTENSION carry their own catalogs (separate bundles) and
  follow the DEVICE language — an extension process can't see the app's
  in-app override; standard iOS behavior.
- Translations are AI-drafted, marked `needs_review` in the catalog — a
  native-speaker pass is the remaining gate before the App Store. The
  format-token integrity of every string was machine-validated (no dropped
  `%@`/`%lld`). Verified on sim across ja/ko/zh-Hans/es: Feed, Settings,
  Home (generative doc), the switcher, tab bar, and the extension bundles.

## 60. "How it works" — the persistent explainer (user, 2026-07-11)

New people need one place to (re)learn the model after the retiring
coach lines (pin/size/chip) are gone. A "How it works" tile joins the
Settings grid (badge questionmark.circle, "New here? Start here"),
and the same sheet greets a new person once at the END of onboarding
(presented on the cover's onDismiss, never racing the dismissal).
Named "How it works", NOT "About" (About reads as version/legal).
DELIBERATELY EVERGREEN — five principle-level points in Casberi's
voice, no gesture-by-gesture manual (three gestures changed in one
day; a written how-to would drift): Connect what's yours / It all
lands in one feed / Act on anything / Home is your board / Ask across
everything. Text auto-localizes (LocalizedStringKey); English until
the catalogs carry the new keys.

## 58h. Board refinements — OPEN (diagnosed 2026-07-11, for a fresh build)

Two board gaps found on device testing (build 35/36), diagnosed in
code, NOT yet built:

1. FREE DRAG ("move anything to any position"). The board drag is
   ROW-based: modules pack into rows first (media pairs 2-up, else
   full-width), and ReorderableBoard.reorderIfNeeded moves whole ROWS
   by vertical position (order is [[String]]). So a paired tile can't
   be pulled out and placed independently — pairs move as a unit.
   FIX: make the drag operate on the flat MODULE order (not rows) —
   drag one card, drop anywhere in the sequence, re-pack (packRows) on
   drop. Likely linearize the board during an active drag (every
   module full-width) so the drop target is unambiguous, then re-pack
   on release. Touches ReorderableBoard + HomeScreen's boardRows/
   packRows/onReorder.

2. TOKEN CHART WON'T SHRINK. GenTokenRow (GenRenderer) has ONE form —
   name + 1D delta pill + a fixed 48pt TokenChartPlot — and ignores
   genModuleLarge/genMediaCompact entirely. Tapping the pin to shrink
   flips HomeModuleSize but the render is unchanged (chart clips, same
   footprint): the user's "stays same size, loses the chart". FIX: add
   a COMPACT form to GenTokenRow — symbol + price + colored delta chip,
   NO chart — shown when the module is regular; the chart only at large.
   (A token reaches Home as a pinned thing → TokenRow inside pinnedW,
   or its own module; confirm the exact container when building.)

Both need DEVICE verification (drag feel; real token/wallet data — the
sim can't exercise either, and its Photos re-request dialog blocks
screenshot repro). Build on prd 58/58a/58f grammar.

## 58i. The bento board (user, 2026-07-12) — BUILT, device verification pending

Supersedes 58h's two fixes and the prd-58a two-state (regular/large)
size model with a THREE-span bento: every module is a tile the person
sizes independently — small (1×1), wide (2×1), or big (2×2) — and the
board bin-packs to fill the gaps, no holes. Ruled after live mocks of
three directions (independent 2-size, three-size, one-hero spotlight):
the person wants the expressiveness of three sizes, so premium comes
from GUARDRAILS, not fewer states — a composed one-hero default (Pinned
opens big, everything else small) plus per-module span limits (a
treemap skips `wide` — it needs area; a social post has no `big` — one
post is empty at 2×2).

FREE DRAG (prd 58h Goal 1): built as diagnosed — ReorderableBoard now
reorders the FLAT module order, linearizing to one column mid-drag so
the drop is unambiguous, re-packing on release. Small tiles pair 2-up;
wide/big span full width.

TOKEN SIZING (prd 58h Goal 2, extended): a pinned token is no longer a
row inside the Pinned card — it's its OWN board tile (HomeComposition's
appendPinned splits tokens out; everything else still rides pinnedW),
sized on its own: small is a bare sparkline (the "shrunk token" rule),
wide adds price + delta, big is the full chart. The token's content IS
its chart at every size, just at a different dose (prd 51).

Every module grew a small form: Pinned → count tile; wallet/"what's
going on" treemaps → a short 3-cell mini-map (subline dropped, no room);
social → avatar only; media shelves already had small (the prd 58f
compact tile). HomeModuleSize migrates the old large/regular Set to the
new span dict on first launch; the pin now CYCLES a module through its
allowed spans instead of a binary toggle.

Also folded in: two drag-engine fixes an adversarial review caught
(MagazineLayout's pair-tile width could go negative under a probe's
tiny/unspecified proposal; paired tiles now fill the row's height so a
short tile sits flush beside a taller one).

NOT YET DEVICE-VERIFIED (sim can't exercise): drag feel, tap-the-pin
cycling, real token chart data (needs a pinned token + live Dexscreener
fetch).

## 58j. A pin is a mark, not a card (user, 2026-07-12) — BUILT, verified on sim

Three consistency rulings, all from the user reviewing 58i's board:

PINS DISSOLVE INTO TILES. The bundled "Pinned" card (`pinnedW`) is gone.
It carried an oversized tilted pin and was force-sized big, so one card
looked and behaved unlike every other module — and a bundle can't answer
"any card can be the hero." A pin is a mark on a thing, not a kind of
card. Now every pinned thing is its OWN board tile (a span-aware `GenRow`
tile — small pairs 2-up, wide/big lead full-width), wearing the SAME
corner `ShelfSizePin` every other module wears. Tokens already composed
this way (58i); everything else joined them. Supersedes 58i's "Pinned
opens big / everything rides pinnedW / Pinned → count tile" — none of
those exist now. The oversized `PinMark`, the "N pinned" count tile, and
the moodboard grid interior were deleted with the bundle.

HERO IS POSITIONAL. The "composed one-hero opening" is kept but decoupled
from Pinned: the FIRST board module leads big (its default span), a hero
SLOT any card can occupy — reorder to change which card heroes, or grow
any card yourself. A module that can't take `big` (a social post) stays
small even when it leads. On a pin-less board the treemap now leads big;
that's the synthesis anchor, so it's the right default hero.

CHIPS ARE THE CORPUS, NOT THE DAY. The cover's kind-count chips now read
the WHOLE corpus by kind (a stable "what your stuff is made of"), the
same every day, no reset — superseding "today's counts" (§ around
prd-677/1978) and the weekend "week's counts" special case. Today's
activity was noise for anyone with feeds (always a big number, never
news); recency is Feed's job. The chips complement the map: map = your
corpus by theme, chips = your corpus by kind. They ride the quiet cover
too now.

ONE LAYOUT EVERY DAY. The weekday-triggered "Your week, banked" weekend
composition (§ prd-54, prd-1978) and the morning/evening split are
removed — Home shouldn't change shape by the clock. The week recap keeps
its home behind the composer's "What's this week?" ask (prd 54's ruling
that the recap is a question you pose, not a screen that ambushes you);
the cover no longer emits `@week`.

## 58k. Pin the app, not the item (user, 2026-07-13) — BUILT, verified on sim

Supersedes 58j's "PINS DISSOLVE INTO TILES" and the whole per-item pin
model. The user's ruling: pinning is per-APP now, not per-thing. You keep
"your reminders" in view, not one reminder; "your watchlist", not one
token; "your Bluesky", not one post. A pinned app is ONE board tile of its
recent things, in the app's own shape.

WHAT WENT. `Thing.pinned` is deleted (property, init arg, CloudKit field).
Every per-item pin affordance is gone with it: the Feed swipe's Pin action
(swipe is now the hand-off only), the thing sheet's Pin row, the
Dexscreener/Kalshi watchlist swipe pins, the composer's "pin the last
link" phrase (`PinAsk`), the Feed pin badges, and `HomeComposition.appendPinned`.

WHAT REPLACED IT. Pinning is `HomePinnedSources` (already the model for the
four media shelves), now generalized to EVERY connected source — the
4-app `pinnable` gate is gone. `appendPinnedApps` composes each pinned
source as its store-preview shape filled from the live corpus: image
sources keep their bespoke `MediaShelf`; the wallet keeps its treemap;
everyone else composes as a `Widget(title, [rows], source)` — a titled
card of the app's recent things (a `TokenChip` — inline sparkline + price + 1D
delta, surface-less so it never nests a card in the card — for Dexscreener
tokens; `MailRow` for the inboxes; a tappable `Row` for the rest). The trailing
`source` arg marks the Widget a board module: draggable, sized by the same
corner `ShelfSizePin`, removed via long-press "Remove from Home" (which drops
that source's pin — carried on every row too, since a row's own contextMenu
would otherwise shadow the card's). Board key `app:<source>`, handed over by the
composer in `Document.boardKeys` so it round-trips on a streamed cold launch
(deriving it from `stream.els` would miss while the doc is still parsing). Rows
tap to open the thing and carry the "Open in app" hand-off, but no per-row
Unpin — removal is the whole app's.

Deletions cleaned up in the same pass: `GenSocialCard`, `GenTokenRow`, and
`GenRow`'s square board-tile form are gone (no emitter after social→Widget and
tokens→TokenChip). Not migrated: a pre-update board's old `pin:`/`token:`/
`social*` size/order keys don't map to the new `app:<source>` keys, so an
existing board's customization resets once on upgrade (acceptable pre-launch;
no real users yet).

WHERE YOU PIN. "Pin to Home" moved onto every app's OWN screen (the reused
`PinToHomeButton`): `BridgeDetailScreen` (ungated to all connected apps),
`HandleSetupScreen`, `RSSScreen`, and the bespoke screens (Dexscreener,
Kalshi, Mail, Twitch, Steam, Obsidian, the imports). Shown once the app
has landed a thing (pinning doesn't invent content). Bluesky/Farcaster
still show by default and carry the inverse "Show on Home" — they just
grew from one auto-earned post to a plural tile.

## Audit note — 2026-07-12 screen sweep (nightly)

Build codesigned clean from `~/Developer/casberi`. Perf warm: **launch
319ms · memory 253MB · answer 1771ms** — all under ceilings, no flags,
`answer` down 28% from the prior run (2453ms). Headless answer probe
returned a well-formed structured answer (Insight + ProjectTile + 3-row
Widget) in 1766ms.

No confirmed regressions or honesty violations. Data tray, Diagnostics,
product/setup screens, project detail, and both answer fallbacks all
render honestly; no hairlines; single-grid catalog, light mode, and
Dynamic Type XXL all hold.

ONE ITEM TO RE-VERIFY once the Home-board WIP commits (§58h/58i/58j,
uncommitted in `GenRenderer`/`HomeComposition`/`HomeScreen` at audit
time): the by-app "What's happening now" board widget rendered its app
header ("Claude") over an **empty body** (no thing rows) across three
warm shots — could be an unfinished renderer or an intended empty board
tile. Flagged WIP-in-flight, NOT filed as a regression; re-audit after
the board work lands. Corpus was the 3-thing reseed and `app.language`
was left on `ja` by a prior session — both environment, not findings.

## 61. The elevation ladder — depth by tone and shadow, never by line (user, 2026-07-12)

The surfaces read flat: #000 page and one flat #111 sheet, with no border
and no shadow, made every screen a wireframe — worst in light mode, where
white cards on the #f2f2f7 page were nearly invisible. The fix is an
**elevation ladder**: depth carried by tone and a soft ambient shadow, never
by a line. This amends design-principle 1 / build-brief §8's "the fill carries
elevation" — the fill alone wasn't enough — WITHOUT reviving hairlines: a
shadow is not a line, and nothing draws one.

Three mechanics, three tokens/modifiers (`Design/Glass.swift`,
`Design/DesignTokens.swift`):

1. **Card lift** — `DS.cardShadow` (dark `#0000008c`, light `#0000001f`) via
   `dsWidgetSurface()` (widget radius) and `dsCard()` (card radius). The shadow
   rides the fill SHAPE, not the composited view, so it casts from a cheap path
   with no per-card offscreen pass on a scrolling board. Every gen-UI module
   card (Home board, Project/App detail, Thing sheets, Wallet), plus the Apps
   catalog cells, Account/Settings bento, Feed rows + header, and Onboarding.
2. **Section lift** — `dsListCardRow()` for inset-grouped `List` rows: the sheet
   fill carries the card shadow, and because inset-grouped rows are GAPLESS a
   row's shadow falls on the adjacent same-color row and vanishes — only the
   section's outer silhouette casts, so a whole section reads as one lifted card
   (no per-row banding). The ~16 setup / import / detail screens. NOT for
   `.plain` lists (Feed), where rows aren't gapless — Feed's rows lift via their
   own inset-card `listRowBackground`.
3. **Well recess** — `DS.surfaceWell` (dark `#080809`, light `#e9e9ef`) steps a
   nested backing BELOW the card plane (chart/cover/media wells). Tone alone
   carries the recess — no inner stroke.

Deliberately EXCLUDED: the floating layer (composer, toasts, tab bar — Liquid
Glass carries its own elevation; a card shadow would double up) and pills /
controls (Deny button, onboarding capsules — controls, not surfaces).
(amendment 2026-07-13, `0764ee3`: the tab bar died — the floating layer is now
composer, FAB, and toasts. The exclusion rule is unchanged; only the example is
retired. Full ruling: §100.) A
"raised chip" token was prototyped and DROPPED: raising by tone alone can't
survive light mode (a white chip on a white card), and it would need a
per-element shadow to work — not worth a fourth mechanic. Lift + recess are the
two that hold in both modes.

## 62. Contacts leaves onboarding — no address-book ask at minute zero (user, 2026-07-12)

The Contacts bridge (added 2026-07-12) auto-joined onboarding's mini store like
every other one-tap local connect. But an address-book ask at minute zero reads
as "this app wants to harvest my contacts" — the exact suspicion the app's
"your things are yours" spine exists to avoid — before any trust is built, and
the person hasn't seen a single one of their things yet. Same reasoning that
held Apple Health out of minute zero (health is sensitive before trust exists,
ruling 2026-07-07): both wait one tap away in the store, where the product page
can state the guarantee (search-only, never leaves the phone, read-only) before
the permission sheet fires. Fix: `OnboardingView.offers` now filters a
`heldBack` set `{Apple Health, Contacts}` rather than the single Health
special-case. Contacts stays a full real bridge everywhere else — the Apps
catalog, Browse (People group), and its connect path are unchanged; it is only
absent from the first-run mini store. Contacts icons still fall in the glass
pile (decorative brand art, not a permission ask).

## 63. The source-feed header: one card for expand, its own row for compose (user, 2026-07-12)

A single-source feed used to stack two full-width bars under the circular chip
row: the synced header card, then an "act in this source" row. Two slabs of
chrome before any content, and the header already re-asserts the identity the
active chip carries. The ruling collapses that — but only where honesty allows,
because the two "act" flavors go to different places.

- The **synced header card stays load-bearing and untouched**: icon (with the
  source-switch coin-flip delight), name, `statusLine`, chevron; the whole card
  taps into that source's settings/setup screen (`destination(forID:)`, which
  by the 2026-07-11 routing fix already lands on the add-another-capable screen).
- **Expand** sources (watch/follow: wallet, dexscreener, kalshi, bluesky,
  farcaster, twitch, pinterest, and now RSS) fold their "add another" into that
  same card as a trailing tinted **"+ Add" hint**. It is a *signpost, not a
  second tap target* — the card already opens where you add another, so the hint
  just advertises the capability. The separate expand row is gone. ("+ Add" is
  a localized literal; the per-source phrase — "Track another account" etc. — is
  no longer displayed and lives only on the destination screen.)
- **Compose** sources (Gmail, Todoist, Calendar, Reminders → "New email / task /
  event / reminder") **keep their own row**. That action hands off to *another
  app* — a genuinely different destination than the card's in-app settings — so
  it can't be a hint on the settings card and earns its own bar. (Corollary,
  same session: Gmail now composes IN the Gmail app via `googlegmail:///co` when
  installed, matching the Calendar/Reminders hand-off rule, falling back to
  `mailto:` only when it isn't — a Gmail source no longer silently opens Apple
  Mail.)
- **Read-only** sources (Photos, one-time imports) get neither — no dead
  affordance.

The rejected alternatives are on record: demoting the synced line to a caption
(it's the tap target into settings and carries the coin-flip — kept), a dashed
ghost "+" chip at the end of the chip row (read as a placeholder, not "add"),
and a "+" button on the card as a second tap target (re-introduces the
two-targets-on-one-bar ambiguity the ruling exists to remove). The rule of
thumb: an affordance may fold onto the card only when it shares the card's
destination; anything that leaves for elsewhere keeps its own row.

## 58l. A pinned app tile takes all three spans (user, 2026-07-14) — BUILT

Ruling: every pinned app tile — not just media shelves and the wallet — must
support the full small/wide/big bento range: **small** = a 1×1 tile of ONE
item, rendered fully; **wide** = a full-width card of ONE item as a line;
**big** = a full-width card of THREE items. Previously `allowedSpans` excluded
`.small` for `appTile*` refs (a cramped square couldn't hold a readable row),
so a pinned app was stuck at wide/big. That guardrail is gone — `GenWidget`
now branches on span instead of assuming rows always fit a list.

WHAT SMALL RENDERS. Not the card chrome shrunk down — a dedicated per-kind
solo tile (`SoloRowTile`/`SoloMailTile`/`SoloPostTile`/`SoloTokenTile` in
GenRenderer.swift), dispatched off the one child's component name. Each gets
the full 1×1 seat: a Reminders/Calendar/GitHub/etc. Row shows its title up to
3 lines (never a fragment); Gmail/iCloud shows subject + snippet; Bluesky/
Farcaster shows the avatar + full post; Dexscreener shows the ticker on its
OWN line, a sparkline, and price/delta below — solving the entangled ask
underneath this ruling: a token's symbol (e.g. "ETH") was truncating because
it shared one HStack with the plot and price. Root cause fixed at the source
too — `appChild` had been passing a WATCHED token's full `"Name · $TICKER"`
title into the symbol slot (`TokenWatch`'s own title format); it now extracts
the bare ticker (`HomeComposition.tickerSymbol`), so the list-row form (wide/
big) stops truncating too, not just the new small tile.

Item ceiling dropped from 5 to 3 (`appendPinnedApps`) — big only ever shows
three, wide one, small one, so nothing past the third was ever reachable.

Each solo tile's own long-press already offers Remove from Home (via
`genAppRemove`, wired the same way the card's rows drop the pin) — no
redundant outer contextMenu on the small branch (that would just be shadowed,
the same bug fixed for the card's rows in 58k).

## 64. Kalshi titles get a third line; Share joins the Feed swipe (user, 2026-07-13) — BUILT

Two small device reports, same session.

**Kalshi clipping.** `BandRow`'s title caps at 2 lines everywhere (ruling
2026-07-09) — right for a headline, wrong for Kalshi, whose title IS the full
market question ("Will the Argentina win the 2026 Men's World Cup?"). Rather
than lift the cap for every source, `ShapedRows.swift` now special-cases
`thing.source == "Kalshi"` to 3 lines; every other source keeps 2. Verified
live against the real Kalshi API (keyless, public) via `-watchMarket`.

**Share widens — amends §18.** Swipe on a Feed row was hand-off-only (Open,
ruling 2026-07-12) — deliberately one gesture, one meaning. §18's Feed spec
also states "utilities like Copy never ride the swipe — they live in the
sheet," which Share (a non-mutating utility, same class as Copy) would
literally fall under. The user asked for it explicitly this session, so this
supersedes that line for Share specifically: it now sits on the trailing edge
too, declared *before* Open so a full swipe still triggers Open unchanged
(SwiftUI: the first trailing action is the one a full swipe performs) — full
swipe is further gated to only fire when Open exists (`openVerb(for:) != nil`),
so a thing with no destination (a voice note, a chat import) doesn't get
Share fired by a full swipe that used to do nothing. Share otherwise only
surfaces on a partial swipe or a tap. Copy itself stays in the sheet — this
amendment is scoped to Share, not a blanket reopening of §18's utility rule.

**Share carries the real thing, not just its title.** The thing sheet's Share
row (and now the Feed swipe) shared `thing.content`/`thing.title` as bare
text — hollow for a screenshot, whose whole point IS the image. New
`ThingShareLink` (`ThingContent.swift`) shares the photo itself via
`ShareLink(item: Image(...))`, loaded the same way `PhotoWell` (ShapedRows.swift,
fixed same session) already does: the corpus's own healed copy
(`thing.previewImageData`) first — instant, no Photos round trip — then the
PHAsset, waiting past a network asset's degraded placeholder so Share never
hands out a blurry stand-in. Every other kind is unchanged (URL when one's
detected, else title/content as text). One implementation, used by both
surfaces.

**Researched and passed on:** basedbot.app (a Base/BSC/ETH/Solana trading
*execution* terminal — no publishing API/RSS, and trade-execution conflicts
with the read-only bridge philosophy) and Etherscan (free-tier REST API
exists, but `WalletIngest` already covers ETH activity via Alchemy — Etherscan
URLs are already used, just as the "view transaction" explorer link, not a
data source). Neither earns a bridge.

## 65. Alchemy's Prices API becomes a second chart tier (user, 2026-07-13) — BUILT

Follow-up to §64's Alchemy research: could Alchemy's Prices/Token APIs
replace Dexscreener in `TokenWatch`? Verified live against the shipping key
(`dashboard.alchemy.com`) before writing any code.

**What moved.** `TokenChart.fetch` (`TokenChart.swift`) gains a second tier —
Alchemy's Prices API historical endpoint — between GeckoTerminal (primary,
unchanged) and the Dexscreener coarse fallback (still last resort). Alchemy
covers the same EVM chains `WalletIngest` already reads (`alchemyNetwork`
table: ethereum/base/arbitrum/optimism/polygon) and returns REAL candles at
GeckoTerminal's exact resolutions (verified: 24 hourly points/24h, 168/7d, 30
daily/30d) — so a token GeckoTerminal hasn't indexed yet, on a chain Alchemy
covers, now gets a real curve with week/month ranges too, instead of dropping
straight to Dexscreener's 24h-only 5-point approximation. The Alchemy key
(previously private to `WalletIngest`) moved to `IngestSupport.alchemyKey`,
shared by both callers now.

**What didn't move, and why.** Dexscreener's free-text search
(`/search?q=`) — typing "pepe" and getting live candidates across chains and
DEXs — has no Alchemy equivalent (Prices/Token APIs are address/symbol-scoped,
not full-text discovery); it stays the entry point for watching a token.
Token API logos for the search-result rows were also considered and passed
on: Dexscreener's search response already carries a free inline image field
for those rows, and it's never even persisted onto the `Thing` after
watching — swapping it for a live Alchemy call would trade a free field for
extra round trips with nothing to show for it.

**Separately noted, not done:** the wallet holdings treemap's token icons
(`WalletIngest.swift`) are a bundled static set (`TokenIcon`/`brand-*`,
Trust Wallet's public asset repo) specifically BECAUSE Alchemy's
Portfolio-API logo field came back null for nearly everything (2026-07-09).
Live-tested this session: Alchemy's dedicated Token API metadata endpoint
(`alchemy_getTokenMetadata`, distinct from the Portfolio API) DOES return
real logos for WETH/PEPE/USDC. That's a genuine reason to revisit the
bundled-icon call — but it's a different feature (wallet treemap, not
Dexscreener token-watch) and reverses a deliberate static-over-live
architecture choice, so it's flagged for a separate decision rather than
folded into this one.

## 66. Dexscreener the bridge becomes "Tokens" (user, 2026-07-13) — BUILT

§65 already made the point: the chart underneath a watched token blends
GeckoTerminal, Alchemy, and Dexscreener — three vendors, not one — so
presenting the whole capability to the person as "Dexscreener" overclaimed a
single-vendor identity it no longer had. Renamed everywhere, same pattern
`Wallet` already set (a capability name, not a vendor's): the bridge, its
screen (`DexscreenerScreen.swift` → `TokenWatchScreen.swift`), its `Offer` in
`BridgeCatalog.swift`, its `thing.source` ("Dexscreener" → "Tokens"), its
sourceRef prefix ("dexscreener:" → "tokens:"), its `BridgeRouter.Destination`
case, and its website marquee/catalog tile.

**Icon**: the bundled `brand-dexscreener.imageset` logo is gone — `BridgeIcon`
already falls back to an SF Symbol on a brand-hue squircle when no bundled
asset exists (the exact path `Wallet` already takes, having never had a
bundled logo). Symbol stays `chart.line.uptrend.xyaxis` (unchanged, just
rekeyed from "dexscreener" to "tokens" in `BridgeGlyph.symbol(for:)`); the
brand hue becomes a new gold, `#f5a623` — this app's own mark now, not
Dexscreener's near-black "their dark field" — since a renamed, de-vendored
capability earns its own color rather than inheriting one that named a logo
that's gone. Website mirrors it: the marquee/catalog tile drops its base64
Dexscreener logo for an inline SVG (a filled trending-up-arrow glyph, the
same fill-path convention `Wallet`'s tile already uses) on the new gold
background; the orphaned `website/icons/icon_dexscreener.png` source file is
deleted.

**What stayed named "Dexscreener"**: every place that names the actual
running dexscreener.com API — the search endpoint (`TokenWatch.swift`), the
stored `content` URL a watched token's thing carries, `TokenChart.swift`'s
private `dexscreener()` fallback function, the privacy policy's vendor
disclosure (now also naming Alchemy, which it had missed) — because those
are real, accurate technical facts, not branding. Diagnostic `NSLog` labels
in `ProbeHooks.swift` also keep saying "Dexscreener probe" — internal
dev-only tooling output, not user-facing.

Historical `docs/prd.md` entries before this one that say "Dexscreener" are
NOT retroactively renamed — they're an append-only record of what was true
when written. Read them as: "Dexscreener" there means what "Tokens" means
now.

## 67. The power-user ring stays server-free (user, 2026-07-13)

The next ring of capability — everything a power user reaches for after the
corpus is flowing — was scoped in one sitting, and one constraint rules all
of it: **Casberi runs no server.** Every planned feature must be one of:

- **Tier 1, fully on-device** — Vision OCR, embeddings, App Intents, the
  on-device model. No tension with the promise.
- **Tier 2, device→third-party** — the phone talks directly to an API the
  person already trusts with that data (their GitHub token, their Anthropic
  key, their Todoist account). Casberi never becomes a data custodian; no
  Casberi-operated machine ever sees a byte.

Anything requiring a Casberi-operated server — instant push from webhooks,
always-on monitoring while the phone is pocketed, an email-in address,
cross-user sharing — is **deferred, not designed around**. The positioning
consequence is embraced rather than apologized for: *Casberi catches you up;
it doesn't interrupt you.* Immediacy is the one honest casualty of
on-device, and calm is the product's temperament anyway.

**The order** (user's ranking): ① BYO-key model escape hatch, ② OAuth
where public-client flows exist, ③ write-back verbs in the sheet —
**reversed 2026-07-15, every bridge stays read-only**, ④ round out App
Intents, ⑤ screenshot OCR, ⑥ the librarian digest.

**Rulings baked in:**

- **BYO-key is a verb, never a fallback.** The person's own Anthropic key
  (Keychain, device→api.anthropic.com direct) powers a "try harder" they
  tap per query. It never fires silently, and the answer wears a badge
  saying their key produced it. On-device by default; their key, their
  choice, per use.
- **OAuth only where the flow is genuinely public-client.** GitHub's device
  flow needs no secret and no server — build it. Providers whose token
  exchange demands a client secret (Notion, Todoist, Linear) stay
  token-paste, and the setup copy says why, plainly. An embedded "secret"
  in an app binary is not a secret; shipping one would be dishonest, and a
  relay to hold it would be a server.
- **Telegram write-back is excluded until Telegram read exists.** Respond
  requires read, and today Telegram is `connectable: false` — a shelf
  offer, not a bridge. The Bot API cannot be that bridge: a bot sees only
  what is explicitly sent or forwarded to it (capture, not sync), and it
  can never send *as the person* — a "reply" would arrive from a bot. The
  only honest read path is TDLib, logging in as the person — fully
  on-device, but a heavy client-grade dependency that is its own future
  decision. Until that day, no Telegram verbs.
- **Goal ③ (write-back verbs) REVERSED, 2026-07-15 — every bridge stays
  read-only.** Complete in Todoist and Close on GitHub had shipped
  (`BridgeWrites.swift`, one-tap writes the tokens could already carry,
  gated behind the sheet's confirm) but the user ruled the app shouldn't
  hold write capability at all — the honesty-rule framing ("read-only —
  never writes") that every other bridge's copy already used should hold
  for GitHub and Todoist too, not just most of the catalog. `BridgeWrites.swift`
  was deleted along with the `bridgeWrite` verb, the `-writeProbe` hook, and
  the TokenSetupScreen/GitHubDeviceFlow copy that promised writes. GitHub's
  OAuth still requests `repo` scope (classic OAuth has no read-only repo
  scope — it's the smallest scope reaching private issues/PRs), but Casberi
  never exercises the write half of it. Linear status/comment,
  Bluesky/Farcaster reply/like/repost, and Calendar accept/decline were
  never built and are not planned — no bridge writes back to its source.
- **The librarian proposes; the person disposes.** Digest, tag proposals,
  resurfacing, dedup candidates — all through the proposal-card pattern
  `OrganizeLLM` already set. Nothing tags, merges, sends, or deletes
  without a tap.

**Already built, so not re-planned:** semantic retrieval
(`EmbeddingIndex`, 2026-07-12), Spotlight (`SpotlightIndex`), Save +
synthesis App Intents (`CasberiIntents.swift`). The gaps are OCR, the
search/ask intents, and everything in the list above.

## 68. Delete things / Delete access — two wipes, two verbs (user, 2026-07-13)

"Delete everything" was one button that wiped the corpus (SwiftData +
sidecars + the CloudKit zone) and reported "Deleted — this iPhone and
iCloud" while leaving every credential in the Keychain: eight bridge
tokens, the Steam key, Twitch tokens, mail passwords, the MCP pairing
token, and (since §67 ①) the person's Anthropic key. The copy overclaimed;
the convenient behavior (wipe data, keep setup) was probably what most
wipes actually want — but silently.

**Ruled: data and access are different deletions.** The Data tray carries
two destructive verbs, each stating what goes AND what stays:

- **Delete things** — corpus, voice recordings, background photo, avatar,
  CloudKit zone. The dialog and outcome line now say "your app
  connections and keys stay" out loud.
- **Delete access** — every credential Casberi holds, one move:
  `TokenVault.deleteAll()` (a service-wide Keychain wipe, so future
  credentials are covered without an enumeration to forget) plus the MCP
  pairing reset (paired clients lose their way in). Credential-backed
  bridges unregister so no shelf tile claims a connection it lost. Things
  stay. Photos/Calendar access is iOS's own — the dialog points at
  Settings rather than pretending to revoke it.

A true scorched-earth exit is both verbs, and each one says so.

## 69. The key is an agent key — four providers, one contract (user, 2026-07-14)

§67's "Try with your key" launched Anthropic-only, and every surface said
so ("Anthropic API key", "a bigger Claude"). Ruled: the key is an AGENT
key — the person names the agent they know (Claude, ChatGPT, Gemini,
Venice), never the vendor alone. `Model/AgentAnswer.swift` carries all
four providers (Anthropic / OpenAI / Google / Venice — one request shape
each), per-provider Keychain keys (Anthropic keeps its original vault key
so existing keys survive), validate-before-save against each provider's
own API, and one ACTIVE provider — the last saved — that keyed answers
run on. The settings card is a segmented agent picker; the Settings tile
names the active agent ("Gemini answers on tap") or lists all four. The
contract is unchanged from §67: same grounding, same consent tap, same
honest nil on failure — the key buys a stronger model, not a different
contract.

## 70. Venice connects as a key seat; Strava rides Apple Health;
## Gemini imports via Takeout (user, 2026-07-14)

Three offers went live, each by its honest path:

- **Venice** — nothing reads IN (Venice keeps chats on-device by design);
  its seat powers answers OUT. Connect = paste a Venice key, checked
  against api.venice.ai before it saves (`VeniceSetupScreen`), same vault
  entry the agent-key picker shows. No feed preview — the tagline speaks.
- **Strava** — no OAuth, no Strava account: Strava saves every activity
  to HealthKit, so the Strava seat is `HealthIngest` filtered to workouts
  whose `sourceRevision` names Strava, labeled "Strava". One ref scheme
  (`hkworkout:<uuid>`) across both Health-backed seats so a workout never
  lands twice; each seat's Connect proof counts only its own. Holds back
  from onboarding with Health (same sensitive-before-trust ruling).
- **Gemini** — the ChatGPT/Claude import grade: Google Takeout's
  `MyActivity.json` (no live read exists), one chat thing per PROMPT
  (Google exports no thread structure), "Used Gemini" records skipped,
  dedup on timestamp + a stable FNV-1a of the ask.

Website ruling, same date: the site lists NO "Soon" apps — an offer the
app can't connect simply isn't on the site. X, Telegram, Slack, Spotify,
and OpenClaw left the web catalog (they stay in-app as Soon); Farcaster
shelves under Onchain on the web; the catalog is packed shelf cards
(`#catalog`) mirroring `AppsScreen.categories`, Markets last.

## 71. Tokens and Wallet grow features around the corpus, not a
## portfolio app (user, 2026-07-14)

The token/wallet enrichment set — the frame is Casberi's own: your
HISTORY with the assets, not a market terminal.

- **Since-you-watched anchor** — `TokenWatch.add` keeps the resolve's
  live price on the thing (`Thing.watchPriceUsd`); the token sheet says
  "+41% · since Jul 2 — you watched at $0.0031". Locally known, never
  back-filled; tokens watched before the field stay anchorless.
- **Stat strip** — liquidity / 24h volume / FDV / market cap under the
  sheet's chart, from the same Dexscreener pair payload that resolved
  the token (`TokenStats`); a stat the pair doesn't report isn't shown.
- **"In your things"** — a watched token's Related shelf is MENTION, not
  tags (every watch shares the Watchlist tag, so tag overlap only ever
  showed the other tokens): corpus things carrying the cashtag ($PEPE,
  boundary-checked) or the distinctive full name (4+ chars). Tag overlap
  stays as the fallback; the shelf renames to "In your things".
- **Counterparty naming** — a landed transfer's title names the other
  side when it has a name: another watched wallet's label, a canonical
  contract (Uniswap/OpenSea/1inch/0x/WETH/ENS — table in WalletIngest),
  or reverse ENS (capped 16 lookups/pass, cached with misses). Nameless
  stays plain — the title never wears a raw hash.
- **Value history, forward-only** — each real holdings fetch samples the
  wallet's USD total (4h throttle, 240 cap, per address, dropped with
  the watch); the Wallet screen draws the line "since the day you
  started watching", footer says it's sampled as you use the app.
- **NFT shelf** — Alchemy NFT API (Ethereum + Base, spam filtered,
  imageless skipped); tap opens the piece on OpenSea. Read-only.
- **Holdings cells open charts** — a treemap cell carries its token's
  route ("@t:chain:address", stripped by the parser, never shown); tap
  opens the thing sheet when watched, else a quick chart sheet
  (`TokenQuickSheet`) with one real verb: Watch. Native coins (ETH,
  MATIC, SOL) route through that chain's wrapped-native contract
  (`WalletIngest.wrappedNativeContract`, 2026-07-21) — same price, a real
  Dexscreener pool — rather than falling back to the Wallet screen, which
  stopped making sense once that screen's own holdings/treemap moved to
  the Feed (2026-07-20 surface split): tapping ETH landed on wallet
  management, unrelated to the tapped cell. A chain with no wrapped-native
  entry or no `chainSlug` (Robinhood) still falls back routeless.
- **Watchlist ask + away line** — "How's my watchlist?" is a computed
  answer off TokenPulse's own curves (chip gated on watched tokens
  existing); the "While I was away?" answer appends the watchlist's
  moves over the frozen away window, from real candles at the window's
  resolution — a gap past the 30-day candles says "over the last 30
  days" instead, and coarse-fallback tokens are left out, never guessed.

## 72. A pinned wallet's NFTs ride Home by default (user, 2026-07-14)

Pinning a wallet brings TWO cards: its holdings treemap and — when it
holds any — an NFT strip as its own sibling board module (MediaShelf,
kind "nft"), removable/resizable/reorderable independently. Cells tap
out to the piece on OpenSea (a URL-shaped MediaItem id is a door, not a
thing). For people who don't want it: default-on with a persistent
per-wallet opt-out — the working control lives on the Wallet screen
under each pinned wallet's shelf ("On Home · remove" / "Show on Home"),
because the board's drag driver lifts cards at 0.35s and pre-empts
long-press context menus (the strip carries the contextMenu anyway, for
whenever that arbitration is revisited — a KNOWN pre-existing gap that
affects every board module's long-press "Remove from Home").
Re-pinning a wallet resets its strip to the default (fresh pin, fresh
presence). Wallets with no NFTs contribute nothing.

## 73. Board removal is the minus badge in edit mode (user, 2026-07-14)

The board's long-press belongs to lift/reorder — the drag driver begins
at 0.35s and pre-empts long-press context menus, so "Remove from Home"
via contextMenu was unreachable on every board module. The fix stays
out of the gesture arbitration entirely (four failed commits' worth of
warnings): while the board wobbles, every REMOVABLE module wears a
minus-in-circle badge on its top-left corner (the size pin keeps the
top-right) — hold → wobble → tap the minus, the gesture every thumb
knows. Glyph ruling: minus, not pin.slash (user: the slash didn't read
as "remove from home"). One derivation (`moduleRemoval`) feeds both the
badge and the still-present context menus so the paths can't drift; it
returns nothing for modules with nothing to remove (auto-earned
shelves, the map, the cover — no badge, honesty rule). New with this:
a pinned wallet's treemap is removable ON the board (the unpin verb the
Wallet screen's swipe carries; the wallet stays watched). A removed
card's badge vanishes and the flash confirms instantly; the card itself
leaves when editing ends (recompose stays deferred through the wobble
so modules never shift under an in-flight drag).

## 74. Farcaster grows likes, mentions, channels, replies, faces (user, 2026-07-14)

User picked five features from the "what else can the keyless node
serve" shortlist (1, 2, 3, 6, 7 — the follow-graph import and the
verified-wallet tie-in stayed on the shelf; write-backs REFUSED: casting
needs an on-chain signer per user, breaking "a username alone connects
it," so the bridge stays honestly read-only). All five ride the same
public Snapchain node (`snap.farcaster.xyz:3381`) — no key, no account:

- **Likes land as saves** (`reactionsByFid?reaction_type=Like`): a
  per-account "Likes" chip on the watched-accounts list — like it on
  Farcaster, it lands here. The thing wears the LIKED CAST's author
  (face + handle) and the LIKE's timestamp (when it entered your
  attention, not when it was cast). No "which account is you" concept:
  likes/mentions are per-account switches that work for anyone watched
  (watching a curator's likes is legitimate too).
- **Mentions ride the away answer** (`castsByMention`): a per-account
  "Mentions" chip — casts by others naming the account land as things,
  replies included (a mention usually is one), so "while I was away"
  can answer with who talked to you (the pulse pools everything in the
  frozen window; no special-casing needed).
- **Channels are followable** (`castsByParent?url=`): a Channels
  section on the Farcaster screen — "/design" by name, with the same
  field anatomy as the username field ("/" prefix). The name resolves
  once against the channel directory (api.farcaster.xyz/v1/channel,
  warpcast.com twin as fallback) and the parent URL is cached like an
  fid. A channels-only connection still counts as connected (syncs,
  disconnects).
- **The thing sheet shows the thread** (`castsByParent?fid=&hash=`):
  a quiet "Replies" card (spec-table clothes) under the actions, up to
  8 replies — face, @handle, words — fetched live on open, rendered
  only when replies exist (no dead section, no spinner theater).
- **Account rows wear the profile** (`userDataByFid`, the same call
  the avatar already cost): face, display name, "@username · bio",
  refreshed each sync and persisted on the Account.

Shared plumbing that came with it: a per-launch fid→profile cache (one
userDataByFid per unique author, ever); mention SPLICING (casts store
@names out-of-band as fids + UTF-8 byte offsets — the raw text reads
"hey  look"; every landed cast now splices the @names back in,
end-first so offsets hold); one `land(cast:)` tail shared by the
likes/mentions/channel flows (dedupe by "fc:<hash>" whichever flow
arrives first); and rowLabel extended — your ONE watched mirror stays
unlabeled, everything else (several accounts, a liked cast's author, a
channel's caster) names itself. Probes: `-fcLikes`, `-fcMentions`,
`-fcChannel`, `-fcReplies "user:0xhash"` (one per launch — the refresh
guard serializes). Verified live against dwr/@six//design: 10 casts,
24 likes, 25+ mentions, /design casts landed with the right authors,
8 replies (the cap) on @six's mosaics cast, zero duplicate refs.
Node quirk paid for: castsByParent serves DOUBLE the asked pageSize
(25 → 50, verified live) — the channel sync and the sheet's replies
both cap client-side.

## 75. Bluesky mirrors Farcaster's keyless parity set; the two share one renderer (user, 2026-07-14)

User, after the Farcaster batch (§74): "can we do all the same with
Bluesky and make both experiences similar?" Assessed the AT Protocol's
public AppView keyless — then built the three that port cleanly and
generalized the shared surfaces so the two social bridges render from
ONE path, not a per-bridge fork (the altitude finding the §74 review
had flagged).

Built for Bluesky (all keyless):
- **Profiles** (getProfile) — the account row wears the face, display
  name, and "@handle · bio", refreshed each sync, persisted on the
  Account. A failed fetch NEVER clobbers stored facts (the §74 rule).
- **Replies** (getPostThread depth 1) — the thing sheet's Replies card,
  cached per launch. Each reply's author is hydrated by the AppView, so
  no per-reply lookups (cheaper than Farcaster's per-fid path).
- **Mentions** (searchPosts `mentions:handle`) — a per-account Mentions
  chip; posts naming the account land, replies and quotes included,
  riding "while I was away". Search results hydrate the mentioner, so
  again no extra lookups.

REFUSED / HELD, honestly:
- **Likes** — getActorLikes is AUTH-ONLY (returns "Profile not found"
  unauthenticated). Bluesky likes need an app-password sign-in, a
  different tier than "a handle alone" — and the catalog copy already
  promised "Likes arrive with sign-in, later." So the Bluesky row shows
  a Mentions chip only; no Likes chip. Parity is keyless-parity-minus-likes.
- **Channels** — Bluesky has no global channel names; its analog is
  custom feeds and lists, each an at:// URI under a creator DID,
  discovered by search (getPopularFeedGenerators). That's a different
  entry gesture than Farcaster's "type /design", so channels were held
  for Bluesky pending a decision on the discovery-search UX.

Generalization (the "make both similar" half) — `Model/SocialBridge.swift`:
- `SocialReply` + `SocialThread.replies(for: thing)` dispatch the sheet's
  thread by `thing.source`; `ThingSheetView` holds `[SocialReply]` and
  calls the neutral dispatcher — no bridge name in the sheet anymore.
- `SocialAccount` + `SocialWatch` are the shape the shared setup row
  renders; `HandleBridge` answers `isRichSocial`, `socialAccounts`,
  `setWatch(_:_:for:)`, and `watchFooter`, each store building its own
  `socialAccounts` (Farcaster: Likes+Mentions; Bluesky: Mentions).
  `HandleSetupScreen.socialAccountRow` + `watchChip` replaced the
  `farcasterAccountRow` fork — one renderer, both bridges, read straight
  off each @Observable store.
- Bluesky's rowLabel joined Farcaster's rule: your one watched mirror
  stays unlabeled, everything else (a mentioner not in your list) names
  itself, so attribution never gets lost.

Host quirk paid for: the AppView's searchPosts 403s on
public.api.bsky.app but is served keyless on api.bsky.app (the official
client's host); the mentions call, and only it, uses that host.

Verified live against jay.bsky.team: 16 posts, 25 mentions (attributed
to the mentioners), 8 replies rendering in the sheet, the rich row
showing "Jay 🦋 · Founder & Chief Innovation Officer…" with the Mentions
chip lit; zero duplicate refs. The sheet's replies section and the
setup row are the exact same views Farcaster uses.

## Coming up — deadline surfacing on Home (user, 2026-07-14)

The Home board leads (right under the cover) with a **"Coming up"** card: the
person's own dated things resurfaced because a deadline is near — the pattern
CardPointers uses to surface an expiring statement credit. Two corpus sources,
soonest first, an overdue reminder leading:

- **Upcoming events** (Calendar/Cal.com/Calendly) — their start rides
  `capturedAt`. Cal.com/Calendly already carried future starts; the EventKit
  calendar ingest, which used to stop at the end of today, now reaches a week
  ahead (`ScheduleIngest.forwardWindow`, re-run each foreground so the window
  rolls). A timed event that already passed today drops off; an all-day event
  today stays (its midnight start is inferred as all-day).
- **Due reminders** — a reminder's `capturedAt` is its CREATION time, so its
  deadline rides a new structured field `Thing.dueAt` (CloudKit-safe optional,
  set from `dueDateComponents` at ingest). A reminder past due leads as
  "Overdue"; the rest read "Today" / "Tomorrow" / the weekday.

**Two stances this re-opens, deliberately:**
1. **§18 "the calendar owns the future."** Narrowed, not dropped: the record is
   still the past, but the next seven days now surface on Home so an imminent
   thing isn't invisible until it's history. The horizon is a week — not "next
   month's agenda."
2. **Home voice, "themes and content, no obligations."** A deadline IS an
   obligation, so this card is a conscious exception to that rule — the whole
   point is the nudge. Scoped to this one card; the rest of the board keeps the
   no-obligations voice. Shown only when something is actually due (no empty
   card, no dead control — honesty rule holds).

Not a pinned board module: no size pin, no "Remove from Home" (there's no pin
behind it) — automatic synthesis like the map. `HomeComposition.appendComingUp`
emits a plain `Widget` of `Row`s (each row's time slot carries the WHEN as
words); `Model/ComingUp.swift` is the query. Headless check: `-comingUpProbe YES`
logs the lane over the current corpus.

Record surfaces stay the past (honesty): because upcoming events now carry a
future `capturedAt`, the Home cover's "Just landed" picks the newest thing with
`capturedAt <= now` — never a future event announced as if it arrived. Overdue
reminders are bounded to the last week (symmetric with the forward window) so a
pile of stale open reminders can't bury today.

**Recurring events (handled — needs device verification).** EventKit gives every
occurrence of a recurring event the SAME `eventIdentifier`, so a daily meeting
arrives as N EKEvents sharing one id. `ScheduleIngest.connectCalendar` collapses
each series to ONE thing (keyed on that id) whose date is the series' NEXT
upcoming occurrence — or its most recent past one when the whole series is
behind, so it stays in the record — and refreshes that thing forward each
foreground as occurrences pass (`betterOccurrence` picks the representative). One
row per meeting, always pointing at the one that matters; a one-off is a series
of one. This avoids both the old bug (only the first, usually-past occurrence
landed, so recurring meetings never reached "Coming up") and the flood a
per-occurrence ref would cause (14 rows for a daily meeting across ±7 days). The
sim's EventKit store can't be granted full access headlessly (iOS 26), so the
collapse/refresh path is **verified by reasoning + compile only** — confirm on a
real device with a recurring meeting.

## 76. GeckoTerminal — trending tokens per chain, an OpenSea-shaped discovery bridge (user, 2026-07-14)

User: "how could we offer something that surfaces trending tokens as a
feed and select per chain?" — then "yes lets do that and add gecko
terminal to app catalogue, website hero icon rain, and website app
catalogue." Ruling on the landing shape after weighing both: **land as
things, cloning the OpenSea bridge** (not an ephemeral discovery tile).

- **Same consent model as OpenSea.** You pick the CHAINS; a curated feed
  lands. OpenSea already lands un-chosen filtered items (newest
  collections) off a chain watch — trending tokens are the same
  contract, so no new honesty question. The earlier worry (corpus
  pollution) was overweighted: GeckoTerminal's `trending_pools` is a
  bounded ~20/chain ranked list, not a firehose, and a $5k reserve floor
  drops the wash-volume dust.
- **Name the ranker.** "Trending" is someone's algorithm, so the screen,
  the catalog copy, and the feed all say WHOSE — GeckoTerminal's own, by
  24h volume and price move. No neutral-truth laundering (honesty rule).
- **Keyless — simpler than OpenSea.** GeckoTerminal's trending endpoint
  needs no account and no key, so there's nothing to mint or store
  (`TrendingStore` is just the watched chains in UserDefaults). This is
  the one place the clone is lighter than its model.
- **The chart comes for free.** Each landed thing's `content` is the base
  token's Dexscreener URL — which `TokenChart.route` already parses — so
  a trending row's sheet draws the same live on-device chart a watched
  token's does, with zero sheet changes. Watching a token stays the
  Tokens bridge's explicit tap: trending is DISCOVERY, the watchlist is
  keeping.
- **Dedupe by token, not pool.** A token trends in several pools at once
  (WBTC landed three times on the pool key in verification); the person
  reading the feed wants "WBTC is trending" once. `sourceRef` is
  `gecko:<network>:<tokenAddress>`.
- **Nine chains, three defaults.** Ethereum/Base/Solana lead (the
  trending-token cultures); BNB/Arbitrum/Polygon/Optimism/Avalanche/Blast
  are a tap. Each chain carries two slugs — GeckoTerminal's network id
  for the API, Dexscreener's for the chart URL — because the two APIs
  spell chains differently.

Model `Model/GeckoTrending.swift`, screen `Screens/GeckoTerminalScreen.swift`
(clones `OpenSeaScreen`), catalog Markets group, headless probe
`-geckoTrending <chains|YES>`. Verified live: 9 distinct Ethereum
trending tokens landed (Synapse, Manyu, WBTC, PYUSD, Pepe, …), zero
duplicates, each carrying a Dexscreener URL the sheet reads for its
chart. Website: hero rain tile + Markets mini-cell + `.ai-geckoterminal`
green, per the same-session parity rule.

## 77. Across your wallets — a combined view, additive to the per-wallet ones (user, 2026-07-15)

Watching more than one wallet earns ONE combined read — the value across
them, and one treemap summing the same holdings the per-wallet charts show
separately. Prompted by looking at Zapper (its "bundle") and rotki (net
worth over time, local-first); the frame stays Casberi's, not either app's.

- **Additive, never replacing (revises the 2026-07-09 separate-holdings
  ruling).** That ruling held holdings apart because summing them "hid
  which wallet actually held what." Still true — so the per-wallet
  treemaps stay exactly as they were, and the combined view leads ABOVE
  them, not instead. Nothing is lost; there's simply one more read for
  "everything together." Shown only with more than one wallet watched —
  one wallet's own screen already is its combined view.
- **Softened framing, not a portfolio app (softens §71).** §71 kept
  Tokens/Wallet as "your history with the assets, not a market terminal."
  So the section is "Across your wallets", the number is "Combined
  value" — never "Net worth" or "Portfolio". "Net worth" would also
  OVERCLAIM: it's these watched wallets' onchain value, not the person's
  actual net worth (no CEX, no chains we don't read). The honest label
  says exactly what it sums.
- **The combined line starts only when every wallet has a sample.** The
  net-worth-over-time line reuses §71's forward-only per-wallet samples,
  merged. But a wallet added later would contribute zero to the early
  total and then jump when it first prices — a real +2,000,000% artifact
  in verification (Binance watched after Vitalik). The series now starts
  at the latest of the wallets' first-sample times, so every wallet
  contributes a real value from the first point; a composition change
  never masquerades as a gain (honesty rule). Empty until two aligned
  points exist.
- **Private by nature (the rotki angle, honestly).** Read on this iPhone,
  no account, watch-only — the footer says so. The differentiator vs
  cloud trackers (Zapper/Zerion) that harvest addresses server-side. The
  honest bound: addresses still reach Alchemy (the indexer), just never a
  Casberi server — the copy claims "no account, read on this iPhone",
  never "never leaves your phone".

Combined fetch reuses `WalletIngest.holdings(addresses:)` (already
aggregates any number of addresses) via `combinedHoldings()`; the merged
line is `WalletStore.combinedValueSamples()`. Section lives atop
`WalletScreen`. Verified live across two real wallets (Vitalik + Binance
14): one $393M "Combined value", one 22-token treemap, a sane +3.3%
combined line after the alignment fix. No new catalog offer, no website
catalog change — it's synthesis over connected wallets, not a bridge.

## 78. Two catalog re-shelvings: GeckoTerminal to Onchain, Pinterest to Media (user, 2026-07-15)

- **GeckoTerminal moves Markets to Onchain** (revises §76's Markets
  placement). Trending crypto tokens per chain are an ONCHAIN interest,
  next to Wallet/Tokens/OpenSea/Farcaster — not a prediction-market tail.
  Markets now holds Kalshi alone (real-event odds, genuinely not onchain),
  and still rides last.
- **Pinterest moves Reading (Saves) to Media.** Pins are visual media, not
  reading — it belongs with YouTube/Twitch/Spotify/Podcasts/Steam, not with
  Readwise/RSS/Substack. Reddit and Raindrop keep the "Saves" group (they
  stay in Reading), so Pinterest gets its own group, "Images", added to the
  Media category's set.

App: `Offer.group` is "Onchain" / "Images" now (BridgeCatalog), and the
Media category maps "Images" (AppsScreen.categories). `group` is Browse +
chart-filter display only, so nothing behaves differently. Website: the
hand-authored catalog shelves mirror the app — GeckoTerminal's mini-cell
sits under Onchain, Pinterest's under Media (index.html; hero marquee
tiles carry no category and stay put). Verified: app Onchain shelf leads
with GeckoTerminal; deploy zip's index.html shelves both correct.

## 79. Wallet — faces, glances, and moments (surprise & delight pass, user, 2026-07-15)

A delight + polish pass over the Wallet experience, prompted by "how would
you improve the wallet and add surprise and delight." Everything stays
inside §71's frame (your history with what you watch, not a market
terminal) and §77's honesty (watched wallets' onchain value, read on this
iPhone, watch-only). Ships:

- **Faces (`WalletFace`).** Watching three wallets was three identical blue
  glyphs. Now each wears its ENS **avatar** when the address published one
  (resolved via the same ensideas call counterparty naming uses, `avatar`
  field, http(s) only — an `eip155:` NFT avatar falls through), else a
  **deterministic identicon** seeded from the address (soft gradient +
  berry blobs, same seed→same face rule as BerryRain). Avatars cache in
  WalletStore (in-memory; the identicon is always a correct meanwhile);
  resolved on the Wallet screen and each foreground (BridgeRefresh). Shown
  on the Watching rows, the combined sheet, and the value lines.
- **Row sparklines.** Each watched row wears a bare value-line sparkline
  (the Tokens split: a glance on the row, the numbers in the Value section
  below). Only with ≥2 sampled points.
- **Combined sheet (`CombinedWalletsSheet`).** The "Across your wallets"
  headline now opens a full read — the combined net-worth line
  (state-colored) decomposed into each wallet's own line in its **face's
  color**, so a move up top reads back to the wallet that drove it. The
  Casberi frame (history, decomposed), not Zapper's single figure.
- **NFT-arrival delight.** A watched wallet receiving a new piece deals the
  berry rain + a toast naming it ("Main received Chromie Squiggle #4021
  🖼️"), sibling to the starred-repo major-release rain. NFTs/holdings
  aren't things (§72), so they can't ride MainSurface's corpus-arrival
  watcher — instead the data paths enqueue on **`WalletMoments`** and
  MainSurface drains it into the same rain+toast. Silent on the first-ever
  read (seeds the baseline; no "received 40 NFTs" on connect), backfill-
  guarded exactly like the release rain.
- **New-high delight.** The combined value hitting a new high fires the
  same rain+toast (multi-wallet: scope "combined", over the FULL set so
  Home's pinned pass and the Wallet screen can't disagree on the mark;
  single wallet: its own per-address mark, in recordSample). Honest and
  asymmetric: a new high over the forward-only samples earns a moment, a
  drawdown earns only the truthful red pill — never a back-fill, never a
  sad-theater toast. First value seeds the mark silently. (This is the one
  item that brushes §71's "not a terminal"; it survives because it marks
  YOUR forward-only record, not market data — approved this pass.)
- **Self-transfer recognition.** A move between two of your own watched
  wallets titles as "Moved 0.5 ETH · Main → Cold" (housekeeping, not news)
  instead of a one-sided "Sent … to Cold". Only with >1 wallet watched and
  the counterparty itself watched — the app understanding your setup.
- **Try-it chip.** The empty state offers "Peek at vitalik.eth" — one tap
  watches a famous public wallet so the whole feature demos in three
  seconds (watch-only makes peeking legitimate). Retires once anything is
  watched.
- **Background densifying (`WalletBackgroundRefresh`).** A BGAppRefreshTask
  samples holdings while away, so the value line fills between opens —
  still forward-only, still real reads, just more of them (footer softens
  to "sampled as you use Casberi, and quietly in the background"). iOS
  decides if/when it runs (never on the Simulator); registered at launch,
  scheduled on background. Info.plist gains `fetch` +
  `BGTaskSchedulerPermittedIdentifiers`.

Treemap touch feel (the 10th proposal) was already shipped — cells carry
`DSHaptic.selection()` + the tile press-settle (GenRenderer). No new catalog
offer, no website change — synthesis over connected wallets, not a bridge.
Verified live across two real wallets (vitalik.eth + Binance 14): vitalik's
ENS avatar and Binance's identicon both render, the row sparkline draws, the
combined sheet decomposes correctly with §77's alignment (combined "since Jul
14", Binance's own line its true earlier start).

## 80. Stocktwits — stocks the keyless way: ticker streams + a Yahoo-drawn chart (user, 2026-07-15)

The user asked for stock tracking ("does Stocktwits or anything like that
have a public feed?"); research confirmed two keyless halves and the ruling
is to ship them as ONE seat, not two:

- **Stocktwits is the bridge** (Markets group, beside Kalshi). Watch a
  TICKER: the watch is a thing (`stocktwits:sym:<T>`, the TokenWatch shape —
  deleting the row is unwatching), and the takes traders post about it land
  as chat things from Stocktwits' public symbol streams — the same keyless
  REST its own website reads (~200 req/hr/IP unauthenticated). Top 3 per
  ticker per pass, ranked by author followers (public messages carry no like
  counts; author reach is the one honest quality signal, and it keeps the
  0DTE spam out). Each post wears its author's OWN Bullish/Bearish call as a
  tag — Stocktwits' sentiment toggle, never a rating of ours.
- **Yahoo v8 is plumbing, not a seat.** The watchlist row's sheet draws the
  live chart natively via the SAME TokenChartView anatomy (now generic over
  a `PriceRange` protocol; tokens unchanged, keys preserved). Yahoo is
  unofficial: fetch fails → the plain Stocktwits link, never a broken or
  faked chart. Honest labels: chips read 1D/5D/1M — "5D" is five TRADING
  days, deliberately not rounded to "7D"; the scrub shows NO "ago" label for
  stocks (candles skip closed-market hours, index×step would lie).
- **Honest boundaries:** watches tickers, never portfolios (holdings aren't
  public anywhere; copy never says "track your portfolio"). Read-only —
  nothing trades. Posts land "on each visit", not "as they're posted" (no
  push; the copy says what the refresh does).
- **Disconnect teardown deletes the WATCHLIST rows** (the watch is access —
  ruling 2026-07-13's two verbs; a kept watch row would re-register the seat
  and keep the foreground poll landing). Landed posts are history and follow
  the person's own "remove its things too" choice.

## 81. Social enrichment — the post itself, why it's here, and the people behind it (user, 2026-07-16)

User: "how could we enrich the farcaster and bluesky experiences… don't think
just features, think design too." The assessment found the plumbing already
excellent (§74/§75) and the PRESENTATION generic: a cast rendered with the same
anatomy as an RSS link, and the most social facts about a post were dropped at
ingest or shown as a URL. Nine changes, all keyless and read-only, both networks
in one pass through the shared `SocialBridge` layer.

**The post is the point (the bug that started it).** A post's text became the
80-char `title`; `Thing.content` held the PERMALINK. So the sheet rendered
`content` through the chat path — a URL in a speech bubble — and the words of
anything longer were absent from the app entirely. Measured live: 53 of 73
Bluesky posts and 58 of 84 casts were longer than their title, i.e. most posts
were losing their words. Now `Thing.postText` carries the full text, and the
SHEET LEADS WITH IT: the post's own words in the title slot, sized by length
(≤100 chars keeps `heading34` and its drama; longer steps to `heading22`, a size
you can read a paragraph in — the type ramp, no other trick). `content` still
holds the permalink, so every open/share/route path is untouched.

**Why it's here (the marker).** A liked cast, a channel cast, a mention, and
your own post all rendered identically. `Thing.socialContext` ("liked" /
"mention") + `Thing.channelName` now stamp WHY at ingest, and the row's trailing
slot says it: "Liked", "/design", "Mentions you". **The marker beats the handle
in that slot** — the row already leads with the author's FACE, so the word that
differentiates is why it arrived, not who a second time. A post with no such
reason falls through to the handle rule (§74), unchanged. The sheet's eyebrow
carries both as a sentence: "@dwr · in /design · 2h ago".

**Engagement, honestly.** Bluesky's AppView serves exact totals and hydrates
them on every post view (free at ingest — they render in the first frame);
Snapchain serves reaction MESSAGES, so a Farcaster count is one page's size and
a full page reads "100+" (`SocialCount.atLeast`). Both are re-read LIVE when the
sheet opens — a count is only true at the moment it's read. A count the network
didn't report has NO cell: an absent number and a reported zero are different
facts.

**Quotes, parents, and all the pictures.** `Thing.quote` / `Thing.parent`
(`SocialCard`: face, handle, words, permalink, protocol ref) and
`Thing.imageURLs`. A quote renders as a recessed card in the body; a parent as
"Replying to @alice" above the words. Bluesky hydrates both a quote and every
image for free; Farcaster's node serves raw protocol data, so a quote/parent is
a bare `{fid, hash}` — one capped fan-out per page (`prefetchCards`) warms them,
and the ref dedupe keeps the steady state at zero.

**Threads stay in-app.** A reply tap used to open the browser, which ended the
session in Casberi. Now it opens the post here — its face, its words, its own
replies — and those push again, so a conversation walks as deep as it goes.
This needs the PROTOCOL ref, not the permalink: Farcaster's web URL carries only
the first 10 chars of the hash, so `SocialCard.ref`/`SocialReply.ref` carry
`sourceRef` form ("fc:<hash>", "bsky:<at-uri>"). A walked post is NOT a thing —
not in the corpus, no row, nothing saved. It's a read.

**People are doors.** Tapping any face — a row's author, a reply's, a quoted
post's — opens `SocialProfileCard`: face, name, bio, and ONE verb, Watch (plus
Farcaster's "Watch their wallet"). That's what turns a mention from a dead end
into a door: someone talks to you, you tap them, you watch them.
**Cross-network is a SEARCH, never a join** — nothing links a Farcaster username
to a Bluesky handle (Farcaster's onchain verifications have no Bluesky analog),
so "Look for them on Bluesky" runs the same people-search the setup field runs
and hands over the hits. Which one is really them is the person's call. Claiming
the match would be a guess wearing a fact's clothes.

**Bluesky feeds — the held question, answered.** §75 held Bluesky channels
"pending a decision on the discovery-search UX". The answer: its topical lanes
are custom FEEDS (at-uri, no global names), so **the search IS the entry
gesture** — type "science", pick from what's there, exactly the finder the name
field above it already uses for people. Once followed, a feed behaves like a
channel: its posts land beside the people's, marked with the feed's name. Verified
live: 25 Science posts landed keyless.

**Bluesky mentions already rode "while I was away"** — the librarian's window is
a pure time filter over the corpus (`AskCommands`), never source-specific, so
any landed thing rides it. Nothing to build; confirmed, not assumed.

Rulings that fell out of the build:
- **Heal, don't strand.** A post already in the corpus dedupes OUT of the
  landing path, so the enrichment would only ever reach posts landed from that
  day on — an existing corpus would show none of it. Both ingests now heal on
  the dedupe hit (fill a gap, never rewrite what a good sync landed), and a
  heal-only pass joins the save condition. Verified: 10 of 10 casts healed their
  full text on the first pass.
- **A card presented from anywhere can't demand the environment.** The first
  deep link to the profile card CRASHED (`_assertionFailure` in
  `EnvironmentValues.subscript.getter`): sheets hang off view chains OUTSIDE
  RootShell's `.environment(chrome)`, and a non-optional `@Environment(ShellChrome.self)`
  traps when the object is absent. It reads chrome OPTIONALLY now. Losing the
  toast costs nothing the person needs — the Watch row states its own outcome.
- Counts are stored AND read live: the snapshot renders in the first frame, the
  live read replaces it. A stored field nothing reads is dead data (caught in
  review — the counts were being written and healed every refresh and displayed
  never).

Debug: `-bskyFeed <query|at-uri>`, `-socialProbe <Bluesky|Farcaster>`, and the
`casberi://person/<Source>/<handle>` deep link (the card by name, so the screen
sweep reaches it headlessly like every other surface).

## 82. Bankr joins the agent keys — the one agent with a wallet (user, 2026-07-16) — BUILT

Bankr (bankr.bot) is a wallet-attached trading agent with a prompt API the
same BYOK shape as the other four: a key in a header, a question in, text
out. It becomes the FIFTH agent provider (§69's picker: Claude, ChatGPT,
Gemini, Venice, Bankr), same vault seat pattern, same consent tap, same
honest-failure wording. A user pastes their own key from bankr.bot/api-keys;
their Bankr Club sub or credits pay for their own prompts — server-free ring
intact (§67).

Two sanctioned divergences from the one contract, both because Bankr is an
agent, not a bare model:

- **Async job flow.** `POST api.bankr.bot/agent/prompt` returns a jobId;
  the answer is polled off `GET /agent/job/<id>` every 2s (~90s cap).
- **Wallet grounding.** Bankr may draw on the connected wallet and live
  markets IN ADDITION to the retrieved things — so an empty corpus match
  still asks it ("what's my portfolio worth" needs no saved thing), where
  every other provider gets the honest "nothing matches" line instead.

One non-negotiable rides every prompt: ANSWER ONLY. The same key could
trade, so the answer path hard-prefixes "do not execute, prepare, or queue
any transaction… even if the question reads like a command", and the
settings small print tells the person to mint the key READ-ONLY (Bankr
keys support that; a read-only key 403s on writes — defense in depth).
Actions through Bankr (an "Ask Bankr" sheet verb, or ever placing a trade)
would be separate consented verbs, deliberately unbuilt.

Key validation spends nothing: auth is checked before the job lookup, so a
bogus job id returns 404 on a good key and 401 on a bad one.

Debug: `-byokKey "bankr:<key>"` + `-byokProbe "<query>"` (a bogus key
verifies the honest 401 → nil path free, and the empty-corpus divergence —
the probe reaches Bankr instead of stopping at "nothing matches").

Bankr also takes a catalog SEAT, Venice's precedent exactly (§70 ①): an
Agents-shelf offer with its own setup screen (`Screens/BankrSetupScreen.swift`,
route + seat id `bankr`), sharing the one vault key — connect it there or in
Settings → Your key, either lands the same key. All four catalog surfaces
moved in the same session per the sync rule: the offer, the website Agents
shelf, the website hero rain, and the onboarding pile. The onboarding pile
was FULL (25 cubes = a 5×5 grid; index 25 starts the Apple row), so Bankr
SWAPPED Calendly's cube rather than appending — Cal.com already carries
scheduling there, and the pile is a curated subset, never the catalog.

## 83. Three honesty repairs the nightly audit found (audit, 2026-07-16) — BUILT

The 2026-07-16 screen audit found no regressions but three live honesty
violations, all shipped, all the same shape: a surface stating something the
data underneath doesn't support. Fixed together.

① **A disabled button has to LOOK disabled.** `VeniceSetupScreen` and
`BankrSetupScreen` each hand-rolled their Connect button: `.buttonStyle(.plain)`
over a custom `.background(DS.tint)`, then `.disabled(...)` when the key field
is empty. SwiftUI dims a plain-style button's *label*, not a background you
painted yourself — so both rendered full-strength blue and tappable-looking
while inert. That is the "no dead controls" rule broken by a styling detail,
not by intent. Both now wear the off state (`DS.gray200` + `DS.textTertiary`)
the way the shared `BridgeFieldRow` always has. RULING: a hand-rolled button
that sets its own background MUST also swap that background on the disabled
path — `.disabled` alone is not a visual state. Prefer `BridgeFieldRow`.

② **A market with no book has no odds.** Kalshi's setup list read
`last_price_dollars` as the probability. Kalshi leaves a market listed long
after its order book empties (yes_bid 0 / yes_ask 1 = no orders either side),
leaving a stale residual trade behind — often $0.0010. Printed, that read
"0%", so six of the eight "busiest open markets, live" claimed the USA,
France, Portugal and Morocco each had a 0% chance of winning a World Cup they
haven't played. Lifetime-volume sorting floated exactly those dead books to
the top.

The fix reads the market the way the market states itself: the book BRACKETS
the answer — yes trades somewhere in [bid, ask] — so `KalshiWatch.bookMid` is
the midpoint of that bracket, and `last_price` is not consulted at all. A
stale trade is not a price. One-sided books stay listed and are quoted from
their bracket (a 99¢ bid with no ask is a near-certainty; a 1¢ ask with no
bid is a long shot) — an earlier draft demanding a two-sided book blanked
exactly those, i.e. the game a team has all but won. Bid 0 / ask 1 is the one
bracket that says nothing (the whole range = no orders either side): that
market quotes nothing, so the row doesn't list and a watched one takes the
card's honest unavailable fallback. Deliberately NOT a coin-flip default —
an empty book's mid is 50%, which would invent a market where there is none.
`previousProbability` reads the PREVIOUS book the same way
(`previous_yes_bid/ask`), so the "vs last" delta subtracts like for like
instead of mid-minus-last-trade, which manufactured half a spread of movement.

RULING: never derive a displayed price from a stale last trade. Quote the
live book, or say nothing — and quote it the same way on both sides of any
delta.

③ **Zero has no direction.** The delta label formatted with `%+.1f%%` and took
its ink from `change >= 0`, so a −0.04% move printed red "−0.0%" — a loss the
number itself denies — and +0.04% printed green "+0.0%". Flat is now its own
state (`TokenChartStyle.isFlat`, `accent(change:)`): no sign, quiet
`DS.textTertiary`, at exactly the boundary where the printed number would
round to 0.0. Green-up/red-down still carries real moves; it just stops
claiming one that rounding erased. RULING: the sign and the state color are
only honest once the change survives the rounding you print at.

Also gated: `RSSScreen`'s toolbar `EditButton` — every other section there is
gated on `!feeds.isEmpty`, but Edit wasn't, so a user with zero feeds got a
live Edit over an empty list.

## 84. Approvals — the wallet's security surface, with Revoke.cash as the write (user, 2026-07-16) — BUILT

**Ruling.** Token approvals join the wallet bridge as a READ: a new `Approval`
/ `ApprovalForAll` event on a watched wallet lands as a thing ("Approved
0x4531…cd4e to spend unlimited USDT"), and the Wallet screen carries an
Approvals section — one row per EVM wallet, opening that wallet's Revoke.cash
dashboard. The WRITE stays off the table entirely: revoking is an on-chain
transaction, Casberi never executes transactions (§82's line), so the thing's
content and the row both point at the tool built for it. Revoke.cash Premium
was evaluated first and offers nothing to integrate — it's a consumer
subscription (batch/auto-revoking), no API; the free per-address page
(`revoke.cash/address/<0x…>?chainId=…`, verified live) is the whole
integration surface.

**Shape.** `Model/WalletApprovals.swift`, riding inside `WalletIngest.refresh`
(same running guard, every sync path). Incremental by design: first sight of a
(wallet, chain) seeds a block cursor silently — the NFT-arrival baseline idiom,
no history dump on connect — and each pass reads only the gap via
`eth_getLogs` filtered on the OWNER topic. ERC-721 single-token grants (the
4-topic `Approval` variant) are skipped as noise; revokes land too ("Revoked
1inch's USDT approval") — good news is still news. Newest 10 per (wallet,
chain) per pass; real block timestamps (capped) so an approval found after a
week away lands dated when it happened.

**Two lessons paid for (2026-07-16, measured before shipping):**
- **Alchemy's free tier caps `eth_getLogs` at a TEN-block range** — the whole
  read runs on per-chain public keyless RPCs instead (mevblocker/onfinality for
  Ethereum, the chains' own official RPCs for Base/Arbitrum/Optimism,
  onfinality for Polygon), each with its measured max range, chunked at up to
  16 chunks per pass. Only `alchemy_getTokenMetadata` (symbol/decimals for
  titles) stays on the Alchemy key. Don't swap hosts without re-measuring;
  drpc.org and most aggregator "free" RPCs are quota-flaky.
- **Spam tokens EMIT FAKE Approval events naming any famous address as owner**
  — vitalik.eth "approved" 3,832 times across ~3,800 junk contracts in one
  measured window, none signed by him. So approvals wear the transfer feed's
  held-filter: an ERC-20 approval lands only for a token the wallet holds
  above the dust floor, an operator grant only for a collection among its
  non-spam NFT holdings — and the pass fails CLOSED (cursor untouched, retry
  next pass) when the held set couldn't be read. A fabricated "you approved X"
  is worse than a delayed one.

**Out of scope, deliberately:** a native open-approvals readout (full-history
backfill is the expensive read — that's Revoke.cash's own moat and what their
page already shows one tap away); Solana and Robinhood Chain (no EVM
approvals / not on Revoke.cash — a door to a 404 would be a dead control).

**Probe:** `-approvalProbe <blocksBack|YES>` — rewinds every cursor N blocks,
runs the sync, NSLogs the landed count. Verified live: a wallet that had just
approved unlimited USDT (holding $290K of it) landed exactly 1 thing from a
5,000-block window while the spam flood landed 0.

## 85. Solana joins the wallet — holdings and `.sol` names, activity honestly held (user, 2026-07-16) — BUILT

> **Superseded in part, same day, by §86:** the activity half shipped once its
> cost was measured instead of assumed. Everything below about HOLDINGS still
> stands; the "activity isn't read" copy it describes is gone. Read the two
> together — §85 is why a partial chain must say so, §86 is why it wasn't
> partial for long.

Reverses §"Solana held" (2026-07-15), but only halfway, and the half matters.
The question that started it was "can we resolve `.sol` names?" — and the
honest answer was: resolving one is trivial, but a resolved name with nowhere
to land is worse than an unresolved one. `toly.sol` already failed *honestly*
("Couldn't resolve — check the name or paste a 0x address"); shipping the
resolver alone would have replaced that with a watched wallet, permanently
empty, indistinguishable from a wallet that holds nothing. So the resolver
ships WITH somewhere to land, or not at all.

**What reads: holdings.** Alchemy's Portfolio `by-address` takes
`solana-mainnet` on the same key the EVM chains use — no new provider, no
dashboard change, no account. A `.sol` wallet gets a real treemap, value
samples, and a face.

**What doesn't: activity.** `alchemy_getAssetTransfers` is an EVM method with
no Solana equivalent — Solana's activity needs getSignaturesForAddress plus
per-signature pre/post balance diffing, a genuinely separate ingest, and the
swap-folding router table has no Solana analog. That path is NOT built, and
the surfaces say so rather than implying otherwise — all four of them: the add
field's footer ("Solana reads holdings only, for now"); the catalog summary,
which promised activity "across chains" and now names the five EVM chains it
means; and, for a Solana-only watch list, both the sync line ("Connected —
reading holdings. Solana activity isn't read yet.") instead of the generic
"watching for activity", and the bridge's own `can:` list, which otherwise told
the Apps page it "reads your wallet's activity" for a person whose activity has
no path. Adding a chain to the picker is what made the last three false — the
lesson is that a partial chain's blast radius is every surface that ever
generalised over "chains". `WalletIngest.transferChains` is what enforces the
split; `ChainKind` is what makes it a property of the chain, not a special case
sprinkled at call sites.

RULING: a chain may join the wallet **partially**, but every surface it touches
must state which half it got. A capability gap is shippable; a capability gap
the UI papers over is not.

**Four things measured, all counter-intuitive, all load-bearing:**

- **`withPrices` doesn't price SPL.** It prices EVM tokens inline, but on
  Solana returns a price for native SOL and *nothing else* — two wallets, 100
  tokens each, exactly one priced. Alchemy knows the prices; that endpoint just
  won't join them. So `WalletIngest.priceSPL` sends the mints back out through
  the Prices endpoint (25/request, its cap). Without it a Solana treemap shows
  SOL alone and reads "holds only SOL" — false.
- **Native decimals can't be read off the response.** The native coin comes back
  with null metadata, and the old code defaulted to 18. SOL is 9. At 18, SOL
  computes to $0.00005, drops under `holdingFloor`, and *vanishes silently* —
  the treemap would have been empty with no error anywhere. Decimals now live on
  `Chain`.
- **Base58 is case-sensitive.** Contracts were lowercased at the source, which
  is free for EVM hex and destroys a Solana mint. `HeldToken.contract` keeps its
  original case now; `heldPricedContracts` lowercases at the point of EVM
  comparison instead (it only ever meets EVM legs).
- **A Solana-only watch list ran zero transfer jobs**, so `reachedAny` was
  vacuously false and `refresh` returned nil — the screen painted "Couldn't
  reach the chain" over a working treemap, and the bridge never registered as
  connected. Reachability for that person is the holdings read, not the transfer
  sync.

**Free rides:** `chainSlug["solana-mainnet"] = "solana"` — both chart tiers
(GeckoTerminal, Dexscreener) spell it that way, so an SPL cell's tap opens a
real chart like any ERC-20's. And Basenames already resolved: `jesse.base.eth`
comes back correct from the existing ENS resolver, since Basenames are ENS
subnames — no work needed, checked before assuming.

**Held deliberately:** Solana NFTs (Alchemy's NFT API is EVM-only) and Solana
activity. Base MCP (`mcp.base.org`) was evaluated in the same session and
passed on: it is an MCP *server* for agent harnesses, Casberi has no MCP client,
and what it offers is mostly writes — which §82's answer-only ruling already
settled.

## 86. Solana activity — the half that was held, once the cost was measured (user, 2026-07-16) — BUILT

§85 shipped Solana holdings and held its activity, and the reasons given were
wrong. The user asked the right question — *"why shouldn't we? because we don't
care? because we love ethereum and EVM?"* — and the honest answer was neither:
the cost had been ASSERTED, not measured. Measuring it took twenty minutes and
reversed every argument.

- *"N+1 requests — 11 calls against EVM's 2."* Wrong. Solana's JSON-RPC accepts
  an ARRAY of calls: ten `getTransaction`s return in ONE ~0.4s request. A Solana
  wallet costs **2 requests**; the EVM path costs **10** (five chains × two
  directions). It is the CHEAPER arm.
- *"No analog to the swap-folding router table."* Wrong. Program ids ARE the
  analog (`pAMMBay…` = PumpSwap), and the logs name the instruction outright
  (`Instruction: BuyExactQuoteIn`). Same table, same shape.
- *"Instruction-level parsing is hard."* Overstated. `jsonParsed` plus a
  pre/post balance diff derived the right answer on 3 of 3, then 10 of 10.

RULING: a capability may be deferred for cost, but the cost must be MEASURED
before it counts as a reason. "It's expensive" asserted from architecture
intuition is not a product decision — it's a guess wearing one. What actually
survived contact was a design problem, not a cost: not *can* we read Solana
activity, but *what counts as news*.

**What the measurements taught, all four load-bearing:**

1. **`getSignaturesForAddress` returns MENTIONS, not transfers.** The real
   asymmetry with EVM, where `getAssetTransfers` only ever returns movement.
   SIX of toly.sol's ten most recent signatures moved nothing for the owner at
   all — his address is merely named in other people's PumpSwap buys. Dropped
   for having no legs.
2. **The native delta is contaminated by fee and rent.** A wallet that sent
   299.9 USDC shows −0.002064 SOL, which is not a send. Add the fee back (when
   the wallet paid it) and the residue lands on EXACTLY 0.000000000 for a
   fee-only tx and EXACTLY 0.00203928 — the rent-exempt account minimum — for
   one that opened an account. Hence `nativeNoiseFloor`, a mechanical filter,
   distinct from the value judgment below.
3. **Signing is Solana's from/to.** Solana has no from/to for EVM's spam rule to
   key on, but signers carry the same meaning: a tx you SIGNED you did (EVM's
   "sent" — always news); one you didn't happened TO you (EVM's "received" —
   filtered). Every one of toly.sol's ten was unsigned by him; all eight of
   Binance's were signed. The mapping held on both.
4. **Solana's noise floor is a different animal.** pump.fun creator fees arrive
   constantly at ~$0.43. `dustFloorUSD` mirrors `holdingFloor` ($1.99) on
   purpose — the line that says a position isn't worth a treemap cell says a
   windfall isn't worth a thing — and applies ONLY to passive receipts, never to
   something you signed.

The filters compose into the honest result: toly.sol lands **0 of 10** (he did
nothing; it was all done around him), Binance lands **10 of 10** ("Sent 39.84
SOL", "Sent 35,289,738 PUMP", "Sent 124.03 $WIF"). A real swapper produced
"Swapped 5,200 Svaicf → 2.44 SOL on PumpSwap".

**Naming is a gate, not a decoration.** `jsonParsed` gives mints, and a mint is
a hash — which the design law forbids in a title. Alchemy doesn't serve Metaplex
DAS. Dexscreener, which the Tokens bridge uses, fails on exactly the mints that
matter: it never names USDC (a pair's QUOTE carries no symbol) and it named
wrapped SOL **"FOGO"**, because SVM forks reuse mint addresses and its pair list
spans chains. Jupiter's keyless search answered all four correctly, batched 8-in
8-out. A leg that still can't be named kills the whole title rather than
printing a mint — the move drops instead.

Two things this cost that are worth remembering: Jupiter's endpoint is a SEARCH,
not a lookup, so an unknown mint can come back matched to some other token by
name — keying the result off the mint the ANSWER carries (never the one asked
for) is what makes a stray harmless. And the odd-looking symbols are real:
`Ctgbpg` is CAPE GRID TOWN PENGUIN, `Svaicf` is SILICON CHIP VALLEY FORGE. Both
looked like base58 fragments and both survived checking.

## 87. Who they follow — the follow graph as a picker, not a mirror (user, 2026-07-16) — BUILT

The question was: both networks expose who you follow, so couldn't we let a
person automatically follow, in Casberi, everyone they already follow?

Yes to the read; no to the "automatically". Both graphs are public and keyless
— `app.bsky.graph.getFollows` on the AppView, `client.farcaster.xyz/v2/following`
on the client API — and both hand back HYDRATED profiles (face, name, handle),
so the list renders with no second lookup. Nothing here needs a sign-in.

**The ruling: it lands as a PICKER.** Three reasons, in order of weight.

1. **Scale.** A measured account follows **1,848** people; another **3,757**.
   Mirroring that isn't importing a few friends, it's subscribing to a
   timeline, and it pays a sync job per person on every refresh. Casberi is a
   personal corpus; a timeline is the thing it isn't.
2. **Precedent.** The app has already ruled this exact shape twice.
   `SocialPeople.findElsewhere` (§81) hands you hits and makes the watch YOUR
   tap rather than claiming a join it can't prove. Trending (§76) shows, and
   the tap watches. This is the same gesture at a bigger scale.
3. **It's not what people mean.** "Follow who I follow" is the wish; the want
   is the handful of people you'd have typed in one by one, without the typing.

**Nothing is preselected** (user, 2026-07-16). You opt people in. A "select
all" was deliberately NOT built — it's one tap back to the flood the picker
exists to prevent. Held as an open question, not a gap.

**The list is in network order, with a filter field** (user, 2026-07-16). No
rank we didn't compute. Bluesky serves most-recently-followed first, which is
already a real signal; Farcaster serves its own. Ranking by follower count was
costed and rejected: free on Farcaster (inline `followerCount`), ~1 extra
request per 25 people on Bluesky (`getProfiles` caps at 25), and it surfaces
the biggest accounts — the loudest feeds, covered everywhere else, which is
backwards for a corpus. The field FILTERS what's already there; it never
searches the network.

**Where it lives:** a "Who they follow" capsule on the watched-account row,
beside "Watch their wallet" (§79) — same anatomy, same place, both networks.
That siting is why the feature needs no new notion of who YOU are: your own
account is normally the one you watch first, so on your row this reads exactly
as "bring in who I follow", with no identity question and no sign-in. On anyone
else's row it's a way into their taste, which is the same verb.

### What the measuring cost, and what not to re-litigate

**Farcaster's client API is rate limited to 20 requests per 10 seconds** (its
own 429 body says so), and the walk MUST stay paced — `SocialFollows.pageDelay`
is load bearing. Unpaced, a 1,848-follow graph came back as exactly **999
people, presented as complete**: `IngestSupport.run` reports a non-200 as nil,
so the loop just stops. That's the honesty rule's nightmare — not an error, a
wrong list wearing a right one's clothes. `Graph.truncated` exists so the sheet
can say "this is the first N" whenever the walk didn't finish.

**The trap:** the ceiling is enforced **per connection**, so it does not
reproduce with curl or any client opening a fresh connection per request —
those walked all 37 pages clean and pronounced the endpoint healthy, three
times, while the app failed identically at page 21. URLSession reuses one
keep-alive connection; that's the whole difference. Reproduce against a single
keep-alive connection or you will conclude the delay is unnecessary. (Measured:
150ms fails, 400ms and 550ms both complete; 500ms shipped, ~14 req/10s.)

Bluesky needs no such pacing — 40 back-to-back pages drew nothing.

**Snapchain was the wrong host for this, and not for the reason expected.** The
keyless node answers the graph too (`linksByFid`), but only as target FIDs, and
there's no batch fid→username — a 1,848-follow graph would cost 1,848 lookups
against the client API's 37. An early worry that the node PRUNES the graph was
checked and is false: it agreed with the client API on dwr's count to within
the self-follow it includes (78 vs 77).

A big graph is a real wait (1,848 people ≈ 31s paced), so the sheet counts out
loud — "Reading the follow list… 450 so far" — rather than spinning mute.

## 88. The feeds swipe; the row swipe dies to pay for it (user, 2026-07-16) — BUILT

Swiping between feeds was asked for, measured, and shipped. The chip strip is
no longer the only way across the corpus: the feeds are one `TabView(.page)`
whose selection BINDS to `FeedFilter.shared.source` — the same value the chips
write — so a tap and a swipe are the same move, and the strip, the source wash,
and every deep link (`casberi://feed/source/X`) keep working with no second
source of truth to reconcile.

**It cost the row swipe, and that was the ruling.** Rows carried Share
(trailing) and Open-in-app (leading) since 2026-07-15. They're gone; both verbs
now ride a LONG-PRESS, which is what the Home board has used for Open/Unpin all
along (`GenRenderer.pinnedRowActions`) — so the two surfaces finally share one
grammar instead of disagreeing. Tap still opens the sheet: one gesture, one
meaning, unchanged.

**Measured before ruling — do not re-litigate this from theory.** The question
was whether a pager and both-edge `swipeActions` could coexist. Two careful
readings of the code predicted opposite winners, so it was tested on the sim
(2026-07-16) instead of argued: **the pager claims 100% of horizontal drags**,
at every drag length, on every page. Not "usually" — the row's actions could not
be revealed once. Worst case is the tell: on the LAST page, where there is no
page to go to, the drag merely rubber-bands the feed and the row still never
opens — so the swipe wasn't degraded by paging, it was made unreachable, and a
gesture that does nothing is worse than a gesture that's gone. The prior
expectation (that the row would win, per Mail vs X) was simply wrong.

**The board stays OUT of the pager** — Pinned is reached by its chip, and it
isn't a feed anyway. This is not squeamishness: `BoardDragDriver` arms its press
for 24pt while a scroll pan begins at ~10pt, and `lift()` fires `onPhase(.began)`
without checking UIKit accepted the transition — a pager pan inside that window
enters edit mode while the page slides away, which is the exact state-leak class
the driver's UIKit rewrite exists to close (four failed repair commits already).
Pulling a tile out of a 2-up pair is inherently a horizontal drag, so it would
be the common motion, not an edge case.

**What a pager broke that a single screen didn't, fixed here:** a pager keeps
neighbours MOUNTED, so `onAppear` stopped meaning "the person is looking at
this". Every per-visit effect now gates on a new `isActive` — the boundary
freeze, the entrance wave, the hue flood, the synthesis stream, and
`minimizesChrome` (three scroll observers writing one global would let an
off-screen page un-minimize the chrome). Without it, a page swiped PAST would
burn its arrival animation unseen and stamp away its own "New since" line.
`FeedScreen(source:)` now owns its room for life, which RETIRES the per-source
`visitFrozen` dictionary and `visitedSources` set — those existed only because
one screen served every room, and with them goes the 2026-07-13 junk-key bug
they guarded (a page can only ever stamp its own key).

The swipe COACH (`SwipeHintNudge`) left the feed with the gesture it taught, but
survives on the pushed management screens (Wallet, Tokens, Stocktwits, Kalshi),
which keep their swipes — they're outside the pager. Also fixed in passing: the
feed List carried TWO `.refreshable`; SwiftUI keeps the outermost, so the real
bridge sync never ran on a pull — only the 600ms pulse stub did.

Verified: 10/10 cold-launch survival with three feeds mounted where one was
(the stack-overflow class of CLAUDE.md — dropping the coach's `hintID` threading
flattened the row path enough to pay for the pager's depth).

## 89. Onboarding teaches the loop, not the philosophy (user, 2026-07-16) — BUILT

A tester finished onboarding and didn't know what to do next. The diagnosis
(after several rounds): every action in Casberi — connect an app, follow a
person, watch a wallet or token — lives in the store, and nothing taught a new
person that the store exists, where it is, or that pinning is how Home gets
built. The old "How it works" greeting spoke in evergreen abstractions ("Keep
tabs", "Take action", "Make it yours") that named categories, not first moves.

**The ruling: a new person must leave onboarding knowing exactly four things —
(1) go to the store, (2) connect, (3) pin to Home, (4) ask about what you've
saved.** The greeting now says precisely that, as numbered steps, wearing the
real controls' glyphs (the Apps door's grid, the composer FAB's plus) so both
are recognizable in the shell later.

Copy subtlety paid for in review: step 3 must NOT read as "pin what you want
to keep in sight" — that implies unpinned things vanish. Pinning picks what
Home leads with; the feed always has everything. The step says both halves.

Held for later (discussed, not ruled): follow-type rows on the onboarding
connect card (a person / a token / a wallet beside the app rows — "any follow
is a connect in the store"), and an embedded store shelf on the sparse feed.
Both aim at the same gap; the four-step greeting is the contained first fix.

## 90. The composer's tool grid dies; "Open in" chips carry the text out (user, 2026-07-16) — BUILT

The 2026-07-12 tool tiles were built for "oh, I need to…" moments — jump to
your own tool without hunting the home screen. Two flaws surfaced when the
user looked at them cold: the tiles read as "what are these for?", and the
jumps carried NOTHING — a blank Notes list or an empty Google page is the
home screen with extra steps. Worse, the grid showed only while the field was
EMPTY: the moment you had text worth handing off was exactly when the tools
disappeared. And the launcher was the first thing a new user saw on tapping
+, diluting the ask (the surface's differentiated verb, and onboarding step 4's
promise).

**The ruling: the grid is gone. In its place, "Open in" chips that appear the
moment there's typed text — and the text goes WITH the jump.** The two chip
bands are the field's two exits, mutually exclusive: ask chips while empty,
Open-in chips while typed. The leading caption + app-name chips read as one
sentence ("Open in · Notes · Messages · Mail · Google") — "take it with you"
copy was rejected as too abstract.

Mechanics (verified on-sim): Messages rides `sms:?body=` (screenshot-proof the
body lands), Mail `mailto:?body=`, Google the `q=` query. Notes has no
compose URL — its chip copies the text and flashes "Copied — paste it into
your note" (honesty rule: never a silent blank jump). Only destinations that
can actually carry text earn a chip: the old grid's blank jumps (Calendar,
Reminders, ChatGPT, Claude tiles) died with it, as did the `-forceTools` hook;
`-composerDraft "<text>"` replaces it as the headless reach for the typed
state. Typed text still never saves — it gains destinations, not persistence.

## 91. Connect pages redesign — wash, tagline, ghost preview, toggle verbs (user approved from mockups, 2026-07-16) — BUILT

The setup-screen family was redesigned from a three-mockup review (RSS,
GitHub, OpenSea) the user approved. Four rulings, two of which supersede
earlier recorded ones:

**Setup wash.** Every setup screen with a brand hue wears a faint top wash
(`bridgeSetupWash`, hue at 0.30 fading out above the action area — about a
third of the product page's atmosphere). Primary controls never sit ON the
wash (two near-match blues read as a mistake), and the connected header wash
plus connect bloom still land on top as the reward. Hueless apps get nothing,
the same ruling every wash follows. The 0.30 strength is the user's call —
the first build shipped 0.10 and read as no wash at all ("so there is no
more color?").

**Tagline header — supersedes §store-rulings item (3) ("the catalog offer's
own summary").** The setup header's blurb is now the offer's TAGLINE in
primary color, not the summary in gray: the person just read the summary on
the product page they arrived from, and an all-gray pre-connect screen read
as disabled. One source of words still holds — the tagline is the catalog's
own field.

**Ghost preview — amends the 2026-07-07 "option 4" confinement ruling.**
`GhostPreviewSection` streams the SAME StorePreview doc the product page
shows, on the setup screen, dimmed (0.55), inert, under a "What lands — a
preview" header and a "Your real things replace this when you …" caption.
The confinement ruling ("fake content is confined to the one surface where
preview framing is honest and expected") now covers BOTH surfaces of the
connect journey — product page and setup screen — under the same explicit
preview framing. Gating is honesty-critical: the ghost shows only when
NOTHING has landed AND the bridge is NOT connected — a connected bridge with
an empty corpus must not wear a caption telling the person to do the thing
they already did (caught in review before commit).

**Toggles as the connect verb.** OpenSea/GeckoTerminal chain rows are
switches now, not appearing checkmarks — a control that starts a live watch
shows both states. All off pre-connect (a preselected default would be fake
status); the footer says plainly that switching one on starts the watching.
Known trade accepted: a SwiftUI Toggle's label is not tappable, so the tap
target shrank from the full row to the switch — platform convention, revisit
if it confuses. GitHub's manual-token path folds behind "Prefer a token by
hand?" (sign-in is THE path); sync proof/errors surface beside sign-in while
folded, and a failed first connect unfolds the field its error points at.

Held for a later pass (review findings, deliberate): Deals/Shopify/
HandleSetup still hand-roll their pin sections (user stopped that
consolidation mid-review); Deals/GitHub-feeds keep the checkmark idiom;
the chains Toggle section is duplicated across OpenSea/GeckoTerminal and
the wash/ghost/hairline patterns are per-screen rather than hoisted into
shared chrome.

## 91. Ask or task — the composer's two exits, named (user, 2026-07-16) — BUILT

§90's "Open in" chips didn't survive first contact: "Open in" is app-plumbing
language (a user wouldn't guess the TEXT travels), and the person typing
"dentist tuesday 3pm" isn't asking — they're writing a FACT bound for another
app. Three rulings, one revised surface:

**We jump, we never write.** Direct EventKit writes were considered and
rejected ("no matter what we should jump — we don't write"). So the chips are
"Send to" + app names — Reminders, Calendar, Notes, Messages, Mail, Google —
and because a jump can't honestly claim "Add to", the labels don't. The text
rides the jump where a URL carries it (Messages/Mail compose body, Google
query) and rides the clipboard where none does (Reminders/Notes/Calendar,
flash: "Copied — paste it in <app>"). Calendar's jump opens AT the detected
date — calshow: takes seconds-since-reference-date (verified on-sim: Jul 21
detected → Calendar opened on Jul 21, 2026).

**Ask or task, taught by the surface.** The send button wears the word "Ask"
whenever there's typed text (a live recording keeps the bare arrow — stopping
SAVES the voice note, and an "Ask" label there would lie). The greeting line:
"Ask about your things, or write something and send it to another app." A
question-shaped draft (trailing "?" or a leading question word) hides the
Send-to band entirely — asking is that draft's one exit. NSDataDetector finds
times in fact-shaped drafts and a receipt line says so ("Found a time:
Tuesday, Jul 21 at 3:00 PM") — proof the Calendar jump lands right, and the
band never reorders (fixed positions, the launcher law §90 kept).

**The away brief is a chip, not a card.** The composer-opens-with-a-brief
mockup was liked but merged down: the existing away chip now wears "Catch me
up — N things" (count roll kept, canonical "While I was away?" ask kept).
`-composerDraft "<text>"` reaches the typed states headlessly.

## 92. The composer's empty state goes bold — ask tiles, one featured (user picked "option A" from three mockups, 2026-07-16) — BUILT

The empty sheet's horizontal chip strip died: it clipped its own labels
("How's m…"), and a suggestion you can't read isn't one. The corpus-derived
asks now render as a 2×2 grid of bold tiles (glyph top-leading in tint, the
whole ask unclipped at the bottom, `DS.Radius.widget` corners, `DS.gray100`
fill) under the "What now?" greeting at display scale (`heading34`, SF
Rounded). The ONE featured tile — the organize invite ("Tag your N <Source>
things") — wears the solid tint, the grid's single accent (one-tint law).
The librarian's catch-up tile keeps its rolling count. The Send-to band's
pills grew to match the grid's grammar (40pt, glyph + callout15 semibold) so
the field's two exits read as one design. Everything else held: greeting +
pairing line, tag completions, Send-to + "Found a time" receipt, mic / field
/ Ask button. The field's invitation placeholder now actually cycles (the
`invitations` list had been wired to nothing).

**Ruling (user, 2026-07-16): "How many links this week?" is never suggested
— nobody cares.** Counting stays a typed power; no chip or tile teaches it.

**Ruling (user, 2026-07-16): no logo in the composer.** A berry-marked
greeting was tried and rejected — the mark stays out of the sheet.

## 93. Discover becomes a deck — teaser cards, reasons, the demo moves to the page (user picked from three mockups, 2026-07-16) — BUILT

The Apps page's Discover carousel (four swipeable 220pt gradient slabs)
became a DECK: one card visible, the next cards peeking above it as scaled
edges, a horizontal swipe DEALS the front card (either direction — it flies
off, the next rises, the dealt card slides round to the bottom; the deck
recycles, browsing not consuming), an honest "1 of 4" count below (the page
dots died). Chosen over two siblings the user reviewed as mockups: a
one-poster-plus-mini-reason-cards layout ("the 2 up row of mini reason
cards is annoying") and a preview-rows-on-the-card demo anatomy ("demo
cards... that is what happens when you click into the app, not on the
card"). Explicitly rejected: any dismissal ("i don't like the idea of
dismissing a card for 30 days") — a card is never hidden by the user;
freshness is the system's job.

The rules, as built (AppsScreen.swift):

- **The card is a TEASER**: reason eyebrow, headline (the tagline), icon +
  Connect. The preview capsule rows LEFT the card — the product page and
  the long-press peek already render the same StorePreview document at
  full contrast; one document, one home. Card height is content-defined
  (the minHeight 220 died with the preview band).
- **Reason or no seat**: the "New" fallback eyebrow died. Every seat's
  eyebrow states a computable reason — "Goes with X" (adjacency to a
  connected bridge) or the offer's own qualifier ("No account" / "One tap"
  / "Import"). An offer with neither waits in its shelf.
- **The whole card is a door**: card body → product page (where the demo
  is); the capsule alone connects (or routes to setup, the shelves'
  split). Via TapGesture + navigationDestination, NOT a
  Button/NavigationLink — a button fires on release even after a drag, so
  a swipe ALSO opened the page (measured).
- **The daily deal**: seat order rotates by day-of-year mod deck size, so
  the deck opens on a different front card each day. Deterministic, no
  per-user state.
- **Honest count**: "1 of 4" is the real seat count; the peeking edges are
  real cards (one per remaining card, max 2).
- Kept: never a Soon app, never a connected one; cap 4; the search field
  is now ALWAYS visible (`.navigationBarDrawer(displayMode: .always)`).

Paid-for lessons (all measured on the sim, 2026-07-16, three probes deep):
(1) the deck swipe is a **UIKit UIPanGestureRecognizer on the enclosing
UIScrollView** (`DeckPanCatcher`, BoardDragDriver's architecture) that
begins only for clearly-horizontal pulls starting on the card — a SwiftUI
DragGesture (plain OR simultaneous, any minimumDistance) beat the scroll
pan and the page stopped scrolling from a finger on the card; (2) the
card gradient is **opaque** (brand mixed toward black, not
brand.opacity(0.65)) because stacked cards bleed through a translucent
one; (3) the ghost glyph rides an **overlay of the gradient, never a
ZStack sibling in the background** — a rigid 150pt image made the
background TALLER than short cards and the gradient painted past both
edges (the count rendered ON the card; minHeight 220 had been hiding this
since the carousel shipped).

## 94. The greeting goes large; onboarding lands in the store (user, 2026-07-16) — BUILT

Two rulings on §89's four-step greeting, from "make it visually stunning,
large proportions — I like the icon rain":

**The steps wear their numerals giant.** Each step is now a full-width card:
the numeral 148pt SF Rounded heavy in the step's hue, bleeding off the card's
top-right corner (clipped by the card); a 58pt glyph chip; the title at the
heading-22 tier; body copy at body-17. The header is the connect screen's own
34-heavy SF Rounded, and the cards arrive staggered with its entrance curve —
the two onboarding beats read as one voice. The numeral is information (the
sequence), not decoration; its hue is the step identity the glyph chip
already carries. Step 1 holds a settled strip of six real app icons, each
resting slightly tilted — the icon rain the person just watched, come to
rest. Titles dropped their "1." prefixes; the numeral IS the number.

**Onboarding lands IN the catalog, not the feed.** The greeting's one door
forward is a glass "Browse the catalog" CTA that dismisses the cover directly
onto the Apps screen — the arc is: apps rain down → the four steps → the
catalog where those apps live, so step 1 ("open the catalog") is fulfilled the
moment the cover lifts. This replaces §opt-4's 2026-07-07 feed landing for
the onboarding tail only; the record ("All" chip) waits one back-swipe
beneath, already holding whatever the connects landed. From Settings the
sheet keeps its plain toolbar Done — the CTA exists only in the onboarding
tail (`HowItWorksSheet(onOpenCatalog:)`).

Headless: `-howItWorksCTA <s>` fires the CTA after a delay (NSLogs
"howItWorksCTA: fired"). [Stale as of §96, same day: `-demoPick` died with
the connect screen — `-fresh YES -howItWorksCTA <s>` walks the arc alone.]

**Naming (user, same day): the Apps surface is never a "store" in
user-facing copy — it's "the catalog."** "Store" reads as a place you pay.
Shopify/Steam copy keeps "store" where it means a literal merchant shop.

Post-review hardening (same session, all re-verified on the sim): the pan
DELIVERS ITS OWN CALLBACKS from its touch handlers (a stock recognizer's
target-action on SwiftUI's scroll view fires only intermittently —
BoardDragDriver's lesson, which the first cut had only half-followed); the
deal swaps state in the spring's COMPLETION (`completionCriteria:
.logicallyComplete`) behind a `dealing` guard — the first cut's fixed
0.3s asyncAfter raced a fast second swipe into double-advances; the daily
rotation seeds the deck INDEX once per mount instead of rotating the seat
array per evaluation (which reshuffled the deck under a live index at
midnight and whenever the seat count changed); the fly-off distance is the
card's measured width + 100 (a hardcoded 640 would have swapped state
on-screen on iPad); a mid-drag unmount settles the drag before removing
the recognizer; swipes may start on the peeking edges; the under-cards are
hidden from VoiceOver and the deck advances via a named accessibility
action ("Next card"); the deck is its own child view owning the drag
state, so a dragged frame re-renders three cards, not every shelf row.

## 94. The qualifier badges die on the shelf rows (user, 2026-07-16) — BUILT

"'No account' repeatedly under the names of things, or 'one tap' or
'import' — who cares, it's extra text the user doesn't need to see." The
qualifier capsule badge left the catalog's shelf rows (and with it, search
results); rows read icon → name → tagline. The qualifier survives in ONE
place: as a Discover card's eyebrow, where a single card states its
reason. `Offer.qualifier` itself stays — it powers the reason-or-no-seat
rule (§93).

## 95. Ask tiles learn from taps; no launcher tile (user + assistant, 2026-07-16) — BUILT

Two rulings from one question ("can the tiles be smarter, and should
there be an 'open my…' tile?").

**Tap-learning decay.** The composer's ask tiles keep their honesty gating
(a tile must answer) but the priority order is no longer fixed forever: an
ask kind offered **10 opens without a tap** steps behind the next
qualifier — demoted by SORT, never filtered, so a short grid still fills
with it. A tap resets its counter. Counters are keyed by MEMORY KEY: the
ask's stable kind ("week", "wallet"), or kind:qualifier where one kind
wears many faces ("showtag:recipes", "context:Photos" — so one tag's
earned neglect never pre-demotes a different tag's first offering), never
display strings (titles carry live counts and would fragment the
counters), stored in UserDefaults (`Model/AskMemory.swift` — the
exemptions live there too, in one place). Exempt: "While I was away?"
(timely, not evergreen — it leads only when a real gap holds enough to
say something) and the organize invite (its own slot and gate). An open
that hands off an ask (a status chip's question filling the field) does
NOT count as an offer — the tiles never had a chance to be tapped. No ML,
no ratios — a counter and a stable partition. Probe: `-askStats
"<key>:<n>[,…]|clear"` seeds the counters (once per launch,
self-guarded — a per-view guard would re-seed each open and clobber the
bumps); every open NSLogs `askTiles:` with the chosen keys.

**No launcher tile.** "Open my wallet" as a tile is ruled out: the
source-chip header on Home IS the launcher, one tap away behind the
sheet, and the tile grid has one grammar — questions the corpus can
answer. Precedent: §90's "counting stays a typed power, never a tile."
If launcher-ness is ever wanted, it's a typed verb ("open …" routing to
the existing deep links), not a tile. Held, not built.

## 96. The connect screen dies — onboarding is the greeting, wearing the rain (user, 2026-07-16) — BUILT

"I no longer think we should have the first screen that has the apps to
connect. The icon tiles should rain down on the screen you created, then the
user goes straight to the app catalogue."

Onboarding is ONE screen now. The connect screen (§opt-4's mini store of
Photos/Calendar/Reminders, re-ruled 2026-07-07) is DELETED —
`OnboardingView.swift` is gone, and with it the `-demoPick` hook and the
minute-zero permission asks. A fresh install opens straight onto the "How it
works" greeting (§89/§94), which now carries the rain itself: the full
curated marquee (31 tiles, the same set the connect screen dropped — the six
Apple bridges still landing last as symbol tiles) falls down the screen IN
FRONT of the step cards and passes off the bottom. Rain, not ice: nothing
rests over scrollable content — step 1's settled strip of six is the rain
come to rest, same metaphor, same jitter. The fall is an ease-IN (gravity
accelerates; the old pile's spring-bounce was for landing, and nothing lands
here), deterministic (golden-ratio columns + the jitter table, no
Math.random), never hit-testable, and its base delay (0.7s) clears the
cover's own presentation — started at onAppear the curtain was half-spent
behind the cover fade (measured on the sim). From Settings there is no rain —
a second rain would be a fake first time.

Connecting moved to where the door already led: the catalog. The greeting's
"Browse the catalog" CTA (§94) is unchanged and is now the whole arc — rain →
four steps → catalog. `RootShell`'s cover lost its two-step swap
(`onboardingHowItWorks` state deleted); the CTA sets the feed to "All",
pushes Apps, and marks onboarded. What's given up, deliberately: the
in-context permission asks at minute zero (they now fire from each app's
catalog row/product page, where §opt-4 always ran them anyway) and the
feed-preview card's fill-in-place reward.

Bookkeeping: `catalog-sync.sh`'s marquee check now reads
`HowItWorksSheet.marqueeApps` (same array name, moved file); the onboarding
arc verifies headless with `-fresh YES -howItWorksCTA <s>` alone. Probe
lesson paid for twice this session: (1) `-onboarded NO` as a launch arg
MASKS the CTA's `onboarded = true` write for the whole run (the argument
domain wins reads), so the cover "never dismisses" — don't pass it when
probing the CTA landing; delete the stored key instead. (2) A concurrent
session driving the same booted sim can foreground THEIR binary mid-probe —
screenshots of a state you didn't launch mean collision, not regression
(this session's b2/video runs caught the other session's composer work).

## 97. The empty feed is the rain come to rest (2026-07-16) — BUILT

The truly-empty feed's quiet line + "Browse apps" chip + skeleton rows died
(supersedes §61's item 4 empty-door shape: the door survives, the quiet
berry and skeletons don't). Skeletons mean "loading" in every app, so an
empty state wearing them forever read as stuck — and the screen whispered
while the rest of the app went bold. What shipped (`FeedScreen.emptyState`
+ `EmptyFeedPile`): a display-tier headline ("Let's fill this feed.",
`.heading34` heavy — the cover voice, scaling with Dynamic Type), one
subline, the "Open the catalog" pill, a tertiary line naming the capture
verbs (paste / share / screenshot — the old copy CLAIMED capture without
teaching a verb), and the settled pile: twelve real catalog tiles resting
at the foot of the screen, slightly uneven, back row smaller behind the
front — the onboarding rain's third act (§96 rains them past, its step-1
strip shows them settled, the empty feed is where they land). On first
appearance the tiles fall in from above the screen and settle (gravity is
an ease-IN, the house rule; under Reduce Motion the pile is simply there,
per 43h). Honesty: every tile is a door — tap opens that offer's product
page via `HomeRoute.openOffer` (the `openTag` pattern), and the pile array
is catalog-sync-checked like the other marquees so a rename can't leave a
dead tile. Rendered FLAT (plain stacks, no Widget/Row path) per the
eager-head stack-depth rule. Headless: `-pileTap "<Offer name>"`;
`QuietStateView`/`CasberiMarkDrawOn` deleted with the old state.

## 98. "What apps do you have" answers from the app set, not the retriever (2026-07-17) — BUILT

The user asked the composer "what apps do you have" and got nonsense: no
handler owned the question, so it fell through to the term-scored
retriever, which read the literal words ("apps", "have") as search terms
and grounded the answer on whatever things happened to score — the same
failure class §"TagsAsk" fixed for "what tags do i have" (2026-07-12).
What shipped: `AppsAsk` (`Model/AskCommands.swift`) parses meta-questions
about the app SET — three intents: connected ("what apps are connected",
"what apps do i have"), catalog ("what apps do you have", "which apps can
i connect"), count ("how many apps") — phrase-gated so "anything new from
my apps" stays a status ask and "which app sent the most" stays
AggregateAsk's superlative (a `most` guard). It runs BEFORE AggregateAsk
on purpose: "how many apps" used to match AggregateAsk's bare "how many"
and answer with the TOTAL THING COUNT — a second live bug this fixes.
The answer (`appsDoc` in `Shell/RootShell.swift`) is computed, never the
model: connected seats from BridgeStore (names + an honest attention
count), catalog size from `BridgeCatalog.offers.filter(\.connectable)`,
worded per the §96 ruling ("the catalog", never "store"). Every variant
carries the catalog door — the same `AppsInvite("@apps")` card the quiet
day's slot uses — and the composer's `genProjectTap` now routes "@apps"
to the Apps page (it used to guard out all @-sentinels there, which would
have made the card a dead control — honesty rule). Like every computed
ask, it clears `lastAnswerHits` so a keyed retry re-retrieves. Headless:
`-answerProbe "what apps do you have"`.

## 99. No notifications, no widget (2026-07-17) — RULING

Casberi does not send notifications — not a deferral, a positioning
ruling (user): the pitch is "easier than relying on notifications," the
app that watches accounts/wallets/feeds so ten other apps do not have to
ping you. Sending our own would make Casberi an eleventh notifier — the
thing it claims to replace. Arrival surfaces carry what other apps would
push: the "while I was away" brief, the Coming up lane, the feed itself.
The answer waits for the user; nothing demands them. Corollary: the app
never shows the notification-permission prompt — the absence is itself
the statement. This holds even for the tempting class (wallet approval
events): a server-less local notification would arrive hours late off
background refresh anyway, so the away brief loses almost nothing.

The Home Screen WIDGET is also OFF the roadmap for now (user, same
session): ~a quarter of users ever place widgets, and the real cost is
not the build but the standing surface — a second process on the shared
store, timeline staleness, its own empty/fallback/theme states, one more
thing every audit walks. Not worth it pre-launch with zero users to
place it. Revisit only post-App-Store if Connect widget analytics say
otherwise. Do not re-suggest either of these.

## 100. The tab bar dies — one surface, a Pinned-first chip header, a FAB (2026-07-13, recorded 2026-07-17) — BUILT

Retroactive ruling: the shell change shipped in `0764ee3` (2026-07-13) but
never got a numbered entry — it lived only in CLAUDE.md's design-law digest,
so every ruling written before it (§16 Shell, the §opt-4 onboarding batch, the
2026-07-08 store/tab batches, §61's elevation-law example) still narrated a tab
bar with no ledger entry marking them superseded. This is that entry; those
older rulings stay as written (append-only ledger — true when ruled), read
against this one.

WHAT DIED: the three-tab shell (Home · Feed · Apps, ruled 2026-07-06 and
carried through the store batches) and its `GlassTabBar`. Home and Feed were
never really two places — both compose the same corpus, one as a board, one as
a stream — and keeping them as separate tab roots forced a standing tax of
reconciliation code (`FeedRoute`, `jumpedFromHome`, `goHomeRequest`, `popFeed`)
that existed only to sync two NavigationStacks. All deleted.

WHAT SHIPPED: ONE surface (`Shell/MainSurface.swift`). A single
`NavigationStack` under a fixed chip header — **Pinned** (your board) leads,
then **All**, then every source most-recent-first (`Corpus.surfaced`, the same
rule Home and Feed already shared, so the chip row lists exactly the sources
the feed shows). The body under the header swaps between the board (Pinned
selected) and the shaped feed (any other chip); there are no tabs to switch,
only chips to filter. The composer returns to a **FAB** the shell floats over
the surface. Management lives in two doors the container owns so they can't
drift between screens: **avatar → Settings**, **grid → Apps**, each a zoom
transition anchored to its door (`doorNS`).

LANDING: a curator with something pinned opens on their board; a new install
or anyone who never pinned opens on the whole record instead of an empty board
(the "Pinned" chip is still there, its body just isn't the landing when it
would be bare).

CONSEQUENCES THAT BIT LATER, logged here so they read as consequences and not
new bugs: (1) Liquid Glass's floating layer is now composer + FAB + toasts —
§61's "tab bar" example was amended in place the same session this was recorded.
(2) `-openSettings` broke: it had lived in HomeScreen's onAppear, but the
one-surface shell only mounts HomeScreen when the landing chip is "Pinned", so
on an unpinned install the hook never fired (fixed 2026-07-14 by moving it to
`RootShell`'s onAppear; `casberi://settings` is the reliable route — see the
deep-links line in CLAUDE.md). (3) `casberi://account` still resolves (→ the
Apps door) for back-compat. Deep links are the audit's way in now that there
are no tabs to select.

## 101. "Coming up" collapses to one row (2026-07-17) — BUILT

User ruling: the card was showing up to five schedule rows at the top of Home,
which "makes the home feed be something it isn't" — a person who sees their
whole day there stops opening their calendar, and Home starts reading as a
calendar app. The user offered a 1/3/5 three-way toggle or a 1/3 two-way and
delegated the pick.

Ruling: **two states, 1 and 3.** Five dies entirely (it's the count that caused
the complaint), and a three-way toggle needs control chrome — a segmented
picker or stepper — on a card that's supposed to be ambient synthesis, not a
widget with settings.

- **Collapsed (default):** one row — the next thing due (overdue leads, same
  order as always) — with its day label ("Today" / "Tomorrow" / "Overdue" /
  weekday) worn inline in the trailing slot. This deliberately drops the
  §always-lead-with-Today sectioning in collapsed mode: the 2026-07-15
  confusion ("why does it lead with tomorrow's meeting?") was about a
  CALENDAR view jumping ahead silently; a single ticker row that says
  "Tomorrow" right on it answers the WHEN without the sections.
- **Expanded:** the existing day-sectioned view (Overdue → Today-always →
  following days), now budgeted at **3 item rows** (`ComingUp.sections`
  default limit 5 → 3).
- **The toggle** is a muted "N more" / "Show less" footer line — the card's
  only control, shown only when there IS more than the lead row (honesty: a
  one-row lane gets no dead control), and its count is the rows the card
  actually holds, so tapping delivers exactly what the label promised. The
  choice persists (`comingUpExpanded` in AppStorage).
- The composition doc still carries the full sectioned lane; collapse is
  purely GenComingUp's draw decision — `-comingUpProbe` (which logs the
  uncapped lane) and the flat-render crash law are untouched.

## 102. Token surfaces go Big money — the sheet re-ranks, the row gets fat (2026-07-17) — BUILT

User asked "can we show market cap on our tokens?", then picked from six
mockups (three sheet, three feed; "Cash App meets Casberi"). Approved: the
**Big money** sheet and **fat rows**. Explicitly REJECTED: the top-mover hero
card on the Tokens view ("user can go to home feed for that and it just gets
in the way") and the tile shelf (duplicates Home's pinned Tokens tile; cards
would orphan the rows' long-press verbs).

- **The sheet (Big money):** `TokenChartView` grew a `hero` dose (only the
  token thing sheet passes it) — price centered at 40pt rounded bold (a
  deliberate hero rung above the ramp's 34; the one place it's allowed),
  delta pill beneath it, range chips move below the plot. The stat strip
  re-ranked: **market cap and 24h volume lead as two bold cards** (24pt
  rounded), FDV and liquidity demote to quiet chips; still cells only for
  stats the pair reported — a capless token leads with FDV, labeled FDV.
  Watch became one full-width tint capsule; the settled "Watching" state
  wears the same capsule quiet, as a label not a control.
- **The feed (fat rows):** a pulsed token row steps out of the band anatomy
  (supersedes Option A's sparkline-in-the-band, prd 2026-07-10): 38pt coin
  (TokenWatch.add now stamps the resolve's logo onto previewImageURL), name
  over "SYMBOL · $94.1B cap" vitals, live price in 16pt rounded bold over a
  **solid** state pill. Flat keeps the quiet fill and no direction (honesty
  §83). The market size rides the SAME fetch the pulse already made —
  `TokenChart` captures `market_cap_usd`/`fdv_usd` off GeckoTerminal's pools
  response and `marketCap`/`fdv` off the Dexscreener pair; zero new
  requests. A pulse-less row keeps the plain band + timestamp.
- **Crash paid for:** any token thing opened via the deep-link/`-openThing`
  sheet crashed at mount since 2026-07-15 — `TokenChartContent`'s required
  `@Environment(BridgeStore.self)` met the `deepLinkThing` sheet chain that
  hangs outside RootShell's `.environment(bridges)`. Fixed both ways: the
  sheet now hands the store in, and the read is optional (missing store only
  skips bridge registration on Watch).

## 103. Bitrefill joins the catalog — orders in, balance in the lede, honesty ceiling on the shelf (2026-07-17) — BUILT

Bitrefill (crypto gift cards / top-ups / eSIMs) lands as a token bridge — a personal API key from bitrefill.com/account/developers, Bearer auth against `api-bitrefill.com/v2` (a DASH in the host, not a dot). Orders land as link things ("Amazon.com · $50", the product's own artwork as the thumb, dated by `delivered_time`; sourceRef `bitrefill:order:<id>`); invoices with no orders on them are balance refills ("Balance refill · $50 in bitcoin"; sourceRef `bitrefill:invoice:<id>`); the account balance is a UserDefaults reading (`BitrefillBalance`), not a thing, feeding the Bitrefill feed's lede ("Balance … $12.40 · N orders this month") — connected-only, so a removed key never wears yesterday's balance.

RULINGS:
- **Shopping, not Markets.** Bitrefill is your own commerce account — receipts — not a market you watch. It shelves with Shopify/Deals, and the website mirrors that.
- **The honesty ceiling, measured 2026-07-17:** the orders schema carries NO redemption status (Bitrefill can't know a code was spent at Amazon) and NO expiry. So the approved mock's "Ready to use" shelf, "Unused/Redeemed" trailing words, and the expiring-card pulse row are DEFERRED — rows claim only name, price, and when it arrived. If Bitrefill's API ever reports expiry or redemption, the mock's shelf+pulse design (session 2026-07-17) is the approved shape to build.
- **Key honesty:** Bitrefill offers no read-only key scope, so the promise is Casberi's conduct, stated on the offer: "nothing here ever buys, pays, or spends your balance" — the Bankr posture, without the mint-it-read-only instruction Bankr can give.

## 104. Wallet screen: Watching and Approvals lead (user, 2026-07-17) — BUILT

User: watching and revoke sat below the transactions, "but that makes them buried and also less clear on what to pin. i think they should be at the top." Connected-state order is now **Watching → Approvals → portfolio bundle → per-wallet treemaps → NFTs → recent → add / chains / status / disconnect**.

This amends §-adjacent 2026-07-15's "value first, admin at the bottom" inversion without betraying it: the watching rows have carried the value themselves since 2026-07-15 (per-wallet USD subline + sparkline + delta pill), so leading with them still leads with the money — and the pin control lives on those rows, so they're also the answer to "what do I pin," which was unfindable under two treemaps and an activity log. Approvals rides directly beneath Watching: the security read belongs beside the wallets it reads, not below the feed of what already happened. Add/chains/status stay clustered at the bottom — still the settings, still not the point.

## 105. Tokens goes ink — the mark is a green chart on black, and the token sheet drops the wash (user, 2026-07-17) — BUILT

User, on the Big money sheet (§102): "the token thing sheets don't look good w gold background b/c you can't see the data that is on them well… it could be a green one or a black one w/ a green price chart." Shown three treatments (short crown / pure ink / direction glow), picked **pure ink**, and ruled the mark should say so: "we need to make the icon reflect that as a black background green chart. that also makes it more purposeful that the token sheet is ink."

The diagnosis behind it: §102 moved the hero price, delta pill, and plot INTO the 300pt source wash, breaking the wash's own charter (2026-07-10: "no ink ever depends on it for contrast") — and gold is the worst hue for direction ink (red on gold ≈ no contrast; red fill over the fading gold reads brown, green would read olive). The 07-17 `fillStrong` pill patch treated the symptom.

RULINGS:
- **The Tokens mark is a green chart on ink**: brandHue `#0b0b0b`, glyph `#30d158` (the dark-scheme confirm green, fixed — the tile is black in both modes). `BridgeGlyph.glyphTint(for:)` carries glyph-colored identities; surfaces that paint the brand hue as a SIGNAL (settings seat chips) substitute it, since near-black carries no light.
- **The token sheet is pure ink ON PURPOSE** — not a special case: the near-zero saturation makes `DS.washHue` nil, the same mechanism as X/Cal.com. The identity and the sheet agree: charts own the color; the day's green/red is the only hue.
- **Direction glow rejected** (crown would repaint per range chip; breaks wash=identity; flat needs a third state). Short crown rejected in favor of the mark change.
- **Stat block is one grid** (amends §102's "quiet chips"): FDV/liquidity join market cap/volume as smaller cards in the same two-column grid — "the tiles were chunkier and the whole thing was more cohesive… please update that too." Demotion is SCALE (price16 vs stat24), not a different anatomy. Tile radius (`DS.Radius.widget`), s4 padding, s2 gutters; the since-watched line centers under the centered hero.
- **Website**: `.ai-tokens` black + green path, and the Tokens/Wallet hero+catalog tiles dropped the `tilefull` class — `.ai.tilefull { background:none }` outranks every per-brand background, so the two glyph-SVG tiles (unlike the full-bleed img tiles the class is for) had been rendering with NO brand field on the live site.

## 106. Translate joins the thing sheet's action row (2026-07-17) — BUILT

A `.translate` verb rides Apple's own `.translationPresentation` sheet (SwiftUI, iOS 17.4+ — under the app's 18.0 deployment target, so no availability gate needed) over a chat/mail/note/file/voice thing's own words (`postText` when present, else `content`). Zero custom UI: the system picks the source language and presents its own translation surface. Offered only when the thing actually carries text — no dead control on an empty body. Lives in both surfaces that derive verbs from `VerbDerivation.verbs(for:)` (the sheet's action rows AND the feed row's swipe actions), each holding its own `showTranslate`/`translateText` state since the two are separate views.

## 107. Semantic Spotlight — things become `IndexedEntity`s, not just search hits (2026-07-17) — BUILT

`ThingEntity` (`Model/ThingEntity.swift`) is additive, not a replacement: `SpotlightIndex`'s manual `CSSearchableItem` indexing (title/description/keywords) keeps running for system search exactly as before, refactored only to share its attribute-set builder (`SpotlightIndex.attributeSet(for:)`) with the new entity's `IndexedEntity.attributeSet`. `SearchCasberiIntent` now returns `[ThingEntity]` instead of a joined string, so a Shortcuts/Siri search hands back tappable, semantically-indexed things instead of plain text. `AskCasberiIntent` is unchanged (its output is a synthesized answer, not a list of things). Known verification gap, stated honestly: Siri/Spotlight's actual semantic surfacing of a donated entity can't be checked headlessly on the simulator — `-intentProbe` confirms the underlying match set is unchanged, but the richer Shortcuts/Siri presentation is a real-device/manual check.

## 108. WeatherKit joins "Coming up" — a live read, never stored (2026-07-17) — BUILT

Today's forecast decorates the "Coming up" card's Today label ("Today · 72°, partly cloudy"); every other day label (Tomorrow, a weekday, Overdue) is untouched. Deliberately NOT a `Thing` field — no schema change, no migration: `WeatherEnrichment.todaySummary()` is a live WeatherKit fetch at render time, cached ~30 min in memory so a recompose doesn't re-hit the API. Needs a ONE-TIME "When In Use" CoreLocation read (never background, never a stored location) — confirmed acceptable to the user as materially lighter than the significant-locations ("Always") ask that was rejected the same session. Denial or fetch failure leaves the label plain (honesty rule: no fake status).

Measured 2026-07-17, don't re-diagnose without re-measuring: a Simulator build (`Sign to Run Locally`) skips provisioning entirely, so `com.apple.developer.weatherkit` in the entitlements file alone can't prove the capability is live — the location read and WeatherKit call both fire correctly (confirmed via `-weatherProbe YES`: resolved to the simulator's SF coordinates, request reached `WeatherDaemon`), but it fails at Apple's JWT auth step (`WDSJWTAuthenticatorServiceListener` code 2) because the App ID isn't yet provisioned for WeatherKit with Apple's servers. That resolves on a real-device/archive build where automatic signing re-registers capabilities — it is not a code bug.

## 109. HomeKit joins the catalog — live accessory state, not an event history (2026-07-17) — BUILT

**Scope ruling, stated up front:** HomeKit has no historical-event query API (accessory state changes are push-only, delegate callbacks while an app or long-lived observer runs), so there's no way to backfill "what happened while the app was closed" the way Calendar/Contacts refresh does. V1 lands each accessory as a live-state reference thing (a plain-English category + room + reachability — e.g. "Lock · Living Room · Reachable"), refreshed in place on each foreground pass, not a growing feed of "the same door again." A new `ThingKind.accessory` case carries it, search-only like Contacts (`Corpus.searchOnlySources` now `["Contacts", "HomeKit"]`) — a house full of accessories re-updating every refresh shouldn't bury the feed. Decoding an accessory's actual characteristic value (locked vs unlocked) is explicitly DEFERRED: it needs per-service-type reads this session couldn't verify without a paired accessory or the HomeKit Accessory Simulator — reachability is the honest v1 ceiling.

New "Home" category shelf (`AppsScreen.categories`, group `"Home"`) — app catalog, website `#catalog` shelf, and `scripts/catalog-sync.sh` all confirmed in sync. Measured 2026-07-17: on the iOS Simulator, `HMHomeManager`'s `homeManagerDidUpdateHomes` delegate callback never fires at all (no homes, and — unlike Contacts/Health — the permission ALERT DOES appear, but answering it doesn't unblock the callback either) — an unbounded wait would have hung the connect flow forever, which the app's own "no dead controls" rule doesn't allow. `HomeManagerBridge.waitForHomes` therefore races a 20s timeout against the callback (generous for a human answering the real alert, bounded against a broken/absent one), confirmed via `-homeKitProbe YES` resolving to an honest `FAILED (denied)` within the window rather than hanging. Live accessory data itself needs a real device or the HomeKit Accessory Simulator to verify — Simulator has none.

## 110. SpeechAnalyzer — the iOS 26 voice-transcription path, alongside SFSpeechRecognizer (2026-07-17) — BUILT

`VoiceCapture.swift` gained a parallel `if #available(iOS 26.0, *)` path using the new `SpeechAnalyzer`/`SpeechTranscriber` API (async-stream-fed, faster and more accurate on-device transcription), with `SFSpeechRecognizer` kept as the fallback below it — the file's first version gate of any kind (previously unconditional). The modern path only engages when its on-device model is ALREADY installed (`AssetInventory.status(forModules:) == .installed`) — it never triggers a download mid-recording, so tapping the mic always starts instantly regardless of which engine answers. Any setup failure on the modern path falls straight through to the legacy one; the two never both run. `ModernSpeechSession` (the analyzer/transcriber pair, boxed as `Any?` on `VoiceCapture` since the class must still compile and run below iOS 26) is a new private type in the same file.

Verified 2026-07-17 end-to-end via the real composer mic flow (not just a probe, given this file's documented threading fragility): on the iOS 26 Simulator, `AssetInventory.status` reports **`.unsupported`** (not merely "not installed") — Apple Intelligence-tier on-device model support isn't present in Simulator at all — so the app correctly falls back to `SFSpeechRecognizer` every time, logged honestly (`VoiceCapture: SpeechAnalyzer model not installed (status=unsupported)`), and the full record → stop → save flow still lands a "Voice note" thing with no regression. The modern path itself is therefore CODE-COMPLETE but UNVERIFIED live — it can only be exercised on real Apple Intelligence-capable hardware, not Simulator.

## 111. 1Claw joins the catalog — the agents' vault, grants not secrets (2026-07-17) — BUILT, UNMEASURED

1Claw (1claw.xyz) is a secrets vault for AI agents: humans grant agents scoped, revocable access to secret paths via policies. Its catalog seat answers exactly one question — **"what can this key actually reach?"** — with the vault's own records, and nothing else. A paste-a-token bridge (`TokenBridge.oneclaw`, Agent group beside Venice/Bankr; fetch in `Model/OneClawBridge.swift`): the agent API key (`ocv_…`) exchanges for a short-lived JWT at the documented endpoint (`POST /v1/auth/agent-token`, body just `{api_key}`; a non-`ocv_` paste is treated as a human's user key and exchanged at `/v1/auth/api-key-token`), then vaults land from `GET /v1/vaults` and each vault's grant table from `GET /v1/vaults/{id}/policies` — one thing per policy (`sourceRef 1claw:policy:<id>`), titled off the record itself ("Prod · secrets/anthropic/* · read, rotate"), dated `created_at`, with `expires_at` stored in `dueAt`. The feed lede is the key's reach ("Access · N grants · M vaults" — vault count cached in `OneClawAccess`, grant count from the rows below so the two can't disagree; cleared on disconnect).

Rulings:
- **Grants, not secrets.** Nothing here ever reads a secret's VALUE, signs, or spends — the endpoints called can't. Copy says so.
- **Grants land as things** (durable, datable, dedupe-able), not a live permissions card — 1Claw stays inside the normal bridge shape.
- **Honest degradation:** a key without `policies:read` lands vaults with no grant rows; the feed never invents a grant table it couldn't read. `-oneclawProbe YES` logs each step (scopes / vaults / per-vault grant count or "UNREADABLE") so "no grants" and "can't read grants" stop looking identical.
- **`dueAt` on a grant** is a real structured deadline, but the Coming up lane still reads only reminders — surfacing expiring access there is a SEPARATE ruling, not taken here.
- **Grants RECONCILE, not append** (code-review round, same day): policies are mutable records — editable and revocable under the same id — so unlike every append-only bridge, the fetch updates a landed grant's title/`dueAt` in place and DELETES rows whose policy vanished (Spotlight included). Deletion only runs when every vault's table was actually readable: with one table unreadable, "revoked" and "couldn't read" are indistinguishable, and guessing would erase real grants. Without reconciliation the feed overstates the key's reach — the one failure a grants surface must not have.
- Same round: 1Claw grants joined the All-feed bundling EXCLUSIONS (policies share a created_at day, so 3+ would collapse into "1Claw · N links", hiding the table the bridge exists to show); the app-side brand identity landed (`DS.brandHue` "1claw" #990029, `BridgeGlyph` "lock.shield") so the tile isn't a gray generic while the website tile wears the brand; the vaults envelope is OPTIONAL per spec (a zero-vault key is an empty reach, not "check the token"); per-vault tables fetch via `boundedGather` (max 4); and `TokenSetupScreen.connect` now calls `onRemove()` before storing a pasted token, so a paste-over reconnect can't leave the NEW key wearing the OLD key's cached readings (fixes Bitrefill's balance too).

**UNMEASURED (2026-07-17):** built against 1Claw's published OpenAPI spec 2.27.0, not the live API — no dev key existed in the session. Before calling this done: store a real key (`scripts/dev-keys.sh set 1claw`), run `-tokenBridge "1Claw:$(scripts/dev-keys.sh get 1claw)"` then `-oneclawProbe YES`, and re-measure (a) the exchange endpoints' envelopes, (b) whether a default agent key carries `policies:read`, (c) whether grant rows should open somewhere better than the dashboard root (the API documents no per-vault web permalink).

## 112. Smart accounts without the finance-app tripwire — the preparing surface (2026-07-17) — BUILT (v1: approvals), UNVERIFIED

**Ruling (user, 2026-07-17), the Apple line stated once:** App Review Guideline 3.1.5(b) judges the in-app experience, not the key architecture — an app whose buttons can move money is a wallet/exchange to a reviewer regardless of where keys or funds technically live, and wallets require organization enrollment (Casberi is a solo individual account). So the wallet bridge's ceiling is the **preparing surface**: Casberi READS on-chain state and PREPARES transactions in-app; signatures and delegation grants always happen elsewhere (a wallet app, Revoke.cash, the web). Corollaries: (1) prepared intents stay BOUND to facts the corpus surfaced (this approval, this expiring session key) — never a freeform send screen, which reads as a wallet's home screen no matter how the signing works; (2) the app's own WalletConnect session stays `methods=0 events=0` — requesting `eth_sendTransaction` over it is the exact moment the line is crossed; (3) every door names its destination and carries the footer promise ("a transaction you sign there — never in Casberi"); (4) outcomes close by WATCHING, never callbacks — the executed action lands back as a feed thing / a flipped card because the chain says so.

**v1 is approvals** (`Model/WalletPrepare.swift` + `Screens/ApprovalPrepareCard.swift`), the one corpus fact with an obvious undo. An approval thing's sheet grows a card computing three keyless reads on the SAME measured hosts as the §84 sync (`WalletApprovals.rpcRead` — one chain table serves both): the grant's LIVE state (`allowance`/`isApprovedForAll` via `eth_call` — "Still active" / "No longer active — revoked", the honest close of the loop after the person revokes elsewhere), the fee to revoke (`eth_estimateGas` × `eth_gasPrice` in the chain's native coin, omitted when unreadable — and a quoted fee doubles as a dry run, since a reverting revoke fails the estimate), and the revoke transaction itself, encoded (`approve(spender, 0)` / `setApprovalForAll(operator, false)`) behind a "Copy revoke transaction" door beside "Revoke on Revoke.cash". The token contract isn't stored on the thing, so the log is refetched by the sourceRef's (txHash, logIndex) and the owner+spender topics are checked against the thing's own fields before anything renders — a drifted index must not dress a stranger's approval in this thing's words. Probe: `-prepareProbe YES` (newest landed approval thing, one line per fact; pairs with `-approvalProbe <blocksBack>`).

**UNVERIFIED, stated honestly:** authored off-Mac (no build run). Before relying: build, then `-approvalProbe <n>` + `-prepareProbe YES`, and specifically re-measure whether the §84 public hosts serve `eth_estimateGas`/`eth_gasPrice`/`eth_getTransactionReceipt` (only `eth_getLogs`/`eth_call`-class reads were measured there; the fee line is designed to drop honestly if not, but the receipt read is load-bearing for the whole card).

**Held, deliberately:** session-key/module reads (richer smart-account watching), preparing the delegation grant itself ("grant the agent a $50/week allowance" as calldata), EIP-681 deep links into wallet apps, and stamping the token contract + forAll flag onto the approval thing at ingest (purely additive `Thing` fields — they'd drop the receipt refetch for things landed from then on; the refetch stays regardless, for the corpus already landed) — each rides the same ruling when it comes; none is blocked by it. If execution ever becomes the product, the paths are an LLC re-enrolled as an organization, or execution surfaces on casberi.app (outside App Review) — not architectural cleverness inside the app.
## 113. Peer joins the catalog — fills as they settle, riding the Wallet bridge (2026-07-17) — BUILT

Peer (peer.xyz, the protocol formerly ZKP2P) is non-custodial P2P fiat↔crypto: pay with Venmo/PayPal/Revolut/Cash App, a zero-knowledge proof verifies the payment, and the crypto settles onchain into the buyer's OWN wallet through Peer's escrow contracts on Base. That shape decided everything:

- **The seat rides the Wallet bridge the way Strava rides Apple Health.** There is no Peer account, key, or OAuth — identity is the wallet. Connecting is one switch (`peer.connected`, the TrendingStore idiom: no credential, nothing for Delete-access to purge) over the already-watched wallets; the setup screen's only prerequisite is a watched wallet, and with none watched the connect row is honestly replaced by a "Watch a wallet first" route (a disabled switch would be a dead control).
- **What the seat adds is the WHY.** A Peer buy already lands via the wallet transfer sync as a bare "received 25 USDC". The seat's sweep (`Model/PeerBridge.swift`, the WalletApprovals shape: per-wallet cursors, running guard, fail-closed, land-before-advance, silent first-sight baseline) reads `IntentFulfilled` on Peer's two orchestrators — the receiving wallet is an INDEXED topic, so one filtered `eth_getLogs` per wallet per pass — then joins each fill's `IntentSignaled` (payment method + fiat, both keccak-hash tables from Peer's published deployment package @zkp2p/contracts-v2 0.3.0; the scheme verified by recomputing their USD constant) and the escrow's `getDeposit` for the settled token: "Bought 25 USDC with Venmo on Peer", sourceRef `peer:<intentHash>`, content = the Basescan tx. Every join miss degrades the TITLE only, never invents ("Bought crypto on Peer" is the floor). Rides `WalletIngest.refresh`'s pass beside WalletApprovals.
- **Capture only, settle only.** Nothing anywhere starts a trade (the Bankr "answer only" line; the Wallet screen's "watching can never trade or move funds"). A signaled-but-unfulfilled intent never lands — a thing lands when a trade settles, not before. The ZK design keeps the fiat leg private: the chain shows platform/token/amount/rate, never the person's Venmo side or counterparty — so neither does Casberi.
- **Catalog category: Markets, by ruling (user, 2026-07-17; corrected same day from Onchain)** — Peer browses beside Kalshi and Stocktwits in the app (offer group `"Markets"`) and leads the website's Markets shelf.
- **Trailing slot** = which watched wallet (the Wallet rows' rule) — the platform already leads in the title.
- **UNVERIFIED live (stated honestly):** this session ran in a sandbox whose network policy blocks public RPC hosts, so the sweep compiles against measured constants but hasn't landed a real fill yet. First Mac-side run: `xcrun simctl launch booted com.casberi.app -walletAddress <a wallet that used Peer> -peerProbe 50000` — the probe rewinds the cursors and NSLogs the landed count; Peer does real volume on Base, so a recent buyer's wallet should land its fills. Re-measure before trusting: the 9k-block Base getLogs cap is inherited from WalletApprovals' measurement, and the IntentSignaled join looks back 12k blocks (Peer's own 6h intent expiry, with margin).
## 114. Catalog re-shelving: Markets leads, Onchain dissolved, Wallet its own, Farcaster social (user, 2026-07-17)

The catalog's category spine is re-cut (`AppsScreen.categories`, mirrored by the website `#catalog` shelves and every offer's `group` in `BridgeCatalog`):

- **The "Onchain" category is dissolved.** Its members scatter by what they actually are: Tokens, OpenSea, GeckoTerminal join **Markets** (things you watch), Farcaster joins **Social** (a social account, beside Bluesky), and **Wallet** stands on its own new one-tile category.
- **Markets LEADS the catalog** (front door), Wallet sits right behind it, then Life, Home, Notes, Social, Agents, Mail, Work, Reading, Media, Shopping. This reverses §61's "Markets rides last / prediction markets are a tail interest" placement — the finance pair is now the opening act, not the closer.
- **Reverses two prior rulings:** §78 (GeckoTerminal → Onchain) and the 2026-07-14 "Farcaster is the onchain network, not Social" shelving. Group strings: Tokens/GeckoTerminal → `"Markets"`, Farcaster → `"Network"`, OpenSea keeps `"NFTs"` (maps to Markets), Wallet keeps `"Wallet"` (its own category). No offer carries `"Onchain"` anymore.
- **Peer** (§113) was already in Markets; it stays, now beside the newcomers. catalog-sync stays green (shelf ↔ connectable set is unchanged — only the grouping and order moved).

## 115. DeFiLlama price backstop — holdings stop vanishing, no new UI (2026-07-17) — BUILT

A keyless price backstop over DeFiLlama's coins API (`coins.llama.fi`), filling the one gap Alchemy pricing leaves in the wallet's holdings read. **Not a catalog app** — the user never connects or sees it; it's infrastructure, so no Apps/website/onboarding sync applies and no new screen, tile, control, or copy is added.

- **The gap it fills:** `fetchHeldTokens` drops any token Alchemy doesn't price (the `price > 0` guard). That's worst on Solana — Alchemy's Portfolio prices only native SOL inline, and even its SPL Prices endpoint (`priceSPL`) misses long-tail mints — and worst under load, since the shared free-tier Alchemy key rate-limits (the vanishing-holdings-card class). A dropped token is a real holding that silently disappears from the treemap.
- **Why DeFiLlama:** keyless, and it prices EVM + SPL mints in ONE batched request, each with `decimals`/`symbol`/`confidence`. Measured 2026-07-17 against the live API: USDC/wSOL/JUP/BONK all priced, SOL decimals `9` (no `?? 18` trap), unknown mint → empty `coins` (clean fall-through), Cloudflare-cached ~3 min. **Emissions/unlocks were considered and rejected — that endpoint now 402s (paid plan), breaking the keyless model.**
- **Fallback only, never authoritative:** `DefiLlamaPrices.prices(for:)` fills `price == nil` only (never overrides Alchemy), runs AFTER `priceSPL`, and off the contended Alchemy key. Gated by a `confidenceFloor` (0.9) so a thin-pool guess isn't spent on a treemap cell (honesty rule). Solana mints pass through case-UNCHANGED (base58 is case-sensitive); EVM keying tolerates hex case.
- **Visible effect, no new chrome:** the treemap fills in (tokens that used to vanish now appear) and the holdings card is less likely to go empty. No price-source badge or confidence marker — mixing sources invisibly is already how `TokenChart`'s cascade works.
- **Verify:** `-defillamaProbe <address>` (pair with `-walletAddress`) reports unpriced-after-Alchemy count and the backstop's per-mint verdict (rescued / below-floor / no-price) — the rescue is the feature, and a count alone can't show it. `-holdingsProbe` exercises the same path end-to-end. `Model/DefiLlamaPrices.swift`; wired at `WalletIngest.backstopPrices`.

## 116. Home: quiet the bento's chrome, restore one synthesized line (2026-07-18) — DEVICE-VERIFIED 2026-07-17

Three changes from the "is the bento too cute?" review. The three-span board (§58i) is kept — each size is a different information DOSE, not decoration — but its always-on machinery was doing the cutefying, and the composition-per-moment promise had thinned to a single header (after §36c removed Insight and §36k removed Threads, Home became "what you pinned + the map", static day to day).

- **The size pin lives in edit mode now.** Every board tile wore a standing `ShelfSizePin` at rest — meta-chrome about the board on a screen whose law is "no dead controls, the content carries it" (§58l/design). Now `HomeScreen.sizeToggleAction` hands the renderer `genSizeToggle` only while `boardEditing`; every `ShelfSizePin` site already gated on that closure being non-nil, so nil at rest hides all nine at once. A long-press lift arms edit mode and brings the pins back beside the remove badge — the iOS hold → wobble → resize grammar removal already moved to (ruling 2026-07-14). Sizes still render at rest; only the CONTROL hides. The coach line now teaches the hold ("Touch and hold a card to resize or rearrange") and retires on the first resize OR the first edit-mode entry.
- **The "Noticed" line returns — model-written, allowed to decline.** §36c removed the deterministic co-occurrence Insight for manufacturing connections and said a genuine model-written version would be "a fresh build, not a revival." This is it: `OnDeviceModel.homeInsight` runs the on-device model over the ~18 newest things and returns ONE cross-thing connection, or nil when it writes the single word NONE (the escape + a "never invent" rail are what keep §36c from recurring). Emitted as an `Insight` under the cover — fixed furniture, not a board module (no size pin, no remove badge). `HomeInsightStore` computes it OFF the render path and caches by a corpus+day signature, so a recompose storm never triggers a run, a device without Apple Intelligence shows no line (Home exactly as before), and a relaunch paints the last line instantly. A throwaway `LanguageModelSession` — never the composer's `ConversationModel`, so Home and Ask can't bleed.
- **Voice fix.** The pinned-mail tile header was "Waiting on you" — the exact phrase handoff-home's voice guardrail bans. Now "In your inbox": the card states what's there, not a duty.

DEVICE-VERIFIED 2026-07-17 (iPhone 17 Pro sim, iOS 26, FoundationModels available) — and the line's voice/quality/decline-rate needed real tuning, since the small on-device model's raw output over the demo corpus was mostly unusable. Three fixes, sampled with a new `-homeInsightProbe` hook (`RootShell` + `HomeInsightStore.debugProbe`; logs candidates, raw model text, and post-guard result):
- **Echo guard** (`FoundationAnswer.echoesACandidate`): the model frequently copied ONE candidate line back verbatim, serialization scaffolding and all ("Sent 51,521,504 VITALIK — Transaction, from Wallet, 12h" — the exact numbered-list format), and it showed on the screen. The guard treats a verbatim echo (a candidate's title, its whole serialized line, the "— kind, from source," metadata fragment, an app name like "the Wallet app", or 3+ bare titles = a pasted list) as a decline (nil), so a mechanical echo becomes "no line," never garbage.
- **Candidate window excludes the Wallet/Tokens firehose** (`HomeInsightStore.window`): 8 of the newest 18 things were transactions/watchlist links — high-volume auto-ingest with its own Home surfaces — and the model latched onto the spam-airdrop numbers. Dropping them (same firehose the away card now excludes) left the window for the meaningful saves; the line then reliably found the real thread (the Lisbon trip across ChatGPT + Calendar + a reminder).
- **Prompt sharpened**: ban single-item restatement, trivial same-kind/same-app groupings, third-person narration of people, and emitting app names / kind labels / timestamps; keep the NONE escape.
Post-tuning over the demo corpus (~8 samples): mostly a genuine grounded thread or an honest NONE; the residual weak case is an occasional third-person line ("Sam attended…"), prompt-only and left for a real-corpus pass. The pin's hold-to-reveal feel still wants a device (sim can't long-press-lift headlessly). `Model/HomeInsightStore.swift`, `Model/OnDeviceModel.swift` (homeInsight + `HomeNoticeLayout` + echo guard), `GenUI/HomeComposition.swift`, `Screens/HomeScreen.swift`.

## 117. Home is a tool, not a pinboard — auto-pin + invert the hierarchy (user, 2026-07-18) — DEVICE-VERIFIED 2026-07-17

The tension the user named: the app promises to help you stay on top of things, but a bento you arrange feels like a pinboard — good-looking, not powerful. A pinboard makes the PERSON do the triage (pin this, size that); a powerful tool does it for them, which is exactly what this app's ingest + on-device model can do. Two moves, ruled together (one makes the other work):

**Auto-pin (subtract, don't build from empty).** Every CONNECTED source is on Home by default — the person removes what they don't want, rather than figuring out what to add. Generalizes the Bluesky/Farcaster show-unless-hidden model to all sources: "connected" = has landed ≥1 thing (pinning still never invents content), the only control is hide. `HomePinnedSources.isOnHome`/`setOnHome` is the new primitive; the tile's "Remove from Home" and the shared `PinToHomeButton` (now an "On Home / Show on Home" toggle) both route through it. Removal HIDES (adds to `hidden`) instead of dropping an explicit pin, since the default is now shown. `appendPinnedApps` derives its set from the corpus (`Set(things.source)`), minus `You` (own captures — the cover leads with those), `Wallet` (its own treemap/NFT modules — a generic activity tile beside it is a redundant second wallet), and the media/graph sources that compose bespoke shelves. `appendMediaModules` follows the same gate (supersedes the magnitude-2 auto-earn / explicit-pin threshold; RSS auto-shows too now — the firehose worry is answered by one-tap removal, not an opt-in wall). On the map-redundancy the user waved off: right — if every source is a tile, a source-clustered map just repeats them, so the "By app" fallback map is RETIRED; the map is the intelligence's THEMES view (projects) only, absent until a theme forms.

**Invert the hierarchy — lead with what the app figured out, board drops below.** The synthesis head now reads: cover → **"While you were away"** (what LANDED since the last visit, bounded to `AppVisit`'s frozen away window — factual, non-obligation, not the daily-count noise §36k removed) → the Noticed thread (§116) → Coming up. Then a titled **"Keeping an eye on"** section demotes the board from the identity of Home to one section of it. Tiles-as-signals (first cut): every app tile's subtitle is its live "N new" since the last visit (bounded to the away gap, empty when quiet — honest), joining the Tokens tile's existing "N up · N down". The away card rides the shared `Insight` element, which grew an optional eyebrow (arg 1, defaults to "Noticed" — every existing caller unchanged).

FOLLOW-UPS (deliberately not done blind): (1) tiles-as-signals is only "N new" + tokens' movers so far — mail's "needs a reply", a wallet mover line, etc. each need per-source honest derivation, best done with a sim to verify the data shape; (2) the bespoke "Pin to Home" toggles on DealsScreen/ShopifyScreen and HandleSetupScreen's non-social pin still say "Pin to Home" (stale under auto-pin — functional, not dangerous); the shared `PinToHomeButton` and `BridgeDetailScreen` are already coherent. (3) A big auto-pinned board deepens the eager tree — watch the first-frame stack budget (CLAUDE.md) on a heavily-connected device.

DEVICE-VERIFIED 2026-07-17 (iPhone 17 Pro sim, `-awayGap`): the 10× cold-launch survival loop passed with the deeper auto-pinned tree (no first-frame stack regression); the away card, the "N new" tile subtitles ("On your calendar · 3 new", "In your inbox · 2 new"), the "Keeping an eye on" demotion, and the "In your inbox" voice fix all render. One signal-vs-noise fix the corpus exposed: with the raw away count, `-awayGap 24` read **"29 new — mostly from Wallet"** — the 134-transaction firehose the board deliberately subtracts, i.e. exactly the daily-count noise this card exists to avoid. `appendAway` now excludes the Wallet/Tokens firehose (`HomeComposition.firehoseSources`), so it reads **"12 new — mostly from Calendar and OpenClaw"** — the meaningful arrivals, consistent with the board's own exclusion and the §116 candidate window. The per-tile "N new" is unaffected (a source's own tile still counts its own arrivals). `GenUI/HomeComposition.swift`, `Screens/HomeScreen.swift`, `Model/HomePinnedSources.swift`, `Screens/PinToHomeButton.swift`, `GenUI/GenRenderer.swift` (Insight eyebrow).

## 118. Home: the intelligence is ONE card, pins above the fold (user, 2026-07-18)

Seeing §116/§117 on-device, the user's ruling: "coming up, noticed, keeping an eye on — all of this is very similar, we can't repeat things, and the stuff a user pinned is below the fold. Keep the intelligence to one card." §117 had stacked four look-alike synthesis cards (cover → While you were away → Noticed → Coming up → then the board), which both repeated content (Coming up ≈ the "On your calendar" tile; the away line named the same Calendar the tile shows) and pushed the person's own pinned board off the first screen — the opposite of §117's "pins shouldn't cost a scroll" intent.

Collapse (decided with the user, in three rounds): **the one blue intelligence card is ONE PARAGRAPH** — the cover hero and the two synthesis cards were all conveying "here's what's new / what the app noticed", so they became one card; and the card's first form (three eyebrow-and-line mini sections) was itself ruled too tall ("it hasn't earned that space") — the composition now JOINS just-landed + the away read + the model's connection into a single flowing paragraph under one "Noticed" eyebrow ("Just landed: Voice note. 9 new while you were away, mostly from Calendar and ChatGPT. Trip plan for Lisbon…"). Each sentence is skipped when it has nothing to say; the card is omitted when none do. ONE tap — the most specific door available: the thing the model's connection ran through (its picks, see below), else what just landed, else the feed (whose "New since" divider marks the away window); `Insight(text, eyebrow, openID, feedFallback)`, single-arg answer-doc callers unchanged. The **cover is just the date header + kind chips** (`GenCover` draws no hero card when its title is empty). The "Coming up" card is retired — dated events/reminders read off their own source tiles, the person's pick to keep the calendar as a tile rather than duplicate it up top. So the head is **date/chips header → one paragraph card → the board**, all above the fold. `appendAway`/`appendComingUp` deleted (the away read survives as `awayLine`); the `ComingUp` model + `GenComingUp` renderer stay (the `-comingUpProbe` still exercises the model, and the flat renderer is retained rather than re-derived if a dated lane returns).

Tiles-as-signals extended (same ruling): each pinned tile's subtitle is now its sharpest HONEST per-source read (`HomeComposition.tileSignal`), not just "N new" — Reminders/Todoist show "N overdue" (else "N due", off `dueAt`, never a done item; this recovers the overdue prominence the retired Coming-up card carried), Calendar/Cal.com/Calendly "N upcoming", Bluesky/Farcaster "N mentions" (off `socialContext`); everything else falls back to "N new". Never a guessed status — mail "needs a reply" is deliberately NOT built (unknowable from what's ingested); a wallet mover line is left for the treemap module, which has the price data.

DEVICE-VERIFIED 2026-07-17 (iPhone 17 Pro sim): the combined card renders — one card with "Just landed · Voice" / "While you were away · 10 new, mostly from Calendar and ChatGPT" / "Noticed · Trip plan for Lisbon…", then "Keeping an eye on" and "On your calendar · 2 upcoming" visible without scrolling. FOLLOW-UP: the "Keeping an eye on" header was named in the same complaint but kept for now (it separates the one card from the board); dropping it is a one-line change.

CRASH FIXED (2026-07-17, same session): heavy board scrolling intermittently hit `EXC_BAD_ACCESS` in `GenWidget.card` — the recurring deep-tree stack-overflow class. Crash-report anatomy (worth keeping): `KERN_PROTECTION_FAILURE` on a **stack guard region**, faulting thread 0 with only ~86 frames bottoming cleanly at `main` — NOT infinite recursion; ~86 SwiftUI/AttributeGraph frames (nested `AGGraphGetValue` → `update_attribute` → `PreferenceKey.reduce` cascades, each carrying huge generic view values, plus the opaque-type demangler) genuinely consumed the whole 8MB main stack, and `sp` landed inside the guard page. Root cause: auto-pin (§117) multiplied the board's `GenWidget` tiles inside the EAGER `MagazineLayout`, and every tile nested up to three ~12-level `GenRender → AnyView → component → mountIn` row subtrees. Fix per the standing rule ("flatten the composition tree, not more stack" — the GenComingUp remedy applied to GenWidget): `GenWidget.card` rows now dispatch FLAT on the child's component (`rowContent` — the same switch `soloContent` already used; a widget row is exactly Row/MailRow/PostRow/TokenChip, what `appChild` emits), no per-row GenRender/AnyView/mountIn. The card still mountIn()s as a unit, so entrance animates. Verified: 13 aggressive drag-scroll rounds over the full board (the trigger that crashed it twice before) with ZERO new crash reports, all four row forms rendering, plus the 10× cold-launch survival loop. `GenUI/GenRenderer.swift` (`GenWidget.rowContent`).

`GenUI/HomeComposition.swift` (`awayLine`, combined `Insight`, `tileSignal`, appendAway/appendComingUp removed), `GenUI/GenRenderer.swift` (`GenInsight` three sections, `GenWidget.rowContent`), `Screens/{Deals,Shopify,HandleSetup}Screen.swift` (pin controls → shared `PinToHomeButton`).

## 119. Home: the tool does the triage — signal order, doors, bounded board (2026-07-17)

Six moves in one pass, all DEVICE-VERIFIED same day (build + 10× cold-launch + probes + screenshots):

- **Signal-driven board order.** App tiles sort by their live signal, not alphabetically — overdue 5 > mentions 4 > due 3 > upcoming 2 > new/movers 1 > quiet 0 (`tileSignal` returns the rank with the text; name is the stable tiebreak). The person's own arrangement still WINS (HomeBoardOrder applies on top); ranking only decides where an un-arranged tile first lands. Measured: "On your list · 1 overdue" now leads the board in the hero slot.
- **Auto-span from signal.** A needs-you tile (rank ≥ 3, carried as the Widget's arg 4 so no localized-string parsing) opens WIDE; quiet tiles open small and pair 2-up; a stored size choice always wins. The spans are information doses — the doses assign themselves now.
- **The paragraph card is a door.** `HomeNoticeLayout` grew `picks` (the model's own indices for the things its connection runs across; validated, mapped to thing ids in `HomeInsightStore.pickedThingID`). The card's one tap opens the picked thing, else what just landed, else the feed. Measured: picks land reliably ("picks=7,10,11" → valid ids).
- **Third-person guard** (voice rail): a line whose FIRST WORD is a person's name (NLTagger `.personalName`) declines — the residual bad output narrated people by name and usually fabricated the action ("Sam and Alex are both in the same group" — measured caught). First word only: a name deeper in ("Dinner with Sam…") is the model correctly citing a thing.
- **Cover chips exclude the firehose.** "134 transactions" was the first number on the screen — a watched wallet's auto-ingest drowning the 7 links the person saved. Chips now count the non-firehose corpus (same exclusion as the away count and the Noticed window). NOTE: landing-time spam filtering already existed (`WalletIngest` skips received-not-held tokens + Alchemy isSpam NFTs; "sends are never spam") — the corpus was already clean; only the COUNT was noise.
- **The board is bounded.** Past `boardTileCap` (6) app tiles, the quiet tail collapses behind one "Show N more" line (`MoreTiles`, rendered below the board, sticky once tapped). Signal order guarantees the cap only hides the quietest tiles — the eager MagazineLayout's first frame stays bounded no matter how many sources connect (the §118 crash class's structural complement).

`GenUI/HomeComposition.swift`, `GenUI/GenRenderer.swift`, `Model/OnDeviceModel.swift`, `Model/HomeInsightStore.swift`, `Screens/HomeScreen.swift`.

Amended same day (user, two de-cute rulings): (1) **tile headers are the app's own name** — "'On your list' — shouldn't it just be called what it is, 'Reminders'?" The whole bespoke-phrase map died with it ("In your inbox" → Gmail, "On your calendar" → Calendar, "Watchlist" → Tokens, "Recent chats" → ChatGPT, …): a tile announces WHICH APP it is and the signal subtitle beside it carries the state; the phrases carried neither. (2) **the "Keeping an eye on" board header is gone** — "it just sounds trite; pinned to Home IS the point of the page." The board follows the one paragraph card directly. Both device-verified ("Reminders · 1 overdue", "Calendar · 2 upcoming", headerless board).

## 120. Home: one row per app (user, 2026-07-17)

The board's last bento residue named and killed. The user, looking at Reminders wearing three different costumes (a 1×1 solo tile showing one item full-size, a wide card of header + one row, a big card of three rows): "why is email a tile but reminders and calendar aren't… it doesn't make sense and still feels too cute." Ruled (picked over row-plus-signal-card and one-size-cards): **every app gets exactly ONE ROW** — icon · the app's name · its live signal · the thing the signal points at (the most-overdue reminder, the next event, the latest mention — `tileSignal` now returns the exemplar, not just the count) · its time. Tap opens that app's feed (`casberi://feed/source/…`, a route that already existed); long-press offers Open (the item) and Remove from Home. Rows are fixed furniture in signal order — not draggable, not resizable, not capped (a row costs one line, so §119's "Show N more" expander died the same day it shipped, along with the app-tile span logic, the solo-tile dispatch for apps, and `appChild`'s per-kind row forms — an app's richness lives in its feed). **Cards now exist ONLY for true visualizations**: the wallet treemap, the GitHub graph, the media strips — things a row genuinely can't carry. Also: the paragraph card's "Just landed" pick is firehose-excluded like every other aggregate read (it had led with "dogwifhat · $WIF" off a token-watch refresh). DEVICE-VERIFIED: six apps above the fold in signal order, Reminders · 1 overdue · Book dentist leading. `GenUI/HomeComposition.swift` (AppRow emit, tileSignal exemplar), `GenUI/GenRenderer.swift` (`GenAppRow`), `Screens/HomeScreen.swift`.

Amended same day (user: "WE NEED THE SPARKLINE"): the Tokens row keeps the one visual its card form carried — its second line is the LIVE chip for the top mover (ticker · on-device sparkline · price · 1D delta; `AppRowTokenLine`, the same keyed fetch/reveal GenTokenChip uses, sized to sit inside the row with no chrome of its own). Every other app's second line stays plain text. Device-verified: "Tokens / WIF ~ $1.50 · 0.0% · 1D" with the plot drawn and the flat delta wearing no color (honesty rule).

Second amendment (user: the 52pt inline plot "doesn't even fill the card"): the Tokens row is a proper watchlist row now — line 1 trailing is ticker · price · 1D delta, and the sparkline is a FULL-WIDTH strip (height 32) spanning the card's inner width beneath it, the same edge-to-edge plot the solo token tile drew, left-to-right reveal on data. The fetch lives on `GenAppRow` itself (keyed like GenTokenChip's; no-op for non-token rows).

## 121. Home: rows drag, visuals earn their space, doors sharpen (2026-07-17)

Follow-ups the row system exposed, all device-verified:
- **Rows are draggable again** (user: "what if someone wants to change their order?"). Signal order is only the default; a long-press lift reorders and persists via HomeBoardOrder, exactly as tiles did — app rows are board modules now (boardRefs + `app:<source>` keys). One size still: `allowedSpans(appRow) == [.wide]` — draggable for order, never resizable, never paired. The coach reworded to "Touch and hold to rearrange" (rows don't resize). Verified: Gmail dragged below Voice, order held.
- **Visual modules render only with real content** (honesty, the row pass applied to the last un-audited section):
  - The GitHub graph shows ONLY once a real year with contributions has landed (`GitHubGraphStore.year.total > 0`, gated in both compose and renderer). An all-empty 53-week grid was a skeleton, and — forced into the 150pt square `soloTileChrome` — a broken empty box ("doesn't even fit the screen"). It's now a tight WIDE STRIP (header + graph, content height, no resize), and in the demo (no real GitHub data) it simply doesn't appear.
  - Media shelves (music/Pinterest/screenshots) compose only over items that actually carry an image (`previewImageURL` or local `previewImageData`), and not at all when none do — the demo's grey placeholder "Screenshots" box is gone; a real device's imaged screenshots still show.
- **"Just landed" excludes calendar EVENTS** — "Just landed: Team standup" read as news about a merely-synced meeting; scheduled things belong to the Calendar row. Now "Just landed: Trip plan: Lisbon".
- **The item line is its own door** — tapping a row's title opens the thing; the rest of the row opens the app's feed (inner gesture wins the overlap).

`GenUI/GenRenderer.swift` (GenAppRow drag/door, GenGithubGraph strip+gate), `GenUI/HomeComposition.swift` (row boardRefs, media `imaged` gate, github data gate, landed excludes events), `Screens/HomeScreen.swift` (appRow spans, removal, coach).

## 122. Home: cut the last decoration, let urgency show, name the themes (2026-07-17)

A design pass over what remained. All device-verified.
- **Kind-count chips retired from the cover.** "6 events · 4 links · 4 reminders…" was a whole-corpus LIFETIME tally that only looked like signal — it never changed meaningfully, the feed filters by kind natively, and the board's rows carry the live signal now. Gone: the date is a clean single-line header straight into the intelligence card, and a row more fits above the fold. `coverChips` deleted; `GenCover.textBlock` draws only the quiet/empty message (else nothing).
- **A needs-you row signal wears PRIMARY ink.** Every row was identical monochrome, so "2 overdue" read like "2 new". Now a rank-≥3 signal (overdue/mentions/due, carried as `AppRow` arg 8) is primary; a merely-moving "N new" stays tertiary. The eye finds what needs it — honest (overdue really is more important), no new color.
- **The away line surfaces mentions.** A raw "22 new" is a volume; when mentions arrived in the window (`socialContext`), the line names them ("22 new while you were away, 3 mentioning you") — the one "someone's waiting on you" read honestly derivable from the arrivals.
- **The themes map is named "Themes"** (was the vague "What's going on") — it's the cross-app threads lens, a different thing from the per-app rows, and the plain name says so (matching the rows' own name-what-it-is).
- **Sparse/first-run audited** — the paragraph card shows only the sentences it has (one line when new), rows appear only for sources with content, empty visual modules don't render: a thin Home reads as calm, not broken. No change needed.

`GenUI/HomeComposition.swift`, `GenUI/GenRenderer.swift`.

Bug fixed same day (user: "Farcaster and Bluesky are rendering like tiles not rows"): `HomeScreen.spanOf` returned the person's STORED size without clamping it to the module's currently-allowed spans — so a Bluesky/Farcaster row still carrying a `.small` from its resizable-tile era paired 2-up at half width (the wrapped "Farcaster"). It now ignores an out-of-range stored size and falls back to the default, so any module whose allowed spans shrank under it (app rows → wide-only, the GitHub graph → one width) renders correctly. Verified by injecting stale `.small` sizes for two demo rows — both still render full-width.

## 123. The app catalogue joins the source strip (user, 2026-07-17)

The catalogue door moved OUT of the top-right cluster and INTO the head of the source chip strip (`SourceChips`) — its own `AppsDoor` grid glyph (attention state and store-zoom intact), as the FIXED first chip, ahead of Pinned/All and the source circles. Reasoning (user's): "add a source" belongs WITH your sources, not stranded next to the avatar; the strip already IS "your sources," so the catalogue is its natural head. Fixed outside the scroll so it stays in reach as the active chip re-centers (an action among filters, distinct as the tinted grid vs neutral source circles). The **avatar stays top-right, alone** — the two doors were on different axes (catalogue = grow my sources; avatar = me/settings), and splitting them lets the avatar be the sole, conventional "me" corner. `TopDoors` is the avatar only now. `Shell/SourceChips.swift`, `Shell/TopDoors.swift`, `Shell/MainSurface.swift`.

## 124. The Wallet feed carries the treemap AND the NFTs (user, 2026-07-18)

Amends §72's Home-only placement for the NFT strip. The Wallet chip's own feed now leads with the holdings treemap (already true) followed by the NFT strip, then the chronological transaction rows. Reasoning (user's): the wallet source's synthesis — what you hold, both fungible and NFT — belongs at the head of the wallet's own feed, not only on a pinned Home card. Scope is the **Wallet source feed only** (`shape == .wallet`), NOT the mixed "All" feed — the treemap/NFTs stay out of All (they aren't `Thing`s; §72's "a treemap cell / NFT strip is a door, not a thing" still holds — nothing lands in the corpus). Both render as gen-UI blocks (`WalletIngest.holdingsChart()` / `nftShelfDocument()` → `Stack` of `TagMap` / `MediaShelf`), painted into two independent `GenStream`s so a slow NFT read never delays the treemap. The feed shows EVERY watched wallet (not pinned-only, matching the treemap here); Home stays pinned-only via `pinnedNFTGroups`. Feed shelves carry no size pin / "Remove from Home" (arg 4 empty) — they're the source's art, not board modules. `Screens/FeedScreen.swift` (`nftBlockSection`, `streamBlock`), `Model/WalletIngest.swift` (`nftShelfDocument`).

## 124. Media sources become rows with a thumbnail filmstrip (user, 2026-07-18)

Debated and settled: a text row is a lossy translation of an image source, so Photos/Pinterest/Apple Music/RSS don't collapse to a text line — but they DON'T stay shelf-cards either (that broke Home's one-row rule and duplicated the source feed's grid). The synthesis, generalizing the Tokens-sparkline precedent into a PRINCIPLE: **every app is one row; its content PEEK renders in the source's native medium** — a text line for text sources, the sparkline for Tokens, a **thumbnail filmstrip (up to 4 recent, filling the row width)** for image sources. One uniform row anatomy, medium-native content; a card is never needed for an app.

Image sources now flow through `appendPinnedApps` like every other source (the `mediaSources` subtraction is gone); an image source's `RowSeed` carries up to 4 imaged things (`hasImage`: a remote preview URL or local thumbnail bytes), emitted as `MediaItem` children and referenced by `AppRow` arg 9. `GenAppRow` renders those as `GenMediaTile` thumbnails (the same component the NFT strip uses) when present, else the text peek — so a source with no real imagery (the demo's byteless screenshots) honestly falls back to text. `appendMediaModules`/`appendMediaShelf` and the media entries in `HomePinnedSources.moduleRef` are deleted (media keys `app:<source>` now, so removal clears the right saved state). DEVICE-VERIFIED with a live RSS feed: the RSS row shows real article hero images as a filmstrip; Photos falls back to text (no demo image bytes). `GenUI/HomeComposition.swift`, `GenUI/GenRenderer.swift` (`GenAppRow` filmstrip), `Model/HomePinnedSources.swift`.

## 125. Wallet becomes a Home row; treemap lives only on the wallet feed (user, 2026-07-18)

The last Home-side duplication closed. The wallet's holdings treemap composed on BOTH Home and the Wallet feed — and it was the final visualization breaking Home's one-row-per-app rule. Now Home carries a single **Wallet row**: the total value (`"$19,204"`, whole dollars — cents are feed precision) and the top holdings (`"ETH · AWETH · MATIC"`, parsed from the value-ordered treemap cells), tapping to `casberi://feed/source/Wallet` where the treemap, NFT strip, and transactions live. Loading/unreachable read as the row's own signal ("Loading…" / "Couldn't reach"), never a vanished slot. `appendWalletHoldings` emits the row (keyed `app:Wallet`, rank 0 — a balance is ambient, not needs-you); the per-wallet/combined `TagMap`s and the loading/error preview cards are gone from Home. `appendWalletNFTs` deleted (the NFT block already composes on the Wallet feed). DEVICE-VERIFIED (vitalik.eth): Home shows "Wallet · $19,204 · ETH · AWETH · MATIC"; the Wallet feed shows the treemap + NFTs + txns. Home is now UNIFORMLY rows (text / sparkline / filmstrip / wallet-total) + the Themes map — every source-level visualization lives in its feed. FOLLOW-UP (minor): HomeScreen still fetches `walletNFTs` for a Home block that no longer exists — a wasted call to drop. `GenUI/HomeComposition.swift`.

## 126. The wallet's own balance line — Home row AND Wallet feed (user, 2026-07-18)

Answers "should the wallet source feed show sparkline / balance line? do we have that data?" — yes: `WalletStore.ValueSample` already samples every real holdings fetch (`recordSample`, throttled to one per 4h), and `combinedValueSamples()` already merges every watched wallet into one honest net-worth line (forward-filled, starts only once every wallet has an aligned sample — no synthesizing). That data just had nowhere to draw until now. `TokenChart` gained `.from(closes:)` / `.from(samples:)` (`Model/TokenChart.swift`) to synthesize a chart from an already-sampled series — no fetch, reusing the exact `TokenChartPlot` renderer a token's sparkline draws.

Two draws off the one series: the **Home Wallet row** carries the balance history as its own full-width sparkline peek (`AppRow` arg 10, a comma-joined `closes` string embedded at compose time — `HomeComposition.appendWalletHoldings`; `GenAppRow`'s `walletChart` parses it, no live fetch since the data's already in hand), and the **Wallet feed** leads with a `Balance` lede (`WalletBalanceLede`, `Screens/ShapedRows.swift`) showing the live total, a "+13.5% · watched" delta pill, and the same chart at feed size (40pt vs the row's 32pt) — above the treemap, `Screens/FeedScreen.swift`. Both are empty (no crash, no stub) until two aligned samples exist, the same honesty floor the history itself already enforced.

Added `-seedWalletHistory "<usd,usd,…>"` (`Shell/ProbeHooks.swift`, declared after `-walletAddress` since hooks run in list-declaration order) — writes a synthetic `ValueSample` line spaced 4h+ apart so `recordSample`'s real throttle can't fold a headless test into one point; otherwise this class of feature only gains its second data point after 4 real hours of use. DEVICE-VERIFIED (`-walletAddress "vitalik.eth" -pinWallet YES -seedWalletHistory "17000,19260"`): the Home row draws a green upward line under "Wallet · $19,297"; the Wallet feed's Balance lede reads "$19296.65 · +13.5% · watched" with the same line at full width above the treemap.

## 127. Themes moves off Home, onto the "All" feed (user, 2026-07-18)

Answers "the themes treemap, should it go on all? and also is it too large? or is it same size as the wallet one" — the same split that already sent the wallet treemap to the Wallet feed (§125): a **cross-source** overview belongs on the **cross-source feed**, not on Home, which is now uniformly per-app rows. "All" is where every source's things already mix, so a themes-of-everything treemap orients that room the way the day's rows orient Home. On sizing: it's the literal same `TagMap` component the wallet treemap draws (`HomeComposition.themesDocument`, mirroring `WalletIngest.holdingsChart`'s doc shape) — so "too large on Home" was really "the one card that never earned a place on a rows-only screen," and off the board it just takes the renderer's own unconstrained size, identical to the wallet treemap's.

`HomeComposition.daily` no longer composes `map`/`TagMapPreview` at all — the real Themes emission, the sparse-corpus starter preview (`appendStarterPreviews`, `isSparse`, `previewMapLine`), and the empty-state's preview map are all deleted; `HomeComposition.empty` is now just the hero. `FeedScreen.themesLedeSection` composes the same document fresh off `visible` (already the surfaced, unfiltered corpus when `source == "All"` and `filter.tag == "All"` — the only case it's shown, ahead of `bundledSections`) via `GenParser.parse(prefix:isComplete:)`, the same synchronous-render pattern `WalletScreen` already uses; a tap opens `ProjectDetailScreen` through a new `FeedScreen.ProjectRoute`/`openProject`, mirroring Home's own project door. DEVICE-VERIFIED: All now leads with the Themes grid (health/ideas/work/life/travel/Work cells from the demo corpus); tapping "health" pushes its detail screen and back returns cleanly; Home has no Themes card anywhere in its scroll.

Cleanup riding along: `HomeScreen.allowedSpans` dropped the dead `walletMap*`/`walletCombined`/`map` branch (those refs haven't existed since §125/this section) and now locks the Wallet row to `.wide` like every app row (`ref == "walletRow"` — it was falling through to the resizable-tile default, the same stale-span bug class §119 fixed for Bluesky/Farcaster). `HomeScreen.moduleRemoval`'s wobble-mode minus badge gained a dedicated `walletRow` case — it had NO working removal control after §125 (its old `walletMap*`/`nftShelf*` cases matched refs that no longer compose, and the generic `AppRow` fallback didn't recognize `walletRow`'s name), so tapping "Remove from Home" on the Wallet row silently did nothing; fixed in both the wobble badge (`moduleRemoval`) and the row's own context menu (`GenAppRow`, `GenUI/GenRenderer.swift`) to unpin every watched wallet. DEVICE-VERIFIED: wobble mode now shows a minus badge on the Wallet row; tapping it unpins the wallet and the row disappears on "Done". The dead per-wallet "Show on Home"/"On Home · remove" NFT-strip control on the Wallet screen (`nftHomeControl`, a casualty of the same rewrite — Home hasn't shown per-wallet NFT strips since §125) and its backing `WalletStore.nftStripHidden`/`setNFTStrip`/`WalletIngest.pinnedNFTGroups` are deleted; `walletNFTs` — the wasted Home fetch flagged as a follow-up in §125 — is dropped from `HomeScreen` and the `HomeComposition.compose`/`daily` signatures. `GenUI/HomeComposition.swift`, `Screens/HomeScreen.swift`, `Screens/FeedScreen.swift`, `Screens/WalletScreen.swift`, `Model/WalletStore.swift`, `Model/WalletIngest.swift`.

## 128. The Wallet FEED scopes to one wallet — a switcher (user, 2026-07-18)

Answers "how does a wallet feed work with more than one wallet — separate or combined? have we thought about it?" The answer was already "combined stream, per-row wallet tags, plus a per-wallet + `All wallets` decomposition" (§72/§125/§126) — but there was no way to say "show me just this wallet." Ruling: a switcher scopes the WHOLE Wallet FEED (`casberi://feed/source/Wallet`, the surface the Home Wallet row opens, §125), not just the activity list — a rows-only filter is incoherent (the combined balance headline still reads across all wallets while the rows below show one), and tapping a wallet should mean "show me this wallet," full stop. Placement is the FEED specifically (user, correcting a first cut that landed it on the `WalletScreen` management screen — that switcher was reverted): the feed is the wallet's consumption surface; the management screen is for add/remove/pin.

`FeedScreen` gains `selectedWallet: String?` (nil = All), meaningful only on the Wallet page (each `FeedScreen` owns one source). A chip strip leads the `case .wallet` sections — `All` then one chip per watched wallet, each wearing its `WalletFace` and, when selected, its `WalletFace.tint` (fill-only selection — the design law draws no lines). Only shown with more than one wallet watched. All four wallet pieces read the scope: the **balance lede** swaps `combinedValueSamples()` → `valueSamples(forAddress:)`; the **holdings treemap** and **NFT strip** pass the scope to `WalletIngest.holdingsChart(scopeTo:)` / `nftShelfDocument(scopeTo:)`, which filter their `HoldingsGroup`/`NFTGroup` results by address AFTER the fetch (never before — every wallet's value history still samples via `topHoldingsByWallet`'s `recordSample` side effect regardless of what's shown); the **transaction rows** gain `walletScopeAllows` in the `visible` filter. `.onChange(of: selectedWallet)` re-paints the two gen-UI streams; the rows and lede re-derive from state. Selection returns to All when the selected wallet is removed or the list drops to one.

Match logic: `Thing.walletAddress` equals the stored `WatchedAddress.address` byte-for-byte (the `watch()` UI resolves ENS/`.sol` to hex before `add()`, and `WalletIngest.resolvedAddresses` returns an already-hex/base58 address UNCHANGED), so ENS wallets "just work" — the sketch's feared ENS/hex gap does not exist. Comparison is hex-case-insensitive (EIP-55 case is a checksum) but base58-exact (Solana case IS identity) — `WalletIngest.scopeMatch` for the group filters, `walletSameAddress`/`walletScopeAllows` in `FeedScreen`, mirroring `WalletStore.dedupeKey`. NOTE: the `-walletAddress` DEBUG hook calls `add()` with the RAW string, so `-walletAddress "vitalik.eth"` stores a NAME (bypassing resolution) — seed with HEX to test the production path.

VERIFIED 2026-07-18 (iPhone 17 Pro sim, two hex wallets — vitalik `0xd8dA…6045` + Binance-14 `0x28C6…1d60`, framebuffer via `simctl io`): the Wallet feed renders the chip strip `All · 0xd8dA…6045 · 0x28C6…1d60` (resolved ENS avatars) below the source header, above the Balance lede ($405M combined) and the per-wallet treemaps. The scoped-after-tap state wasn't captured (the Mac locked mid-run); the tap→scope path mirrors the management-screen switcher that WAS device-verified end-to-end before the revert, and the build is green. `Screens/FeedScreen.swift` (`walletSwitcherSection`/`walletSwitcherChip`, `selectedWallet`, `walletScopeAllows`/`walletSameAddress`/`walletChipIsOn`, scoped `walletBalanceLedeSection`/`streamBlock`), `Model/WalletIngest.swift` (`holdingsChart(scopeTo:)`/`nftShelfDocument(scopeTo:)`/`scopeMatch`).

## 129. Full ink — the source feeds and thing sheets drop the brand-hue wash (user, 2026-07-18) — VERIFIED

Answers "on the source feeds we have a bloom of color… the app would feel more utile if they were just ink." The per-source brand-hue wash — the bold field that flooded the top of every source feed (Calendar → red, §B "bold like Cash App", 2026-07-13) and poured down the crown of every thing sheet ("it's gorgeous", 2026-07-10) — is **retired for full ink.** The reasoning, weighed against keeping it: the hue is the SOURCE's brand color (`AppIconTile.washHue`), not Casberi's — so the app wore a different company's skin on every screen, **borrowed identity, not owned.** On a browsing surface that's decoration competing with the content stream (the chip already names the source), and hues like Calendar's red collide with the alert/loss meaning red carries elsewhere (the wallet). It was also the inverse of the Cash-App boldness it reasoned from — Cash App is bold in ONE color that's *theirs*, consistently; this was bold in a *borrowed* color per screen.

The thing sheet was a genuine judgment call (a deliberate, occasional focus view, not chrome you pass through — where atmosphere is most defensible), decided the same way for consistency: one owned surface, ink everywhere, color only where it's information. The on-device screenshot settled it — the sheet wash wasn't the "atmosphere under content, no ink depends on it" the comment claimed; it flooded the whole spec table and muddied the When/From/Tags labels. Ink made them legible again. (The stage sheets' "seam recipe" — landing signed amounts on near-ink — was the design already conceding the wash had to duck below the data; ink is just that endpoint everywhere.)

Identity now lives where it's information: the source glyph in the chip strip and the row, the tag's own stable hue, the content's own imagery (mosaics, treemaps). **Removed:** `MainSurface.shapeWash` (the feed's resting field) + `FeedScreen.switchFlood` (the on-switch sweep, and its dead `flood` state/animation) + `ThingSheetView`'s wash and "pour" open animation (and dead `washPoured`/`reduceMotion`). `SourceChips`' active ring is always tint now (it went white only to cut against the hue field). **Kept** (the "connect this app" surfaces, where a source IS the subject, not a browsing/detail view for the person's own things): the first-thing connect bloom (once ever per source, on first landing), the app-detail page, the bridge-setup header, the token quick sheet — all still read `washHue`. VERIFIED 2026-07-18 (iPhone 17 Pro sim, `simctl io`): Calendar feed (light + dark) and the Flight-to-Lisbon thing sheet render pure ink, the red surviving only in the Calendar glyph; both builds green. `Shell/MainSurface.swift`, `Screens/FeedScreen.swift`, `Shell/SourceChips.swift`, `Screens/ThingSheetView.swift`, `Design/AppIconTile.swift` (doc).

## 130. Home rows: one image, inline sparklines — no full-width bands (user, 2026-07-18) — VERIFIED

Answers "the media feeds… should only have one image per row" and "just one photo, one album." Every visual an app row carried had grown into a **full-width band stacked below its header** — the token/wallet sparkline (§121/§126, "the sparkline FILLS the card") and the media filmstrip (§124, up to four tiles at 76pt). A few connected sources turned Home into a column of billboards. This amends §121/§124/§126: a row's visual is a **small trailing DETAIL**, not a band, so every row holds one peek height and Home reads as a calm uniform stack.

- **Media sources → one thumbnail** (was a 4-tile filmstrip). `HomeComposition` keeps `prefix(1)` of the newest imaged thing; the renderer draws it as a single 56pt square in the trailing slot. Photos shows its latest photo, Apple Music one album, Pinterest one pin — the source's medium as a peek, not a spread. No "+3" (user: "we don't need +3 either").
- **Token / Wallet sparklines → inline 48×24, trailing** (were 32pt full-width). The Tokens row becomes a watchlist line: ticker · 1D delta on the SUBTITLE, sparkline + price trailing. The Wallet row keeps its total on the header signal, holdings on the subtitle, the balance sparkline trailing. The pre-load skeleton and left-to-right reveal mask are gone (a 48pt inline chart doesn't need them); the chart just fades in when it lands.

VERIFIED 2026-07-18 (iPhone 17 Pro sim, `simctl io` + computer-use scroll): Photos renders one trailing thumbnail; Tokens reads "WETH · −0.1% 1D" with an inline sparkline beside "$2611.56"; Wallet reads "$395,702,962 / ETH · ZKC · ESP" with a green inline sparkline — all peek-height, no bands; build green. `GenUI/GenRenderer.swift` (GenAppRow), `GenUI/HomeComposition.swift`.

RENAME NAMES THE TAG; "PROJECT" IS GONE (2026-07-19, user: "get rid of project user shouldn't see that word… shouldn't be able to rename a title"): tightening the tag vocabulary so one object (a tag) doesn't wear two confusing verbs. (1) "Rename" now always names its object at every ENTRY POINT — the thing-sheet chip menu reads "Rename tag everywhere…" (was "Rename everywhere…"), the tag-detail toolbar reads "Rename tag" (was a bare "Rename" leaning on a hidden a11y label, now dropped), and the composer proposal card reads "Rename tag X to Y — N things" (was "Rename X to Y…"). Bare "Rename" survives only as the CONFIRM button inside an alert whose title already quotes the tag ("Rename \"Trip\" everywhere"), so it's never ambiguous. (2) The person never sees the word "project" — it was already absent from visible copy (the 2026-07-07 leak fix), confirmed here; code identifiers (ProjectDetailScreen, projectTag, ProjectHue) stay invisible per the line-449 ruling. (3) A thing's TITLE is not user-renameable and stays that way — every Thing.title write is an ingest/system path (LinkTitle, RSS, Shopify, ScheduleIngest) or the wallet counterparty "Name this address" flow (untouched by ruling — "don't mess w wallets"); "Name" (titles, wallet-scoped) and "Rename tag" (tags) are two words for two objects, deliberately. Files: OrganizeCommand.swift, ProjectDetailScreen.swift, ThingSheetView.swift, Localizable.xcstrings. NOT sim-verified (edited in a Linux session with no Xcode) — string-only changes, no structural edits.

## 131. The Pinned board is dismantled; the agent's kept asks are the only per-app glance surface (docs/agent-brief.md rulings 11–12, executed 2026-07-20) — VERIFIED

Executes the two rulings the agent-shell brief added on top of its main settlement: the board dies (§11) and "Pin to Home" retires as a concept everywhere, not just on Home (§12). The agent (kept-ask chips, rise/lower bar, the Stack) was built and verified end-to-end first, so the app was never left with neither surface — the board only came down once its replacement was live.

A fresh inventory at execution time found the brief's own checklist had drifted from the real code in two structural ways worth recording (so the NEXT drift doesn't repeat the same wrong assumptions): (1) `Screens/HomeScreen.swift` couldn't be deleted outright — it also defined `HomeRoute`, the whole app's shared navigation-route singleton (Apps push, Settings push, bridge push, tag/offer open), consumed app-wide and wholly unrelated to the board. It was extracted verbatim into its own `Shell/HomeRoute.swift` first, then the rest of the file died safely. (2) "Pin to Home" was bigger than the board: `HomePinnedSources` was called from ~9 non-board screens' bridge-disconnect teardown, `HandleSetupScreen`'s auto-social pin/hide logic, and a `RootShell` rename migration — none of that is "board code," it's "pinning code," and §12 already said pinning retires everywhere. The actually-consistent execution deleted `HomePinnedSources` itself (not just Home's use of it), which was larger in scope than the brief's original "~23 call sites" estimate (24 real `PinToHomeButton` sites, plus the separate non-`PinToHomeButton` teardown/migration call sites above).

**Deleted outright:** `Screens/HomeScreen.swift`, `Design/BoardDragDriver.swift`, `Design/ReorderableBoard.swift`, `Model/HomeBoardOrder.swift`, `Model/HomeModuleSize.swift`, `Model/HomePinnedSources.swift`, `Screens/PinToHomeButton.swift`, `Design/HomeBackgroundStore.swift` (the Home wallpaper/Banner-tray feature — its UI lived inside `Screens/AccountScreen.swift`: the `settingsWash` page tint, the "Background" settings tile, and the whole `HomeCoverSheet` swatch/photo picker, all removed from that file alongside it). `WalletStore.WatchedAddress.pinnedToHome` (field + swipe toggle + the three `WalletIngest` filters) is gone — resolved per §12's "needs to be able to ask for either": `WalletScreen`'s combined portfolio and per-address rows already aggregated over every watched wallet unconditionally, so nothing replaces the deleted filter.

**Trimmed, not deleted:** `GenUI/HomeComposition.swift` keeps the enum, `Cluster`, `sourceClusters`, `projectClusters`, and `themesDocument` — live, non-board dependencies of the "All" feed's Themes treemap (§127) and `MCPTools`' week-synthesis tool; only the board's own composer (`compose`/`daily`, `appendPinnedApps`, `appendWalletHoldings`, `cover`, `boardSources`, `awayLine`) is gone. `GenUI/GenRenderer.swift` lost `GenAppRow` and `GenCover` (board-only renderers, confirmed via grep no surviving doc emits `AppRow(`/`Cover(`) but kept `GenWidget`/`genSpan`/`ModuleSpan` — still live under the general-purpose `Widget(...)` doc emission used by kept-ask composers, `ProjectDetailScreen`, and MCP grounding; `ModuleSpan` (the span enum only, not the deleted `HomeModuleSize` persistence class) had to be restored in `GenRenderer.swift` after the first build pass, since `genSpan`'s environment key still structurally depends on the type even though nothing ever supplies a non-nil value anymore.

**Also retired as a casualty of the board's own eager-head performance fix** (found live-dead during this pass, not in the original brief): the standalone "Coming up" card (`GenComingUp` in `GenRenderer.swift`, `Model/ComingUp.swift`, the `-comingUpProbe` hook) was a Home-only, board-eager-head renderer with no surviving emitter once `HomeComposition`'s board composer was gone — confirmed via grep that nothing constructs a `ComingUp(...)` doc line anymore, so the whole feature (model + renderer + probe) was dead weight, not merely stale, and was deleted rather than left as an unreachable code path.

**Routing collapse:** every `"Pinned"` string literal in `RootShell.swift`/`MainSurface.swift`/`SourceChips.swift` became `"All"` (or was deleted where it named a board-only branch, e.g. `MainSurface.showingBoard`). `casberi://home` still resolves, now to the All feed. `HandleSetupScreen`'s post-connect CTA — a genuinely separate control from `PinToHomeButton` — became "See in Feed", routing to that source's own feed instead of a board that no longer exists.

VERIFIED 2026-07-20 (iPhone 17 Pro sim, `simctl io`): cold launch opens directly on the All feed (Themes card, "Yesterday"/"Today" rows, no Pinned chip); `casberi://home` lands on the same All feed; `-openComposer YES` still rises the full agent surface with kept-ask tiles ("Tag your 243 Wallet things", "How's my wallet?") — confirming the agent shell survived the landing-path rewrite untouched. Grep sweep for `HomePinnedSources`/`HomeBoardOrder`/`HomeModuleSize`/`PinToHomeButton`/`pinnedToHome`/`BoardDragDriver`/`ReorderableBoard`/`showingBoard`/`HomeBackgroundStore` across `Casberi/Casberi` and `Casberi/Shared` returns zero hits. Build green (`xcodebuild … build` succeeds with zero errors). Files: see agent-brief.md rulings 11–12 for the full call-site inventory; this entry is the "as executed" record.

## 132. Kept-ask decay-dim finished; wallet/watchlist answers gain their real visualization (docs/agent-brief.md rulings 5/13, 2026-07-20) — VERIFIED

Two gaps found once the board's dismantling settled and the agent became the app's only per-app glance surface: ruling 5's "ignored asks decay dim (AskMemory's counters)" had shipped only its first half (the changed-dot), and the "wallet"/"watchlist" kept-ask composers answered in text only, even though both already have a real GenUI visualization elsewhere in the app (the Wallet feed's holdings treemap, the free-text watchlist answer's `TokenChip` rows) that the kept-ask path simply wasn't reusing.

**Decay-dim (ruling 5).** `KeptAskStore`'s kept-ask pills already rendered as B1 chips with a changed-dot (shipped this session, prior entry) but never touched `AskMemory` — the neglect counter only ever bumped for the empty-composer suggestion tiles. Fixed by reusing the exact same counters for kept asks: `Shell/Composer.swift`'s `.task(id: isOpen)` now calls `AskMemory.shown(KeptAskStore.shared.order)` once per open, mirroring `computeSuggestions()`'s own call; `keptAskPills` computes `neglected = !changed && AskMemory.neglected(kind)` and applies `.opacity(0.55)` when true; the pill's tap handler now also calls `AskMemory.tapped(kind)`, resetting the counter the same way tapping a suggestion tile does. No double-counting is possible: `computeSuggestions()` already excludes any kept kind from the suggestion list, so a given memory key's counter only ever moves from the kept-pill side or the suggestion-tile side, never both. A changed pill never dims — a fresh signal overrides neglect, regardless of tap history.

**Wallet visualization.** `KeptAskComposers.wallet()` previously emitted a single `Insight(...)` line from `WalletAsk.answer()` and nothing else. Now also calls `WalletIngest.topHoldingsByWallet()` and draws each wallet's holdings as a `TagMap` (the identical idiom `WalletIngest.holdingsChart()` draws on the Wallet feed — label, subline, top-5 cells), via a new shared `KeptAskComposers.walletDoc(line:groups:)`. `RootShell.answerDocument`'s free-text `WalletAsk.matches` branch — previously ALSO text-only via `proseDoc(line)` — now calls the same `walletDoc` builder, so a typed "how's my wallet" and the kept "How's my wallet?" chip render identically. The digest stays the summary line alone (unchanged) — the honest signal for "did the answer change" was already correct, only the doc needed the treemap added.

**Watchlist visualization.** `KeptAskComposers.watchlist()` previously emitted `Insight(...)` only. `RootShell.answerDocument`'s free-text `TokensAsk.matches` branch already drew `Widget("Watchlist", count, [TokenChip rows])` — the kept-ask composer just hadn't caught up. Unified via a new shared `KeptAskComposers.watchlistDoc(line:moves:)` (same 6-shown cap, same `TokenChart.route` guard against a dangling ref), called from both places. Fixed a latent bug found in the process: the original kept-ask `watchlist()` had no guard for `moves.isEmpty` (watched tokens whose price fetches all failed) — it would have composed `TokensAsk.line([])`, which formats to the broken string "Over the last 24h: ." — now mirrors the free-text path's honest "Couldn't read your watchlist's prices right now" fallback.

Scope held deliberately narrow: no new GenUI component was added (no per-token sparkline chart inside the agent, no chart for the wallet's balance-history line) — only existing `TagMap`/`TokenChip` components got a second call site. Asks with no backing visualization (away, overdue, showtag, noticed) are unchanged.

VERIFIED 2026-07-20 (iPhone 17 Pro sim, `simctl io` + `-uiAnswerProbe`/`-keepAskProbe`/`-askStats` hooks): "How's my wallet?" through the real UI answer path rendered "$20K across your wallets, +1.5% since Jul 19." followed by the live per-wallet treemap (`0xd8dA…6045 · $20K across 11 tokens`, cells ETH/AWETH/MATIC/RUSSEL/WBTC) — confirming both the summary and the treemap resolve end-to-end. Decay-dim confirmed with a deterministic kind (`overdue`, digest "0", immune to the wallet path's live-price nondeterminism): seeding `AskMemory` to the neglect threshold and marking the ask's digest already-seen rendered the pill visibly faded (no dot, muted text) against the same pill's bright/bold rendering beforehand. Build green throughout. Files: `Model/KeptAskComposers.swift` (`walletDoc`/`watchlistDoc`), `Shell/RootShell.swift` (wallet/watchlist free-text branches), `Shell/Composer.swift` (`keptAskPills`, the `.task(id: isOpen)` `AskMemory.shown` call).

## 133. The chip vocabulary widens — parameterized kinds, kept searches, proactive minting (docs/agent-brief.md ruling 14, 2026-07-20) — VERIFIED

Answers "more chips, not just the preset ones" — the kept-ask system (rulings 1/4/5) shipped with only four keepable shapes (`wallet`, `watchlist`, `away`, `showtag:<top tag>`) and a hardcoded ~7-kind suggestion menu, both narrower than ruling 1's promise that "chips are kept asks... a saved question plus a deterministic composer." Two composers already written (`overdue`, `noticed`) were never offered or keepable at all. Three widening mechanisms, all still inside the no-model-in-the-kept-path guarantee:

**Foundational — the retriever is now shared.** `RootShell.retrieve(_:in:)` was a `private func` on the `RootShell` View, so `KeptAskComposers` couldn't re-run it. Extracted verbatim (no logic changes) into a standalone `Model/Retriever.swift` (`Retriever.rank(_:in:isPoolRefinement:)`); `RootShell.retrieve` now just resolves the corpus (pool, or a fresh newest-2000 fetch) and forwards to `Retriever.rank`. Confirmed on-device: a probe for "recipes" still found "Meal prep for the week" via the semantic pass post-extraction, matching pre-extraction behavior.

**Move 1 — parameterized kinds.** `context:<Source>` ("What's new in GitHub?") is a real kept kind now — `KeptAskComposers.contextRecap` filters to that source over a 3-day window (widening to a week when quiet, mirroring `StatusAsk`'s own no-timeframe default), recognized in `Composer.recognizeKeptAskKind` by matching "what's new in \<source\>" against the corpus's real source set. `overdue`'s existing composer is now both offered as a suggestion tile (gated on a real overdue Reminders/Todoist item existing) and typed-recognizable ("what's overdue"). `noticed` is tile-only by design — there's no natural typed trigger for a spontaneous connection, so it was deliberately left out of `recognizeKeptAskKind`. `showtag` now offers the top TWO tags instead of one. The suggestion grid still caps at 4 tiles (3 with the organize hint) — widening the candidate pool means more real signals compete for those slots, not a bigger grid.

**Move 2 — kept searches (the headline unlock).** Any free-text ask that actually retrieved something becomes keepable as `search:<query>`, re-running `Retriever.rank` deterministically — never re-synthesizing the original prose. This is the locked, non-negotiable contract: a kept "summarize my week" shows what the summary was drawn from, the same honest-degradation principle ruling 1 already required elsewhere. `recognizeKeptAskKind`'s fallback explicitly excludes anything `TagsAsk`/`AppsAsk`/`AggregateAsk`/`StatusAsk` would answer first — those give a COMPUTED line in the real free-text path (an arithmetic count, a status pulse), not retrieval rows, so letting them mint a `search:` kind would make the kept re-run silently disagree with what the person actually saw asking it live. A real bug was caught and fixed during this build: the composer's digest was first designed as `"<count>|<newest-id>"` for finer change-detection, but `Composer.keptAskPills` renders a kept ask's `digest` VERBATIM as its own trailing signal text — so the raw UUID leaked onto screen. Fixed to a bare count (`"\(hits.count)"`), matching `showtag`/`contextRecap`/`overdue`'s existing digest shape exactly (an accepted, pre-existing limitation shared by every count-only composer: a same-count reshuffle of which things match goes undetected).

**Move 3 — proactive minting.** `AskMemory` gained the neglect counter's inverse: `asked(_:)`/`askedOften(_:)` (`AskMemory.mintThreshold` = 3), bumped once per settled, keepable ask in `Composer.commit()`. Crossing the threshold upgrades the answer's quiet "Keep" pill to "✦ You ask this a lot — keep it?" — same `Chip` component, same tap action, just a label that names why.

**Debug tooling fixed in passing:** `KeptAskStore.seedFromLaunchArgs` (the `-keepAskProbe` hook) split on the FIRST colon, silently truncating any compound kind (`showtag:X`, `context:X`) and swallowing the rest into the title — hit twice while testing this exact work. Fixed to split on the LAST colon (a real title never ends in ": word"). New DEBUG hook `-asksMade "<key>:<n>[,…]|clear"` seeds the minting counter headlessly, mirroring `-askStats`'s shape.

VERIFIED 2026-07-20 (iPhone 17 Pro sim): `-keepAskProbe "context:Calendar:What's new in Calendar?"` kept and re-ran the pill reading "What's new in Calendar? · 6"; typing "What's new in Calendar?" through the real UI answer path showed a Keep pill (a nonexistent source, "GitHub", correctly showed none — the recognizer only fires for a source the corpus actually has). Typing "design links" retrieved a real hit ("Design review", a Calendar event) and offered Keep; kept and reopened, the pill read "design links · 1" with no model activity in the device log during the re-run (only a routine OS-level `SensitiveContentAnalysisML` init, unrelated) and near-instant resolution (vs. the multi-second waits every model-backed answer in this session took). Proactive minting: seeding `-asksMade "wallet:3"` then asking "How's my wallet?" upgraded the pill to "✦ You ask this a lot — keep it?", alongside the still-working wallet treemap from §132. Build green throughout every step. Files: `Model/Retriever.swift` (new), `Model/KeptAskComposers.swift` (`contextRecap`, `search`), `Model/AskMemory.swift` (`asked`/`askedOften`/`seedMadeFromLaunchArgs`), `Model/KeptAskStore.swift` (colon-split fix), `Shell/Composer.swift` (`recognizeKeptAskKind`, `computeSuggestions`, the Keep pill's upgrade), `Shell/RootShell.swift` (`retrieve` now forwards to `Retriever.rank`).

## 134. Onboarding teaches three steps, not four (user, 2026-07-20)

The "How it works" onboarding screen (`Screens/HowItWorksSheet.swift`) drops from four numbered steps to three, because the app changed under it (the §131 agent-shell redesign): **Connect your apps** (the old "Open the catalog" + "Connect things" folded into one — the catalog is WHERE you connect, not its own act; the step keeps the catalog's real grid glyph and the settled icon strip), **One feed, or one app** (the chip header), **Ask anything** (the agent's "Ask your things" bar, wearing sparkles). Rationale: a step count is a cost — four steps where the first two describe one motion (open the door, connect) taxed the reader for no extra understanding. Rain, entrance, CTA, and the `-howItWorksCTA` hook are unchanged; only the `points` array and its numerals moved.

## 135. The Wallet split — manage is the connection, the feed is the wallet (user, 2026-07-20)

Answers "there are so many wallet features in the wallet management screen but isn't that supposed to be for just the app connection? it's really confusing what is supposed to be where." It was: `WalletScreen` carried warnings, the combined value bundle, the per-wallet rows AND a recent-transactions list, while per-wallet holdings/DeFi/safety lived in `WalletDetailScreen` and the Feed independently rendered the value chart and the same treemap — the same content in three places, with no rule saying which surface owned what. The rule now:

**Manage answers one question — what am I watching, and how.** `WalletScreen` keeps Watching (identity rows + their door to per-wallet detail), Add a wallet, Chains, and Disconnect. It fits on one screen, and it reads like every other bridge's connection screen. Warnings, the value bundle, and Recent are GONE from it.

**The feed carries the reads.** The Wallet feed leads with two tiles side by side — **Balance** (value + sparkline + the honest "watched" delta pill) and **Worth a look** (the warnings roll-up) — then the holdings treemap, then a **DeFi** tile (Aave collateral/debt/health, promoted from the detail page: the treemap says what you HOLD, only this says what you OWE), then the transactions.

**Five, then a door.** The stream previews five rows and hands off to a new `WalletHistoryScreen` ("See all transactions · N"), day-grouped, scoped to whatever wallet the switcher was on. The `caughtUpFooter` is suppressed on the Wallet shape for the same reason Reminders already suppresses it — a "that's everything · 131 transactions" line under five rows is a flat lie; the See-all row is the honest close.

**Rulings that came out of the mockup rounds, recorded because they generalize:**
- **Data never wears decorative color — only its own.** The holdings treemap's cells carry no assigned palette (already true since §39's ruling; re-affirmed) and name the token by SYMBOL, no redundant name. Semantic ink (a real green delta, the one warning glyph) keeps its seat; chrome gets none.
- **A tile summarizes by count and kind, never by detail.** "Worth a look" shows "3 items / 3 delegations", not one warning's address — a `0x…` in a 150pt tile is detail belonging to the page behind the tap. `WalletWarning.Kind` exists to make that summary honest.
- **Side-by-side tiles are equal height.** Two tiles in a row sizing to their own content read as broken.
- **Glass covers pinned control bars, not just the composer.** Amends the design-law line to: Liquid Glass on the floating layer only — *including pinned control bars* (the feed's neutral source chips + catalogue/avatar doors, the wallet switcher). A source chip wearing a real app icon stays opaque: an icon IS content. Content still never wears glass.

Implementation: `Model/WalletWarnings.swift` (new — the roll-up lifted out of the view, so any surface reads one list), `Screens/WalletFeedTiles.swift` (new — flat by the §gotchas eager-head law), `Screens/WalletHistoryScreen.swift` (new), plus edits to `FeedScreen`, `WalletScreen`, `SourceChips`, `BridgeRouting` (`.walletHistory(scope:)`). VERIFIED 2026-07-20 (iPhone 17 Pro sim): tiles/treemap/preview/See-all all render, the door opens the day-grouped history, manage is one screen, `verify.sh` green with 10/10 cold-launch survival (the eager-head risk this change ran straight at), perf flat at 455ms launch / 328MB. The DeFi tile's render path is the one piece unexercised on-device — the demo wallets return "no Aave positions found", which is the tile's own honest-absence case.

## 136. Glass needs something to refract (2026-07-20)

A correction to §135's own glass pass, found by asking where else Liquid Glass belonged and discovering the answer was "nowhere new — fix what's there." The shell was a `VStack` (chip strip above, feed pager below), so nothing ever passed *behind* the chips; what sat behind them was `DS.themedPage`, a flat color. Glass blurring a flat color is a slightly tinted solid — visually indistinguishable from the `DS.gray100` fill it replaced, while paying a backdrop blur per chip. The wallet switcher had the same defect for a different reason: built as a List section, it scrolled *with* content rather than over it.

**The structural fix.** `MainSurface` now hangs the strip off the feed pager with `safeAreaInset(edge: .top)` instead of stacking it above. The resting layout is unchanged (the inset reserves exactly the height the VStack row did — rows still start below the chips), but scrolled content now travels underneath, which is the only thing that makes the material read as glass. Verified on device: at rest the screen is pixel-identical; scrolled, rows dissolve under the strip, and in light mode the chips read as translucent rather than solid.

**`dsSoftTopEdge()` is the other half, and was nearly unspent.** iOS 26's scroll edge effect (already tokenised in `Design/Glass.swift`, applied on exactly two screens) dissolves content at a scroll view's top edge so it melts under chrome instead of colliding with it. Now applied to all 32 pushed screens that paint `dsPageBackground()`. Deliberately NOT applied to the two sheets (`CombinedWalletsSheet`, `HowItWorksSheet`) — a sheet has no status-bar edge to melt under, which is the specific gap this closes.

**The rule that generalizes: glass is a relationship, not a finish.** Before adding the material anywhere, ask what moves behind it. If the answer is "a flat color," the glass is decoration with a GPU bill, and a solid fill is the honest choice.

**Standing exclusions, re-affirmed while surveying:** the open composer bubble never takes glass (prd 44 put it on the content and the bubble vanished on a glitched morph; prd 52's veneer got hoisted above the content and frosted it — both on real devices; it is solid ink permanently). Trays and sheets stay opaque, as Apple's own do. Content — cards, rows, treemap cells — never wears it. A source chip showing a real app icon stays opaque: an icon IS content, and frosting a mark someone recognizes only muddies it. Toolbar buttons, the `searchable` field, and the back chip need nothing: iOS 26 already glasses them, and hand-rolling ours would fight the convention.

VERIFIED 2026-07-20 (iPhone 17 Pro sim): verify.sh green with 10/10 cold-launch survival (a shell layout change earns that loop), perf flat at 460ms launch / 330MB — the added blur costs nothing measurable. Files: `Shell/MainSurface.swift` (the inset), plus `.dsSoftTopEdge()` across 32 screens.

## 137. The wallet doors keep their promises; manage loses its last reads (user, 2026-07-20)

The §135 split shipped with three debts, all found by walking their taps: every feed tile's door pushed the MANAGE screen (which no longer shows warnings — a door to the wrong room); the wallet switcher scrolled away with the very stream it scopes; and manage still leaked reads — the Watching rows wore value sublines and sparklines, and the per-wallet page opened with a holdings treemap (user: "I can see vitalik's holdings — that is so confusing; the manage screen should only be about connecting wallets and disconnecting them").

**Doors.** The Worth-a-look tile opens a `DSTray` listing the actual items — a flagged transfer opens its own sheet, a Safe or delegation warning opens the owning wallet's screen (new route `.walletDetail(id:)`), a liquidation row states chain + health factor and carries no chevron (acting on Aave happens on Aave). `WalletWarning` grew an `address` (the person's own spelling, mapped back from the resolved hex — resolved ONE target at a time, because `resolvedAddresses` skips failures and a zipped batch would mis-pair every owner after one). The Balance tile's door now exists only where a breakdown exists (multi-wallet "All" → the combined sheet); scoped or single-wallet it drops the chevron and the tap. The DeFi tile drops its door entirely — collateral/debt/health IS the whole in-app read.

**The switcher pins.** Out of the List, onto `safeAreaInset(edge: .top)` under the shell's chip strip — §136's own rule applied to itself: a scoping control has to stay reachable when you're deep in the transactions it scopes, and its glass finally has the stream moving underneath.

**Manage is plumbing, fully this time.** Watching rows are identity only (face, name, address, chevron); `WalletDetailScreen` drops its holdings treemap, value/gas subline, sparkline, and DeFi section — what remains is rename, Safety (approvals door, delegation, Safe queue — where the tray's doors land), and remove.

**The bug the purge exposed — recorded because the failure mode generalizes:** the §135 block cuts had accidentally deleted `WalletScreen.sync()`, and the `sync()` call left in onAppear KEPT COMPILING by resolving to POSIX `sync(2)` — two green builds were flushing disk buffers instead of reading chains, landing nothing and never registering the seat, with no diagnostic. Restored slim (land + honest status line + seat registration; the old body's warning/portfolio fan-out lives in `WalletWatch.liveState` now). Lesson: when deleting a member whose name shadows a libc symbol (`sync`, `write`, `close`, `open`, `send`…), grep for remaining callers — the compiler will not save you.

VERIFIED 2026-07-20 (iPhone 17 Pro sim, end to end): tile → tray (three delegation rows) → door → vitalik.eth's slimmed page (identity + Safety + remove, nothing else); switcher stays pinned with the treemap dissolving under it; manage shows identity rows and the restored sync's "Connected — watching for activity" line. verify.sh green (cold-launch survival gated), perf flat at 459ms / 329MB.

## 138. Worth-a-look rows are terminal; the see-all door is one phrase (user, 2026-07-20)

Same-day correction to §137, from two screenshots: the see-all row scattered blue text, a gray count, and a chevron across the full row width over a visible List separator ("this looks like crap"), and the Worth-a-look tray's rows deferred to the wallet screen, whose only added value was a Revoke.cash button ("you can't have worth a look pull up a sheet that then says to go look somewhere else").

**Tray rows are TERMINAL now.** Each states the whole fact; where one real action exists it sits on the row itself — a flagged transfer opens its sheet, a delegation row carries "Revoke.cash ↗" directly (the exact URL the wallet screen's Approvals row opens, minus the detour). Safe and liquidation rows carry no control: signing happens in the Safe app, acting on Aave happens on Aave, and the row already says everything this app can honestly say. The `.walletDetail` route died with its only consumer — the manage stack is reached from manage alone now.

**The see-all door is one centered phrase** — "See all 131 transactions" — in the app's own terminal-action grammar ("Stop watching this wallet", "Disconnect Wallet"), separator hidden (the no-lines law; List hands out separators by default and every new row must opt out — second time this same miss shipped in one day, WalletHistoryScreen was the first).

The principle §137 half-stated, now in full: **a door must open onto the thing itself — never onto another door.** Tile → list → act. If a surface's only content is a button to somewhere else, delete the surface and put the button where the person already is.

VERIFIED 2026-07-20 (iPhone 17 Pro sim): tray shows three delegation rows each with inline Revoke.cash ↗; see-all renders as one centered phrase, no line. verify.sh green (10/10 survival), perf flat 457ms / 329MB.

## 139. Manage is one page, no doors — the per-wallet screen is deleted (user, 2026-07-20)

The last cut of the day's wallet arc (user: "the manage screen should really be one page with no doors"). `WalletDetailScreen` — already slimmed to rename + Safety + remove by §137, already half-orphaned when §138 made the tray terminal — is deleted outright, because each of its jobs had a better home that isn't a page:

- **Remove** was always on the row's swipe (and Edit mode).
- **Rename** is the row's own tap again — an alert, not a door; exactly what the tap was before the 07-20 collapse briefly made it a push. The row's chevron dies with the page it promised, and the footer names both verbs ("Tap a wallet to rename it, swipe to remove it").
- **The safety facts** were already the Worth-a-look tray's rows whenever they're true — every delegation and every pending Safe queue IS a warning there, with the Revoke.cash action inline (§138). A page restating them neutrally held nothing the feed doesn't state better.

Manage is now literally one page: identity rows (tap renames, swipe removes), Connect/paste, Chains (an inline disclosure, not a door), the honest status line, Disconnect. The wallet's whole surface count drops to five: feed, tray, combined sheet, history, manage. §137's "doors" section is superseded where it routed to the wallet screen — the ledger stands, this entry rules.

VERIFIED 2026-07-20 (iPhone 17 Pro sim): row tap opens the rename alert over the one page; chains still expands inline; verify.sh green (10/10 survival), perf flat 457ms / 329MB.

## 140. Manage becomes three cards; the crown feature gets a name (user, 2026-07-20)

The manage screen, even after §139's door purge, still read as "a bunch of stuff mashed together" — seven vertical zones wearing four visual idioms at equal weight: a labeled card, loose footer prose, a full-width blue CTA slab, a field-in-a-card, another labeled card, a full-width green status card, a red row, more prose. Nothing outranked anything.

**Three cards, one idiom.** Watching (identity rows), Add a wallet (the paste field leading — universal, covers ENS/.sol/hardware wallets — with "Connect a wallet app" as a quiet row in the SAME card rather than a competing blue slab), and one admin card holding Chains (unchanged inline disclosure) + Disconnect (its exact keep-or-purge dialog, now inlined rather than via the shared `BridgeDisconnectSection` component, since a Section IS the card and the shared component wanted its own). One footer under the admin card states the read-only promise; the rename/remove hint under Watching shrinks to five words.

**Status whispers; only trouble shouts.** The green "Connected — watching for activity" card is gone. Sync state now rides Watching's own header as trailing text ("Synced just now") — the same voice the feed's source chip already speaks. A real status ROW returns only for an error or the typo'd-address nudge (`resultProminent`), which is also the ONLY state that still needs the reader's eyes. Fine is silent — a lesson that generalizes past this screen: a full-width colored card announcing normal operation is noise dressed as news.

**The empty state keeps its own weights.** With nothing watched, Connect leads at full prominence (the fast-path ruling from 2026-07-16 stands) and the pre-connect footer explains both paths — the reweighting is a CONNECTED-screen move, not a universal one.

**The crown feature gets a name (user: "the combined wallet state is our best feature").** The Balance tile's caption reads "Across your wallets" when it's showing the combined multi-wallet number, "Balance" when scoped — so the app's actual differentiator (no wallet app does this) carries its name in the view people see daily, instead of an anonymous tile whose door was the only way to learn what it was.

**The see-all door lost its slab, twice-corrected** (user, back to back: "this still looks bad" / "still looks bad"). It was a List row wearing `dsListCardRow()` — full card treatment for a single line of blue text, reading as a stray bar. Now a quiet inline door on the page itself: smaller type (`callout15`, matching the section labels around it), a trailing chevron instead of a lone number, no card surface — a continuation of the stream above it, not another surface competing with it.

**Verification note, since this round hit a real false alarm:** the first `verify.sh` run after this change failed cold-launch survival at cycle 8 (froze, no first frame in 15s) and perf spiked to 3272ms/24767ms. A same-code re-run reproduced the freeze at cycle 1. Bisected by stashing the diff and running the identical HEAD~1 code — it ALSO froze under `LAUNCH_CYCLES=10`, which ruled out this change as the cause; a `simctl shutdown`+`boot` (clearing ~70 cumulative install/cold-launch cycles' worth of simulator state from one long session) let HEAD~1 pass 4/4 clean, and the restored diff then passed 10/10 with perf back to 437ms. Lesson for future long sessions: a mid-session survival-loop failure is not automatically a code regression — check whether the SIMULATOR has degraded (reboot it) before assuming the diff broke launch, especially after dozens of manual installs in one sitting.

VERIFIED 2026-07-20 (iPhone 17 Pro sim, post-reboot): manage renders as three cards with the whisper header; see-all renders as one inline door; the feed's Balance tile reads "Across your wallets" on the combined view. verify.sh green (10/10 survival); perf 437ms / 329MB, matching the pre-this-round baseline.

## 141. The wallet feed streams in; it doesn't pop (user, 2026-07-20)

The Wallet feed's head is four reads on four different clocks: the Balance tile draws from already-recorded local samples (instant), while warnings, the holdings treemap, and DeFi wait on live chain reads that land seconds later. Unstyled, that truth rendered as a bug — "balance shows then the others pop in but looks unintentional." The reads' timing is honest and stays; what changed is that each arrival now LOOKS intended:

- **Every head block wears `RowEntrance`** — the exact rise (`dy:16`, the wallet `entranceStyle`) every transaction row below already uses, so a late tile arrives in the shape's own established motion vocabulary rather than a silent insert. Balance and warnings at index 0 (side by side, one beat), the treemap at 1, DeFi at 2 — the stagger mirrors the order the reads actually tend to land.
- **The two async landing sites animate their state sets** (`withAnimation(DS.Motion.standard)` around `walletLive = state` and `blockStream.paint`). The modifier carries each tile's own reveal; the animation carries the LAYOUT — the balance tile visibly slides over to make room as the warnings tile rises in beside it, and rows below glide down for the treemap instead of jumping.

The division of labor matters and is the reusable lesson: **an entrance modifier without an animated insert still snaps the container; an animated insert without an entrance still pops the content.** Streaming-in = both, or neither reads as intentional.

Frame-verified 2026-07-20 (15fps extraction from a cold-launch recording straight into the Wallet feed): balance renders alone full-width; ~4.3s later a captured mid-tween frame shows it mid-shrink with the warnings tile semi-transparent and offset below its seat, settling side-by-side the next frame — the arrival is a motion, not a cut. DeFi's own entrance is unexercised on-device (demo wallets hold no Aave positions — its honest-absence case) but wears the identical modifier. verify.sh green (10/10 survival — this touched the eager feed head), perf flat 435ms / 328MB.

## 142. Wallet polish round — and the bug the polish recording caught (user, 2026-07-20)

"Really polish what is already there — surprise and delight and elegance." Four moves, all motion and material, nothing structural, each in vocabulary the app already speaks:

- **Numbers roll like an odometer.** The balance wears `contentTransition(.numericText(value:))` — a scope switch rolls $20K to the new reading in the direction the money differs, saying "same instrument, re-keyed" where a swap says nothing. The Worth-a-look count and the DeFi stats roll with it (plain `.numericText()`), so the head moves in one voice. Already the app's grammar (GenKindBar's legend counts). Reduce Motion → `.identity`.
- **The sparkline draws itself.** A leading-edge mask sweeps 0→1 over 0.8s on arrival — the line draws the way the value accrued. A scope switch resets and redraws (a new line deserves its own draw). Reduce Motion → drawn instantly. The endpoint stays pulse-free (the prd §ruling: pulsing overclaims on a fetch-once surface).
- **The switcher selection travels.** One tinted capsule slides chip-to-chip via `matchedGeometryEffect`, re-tinting to the landing wallet's own hue mid-flight — the source chips' own 2026-07-14 ruling ("selection is an object traveling, not two states blinking") applied to the wallet switcher. Unselected chips keep a static faint fill beneath it.
- **The warning glyph beats once.** `symbolEffect(.bounce, options: .nonRepeating)` fired 0.6s after the tile lands — punctuation after the entrance settles, never a loop. System vocabulary; honors Reduce Motion natively.

**The bug the verification recording caught — this is why polish rounds record themselves.** Frame-stepping the scope-switch capture showed vitalik.eth's scoped feed reading "Nothing from Wallet yet" over a corpus holding that wallet's own transactions. Root cause: `WalletIngest.refresh` resolves the watched list before reading, so every landed thing's `walletAddress` is the RESOLVED hex ("0xd8dA…6045") — while the feed's scope is the WATCHED spelling ("vitalik.eth"). `walletScopeAllows` compared them raw, so **every ENS- and SNS-watched wallet's scoped feed had been permanently empty since prd §128 shipped** — and the history page's scope filter and the row-label lookup carried the same mismatch (the label's doc comment even documented it as an accepted degradation: "no label then, never a wrong one" — fine for a label, not for a filter that empties the screen).

Fix: `WalletStore` gains a persisted resolution cache (watched → resolved), fed by `resolvedAddresses` itself — the one place both forms meet, and it runs on every refresh, so the cache exists before any landed thing does. `scopeMatches(stored:scope:)` matches raw first (hex-watched wallets), then through the cache; the feed filter, history filter, AND `label(forAddress:)` all route through it. Verified on-device: scoped to vitalik.eth now shows his transactions, the see-all door carries the scoped count (127 vs 131 all), and "vitalik.eth" labels appear on rows for the first time.

verify.sh green (10/10 survival), perf flat 478ms / 329MB. The polish itself is frame-verified: a captured mid-flight frame shows the selection capsule between chips; the draw-on and roll ride standard system transitions.

## 143. The app catalog surprise-&-delight pass (user: "how can we surprise and delight in the app catalog?" → "do it all", 2026-07-21)

A delight pass over the Apps catalog, sibling to §79's Wallet pass —
everything honest (a moment only ever marks something real), deterministic,
and off under Reduce Motion. Nine items, all riding existing machinery so no
new design law is needed. Ships:

- **Shelf completed.** When a category's LAST addable app connects, its shelf
  header glows once in the category's own color (`landFlash` gained a `tint:`)
  and a toast names the set — "Work — all connected." Only a real set (≥2
  connectable offers) earns it; a lone-app category completing is trivial.
- **Connect-count milestones.** Crossing 5 / 10 / 25 connected seats flashes a
  quiet "N apps connected." — the catalog's sibling of §36v's "N things
  banked." Persisted (`apps.connectMilestone.reached`), seeded to the highest
  passed threshold on appear so arriving past one never fires late.
  First-connect keeps its berry rain; these are toast-only.
- **Connected rows roll their number.** A tier-2 subline ("3 games in") is now
  drawn through `CountUpText` so the proof counts up rather than sitting — the
  same grammar the setup-screen result wears.
- **Promote-lift on connect.** The just-connected row scales + shadows as the
  shelf re-sorts it into its connected seat (`connectPromote`, the §11 pin-lift
  reused). Keyed on the name delta from `connectedNames`, so every connect path
  (one-tap AND setup-screen) drives it identically.
- **Corpus-aware Discover seats (`CatalogTaste`).** Adjacency already reads as
  the store knowing your SETUP ("Goes with GitHub"); this reads what's in your
  CORPUS and suggests the bridge that keeps more of it — many links → Readwise
  (or RSS if Readwise is taken), many screenshots → Photos, many chats →
  Claude/ChatGPT, etc. Every eyebrow is a real count (≥5 of a kind) over a
  plain fetch, counted in memory (the §36v rule: enums never enter a
  `#Predicate`). Silent when the corpus is too thin to read.
- **"Just added" seats.** `Offer` gained an `added: Date?`; an offer inside the
  week earns a Discover seat eyebrowed "Just added". This is what makes "New"
  HONEST again where the 2026-07-16 reason-or-no-seat rule retired it as an
  assertion — a date is computable and ages itself out. Stamped on the genuine
  2026-07-17 additions (Peer, Bitrefill, 1Claw).
- **Haptics on the deal.** The Discover deck's card commit fires a selection
  tick — dealing a card now reads like dealing (§36v: haptics finish motion).
- **Glyph parallax mid-drag.** The ghost brand glyph on the front card drifts a
  touch against `dragX` for cheap depth as the card is pulled (the deck already
  owns that state, so no extra re-render).
- **Helpful no-match search.** A website-looking query ("something.com", or a
  word like "newsletter"/"substack") with no app match now offers RSS — "RSS
  can follow most sites." — with the real addable row inline, turning a dead
  end into a connect path.

Files: `Design/MicroMotion.swift` (tint on `LandFlash`, new `ConnectPromote`),
`Model/BridgeCatalog.swift` (`added`/`isNew`), `Model/CatalogTaste.swift` (new),
`Screens/AppsScreen.swift`. catalog-sync stays green (no name changes). NOT yet
verified on-sim — this session is the Linux web env with no xcodebuild; build +
screen-sweep to run on the Mac before the checkpoint.

## 144. Source chips learn the front; landing carries over (user: "how do we solve the problem? ... them wanting Wallet to be the default", 2026-07-21)

User's complaint: recency-only chip order means a source you actually live in
still drifts back the moment anything else lands, and there was no way to make
a chip your default. Explored alternatives together (keep-at-front, drag
reorder, a management tray, a landing-only setting, App Shortcuts) before the
user flagged the two problems keep-at-front doesn't solve — it does nothing
for "All" being the fixed landing, and a hand-picked front set gets messy fast
(what happens with five kept chips?) — and asked for the zero-UI shape
instead.

Ruling: **two independent, zero-new-chrome behaviors**, no kept set, no
management surface, nothing to configure.

- **Landing carries over.** `FeedFilter.source` (`Model/FeedFilter.swift`) now
  persists to UserDefaults on every write and reads it back in its own
  `init()`. RootShell's launch `onAppear` no longer hardcodes it to `"All"` —
  this amends §131's "content-first, always" to "content-first, wherever you
  left it": persisting on every change (not just at background) means
  whatever `source` held when the process died IS what's on disk, no
  lifecycle hook required. A fresh install has nothing persisted yet and
  still opens on "All" — the default is unchanged, only the override is new.
- **The strip learns.** `Model/ChipMemory.swift` (new, same shape as
  `AskMemory`): each real chip switch bumps a per-source visit counter,
  decaying by half every week of neglect. `MainSurface.chipLabels` sorts by
  this weight first, falling back to the untouched most-recent-first order on
  a tie (`Array.sorted` is stable since Swift 5) — a source you actually use
  anchors ahead of the recency tail; everything you've never tapped keeps
  sorting exactly as it did before. "All" is excluded from counting — it's
  the baseline every session starts from, not a chip competing for a slot.

Deliberately NOT built: a kept/pinned front set (the mess the user flagged
directly — an edit surface with a cap, order, and add/remove verbs for a
five-item list), drag-to-reorder on the strip (the same three-way gesture
arbitration class `BoardDragDriver` retired paid for three lessons on, for a
capability tap-learning already gives for free), and a settings picker (the
persisted-landing behavior gives the same outcome without a control to find).

Probes: `-landingChip <source>|clear` seeds the persisted landing directly
(without navigating the seeding launch, so a two-launch run — seed, relaunch
plain — verifies the next-launch landing); `-chipStats "<source:n[,…]>"|clear`
seeds the tap-learning counters, and every `MainSurface` mount NSLogs
`chipLabels:` with the computed order, so a promotion verifies in one launch.

Files: `Model/FeedFilter.swift`, `Model/ChipMemory.swift` (new),
`Shell/MainSurface.swift`, `Shell/RootShell.swift`. NOT yet verified on-sim —
this session is the Linux remote environment with no Xcode toolchain at all
(no `xcodebuild`, no `xcrun`, no `swiftc`); build + `scripts/verify.sh` +
the two probes above need to run on the Mac before this ships to TestFlight.

## 145. The wallet answer shows what the wallets DID, not just what they hold (user, 2026-07-21)

User, off a screenshot of the "How's my wallet?" answer: "it's all it says and
it's really not that great. You would expect it to tell me about approvals or
anything else that's in the wallet." The answer was the §132 shape — value
line + holdings treemap — which reads as a balance check, not a wallet brief.

Ruling: the shared `KeptAskComposers.walletDoc` (both the kept chip and the
typed ask, per agent-brief ruling 13) now appends two corpus-backed sections
under the treemap:

- **Token approvals** — the newest 3 approval/Permit2 things the §84 pass
  landed (`wallet:approval:`/`wallet:permit2:` refs). Each row opens the
  thing sheet, which already carries the §112 prepare card and the
  Revoke.cash door — so the answer surfaces the security read the user
  expected without walletDoc re-reading any chain state.
- **Latest activity** — the newest 4 other Wallet/Peer things (transfers,
  swaps, Solana moves, Peer fills), the same rows the feed shows.

Both are reads over things the wallet bridges already landed — no new
network, still deterministic, still no model (ruling 1 intact). A section
with nothing simply doesn't render. The unreachable-wallet branch now uses
the same builder, so a failed live read still shows the local sections under
the honest "Couldn't reach" line. `rows()` gained widget/row id parameters
(defaults keep every single-widget caller byte-identical) so one doc can
stack two widgets without id collisions.

Files: `Model/KeptAskComposers.swift`, `Shell/RootShell.swift`. NOT yet
verified on-sim — this session is the Linux web env with no xcodebuild;
build + `-answerProbe "how's my wallet"` (with `-approvalProbe <blocksBack>`
first to land an approval) to run on the Mac before the checkpoint.

## 146. More generative UI in the composer answers — five chart types (user: "how can we add more generative UI to the composer? Charts and things like that", → "do all these", 2026-07-21)

The agent's answers spoke almost entirely in `Insight` + `Widget`/`Row`, with
`TokenChip` and the holdings `TagMap` the only real visuals. This pass adds
five answer-column components, each drawing a REAL visualization the answer
already had the data for (agent-brief ruling 13 — never invents one), all
deterministic (no model in any composer, ruling 1 intact), and each gating
itself out when the data is thin so a sparse corpus degrades to exactly the
old shape. New views + renderer cases in `GenUI/GenRenderer.swift`; composers
in `Model/KeptAskComposers.swift` (+ the shared free-text paths in
`Shell/RootShell.swift`, so kept and typed answers never disagree).

- **ValueSpark(eyebrow, subline, csv)** — the wallet balance sparkline over
  recorded `WalletStore.ValueSample` history, reusing `TokenChartPlot` so the
  value line wears the exact anatomy a token curve does. The delta pill is
  computed first→last, the same math `WalletAsk.answer()`'s line uses. Inline
  series (not a pointer like TokenChip) because samples are LOCAL facts already
  read — the honest thing is to draw what was recorded. Fewer than two points
  emits nothing (a dot isn't a trend).
- **Bars(eyebrow, subline, counts, labels)** — per-day capture counts over the
  last week, hand-drawn as capsules (no axis/grid — the hairline law holds on
  charts). Wired into the per-source and per-category recaps ("What's new in
  GitHub?"); dropped under four items (a two-item week is a list, not a chart).
- **ChartCard(symbol, chain, address)** — a single token's FULL scrubbable
  curve, reusing `TokenChartView` (its press-then-drag scrub already coexists
  with a scroll view). The watchlist ask emits it when exactly one mover is
  shown; two or more keep the compact TokenChip list.
- **StatRow(v0,l0,v1,l1,v2,l2)** — up to three glanceable number tiles, neutral
  ink (a bare count has no up/down direction to color, honesty §83). The wallet
  answer leads with **Approvals / This week / Tokens** — the approvals count is
  what the user asked to see, at a glance above the detail rows.
- **AllocBar(eyebrow, "label|usd,…")** — how the total splits across watched
  wallets, one segmented bar, monochrome by the one-tint law (DS.tint stepped
  down in opacity, never a rainbow). Only meaningful with two+ wallets.

Also wired the EXISTING shaped rows into answers (they rendered at top level
but weren't dispatched as Widget children): `GenWidget.rowContent` now also
handles **TxRow** (a wallet transfer draws its asset mark + direction + amount,
from `transferDirection`/`transferAmount`/`transferCounterparty`) and
**AgendaRow** (an overdue task draws on the time rail, most-overdue leading).
`ApprovalCard` was deliberately NOT used for the wallet approvals section — its
Approve/Deny pills would be dead controls (honesty: Casberi never signs), so
approvals keep the plain Row whose sheet carries the real prepare card.

The enriched wallet answer, top to bottom when rich: line → balance sparkline →
Approvals/This week/Tokens strip → holdings treemap → per-wallet split → token
approvals → latest activity (transfers as TxRows). An unreachable live read
still shows every LOCAL section under the honest "Couldn't reach" line.

Files: `GenUI/GenRenderer.swift` (five views + cases, two rowContent cases),
`Model/KeptAskComposers.swift`, `Shell/RootShell.swift`. catalog-sync
unaffected (no catalog changes). NOT yet verified on-sim — this session is the
Linux web env with no xcodebuild; build + `-answerProbe`/`-uiAnswerProbe` over
"how's my wallet", "how's my watchlist", "what's new in <source>" and an
overdue corpus to run on the Mac before the checkpoint.

## 147. Day-cards: a day's rows share one card (user: "would look better if … items in a day are all on one card" → "do it all", 2026-07-21)

The feed's rows each wore their own floating card (surfaceSheet fill + the
ambient card shadow, s2 gaps), so a busy day read as a confetti of same-sized
shadowed rectangles and the day structure lived only in the s6 gap above each
header. Ruled: rows within a day now MERGE into one card — the day becomes the
object the eye reads, the way §61's section lift already renders the ~16
setup/import screens ("gapless same-color rows, only the section's silhouette
casts"). This supersedes the 2026-07-13 gap-only clustering note ("without
merging cards") — the header gap stays; the card now agrees with it.

Mechanics (`Screens/FeedScreen.swift`):

- **RunPosition** (only/first/middle/last) computed per section by
  `cardRunPositions` — index-based, so All's FeedRow bundles and plain Thing
  arrays share one derivation. `dayCardBackground` renders it: first/last rows
  carry `UnevenRoundedRectangle` shoulders at the card radius plus the s1
  breathing edge; middle rows run square and gapless so per-row shadows vanish
  on the neighbouring same-color fill (§61's measured mechanic, now on the
  plain list). Content insets unchanged — the rhythm inside the card equals
  the old between-card rhythm.
- **Rhythm-breakers stay free-standing** (`standsAlone`): the approval consent
  card (the one rhythm-breaker everywhere, unchanged ruling), the social
  PostCard (media at width — cards-in-cards would violate §8, so the social
  room keeps individual cards entirely), the chat TakeawayCard, and the fat
  TokenRow. A run breaks around them.
- **The new-since seam splits the day card in two** — the divider capsule
  renders between two closed card edges, making "since you left" a physical
  seam, not just a floating label.
- Applied everywhere rows render: daySection (all shaped rooms + Doing/Done/
  Needs you/Waiting on you), All's bundledSections (bundle rows merge too),
  the token watchlist's flat section (one run; pulsed tokens stand alone
  anyway), and Reminders' To do section — where the "Older" collapsed toggle
  (previously a flat full-bleed band) now closes the card as its last row,
  and expanding it continues the same surface.

NOT yet verified on-sim — this session is the Linux web env with no
xcodebuild; build + a screen sweep (All with bundles + a breaker, a social
room, Reminders with stale todos, a day split by the new-since divider, light
and dark) to run on the Mac before the checkpoint.

## 148. Source feeds diverge by their source's nature — grain, "new", the pile, liveness (user: "what else would you do to improve source feeds? ... think how they differ" → "do all these", 2026-07-21)

Day-cards (§147) quietly assumed every source shares one rhythm. They don't —
a source feed should read the way that source actually behaves. Four axes,
each a self-contained change in `Screens/FeedScreen.swift` (+ `ShapedRows.swift`
for one lede). No schema, no ingest, no catalog changes.

1. **Cadence → adaptive grain.** A day is the right cluster for dense feeds,
   but a sparse source (one Safari save a day, a wallet approval a week) became
   a ladder of one-row day cards under big headers — §147's confetti, re-shaped
   as headers. `chronoGroups` coarsens to "This week / Last week / <month>"
   when the trailing history averages under ~1.5 things a day over ≥6 days;
   above that it's a no-op, so every chronological source (`gmail`, `agent`,
   `safari`, `bitrefill`, `oneclaw`, the plain default, and the sparse tail of
   `social`/`notes`/`chat`) routes through it safely. Music instead uses
   `sessionGroups` — plays <45 min apart are one sitting ("This morning",
   "Yesterday evening"), music's real unit; a colliding label gets its start
   clock appended so the section ForEach ids stay unique.

2. **What "new" means.** The new-since seam was a bare "New since Friday". Now
   it names what's new: a count for most feeds ("New since Friday · 4"), and
   for Wallet — whose rows are SCANNED, not read — the FLOW instead ("2 in, 1
   out since Friday"), the question a wallet answers. Counts run over the frozen
   `visible`; the divider renders once, so it reads it a single time.
   DEFERRED: Calendar "changed since you looked" — an event that MOVED is
   currently invisible, the one real honesty gap here, but surfacing it needs
   per-event previous-start state (Thing tracks neither an ingest timestamp nor
   a prior value), i.e. a schema field + ingest diff. Not shipped as an untested
   change to a core sync from the Linux web env; it's a new-field-plus-backfill
   job for a session that can build and measure it.

3. **Read-in-place vs hand-off.** A post/note is consumed in the feed; a Safari
   save is a DOOR, and doors pile up. The `.safari` shape earns a `ReadingLede`
   — "12 saved this month · 41 older" and the oldest one still waiting — naming
   the pile instead of pretending the rows are read. Honesty: it says "still
   here", never "unopened" (Thing tracks no read state), and it's facts, not a
   count-shaming streak (§10). It yields to an auto hero so no shape stacks two
   overviews.

4. **Liveness.** The Live dot rode rows wherever they fell chronologically, but
   a Twitch stream on RIGHT NOW is the one row whose relevance isn't time.
   `liveFirst` floats live rows to the top of the newest group in the source's
   own room — scoped to Twitch (the one source with a live set) and the first
   group only, a no-op everywhere else.

Recorded rulings so a later "unify" pass doesn't flatten the divergence: the
grain, seam, pile, and live-first behaviours differ ON PURPOSE, each for its
source's nature. NOT verified on-sim — this session is the Linux web env with
no xcodebuild. Mac before the checkpoint: a sparse source (week/month headers),
Music (session headers, two sittings in one morning splitting), Safari (the
reading lede + oldest line), a Wallet feed with a mixed in/out seam, a Twitch
feed with a live stream leading, and a dense feed (unchanged day grain) — light
and dark.

## 149. One ask per subject — the signature chip takes the context slot (user: "redundancy in the composer, we can't have that", 2026-07-21)

Standing on the Wallet feed, the composer offered "What's new in Wallet?"
(the §context recap lead, 2026-07-12) AND "How's my wallet?" (the dedicated
wallet chip, 2026-07-15) in the same grid — two wallet asks, plus the
organize hint also naming Wallet. Same latent collision on Tokens
("What's new in Tokens?" + "How's my watchlist?").

Ruling: one ask per subject. When the context source has its own signature
ask, that ask takes the context lead slot and the generic recap sits out —
the recap of the feed you're literally standing on is the weaker ask (the
feed behind the sheet already shows what's new; the signature chip reads
what the feed can't — live holdings, live prices). The signature chips'
unconditional appends later in `computeSuggestions` now skip themselves
when their kind already led (`Shell/Composer.swift`). The category sibling
("How's my Markets stuff?") still rides the context source unchanged — it
was already gated on being meaningfully broader (§143-era comment), which
is this same ruling applied one level up. The organize hint keeps its slot:
"Tag your 131 Wallet things" is an action invite, not an ask — different
verb, not a duplicate.

Mapping today: Wallet → "How's my wallet?" (still gated on a watched
address existing, else the recap falls back honestly), Tokens → "How's my
watchlist?". A future per-source signature ask joins the same switch.

Verified on-sim headlessly: `-landingChip Wallet` then `-openComposer YES`
logs `askTiles: hint:Wallet wallet,…` (no `context:Wallet`); `-landingChip
Reminders` still logs `context:Reminders,category:Life,…` (recap + sibling
intact for sources without a signature ask).

## 150. The holdings treemap goes to 160 and wears the wash (user, 2026-07-21)

The user, on the Wallet feed's holdings map: "the tree map doesn't even have
to be as large as it is … why does it need to be so large, or does it?" It
didn't. 220 was inherited from the Home-board module era — sized for tag maps
whose cells stack icon + label + a "N things" count line. Token cells never
show that count line, so the wallet map held vertical room it never used, and
the map already renders at 160 inside agent answers ("same data, denser
read", 2026-07-20). The user: "if it is smaller in the composer it can be in
our feed too."

Ruled from three side-by-side mockups (prototype/wallet-treemap-160-v2.html —
today's 220, a 160 with values stated, and a 160 with values + the tint
magnitude wash): **the wash version.** "I like c the best."

- **Token maps are 160pt everywhere** (`GenTagMap.boardHeight`): the default
  220 stays for tag/theme/source maps; token mode joins the agent-answer
  height. Bloomed-large 320 and small-tile 150 are unchanged.
- **Cells state the value their area encodes.** The cell ref grows a
  space-free " @v:$8.4K" marker (`TokenStats.compact`, built in
  `WalletIngest.holdings`, sliced by `KindCountRow.parse` like " @t:").
  Placement: bottom of a ≥2-unit-tall cell in primary ink, trailing secondary
  on a wide 1-unit cell, dropped on a 1×1 (no room — the area still speaks).
- **1-unit token cells go inline** (icon beside symbol, vertically centered)
  — at 160 a ~48pt cell can't stack a 20pt icon over a 17pt label, and the
  inline row is what makes the height work.
- **Token cells wear the magnitude wash** — `DS.tint(magnitude:)` at the
  cell's true USD share (weights are sqrt-scaled, so the share squares the
  weight back). A ~45% position washes at ~0.16 opacity, a sliver at ~0.07.
  This deliberately AMENDS the 2026-07-10 "tiles are literally the
  Settings-tile surface, no hue wash" ruling FOR TOKEN MODE ONLY — re-ruled
  by the user with the smaller map in front of them, not by memory of the
  bigger one. Tag/theme/source maps stay plain sheet tiles; 2026-07-10 still
  governs them.
- **Labels are symbol-first, name as the fallback, never both** (the same
  session's first ruling): both holdings readers now fall back to the
  metadata NAME when a token registered no ticker — `fungible_info.name` on
  the Zerion path, `tokenMetadata.name` on the Alchemy path — where before a
  symbol-less token silently dropped out of the map. `TokenIcon` renders
  nothing for an unmatched label, so name cells go text-only (the honest
  fallback it already had).
- Deliberately NOT built: the mockup's per-cell 24h micro-deltas — honest
  per-token change isn't in the holdings payload, and inventing a second
  fetch fan-out for a garnish isn't worth it until something else needs the
  same read.

Files: `GenUI/GenRenderer.swift` (GenTagMap + KindCountRow.parse),
`Model/WalletIngest.swift`, `Model/ZerionAPI.swift`. NOT yet verified on-sim
— Linux remote session, no Xcode toolchain; build + `scripts/verify.sh` and
an eyeball of the wash opacities on-device need to happen on the Mac before
this ships.

## 151. The balance takes the headline; Worth a look drops to a line (user, 2026-07-21)

Second pass on the Wallet feed, after the treemap settled (§145). From a
three-way mockup (prototype/wallet-feed-directions-v3.html), the user: "i like
how A puts the 'worth a look' as a line not a card."

- **The combined balance becomes the room's display headline**
  (`WalletBalanceHeadline`, replacing `WalletBalanceTile`). The crown feature
  ("the combined wallet state is our best feature", §140) stops sharing a row
  as a half-width card and takes the feed's headline voice: eyebrow, the big
  money number at the sanctioned `price40` rung (§102, so it scales with
  Dynamic Type), its honest `watched`-window delta beside it, and the sparkline
  full-width underneath as a whisper. Set on the page — no card surface. The
  combined-breakdown door (chevron → sheet) shows only in the multi-wallet
  "All" view, unchanged from before.
- **Worth a look drops from a standing card to a quiet line**
  (`WalletWarningsLine`, replacing `WalletWarningsTile`). Warnings are usually
  absent, and a permanent half-width card was reserving prominent space for the
  exception; as a line it whispers when clear and speaks up with its own
  attention glyph (red on a critical) only when something's actually there.
  Glyph · "Worth a look" · the top warnings' summary · chevron; the whole line
  opens the same tray. The tray behind it is unchanged.
- The section restructures from a side-by-side `HStack` of two tiles to a
  `VStack` of the headline then the line. Still flat (eager-head render law),
  still absent entirely when there's neither a balance nor a warning.

Files: `Screens/WalletFeedTiles.swift`, `Screens/FeedScreen.swift`. NOT
verified on-sim (Linux session, no Xcode) — build + `scripts/verify.sh` +
an on-device eyeball pend on the Mac.

**Held: the transaction ledger (mockup B).** The same session mocked a "ledger
stream" where each transaction row states its USD effect (+$120, −$132) and
day headers carry the day's net. NOT built — and not a styling change: a
Wallet transaction `Thing` carries `transferAmount` as a TOKEN amount
("120 USDC", "0.05 ETH") and `transferDirection`, but no USD. Quoting a USD
figure means multiplying by a price, and the only price on hand is the token's
CURRENT price — using it for a PAST transfer would misstate a volatile token's
then-value, which the honesty rule (§83) points directly at; a day-net can't
even be summed across tokens without it. An honest version (token amount in the
trailing slot, directional colour, no cross-token net) is possible but needs a
rewrite of the shared grouped-row renderer, and the full USD version needs a
historical-price read we don't do. Parked for the user to weigh against that
cost rather than shipped with a fabricated number.

## 152. No notifications — ever, as a product identity (user, 2026-07-21)

**Ruling (user, verbatim rationale): "i dont' want to add notifications because
then we become annoying and the apps we source are already notifying a user."**

Casberi sends NO notifications — not push, not local, not even a single opt-in
daily digest (one was floated in build-104 planning and declined). The sourced
apps (social networks, calendars, wallets, feeds) already own the interrupt;
Casberi's whole value is being the quiet place their output lands, read on the
user's own schedule. Becoming a second notifier would make the app part of the
noise it exists to absorb.

Consequences:

- The "presence outside the app" direction (kept asks on the widget, wider
  background refresh, Smart Stack relevance) proceeds WITHOUT the notification
  leg — widgets and the lock screen are the calm delivery surfaces; they show
  state when glanced at, they never demand a glance.
- `UNUserNotificationCenter` stays out of the codebase entirely (it has never
  been imported; keep it that way). No permission prompt for notifications
  should ever appear.
- The one standing exception-shaped thing we have — the voice-recording Live
  Activity — is fine: it reflects an action the user is currently taking, not
  an interrupt we initiated.
- If a future feature seems to "need" a notification (an approval landing, a
  watched wallet moving), the answer is the widget, the away answer, or the
  feed's attention glyphs — surfaces the user comes to, not ones that come to
  the user.

## 153. Semantic Spotlight + Visual Intelligence — the corpus answers system search (2026-07-21)

Two upgrades in one cut, both riding surfaces the user comes to (§152 — no
notifications; these are pull, not push):

**Spotlight, upgraded from text rows to entities.** `ThingEntity` had conformed
to `IndexedEntity` since 2026-07-17, but conformance alone donates nothing —
no code ever associated entities with the indexed items, so the semantic index
that Siri and Apple Intelligence ground on never received the corpus, only the
plain `CSSearchableItem` text rows. `SpotlightIndex.index` now calls
`associateAppEntity(ThingEntity(thing), priority: 0)` on every item it writes
— same watermark reconcile, same inline-at-save path, one new line where the
item is built, so both index surfaces stay in lockstep by construction.
Entities also wear the kind's own SF Symbol now (`ThingKind.symbol` in the
`DisplayRepresentation`), so Spotlight/Shortcuts/VI cards show a mark, not a
bare row.

**`OpenThingIntent` (an `OpenIntent`)** — tapping a thing anywhere the system
shows it as an entity opens its sheet in-app, routed through the existing
`casberi://thing/<id>` deep link (one proven path, not a second navigation
mechanism). Required plumbing for Visual Intelligence taps; free utility in
Shortcuts.

**Visual Intelligence (iOS 26)** — `Model/VisualIntelligenceSearch.swift`:
an `IntentValueQuery` over `SemanticContentDescriptor` returns matching
`ThingEntity` cards when the person points the camera at something or circles
it in a screenshot. On-brand for a screenshot-heavy corpus: the thing you
saved about an espresso machine surfaces when you're looking at one.

Honesty rulings baked in:
- **Labels only, pixel buffer unused on purpose.** The corpus has no
  image-similarity index; matching the system's own words for the scene is
  honest, pretending to match pixels would not be. If a real visual index
  (e.g. embedding screenshots) lands later, revisit.
- **A label with no usable term (>2 chars) is dropped, not passed through** —
  `IntentCorpus.match` treats an empty term list as "everything, newest
  first" (the Search intent's deliberate browse fallback), which here would
  dump the whole corpus into every camera frame.

Verification: `-viProbe "<label,label>"` runs the same matcher headlessly and
NSLogs the hits (VI's camera UI can't be driven on the sim). Verified
2026-07-21: seeded "Ring demo" surfaced for label "ring" alongside honest
content matches for "machine"; the launch reconcile exercised the association
path crash-free. The end-to-end VI surface itself needs a real device with
Apple Intelligence — untested there; the probe covers the app's half.

## 154. Handoff features don't make the cut (user, 2026-07-21)

A full survey of "transact through someone else's rails" extensions was
considered and CUT wholesale — user: "none of these really move the needle
... they would just water down the app." Declined, with the reasons found in
the discussion, so none of these get re-pitched without new evidence:

- **Pay links / EIP-681 URIs** ("pay back jesse.base.eth") — mechanically
  elegant, audience-thin; person-to-person crypto payments are rare behavior,
  and iOS custom-scheme handling can't even pick which wallet opens.
- **QR payment cards** — dead on arrival on mobile: you can't scan your own
  screen. (Receiving-side QR is a different, thinner feature; also cut.)
- **Wallet "Open in" deep links** on token things — the WalletConnect
  session's peer metadata does name the user's wallet, and the `canOpenURL`
  pattern is proven in-app, but the payoff doesn't justify the surface.
- **Kalshi market handoff, Bitrefill top-up links** — trivial builds, small
  wins; not worth the added chrome.
- **Fiat splits** (Venmo/Cash App prefilled links) — gated on an identity
  problem we'd have to build (nobody's $cashtag is in the corpus), and Apple
  Cash, the split rail iPhone users actually use, has no API.

What SURVIVES: prd 112 exactly as it stands — the approval prepare card
(reads, previews, revoke calldata, fee quote; signatures always elsewhere)
is a bounded surface, not the seed of a general "actions" layer. The Peer
capture-only pattern (settled fills landing as things) also stands — capture
is the app's job; initiating is not. If a future feature wants a handoff
button, it argues against this ruling first.

## 155. The combined portfolio, made whole (2026-07-21)

User: "the wallet's best feature is being able to see a combined portfolio."
Everything in this ruling follows from taking that literally — the combined
read stops being an overview bolted onto per-wallet views and becomes what the
Wallet room IS. Six changes, one derivation behind all of them
(`Model/WalletPortfolio.swift`, merged in memory from the per-wallet holdings
groups the app already fetches every foreground — no new network read, and no
way for the map, the number, and the lines under them to disagree).

1. **The crown number no longer waits four hours.** The balance headline drew
   off `TokenChart.from(samples:)`, which needs two samples, and samples are
   throttled to one per four hours — so a new user who watched three wallets
   saw NO combined total during exactly the first-impression window. The total
   is real from the first holdings read: it leads now, the sparkline joins when
   there is a line to draw, and the absence is worded ("The line starts once a
   second reading lands") instead of leaving a gap. The live total also beats
   the last sample as the displayed number everywhere, including the combined
   sheet's header — a sample can be four hours stale.

2. **The All room paints ONE combined treemap** — "What you hold", subline
   "$X across N tokens in M wallets". Scoped to a wallet (or watching only
   one), the per-wallet map is unchanged. This REVISES 2026-07-09's "separate,
   not combined": that ruling protected "which wallet holds what" at a time
   when the feed had no other way to ask. The wallet switcher (§128) is that
   way now — one chip per wallet — and the held-in breakdown (below) carries
   the same fact down to the position. Title is "What you hold", not "Across
   your wallets": the balance headline directly above owns that phrase, and on
   screen the two stacked read as one thing said twice.

3. **A tapped combined cell says whose it is.** The quick sheet gains a "Held
   in" section — wallet faces, labels, and each stake — shown only with more
   than one holder. This is the fact the per-wallet maps got for free by never
   merging.

4. **"Mostly ETH · +$310"** under the headline: the top attributed mover, from
   the same per-token snapshots the combined sheet's "What moved" reads, in
   whatever scope the switcher is standing in. The delta pill says the line
   moved; this says what moved it. Alongside it, **7d / 30d / watched** window
   chips — offered ONLY when the record reaches back that far and holds two
   points inside, so a chip can never name a period the history doesn't cover
   (the same rule that made "watched" the original label).

5. **Transactions are marked on the balance line.** A balance line conflates
   two stories — prices moved, and money moved in or out — and the app holds
   both halves. Marks sit at the moment each transaction landed (fractional,
   between samples, which is why `TokenChartPlot`'s x scale is now Double), and
   a tap opens that transaction's sheet. Only things falling BETWEEN the first
   and last sample are marked; capped at ten, past which punctuation becomes a
   second series.

6. **"ETH is 62% of everything"** under the treemap — the concentration read, a
   sentence that only means something about a whole portfolio. With more than
   one wallet it opens **Where it's held**: every position, its share, and the
   wallets holding it.

And one thing tried and REVERTED, recorded so it isn't re-pitched: the combined
sheet's hero as a **stacked area** (one band per wallet, summing to the total).
Built, screenshotted, backed out — a stack must be zero-based to stack
honestly, and at real portfolio ratios (one wallet holding almost everything)
that paints a full-height slab of one color in which a 3% move is invisible.
The line keeps the hero (its own non-zero scale, movement legible); the bands
live below it as a compact **"Made of"** strip with a share legend. Two
questions, two pictures, neither lying to flatter the other.

Verified headlessly with `-portfolioProbe` (new): two real watched wallets
merged to one map with per-position holders (ETH attributed across both), the
scoped shape still per-wallet, and the concentration line computed off the
merged book.

## 156. Accessibility as a feature, not a compliance checkbox (user: "lets do all of these", 2026-07-21)

Prompted by App Store Connect's **Accessibility Nutrition Labels**, which ask an
app to declare, per feature, what it supports. The labels are metadata — they
don't gate review — but a claim that isn't true is worse than an honest "not
yet", so the pass below is what makes each claim real. The framing that decided
the scope: **Larger Text, Reduce Motion and Dark Interface are not edge cases**
— a large share of iPhone users run a non-default text size, many simply
because they're over forty. This is mainstream configuration, not a minority
accommodation, and the honesty rule (§83) already forbids claiming what we
don't do.

**Contrast — the text ramp was failing, and it was carrying real text.**
Measured every token against every surface in both themes. `textTertiary` came
in at **2.3:1 dark and 1.7:1 light** — the worst failure in the app, and not a
placeholder tone: it paints `subhead13` row metadata (timestamps, source names,
"3 delegations") in 302 places. Light-mode `textSecondary` measured 3.3:1,
under the 4.5:1 body bar, on a tier that carries whole sentences. Both were
Apple's own `secondaryLabel`/`tertiaryLabel` values, which is how they passed
unnoticed — inheriting a system value is not the same as measuring it against
*our* surfaces. Raised: tertiary 30% → **49% dark / 74% light**, light
secondary 60% → **84%**. Every text tier now clears 4.5:1 on page, sheet and
well, in both themes, and the three-tier hierarchy still reads (secondary sits
~6:1, tertiary ~4.5:1).

**Increase Contrast is now answered.** `ContrastStore` mirrors the system
setting into the token layer (the same `@Observable` singleton shape
`ThemeStore` uses, because `DS` is a static enum with no environment to read).
Under it the ramp climbs to 7–10:1, and the tint and the three semantic colors
step to measured variants — light-mode system orange and green measure **1.8:1**
and are indefensible the moment they carry a word. Default stays Apple-native;
the person who asks for contrast gets it.

**Color is never the only carrier** (Differentiate Without Color). Fixed, in
descending order of what's at stake: the Aave **health** stat, where orange
alone signalled liquidation risk to anyone who happens to know where the margin
sits, now says "Health · at risk"; the source-chip **ring**, where "selected"
and "this connection is broken" were the same 2.5pt ring in two hues, gives
broken a **dashed** stroke and keeps solid for selection; bridge **status** gains
a glyph per state (filled dot / triangle / hollow pause) so the header mark
survives greyscale; the wallet warnings line swaps its glyph with severity
rather than only its color; `Sparkline` draws **dashed when down**, because it's
a reusable component and the one call site that pairs it with a signed number
can't vouch for the next. `TokenChartView` was already the reference — `isFlat`
strips sign and color together — and is untouched.

**Dynamic Type.** Eleven pieces of real reader text were frozen at raw
`.system(size:)` while their neighbours grew: four copies of the row project
tag, the media day pill, the command card, the sheet's tag line, both
device-flow user codes, the onboarding header, the diagnostic log. Three ramp
rungs were added (`label11`, `mono13`, `monoCode34`) rather than folding them
into the nearest existing rung, so each fix costs nothing visually — same size,
same weight, now scaled. The day pill traded a pinned 22pt height for vertical
padding, which is what let it clip.

**VoiceOver.** The app was in better shape than feared — every swipe action
already uses `Label`, and only eight icon-only controls were unlabeled (the
agent tray's ✕, the two profile avatars, the tag chip whose tap *removes* the
tag, Share, Clear search, the name-this-address column). The real problem was
noise and silence: **40 decorative glyphs** were read aloud (the onboarding rain
alone announced 31 brand tiles before the first step; the account tile read
sixteen SF Symbol names in a row), while facts that exist only as visuals were
silent — the address-poisoning flag, the strikethrough that means done, the
Apps door's breakage state. And a feed row was **five separate stops**: icon,
title, thumbnail, time, tag.

The ruling that follows from that: **a row is one thing, so it is one element
and one sentence.** `ThingVoice.rowLabel` composes it — kind, title, where it
came from, why it's here, state, when — and every shaped row speaks that one
grammar. "2h" is spoken as "2 hours ago"; the abbreviation is a glance, not a
reading.

**Measured, not assumed:** running the feed at `accessibility-extra-large`
immediately found the "All" source chip's label growing past its fixed 46pt
circle and colliding with the catalogue door. It now scales inside its own
circle. The neighbouring chips are app icons, which don't scale at all — that
strip is fixed-geometry chrome by design, and the one word in it has to respect
the geometry.

## 157. Morpho rides the watched wallets — the Aave shape, per market (user: "can we still add morpho? if so lets do all", 2026-07-21)

Morpho joins Aave as the second lending protocol the Wallet seat reads — no
account, no key, no catalog offer of its own (the Strava-rides-Health shape,
same as Aave §wallet-defi). Everything comes from Morpho's own public GraphQL
API (`blue-api.morpho.org/graphql`, keyless, measured live 2026-07-21) because
Morpho's positions are structurally unreadable the Aave way: Aave is one
account-wide `getUserAccountData` call; Morpho is ISOLATED MARKETS (plus earn
vaults), and enumerating a wallet's markets on-chain requires already knowing
every market id — which is exactly what the API answers in one batched
request (`userAddress_in`/`chainId_in`, all wallets and chains at once).

Three parts, mirroring the Aave split plus the Peer sweep:

- **Live book** (`MorphoDeFi.book`): market positions (collateral / debt /
  per-market health factor) + vault deposits, drawn as a second DeFi tile
  beside Aave's in the Wallet feed. The tile adapts between Morpho's two
  faces: borrowing (the Aave layout, worst market leading) and earning
  (Deposits + an honest "No debt"). At-risk markets roll into the
  Needs-attention warnings EACH ON THEIR OWN — Morpho markets are isolated,
  so two risky markets are two liquidations, not one.
- **Risk alert** (`MorphoDeFi.sync`): lands a thing on a NEW crossing below
  health factor 1.5 (same threshold, same bucket-reset lesson as Aave —
  no debt is a definitive "safe"). Links app.morpho.org; acting stays there.
- **Activity** (`MorphoDeFi.syncActivity`): settled Supply / Borrow / Repay /
  collateral / vault-deposit / liquidation events land as things — the Peer
  cursor shape, but TIMESTAMPS not blocks (the API filters on
  `timestamp_gte`). First sight seeds silently; `-morphoProbe <daysBack>`
  is the deliberate door to the past. Capture-only by ruling: settled events,
  never a pending intent, never a path that trades.

The ask ("what's my health factor", "how are my Morpho vaults") is now one
DeFi ask across BOTH protocols — worst health factor anywhere leads, earn
side follows; the kept ask upgrades with it for free.

Measured quirks (re-measure before "fixing"): the API's `collateralUsd` can
be NULL while the health factor reads (unpriced collateral — a real position,
don't drop it, and the tile falls back to stating deposits); dust is
everywhere (the burn address holds hundreds of sub-cent vault positions), so
`WalletIngest.holdingFloor` gates rows — except a live borrow, which is too
load-bearing to floor away; transaction amounts are raw BigInts scaled by
each asset's own decimals; and the schema DRIFTS — market transactions order
by `Timestamp` but vault transactions by `Time` (same field, two enum names;
either wrong 400s the whole document — caught live 2026-07-21), so
`live-integrations.sh` now POSTs the app's exact query shapes nightly.

Deliberately NOT built: any path that supplies, borrows, or migrates
positions (forecloses on §84's watching-can-never-trade promise), and
yield-ranked vault discovery ("top APY vaults") — unlike GeckoTerminal
trending, surfacing ranked yields drifts toward recommending financial
products, which the honesty rule and the no-advice line both refuse.

## 158. The wallet room stops being sterile (user: "how do we make it look cooler… i don't think 'ooooh this is lovely'", 2026-07-21)

Ruled from three on-page treatments (`design/wallet-look/wallet-look-mocks.html`,
same components, different color temperature): **A (the pour) + the four shared
moves + C's treemap.** The diagnosis the mocks made visible: the room was
ink-only — every hue on it was a 16pt face or a delta pill — so the crown
feature photographed as a dashboard, not a money app. Cash App and Uber both
let one color own a region; we let none.

**The pour — the one exception to §129, argued from inside it.** §129 retired
the per-source brand wash because the hue was the SOURCE's brand ("borrowed
identity, not owned") and because a browsing surface doesn't need decoration
the chip strip already provides. Both objections are answered rather than
ignored: the Wallet feed pours **Casberi's own tint**, not Wallet's brand blue
(§129's own words: Cash App is "bold in ONE color that's *theirs*"), and scoped
to a wallet it pours **that wallet's face tint**, where hue is information —
which wallet am I standing in — and switching wallets re-tints the room. 340pt,
gone before the transaction rows, half dose in light mode (the same field that
reads as atmosphere on ink reads as a stain on white). Every OTHER feed stays
ink: §129 holds everywhere it was aimed.

**C's treemap — tokens wear their own color.** A cell's wash is now the token's
brand hue (`Design/TokenHue.swift`) at the opacity `DS.tint(magnitude:)` used —
hue became identity, magnitude still rides size AND saturation, so nothing the
old wash encoded was lost. This amends 2026-07-10's "colored fills read as
noise", which judged FLAT fills before the magnitude wash existed. A symbol
whose brand color we don't actually know keeps the neutral wash — `TokenIcon`'s
own rule (never a guessed mark) applied to color, which is why a real map reads
half-branded and that's correct.

**The four moves, independent of the above.** (1) The total takes a new type
rung, `price48` — the one number in the app that earns it. (2) Its caption
drops to tertiary: hierarchy is the GAP between loud and quiet. (3) The line
gets body in the STROKE (2.6pt) and LESS in the fill (0.16) — measured on
screen: a portfolio line is nearly flat most weeks, so it hugs the top of its
box and a heavy fill paints a slab, not a glow — plus a static endpoint dot
(the pulse's honest twin: "latest reading", not "streaming"). (4) Transaction
rows become a **ledger**: the moved amount leaves the sentence and becomes a
right-aligned rounded tabular figure, green only on a receive ("Sent" ·
"−100,000 USDC"). It is the ASSET amount, never a dollar value — nothing on a
landed transfer records what it was worth then, and pricing a past transfer at
today's rate would be a number the record can't support.

**Bug this pass caught (shipped this morning, in every single-wallet install):**
the balance headline was a `Button` that `.disabled()` itself when there was no
breakdown to open — and a disabled plain button dims its whole label, so the
room's loudest element rendered grey for anyone watching one wallet. A
door-less reading now renders bare instead of as an inert control. The design
law's existing corollary ("a hand-rolled button MUST swap its background when
disabled") extended to ink: when there's no action, don't render a control.

**Found while verifying, filed separately:** a watched wallet's history carried
"Sent 100,000 USDC" where the symbol is `U`+U+0301, Cyrillic `Ѕ`, `D`, Cyrillic
`С` — a homograph spoof, rendered faithfully and unflagged. The app detects
address poisoning but not symbol spoofing; same attack, different field. The
money column raises the stakes by setting symbols large.

## 159. The crown pour goes permanent, and up to the shell (user, 2026-07-21)

Same-day correction to §158's pour, from a screenshot: "is this how we want
wallet to look w/ a hard black line and all that black over the source chips?
i think the app could permanently have that blue pour up there instead of
black." Two rulings in one:

**Where it lives.** The page-level pour produced exactly the seam the
screenshot shows — the chip strip floats over the pager on a `safeAreaInset`,
so a field painted by the feed page stops at the page's edge and the strip
zone stays flat black: a hard line, on the no-hairlines law. The pour moved UP
to `MainSurface`'s background (over `DS.themedPage`, under everything,
ignoring safe areas), which is where the retired `shapeWash` always lived —
that mechanism solved this layering in 2026-07-14 ("the wash used to start at
the feed's List, leaving the chips flat black above it"). The feed pages STOP
painting their own opaque coat (it would slide black between the shell's field
and the content); only a chosen background PHOTO still renders per-screen,
covering the pour on purpose — the person's own atmosphere wins.

**When it shows: always.** Not a wallet-room exception anymore — the crown
pour is PERMANENT, app-wide, in Casberi's own tint. This is §129's own
endorsed shape ("Cash App is bold in ONE color that's *theirs*") and none of
what §129 retired: nothing borrowed, nothing per-source, nothing deciding
screen by screen. One owned color, always there, half dose on a light page.
The Wallet feed keeps its one privilege through `ShellChrome.pourHue`: scoped
to a wallet, the crown re-tints to that wallet's face color (set on landing
and on scope switch; every page's landing writes the field, so a stale hue
can't outlive its room).

VERIFIED on a dedicated sim (a THIRD device — two Claude sessions were
fighting over `booted`, per the CLAUDE.md gotcha): dark reads as one
continuous field from status bar through chips into ink, light reads as sky,
no seam in either.
## 160. A fake symbol is address poisoning in the asset field (2026-07-21)

Closes the item §158 filed while verifying. The finding was one spoofed symbol
on poap.eth; the first probe run over the real corpus found **21**, in four
distinct spellings, none of which any existing check objected to:

| what landed | how | named by the rule |
| --- | --- | --- |
| `ÚЅDС` | `U`+U+0301, Cyrillic `Ѕ`, `D`, Cyrillic `С` | USDC |
| `UЅDС` | plain Cyrillic, no accent | USDC |
| `USḌC` | `D`+U+0323 combining dot below | USDC |
| `UႽD‸C` | Georgian `Ⴝ` + an INVISIBLE U+202C bidi control | USDC |
| `ꓴꓢꓓꓔ0` | written entirely in **Lisu** | USDT0 |

**The ruling: flag it, never hide it, never rewrite it.** Identical grammar to
poisoning (§84) — the transfer lands honestly, wears a `securityFlag`, and the
symbol keeps its real spelling on every surface. We do not "correct" a symbol
to what it imitates: that would make the app the author of a claim the chain
never made. The warning speaks in the poisoning line's voice — "Looks like a
copy of USDC — this is a different token."

**Two clauses, because one is a table and tables are always incomplete.** A
symbol is suspicious if (1) it contains ANY non-ASCII scalar, or (2) its
confusable skeleton matches a well-known symbol while its literal text does
not. Clause 1 needs no table and cannot be evaded by reaching for an alphabet
we forgot — it is what made Lisu and the bidi control land flagged on the first
run, before either was in the table. Clause 2 is what catches the pure-ASCII
attacks clause 1 cannot see (`DAl` with a lowercase L, `U5DT`, `S0L`, `3TH`).
The known-symbol list stays TIGHT, per `TokenHue`/`TokenIcon`'s precedent: a
short list of symbols actually worth impersonating produces a warning we can
stand behind; a general resemblance engine produces noise.

**Measurement writes the table, not intuition.** Every alphabet added after the
first run (Lisu, Georgian) and the one symbol added to the known set (`USDT0`,
a real omnichain token) came from the probe's own output. The skeleton also
strips invisible scalars before comparing — anything that draws no ink cannot
be part of what a symbol LOOKS like, and U+202C was in the corpus for exactly
that reason. Note what was NOT used: ICU's `.toLatin` transform is PHONETIC,
and renders Cyrillic `Ѕ` as "Dz" — it turns the real spoof into `UDzDC` and
matches nothing. Confusability is visual; the table is visual.

**Where it shows.** The row badge (the same glyph poisoning wears — the row is
where the lie is read), the sheet's warning line, a `Needs attention` roll-up
whose every row states ITS OWN flag, and the holdings treemap, where a
suspicious symbol wears `⚠︎` and thereby drops out of `TokenIcon`'s lookup so
it cannot borrow the real token's mark. The treemap marker goes on the display
CELL, never on the symbol key: that key is the token's identity, and it is
persisted inside every `WalletStore.ValueSample` — marking it there renamed the
token in the record, so one holding read as a position vanishing and another
appearing. A warning belongs on the label, never in the identity.
Two honesty corollaries fell out and were fixed here: the ledger figure
(§158.4) **loses its green on a flagged receive** — "money arrived" is exactly
the claim a fake USDC is making, and the confirm color would make the design a
party to it — and the warnings subline was counting WARNING ROWS, so 21 spoofed
transfers read "1 fake symbol" while the row two taps behind it said 21.
Poisoning had the identical bug; one `count` field fixed both.

**VoiceOver is not a secondary surface here.** "ÚЅDС" and "USDC" are read
identically aloud, so for that reader the spoken flag is the ONLY difference
between the two rows — not an enhancement of a visual cue, but the entire cue.

**`securityFlag` became a set** (comma-joined, no migration — still a String):
one transfer can be both a lookalike address and a lookalike symbol, and the
old equality test would have silently dropped whichever arrived second.

**The offending symbol is STORED** (`Thing.spoofedSymbol`, an additive optional
— no migration stage; the "a new field would need one" instinct is wrong, see
`ThingSchemaVersioning`). Ingest is the only place holding ground truth: it
flags from the raw symbol, while a surface can only re-scan the rendered title,
where the symbol sits beside a counterparty and a venue that may themselves be
non-ASCII. Re-parsing prose to recover a fact we had in hand is how a warning
ends up naming the wrong token; the text scan survives only as the fallback for
transfers that landed before the field.

**Backfill, once.** Ingest-time flagging alone would have shipped doing nothing
for the wallet that revealed the attack: `refresh` dedupes on `sourceRef`, so
the 21 already-landed transfers would never be re-examined. A one-time heal
flags them (measured: 21 healed, then 21/21 on re-probe). Honest limit — a
thing arriving later from another device via CloudKit misses that pass, the
same gap poisoning has; `-symbolProbe YES` is how you'd see it.

**Every wallet producer flags, not just the transfer arms.** Review caught the
approvals arm building "Approved Uniswap to spend unlimited ÚЅDС" unflagged —
the same lie in a more dangerous sentence, since the thing being trusted IS the
token. It flags now. The corpus must not disagree with itself about one token
depending on which arm landed it.

Rule for later: **a spoofable string is any string the chain hands us and we
then set in type.** Symbols were the second one found. NFT collection names,
ENS-adjacent labels and token NAMES (not just symbols) are the same shape and
are unchecked today.

## 160. Both boxed — the wallet room's two reads become parcels (user: "i like both boxed", 2026-07-21)

Ruled from five on-page frames (`design/wallet-look/wallet-cards-mocks.html`,
redrawn mid-review with the REAL crown context — source chips, wallet switcher
pills, sync capsule — after the user pointed out the first cut had flattered
the card by omitting them). **Both the balance and the holdings map get card
surfaces.** The argument that won: parcels are easier to SCAN than strata, and
in a room the eye enters looking for sections, edges are the strongest grouping
signal there is.

This AMENDS §146/§151, which took the balance OUT of a tile so it could hold
"the room's headline voice — set on the page, no card". That reasoning was
sound when the crown was ink; it lost to the scanning argument once the crown
was full of shapes anyway. The number keeps every ounce of weight it earned in
§158 (price48, the crown pour behind it, the delta pill and mover line with
it) — it just gets an edge.

Recorded because it was argued and lost, so it isn't re-pitched as new: the
counter-case was that a boxed number reads as a widget reporting rather than
the room speaking, and that with everything parcelled nothing leads. Two other
options died on the way — a card around the map ALONE (the user's own
objection: in a parade of chips, pills, and capsules, one more rounded surface
is camouflage, not distinction) and a full-bleed map band (the shape-grammar
break; built as frame E, not chosen).

Craft the ruling required:

- **Translucent, not opaque** (`dsWidgetSurface(fillOpacity:)`, 0.82). These
  cards sit ON the crown pour (§159); an opaque fill punches a hole in the one
  atmospheric move the shell makes. Still a fill, never a material — glass
  belongs to the floating layer alone.
- **Worth a look stays a LINE between them.** Warnings are usually absent, and
  a third card would reserve a permanent parcel for the exception (§146's own
  reasoning, which survives intact for that element).
- **The holdings card is one object**: title, subline, treemap, and the
  concentration line inside one edge. GenTagMap's own s4 horizontal padding
  becomes the card's inner gutter, so the cells nest without a second inset;
  the map keeps its own card-cells (a card of cards, as approved on the mock).

**Amendment, same day (the DeFi tiles):** Aave and Morpho were ALREADY cards —
they share `WalletTile`, which has worn `dsWidgetSurface` since the 2026-07-20
split — so §160 didn't need to box them. It needed to make them MATCH. Two
defects showed the moment they rendered beside the two new cards, both caught
on screen against a live wallet ($43.3M collateral / $39.4M debt / health 1.04
on Aave, plus a Morpho book on the same address):

1. **Opacity parity.** The DeFi tiles were opaque while the balance and
   holdings cards were translucent — a room of cards at two opacities reads as
   a bug. `WalletCardStyle.fill` is now the single constant all four share.
2. **The money voice.** The tiles printed `WalletIngest.format` — full grouped
   digits ("$43,315,267") — while every other number in the room speaks
   `TokenStats.compact` ("$3.2M"). At eight figures the full number also
   cramped its column. Money is compact now; the HEALTH FACTOR keeps
   `format` (1.04 is not money, and rounding it would hide the risk).

VERIFIED on the dedicated sim, dark and light: the pour still reads at the
crown and between the parcels, cells keep their brand washes inside the
holdings card, and the light page renders the two cards as white parcels on
sky without a seam.

## 161. Settings speaks the feed's row grammar (user: "lets go w/ rows the feed's own grammar", 2026-07-21)

The Settings tile grid retires. The screen came up in a vibecoded-parts audit
as the one surface that read generated rather than drawn: seven one-fact
entries in uniform two-column tiles (minHeight 96) left dead air at the bottom
of every card and an orphan in the last row — the generic dashboard-tile
layout, in an app whose every neighboring surface (the feed's parcels, the
Apps page rows, Settings' own aliveRow detail trays) already speaks rows.

Ruled on a two-way mock (design/settings-look/mock-settings-rows-vs-grid.html):
**A — rows in the feed's grammar** vs **B — the grid kept, facts at display
size**. B surprised where a real fact exists ("279" big reads like the Wallet
card) but strains on the three entries that have no fact to wear big
(Diagnostics, How it works, Avatar) — an action line at headline size is an
announcement about nothing. A speaks with one voice across all seven. User
ruled A.

Shape: ONE parcel (`dsWidgetSurface`), every entry an `AccountRow` — leading
glyph-in-a-squircle at 34pt (the Apps-page trust-mark grammar; the Avatar row
seats the photo or the Casberi mark), title `heading17`, the live fact
TRAILING right-aligned in `callout15` (the feed rows' own seat for it). No
hairlines between rows — padding separates, per the no-hairlines law. Theme
keeps its tap-flips-in-place behavior as a row. New beside the mock: a KEYED
"Your key" row speaks its fact in the badge's green (`DS.confirm`) — a live
connection states itself in the connected color; unkeyed stays tertiary. The
A–Z single-field ordering and every action/badge/debug hook carry over
unchanged; the tile's `seats` shelf machinery (dead since the Apps tile
retired) is deleted with it.

## 162. Privacy Pools rides the watched wallets — the alert IS the feature (user: "ok lets add that and make it a new bridge", 2026-07-21)

0xBow's Privacy Pools is compliant onchain privacy: you deposit, an
Association Set Provider (ASP) screens the deposit, and once cleared you can
withdraw to a fresh address with a proof that your funds came from the
approved set. The seat rides the watched wallets the way Peer does (prd
§113) — depositing happens from the person's own wallet on 0xBow's app, so
there is no account, no key, no OAuth, and connecting is one switch.

**Two reads, and the second is the reason to build it.** Deposits land as
things ("Put 0.0700 ETH into Privacy Pools") off Ethereum's public chain.
But the differentiated read is the ASP STATUS: a deposit sits in review
until it's approved, and that flip is what people otherwise keep re-checking
a website for. Casberi polls it and lands "Privacy Pools cleared your 0.0700
ETH deposit — ready to withdraw privately". A deposit alone is a transfer
the wallet feed half-shows anyway; the cleared-to-withdraw moment is news
nothing else in the app could tell you.

**Category: Wallet, not Markets** (user asked; ruled 2026-07-21). Peer sits
in Markets because a Peer fill is a TRADE — fiat became crypto, the same
shelf as watching a token or an event's odds. Privacy Pools trades nothing
and quotes nothing: it's your own funds, moving between your own addresses,
wearing a status. That's the Wallet shelf's subject. (Bitrefill set the
precedent for splitting on subject rather than on chain-ness: it went to
Shopping, not Markets, because it's your own commerce account.)

**Honesty boundaries.**
- CAPTURE ONLY. Nothing deposits, withdraws, proves, or signs — the Peer
  line ("lands settled fills, never a path that trades").
- The WITHDRAWAL side is unlinkable BY DESIGN — that IS the product. The
  chain cannot tie a withdrawal to its deposit, so Casberi never shows it and
  the copy never implies otherwise. Watching a second address would show the
  arrival, and correlating the two is not something the app does.
- Alerts are NEWS: a status thing lands only for a transition observed WHILE
  watching. A backfilled deposit whose review resolved months ago lands as
  the deposit alone — no stale "cleared!" theater. Implemented as a baseline
  rule: a deposit younger than a day seeds "pending" (its flip is ahead of
  us), an older one seeds "" and the first poll records silently.
- `exited` / `spent` are terminal non-news — the person acted elsewhere;
  the entry drops without an alert.

**Divergence from Peer, on purpose:** Peer seeds a silent block baseline on
first sight (history before the watch isn't ours to dump). Privacy Pools
BACKFILLS from the deploy block instead, because deposits are rare (~4k in
the ETH pool ever, so the read is cheap) and because the primary case for
the alert is a deposit made BEFORE connecting — a silent baseline would make
the feature miss exactly the person it's for.

**Measured 2026-07-22** (re-measure before "fixing" any of it): one
Entrypoint (`0x6818…6b46`) serves all 14 mainnet pools with the depositor
indexed, so one filtered `eth_getLogs` per wallet finds every deposit in any
asset; `rpc.mevblocker.io` served the FULL 3.4M-block history in 0.33s
(publicnode now token-walls getLogs entirely, drpc caps at 10k); the ASP API
is fully keyless (`/{chainId}/public/…`, CORS `*`, no 429 across a burst),
pool-keyed by an `X-Pool-Scope` decimal and batched via comma-joined
`X-Labels`. Labels are uint256 DECIMAL strings — hence the exact
byte-wise base conversion in `decimalString(hexWord:)`; a Double round-trip
would silently corrupt every label and the poll would match nothing.

Verified end to end on a real depositor wallet: two same-day deposits landed
with real amounts, both their approvals landed as alerts, a re-run deduped to
zero, and the corpus dupe probe stayed clean.

## 163. Read-only exchange seats — the balance that isn't onchain (user: "i think it should merge and that doesn't change wallet room's can never trade", 2026-07-21)

Most people's crypto is not all onchain. A portfolio built only from watched
addresses is quietly wrong for anyone whose main holding sits on an exchange,
which makes this the largest remaining gap in the crown feature §155 named.
Coinbase and Kraken connect with a view-only API key.

**Ruling 1 — they MERGE.** §155 already settled that the combined read IS what
the wallet room is, so an exchange balance joins the same total and the same
treemap rather than living in a sidecar. A venue appears as a `Holder` beside
the wallets, so §155.3's "Held in" read answers *which of my places holds this*
instead of *which of my addresses* — and every share, the token count and the
concentration line come out right for free, because all three already compute
over the merged positions.

Three boundaries the ruling implies:
- A venue does NOT count toward `walletCount`. That number backs the phrase
  "in M wallets" and an exchange is not a wallet; inflating it would be the
  honesty rule's own failure mode, a true-sounding number that isn't counting
  what it says. The combined map now offers itself on more than one PLACE.
- Merging happens on the COMBINED read only. A feed scoped to one wallet (§128)
  answers "what does THIS address hold"; folding a Kraken balance in would make
  the scope a lie.
- Either source alone is a real portfolio. Someone whose crypto is all on an
  exchange has one, and the old empty-groups guard would have painted the empty
  state over a balance we had successfully read.

**Ruling 2 — it does NOT change "watching can never trade or move funds", and
the reason matters.** An earlier draft of this feature claimed the promise came
to rest on the key's scope once a credential existed. The user rejected that
framing outright ("how would someone be able to trade, we don't even have a
wallet") and was right. The promise holds for the reason it always did: the app
has NO capability to trade — no `personal_sign`, no `eth_sendTransaction`, no
signing path anywhere, WalletConnect proposes `methods: []` (§84), and no
order/withdrawal/transfer endpoint is reachable from the exchange code at all.
A key changes none of that.

The permission check still earns its place, for a narrower reason: **blast
radius**. An API key is a bearer credential, usable by whoever holds it
regardless of what this code does, so a key that can withdraw turns a keychain
leak or a bad backup from a privacy problem into a funds-loss one. Casberi asks
the exchange what the key may do BEFORE storing it, and a key that can move
money is never written to the device. It also catches the likelier case: people
reuse the trading key they already had.

Recorded because it was argued and corrected, so the overstatement isn't
re-derived: the check is least privilege, not self-restraint.

**The gate fails closed.** Unreachable check, unparseable answer, or a
permission string we don't recognise all mean refuse — deny-by-unknown, so a
permission the exchange adds next year can't slip through an allowlist that
ignored it. Coinbase answers `can_view`/`can_trade`/`can_transfer`; Kraken a
permissions array from `GetApiKeyInfo`, documented to require no permissions
itself, so it works on the most restricted key a person can make.

One consequence of ruling 2 was behavioural, not cosmetic: `can_receive` was
disqualifying at first on the reasoning that it is "a funds-movement right".
Receiving is inbound and cannot lose anyone money, so refusing it bought
nothing and could have rejected perfectly safe view keys with an undiagnosable
error. Only trade and transfer disqualify. A check must refuse a real power,
not a named one.

**Catalog: the Wallet group** (user), because the balances merge into the
wallet room's own total — not Markets, which is where things you watch rather
than own live.

Two smaller rulings inside the build:
- Prices are the bid/ask MIDPOINT from Kraken's keyless public book, never the
  last trade — §83's honesty rule about stale quotes, applied to a new surface.
  An unpriceable holding is dropped rather than counted at zero, which would
  shrink the total and make the treemap misstate shares.
- Deposit/withdraw history rides `query-ledger`, never Kraken's Deposit/Withdraw
  permissions — those gate the transfers themselves, so "enable Withdraw to see
  your history" would hand over the exact power being checked for.

VERIFIED without any exchange key, which is the point — the crypto is asserted
against published ground truth rather than a live call. Kraken's `API-Sign`
reproduces its OFFICIAL published worked example byte-for-byte; the Coinbase
JWT is a real ES256 token that verifies against its own public key and emits
raw r‖s rather than the DER every JWT verifier rejects. Live keyless pricing
confirmed across BTC/ETH/SOL/USDC/USDT/XTZ/DOGE. Website shelf, brand CSS and
cache-busters shipped the same session; catalog-sync green.

STILL UNVERIFIED: no live authenticated call has ever run — with no exchange
key available, the success path (a good key connecting and landing balances)
and the refusal path (a trade-capable key actually being turned away) are both
unexercised. Store a read-only Kraken key via `scripts/dev-keys.sh` and run the
connect flow before this ships to anyone.

## 164. The feed-head doctrine — one boxed aggregate; rows own recency (user: "how should we think about these visualizations", 2026-07-21)

Asked while extending §160's parcels: should the All feed's Themes map be
boxed like the wallet map, and should media feeds lead with a hero of their
most recent item? The first is yes and shipped (the Themes card wears the
exact holdings-card recipe — same widget surface, same fill, same gutter; it
was the last head read floating bare). The second is no, and the reasoning is
the doctrine:

**The head card answers the source's STANDING question; the rows answer
"what's new." The head must never duplicate row one.** Every head that exists
passes this test by being an AGGREGATE — a fact no single row can say:

- consistency over time → the heatmap (GitHub, journaling, social, chats)
- composition → the treemap (holdings, Themes)
- ranking → the leaderboard (senders, subreddits, artists)
- mood → the distribution bar (Stocktwits)
- texture of what's arriving → the mosaic (OpenSea, Pinterest, Shopify,
  YouTube — and from today Deals, which had no head at all, plus Steam,
  Podcasts, and Substack as the FALLBACK head their leaderboards leave open:
  a leaderboard refuses to render under two groups, so a single followed
  show/publication/game previously led with nothing)

A most-recent-item hero fails by definition: the most recent item IS the
first row, one glance below. Promoting it reads the same fact twice and
spends the screen's best real estate doing it. The mosaic is the honest form
of that instinct — the newest items' art, plural, as texture rather than one
item ranked over the rest by nothing but its timestamp.

**The one exception: live beats aggregate.** A single item may claim the head
only while it is a LIVE STATE rather than a landed thing (a Twitch stream on
right now) — which is why Twitch is deliberately NOT in the mosaic set: its
`previewImageURL` is a live frame, perishable by the honesty rule, and a
mosaic of dead frames would claim streams are on. Its head-worthy fact is
"live now", which live-first ordering already carries.

In three lines: one head parcel per feed, always boxed, always an aggregate
derived from the feed's own things; rows own recency; a single item reaches
the head only while it's live.

## 165. The whisper carries the day brief (user: "ooh i like the idea of the whisper capsule with the headline. lets do that", 2026-07-22) — VERIFIED

Ruling 6 of docs/agent-brief.md sketched the whisper as optional and
flag-gated ("one glass whisper capsule above the bar with the top changed
signal"). This ruling makes it real, with a different payload: not the top
changed kept-ask signal, but **the day brief's headline** — "Your Wednesday ·
14 new, wallet +1.5%" — shown on the **first foreground of a calendar day**
only. The context was a landing-surface discussion (should the app open on
the agent with a day summary?): agent-first was declined as re-litigating
ruling 2 (content-first open) and rebuilding the §131 board one abstraction
up; the whisper is the settled middle — the app still opens into your things,
and the day greets you from the floating layer, one tap from the agent.

**Deterministic by construction** (`Model/DayBrief.swift`) — ruling 1's spine
guarantee extended to the launch path: every fragment is a fact already held.
Two fragments today, fixed order: the landed count since the frozen away
window (or since midnight when no window froze), and the wallet delta off
`WalletStore.combinedValueSamples()` — the CACHED line, synchronous, no
network read on the launch path. Honest skips are the design: no landed
things and no wallet movement → `headline()` returns nil and the whisper
simply never shows; a wallet history younger than ~20h can't speak at day
scale → no wallet fragment; a move that rounds to flat has no direction (§83)
→ no fragment, no sign.

**Conduct:** shows at most once per calendar day (`whisper.lastShownDay`
stamp), suppressed until onboarded, dies the moment the agent rises by ANY
path (its job is done), and never returns until a new day has something to
say. Tap = raise the agent, same move as the bar's own. The rest surface
(greeting + kept-ask pills) is the tap's landing FOR NOW — it upgrades to the
Today answer once the daily-summary design is ruled (three mockups delivered
alongside this build; the user rules next). No badge, no count on the bar
itself — the whisper is its own line, per ruling 6's no-badges-ever.

Placement: `WhisperCapsule` (in `Shell/AgentBar.swift`) rides a VStack above
`AgentBar` in RootShell's floating layer — glass is lawful there (§8). The
compose rides the SAME foreground corpus walk that refreshes kept-ask
digests (`RootShell.refreshWhisper`), never its own fetch.

VERIFIED 2026-07-22 (iPhone 17 Pro sim, udid-pinned — three sims were booted):
`-whisperProbe YES -awayGap 720 -onboarded YES` logged `whisper: Your
Wednesday · 52 new` and rendered the capsule above the bar; relaunch WITHOUT
the probe logged nothing (the day stamp held); a headless tap on the capsule
raised the agent to its rest state; ✕ lowered back to the feed exactly, bar
present, whisper gone. Wallet-fragment path exercised in code review only
(this sim watches no wallet with ≥20h history) — pairs with
`-seedWalletHistory` when a live check is wanted. Hook: `-whisperProbe YES`
bypasses the day stamp; logs "(nothing to say)" when the brief is honestly
empty. Found in passing, spun off: the rest greeting truncates on
"Wednesday morning." (longest weekday vs the ✕ button's row).

## 166. The Today brief — the mosaic, with the agent's own read on top (user: "definitely prefer B the signal board… lets build b2 with b3 synthesis card", 2026-07-22) — VERIFIED

The screen the whisper capsule (§165) opens. Three directions were mocked; the
user picked the **signal board (B2)** and asked for the **synthesis card (B3)**
folded in, plus a ruling that reshapes every module in it.

**The module doctrine (the ruling).** Verbatim: *"counts of things rarely
matter except transactions maybe, why b/c people don't care how many they get,
they get dozens a day, they care what it is."* So a module is never a tally.
Every module is exactly one of four shapes: a **visualization**, the **most
recent thing itself**, **what's next**, or a **synthesis card**. Counts survive
in exactly one place — money moving, where the count IS the event ("1
transaction — Swapped 0.5 ETH → 1,240 USDC"). This ruling also reached back
into §165's whisper: its headline now leads with a NAMED subject ("mara.eth
mentioned you", "1 transaction") and falls back to a bare count only when
nothing nameable landed.

**What composes** (`Model/TodayBrief.swift`, deterministic — ruling 1's spine
guarantee, no model on this path):
1. **The synthesis card** (B3) — up to three observations, each a pattern that
   actually fired: a mention gathering replies (reply count ≥ 3), a dominant
   topic across the day's reads (one significant word carried by 3+ titles,
   counted once per title) with the ONE read that isn't about it promoted as
   the outlier, the day-scoped wallet attribution ("ETH did the lifting"), and
   a watchlist leader (≥3% only). **No branch pads**: a patternless day emits
   no `DayNotes` line at all and the brief starts at the hero. Three strong
   lines read as intelligence; three padded ones read as a horoscope.
2. **The money hero** — the fused visualization B2's mock led with: combined
   total, day-move pill, holdings treemap and balance line SIDE BY SIDE, then
   what settled. Fused because the wallet is the only always-on aggregate, so
   it alone earns both shapes; every other module carries one.
3. **The pair** — `MoversTile` (watchlist, real direction in real color, "flat"
   uncolored per §83) beside `NextTile` (the nearest DEADLINE).
4. **The leads** — the mention rendered as the real post (`PostRow`), and the
   one read worth opening: the topic outlier when a topic exists, else the
   newest. Residue is NAMED, never counted ("the rest keeps circling Samsung").
5. **The hour strip** — `Bars` over the window, the one module that answers
   "when did this arrive" rather than "what is it".

**Deliberate scoping decisions.** `NextTile` reads deadlines (`dueAt`) only,
never calendar events — folding events in would rebuild the day-planner lane
§101 cut. "Reading" excludes Markets/Wallet sources by the catalog's own
category vocabulary: a watched token lands as `.link` (its content is a
Dexscreener URL, which is what makes its sheet draw a chart), so an unfiltered
`kind == .link` filed "dogwifhat · $WIF" under Reading and let it win the topic
outlier (caught on-device).

**Three paths, one composer** (the §132 principle): the whisper's tap
(`chrome.askRequest = TodayBrief.title`), a typed "how's my day", and a kept
`today` pill all route through `KeptAskComposers.compose("today", …)`. The
kept pill's digest IS the whisper's own fragment set, so the pill's trailing
signal and the capsule that teased the screen always agree, and the changed-dot
fires on exactly the days the headline would have changed.

**New GenUI components** (`GenRenderer.swift`): `DayNotes`/`DayNote`,
`MoneyHero`, `TilePair`, `MoversTile`, `NextTile`. `DayNote` has no dispatch
case of its own — it renders flat as a child of `DayNotes`, the discipline
`GenWidget.rowContent` already keeps for the eager-depth reason. `TilePair` is
NOT `Bento`: Bento is a two-column `LazyVGrid`, so a day offering one tile
rendered a half-width card beside an empty column (caught on-device); an HStack
degrades honestly. Both tiles stretch to the taller one.

`WalletStore.holdingsDeltas(forAddress:)` gained an additive `since:` — the
start moves forward to the last snapshot at or before that date but never
earlier than the cross-wallet alignment point, so the day-scoped attribution
keeps §77's guarantee that a composition change can't masquerade as a move.

VERIFIED 2026-07-22 (iPhone 17 Pro sim, udid-pinned; `-todayProbe`,
`-uiAnswerProbe`, `-whisperProbe`, `-seedWalletHistory`, `-watchToken`): the
composer logged the full doc with every module chosen; the rendered brief shows
the synthesis card (topic + wallet attribution), the hero ($164, +10.1% pill,
ETH/RAIN cells, green line, transaction subline), both tiles equal-height, the
Reading card with the outlier promoted, and the hour strip labelled 7 PM → 8 AM.
Tapping the whisper capsule raised the agent straight into this brief. Four
bugs found and fixed on-device along the way: the Bento empty column, blank
`Bars` labels being dropped by `split(separator:)` (they bunched both stamps
under the first two bars — blanks are a SPACE now), a clamped title's ellipsis
colliding with a sentence period ("…."), and the whisper line truncating its
wallet fragment (the headline is budgeted now, and a lead that doesn't fit
yields to its own short form — "1 transaction" beats "Swapped 0.5…").

### 165a. The whisper names itself (user: "user wont know that is a daily synthesis, they will think it is just a single notification for a transaction", 2026-07-22) — VERIFIED

§165 shipped the whisper as a PILL: a tint dot beside one line of facts ("Your
Wednesday · 1 transaction, wallet +10.1%"). That is notification grammar — a
dot plus a sentence reads as "an event happened", so a daily synthesis was
indistinguishable from a single transaction alert. Naming the weekday inside
the sentence wasn't enough: it scanned as part of the fact, not as a label for
the artifact.

Three changes, each doing one job:
- **The brief is NAMED, on its own line** — "Your Wednesday brief" above the
  facts, so what the thing IS reads before what's in it. The two-part shape
  (`DayBrief.Whisper` = title + detail) is what makes it a digest rather than
  an item.
- **The unread dot becomes the agent's own mark** (`CasberiMark`) — it says who
  this is from, not merely that it's new. The dot could only ever say "new".
- **A trailing chevron** — it opens something. A capsule with no affordance
  reads as a passive banner.

Shape follows: the pill becomes a `DS.Radius.control` card (still floating-layer
glass, still one tap). Moving the weekday out of the fact line also widened the
detail budget (46 → 40 chars for the facts alone, which is MORE room than
before since the ~17-character "Your Wednesday · " prefix is gone), so a lead
that used to be squeezed out now often fits.

`DayBrief.detail` is now the single source for the fact line, and the kept
`today` pill's digest reads it directly — which retired §166's original
string-stripping hack (the digest used to be the headline with the weekday
prefix removed by `replacingOccurrences`). The whisper's TITLE is deliberately
not in the digest: a pill already reading "How's my day?" doesn't need "Your
Wednesday brief" repeated after it.

VERIFIED 2026-07-22 (iPhone 17 Pro sim): the capsule renders the berry mark,
"Your Wednesday brief" in primary ink, "1 transaction, wallet +10.1%" in
secondary, and the chevron; tapping it still raises the agent straight into the
Today brief. VoiceOver reads the two lines as one element with the hint "Opens
your day".

## 167. The brief's design pass — six corrections (user: "how would you improve the design of what we have done so far", then "make all six", 2026-07-22) — VERIFIED

A refinement pass over §165a/§166 as shipped, driven off the real screenshots
rather than the mockups. One principle behind all six: **every promise the
surface makes gets kept in pixels.** No new features; each item closes a gap
between what the composer already knew and what the screen actually said.

**1. The brief owns its name.** The capsule promised "Your Wednesday brief"
and opened a screen titled "How's my day?" — the typed question. That is
§165a's own lesson (name the artifact) failing one screen deeper. The answer
header now renders a MASTHEAD when `TodayBrief.matches(question)`: an eyebrow
naming the window ("Wednesday, July 22 · since 8:17 pm" — dropped when the
window IS the calendar day, rather than stating the obvious) over the same
words the capsule used. Lives in `Composer.convoTurn`, not the doc, so
scrolled-back turns render identically.

**2. The whisper is seated, and its figure wears its direction.** Two
full-width glass slabs stacked read as one confusing double-bar; the capsule
is inset a step narrower than the bar, so the floating layer has hierarchy
(bar = furniture, whisper = today's delivery). `DayBrief.Whisper` now carries
`lead` and `walletPct` SEPARATELY — a single pre-joined string gave the view
no way to find the figure inside it, so a gain and a loss read identically.
`DayBrief.detail` (the kept pill's digest) is now derived from the same
`Whisper`, so the two can't drift.

**3. The hero's cells state their magnitude.** The doc's cells already carry a
value (`@v:$92`, `KindCountRow.Item.value`) and the compact map dropped it —
a treemap whose entire point is magnitude, refusing to say the magnitude it
holds. Cells show symbol over value; the sparkline gained its own "since Jul
21" anchor (the job `ValueSpark`'s subline already does elsewhere).

**4. The settled transaction is a row, not a caption.** "1 transaction —
Swapped 0.5 ETH → 1,240 USDC" was tertiary text that opened nothing while
naming a real thing. It draws as a real row now — kind glyph, title, meta
("your only transaction · settled 8:32 pm"), chevron, tappable to the thing.
Dead-looking text that should be live is an honesty bug, not a style choice.
The plural and empty cases have no single thing to name, so they keep the
plain subline.

**5. Agent voice gets one grammar, and leads get room.** The synthesis card
moved from `dsWidgetSurface` to the `DS.tintDim` surface `Insight` already
wears — tinted surface = the agent talking, ink cards = your things; on a plain
card it was indistinguishable from the modules it summarizes. Signed
percentages inside a note render in their own accent (`GenSignedText`, which
colors only what the composer already wrote and leaves a flat 0.0% in body ink
per §83), and a note naming a real thing wears a chevron. The two lead modules
gained real components: `LeadRow` (thumbnail, two-line title, meta) and
`LeadPost` (avatar, author, the words, a meta line carrying replies + what's
behind it). The first cut used the ordinary one-line `Row`, which showed the
thing while cutting off what it is — against the brief's own doctrine. Feed
rows elsewhere keep their one-line discipline on purpose: a lead is one item
GIVEN ROOM, which is the whole meaning of promoting it.

**6. The residue has somewhere to go, and the clock a midpoint.** "The rest
keeps circling Samsung" was a plain subline naming a topic the reader then had
no way to see. New `AskMore(label, query)` hands the agent that query through a
new `genAskRequest` environment hook — ruling 9 (a bare tap never ejects) plus
ruling 8 (a new ask pushes a fresh answer onto the Stack), so the session model
already had the right move. Its label is deliberately "See the rest", NOT the
topic again: the synthesis note above already said "keeps circling Samsung",
and naming it here put the word on screen three times. The hour strip gained a
MIDPOINT label — with ends alone, an overnight window's long quiet stretch is
unreadable. `GenBars`' own geometry was left untouched (it's shared with the
recap answers); only the label set changed. The synthesis note's outlier clamp
went 48 → 60 so an ordinary headline stops cutting mid-phrase directly above
the Reading card showing the same headline in full.

VERIFIED 2026-07-22 (iPhone 17 Pro sim): masthead, tinted synthesis card with
green +10.1% and chevron, hero cells with values, "since Jul 21", the
transaction row, both tiles, the `LeadRow` with its loaded thumbnail and
two-line title, "See the rest ›", and the three-anchor hour strip all render;
tapping "See the rest" asked "Samsung" and pushed a fresh turn onto the Stack
(3 reads found) without leaving the agent. Debug lesson paid for: the
`todayProbe` doc was logged as ONE multi-line message and the log reader
truncated it mid-document, hiding an unresolved ref for a full debugging round
— it logs one `todayDoc|` line per doc line now. Also re-learned: the answer's
provenance badge and Keep pill appear BEFORE the typewriter finishes painting,
so a screenshot taken too early shows skeleton rows and reads as a bug; wait
~20s or the stream is still arriving.

## 168. The brief paints like generative UI — the stream paces by document size (user: "will the daily brief render like generative UI? i'd like it to", 2026-07-22) — VERIFIED

It always WAS generative UI structurally: `TodayBrief` composes a real GenUI
document, the answer path sends it through `answerStream.stream(…)` (not
`paint`), so components mount progressively as their lines arrive and declared-
but-unresolved children draw skeletons — the mount law, exactly as §5 of the
build brief specifies. What it didn't do was *feel* like it.

**The cadence was tuned for a sentence, not a composition.** `GenStream` stepped
2–6 characters per 30ms tick — about 133 chars/second. A short prose answer is
~200 characters, so it assembles in under two seconds. The Today brief is
~1,400, and a single `MoneyHero` line is ~400 of them, so it took over TEN
seconds to finish painting. Worse, most of that time bought nothing visible: a
component mounts on its line's FIRST token (the mount law again) and its value
CSV and treemap cells render no incremental change, so the typewriter was
spending seconds on characters that moved no pixels.

**The step now scales with the document**: `step = max(2, min(18, total / 90))`.
Under ~270 characters that floors at 2 and the step stays exactly the old 2–6,
so nothing about existing prose answers changes; a long document steps WIDER
rather than taking longer. The per-boundary pause (150–400ms after a `root`/
`Widget`/`Shelf` line) is untouched — that pause is what gives the assembly its
section-by-section rhythm, and it's the part worth keeping. The brief now lands
in roughly 1.5–2 seconds, still visibly building module by module.

**One streaming artifact fixed in passing.** `KindCountRow.parse` only strips a
COMPLETE `@v:value` / `@t:route` marker, so mid-stream a treemap cell read
" @v" with no colon yet and the whole raw token became the cell's label — the
hero visibly flashed "ETH 95 @v" while its cells arrived. A trailing fragment
that opens " @", carries no space, and is too short to be a real marker is now
dropped until the rest lands. This helps every streamed `TagMap`, not just the
brief's hero.

VERIFIED 2026-07-22 (iPhone 17 Pro sim, frame series at 0.45s): the masthead
appears first with the berry breathing under it while the live wallet/token
reads run (the honest in-flight state), then the document assembles top-down —
synthesis card, hero, tile pair, reading lead, hour strip — complete in about
1.5–2s, with no raw-token flash in the treemap cells.

## 169. The address book — naming is free, watching is the upgrade (user: "lets imagine a user wants to track N wallets but just their addresses and names", 2026-07-21)

The app had TWO naming systems that never met. `WalletStore` held the labels of
WATCHED wallets; `CounterpartyLabels` held names for addresses met in your own
activity — and only the expensive tier had a front door. You could name an
address only AFTER a transaction with it happened to land, there was no surface
listing what you'd named, and unwatching a wallet DESTROYED its name along with
its cursors. Meanwhile the only way to bookkeep an address was to watch it,
which starts six pipelines you didn't ask for.

**One ledger** (`Model/AddressBook.swift`). Every named address, watched or not,
in one store that outlives every watch — because a name the person typed is
their data, not bookkeeping. Migrates both old sources on first launch (neither
is deleted, so a downgrade loses nothing). Watched wallets are book entries that
happen to be watched; the naming cascade in `WalletIngest` and the wallet
switcher both read the book first, so a wallet renamed anywhere reads the same
word everywhere.

**Membership: the copy test.** An entry is something you'd copy to send value or
look up on an explorer — personal wallets, your own accounts, contracts, Safes,
exchange deposits; EVM hex and Solana base58 alike. Emails and phone numbers
fail that test and belong to the phone's own contacts. Crypto-only isn't a
limitation to apologise for: it's what keeps the list scannable at fifty rows.

**Kind is detected, never asked** (`Model/AddressKind.swift`). `eth_getCode`
says contract, Safe's own service says Safe, everything else is a wallet;
`.unknown` is the honest resting state for anything not yet checked. Both reads
are KEYLESS and already ran elsewhere, so naming stays free on the keyed budget.
A kind PICKER would be homework, and the app would know better half the time.
**Only a wallet is a "who"** — it wears the identicon face; contracts and Safes
wear square glyph marks, which is what lets a long book separate people from
machinery with no grouping UI at all.

**Provenance, never inference.** An entry added from a Farcaster/Bluesky profile
remembers where it came from — a pointer captured from a link the app already
verified. What the app will NOT do, now or later without a deliberate ruling, is
GUESS identity across sources ("this email sender is probably this wallet").
A wrong link silently retitles history with a wrong name, and the person can't
see it to correct it. User-asserted or protocol-verified only.

**Three doors, all pre-existing:** the Wallet screen (the book's home, one
section below Watching — §139's one-page manage surface), any transaction's
counterparty pencil (now writes through the book), and the **second-encounter
nudge** (`Screens/NameAddressPrompt.swift`): once is noise, twice is a
relationship, so the prompt appears from the second landed transfer with an
unnamed address — never for one the app can already name itself, and never
again once declined for that address.

**The address card** (`Screens/AddressBookViews.swift`): face, name, detected
kind, the full address with **Copy** (the book's most-used verb, also on every
row — it did not exist anywhere before this), the watch toggle as an upgrade
with its cost stated, your history together pulled from the corpus, and the
explorer door only where an explorer can serve it. Unwatching DEMOTES to the
book: the landed history and cursors go honestly, the name stays.

VERIFIED headlessly (`-addressBook`, `-addressBookProbe`) and on screen: a book
of four resolved as `toly.sol → wallet`, `Uniswap router → contract` (real
`eth_getCode`), `Mom → wallet`, `Main → wallet · WATCHED`, with the square
contract mark and the round faces rendering as designed.

## 170. Watching is capped at five (user: "should we limit people to how many wallets they can watch? like lets say 5", 2026-07-21)

**Five watched wallets.** Watching is the expensive tier — a Zerion
transactions call plus a share of the Portfolio holdings read per wallet, every
foreground, forever, against a key shipped in the binary and shared by every
user. One person watching fifty wallets costs more than fifty people watching
one. The cap converts the worst case into a bounded one.

Five is also where the room's own design already topped out: the switcher chips
crowd past six, and the combined line only starts once EVERY watched wallet has
an aligned sample, so each extra wallet is one more thing that can stall the
crown feature. And it's the honest seam for a future paid tier — wallet count
is the classic gate, trivially explainable, and it degrades no existing data
(unlike gating chains or history depth, which would make the corpus lie).

Four rules the honesty law imposes, all shipped:

1. **Stated before it's hit, never discovered at failure.** At the limit the add
   card's controls are REPLACED by the statement, not disabled — a live-looking
   field that refuses on submit is the §83 dead-control bug. Every other door
   words its own refusal.
2. **No upsell copy until the tier exists.** "Upgrade to watch more" today would
   be fake status. Plain statement now; the same seam becomes the paid door
   later without moving anything.
3. **Grandfathered, never evicted.** An install already past five keeps every
   wallet; the cap gates ADDING only. Dropping someone's sixth wallet would
   delete their data to enforce our cost policy.
4. **One choke point.** `WalletStore.outcome(ofAdding:)` — every door already
   funnels through it, so a new entry point can't side-step the cap. `add()`
   keeps its Bool for the call sites that only branch.

The cap and the book are ONE design: the person tracking twenty addresses names
twenty and watches five. Every door that refuses a watch says so and names the
way that still works — the social doors save the name to the book instead.

VERIFIED headlessly (`-watchCapProbe`): five added, the sixth returned
`limitReached`; on screen, the add card states the limit and the address card's
toggle refuses with "Stop watching one to watch this. Its name stays either way."

## 171. Delight, part two — the moments the wallet work left silent (user: "how would you add surprise and delight and polish the UI?", then "do all these", 2026-07-22)

§79's definition holds and this pass is measured against it: delight is **a real
moment, made visible** — never decoration, never an idle loop. Everything below
is gated on an event that actually happened; the moment any of them could fire
without one, it would be exactly what §79 forbids. Eight, in three families.

**Recognition — the app visibly understanding you.**

1. **The naming ripple.** The best moment in the app, and it was invisible.
   `retitleWalletThings` already rewrites every landed transfer when you name a
   counterparty — so now each row CROSSFADES its title as the change reaches
   it, a beat behind the row above (`rippleIndex`, modulo'd so a long feed
   still finishes quickly). You type one word and watch it travel back through
   months of your own history: the corpus thesis — your record, in your words —
   performed in half a second. Keyed on the title string, so it fires only on a
   real retitle, never on scroll or first appearance.
2. **The kind reveal.** `eth_getCode` answers a beat after a book row is on
   screen; the mark used to hard-swap from round face to square glyph. It turns
   over now — the app worked out WHAT this address is while you watched, and
   that is a real moment.
3. **The avatar hatch.** A resolved ENS avatar settles onto its identicon
   (crossfade + a touch of scale) instead of popping over it — the wallet
   introducing itself. Fires on every fresh watch.

**Identity colour, carried further.** The through-line of the whole session:
faces → tints → the crown pour → the rain → the cards, one colour system saying
who things are at every layer.

4. **The address card wears its own weather.** A wallet's card pours in ITS
   face tint — the same hue its identicon, switcher chip, and combined-sheet
   band already carry, so Mom looks like Mom everywhere. §129-legal: it kept
   the wash exactly where the source IS the subject, and a person's card is
   that case precisely. Machinery (contract, Safe) pours in Casberi's own tint,
   because a contract has no identity to borrow — the round-vs-square rule,
   said in colour.
5. **The rain wears the scope.** Pull-to-refresh in a wallet-scoped feed rains
   in THAT wallet's colour. The crown already retints on a scope switch (§159);
   the refresh that follows now agrees.

**Motion fit-and-finish — gestures we started, finished.**

6. **The marks land.** The balance line draws itself on over 0.8s; its
   transaction dots used to simply exist inside that mask. They wait now, then
   spring in left to right in the order the money moved — the line and the
   events that explain it, shown as cause and effect.
7. **The history cascades.** The address card's "history together" arrives a
   beat at a time (`settleIn`), the sheet grammar it was missing.
8. **The full shelf.** The watch-cap card shows the five faces above the
   sentence. Same facts, warmer voice: a refusal that shows you the collection
   reads as "look what you've got" rather than a scolding — and the faces are
   literally the five, so nothing is dressed up.

**Declined, on purpose:** idle shimmer on treemap cells, pulsing anything,
sound, and any confetti beyond the berry rain's two earned triggers. All eight
above inherit Reduce Motion for free — `settleIn`, `symbolEffect`, the draw-on
and the springs all already honour it.

VERIFIED on the dedicated sim: the full shelf renders five overlapping faces
above the limit sentence, and an address card pours in its wallet's own hue
(confirmed the tint and the identicon share a seed — the pour is the face's
first hue, its top-left, so they agree by construction).

## 172. The brief's surprise & delight pass, and a design polish sweep (user: "how would you improve the surprise & delight in the daily brief? how would you polish the UI", then "do all these", 2026-07-22) — VERIFIED

Six delight items plus a small polish sweep over §166/§167's Today brief,
built from a proposal the user approved wholesale.

**1. The capsule's title travels into the masthead.** The whisper's promise
doesn't just happen to match the masthead's words (§165a/§167) — the TEXT
ITSELF morphs there. A SECOND, independent `matchedGeometryEffect` pairing
(id `"whisperTitleMorph"`, POSITION-only — see `WhisperTitleMorph` in
`AgentBar.swift`) rides inside the same `agentMorph` namespace the bar→surface
shape morph already uses. Position-only on purpose: the two texts are
genuinely different type scales (`subhead13` → `heading22`), and matching full
frames would stretch the smaller glyph run into the bigger one's bounds for a
beat — a visible distortion. The real hazard this item had to solve: the
masthead's real `Text` doesn't mount until `commit()` actually runs, which
trails the whisper tap by 400ms+ (`consumeAskRequest`'s settle delay, then the
compose itself) — well past the ~250ms rise transition's own duration, so
without a bridge there'd be nothing on the far side of the pairing to animate
into. `ShellChrome.risingBriefTitle` is that bridge: set the instant the
capsule is tapped (before `composerOpen` flips), read by a purely cosmetic
proxy `Text` overlaid on RootShell's own composerOpen-driven ZStack — so the
proxy mounts in the EXACT SAME transaction as the capsule vanishing, and the
real masthead simply takes over the geometry pairing once it exists, crossfading in place. Cleared by a guarded 700ms timer (keyed to its own word, so a
fast re-tap's newer title can't be stomped by an older timer) and, as a
safety, whenever the agent lowers.

**2. The total rolls; the delta pill waits for it to land.** `GenMoneyHero`
gained `displayedTotal`/`pillShown` state: on mount (no Reduce Motion, and a
real anchor exists) the total starts at the day's ANCHOR value and rolls to
the current one via `.contentTransition(.numericText(value:))` — the same
odometer idiom `WalletFeedTiles`' own hero balance already uses — so the
number tells the day's story before the pill summarizes it. The pill pops in
~770ms later, once the roll has settled. `TodayBrief.moneyHero` now emits the
RAW total and anchor as two additive trailing args (`WalletMove` gained
`anchorUSD`) alongside the pre-formatted display string, so the renderer can
animate real numbers instead of crossfading opaque text.

**3. The line draws; the endpoint dot lands last.** The hero's balance line now
uses the identical left-to-right reveal mask `GenValueSpark` already wears
(`.mask` + a growing `Rectangle`, `.easeOut(duration: 0.7)`), and flips
`pulses: false, endpointDot: true` on `TokenChartPlot` — a flag flip, not new
chart code — so the static dot (the honest twin of the live pulse, per the
existing 2026-07-11 ruling) appears to "land" exactly when the reveal
completes on it, for free.

**4. A 4th observation family: records.** `TodayBrief.records` checks two
deterministic, RARE-by-construction patterns ahead of the routine
observations: the wallet's best day since watching began (day-bucketed
`combinedValueSamples()`, needs 4+ distinct prior days and 3+ real
day-over-day moves before "record" means anything), and the most reading to
land in a day this month (needs 5+ distinct prior days with reads). Both are
POSITIVE-only by design — celebrating a big drop as a "record" would be
tone-deaf, and there is deliberately no fixed-percentage "big green day"
threshold anywhere: a fixed threshold is exactly the horoscope failure mode
this card's whole discipline (§166) exists to avoid. A record that doesn't
fire produces nothing, same as every other observation here.

**5. The skyline builds; a zero reads as a dot.** `GenBars` (shared by the
brief's hour strip AND every recap's weekly chart — one nicer entrance
everywhere the component is used) now rises from the baseline with a small
per-bar stagger, ordered by RANK not array index — `risingOrder` sorts bars by
height ascending, so the TALLEST bar is the one that lands last regardless of
where it sits in the strip, the assembling-skyline read the user asked for. A
zero count draws a small 4pt dot instead of the old 2px sliver, which read as
a rendering glitch at that height; "deliberately nothing" now looks
deliberate. The treemap's compact cells (`GenMoneyHero.cell`) stagger in
largest-first too — free, since the render order already IS magnitude order
(`WalletIngest.treemapCells` sorts descending).

**6. A soft completion tick.** `.onChange(of: answerStream.completed)`, scoped
to `TodayBrief.matches(currentQuestion)`, fires ONE `DSHaptic.selection()` —
deliberately the lightest tap, not `.success()` again (that already fires the
moment the doc is COMPOSED, well before the typewriter finishes — firing it
twice for one answer would be a redundant buzz, not delight). Scoped to the
brief only: every other answer already reads as "done" at the existing settle
haptic, so a second tick there would be noise.

**First brief ever, marked.** Found while wiring #6: the settle block gained a
first-time-only rain + toast ("Your first brief — I'll have it ready every
morning."), gated by a persisted `today.firstBriefShown` flag — the exact
`bloom.seen.<source>` idiom `MainSurface` already uses for a source's
first-ever landing, applied to the brief's own debut. A dedicated
`firstBriefRainTrigger`, not a reuse of the existing `awayRainTrigger` — that
state's name and doc comment are specific to the away haul, and repurposing
it would leave a future reader wondering why "away" rain played for a brief.

**The polish sweep.** The hero's total moved off `stat24` onto the wallet
room's own `price40` rung — same fact, it was wearing the generic number tier
while `WalletFeedTiles`' hero balance speaks in the rounded money voice
everywhere else; one wallet grammar wins now. Three polish ideas turned out to
be no-ops on inspection, recorded rather than silently dropped: the movers
tile was ALREADY capped at 3 upstream (`TodayBrief.moversTile`'s
`.prefix(3)`) — the 2-mover screenshot that prompted the idea was a data
artifact of the test sim, not a missing cap; `LeadRow`'s thumbnail already
uses `RemoteThumb`'s standard app-icon-squircle radius, the same shape every
other image in the app wears — there was no bespoke "feed radius" to
mismatch. The masthead's scroll-away behavior was PROPOSED and DEFERRED on
purpose: making the eyebrow/title collapse or fade with scroll needs real
scroll-offset plumbing threaded into `Composer`'s already-large ScrollView,
and the risk of regressing an established, working scroll interaction wasn't
worth it for a cosmetic nicety — flagged here rather than quietly skipped.

VERIFIED 2026-07-22 (iPhone 17 Pro sim, `-todayProbe`/`-uiAnswerProbe`/
`-whisperProbe`/`-seedWalletHistory`/`-watchToken`): the composed doc carries
the new raw total/anchor args; the rendered brief shows the price40 total,
the delta pill, cells with values, a drawn line with a landed endpoint dot,
two genuine zero-count dots in the hour strip alongside real staggered bars,
and colored (+/− and flat) watchlist figures. The whisper tap raised the
agent straight into a clean, artifact-free masthead with no ghost/duplicate
title left behind — the transient morph itself resolved too fast for
screenshot-polling to catch mid-flight in this environment (the demo
composed off cached reads), but the mechanism is structurally identical to
the already-proven bar→surface morph, and both its rest states (whisper up;
masthead settled) render correctly with nothing stray between them. The
first-brief rain and toast fired exactly once, correctly, on the very first
non-fallback brief this build ever composed. Build green throughout — two
build races with a concurrent session's edits (`WalletScreen.swift`,
`ThingSheetView.swift`) resolved on retry, touching none of this pass's files.

## 173. Lists are air; parcels are for the reads (user, refined across three observations, 2026-07-22)

The day card is gone from the source-feed row lists. It was doing no
group-work — the DAY HEADER does the grouping — so it was only ever a
surface, and it failed at both extremes the user named across one
conversation: a run of ONE ordinary row wearing a full card is "chrome
around nothing," and a busy day (GitHub, an 86-link RSS sync) collapses the
card into "one long giant slab." A same-day first cut ("a card is a group,
so a single row goes bare") was superseded by this fuller one when the giant
slab surfaced: the real rule is not about run length at all.

**Apple Music is the named model** (user: "when I think of lists, I think of
Apple Music, and Apple Music doesn't use cards in long lists of their
songs"). A homogeneous list IS its own structure; surfaces are spent on
featured content, never on the rows. So ordinary rows now render bare on the
ink — every source shape, every run length — with the day header (stepped up
17→22pt, the display tier, to carry the structure the card used to) as the
only grouping.

**Scope note on §160, not a reversal of it.** §160 boxed the wallet room's
two READS and this morning extended that to the Themes map — and those stay
boxed. The precise rule is: **parcels are for the reads** (heatmap, treemap,
mosaic, leaderboard, lede — the §164 head aggregates) and **for the designed
cards** (the consent card, social PostCard, chat TakeawayCard, the fat
TokenRow — cards by ANATOMY, whose own surface is the row background). Lists
of ordinary rows are air. The payoff reads on the All feed: a token card now
looks FEATURED beside its plain neighbours, exactly the Apple-Music split.

Mechanically one predicate: `runBackground(bare:)` returns `Color.clear`
unless the row `standsAlone` (a designed card) — the same standsAlone the
run-break logic already used, so no new taxonomy. Verified on-sim: All
(mixed, token cards featured), RSS (86 links, no slab), Bluesky (posts keep
their cards), Voice (bare singles under headers).

**Extended to the app catalog** (user: "the App Store also doesn't use cards
for its items in categories, so since those are lists they too should have
the same treatment", 2026-07-22). The category shelves in `AppsScreen`
wrapped each page of three app rows in a `.dsCard()` — the same list-on-a-card
the feeds just shed. Dropped: the shelf rows now sit bare on the ink under
their category header (which already carries the App Store's name+chevron
grammar), horizontal paging unaffected (the `containerRelativeFrame` width
still defines each page). What KEEPS its card, correctly: the "Just added"
Discover story card at the top — that's featured content, the App Store's own
Today-tab grammar, a read and not a list. The rule holds across both surfaces:
lists are air, featured reads are cards.

**The rule sharpened — CONTENT lists are air; control panels keep their card**
(user asked how §173 applies to Settings, 2026-07-22). "Lists are air" read
too literally sweeps in Settings, which is ONE card by §161 — and that would
be wrong. The distinction Apple itself draws is not list-vs-not but
**content-stream vs. control-panel**: an unbounded river of items you scroll
and consume (Music songs, Mail, App Store category browse, our feeds and
catalog) flows bare — the stream IS the structure, the container is chrome; a
bounded, fixed set of controls that belong together as a unit (iOS Settings'
grouped inset cards, a Contact detail, a form, our Settings parcel and Wallet
manage screen) KEEPS its card — the card is doing the grouping, saying "this
is the set." App Store category browse (bare) and iOS Settings (grouped) sit
in the same OS; we mirror both. So the meta-rule under §173: **a card groups a
bounded set that belongs together, or features a read; a content stream flows
without one.** Settings' §161 parcel stays; §173 governs content streams only.

## 174. Named asks widen to publishers, and finally reach the live path (user: "when i talk to the agent i should be able to ask things like 'synthesize my verge feed' or 'what happened in bbc'", 2026-07-22) — VERIFIED

Two gaps, found by tracing the exact recognizer path before touching anything.

**Gap 1 — the wrong scope.** The existing per-source recognizer
(`namedTopicPhrase`, six fixed prefixes: "what's new in", "how's my", …)
matched only `Thing.source` — a BRIDGE ("RSS", "Calendar", "GitHub"). "The
Verge" and "BBC" aren't bridges, they're PUBLISHERS *within* RSS —
`RSSIngest` (and Substack/Podcasts/every social account) already stamps the
publisher's own name in `Thing.authorHandle` (§172's FeedInsight fix
surfaced the same field). So "verge"/"bbc" could never match anything, at
any layer — the bridge-only recognizer had no concept of what's inside a
bridge.

**Gap 2 — recognition never reached the live answer at all.** Tracing
`RootShell.answerDocument` end to end found `contextRecap`/`categoryRecap`
(`KeptAskComposers.swift`) are called ONLY from the kept-pill RE-RUN path —
neither string ever appears in `RootShell.swift`. A FRESH, never-before-kept
"what's new in Calendar" fell straight through to `StatusAsk.pulse` (whose
filler-word gate REJECTS it — "calendar" survives filler-stripping as a
leftover content word, so `pulse` returns nil) and then to `Retriever.rank`
(which has zero awareness of `Thing.source` — it only scores title/tags/
content). The per-source recap only ever worked *after* being kept once. This
was a real, silent, pre-existing gap, not a corollary of the new request.

**The fix, one recognizer for both gaps.** `KeptAskComposers.namedAskTarget`
is now the ONE shared definition (`matchesUpcoming`'s precedent) both
`Composer.recognizeKeptAskKind` (mint) and `RootShell.answerDocument` (the
LIVE path — this is the actual fix for gap 2) call. Widened phrase list
(`synthesize`/`summarize`/`recap` — flagged `synth: true` — alongside the
existing "what's new in"/"what happened in"/"how's my"), then resolved in
priority order: a PUBLISHER/HANDLE match first — fuzzy, case-insensitive,
either-containing-the-other (`bestHandle`), because a publisher's real name
is free text nobody types exactly ("verge" for "The Verge") — then the
existing exact bridge SOURCE match, then an exact catalog CATEGORY match.
`NamedAskTarget` (`.handle`/`.source`/`.category`) carries its own
`keptKind`/`pool(in:)`/`hasRealThings(in:)`, so both callers resolve and
scope identically by construction. `namedTopicPhrase`/`categoryHasThings` in
`Composer.swift` are dead now that both call sites route through the shared
enum — deleted, not left as a shim.

**The verb decides recap vs. real synthesis, but only live.** `synthesize`/
`summarize`/`recap` route the SAME resolved pool through `streamSynthesis` —
the exact primitive `StatusAsk`'s pulse branch already uses (`OnDeviceModel.
synthesisStream`, capped at 16 candidates, the same convention `StatusAsk.
sample` keeps), falling back to the deterministic recap doc when the model
is unavailable or declines. A KEPT pill ignores the verb entirely and always
re-runs the deterministic recap (`handleRecap`/`contextRecap`/
`categoryRecap`) — ruling 13's principle ("a kept ask never re-synthesizes,
it shows what the answer was drawn from") extended from `search:` to
`handle:`/`context:`/`category:` for the first time: a "synthesize my Verge
feed" kept today reads as a live model-written paragraph, but its pill
re-runs tomorrow as the plain counted recap, on purpose.

**New kind:** `handle:<publisher>` (`KeptAskComposers.handleRecap`), the
handle-scoped twin of `contextRecap` — same 3-day/week window widening, same
`recapDoc` shared builder, filtered by the exact, already-resolved
`authorHandle` (never re-fuzzed at re-run time, so a kept pill stays a fixed
lookup forever).

VERIFIED 2026-07-22 (iPhone 17 Pro sim, `-uiAnswerProbe`/`-keepAskProbe`):
"what happened in verge" → "17 things from The Verge in the last three
days." with a real Bars chart and 6 real Verge rows. "synthesize my verge
feed" → genuine on-device model prose ("Samsung is the main thread here...")
scoped to only the Verge pool, with Keep AND Save-as-a-note both offered (the
existing long-prose affordance, unchanged). "what happened in bbc" → fuzzy-
matched to the corpus's real "BBC News" handle, 26 things, 6 real BBC rows.
`-keepAskProbe "handle:BBC News:..."` composed via the kept-pill path and
reported the identical count (26) the live answer showed. Gap 2's fix
confirmed as a byproduct: "what's new in Calendar" — a phrasing that existed
before this session and, per the trace, never actually recapped live — now
correctly returns Calendar's own 3-day recap on a fresh ask, not just after
being kept once.

## 175. The suggestion chips get timely, legible, and diverse (user: "how would we improve also the suggestion chips", then "make all these changes", 2026-07-22) — VERIFIED

Six improvements to the composer's empty-field ask chips (`computeSuggestions`/
`askChips` in `Shell/Composer.swift`), the first half of a two-phase "make the
agent smarter" pass (phase two is the response/question set).

**1. Signals on every chip.** Parity with the kept pills, which have carried a
`· N` digest since §132: each chip now shows a cheap, SYNCHRONOUS count
computed at open — "What's overdue? · 3", "Show Book club · 3", "Catch me up ·
11 new" (the away chip names WHAT landed — "· N new, M mentions" — not a bare
count, the module doctrine §166 at chip scale). Wallet and watchlist show NO
signal: they read live prices/holdings async, and §83 forbids a stale number
wearing a fresh face. One `sig(_ n:)` helper owns the "· " format.

**2. A timely publisher chip.** The one genuinely event-driven chip: when a
publisher (any `authorHandle` — RSS feed, Substack, watched account) dominates
the recent window (≥5 things AND ≥2× the runner-up, over the frozen away
window or last 24h), it leads with a tint dot + tintDim wash and its own count
("What happened in BBC · 26"). Honest by construction — fires only on a real
burst, ages out as the burst recedes. Doubles as the teaching chip for §174's
per-publisher vocabulary, naming a real entity that answers. `timely` is
DERIVED from `kind`, not a stored flag. It shows a SHORTENED name
("DealNews", not the padded feed title) but sends the CANONICAL full handle on
tap (`AskOption.query` reads it from `memoryKey`), so the answer resolves the
exact publisher the chip named — not a fuzzy near-match, since §174's
`bestHandle` ranks by history while `busyPublisher` ranks by recency and the
two can disagree.

**3. A diversity rule.** The four slots span DOORS, not four flavors of one.
`selectSuggestions` pulls timely/away leads first, then diversifies the rest by
a stable-sort round-robin across shapes (recency / money / tasks / entity /
insight): round 0 is one-of-each-shape in rank order, round 1 the seconds, so a
pool heavy in tags doesn't crowd out the money/time/task doors. A shape only
doubles up after every other shape has had a turn; the grid still fills to N
when the pool is thin.

**4. Teaching the widened vocabulary.** The empty field's cycling placeholder
now mixes real-corpus examples that name things that exist and would answer —
"Try: synthesize my Verge feed" when a publisher is busy, "How's ETH doing?"
for a watched token (via `TokensAsk.symbol(of:)`, the one parser of the
"Name · $TICKER" format — a naive space-split would read "Wrapped" from
"Wrapped Bitcoin · $WBTC"). Discovery by example, the only teaching surface the
composer has.

**5. Daypart weighting.** A tiny rank nudge floats the moment's natural ask up:
"What landed today?" in the evening (≥18:00, the same boundary `timeGreeting`
uses), the week recap on Friday. Morning is deliberately absent — the whisper
capsule already owns the day brief there, so a competing chip would say the
same thing twice.

**6. Instant answers for one-liners.** A deterministic answer that composes to
a single bare `Insight` ("Nothing overdue.", a status count) now PAINTS
instead of streaming — the typewriter added a beat of latency before an answer
already fully known. Detected structurally via `GenParser` (the same engine the
renderer uses, indifferent to ref name or line count — mirrors `keepableText`),
never by sniffing line strings; anything with rows/charts/a treemap still
streams module by module.

Cleanup pass (`/simplify`, 4 reviewers): fixed the token-symbol parse
(reuse), the canonical-handle send (altitude), a dead `AskShape.organize` case,
`timely` as computed not stored, the `sig()` helper dedup, round-robin as a
stable sort, `isInstantDoc` via `GenParser`, and hoisted the duplicated
`busyPublisher` scan to one call per open. Skipped: extracting a shared away-
mention helper (pre-existing looseness, intentional terser chip wording) and
lifting `selectSuggestions` to a free type for testability (no test target
exists).

VERIFIED 2026-07-22 (iPhone 17 Pro sim, `-openComposer`/`-uiAnswerProbe`):
chips render with signals and four-shape diversity (away/wallet/Book club/
overdue = recency/money/tasks/entity, wallet correctly signal-less); the timely
DealNews chip fired, led with dot+wash, and showed its shortened name; the log
confirms the slot cap holds (≤3 with the organize hint, ≤4 without). Build
green alongside a large concurrent refactor of `HomeRoute` in another session,
which briefly broke the shared build — retried until it settled; none of this
pass's changes touch those files.

## 176. The agent answers smarter — receipts, more entities, follow-ups, comparatives (user: "how else would we make responses and questions 'smarter'", then "make all these changes", 2026-07-22) — VERIFIED

Phase two of the "make the agent smarter" pass (phase one was §175's chips).
Five upgrades to the answer path, all deterministic, all reusing existing
seams.

**Synthesis receipts.** A synthesized answer (`proseDoc`, a bare Insight) now
carries a "Drawn from · N" footer — the things the model wrote from, shown
below the prose (`appendingGrounding`). Every answer's grounding rows became
TAPPABLE in the process: `groundingLines` now emits each thing's id (arg 4),
which is all `GenRow`'s tap needed — so a receipt row (and every "Found" row)
drills into its thing-view on the agent's Stack (ruling 8). Verified on-device:
"what's going on" → prose + four real tappable rows; tapping one pushed the
Design-review thing-view. Applies to all three synthesis sites (status pulse,
named-ask synthesis, free-text `.synthesis`).

**People join the named-ask vocabulary.** §174 resolved publishers/sources;
this adds person/sender phrasings — "what did Sam send", "anything from X" —
resolving to the same `authorHandle` scope (a sender's name lives there like a
publisher's), via new prefixes plus a trailing verb/pronoun stripper
(`trailingPersonWords`: "what did sam send me" → "sam"). Bare "what's " was
deliberately NOT added — it would fuzzy-match "what's new" to "BBC News".

**Follow-up ellipsis.** After a per-source/publisher answer, a bare "and bbc?"
/ "what about calendar" re-runs the SAME shape (recap vs. synthesize) with the
new entity — the natural conversational follow-up. Stateful (`lastNamedAskSynth`
remembers the last answer's shape, captured before each call resets it); fires
only when the prior answer was a named ask AND the residual resolves to a real
entity (`ellipsisEntity`), so it never hijacks an ordinary short query. The
named-ask block was extracted to `answerNamedAsk` so both the normal path and
the ellipsis call it. Verified: "what's new in Calendar" then "and reminders" →
the Reminders recap.

**Comparatives.** An aggregate count over a nameable period gains its
predecessor — "40 things this week — 9 more than last week" — the same filters
over the window before (`AggregateAsk`'s `.count` case + `priorPeriodLabel`).
Only a real non-zero delta earns the clause (§83). Reads as intelligence, is
pure arithmetic.

**The next-question offer.** After an answer settles, one related follow-up
chip sits in the verb row where the thumb is — a wallet answer → "What about
gas?", a source recap → "Synthesize it instead", the day brief → "While I was
away?". A small deterministic kind→next map (`Composer.nextAsk`), never a
model; nil when there's no clean pairing, and skipped on the "nothing matches"
fallback. Verified: "how's my wallet" → the "What about gas?" chip.

Cleanup (`/simplify`, 4 angles): fixed a double corpus fetch (`answerNamedAsk`
now takes the caller's memoized `allThings()`, restoring the §-21 lazy
invariant), added a `NamedAskTarget.name` accessor so `nextAsk` doesn't
re-switch the enum, special-cased the weekend comparative's prior window (a
2-day span shifted by its own duration lands on Thu–Sat, not last weekend — now
−7 days), and normalized apostrophes in `ellipsisEntity`'s query-word guard.
Skipped two low-value items (a shared root-splice helper, and substituting
`keepableAskKind` for `nextAsk`'s re-run matchers) as documented light
duplication. New DEBUG hook `-ellipsisProbe "<q1>|<q2>"` runs the stateful
two-ask sequence headlessly (it can't be tested across two launches, which each
reset @State).

VERIFIED 2026-07-22 (iPhone 17 Pro sim, `-uiAnswerProbe`/`-answerProbe`/
`-ellipsisProbe`): receipts render + tap through; "what did calendar send"
resolves via the person prefix; the ellipsis re-runs the shape; the comparative
computes ("… more than last week"); the next-question chip appears. Build green
alongside a concurrent `HomeRoute` refactor in another session; none of this
touches those files.

## 178. Tags become invisible infrastructure — the filing surface retires (user: "i feel like the tag feature is not useful... we aren't an organizing app really", 2026-07-22)

Re-ruling on §20/§21, not a reversal of the retrieval-vocabulary framing —
that framing was right, but two hand-filing doors still lived inside it and
both are gone now. **The app assigns, the agent reads, the person never
files:**

- Kept: the `tags` field itself; type tags; bridge/import auto-labels
  (Watchlist, Trending, NFT, Day One's own tags, RSS categories); project
  clustering (a project IS a shared tag, §21 unchanged) and its one write —
  renaming a cluster in project detail; the retriever's 2× tag boost;
  Spotlight keywords; `showtag:` kept pills; `#hashtag` extraction on
  capture (Capture.swift — zero UI, a property of the text itself, not a
  filing act).
- **Retired:** the thing sheet's tag editor (`ThingSheetView` — add/remove
  chips, rename-everywhere, delete-everywhere, all behind the TAGS row's
  tap). The row is now read-only provenance: your own tags keep their hue,
  type tags stay quiet, nothing opens. The composer's `OrganizeCommand` /
  `OrganizeLLM` machinery (`tag X as Y` / `rename A to B`, the strict parser
  and the loose-wording LLM fallback) — deleted outright
  (`Model/OrganizeCommand.swift`, `Model/OrganizeLLM.swift`), along with its
  proposal card, the "Tag your N things" invite chip, and the `-organizeApply`
  probe hook. The parse card (`ParseCard`) no longer offers candidate-tag
  chips on a pasted draft — it previews kind + title only; `chosenTags`
  is gone from `Composer`, and `onCommit` no longer carries a tag list.

Why: the manual doors were the one place tags asked something OF the
person — "you should be filing this" — in an app that was never supposed to
ask that. `tagCandidates()`/`tagPool` survive because they still serve pure
reads: typed-ask tag-word completion, the "Show \<tag\>" chips,
`NavigateCommand`'s tag matching. The empty-tags answer
(`RootShell.tagsDoc`) now says tags arrive on their own rather than
inviting a manual tag.

Files touched: `Screens/ThingSheetView.swift`, `Shell/Composer.swift`,
`Shell/RootShell.swift`; `Model/OrganizeCommand.swift` and
`Model/OrganizeLLM.swift` deleted.

## 179. A watched wallet always shows its hero — last-known when the read fails, sparkline from recorded history (user: "if a user has a wallet i think we should show it no matter what because it is a rich visualization, even if the daily brief says all steady no changes", then "why doesn't it show a sparkline? even if flat", 2026-07-22) — VERIFIED

Two clarifications framed this. First: a steady day was never the gap — the
Today brief's money hero (§166) is gated on holdings EXISTING, not on movement,
so a no-change day already draws the treemap + total with "Nothing moved
today". The ONLY case a watched wallet vanished was a failed live holdings read
(`topHoldingsByWallet` returns empty when the chain is unreachable / rate-
limited), where the hero dropped entirely.

**Last-known fallback.** New `WalletIngest.lastKnownHoldingsByWallet()` rebuilds
each wallet's holdings from its recorded value samples (which already carry a
top-positions snapshot per §-15), stamped `stale` with the sample's time —
reviving the vestigial `HoldingsGroup.stale` field the board's retirement
(§131) left unused. `TodayBrief.compose` falls back to it when the live read is
empty but a wallet is watched, so the rich treemap stays up rather than
vanishing on a transient blip. Bounded to reads within 3 days: a wallet that
hasn't priced in days is either abandoned or genuinely emptied (a sold-out
wallet records no new sample, so its last one just ages), and a weeks-old
treemap marked "as of" is worse than an absent one. Stale cells carry no tap
routes (a sample stores only symbol→USD), the honest limit of cached data.

**Honesty marking (§83).** A last-known read never claims currency: the anchor
line reads "as of Xh ago" (matching `HoldingsGroup.subline`'s own staleness
grammar) instead of the curve's "since" date. `GenMoneyHero` renders that
marker even with no sparkline to host it.

**The sparkline is recorded history, not the failed read (user's follow-up).**
The first cut of the fallback wrongly suppressed the balance sparkline and its
delta along with everything else. But those come from `combinedValueSamples` —
recorded value history, a SEPARATE honest source from the live holdings read.
So they now draw whenever there are ≥2 samples, flat line included (a flat
curve honestly reads "steady"); the curve simply ends at the last-known moment,
which the "as of Xh ago" anchor already dates. Only the TREEMAP's currency is
what "stale" concerns.

VERIFIED 2026-07-22 (iPhone 17 Pro sim; a temporary `-forceStaleWallet` DEBUG
flag forced the empty-read path, then removed): with the live read forced
empty, the hero drew "$164K", a +10.1% delta pill, the ETH/USDC last-known
treemap, a rising green sparkline from recorded history, and "as of 5m ago" —
nothing vanished, nothing claimed to be current. The live path (vitalik.eth)
still draws its normal hero with no stale marker. Build green.

## 180. Two more brief visualizations — what landed by source, and the watchlist drawn (user: "how can we add more visualizations to the daily brief", then "add A and B those are both good components to have", 2026-07-23) — VERIFIED

Asked for more visual density in the Today brief (§166) without reopening the
day-planner lane §101 cut — the user's own instinct ("this isn't really a
daily brief then" if Calendar started listing other days' events) matched the
existing ruling exactly. Four candidate visualizations were mocked up
side-by-side (composition-by-source, drawn watchlist rows, a reading-topic
strip, an avatar cluster); the user picked the first two.

**Candidate A — "What landed" (`TodayBrief.sourceMix`, `GenSourceMix`).** A
mosaic by SOURCE — the visualization the hour strip doesn't answer: the strip
says WHEN, this says WHERE FROM. Gated like `hourStrip` on a dual floor (6+
landed things AND 3+ distinct sources), not just the source count alone — a
3-source day with one thing per source is a trivial partition, not a real
composition. Capped at 4 cells (the money hero's own compact footprint); a
residual folds into a named tail ("and 4 more, elsewhere") rather than growing
the map. Sits right after the hour strip, so the brief's two "shape of the
day" modules read as a matched pair.

**Candidate B — "Movers, drawn" (`TokensAsk.moversTile` → `GenMoversTile`).**
Each watchlist row now draws a tiny sparkline beside its percentage, reusing
`TokenPulse`'s already-cached closes (no second fetch) via
`TokenChartPlot` at 20pt tall. The `MoversTile` wire grammar grew a third
per-row field for the closes CSV, so rows now join on `;` instead of `,` (each
row's own closes are comma-joined) — `tileSafe` was widened to strip `;` too,
alongside its existing `,`/`|` scrub.

**Cleanup pass (4-angle review before commit).** `GenSourceMix`'s first cut
copy-pasted its cell layout and squared share-weighting straight from
`GenMoneyHero`'s holdings mini-map — caught by three of the four reviewers
independently. Fixed by extracting the shared "biggest left, up to three
stacked right" layout into a `MiniTreemap` view and the cell chrome into a
`miniTreemapCellChrome` modifier, both now used by `GenMoneyHero` and
`GenSourceMix`. The extraction also surfaced a latent correctness gap in the
copy-paste: a holdings cell's `n` is pre sqrt-scaled by
`WalletIngest.treemapWeight`, so squaring it recovers true USD proportion —
but a source cell's `n` is a raw thing-count, never scaled, so squaring it
skewed the wash disproportionately toward the top source. `GenSourceMix` now
computes a plain linear share instead of reusing the squared formula. Also
fixed: a stale doc comment still showing `MoversTile`'s pre-candidate-B
grammar; `TokensAsk.Move` dropped its added `closes` field (derivable via
`TokenPulse.shared.pulse(for:)` at the one call site, so nothing needs to
carry a second copy); a redundant ternary in the source-mix residual count.
One reviewer flagged `GenMoversTile`'s tolerant 2-or-3-field row parse as
over-general — kept as is and commented: mid-stream a row's closes are still
arriving, and requiring all three fields up front would hold the symbol and
value off-screen until the whole sparkline lands, against GenParser's own
"any prefix of any document renders" law.

VERIFIED 2026-07-23 (iPhone 17 Pro sim, pinned UDID, both before and after the
cleanup refactor): `-todayProbe YES` over a corpus with two watched tokens
(WIF/ETH) and a mixed-source day composed `mix = SourceMix("What landed", "and
4 more, elsewhere", [Calendar 5, Gmail 4, ChatGPT 2, Tokens 2])` and `tmov =
MoversTile("Watchlist", "WIF|+49.4%|0.0006848,…;ETH|-2.4%|1933,…")`. The real
UI path (`-uiAnswerProbe "How's my day?"`) rendered both live: a green rising
WIF sparkline and a red declining ETH sparkline beside their percentages, and
the source mix's four bridge-icon cells with counts and residual line, paired
directly under the hour strip. Build green.

## 181. The agent opens on the brief — chips docked, keyboard down (user: "make daily brief be the default when a user opens the agent", picked mockup A, 2026-07-23) — VERIFIED

The agent used to rise to an empty composer wearing ask chips — but "How's my
day?" is already the top suggested ask most mornings, so showing the QUESTION
instead of the ANSWER was a wasted tap. Now a bare agent-bar tap lands on the
Today brief itself, with the ask chips docked in a row above the ask bar. Three
mockups were shown (chips-first reference, brief-leads-chips-docked,
chips-ride-the-masthead); the user picked the middle one.

**The seam is the existing `askRequest` door.** The agent-bar tap sets
`chrome.askRequest = TodayBrief.title` (guarded on nil so a surface that seeded
a specific ask still wins), the SAME door the whisper tap and a typed "how's my
day" already use — one `consumeAskRequest → commit` consumer, so all three
reach the one composer and none can drift (the §132 principle). Deliberately
scoped to the agent-bar tap, NOT centralized in the `composerOpen` onChange:
the FAB/Control-Center "compose" intents and the DEBUG probes
(`-openComposer`/`-uiAnswerProbe`) legitimately want an empty field, and
centralizing would seed the brief over them.

**The brief keeps its chips (the one exception).** Seeding via `askRequest` puts
the composer into the ANSWER state, where every rest-screen gate
(`askChips`/`keptAskPills`/greeting) is hidden by its `!answering` clause. A new
`briefLanding` predicate — the brief settled, `turns` still empty, nothing typed
— re-opens exactly the two chip rows beside it, so opening the agent never costs
the "what else can I ask" row. The three rest-chrome gates, which each hand-
rolled `isOpen && !hasDraft && !answering && !isRecording`, were unified into one
`restChrome(keepBrief:)` predicate in the cleanup pass (the placeholder cycle
passes `keepBrief: false` — deliberately off on the landing, whose field reads a
static "Ask about this…"). The landing also keeps the keyboard DOWN (skips the
usual post-answer `fieldFocused = true`): the brief is a screen to take in, not a
prompt to answer; the person taps the field when they're ready. Asking anything
(a chip, or typing) grows `turns`, `briefLanding` goes false, and it's an
ordinary conversation again — docked chips retire, keyboard rises, exactly as
before.

Two cleanup reviewers (simplification, altitude) confirmed the `briefLanding`
clauses are load-bearing (they gate the opposite loading vs. streaming windows,
so the chips appear once on settle, no flicker) and the seed altitude is right;
their one real finding — the diverging hand-rolled gates — became the
`restChrome` consolidation above. The altitude note that an explicit enum
landing-state would beat a derived Bool was considered and skipped: the
derivation is verified-correct, and an enum would touch commit/settle/close for
marginal elegance in a working state machine.

VERIFIED 2026-07-23 (iPhone 17 Pro sim, pinned UDID, before and after the
cleanup consolidation): tapping the agent bar on the feed streamed the brief in
(masthead "Your Thursday brief", the WIF day note, the $1.0M money hero, the
watchlist + up-next pair, the hour strip, the source mix), with the keyboard
down and four chips ("What's going on? · 44", "How's my watchlist?", "Show Book
club · 3", "What's overdue? · 1") docked above the ask bar. Tapping "How's my
watchlist?" settled the brief into a turn, streamed the watchlist answer below
it, retired the docked chips, and raised the keyboard — the ordinary
conversation state, unchanged. Build green.
## 182. The wallet manager stops looking like a settings page (user: "it still looks like a settings feature and not like a pure wallet manager purposely built for adding the addresses… give me three mockups", then "lets do your recommendation", 2026-07-22)

Recommendation A (the roster) with B's omnibox grafted in, from three mockups
(`design/wallet-look/wallet-manager-mocks.html`). The old screen was an
insetGrouped List of section cards — watching, add, chains, disconnect — at
equal weight: a settings page's grammar wearing wallet content. This inverts
the three things that made it read that way.

- **Identity leads.** The watched wallets render as a horizontal shelf of
  faces — the Stories grammar the source chips already taught — with their
  REAL empty slots drawn up to the cap (dashed rings, tap to focus the
  omnibox). The cap stops being a sentence you might hit and becomes a shape
  you can see filling; "N of 5 watched" is now ambient text under a shelf
  that already showed you the same fact. Tap a face to rename (unchanged),
  long-press for Copy/Remove (the gesture a horizontal shelf actually
  teaches, replacing the swipe-to-remove a shelf can't perform).
- **Adding is the primary act, not an errand.** One field under the shelf —
  placeholder "Address, ENS, .sol — or search your book" — both watches on
  submit AND filters the address book live as you type (the SAME binding
  drives both, so there's one input, not two). Connect demotes to a quiet
  secondary row beside it; the old full-prominence blue capsule died because
  the shelf's own dashed slots now carry that invitation.
- **Plumbing collapses to one door.** Chains and Disconnect move to a pushed
  `WalletConnectionScreen`, reached by a single "Connection" row. This AMENDS
  §139 ("manage is one page, no doors"): §139 killed doors to READS — the old
  per-wallet screen's safety facts had a better home in the Worth-a-look tray.
  Configuration nobody revisits isn't a read, and it was charging every visit
  to the manager rent it shouldn't pay.

**Face shape, corrected mid-build (user: "i thought we were going to add it
like the roster are we not?").** The approved mockup drew round circular
faces; the first build reused `WalletFace`'s existing app-icon SQUIRCLE
(the shape every other use of that view has always worn — rename rows, the
switcher chips, transfer stages) for cross-screen consistency, which quietly
walked back the mock's circles without a ruling. Fixed with a `circular`
parameter on `WalletFace` (default false, so every existing call site is
untouched) — true only for the roster's filled and empty slots. The book
below keeps the squircle: a roster of PEOPLE reads as faces, a ledger of
mixed wallets/contracts/Safes keeps the mark that already tells them apart.

**A bug found and fixed along the way:** the manager's last row (Disconnect,
now Connection) sat partly under the floating agent bar with no bottom
clearance — a pre-existing issue this redesign exposed by giving the screen
enough content to reach that edge for the first time. Fixed with the same
`Color.clear.frame(height: ShellMetrics.bottomInset - 40)` spacer row
`FeedScreen` already uses for the identical reason.

VERIFIED on-device end to end: the roster renders a real ENS avatar in a
circular slot with accurate dashed "Watch" rings for the remaining cap, the
omnibox's live filter narrows the book correctly, the Connection door pushes
`WalletConnectionScreen` (all six chains, correct summary text, Disconnect)
and the system back chevron pops it cleanly, and every existing squircle use
of `WalletFace` elsewhere in the app is confirmed unchanged.

## 183. A tap-coordinate lesson, recorded so it isn't relearned (2026-07-22)

Paid for over roughly ninety minutes of this session: the on-device Connection
door appeared completely unresponsive to taps — through a `NavigationLink`
rewrite, a plain-`Button` rewrite, multiple fresh app relaunches, and a device
log capture — before the actual cause surfaced. It was never the app: every
tap issued to `mcp__Claude_Code_iOS_Simulator__control` had been sent in
SCREENSHOT-PIXEL coordinates (~920×2000, the size a screenshot displays at)
rather than the tool's own DEVICE-POINT coordinate space (402×874 for this
simulator) — a ~2.29× error on both axes. Large targets (a 60pt face, a
full-width book row) absorbed the error by accident often enough to look like
things were working; a single-line settings row did not, which is what made
it look targeted rather than systemic.

The tool states its coordinate space explicitly on `attach`
("Coordinate space for tap/swipe: WxH points") — call that, or derive the
scale from a screenshot's reported pixel size divided by the device's point
size, BEFORE trusting raw pixel coordinates read off a displayed image.
Symptom to recognize next time: a control that renders correctly, that the
same code pattern elsewhere in the app already proves works, and that fails
identically across unrelated rewrites of the code underneath it — that
combination points at the harness, not the view.

## 184. The manager pattern, generalized — roster for people, ledger for topics (user: "should we do roster in the feeds like the wallet", 2026-07-23)

The wallet manager's rebuild (prd §182) wasn't really about wallets — it was
three moves any watch-list screen needed: identity leads, one omnibox both
adds and searches, plumbing demotes to a door. Applied to Farcaster, Bluesky,
and RSS (`HandleSetupScreen`, shared by Farcaster/Bluesky/Pinterest/Substack/
Reddit/YouTube/Podcasts, and `RSSScreen`), with one split the wallet didn't
need to make: **a watched Farcaster/Bluesky account is a PERSON — the same
shape as a watched address — so it gets the wallet's own face roster; a
followed channel or feed is a TOPIC, not a person, so it stays a square-marked
ledger.** Mocked at `design/manager-look/ledger-mocks.html` (three shapes: a
Farcaster roster-over-ledger, RSS as the reference pure ledger, Tokens as a
third proof point deferred to a follow-up sweep) before any code changed.

**Ruling: round is a person, square is a topic — standing rule, every ledger.**
`AddressMark` already drew this line for the address book (a face for a
wallet, a square glyph for a contract/Safe). It now generalizes: Farcaster
channels, Bluesky feeds, and RSS publications all render as SQUARE marks
(`circular: false` on `RemoteThumb`/`BridgeIcon`, the already-existing
app-icon squircle — no new component needed, since square was already each
view's *default* shape and the old rows had opted INTO circular by mistake).
A face — a roster slot, an address book entry, an author avatar — stays
round. One glance down any ledger now tells identity from topic.

**The roster has no cap, so no dashed slots.** The wallet's emptiest-slots
delight draws a hard 5-limit (prd §170); Farcaster/Bluesky watch lists are
unbounded and keyless (a follow-import alone can land hundreds), so the
roster scrolls horizontally and ends in one dashed "+" that focuses the
omnibox — an invitation, not a countdown.

**Every per-account action moved off the row and onto `SocialProfileCard`** —
the same card a post's byline already opens (`casberi://person/<Source>/
<handle>`). Likes/Mentions switches, "Watch their wallet," and "Who they
follow" (previously three inline row elements that would not have survived a
50-account ledger) are now reached by tapping a roster face. The switches
carry the bridge's own explanation (`HandleBridge.watchFooter`) as a caption
beneath them, moved verbatim from the old row footer. `SocialProfileCard`'s
tray grew from height 460 to 560 to fit the new content — no internal scroll,
so the fixed detent has to be generous.

**One omnibox replaces the old two-field screens.** Farcaster's separate
"name" and "channel" fields, and Bluesky's separate "name" and "feed search"
fields, collapse into one `query` binding. On Farcaster, a leading `/` follows
a channel by name (`FarcasterStore.normalizeChannel`); anything else searches
people. On Bluesky, plain text searches people AND feeds concurrently
(`async let`, both `debouncedSearch` calls racing, merged into one
`OmniHit` list so search-result rows share one grammar — a feed's subtitle
just reads "Feed"). Typing also filters the field the same way it always
did — the omnibox is search AND add in one input, the wallet's own pattern.

**Recents dropped, following prd §182's own precedent.** The old
`RecentThingsSection`/cached-`recent` query is gone from both
`HandleSetupScreen` and `RSSScreen` — the feed already shows what landed, and
a manager screen manages rather than previews. Knock-on: the proof-line
facepile (`BridgeSyncStatusRows(faces:)`) depended on that cache and is gone
too; the plain count-up result text carries the connect-time proof now.

**Deferred:** Tokens and Stocktwits (watchlists of assets, not people or
publications — a token's mark is a coin logo, arguably round, "worth a
ruling" per the mock) are the pattern's next candidates but weren't touched
this pass — flagged as a follow-up sweep rather than pushed through
unreviewed.

Build green (`xcodebuild … build`, 2026-07-23).

## 185. The asset roster — every manager is one shelf of circles (user: "circles", then "why wouldn't we do the same horizontal row treatment", 2026-07-23)

The pass that finished the manager family. §182 gave the wallet a roster of
addresses; §184 gave the social screens a roster of people over a ledger of
topics. Tokens and Stocktwits were the two left, and they forced the question
§184 had ducked: **what is an asset?**

**Ruling one — "circles".** A token ships round coin art; a stock ships none.
Clipping a coin into a squircle reads as a mistake (the 2026-07-10 chip lesson
in reverse), and giving a stock a fake logo or a generic "stock" glyph would be
a mark that names nothing. So a stock wears its TICKER in a round disc
(`TickerDisc` in `Screens/AssetRoster.swift`) — a coin without art, honest to
the material, since a ticker IS the symbol. The mark grammar across the whole
app now reads: **round is a person or an asset, square is a topic** (a channel,
a feed, a publication, a contract glyph). This supersedes §184's cruder
"round = person, square = everything else".

**Ruling two — the shelf, not the table.** Asked why assets wouldn't get the
same horizontal treatment, the honest answer was that they should. The argument
against was the price COLUMN: a vertical ledger lets you scan deltas down and
compare. The argument that won: comparison is a READING job, and reading lives
in the feed (the movers tile, the chart things) — a manager only owes you add,
remove, and reorder. So `AssetRosterShelf` / `AssetRosterSlot` carry each asset
as a circle with its symbol, live price, and signed delta whispered underneath,
and every watch-list manager in the app is now the same shelf.

**What the shelf costs, accepted with the ruling.** The sparkline and the
scan-down price column are gone. Swipe-to-unwatch becomes a HOLD (the roster's
own gesture everywhere else), so the shelf states its gestures in its note line
("Watching 4 · tap for its chart, hold to unwatch") — a shelf can't demo a
swipe, which also retires this screen's `SwipeHintNudge` coach.

**"My order" survives as a live control, not a dead one.** Drag-to-reorder was
the vertical list's; a horizontal drag-reorder is a custom gesture over a
UIScrollView — the exact fight the retired Home board lost (§131). Rather than
leave a sort mode with no way to set it (the no-dead-controls rule), manual
order is set one coin at a time via **"Move to front"** in the hold menu, which
saves the whole sequence the way the drag did. The sort menu moved from the old
section header to the toolbar, since the shelf has no header.

**Two things got better on the way.** The Tokens watchlist row was never
tappable — the shelf's tap opens the token's chart sheet, so the chart is newly
reachable from its own manager. And Stocktwits' rows now carry a live day quote
(`StockChart.fetch`, the same read the chart sheet does, concurrent per ticker),
where before they showed only a watched-since timestamp.

**Honesty details worth keeping.** A price we couldn't reach renders NOTHING,
never a dash — a dash in a price slot reads like a number. Tokens' figures come
from the same `TokenPulse` cache the feed reads, so manager and feed can never
disagree about which tokens moved. Stocktwits' per-post Bullish/Bearish stays
per-POST in the feed, where it's the author's own call — the roster invents no
per-ticker sentiment.

Also in this pass, matching §184: the header coin cards and section furniture
came off both screens, and Stocktwits' "Latest takes" preview retired under the
same recents ruling.

Build green (`xcodebuild … build`, 2026-07-23).

## 186. The two-state setup screen — connect is a form, connected is a manager (user: "the other manage / connect pages all have a similar shape, and feel like forms… how would you improve the template", then "nah, I like the state today for the form, it's important to know what the steps are. but lets change the connected pages how you recommend", 2026-07-23)

The manager pattern's last frontier: the ~20 setup screens that aren't
watch-lists. Their defect was never the form — pasting a key IS a form-filling
moment — it was that **the screen never changed state**. Steam showed its API
key and profile fields forever; Mail kept app-password boxes on screen for
months; the eleven keyed bridges kept numbered setup steps you finished in
week one. A person opening a connected bridge isn't there to re-read
instructions; they're there to see it working.

**Ruling: State 1 is kept EXACTLY as it is.** A mock offered a "consumer"
reorder of the unconnected screen (ghost preview promoted to hero, steps
collapsed behind a disclosure, step 1 as a link capsule). The user declined:
*"it's important to know what the steps are."* The connect form keeps its
steps, its fields, its ghost preview, its ordering — nothing about the
pre-connect screen changed in this pass, and future passes shouldn't quietly
erode it either.

**Ruling: State 2 is new.** The moment a connection verifies, the form retires
behind one door and `BridgeConnectedState` (`Screens/BridgeConnectedState.swift`)
takes the screen: **identity → live proof → capability sentences → one ⚙︎
Connection door**. The door opens `BridgeConnectionSheet`, which renders the
screen's OWN existing form sections verbatim plus Disconnect — the form moved,
it was not rewritten. A sheet rather than a push, deliberately: these screens
are themselves pushed, and `HomeRoute.Node` would have needed a case per
bridge (or one giant switch) to route a destination that differs per bridge.

**Unified with `BridgeDetailScreen` by construction.** The proof line and the
capability sentences are read from `BridgeStore` — the same records that
screen renders — so a bridge can never tell two different stories about
itself on two surfaces. That was the alternative's real cost: building this
inside each setup screen would have made a third copy of the same screen.

**Identity is never invented — measured, not assumed.** The mock cheerfully
showed "Alex's Workspace" for Notion and "Alex" for Spotify. Neither exists:
`TokenVault` holds a secret and nothing else, Spotify's PKCE flow stores only
tokens, and Twitch caches an opaque `twitch.userid`, not a login name. Only
three bridges actually hold an identity — **Steam** (`profile`), **Mail**
(`address`), **Obsidian** (`vaultName`) — plus **Exchange**, whose identity is
its §163 permission VERDICT ("Read-only key · the venue confirmed it can't
trade or withdraw"), which is the most meaningful line that screen could
possibly lead with. Everything else passes `identity: nil` and leads with the
bridge's own name over a truthful note about HOW it connects. Fetching display
names purely to decorate a header is a follow-up, per-bridge, not a licence to
guess.

**The proof pill waits for a real sync; capabilities don't.** Found live: a
credential can be stored while `registerConnected` has never run (a bad key,
a first sync that failed), leaving no `BridgeStore` record — and the screen
rendered as just identity + door, barren. Fix: `capabilitiesFallback` carries
each bridge's static can-do sentences (`TokenBridge.canLine` and friends) for
that state. The distinction is the honesty rule doing its job — **a capability
is a fact about the bridge, safe to state early; a proof is a claim about what
happened, so no pill until something did.**

**Also in this pass:** `TokenBridge.credentialNoun` (each venue's own word —
"integration secret" for Notion, "personal access token" for GitHub — since
telling someone their "key" is stored when the site called it a secret is a
small lie on the one screen that's about trust). And **Shopify** got the
§184/§185 ledger treatment rather than a two-state flip: it was the manager
pattern hiding in a form (paste a store, list, swipe to remove — RSS's exact
shape), so the omnibox leads and stores wear SQUARE marks, being publications
rather than people or assets.

Applied to: the 11 keyed bridges (one `TokenSetupScreen` rework), Steam, Mail,
Twitch, Spotify, Obsidian, Exchange, and Shopify.

VERIFIED 2026-07-23 (iPhone 17 Pro sim, pinned UDID): a stored Readwise token
renders the connected state — mark, "Your access token · stored in this
iPhone's Keychain", the "Reads your highlights." capability, and the
Connection row — with NO proof pill, correctly, since that bogus key never
synced. Tapping Connection opens the sheet carrying the untouched form: the
three numbered steps, the token field, the honest "couldn't refresh" line, the
Keychain footer, and Remove token. Build green.

## 187. Three fixes to the brief landing — one scrolling chip row, no chips the brief already answers, and a `.link` is not a read (user: "i thought the mockup we did had scrolling horizontal chips, but in my app they are stacked", "daily brief tells me about my reading but lists my music", "it also has two wallet chips which is redundant", 2026-07-23) — VERIFIED

Three reports against §181's landing, all real.

**The chips stacked instead of scrolling.** The docked row was a `FlowRow`,
which WRAPS — and these chips are wide once they wear their signals ("What's
going on? · 44"), so under the brief they stacked one-per-line into a tall
column instead of the single row the mockup drew. Both docked rows (`askChips`
and `keptAskPills`) are now one horizontally scrolling row each, the same shape
`takeChips` already used. Width stopped costing height, so the suggestion set
grew 4 → 7 slots; what doesn't fit slides.

**Two wallet chips, both redundant.** "How's my wallet?" and "How's my
watchlist?" were being offered while the brief's money hero and movers tile
were ON SCREEN answering exactly those questions — and "What's overdue?" beside
a next tile already reading "Book dentist is late". A chip offering an answer
the person is looking at is the chip-shaped form of a dead control: it can only
re-state what's already there. `dockedSuggestions` now drops the kinds the brief
answers (`wallet`, `watchlist`, `overdue`, `today`) on the landing only, so the
row spends its width on what the brief DIDN'T say. `upcoming` deliberately
stays: the brief names the single nearest deadline, that ask lists the rest.

**A `.link` is not a read.** `reads()` — which feeds the Reading card, the
dominant-topic observation, and the reading record — filtered `.link` things
minus MARKETS/WALLET sources only. But `.link` is the app's catch-all for "has
a URL", so a Spotify track, an Apple Music song, a Twitch stream, a Steam game,
a Pinterest image and a Bitrefill order all wear it too: hence a brief that
announced your reading and then listed your music. Now scoped against
Markets/Wallet/**Media**/**Shopping**, still by the catalog's own category
vocabulary so a new source in an excluded category is handled for free, and
still permissive by default so a pasted link, an RSS article, a Substack post
(group `Reading`) or a subreddit post all still count. This is the SECOND time
this exact leak has been caught on-device (Markets/Wallet, 2026-07-22); the
lesson is recorded in the function's own doc comment.

**One subtle thing the fix would have broken.** `AskMemory.shown()` — §175's
tap-learning decay — was guarded by `chrome.askRequest == nil`, on the sound
old rationale that a handed-off ask fills the field and HIDES the chip row, so
that open must not count against the chips. But §181 made every agent-bar open
a hand-off, which would have silently stopped the decay running at all on the
main path: no chip could ever be demoted again. The brief landing is now an
explicit exception — it hands off an ask AND docks the chips in view, so it
counts, minus the kinds `dockedSuggestions` drops (a chip that never appears
must not decay for having been "offered").

VERIFIED 2026-07-23 (iPhone 17 Pro sim, pinned UDID): tapping the agent bar
lands the brief with the chips in ONE scrolling row — "What's going on? · 98"
and "Show AAPL · 5" side by side, a third scrolling in from the right — where
the same corpus previously stacked four chips vertically including "How's my
watchlist?" and "What's overdue?". `askTiles:` logged the full 7-slot selection
(`pulse, watchlist, showtag:AAPL, overdue, wallet, showtag:BRK.B, upcoming`),
confirming the landing filter drops `watchlist`/`overdue`/`wallet` and docks the
four additive ones. The Reading card read "Bond Movie Filming Locations Map ·
RSS", a real article. Media exclusion confirmed by construction through the
catalog: Spotify/Apple Music (`Listening`), Steam (`Games`), Twitch
(`Watching`) all resolve to `Media`; Substack (`Reading`) still counts. Build
green.

## 188. Connect a wallet app — a real button, and not claiming `wc:` stops meaning "no wallet" (user: "the 'connect a wallet app' doesn't work… also, it should be a button not a link", 2026-07-23)

Two faults in one row, one visual and one real.

**It read as a link because it was built like one** — a link glyph, body text on
a plain row, no fill, `.buttonStyle(.plain)`. §182 had deliberately quieted it
so it wouldn't compete with the roster's dashed slots, and quieted it past the
point of looking tappable. It's now the same filled capsule the omnibox's Watch
wears, since connecting a wallet is the screen's second real verb, with the
"read-only, never signs" line moved OUT of the button and under it — a button
says what it does in as few words as it can.

**The real bug: `canOpenURL("wc:")` returning false was treated as "no wallet
app is installed".** That inference has quietly expired. `canOpenURL` is still
the only trustworthy read of the scheme (both `UIApplication.open`'s completion
and SwiftUI's `openURL` report success for an unhandled `wc:` while
LaunchServices fails it asynchronously — measured 2026-07-16, unchanged), but
the SCHEME is no longer a proxy for the app: wallets increasingly register a
universal link (`metamask.app.link/wc?uri=…`) and never claim bare `wc:`. On
such a device the screen told a person with a wallet on their home screen that
they had none, and stopped.

**The fix is a route, not a better error.** `WalletConnectBridge.connect` takes
an `offerManualPairing` callback; when nothing claims the scheme it hands over
the pairing URI and **keeps the settle listener running** while the person
pastes it into their wallet's own scan / "connect with link" screen — every
WalletConnect wallet has one, and the approval it produces is the same approval
the direct open would have produced. The screen shows the URI with a Copy
button and says it's still waiting.

This deliberately reverses the 2026-07-16 early return, whose reasoning was
recorded and is worth preserving: returning immediately avoided a button that
span for the full five-minute timeout over a no-wallet we already knew about at
second one. That was right *while this branch had nothing to offer*. Now it
does, so waiting is the correct behavior — the person is mid-paste — and the
button's own tap-to-cancel is the way out. `.noWalletApp` survives for the
probe and for callers that pass no handler.

Knock-on: a `timedOut` now picks its words by whether the URI was on screen —
"approve the request in your wallet" describes a tap that never existed if the
person was pasting, so that path says the link expired and offers a fresh one.

VERIFIED 2026-07-23 (iPhone 17 Pro sim — the ideal case, since a simulator has
no wallet app and `canOpenURL` is always false, which is exactly the branch
that used to dead-end): the button renders as a filled capsule; tapping it
flips to "Waiting for your wallet — tap to cancel" and reveals the minted
`wc:460f836c…` URI with Copy and the still-waiting line, where the old build
ended at "No wallet app on this iPhone". The handshake probe separately
confirms the proposal still mints with `methods=0 events=0`. Build green.

## 189. The Wallet manager below the shelf — one shape, one font, four slabs (user: "we have different fonts, different shapes, and I think to myself, how would Cash App do this screen", then "yes! this is what I want", 2026-07-23)

The shelf was right; everything under it had accumulated. A census of what was
actually on screen: a recessed field with a side pill, a full-width capsule
with a caption, three paragraph footers, a headed section with a blue text link
and an unbounded row list, and a gear row — **six shapes and four type rungs**,
each defensible alone and a collage together.

**The rule, not new art: below the shelf every block is the same slab.** One
height (56), one radius (`DS.Radius.widget`, the tile radius §8 already
sanctions), in `Screens/WalletSlabs.swift` — `WalletSlabField`,
`WalletSlabButton`, `WalletSlabDoor`. The only round things left on the screen
are people. What ships is four slabs and one sentence: field, connect, the
promise, and two doors.

**The field swallowed its own verb.** Field-plus-side-pill read as two controls
for one act; WATCH is now text inside the same slab, dimmed until there's
something to act on (§83 — a control states its own disabled state). A filled
capsule inside a filled well was the "button in a button" doing most of the
visual noise.

**Doors wear their facts, so nothing hides.** "Address book · 4 names" and
"Connection · Ethereum, Base +4". The address book moved to its own page
(`Screens/AddressBookScreen.swift`, route `.addressBook`) for the same reason
the chains did in §182 — it was the largest furniture on a screen whose job is
the shelf and the one field.

**One casualty worth naming: the omnibox stopped doubling as the book's
filter** (§184's clever bit, and the reason its placeholder had to say "or
search your book"). The book searches itself now. One field per job is the
simpler trade, and it's what let the placeholder shrink to "Address, ENS,
.sol".

**Words: ~70 → 9.** The three always-on footers are one line — "Read-only —
watching can never move funds." The other two moved to the doors that own them:
where activity is read now lives in Connection, what naming costs in Address
book. The Connect button's caption went too — it said the same thing as the
sentence two lines under it.

**The approved mock had to be corrected on one point.** It set the tappable
slabs in SF Rounded, Cash App style. That breaks a standing rule
(`Typography.swift`, 2026-07-09): SF Rounded is the DISPLAY tier only —
"functional text (body, rows, labels) stays SF Pro Text, which scans crisper at
UI sizes and keeps the app feeling native." The complaint was *inconsistency*,
and consistency is the fix, so every slab is the text face at one weight and
the rounded face stays where it already lived: the large nav title. Mock at
`design/manager-look/wallet-simple-mock.html`.

VERIFIED 2026-07-23 (iPhone 17 Pro sim, seeded book + a watched wallet): the
screen renders as the mock — field slab, blue Connect slab, the one gray line,
then "Address book · 4 names" and "Connection · Ethereum, Base +4" at matching
height and radius. The Address book door pushes to its own page carrying the
search slab, all four names, and the naming paragraph. Build green.

Housekeeping: this pass also resolved a THIRD prd numbering collision — two
sections had been written as §187 by concurrent sessions. The brief-landing
section (first in file) keeps 187; the wallet Connect-button fix became 188.

## 190. The slab, generalized — one shape per control, one signature shape per page type (user: "how would you make the rest of the app catalogue manage pages stupid simple like you have here, and perhaps different types of pages have different shapes… I do not want to change any of the top shelf rows of avatars", 2026-07-23)

§189 fixed one screen. This makes its rule the app's, across every manage page
in the catalog — and answers the "different types have different shapes"
instinct, which turned out to be right in a specific way.

**The kit** (`Design/DSSlab.swift`, graduated from `WalletSlabs.swift`): one
height (56), one radius (`DS.Radius.widget`), four controls —
`DSSlabField` (input with its verb inside), `DSSlabButton` (the one filled
block), `DSSlabDoor` (title · fact ›), and the new `DSSlabSwitch` — plus
`DSSlabNote` for the screen's single sentence and a `dsSlabSection()` modifier
so a slab stack can't drift from the Wallet's spacing.

**The type grammar — each page type has ONE signature shape:**
- **Watch-list pages** (Farcaster, Bluesky, Pinterest, Substack, Reddit,
  YouTube, Podcasts, RSS, Tokens, Stocktwits, Shopify, Kalshi) → the FIELD
  slab. Field, status, one sentence; then the page's own content rows.
- **Connected managers** (11 keyed bridges + Steam, Mail, Twitch, Spotify,
  Obsidian, Exchange) → the DOOR slab. One edit to `BridgeConnectedState`
  reached all eighteen.
- **Picker pages** (OpenSea, GeckoTerminal) → the SWITCH slab. Each chain's row
  IS that screen's connect verb for one lane, so it earns a full block instead
  of a line in a stacked toggle list inside a card.
- **Seat pages** (Peer, Privacy Pools) → one switch slab and one sentence. When
  no wallet is watched the prerequisite is a DOOR slab, since it navigates — a
  disabled switch there would be the dead control the honesty rule forbids.

**What is deliberately NOT a slab:** the shelves and rosters (the ruling kept
them explicitly — "I do not want to change any of the top shelf rows of
avatars"); a page's own content rows, which wear §184/§185's marks and are the
person's data, not controls; the numbered steps of a pre-connect form (§186);
and Disconnect, which stays the quiet centered red row — destructive sits
outside the rhythm on purpose.

**The companion rule did most of the work: one gray sentence per screen.** The
"form feel" was never really the controls, it was two or three footer
paragraphs stacked under them. Kalshi's 34-word field footer became "Public
odds only — nothing here places a trade."; Stocktwits' 39-word one became
"Read-only — nothing here trades or sees a portfolio."; Tokens', Shopify's,
Farcaster's and the chain pickers' went the same way. Everything longer already
lives on the catalog product page the person arrived from.

Two smaller consequences, both deliberate: `BridgeFieldRow`'s fixed affixes
("farcaster.xyz/" wrapped around the field) are gone — a slab holds one input,
and an affix was a third shape inside the second one, so it folds into the
placeholder, which reads the same and draws less. And the section headers
("Add a username", "Chains", "Watch a market") went with the furniture: the
placeholder says what to type and the verb says what happens.

VERIFIED 2026-07-23 (iPhone 17 Pro sim): Farcaster renders field slab
("@name, or /channel" · ADD), status, "Public posts only — no password,
ever.", then the untouched roster and its topic rows. GeckoTerminal renders
nine switch slabs, each a full block with live state, no card and no
paragraph. Caught live and fixed in the same pass: the handle screens' verb
still read "Add" beside neighbours reading "WATCH" and "FOLLOW" — the exact
inconsistency this pass exists to remove. Build green.

## 191. The product pages, checked against the slab pass — one real bug found, no shape problem (user: "now what about the app catalogue individual app pages, is there a way you would make them stupid simple", 2026-07-23)

Checked live rather than assumed. Unlike the manage pages (§189/§190), the
product pages (`AppDetailScreen`) don't have a shape-consistency problem: one
column, one preview card, one Connect capsule, App-Store grammar throughout.
No slab pass warranted here — applying one would have been solving a problem
that doesn't exist.

**What was actually wrong, found by testing an offer with no authored preview
doc (Coinbase):** the fallback row repeated `offer.tagline` **verbatim** — the
exact sentence already shown one line above it, under the header. Ten offers
hit this path (1Claw, Bankr, Bitrefill, Coinbase, Contacts, HomeKit, Kraken,
Peer, Privacy, Venice — computed by diffing `BridgeCatalog.offers` against
`StorePreview.doc`'s case labels). Fixed with one line that adds a fact
instead of echoing one: "Lands in your feed the moment you connect." (WHEN,
since "What it does" already covers what).

**A second bug surfaced fixing the first:** the old fallback also rendered
after connecting — a static teaser row that never updated, sitting under a
button that now says Open. The exact "form that never changes state" defect
§189 fixed on the manage pages, just not yet noticed here. `whatLands` now
retires entirely once connected; the promise is redeemed the moment Open
replaces Connect, and the real feed answers the question the section exists to
ask.

**Flagged, not fixed:** `offer.summary` length varies 8–107 words with no
consistency rule (Wallet's is a 107-word essay; Notion's is one paragraph).
Real, but a copywriting call across a dozen offers' marketing text, not a
shape bug — left for the user's own editorial pass rather than rewritten
unbidden.

VERIFIED 2026-07-23 (iPhone 17 Pro sim): Coinbase now shows one honest line, no
duplicate; Notion's real preview card renders unchanged, confirming the fix is
scoped to the no-doc fallback only. Build green.

## 192. The three-beat summary rule, and where it actually applies (user: "what consistency rule would you apply", then "yes i agree it's important. show me the scannable version that keeps the content but displays it differently", then "and so we can now apply this to the other places in the catalogue that do this too right?", 2026-07-23)

**The rule**, codified rather than left implicit: every offer's `summary` is
Hook (1 sentence, payoff only) → Mechanism (1 sentence, credential + where it's
stored, omitted when there's no credential) → Boundary (1 sentence, MANDATORY
whenever money/credentials/writes are involved, always last, always leads with
the capability word — "Read-only…", "No account…"). A flat word cap was
rejected: pulling the real text showed Coinbase/Kraken's extra length is the
§163 permission-check disclosure, load-bearing trust content the honesty rules
require, not padding — a cap would have forced cutting it.

**Wallet was the one genuine outlier.** Its 107-word summary had a real
enumerable feature list (approval alerts, delegation warnings, address-
poisoning detection, gas tracking, Aave/Morpho positions, the Safe queue) fused
into a single 60-word run-on clause. The user confirmed that content matters —
Wallet's most differentiated capability shouldn't be deleted to fit a rule.
Fix: `Offer` gained a `features: [String]` field (empty for the other 54
offers) rendered via a new shared component, `Design/DSSlab.swift`'s
`DSCheckList` — promoted out of `BridgeConnectedState`'s `capabilities(_:)`
(previously private to that file), so the PRE-connect product page and the
POST-connect manager page render the exact same checkmark grammar. Nothing
shifts visually the moment Connect flips to Open. Wallet's summary trimmed to
the clean two-sentence hook+boundary; the six capabilities moved to
`features`, rendered as scannable checkmark lines under it.

**Checked the rest of the catalog before extending the pattern — most didn't
need it.** Pulled the full text of every long summary (Stocktwits, GeckoTerminal,
Bitrefill, Privacy, Shopify, Open Food Facts, 1Claw) and classified each
honestly: none had Wallet's disease. Their extra length is legitimate —
a single bonus sentence (GeckoTerminal, Shopify), an efficiently-compressed
enumeration folded into the hook via em-dash apposition (Bitrefill's "gift
cards…, phone top-ups, eSIMs, balance refills"), or a real safety caveat that
must be stated once (Privacy.com's unscoped-key disclosure). Extracting bullets
from any of these would have been applying the fix to problems that don't
exist — exactly the mistake §191 already flagged once this session (don't
manufacture shape work where none is warranted).

**The one place that DID need a trim, not bullets:** 0xBow Privacy Pools (97w)
had no enumerable list — just a mechanism explanation plus one purely
rhetorical sentence ("That's the wait people otherwise keep checking a website
for.") that added no new fact. Cut. Its real content (mechanism + boundary) was
already complete without it.

VERIFIED 2026-07-23 (iPhone 17 Pro sim): Wallet's product page renders the
two-sentence hook, then six green-checkmark capability lines, full width,
readable at a glance. Build green.

## 193. The brief is renamed "What's going on" — and absorbs the ask that had that name (user: "i think we can just call it 'what's goin on' b/c it's now no longer a daily brief, its a brief whenever you open it", "so we wouldn't say 'Your Thursday brief'", 2026-07-23) — VERIFIED

§181 made this screen the agent's landing, rendered fresh on every rise. That
broke its own name: "Your Thursday brief" claims a once-a-day artifact, a dated
edition, and it stopped being one the moment it started recomposing on every
open. It's a standing question now, so it's named like one — **"What's going
on"**.

**The eyebrow follows.** It read "Thursday, July 23 · since 9:40 pm"; the date
now leads with the wrong idea twice over — re-asserting the daily framing the
title just dropped, and spending the lede on the half a person already knows.
What they can't know is how far back "going on" reaches, so the span stands
alone: "since 9:40 pm", or "today so far" when the window IS the calendar day
(rather than printing a start time that only restates midnight). The honesty
job §166 gave this line is unchanged — an overnight window and a since-midnight
one still produce the same-looking screen from very different spans.

**The collision, and the ruling.** "What's going on?" was already an ask — the
feeds' prose pulse (`StatusAsk`, prd 2026-07-11), which was literally one of the
chips docked under this screen. Renaming without resolving that would have put
a chip named "What's going on?" directly beneath a screen titled "What's going
on". Ruled (user, "brief absorbs it"): **the screen takes the name and the ask**.
`TodayBrief.matches` now recognizes the phrase — and sits above `StatusAsk`'s
branch in `answerDocument`, so a typed "what's going on?" lands here, on the
richer answer to the same question. The chip is retired: it offered to fetch the
screen you're already looking at, which is a dead control wearing a pill. Exact
matches only, so "what's going on with sam" stays a real search. `StatusAsk`
itself is untouched and still powers "While I was away?"; the pulse ask was
never keepable, so no kept pill is stranded.

**Copy that named the old artifact.** The Keep verb was "Keep this brief" →
"Keep this view". The first-ever flash promised "Your first brief — I'll have it
ready every morning" → "I'll have this ready every time you open", which was
wrong twice (not a brief, not a morning). The persisted flag behind that flash
keeps its old key on purpose: renaming it would re-fire a once-ever delight for
everyone who already saw it.

VERIFIED 2026-07-23 (iPhone 17 Pro sim, pinned UDID): tapping the agent bar
lands the screen with eyebrow "today so far" over the masthead "What's going
on", followed by the synthesis card, the $19K money hero, the watchlist +
up-next pair and the Reading card. The docked chip row reads "Show AAPL · 7 /
Noticed / Show BRK…" — no "What's going on?" chip, confirming the retirement.
Build green.

## 194. The "What landed" map drew outside its own card (user: "the treemap for what's going on isn't rendered right its larger than the card and doesn't look good", 2026-07-23) — VERIFIED

§180's source map shipped with four cells — one big, three stacked — copied
from the money hero's own mini-map, which carries four comfortably. But a
holdings cell is two bare text lines, and a SOURCE cell also wears a
`BridgeIcon`: stacked icon over name over count, each cell needs ~60pt, so
three of them need ~190pt of intrinsic height. Forced into an 84pt frame they
did not compress — **SwiftUI spills an over-tall child rather than clipping
it** — so the right column rendered straight out through the card's rounded
edge, above its top and below its bottom.

Three fixes, in the order that actually matters:

1. **Three cells, not four** (one big + two stacked). This is what the approved
   mockup drew, and it halves the height pressure at the source. The composer's
   `prefix(3)` and the renderer's `cap: 3` must agree; the residual line ("and
   21 more, elsewhere") names whatever they leave out, so nothing is lost.
2. **The icon rides inline with the name**, making a cell two rows instead of
   three — the same move `GenTagMap.cellLabel` already makes for its short
   token cells, for the same reason: at this height a cell affords two rows.
3. **96pt, with `.clipped()` as a backstop.** The height is set with real
   headroom rather than to-the-pixel (a to-the-pixel fit is one Dynamic Type
   step from the same bug), and the clip guarantees the failure mode is a crop
   INSIDE the card rather than a draw through its edge.

The lesson, worth keeping: a fixed `.frame(height:)` is not a constraint on a
child, it's a suggestion — content that can't compress will overflow it in both
directions and paint over whatever surrounds it. Any map or grid pinned to a
fixed height needs its cell content sized to fit, and a clip for what sizing
can't foresee.

VERIFIED 2026-07-23 (iPhone 17 Pro sim, pinned UDID): "What landed" renders
entirely within its card — Stocktwits (39 things) as the big cell, GeckoTerminal
(34) and RSS (5) stacked beside it, icons inline with their names, "and 21 more,
elsewhere" beneath. Nothing crosses the card's edge. Build green.

## 195. Module order is RANK, not arrival — "What landed" moves up behind the wallet (user: "what landed is more important than the one reading source and when it landed... it should be after the wallet", 2026-07-23) — VERIFIED

§180 appended the source map last, simply because it was built last. That was
the wrong rank and the user caught it: "What landed" is an orienting SUMMARY of
the whole day — where everything came from, in one glance — while the Reading
card beneath it is a single item and the hour strip is texture. A summary
outranks both.

Final order: synthesis card, **wallet**, **the glanceable pair** (watchlist /
up next), **what landed**, the leads (mention, reading), and the hour strip
closing.

**The money block is one story and never splits** (user, same session: "keep
wallet and watchlist together"). The first cut put "what landed" directly after
the hero, which read the words of the ruling but broke something better: the
watchlist IS money, so slotting the source map between it and the wallet split
one subject across two places. The summaries still lead — the money block, then
what landed — the ruling just applies to the BLOCK, not to the hero alone.

The principle worth keeping, now recorded in the file's own doctrine comment:
**the whole-day summaries lead, the single things follow, the texture closes.**
Order in this screen is a claim about importance, so a module added later has
to earn its position rather than inherit the bottom of the list — which is
exactly the trap §180 fell into.

VERIFIED 2026-07-23 (iPhone 17 Pro sim, pinned UDID): with a wallet watched,
`-todayProbe` composed `root = Stack([hero, pair, mix, read, hours])` — wallet
and watchlist adjacent, the source map directly behind them, the single things
and the hour strip after. Build green.

## 196. Worth a look splits by TYPE, approvals get a live-checked seat, and the trigger line earns its card back (user: "mock up for me three stupid simple ways we could design that... use cash app, apple, and robinhood for inspiration", then "i would think it would split the different types of warnings up, delegations, approvals, position risk, etc", 2026-07-23) — VERIFIED

Three mockup rounds, each narrowing on a real gap the last one exposed.

**Round one** (Cash App / Apple / Robinhood, severity-sorted) proved the brand
skins beat today's plain list but all three still mixed kinds in one run —
picking Apple's Battery-Health-style ring as the safest structural idea
missed the actual ask, which surfaced on the next round.

**Round two** (three ways to split by TYPE — a drill-down board, stacked
sections, one-type-at-a-time chips) found a REAL gap while grounding the mock
in the live model: **token approvals weren't in `WalletWarning.Kind` at all**
— they landed as plain feed things with a Revoke.cash link and never rolled
up here, so "delegations, approvals, position risk" (the user's own list)
was only two-thirds real. The user liked the chips (round two, direction F)
for being tactile but named the actual complaint precisely: "it's annoying to
tap a thing sheet and then have to tap chips for more navigation" — F's chips
SWAPPED the visible section, making them a second router stacked on a tray
that's already one tap from the feed.

**The synthesis**: keep the stacked, severity-ordered, terminal-row shape
(round two's direction E — nothing pushes, per §137) and turn the chip idea
into a sticky JUMP INDEX instead of a filter — tap a chip and `ScrollViewReader`
scrolls to that section and lights it; nothing is ever hidden, so the second
tap becomes optional. Gated to only appear past 3 sections (`showsJumpBar`) —
today's typical 2–4-warning tray doesn't earn the extra 44pt of chrome.

**The real backend addition**: `WalletApprovals.activeApprovals(hexAddresses:
context:)` batches the exact live check `WalletPrepare`'s own prepare card
already runs (`WalletPrepare.check(for:)` — refetch the receipt, read the live
allowance/isApprovedForAll) over every landed approval/Permit2 thing, sequen­
tially (not a `TaskGroup` — `Thing` isn't `Sendable` and a live-checked list is
a handful of `eth_call`s at most). This is the honesty-load-bearing part: an
approval THING is the record of the event, which never expires on its own —
without the live re-check, a revoked approval would warn forever. Verified
live against vitalik.eth: 10 approval things landed via `-approvalProbe
3000000`, and BOTH `-worthALookProbe` (the new aggregate) and `-prepareProbe`
(the existing single-thing check) independently agreed `approvals=0` / `active
=NO` on the same data — proof the new aggregate isn't just echoing the landed
count.

**`WalletWorthALookTray` rebuilt** into five severity-ordered sections
(Position risk, Flagged transfers, Approvals, Delegations, Safe signatures),
each a glyph+count header over its rows; a section's header carries ONE bulk
Revoke.cash link only when every row underneath shares a single wallet
address (`bulkRevoke(addresses:)`), falling back to a per-row link the moment
two wallets mix in — a single header link covering an address it doesn't
would be exactly the fake-unified-control the honesty rule bans.

**Caught in review, twice, both real:**
1. **§173 violation** (user: "check our rule, we don't put lists in cards").
   The first cut wrapped each section's rows in `.dsWidgetSurface` — boxing a
   CONTENT STREAM (a scrollable list of individual warning rows) exactly the
   way §173 already killed for feed rows and catalog shelves. Fixed: rows sit
   bare, the section header does the grouping (the same job a day header
   does), matching §173's own meta-rule precisely — this is not a "bounded
   set of controls" (Settings' shape) but a list you scroll and consume.
2. **Tap-back regression** (user: "there is no way to get back to the list of
   flagged transfers from the thing sheet in one tap"). `flaggedRow` called
   the tray's caller-supplied `onOpenThing`, which closed the WHOLE tray
   before opening `ThingSheetView` as a sibling sheet on the Wallet FEED —
   dismissing it stranded you on the feed, not the list, so reviewing several
   flagged transfers meant re-opening "Worth a look" and re-scrolling after
   every single tap. This was pre-existing behavior (the original flat list
   called the identical closure), just far more painful once a list could
   run to a dozen rows. Fixed by moving the sheet INSIDE the tray itself
   (`@State private var sheetThing: Thing?` + `.sheet(item:)` on the tray's
   own body, the same nesting `WalletHistoryScreen` already uses) — dismissing
   the thing sheet now reveals the tray exactly where it was, scroll position
   included, because the tray never left the view hierarchy.

**The trigger line earns its card back**, reversing §146 (2026-07-21, which
demoted it to a bare line because a permanent half-width card reserved space
for warnings that are usually absent — still true, and still why it only
renders when `warnings` isn't empty). What changed is what fills the card:
`WalletWatch.breakdown(_:)` (the shared per-kind tally `summary(_:)` now
builds ON, so the two can't disagree) drives a badge row — one tinted glyph +
count per active kind, wrapped by a small `FlowLayout` (reused verbatim from
`ThingSheetView.swift`, not redeclared) — which reads faster than the old
run-on caption and gives the door real content instead of a sentence. This is
a `WalletTile`-shaped card like its Aave/Morpho siblings, so it's a READ
(§160's carve-out), not a list — no conflict with the §173 fix two doors up.

**Title dropped the severity claim** (user: "we don't know if it needs
attention, do we?"). The old title flipped "Needs attention" on for any
critical warning; the user's challenge held up — nothing here is a push-
tracked, actively-worsening alert (a spoofed transfer already happened, an
Aave position isn't paged), so the word was claiming urgency the app doesn't
actually monitor. Now always "Worth a look"; severity still reads honestly
through glyph color alone (red critical badges, orange notice), never through
wording — the same "color carries state, words don't overclaim" split the
design law already applies everywhere else (§83's flat-change rule, the
approval honesty divergence).

**Kind gained a `glyph` property** (`chart.line.downtrend.xyaxis` liquidation,
`eye.trianglebadge.exclamationmark.fill` poisoning, `doc.on.doc.fill` spoofed
symbol — "a copy of X", `key.fill` approval, `signature` safe,
`arrow.triangle.branch` delegation) so the feed card's badges and the tray's
section headers can never pick different icons for the same kind.

VERIFIED 2026-07-23 (iPhone 17 Pro sim, pinned UDID, real vitalik.eth data):
`-worthALookProbe` reported `position=0 transfers=12 approvals=0
delegations=3 safe=0` matching the on-screen card's two badges exactly
("12 fake symbols", "3 delegations"); opened the tray, confirmed bare
(un-boxed) rows under each section header; tapped a flagged-transfer row,
confirmed its real on-chain detail (`−0.0100 ETH`, `You → 0x6ff9…a434`) —
answering in passing why it says "Sent" not "Received": `flagSpoofedSymbol`
is deliberately called on outgoing transfers too, since a scam contract can
emit a fake event naming your wallet as sender. Build green throughout.

## 197. The Worth-a-look tray and its detail sheet, de-vibe-coded (user: "this still looks like crap tho, vibe coded" / "channel cashapp" / "you can do better on these" / "nothing is happening when i click the chips", 2026-07-23) — VERIFIED

Eight fixes across the tray, its jump chips, and the flagged-transfer
detail sheet, after the §196 rebuild still read as unfinished.

**The tray rows were twelve copies of one sentence.** Every flagged-transfer
row repeated "Looks like a copy of ETH — this is a different token," half of
them truncating mid-word — the single loudest "vibe coded" tell. Rows are
ONE LINE now, carrying only what DIFFERS between them (the amount, wearing
the confusable symbol as its own tell), no leading glyph (the section header
carries the one glyph for the whole kind, so the mark stops stamping twelve
times), no repeated subtitle. The shared "why" moved once to a per-type
EXPLAINER line under each section header ("Someone sent these on purpose —
don't trust the token or address"), the idea lifted from the round-two
mockup's direction D. `WalletWatch.breakdown` already had the shared tally;
the count rides the header, not the rows.

**The chips did nothing** (user: "nothing is happening when i click them").
`ScrollViewReader.scrollTo` silently no-oped on device — the chip lit its
own tap state and the list never moved. Replaced with the ScrollView's
`scrollPosition(id:)` binding + `scrollTargetLayout()`, the API `AppsScreen`'s
category rail already ships — which is honest in BOTH directions for free:
tap a chip to scroll, or scroll by hand and the right chip lights up. The
`NavigationStack`'s nested `ScrollViewReader` is gone with it.

**The chips looked generic** (user: "channel Cash App"). Chip anatomy is now
a severity dot (the same destructive/attention hue the section's header glyph
wears) + bold word + muted count, in a chunky capsule — so the rail reads as
a legend for the list, not a row of plain words.

**The chip GATE was measuring the wrong thing** (already reasoned through with
the user before this batch): show the bar when the content actually OVERFLOWS
the sheet AND there's more than one section to jump between — not the old
`> 3 sections` count, which hid the bar on the exact two-section-but-fifteen-
row tray that needed it and would have shown it on a tidy four-section tray
that fits with nothing to scroll. `uncappedHeight > maxTrayHeight`.

**The detail sheet:**
- **The scam token's name was the 34pt headline.** "− 4,672 USDT Staked •
  gitos.org" rendered a phishing domain at hero size across two wrapped
  lines — amplifying the exact lie the warning below was calling out. Clamped
  to one line with `minimumScaleFactor`; the full (untrusted) spelling stays
  in Copy and the warning, never the hero seat.
- **The flag warning was a thin red line under a routine card.** The whole
  reason you tapped in lost the visual fight to the "Name this address?"
  prompt sitting right below it. It's a tinted red BANNER now — §160's
  "one-line flag, not a card" rule was written for the FEED, where it's a
  heads-up you scroll past; on a flagged transfer's own detail it's the
  headline, and the banner also fills the dead space the sheet left below
  the fold.
- **"You" over a public wallet.** Every watched wallet is read-only, so
  nothing distinguishes the owner's wallet from a tracked one — the sheet
  was captioning vitalik.eth "You". Now the wallet's real name (matched
  hex↔ENS through `scopeMatches`), never an assumed identity. Faces went
  circular (a wallet is a "who", `AddressBook.Kind`'s own round-vs-square
  rule) unless the counterparty is a known contract/Safe.
- **Three doors to one action.** Naming was offered by a barely-visible
  pencil on the face, the Name dial disc, AND the nudge card, all at once.
  The pencil's gone; the face is pure identity.
- **The nudge card was the loudest block on the sheet.** A tertiary prompt
  wore a heading, a three-line paragraph, and two full-width buttons.
  Compressed to a title, one sentence, and two compact controls (a small
  tinted "Name it" capsule + a plain "Not now") — an aside, not a headline.
- **The dead top zone.** The pushed sheet's back chevron floated ~100pt above
  the eyebrow in an empty system nav bar; the chevron rides the eyebrow's own
  line now (`onBack`, set only when pushed) and the bar is hidden, so content
  starts a full breath higher.
- **"From: in your wallet"** was a one-row spec table saying nothing the
  stage's two depicted parties hadn't — dropped on stage layouts (like the
  Who row already was), and the whole faint card skips rendering when no rows
  remain.

Build green throughout; standalone-verified in a worktree before commit.

## 198. The agent's answer forms — skeleton-first assembly, not a blur (user: "does the whats going on and agent in general render like generative UI or does it just render", "how would you improve it", "yes do that", 2026-07-23) — VERIFIED

Asked whether the agent's answers genuinely render like generative UI. They do
— `GenStream.stream()` reveals module by module with real pacing at each
section boundary — but the "forming" feel was thin: a resolved module just
faded in from `EmptyView`, so the screen's shape kept jumping as new blocks
popped into existence.

**First cut (reverted): a blur+scale entrance on `MountIn`.** Scoped to the
agent's answer column, each module scaled up from 0.96, rose 8pt, and came
into focus from a 4pt blur. It looked like something LOADING — a photo
resolving into focus — not like a component being drawn. Asked "how would you
improve it": the better move is structural, not cosmetic.

**Shipped: skeleton-first assembly.** A new `GenSlot.block` + `GenSkeletonBlock`
— a full-width card wearing the SAME outer margins the brief's own modules
close on. `GenRender`'s shared `"Stack"` case (root-only; nothing composes a
nested `Stack`) now passes `slot: .block` to its children whenever
`genAgentAnswerContext` is set. Root resolves almost immediately (a short line,
first in the doc), so the instant the stream reaches it, EVERY module's block
lays out at once — the whole screen's shape is visible before a single one has
content — and each block simply becomes its real component the moment that
module's own line streams in. `MountIn` reverts to its plain original fade+rise
everywhere: the richness now belongs to structure (the skeleton) and to each
component's own existing build (the money hero's rolling total and drawn
sparkline, the bars rising from baseline), not to a generic wrapper effect.

Two cleanup reviewers ran in parallel. Simplification/efficiency came back
clean. Reuse/altitude confirmed the scoping is correct (Stack is genuinely
root-only; `genAgentAnswerContext` defaults false so nothing outside the agent
changes; `paint()` docs — live model prose, and the trivial single-`Insight`
case — never show a skeleton at all, since `cursor = doc.count` before the
first publish) and flagged one real thing: the doc comment claimed to match
"every real module"'s padding, checked only against `GenInsight`/`GenWidget`
(both `s4`). Verified directly against the brief's own family instead —
`GenDayNotes`, `GenMoneyHero`, `GenTilePair`, `GenBars` all close on `s2` — so
`s2` was already the right number for the modules this shipped for; the fix was
correcting the comment's claim, not the padding. (The app does carry a second,
`s4` convention for `RootShell.modelDoc`'s "ins, res" answers — an inherent,
pre-existing split this one skeleton default can't fully match both sides of;
picked `s2` because the brief is the majority case and this feature's reason
for existing.)

VERIFIED 2026-07-23 (iPhone 17 Pro sim, pinned UDID): a temporary debug NSLog
in `GenSkeletonBlock` (removed before commit) confirmed 6 block mounts for one
`-uiAnswerProbe "What's going on"` run. Two screenshots taken back-to-back
during the same stream show it directly: frame 1 has the masthead, both docked
chips, and the Keep pill already in their final places with five gray module
blocks below; frame 2 (moments later) shows "What landed" and "Reading" now
holding real content while "Up next" and the module above it are still
unresolved skeletons — the layout never jumped, it just filled in. Build green.

## 199. The materializing was jittery — hold a module until its own line is complete (user: "they streaming is a bit jittery... the materializing i mean", 2026-07-23) — VERIFIED

§198's skeleton-first assembly fixed the SCREEN-level jump (a module popping
from `EmptyView` to fully-formed) but left a second, smaller jump: the design
law "props fill as tokens arrive" means a component's OWN properties fill in
progressively while its OWN line is still streaming — fine for a component
that's just growing text, but not for one deriving LAYOUT from its args. The
money hero's holdings treemap recomputes each cell's SHARE from the whole
items array on every render; its sparkline re-parses a comma-separated series.
While `hero`'s ~400-character line was still arriving, both were being fed a
partial, discontinuously-growing array — the treemap's proportions and the
chart's point count shifted with every few characters, reading as jitter
rather than a smooth reveal.

**The fix.** `GenEl` (`GenParser.swift`) gained `isComplete: Bool` — `true` from
`parseCompleteLine`, `false` from `parsePartialLine`, the exact distinction the
parser already made internally to decide which line may still be growing,
just never externalized before. `GenRender`'s shared dispatch
(`GenRenderer.swift`) changed from `if let el = els[id]` to `if let el =
els[id], slot != .block || el.isComplete` — a `.block`-slotted top-level
module (the brief's own modules, gated on `genAgentAnswerContext` since §198)
now holds its skeleton for its line's ENTIRE transit, not just its first
token, and swaps to the real component once, complete and stable. Every other
slot (`.row`/`.tile`/`.none`) is untouched — a plain sentence or a growing note
still fills in char by char, which is the right feel for text.

Cleanup review (reuse/simplification/efficiency/altitude, one pass since the
diff was ~15 lines): three angles clean, no changes. One real gap found and
accepted as an explicit, documented scope decision rather than silently left:
`StorePreview.swift`'s static "Wallet" product-page preview streams a
top-level `TagMap` under slot `.none` (no `genAgentAnswerContext`) and has the
SAME jitter class, unfixed — noted inline at the gate and here rather than
expanded into, since it's a one-time preview animation on a different surface
than the daily-use one this was reported against, not the agent's own
answers.

VERIFIED 2026-07-23 (iPhone 17 Pro sim, pinned UDID): a temporary debug NSLog
(removed before commit, confirmed absent via `strings` on the installed
binary) counted the gate holding "hero" across 52 consecutive re-renders
while its line streamed, each of which would previously have rendered
partially-parsed treemap/chart data — then flipping once to real, stable
content. Final render unchanged and correct (`$1.0M` hero, watchlist/up-next
pair, "Nothing moved today"). Build green.

## 200. The catalog is a wall, not an App Store (user: "one issue with the app catalogue is that it looks like apple's app store... give me three mockups... use cashapp, robinhood, and your own creative bold ideas", then a live iteration to "each category on its own card", "don't leave any empty spaces", "make sure the search bar is at the top", 2026-07-23)

The complaint: the catalog wore the App Store's clothes — hero shelves,
horizontal category scrolls — a grammar built to sell one app at a time, which
is why 56 apps felt like 200. Mocked three shapes (Cash App's flat A–Z list,
Robinhood's portfolio-of-connections, and a bold "home screen" wall of every
icon at once); the user picked the wall and then art-directed it live through
several corrections, each catching a real defect:

- **"we need categories no matter what"** — the wall isn't chipless; every
  real category from `BridgeCatalog.categories` gets its own labeled card.
- **"put them next to each other... not as one category"** — an earlier draft
  had merged small categories ("MARKETS & WALLET") under one label. Categories
  never merge; a small one just packs beside another, each keeping its own
  header.
- **"don't leave gaps"**, twice — first caught in the HTML mock: CSS
  `columns: 2` auto-BALANCES by estimated height, which silently reordered
  category cards out of sequence (Life jumped ahead of Social/Agents/Media).
  Fixed there with CSS Grid (strict row-major order). The SECOND time, in the
  Swift build, "don't leave gaps" was reasserted as a harder requirement —
  answered with true two-column MASONRY: each category, in fixed catalog
  order, assigned to whichever column is currently shorter (a plain row-count
  estimate: 1 label row + ⌈apps/2⌉ tile rows). Deterministic — computed once
  in Swift from real data, not the browser's live auto-balance — so unlike the
  CSS version there's no render-to-render reordering risk.
- **"they need their titles too"** — bare icons gamble on recognition (fine
  for Spotify, weak for 1Claw or Peer); every tile carries its name.
- **"perhaps they should be on a card each category"** — the shape that shipped.
- **"move social agents and media up... notes work home reading shopping
  down"** — `BridgeCatalog.categories`' order changed (the single source of
  truth the agent's `category:` kept-ask kind also reads), not just this
  screen's display order.
- **"make sure the search bar is at the top"** — a persistent slab
  (`searchField`) leads the page now; the nav-bar's pull-down `.searchable`
  hid the field a scroll below the fold.
- **"i also think we should still have the swipe discover cards"** —
  `DiscoverDeck` is untouched; only the shelf architecture below it retired.

**What ships:** `searchField` → `DiscoverDeck` → `jumpChips` → `catalogWall`
(two masonry columns of `categoryCard`s, each a `LazyVGrid` of `appTile`s —
icon, connected dot, name). `appRow` (the list row) survives for search
results, which stay a scannable list rather than a grid. Every honest verb
(Connect/Open/Fix/Soon), the connect bloom, the peek-preview long-press, and
`connectPromote`'s lift animation carry over unchanged onto the tile.

**A real SwiftUI compiler limit, paid for and worth recording.** Wrapping the
new content in a `pageContent(_ proxy:)` helper function — reasonable
refactoring instinct, to keep `body` short — actually caused "the compiler is
unable to type-check this expression in reasonable time." Bisection (stubbing
every new view to `EmptyView()` one at a time, and in combination) proved the
complexity wasn't in any single piece: it was `searchField` becoming a new
SIBLING view ahead of the old lone if/else, turning the VStack's content into
a tuple type that then had to thread through `ScrollView`/`ScrollViewReader`
AND survive a ~16-modifier chain on `body` as one combined inference problem.
Fix: erase the type at exactly that boundary — `scrollContent: AnyView`
wraps the `ScrollViewReader`, so the long modifier chain solves against plain
`AnyView` instead of the fully generic nested type. Nothing behavioral
changes.

VERIFIED 2026-07-23 (iPhone 17 Pro sim, real catalog data): search field at
top with live filtering, the Discover deck paging (2 of 4), jump chips
(Markets/Wallet/Social/Agents…), and the two-column wall rendering real icons
and names — Markets | Wallet in row one exactly as ruled, Wallet correctly
wearing its live green connected dot. Build green.

## 201. The catalog wall goes horizontal — paired bands, four across, full names (user: "it would be more natural for users if the groups were horizontal instead of vertical... we can't truncate app names... three mockups... four apps per row", then "for sure lets do B", "lets make the order be Wallet, Markets, Social / mail, Agents, Media, and then the rest", 2026-07-23)

§200 stood the catalog up as a two-column vertical masonry of category cards.
That fixed "see it all at once" but introduced two problems the user caught:
tile names TRUNCATED at the narrow two-up width ("GeckoTermir"), and the
masonry left ragged column gaps. Turned it horizontal: full-width category
bands, four apps per row. Mocked three shapes (A even bands / B paired bands /
C flat sectioned grid); the user picked B.

**Paired bands** (`WallBand` + `wallBands`): a category of two apps or fewer
would waste most of a four-wide row alone, so a small category pairs with the
next small one — each keeping its own label and a gap between (the "next to
each other, not as one category" rule, §200's own, turned horizontal). Under
the ruled order that pairs **Social + Mail** onto one row. Everything larger is
a full-width band, four across, last row left-aligned.

**Order, set by the user:** Wallet, Markets, Social/Mail, Agents, Media, then
Life, Notes, Work, and Reading + Shopping LAST (they carry the biggest
trailing gaps, so the blank settles at the very bottom of the scroll). Wallet
leads now, not Markets. Changed in
`BridgeCatalog.categories` (the single source of truth the agent's `category:`
kept-ask kind also reads).

**HomeKit → Life** (user's own suggestion): a one-app Home category wasted a
whole four-wide row, so "Home" folds into Life's group set. Life absorbs it
cleanly; the standalone Home category is gone.

**No truncation, made true** (`appTile`): a multi-word name wraps to two lines;
a long single word that can't wrap ("GeckoTerminal") SHRINKS to fit via
`minimumScaleFactor(0.7)` rather than clipping. "0xBow Privacy Pools", "Open
Food Facts", "Cal.com" all render whole at four-per-row.

**Where gap-chasing was deliberately STOPPED** (user: "is it possible to put
Work and Shopping in the same card... or do you think trying to do all that is
bad"). It's possible — Shopping (5) + Work (3) = 8 = two clean rows, saving one
row. But filling that gap requires the two categories to SHARE a row (Open Food
Facts beside GitHub/Linear/Notion), which bleeds the grouping and orphans the
"Work" label mid-card — the exact App-Store clutter the wall exists to escape.
Ruled against: the small trailing gaps read as breathing room, and clean
per-category grouping is what keeps the wall scannable. The paired-band rule
stays "both categories ≤2 apps," never a mid-row interleave.

VERIFIED 2026-07-23 (iPhone 17 Pro sim): Wallet band leads four-across; jump
chips read Wallet/Markets/Social/Mail; Social+Mail render paired on one row;
Agents (incl. the new OpenRouter seat), Media, Life (with HomeKit), then
Reading/Shopping/Notes/Work — every long name whole, no clip. Build green.

## 202. The wallet manager collapses to one list — a star is "watch", the roster is the starred (user: "this whole page is a mess… stupid simple and clear and concise. give me three mockups", then chose stars + roster, 2026-07-24) — VERIFIED

Three mockups (two labeled zones / one list + star / value-prop cards); the
user picked the star model but kept the face roster: "I like the stars, but
I still want the roster shelf — so if starred, maybe it shows the roster at
top."

The page had accreted past legibility — a face roster, a WATCH field, a
"just name it" verb, a Connect button, a Connection door, AND (as of §198) a
separate Address-book door — and never once said, in plain words, what the
two jobs ARE. It now says both, and drops the split that caused "which page
is this even on":

- **One list, watched or not.** The Address-book door (§189/§198) is gone;
  every named address lives on the wallet manager itself, in one list. The
  standalone `AddressBookScreen` is deleted, its `BridgeRouter.addressBook`
  destination with it.
- **The star IS watching.** Each row carries a ★ — filled = watching (its
  activity lands in your feed, capped at 5), outline = named only. Tapping it
  is the whole promote/demote: a fresh star adds the wallet to the roster
  shelf above and starts its feed; an emptied one demotes to a plain name,
  which stays. The old static "Watching" pill (a label you couldn't act on)
  is gone.
- **The roster shelf is the starred, shown big.** It stays at the top as the
  glanceable showcase the user asked to keep — the same wallets the list
  shows with a filled star, as faces. Redundant on purpose: the shelf is the
  summary, the list is the manager, and §189's old "listing twice reads as
  two books" worry is overridden by the user's explicit ask.
- **Watching auto-books.** `WalletStore.add` now writes a book entry for
  EVERY watched wallet, not just named ones — a raw-hex watch used to leave
  a wallet that didn't appear in its own book, which read as a bug. A blank
  label takes the short-address fallback, renamed in one tap.
- **The two sentences, stated once each.** The list footer: "Tap ★ to watch
  — its activity lands in your feed, up to 5. Every name here shows instead
  of a hex address when you transact." The cap, when a sixth star is tapped,
  is an honest modal, not a silently dead control.

`DSSlabField` gained an optional `isArmed` override so a verb can light only
in a specific state (the field's own arm-on-addable-text case). Build green;
standalone-verified in a worktree before commit.

## 203. Worth a look sections by whether you can ACT, not by raw severity — and the spam pile can be muted (user: "how would you improve our wallet design 'worth a look' design", three mockups, then "lets do A with C's mut and the jump chips", 2026-07-24) — VERIFIED

§196's type split fixed "one undifferentiated wall" but colored rows by raw
`Severity`, and severity was the wrong axis: a poisoning or spoofed-symbol
transfer already happened — spam, nothing to do about it — yet it wore the
loudest "critical" red, while a LIVE approval that can still drain the
wallet sat in quiet "notice" orange. At real scale (a whale wallet's dozens
of routine airdrops) the card stayed permanently red for nothing actionable,
burying the one thing worth a decision.

New axis, `WalletWarning.Kind.isActionable`: liquidation/approval/
delegation/safe are actionable; poisoning/spoofedSymbol are not — they
already happened and there's no button. The tray now has exactly two
groups instead of five flat sections:

- **Worth doing** — the four actionable type-sections (Position risk,
  Approvals, Delegations, Safe), unchanged internally from §196, under one
  small label and one scroll-anchor.
- **Just so you know** — the old "Flagged transfers" section, collapsed to
  one line by default (title + count + "nothing to do"), expandable to the
  same per-row list as before. Never wears destructive red, muted or not —
  recognized spam isn't a live risk.
- **Mute.** A button inside the expanded aware section flips
  `WalletAwareness.isMuted` (plain UserDefaults, per install not per
  wallet — recognizing spam doesn't need re-teaching per address). Muting
  drops those kinds out of the FEED CARD's color and badge row entirely
  (`WalletWarningsLine.visible`), so a wallet whose spam is already known
  can stop crying wolf in red forever; the tray itself still lists what's
  muted, it just stops shouting about it elsewhere.
- **Jump chips, kept per the user's ask**, now target the two groups
  ("Worth doing" / "Just so you know") instead of five type-sections — the
  same overflow-based gate as §197 (`superSectionIDs.count > 1 &&
  uncappedHeight > maxTrayHeight`), which in practice now fires mainly when
  the spam pile is expanded and long, since a spam-free "Worth doing" rarely
  overflows on its own.

Feed card (`WalletWarningsLine`) icon/color now reads `isActionable` the
same way: destructive red only for an active liquidation, attention orange
for any other actionable kind, and a plain neutral info mark when everything
actionable is muted or absent and only the aware pile remains unmuted.

Build green.

## 204. The crown pour becomes the person's color — five, curated (user: "let user choose their tint bleed color", then "i want to limit it to a few only. like 5 max", 2026-07-24)

Amends §159 and re-opens the 2026-07-06 appearance ruling, both deliberately.
The crown pour (`MainSurface.crownPour`) is the largest color surface in the
app — a permanent gradient, 30% → 10% → 0 down 500pt from the top (16%/5% on a
true light page), painted in the shell's background so it runs behind the chip
strip. Today it reads `chrome.pourHue ?? DS.tint`: Casberi blue everywhere,
re-tinted to a wallet's face color when the Wallet feed is scoped to one.

**The ruling: the fallback becomes the person's.** A new `DS.bleed` token,
default Casberi blue, replaces `DS.tint` at that one `??`. Nothing else moves.

**What this trades, stated plainly.** §159's recorded why was brand ownership —
"one owned color, everywhere, always", explicitly §129's endorsed shape ("Cash
App is bold in ONE color that's *theirs*"). This makes it the PERSON's color
instead, with ours as the default. That is the whole trade, and it is being
made on purpose: the pour is atmosphere, not a logo, and §159 already broke its
own "one color" claim with the wallet-face carve-out — the mechanism to vary it
shipped that same day. The precedence is unchanged: a scoped wallet still wins
(`pourHue` is checked first), so the person's color is the DEFAULT pour, never
an override of identity-as-information.

**What this is NOT.** Not the return of the background picker retired
2026-07-06 (that ruling stands for what it actually covered: no solid page
colors, no background photos, appearance is still one knob — light or dark).
Not a change to `DS.tint`, which stays Casberi blue at all 157 sites: it is the
pressable signal, it carries the measured contrast pair under Increase Contrast
(`#62a1ee`/`#1366cd`), and a person's color must never decide whether a button
reads as a button. The widget also keeps Casberi blue — it reads
`theme.tint.hex` from the app group, which tracks `accentHex`, not the bleed.
Do not "fix" that to follow the pour.

**The five.** Curated, not a color well (user: five max). Every option except
the default sits in `WalletFace.tint`'s berry register (S 0.68, B 0.78), so a
personal pour and a wallet pour read as one family:

| Name | Hex | H / S / B | Nearest reserved hue |
|---|---|---|---|
| Blue *(default)* | `#1673e6` | 213 / .90 / .90 | 78° |
| Teal | `#40c7c2` | 178 / .68 / .78 | 43° |
| Violet | `#8c40c7` | 274 / .68 / .78 | 89° |
| Magenta | `#c74095` | 322 / .68 / .78 | 41° |
| Slate | `#7b8a9e` | 214 / .22 / .62 | 79° |

Blue keeps its exact shipped hex rather than being normalized into the register
— it is the default and must not shift under anyone already looking at it.
Slate is the quiet option: same hue as the default, desaturated to .22, so it
reads as "almost none" while keeping the gradient (a true black pour would
bring back the flat-black crown §159 replaced).

**Why no warm option.** Red, orange, and green are spoken for by the app's own
color law — destructive/loss (H 3), attention/needs-you (H 36), confirm/done
(H 135). A permanent field in any of them puts an alert color behind every
screen, and in a wallet app a green or red wash biases how a P&L number reads
before the number says anything. Every option above clears the nearest reserved
hue by ≥41°. This is the real constraint on the palette, not taste.

**Two implementation rules.** (1) The light-mode half dose applies to the
chosen color exactly as it applies to blue — the `light ? 0.16 : 0.30` exists
because a field that reads as atmosphere on ink reads as a stain on white, and
a curated set does not remove that. (2) The pour is the only consumer; a
picked color must not leak into chips, glyphs, or any state fill.

Settings gains one row, "Color", stating the choice in force — the tile
grammar §161 already sets. Its detail is five swatches, each wearing the pour
it applies (ruling 2026-07-05's principle: a swatch shows what it does).

Files: `Design/DesignTokens.swift` (new `DS.bleed`), `Design/ThemeStore.swift`
(the stored choice + its palette), `Shell/MainSurface.swift` (the one `??`),
`Screens/AccountScreen.swift` + `Screens/AccountDetailSheet.swift` (row and
picker). NOT `Design/WalletFace.swift`, NOT any `DS.tint` call site.

Status: RULED, NOT BUILT.

## 205. Privacy, made legible — "What this app reaches", the ADP nudge, and the at-rest finding (user: "how if at all would we improve privacy in the app? is there even a need", then "ok do all", 2026-07-24)

The privacy posture is already the product's spine: no server, on-device
answers, no analytics, keys in the Keychain, keyless bridges, read-only
wallets. The honest assessment found the need is NOT more cryptography —
it's making the guarantees we already keep VERIFIABLE, plus closing two
small honesty gaps. Four things done, one deliberately not.

**1. "What this app reaches" (the real feature).** A Settings › Network
screen listing every service Casberi talks to, straight from this iPhone,
and exactly what each call carries — grouped into what's reaching now
(always-on + your connected apps), what reaches only if you connect it, and
the agent key that reaches only when you tap "Try with your key." This turns
"nothing routes through us" from a claim into something a skeptic can read
top to bottom. `Model/NetworkReach.swift` + `Screens/NetworkReachScreen.swift`.

It is a CURATED registry, not a live request log, ON PURPOSE: ~18 call sites
each hold their own URLSession, so a live logger would miss one and lie by
omission — worse than no log for a privacy surface. Instead
`scripts/network-reach-audit.sh` (in verify.sh) asserts every host literal
in the app appears either in the registry or an explicit non-reach denylist
(browser permalinks, demo hosts) — so the registry is complete BY
CONSTRUCTION: a new fetch host added in code that nobody disclosed fails the
build. Provable where a log would only be plausible.

Placement: its own A–Z Settings row ("Network"), its own sheet — the
reliable Diagnostics pattern. (First built as a row inside the Data tray;
a nested sheet from a fixed-detent tray presents flakily. Data owns your
DATA — things, delete, sync; Network owns the wire. One clearly-named axis
each, and the privacy story stays whole.)

**2. The ADP nudge.** A contextual line under the iCloud-sync toggle,
shown only while sync is ON (with sync off there's no iCloud copy to
encrypt), pointing the person at Advanced Data Protection — the one thing
that upgrades their sync to true end-to-end, which is theirs to enable, not
ours. Cheapest real win.

**3. The URL audit (verification, passed).** Confirmed every identifier in
an outbound query string is the PUBLIC subject the person chose to watch —
a wallet address, a Farcaster fid, a Safe address — never a hidden identity,
analytics id, email, or device id. Matches the privacy policy's "carries
only the token" claim. The reach audit script now guards this surface going
forward.

**4. At-rest — verified, and deliberately NOT changed.** The app carries no
`default-data-protection` entitlement, so the SwiftData store sits at the
iOS default, which since iOS 7 is `NSFileProtectionCompleteUntilFirst-
UserAuthentication` — already encrypted, readable after first unlock.
Raising to `Complete` (locked whenever the screen locks) requires that
entitlement (an App-ID capability + provisioning change, an UNVERIFIABLE
signing risk on the sim while build 103 is in review) AND would BREAK the
background wallet/bridge refresh and CloudKit mirroring, which must read
while the device is locked-after-first-unlock. So the honest outcome of
"verify carefully" is: at rest is already at the correct background-safe
encrypted class; no change is right, and forcing higher would regress
background sync. Documented rather than shipped.

**What we did NOT build, and why:** no mixers, no shielding, no
transaction-signing (that becomes a wallet — the Kohaku conversation), no
onion-routing proxy (needs the server we've sworn off). And nothing
mixer-adjacent or entitlement-churning while build 103 is in App Store
review. The privacy win on the table was legibility, not more crypto.
