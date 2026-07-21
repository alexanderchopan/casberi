import Foundation

/// Safe (multisig) asks (2026-07-20) — "anything pending on my Safe",
/// "signatures needed". "safe" alone is far too common a word ("is this
/// safe") to trust bare — requires either the specific word "multisig", or
/// "safe" paired with a queue-shaped word.
enum SafeAsk {
    static func matches(_ raw: String) -> Bool {
        let q = raw.lowercased()
        if q.contains("multisig") { return true }
        guard q.contains("safe") else { return false }
        return q.contains("pending") || q.contains("signature") || q.contains("queue")
    }

    /// nil ONLY when no EVM wallet is watched; no detected Safe, or nothing
    /// pending, still answers honestly.
    @MainActor
    static func answer() async -> String? {
        let watched = WalletStore.shared.addresses.map(\.address)
        let addresses = await WalletIngest.resolvedAddresses(watched).filter { ENS.isHexAddress($0) }
        guard !addresses.isEmpty else { return nil }
        let counts = await SafeBridge.pendingCounts(addresses: addresses)
        guard !counts.isEmpty else {
            return String(localized: "No Safe wallets detected.")
        }
        let total = counts.values.reduce(0, +)
        guard total > 0 else {
            return String(localized: "Nothing pending on your Safe.")
        }
        return total == 1
            ? String(localized: "1 signature needed across your Safes.")
            : String(localized: "\(total) signatures needed across your Safes.")
    }
}
