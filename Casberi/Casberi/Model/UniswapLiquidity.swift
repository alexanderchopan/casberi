import Foundation
import SwiftData

/// Uniswap concentrated-liquidity positions, **V3 and V4** (2026-07-30) —
/// parity with `WalletDeFi`/`MorphoDeFi`. Ticks are read straight off the
/// position/pool contracts over the same measured-keyless-public-RPC shape
/// `WalletDeFi` uses, on the SAME five chains Aave/Morpho already read
/// (both versions are deployed on all five, so no new chain-support
/// decision was needed).
///
/// The two versions diverge on ENUMERATION ONLY, and the reason is
/// measured, not assumed:
/// - **V3** is fully keyless. `NonfungiblePositionManager` is
///   ERC721Enumerable, so `balanceOf` → `tokenOfOwnerByIndex` lists a
///   wallet's positions with no key and no indexer.
/// - **V4 cannot be.** Its PositionManager is ERC721 but **NOT**
///   ERC721Enumerable (MEASURED 2026-07-30: `supportsInterface(0x780e9d63)`
///   → false, and `tokenOfOwnerByIndex` reverts), so no on-chain call can
///   list a wallet's positions at all. Scanning `Transfer` logs instead is
///   fine on Ethereum but IMPOSSIBLE on Base, where every keyless host caps
///   `eth_getLogs` far below the ~23M-block backfill required
///   (`mainnet.base.org` 10k, `publicnode` 50k, `1rpc` 50 — all measured).
///   So V4 enumeration rides `ZerionAPI.liquidityPositions`, and the chain
///   supplies the ticks.
///
/// Zerion also supplies the USD VALUE for both versions — the number this
/// file originally declined to compute, since deriving it on-chain needs the
/// sqrt-price/liquidity math the honesty rule wouldn't let us guess at.
/// Zerion already computes it, so it arrives measured rather than derived.
/// Its fee figures were cross-checked against this file's own independent
/// simulated-`collect()` read and agreed TO THE CENT ($47.65 on position
/// #1327831), which is why they're trusted for V4, where no cheap on-chain
/// fee read exists.
///
/// Both versions render as ONE merged list (user ruling 2026-07-30) — a
/// person doesn't think of their LP by protocol version.
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
/// Deliberately NOT attempted: an impermanent-loss / "vs. just holding"
/// number. It needs each position's cost basis across every increase and
/// decrease, and a subtly wrong figure there is worse than none. The
/// Aave-rate-comparison toast is deferred for a related reason — see
/// `clearState`'s doc comment.
///
/// V4 caveats worth knowing before extending this:
/// - **33% of newly-initialized V4 pools carry a HOOK** (measured over 1,245
///   pools in 20k mainnet blocks) — a contract that can override swap and
///   fee behavior. Range is unaffected (tick math belongs to the
///   PoolManager, not the hook), which is exactly why range is what this
///   ships for V4 and an on-chain fee derivation is not.
/// - V4 fee reads have no cheap equivalent of V3's simulated `collect()`:
///   `modifyLiquidities(bytes,uint256)` is an encoded-action entry point,
///   not a callable getter. Hence Zerion for that number.
/// - Zerion's LP list is NOT exhaustive (measured: it returned 2 of a
///   wallet's 3 real V3 positions, omitting a zero-fee out-of-range one).
///   That's why V3 keeps its own complete on-chain enumeration and only
///   borrows Zerion's money; for V4 the incompleteness is accepted, since
///   the alternative is showing nothing at all.
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

    /// Which watched wallets actually hold a Uniswap LP position — the
    /// catalog seat's gate (2026-07-30). See `WalletSeatEvidence` for why a
    /// seat is evidence-gated rather than lit for every watched wallet.
    static let evidence = WalletSeatEvidence("uniswap.accounts")

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
        /// 3 or 4 — the protocol version this position lives in. Both render
        /// as one merged list (user ruling 2026-07-30): a person doesn't
        /// think of their LP by protocol version, and splitting them would
        /// repeat exactly what prd §212 undid for Aave/Morpho.
        let version: Int
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
        /// Uncollected fees, scaled by each token's own decimals. V3 reads
        /// these via a SIMULATED `collect()` (an `eth_call`, never sent) —
        /// the only way to see fees accrued since the position's last
        /// on-chain poke, since `positions()`'s own `tokensOwed` is stale.
        /// V4 has no cheap equivalent (`modifyLiquidities` is an encoded-
        /// action pattern, not a callable getter), so its fee number comes
        /// from Zerion instead and these two stay 0.
        let uncollectedFee0: Double
        let uncollectedFee1: Double
        /// Uncollected fees in USD. V3: priced from the on-chain amounts via
        /// `DefiLlamaPrices`, cross-checked against Zerion to the cent
        /// (2026-07-30). V4: straight from Zerion's `reward` legs.
        let uncollectedFeeUSD: Double?
        /// The position's principal in USD, from Zerion (2026-07-30) — the
        /// number this file's header once declined to compute on-chain,
        /// because doing so needs the sqrt-price/liquidity math the honesty
        /// rule wouldn't let us guess at. Zerion already computes it, so it
        /// arrives measured rather than derived. nil when Zerion didn't
        /// answer or doesn't know this position.
        let valueUSD: Double?

        /// Stable identity across network AND version — V3 and V4 mint
        /// tokenIds from separate counters, so #8472 exists in both and a
        /// bare tokenId would collide in a `ForEach` (the reused-id trap
        /// that traps SwiftUI hard). Also the UserDefaults key shape for the
        /// range bucket and the out-of-range stamp.
        var key: String { "\(network)|\(version)|\(tokenId)" }
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
        // Zerion's LP read, once per wallet — the enumeration for V4 (whose
        // PositionManager isn't ERC721Enumerable, so no on-chain call can
        // list a wallet's positions) and the money for BOTH versions. Keyed
        // "network|version|tokenId" so the V3 arm below can enrich by lookup.
        var zerion: [String: ZerionAPI.LiquidityPosition] = [:]
        for address in addresses {
            guard let found = await ZerionAPI.liquidityPositions(address: address) else { continue }
            for p in found { zerion["\(p.network)|\(p.version)|\(p.tokenId)"] = p }
        }

        for chain in chains {
            for address in addresses {
                // V4 first — enumeration comes from Zerion, ticks from chain.
                book.positions += await v4Positions(chain: chain, owner: address, zerion: zerion)

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
                    let known = zerion["\(chain.network)|3|\(entry.tokenId)"]
                    book.positions.append(Position(
                        network: chain.network, address: address.lowercased(),
                        version: 3, tokenId: entry.tokenId,
                        token0: info.token0, token1: info.token1,
                        token0Symbol: meta0?.symbol ?? "?", token1Symbol: meta1?.symbol ?? "?",
                        feeTier: info.fee, tickLower: info.tickLower, tickUpper: info.tickUpper,
                        currentTick: tick, inRange: inRange,
                        uncollectedFee0: scaled0, uncollectedFee1: scaled1,
                        // The on-chain read stays authoritative for V3 fees
                        // (it's complete and independently verified); Zerion
                        // only fills in when pricing failed.
                        uncollectedFeeUSD: usd ?? known?.feesUSD,
                        valueUSD: known?.valueUSD))
                }
            }
        }
        return book
    }

    // MARK: - Uniswap V4 (2026-07-30)
    //
    // Structurally different from V3 in the one way that matters: V4's
    // PositionManager is ERC721 but NOT ERC721Enumerable (MEASURED —
    // `supportsInterface(0x780e9d63)` returns false and `tokenOfOwnerByIndex`
    // reverts), so `ownedTokenIds`' loop cannot work and NO on-chain call
    // lists a wallet's positions. Zerion supplies the ids; the chain supplies
    // the ticks. Everything else about the feature is shared.
    //
    // The read chain, verified live end-to-end 2026-07-30 against mainnet
    // position #356417:
    //   getPoolAndPositionInfo(tokenId)  → PoolKey + a PACKED PositionInfo
    //   unpack                            → 200b poolId | 24b tickUpper
    //                                       | 24b tickLower | 8b hasSubscriber
    //   keccak256(abi.encode(PoolKey))    → the FULL 32-byte poolId
    //   StateView.getSlot0(poolId)        → the current tick
    // Decoded that position as range [-881100, 881100] against tick 241595.
    //
    // Note keccak is MANDATORY here, unlike V3 where `factory.getPool()` let
    // this file avoid it: the packed info stores only the poolId's top 25
    // bytes and `getSlot0` needs all 32. The derivation is checked against
    // those 25 bytes on every read (see `v4PoolId`), so a wrong PoolKey
    // encoding can never silently read some other pool's price.

    private struct V4Chain {
        let network: String
        let positionManager: String
        let stateView: String
    }
    /// Every address INDEPENDENTLY deployed per chain (unlike V3's shared
    /// deterministic deploy) — all six verified live via `eth_getCode`
    /// returning byte-identical code lengths on all five chains, 2026-07-30.
    private static let v4Chains: [V4Chain] = [
        V4Chain(network: "eth-mainnet",
                positionManager: "0xbd216513d74c8cf14cf4747e6aaa6420ff64ee9e",
                stateView: "0x7ffe42c4a5deea5b0fec41c94c136cf115597227"),
        V4Chain(network: "base-mainnet",
                positionManager: "0x7c5f5a4bbd8fd63184577525326123b519429bdc",
                stateView: "0xa3c0c9b65bad0b08107aa264b0f3db444b867a71"),
        V4Chain(network: "arb-mainnet",
                positionManager: "0xd88f38f930b7952f2db2432cb002e7abbf3dd869",
                stateView: "0x76fd297e2d437cd7f76d50f01afe6160f86e9990"),
        V4Chain(network: "opt-mainnet",
                positionManager: "0x3c3ea4b57a46241e54610e5f022e5c45859a1017",
                stateView: "0xc18a3169788f4f75a170290584eca6395c75ecdb"),
        V4Chain(network: "matic-mainnet",
                positionManager: "0x1ec2ebf4f37e7363fdfe3551602425af0b3ceef9",
                stateView: "0x5ea1bd7974c8a611cbab0bdcafcb1d9cc9b3ba5a"),
    ]

    /// The V4 positions Zerion listed for this wallet on this chain, each
    /// given its live range status from the chain. A position Zerion knows
    /// but whose on-chain read fails is DROPPED, not shown range-less — a
    /// liquidity row whose whole job is "is it earning" must not appear
    /// unable to say.
    private static func v4Positions(chain: Chain, owner: String,
                                    zerion: [String: ZerionAPI.LiquidityPosition])
        async -> [Position] {
        guard let v4 = v4Chains.first(where: { $0.network == chain.network }) else { return [] }
        let mine = zerion.values.filter { $0.network == chain.network && $0.version == 4 }
        guard !mine.isEmpty else { return [] }
        var out: [Position] = []
        for entry in mine {
            guard let info = await v4PositionInfo(v4, tokenId: entry.tokenId),
                  let tick = await v4CurrentTick(v4, poolId: info.poolId)
            else { continue }
            let meta0 = await tokenMeta(chain: chain, contract: info.currency0)
            let meta1 = await tokenMeta(chain: chain, contract: info.currency1)
            out.append(Position(
                network: chain.network, address: owner.lowercased(),
                version: 4, tokenId: entry.tokenId,
                token0: info.currency0, token1: info.currency1,
                // A V4 pool can hold the NATIVE coin (currency 0x0), which has
                // no `symbol()` to call — name it from the chain rather than
                // showing "?" (`tokenMeta` correctly fails on address zero).
                token0Symbol: meta0?.symbol ?? nativeSymbol(chain.network, info.currency0),
                token1Symbol: meta1?.symbol ?? nativeSymbol(chain.network, info.currency1),
                feeTier: info.fee, tickLower: info.tickLower, tickUpper: info.tickUpper,
                currentTick: tick, inRange: info.tickLower <= tick && tick < info.tickUpper,
                // V4 fees ride Zerion — no cheap on-chain equivalent exists
                // (see the Position doc); the two token amounts stay 0 rather
                // than being back-derived from a USD figure.
                uncollectedFee0: 0, uncollectedFee1: 0,
                uncollectedFeeUSD: entry.feesUSD,
                valueUSD: entry.valueUSD))
        }
        return out
    }

    private struct V4Info {
        let currency0: String
        let currency1: String
        let fee: Int
        let tickLower: Int
        let tickUpper: Int
        let poolId: String   // full 32-byte hex, no 0x
    }

    /// `getPoolAndPositionInfo(uint256)` → the PoolKey's five words plus the
    /// packed PositionInfo, with the poolId re-derived and CHECKED against
    /// the 25 bytes the packed value carries.
    private static func v4PositionInfo(_ chain: V4Chain, tokenId: Int) async -> V4Info? {
        guard let hex = await WalletApprovals.rpcRead(
            network: chain.network, method: "eth_call",
            params: [["to": chain.positionManager, "data": "0x7ba03aad" + padUint(tokenId)], "latest"]
        ) as? String else { return nil }
        var s = hex.lowercased(); if s.hasPrefix("0x") { s.removeFirst(2) }
        guard s.count >= 64 * 6 else { return nil }
        func word(_ i: Int) -> String {
            let start = s.index(s.startIndex, offsetBy: i * 64)
            return String(s[start..<s.index(start, offsetBy: 64)])
        }
        let currency0 = "0x" + word(0).suffix(40)
        let currency1 = "0x" + word(1).suffix(40)
        let fee = Int(WalletIngest.hexToDouble("0x" + word(2)))
        let tickSpacing = word(3)
        let hooks = "0x" + word(4).suffix(40)
        // PositionInfo packing, MEASURED against position #356417 (whose real
        // range is [-881100, 881100]): the 64-hex-char word is, from the
        // RIGHT, 2 chars hasSubscriber, 6 chars tickLower, 6 chars tickUpper,
        // then the poolId's top 25 bytes in the leading 50. The two slices
        // below are pinned by that decode — an off-by-one here reads
        // 6753649 instead of -881100 and every range verdict is silently
        // wrong, so do not "tidy" them without re-checking against a real
        // position.
        let packed = word(5)
        let tickLower = hexToSignedInt(String(packed.suffix(8).prefix(6)), bits: 24)
        let tickUpper = hexToSignedInt(String(packed.suffix(14).prefix(6)), bits: 24)
        // keccak256(abi.encode(PoolKey)) — the five words exactly as returned,
        // which is what `abi.encode` of the struct produces.
        let encoded = word(0) + word(1) + word(2) + tickSpacing + word(4)
        guard let bytes = hexBytes(encoded) else { return nil }
        let poolId = Keccak256.hexString(Keccak256.hash(bytes))
        // The derived id must agree with the 25 bytes the position itself
        // carries — otherwise the PoolKey encoding is wrong and `getSlot0`
        // would read a DIFFERENT pool's price and silently mis-report range.
        guard poolId.prefix(50) == packed.prefix(50) else { return nil }
        _ = hooks
        return V4Info(currency0: currency0, currency1: currency1, fee: fee,
                      tickLower: tickLower, tickUpper: tickUpper, poolId: poolId)
    }

    /// `StateView.getSlot0(bytes32)` → the pool's current tick (word 1).
    private static func v4CurrentTick(_ chain: V4Chain, poolId: String) async -> Int? {
        guard let hex = await WalletApprovals.rpcRead(
            network: chain.network, method: "eth_call",
            params: [["to": chain.stateView, "data": "0xc815641c" + poolId], "latest"]
        ) as? String else { return nil }
        var s = hex.lowercased(); if s.hasPrefix("0x") { s.removeFirst(2) }
        guard s.count >= 128 else { return nil }
        return hexToSignedInt(String(s.dropFirst(64).prefix(64)), bits: 24)
    }

    /// A V4 pool may hold the chain's NATIVE coin as `currency0` (address
    /// zero), which answers no `symbol()` call.
    private static func nativeSymbol(_ network: String, _ contract: String) -> String {
        guard Int(contract.dropFirst(2), radix: 16) == 0 else { return "?" }
        return network == "matic-mainnet" ? "POL" : "ETH"
    }

    // MARK: - Range-crossing alert (the WalletDeFi.sync bucket shape)

    /// Both keys carry the VERSION (2026-07-30) — V3 and V4 mint tokenIds
    /// from separate counters, so without it a V4 position could inherit a
    /// same-numbered V3 position's range bucket and either fire a phantom
    /// crossing or swallow a real one.
    private static func rangeKey(_ address: String, _ position: Position) -> String {
        "wallet.defi.uniswap.range.\(address.lowercased()).\(position.key)"
    }
    private static func sinceKey(_ address: String, _ network: String,
                                 _ version: Int, _ tokenId: Int) -> String {
        "uniswap.range.since.\(address.lowercased()).\(network)|\(version)|\(tokenId)"
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
        // The catalog seat's evidence mark (2026-07-30) — an LP position, in
        // range or out, is proof this wallet provides liquidity here. Read
        // off this pass's own `book`, so it costs nothing extra; never
        // unstamped on an empty book (`WalletSeatEvidence`'s
        // stamp-never-unstamp rule), so closing one position for a week
        // doesn't flap the seat.
        for position in book.positions { evidence.remember(position.address) }
        for position in book.positions {
            let key = rangeKey(position.address, position)
            let bucket = position.inRange ? "in-range" : "out-of-range"
            let last = defaults.string(forKey: key)
            defaults.set(bucket, forKey: key)
            let since = sinceKey(position.address, position.network,
                                 position.version, position.tokenId)
            if bucket == "out-of-range", last != "out-of-range" {
                defaults.set(Date.now.timeIntervalSince1970, forKey: since)
            } else if bucket == "in-range" {
                defaults.removeObject(forKey: since)
            }
            guard let last, last != bucket else { continue }   // first sight or unchanged
            let ref = "wallet:defi:uniswap:range:\(position.network):v\(position.version):\(position.tokenId):"
                + String(Int(Date.now.timeIntervalSince1970))
            guard !existing.contains(ref) else { continue }
            let pair = "\(position.token0Symbol)/\(position.token1Symbol)"
            let chainName = WalletIngest.displayName(forNetwork: position.network) ?? position.network
            let title = bucket == "out-of-range"
                ? String(localized: "Your \(pair) position on \(chainName) drifted out of range — it stopped earning fees")
                : String(localized: "Your \(pair) position on \(chainName) is back in range and earning again")
            let thing = Thing(kind: .transaction, title: title,
                              content: positionURL(position),
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
    static func timeOutOfRange(address: String, network: String,
                               version: Int, tokenId: Int) -> String? {
        let key = sinceKey(address, network, version, tokenId)
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
                              // v3 by construction: this sweep only scans the
                              // V3 PositionManager's own events.
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
        // …and the catalog seat's mark, or the seat stays lit for a wallet
        // that's gone (`WalletSeatEvidence` rule 2).
        evidence.forget(address)
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

    /// A hex nibble string (no `0x`, even length) as raw bytes — the input
    /// `Keccak256.hash` takes. nil on odd length or a non-hex character, so
    /// a malformed RPC response fails the poolId derivation cleanly instead
    /// of hashing garbage.
    private static func hexBytes(_ hex: String) -> [UInt8]? {
        guard hex.count % 2 == 0 else { return nil }
        var out: [UInt8] = []
        out.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            out.append(byte)
            index = next
        }
        return out
    }

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

    /// Uniswap's own position page — the route carries the version, so a V4
    /// position must not be linked as `/positions/v3/…` (a door to the wrong
    /// page, or none, is the honesty rule's dead control).
    private static func positionURL(_ position: Position) -> String {
        "https://app.uniswap.org/positions/v\(position.version)/"
            + "\(chainSlug(position.network))/\(position.tokenId)"
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
    /// Uniswap book, V3 AND V4 (pair, version, range status, value, fees) or
    /// the honest miss. A numeric spec ALSO rewinds every activity cursor
    /// that many BLOCKS (not Morpho's days — this rides raw RPC like
    /// Approvals/Peer/GnosisPay) and runs the settled-activity sweep. Pairs
    /// with `-walletAddress`; two live-verified reference wallets
    /// (2026-07-30): `0x7516d4e35a369fc18ddfeec0d69c28112fe13bf0` holds
    /// three real V3 positions including an out-of-range one, and
    /// `0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045` holds V4.
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
                let sinceLine = timeOutOfRange(address: p.address, network: p.network,
                                               version: p.version, tokenId: p.tokenId)
                    .map { " (\($0))" } ?? ""
                let feeLine = p.uncollectedFeeUSD.map { "fees=$\(WalletIngest.format($0))" } ?? "fees=unpriced"
                let valueLine = p.valueUSD.map { "value=$\(WalletIngest.format($0))" } ?? "value=unknown"
                lines.append("\(WalletStore.shortAddress(p.address)) \(chainName) v\(p.version) \(p.token0Symbol)/\(p.token1Symbol) #\(p.tokenId): \(range)\(sinceLine) tick=\(p.currentTick) range=[\(p.tickLower),\(p.tickUpper)] \(valueLine) \(feeLine)")
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
        let key = rangeKey(position.address, position)
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
