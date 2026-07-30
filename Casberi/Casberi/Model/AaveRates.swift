import Foundation

/// Aave V3's Core-market supply APY, for comparison against a Morpho
/// vault's own rate — "Aave is paying more on USDC than your vault right
/// now" (2026-07-30). Deliberately NOT a raw on-chain `getReserveData` read:
/// that ABI wasn't re-derivable with confidence this session (no live
/// re-measurement), and DeFiLlama's public yields API already answers the
/// exact number Aave's own app shows, keyless.
///
/// MEASURED live 2026-07-30 (Ethereum/USDC): Aave now runs FOUR separate
/// pools there — the flagship Core market, plus "Umbrella" (its
/// safety-module wrapper, carries `apyReward` on top of the same base
/// rate), "Aave Horizon Market", and "Prime Instance". `poolMeta == nil` +
/// the highest `tvlUsd` picked Core every time ($210M vs $1–65M for the
/// others) — that's the heuristic `coreApy` keys on. This was cross-checked
/// only for Ethereum; other chains' pool naming isn't separately
/// re-verified, so a miss there returns nil rather than guessing.
enum AaveRates {
    /// chain display name + asset symbol → Core supply APY, a fraction
    /// (0.03185 for 3.185%) to match `MorphoDeFi.VaultHolding.netApy`'s
    /// scale. Rebuilt at most once every 6 hours — a lending rate doesn't
    /// move fast enough to justify pulling the endpoint more often, and
    /// URLSession negotiates gzip transparently, so the real transfer is a
    /// fraction of the ~11MB raw payload.
    private static let cache = CoalescingCache<[String: Double]>()

    static func coreApy(network: String, symbol: String) async -> Double? {
        guard let chainName = WalletIngest.displayName(forNetwork: network) else { return nil }
        let map = await cache.value(key: "aave-core", ttl: 6 * 3600) { await fetchCoreRates() }
        return map?["\(chainName)|\(symbol.uppercased())"]
    }

    /// One keyless GET; nil on transport failure or a malformed body —
    /// every caller treats nil as "unreachable, try again next pass".
    private static func fetchCoreRates() async -> [String: Double]? {
        guard let root = await IngestSupport.getJSON("https://yields.llama.fi/pools") as? [String: Any],
              let pools = root["data"] as? [[String: Any]]
        else { return nil }
        // (apy, tvl) per "chain|SYMBOL" — keep only the highest-TVL,
        // poolMeta-less entry, which is Core (see the header comment).
        var best: [String: (apy: Double, tvl: Double)] = [:]
        for pool in pools {
            // `poolMeta` is present-but-JSON-`null` for Core (NSNull via
            // JSONSerialization, not an absent key) — `pool["poolMeta"] ==
            // nil` would compare the dictionary lookup itself (`.some
            // (NSNull())` is never `== nil`) and silently exclude every
            // pool. Cast to String? first so a null value reads as nil too.
            guard pool["project"] as? String == "aave-v3",
                  (pool["poolMeta"] as? String) == nil,
                  let chain = pool["chain"] as? String,
                  let symbol = pool["symbol"] as? String,
                  let apy = pool["apy"] as? Double, apy.isFinite,
                  let tvl = pool["tvlUsd"] as? Double, tvl.isFinite
            else { continue }
            let key = "\(chain)|\(symbol.uppercased())"
            if tvl > (best[key]?.tvl ?? 0) { best[key] = (apy / 100, tvl) }
        }
        guard !best.isEmpty else { return nil }
        return best.mapValues(\.apy)
    }
}
