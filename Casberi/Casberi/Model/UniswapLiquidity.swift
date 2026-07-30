import Foundation
import SwiftData

/// Uniswap V3 concentrated-liquidity positions (2026-07-30) — parity with
/// `WalletDeFi`/`MorphoDeFi`: a wallet's LP positions read straight off the
/// NonfungiblePositionManager + pool contracts, the same measured-keyless-
/// public-RPC shape `WalletDeFi` uses — NOT Morpho's own free GraphQL API,
/// which is a lucky exception its own docstring calls out. Uniswap Labs has
/// no equivalent free public position API (its subgraph needs a paid Graph
/// Gateway key), so this rides raw RPC on `WalletApprovals`'s own measured
/// chain table instead, on the SAME five chains Aave/Morpho already read —
/// Uniswap V3 is deployed on all five, no new chain-support decision needed.
///
/// Structurally different from the other two: Aave/Morpho ask "is it safe"
/// (health factor vs. liquidation). A Uniswap LP position asks "is it
/// working" — a concentrated range earns fees only while the pool's price
/// sits inside it, and drifting out of range is SILENT (Uniswap's own app
/// shows a grey badge only if you go look). That's the delight this file
/// exists to deliver: the range crossing (both directions — re-entering
/// range is real news too, unlike a liquidation recovery), how long a
/// position has sat idle, and a fee-milestone thing — facts no Uniswap UI
/// surfaces as news on its own.
///
/// Modeled in THREE parts, the `MorphoDeFi` shape minus its rate-comparison
/// pass (see the note by `clearState` for why that one's deferred, not
/// skipped by oversight):
/// (1) `book(addresses:)` — LIVE STATE, never landed, re-read every
///     foreground pass (60s coalesced, the `WalletDeFi`/`MorphoDeFi` TTL).
/// (2) `sync(...)` — a DISCRETE ALERT on a range crossing, in BOTH
///     directions on purpose.
/// (3) `syncActivity(...)` — SETTLED events (IncreaseLiquidity/
///     DecreaseLiquidity/Collect), the `WalletApprovals` cursor shape
///     (blocks, not Morpho's timestamps — this rides raw RPC, not a
///     timestamp-filtered API). A landed Collect event also feeds the
///     lifetime-fees-collected running total the milestone ladder reads.
///
/// Deliberately NOT attempted: a position's total USD value (locked
/// token0+token1 at the current price) needs the same sqrt-price/liquidity
/// math Uniswap's own SDK implements — real math, easy to get subtly wrong,
/// and the honesty rule says a confidently-wrong dollar figure is worse than
/// none. What ships instead is fully derived from values already read
/// straight off the contracts: uncollected fees (from a simulated
/// `collect()` call, never sent) and the range/tick facts. No IL number
/// either, same reasoning, deferred. The Aave-rate-comparison toast is
/// deferred for the same structural reason — see `clearState`'s doc comment.
///
/// MEASURED live 2026-07-30, don't re-derive without re-measuring:
/// - Factory/NonfungiblePositionManager addresses, from Uniswap's own
///   deployments docs, cross-checked with `eth_getCode` returning real,
///   IDENTICAL-length bytecode on every chain below: the SAME address on
///   Ethereum/Arbitrum/Optimism/Polygon (`0x1F98…F984` factory,
///   `0xC364…FE88` position manager — one deterministic deploy), Base
///   independently deployed with its own two addresses (the Aave-on-Base
///   precedent in `WalletDeFi`).
/// - Multicall3 (`0xcA11…CA11`) confirmed live via `eth_getCode` on all five
///   chains — available for a future batching pass; this file reads
///   sequentially per position for now (typical wallets hold a handful of
///   positions at most, and sequential keeps the ABI encoding simple and
///   easy to verify, the same tradeoff `WalletDeFi.positions` already
///   makes).
/// - Every selector below is keccak256-derived, not copied from memory:
///   `balanceOf(address)` 0x70a08231, `tokenOfOwnerByIndex(address,uint256)`
///   0x2f745c59, `positions(uint256)` 0x99fbab88,
///   `getPool(address,address,uint24)` 0x1698ee82, `slot0()` 0x3850c7bd,
///   `collect((uint256,address,uint128,uint128))` 0xfc6f7865. Event topics:
///   `IncreaseLiquidity(uint256,uint128,uint256,uint256)` 0x3067048b…,
///   `DecreaseLiquidity(uint256,uint128,uint256,uint256)` 0x26f6a048…,
///   `Collect(uint256,address,uint256,uint256)` 0x40d0efd1….
/// - `positions()`'s `tickLower`/`tickUpper` are SIGNED — Solidity
///   sign-extends a negative `int24` across the WHOLE 32-byte ABI word, so
///   reading the word as unsigned (the naive `WalletIngest.hexToDouble`
///   read) silently corrupts a real negative tick into ~1.16e77 instead of
///   -27840. `hexToSignedInt` below fixes this by taking the low N bits and
///   sign-extending from THAT width, which is exact for any value that
///   genuinely fits in an `intN` (it always does, for a well-formed
///   response) without needing arbitrary-precision arithmetic.
/// - The whole read chain — `positions()` → `getPool()` → `slot0()` → a
///   simulated `collect()` — was verified end-to-end live against a real
///   position: tokenId 1342508, owned by
///   `0x7516d4e35a369fc18ddfeec0d69c28112fe13bf0` on Ethereum, a genuine
///   out-of-range position (current tick -28284 sits below its
///   [-27840, -27300] range). That wallet is the reference address for
///   `-uniswapProbe`.
enum UniswapLiquidity {

