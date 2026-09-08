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

• Developer networks — Base Vibenet, Hegota Devnet and Frames are test networks: make an account, claim from the faucet and send test transactions. Nothing on them has a price or a market; no real cryptocurrency or value is transferred, and none of it can reach a live network.

• Bankr — answers about your onchain holdings and only answers. It never moves funds or makes transactions on your behalf.
## Mac — BLOCKED, In Review (§643)

macOS 1.0.11 is In Review as of 2026-09-07, so its **description and What's New
answer 409** and the copy below cannot be applied yet. Apply it the moment the
review clears; until then the Mac listing still carries the 3,994-character
catalogue version, so the two platforms deliberately disagree and that is
recorded rather than fixed.

**Promotional text is NOT blocked.** It takes a PATCH while a version is In
Review (`store-metadata-editable-in-review`), so the new 154-character line at
the foot of this file can go to Mac today, ahead of the description.

The Mac description is NOT the iOS one. `BridgeCatalog.Offer.unavailableOnMac`
drops Apple Wallet, Apple Health, Strava and HomeKit on Catalyst, so the Mac
copy must never list them, and the seat count is 99 against iOS's 103. The two
descriptions were byte-identical until 2026-09-03, which is how the Mac listing
came to advertise four seats the Mac app does not have. Four differences in the
copy below, each deliberate: no Apple Card block, "reading" where iOS says
"workouts", no fitness in the category list, and a menu-bar-and-keyboard line
where the Apple Card sentence sits on iOS.

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

### Mac What's New (2,445 chars)

The wallet rebuilt, three developer networks, and the biggest type on a screen now belongs to whatever that screen is for.

• Wallet — watched addresses get their own roster, everyone else lives in the address book, and one swipe opens exactly one Remove on the row you swiped. An ENS avatar now loads for an address added while the app is open.
• Developer networks — Base Vibenet, Hegota Devnet and Frames are public test networks: make an account, claim from the faucet, send test transactions and read back what the chain did. Nothing on them has a price or a market; no real cryptocurrency or value is transferred, and none of it can reach a live network.
• Frames Devnet — a new connector for the EIP-8141 frame-transaction chain: budgets, per-frame status and the payer, decoded move by move.
• Vibenet — token movement lands in Activity in both directions, per token, with ranked counterparties and a balance curve read back from the chain. Policy runs get their own rows with the caller named, and the chain's own pulse tells a quiet account apart from a stopped devnet.
• Hegotá — a whole sweep now reads a single block, so a spend landing mid-read can't break its proof. Lane counts read the on-chain counter, fees are undone in the balance line where this address paid them, and the block producer is named.
• Detail sheets — a transaction, an account, a key or a note now leads with the words themselves instead of a boxed receipt. Gas and queue facts read as a table rather than four sentences, and a step whose receipt couldn't be paired says so rather than reading as failed.
• Bankr — answers about your onchain holdings and only answers. It never moves funds or makes transactions on your behalf.
• Rooms — empty rooms, the address book and the sources tray each say one thing and offer one act. The feed opens on the newest thing at full size, with its source as the mark.
• Privacy — "there is no server" now leads the privacy screen instead of being its smallest line.
• Design — the chip strip is ink at rest, so the selected chip is the only blue; state words like Pending, Final and Locked lost their pill; trays and sheets are consistent throughout.
• Fixed — the app could get stuck behind grey placeholder bars after a dismissed system alert or a glance at the app switcher, which read as loading forever. Returning now always clears it. Images in a connected folder no longer stay blank when the files live in iCloud.

### Promotional text — both platforms (154 chars)

Everything you build is scattered across apps, wallets and agents. Casberi puts all your accounts in one private feed, with an agent that answers from it.
