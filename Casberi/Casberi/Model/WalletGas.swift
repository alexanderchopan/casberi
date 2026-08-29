import Foundation
import SwiftData

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
            UserDefaults.standard.removeObject(forKey: sponsoredKey(network, address))
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
        let whole = WalletIngest.hexToDouble(gasUsedHex) * WalletIngest.hexToDouble(priceHex) / 1e18
        // WHO ACTUALLY PAID (2026-08-03, prd §293). This used to charge the
        // wallet `whole` unconditionally, which is right for an EOA and wrong
        // for every smart account: a 4337 bundle's receipt covers several
        // people's operations, and a Safe's is paid by the owner who executed
        // it. `WalletUserOps` reads the receipt's OWN logs — already in this
        // reply, no extra request — and answers what it really cost us.
        switch WalletUserOps.attribution(logs: (receipt["logs"] as? [[String: Any]]) ?? [],
                                         from: receipt["from"] as? String,
                                         wallet: job.address, fallbackNative: whole) {
        case .paid(let native):
            add(native, to: totalKey(job.network, job.address))
        case .sponsored(_, let native):
            // Zero into the gas total — the wallet paid nothing — and into the
            // SPONSORED total, which is the fact worth having: somebody else
            // paying for you is money moving, and the doctrine's standing
            // exception covers it.
            add(native, to: sponsoredKey(job.network, job.address))
        case .notYours:
            break
        }
    }

    private static func add(_ amount: Double, to key: String) {
        guard amount > 0, amount.isFinite else { return }
        UserDefaults.standard.set(UserDefaults.standard.double(forKey: key) + amount, forKey: key)
    }

    private static func sponsoredKey(_ network: String, _ address: String) -> String {
        "wallet.gas.sponsored.\(network).\(address.lowercased())"
    }

    /// What somebody else paid on this wallet's behalf, per chain's native
    /// symbol (2026-08-03) — the mirror of `totals`, and empty for a wallet
    /// nobody has sponsored, never a fabricated zero row.
    static func sponsoredTotals(address: String) -> [(symbol: String, amount: Double)] {
        WalletChainStore.allNetworkIDs.compactMap { network in
            let amount = UserDefaults.standard.double(forKey: sponsoredKey(network, address))
            guard amount > 0, let symbol = WalletIngest.nativeSymbol(forNetwork: network) else { return nil }
            return (symbol, amount)
        }
    }

    /// The sponsored running total across the given addresses, in USD — nil
    /// when nobody has been sponsored, so the ask can stay silent rather than
    /// print "$0 sponsored" at everyone who has never used a paymaster.
    @MainActor
    static func sponsoredUSD(addresses: [String]) async -> Double? {
        var sum = 0.0
        var any = false
        for address in addresses {
            for network in WalletChainStore.allNetworkIDs {
                let amount = UserDefaults.standard.double(forKey: sponsoredKey(network, address))
                guard amount > 0, let price = await nativePrice(network: network) else { continue }
                sum += amount * price
                any = true
            }
        }
        return any ? sum : nil
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
        // WHYPE / WMON, both read back off their own chain via `symbol()`
        // (2026-08-28) — see `WalletIngest.wrappedNativeContract`, which
        // carries the same two addresses for the chart route. Kept spelled out
        // twice rather than shared: that table is the CHART's route and this
        // one is the FEE's price, and folding them would tie a gas total to a
        // Dexscreener slug it has nothing to do with.
        "hyperliquid-mainnet": "0x5555555555555555555555555555555555555555",
        "monad-mainnet": "0x3bd359c1119da7da1d913d1c4d2b7c461115433a",
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

    /// The running total across ALL given addresses, summed in USD
    /// (2026-07-20, for the "what have I spent on gas" ask) — nil when NONE
    /// of them have spent anything yet, never a fabricated $0.
    @MainActor
    static func totalUSD(addresses: [String]) async -> Double? {
        var sum = 0.0
        var any = false
        for address in addresses {
            if let usd = await totalUSD(address: address) { sum += usd; any = true }
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
            let sponsored = sponsoredTotals(address: w.address)
                .map { "\(WalletIngest.format($0.amount)) \($0.symbol)" }
                .joined(separator: ", ")
            lines.append("\(w.short): \(perChain.isEmpty ? "none yet" : perChain)"
                + (usd.map { " (~$\(WalletIngest.format($0)))" } ?? "")
                + (sponsored.isEmpty ? "" : " | sponsored: \(sponsored)"))
        }
        return lines.joined(separator: " | ")
    }

    /// `-userOpProbe YES` (2026-08-03, prd §293) — re-reads the receipts
    /// behind this wallet's recent outgoing transactions and reports the
    /// attribution the gas total now uses, one line each.
    ///
    /// It reads LANDED transaction things rather than re-walking the chain:
    /// the point is to check the rule against transactions this app has
    /// actually seen, and a fresh transfer sweep would cost Alchemy credits to
    /// answer a question about arithmetic. Spends one `eth_getTransactionReceipt`
    /// per row, on the keyless public hosts, and writes NOTHING — the running
    /// totals are untouched, so a probe can't inflate them.
    @MainActor
    static func attributionProbeLines(context: ModelContext) async -> [String] {
        let watched = WalletStore.shared.addresses.map(\.address)
        let resolved = await WalletIngest.resolvedAddresses(watched).filter { ENS.isHexAddress($0) }
        guard !resolved.isEmpty else { return ["no EVM wallets watched"] }
        var descriptor = FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == "Wallet" },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        descriptor.fetchLimit = 200
        let things = ((try? context.fetch(descriptor)) ?? []).filter(\.isLive)

        var lines: [String] = []
        var seen = Set<String>()
        for thing in things {
            // "wallet:tx:<network>:<hash>" and friends — only a ref carrying a
            // real transaction hash can be re-read.
            guard let ref = thing.sourceRef else { continue }
            let parts = ref.split(separator: ":").map(String.init)
            guard parts.count >= 4, parts[0] == "wallet",
                  let hash = parts.last, hash.hasPrefix("0x"), hash.count == 66,
                  let owner = thing.walletAddress,
                  resolved.contains(where: { WalletWatch.sameAddress($0, owner) }),
                  seen.insert(hash).inserted else { continue }
            let network = parts[2]
            guard let receipt = await WalletApprovals.rpcRead(
                    network: network, method: "eth_getTransactionReceipt",
                    params: [hash]) as? [String: Any] else {
                lines.append("\(WalletStore.shortAddress(hash)) \(network): receipt unreadable")
                continue
            }
            let logs = (receipt["logs"] as? [[String: Any]]) ?? []
            let gasUsed = WalletIngest.hexToDouble((receipt["gasUsed"] as? String) ?? "0x0")
            let price = WalletIngest.hexToDouble(
                (receipt["effectiveGasPrice"] as? String) ?? (receipt["gasPrice"] as? String) ?? "0x0")
            let whole = gasUsed * price / 1e18
            let verdict: String
            switch WalletUserOps.attribution(logs: logs, from: receipt["from"] as? String,
                                             wallet: owner, fallbackNative: whole) {
            case .paid(let n):
                verdict = "PAID \(WalletIngest.format(n))"
                    + (abs(n - whole) > 1e-18 ? " (receipt said \(WalletIngest.format(whole)))" : "")
            case .sponsored(let paymaster, let n):
                verdict = "SPONSORED by \(WalletStore.shortAddress(paymaster))"
                    + " — they paid \(WalletIngest.format(n)), you paid 0"
                    + " (old behaviour charged you \(WalletIngest.format(whole)))"
            case .notYours:
                verdict = "NOT YOURS — someone else sent it"
                    + " (old behaviour charged you \(WalletIngest.format(whole)))"
            }
            let unknown = WalletUserOps.unknownEmitters(logs: logs)
            lines.append("\(WalletStore.shortAddress(hash)) \(network): \(verdict)"
                + (unknown.isEmpty ? "" : " | UNKNOWN EntryPoint: \(unknown.joined(separator: ","))"))
            if lines.count >= 25 { break }
        }
        return lines.isEmpty ? ["no re-readable wallet transactions landed yet"] : lines
    }
}
