import Foundation

/// A keyed read over the Zerion API (`api.zerion.io/v1`), added 2026-07-19 to
/// move the wallet holdings hot path OFF Alchemy's paid credits (the account
/// went pay-as-you-go on Alchemy and hit the ceiling — the shared free key is
/// no longer free). One `/wallets/{address}/positions` call returns every
/// fungible holding across EVM AND Solana in one normalized, PRICED response,
/// with per-chain contract inline — replacing the Alchemy Portfolio
/// `by-address` call (the app's single biggest credit burn, fanned out 5–8× a
/// foreground) AND its separate SPL Prices fill (`WalletIngest.priceSPL`) in
/// one keyed request on Zerion's free developer tier (60k calls/month).
///
/// UNMEASURED against the live API. Written against Zerion's documented schema
/// (developers.zerion.io, `listWalletPositions`) but NOT yet exercised on device
/// — this file was authored on a Linux box with no Xcode/simulator, so the
/// field paths, the native-coin shape, and the Solana chain id are spec-derived,
/// not observed. Mirrors the 1Claw precedent (prd §111): ship behind a probe,
/// re-measure before trusting. Run `-zerionProbe <address>` on a real wallet and
/// compare its holdings against the treemap before relying on it.
///
/// Alchemy stays the FALLBACK (see `WalletIngest.collectCandidates`): an empty
/// key here, or any unreachable/failed read, silently falls through to today's
/// Alchemy path, so shipping this — or shipping it before the key is pasted in —
/// cannot break holdings. Zerion is preferred only when it actually answers.
enum ZerionAPI {

    /// The shipped read-only Zerion key. Paste your `zk_…` from
    /// dashboard.zerion.io here. EMPTY = Zerion off → the Alchemy fallback runs,
    /// exactly as before. Ships in the binary like `IngestSupport.alchemyKey`; a
    /// Zerion API key grants read-only portfolio data, the same risk class as the
    /// Alchemy key already committed here — if it leaks, the worst case is quota
    /// use on public data. Rotate at dashboard.zerion.io.
    static let key = ""

    /// Whether a real key is configured. When false every entry point returns nil
    /// immediately (no request, no auth header built), so the Alchemy fallback
    /// takes over with zero cost.
    static var isConfigured: Bool { !key.isEmpty }

    /// Zerion chain id → the Alchemy network id the rest of the app keys on
    /// (`WalletChainStore`, the treemap, `DefiLlamaPrices.chainKey`). The inverse
    /// of `DefiLlamaPrices.chainKey`, and deliberately ONLY the chains Casberi
    /// reads: a Zerion position on any other chain is skipped, never mis-mapped
    /// onto a network the treemap can't route.
    static let networkFor: [String: String] = [
        "ethereum": "eth-mainnet", "base": "base-mainnet", "arbitrum": "arb-mainnet",
        "optimism": "opt-mainnet", "polygon": "matic-mainnet", "solana": "solana-mainnet",
    ]

    /// One fungible holding as Zerion hands it over — already decimal-adjusted
    /// (`quantity.float`, so no decimals math and none of the `?? 18` SOL trap
    /// the Alchemy path lives with) and priced. The neutral shape
    /// `WalletIngest` maps straight into its private `Candidate`.
    struct Holding {
        let symbol: String
        /// nil = the chain's native coin (Zerion reports it with no on-chain
        /// implementation address). Passed through UNCHANGED downstream — an EVM
        /// address is case-insensitive hex but a Solana mint is base58 where case
        /// IS the address, so this must not be folded (the per-family rule
        /// `WalletIngest.heldPricedContracts` already lives with).
        let contract: String?
        /// Alchemy network id (mapped through `networkFor`).
        let network: String
        let amount: Double
        /// nil when Zerion didn't price it — `WalletIngest` then lets its SPL /
        /// DeFiLlama fills cover the gap exactly as they cover an Alchemy miss.
        let price: Double?
        let owner: String
    }