    private struct Chain {
        let network: String
        let factory: String
        let positionManager: String
    }

    /// Ethereum/Arbitrum/Optimism/Polygon share one deterministic deploy;
    /// Base was deployed separately and carries its own two addresses (see
    /// the type doc above). All lowercased — every address comparison in
    /// this file works on lowercased hex, matching `WalletDeFi`/`MorphoDeFi`.
    private static let allChains: [Chain] = [
        Chain(network: "eth-mainnet",
              factory: "0x1f98431c8ad98523631ae4a59f267346ea31f984",
              positionManager: "0xc36442b4a4522e871399cd717abdd847ab11fe88"),
        Chain(network: "base-mainnet",
              factory: "0x33128a8fc17869897dce68ed026d694621f6fdfd",
              positionManager: "0x03a520b32c04bf3beef7beb72e919cf822ed34f1"),
        Chain(network: "arb-mainnet",
              factory: "0x1f98431c8ad98523631ae4a59f267346ea31f984",
              positionManager: "0xc36442b4a4522e871399cd717abdd847ab11fe88"),
        Chain(network: "opt-mainnet",
              factory: "0x1f98431c8ad98523631ae4a59f267346ea31f984",
              positionManager: "0xc36442b4a4522e871399cd717abdd847ab11fe88"),
        Chain(network: "matic-mainnet",
              factory: "0x1f98431c8ad98523631ae4a59f267346ea31f984",
              positionManager: "0xc36442b4a4522e871399cd717abdd847ab11fe88"),
    ]
    private static var chains: [Chain] {
        let active = Set(WalletChainStore.activeNetworkIDs())
        return allChains.filter { active.contains($0.network) }
    }

    /// The health-factor-style margin doesn't apply here (there's no
    /// liquidation) — range crossing is binary, in or out, so there is no
    /// threshold to keep in step with `DeFiRisk.floor`. Kept separate from
    /// that type on purpose (see the file doc): folding a structurally
    /// different risk into a type built for one liquidation number would
    /// overload it.

    // MARK: - Live state

    struct Position: Equatable, Sendable {
        let network: String
        let address: String       // the watched wallet, lowercased
        let tokenId: Int
        let token0: String
        let token1: String
        let token0Symbol: String
        let token1Symbol: String
        let feeTier: Int          // hundredths of a bip — 3000 = 0.30%
        let tickLower: Int
        let tickUpper: Int
        let currentTick: Int
        let inRange: Bool
        /// Uncollected fees, scaled by each token's own decimals — read via
        /// a SIMULATED `collect()` (an `eth_call`, never sent), which is the
        /// only way to read fees still accruing since the position's last
        /// on-chain interaction; `positions()`'s own `tokensOwed` field only
        /// reflects the LAST poke, not the live number.
        let uncollectedFee0: Double
        let uncollectedFee1: Double
        let uncollectedFeeUSD: Double?   // nil when either token is unpriced
    }

    struct Book: Equatable, Sendable {
        var positions: [Position] = []
        var isEmpty: Bool { positions.isEmpty }
    }

    /// Coalesced like `WalletDeFi`/`MorphoDeFi`'s own book reads — the
    /// refresh arm, the Wallet screen's live state, and the ask all want
    /// this same read every foreground pass.
    private static let cache = CoalescingCache<Book>()

    static func book(addresses: [String]) async -> Book? {
        guard !addresses.isEmpty, !chains.isEmpty else { return Book() }
        let key = addresses.map { $0.lowercased() }.sorted().joined(separator: ",")
            + "|" + chains.map(\.network).joined(separator: ",")
        return await cache.value(key: key, ttl: 60) {
            await fetchBook(addresses: addresses)
        }
    }

