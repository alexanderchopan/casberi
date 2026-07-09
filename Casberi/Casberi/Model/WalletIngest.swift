import Foundation
import SwiftData

/// The wallet bridge (2026-07-08) — reads a public wallet's onchain activity
/// (received/sent, tokens in and out) across chains and lands it as things.
/// Powered by Alchemy's Transfers API, called directly from this iPhone: no
/// server. The address is public and read-only — watching one can never trade
/// or move funds. (This replaced the Zerion concept: Zerion's key is server-
/// only by their rules, so it couldn't stay serverless; Alchemy can.)
enum WalletIngest {

    /// Alchemy read-only key, restricted to reads. If it ever leaks, the worst
    /// case is quota use on public data — rotate at dashboard.alchemy.com.
    private static let alchemyKey = "8ilcJd0_tmnF-IPrI3CRl"

    /// The chains we read, and where a tx opens. One `getAssetTransfers` per
    /// direction per chain.
    private struct Chain { let network, explorer, symbol: String }
    private static let chains: [Chain] = [
        Chain(network: "eth-mainnet",  explorer: "https://etherscan.io/tx/",              symbol: "ETH"),
        Chain(network: "base-mainnet", explorer: "https://basescan.org/tx/",              symbol: "ETH"),
        Chain(network: "arb-mainnet",  explorer: "https://arbiscan.io/tx/",               symbol: "ETH"),
        Chain(network: "opt-mainnet",  explorer: "https://optimistic.etherscan.io/tx/",   symbol: "ETH"),
        Chain(network: "matic-mainnet",explorer: "https://polygonscan.com/tx/",           symbol: "MATIC"),
    ]

    @MainActor private static var running = false

    /// Reads recent transfers for every watched address, across chains, and
    /// lands new ones. Returns the new count, or nil when nothing could be
    /// reached at all (offline / bad key).
    @MainActor
    static func refresh(context: ModelContext) async -> Int? {
        let watched = WalletStore.shared.addresses.map(\.address)
        guard !watched.isEmpty, !running else { return watched.isEmpty ? nil : 0 }
        running = true
        defer { running = false }

        // Watched entries can be ENS names; the Transfers API needs hex —
        // resolve first, or nothing ever lands (the bug: a watched name
        // returned empty silently).
        let addresses = await hexAddresses(watched)
        guard !addresses.isEmpty else { return nil }

        let existing = IngestSupport.existingSourceRefs(context)
        var added = 0
        var reachedAny = false

        for address in addresses {
            for chain in chains {
                for received in [true, false] {   // received (to) + sent (from)
                    guard let transfers = await fetch(address: address, chain: chain,
                                                      received: received) else { continue }
                    reachedAny = true
                    for t in transfers {
                        guard let uid = t["uniqueId"] as? String else { continue }
                        let ref = "wallet:\(uid)"
                        guard !existing.contains(ref) else { continue }
                        guard let thing = thing(from: t, chain: chain, received: received,
                                                ref: ref, address: address)
                        else { continue }
                        context.insert(thing)
                        SpotlightIndex.index([thing])
                        added += 1
                    }
                }
            }
        }
        if added > 0 { try? context.save() }
        return reachedAny ? added : nil
    }

    /// Resolves watched entries to hex, dropping any ENS name that won't
    /// resolve (a typo'd name simply lands nothing, honestly).
    private static func hexAddresses(_ raw: [String]) async -> [String] {
        var out: [String] = []
        for a in raw {
            if ENS.isHexAddress(a) { out.append(a) }
            else if let hex = await ENS.resolve(a) { out.append(hex) }
        }
        return out
    }

    private static func fetch(address: String, chain: Chain,
                              received: Bool) async -> [[String: Any]]? {
        let url = "https://\(chain.network).g.alchemy.com/v2/\(alchemyKey)"
        let params: [String: Any] = [
            "fromBlock": "0x0", "toBlock": "latest",
            received ? "toAddress" : "fromAddress": address,
            // "internal" added (2026-07-09): ETH that moves through a
            // contract call — swap proceeds, unwrapped WETH, a DeFi
            // withdrawal — rides an internal transfer, not "external". A
            // wallet whose recent activity is mostly onchain interactions
            // rather than direct sends was showing "connected, nothing
            // landed" because that whole category was unfetched.
            "category": ["external", "internal", "erc20", "erc721", "erc1155"],
            "withMetadata": true, "excludeZeroValue": true,
            "maxCount": "0xa", "order": "desc",
        ]
        let body: [String: Any] = [
            "id": 1, "jsonrpc": "2.0",
            "method": "alchemy_getAssetTransfers", "params": [params],
        ]
        guard let root = await IngestSupport.postJSON(url, body: body) as? [String: Any],
              let result = root["result"] as? [String: Any],
              let transfers = result["transfers"] as? [[String: Any]] else { return nil }
        return transfers
    }

