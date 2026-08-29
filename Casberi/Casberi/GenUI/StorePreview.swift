import Foundation

/// Store-page previews (option 4, 2026-07-07): the dream left the feed and
/// lives HERE — each not-yet-connectable app's product page streams a small
/// preview of its shape through the real gen-UI engine, the way App Store
/// screenshots preview an app. The feed itself is 100% real from minute one;
/// fake content is confined to the one surface where preview framing is
/// honest and expected.
enum StorePreview {

    /// The preview document for an offer, or nil when a preview would add
    /// nothing (connectable apps show real things instead; Venice lands no
    /// things — its key powers answers, so the tagline row speaks for it).
    static func doc(for name: String) -> [String]? {
        switch name {
        case "Wallet": [
            "root = Stack([map, t1, t2])",
            "map = TagMap(\"Holdings\", null, [ETH 4210, USDC 1840, SOL 980, LINK 460])",
            "t1 = TxRow(\"Swapped\", \"0.4 ETH → 1,120 USDC\", \"Base · Uniswap\")",
            "t2 = TxRow(\"Received\", \"250 USDC\", \"from maya.eth\")",
        ]
        case "0xBow Privacy Pools": [
            "root = Stack([w])",
            "w = Widget(\"Privacy Pools\", null, [p1, p2])",
            "p1 = TxRow(\"Cleared\", \"0.5 ETH\", \"ready to withdraw privately\")",
            "p2 = TxRow(\"Deposited\", \"0.5 ETH\", \"in review\")",
        ]
        // Both doors, and only the doors — the preview must not imply a
        // private balance or a named sender, since the whole seat is built on
        // not claiming either (prd §268).
        case "Railgun": [
            "root = Stack([w])",
            "w = Widget(\"Railgun\", null, [r1, r2])",
            "r1 = TxRow(\"Received\", \"500 USDC\", \"from Railgun · sender private\")",
            "r2 = TxRow(\"Shielded\", \"1.2 WETH\", \"into Railgun\")",
        ]
        // Amounts and moments, never a shop. The merchant, the MCC and the
        // original currency live behind Gnosis Pay's authenticated API and
        // never reach the chain at all, so a preview naming a store would be
        // inventing the one field this bridge provably cannot read. Refunds
        // settle off-chain too — these are spends, not a statement.
        case "Gnosis Pay": [
            "root = Stack([w])",
            "w = Widget(\"Card spending\", null, [t1, t2])",
            "t1 = TxRow(\"Spent\", \"€42.50\", \"with Gnosis Pay\")",
            "t2 = TxRow(\"Spent\", \"£13.20\", \"with Gnosis Pay\")",
        ]
        // The exchanges land NO feed rows at all — `ExchangeBridge` returns
        // balances, never things. What they actually do is join the combined
        // total and its one map, so the map IS the honest preview; a row here
        // would promise a trade history this seat never reads.
        case "Coinbase", "Kraken", "Binance", "Gemini Exchange": [
            "root = Stack([map])",
            "map = TagMap(\"In your combined total\", null, [BTC 5200, ETH 2400, USDC 900])",
        ]
        // Balance only, like the exchanges — a validator's balance joins the
        // total and nothing lands in the feed, not even a status change.
        case "ETH Validators": [
            "root = Stack([map])",
            "map = TagMap(\"In your combined total\", null, [ETH 3210])",
        ]
        // Settled fills only — a signaled-but-unfulfilled intent never lands.
        // The payment app is nameable because the chain carries it; the fiat
        // side stays private by Peer's design, so no counterparty appears.
        case "Peer": [
            "root = Stack([w])",
            "w = Widget(\"As they settle\", null, [t1, t2])",
            "t1 = TxRow(\"Bought\", \"25.00 USDC\", \"with Venmo on Peer\")",
            "t2 = TxRow(\"Sold\", \"100.00 USDC\", \"with Revolut on Peer\")",
        ]
        // "Your signature is needed" can only be said when the Safe was
        // reached through your OWN watched signer — watching a Safe's address
        // never says which of its owners you are, so the second row carries no
        // such claim.
        case "Safe": [
            "root = Stack([w])",
            "w = Widget(\"Waiting on signatures\", null, [r1, r2])",
            "r1 = Row(\"2 of 3 signatures collected on a transfer to maya.eth — your signature is needed\", \"Transaction\", \"Wallet\", \"now\")",
            "r2 = Row(\"Your Safe gained a new owner (alice.eth)\", \"Transaction\", \"Wallet\", \"Thu\")",
        ]
        // (Aave, Morpho, Uniswap, Hyperliquid and Aerodrome had previews here
        // until prd §515 retired their seats. A preview is reached only from a
        // product page, and those five have none — the same reading now lands
        // through the Wallet room's DeFi tiles, which draw the real position
        // rather than a written one.)
        // The queued row names no date on purpose — ether.fi finalizes in
        // batches at its own pace, so any ETA would be invented; the row
        // retitles itself the moment it really is claimable. Cash spends carry
        // no merchant, the Gnosis Pay ceiling.
        case "ether.fi": [
            "root = Stack([w])",
            "w = Widget(\"Staking and the card\", null, [r1, r2])",
            "r1 = Row(\"5.50 ETH is unstaking from ether.fi — still in the queue\", \"Link\", \"Wallet\", \"now\")",
            "r2 = Row(\"Spent $21.79 with ether.fi Cash\", \"Transaction\", \"Wallet\", \"Yesterday\")",
        ]
        case "Gmail": [
            "root = Stack([w])",
            "w = Widget(\"Waiting on you\", null, [m1, m2])",
            "m1 = MailRow(\"Your hotel reservation is confirmed\", \"Check-in Fri, 2 nights.\", \"8:12 AM\")",
            "m2 = MailRow(\"Re: token layer sign-off\", \"Looks good — ship it.\", \"Yesterday\")",
        ]
        case "iCloud Mail": [
            "root = Stack([w])",
            "w = Widget(\"Waiting on you\", null, [m1])",
            "m1 = MailRow(\"Your invoice is ready\", \"View or download anytime.\", \"9:02 AM\")",
        ]
        case "Tokens": [
            "root = Stack([w])",
            "w = Widget(\"Watchlist\", null, [r1, r2])",
            "r1 = Row(\"BankrCoin · $BNKR\", \"Link\", \"Tokens\", \"now\")",
            "r2 = Row(\"Degen · $DEGEN\", \"Link\", \"Tokens\", \"now\")",
        ]
        case "ChatGPT": [
            "root = Stack([c])",
            "c = TakeawayCard(\"LISBON TRIP\", \"Trip plan: Lisbon\", \"Three neighborhoods, two day trips, one food market.\")",
        ]
        case "Claude": [
            "root = Stack([c])",
            "c = TakeawayCard(\"IMPORTED\", \"Refactor plan: sync layer\", \"CloudKit zones, conflict rules, and the migration order.\")",
        ]
        case "Gemini": [
            "root = Stack([c])",
            "c = TakeawayCard(\"IMPORTED\", \"Compare mirrorless cameras\", \"Sensor size first, then lenses — the body is the cheap part.\")",
        ]
        case "GitHub": [
            "root = Stack([w])",
            "w = Widget(\"In your feed\", null, [r1, r2])",
            "r1 = Row(\"PR #142: token layer\", \"Link\", \"GitHub\", \"1h\")",
            "r2 = Row(\"Issue: dark mode contrast\", \"Link\", \"GitHub\", \"3h\")",
        ]
        case "Linear": [
            "root = Stack([w])",
            "w = Widget(\"Assigned to you\", null, [r1])",
            "r1 = Row(\"CAS-88: polish the composer\", \"Link\", \"Linear\", \"2h\")",
        ]
        case "Notion": [
            "root = Stack([w])",
            "w = Widget(\"Pages\", null, [r1])",
            "r1 = Row(\"Q3 planning notes\", \"Note\", \"Notion\", \"1d\")",
        ]
        // Only a repo that did not exist before — a download total and a like
        // count are counts, and a repo being UPDATED isn't news either
        // (lastModified moves for a README typo). Papers land with their
        // abstract, which no screen shows, so it can't appear here.
        case "Hugging Face": [
            "root = Stack([w])",
            "w = Widget(\"Just shipped\", null, [r1, r2])",
            "r1 = Row(\"google/gemma-3-27b-it · new model\", \"Link\", \"Hugging Face\", \"3h\")",
            "r2 = Row(\"DeepSeek-OCR: Contexts Optical Compression\", \"Link\", \"Hugging Face\", \"1d\")",
        ]
        // The three shapes a number is allowed to take, and no others: a note
        // you wrote, a milestone the count IS the event for, and a metric that
        // stopped. A watched event never re-lands weekly wearing a new tally.
        case "PostHog": [
            "root = Stack([w])",
            "w = Widget(\"What moved\", null, [r1, r2, r3])",
            "r1 = Row(\"Shipped 2.4.0 · signed_up +18.4% since\", \"Link\", \"PostHog\", \"2d\")",
            "r2 = Row(\"signed_up crossed 1,000\", \"Link\", \"PostHog\", \"6h\")",
            "r3 = Row(\"checkout_completed hasn't fired since yesterday\", \"Link\", \"PostHog\", \"now\")",
        ]
        // Mentions and nothing else — the token carries one scope, search:read,
        // so channels and files are never reached and can't be previewed.
        case "Slack": [
            "root = Stack([w])",
            "w = Widget(\"Mentions of you\", null, [r1, r2])",
            "r1 = PostRow(\"maya\", \"can you take a look at the deploy before standup?\", \"\", \"\", \"\")",
            "r2 = PostRow(\"sam\", \"staging cert expired again — worth a permanent fix?\", \"\", \"\", \"\")",
        ]
        // The BOARD leads the title, because a card name is a fragment written
        // against a context you had at the time. The list a card sits in is
        // never read — Trello lists are user-named ("Doing", "Icebox",
        // "Done ✅"), so no column name can appear in a row.
        case "Trello": [
            "root = Stack([w])",
            "w = Widget(\"Assigned to you\", null, [r1, r2])",
            "r1 = Row(\"Casberi · Ship the Cloudflare bridge\", \"Reminder\", \"Trello\", \"today\")",
            "r2 = Row(\"Website · Rewrite the pricing page\", \"Reminder\", \"Trello\", \"Fri\")",
        ]
        // Dates and changes, never analytics: requests served, bandwidth and
        // threats blocked are counts, and not one of them lands.
        case "Cloudflare": [
            "root = Stack([w])",
            "w = Widget(\"Before it bites\", null, [r1, r2])",
            "r1 = Row(\"casberi.app — TLS certificate expires in 9 days\", \"Reminder\", \"Cloudflare\", \"now\")",
            "r2 = Row(\"casberi.app — DNS changed: A casberi.app → 104.21.44.19\", \"Link\", \"Cloudflare\", \"Thu\")",
        ]
        // An individual charge NEVER lands — a £9 payment is a tally wearing a
        // currency symbol. Only money whose movement is itself the news.
        case "Stripe": [
            "root = Stack([w])",
            "w = Widget(\"What your money did\", null, [r1, r2])",
            "r1 = Row(\"Dispute opened · £49.00 — evidence due Aug 14\", \"Link\", \"Stripe\", \"1h\")",
            "r2 = Row(\"£2,140.00 paid out to your bank\", \"Link\", \"Stripe\", \"Yesterday\")",
        ]
        // Terminal runs only — an in-flight agent has no summary and no PR yet.
        // The outcome LEADS an abnormal title rather than trailing it, since a
        // trailing "failed" is exactly what the 80-character clamp eats.
        case "Cursor": [
            "root = Stack([w])",
            "w = Widget(\"Runs that finished\", null, [r1, r2])",
            "r1 = Row(\"your-org/casberi · Add README documentation\", \"Link\", \"Cursor\", \"2h\")",
            "r2 = Row(\"Failed · your-org/casberi · fix the flaky snapshot test\", \"Link\", \"Cursor\", \"Yesterday\")",
        ]
        // Counts NEVER land — an issue's event total and user count are the
        // two numbers Sentry's own UI leads with, and both are tallies. The
        // regression is the row worth having, so it leads the preview; its
        // outcome LEADS the title for the reason every other outcome here
        // does, since a stack-frame title is exactly what the clamp eats.
        case "Sentry": [
            "root = Stack([w])",
            "w = Widget(\"Unresolved\", null, [r1, r2])",
            "r1 = Row(\"Regressed · checkout-web · TypeError: cart is undefined\", \"Link\", \"Sentry\", \"20m\")",
            "r2 = Row(\"api · KeyError: 'customer_id'\", \"Link\", \"Sentry\", \"3h\")",
        ]
        // A successful PREVIEW deploy never lands — that's a git log, and it
        // is the firehose this bridge exists not to be. Production ships and
        // broken builds, nothing else.
        case "Vercel": [
            "root = Stack([w])",
            "w = Widget(\"Shipped and broken\", null, [r1, r2])",
            "r1 = Row(\"casberi-site · Rewrite the pricing page\", \"Link\", \"Vercel\", \"1h\")",
            "r2 = Row(\"Build failed · casberi-site · bump next to 15.4\", \"Link\", \"Vercel\", \"Yesterday\")",
        ]
        // Both halves of an incident's life. The second row is the one worth
        // keeping — how long it actually lasted, from PagerDuty's own two
        // timestamps rather than a duration we inferred.
        case "PagerDuty": [
            "root = Stack([w])",
            "w = Widget(\"Incidents\", null, [r1, r2])",
            "r1 = Row(\"Checkout API · Error rate above 5%\", \"Link\", \"PagerDuty\", \"now\")",
            "r2 = Row(\"Resolved after 41 min · Payments · Webhook backlog\", \"Link\", \"PagerDuty\", \"Tue\")",
        ]
        // Download counts never land — they are the biggest number a registry
        // publishes and the emptiest. A deprecation is rare, permanent, and
        // exactly the thing you otherwise learn six months late.
        case "npm": [
            "root = Stack([w])",
            "w = Widget(\"New versions\", null, [r1, r2])",
            "r1 = Row(\"react 19.2.8\", \"Link\", \"npm\", \"2d\")",
            "r2 = Row(\"Deprecated · request\", \"Link\", \"npm\", \"Mon\")",
        ]
        case "PyPI": [
            "root = Stack([w])",
            "w = Widget(\"New versions\", null, [r1, r2])",
            "r1 = Row(\"requests 2.34.2\", \"Link\", \"PyPI\", \"1d\")",
            "r2 = Row(\"httpx 0.29.0\", \"Link\", \"PyPI\", \"Thu\")",
        ]
        case "Reddit": [
            "root = Stack([w])",
            "w = Widget(\"Saved\", null, [r1])",
            "r1 = Row(\"The best coastal drives near Lisbon\", \"Link\", \"Reddit\", \"1d\")",
        ]
        case "YouTube": [
            "root = Stack([w])",
            "w = Widget(\"Liked and saved\", null, [r1])",
            "r1 = Row(\"Deadlift form, 8 minutes\", \"Link\", \"YouTube\", \"2d\")",
        ]
        case "Twitch": [
            "root = Stack([w])",
            "w = Widget(\"Live now\", null, [r1])",
            "r1 = Row(\"LIVE: northernlion — Balatro\", \"Link\", \"Twitch\", \"now\")",
        ]
        case "Apple Music", "Spotify": [
            "root = Stack([w])",
            "w = Widget(\"Listening\", null, [r1])",
            "r1 = Row(\"Liked: Verano porteño\", \"Link\", \"\(name)\", \"1d\")",
        ]
        case "Apple Health": [
            "root = Stack([w])",
            "w = Widget(\"Training\", null, [r1, r2])",
            "r1 = Row(\"Evening run · 5.2 km\", \"Event\", \"Apple Health\", \"6:31 PM\")",
            "r2 = Row(\"Strength · 45 min\", \"Event\", \"Apple Health\", \"Yesterday\")",
        ]
        case "Strava": [
            "root = Stack([w])",
            "w = Widget(\"Activities\", null, [r1, r2])",
            "r1 = Row(\"Morning ride · 24.1 km\", \"Event\", \"Strava\", \"7:02 AM\")",
            "r2 = Row(\"Long run · 12 km\", \"Event\", \"Strava\", \"Sun\")",
        ]
        case "Cal.com": [
            "root = Stack([w])",
            "w = Widget(\"Booked with you\", null, [r1, r2])",
            "r1 = Row(\"Intro call · Sam K\", \"Event\", \"Cal.com\", \"2:00 PM\")",
            "r2 = Row(\"Portfolio review · 30 min\", \"Event\", \"Cal.com\", \"Thu\")",
        ]
        case "Calendly": [
            "root = Stack([w])",
            "w = Widget(\"On your schedule\", null, [r1, r2])",
            "r1 = Row(\"Interview · Riley M\", \"Event\", \"Calendly\", \"11:30 AM\")",
            "r2 = Row(\"Coffee chat · 15 min\", \"Event\", \"Calendly\", \"Fri\")",
        ]
        case "Todoist": [
            "root = Stack([w])",
            "w = Widget(\"On your list\", null, [r1, r2])",
            "r1 = Row(\"Renew passport\", \"Reminder\", \"Todoist\", \"today\")",
            "r2 = Row(\"Send the invoice\", \"Reminder\", \"Todoist\", \"Fri\")",
        ]
        case "Raindrop": [
            "root = Stack([w])",
            "w = Widget(\"Saved\", null, [r1, r2])",
            "r1 = Row(\"The grammar of color systems\", \"Link\", \"Raindrop\", \"2h\")",
            "r2 = Row(\"Lisbon: 36 hours\", \"Link\", \"Raindrop\", \"1d\")",
        ]
        case "Readwise": [
            "root = Stack([c])",
            "c = TakeawayCard(\"HIGHLIGHT · THE CREATIVE ACT\", \"Perfection is the enemy of done\", \"The work tells you what it wants to be — your job is to listen.\")",
        ]
        case "RSS": [
            "root = Stack([w])",
            "w = Widget(\"New posts\", null, [r1, r2])",
            "r1 = Row(\"Daring Fireball: On the new iPad\", \"Link\", \"RSS\", \"3h\")",
            "r2 = Row(\"Stratechery: Aggregation, again\", \"Link\", \"RSS\", \"6h\")",
        ]
        // Broad, not "your posts": the bridge watches ANY account — your own
        // or anyone's — plus mentions, so the preview shows the accounts you
        // follow, not a personal timeline (user, 2026-07-14).
        case "Bluesky": [
            "root = Stack([w])",
            "w = Widget(\"Accounts you watch\", null, [r1, r2])",
            "r1 = PostRow(\"jay\", \"the feed you own beats the feed you rent\", \"https://cdn.bsky.app/img/avatar/plain/did:plc:oky5czdrnfjpqslsw2a5iclo/bafkreihxtnc37g7jqdcgidtkknwuswtjiijcdnc6cx4imc4oq33cnsc5da\", \"\", \"\")",
            "r2 = PostRow(\"pfrazee\", \"at-proto federation is live\", \"https://cdn.bsky.app/img/avatar/plain/did:plc:ragtjsm2j2vknwkz3zp4oxrd/bafkreihhpqdyntku66himwor5wlhtdo44hllmngj2ofmbqnm25bdm454wq\", \"\", \"\")",
        ]
        // Farcaster grew likes, mentions, and /channels (2026-07-14) — the
        // preview shows a watched account and a channel cast, not a save pile.
        case "Farcaster": [
            "root = Stack([w])",
            "w = Widget(\"Accounts and channels\", null, [r1, r2])",
            "r1 = PostRow(\"vitalik.eth\", \"Looks like the options thing is happening already!\", \"https://media.firefly.land/lens/126a045e-f7bb-44cc-80b1-2bd63ce9be58.png\", \"\", \"\")",
            "r2 = PostRow(\"clanker\", \"you have my attention\", \"https://imagedelivery.net/BXluQx4ige9GuW0Ia56BHw/f770987a-9c3a-45fd-eee3-2c0b182f8700/original\", \"\", \"\")",
        ]
        // No avatar URLs: a Nostr pubkey resolves a picture only if its author
        // published a profile, so these fall back to the initial rather than
        // asserting a face the relays may never answer with.
        case "Nostr": [
            "root = Stack([w])",
            "w = Widget(\"Accounts you watch\", null, [r1, r2])",
            "r1 = PostRow(\"fiatjaf\", \"relays are the whole protocol, the rest is a client detail\", \"\", \"\", \"\")",
            "r2 = PostRow(\"jb55\", \"shipped the note threading fix\", \"\", \"\", \"\")",
        ]
        // The export's own split, which the copy promises and this must keep:
        // what you WROTE arrives as text, what you TAPPED arrives as a named
        // link. Meta leaves other people's captions out entirely and the
        // oEmbed endpoint answers with nothing, so a save can only ever wear
        // the handle that made it — named, never quoted.
        case "Instagram": [
            "root = Stack([w])",
            "w = Widget(\"In your Instagram room\", null, [r1, r2])",
            "r1 = Row(\"@houseofgaming\", \"Link\", \"Instagram\", \"Mar 2\")",
            "r2 = Row(\"three days in Lisbon and still no bad pastel de nata\", \"Note\", \"Instagram\", \"Jul 14\")",
        ]
        // Saved chats only — Snapchat deletes the rest off its own servers, so
        // there is nothing else to import. A memory is titled by its date
        // because the export gives it no name of its own.
        case "Snapchat": [
            "root = Stack([w])",
            "w = Widget(\"In your Snapchat room\", null, [r1, r2])",
            "r1 = Row(\"Chat with sofia.reyes\", \"Chat\", \"Snapchat\", \"Mar 2\")",
            "r2 = Row(\"Memory · Jul 14, 2025 at 4:32 PM\", \"File\", \"Snapchat\", \"Jul 14\")",
        ]
        // A save lands as a bare link and gains its caption and creator only
        // after the separate naming pass — the export itself carries neither,
        // so the first row is what a NAMED save looks like, not what imports.
        case "TikTok": [
            "root = Stack([w])",
            "w = Widget(\"In your TikTok room\", null, [r1, r2])",
            "r1 = Row(\"POV: your sourdough starter has opinions\", \"Link\", \"TikTok\", \"Jun 2\")",
            "r2 = Row(\"the transition at 0:12 is unreal\", \"Note\", \"TikTok\", \"May 8\")",
        ]
        // Posts, replies and likes. Reposts are deliberately skipped — the
        // archive stores one as YOUR row wearing somebody else's sentence cut
        // at 140 characters — and bookmarks have never been in the export at
        // all, so neither may appear here.
        case "X": [
            "root = Stack([w])",
            "w = Widget(\"In your X room\", null, [r1, r2])",
            "r1 = Row(\"shipped the thing. it works. going to bed.\", \"Note\", \"X\", \"Apr 2\")",
            "r2 = Row(\"the best debugging tool is a print statement and a bad attitude\", \"Link\", \"X\", \"Jan 8\")",
        ]
        case "OpenSea": [
            "root = Stack([w])",
            "w = Widget(\"New drops\", null, [r1, r2])",
            "r1 = Row(\"Fidenza · new collection\", \"Link\", \"OpenSea\", \"now\")",
            "r2 = Row(\"Base Punks · minting now\", \"Link\", \"OpenSea\", \"1h\")",
        ]
        case "GeckoTerminal": [
            "root = Stack([w])",
            "w = Widget(\"Trending on Base\", null, [r1, r2])",
            "r1 = Row(\"Higher · $HIGHER\", \"Link\", \"GeckoTerminal\", \"now\")",
            "r2 = Row(\"Brett · $BRETT\", \"Link\", \"GeckoTerminal\", \"now\")",
        ]
        case "Kalshi": [
            "root = Stack([w])",
            "w = Widget(\"Following\", null, [r1, r2])",
            "r1 = Row(\"Fed cuts rates at the March meeting? · 68%\", \"Link\", \"Kalshi\", \"now\")",
            "r2 = Row(\"Lakers make the playoffs? · 74%\", \"Link\", \"Kalshi\", \"2h\")",
        ]
        case "Polymarket": [
            "root = Stack([w])",
            "w = Widget(\"Following\", null, [r1, r2])",
            "r1 = Row(\"Bitcoin above $150k this year? · 52%\", \"Link\", \"Polymarket\", \"now\")",
            "r2 = Row(\"Fed cuts rates at the March meeting? · 77%\", \"Link\", \"Polymarket\", \"1h\")",
        ]
        case "Stocktwits": [
            "root = Stack([w])",
            "w = Widget(\"Watching\", null, [r1, r2])",
            "r1 = Row(\"Apple Inc · $AAPL\", \"Link\", \"Stocktwits\", \"now\")",
            "r2 = Row(\"NVDA holding the 200-day — adding here\", \"Chat\", \"Stocktwits\", \"1h\")",
        ]
        // The rest of the connectable catalog (2026-07-14): every card in the
        // discover carousel now ghosts what lands instead of empty air. Each
        // row's tag is the kind it becomes; the source is the app it comes from.
        case "Photos": [
            "root = Stack([w])",
            "w = Widget(\"From your screenshots\", null, [r1, r2])",
            "r1 = Row(\"Recipe: miso-glazed salmon\", \"Screenshot\", \"Photos\", \"2h\")",
            "r2 = Row(\"Lisbon flight — confirmation\", \"Screenshot\", \"Photos\", \"Yesterday\")",
        ]
        case "Calendar": [
            "root = Stack([w])",
            "w = Widget(\"On your calendar\", null, [r1, r2])",
            "r1 = Row(\"Dentist\", \"Event\", \"Calendar\", \"9:00 AM\")",
            "r2 = Row(\"Team sync\", \"Event\", \"Calendar\", \"Wed\")",
        ]
        case "Reminders": [
            "root = Stack([w])",
            "w = Widget(\"Your lists\", null, [r1, r2])",
            "r1 = Row(\"Book the flights\", \"Reminder\", \"Reminders\", \"today\")",
            "r2 = Row(\"Call the landlord\", \"Reminder\", \"Reminders\", \"Fri\")",
        ]
        case "Pinterest": [
            "root = Stack([w])",
            "w = Widget(\"Your pins\", null, [r1, r2])",
            "r1 = Row(\"Kitchen shelving ideas\", \"Link\", \"Pinterest\", \"1d\")",
            "r2 = Row(\"Weeknight pasta board\", \"Link\", \"Pinterest\", \"2d\")",
        ]
        case "Substack": [
            "root = Stack([w])",
            "w = Widget(\"New posts\", null, [r1, r2])",
            "r1 = Row(\"Slow Boring: the housing fix\", \"Link\", \"Substack\", \"3h\")",
            "r2 = Row(\"Lenny: onboarding that sticks\", \"Link\", \"Substack\", \"1d\")",
        ]
        case "Podcasts": [
            "root = Stack([w])",
            "w = Widget(\"New episodes\", null, [r1, r2])",
            "r1 = Row(\"Acquired: the Nvidia episode\", \"Link\", \"Podcasts\", \"6h\")",
            "r2 = Row(\"The Daily: this morning\", \"Link\", \"Podcasts\", \"1d\")",
        ]
        case "Steam": [
            "root = Stack([w])",
            "w = Widget(\"Recently played\", null, [r1, r2])",
            "r1 = Row(\"Balatro · 2.1 hrs\", \"Link\", \"Steam\", \"today\")",
            "r2 = Row(\"Hades II · 40 min\", \"Link\", \"Steam\", \"Yesterday\")",
        ]
        case "Kindle": [
            "root = Stack([w])",
            "w = Widget(\"Highlights\", null, [r1, r2])",
            "r1 = Row(\"Atomic Habits — you get what you repeat\", \"Note\", \"Kindle\", \"1d\")",
            "r2 = Row(\"Dune — fear is the mind-killer\", \"Note\", \"Kindle\", \"3d\")",
        ]
        case "Apple Notes": [
            "root = Stack([w])",
            "w = Widget(\"Shared in\", null, [r1])",
            "r1 = Row(\"Apartment move — checklist\", \"Note\", \"Apple Notes\", \"2h\")",
        ]
        case "Apple Journal": [
            "root = Stack([w])",
            "w = Widget(\"Your entries\", null, [r1, r2])",
            "r1 = Row(\"A good day on the coast\", \"Note\", \"Apple Journal\", \"Sun\")",
            "r2 = Row(\"First run in weeks\", \"Note\", \"Apple Journal\", \"Mar 3\")",
        ]
        case "Day One": [
            "root = Stack([w])",
            "w = Widget(\"Your journal\", null, [r1, r2])",
            "r1 = Row(\"Lisbon, day two\", \"Note\", \"Day One\", \"May 14\")",
            "r2 = Row(\"On finishing the draft\", \"Note\", \"Day One\", \"Apr 2\")",
        ]
        case "Obsidian": [
            "root = Stack([w])",
            "w = Widget(\"From your vault\", null, [r1, r2])",
            "r1 = Row(\"Sync layer — design notes\", \"Note\", \"Obsidian\", \"1d\")",
            "r2 = Row(\"Books to read in 2026\", \"Note\", \"Obsidian\", \"4d\")",
        ]
        case "Files": [
            "root = Stack([w])",
            "w = Widget(\"From your folder\", null, [r1, r2])",
            "r1 = Row(\"TAP-1147-confirmation.pdf\", \"File\", \"Files\", \"1d\")",
            "r2 = Row(\"receipt-lyft-0630.png\", \"File\", \"Files\", \"4d\")",
        ]
        case "Shopify": [
            "root = Stack([w])",
            "w = Widget(\"New drops\", null, [r1, r2])",
            "r1 = Row(\"Aer Travel Pack 3 · $230\", \"Product\", \"Shopify\", \"2h\")",
            "r2 = Row(\"Restock: the merino tee\", \"Product\", \"Shopify\", \"1d\")",
        ]
        case "Deals": [
            "root = Stack([w])",
            "w = Widget(\"Fresh deals\", null, [r1, r2])",
            "r1 = Row(\"Sony WH-1000XM5 · $278 (was $399)\", \"Product\", \"Deals\", \"1h\")",
            "r2 = Row(\"Anker power bank · $34\", \"Product\", \"Deals\", \"3h\")",
        ]
        // No row ever claims "unused" or "expires": the API reports neither a
        // redemption status (Bitrefill can't know a code was spent at Amazon)
        // nor an expiry date.
        case "Bitrefill": [
            "root = Stack([w])",
            "w = Widget(\"Your orders\", null, [r1, r2])",
            "r1 = Row(\"Amazon.com · $50\", \"Link\", \"Bitrefill\", \"2h\")",
            "r2 = Row(\"Balance refill · $200 in USDC\", \"Link\", \"Bitrefill\", \"Yesterday\")",
        ]
        // The merchant descriptor IS readable here — Privacy records it
        // itself — which is exactly what a card settling onchain can never
        // have. Approved purchases only; a declined attempt isn't a purchase.
        case "Privacy": [
            "root = Stack([w])",
            "w = Widget(\"Card purchases\", null, [r1, r2])",
            "r1 = Row(\"NETFLIX.COM · $12.99\", \"Link\", \"Privacy\", \"1d\")",
            "r2 = Row(\"SQ *BLUE BOTTLE COFFEE · $6.50\", \"Link\", \"Privacy\", \"3d\")",
        ]
        // Grants, never secrets: vault, path pattern and permissions. Nothing
        // here ever reads a secret's VALUE — the endpoints called can't.
        case "1Claw": [
            "root = Stack([w])",
            "w = Widget(\"What the key reaches\", null, [r1, r2])",
            "r1 = Row(\"Prod · secrets/anthropic/* · read, rotate\", \"Link\", \"1Claw\", \"1d\")",
            "r2 = Row(\"Staging · secrets/stripe/* · read\", \"Link\", \"1Claw\", \"4d\")",
        ]
        // Only the folder you name — never a shared link, never "shared with
        // me". A text file previews its opening; anything else lands wearing
        // just its size, which is why the second row shows a bare filename.
        case "Dropbox": [
            "root = Stack([w])",
            "w = Widget(\"From your folder\", null, [r1, r2])",
            "r1 = Row(\"Q3 offsite notes.md\", \"File\", \"Dropbox\", \"2h\")",
            "r2 = Row(\"IMG_4821.HEIC\", \"File\", \"Dropbox\", \"1d\")",
        ]
        case "Bookmarks": [
            "root = Stack([w])",
            "w = Widget(\"Imported\", null, [r1, r2])",
            "r1 = Row(\"Designing Data-Intensive Applications — Kleppmann\", \"Link\", \"Bookmarks\", \"Mar 2\")",
            "r2 = Row(\"A visual guide to SSH tunnelling\", \"Link\", \"Bookmarks\", \"Jan 8\")",
        ]
        // Search-only (`Corpus.searchOnlySources`): these never enter the feed
        // at all, so the header says so rather than letting the section's own
        // "What lands in your feed" go unqualified. A contact row is the name
        // and nothing else — the reach line isn't part of the title. No times:
        // neither source stamps a thing with a date it could show.
        case "Contacts": [
            "root = Stack([w])",
            "w = Widget(\"Findable, never in your feed\", null, [r1, r2])",
            "r1 = Row(\"Sofia Reyes\", \"Contact\", \"Contacts\", \"\")",
            "r2 = Row(\"Blue Bottle Coffee\", \"Contact\", \"Contacts\", \"\")",
        ]
        // Accessories are LIVE STATE refreshed in place, not events — HomeKit
        // has no historical query at all — and the row is the accessory's own
        // name, so no lock/on-off state may appear (only reachability is
        // readable, and it lives off the title).
        case "HomeKit": [
            "root = Stack([w])",
            "w = Widget(\"Findable, never in your feed\", null, [r1, r2])",
            "r1 = Row(\"Front Door\", \"Accessory\", \"HomeKit\", \"\")",
            "r2 = Row(\"Kitchen Ceiling\", \"Accessory\", \"HomeKit\", \"\")",
        ]
        case "Open Food Facts": [
            "root = Stack([w])",
            "w = Widget(\"Scanned in\", null, [r1, r2])",
            "r1 = Row(\"Oatly Barista Edition · Nutri-Score C\", \"Product\", \"Open Food Facts\", \"now\")",
            "r2 = Row(\"Clif Bar, Chocolate Chip · Nutri-Score D\", \"Product\", \"Open Food Facts\", \"1d\")",
        ]
        default:
            nil
        }
    }
}