    private static func fetchBook(addresses: [String]) async -> Book {
        var book = Book()
        for chain in chains {
            for address in addresses {
                let tokenIds = await ownedTokenIds(chain: chain, owner: address)
                guard !tokenIds.isEmpty else { continue }
                var pairs: Set<String> = []   // dedupe pricing requests per pass
                var raw: [(tokenId: Int, info: PositionInfo, fee0: Double, fee1: Double)] = []
                for tokenId in tokenIds {
                    guard let info = await positionInfo(chain: chain, tokenId: tokenId),
                          info.liquidity > 0 else { continue }
                    let (fee0, fee1) = await simulatedFees(chain: chain, tokenId: tokenId,
                                                           owner: address, info: info)
                    raw.append((tokenId, info, fee0, fee1))
                    pairs.insert("\(chain.network)|\(info.token0)")
                    pairs.insert("\(chain.network)|\(info.token1)")
                }
                guard !raw.isEmpty else { continue }
                let prices = await DefiLlamaPrices.prices(for: pairs.compactMap { pair in
                    let parts = pair.split(separator: "|", maxSplits: 1)
                    guard parts.count == 2 else { return nil }
                    return (network: String(parts[0]), contract: String(parts[1]))
                })
                for entry in raw {
                    let info = entry.info
                    guard let pool = await poolAddress(chain: chain, token0: info.token0,
                                                       token1: info.token1, fee: info.fee),
                          let tick = await currentTick(chain: chain, pool: pool)
                    else { continue }
                    let inRange = info.tickLower <= tick && tick < info.tickUpper
                    let meta0 = await tokenMeta(chain: chain, contract: info.token0)
                    let meta1 = await tokenMeta(chain: chain, contract: info.token1)
                    let scaled0 = entry.fee0 / pow(10, Double(meta0?.decimals ?? 18))
                    let scaled1 = entry.fee1 / pow(10, Double(meta1?.decimals ?? 18))
                    var usd: Double? = nil
                    if let p0 = prices["\(chain.network)|\(info.token0)"]?.price,
                       let p1 = prices["\(chain.network)|\(info.token1)"]?.price {
                        usd = scaled0 * p0 + scaled1 * p1
                    }
                    book.positions.append(Position(
                        network: chain.network, address: address.lowercased(),
                        tokenId: entry.tokenId,
                        token0: info.token0, token1: info.token1,
                        token0Symbol: meta0?.symbol ?? "?", token1Symbol: meta1?.symbol ?? "?",
                        feeTier: info.fee, tickLower: info.tickLower, tickUpper: info.tickUpper,
                        currentTick: tick, inRange: inRange,
                        uncollectedFee0: scaled0, uncollectedFee1: scaled1,
                        uncollectedFeeUSD: usd))
                }
            }
        }
        return book
    }

    // MARK: - Range-crossing alert (the WalletDeFi.sync bucket shape)

    private static func rangeKey(_ address: String, _ network: String, _ tokenId: Int) -> String {
        "wallet.defi.uniswap.range.\(address.lowercased()).\(network).\(tokenId)"
    }
    private static func sinceKey(_ address: String, _ network: String, _ tokenId: Int) -> String {
        "uniswap.range.since.\(address.lowercased()).\(network).\(tokenId)"
    }

    /// Lands a thing on a NEW range crossing, in BOTH directions — the
    /// deliberate divergence from Aave/Morpho's one-way liquidation alert.
    /// Re-entering range means the position started earning again, which is
    /// real news for a market-maker the way "recovering" isn't for a
    /// borrower. First sight seeds silently, fails closed on a read miss —
    /// the exact `WalletDeFi.sync` idiom.
    @MainActor
    static func sync(context: ModelContext, addresses: [String], existing: Set<String>) async -> Int {
        guard !addresses.isEmpty, let book = await book(addresses: addresses) else { return 0 }
        let defaults = UserDefaults.standard
        var added = 0
        for position in book.positions {
            let key = rangeKey(position.address, position.network, position.tokenId)
            let bucket = position.inRange ? "in-range" : "out-of-range"
            let last = defaults.string(forKey: key)
            defaults.set(bucket, forKey: key)
            let since = sinceKey(position.address, position.network, position.tokenId)
            if bucket == "out-of-range", last != "out-of-range" {
                defaults.set(Date.now.timeIntervalSince1970, forKey: since)
            } else if bucket == "in-range" {
                defaults.removeObject(forKey: since)
            }
            guard let last, last != bucket else { continue }   // first sight or unchanged
            let ref = "wallet:defi:uniswap:range:\(position.network):\(position.tokenId):"
                + String(Int(Date.now.timeIntervalSince1970))
            guard !existing.contains(ref) else { continue }
            let pair = "\(position.token0Symbol)/\(position.token1Symbol)"
            let chainName = WalletIngest.displayName(forNetwork: position.network) ?? position.network
            let title = bucket == "out-of-range"
                ? String(localized: "Your \(pair) position on \(chainName) drifted out of range — it stopped earning fees")
                : String(localized: "Your \(pair) position on \(chainName) is back in range and earning again")
            let thing = Thing(kind: .transaction, title: title,
                              content: "https://app.uniswap.org/positions/v3/\(chainSlug(position.network))/\(position.tokenId)",
                              source: "Wallet", sourceRef: ref)
            thing.walletAddress = position.address
            context.insert(thing)
            SpotlightIndex.index([thing])
            added += 1
        }
        if added > 0 { context.saveHonestly() }
        return added
    }

    /// "out of range for 6 days" — a single stored crossing timestamp per
    /// position, simpler than `MorphoDeFi.hfTrend`'s sampled series since
    /// range is a binary state, not a continuous drift. nil while in range
    /// or before a full day has passed.
    static func timeOutOfRange(address: String, network: String, tokenId: Int) -> String? {
        let key = sinceKey(address, network, tokenId)
        guard UserDefaults.standard.object(forKey: key) != nil else { return nil }
        let since = UserDefaults.standard.double(forKey: key)
        let elapsed = Date.now.timeIntervalSince1970 - since
        guard elapsed >= 86_400 else { return nil }
        let days = Int(elapsed / 86_400)
        return days == 1 ? String(localized: "out of range for a day")
                          : String(localized: "out of range for \(days) days")
    }

    // MARK: - Settled activity (blocks, the WalletApprovals cursor shape)

