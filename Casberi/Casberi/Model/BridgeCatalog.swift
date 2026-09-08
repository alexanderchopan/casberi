import Foundation

/// The catalog — the 15 bridges research proved viable (PRD S9 grades), one
/// list read by the Apps tile (count), the Apps page (Available section),
/// and the catalog screen (grouped). Names are the join key everywhere.
enum BridgeCatalog {

    struct Offer {
        let name: String
        let tagline: String
        let group: String
        /// True = the bridge is wired today (local frameworks). The rest say
        /// "Arrives with bridges" instead of pretending.
        let connectable: Bool
        /// Named things this offer reads that have no seat of their own
        /// (prd §515) — the protocols, venues or formats it covers. Two jobs,
        /// both of which the five retired DeFi seats used to do badly: catalog
        /// SEARCH matches these, so typing "aave" finds the seat that really
        /// reads it instead of one that misleads you; and the product page
        /// lists them, so the capability is stated where it is true rather than
        /// asserted by an icon that opens somebody else's room.
        ///
        /// A name belongs here ONLY while it has no seat — an entry that also
        /// ships as an offer would put one thing in the catalog twice, which is
        /// the defect §515 removed, arriving from the other side.
        var alsoReads: [String] = []

        /// True when connecting needs the person's input first (feed URLs,
        /// a pasted token) — Connect opens the bridge's setup screen instead
        /// of firing a permission ask. Setup bridges skip onboarding's
        /// mini store: that screen is one-tap connects only.
        var needsSetup: Bool = false

        /// The day this offer joined the catalog (nil = it has always been
        /// here / predates the stamp). This is what makes "Just added" HONEST
        /// where the old "New" badge was pure assertion (ruling 2026-07-16):
        /// a computable date, so a genuinely-recent offer can earn a Discover
        /// seat and the badge retires itself when the date ages out. Only
        /// stamp an offer the day it actually lands.
        var added: Date? = nil

        /// True for a bridge whose framework is genuinely unavailable under
        /// Mac Catalyst — HealthKit, HomeKit and FinanceKit don't exist there
        /// (compile-time unavailable, not just runtime-unsupported; see
        /// CLAUDE.md's Catalyst notes). An offer a Mac user can never
        /// connect is a dead seat, which the honesty rule (docs/build-brief
        /// §8, "no dead controls") forbids — so `BridgeCatalog.offers`
        /// filters these out on Mac (see below) rather than showing a
        /// Connect button that can only ever fail. `allOffers` (the literal
        /// array `scripts/catalog-sync.sh` greps) is untouched either way —
        /// this only ever narrows what a MAC session's `offers` returns.
        var unavailableOnMac: Bool = false

        /// True when this offer joined within the last week — the window the
        /// Discover deck reads for a "Just added" seat. Time-relative on
        /// purpose: a stamped offer stops being new on its own, no cleanup.
        func isNew(asOf now: Date = Date()) -> Bool {
            guard let added else { return false }
            return now.timeIntervalSince(added) < 7 * 24 * 60 * 60
        }

        /// A one-word honest hook for the row badge and the story eyebrow —
        /// derived from HOW the bridge connects, never marketing. "One tap"
        /// (a system-permission bridge — a single grant, no fields), "No
        /// account" (keyless — a handle or address, no sign-in, public
        /// feeds), or "Import" (a one-time export you point at). Everything
        /// else stays unbadged: a row earns a badge only when the fact
        /// differentiates it. Never applied to a connected row (its subline
        /// already carries live status).
        var qualifier: String? {
            if connectable && !needsSetup { return "One tap" }
            let keyless: Set<String> = ["Wallet", "Tokens", "Peer", "0xBow Privacy Pools", "Railgun", "Safe", "Reddit", "YouTube",
                "RSS", "Substack", "Podcasts", "Pinterest", "Farcaster",
                "Bluesky", "Nostr", "Shopify", "Deals",
                "Stocktwits", "Hugging Face", "Radicle", "npm", "PyPI", "Altana",
                "Walletbeat", "L2BEAT", "ENS"]
            if keyless.contains(name) { return "No account" }
            // Instagram and Snapchat were missed here when they landed
            // (2026-07-31) and TikTok would have been missed the same way:
            // all three connect by pointing at an export, which is exactly
            // what this badge is for, and all three were showing none.
            let imports: Set<String> = ["ChatGPT", "Claude", "Gemini",
                "Day One", "Apple Journal", "Kindle", "Bookmarks",
                "Instagram", "Snapchat", "TikTok", "X"]
            if imports.contains(name) { return "Import" }
            return nil
        }
    }

