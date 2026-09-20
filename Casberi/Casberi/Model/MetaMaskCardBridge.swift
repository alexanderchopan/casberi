import Foundation
import SwiftData

/// MetaMask Card — the Mastercard whose spending settles ONCHAIN (2026-09-20).
/// A cardholder grants an allowance to Baanx's "foxConnect" spender; every
/// purchase is that spender calling `transferFrom`, moving a stablecoin from
/// the person's own wallet to one settlement address. That transfer is public,
/// so the seat RIDES the watched wallets exactly like Gnosis Pay and ether.fi
/// Cash: no account, no key, no connect switch — watching the wallet is the
/// consent.
///
/// TWO CHAINS, and the second one is why `Chain` exists. Linea and Base run
/// the same card and answer nothing alike: Linea's best host serves 10,000
/// blocks a request, Base's serves 2,000, and a Base block is 2.0s against
/// Linea's 8.8s — so one Linea request buys a day of history and one Base
/// request buys an hour. Treating them as one chain with one window would
/// either cost 130 requests per wallet or silently read six hours and call it
/// six days. **Monad is read through Alchemy's index instead** (prd §860):
/// its public RPCs cap a log read at 100 blocks of 0.302s, which no phone can
/// walk, but an indexer has already walked it — see `monad`.
///
/// This is the THIRD seat on the same shape, and the shape is the reason it is
/// buildable at all: `GnosisPayBridge` proved the pattern, `EtherFiCash`
/// proved it generalised, and everything below that differs from them differs
/// because Linea measured differently, not because it was written fresh.
///
/// Honesty boundaries — the copy must not overreach:
/// - CAPTURE ONLY. Nothing here spends, tops up, freezes a card, changes a
///   spending cap, or signs.
/// - NO MERCHANT NAMES. The merchant, MCC category, fees, the card's last four
///   and the pending/declined/reversed status live only behind Baanx's
///   authenticated API (`GET /v1/card/transactions`, OAuth + PKCE against
///   MetaMask's own client id). The chain carries the amount, the token and
///   the moment, and nothing else. Rows say what was spent, never where.
/// - NO REFUNDS. A refund is a credit on Baanx's books; nothing measured here
///   settles back out of the settlement address to a cardholder. This is a
///   record of card SPENDS, not a balanced ledger.
///
/// The API path was deliberately NOT built, and for a sharper reason than
/// Gnosis Pay's. Gnosis Pay's API wanted a SIWE signature, which prd §112
/// forbids in-app; Baanx's wants MetaMask's own OAuth client id. Reaching it
/// would mean this app presenting itself as MetaMask to Baanx — which is not
/// the §701 shape (a session cookie the person owns, handed over by the person)
/// but impersonation of another app's client. There is no version of that we
/// would ship, so the ceiling above is permanent rather than pending.
///
/// The addresses below are NOT guessed and must not be edited from memory.
/// They come from MetaMask's own repo — `metamask-mobile`,
/// `app/selectors/featureFlagController/card/defaults.ts`, the fallback for
/// the `cardFeature` remote flag — which names the spender per chain and the
/// exact supported-token list. It is a REMOTE flag, so MetaMask can move these
/// without shipping: re-read that file before trusting a stale constant, and
/// treat a seat that suddenly lands nothing as that first.
///
/// MEASURED (2026-09-20, live against Linea — every number below was read, not
/// assumed):
///  1. HOSTS DISAGREE WILDLY, and most of the obvious ones are unusable.
///     `linea.drpc.org` caps `eth_getLogs` at 10k on its free plan and refused
///     every range tried; `linea-rpc.publicnode.com` calls a 2,000-block
///     lookback an "archive request" needing a token; `1rpc.io/linea` caps at
///     **50 blocks**; `linea.blockpi.network` 521s; `blastapi`, `onfinality`
///     and `therpc.io` did not answer at all. The two hosts below are what
///     survived, and they agree exactly (239 / 971 / 1114 logs at 2k / 9k /
///     10k). Do not add a host to this list without running that comparison.
///  2. THE RANGE CEILING IS HONEST HERE, unlike Gnosis Chain's. `rpc.linea.
///     build` caps at 10,000 and ERRORS (`range 20000 exceeds limit of 10000`)
///     rather than returning `[]`; Tenderly has no cap at all and answered
///     100,000 blocks (11,319 logs). So the silent-zero trap that shaped
///     `GnosisPayBridge` does not exist on this chain. `maxRange` sits under
///     the STRICTER host's cap anyway, because a pair that answers different
///     questions is worse than a pair that answers one.
///  3. A FILTERED READ IS EXACT. One call over 9,000 blocks and a three-way
///     chunked sum of the same span both returned 970 — so, as on Gnosis
///     Chain, the `from` topic is what makes this read honest and not merely
///     fast. Never drop it.
///  4. DECIMALS DIVERGE, and were verified on chain rather than trusted from
///     the flag file: USDC/USDT/aUSDC/mUSD/amUSD are 6, **WETH/EURe/GBPe are
///     18**. Every one matched `decimals()`. Hardcoding 18 would render every
///     dollar spend as ~$0.000000000001 — Gnosis Pay's USDCe trap exactly.
///  5. A LINEA BLOCK IS ~8.8s, not the ~2s the chain is usually described
///     with. Measured three ways (200 / 2,000 / 20,000-block spans: 8.54,
///     7.57, 8.93) and again at 60,000 blocks = 6.1 days. Every block-count
///     constant here is derived from that, so re-measure before changing one.
/// Also measured: one settlement address serves every non-US cardholder (444
/// distinct wallets spending in a ~23h window, 973 spends), the US programme
/// uses a second one (36 in the same window), an OR-array in the `to` topic
/// reads both in ONE call and its count equals the two separate reads summed
/// (1,006 = 970 + 36) on both hosts, and both hosts answer batched JSON-RPC
/// (20 blocks in 0.20s / 0.35s).
enum MetaMaskCardBridge {