    private static func cursorKey(_ address: String, _ network: String) -> String {
        "uniswap.cursor.\(address.lowercased()).\(network)"
    }
    private static func lifetimeFeesKey(_ address: String) -> String {
        "uniswap.fees.lifetime.\(address.lowercased())"
    }

    private static let increaseTopic =
        "0x3067048beee31b25b2f1681f88dac838c8bba36af25bfb2b7cf7473a5847e35f"
    private static let decreaseTopic =
        "0x26f6a048ee9138f2c0ce266f322cb99228e8d619ae2bff30c67f8dcf9d2377b4"
    private static let collectTopic =
        "0x40d0efd1a53d60ecbf40971b9daf7dc90178c3aadc7aab1765632738fa8b8f01"

    /// Chunks per (wallet, chain) pass — the `WalletApprovals.maxChunks`
    /// idiom, bounding a long-absence catch-up to the newest window rather
    /// than an unbounded crawl of a shared public RPC.
    private static let maxChunks = 16

    /// Newest events landed per (wallet, chain) per pass — the
    /// `MorphoDeFi.maxLanded` idiom: a long gap folds to its recent tail
    /// rather than flooding the feed with every Increase/Decrease/Collect
    /// since the last visit.
    private static let maxLanded = 12

    @MainActor private static var runningActivity = false

    /// Lands settled position events for the given (resolved, hex)
    /// addresses. First sight of a (wallet, chain) seeds the cursor silently
    /// — history before the watch isn't ours to dump. A landed Collect event
    /// also grows the wallet's lifetime-fees-COLLECTED total (never the
    /// still-pending uncollected balance, which can move before it's really
    /// collected) — the number `syncMilestone` below checks against the
    /// PostHog-shared 1-2-5 ladder.
    @MainActor
    static func syncActivity(context: ModelContext, addresses: [String],
                             existing: Set<String>) async -> Int? {
        guard !runningActivity else { return 0 }
        runningActivity = true
        defer { runningActivity = false }
        return await syncActivityLocked(context: context, addresses: addresses, existing: existing)
    }

    @MainActor
    private static func syncActivityLocked(context: ModelContext, addresses: [String],
                                           existing: Set<String>) async -> Int? {
        guard !addresses.isEmpty, !chains.isEmpty else { return 0 }
        var added = 0
        var reachedAny = false
        var seededOnly = true
        for chain in chains {
            guard let latest = await blockNumber(chain) else { continue }
            for address in addresses {
                let key = cursorKey(address, chain.network)
                guard let cursor = UserDefaults.standard.object(forKey: key) as? Int else {
                    UserDefaults.standard.set(latest, forKey: key)
                    continue
                }
                seededOnly = false
                guard latest > cursor else { continue }
                let tokenIds = await ownedTokenIds(chain: chain, owner: address)
                guard !tokenIds.isEmpty else {
                    // Nothing owned right now — nothing to scan for. Still
                    // advance so a long-closed wallet doesn't accumulate an
                    // ever-growing gap for the day it opens a new position.
                    UserDefaults.standard.set(latest, forKey: key)
                    reachedAny = true
                    continue
                }
                let maxRange = WalletApprovals.maxLogRange(forNetwork: chain.network) ?? 9_000
                var from = cursor + 1
                let budget = maxRange * maxChunks
                if latest - from >= budget { from = latest - budget + 1 }   // hole accepted
                var scanned = from - 1
                var logs: [[String: Any]] = []
                while scanned < latest {
                    let chunkFrom = scanned + 1
                    let to = min(scanned + maxRange, latest)
                    guard let chunk = await fetchPositionLogs(chain, tokenIds: tokenIds,
                                                              from: chunkFrom, to: to)
                    else { break }   // keep `scanned` at the last durable point; retry next pass
                    logs += chunk
                    scanned = to
                }
                guard scanned > cursor else { continue }   // nothing durable read — transient
                reachedAny = true
                let landed = await things(from: logs, chain: chain, owner: address, existing: existing)
                if !landed.isEmpty {
                    for thing in landed {
                        context.insert(thing)
                        SpotlightIndex.index([thing])
                    }
                    guard context.saveHonestly() else { continue }
                    added += landed.count
                }
                UserDefaults.standard.set(scanned, forKey: key)
            }
        }
        return (reachedAny || seededOnly) ? added : nil
    }

    private static func fetchPositionLogs(_ chain: Chain, tokenIds: [Int],
                                          from: Int, to: Int) async -> [[String: Any]]? {
        let idTopics = tokenIds.map { "0x" + padUint($0) }
        let params: [String: Any] = [
            "address": chain.positionManager,
            "fromBlock": hex(from), "toBlock": hex(to),
            "topics": [[increaseTopic, decreaseTopic, collectTopic], idTopics],
        ]
        return await WalletApprovals.rpcRead(network: chain.network, method: "eth_getLogs",
                                             params: [params]) as? [[String: Any]]
    }

