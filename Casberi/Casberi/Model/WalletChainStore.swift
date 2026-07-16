import Foundation
import Observation

/// Which chains the wallet reads (2026-07-15) — the same follow-a-list-of-chains
/// idiom GeckoTerminal and OpenSea already wear, pointed at the wallet's Alchemy
/// reads. Every watched wallet is read across the SELECTED chains only; turning
/// one off drops it from the transfer sync, the holdings treemap, and the value
/// samples, and cuts the requests each refresh spends on it. Defaults to ALL
/// chains on, so a wallet connected before this ruling reads exactly as it did.
///
/// Kept deliberately small: the set of network ids in UserDefaults, no Observable
/// gymnastics on the read path. The ingest reads it through the thread-safe
/// `activeNetworkIDs()` (off Observation, callable from any fetch), while the
/// Wallet screen binds the `@Observable` instance for its picker.
@Observable
final class WalletChainStore {
    static let shared = WalletChainStore()
    private static let key = "wallet.chains.v1"

    /// Every selectable chain — Alchemy network id + the display name the picker
    /// shows. Each is verified to read end-to-end (transfers + holdings + prices,
    /// and a live tx explorer) before it lands here; adding a chain the Portfolio
    /// prices endpoint doesn't cover would 400 the whole holdings read.
    /// (Solana was evaluated 2026-07-15 and held: getAssetTransfers is EVM-only,
    /// so its activity can't ride this pipeline — a separate non-EVM path.)
    static let selectable: [(id: String, name: String)] = [
        ("eth-mainnet",      "Ethereum"),
        ("base-mainnet",     "Base"),
        ("arb-mainnet",      "Arbitrum"),
        ("opt-mainnet",      "Optimism"),
        ("matic-mainnet",    "Polygon"),
        ("robinhood-mainnet","Robinhood"),
    ]
    static var allNetworkIDs: [String] { selectable.map(\.id) }

    /// What a wallet reads by default — the five established chains. Robinhood
    /// Chain (added 2026-07-15) is genuinely readable but niche and new, so it's
    /// available in the picker yet OFF by default: a chain you turn on, not one
    /// every wallet spends requests on.
    static let defaultNetworkIDs = ["eth-mainnet", "base-mainnet", "arb-mainnet",
                                    "opt-mainnet", "matic-mainnet"]

    private var selected: [String] { didSet { persist() } }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([String].self, from: data), !saved.isEmpty {
            // Only ids still selectable survive (a chain retired from the list
            // shouldn't linger in the saved set).
            let known = Set(Self.allNetworkIDs)
            selected = saved.filter { known.contains($0) }
            if selected.isEmpty { selected = Self.defaultNetworkIDs }
        } else {
            selected = Self.defaultNetworkIDs   // default: the five established chains
        }
    }

    var activeIDs: [String] { selected }

    func isSelected(_ id: String) -> Bool { selected.contains(id) }

    /// Toggles a chain — but never lets the last one off (a wallet reading zero
    /// chains would silently stop landing anything). Keeps canonical order.
    func toggle(_ id: String) {
        if selected.contains(id) {
            guard selected.count > 1 else { return }
            selected.removeAll { $0 == id }
        } else {
            selected = Self.allNetworkIDs.filter { selected.contains($0) || $0 == id }
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(selected) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    /// The active network ids, read straight from UserDefaults — thread-safe and
    /// free of Observation, so `WalletIngest`'s background fetches can call it.
    /// Falls back to every chain when nothing's been chosen.
    static func activeNetworkIDs() -> [String] {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([String].self, from: data) {
            let known = Set(allNetworkIDs)
            let kept = saved.filter { known.contains($0) }
            if !kept.isEmpty { return kept }
        }
        return defaultNetworkIDs
    }
}
