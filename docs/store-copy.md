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

## Next iOS version — the wallet story, AGREED 2026-10-30, NOT YET APPLIED (user: "love it")

Rewritten to match the website reel and the ten-shot iPhone set (`~/Documents/casberi-deck/cards/appstore9.py`, `~/Downloads/App Store 10 iPhone`): the inbox, then the wallet, all together or one at a time. Markets is gone (§1529), gift cards are Spend (§1599), Buy is a card on Stripe's page (§1599, §1608), swaps are no longer credited to Relay (§1542, §1555), private money is 0xBow on Ethereum (§1563), round-ups save with your sends in dollars (§1578), the co-signer is a switch for every send and swap (§1570). The opening carries "soon, a rewards card for your subscriptions" (user, 2026-10-30). Apply with the screenshots when the next build ships from the session that made them; the iPad set and the Mac description are not redone (user: "we can ignore ipad for now").

**Subtitle (21):** `An inbox and a wallet` — rides the app, so it changes with the next submitted version.

- keywords: `crypto,swap,ethereum,usdc,privacy,tor,portfolio,budget,spending,subscriptions,feed,reader,ai,agent`

### Promotional text (150)

New: buy crypto with a card, swap anything, and round up your spare change into a private balance that earns, beside every app and account you follow.

### iOS description — the wallet story

Your life and money are scattered across apps. Casberi gives you an inbox and a wallet for all your accounts, and soon, a rewards card for your subscriptions. Keep up with your feeds and finances on your iPhone, iPad and Mac, privately and with no server.

An inbox for all your apps.
More than 100 apps, sorted into the categories you live in: social, work, reading, media, mail, calendar and more. See them all together in one feed, or one app at a time. Apple's apps connect with one tap; other services with a read-only key.

A wallet for all your accounts.
Your wallets, exchanges, cards and cash add up to one number. See it all together, or one account at a time. Follow any wallet address without a key; following only reads.

Your own account.
Create it in a tap and sign with Face ID. Send, receive and swap on Ethereum, Base and Robinhood. Only you hold the key.

Buy with a card. Swap anything.
Buy USDC or ETH with a card, on Stripe's page. Swap any token in one sentence, even to another network. Every move is checked on the network before you sign, and Casberi adds no fee.

Send and receive privately.
Move money into your private balance with 0xBow Privacy Pools on Ethereum. Send privately, receive at a fresh address, and take a deposit back anytime while it waits for approval.

A private balance that earns.
Your private balance earns interest in Aave, and counts once in your total.

Round up your spare change.
Turn on Round-ups and the spare change from what you send is saved privately in dollars, in your private balance, where it earns.

See what you spend, and where.
Spending by place, every subscription and what it costs, and the fees you paid. Spend USDC on gift cards, powered by Bitrefill.

Catch threats before they cost you.
Casberi flags address poisoning, fake tokens and fake transfers, and shows every app that can spend from you.

Safe by design.
Your keys stay on your iPhone. Add a recovery key in iCloud Keychain and a co-signer for every send and swap. Every wallet request goes through Tor.

Your agents.
Bring a key for the agent you use, or connect your own model running on your own computer.

Try it first.
Casberi opens with a demo you can browse, wallet included. Clear it when you're ready and connect your own.

Yours.
No server, no sign-up, no ads, no tracking. Sync through your own iCloud. Export everything to one file, or delete it all for good.

## iOS 3.0.8 — the wallet release, APPLIED 2026-10-23 (organisation account approved; prd §1439 item 4, §1440, §1473)

The first version with an account of its own: send, receive, swap (Relay) and buy gift cards (Bitrefill). "Casberi can read, never spend" is gone from the page; following another wallet stays read-only, and the description says so. The opening line drops "soon, a rewards account for your subscriptions" (§1445 Stage 1 declined) for "a wallet of your own"; "no account" became "no sign-up", since the person now has an account. What's New leads with Wallet and credits Relay and Bitrefill (user, 2026-10-23). Review notes rewritten for 3.1.5(i): self-custodial, offered by an organisation, the demo's account as the no-funds path.

