# Casberi — Product Doc

A narrative synthesis of docs/prd.md (which stays the source of truth for specs and rulings) and docs/prd-table.md (the same material as one table). Three parts: the intro states who this is for and what goes wrong today; the solution states the mechanism; the walkthroughs show the product surface by surface, as built.

---

## Part 1 — Intro: the users, their goals, and how it works today

### The situation

Doing creates things. Things land in apps. Apps multiply with the doing, and every new app adds a boundary — another place to look, another container to remember. The friction grows with the boundaries: the more you produce, the more it costs to use what you produced. The market's answer is agents, and each agent ships as another app — another history, another memory, another settings panel. The remedy repeats the disease.

### Who it's for

**Bob** — the target user, built for first. A young professional whose iPhone is his computer. He uses many apps (Notes, Calendar, Reminders, Messages) and one agent app (ChatGPT). He has no tolerance for setup.

**Alice** — the power user, served later on the same app. She runs agents as labor: Claude Code in a terminal, a gateway supervising agents across her laptop, server, and phone. She tolerates setup when it buys leverage. Her phone is a remote, not her computer. Bob consumes agent output; Alice operates agent labor.

Alice never gets new screens. She gets more kinds of things (jobs, runs, skills), more kinds of connections (agents, gateways, machines), and exactly two features Bob doesn't need: approvals and machine status in the feed.

### What they're trying to do

Six goals, shared by both:

1. **Stay mobile** — the phone completes the job.
2. **Capture things** — any thought, image, or link, in the moment.
3. **Organize things** — order among the things.
4. **Find things** — retrieve by what a thing is.
5. **Do things** — finish tasks: plan, book, draft, schedule.
6. **Own things** — things live on the device, work offline, leave only by choice.

"Operate" — configure, direct, track, review — is not a goal. It's what a person spends to get the goals. Bob's operate budget is zero; Alice's is large but the spend must accrue. The product minimizes operate at every budget.

### How it works today

**Bob runs two worlds on one phone.** The Apple world: capture through screenshots, Notes, Siri, Messages-to-self; organization per app; retrieval per app. The ChatGPT world: threads, Projects, Memory, a settings panel that explains nothing. Neither world writes to the other — the agent can't put anything on his calendar, and no search spans the two.

**Alice runs four worlds across three machines.** The Apple world, the agent-app world, the terminal world (output lands in the filesystem and never reaches the phone), and the gateway world (approvals arrive as pushes; a missed notification is gone). Each world holds its own record of her labor: one job's prompt sits in the terminal, its output in a repo, its approval in the gateway, its writeup in a chat. Reconstructing one job means visiting four records.

### What actually happens

The evidence, condensed (full list in prd.md §7–8):

- A recipe sits untitled in Notes; it's never found and never cooked. An itinerary sits 40 messages deep in one of three chats; at the airport he re-asks and the new answer drops the hotel address.
- A dentist reminder is snoozed six times because booking takes a call. A dinner plan scatters across Calendar, Messages, and Safari by hand; the guest list never leaves the chat.
- He opens ChatGPT's settings once, connects nothing, and closes it. He downloads a second agent, gets a second history and memory, and deletes it in a week.
- Her overnight run finishes at 11pm; she learns at 8am and the follow-up starts a day late. She approves a diff bigger than its notification on trust, and the write breaks a config.
- She rebuilds in June a skill she wrote in March, because the March version lives in a forgotten directory on a retired machine. A new laptop costs two days of keys and scopes, and one wrong scope gets blamed on the model for a month.
- A cron job dies silently; she notices a week later, from the absence.

### The problems

One problem set at two magnitudes — Bob hits each at app scale, Alice at machine-and-agent scale:

- **P1. Mobile gets hard.** Tasks cross apps by copy → switch → paste (Bob); the phone can't reach the machines at all (Alice).
- **P2. Capture betrays them.** The moment picks the container (Bob) or the machinery does (Alice), and the choice is permanent.
- **P3. They can't organize.** Order costs labor per container; nothing spans containers; no unit of "job" exists anywhere.
- **P4. They can't find.** Retrieval starts with "which app" (Bob) or "which world, which machine, which session" (Alice). Failure lands at the moment of use.
- **P5. They can't finish.** Agent output is stranded one copy-paste from done (Bob); approvals arrive without their context (Alice).
- **P6. They won't configure — or the spend evaporates.** Bob connects nothing; Alice configures constantly and nothing accrues.
- **P7. They won't add another agent — or pay for five.** Agents share nothing; each addition multiplies containers.
- **P8. They aren't aware.** What Bob keeps stays mute; Alice's machines finish, fail, and die without a signal. The state exists and never arrives.

