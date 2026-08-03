import Foundation
import SwiftData

/// Aave V3 (+ Spark, 2026-07-30) positions — a wallet's collateral/debt/
/// health factor on either lending pool, read straight off its `Pool`
/// contract (`getUserAccountData`), the same measured-keyless-RPC shape
/// every other wallet-adjacent read here uses. Modeled in TWO parts,
/// deliberately not as one:
///
/// (1) `positions(addresses:)` is LIVE STATE, like the holdings treemap — a
///     number that changes constantly and is read fresh whenever the Wallet
///     screen wants it, never landed as a thing and never persisted beyond
///     the screen's own state.
/// (2) `sync(...)` is a DISCRETE ALERT, like an approval or a 7702
///     delegation change — it rides `WalletIngest.refresh` and lands a thing
///     only when a wallet's health factor crosses INTO risk (below 1.5, the
///     standard liquidation-warning line), tracked per (wallet, chain,
///     protocol) so a healthy position, or one already sitting in the risk
///     bucket, never re-lands.
///
/// Pool addresses and the `getUserAccountData` selector/return shape were
/// verified live (Aave's own docs + `bgd-labs/aave-address-book` + each
/// chain's own explorer, cross-checked against `GenericLogic.sol`'s
/// `healthFactor = ... .wadDiv(totalDebtInBaseCurrency)` for the WAD (1e18)
/// scale, distinct from the base-currency's own 1e8 units) — 2026-07-20,
/// don't re-derive without re-measuring.
///
/// Spark (SparkLend) is a straight Aave V3 fork — same selector, same
/// six-word return layout, same 1e8/1e18 scale — added it as a second `Pool`
/// row rather than a new type. Its ONE mainnet market address is
/// `sparkdotfi/spark-address-registry`'s `SparkLend.POOL`
/// (0xC13e...BE987); MEASURED live 2026-07-30 by pulling ~40 real borrower
/// addresses out of the Pool's own recent event logs (no subgraph needed)
/// and decoding `getUserAccountData` for each — every one came back a sane
/// collateral/debt/health-factor triple ($20k–$180M collateral, HF
/// 1.03–9x), confirming the word layout is byte-identical to Aave's. Spark
/// ALSO runs a second market on Gnosis Chain (`Gnosis.sol.POOL`,
/// 0x2Dae5307c5E3FD1CF5A72Cb6F698f915860607e0) — deliberately NOT added:
/// Gnosis Chain isn't one of `WalletChainStore`'s five toggleable networks
/// or `WalletApprovals`'s RPC table at all (the only precedent, `GnosisPay
/// Bridge`, carries its own private RPC host list because of exactly this
/// gap), so wiring it in is a new chain-support decision, not a pool-table
/// addition — do that as its own piece of work, not folded in here. Base
/// has NO SparkLend Pool (checked `Base.sol` — Spark's Base footprint is
/// its PSM/vaults/Fluid integration, not a lending market), so it's simply
/// absent, not skipped.
enum WalletDeFi {

    /// Which watched wallets actually hold an Aave position — the catalog
    /// seat's gate (2026-07-30). See `WalletSeatEvidence` for why a seat is
    /// evidence-gated rather than lit for every watched wallet.
    ///
    /// Aave ONLY, not Spark: this file reads both (Spark is a straight Aave
    /// V3 fork on the same selector), but they are different products and a
    /// Spark position is not evidence that someone uses Aave. Spark has no
    /// catalog seat yet — when it gets one it gets its own mark beside this,
    /// keyed off the same `protocolName` the positions already carry.
    static let evidence = WalletSeatEvidence("aave.accounts")

    /// Wallet unwatch takes the seat's mark with it (`WalletSeatEvidence`
    /// rule 2). The risk buckets are cleared by `clearDelegation`'s sibling
    /// path already; this is only the seat's own record.
    static func clearSeatEvidence(address: String) {
        evidence.forget(address)
    }