    /// tokenId → (token0, token1, fee) within one activity pass, so several
    /// events for the same mint (Increase then Collect, a common pattern)
    /// share one `positions()` read.
    @MainActor
    private static func things(from logs: [[String: Any]], chain: Chain, owner: String,
                               existing: Set<String>) async -> [Thing] {
        var infoCache: [Int: PositionInfo?] = [:]
        var landed: [Thing] = []
        var feeGain: Double = 0
        for log in logs.sorted(by: { blockOf($0) < blockOf($1) }).suffix(maxLanded) {
            guard (log["removed"] as? Bool) != true,
                  let topics = log["topics"] as? [String], topics.count >= 2,
                  let topic0 = topics.first?.lowercased(),
                  let txHash = log["transactionHash"] as? String,
                  let logIndexHex = log["logIndex"] as? String,
                  let data = log["data"] as? String
            else { continue }
            let tokenId = WalletIngest.hexToInt(topics[1])
            if infoCache[tokenId] == nil {
                infoCache[tokenId] = await positionInfo(chain: chain, tokenId: tokenId)
            }
            let info = infoCache[tokenId] ?? nil
            let meta0 = info != nil ? await tokenMeta(chain: chain, contract: info!.token0) : nil
            let meta1 = info != nil ? await tokenMeta(chain: chain, contract: info!.token1) : nil
            let pairLabel = (meta0?.symbol).map { s0 in
                (meta1?.symbol).map { s1 in "\(s0)/\(s1)" } ?? s0
            }
            // amount0/amount1 are always the LAST two 32-byte words of
            // `data` for all three event shapes here — Increase/Decrease
            // carry (liquidity, amount0, amount1), Collect carries
            // (recipient, amount0, amount1); only the leading word differs,
            // which this never reads.
            let (rawAmt0, rawAmt1) = lastTwoWords(data)
            var amountText: String? = nil
            var usd: Double? = nil
            if let info, let m0 = meta0, let m1 = meta1 {
                let scaled0 = rawAmt0 / pow(10, Double(m0.decimals))
                let scaled1 = rawAmt1 / pow(10, Double(m1.decimals))
                if scaled0 > 0 || scaled1 > 0 {
                    let parts = [scaled0 > 0 ? "\(WalletIngest.format(scaled0)) \(m0.symbol)" : nil,
                                scaled1 > 0 ? "\(WalletIngest.format(scaled1)) \(m1.symbol)" : nil]
                        .compactMap { $0 }
                    amountText = parts.joined(separator: " + ")
                }
                let prices = await DefiLlamaPrices.prices(for: [
                    (network: chain.network, contract: info.token0),
                    (network: chain.network, contract: info.token1)])
                if let p0 = prices["\(chain.network)|\(info.token0)"]?.price,
                   let p1 = prices["\(chain.network)|\(info.token1)"]?.price {
                    usd = scaled0 * p0 + scaled1 * p1
                }
            }
            let logIndex = WalletIngest.hexToInt(logIndexHex)
            let ref = "uniswap:tx:\(chain.network):\(txHash.lowercased()):\(topic0):\(logIndex)"
            guard !existing.contains(ref), !landed.contains(where: { $0.sourceRef == ref }) else { continue }

            let title: String?
            switch topic0 {
            case increaseTopic:
                if let amountText {
                    title = String(localized: "Added \(amountText) to your Uniswap position")
                } else {
                    title = pairLabel.map { String(localized: "Added liquidity to \($0) on Uniswap") }
                        ?? String(localized: "Added liquidity to a Uniswap position")
                }
            case decreaseTopic:
                if let amountText {
                    title = String(localized: "Removed \(amountText) from your Uniswap position")
                } else {
                    title = pairLabel.map { String(localized: "Removed liquidity from \($0) on Uniswap") }
                        ?? String(localized: "Removed liquidity from a Uniswap position")
                }
            case collectTopic:
                if let usd, usd > 0 {
                    title = String(localized: "Collected \(TokenStats.compact(usd)) in fees on Uniswap")
                    feeGain += usd
                } else if let amountText {
                    title = String(localized: "Collected \(amountText) in fees on Uniswap")
                } else {
                    title = String(localized: "Collected fees on Uniswap")
                }
            default:
                title = nil
            }
            guard let title else { continue }
            let thing = Thing(kind: .transaction, title: title,
                              content: "https://app.uniswap.org/positions/v3/\(chainSlug(chain.network))/\(tokenId)",
                              source: "Wallet", sourceRef: ref)
            thing.walletAddress = owner
            landed.append(thing)
        }
        if feeGain > 0 {
            let key = lifetimeFeesKey(owner)
            let total = UserDefaults.standard.double(forKey: key) + feeGain
            UserDefaults.standard.set(total, forKey: key)
            syncMilestone(owner: owner, total: total, landed: &landed, existing: existing)
        }
        return landed
    }

    /// A crossing of the shared `PostHogMilestone` 1-2-5 ladder over lifetime
    /// fees actually COLLECTED (never the still-pending uncollected balance)
    /// lands a thing — the money-moving exception to "never a tally" the
    /// module doctrine carves out, reusing the same generic ladder utility
    /// PostHog's milestones already built rather than forking the logic.
    private static func syncMilestone(owner: String, total: Double,
                                      landed: inout [Thing], existing: Set<String>) {
        let cents = Int(total)   // whole dollars — the ladder's own unit
        let rung = PostHogMilestone.reached(cents)
        guard rung > 0 else { return }
        let key = "uniswap.fees.milestone.\(owner.lowercased())"
        let announced = UserDefaults.standard.integer(forKey: key)
        guard rung > announced else { return }
        UserDefaults.standard.set(rung, forKey: key)
        let ref = "uniswap:milestone:\(owner.lowercased()):\(rung)"
        guard !existing.contains(ref), !landed.contains(where: { $0.sourceRef == ref }) else { return }
        let thing = Thing(kind: .transaction,
                          title: String(localized: "You've collected $\(rung) in Uniswap fees"),
                          content: "https://app.uniswap.org/positions", source: "Wallet",
                          sourceRef: ref)
        thing.walletAddress = owner
        landed.append(thing)
    }