    /// The `Thing.source` every row here lands under. Its own room, like
    /// ether.fi Cash and unlike the retired DeFi seats: this is a card, not a
    /// wallet reading, and prd §515 forbids a seat whose rows land under
    /// another seat's source.
    static let source = "MetaMask Card"

    /// Where a swipe's money lands, on EVERY chain. `to == settlement` is what
    /// separates a card spend from the person's own outbound transfer, and
    /// both `from` and `to` are indexed on ERC-20 `Transfer`, so this filters
    /// server-side with no false positives to clean up afterwards.
    ///
    /// TWO addresses, because MetaMask runs two card programmes — a global one
    /// and a separate US one, each behind its own foxConnect spender. Both are
    /// read in one call via an OR-array in the topic (measured on Linea:
    /// 1,006 = 970 + 36, on both hosts). A person holds one card or the other,
    /// never both, so this costs nothing and removes a whole class of "the
    /// seat works except in America".
    ///
    /// **They are CHAIN-INDEPENDENT, and that was measured rather than
    /// assumed** (2026-09-20): a real spend decoded on Linea, on Base and on
    /// Monad all settled to the same global address. So this list is global
    /// while the token tables and hosts below are per-chain — which is the
    /// shape the facts have, not a convenience.
    static let settlements = ["0x8dfe562cbb4e93d5029f39da26bb6b501a8d1d3e",
                              "0x2baa8380b362682bd373448f2f99842ed9aca24a"]

    /// One chain this seat reads, with the numbers that chain actually
    /// answered. Nothing here is shared between chains on the assumption that
    /// chains are alike — Linea and Base differ by 5× in how much history one
    /// request can carry, and that difference is the whole reason this is a
    /// struct rather than three constants.
    struct Chain {
        /// What a row's `content` names, and what the person reads.
        let name: String
        /// The explorer a spend's permalink opens in the PERSON's browser.
        /// Declared in `network-reach-audit.sh`'s non-reach list, never
        /// fetched by this app.
        let explorer: String
        /// Hosts that survived measurement, in preference order.
        let rpcs: [String]
        /// Blocks per `eth_getLogs`. Sits UNDER the strictest listed host's
        /// cap so every host answers the same question — a pair that answers
        /// different questions is worse than one that answers a smaller one.
        let maxRange: Int
        /// Requests per wallet per pass. `maxRange * maxChunks` is how far a
        /// single pass can travel; a wallet further behind catches up over
        /// several, because the cursor persists even when the head is not
        /// reached.
        let maxChunks: Int
        /// How far back first sight looks. Sized in TIME, not blocks — see
        /// each chain's note below.
        let backfillBlocks: Int
        /// Keyed by lowercased contract address (the log's own `address`
        /// field). This IS the `address` filter for the read, so an unlisted
        /// token cannot land as a spend — deliberately: the settlement address
        /// is the card's, but a token outside the card's own list arriving
        /// there is something this seat has not measured and must not name.
        let spendable: [String: Spendable]
        /// Set when the chain is read through ALCHEMY'S INDEX rather than a
        /// log walk (`alchemy_getAssetTransfers`, one call per wallet). The
        /// RPC fields above are then unused — `rpcs` is empty and the ranges
        /// are zero, so a log walk on such a chain cannot even start.
        var alchemyNetwork: String? = nil
    }

    /// The chains this seat reads. Monad rides a different reader — see
    /// `monad` — but the SAME list, so the cursor key, `clearState` and the
    /// one-chain's-outage rule all reach it without being told.
    static let chains: [Chain] = [linea, base, monad]

