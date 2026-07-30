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

    private static func accountData(pool: Pool, address: String) async -> AccountData? {
        await cache.value(key: "\(pool.network)|\(address.lowercased())", ttl: 60) {
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
    static func positions(addresses: [String]) async -> [Position] {
        guard !addresses.isEmpty else { return [] }
        let active = Set(WalletChainStore.activeNetworkIDs())
        var out: [Position] = []
        for pool in pools where active.contains(pool.network) {
            for address in addresses {
                guard let data = await accountData(pool: pool, address: address),
                      data.totalCollateralUSD > 0 else { continue }
                out.append(Position(network: pool.network, address: address,
                                    protocolName: pool.protocolName,
                                    totalCollateralUSD: data.totalCollateralUSD,
                                    totalDebtUSD: data.totalDebtUSD,
                                    healthFactor: data.healthFactor))
            }
        }
        return out
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