    /// The last two 32-byte words of a log's `data` — amount0/amount1 on
    /// every event shape this file reads (see the call site's comment).
    private static func lastTwoWords(_ data: String) -> (Double, Double) {
        var s = data.lowercased(); if s.hasPrefix("0x") { s.removeFirst(2) }
        guard s.count >= 128 else { return (0, 0) }
        let start = s.count - 128
        let amt0 = String(s[s.index(s.startIndex, offsetBy: start)..<s.index(s.startIndex, offsetBy: start + 64)])
        let amt1 = String(s[s.index(s.startIndex, offsetBy: start + 64)...])
        return (WalletIngest.hexToDouble("0x" + amt0), WalletIngest.hexToDouble("0x" + amt1))
    }

    private static func blockOf(_ log: [String: Any]) -> Int {
        (log["blockNumber"] as? String).map(WalletIngest.hexToInt) ?? 0
    }

    // MARK: - Unwatch (the Peer/Morpho rule: state leaves with the watch)

    /// No fee-rate-vs-Aave toast in this pass (the `MorphoDeFi
    /// .checkRateComparison` shape it would mirror) — a real comparison
    /// needs an annualized yield, which needs a position's USD principal,
    /// which needs the same sqrt-price/liquidity math this file's header
    /// comment already declined to implement for the honesty rule. Fabricating
    /// a rate off uncollected fees alone with no principal to divide by
    /// would be a guess wearing a percentage sign. Left for a pass that
    /// reads a position's own deposit history and computes a real number.
    static func clearState(address: String) {
        let defaults = UserDefaults.standard
        let addr = address.lowercased()
        let prefixes = ["wallet.defi.uniswap.range.\(addr).", "uniswap.range.since.\(addr).",
                        "uniswap.cursor.\(addr)."]
        for key in defaults.dictionaryRepresentation().keys
            where prefixes.contains(where: { key.hasPrefix($0) }) {
            defaults.removeObject(forKey: key)
        }
        defaults.removeObject(forKey: lifetimeFeesKey(addr))
        defaults.removeObject(forKey: "uniswap.fees.milestone.\(addr)")
    }

    // MARK: - RPC primitives

    private struct PositionInfo {
        let token0: String
        let token1: String
        let fee: Int
        let tickLower: Int
        let tickUpper: Int
        let liquidity: Double
    }

    private static func ownedTokenIds(chain: Chain, owner: String) async -> [Int] {
        guard let balHex = await WalletApprovals.rpcRead(
            network: chain.network, method: "eth_call",
            params: [["to": chain.positionManager, "data": "0x70a08231" + padAddress(owner)], "latest"]
        ) as? String else { return [] }
        let count = WalletIngest.hexToInt(balHex)
        // A sane upper bound — no real wallet holds hundreds of LP NFTs, and
        // an adversarial/malformed balance must degrade, not loop unbounded.
        guard count > 0 else { return [] }
        var ids: [Int] = []
        for i in 0..<min(count, 50) {
            let calldata = "0x2f745c59" + padAddress(owner) + padUint(i)
            guard let hex = await WalletApprovals.rpcRead(
                network: chain.network, method: "eth_call",
                params: [["to": chain.positionManager, "data": calldata], "latest"]
            ) as? String else { continue }
            ids.append(WalletIngest.hexToInt(hex))
        }
        return ids
    }

    private static func positionInfo(chain: Chain, tokenId: Int) async -> PositionInfo? {
        guard let hex = await WalletApprovals.rpcRead(
            network: chain.network, method: "eth_call",
            params: [["to": chain.positionManager, "data": "0x99fbab88" + padUint(tokenId)], "latest"]
        ) as? String else { return nil }
        var s = hex.lowercased(); if s.hasPrefix("0x") { s.removeFirst(2) }
        guard s.count >= 64 * 12 else { return nil }
        func word(_ i: Int) -> String {
            let start = s.index(s.startIndex, offsetBy: i * 64)
            let end = s.index(start, offsetBy: 64)
            return String(s[start..<end])
        }
        let token0 = "0x" + word(2).suffix(40)
        let token1 = "0x" + word(3).suffix(40)
        let fee = Int(WalletIngest.hexToDouble("0x" + word(4)))
        let tickLower = hexToSignedInt(word(5), bits: 24)
        let tickUpper = hexToSignedInt(word(6), bits: 24)
        let liquidity = WalletIngest.hexToDouble("0x" + word(7))
        return PositionInfo(token0: token0, token1: token1, fee: fee,
                            tickLower: tickLower, tickUpper: tickUpper, liquidity: liquidity)
    }