    /// LINEA — the reference implementation. `rpc.linea.build` caps at 10,000
    /// and ERRORS past it; `linea.gateway.tenderly.co` has no cap at all and
    /// answered 100,000 blocks. Tenderly is already this app's fallback shape
    /// on Optimism (`EtherFiCash`), so it is a known quantity rather than a
    /// host picked for having answered once. Blocks run ~8.8s, so 60,000 is
    /// 6.1 days and 7 chunks of 9,000 cover it in ONE pass.
    static let linea = Chain(
        name: "Linea",
        explorer: "https://lineascan.build/tx/",
        rpcs: ["https://rpc.linea.build", "https://linea.gateway.tenderly.co"],
        maxRange: 9_000, maxChunks: 7, backfillBlocks: 60_000,
        spendable: [
            // Decimals verified against each contract's `decimals()`, not
            // copied from the flag file (trap 4). `aUSDC` and `amUSD` answer
            // `symbol()` as `aLinUSDC` and `aLinmUSD` on chain; the shorter
            // names are MetaMask's own, which is what the cardholder saw when
            // they enabled the token.
            "0x176211869ca2b568f2a7d4ee941e073a821ee1ff":
                Spendable(symbol: "USDC", decimals: 6, currency: "USD"),
            "0xa219439258ca9da29e9cc4ce5596924745e12b93":
                Spendable(symbol: "USDT", decimals: 6, currency: "USD"),
            "0xaca92e438df0b2401ff60da7e4337b687a2435da":
                Spendable(symbol: "mUSD", decimals: 6, currency: "USD"),
            "0x374d7860c4f2f604de0191298dd393703cce84f3":
                Spendable(symbol: "aUSDC", decimals: 6, currency: "USD"),
            "0x61b19879f4033c2b5682a969cccc9141e022823c":
                Spendable(symbol: "amUSD", decimals: 6, currency: "USD"),
            "0x3ff47c5bf409c86533fe1f4907524d304062428d":
                Spendable(symbol: "EURe", decimals: 18, currency: "EUR"),
            "0x3bce82cf1a2bc357f956dd494713fe11dc54780f":
                Spendable(symbol: "GBPe", decimals: 18, currency: "GBP"),
            "0xe5d7c2a44ffddf6b295a15c148167daaaf5cf34f":
                Spendable(symbol: "WETH", decimals: 18, currency: nil),
        ])

    /// BASE — the same card, five times less history per request, and the
    /// window is sized DOWN to match rather than the request count sized up.
    ///
    /// Measured 2026-09-20: `mainnet.base.org` is the ONLY free host that
    /// answered a filtered read at all, and it caps at 2,000 blocks;
    /// `base.gateway.tenderly.co` answers 100 but errors at 2,000, and
    /// publicnode, 1rpc and drpc refused every window tried. Blocks are
    /// exactly 2.0s, so 2,000 blocks is ~67 minutes.
    ///
    /// **Hence a 1-day backfill, not Linea's 6.** 43,200 blocks is one day and
    /// costs 22 requests at first sight; six days would cost 130, which is not
    /// a thing to do on a phone over a public endpoint for a card almost
    /// nobody watching a wallet holds. After first sight a sweep covers only
    /// the time since the cursor — an hour is 1,800 blocks, so ONE request —
    /// which is the cost that actually recurs. Tenderly stays listed second:
    /// it cannot serve 2,000, so it is reached only if `fetchSpends` is ever
    /// called with a smaller window, and `blockNumber` uses whichever answers.
    static let base = Chain(
        name: "Base",
        explorer: "https://basescan.org/tx/",
        rpcs: ["https://mainnet.base.org", "https://base.gateway.tenderly.co"],
        maxRange: 2_000, maxChunks: 22, backfillBlocks: 43_200,
        spendable: [
            // All four verified against `decimals()` on Base.
            "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913":
                Spendable(symbol: "USDC", decimals: 6, currency: "USD"),
            "0xfde4c96c8593536e31f229ea8f37b2ada2699bb2":
                Spendable(symbol: "USDT", decimals: 6, currency: "USD"),
            "0x4e65fe4dba92790696d040ac24aa414708f5c0ab":
                Spendable(symbol: "aUSDC", decimals: 6, currency: "USD"),
            "0x4200000000000000000000000000000000000006":
                Spendable(symbol: "WETH", decimals: 18, currency: nil),
        ])