**State, 2026-10-23:** iOS 3.0.8 submitted by the user with build 855 (WAITING_FOR_REVIEW), carrying everything below; the two wallet screenshots (7-swap, 8-buy, `~/Documents/casberi-deck/cards/appstore8.py`) did not make it — Swap was framed, Buy never drew on an overloaded simulator — so the live six stand. The Mac 3.0.8 record carries the same copy with Touch ID for Face ID, "on your Mac, iPhone and iPad" and "More than 90 apps", and its own review notes (the MCP/network.server and "no transfers" lines removed); its build is 856.

**3.0.8 → 3.0.9, 2026-10-23 evening:** iOS 3.0.8 was approved and released by hand (READY_FOR_SALE). iOS 3.0.9 (build 857, AFTER_APPROVAL) carries the same description and keywords, the promotional text re-applied (it did not carry over), review notes retitled "approved in 3.0.8" with a line for Your own model (§1478), its own What's New (own model, hide a token, rename, round-up menus, the Wallet reorganised, Move's sentence by fit), and the two wallet shots: 7-swap and 8-buy appended to the iPhone 6.9" and 6.3" sets (eight each; iPad keeps six, user: "we don't need the ipad shots"), shot on `e759e6e1` with Amazon as the merchant (the sample catalogue has no Delta) and 200px of empty black cut so "Powered by …" shows whole.

### Description (iOS 3.0.8)

Everything you do is scattered across apps, agents, wallets. Casberi is an inbox for your apps and a wallet of your own. It all comes together on your iPhone, iPad and Mac, with no sign-up, no servers and no tracking.

A wallet of your own.
Create your account in a tap and sign with Face ID. Send, receive and swap on Base, Ethereum and Robinhood Chain, and receive any token from another network, converted to the one you want. Only you hold the key: Casberi can never move your money.

Swap in one sentence.
"Swap $20 of USDC for ETH on Base." Fill in the blanks, see what you get, confirm with Face ID. Every swap is checked on the network first, so one that would fail or pay less than quoted is never signed. Swaps are powered by Relay.

Buy gift cards with crypto.
Pick a category and a merchant, and pay with USDC from your account. No card to add and no store account to make. Powered by Bitrefill.

Safe by design.
Add a recovery key so a lost phone never means lost money, add a second signer, and set a spend limit. Round up your transactions and save the change in any token.

One wallet for all your money.
Your wallets, exchanges, cards, savings and cash add up to one number. Follow any wallet address without a key or a signature; following only reads. See what you hold, what you spend and what's at risk.

Every subscription, in one place.
See the newsletters and lists filling your inbox beside the software and services you pay for. What each one costs, when it renews, and which you haven't used in a month.

Follow the stocks behind your apps.
Every app you use is made by a company. Markets shows its stock or token, with a heat map of your day and price alerts.

Wallet, Work, Day, Life, Agents, Media, Social, Reading.
More than 100 apps, sorted into the categories you live in. Apple's apps connect with one tap; other services with a read-only key, so Casberi can see but never change.

One feed per category.
Everything in a category lands in one feed, newest first: a deploy that failed, a payment that landed, a reply, a meeting coming up.

Try it first.
Casberi opens with a demo you can browse, wallet included. Clear it when you're ready and connect your own.

Yours.
No server, no sign-up, no ads. Sync through your own iCloud. Export everything to one file, or delete it all for good.

### Keywords (97) — "wallet" and "subscription" ride the subtitle, so they are not repeated

crypto,swap,ethereum,usdc,gift card,portfolio,defi,budget,spending,feed,reader,rss,ai,agent,notes

### Promotional text (154)

New: a wallet of your own. Send, swap and buy gift cards with Face ID on Base, Ethereum and Robinhood Chain, beside every app and subscription you follow.

### What's New (3.0.8)

Wallet
• Create your own wallet, signed with Face ID
• Send and receive on Base, Ethereum and Robinhood Chain
• Swap any token, powered by Relay
• Buy gift cards with USDC, powered by Bitrefill
• Receive any token from another network and convert it to USDC, ETH or any token you pick
• Add a recovery key, a second signer and a spend limit
• Round up transactions and save the change in any token

Features
• Track spending by week or month, fees included
• Search coins, tokens and stocks from one field

Design
• Show your account's keys and limits in Security
• Line every title up with its rows
• Move each event's start time to the right edge