    private struct Pool {
        let network: String
        let address: String
        let protocolName: String
        /// Where "Aave position on Ethereum" or "Your Spark position…" opens
        /// when tapped — each protocol's own app, never a chain-specific
        /// deep link (unverified query-param format; a working door beats a
        /// guessed one).
        let appURL: String
    }
    /// Arbitrum/Optimism/Polygon share one address (the original March-2022
    /// multi-chain V3 launch, one deployer); Ethereum and Base were deployed
    /// separately later and have their own. Spark rides Ethereum only (see
    /// the type doc above).
    private static let pools: [Pool] = [
        Pool(network: "eth-mainnet",   address: "0x87870bca3f3fd6335c3f4ce8392d69350b4fa4e2",
             protocolName: "Aave", appURL: "https://app.aave.com/"),
        Pool(network: "base-mainnet",  address: "0xa238dd80c259a72e81d7e4664a9801593f98d1c5",
             protocolName: "Aave", appURL: "https://app.aave.com/"),
        Pool(network: "arb-mainnet",   address: "0x794a61358d6845594f94dc1db02a252b5b4814ad",
             protocolName: "Aave", appURL: "https://app.aave.com/"),
        Pool(network: "opt-mainnet",   address: "0x794a61358d6845594f94dc1db02a252b5b4814ad",
             protocolName: "Aave", appURL: "https://app.aave.com/"),
        Pool(network: "matic-mainnet", address: "0x794a61358d6845594f94dc1db02a252b5b4814ad",
             protocolName: "Aave", appURL: "https://app.aave.com/"),
        Pool(network: "eth-mainnet",   address: "0xc13e21b648a5ee794902342038ff3adab66be987",
             protocolName: "Spark", appURL: "https://app.spark.fi/"),
    ]

    /// The health-factor line below which a position (Aave or Spark) gets
    /// flagged as at risk of liquidation. `DeFiRisk.floor` since 2026-07-25 —
    /// this file,
    /// `MorphoDeFi`, `WalletWarnings` and the brief's lede each held their
    /// own copy of the same 1.5, and a threshold that decides whether the app
    /// warns you must not be able to disagree with itself.
    private static var riskThreshold: Double { DeFiRisk.floor }

    struct Position: Equatable {
        let network: String
        let address: String
        /// "Aave" or "Spark" — which pool this position lives on, since both
        /// now share this one type.
        let protocolName: String
        let totalCollateralUSD: Double
        let totalDebtUSD: Double
        /// nil means no debt (Aave's own `type(uint256).max` sentinel) —
        /// not "about to liquidate"; there's nothing to liquidate.
        let healthFactor: Double?
    }

    private struct AccountData {
        let totalCollateralUSD: Double
        let totalDebtUSD: Double
        let healthFactor: Double?
    }

    /// Coalesced (2026-07-20) — three independent callers (`WalletIngest
    /// .refresh`'s sync arm, the Wallet screen's live state, the Aave kept
    /// ask) now read this exact primitive every foreground pass; a 60s TTL
    /// (roughly how fast a health factor actually moves) collapses them to
    /// one real network read.
    private static let cache = CoalescingCache<AccountData>()

    /// The key carries the POOL, not just the chain (fixed 2026-08-03). It was
    /// `network|address`, which was correct while Aave was the only pool — and
    /// silently wrong the day Spark landed (2026-07-30) as a second pool on
    /// eth-mainnet. Both pools share that network, so both shared one cache
    /// entry: whichever read ran first won the 60s slot and the other was
    /// served ITS numbers, then labelled with its own `protocolName`. That
    /// reports a Spark position a wallet may not hold, wearing an Aave health
    /// factor — a fake status (§83) in the one place the app warns about
    /// liquidation. `riskKey` right below already learned exactly this lesson
    /// ("Aave and Spark both run on Ethereum, so the protocol must be in the
    /// key"); the cache key predates Spark and never caught up.
    private static func accountData(pool: Pool, address: String) async -> AccountData? {
        await cache.value(key: "\(pool.network)|\(pool.address)|\(address.lowercased())", ttl: 60) {
            await fetchAccountData(pool: pool, address: address)
        }
    }