    /// MONAD — read through an INDEX, because the chain itself refuses a walk
    /// (prd §860, 2026-09-20; §857b had refused the chain outright).
    ///
    /// Every free Monad host caps `eth_getLogs` at **100 blocks**
    /// (`rpc.monad.xyz`, `monad.rpc.thirdweb.com`; drpc and the `/mainnet`
    /// path refuse even that), and a Monad block is **0.302s**. One request
    /// buys 30 seconds of history: one day is 2,860 requests per wallet. That
    /// arithmetic stands and is why `rpcs` is empty. What §857b missed is that
    /// nobody reads Monad that way — an indexer walks the head once for
    /// everyone, and this app already holds a door to one.
    ///
    /// MEASURED against a live cardholder (`0xe8ee9f…`):
    /// `alchemy_getAssetTransfers` with `fromAddress` = the wallet, the two
    /// card tokens as `contractAddresses` and category `erc20` answered the
    /// wallet's WHOLE history in one 0.6s call — 42 rows, 39 to a settlement
    /// address, back eleven days — and every row carried
    /// `metadata.blockTimestamp` (§790's missing-time trap is HyperEVM's and
    /// World Chain's, not Monad's). `internal` is never asked for: Monad
    /// refuses the whole call with it (`WalletIngest.Chain.internalTransfers`).
    /// Zerion reads the same spends but has no price for vmUSD and spends the
    /// shared 300-a-day key, so it is not the door.
    ///
    /// `toAddress` takes ONE address, so the two programmes are filtered here
    /// rather than on the wire; the token filter keeps the page to card tokens,
    /// so the three non-settlement rows above are the whole cost of that.
    ///
    /// **vmUSD IS NOT A DOLLAR, and it is 98% of Monad's card spending**
    /// (1,971 of 2,000 settlement transfers sampled; USDC is the rest). It is
    /// a Veda vault SHARE over mUSD, and the contract is not ERC-4626
    /// (`convertToAssets` and `asset()` revert). The rate lives on Veda's
    /// ACCOUNTANT, found by following the chain rather than a docs page:
    /// vmUSD's `hook()` is its Teller (`0xb30755c7…`), whose `accountant()` is
    /// `0x98a45d90…`; that contract's `vault()` answers vmUSD, its `base()` is
    /// mUSD, its `decimals()` 6, and `getRate()` read 1016199 — which is the
    /// measured wallet's own deposit to five figures (23.926019 mUSD for
    /// 23.544781 vmUSD). See `Share` for how the rate is allowed to be used.
    /// Both token decimals verified against `decimals()` on chain.
    static let monad = Chain(
        name: "Monad",
        explorer: "https://monadscan.com/tx/",
        rpcs: [], maxRange: 0, maxChunks: 0, backfillBlocks: 0,
        spendable: [
            "0x1c8a336051d2024e318a229d01f9f6cf96efd316":
                Spendable(symbol: "vmUSD", decimals: 6, currency: "USD",
                          share: Share(
                            accountant: "0x98a45d90e81849a5743241d3ff765f9fd788206a",
                            rateDecimals: 6)),
            "0x754704bc059f8c67012fed69bc8a327a5aafb603":
                Spendable(symbol: "USDC", decimals: 6, currency: "USD"),
        ],
        alchemyNetwork: "monad-mainnet")

    /// `Transfer(address indexed from, address indexed to, uint256 value)`.
    private static let transferTopic =
        "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"

    struct Spendable {
        let symbol: String
        let decimals: Int
        /// The ISO code the amount is really denominated in, so a spend reads
        /// "€42.50" rather than a ticker nobody outside crypto knows.
        ///
        /// NIL FOR WETH, and that is the honesty rule rather than an omission
        /// (prd §83). The other tokens here are fiat stablecoins, so the token
        /// amount IS the money and rendering it as money is true. Ether is
        /// not: turning 0.0031 WETH into a dollar figure needs a price at the
        /// moment of the swipe, which the chain does not carry and this pass
        /// does not fetch. So a WETH spend shows the token amount and sets no
        /// `priceValue` — a row that says nothing about dollars rather than
        /// one that says something false about them.
        let currency: String?
        /// Set when the token is a vault SHARE rather than the money itself:
        /// its amount is worth `currency` only after multiplying by a rate.
        var share: Share? = nil
    }

    /// A Veda vault share's price, and the limit on using it (prd §860).
    ///
    /// The rate is read ONCE PER SWEEP, at the head — neither Monad's public
    /// RPC nor Alchemy serves `eth_call` at a block eleven days back (measured:
    /// "Block requested not found"), so a spend cannot be priced at its own
    /// moment. The rate only creeps (1016198 → 1016199 across a few hours;
    /// ~1.6% over the vault's whole life), so the head's rate is true to the
    /// cent for a RECENT spend and quietly wrong for an old one. Hence
    /// `freshness`: a share spend older than that lands with the token amount
    /// and no `priceValue`, exactly like WETH, rather than a dollar figure
    /// quoted off a rate it never traded at (§83). In practice only a first
    /// sight's older history is affected — every later sweep prices what is
    /// new within minutes of it happening.
    struct Share {
        /// Lowercased. `getRate()` on it answers base-per-share.
        let accountant: String
        let rateDecimals: Int
        static let freshness: TimeInterval = 7 * 86_400
        /// A share over a dollar stablecoin is worth a little over a dollar.
        /// Anything outside this is a wrong contract or a broken read, and
        /// lands unpriced rather than multiplied in.
        static let plausible = 1.0...1.5
    }

    // MARK: - The seat (automatic — rides the watched wallets)

    /// Per CHAIN and per address. The chain is in the key because the cursors
    /// are block numbers on different chains and are not comparable: one key
    /// for both would have Base's ~51,000,000 head overwrite Linea's
    /// ~32,000,000 and skip four months of Linea in one pass.
    private static func cursorKey(_ chain: Chain, _ address: String) -> String {
        "metamaskcard.cursor.\(chain.name.lowercased()).\(address.lowercased())"
    }

    /// Which watched wallets have actually spent on a MetaMask Card.
    ///
    /// Same rule as Gnosis Pay and ether.fi Cash: most wallets hold no card,
    /// and a seat reading "MetaMask Card · watching 3 wallets" for someone who
    /// has never held one is a fake status, which the honesty rule forbids. So
    /// the seat appears only once a spend has actually been seen.
    static let evidence = WalletSeatEvidence("metamaskcard.accounts")

    static func accounts() -> [String] { evidence.addresses }

