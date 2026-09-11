# App Store copy

Last applied 2026-09-07 (iOS). Read back through the App Store Connect API on 2026-09-03. Field
editability while a version is in review is recorded in the
`store-metadata-editable-in-review` memory: promotional text and review notes
take a PATCH, description / What's New / keywords / subtitle answer 409.

Caps: description 4000, What's New 4000, review notes 4000, keywords 100,
promotional text 170, subtitle 30.

## iOS — APPLIED 2026-09-07 (§643)

The description below is LIVE on iOS. The user applied it by hand on
2026-09-07, the day it was written. **This heading said "Pending, apply to
1.0.12" for four days after the copy had moved on**, which is the whole reason
the §643 session had to re-derive what was live rather than read it here — so
when a field is applied, change this heading in the same breath.

Still pending on iOS, refused with 409 on 2026-09-03 and already applied on Mac:

- keywords: `feed,reader,rss,notes,journal,dashboard,tracker,agent,assistant,ai,private,portfolio,wallet,crypto`
  (98 chars — the old string led with `wallet,crypto`, which is the first thing
  a reviewer scans on an app that was just rejected under Guideline 3.1.5;
  reordering costs nothing, since keyword order does not affect search ranking)

### iOS description (1,794 chars)

Everything you build is scattered across apps, wallets and agents. Casberi is a productivity app that puts all your accounts in one private feed, with an agent that answers from it. No account, no servers, no tracking.

TRY IT BEFORE YOU CONNECT ANYTHING
One tap fills Casberi with sample data, so you can feel the whole app first.

ONE FEED
A deploy failing, an incident resolving, a dispute deadline, App Review's verdict — beside your posts, your workouts and your notes. Read it all together, or one app at a time. No dashboard tour every morning. In the US, Apple Card, Apple Cash and Savings land with the merchant's real name, read on this iPhone and never uploaded.

ASK IT
The agent searches your things, follows leads across sources, and shows exactly which things it read. Answers draw real charts. With Apple Intelligence it runs on Apple's on-device model, or bring your own key and it stays in your Keychain.

CONNECT HONESTLY
Over 90 apps across work, wallet, social, reading, notes, schedule, fitness, mail and storage. A tap for Apple apps. A read-only key for services. An import where there is no API. A pasted address for wallets, which can never trade or move funds. Never a password.

CAPTURE WITHOUT FRICTION
Share from any app and it lands instantly. Screenshots flow in on their own and become searchable by what is in them. Voice notes transcribe. Import your X, Instagram, TikTok and Snapchat archives, plus ChatGPT and Claude conversations, then search them like memory.

YOURS, ACTUALLY
There is no Casberi server and no backend at all. No account, no ads, no tracking. Optional sync through your own iCloud. Export everything to one file. Delete everything for real.

Casberi isn't another chatbot. It's your own things, in one feed, with an agent that knows them.

### iOS What's New — append these two bullets

• Developer networks — Base Vibenet, Hegotá UTXO and Frames are test networks: make an account, claim from the faucet and send test transactions. Nothing on them has a price or a market; no real cryptocurrency or value is transferred, and none of it can reach a live network.

• Bankr — answers about your onchain holdings and only answers. It never moves funds or makes transactions on your behalf.
## Mac — APPLIED 2026-09-08, on 1.0.15

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

### Mac description (1,778 chars)

Everything you build is scattered across apps, wallets and agents. Casberi is a productivity app for Mac that puts all your accounts in one private feed, with an agent that answers from it. No account, no servers, no tracking.

TRY IT BEFORE YOU CONNECT ANYTHING
One tap fills Casberi with sample data, so you can feel the whole app first.

ONE FEED
A deploy failing, an incident resolving, a dispute deadline, App Review's verdict — beside your posts, your reading and your notes. Read it all together, or one app at a time. No dashboard tour every morning. Rooms answer to the menu bar and the keyboard; a row copies, previews with Space, and drags out to any app.

ASK IT
The agent searches your things, follows leads across sources, and shows exactly which things it read. Answers draw real charts. With Apple Intelligence it runs on Apple's on-device model, or bring your own key and it stays in your Keychain.

CONNECT HONESTLY
Over 90 apps across work, wallet, social, reading, notes, schedule, mail and storage. A tap for Apple apps. A read-only key for services. An import where there is no API. A pasted address for wallets, which can never trade or move funds. Never a password.

CAPTURE WITHOUT FRICTION
Share from any app and it lands instantly. Screenshots flow in on their own and become searchable by what is in them. Voice notes transcribe. Import your X, Instagram, TikTok and Snapchat archives, plus ChatGPT and Claude conversations, then search them like memory.

YOURS, ACTUALLY
There is no Casberi server and no backend at all. No account, no ads, no tracking. Optional sync through your own iCloud. Export everything to one file. Delete everything for real.

Casberi isn't another chatbot. It's your own things, in one feed, with an agent that knows them.

### Mac What's New — APPLIED 2026-09-08 on 1.0.15 (1,891 chars)

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

### Promotional text — both platforms (154 chars)

Everything you build is scattered across apps, wallets and agents. Casberi puts all your accounts in one private feed, with an agent that answers from it.
