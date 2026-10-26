import Foundation

/// **AN OPEN TOKEN LIST IN PLACE OF RELAY'S (prd §1542).** Uniswap's default
/// token list (`tokens.uniswap.org`, the Token Lists standard: one public
/// JSON file, Cloudflare-served, a day's cache) names the tokens Move offers
/// unasked and marks "on the list", where Relay's search and its "verified"
/// did. Measured 2026-10-26: 483 tokens on Ethereum, 195 on Base and 205 on
/// Robinhood Chain (its stock tokens and USDG), every logo on CoinGecko's
/// image hosts but a few; the file answered through Tor 3 of 3 (about 860 KB,
/// 2–3 s). The Superchain list (static.optimism.io) carries Base (326) but
/// not Robinhood Chain, and CoinGecko's Base list carries every token
/// CoinGecko has seen (2,900+, no curation), so it would mark anything:
/// Uniswap's covers all three networks and is the one used.
///
/// A token not on the list is still offered when typed or pasted (a pasted
/// contract is read off the chain, `symbol()` and `decimals()`), and is said
/// to be "Not on Uniswap's list", so a look-alike never passes as the real one.
///
/// Pure: `direct-swap-selftest.sh` reads it with no network.
enum OpenTokenList {
    static let url = "https://tokens.uniswap.org"
    /// Said wherever the list's mark is: "Not on Uniswap's list".
    static let name = "Uniswap"

    struct Entry: Equatable, Sendable {
        let chainId: Int
        /// Lowercase hex.
        let address: String
        let symbol: String
        let name: String
        let decimals: Int
        /// An https picture, when the list gives one.
        let logo: String?
    }

    /// The list's tokens on `chains`, in the list's order, each once per
    /// network. A row with a malformed address, an empty or long symbol, or
    /// decimals past 36 is dropped, never repaired.
    static func parse(_ data: Data, chains: Set<Int>) -> [Int: [Entry]] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = root["tokens"] as? [[String: Any]] else { return [:] }
        var out: [Int: [Entry]] = [:]
        var seen: Set<String> = []
        for t in tokens {
            guard let chain = t["chainId"] as? Int, chains.contains(chain),
                  let address = t["address"] as? String, isAddress(address),
                  let symbol = (t["symbol"] as? String)?.trimmingCharacters(in: .whitespaces),
                  !symbol.isEmpty, symbol.count <= 16,
                  let decimals = t["decimals"] as? Int, (0...36).contains(decimals) else { continue }
            let key = "\(chain)|\(address.lowercased())"
            guard seen.insert(key).inserted else { continue }
            let logo = (t["logoURI"] as? String).flatMap { $0.hasPrefix("https://") ? $0 : nil }
            out[chain, default: []].append(Entry(chainId: chain, address: address.lowercased(), symbol: symbol,
                                                 name: (t["name"] as? String) ?? symbol, decimals: decimals, logo: logo))
        }
        return out
    }

    /// The entries matching typed words: a symbol or name holding them, or
    /// the address itself. Order is the list's; `YourAccountTokens.matches`
    /// ranks what is shown.
    static func search(_ entries: [Entry], _ term: String) -> [Entry] {
        let q = term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return entries }
        if isAddress(q) { return entries.filter { $0.address == q } }
        return entries.filter { $0.symbol.lowercased().contains(q) || $0.name.lowercased().contains(q) }
    }

    static func isAddress(_ s: String) -> Bool {
        s.count == 42 && s.lowercased().hasPrefix("0x") && s.dropFirst(2).allSatisfy(\.isHexDigit)
    }
}
