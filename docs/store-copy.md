# App Store copy

Written and read back through the App Store Connect API on 2026-09-03. Field
editability while a version is in review is recorded in the
`store-metadata-editable-in-review` memory: promotional text and review notes
take a PATCH, description / What's New / keywords / subtitle answer 409.

Caps: description 4000, What's New 4000, review notes 4000, keywords 100,
promotional text 170, subtitle 30.

## Pending — iOS, apply to 1.0.12

iOS 1.0.11 was In Review on 2026-09-03, so its description and What's New could
not be changed. Both below are finished and measured; paste them into the next
version. The Mac equivalents are already live on 1.0.11.

Also pending on iOS, both refused with 409 and both already applied on Mac:

- keywords: `feed,reader,rss,notes,journal,dashboard,tracker,agent,assistant,ai,private,portfolio,wallet,crypto`
  (98 chars — the old string led with `wallet,crypto`, which is the first thing
  a reviewer scans on an app that was just rejected under Guideline 3.1.5;
  reordering costs nothing, since keyword order does not affect search ranking)

### iOS description (3,999 chars)

Casberi is a productivity app: one private feed for everything your apps produce, and an agent that answers from it.

Connect once, and posts, transactions, deploys, releases, workouts, events, screenshots and notes land in one feed on your iPhone. Ask about any of it in plain words; the answer comes from your own things, never invented.

New here? Start with the demo: one tap fills Casberi with sample data before you connect anything.

Every app connects its own honest way — a tap for Apple apps, a read-only key for services, an import where there's no API, a pasted address for wallets. Never a password.

THE CATALOG — 100+ APPS, BY CATEGORY

• Work — GitHub, GitLab, Jira, Stripe, Sentry, Vercel, PagerDuty, Cloudflare, AWS, PostHog, Slack, Linear, Notion, Trello, Polar, Radicle, App Store Connect, npm, PyPI, Hugging Face
• Wallet — Apple Wallet, Coinbase, Kraken, Binance, Gemini, Safe, ENS, ether.fi, Gnosis Pay, Peer, Railgun, 0xBow Privacy Pools, ETH Validators, Walletbeat, Altana, Dodo Payments, CardPointers
• Developer networks — Base Vibenet, Ethrex Hegotá, Frames Devnet
• Network — X, Instagram, TikTok, Snapchat, Telegram, Farcaster, Bluesky, Nostr
• Agent — ChatGPT, Claude, Claude Code, Gemini, Grok, Cursor, Venice, Bankr, OpenRouter, 1Claw
• Markets — Tokens, Kalshi, Polymarket, Stocktwits, GeckoTerminal, L2BEAT, Circle x402
• Reading — RSS, Substack, Readwise, Kindle, Bookmarks
• Notes — Apple Notes, Apple Journal, Day One, Obsidian
• Schedule — Calendar, Reminders, Todoist, Cal.com, Calendly
• Watching & Listening — YouTube, Twitch, Apple Music, Podcasts
• Shopping — Shopify, Privacy, Bitrefill, Deals, Open Food Facts
• Saves & Images — Reddit, Raindrop, Pinterest
• Fitness — Apple Health, Strava
• Mail — Gmail, iCloud Mail
• Storage — Files, Dropbox
• Plus — Photos, Contacts, HomeKit, OpenSea, Steam. More join weekly.

WORK, ACTUALLY COVERED
A deploy failing, an error regressing, an incident resolving, a dispute deadline, App Review's verdict — all in one feed. No dashboard tour every morning.

ASK YOUR THINGS
The agent searches your things, follows leads across sources, and shows exactly which things it read. Answers draw real charts. With Apple Intelligence it's Apple's on-device model; optionally bring your own key — it stays in your Keychain. Bankr answers about your onchain holdings; it never moves funds or transacts for you.

YOUR APPLE CARD, IN THE FEED (US)
Apple Card, Apple Cash and Savings land with the merchant's real name — read on this iPhone, never uploaded. Casberi speaks up when a subscription's price rises or quietly stops.

WATCH ANY WALLET
Paste an address or a name (ENS, .sol), or connect read-only through WalletConnect — watching can never trade or move funds. Holdings as a treemap with Aave, Morpho, Uniswap, Hyperliquid and Aerodrome positions; approvals ranked by dollars at stake, with a path to revoke.

