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

**Subtitle, owed with the next version (user, 2026-10-05):** `Every subscription, one place` (29 of 30). The live
appInfo reads `One app for your things`; the subtitle rides the app, so it changes with the next submitted version.
The iOS description's opening line below carries the same line; the Mac description's opening is owed the same edit
when it is next rewritten.

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

### Wallet paragraph for the release that ships Your account (prd §1439) — DRAFT, NOT YET APPLIED

"Casberi can read, never spend" stops being true when Move ships: the account sends and swaps. This replaces the "One wallet for all your money." paragraph in both descriptions at the next App Store submission; following other wallets stays read-only, and the line says so.

One wallet for all your money, and an account of your own.
Your wallets, exchanges, cards, savings and cash add up to one number. Follow any wallet address without a key or a signature; following only reads. Your own account is a Safe only you control, with no seed phrase: it sends, swaps and receives on Base and Ethereum, signed with Face ID, and recovers on a new device through iCloud Keychain.

### iOS description (1547 chars) — LIVE on 3.0.6 (in review), read back 2026-10-15; the opening is the line (user, 2026-10-15)

Everything you do is scattered across apps, agents, wallets. Casberi is an inbox for your apps and, soon, a rewards account for your subscriptions. It all comes together on your iPhone, iPad and Mac, with no account, no servers and no tracking.

Every subscription, in one place.
See the newsletters and lists filling your inbox beside the software and services you pay for. What each one costs, when it renews, and which you haven't used in a month.

One wallet for all your money.
Your wallets, exchanges, cards, savings and cash add up to one number. Follow any wallet address without a key or a signature. See what you hold, how it moved and what's at risk. Casberi can read, never spend.

Follow the stocks behind your apps.
Every app you use is made by a company. Markets shows its stock or token, with a heat map of your day and price alerts.

Wallet, Work, Day, Life, Agents, Media, Social, Reading.
More than 100 apps, sorted into the categories you live in. Apple's apps connect with one tap; other services with a read-only key, so Casberi can see but never change.

One feed per category.
Everything in a category lands in one feed, newest first: a deploy that failed, a payment that landed, a reply, a meeting coming up.

Or one app at a time.
Pick one account from a category's menu to see only that.

Try it first.
Casberi opens with a demo you can browse. Clear it when you're ready and connect your own.

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

### Mac description (1546 chars) — iOS 3.0.6's text for the next Mac version; "More than 90 apps" because four seats are not on the Mac (`unavailableOnMac`), NOT YET APPLIED

Everything you do is scattered across apps, agents, wallets. Casberi is an inbox for your apps and, soon, a rewards account for your subscriptions. It all comes together on your Mac, iPhone and iPad, with no account, no servers and no tracking.

Every subscription, in one place.
See the newsletters and lists filling your inbox beside the software and services you pay for. What each one costs, when it renews, and which you haven't used in a month.

One wallet for all your money.
Your wallets, exchanges, cards, savings and cash add up to one number. Follow any wallet address without a key or a signature. See what you hold, how it moved and what's at risk. Casberi can read, never spend.

Follow the stocks behind your apps.
Every app you use is made by a company. Markets shows its stock or token, with a heat map of your day and price alerts.

Wallet, Work, Day, Life, Agents, Media, Social, Reading.
More than 90 apps, sorted into the categories you live in. Apple's apps connect with one tap; other services with a read-only key, so Casberi can see but never change.

One feed per category.
Everything in a category lands in one feed, newest first: a deploy that failed, a payment that landed, a reply, a meeting coming up.

Or one app at a time.
Pick one account from a category's menu to see only that.

Try it first.
Casberi opens with a demo you can browse. Clear it when you're ready and connect your own.

Yours.
No server, no account, no ads. Sync through your own iCloud. Export everything to one file, or delete it all for good.

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

### Promotional text — both platforms (147 chars) — the line (user, 2026-10-15), APPLIED 2026-10-15 (iOS 3.0.5 live, 3.0.6 in review; Mac 3.0.3 live, 3.0.5 in review)

Everything you do is scattered across apps, agents, wallets. Casberi is an inbox for your apps and, soon, a rewards account for your subscriptions.
