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
    private static let alchemyKey = "1BymL53WZVbPw9fTm42D8"

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
        let addresses = WalletStore.shared.addresses.map(\.address)
        guard !addresses.isEmpty, !running else { return addresses.isEmpty ? nil : 0 }
        running = true
        defer { running = false }

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
                        guard let thing = thing(from: t, chain: chain, received: received, ref: ref)
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

    private static func fetch(address: String, chain: Chain,
                              received: Bool) async -> [[String: Any]]? {
        let url = "https://\(chain.network).g.alchemy.com/v2/\(alchemyKey)"
        let params: [String: Any] = [
            "fromBlock": "0x0", "toBlock": "latest",
            received ? "toAddress" : "fromAddress": address,
            "category": ["external", "erc20", "erc721", "erc1155"],
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
                              received: Bool, ref: String) -> Thing? {
        guard let hash = t["hash"] as? String else { return nil }
        let asset = (t["asset"] as? String) ?? chain.symbol
        let amount = (t["value"] as? Double).map(format) ?? ""
        let verb = received ? "Received" : "Sent"
        let title = amount.isEmpty ? "\(verb) \(asset)" : "\(verb) \(amount) \(asset)"
        let when = IngestSupport.isoDate((t["metadata"] as? [String: Any])?["blockTimestamp"])
        return Thing(
            kind: .transaction,
            title: title,
            content: chain.explorer + hash,
            source: "Wallet",
            capturedAt: when ?? .now,
            sourceRef: ref
        )
    }

    /// A treemap of the wallet's token holdings, sized by USD value — the
    /// same TagMap idiom Home uses. Real, from Alchemy's Portfolio API
    /// (balances + metadata + prices in one call). Unpriced spam tokens have no
    /// price and drop out; the top 5 by value are shown. A normal wallet fits
    /// in one page; a wallet holding hundreds of tokens (its real holdings
    /// scattered behind pages of spam) is paged through, bounded, until we have
    /// the true top of the book. Returns nil when nothing priced is held.
    @MainActor
    static func holdingsChart() async -> [String]? {
        let addresses = WalletStore.shared.addresses.map(\.address)
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
        let cells = bySymbol.sorted { $0.value > $1.value }.prefix(5)
            .map { "\($0.key) \(max(1, Int($0.value.squareRoot() * 10)))" }
        return ["root = Stack([m])",
                "m = TagMap(\"Holdings\", \"By value\", [\(cells.joined(separator: ", "))])"]
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