    private static func thing(from t: [String: Any], chain: Chain,
                              received: Bool, ref: String, address: String) -> Thing? {
        guard let hash = t["hash"] as? String else { return nil }
        let asset = (t["asset"] as? String) ?? chain.symbol
        let amount = (t["value"] as? Double).map(format) ?? ""
        let verb = received ? "Received" : "Sent"
        let title = amount.isEmpty ? "\(verb) \(asset)" : "\(verb) \(amount) \(asset)"
        let when = IngestSupport.isoDate((t["metadata"] as? [String: Any])?["blockTimestamp"])
        let thing = Thing(
            kind: .transaction,
            title: title,
            content: chain.explorer + hash,
            source: "Wallet",
            capturedAt: when ?? .now,
            sourceRef: ref
        )
        thing.walletAddress = address
        return thing
    }

    /// One watched wallet's holdings — a label (name or short address) paired
    /// with its top-5-by-value cells ("ETH 34, USDC 12, …").
    struct HoldingsGroup {
        let label: String
        let cells: [String]
    }

    /// A treemap PER watched wallet, sized by USD value — the same TagMap
    /// idiom Home uses. Real, from Alchemy's Portfolio API (balances +
    /// metadata + prices in one call). Unpriced spam tokens have no price and
    /// drop out; the top 5 per wallet are shown. Separate, not combined
    /// (ruling 2026-07-09): two watched addresses are usually two different
    /// purposes (main vs. cold, personal vs. a DAO) and summing them into one
    /// total hid which wallet actually held what.
    @MainActor
    static func holdingsChart(pinnedOnly: Bool = false) async -> [String]? {
        let groups = await topHoldingsByWallet(pinnedOnly: pinnedOnly)
        guard !groups.isEmpty else { return nil }
        let ids = groups.indices.map { "w\($0)" }
        var doc = ["root = Stack([\(ids.joined(separator: ", "))])"]
        for (i, g) in groups.enumerated() {
            doc.append("w\(i) = TagMap(\(q(g.label)), \(q("Holdings by value")), [\(g.cells.joined(separator: ", "))])")
        }
        return doc
    }