    /// Wallet unwatch takes this seat's cursor and its card-account mark with
    /// it — called from WalletStore beside the siblings'. A stale mark would
    /// keep the seat lit for a card whose wallet is gone.
    static func clearState(address: String) {
        let a = address.lowercased()
        // EVERY chain's cursor, derived from `chains` rather than listed — a
        // hand-kept list here would leave a cursor behind the day a chain is
        // added, and that cursor is ahead of blocks never read, so re-watching
        // would land nothing and look like a broken seat.
        for chain in chains {
            UserDefaults.standard.removeObject(forKey: cursorKey(chain, a))
        }
        evidence.forget(a)
    }

    // MARK: - Sync

    @MainActor private static var running = false

    /// Reads new card spends for the given (resolved, hex) addresses and lands
    /// them — called inside `WalletIngest.refresh`'s pass beside
    /// `GnosisPayBridge.sync`, under that pass's running guard. Returns the
    /// landed count, nil when NO chain could be reached at all.
    @MainActor
    static func sync(context: ModelContext, addresses: [String],
                     existing: Set<String>) async -> Int? {
        guard !running else { return 0 }
        running = true
        defer { running = false }
        return await syncLocked(context: context, addresses: addresses,
                                existing: existing)
    }

    @MainActor
    private static func syncLocked(context: ModelContext, addresses: [String],
                                   existing: Set<String>) async -> Int? {
        guard !addresses.isEmpty else { return 0 }
        var added = 0
        var anyChainAnswered = false
        // ONE CHAIN'S OUTAGE IS NOT THE SEAT'S (the §825 rule, one layer
        // down): a chain that cannot be reached leaves its own cursor alone
        // and the others still land. `nil` is returned only when NONE
        // answered, which is the difference between "nothing was spent" and
        // "we could not ask" — and this seat's whole surface is a feed, where
        // an empty pass is indistinguishable from a healthy one.
        for chain in chains {
            guard let n = await syncChain(chain, context: context,
                                          addresses: addresses, existing: existing)
            else { continue }
            anyChainAnswered = true
            added += n
        }
        return anyChainAnswered ? added : nil
    }

    @MainActor
    private static func syncChain(_ chain: Chain, context: ModelContext,
                                  addresses: [String],
                                  existing: Set<String>) async -> Int? {
        if let network = chain.alchemyNetwork {
            return await syncIndexed(chain, network: network, context: context,
                                     addresses: addresses, existing: existing)
        }
        guard let latest = await blockNumber(chain) else { return nil }
        let defaults = UserDefaults.standard
        var added = 0

        for address in addresses {
            let key = cursorKey(chain, address)
            let cursor = (defaults.object(forKey: key) as? Int)
                ?? max(0, latest - chain.backfillBlocks) - 1
            guard latest > cursor else { continue }
            var from = cursor + 1
            let budget = chain.maxRange * chain.maxChunks
            if latest - from >= budget { from = latest - budget + 1 }
            var scanned = from - 1
            var logs: [[String: Any]] = []
            while scanned < latest {
                let to = min(scanned + chain.maxRange, latest)
                guard let chunk = await fetchSpends(chain, wallet: address,
                                                    from: scanned + 1, to: to)
                else { break }   // transient — keep the cursor, retry next pass
                logs += chunk
                scanned = to
            }
            guard scanned > cursor else { continue }

            // The card-account mark keys on spends FOUND, not on things
            // LANDED — Gnosis Pay's rule, and for its reason: keying it on new
            // things loses the seat forever for anyone who unwatches and
            // re-watches, because `clearState` drops the mark, the re-scan
            // finds the same spends, dedupe removes every one, nothing lands,
            // and the seat never comes back. A log that passed this filter
            // (from == wallet, to == a settlement, on a card token) IS a card
            // spend by construction.
            if !logs.isEmpty { evidence.remember(address) }

            let found = spends(chain, from: logs)
            let times = await blockTimes(chain, blocks: found.map(\.block))
            let landed = things(chain, from: found, times: times, rates: [:],
                                wallet: address, existing: existing)
            if !landed.isEmpty {
                for thing in landed {
                    context.insert(thing)
                    SpotlightIndex.index([thing])
                }
                // Land and SAVE before advancing (the WalletApprovals rule) —
                // a cursor that runs ahead of a failed save loses the spends
                // it skipped, permanently.
                guard context.saveHonestly() else { continue }
                added += landed.count
            }
            defaults.set(scanned, forKey: key)
        }
        return added
    }

