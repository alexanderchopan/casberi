import Foundation

/// Gas asks (2026-07-20) — "what have I spent on gas", "gas fees". "gas"
/// alone is too common a word to trust bare (a note mentioning a gas bill
/// shouldn't hijack this) — requires BOTH "gas" and a spend-shaped word,
/// mirroring `WalletAsk`'s residual-word discipline in spirit.
enum WalletGasAsk {
    static func matches(_ raw: String) -> Bool {
        let q = raw.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
        guard q.contains("gas") else { return false }
        return q.contains("spent") || q.contains("spend") || q.contains("fee")
            || q.contains("cost") || q.contains("paid")
    }

    /// nil ONLY when no EVM wallet is watched; nothing spent yet still
    /// answers honestly.
    @MainActor
    static func answer() async -> String? {
        let watched = WalletStore.shared.addresses.map(\.address)
        let addresses = await WalletIngest.resolvedAddresses(watched).filter { ENS.isHexAddress($0) }
        guard !addresses.isEmpty else { return nil }
        // Sponsored gas is stated alongside (2026-08-03, prd §293): with a
        // smart account somebody else can pay for you, and a total that
        // silently omitted it would answer "what have I spent on gas" without
        // mentioning the part that cost nothing — which is the interesting
        // half. Nil for everyone who has never used a paymaster, so the
        // sentence only grows when there's something to say.
        let sponsored = await WalletGas.sponsoredUSD(addresses: addresses)
        guard let total = await WalletGas.totalUSD(addresses: addresses) else {
            if let sponsored {
                return String(localized:
                    "No gas of your own since you started watching — \(TokenStats.compact(sponsored)) was sponsored for you.")
            }
            return String(localized: "No gas spent since you started watching.")
        }
        if let sponsored {
            return String(localized:
                "\(TokenStats.compact(total)) in gas since you started watching, plus \(TokenStats.compact(sponsored)) somebody else paid for you.")
        }
        return String(localized: "\(TokenStats.compact(total)) in gas since you started watching.")
    }
}
