import Foundation

/// **PRIVATE MONEY IS PRICED FROM THE FIRST FRAME (prd §1593, §1858).**
///
/// The Wallet opens on its last reading (`WalletLastReading`), whose total
/// counts your private money. The private stores kept what you hold and not
/// what it was worth: their prices lived in memory, empty at every launch. So
/// Home drew the whole total as Public and no Private at all, then each store
/// priced itself at its own moment (Privacy Pools, Railgun, Aztec), and the
/// two halves moved for seconds before they agreed.
///
/// Each store keeps the prices of its last read here and starts on them. They
/// are written on every read that answered, so they are never older than the
/// reading they split. Never the demo's invented prices.
enum LastPrices {
    static func read(_ key: String) -> [String: Double] {
        UserDefaults.standard.data(forKey: key)
            .flatMap { try? JSONDecoder().decode([String: Double].self, from: $0) } ?? [:]
    }

    /// What a store holds after a read: the answer, or what stood when the
    /// read answered nothing. Prices are read through Tor (prd §1495), and a
    /// read that could not look is not a price of nothing: it emptied the
    /// store, and Private left Home while the total still counted it.
    static func settled(_ found: [String: Double], over standing: [String: Double]) -> [String: Double] {
        found.isEmpty ? standing : found
    }

    static func keep(_ prices: [String: Double], key: String) {
        guard !DemoMode.isActive, let data = try? JSONEncoder().encode(prices) else { return }
        DefaultsWrite.set(data, forKey: key)
    }
}
