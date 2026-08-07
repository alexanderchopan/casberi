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
        /// The App-Store-style detail-page copy — what connecting is worth,
        /// in Bob's words. PARAGRAPH RULE (user, 2026-07-25): a paragraph
        /// holds at most two sentences; when a summary needs a third, a blank
        /// line (`\n\n`) starts a new paragraph, so nothing reads as a wall of
        /// prose. The break falls on the BEAT, not mechanically every two
        /// sentences — the usual shape is "what lands" / "how it connects +
        /// the read-only promise", and a beat that spans two sentences (the
        /// safety promise, an honest caveat) stays whole rather than being
        /// split to hit the count. A two-sentence hook stays one paragraph.
        /// Rendered by `AppDetailScreen` via `Text` (the `\n\n` is a real
        /// paragraph gap); the same rule governs the long setup/manage-sheet
        /// `Text` blocks. Localized copies carry the SAME breaks (the beats
        /// translate), split at the matching sentence boundary per language.
        let summary: String
        /// Extra capabilities beyond the hook, as short scannable lines
        /// (prd §192, 2026-07-23) — the fix for a real tension the three-beat
        /// summary rule exposed: Wallet's differentiated features (approval
        /// alerts, DeFi positions, the Safe queue) don't fit a one-sentence
        /// hook, but cramming them into the summary as a second run-on clause
        /// bloated it to 107 words and buried the actual promise. Rather than
        /// deleting real, true, differentiating information to match a word
        /// count, it moves to its own scannable list — same content, same
        /// checkmark grammar `BridgeConnectedState.capabilities` already
        /// established for the CONNECTED state, so a person reads the same
        /// visual language before and after they connect. Empty for the
        /// other 54 offers, whose one-sentence hook already says it all.
        var features: [String] = []
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
        /// Mac Catalyst — HealthKit and HomeKit don't exist there at all
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

        /// The Mac-accurate summary, for the one offer whose iOS wording
        /// makes a promise Mac can't keep (Mac polish, 2026-07-28). "The
        /// screenshots you take flow into your feed" is true on iPhone/iPad;
        /// on Mac a screenshot goes to the Desktop, not the Photos library,
        /// so this seat only ever sees ones that arrive via iCloud Photos
        /// from another device — a real, still-useful seat, just not what
        /// the iOS sentence describes. Falls back to `summary` everywhere
        /// else, including Photos on iOS/iPadOS.
        ///
        /// The closing sentence (2026-07-31) points at the seat that DOES
        /// cover a Mac screenshot: `FilesBridge.heal` already thumbnails,
        /// OCRs, and retitles any image a connected folder sees — the exact
        /// machinery Photos runs on iOS — and `isMachineGeneratedName`
        /// already matches a `screenshot`-prefixed filename, which is how
        /// macOS names its own. Connecting `~/Desktop` through Files gets a
        /// Mac screenshot the same treatment for free; leaving the summary
        /// silent about that read as the gap being unaddressed rather than
        /// one door over.
        var effectiveSummary: String {
            #if targetEnvironment(macCatalyst)
            if name == "Photos" {
                return "Screenshots synced from your iPhone or iPad flow into your feed, searchable by what's in them.\n\nA screenshot taken on this Mac lands on your Desktop — connect that folder from Files and it gets the same treatment."
            }
            #endif
            return summary
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
                "Bluesky", "Nostr", "OpenSea", "Kalshi", "Shopify", "GeckoTerminal", "Deals",
                "Circle x402",
                "Open Food Facts", "Stocktwits", "Hugging Face", "npm", "PyPI"]
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
        Offer(name: "Photos",      tagline: "Screenshots, straight to your feed",            group: "Photos",    connectable: true,
              summary: "The screenshots you take flow into your feed, searchable by what's in them — no album to dig through."),
        Offer(name: "Calendar",    tagline: "Events join your things",               group: "Schedule",  connectable: true,
              summary: "Your events land alongside everything else — and Casberi can add one when you ask."),
        Offer(name: "Reminders",   tagline: "Lists stay in reach",                   group: "Schedule",  connectable: true,
              summary: "Your reminders join your things and stay findable, and Casberi can add one to your list when you ask."),
        Offer(name: "Wallet",      tagline: "Track any wallet's activity",          group: "Wallet",    connectable: true,
              summary: "Paste a wallet address — 0x…, an ENS name, or a .sol name — and its onchain activity lands in your feed like anything else.\n\nRead-only, public data, no server: watching an address can never trade or move funds.",
              features: [
                "Flags new token approvals, including through Permit2.",
                "Warns if the wallet starts delegating its control.",
                "Catches transfers that look like address-poisoning scams.",
                "Tracks what you've paid in gas.",
                // Aave/Morpho/Uniswap/Hyperliquid/Aerodrome each carry their
                // own tile since 2026-07-30, so naming them here would sell
                // the same thing twice. Spark has no tile of its own yet and
                // would otherwise go unmentioned anywhere — hence the one
                // name left in this bullet.
                "Shows your DeFi positions, Spark's included.",
              ],
              needsSetup: true),
        // Wallet group by ruling (user, 2026-07-21, prd §162). Privacy Pools
        // rides the watched wallets the Peer way: no account exists to
        // connect — deposits come from the person's own wallet, so the seat
        // is a switch over the watched list.
        Offer(name: "0xBow Privacy Pools", tagline: "Know when your deposit clears",       group: "Wallet",    connectable: true,
              summary: "Privacy Pools moves crypto privately, behind a compliance screen. Connect and your deposits land in your feed.\n\nNo account, no key, read-only: nothing here deposits, withdraws, or moves funds.",
              features: ["Says the moment a deposit clears, or is declined",
                         "Read from Ethereum's public chain and 0xBow's public API",
                         "For the wallets you already watch"],
              needsSetup: true, added: day(2026, 7, 21)),
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
              summary: "Railgun is a shielded pool on Ethereum. Watch a wallet and its two public doors land in your feed — what you shielded in, and what came back out.\n\nNo account, no key. What happens inside the pool stays invisible, which is the point.",
              features: ["An unshield shows money arriving without guessing whose it was",
                         "A shield sent through Railgun's relayer leaves no public trace at all",
                         "Read from Ethereum's public chain — never the pool's inside"],
              needsSetup: true, added: day(2026, 8, 1)),
        // Wallet group by ruling (prd §222, 2026-07-26): a Gnosis Pay account
        // IS a Safe holding your own balance, so it belongs beside the wallets
        // whose total it joins — not Shopping, where Privacy.com's card
        // receipts live, because this is the account and not just the receipt.
        // Honesty note: the summary names BOTH ceilings plainly — no merchant
        // names (they never reach the chain) and no refunds (they settle off
        // it) — because the obvious expectation of a card feed is that it
        // reads like a statement, and this one can't.
        Offer(name: "Gnosis Pay",  tagline: "Card spending, straight off the chain", group: "Wallet",    connectable: true,
              summary: "A Visa card that settles onchain: every purchase moves stablecoin out of your own Safe in real time. Watch that wallet and each one lands in your feed.\n\nNo account, no key.",
              features: ["What you spent and when, with a link to the transaction",
                         "The merchant's name never reaches the chain, so rows don't say where you were",
                         "Refunds settle off-chain — this is what you spent, not a statement",
                         "Read from Gnosis Chain for the wallets you already watch"],
              needsSetup: true, added: day(2026, 7, 26)),
        // Apple Wallet (prd §313, 2026-08-06) — FinanceKit, granted by Apple
        // for this bundle id on request QVDBMBPMJU. Wallet group beside Gnosis
        // Pay for that seat's own reason: a card feed belongs with the cards.
        // The summary's third paragraph is the entitlement's terms in plain
        // words and is NOT ordinary marketing copy — see AppleWalletScreen.
        // The last line names the two ceilings so the copy can never drift
        // past them: US-only, and pending charges aren't a statement.
        Offer(name: "Apple Wallet", tagline: "What your card actually spends",  group: "Wallet",    connectable: true,
              summary: "Apple Card, Apple Cash and Savings, read on your \(DS.device). Every purchase lands with the merchant's real name.\n\nRead-only, on device, never uploaded or sold. United States only.",
              features: ["The room leads with who you pay most",
                         "Speaks up when a subscription's price rises, or quietly stops",
                         "Disconnect and everything it brought in is deleted"],
              needsSetup: true, added: day(2026, 8, 6)),
        // Wallet group by ruling (user, 2026-07-21): the balances MERGE into
        // the combined portfolio, so an exchange belongs beside the wallets
        // whose total it joins — not in Markets, which is where things you
        // watch rather than own live.
        Offer(name: "Coinbase",    tagline: "Your exchange balance, in your total",  group: "Wallet",    connectable: true,
              summary: "Your Coinbase balances join your watched wallets in one combined total and one map.\n\nTakes a view-only key — Casberi checks what it can do before storing it, and refuses anything that can trade or move money.",
              needsSetup: true, added: day(2026, 7, 21)),
        Offer(name: "Kraken",      tagline: "Your exchange balance, in your total",  group: "Wallet",    connectable: true,
              summary: "Your Kraken balances join your watched wallets in one combined total and one map.\n\nTakes a query-only key — Casberi checks what it can do before storing it, and refuses anything that can trade, withdraw, or manage withdrawal addresses.",
              needsSetup: true, added: day(2026, 7, 21)),
        Offer(name: "Binance",     tagline: "Your exchange balance, in your total",  group: "Wallet",    connectable: true,
              summary: "Your Binance balances join your watched wallets in one combined total and one map.\n\nTakes a read-only key — Casberi checks what it can do before storing it, and refuses anything that can trade or withdraw.",
              needsSetup: true, added: day(2026, 7, 27)),
        // "Gemini Exchange", not "Gemini" — the catalog already has an offer
        // named "Gemini" (the Google AI chat importer), an unrelated company
        // that happens to share the word. Named fully everywhere it's
        // user-facing (this tile, the venue's display name, the website) so
        // the two are never confused for one another.
        Offer(name: "Gemini Exchange", tagline: "Your exchange balance, in your total", group: "Wallet", connectable: true,
              summary: "Your Gemini balances join your watched wallets in one combined total and one map.\n\nTakes a key with Gemini's Auditor role — Casberi checks what it can do before storing it, and refuses anything that can trade or move funds.",
              needsSetup: true, added: day(2026, 7, 27)),
        // A validator can't be FOUND from a wallet address the way a Solana
        // stake account can (see EthValidatorWatch.swift) — the only free
        // path is asking for the index directly, which is why this is a
        // named watch-list like Tokens/Kalshi rather than something that
        // rides a watched wallet automatically.
        Offer(name: "ETH Validators", tagline: "Your validator balance, in your total", group: "Wallet", connectable: true,
              summary: "A validator's balance lives on the beacon chain, not in your wallet, so every ordinary wallet read misses it.\n\nWatch one by its index and its balance joins your combined total. Read-only: watching can never stake, exit, or move it.",
              features: ["Your staking client shows the index",
                         "Stays current every time you open the app",
                         "Keyless — a public beacon-chain read, no account"],
              needsSetup: true, added: day(2026, 7, 27)),
        Offer(name: "Gmail",       tagline: "Your inbox, findable",                  group: "Mail",      connectable: true,
              summary: "Your recent mail becomes findable things.\n\nConnects over IMAP with a Google app password — your real password is never shared, and it's read-only.\n\nNeeds 2-Step Verification on your Google account.",
              needsSetup: true),
        Offer(name: "iCloud Mail", tagline: "Your @icloud.com inbox, findable",      group: "Mail",      connectable: true,
              summary: "Your recent @icloud.com mail becomes findable things. Connects over IMAP with an app-specific password from appleid.apple.com — your real password is never shared, and it's read-only.",
              needsSetup: true),
        Offer(name: "ChatGPT",     tagline: "Import your chats, keep them findable", group: "Agent",     connectable: true,
              summary: "ChatGPT hands you your history as a download and nothing more — there's no live read to connect to.\n\nCasberi makes that file usable: every chat becomes searchable alongside everything else you keep. Re-import any time for what's new.",
              needsSetup: true),
        Offer(name: "Claude",      tagline: "Import your chats, keep them findable", group: "Agent",     connectable: true,
              summary: "Claude hands you your conversations as a download and nothing more — there's no live read to connect to.\n\nCasberi makes that file usable: every chat becomes searchable alongside everything else you keep. Re-import any time for what's new.",
              needsSetup: true),
        Offer(name: "Gemini",      tagline: "Import your chats, keep them findable", group: "Agent",     connectable: true,
              summary: "Gemini lets your history out through Google Takeout and no other way — a download, not a connection.\n\nCasberi makes that file usable: every prompt becomes searchable alongside everything else you keep. Re-import any time for what's new.",
              needsSetup: true),
        Offer(name: "Tokens",      tagline: "Track any token",                       group: "Markets",   connectable: true,
              summary: "Watch any token — paste its address or a link and its live price chart lands in your feed, drawn on \(DS.device). Public price data only; nothing about you leaves the device.",
              needsSetup: true),
        Offer(name: "Kalshi",      tagline: "Watch real-event odds",                 group: "Markets",   connectable: true,
              summary: "Every open market on Kalshi, the CFTC-regulated event exchange. Browse the whole book, follow what you want. Public odds, read-only — nothing here places a trade.",
              features: ["Browse every open market — by category, or by what closes soonest",
                         "Follow a question and its odds land in your feed",
                         "See where Polymarket's crowd prices the same question differently",
                         "No account, no key — public odds, read-only"],
              needsSetup: true),
        Offer(name: "Polymarket", tagline: "Watch any prediction market",           group: "Markets",   connectable: true,
              summary: "Every open market on Polymarket, the onchain prediction-market exchange. Browse the whole book, follow what you want. Public odds, read-only — nothing here places a trade.",
              features: ["Browse every open market — by category, or by what closes soonest",
                         "Follow a question and its odds land in your feed, with a real price curve",
                         "See where Kalshi's crowd prices the same question differently",
                         "No account, no wallet — public odds, read-only"],
              needsSetup: true, added: day(2026, 7, 28)),
        Offer(name: "Stocktwits",  tagline: "Watch any stock",                      group: "Markets",   connectable: true,
              summary: "Search a ticker and the takes traders post about it land in your feed, each wearing its author's own bullish or bearish call.\n\nNo account, no key, read-only: nothing here trades, and a watched ticker can never see your portfolio.",
              features: ["The stock's live price chart draws on \(DS.device)",
                         "From public market data — no brokerage, no holdings"],
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
        Offer(name: "Peer",        tagline: "Your Peer trades, as they settle",      group: "Wallet",    connectable: true,
              summary: "Peer trades settle onchain into your own wallet. Watch it and each fill lands as it settles — \"Bought 25 USDC with Venmo on Peer\".\n\nNo account, no key, read-only: nothing here ever starts a trade.",
              features: ["Which token, how much, and the payment app that paid for it",
                         "Peer's design keeps the Venmo or PayPal side off the chain, so Casberi never sees it either",
                         "Read from the public chain for the wallets you already watch"],
              needsSetup: true, added: day(2026, 7, 17)),
        // Wallet group, beside Peer/Privacy Pools/Gnosis Pay (2026-07-30): a
        // Safe multisig is your own account too, and the seat rides the
        // watched wallets the same way — no account, no key, watching is
        // consent (§207). Split from a generic Wallet feature into its own
        // tile once it grew a second detection path (a watched EOA that's a
        // SIGNER on a Safe, not just a directly-watched Safe address) and its
        // own alert class (owner/threshold/module changes) — too much to
        // fold into one bullet under Wallet's summary honestly.
        Offer(name: "Safe",        tagline: "Your Safe's signature queue, live",     group: "Wallet",    connectable: true,
              summary: "Watch a Safe — or just your own wallet, if it's one of the signers — and its pending signature queue lands in your feed.\n\nNo account, no key, read-only: signing always happens in your own Safe app.",
              features: ["Finds every Safe you're a signer on, not just the ones you watch",
                         "Says when yours is the signature still missing",
                         "Alerts on a new owner, a changed threshold, or a new module",
                         "Ethereum, Base, Arbitrum, Optimism, Polygon and Gnosis Chain"
              ],
              needsSetup: true, added: day(2026, 7, 30)),
        // The five DeFi protocols the wallet has been reading all along
        // (2026-07-30), seated in the catalog beside Peer/0xBow/Gnosis
        // Pay/Safe. NOT a new integration and NOT a new request: every one of
        // these sweeps already runs unconditionally for every watched wallet
        // inside `WalletIngest.refresh` — the seat gates nothing, it says the
        // protocol is part of this person's life. Which is why each is
        // EVIDENCE-gated (`WalletSeatEvidence`): the seat lights the day a
        // real position is seen, never merely because a wallet is watched.
        // Connect and Open both route to the wallet manager (the Gnosis Pay
        // rule, `BridgeRouter`) — there is no setting to set, and the live
        // book already has a home in the Wallet feed's own DeFi tiles, so a
        // screen here would only duplicate it.
        Offer(name: "Aave",        tagline: "Your lending position, watched",       group: "Wallet",    connectable: true,
              summary: "Aave is where a lot of onchain lending happens: collateral posted, borrowed against.\n\nWatch the wallet and your position lands with a warning while there's still time to act. Read-only: nothing supplies, borrows, repays, or withdraws.",
              features: ["Warns before a position gets close to liquidation",
                         "Ethereum, Base, Arbitrum, Optimism and Polygon",
                         "No account, no key — read from each chain's public RPC"
              ],
              needsSetup: true, added: day(2026, 7, 30)),
        Offer(name: "Morpho",      tagline: "Your markets and vaults, watched",     group: "Wallet",    connectable: true,
              summary: "Morpho is isolated markets and vaults rather than one pool — powerful, and easy to lose track of.\n\nWatch the wallet and every position lands with its health factor's trajectory. Read-only: nothing supplies, borrows, repays, or withdraws.",
              features: ["Warns when a position drifts close to liquidation, and which way it's trending",
                         "Tells you when a vault you're in materially reallocates",
                         "Notices when a vault's rate falls behind Aave's for the same asset"
              ],
              needsSetup: true, added: day(2026, 7, 30)),
        Offer(name: "Uniswap",     tagline: "Your liquidity, in or out of range",   group: "Wallet",    connectable: true,
              summary: "A concentrated-liquidity position stops earning the moment price leaves its range, and nothing tells you.\n\nWatch the wallet and yours land, V3 and V4 together. Read-only: nothing swaps, adds, removes, or collects.",
              features: ["Alerts both ways — out of range, and back in",
                         "Shows uncollected fees, and marks the milestones as they add up",
                         "Ethereum, Base, Arbitrum, Optimism and Polygon"
              ],
              needsSetup: true, added: day(2026, 7, 30)),
        Offer(name: "Hyperliquid", tagline: "Your positions, as they turn",         group: "Wallet",    connectable: true,
              summary: "Hyperliquid moves fast enough that a fill-by-fill feed would be noise — one measured wallet made 2,000 trades in three hours. So this watches what actually changes.\n\nNo account, no key, read-only: nothing here opens, closes, or adjusts a position.",
              features: ["Lands a position opening and closing — never the fills in between",
                         "Warns when a position drifts close to liquidation",
                         "Counts down your staked HYPE's unlock",
                         "Sub-accounts included"
              ],
              needsSetup: true, added: day(2026, 7, 30)),
        Offer(name: "Aerodrome",   tagline: "Never miss the weekly vote",           group: "Wallet",    connectable: true,
              summary: "A veAERO lock earns by voting every week, in a window that closes whether you remembered or not. Watch the wallet and that deadline lands as a real date.\n\nNo account, no key, read-only: nothing here votes, locks, or claims.",
              features: ["Reminds you before the weekly vote window closes — read live",
                         "Counts down a lock's expiry, and stays quiet about permanent locks",
                         "Shows how much of a decaying lock's voting power is left"
              ],
              needsSetup: true, added: day(2026, 7, 30)),
        Offer(name: "ether.fi",    tagline: "Your staked ETH, and the card",     group: "Wallet",    connectable: true,
              summary: "Unstaking hands you a claim ticket that queues about ten days, then waits silently. ether.fi Cash is the other half: a Visa card that settles onchain.\n\nWatch the wallet and both land. Read-only: claiming and spending happen in ether.fi's own app.",
              features: ["Tells you the moment your ETH is actually claimable",
                         "Shows what's still queued",
                         "Lands each card purchase, and says when one went on credit",
                         "Warns when the credit line drifts close to its limit",
                         "Amounts and timing only — the merchant never reaches the chain"
              ],
              needsSetup: true, added: day(2026, 7, 31)),
        Offer(name: "GeckoTerminal", tagline: "Trending tokens, per chain",          group: "Markets",   connectable: true,
              summary: "Pick the chains you care about and the tokens trending on each land in your feed as links.\n\nNo account, no key. Read-only public price data — nothing here buys, sells, or trades.",
              features: ["GeckoTerminal's own ranking, by 24-hour volume and price move",
                         "Each row opens to its live on-device chart",
                         "Fetched straight from the public API by \(DS.device)"],
              needsSetup: true),
        Offer(name: "Circle x402", tagline: "The APIs that sell to agents",          group: "Markets",   connectable: true,
              summary: "The companies selling APIs to AI agents land in your feed — each with what it sells and what a call costs.\n\nFetched straight from Circle's public directory: no account, no key. Read-only — Casberi never pays for a call.",
              needsSetup: true, added: day(2026, 8, 6)),
        Offer(name: "OpenSea",     tagline: "New NFT drops in your feed",            group: "NFTs",      connectable: true,
              summary: "Watch the chains you care about and their newest NFT collections land in your feed as links — the ones with real artwork, not the empty test contracts. Fetched straight from OpenSea's public API, read-only: nothing here buys, sells, or bids.",
              needsSetup: true),
        // Shopping, not Markets (2026-07-17): Bitrefill is your own commerce
        // account — orders and receipts — not a market you watch.
        Offer(name: "Bitrefill",   tagline: "Your gift cards, in reach",             group: "Shopping",  connectable: true,
              summary: "What you buy on Bitrefill lands in your feed — gift cards wearing their own artwork, phone top-ups, eSIMs, balance refills.\n\nRead-only by conduct: nothing here ever buys, pays, or spends your balance.",
              features: ["Your balance sits at the top of the Bitrefill feed",
                         "An API key from Bitrefill's developer settings, kept in \(DS.device)'s Keychain"],
              needsSetup: true, added: day(2026, 7, 17)),
        // Shopping, beside Bitrefill: Privacy.com is your own card-spending
        // record — receipts across every merchant — not a market you watch.
        // Honesty note (2026-07-22): Privacy's key is NOT scoped read-only, so
        // the summary says plainly that the read-only promise is kept by
        // conduct, not by the credential (unlike every other keyed bridge).
        Offer(name: "Privacy",     tagline: "Your card purchases, in reach",         group: "Shopping",  connectable: true,
              summary: "What you buy with your Privacy.com virtual cards lands in your feed, findable next to everything else.\n\nPrivacy's key can't be scoped read-only. Casberi only reads transactions — it never creates, closes, or funds a card.",
              features: ["Each purchase with its merchant and amount",
                         "An API key from your Privacy account, kept in \(DS.device)'s Keychain",
                         "Needs a paid Privacy plan"],
              needsSetup: true, added: day(2026, 7, 22)),
        Offer(name: "Shopify",     tagline: "Follow any store's new drops",          group: "Shopping",  connectable: true,
              summary: "Follow any Shopify store — paste its web address and its newest products, restocks and sale prices land in your feed.\n\nNo account, no sign-in, read-only: nothing here checks out or pays.",
              features: ["Fetched straight from the store's public catalog by \(DS.device)",
                         "Some big stores block automated reads — it says so when one does"],
              needsSetup: true),
        Offer(name: "Deals",       tagline: "The best deals, as they drop",          group: "Shopping",  connectable: true,
              summary: "Follow the deal aggregators — Slickdeals, DealNews — and their newest deals land in your feed as products, each already priced in the headline. Fetched straight from each source's public feed by \(DS.device): no account, read-only — nothing here buys anything.",
              needsSetup: true),
        Offer(name: "Open Food Facts", tagline: "Scan a grocery barcode",           group: "Shopping",  connectable: true,
              summary: "Scan a grocery barcode and the product lands in your feed — its name, picture and Nutri-Score.\n\nKeyless and free. Nothing about you leaves \(DS.device) but the barcode.",
              needsSetup: true),
        Offer(name: "Venice",      tagline: "Private answers with your key",         group: "Agent",     connectable: true,
              summary: "Venice keeps chats on your own device by design, so there's nothing to read in — instead, your Venice key powers \"Try with your key\": any answer re-runs on Venice's private API, straight from \(DS.device), only when you tap.",
              needsSetup: true),
        Offer(name: "Bankr",       tagline: "Answers that know your wallet",        group: "Agent",     connectable: true,
              summary: "Bankr is an agent with a wallet, so its answers can weigh what you hold and what the market is doing — not just what you saved.\n\nMake it a read-only key: every question says answer only, and nothing here trades, sends, or swaps.",
              features: ["Powers \"Try with your key\" — any answer re-runs on Bankr",
                         "Straight from \(DS.device), only when you tap"],
              needsSetup: true),
        // 1Claw is the agents' vault (2026-07-17, prd 111): grants, not
        // secrets — the feed answers "what can this key reach", never what
        // a secret's value is.
        Offer(name: "1Claw",       tagline: "What your agent's key can reach",       group: "Agent",     connectable: true,
              summary: "1Claw is a vault that holds your AI agents' secrets behind human-granted permissions.\n\nPaste an agent's key and its actual reach lands in your feed. Names and permissions only: nothing here ever reads a secret's value, signs, or spends.",
              features: ["Every vault the key can see",
                         "Each grant's secret paths and permissions",
                         "Read straight from \(DS.device), from 1Claw's own records"],
              needsSetup: true, added: day(2026, 7, 17)),
        // OpenRouter (2026-07-24): a sixth agent key, one API routed across
        // 400+ models. It never pins one model — it rides OpenRouter's own
        // `openrouter/auto` router, so the answer's capabilities stay
        // honestly text-only/no-search rather than claiming whatever the
        // picked model might not have.
        Offer(name: "OpenRouter",  tagline: "One key, whichever model fits",         group: "Agent",     connectable: true,
              summary: "OpenRouter routes your question to whichever of its 400+ models fits, so your OpenRouter key powers \"Try with your key\" without pinning one model. Any answer re-runs straight from \(DS.device), only when you tap.",
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
        Offer(name: "Grok",        tagline: "Try with your key, on Grok",            group: "Agent",     connectable: true,
              summary: "Grok's key powers \"Try with your key\" like every agent here — any answer re-runs on Grok, straight from \(DS.device), only when you tap.\n\nNeeds credits on your xAI team — there's no free tier, and a key without them can't answer.",
              needsSetup: true, added: day(2026, 7, 31)),
        Offer(name: "GitHub",      tagline: "Stars, releases, issues — your GitHub", group: "Work",      connectable: true,
              summary: "Pick the feeds you want — starred repos, new releases, gists, your contributions, watched repos, and the issues and pull requests that involve you. Connects with a read-only token you make in GitHub settings — it stays in \(DS.device)'s Keychain.",
              needsSetup: true),
        // Work, not Agent (2026-08-03): the Agent group is BYO-key seats that
        // answer a question. This one publishes nothing and answers nothing —
        // it's a release feed for the hub AI ships on, which is the GitHub
        // seat's job three rows up, so it sits beside it.
        Offer(name: "Hugging Face", tagline: "What the AI world just shipped",       group: "Work",      connectable: true,
              summary: "Watch an org or a person — meta-llama, google, anyone — and their new models, datasets and Spaces land as links.\n\nNo account and no key. Read-only: it never publishes, stars, or downloads weights.",
              features: ["New models, datasets and Spaces from anyone you watch",
                         "Daily Papers land with their abstracts, searchable months later",
                         "Only what's NEW — downloads and likes are counts, not news"],
              needsSetup: true, added: day(2026, 8, 3)),
        Offer(name: "Linear",      tagline: "Your issues stay in reach",             group: "Work",      connectable: true,
              summary: "The issues assigned to you join your things and surface when they matter. Connects with a personal API key from Linear settings — it stays in \(DS.device)'s Keychain.",
              needsSetup: true),
        Offer(name: "Notion",      tagline: "Pages join your things",                group: "Work",      connectable: true,
              summary: "The pages you connect become findable things, so what you wrote isn't stranded in one more app.\n\nPages only.\n\nConnects with an integration token from notion.so — it stays in \(DS.device)'s Keychain.",
              needsSetup: true),
        Offer(name: "PostHog",     tagline: "The numbers behind what you ship",      group: "Work",      connectable: true,
              summary: "Name a metric and its curve draws in your feed, on \(DS.device).\n\nA personal API key you mint read-only: it can query and read, and cannot ship a flag, edit a dashboard, or write anything back.",
              features: ["Watch any event — its seven-day curve is its mark",
                         "Your PostHog annotations land as things",
                         "A milestone lands once — never a weekly tally",
                         "A metric that stops firing tells you it stopped",
                         "Aggregates only — never an individual's profile"],
              needsSetup: true, added: day(2026, 7, 27)),
        Offer(name: "Slack",       tagline: "Never miss a mention",                  group: "Work",      connectable: true,
              summary: "Anyone who @-mentions you across Slack lands in your feed, on \(DS.device).\n\nSign in with Slack — no password, no token. Search only: Casberi looks up your mentions and nothing else.",
              needsSetup: true, added: day(2026, 7, 28)),
        Offer(name: "Trello",      tagline: "The cards you're carrying",             group: "Work",      connectable: true,
              summary: "The cards assigned to you land in your feed with their board, their due date, and the notes on the back.\n\nCasberi asks Trello for a read-only token: it cannot move a card, comment, or write anything back.",
              features: ["Cards arrive named by the board they came from",
                         "Due dates ride along, so a card can be overdue",
                         "A card you finish elsewhere closes here",
                         "Read-only by construction — never a write"],
              needsSetup: true, added: day(2026, 8, 3)),
        Offer(name: "Cloudflare",  tagline: "The dates behind the sites you run",    group: "Work",      connectable: true,
              summary: "The dates something you run stops working land in your feed before they bite.\n\nA read-only token: no analytics, nothing about your visitors, and it can't change a record or purge cache.",
              features: ["A DNS record changes — with what it used to point at",
                         "A certificate that hasn't renewed, before the browser warning",
                         "Domains coming up for renewal, auto-renew or not",
                         "A zone sitting at pending instead of serving",
                         "The token warns you before it expires itself"],
              needsSetup: true, added: day(2026, 8, 3)),
        Offer(name: "Sentry",      tagline: "The errors your users really hit",     group: "Work",      connectable: true,
              summary: "A new error, or one you'd closed coming back — with the project it broke and where in your code it happened.\n\nA read-only token, and never an event, a stack trace, or anything about the person who hit it.",
              features: ["A regression tells you what came back",
                         "New issues land named by the project",
                         "Counts never land — a tally isn't news",
                         "Cannot resolve an issue, comment, or change a project"],
              needsSetup: true, added: day(2026, 8, 4)),
        Offer(name: "Vercel",      tagline: "What shipped, and what broke",         group: "Work",      connectable: true,
              summary: "Every production deploy lands as it goes live, and every failed build lands whatever branch it was on.\n\nVercel has no read-only token. Casberi only lists deployments, and never reads your environment variables.",
              features: ["Production deploys, with the commit that shipped",
                         "Failed builds, on any branch",
                         "One tap to the live site, or to the build log",
                         "Successful previews are skipped — that's your git log, not news",
                         "Never deploys, promotes, rolls back, or cancels"],
              needsSetup: true, added: day(2026, 8, 4)),
        Offer(name: "PagerDuty",   tagline: "What caught fire, and for how long",   group: "Work",      connectable: true,
              summary: "An incident lands when it fires, and again when it's resolved — carrying how long it actually lasted.\n\nA read-only key: it cannot page anyone, acknowledge, resolve, or reassign.",
              features: ["Incidents land named by the service that broke",
                         "A resolution says how long it took — the record you want three weeks later",
                         "Urgency rides along, so you can tell 3am from 3pm",
                         "Read-only — it can never page your team"],
              needsSetup: true, added: day(2026, 8, 4)),
        Offer(name: "npm",         tagline: "Your dependencies, when they ship",    group: "Work",      connectable: true,
              summary: "Name the packages you depend on and their releases land in your feed, stamped with when they actually shipped.\n\nNo account and no key: read straight from the public registry by \(DS.device).",
              features: ["A new version lands the day it's published",
                         "A deprecation lands with what to use instead — that week, not six months later",
                         "Download counts never land — a tally isn't news",
                         "Scoped packages work — @vercel/og and friends"],
              needsSetup: true, added: day(2026, 8, 4)),
        Offer(name: "PyPI",        tagline: "Your Python packages, on release",     group: "Work",      connectable: true,
              summary: "Name the packages you depend on and their releases land in your feed, stamped with when they actually shipped.\n\nNo account and no key: read straight from the public index by \(DS.device).",
              features: ["A new version lands the day it's published",
                         "Download counts never land — a tally isn't news",
                         "Read-only — it never installs or publishes"],
              needsSetup: true, added: day(2026, 8, 4)),
        Offer(name: "Cursor",      tagline: "What your coding agents did",          group: "Agent",     connectable: true,
              summary: "The cloud agents you launch in Cursor land here once they finish.\n\nCursor's key can't be scoped read-only. Casberi only ever lists them.",
              features: ["Finished runs, named by the repo they ran on",
                         "The agent's own account of what it changed",
                         "One tap to the pull request it opened",
                         "A run that failed or expired says which",
                         "Only ever reads — it can't start an agent"],
              needsSetup: true, added: day(2026, 8, 4)),
        Offer(name: "App Store Connect", tagline: "How your app is doing",           group: "Work",      connectable: true,
              summary: "What Apple does to your apps lands in your feed: a version rejected or approved, a customer review, a build about to expire.\n\nApple has no read-only role. Casberi only reads — never submits, releases, or replies.",
              features: ["A review verdict lands the moment it changes",
                         "Customer reviews arrive with what people wrote",
                         "A TestFlight build warns you before it expires",
                         "Downloads and proceeds never land — a tally isn't news",
                         "Only ever reads — it can't ship anything"],
              needsSetup: true, added: day(2026, 8, 6)),
        Offer(name: "Stripe",      tagline: "What your money did today",             group: "Work",      connectable: true,
              summary: "The five things that happen to money, landing in your feed as they happen — disputes opened and closed, payouts, canceled subscriptions, failed payments.\n\nConnects with a restricted key you mint read-only: it cannot refund, charge, or pay out. Test-mode keys are refused.",
              features: ["A dispute lands with its evidence deadline",
                         "Payouts, so you know when money really arrived",
                         "A canceled subscription tells you it canceled",
                         "Failed payments, with Stripe's own retry date",
                         "Never an individual charge — and never a customer's details"],
              needsSetup: true, added: day(2026, 7, 31)),
        Offer(name: "Reddit",      tagline: "Follow subreddits and people",          group: "Saves",     connectable: true,
              summary: "Follow any subreddit or person on Reddit — their new posts land in your feed as links, through Reddit's own public feed.\n\nNo account, no sign-in.\n\nRead-only.",
              needsSetup: true),
        Offer(name: "YouTube",     tagline: "Follow any channel",                    group: "Watching",  connectable: true,
              summary: "Follow any YouTube channel — its new uploads land in your feed as links, through YouTube's own public feed. Paste the channel's @handle or URL.\n\nNo account.\n\nRead-only.",
              needsSetup: true),
        Offer(name: "Apple Music", tagline: "What you play stays in reach",          group: "Listening", connectable: true,
              summary: "What you've recently played lands in your feed, opening back in Apple Music.\n\nUses Apple's own MusicKit with your permission — read-only, nothing added to your library.\n\nEverything stays on \(DS.device)."),
        Offer(name: "Spotify",     tagline: "Liked songs join your things",          group: "Listening", connectable: true,
              summary: "Your liked songs become things you can find and revisit alongside everything else. Connects with Spotify's own sign-in — PKCE, entirely on \(DS.device), no server holds a secret.",
              needsSetup: true),
        Offer(name: "Apple Health", tagline: "Workouts land in your feed",           group: "Fitness",   connectable: true,
              summary: "Your workouts join your things — a run shows up next to the plan that inspired it. Everything stays on \(DS.device): HealthKit never touches a server.",
              unavailableOnMac: true),
        Offer(name: "Strava",      tagline: "Every activity, one record",            group: "Fitness",   connectable: true,
              summary: "Rides and runs land in your feed with distance and time — read from Apple Health, where Strava saves them. Turn on Strava's Health sync and everything stays on \(DS.device); no Strava account is asked for.",
              unavailableOnMac: true),
        Offer(name: "Cal.com",     tagline: "Bookings land in your feed",            group: "Schedule",  connectable: true,
              summary: "The meetings people book with you join your things as events, next to your calendar. Connects with an API key from Cal.com settings — it stays in \(DS.device)'s Keychain.",
              needsSetup: true),
        Offer(name: "Calendly",    tagline: "Meetings join your things",             group: "Schedule",  connectable: true,
              summary: "Your scheduled meetings land as events beside everything else. Connects with a personal access token from Calendly's integrations page — it stays in \(DS.device)'s Keychain.",
              needsSetup: true),
        Offer(name: "Todoist",     tagline: "Tasks beside your lists",               group: "Schedule",  connectable: true,
              summary: "Your open tasks join your things alongside Reminders. Connects with the API token from Todoist settings — it stays in \(DS.device)'s Keychain.",
              needsSetup: true),
        Offer(name: "Pinterest",   tagline: "Your pins, in your feed",               group: "Images",    connectable: true,
              summary: "Your recent public pins land in your feed as links — what you saved on Pinterest joins everything else.\n\nConnects with just your username through Pinterest's own public feed: no password, nothing stored but the name.\n\nPublic boards only.",
              needsSetup: true),
        Offer(name: "Raindrop",    tagline: "Bookmarks become findable",             group: "Saves",     connectable: true,
              summary: "Your Raindrop bookmarks join your things, searchable next to everything else you saved. Connects with a token from Raindrop settings — it stays in \(DS.device)'s Keychain.",
              needsSetup: true),
        Offer(name: "Readwise",    tagline: "Highlights stay with you",              group: "Reading",   connectable: true,
              summary: "Your highlights land in your feed — what you read joins what you do. Connects with your Readwise access token — it stays in \(DS.device)'s Keychain.",
              needsSetup: true),
        Offer(name: "Apple Journal", tagline: "Your entries, findable",              group: "Notes",     connectable: true,
              summary: "Apple offers no live read of Journal — its own export is the only door.\n\nBring the unzipped folder here and every entry becomes a findable note, dated as you wrote it. Photos stay in the export for now.\n\nRe-imports add only what's new.",
              needsSetup: true),
        Offer(name: "Day One",     tagline: "Import your journal",                   group: "Notes",     connectable: true,
              summary: "Day One keeps your journal to itself — the export is the only way out.\n\nBring the JSON here and every entry becomes a findable note, dated as you wrote it, tags kept. Photos stay in the export for now.\n\nRe-imports add only what's new.",
              needsSetup: true),
        Offer(name: "Apple Notes", tagline: "Share notes in",                        group: "Notes",     connectable: true,
              summary: "Share any note straight into Casberi — open it in Notes, tap share, choose Casberi. Apple offers no export or live read for Notes, so they arrive one at a time, as you share them.",
              needsSetup: true),
        Offer(name: "RSS",         tagline: "Any site with a feed",                  group: "Reading",   connectable: true,
              summary: "Follow any site that publishes a feed — new posts land in your feed as links, fetched by \(DS.device) directly. No account, no algorithm in between.",
              needsSetup: true),
        // Social, with Bluesky (user ruling 2026-07-17, reversing the
        // 2026-07-14 "onchain network" shelving): Farcaster is a social account
        // first — it browses beside Bluesky, and its detail eyebrow says so.
        Offer(name: "Farcaster",   tagline: "Track any Farcaster account",           group: "Network",   connectable: true,
              summary: "An open social protocol — casts are public, so this connects with just a username: your own or anyone's, plus /channels by name. An account's likes and mentions can land too.\n\nNo password, nothing stored but the name.",
              needsSetup: true),
        Offer(name: "Bluesky",     tagline: "Track any Bluesky account",             group: "Network",   connectable: true,
              summary: "Built on an open protocol — posts are public, so this connects with just a handle: your own or anyone's, and mentions of them can land too.\n\nNo password, nothing stored but the name.\n\nLikes arrive with sign-in, later.",
              needsSetup: true),
        // Network, beside Farcaster/Bluesky (2026-07-27): a third open,
        // keyless protocol — public relays serve reads with no account and
        // no key. Connects by npub, raw hex pubkey, or a NIP-05 identifier
        // ("name@domain.com") instead of a username, since Nostr has no
        // global directory to search.
        Offer(name: "Nostr",       tagline: "Track any Nostr account",               group: "Network",   connectable: true,
              summary: "Notes on Nostr are public, so this connects with an npub, a raw pubkey, or a name@domain identifier — your own or anyone's.\n\nNo password, nothing stored but the identity. Read from whichever public relays answer.",
              features: ["#hashtags by name, too",
                         "An account's reactions and mentions can land"],
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
              summary: "Instagram only lets you export your account — a folder you'll never open again. Casberi lets you actually use it.\n\nMeta leaves other people's captions out, so a saved post lands named for who made it.",
              features: ["Your captions and comments, as searchable text",
                         "Saves and likes, named and openable",
                         "One-time import — re-importing adds only what's new",
                         "Read on \(DS.device); nothing is sent to Meta"],
              needsSetup: true, added: day(2026, 7, 31)),
        // The second import-grade social seat, beside Instagram (2026-07-31, prd
        // §246). Snapchat has no keyless read either — and less than no read:
        // Login Kit's entire scope list is a display name, a Bitmoji avatar
        // and a user id, so a connect-by-name seat could only ever say
        // "connected" and land nothing. The export is the one door, and the
        // copy names what the export honestly holds.
        Offer(name: "Snapchat",    tagline: "Import your saved chats and memories",  group: "Network",   connectable: true,
              summary: "Snapchat only lets you export your account — and the pictures inside die after 7 days. Casberi keeps them for good.\n\nOnly saved chats are in there; Snapchat deletes the rest on view.",
              features: ["Memories dated as you took them, with their pictures fetched",
                         "Saved conversations, searchable beside everything else",
                         "Re-importing keeps a conversation up to date",
                         "Read on \(DS.device) — the export is a file you already have"],
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
              summary: "TikTok's download link dies four days after you ask for it. Import once and what was in it is yours for good.\n\nThe export is only links, so naming them is a second tap.",
              features: ["Saved and liked videos, named and openable",
                         "Your own captions and comments, as searchable text",
                         "Re-importing adds only what's new",
                         "No account and no key — the export is a file you already have"],
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
              summary: "X charges per post read now, so the free archive is the whole door. Casberi opens it.\n\nBookmarks aren't in X's archive — they never have been — so those can't come.",
              features: ["Your posts and replies, as searchable text",
                         "Your likes, carrying the post's own words",
                         "One-time import — re-importing adds only what's new",
                         "Read on \(DS.device); no account, no key, nothing sent to X"],
              needsSetup: true, added: day(2026, 8, 2)),
        Offer(name: "Steam",       tagline: "What you play, in your feed",           group: "Games",     connectable: true,
              summary: "Recently played games land in your feed, linking to their store pages.\n\nConnects with a free Steam Web API key and your public profile name — the key stays in \(DS.device)'s Keychain.\n\nRead-only.",
              needsSetup: true),
        Offer(name: "Obsidian",    tagline: "Your vault, beside your things",        group: "Notes",     connectable: true,
              summary: "Point at your vault folder and your notes land as things — findable next to everything else. Fully local: the vault is read in place, never modified, and nothing leaves \(DS.device).",
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
              summary: "Point at any folder and what's inside lands in your feed, findable next to everything else. Fully local: the folder is read in place, never modified, and nothing leaves \(DS.device).",
              needsSetup: true, added: day(2026, 7, 27)),
        // Storage, beside Files (2026-07-27): the same "point at a folder"
        // idea, reading Dropbox's own API instead of a local bookmark — so it
        // works without the Dropbox app installed, and Dropbox's own delta
        // cursor makes a delete arrive as news instead of something a re-walk
        // has to infer. Scoped to the folder you name ONLY — never a shared
        // link, never "shared with me" — the reasoning the user gave for
        // building this at all: a stranger sharing something with you can
        // never make it appear here.
        Offer(name: "Dropbox",     tagline: "Your Dropbox, without the notifications", group: "Storage", connectable: true,
              summary: "Name a folder and what's inside lands in your feed, synced with Dropbox's own change feed — so deletes arrive too.\n\nRead-only: Casberi can't write to your Dropbox.",
              features: ["Never shared links, never \u{201c}shared with me\u{201d} — only the folder you name"],
              needsSetup: true, added: day(2026, 7, 27)),
        Offer(name: "Twitch",      tagline: "Live follows land in your feed",        group: "Watching",  connectable: true,
              summary: "When a channel you follow goes live, the stream lands in your feed as a link — catch it while it's on. Sign-in happens on Twitch's own page with a short code; read-only, no password in the app.",
              needsSetup: true),
        Offer(name: "Substack",    tagline: "Follow any publication",                group: "Reading",   connectable: true,
              summary: "Follow any Substack — new posts land in your feed as links, fetched straight from the publication's own feed. Paste its URL or name.\n\nNo account.\n\nRead-only.",
              needsSetup: true),
        Offer(name: "Kindle",      tagline: "Import your highlights",                group: "Reading",   connectable: true,
              summary: "Amazon offers no live read of your highlights — but your Kindle writes them to a My Clippings.txt itself.\n\nPlug it in, bring that file here, and every passage you marked becomes a findable note, grouped by book.",
              features: ["Grouped by book, findable next to everything else",
                         "No account — re-imports add only what's new"],
              needsSetup: true),
        // Reading group, beside Kindle (2026-07-28, prd §224, corrected same
        // day from an initial Notes placement) — both are import-only, no
        // live read. Safari has no bookmarks API at all, and Chrome's own
        // export never includes its separate Reading List store. Both
        // browsers write the SAME file format though (Netscape Bookmark File
        // Format), so one offer, one parser, one screen covers both —
        // Safari's Reading List rides along as a folder inside that same
        // file, for free.
        Offer(name: "Bookmarks",   tagline: "Import your bookmarks",                 group: "Reading",   connectable: true,
              summary: "Your bookmarks live inside your browser, which hands them over only as a file.\n\nExport from Safari or Chrome, bring it here, and they become findable links with folders kept as tags.",
              features: ["Safari's Reading List rides along as its own folder",
                         "Re-imports add only what's new"],
              needsSetup: true, added: day(2026, 7, 28)),
        Offer(name: "Podcasts",    tagline: "Follow any show",                       group: "Listening", connectable: true,
              summary: "Follow any podcast — new episodes land in your feed as links. Search for a show and pick it; episodes arrive through the show's own public feed.\n\nNo account.\n\nRead-only.",
              needsSetup: true),
        Offer(name: "Contacts",    tagline: "The people you know, findable",         group: "People",    connectable: true,
              summary: "Your contacts become findable people — a name you're looking for turns up with everything it connects to. Search-only: they never crowd your feed.\n\nEverything stays on \(DS.device) — Contacts never touches a server.\n\nRead-only."),
        Offer(name: "HomeKit",     tagline: "Your home's accessories, at a glance",  group: "Home",      connectable: true,
              summary: "Your HomeKit accessories — locks, doors, sensors — land as things you can find, kept current while the app is open.\n\nSearch-only: they never crowd your feed.\n\nRead-only — Casberi never controls anything.",
              unavailableOnMac: true),
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
        // and settle after Shopping.
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
        //   • Social keeps a mid slot and stays ADJACENT TO MAIL, the pairing
        //     the wall's band layout was ruled around.
        // Mail (2 seats) is the only small category in the catalog, so it has
        // no small neighbour to pair with in ANY order and draws a 2-tile band
        // wherever it sits — the same as before this move. Nothing else here
        // changes shape: every other band is ≥4 seats and full-width.
        //
        // Ordering only — no seat changed category, so `category:<name>`
        // kept-asks, `category(of:)`/`category(forSource:)` and the
        // `SourcesTray` join are all untouched.
        ("Wallet",  "Wallet",      ["Wallet"]),
        ("Work",    "GitHub",      ["Work"]),
        // Life absorbs Home (user ruling 2026-07-23): HomeKit was the lone app
        // in its own category, and a one-app band wastes a whole 4-wide row —
        // "one option would be we could put HomeKit in Life." "People"
        // (Contacts) already lives here (2026-07-20). Storage joins for the
        // same reason (user ruling 2026-07-27): Files' folder contents are
        // unpredictable, so it reads as personal-life miscellany, not a
        // dedicated content type.
        ("Life",    "Photos",      ["Photos", "Schedule", "Fitness", "People", "Home", "Storage"]),
        ("Agents",  "Claude",      ["Agent"]),
        ("Media",   "Spotify",     ["Watching", "Listening", "Games", "Images"]),
        ("Social",  "Bluesky",     ["Network"]),
        ("Mail",    "Gmail",       ["Mail"]),
        // Reading sits AHEAD of Shopping (user ruling 2026-08-06, "should
        // reading come before shopping?"). Two reasons, both about the band
        // rather than the taste: Reading is 7 seats to Shopping's 5, and every
        // one of them is a live connect that fills the feed with something to
        // READ (RSS, Substack, Reddit, Readwise, Raindrop, Kindle, Bookmarks)
        // — the app's own core loop. Shopping is the narrowest band in the
        // catalog: Privacy needs a paid plan, Open Food Facts is a barcode
        // scanner rather than a feed, Bitrefill is crypto gift cards.
        ("Reading", "Readwise",    ["Reading", "Saves"]),
        ("Shopping", "Shopify",    ["Shopping"]),
        ("Markets", "Kalshi",      ["Markets", "NFTs"]),
        ("Notes",   "Apple Notes", ["Notes"]),
    ]

    static func category(of offer: Offer) -> String {
        categories.first { $0.groups.contains(offer.group) }?.name ?? "Life"
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
        offer(forSource: source).map(category(of:))
    }

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
    static func offer(forSource source: String) -> Offer? {
        if let exact = allOffers.first(where: { $0.name == source }) { return exact }
        return allOffers.first(where: { $0.name.hasSuffix(" " + source) })
    }

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
