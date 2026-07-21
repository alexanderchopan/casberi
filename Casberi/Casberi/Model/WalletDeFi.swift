import Foundation
import SwiftData

/// Aave V3 positions (2026-07-20) — a wallet's collateral/debt/health factor
/// on Aave, read straight off its `Pool` contract (`getUserAccountData`), the
/// same measured-keyless-RPC shape every other wallet-adjacent read here
/// uses. Modeled in TWO parts, deliberately not as one:
///
/// (1) `positions(addresses:)` is LIVE STATE, like the holdings treemap — a
///     number that changes constantly and is read fresh whenever the Wallet
///     screen wants it, never landed as a thing and never persisted beyond
///     the screen's own state.
/// (2) `sync(...)` is a DISCRETE ALERT, like an approval or a 7702
///     delegation change — it rides `WalletIngest.refresh` and lands a thing
///     only when a wallet's health factor crosses INTO risk (below 1.5, the
///     standard liquidation-warning line), tracked per (wallet, chain) so a
///     healthy position, or one already sitting in the risk bucket, never
///     re-lands.
///
/// Pool addresses and the `getUserAccountData` selector/return shape were
/// verified live (Aave's own docs + `bgd-labs/aave-address-book` + each
/// chain's own explorer, cross-checked against `GenericLogic.sol`'s
/// `healthFactor = ... .wadDiv(totalDebtInBaseCurrency)` for the WAD (1e18)
/// scale, distinct from the base-currency's own 1e8 units) — 2026-07-20,
/// don't re-derive without re-measuring.
enum WalletDeFi {

    private struct Pool {
        let network: String
        let address: String
    }
    /// Arbitrum/Optimism/Polygon share one address (the original March-2022
    /// multi-chain V3 launch, one deployer); Ethereum and Base were deployed
    /// separately later and have their own.
    private static let pools: [Pool] = [
        Pool(network: "eth-mainnet",   address: "0x87870bca3f3fd6335c3f4ce8392d69350b4fa4e2"),
        Pool(network: "base-mainnet",  address: "0xa238dd80c259a72e81d7e4664a9801593f98d1c5"),
        Pool(network: "arb-mainnet",   address: "0x794a61358d6845594f94dc1db02a252b5b4814ad"),
        Pool(network: "opt-mainnet",   address: "0x794a61358d6845594f94dc1db02a252b5b4814ad"),
        Pool(network: "matic-mainnet", address: "0x794a61358d6845594f94dc1db02a252b5b4814ad"),
    ]

    /// The health-factor line below which Aave positions commonly get
    /// flagged as at risk of liquidation — a widely used warning threshold,
    /// not Aave's own liquidation point (that's 1.0; 1.5 is the standing
    /// margin worth a heads-up before it gets there).
    private static let riskThreshold = 1.5

    struct Position {
        let network: String
        let address: String
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
                                    totalCollateralUSD: data.totalCollateralUSD,
                                    totalDebtUSD: data.totalDebtUSD,
                                    healthFactor: data.healthFactor))
            }
        }
        return out
    }

    private static func riskKey(_ network: String, _ address: String) -> String {
        "wallet.defi.aave.risk.\(network).\(address.lowercased())"
    }

    /// Reads each watched wallet's Aave health factor per active EVM chain
    /// and lands a thing only on a NEW crossing into risk (below
    /// `riskThreshold`) — a healthy position, or one already sitting in the
    /// risk bucket from a prior pass, never re-lands. Rides
    /// `WalletIngest.refresh` inside its running guard, like the other arms.
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
                let key = riskKey(pool.network, address)
                guard data.totalCollateralUSD > 0, let hf = data.healthFactor else {
                    defaults.set("safe", forKey: key)
                    continue
                }
                let bucket = hf < riskThreshold ? "at-risk" : "safe"
                let lastBucket = defaults.string(forKey: key)
                defaults.set(bucket, forKey: key)
                guard bucket == "at-risk", lastBucket != "at-risk" else { continue }
                let ref = "wallet:defi:aave:\(pool.network):\(address.lowercased()):"
                    + String(Int(Date.now.timeIntervalSince1970))
                guard !existing.contains(ref) else { continue }
                let chainName = WalletIngest.displayName(forNetwork: pool.network) ?? pool.network
                let title = String(localized:
                    "Your Aave position on \(chainName) is close to liquidation — health factor \(WalletIngest.format(hf))")
                // Aave's own app, not a chain-specific deep link (unverified
                // query-param format) — a working door beats a guessed one.
                let thing = Thing(kind: .transaction, title: title,
                                  content: "https://app.aave.com/", source: "Wallet",
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
    /// watched wallet across every active Aave-supported chain (a position
    /// or its absence, never a fabricated zero row).
    @MainActor
    static func probe() async -> String {
        let watched = WalletStore.shared.addresses.map(\.address)
        let addresses = await WalletIngest.resolvedAddresses(watched).filter { ENS.isHexAddress($0) }
        guard !addresses.isEmpty else { return "no EVM wallets watched" }
        let found = await positions(addresses: addresses)
        guard !found.isEmpty else { return "no Aave positions found" }
        return found.map { p in
            let chainName = WalletIngest.displayName(forNetwork: p.network) ?? p.network
            let hfLine = p.healthFactor.map { "hf=\(WalletIngest.format($0))" } ?? "no debt"
            return "\(WalletStore.shortAddress(p.address)) \(chainName): collateral=$\(WalletIngest.format(p.totalCollateralUSD)) debt=$\(WalletIngest.format(p.totalDebtUSD)) \(hfLine)"
        }.joined(separator: " | ")
    }
}
