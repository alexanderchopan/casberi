# App Store copy

Last applied 2026-09-07 (iOS). Read back through the App Store Connect API on 2026-09-03. Field
editability while a version is in review is recorded in the
`store-metadata-editable-in-review` memory: promotional text and review notes
take a PATCH, description / What's New / keywords / subtitle answer 409.

Caps: description 4000, What's New 4000, review notes 4000, keywords 100,
promotional text 170, subtitle 30.

**Live subtitle (read 2026-09-27, `asc-copy.py read`): `One app for your things`** — both the
live appInfo (READY_FOR_SALE) and the in-review one (WAITING_FOR_REVIEW). Shared by iOS and
Mac: the subtitle rides the app, not a version. Promotional text was EMPTY on both
platforms until it was applied the same day (below). Full snapshot: `docs/store-live.json`.

## iOS — description REWRITTEN 2026-09-13 for §697b, REVISED 2026-09-27, NOT YET APPLIED

**2026-09-27 revision (user):** the ask lives on through the keyed agents — each opens
with All and Chat (§839, §840). The 09-13 text closed on "isn't another chatbot" and
named no agent; both descriptions now carry a `YOUR OWN AGENT` block and a new
closing line. The word "room" is off the store page (user, 2026-09-27: it reads as AI);
the two shipped What's New records keep it, verbatim. No MCP claim: `MCPPairing.transportReady` is false. Apple
Intelligence is not named: its seat is dark until the managed entitlement lands (§833).

**The live iOS and Mac descriptions and the promotional text still sell the
ask** ("ASK IT", "an agent that answers from it"). prd §697b deprecated the
ask on 2026-09-11 and recorded that copy as owed before the next submission.
The text below is the replacement, rewritten in the repo on 2026-09-13 and
not pushed to App Store Connect. When it is applied, change this heading and
the Mac and promotional-text headings in the same breath.

The description this replaces is LIVE on iOS. The user applied it by hand on
2026-09-07, the day it was written. **This heading said "Pending, apply to
1.0.12" for four days after the copy had moved on**, which is the whole reason
the §643 session had to re-derive what was live rather than read it here — so
when a field is applied, change this heading in the same breath.

Still pending on iOS, refused with 409 on 2026-09-03 and already applied on Mac:

- keywords: `feed,reader,rss,notes,journal,dashboard,tracker,agent,assistant,ai,private,portfolio,wallet,crypto`
  (98 chars — the old string led with `wallet,crypto`, which is the first thing
  a reviewer scans on an app that was just rejected under Guideline 3.1.5;
  reordering costs nothing, since keyword order does not affect search ranking)

### iOS description (1,641 chars) — 2.0, no third-party product names (4.1(a), 2026-10-02)

Everything you build, run and owe is scattered across apps. Casberi brings it into one private place on your iPhone, iPad and Mac. No account, no servers, no tracking.

Everything new, in one place.
Home is your daily brief: a deploy that failed, a payment that landed, a meeting coming up, a note you saved. Newest first, in one feed.

Know what needs you.
Work gathers issues, reviews, releases, incidents, payouts and disputes from the tools you build with. Deadlines rise to the top, soonest first. Pick one account to see only that.

All your money, one number.
Follow any wallet address without a key or a signature, alongside your exchanges, cards and bank balances. See what you hold, how it moved and what is at risk. Casberi can read, never spend.

What's next, soonest first.
Day puts your calendar, to-dos and mail in one list that reads forward: what is next, then what already happened.

Your notes, and everything you keep.
Write, record or sketch a note. Share anything from any app and it lands instantly. Screenshots are searchable by the words inside them.

Every category, one screen.
Wallet, Work, Day, Life, Media, Social, Reading and Agents each open as one screen. Pick an account to narrow it, or see them all together.

Connect with confidence.
More than 100 apps. Apple's apps connect with one tap. Other services connect with a read-only key, so Casberi can see but never change.

Try it first.
Casberi opens with a demo you can browse. Clear it when you are ready and connect your own.

Yours.
No server, no account, no ads. Sync through your own iCloud. Export everything to one file, or delete it all for good.

### iOS What's New — append these two bullets

• Developer networks — Base Vibenet, Hegotá UTXO and Frames are test networks: make an account, claim from the faucet and send test transactions. Nothing on them has a price or a market; no real cryptocurrency or value is transferred, and none of it can reach a live network.

• Bankr — answers about your onchain holdings and only answers. It never moves funds or makes transactions on your behalf.
## Mac — APPLIED 2026-09-08, on 1.0.15; description REWRITTEN 2026-09-13 for §697b, NOT YET APPLIED

