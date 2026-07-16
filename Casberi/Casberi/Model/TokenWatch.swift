import Foundation
import SwiftData

/// Watching a token (2026-07-07) — the general capability that replaced the
/// Bankr bridge, presented to the person as "Tokens" (2026-07-13 rename — the
/// chart itself blends GeckoTerminal/Alchemy/Dexscreener, so branding the
/// whole capability as one vendor overclaimed). A pasted token (address,
/// symbol, or link) resolves through Dexscreener's public search (no key,
/// the one piece nothing else replaces — see TokenChart.swift), and joins
/// the watchlist as a thing whose sheet draws its live price chart
/// (TokenChart). Read-only public price data — no wallet, no account, no
/// trading. This is Casberi's OWN watchlist, not a sync of any exchange
/// account.
enum TokenWatch {

    struct Resolved: Identifiable {
        let chain: String
        let address: String
        let name: String
        let symbol: String
        let priceUsd: String?
        /// The token's logo, when Dexscreener has one — for the search rows.
        let imageURL: String?
        var id: String { "\(chain):\(address.lowercased())" }
    }

    /// The top matching tokens for a typed query, most liquid first — one
    /// row per token (a token trades in many pairs; its most-liquid pair
    /// speaks for it). This is what the setup screen shows as you type.
    static func search(_ query: String, limit: Int = 6) async -> [Resolved] {
        var q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if let route = TokenChart.route(from: q) { q = route.address }   // a link → its address
        guard !q.isEmpty,
              let encoded = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let root = await IngestSupport.getJSON(
                "https://api.dexscreener.com/latest/dex/search?q=\(encoded)") as? [String: Any],
              let pairs = root["pairs"] as? [[String: Any]]
        else { return [] }

        func liquidity(_ p: [String: Any]) -> Double {
            (p["liquidity"] as? [String: Any])?["usd"] as? Double ?? 0
        }
        // One parse per pair — the dedupe key and the emitted row come from
        // the same Resolved, so they can't drift out of sync.
        var best: [String: (token: Resolved, liquidity: Double)] = [:]
        for pair in pairs {
            guard let chain = pair["chainId"] as? String,
                  let base = pair["baseToken"] as? [String: Any],
                  let address = base["address"] as? String,
                  let name = base["name"] as? String,
                  let symbol = base["symbol"] as? String else { continue }
            let liq = liquidity(pair)
            let token = Resolved(
                chain: chain, address: address, name: name, symbol: symbol,
                priceUsd: pair["priceUsd"] as? String,
                imageURL: IngestSupport.imageURL(
                    (pair["info"] as? [String: Any])?["imageUrl"] as? String))
            if liq > (best[token.id]?.liquidity ?? -1) {
                best[token.id] = (token, liq)
            }
        }
        return best.values
            .sorted { $0.liquidity > $1.liquidity }
            .prefix(limit)
            .map(\.token)
    }

    /// Resolves a query to its most-liquid token — the Watch button's path.
    static func resolve(_ query: String) async -> Resolved? {
        await search(query, limit: 1).first
    }

    /// Adds a resolved token to the watchlist. Returns the new thing, or nil
    /// when it's already watched (dedupe by chain+address).
    @MainActor
    @discardableResult
    static func add(_ token: Resolved, context: ModelContext) -> Thing? {
        let ref = "tokens:\(token.chain):\(token.address.lowercased())"
        guard !IngestSupport.existingSourceRefs(context).contains(ref) else { return nil }
        let thing = Thing(
            kind: .link,
            title: "\(token.name) · $\(token.symbol)",
            content: "https://dexscreener.com/\(token.chain)/\(token.address)",
            source: "Tokens",
            capturedAt: .now,
            tags: ["Watchlist"],
            sourceRef: ref
        )
        // The since-you-watched anchor (2026-07-14): the resolve already
        // carried the live price — keep it, so the sheet can say "+41% since
        // you watched" against a number that was really true at this moment.
        thing.watchPriceUsd = token.priceUsd.flatMap(Double.init)
        context.insert(thing)
        context.saveHonestly()
        SpotlightIndex.index([thing])
        return thing
    }

    /// Registers (or refreshes) the Tokens bridge with the live watched
    /// count — one registrar for every door that can watch a token (the
    /// setup screen, and a tapped holdings cell's quick sheet).
    @MainActor
    static func registerBridge(store: BridgeStore, context: ModelContext) {
        let count = (try? context.fetchCount(FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == "Tokens" }))) ?? 0
        let proof = "\(count) token\(count == 1 ? "" : "s") watched"
        if let existing = store.bridges.first(where: { $0.name == "Tokens" }) {
            store.reconnect(existing.id, proof: proof)
        } else {
            store.bridges.append(BridgeApp(
                id: "tokens", name: "Tokens", status: .connected,
                statusLine: proof,
                can: ["Watches the tokens you add.", "Read-only — public price data only."]
            ))
            DSHaptic.success()
        }
    }
}
