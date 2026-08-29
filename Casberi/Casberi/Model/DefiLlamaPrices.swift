import Foundation

/// A keyless price backstop over DeFiLlama's coins API (`coins.llama.fi`),
/// added 2026-07-17 (prd §115). It fills the one gap the wallet's Alchemy
/// pricing leaves: a held token Alchemy doesn't price is silently DROPPED by
/// `WalletIngest.fetchHeldTokens`' `price > 0` guard, so a real holding can
/// vanish from the treemap — worst on Solana, where Alchemy prices only native
/// SOL inline (see `WalletIngest.priceSPL`), and worst under load, since the
/// shared free-tier Alchemy key rate-limits (the vanishing-holdings-card
/// class the 2026-07-17 retry work chipped at).
///
/// DeFiLlama is keyless and, unlike Alchemy, prices EVM and SPL mints in ONE
/// batched request. Measured 2026-07-17 against the live API: USDC / wSOL /
/// JUP / BONK all priced with correct decimals (SOL comes back `9`, no `?? 18`
/// trap), each carrying a `confidence` (0.99 for blue chips), an unknown mint
/// returns an empty `coins` object (a clean fall-through), Cloudflare-cached
/// ~3 min, no key. It is used ONLY as a fallback — it never overrides an
/// Alchemy price, only fills a missing one — so the primary source stays
/// authoritative and this spends requests only on what would otherwise be
/// dropped, off the contended Alchemy key.
enum DefiLlamaPrices {

    /// Alchemy network id → DeFiLlama chain key. Mirrors `WalletIngest`'s own
    /// `chainSlug` (DeFiLlama, Dexscreener, and GeckoTerminal happen to spell
    /// every chain we read the same way). A network absent here — Robinhood,
    /// say — simply isn't backstopped rather than asked with a bad key.
    private static let chainKey: [String: String] = [
        "eth-mainnet": "ethereum", "base-mainnet": "base", "arb-mainnet": "arbitrum",
        "opt-mainnet": "optimism", "matic-mainnet": "polygon", "solana-mainnet": "solana",
        // Measured 2026-08-28 against real tokens on each (WHYPE 0.99
        // confidence, WMON/USDC/CHOG likewise). DeFiLlama names HyperEVM
        // `hyperliquid` — a THIRD spelling for one chain, after Alchemy's
        // `hyperliquid-mainnet` and Zerion's `hyperevm`. It also answers to
        // `hyperevm`, but `hyperliquid` is the key its own `/chains` listing
        // publishes, so that is the one kept.
        "hyperliquid-mainnet": "hyperliquid", "monad-mainnet": "monad",
    ]

    /// One priced coin as DeFiLlama returns it — the price plus the confidence
    /// the caller gates on (a thin/one-sided pool reads lower than a blue
    /// chip's 0.99, and the honesty rule says don't show a number we half-
    /// believe).
    struct Priced {
        let price: Double
        let confidence: Double
    }

    /// Below this, a price is too speculative to spend a treemap cell on. Blue
    /// chips return 0.99; kept as a named constant so the merge and the probe
    /// agree on the line.
    static let confidenceFloor = 0.9

    /// Prices the given `(network, contract)` mints, keyed by a
    /// `"network|contract"` string the caller can rebuild from its own
    /// candidates. The contract is passed through UNCHANGED: an EVM address is
    /// case-insensitive hex, but a Solana mint is base58 where case IS the
    /// address, so the key must not fold case (the per-family quirk
    /// `WalletIngest.heldPricedContracts` already lives with). Returns `[:]` on
    /// total failure — a backstop that can't reach the network just leaves the
    /// primary source's result untouched.
    static func prices(for mints: [(network: String, contract: String)]) async -> [String: Priced] {
        // Build DeFiLlama coin ids, remembering which input each maps back to.
        // A dictionary dedupes ids for free (a token held by several watched
        // wallets appears once per owner in the candidate list).
        var idToKey: [String: String] = [:]   // "solana:Mint" → "network|contract"
        for m in mints {
            guard let chain = chainKey[m.network] else { continue }
            idToKey["\(chain):\(m.contract)"] = "\(m.network)|\(m.contract)"
        }
        guard !idToKey.isEmpty else { return [:] }

        var out: [String: Priced] = [:]
        // Chunked so no single request URL grows unreasonable (each id ~50
        // chars); the endpoint itself takes a comma-separated list of any size.
        let ids = Array(idToKey.keys)
        for chunk in stride(from: 0, to: ids.count, by: 50).map({
            Array(ids[$0..<min($0 + 50, ids.count)])
        }) {
            let url = "https://coins.llama.fi/prices/current/\(chunk.joined(separator: ","))"
            guard let root = await IngestSupport.getJSON(url) as? [String: Any],
                  let coins = root["coins"] as? [String: Any] else { continue }
            for (id, raw) in coins {
                guard let key = idToKey[id],
                      let entry = raw as? [String: Any],
                      let price = priceValue(entry["price"]), price > 0 else { continue }
                out[key] = Priced(price: price, confidence: confidenceValue(entry["confidence"]))
            }
        }
        return out
    }

    /// The `price` field, tolerant of the JSON number arriving as Double, Int,
    /// or String, and rejecting a non-finite value (`Double("1e400")` is
    /// `.infinity`, not nil — the same guard `WalletIngest.firstPrice` keeps).
    private static func priceValue(_ raw: Any?) -> Double? {
        if let d = raw as? Double, d.isFinite { return d }
        if let i = raw as? Int { return Double(i) }
        if let s = raw as? String, let d = Double(s), d.isFinite { return d }
        return nil
    }

    /// `confidence`, defaulting to 0 (fails the floor → drop) when absent. The
    /// field is present on every measured response (always 0.99); its ABSENCE
    /// would be a schema change, and the honesty-rule-safe response to an
    /// unscored price is to not spend a treemap cell on it rather than trust it
    /// blindly. Fail-closed degrades the backstop to a no-op — exactly today's
    /// behavior — instead of surfacing a price we can't vouch for.
    private static func confidenceValue(_ raw: Any?) -> Double {
        if let d = raw as? Double, d.isFinite { return d }
        if let i = raw as? Int { return Double(i) }
        return 0
    }
}
