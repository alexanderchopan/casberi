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
    ///
    /// Solana (2026-07-16) arrived in two halves. Holdings first (prd §85): the
    /// Portfolio endpoint takes `solana-mainnet` on the same key, so a `.sol`
    /// name lands a wallet with a real treemap. Activity followed the same day
    /// (prd §86) once the cost was MEASURED rather than assumed — it rides
    /// `SolanaActivity`, not `getAssetTransfers`, which stays EVM-only (hence
    /// `WalletIngest.transferChains`). Solana is a full chain here now; the
    /// split lives in HOW each half is read, not in what a person gets.
    static let selectable: [(id: String, name: String)] = [
        ("eth-mainnet",      "Ethereum"),
        ("base-mainnet",     "Base"),
        ("arb-mainnet",      "Arbitrum"),
        ("opt-mainnet",      "Optimism"),
        ("matic-mainnet",    "Polygon"),
        ("solana-mainnet",   "Solana"),
        ("robinhood-mainnet","Robinhood"),
    ]
    static var allNetworkIDs: [String] { selectable.map(\.id) }

    /// What a wallet reads by default. Robinhood Chain (added 2026-07-15) is
    /// genuinely readable but niche and new, so it's available in the picker yet
    /// OFF by default: a chain you turn on, not one every wallet spends requests
    /// on. Solana is ON, and unlike Robinhood it costs an EVM-only person
    /// nothing — the holdings read routes each address to the chains its own
    /// SHAPE can live on (`WalletIngest.networks(for:)`), so a `0x…` wallet
    /// never spends a request on Solana and vice versa.
    static let defaultNetworkIDs = ["eth-mainnet", "base-mainnet", "arb-mainnet",
                                    "opt-mainnet", "matic-mainnet", "solana-mainnet"]

    private var selected: [String] { didSet { persist() } }

    /// One-time seed of a chain added AFTER a person already chose their set.
    /// A saved set that predates an option doesn't mean "off" — it means never
    /// asked; treating the two the same would leave every existing wallet
    /// unable to read a `.sol` name it can now resolve. Seeded once, so turning
    /// Solana back off afterwards sticks.
    private static let solanaSeededKey = "wallet.chains.solanaSeeded.v1"

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([String].self, from: data), !saved.isEmpty {
            // Only ids still selectable survive (a chain retired from the list
            // shouldn't linger in the saved set).
            let known = Set(Self.allNetworkIDs)
            selected = saved.filter { known.contains($0) }
            if selected.isEmpty { selected = Self.defaultNetworkIDs }
            let defaults = UserDefaults.standard
            if !defaults.bool(forKey: Self.solanaSeededKey) {
                defaults.set(true, forKey: Self.solanaSeededKey)
                if !selected.contains("solana-mainnet") {
                    selected = Self.allNetworkIDs.filter {
                        selected.contains($0) || $0 == "solana-mainnet"
                    }
                }
            }
        } else {
            selected = Self.defaultNetworkIDs   // a fresh wallet reads the defaults
            UserDefaults.standard.set(true, forKey: Self.solanaSeededKey)
        }
    }

    /// Turns a chain on if it isn't already — used when a watched address can
    /// ONLY be read on that chain (adding a `.sol` name with Solana switched
    /// off would otherwise land a wallet that can never show anything).
    func ensureEnabled(_ id: String) {
        guard Self.allNetworkIDs.contains(id), !selected.contains(id) else { return }
        selected = Self.allNetworkIDs.filter { selected.contains($0) || $0 == id }
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