    /// The indexed chains' pass — one `alchemy_getAssetTransfers` per wallet.
    /// Same contract as the log walk above: evidence keys on spends FOUND,
    /// land and SAVE before the cursor moves, and nil only when the index
    /// answered for nobody.
    ///
    /// FIRST SIGHT READS FROM BLOCK ZERO, where the walked chains read days.
    /// Their windows are a request budget; here the whole history is one
    /// request, so the newest page (1,000 card-token transfers) is the bound.
    @MainActor
    private static func syncIndexed(_ chain: Chain, network: String,
                                    context: ModelContext, addresses: [String],
                                    existing: Set<String>) async -> Int? {
        let defaults = UserDefaults.standard
        var added = 0
        var answered = false
        // Read lazily and once: most wallets hold no card, and a pass that
        // finds no share spend never asks.
        var rates: [String: Double]?

        for address in addresses {
            let key = cursorKey(chain, address)
            let cursor = (defaults.object(forKey: key) as? Int) ?? -1
            guard let transfers = await fetchTransfers(chain, network: network,
                                                       wallet: address,
                                                       from: cursor + 1)
            else { continue }   // transient — keep the cursor, retry next pass
            answered = true

            var spends: [Spend] = []
            var times: [Int: Date] = [:]
            var scanned = cursor
            var undated = false
            for t in transfers {
                guard let blockHex = t["blockNum"] as? String else { continue }
                let block = WalletIngest.hexToInt(blockHex)
                scanned = max(scanned, block)
                guard let to = (t["to"] as? String)?.lowercased(),
                      settlements.contains(to),
                      let raw = t["rawContract"] as? [String: Any],
                      let contract = (raw["address"] as? String)?.lowercased(),
                      let token = chain.spendable[contract],
                      let value = raw["value"] as? String,
                      let txHash = t["hash"] as? String,
                      // `<hash>:log:<index>` — the same (hash, log index) pair
                      // the walked chains key a row on.
                      let logIndex = (t["uniqueId"] as? String)
                          .flatMap({ Int($0.split(separator: ":").last ?? "") })
                else { continue }
                // A spend the index cannot date is NOT dated now (§790): the
                // whole read is treated as transient, so the cursor stays and
                // the next pass asks again.
                guard let when = IngestSupport.isoDate(
                    (t["metadata"] as? [String: Any])?["blockTimestamp"])
                else { undated = true; break }
                times[block] = when
                spends.append(Spend(token: token,
                                    raw: WalletIngest.hexToDouble(value),
                                    block: block, txHash: txHash,
                                    logIndex: logIndex))
            }
            guard !undated, scanned > cursor else { continue }
            if !spends.isEmpty { evidence.remember(address) }

            if rates == nil, spends.contains(where: { $0.token.share != nil }) {
                rates = await shareRates(chain, network: network)
            }
            let landed = things(chain, from: spends, times: times,
                                rates: rates ?? [:],
                                wallet: address, existing: existing)
            if !landed.isEmpty {
                for thing in landed {
                    context.insert(thing)
                    SpotlightIndex.index([thing])
                }
                guard context.saveHonestly() else { continue }
                added += landed.count
            }
            defaults.set(scanned, forKey: key)
        }
        return answered || addresses.isEmpty ? added : nil
    }

