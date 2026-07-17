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
controls (Deny button, onboarding capsules — controls, not surfaces). A
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
  (`TokenQuickSheet`) with one real verb: Watch. Native coins stay
  routeless and fall back to the Wallet screen.
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