The 1.0.12 record (In Review since 2026-09-07, build 535) was cancelled on
2026-09-08 by the user's call — "burn our queue position" — RENAMED to 1.0.15
(a build attaches only to the version whose string matches its own, and a
second editable Mac version cannot be created), and the description, the
promotional text and a fresh What's New below were applied the same minute.
Build 541 (the 1.0.15 tree, `955f2916`) carries it. The review notes on the
record — entitlements, the 3.1.5 response — travelled with the rename.

**Promotional text is NOT blocked.** It takes a PATCH while a version is In
Review (`store-metadata-editable-in-review`).

The Mac description is NOT the iOS one. `BridgeCatalog.Offer.unavailableOnMac`
drops Apple Wallet, Apple Health, Strava and HomeKit on Catalyst, so the Mac
copy must never list them, and the seat count is 99 against iOS's 103. Four
differences in the copy below, each deliberate: no Apple Card block, "reading"
where iOS says "workouts", no fitness in the category list, and a
menu-bar-and-keyboard line where the Apple Card sentence sits on iOS.

### Mac description (2,039 chars)

Everything you build is scattered across apps, wallets and agents. Casberi is a productivity app for Mac that puts all your accounts in one private feed, so you read them in one place. No account, no servers, no tracking.

TRY IT BEFORE YOU CONNECT ANYTHING
One tap fills Casberi with sample data, so you can feel the whole app first.

ONE FEED
A deploy failing, an incident resolving, a dispute deadline, App Review's verdict — beside your posts, your reading and your notes. Read it all together, or one app at a time. No dashboard tour every morning. Every view answers to the menu bar and the keyboard; a row copies, previews with Space, and drags out to any app.

SEE WHAT'S HAPPENING
Every app opens shaped like what's in it: a calendar reads as an agenda, a wallet leads with its balance. Widgets carry your day, what's due and your wallet. Spotlight and Shortcuts find any thing by what it says.

CONNECT HONESTLY
Over 90 apps across work, wallet, social, reading, notes, schedule, mail and storage. A tap for Apple apps. A read-only key for services. An import where there is no API. A pasted address for wallets, which can never trade or move funds. Never a password.

CAPTURE WITHOUT FRICTION
Share from any app and it lands instantly. Screenshots flow in on their own and become searchable by what is in them. Voice notes transcribe. Import your X, Instagram, TikTok and Snapchat archives, plus ChatGPT and Claude conversations, then search them like memory.

YOUR OWN AGENT
Bring your own key for Claude, ChatGPT, Gemini, Grok, Venice, OpenRouter, NEAR AI, Muse or Bankr. Open an agent to talk to it, and every conversation lands beside the history you imported from it. Your words go from this Mac straight to that provider, on your key. Nothing routes through us.

YOURS, ACTUALLY
There is no Casberi server and no backend at all. No account, no ads, no tracking. Optional sync through your own iCloud. Export everything to one file. Delete everything for real.

Your own things in one feed, with your own agent beside them.

### Mac What's New — APPLIED 2026-09-08 on 1.0.15 (1,891 chars)

> A record of what shipped, kept verbatim. Its first Features bullet says the
> demo can be "asked about" — true on 1.0.15, false since §697b. Do not reuse
> it in a later What's New.

The Mac sets type at its own size, the dock moves as one piece, and a first run opens into a live demo.

Features
• First run opens straight into a furnished demo you can read, ask about, and leave whenever you like
• With a row selected, ⌘C copies it, Space opens Quick Look, and any row drags out into another app
• Saved articles read here whole, with their paragraphs and section titles, and every room has next and previous
• Setup doors open the provider's page in a sheet, the key row offers Paste on return, and catalogue rows say what a tap costs — Allow, Sign in, Add key, Import or Connect
• Watched addresses get their own roster; everyone else lives in the address book, with one Remove per swipe
• Base Vibenet, Ethrex Hegotá and Frames are public test networks: make an account, claim from the faucet, send test transactions. Nothing on them has a price or a market; no real cryptocurrency or value is transferred, and none of it can reach a live network

Performance
• Text is set for this platform, so a window holds more without anything feeling tighter
• Faster launch and smoother scrolling: per-row costs are gone, saves are batched, and pictures decode off the main thread

Design
• The dock is one continuous surface — a folder springs out of its own chip, chips grow under the pointer, a flick parks the page
• "There is no server" leads the privacy screen; state words like Pending and Final lost their pills

Bugs
• The app no longer sticks behind grey placeholder bars after a dismissed alert or a glance away
• Images in a connected folder no longer stay blank when the files live in iCloud
• Two crashes fixed: one when leaving the app or locking the screen, one in the source chips
• Items saved under a renamed account find their room again

Bankr answers about your onchain holdings and only answers. It never moves funds or makes transactions on your behalf.

### Promotional text — both platforms (134 chars) — APPLIED 2026-09-27 (iOS 1.0.39 live, 1.0.40 in review; Mac 1.0.40 live)

Your apps, wallets and agents in one private feed. Bring your own key for Claude, ChatGPT or Gemini and talk to it beside your things.