    /// Uncollected fees via a SIMULATED `collect()` (an `eth_call` with
    /// `from` set to the real owner so the position manager's
    /// authorization check passes — never a sent transaction, nothing is
    /// signed or spent). `amount0Max`/`amount1Max` at `uint128.max` reads
    /// the full owed amount rather than partially draining it — irrelevant
    /// for a simulation, but matches the real max-collect convention.
    private static func simulatedFees(chain: Chain, tokenId: Int, owner: String,
                                      info: PositionInfo) async -> (Double, Double) {
        let uint128Max = String(repeating: "f", count: 32)
        let calldata = "0xfc6f7865" + padUint(tokenId) + padAddress(owner)
            + uint128Max.leftPadded64() + uint128Max.leftPadded64()
        guard let hex = await WalletApprovals.rpcRead(
            network: chain.network, method: "eth_call",
            params: [["to": chain.positionManager, "from": owner, "data": calldata], "latest"]
        ) as? String else { return (0, 0) }
        var s = hex.lowercased(); if s.hasPrefix("0x") { s.removeFirst(2) }
        guard s.count >= 128 else { return (0, 0) }
        let amt0 = WalletIngest.hexToDouble("0x" + s.prefix(64))
        let amt1 = WalletIngest.hexToDouble("0x" + String(s.dropFirst(64).prefix(64)))
        return (amt0, amt1)
    }

    /// Pool address is immutable per (token0, token1, fee) once created —
    /// cached for the process lifetime via the actor cache with a long TTL
    /// rather than a raw mutable dictionary (this enum isn't itself an
    /// actor, and `book` runs off-MainActor).
    private static let poolCache = CoalescingCache<String>()

    private static func poolAddress(chain: Chain, token0: String, token1: String,
                                    fee: Int) async -> String? {
        let key = "\(chain.network)|\(token0)|\(token1)|\(fee)"
        return await poolCache.value(key: key, ttl: 365 * 24 * 3600) {
            let calldata = "0x1698ee82" + padAddress(token0) + padAddress(token1) + padUint(fee)
            guard let hex = await WalletApprovals.rpcRead(
                network: chain.network, method: "eth_call",
                params: [["to": chain.factory, "data": calldata], "latest"]
            ) as? String else { return nil }
            let addr = "0x" + hex.lowercased().suffix(40)
            return addr == "0x0000000000000000000000000000000000000000" ? nil : addr
        }
    }

    private static func currentTick(chain: Chain, pool: String) async -> Int? {
        guard let hex = await WalletApprovals.rpcRead(
            network: chain.network, method: "eth_call",
            params: [["to": pool, "data": "0x3850c7bd"], "latest"]
        ) as? String else { return nil }
        var s = hex.lowercased(); if s.hasPrefix("0x") { s.removeFirst(2) }
        guard s.count >= 64 * 2 else { return nil }
        let tickWord = String(s[s.index(s.startIndex, offsetBy: 64)..<s.index(s.startIndex, offsetBy: 128)])
        return hexToSignedInt(tickWord, bits: 24)
    }

    private struct TokenMeta { let symbol: String; let decimals: Int }
    private static let metaCache = CoalescingCache<TokenMeta>()

    /// Symbol/decimals off the token contract itself, keyless — mirrors
    /// `WalletApprovals.tokenMetadata`'s own `symbol()`/`decimals()`/`name()`
    /// fallback, cached long-lived since neither value ever changes.
    private static func tokenMeta(chain: Chain, contract: String) async -> TokenMeta? {
        await metaCache.value(key: "\(chain.network)|\(contract)", ttl: 24 * 3600) {
            async let symbolRet = WalletApprovals.rpcRead(
                network: chain.network, method: "eth_call",
                params: [["to": contract, "data": "0x95d89b41"], "latest"])
            async let decimalsRet = WalletApprovals.rpcRead(
                network: chain.network, method: "eth_call",
                params: [["to": contract, "data": "0x313ce567"], "latest"])
            var symbol = (await symbolRet as? String).flatMap(IngestSupport.decodeABIString)
            if symbol == nil {
                let nameRet = await WalletApprovals.rpcRead(
                    network: chain.network, method: "eth_call",
                    params: [["to": contract, "data": "0x06fdde03"], "latest"])
                symbol = (nameRet as? String).flatMap(IngestSupport.decodeABIString)
            }
            guard let symbol else { return nil }
            let decimals = (await decimalsRet as? String).map(WalletIngest.hexToInt) ?? 18
            return TokenMeta(symbol: symbol, decimals: decimals)
        }
    }

    private static func blockNumber(_ chain: Chain) async -> Int? {
        guard let hex = await WalletApprovals.rpcRead(network: chain.network,
                                                       method: "eth_blockNumber", params: []) as? String
        else { return nil }
        return WalletIngest.hexToInt(hex)
    }

    // MARK: - ABI helpers

    private static func padAddress(_ address: String) -> String {
        String(repeating: "0", count: 24) + address.dropFirst(2).lowercased()
    }

    private static func padUint(_ n: Int) -> String {
        let hex = String(n, radix: 16)
        return String(repeating: "0", count: max(0, 64 - hex.count)) + hex
    }

    private static func hex(_ n: Int) -> String { "0x" + String(n, radix: 16) }