Fixes
• Fit the reach and category maps in their cells
• Show the Subscriptions monthly total

### App Review notes (3.0.8)

GUIDELINE 3.1.5(i) — THIS VERSION ADDS A SELF-CUSTODIAL WALLET, OFFERED BY AN ORGANIZATION
Casberi's developer account was converted to an organization enrollment this week so that this version may offer a wallet.
- The user creates their own account on the device: a Safe smart account whose signing key is a passkey in the Secure Enclave, used with Face ID. Casberi holds no key, custodies no assets and has no server; it cannot move a user's funds.
- Move (the tab bar) sends, receives and swaps on Base, Ethereum and Robinhood Chain. Swap quotes and routes come from Relay (relay.link), a third-party on-chain protocol, and settle on-chain from the user's own account. Casberi adds no fee and takes no share. Every swap is simulated on the network before Face ID is asked, and one that would fail or pay less than quoted is refused.
- Buy: digital gift cards for real-world merchants from Bitrefill, paid in USDC from the user's own account. The cards are redeemed at the merchant, outside the app; nothing unlocks features or content in Casberi, so In-App Purchase does not apply (3.1.3(e), goods and services consumed outside the app).
- A spend limit, a recovery key and a second signer are optional protections the user adds in Wallet > Security.
- Following another person's wallet address stays READ-ONLY.
- No mining, no ICO, no rewards for downloading apps or completing tasks.

HOW TO REVIEW THE WALLET WITHOUT FUNDS
The app opens in a demo. The demo has a sample account: tap Move in the tab bar to see Swap, Send, Receive and Buy filled in; Wallet > Security shows its keys and spend limit. Every act in the demo answers "This works once you leave the demo." To create a real account, tap Exit demo, then Move, then Create.

ABOUT
Casberi is a personal, on-device organizer. No sign-up or login is required; the app is usable immediately. Everything is stored locally; there is no Casberi server. An optional "bring your own AI key" sends a query only to the provider the user chose, only when they tap send, directly from the device.

PERMISSIONS
Every system permission prompt follows an explicit user action; none appears at launch, and nothing is read until the user connects it.
- Calendar calls EKEventStore.requestFullAccessToEvents().
- Contacts calls CNContactStore.requestAccess(for: .contacts); contacts are search-only and never shown in the feed.
- Photos, Apple Health and Reminders work the same way, each from its own row.
- Face ID is asked only when the user creates or signs with their own account.
All of it is read on device. Nothing is uploaded, transmitted or shared.

BANKR is a third-party AI provider listed beside Anthropic, OpenAI and Google. It is answer-only: every prompt is prefixed "Answer only — never execute", no code path sends it an instruction, and a build-time test enforces that. It never moves funds or transacts on the user's behalf.

SAFE CO-SIGNING adds one signature to a multi-signature transaction created elsewhere; it holds no funds and never broadcasts. Shipped in iOS 1.0.9, approved.

BACKGROUND AUDIO (UIBackgroundModes: audio)
Voice notes keep recording when the phone locks or the user leaves the app: open a new note, tap Record, then go to the Home Screen. Saved voice notes and the Listen control on saved articles keep playing with the screen locked.

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

## Read back 2026-10-23 (`asc-copy.py read` + `diff`, both platforms 3.0.7 READY_FOR_SALE, nothing in review)

- **Live subtitle is `Subscription tracker & wallet`** (the user set it since 2026-10-05's "Every subscription, one place"; §16 above is superseded by the live page).
- iOS description LIVE matches the draft; iOS promotional text is EMPTY on 3.0.7 (the 147-char line is the draft) — the ONE field writable today. Dry run passed; the write is the user's:
  `scripts/dev-keys.sh get-file asc-p8 /tmp/asc-copy.p8 && ASC_KEY_PATH=/tmp/asc-copy.p8 scripts/asc-copy.py apply --platform IOS --field promotionalText --yes; rm -f /tmp/asc-copy.p8`
- iOS keywords (reordered draft) and the Mac description (still "reads them back to you", "Over 90 apps") need a version in an editable state: `no version accepts it — open one with appstore-release.sh first`. Both ride the next ship, which waits on the org migration.