    /// A catalog date at midnight UTC — the join key for `Offer.added`. Only
    /// used for the "Just added" window, so day granularity is enough.
    static func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day
        c.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: c) ?? Date(timeIntervalSince1970: 0)
    }

    /// Grouped by what they're worth, verb taglines (S25).
    /// The full literal catalog — `scripts/catalog-sync.sh` greps THIS
    /// array's source text (every `Offer(name: "…"` line) to check parity
    /// with the website/onboarding, so it must keep every offer that has
    /// ever existed, unfiltered by platform. `offers` (below) is what every
    /// screen actually reads.
    static let allOffers: [Offer] = [
        Offer(name: "Photos",      tagline: "Screenshots, straight to your feed",            group: "Photos",    connectable: true),
        Offer(name: "Calendar",    tagline: "Events join your things",               group: "Schedule",  connectable: true),
        Offer(name: "Reminders",   tagline: "Lists stay in reach",                   group: "Schedule",  connectable: true),
        Offer(name: "Wallet",      tagline: "Any address — holdings and moves",          group: "Wallet",    connectable: true,
              alsoReads: ["Aave", "Morpho", "Uniswap", "Hyperliquid", "Aerodrome", "Spark"],
              needsSetup: true),
        // Wallet group by ruling (user, 2026-07-21, prd §162). Privacy Pools
        // rides the watched wallets the Peer way: no account exists to
        // connect — deposits come from the person's own wallet, so the seat
        // is a switch over the watched list.
        Offer(name: "0xBow Privacy Pools", tagline: "Know when your deposit clears",       group: "Wallet",    connectable: true,
              needsSetup: true, added: day(2026, 7, 21)),
        // Wallet group, beside Privacy Pools and Railgun (prd §403). Altana is
        // an onchain KEYSTORE — a public registry of the credentials allowed
        // to sign for an account — so it rides the watched wallets the Peer
        // way: no account, no key, nothing to connect but a wallet you already
        // watch.
        //
        // The summary names the two ceilings, because both would otherwise be
        // assumed the other way. A session key's SCOPE is not published, so
        // this says what a key may sign UNTIL and never what it may sign FOR;
        // and revoking happens on Altana's own surface, never here (§112).
        Offer(name: "Altana", tagline: "Which keys can sign as you", group: "Wallet", connectable: true,
              needsSetup: true, added: day(2026, 8, 18)),
        // Wallet group, beside Privacy Pools — the same category for the same
        // reason (prd §268): Railgun trades nothing, it's your own funds
        // wearing a privacy status, and it rides the watched wallets with no
        // account and no key.
        //
        // The summary names all three ceilings plainly, because the obvious
        // expectation of a privacy-tool feed is that it shows your private
        // balance, and this one can't and shouldn't: nothing inside the pool
        // is read; an unshield can never name its sender; and native ETH
        // shields route through a wrapper that leaves the wallet in no log.
        // The middle one is the interesting half, not an apology — it's the
        // only shape in this app where someone can pay you privately and the
        // money still shows up.
        Offer(name: "Railgun", tagline: "See what you shield, and what comes back", group: "Wallet", connectable: true,
              needsSetup: true, added: day(2026, 8, 1)),
        // Wallet group, and the only seat here that reads no money at all (prd §419):
        // every other one reads what your funds did, this reads what the SOFTWARE
        // holding them does. Walletbeat is an independent, MIT-licensed registry.
        Offer(name: "Walletbeat", tagline: "How your wallet apps actually behave", group: "Wallet", connectable: true,
              needsSetup: true, added: day(2026, 8, 20)),
        Offer(name: "ENS",         tagline: "Follow a name, know when it expires", group: "Wallet", connectable: true,
              needsSetup: true, added: day(2026, 8, 29)),
        // WALLET group (user ruling, 2026-08-20, prd §420). Settled twice the
        // same afternoon: first to Shopping on §222's receipts-vs-account
        // line, then to Wallet on a better one — WALLET IS THE INSTRUMENTS YOU
        // PAY WITH, SHOPPING IS THE MERCHANTS YOU SPEND AT. Privacy.com moved
        // here in the same pass for the same reason, so §222's "Privacy.com
        // sits in Shopping" is amended and must not be cited again. Note this
        // seat therefore has NO standalone chip — `CategoryFold` folds Wallet's
        // chips with no floor, so it is a venue in that cluster's switcher, one
        // tap deeper, knowingly. It still pairs with Apple Wallet across the
        // catalog: that seat is the only one here that sees a MERCHANT name,
        // this is the only one that knows which offer sits unused on which
        // card. The tagline names the subscription because every read needs it
        // — measured, all five of their tools answer "-32001" for a free
        // account — and a tile that discovered that after the tap is the §83
        // dead control.
        Offer(name: "CardPointers", tagline: "Unused card offers — needs CardPointers+", group: "Wallet", connectable: true,
              needsSetup: true, added: day(2026, 8, 20)),
        // Wallet group by ruling (prd §222, 2026-07-26): a Gnosis Pay account
        // IS a Safe holding your own balance, so it belongs beside the wallets
        // whose total it joins — not Shopping, where Privacy.com's card
        // receipts live, because this is the account and not just the receipt.
        // Honesty note: the summary names BOTH ceilings plainly — no merchant
        // names (they never reach the chain) and no refunds (they settle off
        // it) — because the obvious expectation of a card feed is that it
        // reads like a statement, and this one can't.
        Offer(name: "Gnosis Pay",  tagline: "Card spending, straight off the chain", group: "Wallet",    connectable: true,
              needsSetup: true, added: day(2026, 7, 26)),
        // Apple Wallet (prd §313, 2026-08-06) — FinanceKit, granted by Apple
        // for this bundle id on request QVDBMBPMJU. Wallet group beside Gnosis
        // Pay for that seat's own reason: a card feed belongs with the cards.
        // The summary's third paragraph is the entitlement's terms in plain
        // words and is NOT ordinary marketing copy — see AppleWalletScreen.
        // The last line names the two ceilings so the copy can never drift
        // past them: US-only, and pending charges aren't a statement.
        Offer(name: "Apple Wallet", tagline: "What your card actually spends",  group: "Wallet",    connectable: true,
              // Dead on Mac, and it always was (2026-08-12). FinanceKit is
              // compiled out of the Catalyst build outright
              // (`#if canImport(FinanceKit) && !targetEnvironment(macCatalyst)`,
              // AppleWalletBridge.swift:3) and the Mac profile carries no such
              // entitlement, so every Mac connect could only ever reach the
              // `.unavailable` branch — whose sentence reads "This iPhone
              // can't share financial data… this needs iOS 17.4 or later" in
              // a macOS window. A tile whose only outcome is a dead control
              // wearing a false sentence is the honesty rule twice over, and
              // Health/Strava/HomeKit already set the precedent for a seat
              // that cannot exist here.
              needsSetup: true, added: day(2026, 8, 6), unavailableOnMac: true),
        // Wallet group by ruling (user, 2026-07-21): the balances MERGE into
        // the combined portfolio, so an exchange belongs beside the wallets
        // whose total it joins — not in Markets, which was where things you
        // watched rather than owned lived until that category was deleted
        // (2026-09-06, prd §638).
        Offer(name: "Coinbase",    tagline: "Your exchange balance, in your total",  group: "Wallet",    connectable: true,
              needsSetup: true, added: day(2026, 7, 21)),
        Offer(name: "Kraken",      tagline: "Your exchange balance, in your total",  group: "Wallet",    connectable: true,
              needsSetup: true, added: day(2026, 7, 21)),
        Offer(name: "Binance",     tagline: "Your exchange balance, in your total",  group: "Wallet",    connectable: true,
              needsSetup: true, added: day(2026, 7, 27)),
        // "Gemini Exchange", not "Gemini" — the catalog already has an offer
        // named "Gemini" (the Google AI chat importer), an unrelated company
        // that happens to share the word. Named fully everywhere it's
        // user-facing (this tile, the venue's display name, the website) so
        // the two are never confused for one another.
        Offer(name: "Gemini Exchange", tagline: "Your exchange balance, in your total", group: "Wallet", connectable: true,
              needsSetup: true, added: day(2026, 7, 27)),
        // A validator can't be FOUND from a wallet address the way a Solana
        // stake account can (see EthValidatorWatch.swift) — the only free
        // path is asking for the index directly, which is why this is a
        // named watch-list like Tokens/Kalshi rather than something that
        // rides a watched wallet automatically.
        Offer(name: "ETH Validators", tagline: "Your validator balance, in your total", group: "Wallet", connectable: true,
              needsSetup: true, added: day(2026, 7, 27)),
        Offer(name: "Gmail",       tagline: "Your inbox, findable",                  group: "Mail",      connectable: true,
              needsSetup: true),
        Offer(name: "iCloud Mail", tagline: "Your @icloud.com inbox, findable",      group: "Mail",      connectable: true,
              needsSetup: true),
        Offer(name: "ChatGPT",     tagline: "Import your chats, keep them findable", group: "Agent",     connectable: true,
              needsSetup: true),
        Offer(name: "Claude",      tagline: "Import your chats, keep them findable", group: "Agent",     connectable: true,
              needsSetup: true),
        Offer(name: "Claude Code", tagline: "Import your sessions, keep them findable", group: "Agent", connectable: true,
              needsSetup: true, added: day(2026, 8, 8)),
        Offer(name: "Gemini",      tagline: "Import your chats, keep them findable", group: "Agent",     connectable: true,
              needsSetup: true),
        // MARKETS IS DELETED (user ruling 2026-09-06, prd §638: "i want to get
        // away from crypto bullshit but wallets and the other stuff in them
        // are important"). Six seats went with the category — Kalshi,
        // Polymarket, GeckoTerminal, Circle x402, 1Claw and Open Food Facts
        // — and the ones that read as a lens on money you hold (Tokens,
        // L2BEAT) moved to Wallet. OpenSea moved with them and was retired
        // the same day by the ruling's second amendment. Their bridge files
        // stay in the
        // tree for one release so a connected seat is not stranded, but
        // nothing here offers them, and nothing in the strip draws them
        // (`Corpus.retiredSources`).
        Offer(name: "Tokens",      tagline: "Track any token",                       group: "Wallet",    connectable: true,
              needsSetup: true),
        // STOCKTWITS CAME BACK THE SAME DAY, under WALLET (user ruling
        // 2026-09-06, §638's amendment). It was retired with the Markets
        // seats for one commit, and the ruling that deleted Markets is the
        // reason it returns: the category went because of "crypto bullshit",
        // and a stock is not crypto — it is the same kind of thing a Token
        // watch is, money you hold or nearly do, read from public price
        // data. Same seat, same copy, same keyless read; only the group moved.
        Offer(name: "Stocktwits",  tagline: "Watch any stock",                      group: "Wallet",    connectable: true,
              needsSetup: true),
        // Wallet, not Markets (2026-07-25, prd §210 — amending the 2026-07-17
        // ruling below, kept for the record). A Peer fill is the person's OWN
        // settled transaction landing in their OWN wallet — not a market they
        // watch, the same shape as Privacy Pools/Coinbase/Kraken, all already
        // in Wallet. §207 made this literal: Peer rides the watched wallets
        // automatically and its connect routes straight to the Wallet manager
        // (§209) — it already walks and talks like a wallet feature, not a
        // marketplace. (Original ruling, 2026-07-17 — corrected from Onchain
        // the same day: Peer rides the Wallet bridge the way Strava rides
        // Apple Health, prd §113: no account exists to connect — trades
        // settle into the person's own wallet, so the seat is a switch over
        // the watched list. That mechanism argument is now Wallet's own
        // argument too — it no longer distinguishes the two groups.)
        Offer(name: "Peer",        tagline: "Your trades, as they settle",      group: "Wallet",    connectable: true,
              needsSetup: true, added: day(2026, 7, 17)),
        // Wallet group, beside Peer/Privacy Pools/Gnosis Pay (2026-07-30): a
        // Safe multisig is your own account too, and the seat rides the
        // watched wallets the same way — no account, no key, watching is
        // consent (§207). Split from a generic Wallet feature into its own
        // tile once it grew a second detection path (a watched EOA that's a
        // SIGNER on a Safe, not just a directly-watched Safe address) and its
        // own alert class (owner/threshold/module changes) — too much to
        // fold into one bullet under Wallet's summary honestly.
        // The summary said "signing always happens in your own Safe app" until
        // 2026-08-21, and prd §425 made that false — the §303 tripwire class,
        // caught by reading rather than by any check, because the setup-copy
        // audit governs the SCREEN's intro and this is the product page.
        // Whatever this offer claims about signing has to move in the same
        // commit as the code that signs.
        Offer(name: "Safe",        tagline: "The signature queue, and this phone as a signer", group: "Wallet",    connectable: true,
              needsSetup: true, added: day(2026, 7, 30)),
        // THE FIVE THAT ARE NOT SEATS (prd §515, 2026-08-29) — Aave, Morpho,
        // Uniswap, Hyperliquid and Aerodrome had offers here from 2026-07-30
        // until this date, and the reason they are gone is the one test that
        // separates a seat from a reading: **a catalog seat lands rows under a
        // source of its own.** All five stamp `source: "Wallet"`, so
        // `BridgeRouter.roomSource` answered "Wallet" for every one of them and
        // Open went exactly where the Wallet seat's own Open goes — five icons,
        // one destination, and that destination already had an icon. Connect was
        // worse: there is nothing to connect (each sweep runs unconditionally
        // for every watched wallet inside `WalletIngest.refresh`), so it pushed
        // the wallet manager, a screen that cannot say why you are on it. A
        // person who tapped Aave with seven addresses watched got a door to a
        // room, a book and a chains row, and no answer at all.
        //
        // The capability did not go anywhere — it is stated on the Wallet offer
        // above, in its DeFi bullet and its `alsoReads` list, which is what a
        // catalog search for "aave" now resolves to. The comment on that bullet
        // used to say naming them there would "sell the same thing twice"; it
        // was right that it was twice, and wrong about which half to keep.
        //
        // Peer, 0xBow, Railgun, Safe, Altana, Gnosis Pay and ether.fi keep their
        // seats and pass the same test: every one lands rows under its own
        // source, so its icon is the only door to a room nothing else opens.
        Offer(name: "ether.fi",    tagline: "Your staked ETH, and the card",     group: "Wallet",    connectable: true,
              needsSetup: true, added: day(2026, 7, 31)),
        // WALLET since 2026-09-06 (prd §638), and the alternative §428 named
        // on 2026-08-21 is now the home: L2BEAT reviews CHAINS, and Wallet —
        // where Walletbeat sits reviewing wallet apps — was always the other
        // defensible seat. Markets won then because it was a venue you go to
        // in order to compare things before committing; with that category
        // deleted, the chains your money sits on are a lens on money you hold.
        // Still no standalone chip: it is a venue in the Wallet folder.
        Offer(name: "L2BEAT", tagline: "How safe the chains you use really are", group: "Wallet", connectable: true,
              needsSetup: true, added: day(2026, 8, 21)),
        // OPENSEA IS RETIRED (user ruling 2026-09-06, §638's second
        // amendment: "opensea should not have its own category or exist").
        // §638 had folded the `NFTs` group into Wallet so the drops seat
        // survived the category that held it; this finishes the job the
        // ruling started, and the group goes with the seat rather than
        // sitting in Wallet with nothing in it. Wallet keeps the NFTs you
        // HOLD — `WalletNFTShelf`/`WalletNFTPicks` (prd §387) read Alchemy on
        // the wallet's own sweep and are a different feature entirely; what
        // goes is following a chain for other people's new drops.
        // `OpenSeaBridge`/`OpenSeaScreen` stay one release like the other
        // retired seats, so a connected person is not stranded.
        // Shopping, not Markets (2026-07-17): Bitrefill is your own commerce
        // account — orders and receipts — not a market you watch.
        Offer(name: "Bitrefill",   tagline: "Your gift cards, in reach",             group: "Shopping",  connectable: true,
              needsSetup: true, added: day(2026, 7, 17)),
        // Shopping, beside Bitrefill: Privacy.com is your own card-spending
        // record — receipts across every merchant — not a market you watch.
        // Honesty note (2026-07-22): Privacy's key is NOT scoped read-only, so
        // the summary says plainly that the read-only promise is kept by
        // conduct, not by the credential (unlike every other keyed bridge).
        Offer(name: "Privacy",     tagline: "Your card purchases, in reach",         group: "Wallet",  connectable: true,
              needsSetup: true, added: day(2026, 7, 22)),
        Offer(name: "Shopify",     tagline: "Follow any store's new drops",          group: "Shopping",  connectable: true,
              needsSetup: true),
        Offer(name: "Deals",       tagline: "The best prices, as they drop",          group: "Shopping",  connectable: true,
              needsSetup: true),
        Offer(name: "Venice",      tagline: "Private answers with your key",         group: "Agent",     connectable: true,
              needsSetup: true),
        // "Nothing here trades" went false on 2026-08-29 (prd §529) and is
        // true again (2026-09-03): the second verb is gone and every prompt
        // carries the answer-only rail. The summary says what Bankr IS, whose
        // account it uses, and that Casberi only ever asks it questions —
        // the strongest fact last, because it is the one that holds.
        Offer(name: "Bankr",       tagline: "An agent that knows the market", group: "Agent", connectable: true,
              needsSetup: true),
        // 1Claw (the agents' vault, 2026-07-17, prd 111) left the catalog on
        // 2026-09-06 with the Markets seats (prd §638).
        // OpenRouter (2026-07-24): a sixth agent key, one API routed across
        // 400+ models. It never pins one model — it rides OpenRouter's own
        // `openrouter/auto` router, so the answer's capabilities stay
        // honestly text-only/no-search rather than claiming whatever the
        // picked model might not have.
        Offer(name: "OpenRouter",  tagline: "One key, whichever model fits",         group: "Agent",     connectable: true,
              needsSetup: true, added: day(2026, 7, 24)),
        // Grok (2026-07-31, prd §242): a seventh agent key. The eventual
        // reason for it isn't "a seventh model" — it would be the only
        // provider that could ever see X, which none of this app's own
        // bridges can read at all (closed API, no keyless path) — but that
        // search is UNBUILT (three docs fetches disagreed on xAI's current
        // wire shape; see the doc comment on `AgentProvider`), so nothing
        // user-facing claims it. What ships today is the same honest BYOK
        // contract every agent here keeps.
        // The credits line is MEASURED, not boilerplate (2026-07-31): xAI has
        // no free tier, and a key on a team without credits answers 200 to
        // the key check but 403 to every real request. Gemini's API *does*
        // have a free tier, so someone who added that key for nothing would
        // reasonably expect the same here and be wrong. Same shape as
        // Privacy.com's "Requires a paid Privacy plan" — a cost precondition
        // belongs in the offer, not discovered after connecting.
        Offer(name: "Grok",        tagline: "Try it with your own key",            group: "Agent",     connectable: true,
              needsSetup: true, added: day(2026, 7, 31)),
        Offer(name: "GitHub",      tagline: "Your work, and what you follow", group: "Work",      connectable: true,
              needsSetup: true),
        Offer(name: "GitLab",      tagline: "The issues and MRs assigned to you",     group: "Work",      connectable: true,
              needsSetup: true, added: day(2026, 8, 8)),
        // Work, not Agent (2026-08-03): the Agent group is BYO-key seats that
        // answer a question. This one publishes nothing and answers nothing —
        // it's a release feed for the hub AI ships on, which is the GitHub
        // seat's job three rows up, so it sits beside it.
        Offer(name: "Hugging Face", tagline: "What the AI world just shipped",       group: "Work",      connectable: true,
              needsSetup: true, added: day(2026, 8, 3)),
        // Peer-to-peer Git (prd §400). Work, beside GitHub and Hugging Face —
        // it is the same "what happened to the code" read pointed at a network
        // with no central host in it. Keyless in the strongest grade here:
        // `radicle-httpd` has no credential at all, so unlike GitHub's
        // read-only token there is nothing to mint and nothing to leak.
        Offer(name: "Radicle", tagline: "Peer-to-peer Git, as it happens", group: "Work", connectable: true,
              needsSetup: true, added: day(2026, 8, 18)),
        // Base's own experimental devnet testing EIP-8130 native account
        // abstraction (2026-08-23, moved to Wallet the same day). What it
        // watches is account-abstraction STANDING — which keys can act for
        // an address, its lock state — the same subject Safe and Altana
        // already hold this group for ("your Safe's queue and this phone as
        // a signer", "which keys can sign as you"), not developer tooling
        // like Radicle/Cursor and not a market. The Radicle SHAPE still
        // applies (no account, no key, watch an identifier and read its
        // state) — only the category read differently at first. The one
        // thing that makes this different from every other keyless watch
        // here is stated in the summary rather than assumed — vibenet's
        // contracts get redeployed on no fixed schedule, so nothing about it
        // may ever be treated as permanent.
        //
        // 2026-08-24: the summary's middle paragraph ("Watch an address and
        // see whether it's established, which keys can act for it, and
        // whether it's locked") said, in one sentence, what the line under
        // the icon and both feature rows already said — the tagline is
        // "Watch an account on Base's devnet", and the checks below name the
        // keys and the lock state in more detail than the paragraph could.
        // §192's split is the point: the hook says what this IS, the checks
        // carry the differentiated extras, and cramming them into both is
        // the same defect `whatLands` was fixed for on 2026-07-23 (it echoed
        // the tagline one line under itself). The paragraph's ONE unique
        // fact — established-or-not, a real state the room reads first and
        // no check named — became the first check rather than being trimmed
        // away with the repetition; the checks now run in the read's own
        // order (established, actors, lock).
        Offer(name: "Base Vibenet", tagline: "Watch an account on Base's devnet", group: "Wallet", connectable: true,
              // "no key" was true until 2026-08-29 and is not any more: the
              // THE NEVER-SIGNS BULLET IS GONE, and it had to go (prd §523,
              // 2026-08-29): `VibenetSend` gives `VibenetDeviceKey.sign` its
              // first caller, so the seat can now make an account. Saying
              // otherwise would be the §83 failure on the page where somebody
              // decides whether to connect. What replaces it is the part that
              // is still true and is the whole point — the key is made in the
              // Secure Enclave, cannot leave it, and costs a Face ID every
              // time it is used. `vibenet-selftest.sh` ties this bullet to the
              // code both ways: it may not claim read-only while a signing
              // path exists, and it may not give up the claim while none does.
              needsSetup: true, added: day(2026, 8, 23)),
        // THE NEVER-SIGNS BULLET IS GONE (prd §525, 2026-08-29), the same
        // day and the same reason as vibenet's: `HegotaSend` gives
        // `HegotaKey.sign` its first caller, so saying this seat only ever
        // reads would be the §83 failure on the page where somebody decides
        // whether to connect. What replaces it is the part that is different
        // from vibenet and has to be SAID as different — this key is a plain
        // secp256k1 scalar in the Keychain, not an Enclave key, on the user's
        // own ruling that a devnet with worthless money does not need
        // hardware-backed non-export. `hegota-selftest.sh` ties this bullet to
        // the code both ways.
        Offer(name: "Hegota Devnet", tagline: "Explore UTXOs — coins as objects, not a balance", group: "Wallet", connectable: true,
              needsSetup: true, added: day(2026, 8, 27)),
        // The OTHER frame-transaction devnet, and a separate seat by ruling
        // (user, 2026-09-01: "hegota is for hegota writ large" / "this one is
        // for Frames specifically"). The features below are deliberately NOT
        // Hegotá's: this chain implements no keyed nonces, so no bullet claims
        // parallel sends, and no bullet claims coins — it has none. What it
        // has that nothing else does is the SENDING, which is why that bullet
        // leads: EIP-8141 is a draft, so no released library encodes a frame
        // transaction at all.
        //
        // NO USER-VISIBLE STRING IN ANY DEVNET SEAT MAY CALL THIS APP A WALLET,
        // OR IMPLY IT BY COMPARISON (user, 2026-09-04). The tagline read "Send
        // a transaction no wallet can make" and the lead bullet "no other
        // wallet can encode one" — both position the app AS a wallet by saying
        // it does what wallets cannot, and this app has already been rejected
        // twice on crypto grounds (3.1.1 on BYOK, 3.1.5 on the devnet send).
        // The capability is unchanged and still said: "no released library
        // encodes one" is the same fact about EIP-8141 being a draft, with the
        // comparison moved off the app and onto the tooling. `library` and
        // `tooling` are safe words here; `wallet` is not.
        //
        // The reset bullet is not fine print. The network's own footer says it
        // may be reset without notice, and a seat that let somebody keep
        // something here without saying so would be the §83 failure on the
        // page where they decide whether to connect.
        Offer(name: "Frames Devnet", tagline: "Try Ethereum's new frame transactions", group: "Wallet", connectable: true,
              needsSetup: true, added: day(2026, 9, 1)),
        // The THIRD ethrex devnet (prd §593, 2026-09-04), and a chain of its
        // own — 8141, distinct genesis — not a re-host of Hegotá. A separate
        // seat on the same reasoning that split Frames from Hegotá: no chain
        // here is a superset of the others. Hegotá alone has the UTXO vault,
        // this one alone has EIP-8272's recent-roots predeploy, and Frames has
        // neither. Naming follows the family grammar, operator then chain:
        // Base Vibenet, Ethrex Hegotá, Ethrex Privacy.
        //
        // THE COPY MAY NOT SAY THIS CHAIN MAKES YOU PRIVATE, and the reason is
        // measured rather than cautious: all 14 type-0x6 transactions on it
        // carry `sender` in the clear, and EIP-8182's protocol-level shielded
        // pool is NOT deployed — the pool that exists is an ordinary contract
        // somebody deployed. What is shielded is the LINK between a commitment
        // and its spend. Somebody who reads "privacy features" and infers
        // shielded transfers has been misled on the page where they decide
        // whether to connect, which is §83 in the domain where believing it is
        // most expensive. Hence "the proposals" and "what it does and doesn't
        // hide" rather than any promise.
        //
        // WATCH-ONLY, and the bullets say so rather than leaving it to be
        // discovered. §593a could not reproduce this chain's type-0x6 envelope
        // byte-exactly — the shipped Hegotá encoder matches its own chain and
        // nothing here across every candidate encoding — so a send would sign
        // a guessed layout, which yields a signature that is well-formed,
        // recovers to a real address, and authorises something other than what
        // the screen said. The last bullet is the honest version of that and
        // must be removed in the same commit that lands sending, never before.
        Offer(name: "Privacy Devnet", tagline: "Try Ethereum's new privacy proposals", group: "Wallet", connectable: true,
              needsSetup: true, added: day(2026, 9, 4)),
        Offer(name: "Linear",      tagline: "Your issues stay in reach",             group: "Work",      connectable: true,
              needsSetup: true),
        Offer(name: "Notion",      tagline: "Pages join your things",                group: "Work",      connectable: true,
              needsSetup: true),
        Offer(name: "PostHog",     tagline: "The numbers behind what you ship",      group: "Work",      connectable: true,
              needsSetup: true, added: day(2026, 7, 27)),
        Offer(name: "Slack",       tagline: "Never miss a mention",                  group: "Work",      connectable: true,
              needsSetup: true, added: day(2026, 7, 28)),
        Offer(name: "Trello",      tagline: "The cards you're carrying",             group: "Work",      connectable: true,
              needsSetup: true, added: day(2026, 8, 3)),
        Offer(name: "Jira",        tagline: "The issues assigned to you",            group: "Work",      connectable: true,
              needsSetup: true, added: day(2026, 8, 8)),
        Offer(name: "Cloudflare",  tagline: "The dates behind the sites you run",    group: "Work",      connectable: true,
              needsSetup: true, added: day(2026, 8, 3)),
        Offer(name: "Sentry",      tagline: "The errors your users really hit",     group: "Work",      connectable: true,
              needsSetup: true, added: day(2026, 8, 4)),
        Offer(name: "Vercel",      tagline: "What shipped, and what broke",         group: "Work",      connectable: true,
              needsSetup: true, added: day(2026, 8, 4)),
        Offer(name: "PagerDuty",   tagline: "What caught fire, and for how long",   group: "Work",      connectable: true,
              needsSetup: true, added: day(2026, 8, 4)),
        Offer(name: "npm",         tagline: "Your dependencies, when they ship",    group: "Work",      connectable: true,
              needsSetup: true, added: day(2026, 8, 4)),
        Offer(name: "PyPI",        tagline: "Your Python packages, on release",     group: "Work",      connectable: true,
              needsSetup: true, added: day(2026, 8, 4)),
        Offer(name: "Cursor",      tagline: "What your coding agents did",          group: "Agent",     connectable: true,
              needsSetup: true, added: day(2026, 8, 4)),
        Offer(name: "App Store Connect", tagline: "How your app is doing",           group: "Work",      connectable: true,
              needsSetup: true, added: day(2026, 8, 6)),
        Offer(name: "AWS",         tagline: "What needs you, on your infrastructure", group: "Work",      connectable: true,
              needsSetup: true, added: day(2026, 8, 30)),
        Offer(name: "Stripe",      tagline: "What your money did today",             group: "Work",      connectable: true,
              needsSetup: true, added: day(2026, 7, 31)),
        Offer(name: "Polar",       tagline: "What your money did today",             group: "Work",      connectable: true,
              needsSetup: true, added: day(2026, 8, 30)),
        Offer(name: "Dodo Payments", tagline: "Every payment, the moment it lands", group: "Wallet",    connectable: true,
              needsSetup: true, added: day(2026, 8, 30)),
        Offer(name: "Reddit",      tagline: "Follow subreddits and people",          group: "Saves",     connectable: true,
              needsSetup: true),
        Offer(name: "YouTube",     tagline: "Follow any channel",                    group: "Watching",  connectable: true,
              needsSetup: true),
        Offer(name: "Apple Music", tagline: "What you play stays in reach",          group: "Listening", connectable: true),
        Offer(name: "Apple Health", tagline: "Workouts land in your feed",           group: "Fitness",   connectable: true,
              unavailableOnMac: true),
        Offer(name: "Strava",      tagline: "Every activity, one record",            group: "Fitness",   connectable: true,
              unavailableOnMac: true),
        // Garmin rides Apple Health exactly as Strava does (2026-09-06), and
        // for a harder reason: Garmin's own Health/Activity API is a partner
        // program you apply to as a business, with credentials that cannot
        // ship inside a client. Garmin Connect writes every activity to
        // HealthKit, so that read is the whole bridge — and the only honest
        // thing to promise. Its tagline is deliberately NOT Strava's: two
        // seats in one shelf saying the same six words is the collision
        // prd §518 removed from the catalog, arriving from the other side.
        Offer(name: "Garmin",      tagline: "Watch activities, in your feed",        group: "Fitness",   connectable: true,
              added: day(2026, 9, 6), unavailableOnMac: true),
        Offer(name: "Cal.com",     tagline: "Bookings land in your feed",            group: "Schedule",  connectable: true,
              needsSetup: true),
        Offer(name: "Calendly",    tagline: "Meetings join your things",             group: "Schedule",  connectable: true,
              needsSetup: true),
        Offer(name: "Todoist",     tagline: "Tasks beside your lists",               group: "Schedule",  connectable: true,
              needsSetup: true),
        Offer(name: "Pinterest",   tagline: "Your pins, in your feed",               group: "Images",    connectable: true,
              needsSetup: true),
        Offer(name: "Raindrop",    tagline: "Bookmarks become findable",             group: "Saves",     connectable: true,
              needsSetup: true),
        Offer(name: "Readwise",    tagline: "Highlights stay with you",              group: "Reading",   connectable: true,
              needsSetup: true),
        Offer(name: "Apple Journal", tagline: "Your entries, findable",              group: "Notes",     connectable: true,
              needsSetup: true),
        Offer(name: "Day One",     tagline: "Import your journal",                   group: "Notes",     connectable: true,
              needsSetup: true),
        Offer(name: "Apple Notes", tagline: "Share notes in",                        group: "Notes",     connectable: true,
              needsSetup: true),
        Offer(name: "RSS",         tagline: "Any site with a feed",                  group: "Reading",   connectable: true,
              needsSetup: true),
        // Social, with Bluesky (user ruling 2026-07-17, reversing the
        // 2026-07-14 "onchain network" shelving): Farcaster is a social account
        // first — it browses beside Bluesky, and its detail eyebrow says so.
        Offer(name: "Farcaster",   tagline: "Any account — casts, channels, likes",           group: "Network",   connectable: true,
              needsSetup: true),
        // Telegram RETURNS (prd §456, 2026-08-23), reversing §57's 2026-07-14
        // removal. That ruling weighed three doors and cut the seat because
        // all three failed; what it did not weigh is that a public CHANNEL is
        // not a chat — it is broadcast media with a public web page, so it
        // reads the way Substack does, with no server and no MTProto. The
        // export import is the second door, and the reason the two share one
        // seat rather than two tiles.
        Offer(name: "Telegram",    tagline: "Follow public channels",                group: "Network",   connectable: true,
              needsSetup: true, added: day(2026, 8, 23)),
        Offer(name: "Bluesky",     tagline: "Any account — posts, feeds, likes",             group: "Network",   connectable: true,
              needsSetup: true),
        // Network, beside Farcaster/Bluesky (2026-07-27): a third open,
        // keyless protocol — public relays serve reads with no account and
        // no key. Connects by npub, raw hex pubkey, or a NIP-05 identifier
        // ("name@domain.com") instead of a username, since Nostr has no
        // global directory to search.
        Offer(name: "Nostr",       tagline: "Any account, as it posts",               group: "Network",   connectable: true,
              needsSetup: true, added: day(2026, 7, 27)),
        // Network, beside the open protocols — and the opposite of them
        // (2026-07-31, prd §245). Farcaster/Bluesky/Nostr connect with a name
        // because their posts are public; Instagram has no keyless read at
        // all, so it connects by IMPORT, the ChatGPT grade. The summary states
        // the split the export itself has rather than letting "your saves"
        // imply a caption we never receive: what you MADE arrives as text,
        // what you TAPPED arrives as a named link. Saying that here is the
        // honesty rule — the alternative is a seat that reads as full search
        // over your saves and isn't.
        Offer(name: "Instagram",   tagline: "Your posts and saves, findable",        group: "Network",   connectable: true,
              needsSetup: true, added: day(2026, 7, 31)),
        // The second import-grade social seat, beside Instagram (2026-07-31, prd
        // §246). Snapchat has no keyless read either — and less than no read:
        // Login Kit's entire scope list is a display name, a Bitmoji avatar
        // and a user id, so a connect-by-name seat could only ever say
        // "connected" and land nothing. The export is the one door, and the
        // copy names what the export honestly holds.
        Offer(name: "Snapchat",    tagline: "Import your saved chats and memories",  group: "Network",   connectable: true,
              needsSetup: true, added: day(2026, 7, 31)),
        // The third import-grade social seat (2026-08-02, prd §279), and the
        // one that overturns a ruling this app made twice: §36 and §244 both
        // declined TikTok because the export lands 1–4 days stale, which is
        // fatal for a FEED and irrelevant for an IMPORT — the same reasoning
        // Instagram and Snapchat shipped on the day §244 was written.
        //
        // The tagline leads with the deadline because the deadline is the
        // pitch: TikTok makes you wait up to four days and then gives you four
        // days to act. The summary states the export's own split (§245's rule)
        // AND the one thing this import does that Instagram's can't — TikTok's
        // oEmbed endpoint is live and keyless, so a bare saved link can be
        // given back its caption, its creator and its cover.
        Offer(name: "TikTok",      tagline: "Your saves, before the link expires",   group: "Network",   connectable: true,
              needsSetup: true, added: day(2026, 8, 2)),
        // The fourth import-grade social seat, and the one with the least
        // choice behind it (2026-08-02, prd §280). Instagram and TikTok at
        // least have a theoretical API; X discontinued its free tier for new
        // developers on 2026-02-06 and now charges per post read, so there is
        // no keyless door and no cheap one. The archive is all of it.
        //
        // The summary names the BOOKMARKS GAP in its own line. That is not
        // hedging — bookmarks are the pile an X user would most expect this
        // seat to hold, they have never been in the export, and an offer that
        // let "your saves" imply them would be selling something it can't
        // deliver. §245's rule, applied to the one absence that matters here.
        Offer(name: "X",           tagline: "Your posts and likes, searchable",     group: "Network",   connectable: true,
              needsSetup: true, added: day(2026, 8, 2)),
        Offer(name: "Steam",       tagline: "What you play, in your feed",           group: "Games",     connectable: true,
              needsSetup: true),
        Offer(name: "Obsidian",    tagline: "Your vault, beside your things",        group: "Notes",     connectable: true,
              needsSetup: true),
        // Any folder, not just an Obsidian vault (2026-07-27) — Files
        // generalizes the same "point at a folder" mechanism past Markdown to
        // whatever's inside: receipts, scans, a Downloads folder redirected to
        // iCloud Drive. NOT the Notes group (user ruling, 2026-07-27): Notes'
        // other three members are all genuinely writing/journaling tools, and
        // a picked folder's contents are unpredictable — it fits the Life
        // category's personal-life miscellany better (the same reasoning that
        // put HomeKit there). Own "Storage" group so its detail-page eyebrow
        // reads honestly ("Storage · Files", not "Notes · Files").
        Offer(name: "Files",       tagline: "Any folder, findable",                  group: "Storage",   connectable: true,
              needsSetup: true, added: day(2026, 7, 27)),
        // Storage, beside Files (2026-07-27): the same "point at a folder"
        // idea, reading Dropbox's own API instead of a local bookmark — so it
        // works without the Dropbox app installed, and Dropbox's own delta
        // cursor makes a delete arrive as news instead of something a re-walk
        // has to infer. Scoped to the folder you name ONLY — never a shared
        // link, never "shared with me" — the reasoning the user gave for
        // building this at all: a stranger sharing something with you can
        // never make it appear here.
        Offer(name: "Dropbox",     tagline: "Your files, without the notifications", group: "Storage", connectable: true,
              needsSetup: true, added: day(2026, 7, 27)),
        Offer(name: "Twitch",      tagline: "Live follows land in your feed",        group: "Watching",  connectable: true,
              needsSetup: true),
        Offer(name: "Substack",    tagline: "Follow any publication",                group: "Reading",   connectable: true,
              needsSetup: true),
        Offer(name: "Kindle",      tagline: "Import your highlights",                group: "Reading",   connectable: true,
              needsSetup: true),
        // Reading group, beside Kindle (2026-07-28, prd §224, corrected same
        // day from an initial Notes placement) — both are import-only, no
        // live read. Safari has no bookmarks API at all, and Chrome's own
        // export never includes its separate Reading List store. Both
        // browsers write the SAME file format though (Netscape Bookmark File
        // Format), so one offer, one parser, one screen covers both —
        // Safari's Reading List rides along as a folder inside that same
        // file, for free.
        Offer(name: "Bookmarks",   tagline: "Safari and Chrome, imported",                 group: "Reading",   connectable: true,
              needsSetup: true, added: day(2026, 7, 28)),
        Offer(name: "Podcasts",    tagline: "Follow any show",                       group: "Listening", connectable: true,
              needsSetup: true),
        Offer(name: "Contacts",    tagline: "The people you know, findable",         group: "People",    connectable: true),
    ]

    /// What every screen actually reads (Apps page, Home tile count, the
    /// onboarding mini store, `available(besides:)` below) — `allOffers`
    /// minus the seats that are dead on Mac. Filtering happens HERE, once,
    /// rather than at each of the ten-odd call sites, so nothing can add a
    /// new consumer that forgets the platform check.
    static var offers: [Offer] {
        #if targetEnvironment(macCatalyst)
        allOffers.filter { !$0.unavailableOnMac }
        #else
        allOffers
        #endif
    }

    /// Group order for the catalog screen (insertion order of first member).
    static var groups: [(String, [Offer])] {
        var order: [String] = []
        var buckets: [String: [Offer]] = [:]
        for offer in offers {
            if buckets[offer.group] == nil { order.append(offer.group) }
            buckets[offer.group, default: []].append(offer)
        }
        return order.map { ($0, buckets[$0] ?? []) }
    }

    // MARK: - Categories (merge map over Offer.group — Browse + chart filter
    // ONLY, never vertical section headers). Moved here from AppsScreen
    // (2026-07-20) so the agent's `category:<name>` kept-ask kind reads the
    // SAME mapping the catalog page shows — the whole point of this being
    // the ruled single source of truth.
    static let categories: [(name: String, exemplar: String, groups: Set<String>)] = [
        // WALL ORDER IS THE USER'S, DICTATED BAND BY BAND (ruling 2026-08-06,
        // prd §322): "wallet, work, life, agents, media, social, mail,
        // shopping and whatever else if there is another category" — the three
        // they didn't name (Markets, Notes, Reading) keep their relative order
        // and settle after Shopping. (Markets itself is DELETED as of
        // 2026-09-06, prd §638 — the notes below that place it are the
        // record of an order that no longer has that band in it.)
        //
        // It keeps every property the earlier rulings were protecting and
        // states them plainly, so a later pass doesn't "restore" one of them:
        //   • Wallet leads, Markets sits far from it (ruling 2026-07-23) — two
        //     crypto bands up top read as a crypto-only app. Markets is now
        //     ninth, so that gap is wider than it has ever been.
        //   • Work is second (ruling 2026-08-06, prd §321): 14 live seats,
        //     every one a real connect, and the strongest answer to the same
        //     crypto-wall problem.
        //   • Life third pulls the Apple apps (Photos, Calendar, Reminders,
        //     Health, Contacts, Files) up where a new phone can connect
        //     something in one tap.
        //   • Social keeps a mid slot. It used to be ruled adjacent to MAIL;
        //     that category no longer exists (below), so the pairing dissolved
        //     rather than being broken.
        //
        // MAIL IS NOT ITS OWN CATEGORY (user ruling 2026-08-06, prd §326:
        // "mail doesn't need it's own category"). It was the only two-seat
        // category in the catalog and drew a half-empty band wherever it sat.
        // Its group folds into Life, which is where mail belongs by the same
        // reasoning that already pulled Home, People and Storage in: a band of
        // the things that are yours rather than a dedicated content type.
        //
        // MARKETS SAT AHEAD OF SHOPPING AND NOTES (same ruling), well clear of
        // Wallet — seventh, not second — so the 2026-07-23 property this
        // order exists to protect (no two crypto bands up top) held. The
        // band is gone entirely since 2026-09-06 (prd §638): Tokens, L2BEAT
        // and (for one day) OpenSea fold into Wallet, the other seven seats
        // are retired,
        // and the "two crypto bands" problem is closed by there being one.
        //
        // **Unlike §322, a seat DOES change category here.** Every Mail-group
        // offer now answers "Life" from `category(of:)`, so a kept ask of the
        // form `category:Mail` no longer resolves — see `KeptAskComposers`.
        // Nothing migrates it: the ask simply finds no category and composes
        // nothing, which is the same outcome as a category being renamed and
        // is why the recap is written to tolerate an unknown name.
        // "NFTs" joined Wallet's groups when Markets was deleted (2026-09-06,
        // prd §638) and left again the same day with OpenSea, its only
        // offer (§638's second amendment). A group nothing declares is a
        // heading waiting to render blank — the reason "Home" is gone from
        // this list too, three rows down.
        ("Wallet",  "Wallet",      ["Wallet"]),
        ("Work",    "GitHub",      ["Work"]),
        // "Home" is GONE from this list, not merely empty (2026-09-04). Life
        // absorbed it on 2026-07-23 because HomeKit was the lone app in its
        // own category; with HomeKit itself retired (App Review 2.5.1) the
        // group has no offers at all, and a named group that can never
        // resolve one is a heading waiting to render blank. "People"
        // (Contacts) already lives here (2026-07-20). Storage joins for the
        // same reason (user ruling 2026-07-27): Files' folder contents are
        // unpredictable, so it reads as personal-life miscellany, not a
        // dedicated content type.
        ("Life",    "Photos",      ["Photos", "Schedule", "Fitness", "People", "Storage", "Mail"]),
        ("Agents",  "Claude",      ["Agent"]),
        ("Media",   "YouTube",     ["Watching", "Listening", "Games", "Images"]),
        ("Social",  "Bluesky",     ["Network"]),
        // Reading sits AHEAD of Shopping (user ruling 2026-08-06, "should
        // reading come before shopping?"). Two reasons, both about the band
        // rather than the taste: Reading is 7 seats to Shopping's 5, and every
        // one of them is a live connect that fills the feed with something to
        // READ (RSS, Substack, Reddit, Readwise, Raindrop, Kindle, Bookmarks)
        // — the app's own core loop. Shopping is the narrowest band in the
        // catalog: Privacy needs a paid plan, Bitrefill is crypto gift cards
        // (Open Food Facts, a barcode scanner rather than a feed, was retired
        // 2026-09-06 with the Markets seats, prd §638).
        ("Reading", "Readwise",    ["Reading", "Saves"]),
        ("Shopping", "Shopify",    ["Shopping"]),
        ("Notes",   "Apple Notes", ["Notes"]),
    ]

    static func category(of offer: Offer) -> String {
        categories.first { $0.groups.contains(offer.group) }?.name ?? "Life"
    }

    /// The Agents category's name, DERIVED from the table above rather than
    /// spelled a second time (prd §550 — the agent's empty-chat link lands the
    /// catalog filtered to it).
    ///
    /// A category name is an ordinary string that doubles as a join key (a
    /// kept `category:…` ask resolves through it), so a rename must move every
    /// reader at once; a literal in another file is exactly the drift §326
    /// records when Mail's fold silently orphaned `category:Mail`. Nil when no
    /// category owns the `Agent` group, which every caller must treat as "no
    /// filter" rather than as an error — the catalog is still perfectly usable
    /// unfiltered.
    static var agentsCategory: String? {
        categories.first { $0.groups.contains("Agent") }?.name
    }

    /// The catalog category a landed SOURCE belongs to — the join `SourcesTray`
    /// groups by, so the tray reads like the catalog rather than inventing a
    /// second taxonomy (2026-08-06).
    ///
    /// A source name is NOT always an offer name, which is the whole reason
    /// this exists rather than a bare `offers.first { $0.name == source }`:
    /// `Thing.source` is "Privacy Pools" while the offer (and the wallet seat)
    /// is "0xBow Privacy Pools", so exact matching alone files the flagship
    /// privacy seat under nothing. The suffix rule fixes that family at a
    /// stroke — it is also what resolves "Music" → "Apple Music", "Notes" →
    /// "Apple Notes" and "Journal" → "Apple Journal", where the catalog carries
    /// the vendor prefix and the corpus does not.
    ///
    /// Matched on a SPACE boundary (`" " + source`), never `contains`: a bare
    /// substring test would file "Deals" under "Open Food Facts" the first time
    /// an offer name happened to carry the word. First match in catalog order
    /// wins, so the answer is stable and reviewable rather than dependent on
    /// dictionary ordering.
    ///
    /// Reads `allOffers`, not `offers`: a platform-filtered offer can still
    /// have landed things on this device (its rows sync from another one), and
    /// a source with rows in the corpus must never lose its category because
    /// the seat is hidden on the Mac.
    ///
    /// Returns nil for a source the catalog has never heard of — the caller
    /// decides what to do with it, because "we don't know" and "Life" are
    /// different answers and `category(of:)`'s default must not leak here.
    static func category(forSource source: String) -> String? {
        if let offer = offer(forSource: source) { return category(of: offer) }
        return categoryBySeatlessSource[source]
    }

    /// Sources with NO catalog seat, and the category they belong to anyway
    /// (2026-08-11).
    ///
    /// The catalog lists what you CONNECT, and a voice note connects nothing —
    /// the mic is an always-on device capability, which is why `offer(forSource:)`
    /// answers nil for it and why `demo-selftest.py` carries "Voice" in its own
    /// `KNOWN_NO_CATALOG_SEAT`. Every category-shaped read then filed it
    /// nowhere: the Sources Tray put it in the trailing "Other" block, and the
    /// source strip left it as the one bare brand circle sitting outside the
    /// fold beside a row of category words — "voice looks stupid by itself…
    /// notes is better" (user ruling 2026-08-11). A voice note is notes by any
    /// reading.
    ///
    /// **A CATEGORY, never a synthetic `Offer`.** Inventing an offer would be
    /// the cheaper-looking fix and would be wrong in four places at once: it
    /// would give Voice a product page and a Connect button for a capability
    /// with nothing to connect, put a tile in the catalog grid and on the
    /// website (which `catalog-sync.sh` enforces as one set), and make
    /// `SourceChips.chip` look for a BridgeApp seat named "Voice" when it
    /// decides whether to draw the needs-reconnecting ring. Mapping the
    /// category alone leaves all of that untouched — `offer(forSource:)` still
    /// answers nil, so seat resolution is unchanged everywhere.
    ///
    /// The value must name a real `categories` entry; `category-fold-selftest.sh`
    /// fails the build if it ever stops doing so (a category renamed out from
    /// under this table would silently put Voice back in "Other").
    private static let categoryBySeatlessSource: [String: String] = [
        "Voice": "Notes",
    ]

    /// The catalog offer a landed SOURCE belongs to — the join itself, factored
    /// out of `category(forSource:)` because grouping was never the only thing
    /// that needs it (2026-08-06).
    ///
    /// An offer's name is also the name its BRIDGE registers under
    /// (`BridgeStore.registerConnected(id:name:)` is handed `WalletSeat.name`,
    /// which is the offer name), so this doubles as source → seat. That matters
    /// for every read that asks "is this source's connection in trouble": the
    /// two source chips compared a chip label against `BridgeApp.name`
    /// directly, so for the family whose names differ — "Privacy Pools" the
    /// source against "0xBow Privacy Pools" the seat — the dashed
    /// needs-reconnecting ring could never light, no matter how broken the
    /// connection was. Silent by construction: a seat that never draws the ring
    /// looks exactly like a seat that is perfectly healthy.
    ///
    /// See `category(forSource:)` above for why the match is exact-then-suffix
    /// on a SPACE boundary rather than `contains`, and why it reads `allOffers`.
    ///
    /// **INDEXED, and that is a crash fix rather than a tidy-up (2026-09-05).**
    /// This was two `allOffers.first(where:)` scans returning an `Offer` BY
    /// VALUE, and `Offer` is nine stored properties including four `String`s
    /// and two `[String]`s — so every call walked up to ~90 offers twice and
    /// then deep-copied the winner, retaining a bridge object per field.
    /// `SourceChips.chip(_:pinned:)` calls it once PER CHIP, inside a
    /// `ForEach` content closure, so the whole thing re-ran for every chip on
    /// every observation-driven graph update. Build 522 died there: a
    /// `process-exit` watchdog ("Failed to terminate gracefully after 5.0s")
    /// whose main thread was `swift_bridgeObjectRetain` ←
    /// `initializeWithCopy for BridgeCatalog.Offer` ← `offer(forSource:)` ←
    /// `SourceChips.chip(_:pinned:)` ← `ForEachChild.updateValue()`. The same
    /// rail was already on record as a measured latency cause (the source rail
    /// resolving chips 4-5x per body pass); this is that finding as a fix.
    ///
    /// Semantics are UNCHANGED and that is the point — exact name first, then
    /// the first offer in `allOffers` order whose name ends in
    /// `" " + source`. The maps below are built to preserve both, including
    /// the first-wins tie-break, so no caller has to think about it.
    static func offer(forSource source: String) -> Offer? {
        guard let name = seatNameBySource[source] else { return nil }
        return offerByName[name]
    }

    /// The seat NAME for a source, without copying an `Offer` (2026-09-05).
    ///
    /// Every hot caller of `offer(forSource:)` wanted exactly `?.name ?? source`
    /// — the strip, the venue switcher, the room gear's label, the feed's two
    /// reads — and paying a nine-field struct copy to read one `String` is
    /// what put the chip strip on a crash report. One dictionary lookup and one
    /// retain now. Callers that genuinely need the whole offer still take it.
    static func seatName(forSource source: String) -> String {
        seatNameBySource[source] ?? source
    }

    /// `allOffers` by name, first occurrence winning — `first(where:)`'s own
    /// tie-break, kept so a duplicated name cannot quietly change which offer
    /// resolves.
    private static let offerByName: [String: Offer] = {
        var map: [String: Offer] = [:]
        for offer in allOffers where map[offer.name] == nil { map[offer.name] = offer }
        return map
    }()

    /// Source → seat name, covering BOTH routes `offer(forSource:)` answers.
    ///
    /// Built suffixes-first and exact names second, so an exact match always
    /// overwrites a suffix route — the order the linear version tried them in.
    /// Within each pass `allOffers` is walked in REVERSE and writes are
    /// unconditional, so the EARLIEST offer ends up as the stored value, which
    /// is `first(where:)`'s tie-break again.
    ///
    /// Suffixes are taken at real space boundaries by walking the string rather
    /// than by `split`, because `split` collapses runs of spaces and
    /// `hasSuffix(" " + source)` does not — no offer name has a double space
    /// today, and this way none ever has to.
    private static let seatNameBySource: [String: String] = {
        var map: [String: String] = [:]
        for offer in allOffers.reversed() {
            let name = offer.name
            var i = name.startIndex
            while let space = name[i...].firstIndex(of: " ") {
                let after = name.index(after: space)
                map[String(name[after...])] = name
                i = after
            }
        }
        for offer in allOffers.reversed() { map[offer.name] = offer.name }
        // RENAMED SEATS, LAST AND NON-DESTRUCTIVELY (prd §647, 2026-09-08).
        // A row keeps its `source` string forever, so a seat that was renamed
        // leaves rows behind that resolve to no offer at all — no category, so
        // the chip escapes `CategoryFold` and sits in the dock as a bare circle
        // beside a row of category words, wearing `BridgeGlyph`'s blank `app`
        // fallback. `Corpus.renamedSources` is the one table that says which
        // string means which seat; see its own doc for why the one-shot
        // migration that used to be the whole answer could not be.
        //
        // Written only where nothing already answers, so a live offer name can
        // never be displaced by an alias — the same "an exact match always
        // wins" property the two passes above are ordered for.
        for (old, rename) in Corpus.renamedSources where map[old] == nil { map[old] = rename.current }
        return map
    }()

    /// Offers not yet among the person's bridges — what the Apps page lists
    /// under Available and the tile counts as "to add". A–Z: the flat list is
    /// an inventory you scan by name (the grouped catalog keeps value order —
    /// its job is selling the worth; this list's job is lookup).
    static func available(besides bridgeNames: [String]) -> [Offer] {
        let taken = Set(bridgeNames)
        return offers.filter { !taken.contains($0.name) }
            .sorted { $0.name < $1.name }
    }
}