    /// `-metamaskCardProbe <blocksBack|YES>` — runs the sweep over the watched
    /// wallets headlessly. A numeric spec rewinds every cursor that many blocks
    /// below the head first, so real past spends land without waiting for
    /// someone to buy something. Pair with `-walletAddress <a cardholder>`.
    ///
    /// The rewind is in BLOCKS and the chains do not agree on what a block is
    /// worth — 10,000 is a day on Linea and under six hours on Base — so the
    /// probe NSLogs each chain's head with the spec it applied, rather than
    /// letting one number read as one window.
    @MainActor
    static func probe(context: ModelContext, blocksBack: Int?) async -> Int? {
        for _ in 0..<60 where running {
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        guard !running else { return 0 }
        running = true
        defer { running = false }
        let watched = WalletStore.shared.addresses.map(\.address)
        let addresses = await WalletIngest.resolvedAddresses(watched)
            .filter { ENS.isHexAddress($0) }
        for chain in chains {
            if let network = chain.alchemyNetwork {
                // No head to rewind from and no need: a rewind on an indexed
                // chain is "forget the cursor", which re-reads the whole page.
                NSLog("[Casberi] metamaskCardChain| %@ | indexed via %@%@",
                      chain.name, network,
                      blocksBack == nil ? "" : " | cursor cleared")
                if blocksBack != nil {
                    for address in addresses {
                        UserDefaults.standard.removeObject(
                            forKey: cursorKey(chain, address))
                    }
                }
                continue
            }
            guard let latest = await blockNumber(chain) else {
                NSLog("[Casberi] metamaskCardChain| %@ | UNREACHABLE", chain.name)
                continue
            }
            NSLog("[Casberi] metamaskCardChain| %@ | head %d | range %d × %d | backfill %d",
                  chain.name, latest, chain.maxRange, chain.maxChunks,
                  chain.backfillBlocks)
            guard let back = blocksBack else { continue }
            for address in addresses {
                UserDefaults.standard.set(max(0, latest - back) - 1,
                                          forKey: cursorKey(chain, address))
            }
        }
        let n = await syncLocked(
            context: context, addresses: addresses,
            existing: IngestSupport.existingSourceRefs(context, source: source))
        dumpRows(context: context)
        return n
    }

    /// One NSLog PER ROW, never one joined message — the log reader truncates a
    /// long multi-line NSLog mid-document (the `-todayProbe` lesson). A count
    /// alone can't tell a correct amount from one off by 12 decimal places,
    /// which is exactly trap 4, so the probe has to show the money it wrote.
    @MainActor
    private static func dumpRows(context: ModelContext) {
        let name = source
        var descriptor = FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == name },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        descriptor.fetchLimit = 12
        let rows = (try? context.fetch(descriptor)) ?? []
        NSLog("[Casberi] metamaskCardRows: %d in corpus (newest %d shown)",
              (try? context.fetchCount(FetchDescriptor<Thing>(
                  predicate: #Predicate { $0.source == name }))) ?? rows.count,
              rows.count)
        let stamp = ISO8601DateFormatter()
        for row in rows where row.isLive {
            NSLog("[Casberi] metamaskCardRow| %@ | %@ | %@ %@ | %@",
                  stamp.string(from: row.capturedAt),
                  row.title,
                  row.priceValue.map { String(format: "%.2f", $0) } ?? "—",
                  row.priceCurrency ?? "—",
                  row.content)
        }
    }

    /// The probe's status line — which watched wallets are card accounts.
    static func accountSummary() -> String {
        let known = accounts()
        guard !known.isEmpty else { return "no card accounts seen" }
        return "\(known.count) card account\(known.count == 1 ? "" : "s"): "
            + known.map { WalletStore.shortAddress($0) }.joined(separator: ", ")
    }

    // MARK: - Landing spends

    private struct Spend {
        let token: Spendable
        let raw: Double
        let block: Int
        let txHash: String
        let logIndex: Int
    }

    private static func spends(_ chain: Chain,
                               from logs: [[String: Any]]) -> [Spend] {
        var spends: [Spend] = []
        for log in logs {
            guard (log["removed"] as? Bool) != true,
                  let contract = (log["address"] as? String)?.lowercased(),
                  let token = chain.spendable[contract],
                  let txHash = log["transactionHash"] as? String,
                  let blockHex = log["blockNumber"] as? String,
                  let indexHex = log["logIndex"] as? String,
                  let data = log["data"] as? String
            else { continue }
            spends.append(Spend(token: token,
                                raw: WalletIngest.hexToDouble(data),
                                block: WalletIngest.hexToInt(blockHex),
                                txHash: txHash,
                                logIndex: WalletIngest.hexToInt(indexHex)))
        }
        return spends
    }

    @MainActor
    private static func things(_ chain: Chain, from spends: [Spend],
                               times: [Int: Date], rates: [String: Double],
                               wallet: String,
                               existing: Set<String>) -> [Thing] {
        guard !spends.isEmpty else { return [] }

        // NO `suffix(N)` cap here — Gnosis Pay's divergence, for its reason.
        // The sibling wallet paths cap to the newest 10 and advance the cursor
        // past the rest, which is fine when the event is rare. Card spends are
        // not rare, so capping would silently discard most of a person's
        // history the cursor then skips forever. The chain's own backfill
        // window is what bounds the first landing instead.
        var out: [Thing] = []
        var seen = Set<String>()

        for spend in spends {
            let ref = "metamaskcard:spend:\(spend.txHash.lowercased()):\(spend.logIndex)"
            guard !existing.contains(ref), seen.insert(ref).inserted else { continue }

            let amount = spend.raw / pow(10, Double(spend.token.decimals))
            let tokenAmount = "\(WalletIngest.format(amount)) \(spend.token.symbol)"
            // The fiat rendering is the honest one for the stablecoins — a
            // card spend in USDC was a dollar spend. WETH and vmUSD have no
            // currency, so they keep the token amount and claim nothing about
            // money.
            //
            // A SHARE is money only through its rate, and only while that rate
            // is fresh for this spend (`Share`). No rate, or a spend too old
            // for it, and the token falls back to WETH's rule.
            var rate: Double? = 1
            if let share = spend.token.share {
                let fresh = times[spend.block].map {
                    Date.now.timeIntervalSince($0) <= Share.freshness } ?? false
                rate = fresh ? rates[share.accountant] : nil
            }
            let value = amount * (rate ?? 1)
            let currency = rate == nil ? nil : spend.token.currency
            let money = currency
                .flatMap { PriceFormat.string(value, currency: $0) } ?? tokenAmount
            let thing = Thing(
                kind: .transaction,
                title: String(localized: "Spent \(money) with MetaMask Card"),
                content: chain.explorer + spend.txHash,
                source: source,
                capturedAt: times[spend.block] ?? .now,
                sourceRef: ref)
            thing.walletAddress = wallet
            thing.transferAmount = tokenAmount
            thing.transferDirection = "sent"
            // Set BOTH or NEITHER. Without them an amount can never be
            // re-formatted or compared — but a WETH spend has no currency to
            // set, and a `priceValue` with no `priceCurrency` reads as dollars
            // everywhere downstream.
            if let currency = currency {
                thing.priceValue = value
                thing.priceCurrency = currency
            }
            out.append(thing)
        }
        return out
    }

    // MARK: - RPC reads (each chain's own hosts, first that answers wins)

    private static func call(_ chain: Chain, method: String,
                             params: [Any]) async -> Any? {
        let body: [String: Any] = ["id": 1, "jsonrpc": "2.0",
                                   "method": method, "params": params]
        for rpc in chain.rpcs {
            if let root = await IngestSupport.postJSON(rpc, body: body) as? [String: Any],
               let result = root["result"], !(result is NSNull) {
                return result
            }
        }
        return nil
    }

    private static func blockNumber(_ chain: Chain) async -> Int? {
        guard let hex = await call(chain, method: "eth_blockNumber",
                                   params: []) as? String
        else { return nil }
        return WalletIngest.hexToInt(hex)
    }

    /// Settlement transfers out of this wallet — every card token and BOTH
    /// programmes in one call, filtered server-side on both indexed topics.
    /// Do NOT split this per token or per settlement address; the token list is
    /// the `address` filter, the two settlements are an OR-array in the `to`
    /// topic, and one call is the whole read (measured: the OR count equals
    /// the two separate reads summed).
    private static func fetchSpends(_ chain: Chain, wallet: String, from: Int,
                                    to: Int) async -> [[String: Any]]? {
        guard to - from <= chain.maxRange else { return nil }  // trap 2, structurally
        let params: [String: Any] = [
            "fromBlock": hex(from), "toBlock": hex(to),
            "address": Array(chain.spendable.keys),
            "topics": [transferTopic, topic(wallet), settlements.map(topic)],
        ]
        return await call(chain, method: "eth_getLogs",
                          params: [params]) as? [[String: Any]]
    }

    /// One wallet's outbound card-token transfers on an INDEXED chain, newest
    /// first, from `from` to the head. `erc20` only — see `monad` for why
    /// `internal` is never asked for. nil when the index did not answer; an
    /// empty array is a real "nothing since the cursor".
    private static func fetchTransfers(_ chain: Chain, network: String,
                                       wallet: String,
                                       from: Int) async -> [[String: Any]]? {
        let params: [String: Any] = [
            "fromBlock": hex(from), "toBlock": "latest",
            "fromAddress": wallet,
            "contractAddresses": Array(chain.spendable.keys),
            "category": ["erc20"], "order": "desc",
            "maxCount": "0x3e8", "withMetadata": true,
        ]
        let body: [String: Any] = ["id": 1, "jsonrpc": "2.0",
                                   "method": "alchemy_getAssetTransfers",
                                   "params": [params]]
        let url = "https://\(network).g.alchemy.com/v2/\(IngestSupport.alchemyKey)"
        guard let root = await IngestSupport.postJSON(url, body: body) as? [String: Any],
              let result = root["result"] as? [String: Any]
        else { return nil }
        return result["transfers"] as? [[String: Any]]
    }

    /// `getRate()` for every share token on an indexed chain, keyed by
    /// accountant. Asked of the SAME Alchemy host the transfers came from, so
    /// it adds no host to what this seat reaches. The selector is
    /// `keccak256("getRate()")[:4]`, computed with `scripts/support/keccak.py`
    /// and proved by the read above — never typed from memory (§795).
    private static func shareRates(_ chain: Chain,
                                   network: String) async -> [String: Double] {
        let url = "https://\(network).g.alchemy.com/v2/\(IngestSupport.alchemyKey)"
        var out: [String: Double] = [:]
        for share in chain.spendable.values.compactMap(\.share) {
            let body: [String: Any] = [
                "id": 1, "jsonrpc": "2.0", "method": "eth_call",
                "params": [["to": share.accountant, "data": "0x679aefce"], "latest"]]
            guard let root = await IngestSupport.postJSON(url, body: body) as? [String: Any],
                  let hexRate = root["result"] as? String, hexRate.count == 66
            else { continue }
            let rate = WalletIngest.hexToDouble(hexRate)
                / pow(10, Double(share.rateDecimals))
            if Share.plausible.contains(rate) { out[share.accountant] = rate }
        }
        return out
    }

    /// Block timestamps, BATCHED — one HTTP request for every block in the
    /// pass (measured on Linea: 20 blocks in 0.20s and 0.35s on the two
    /// hosts). A per-block call would be one round trip per card spend, which
    /// for a first-sight backfill is dozens.
    private static func blockTimes(_ chain: Chain,
                                   blocks: [Int]) async -> [Int: Date] {
        let wanted = Array(Set(blocks)).sorted(by: >)
        guard !wanted.isEmpty else { return [:] }
        var out: [Int: Date] = [:]
        for slice in stride(from: 0, to: wanted.count, by: 50).map({
            Array(wanted[$0..<min($0 + 50, wanted.count)])
        }) {
            let body: [[String: Any]] = slice.enumerated().map { i, block in
                ["id": i, "jsonrpc": "2.0", "method": "eth_getBlockByNumber",
                 "params": [hex(block), false]]
            }
            var rows: [[String: Any]]?
            for rpc in chain.rpcs {
                if let r = await IngestSupport.postJSONArray(rpc, body: body) {
                    rows = r
                    break
                }
            }
            // The batch answers in whatever order it likes, so read the block
            // number off each RESULT rather than trusting position.
            for row in rows ?? [] {
                guard let result = row["result"] as? [String: Any],
                      let numberHex = result["number"] as? String,
                      let ts = result["timestamp"] as? String else { continue }
                out[WalletIngest.hexToInt(numberHex)] =
                    Date(timeIntervalSince1970: WalletIngest.hexToDouble(ts))
            }
        }
        return out
    }

    /// An address as a 32-byte indexed log topic.
    private static func topic(_ address: String) -> String {
        "0x000000000000000000000000" + address.dropFirst(2).lowercased()
    }

    private static func hex(_ n: Int) -> String { "0x" + String(n, radix: 16) }
}