DEVELOPER NETWORKS
Base Vibenet, Ethrex Hegotá and Frames are test networks. Make an account, claim from the faucet, send test transactions and explore each one. Nothing on them has a price or a market: no real cryptocurrency or value is transferred, and none of it can reach a live network.

BRING YOUR ARCHIVES
Import your X, Instagram, TikTok, Snapchat and Telegram exports, plus ChatGPT, Claude and Gemini conversations — then search them like memory: "my posts from 2019".

CAPTURE WITHOUT FRICTION
Share from any app and it lands instantly. Screenshots flow in on their own, searchable by what's in them. Voice notes transcribe; links get read for you.

FOUND EVERYWHERE
Spotlight, Siri and Shortcuts reach your things. Visual Intelligence matches what your camera sees to what you've saved.

YOURS, ACTUALLY
No account, no tracking, no ads. No Casberi server holds your things — there is no backend at all. Optional sync through your own iCloud. Export everything to one file; delete everything for real.

Casberi isn't another chatbot. It's your own things, in one feed, with an agent that knows them.

### iOS What's New — append these two bullets

• Developer networks — Base Vibenet, Ethrex Hegotá and Frames are test networks: make an account, claim from the faucet and send test transactions. Nothing on them has a price or a market; no real cryptocurrency or value is transferred, and none of it can reach a live network.

• Bankr — answers about your onchain holdings and only answers. It never moves funds or makes transactions on your behalf.
## Live — macOS 1.0.11

The Mac description is NOT the iOS one. `BridgeCatalog.Offer.unavailableOnMac`
drops Apple Wallet, Apple Health, Strava and HomeKit on Catalyst, so the Mac
copy must never list them, and the seat count is 99 against iOS's 103. The two
descriptions were byte-identical until 2026-09-03, which is how the Mac listing
came to advertise four seats the Mac app does not have.

### Mac description (3,994 chars)

Casberi is a productivity app for Mac: one private feed for everything your apps produce, and an agent that answers from it.

It isn't another client for them. Connect once, and posts, transactions, deploys, releases, events, screenshots and notes land in one feed. Ask about any of it in plain words; answers come from your own things, never invented.

New here? Start with the demo: one tap fills Casberi with sample data before you connect anything.

Every app connects its own honest way — a tap for Apple apps, a read-only key for services, an import where there's no API, an address for wallets. Never a password.

THE CATALOG — 99 APPS, BY CATEGORY

• Work — GitHub, GitLab, Jira, Stripe, Sentry, Vercel, PagerDuty, Cloudflare, AWS, PostHog, Slack, Linear, Notion, Trello, Polar, Radicle, App Store Connect, npm, PyPI, Hugging Face
• Wallet — Coinbase, Kraken, Binance, Gemini, Safe, ENS, ether.fi, Gnosis Pay, Peer, Railgun, 0xBow Privacy Pools, ETH Validators, Walletbeat, Altana, Dodo Payments, CardPointers
• Developer networks — Base Vibenet, Ethrex Hegotá, Frames Devnet
• Network — X, Instagram, TikTok, Snapchat, Telegram, Farcaster, Bluesky, Nostr
• Agent — ChatGPT, Claude, Claude Code, Gemini, Grok, Cursor, Venice, Bankr, OpenRouter, 1Claw
• Markets — Tokens, Kalshi, Polymarket, Stocktwits, GeckoTerminal, L2BEAT, Circle x402
• Reading — RSS, Substack, Readwise, Kindle, Bookmarks
• Notes — Apple Notes, Apple Journal, Day One, Obsidian
• Schedule — Calendar, Reminders, Todoist, Cal.com, Calendly
• Watching & Listening — YouTube, Twitch, Apple Music, Podcasts
• Shopping — Shopify, Privacy, Bitrefill, Deals, Open Food Facts
• Saves & Images — Reddit, Raindrop, Pinterest
• Mail — Gmail, iCloud Mail
• Storage — Files, Dropbox
• Plus — Photos, Contacts, OpenSea, Steam and your own wallet addresses. More weekly.

