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
        guard let total = await WalletGas.totalUSD(addresses: addresses) else {
            return String(localized: "No gas spent since you started watching.")
        }
        return String(localized: "\(TokenStats.compact(total)) in gas since you started watching.")
    }
}
