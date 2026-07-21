import Foundation

/// Gas spent (2026-07-20) — a forward-only running total per (wallet,
/// chain), in the chain's own native units. Rides `WalletIngest.refresh`'s
/// existing per-leg walk: for each NEW outgoing transaction this wallet
/// initiated this pass (deduped by hash — a batch tx can produce several
/// legs but pays gas once), one `eth_getTransactionReceipt` on the SAME
/// measured public hosts `WalletApprovals` already reads
/// (`gasUsed × effectiveGasPrice`). Forward-only like every wallet cursor
/// here: "gas spent since you started watching", stated honestly — a fresh
/// watch can't actually know a wallet's lifetime total, so it never claims to.
enum WalletGas {

    private static func totalKey(_ network: String, _ address: String) -> String {
        "wallet.gas.\(network).\(address.lowercased())"
    }

    /// Unwatching wipes the running total too — the same "re-watching starts
    /// honest, at zero" rule every sibling cursor obeys.
    static func clearTotals(address: String) {
        for network in WalletChainStore.allNetworkIDs {
            UserDefaults.standard.removeObject(forKey: totalKey(network, address))
        }
    }

    /// One (network, address, hash) needing a receipt read this pass.
    struct Job {
        let network: String
        let address: String
        let hash: String
    }

    /// Fetches each job's receipt and adds its fee to the running total —
    /// bounded concurrency, the same public-RPC courtesy every other reader
    /// here already practices.
    static func accumulate(jobs: [Job]) async {
        guard !jobs.isEmpty else { return }
        _ = await IngestSupport.boundedGather(jobs, maxConcurrent: 4) { job in
            await addFee(job)
        }
    }

    private static func addFee(_ job: Job) async {
        guard let receipt = await WalletApprovals.rpcRead(
                network: job.network, method: "eth_getTransactionReceipt",
                params: [job.hash]) as? [String: Any],
              let gasUsedHex = receipt["gasUsed"] as? String,
              // `effectiveGasPrice` is the post-EIP-1559 field; an older node
              // or a pre-1559 chain may only answer the legacy `gasPrice`.
              let priceHex = (receipt["effectiveGasPrice"] as? String) ?? (receipt["gasPrice"] as? String)
        else { return }
        let fee = WalletIngest.hexToDouble(gasUsedHex) * WalletIngest.hexToDouble(priceHex) / 1e18
        guard fee > 0, fee.isFinite else { return }
        let key = totalKey(job.network, job.address)
        let running = UserDefaults.standard.double(forKey: key)
        UserDefaults.standard.set(running + fee, forKey: key)
    }

    /// The running total for one watched address, per chain's native symbol
    /// — empty for a wallet that hasn't initiated anything since being
    /// watched (never a fabricated zero row for a chain with no story).
    static func totals(address: String) -> [(symbol: String, amount: Double)] {
        WalletChainStore.allNetworkIDs.compactMap { network in
            let amount = UserDefaults.standard.double(forKey: totalKey(network, address))
            guard amount > 0, let symbol = WalletIngest.nativeSymbol(forNetwork: network) else { return nil }
            return (symbol, amount)
        }
    }

    /// The wrapped-native contract per chain — WETH/WMATIC share the native
    /// coin's price, so pricing the wrapped token IS pricing gas (the same
    /// trick `SolanaActivity.solPrice` plays with wrapped SOL, since
    /// Alchemy's Prices API has no "native coin" concept, only priced token
    /// addresses). Arbitrum's WETH is its own separate deployment — verified
    /// on Arbiscan (2026-07-20), NOT the OP-stack predeploy address Base and
    /// Optimism share (`WalletIngest.knownContracts` only lists that shared
    /// one, which is why Arbitrum needs its own entry here).
    private static let wrappedNative: [String: String] = [
        "eth-mainnet":   "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2",
        "base-mainnet":  "0x4200000000000000000000000000000000000006",
        "arb-mainnet":   "0x82af49447d8a07e3bd95bd0d56f35241523fbab1",
        "opt-mainnet":   "0x4200000000000000000000000000000000000006",
        "matic-mainnet": "0x0d500b1d8e8ef31e21c99d1db9a6444d3adf1270",
    ]

    @MainActor private static var priceCache: [String: (price: Double, at: Date)] = [:]

    /// Cached 15 minutes, same as `SolanaActivity.solPrice` — a running gas
    /// total doesn't need tick-accurate pricing, and this must not cost a
    /// call per wallet per refresh.
    @MainActor
    private static func nativePrice(network: String) async -> Double? {
        if let cached = priceCache[network], cached.at.timeIntervalSinceNow > -900 { return cached.price }
        guard let contract = wrappedNative[network] else { return nil }
        let body: [String: Any] = ["addresses": [["network": network, "address": contract]]]
        guard let root = await IngestSupport.postJSON(
                "https://api.g.alchemy.com/prices/v1/\(IngestSupport.alchemyKey)/tokens/by-address",
                body: body) as? [String: Any],
              let data = root["data"] as? [[String: Any]],
              let prices = data.first?["prices"] as? [[String: Any]],
              let raw = prices.first?["value"],
              let price = (raw as? Double) ?? Double(raw as? String ?? "")
        else { return nil }
        priceCache[network] = (price, .now)
        return price
    }

    /// The running total in USD, summed across chains — nil when nothing's
    /// been spent yet (never a fabricated $0 line where there's no story).
    @MainActor
    static func totalUSD(address: String) async -> Double? {
        var sum = 0.0
        var any = false
        for network in WalletChainStore.allNetworkIDs {
            let amount = UserDefaults.standard.double(forKey: totalKey(network, address))
            guard amount > 0, let price = await nativePrice(network: network) else { continue }
            sum += amount * price
            any = true
        }
        return any ? sum : nil
    }

    /// `-gasSpentProbe YES` — NSLogs the running total per watched wallet,
    /// per chain and combined USD.
    @MainActor
    static func probe() async -> String {
        let watched = WalletStore.shared.addresses
        guard !watched.isEmpty else { return "no wallets watched" }
        var lines: [String] = []
        for w in watched {
            let perChain = totals(address: w.address)
                .map { "\(WalletIngest.format($0.amount)) \($0.symbol)" }
                .joined(separator: ", ")
            let usd = await totalUSD(address: w.address)
            lines.append("\(w.short): \(perChain.isEmpty ? "none yet" : perChain)"
                + (usd.map { " (~$\(WalletIngest.format($0)))" } ?? ""))
        }
        return lines.joined(separator: " | ")
    }
}