Goal 6 — own things — has no numbered problem. It's the standing requirement that decides the platform.

---

## Part 2 — The solution

**One assistant that works across your apps instead of adding another one.** Casberi is a native iOS app: one home where everything you make becomes a **thing** — notes, links, screenshots, events, chats, voice notes, transactions, and (for Alice) jobs, runs, and approvals. The mechanism, feature by feature:

- **One home for their things (S1).** One container joins the containers. A job is one thing: prompt, output, approval, and writeup under one record.
- **Find by what it is (S2).** One search over the home. Query by content, get the thing — not the thread. For Alice, provenance is a set of fields: source, agent, run, machine. "Which agent broke the build" is a query.
- **Capture in one gesture (S3).** Every capture surface routes here with no destination decision, no title, no folder. Alice's machines capture for her — once connected, output flows in on its own.
- **Captures become outcomes (S4).** The thing carries its next action. Writes exit through bridges; the connected app finishes the job. Alice's follow-up job leaves from the sheet — the phone directs what the machines run.
- **Setup accrues (S5).** Bob pays zero setup: the app is useful before it asks for anything, and permissions arrive at the moment they unlock something. Alice pays once and keeps it: keys, scopes, and skills are saved as things (the secret itself lives only in the Keychain; the thing is the address).
- **Not another agent (S6).** Casberi presents as an organizer. No model picker, no memory panel, no persona. Agents are rows in Apps and labor in the feed — the sixth agent adds a row, not a world.
- **Feels like an Apple product (S8).** iOS grammar in type, motion, and touch targets. The polish is how the promises land — felt, not announced.
- **Apps are bridges (S9).** Adding an app builds the bridge: iOS frameworks for Apple apps, OAuth or a pasted token for services, a key or endpoint for agents and machines. Bridges come in three grades — framework (live, on-device), account (live via OAuth/token), import (batch via official export) — and every detail page states its grade truthfully.
- **Approvals carry context (S10).** An agent's ask arrives with what judgment needs — the exact command, scope, agent, and target — rendered for the phone. Approve or deny from the sheet. Dormant for Bob.
- **State lands as things (S11).** Run finished, run failed, cron died — each a feed row. An expected thing that fails to arrive is itself a thing. Bob's version (surfacing the right saved thing at the right moment) is parked until the build has context signals.

**The platform is the ownership answer.** Native iOS: SwiftData on device, iCloud sync through CloudKit (opt-in, default off), no Casberi server holds your things. Reads and capture work offline. Telemetry default off. Answers run on the person's own device by default (Apple's on-device model); a stronger opt-in cloud brain is the planned power layer, and the day it ships, the "nothing leaves the phone" copy goes conditional — the claim always tracks the truth.

**Two rules hold everything together:**

- **Honesty.** No dead controls, no fake status, no invented content. Every fact the app states is answered live; every button does what it says; settings that meter things that don't exist get cut.
- **Consent.** Typed text never saves silently — things enter only through deliberate capture paths, and saving is an outcome a toast reports. Any write that leaves the app (calendar events, agent actions, a client saving into your corpus) waits for a tap.

**Known risks, held deliberately** (prd.md §12): Alice's magnitude could flood the feed, approvals could become her job, and a run's steps could drown the corpus. The job-as-one-thing rule and a reversal trigger (if approvals pile past what the feed carries, a queue earns its own screen) guard all three. Bob proves the primitives; Alice stress-tests them. Build order stays Bob-first.

---

## Part 3 — Feature walkthroughs

### First run

Onboarding is one screen that acts out the pitch. Sixteen app icons rain from the top of the screen and stack into the bottom half — the visual is the headline: *all of this lands here*. Above them, a mini store offers exactly the three bridges that connect in one tap — Photos, Calendar, Reminders — and Connect runs the real flow; the iOS permission dialog is the in-context ask. Each connect fills its slot in place: the icon springs to color, the line flips to present tense ("Your screenshots, flowing in"), a green check pops. There is no demo data anywhere — the feed is 100% real from the first minute. When the person continues, they land on the **Feed**, watching their own things arrive, because that's the reward for what they just did. The rest of the catalog waits one tap away.