WORK, ACTUALLY COVERED
A deploy failing, an error regressing, an incident resolving and how long it lasted, a dispute deadline, App Review's verdict — all in one feed, each as a reading rather than a raw event. No dashboard tour each morning.

ASK YOUR THINGS
The agent searches your things, follows leads across sources, and shows which ones it read. Answers draw real charts from your own numbers. With Apple Intelligence it's Apple's on-device model; or bring your own key — it stays in your Keychain, and Casberi records what it billed. Bankr answers about your onchain holdings; it never moves funds or transacts for you.

WATCH ANY WALLET
Paste an address or a name (ENS, .sol), or connect read-only through WalletConnect — watching can never trade or move funds. Holdings as a treemap, with Aave, Morpho, Uniswap, Hyperliquid and Aerodrome positions alongside; approvals ranked by the dollars at stake, with a path to revoke.

DEVELOPER NETWORKS
Base Vibenet, Ethrex Hegotá and Frames are public test networks. Make an account, claim from the faucet, send test transactions and read back what the chain did — frames, lanes, gas, queue. Nothing on them has a price or a market: no real cryptocurrency or value is transferred, and none of it can reach a live network.

BRING YOUR ARCHIVES
Import your X, Instagram, TikTok, Snapchat and Telegram exports, plus ChatGPT, Claude and Gemini conversations — then search them like memory: "my posts from 2019".

CAPTURE WITHOUT FRICTION
Share from any app and it lands instantly. Screenshots from your iPhone flow in on their own, searchable by the words inside them. Voice notes transcribe; links get read.

FOUND EVERYWHERE
Spotlight, Siri and Shortcuts reach your things. Agents on this Mac can read them too, over a local connection you switch on yourself — loopback only, token-gated, off by default.

YOURS, ACTUALLY
No account, no tracking, no ads. No Casberi server holds your things — there is no backend. Optional sync through your own iCloud. Export everything to one file; delete everything for real.

Casberi isn't another chatbot. It's your own things, in one feed, with an agent that knows them.

### Mac What's New (2,445 chars)

The wallet rebuilt, three developer networks, and the biggest type on a screen now belongs to whatever that screen is for.

• Wallet — watched addresses get their own roster, everyone else lives in the address book, and one swipe opens exactly one Remove on the row you swiped. An ENS avatar now loads for an address added while the app is open.
• Developer networks — Base Vibenet, Ethrex Hegotá and Frames are public test networks: make an account, claim from the faucet, send test transactions and read back what the chain did. Nothing on them has a price or a market; no real cryptocurrency or value is transferred, and none of it can reach a live network.
• Frames Devnet — a new connector for the EIP-8141 frame-transaction chain: budgets, per-frame status and the payer, decoded move by move.
• Vibenet — token movement lands in Activity in both directions, per token, with ranked counterparties and a balance curve read back from the chain. Policy runs get their own rows with the caller named, and the chain's own pulse tells a quiet account apart from a stopped devnet.
• Hegotá — a whole sweep now reads a single block, so a spend landing mid-read can't break its proof. Lane counts read the on-chain counter, fees are undone in the balance line where this address paid them, and the block producer is named.
• Detail sheets — a transaction, an account, a key or a note now leads with the words themselves instead of a boxed receipt. Gas and queue facts read as a table rather than four sentences, and a step whose receipt couldn't be paired says so rather than reading as failed.
• Bankr — answers about your onchain holdings and only answers. It never moves funds or makes transactions on your behalf.
• Rooms — empty rooms, the address book and the sources tray each say one thing and offer one act. The feed opens on the newest thing at full size, with its source as the mark.
• Privacy — "there is no server" now leads the privacy screen instead of being its smallest line.
• Design — the chip strip is ink at rest, so the selected chip is the only blue; state words like Pending, Final and Locked lost their pill; trays and sheets are consistent throughout.
• Fixed — the app could get stuck behind grey placeholder bars after a dismissed system alert or a glance at the app switcher, which read as loading forever. Returning now always clears it. Images in a connected folder no longer stay blank when the files live in iCloud.

### Promotional text — both platforms (169 chars)

Everything your apps produce — deploys, posts, transactions, events, notes — in one private feed, with an agent that answers from it. No account, no server, no tracking.