    /// Solidity sign-extends a negative `intN` across the WHOLE 32-byte ABI
    /// word. Taking the low `bits` bits and sign-extending from THAT width
    /// gives the identical result to a full 256-bit two's-complement read
    /// without needing arbitrary-precision math — exact for any value that
    /// genuinely fits in `intN`, which a well-formed response always does.
    /// MEASURED 2026-07-30: a real tick decoded this way read -27840; the
    /// naive unsigned/masked read produced ~1.16e77 for the same word.
    private static func hexToSignedInt(_ hexWord: String, bits: Int) -> Int {
        var s = hexWord.lowercased(); if s.hasPrefix("0x") { s.removeFirst(2) }
        let hexDigits = bits / 4
        guard s.count >= hexDigits else { return 0 }
        let low = String(s.suffix(hexDigits))
        guard let raw = Int(low, radix: 16) else { return 0 }
        let signBit = 1 << (bits - 1)
        return raw >= signBit ? raw - (1 << bits) : raw
    }

    private static func chainSlug(_ network: String) -> String {
        switch network {
        case "eth-mainnet": return "ethereum"
        case "base-mainnet": return "base"
        case "arb-mainnet": return "arbitrum"
        case "opt-mainnet": return "optimism"
        case "matic-mainnet": return "polygon"
        default: return "ethereum"
        }
    }

    #if DEBUG
    /// `-uniswapProbe <blocksBack|YES>` — NSLogs every watched wallet's
    /// Uniswap V3 book (pair, range status, uncollected fees) or the honest
    /// miss. A numeric spec ALSO rewinds every activity cursor that many
    /// BLOCKS (not Morpho's days — this rides raw RPC like Approvals/Peer/
    /// GnosisPay) and runs the settled-activity sweep. Pairs with
    /// `-walletAddress` — `0x7516d4e35a369fc18ddfeec0d69c28112fe13bf0` is a
    /// real, live-verified out-of-range position on Ethereum (2026-07-30).
    @MainActor
    static func probe(context: ModelContext, blocksBack: Int?) async -> String {
        let watched = WalletStore.shared.addresses.map(\.address)
        let addresses = await WalletIngest.resolvedAddresses(watched).filter { ENS.isHexAddress($0) }
        guard !addresses.isEmpty else { return "no EVM wallets watched" }
        var lines: [String] = []
        if let book = await book(addresses: addresses) {
            if book.isEmpty {
                lines.append("no Uniswap V3 positions (a real empty book, not a miss)")
            }
            for p in book.positions {
                let chainName = WalletIngest.displayName(forNetwork: p.network) ?? p.network
                let range = p.inRange ? "in-range" : "out-of-range"
                let sinceLine = timeOutOfRange(address: p.address, network: p.network, tokenId: p.tokenId)
                    .map { " (\($0))" } ?? ""
                let feeLine = p.uncollectedFeeUSD.map { "fees=$\(WalletIngest.format($0))" } ?? "fees=unpriced"
                lines.append("\(WalletStore.shortAddress(p.address)) \(chainName) \(p.token0Symbol)/\(p.token1Symbol) #\(p.tokenId): \(range)\(sinceLine) tick=\(p.currentTick) range=[\(p.tickLower),\(p.tickUpper)] \(feeLine)")
            }
        } else {
            lines.append("book UNREACHABLE")
        }
        if let back = blocksBack {
            for chain in chains {
                guard let latest = await blockNumber(chain) else { continue }
                for address in addresses {
                    UserDefaults.standard.set(max(0, latest - back), forKey: cursorKey(address, chain.network))
                }
            }
            let landed = await syncActivityLocked(
                context: context, addresses: addresses,
                existing: IngestSupport.existingSourceRefs(context, source: "Wallet"))
            lines.append("activity: \(landed.map { "\($0) landed" } ?? "UNREACHABLE")")
        }
        return lines.joined(separator: " | ")
    }

    /// `-uniswapDelightProbe YES` — flips a real held position's stored
    /// range bucket to the OPPOSITE of its live state, so `sync` fires the
    /// crossing thing deterministically without waiting for a real tick
    /// move, the `-morphoDelightProbe` shape. Reports what landed.
    @MainActor
    static func probeDelight(context: ModelContext) async -> String {
        let watched = WalletStore.shared.addresses.map(\.address)
        let addresses = await WalletIngest.resolvedAddresses(watched).filter { ENS.isHexAddress($0) }
        guard !addresses.isEmpty else { return "no EVM wallets watched" }
        guard let book = await book(addresses: addresses), let position = book.positions.first
        else { return "no Uniswap position to probe" }
        let key = rangeKey(position.address, position.network, position.tokenId)
        let fakeLast = position.inRange ? "out-of-range" : "in-range"
        UserDefaults.standard.set(fakeLast, forKey: key)
        let existing = IngestSupport.existingSourceRefs(context, source: "Wallet")
        let added = await sync(context: context, addresses: addresses, existing: existing)
        return "\(position.token0Symbol)/\(position.token1Symbol) #\(position.tokenId): fakeLast=\(fakeLast) live=\(position.inRange ? "in-range" : "out-of-range") landed=\(added)"
    }
    #endif
}

private extension String {
    /// Left-pads a hex nibble string (no `0x`) to a full 32-byte ABI word.
    func leftPadded64() -> String {
        count >= 64 ? String(suffix(64)) : String(repeating: "0", count: 64 - count) + self
    }
}