### The shell

Two tabs — **Home** (synthesis) and **Feed** (the record) — in a glass capsule, with the **composer** as a glass button on the same axis. Think, browse, capture. Management lives behind two doors worn by every tab root, top-right: the avatar opens Settings; a grid glyph opens Apps, and it pulses only when a bridge needs attention. Re-tapping a tab pops its stack back to the root. One toast surface above the bar reports every outcome ("Saved", "On your calendar") — no write ends in silence, and a failure states the honest fix.

### Capture

Things enter through deliberate gestures, never through typing:

- **Share sheet** from any app — the thing lands with no folder or title step.
- **Screenshots** flow in automatically once Photos is connected.
- **Siri and App Intents** capture by voice from anywhere on the phone.
- **Paste** into the composer — a paste-sized insertion flags the draft as a capture; the parse card shows what will be saved, with editable fields and tags, and save happens on send.
- **Mic** — speech routes through the same parse; a recording gets a Live Activity on the lock screen while it runs.

A captured thing flies as a small card to the Feed tab, which pulses once. The toast reads "Saved · Undo." The first thing ever gets its own moment. Casberi never authors or edits content — it collects and connects; the source app stays the editor.

### Feed

The record. It paints instantly from the local store, newest on top — no spinner, no stream. Every row is one anatomy: a separate rounded card washed in its kind's color, with the source's icon leading (where it came from), the title full-width (what it is), and time plus tag on the right. Pinned rows hold a section above Today.

- **Filtering:** one row of source chips (each wearing its app's real icon); kind filters arrive from Home's map. A filter with zero hits shows the app's own icon and a "Show everything" pill.
- **One gesture, one meaning:** tap opens the thing sheet; swipe offers exactly Pin and — when a real destination exists — Open in the source app. Nothing else rides the swipe.
- **Shapes:** a source chip changes the feed's shape, not just its query. Calendar reads as an agenda with the next event emphasized; Reminders groups by state with a check circle that completes the real reminder through EventKit (tap again to undo); Photos becomes a continuous grid with day pills; a wallet leads with a holdings treemap.
- **Rhythm-breakers:** an agent's approval renders as a consent card — provenance in the header, the exact command in monospace, Approve/Deny as the verbs. The card is the consent; no dialog rides it.

### The thing sheet

Tap any row and the sheet opens ink-black in both modes, like a photo viewer. No cards, no lines — spacing separates. From top: an eyebrow (source dot · kind · age), the title large, then the thing's media — a screenshot leads with its image, a token thing leads with a live native price chart. Below, a spec table with per-kind labels (WHEN for events, SITE for links, BY for agent provenance), then tags as a text line — tap it and the full chip editor opens in place: add, remove, rename everywhere, delete everywhere. Verbs are quiet text rows, derived from what the thing is (Open in Calendar, Add Reminder), capped at three; writes confirm before acting. Pin and Share are rows. A Related shelf streams last.

### Tags

The one word for grouping — the app never says "project" or "folder." A tag is a name on things that belong together; a thing carries many. Two flavors: type tags the app assigns (Link, Event — structural, unrenameable) and the person's own. Each tag owns one stable color everywhere — its text on feed rows, its tile on Home's map, its detail header. The system proposes groupings by clustering; the person renames or removes, never files. There is no tag-management screen; a tag with zero things dies. The composer understands organizing as a command — "tag lisbon as Trip", "rename Trip to Travel" — and streams a proposal card showing the matched things and the exact change; the write happens on Apply, with Undo in the toast.

### Home

The synthesis surface, authored fresh each open and streamed in. From top: a full-bleed **cover** — the newest screenshot's photo with its own color bled into the page, or a bright field of the day's lead kind color — carrying the dateline ("MONDAY · 24 THINGS"); one **insight** under a "Noticed" eyebrow, a cross-source fact the corpus proves; the **tag map** ("What's going on") — an interactive treemap of the person's tags, sized by count, tap-through to detail; **kind pills** (what landed today, tap-through to the filtered feed); the **Pinned** card (the person's own choices, newest three); and **Threads**, links the system found across apps. The voice rule: Home speaks to themes and content, never obligations — nothing reads as "you should." No task lists, no counters, no streaks. A new user with a sparse corpus sees honest previews of the same modules — kind names and skeletons, never fake data — so the screen shows the shape it will take.

### The composer

One field for ask, search, and capture. Tap the glass button and it morphs into the bubble: "Ask anything. Organize everything."