    private static func q(_ s: String) -> String {
        "\"\(s.replacingOccurrences(of: "\"", with: "'"))\""
    }

    /// Every watched wallet's holdings, one group per address — for a caller
    /// composing its own document (Home's and Feed's pinned-wallet module)
    /// rather than rendering the Wallet screen's standalone one. A wallet
    /// with nothing priced simply doesn't contribute a group (correct-but-
    /// empty, not a failure) — order follows watch order, the first address leads.
    /// `pinnedOnly` restricts to addresses with their own pin on (Home and
    /// Feed's leading module); the Wallet screen and its own Feed chip show
    /// everything watched regardless of pin (ruling 2026-07-09).
    @MainActor
    static func topHoldingsByWallet(pinnedOnly: Bool = false) async -> [HoldingsGroup] {
        let watched = pinnedOnly
            ? WalletStore.shared.addresses.filter(\.pinnedToHome)
            : WalletStore.shared.addresses
        guard !watched.isEmpty else { return [] }
        // Concurrent, not sequential — three watched wallets waiting on three
        // requests in a row is the difference between a couple seconds and
        // most of an app launch (2026-07-09: separating wallets must not
        // make the pinned module noticeably slower to appear than the old
        // single combined request was).
        let results = await withTaskGroup(of: (Int, HoldingsGroup?).self) { group in
            for (i, entry) in watched.enumerated() {
                group.addTask {
                    guard let hex = await hexAddresses([entry.address]).first,
                          let cells = await holdings(addresses: [hex]) else { return (i, nil) }
                    return (i, HoldingsGroup(label: entry.label.isEmpty ? entry.short : entry.label,
                                             cells: cells))
                }
            }
            var collected: [(Int, HoldingsGroup?)] = []
            for await result in group { collected.append(result) }
            return collected
        }
        return results.sorted { $0.0 < $1.0 }.compactMap(\.1)
    }

    /// The top-5-by-value cells for one or more hex addresses, combined —
    /// the shared fetch/page/aggregate loop both the per-wallet path and
    /// diagnostics call into.
    private static func holdings(addresses: [String]) async -> [String]? {
        guard !addresses.isEmpty else { return nil }
        let networks = chains.map(\.network)
        // network → native symbol, so a chain's own coin (ETH/MATIC) — which
        // the API returns with a null symbol — still names itself.
        let native = Dictionary(uniqueKeysWithValues: chains.map { ($0.network, $0.symbol) })
        let url = "https://api.g.alchemy.com/data/v1/\(alchemyKey)/assets/tokens/by-address"

        var bySymbol: [String: Double] = [:]
        var pageKey: String? = nil
        var reached = false
        // Up to 8 pages (≈800 tokens) — enough to surface a whale's real
        // holdings without unbounded paging; a normal wallet stops after one.
        for _ in 0..<8 {
            var body: [String: Any] = [
                "addresses": addresses.map { ["address": $0, "networks": networks] },
                "withMetadata": true, "withPrices": true,
            ]
            if let pageKey { body["pageKey"] = pageKey }
            guard let root = await IngestSupport.postJSON(url, body: body) as? [String: Any],
                  let data = root["data"] as? [String: Any],
                  let tokens = data["tokens"] as? [[String: Any]] else { break }
            reached = true

            for t in tokens {
                let md = t["tokenMetadata"] as? [String: Any]
                let mdSymbol = (md?["symbol"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                // Native coin has no tokenAddress and no symbol — name it by chain.
                let isNative = (t["tokenAddress"] as? String) == nil
                guard let symbol = mdSymbol ?? (isNative ? native[t["network"] as? String ?? ""] : nil),
                      let balHex = t["tokenBalance"] as? String,
                      let price = firstPrice(t["tokenPrices"]), price > 0 else { continue }
                let decimals = (md?["decimals"] as? Int) ?? 18   // native is always 18
                let amount = hexToDouble(balHex) / pow(10, Double(decimals))
                let usd = amount * price
                if usd >= 1 { bySymbol[clean(symbol), default: 0] += usd }
            }

            guard let next = data["pageKey"] as? String, !next.isEmpty else { break }
            pageKey = next
        }
        guard reached, !bySymbol.isEmpty else { return nil }

        // Top 5 by value; sqrt-scale so a big holding doesn't slice the rest to slivers.
        return bySymbol.sorted { $0.value > $1.value }.prefix(5)
            .map { "\($0.key) \(max(1, Int($0.value.squareRoot() * 10)))" }
    }

    /// A step-by-step trace of the holdings path for DiagnosticsScreen — the
    /// same call `topHoldings` makes, reporting each step's real result so a
    /// screenshot says WHY the treemap is (or isn't) on Home. Distinguishes an
    /// unreachable API from a wallet that simply holds nothing priced (all
    /// airdrop spam) — the latter is correct-but-empty, not a failure.
    @MainActor
    static func holdingsDiagnostic() async -> [String] {
        var out: [String] = []
        let watched = WalletStore.shared.addresses.map(\.address)
        guard !watched.isEmpty else { return ["No watched address"] }
        let addresses = await hexAddresses(watched)
        out.append("Resolved \(addresses.count)/\(watched.count) address(es) to hex")
        guard !addresses.isEmpty else {
            out.append("FAIL address/ENS resolution — nothing to query")
            return out
        }

        let networks = chains.map(\.network)
        let url = "https://api.g.alchemy.com/data/v1/\(alchemyKey)/assets/tokens/by-address"
        let body: [String: Any] = [
            "addresses": addresses.map { ["address": $0, "networks": networks] },
            "withMetadata": true, "withPrices": true,
        ]
        guard let root = await IngestSupport.postJSON(url, body: body) as? [String: Any] else {
            out.append("FAIL Portfolio API unreachable (no 200 JSON) — key or network")
            return out
        }
        guard let data = root["data"] as? [String: Any],
              let tokens = data["tokens"] as? [[String: Any]] else {
            out.append("FAIL Portfolio API returned no data.tokens (unexpected shape)")
            return out
        }
        let priced = tokens.filter { (firstPrice($0["tokenPrices"]) ?? 0) > 0 }.count
        out.append("Tokens returned: \(tokens.count), of which priced: \(priced)")
        let groups = await topHoldingsByWallet()
        if !groups.isEmpty {
            for g in groups {
                out.append("OK \(g.label): \(g.cells.count) cells — \(g.cells.joined(separator: ", "))")
            }
        } else if priced == 0 {
            out.append("Empty (correct): nothing priced held — only unpriced/airdrop tokens")
        } else {
            out.append("FAIL: \(priced) priced token(s) but all under the $1 floor")
        }
        return out
    }

    private static func firstPrice(_ raw: Any?) -> Double? {
        guard let arr = raw as? [[String: Any]], let first = arr.first else { return nil }
        if let s = first["value"] as? String { return Double(s) }
        if let d = first["value"] as? Double { return d }
        return nil
    }

    private static func hexToDouble(_ hex: String) -> Double {
        var s = hex.lowercased(); if s.hasPrefix("0x") { s.removeFirst(2) }
        var v = 0.0
        for c in s { guard let d = c.hexDigitValue else { return v }; v = v * 16 + Double(d) }
        return v
    }

    private static func clean(_ symbol: String) -> String {
        let up = symbol.uppercased().filter { $0.isLetter || $0.isNumber }
        return up.isEmpty ? "TOKEN" : String(up.prefix(6))
    }

    /// Compact amount: 1,240 · 0.53 · 0.00042.
    private static func format(_ v: Double) -> String {
        if v == 0 { return "0" }
        if v >= 1000 {
            let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0
            return f.string(from: NSNumber(value: v)) ?? String(Int(v))
        }
        if v >= 1 { return String(format: "%.2f", v) }
        return String(format: "%.4f", v)
    }
}
