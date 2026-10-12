import Foundation

/// The app half of `CowOrder` (prd §1285): before the Safe sign block draws a
/// transaction that pre-signs a CoW order, ask CoW's public API for the order
/// by its id, keep it only if `CowOrder.verify` proves it hashes to that id,
/// and read its tokens' decimals off the chain the signer already reads. A
/// failure anywhere leaves the reading exactly as it was (§1282's owner and
/// expiry), never a guess.
enum CowOrders {
    /// The native-coin placeholder CoW uses for a buy token paid out in ETH.
    private static let native = "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"

    /// At most this many orders are fetched for one transaction; a batch
    /// pre-signing more keeps §1282's reading for the rest.
    private static let maxOrders = 4

    static func enrich(_ reading: SafeCalldata, to: String, data: String, safe: String,
                       chainId: Int, network: String?, nativeSymbol: String) async -> SafeCalldata {
        let calls = CowOrder.preSignatures(to: to, data: data, reading: reading)
        guard !calls.isEmpty else { return reading }
        var verified: [String: CowOrder.Order] = [:]
        for call in calls.prefix(maxOrders) {
            guard let url = CowOrder.url(chainId: chainId, uid: call.uid),
                  let json = await IngestSupport.getJSON(url, service: "Wallet DeFi & Safe") as? [String: Any],
                  let order = CowOrder.verify(json: json, uid: call.uid, chainId: chainId)
            else { continue }
            verified[SafeABI.hex(call.uid)] = order
        }
        guard !verified.isEmpty else { return reading }
        var tokens: [String: ClearSign.Token] = [native: ClearSign.Token(ticker: nativeSymbol, decimals: 18)]
        if let network {
            for token in Set(verified.values.flatMap { [$0.sellToken, $0.buyToken] }) where token != native {
                let fact = await WalletApprovals.tokenFacts(network: network, contract: token)
                if let symbol = fact.symbol, let decimals = fact.decimals {
                    tokens[token] = ClearSign.Token(ticker: symbol, decimals: decimals)
                }
            }
        }
        return CowOrder.enrich(reading, to: to, data: data, safe: safe, verified: verified,
                               token: { tokens[$0.lowercased()] },
                               address: { WalletIngest.canonicalName(for: $0) ?? WalletStore.shortAddress(EIP55.checksum($0)) },
                               date: { $0.formatted(date: .abbreviated, time: .shortened) })
    }

    #if DEBUG
    /// `-cowOrderProbe "<chainId>:<0x order id>"` — the sign block's CoW path
    /// for one order, headless: fetched, verified, and the reading it draws.
    static func probe(_ spec: String) async -> [String] {
        let parts = spec.split(separator: ":").map(String.init)
        guard parts.count == 2, let chainId = Int(parts[0]), let uid = SafeABI.hexBytes(parts[1]), uid.count == 56,
              let url = CowOrder.url(chainId: chainId, uid: uid) else { return ["bad spec"] }
        guard let json = await IngestSupport.getJSON(url, service: "Wallet DeFi & Safe") as? [String: Any] else { return ["UNREACHABLE"] }
        guard CowOrder.verify(json: json, uid: uid, chainId: chainId) != nil else { return ["fetched, NOT VERIFIED"] }
        let data = "0xec6cb13f" + String(repeating: "0", count: 62) + "40" + String(repeating: "0", count: 63) + "1"
            + String(repeating: "0", count: 62) + "38" + SafeABI.hex(uid).dropFirst(2) + String(repeating: "0", count: 16)
        let owner = SafeABI.hex(Array(uid[32..<52]))
        let out = await enrich(.undecoded(selector: "0xec6cb13f"), to: CowOrder.settlement, data: data, safe: owner,
                               chainId: chainId, network: chainId == 1 ? "eth-mainnet" : nil, nativeSymbol: "ETH")
        guard case .described(let r) = out else { return ["verified, NOT DRAWN"] }
        return ["verified | \(r.headline)"] + r.lines.map { "\($0.label) = \($0.value)" }
    }
    #endif
}