Asking runs in two layers, both on the phone. A scoring engine always retrieves first — it ranks the corpus (title, tags, content, freshness) and returns the top hits; on any iPhone, that alone answers. On Apple-Intelligence iPhones the free on-device model then composes over those same hits: a lookup ("find what I saved about work") returns a typed layout — one plain sentence plus real things, most relevant first; a reflection ("what's my week") streams a short plain summary. Two rails hold honesty: the model can only choose among retrieved things, never invent one, and every displayed row paints from the real thing. Nothing leaves the phone; nothing is billed.

### Apps — the store

Behind the grid door. One scroll, two zones split by the app's only line: **management above** — the connected strip, where paused bridges dim and broken ones lead with Fix — and **the store below**. Discover leads with a story carousel of the track-anything bridges (watch any token, any wallet, any Farcaster account), then category shelves (Your life, Onchain, Social, …) like the App Store. Every offer opens a product page: the real icon, what it does, what lands in your feed, and one honest verb — Connect, Pair, Fix, Open, or Soon. Never "GET," never a dead button; an offer that needs a key it doesn't have yet stays a Soon card.

Bridges are graded truthfully, and every connect ends in proof — things land:

- **Framework (live, on-device):** Photos, Calendar, Reminders, Apple Health, Apple Music.
- **Account (live, no server):** RSS, Bluesky, Farcaster, Tokens (price watching, renamed from Dexscreener 2026-07-13 — the chart blends GeckoTerminal/Alchemy/Dexscreener, so one vendor's name overclaimed); iCloud Mail and Gmail over IMAP with an app-specific password; eight paste-token bridges (Readwise, GitHub, Todoist, Raindrop, Cal.com, Calendly, Notion, Linear); Reddit and Spotify built and gated on free client ids. Auth tokens go straight to the Keychain and never render.
- **Import (batch, official export):** ChatGPT — conversations land as chat things, deduped on re-import.

Apps with no readable API (Apple Notes, Messages) are never listed as bridges — they reach Casberi through capture, and the catalog says so.

### Agents and approvals

Alice's rung, built on the same surfaces. An agent, gateway, or machine connects like any app — a key or endpoint, a row with a state ring; multiple agents behind one gateway are provenance fields on things, never extra rows. Their labor lands in the feed: outputs as things carrying provenance (source, agent, run, machine), state changes as rows (run finished, run failed, cron died). When an agent wants to act, the ask arrives as an approval thing — the exact command, who's asking, by what route — and the Approve tap is the consent. Casberi holds no funds and never trades; any bridge to a trading platform is read-only. The one key it holds is a co-signer: an Enclave key that can add a signature to a multisig the user already owns, on an explicit tap, and can never execute on its own.

**MCP — Casberi is the server.** Outside clients (Claude, Raycast, any MCP client) connect to the person's corpus, not the other way around. Three tools: search over real things, the week's synthesis, and save — which never lands silently but arrives as an approval in the feed. Reads are gated by the connection being live (unpair revokes); writes are gated by the tap. Pairing is a QR code; the client appears as a bridge-shaped row like everything else. The tools and pairing surface are built; the transport ships with the sync-backed server.

### Settings and ownership

Behind the avatar: Avatar, Data, Theme — three tiles, each with a real job, and nothing else. No account, no sign-in, no subscription tile until one exists.

**Data is the trust surface.** Two big numbers lead — things and storage — then the guarantee in plain rows: answers run on this iPhone; iCloud sync is a real toggle, default off (its badge is the tell: green lock = on this iPhone, blue cloud = your iCloud); Hide previews redacts the app switcher, default on. Three controls, all real: Export (everything to one JSON file, provenance included), Import, and Delete everything — which purges the local store, the voice recordings, and the CloudKit zone, and reports what it did. Every fact on the sheet is answered live.

**Theme** is one knob: light or dark. Identity stays with the system — one fixed Casberi blue marks everything pressable; kind hues say what things are; orange means needs-you; green means done.

### What's deliberately not here

No Actions tab — do lives where its object lives (the composer creates, the feed triages, sheets consent). No automations yet; the product takes no alert away from the app that owns it. No model picker, no persona, no "I", no thinking indicators — agency renders as results. No note editor. No streaks, goals, or guilt mechanics. No trading surface, ever. Each absence has a return trigger recorded in the PRD; until a trigger fires, the absence is the feature.