    /// One `eth_call` to `getUserAccountData(address)` (selector `0xbf92857c`),
    /// decoding only the three of its six returned words this feature needs
    /// (collateral, debt, health factor) — the other three (available
    /// borrows, liquidation threshold, LTV) aren't read, so their basis-point
    /// scale doesn't need verifying here.
    private static func fetchAccountData(pool: Pool, address: String) async -> AccountData? {
        let calldata = "0xbf92857c" + pad(address)
        guard let hex = await WalletApprovals.rpcRead(
                network: pool.network, method: "eth_call",
                params: [["to": pool.address, "data": calldata], "latest"]) as? String
        else { return nil }
        var s = hex.lowercased(); if s.hasPrefix("0x") { s.removeFirst(2) }
        guard s.count >= 64 * 6 else { return nil }
        func word(_ i: Int) -> Double {
            let start = s.index(s.startIndex, offsetBy: i * 64)
            let end = s.index(start, offsetBy: 64)
            return WalletIngest.hexToDouble("0x" + s[start..<end])
        }
        let totalCollateralUSD = word(0) / 1e8
        let totalDebtUSD = word(1) / 1e8
        let hfRaw = word(5)
        // type(uint256).max (huge, not a real ratio) means "no debt" — never
        // read as an at-risk number.
        let healthFactor: Double? = (totalDebtUSD > 0 && hfRaw < 1e30) ? hfRaw / 1e18 : nil
        return AccountData(totalCollateralUSD: totalCollateralUSD, totalDebtUSD: totalDebtUSD,
                           healthFactor: healthFactor)
    }

    private static func pad(_ address: String) -> String {
        String(repeating: "0", count: 24) + address.dropFirst(2).lowercased()
    }

    /// Every Aave position across the given addresses and active EVM chains
    /// — live state for the Wallet screen, not landed as things. Skips a
    /// (wallet, chain) with no collateral at all (nothing to show).
    ///
    /// CONCURRENT PER NETWORK (2026-08-03), and where the split falls is the
    /// whole point. This was one flat nested loop awaiting every (pool,
    /// address) pair in turn — six pools against five watched wallets is
    /// **thirty sequential `eth_call`s** before it returns a single position,
    /// each one able to spend `IngestSupport`'s 15s request timeout across a
    /// chain's host fallbacks. That made it the slowest read in the Today
    /// brief by a wide margin (see `TodayBrief.compose`, which awaits it for
    /// the lede's risk rung), and the brief's load time was mostly this.
    ///
    /// Networks now run concurrently while each network's own calls stay
    /// SEQUENTIAL, rather than firing all thirty at once. That is deliberate,
    /// and it is the measured lesson from `AerodromeDeFi`: these are public
    /// RPC hosts, `mainnet.base.org` is the ONLY host `WalletApprovals`
    /// carries for base-mainnet, and an unpaced burst against it 429s — five
    /// sequential `eth_call`s there needed a 200ms pacer. Per-network chains
    /// leave the per-host request rate exactly where it is today while paying
    /// the slowest chain instead of the sum of all of them: worst case drops
    /// from (pools × addresses) round trips to (pools-on-the-busiest-network
    /// × addresses) — thirty to ten, since Ethereum is the only network
    /// carrying two pools (Aave and Spark).
    ///
    /// Output order is byte-identical to the old loop's (pool-major,
    /// address-minor): each job is indexed before the split and reassembled
    /// by that index, so no caller can tell this changed except in latency.
    static func positions(addresses: [String]) async -> [Position] {
        guard !addresses.isEmpty else { return [] }
        let active = Set(WalletChainStore.activeNetworkIDs())
        var byNetwork: [String: [(index: Int, pool: Pool, address: String)]] = [:]
        var jobCount = 0
        for pool in pools where active.contains(pool.network) {
            for address in addresses {
                byNetwork[pool.network, default: []].append((jobCount, pool, address))
                jobCount += 1
            }
        }
        guard jobCount > 0 else { return [] }

        var slots = [Position?](repeating: nil, count: jobCount)
        await withTaskGroup(of: [(Int, Position)].self) { group in
            for chain in byNetwork.values {
                group.addTask {
                    var found: [(Int, Position)] = []
                    for job in chain {
                        guard let data = await accountData(pool: job.pool, address: job.address),
                              data.totalCollateralUSD > 0 else { continue }
                        found.append((job.index,
                                      Position(network: job.pool.network, address: job.address,
                                               protocolName: job.pool.protocolName,
                                               totalCollateralUSD: data.totalCollateralUSD,
                                               totalDebtUSD: data.totalDebtUSD,
                                               healthFactor: data.healthFactor)))
                    }
                    return found
                }
            }
            for await chainResults in group {
                for (index, position) in chainResults { slots[index] = position }
            }
        }
        return slots.compactMap { $0 }
    }

    private static func riskKey(_ protocolName: String, _ network: String, _ address: String) -> String {
        "wallet.defi.\(protocolName.lowercased()).risk.\(network).\(address.lowercased())"
    }

