import Foundation
import SwiftData

/// Watching a token (2026-07-07) — the general capability that replaced the
/// Bankr bridge. A pasted token (address, symbol, or Dexscreener link) resolves
/// through Dexscreener's public search (no key), and the token joins the
/// watchlist as a thing whose sheet draws its live price chart (TokenChart).
/// Read-only public price data — no wallet, no account, no trading. This is
/// Casberi's OWN watchlist, not a sync of anyone's Dexscreener account (which
/// has no read API).
enum TokenWatch {

    struct Resolved: Identifiable, Equatable {
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
        var best: [String: (pair: [String: Any], liquidity: Double)] = [:]
        for pair in pairs {
            guard let chain = pair["chainId"] as? String,
                  let base = pair["baseToken"] as? [String: Any],
                  let address = base["address"] as? String else { continue }
            let key = "\(chain):\(address.lowercased())"
            let liq = liquidity(pair)
            if best[key] == nil || liq > best[key]!.liquidity {
                best[key] = (pair, liq)
            }
        }
        return best.values
            .sorted { $0.liquidity > $1.liquidity }
            .prefix(limit)
            .compactMap { entry in
                let p = entry.pair
                guard let chain = p["chainId"] as? String,
                      let base = p["baseToken"] as? [String: Any],
                      let address = base["address"] as? String,
                      let name = base["name"] as? String,
                      let symbol = base["symbol"] as? String else { return nil }
                return Resolved(
                    chain: chain, address: address, name: name, symbol: symbol,
                    priceUsd: p["priceUsd"] as? String,
                    imageURL: IngestSupport.imageURL(
                        (p["info"] as? [String: Any])?["imageUrl"] as? String))
            }
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
        let ref = "dexscreener:\(token.chain):\(token.address.lowercased())"
        guard !IngestSupport.existingSourceRefs(context).contains(ref) else { return nil }
        let thing = Thing(
            kind: .link,
            title: "\(token.name) · $\(token.symbol)",
            content: "https://dexscreener.com/\(token.chain)/\(token.address)",
            source: "Dexscreener",
            capturedAt: .now,
            tags: ["Watchlist"],
            sourceRef: ref
        )
        context.insert(thing)
        try? context.save()
        SpotlightIndex.index([thing])
        return thing
    }
}