    /// Every simple (wallet) fungible holding for one address, across the chains
    /// Casberi maps — priced, non-trash — or nil when Zerion couldn't be reached
    /// at all (the caller's honest-failure signal to fall back to Alchemy; an
    /// EMPTY array is a real "holds nothing"). Filters server-side to
    /// `only_simple` non-trash positions so DeFi LP/loan legs and airdrop spam
    /// never reach the treemap. The address goes in the PATH; auth is HTTP Basic
    /// over base64("<key>:") (Zerion's documented scheme — key as the username,
    /// empty password).
    static func holdings(address: String) async -> [Holding]? {
        guard isConfigured,
              let auth = "\(key):".data(using: .utf8)?.base64EncodedString(),
              let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else { return nil }

        // Ask only for the chains we can route; `filter[positions]=only_simple`
        // drops complex DeFi positions and `filter[trash]=only_non_trash` drops
        // spam, so what comes back is exactly the treemap's population.
        let chains = networkFor.keys.sorted().joined(separator: ",")
        let query = "filter[positions]=only_simple"
            + "&filter[trash]=only_non_trash"
            + "&currency=usd"
            + "&filter[chain_ids]=\(chains)"
        let url = "https://api.zerion.io/v1/wallets/\(encoded)/positions/?\(query)"

        guard let root = await IngestSupport.getJSON(url, auth: "Basic \(auth)") as? [String: Any],
              let data = root["data"] as? [[String: Any]] else { return nil }

        let owner = address.lowercased()   // matches the Alchemy candidate path
        var out: [Holding] = []
        for item in data {
            guard let attrs = item["attributes"] as? [String: Any] else { continue }
            // Defensive: only simple wallet holdings, never a trash position that
            // slipped the server filter.
            if let flags = attrs["flags"] as? [String: Any],
               flags["is_trash"] as? Bool == true { continue }

            guard let chainId = ((item["relationships"] as? [String: Any])?["chain"]
                    as? [String: Any])?["data"] as? [String: Any],
                  let zid = chainId["id"] as? String,
                  let network = networkFor[zid] else { continue }

            let info = attrs["fungible_info"] as? [String: Any]
            guard let symbol = (info?["symbol"] as? String).flatMap({ $0.isEmpty ? nil : $0 }),
                  let quantity = attrs["quantity"] as? [String: Any],
                  let amount = doubleValue(quantity["float"]), amount > 0 else { continue }

            // The on-chain address for THIS position's chain. Absent / empty ⇒
            // the native coin (contract nil), the same signal the Alchemy path
            // reads from a missing `tokenAddress`.
            let contract = implementationAddress(info?["implementations"], chainId: zid)

            out.append(Holding(symbol: clean(symbol), contract: contract, network: network,
                               amount: amount, price: doubleValue(attrs["price"]), owner: owner))
        }
        return out
    }

    // MARK: - Parsing helpers

    /// The implementation address for a given chain id, or nil for the native
    /// coin (no implementation, or one whose address is null/empty). Passed
    /// through UNCHANGED — never case-folded (see `Holding.contract`).
    private static func implementationAddress(_ raw: Any?, chainId: String) -> String? {
        guard let impls = raw as? [[String: Any]] else { return nil }
        for impl in impls where impl["chain_id"] as? String == chainId {
            if let addr = impl["address"] as? String, !addr.isEmpty { return addr }
            return nil   // matched the chain but native (no address)
        }
        return nil
    }

    /// A JSON number tolerant of Double / Int / String encodings, rejecting a
    /// non-finite value (`Double("1e400")` is `.infinity`, not nil) — the same
    /// guard `WalletIngest.firstPrice` and `DefiLlamaPrices.priceValue` keep, so
    /// a poison quantity/price can't reach the treemap's `Int(...)`.
    private static func doubleValue(_ raw: Any?) -> Double? {
        if let d = raw as? Double, d.isFinite { return d }
        if let i = raw as? Int { return Double(i) }
        if let s = raw as? String, let d = Double(s), d.isFinite { return d }
        return nil
    }

    /// Trims a symbol the way `WalletIngest.clean` does at the boundary — one
    /// copy here so this file stays self-contained. A symbol is a short ticker;
    /// newlines and surrounding whitespace are never part of it.
    private static func clean(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    #if DEBUG
    /// The `-zerionProbe <address>` walk: what Zerion actually returns for one
    /// wallet — reachability, holding count, priced-vs-unpriced, and the first
    /// rows (symbol / network / amount / price) — so its parity with the Alchemy
    /// treemap can be eyeballed in one launch before it's trusted. Reads only.
    static func diagnostic(address: String) async -> [String] {
        guard isConfigured else {
            return ["Zerion probe: NO KEY set (ZerionAPI.key empty) — Alchemy fallback is live"]
        }
        guard let holdings = await holdings(address: address) else {
            return ["Zerion probe: FAILED — unreachable (offline / bad key / bad address)"]
        }
        guard !holdings.isEmpty else {
            return ["Zerion probe: reached, 0 holdings (a real 'holds nothing', not a miss)"]
        }
        let priced = holdings.filter { $0.price != nil }.count
        var out = [String(format: "Zerion probe: %d holding(s), %d priced, %d unpriced",
                          holdings.count, priced, holdings.count - priced)]
        for h in holdings.prefix(15) {
            out.append(String(format: "  %@ [%@] amt=%@ price=%@",
                              h.symbol, h.network,
                              String(format: "%g", h.amount),
                              h.price.map { String(format: "$%.4f", $0) } ?? "—"))
        }
        if holdings.count > 15 { out.append("  … +\(holdings.count - 15) more") }
        return out
    }
    #endif
}