    /// Reads each watched wallet's health factor per active EVM chain and
    /// pool, and lands a thing only on a NEW crossing into risk (below
    /// `riskThreshold`) — a healthy position, or one already sitting in the
    /// risk bucket from a prior pass, never re-lands. Rides
    /// `WalletIngest.refresh` inside its running guard, like the other arms.
    /// Keyed by (protocol, chain, wallet) — Aave and Spark both run on
    /// Ethereum, so the protocol must be in the key or one liquidation risk
    /// would silently mask the other's alert (and, before it was, two
    /// `WalletWarning`s sharing an `id` — the ForEach crash class).
    @MainActor
    static func sync(context: ModelContext, addresses: [String], existing: Set<String>) async -> Int {
        guard !addresses.isEmpty else { return 0 }
        let defaults = UserDefaults.standard
        let active = Set(WalletChainStore.activeNetworkIDs())
        var added = 0
        for pool in pools where active.contains(pool.network) {
            for address in addresses {
                // A read failure fails CLOSED (skip entirely, retry next
                // pass) — but no collateral or no debt at all is a REAL,
                // definitive "safe" (nothing left to liquidate), and the
                // bucket must say so: without this reset, a wallet that
                // paid off its debt (healthFactor → nil) keeps its old
                // "at-risk" bucket forever, so reopening a position and
                // crossing back into risk later would never land (caught
                // in review, 2026-07-20 — an ordinary DeFi usage pattern,
                // not an edge case).
                guard let data = await accountData(pool: pool, address: address) else { continue }
                // The catalog seat's evidence mark (2026-07-30) — collateral
                // posted on an Aave pool is proof this wallet lends there.
                // Read off this pass's own account data, so it costs nothing
                // extra; never unstamped once set (`WalletSeatEvidence`'s
                // stamp-never-unstamp rule), so repaying and withdrawing for
                // a month doesn't flap the seat. Spark deliberately excluded
                // — see `evidence`'s own doc.
                if pool.protocolName == "Aave", data.totalCollateralUSD > 0 {
                    evidence.remember(address)
                }
                let key = riskKey(pool.protocolName, pool.network, address)
                guard data.totalCollateralUSD > 0, let hf = data.healthFactor else {
                    defaults.set("safe", forKey: key)
                    continue
                }
                let bucket = hf < riskThreshold ? "at-risk" : "safe"
                let lastBucket = defaults.string(forKey: key)
                defaults.set(bucket, forKey: key)
                guard bucket == "at-risk", lastBucket != "at-risk" else { continue }
                let ref = "wallet:defi:\(pool.protocolName.lowercased()):\(pool.network):\(address.lowercased()):"
                    + String(Int(Date.now.timeIntervalSince1970))
                guard !existing.contains(ref) else { continue }
                let chainName = WalletIngest.displayName(forNetwork: pool.network) ?? pool.network
                let title = String(localized:
                    "Your \(pool.protocolName) position on \(chainName) is close to liquidation — health factor \(WalletIngest.format(hf))")
                let thing = Thing(kind: .transaction, title: title,
                                  content: pool.appURL, source: "Wallet",
                                  sourceRef: ref)
                thing.walletAddress = address
                context.insert(thing)
                SpotlightIndex.index([thing])
                added += 1
            }
        }
        if added > 0 { context.saveHonestly() }
        return added
    }

    /// `-defiProbe YES` — NSLogs collateral/debt/health-factor for every
    /// watched wallet across every active Aave- or Spark-supported chain (a
    /// position or its absence, never a fabricated zero row).
    @MainActor
    static func probe() async -> String {
        let watched = WalletStore.shared.addresses.map(\.address)
        let addresses = await WalletIngest.resolvedAddresses(watched).filter { ENS.isHexAddress($0) }
        guard !addresses.isEmpty else { return "no EVM wallets watched" }
        let found = await positions(addresses: addresses)
        guard !found.isEmpty else { return "no Aave/Spark positions found" }
        return found.map { p in
            let chainName = WalletIngest.displayName(forNetwork: p.network) ?? p.network
            let hfLine = p.healthFactor.map { "hf=\(WalletIngest.format($0))" } ?? "no debt"
            return "[\(p.protocolName)] \(WalletStore.shortAddress(p.address)) \(chainName): collateral=$\(WalletIngest.format(p.totalCollateralUSD)) debt=$\(WalletIngest.format(p.totalDebtUSD)) \(hfLine)"
        }.joined(separator: " | ")
    }
}
