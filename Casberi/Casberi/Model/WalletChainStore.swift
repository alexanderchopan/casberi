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
    ///
    /// HyperEVM and Monad (2026-08-28, prd §512) join as full EVM chains, MEASURED
    /// end-to-end before landing here rather than added on their reputation:
    /// Zerion serves both (`hyperevm` / `monad` chain ids — positions AND
    /// transactions, so holdings and activity both arrive on the primary
    /// read), Alchemy answers `eth_chainId`, `alchemy_getAssetTransfers` and
    /// the Portfolio `by-address` call on `hyperliquid-mainnet` /
    /// `monad-mainnet` (the last is the one that matters — a chain the
    /// Portfolio endpoint refuses 400s the WHOLE holdings read, and both were
    /// checked with the new id beside `eth-mainnet` in one body), and
    /// DeFiLlama prices both (`hyperliquid:` / `monad:`) for the backstop.
    ///
    /// **`hyperliquid-mainnet` is Alchemy's name for HyperEVM (chain id 999),
    /// and it is NOT the Hyperliquid L1.** `HyperliquidDeFi` already reads the
    /// other half — perps, spot and staked HYPE off `api.hyperliquid.xyz`,
    /// which has no EVM RPC and no address model this pipeline could touch.
    /// Two reads, two halves of one product; the picker says "HyperEVM"
    /// because that is the chain a token balance lives on, and calling the row
    /// "Hyperliquid" would claim the perps book is in it.
    static let selectable: [(id: String, name: String)] = [
        ("eth-mainnet",      "Ethereum"),
        ("base-mainnet",     "Base"),
        ("arb-mainnet",      "Arbitrum"),
        ("opt-mainnet",      "Optimism"),
        ("matic-mainnet",    "Polygon"),
        ("hyperliquid-mainnet", "HyperEVM"),
        ("monad-mainnet",    "Monad"),
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
    ///
    /// HyperEVM and Monad are ON, unlike Robinhood, and the difference is
    /// COST rather than taste: both are mapped in `ZerionAPI.networkFor`, and
    /// Zerion's positions/transactions calls ask for every mapped chain in ONE
    /// request per wallet whatever this set says (the toggle filters the
    /// answer, `WalletIngest.collectCandidatesZerion`) — so switching them on
    /// spends nothing on the read that actually runs. Robinhood has no Zerion
    /// mapping, so it costs a real extra chain in the Alchemy body and stays
    /// a chain you turn on. The only marginal cost here is the Alchemy
    /// transfer FALLBACK, two requests per chain per wallet, and only when
    /// Zerion is unreachable.
    static let defaultNetworkIDs = ["eth-mainnet", "base-mainnet", "arb-mainnet",
                                    "opt-mainnet", "matic-mainnet",
                                    "hyperliquid-mainnet", "monad-mainnet",
                                    "solana-mainnet"]

    private var selected: [String] { didSet { persist() } }

    /// One-time seed of a chain added AFTER a person already chose their set.
    /// A saved set that predates an option doesn't mean "off" — it means never
    /// asked; treating the two the same would leave every existing wallet
    /// unable to read a `.sol` name it can now resolve. Seeded once each, so
    /// turning a seeded chain back off afterwards sticks.
    ///
    /// A LIST rather than the single Solana flag it started as (2026-08-28):
    /// two more chains arrived at once, and a second copy of the same one-off
    /// `if` is how the third gets forgotten. Every entry that is ON by default
    /// must be here — a chain in `defaultNetworkIDs` with no seed row reaches
    /// only installs made after it landed, silently, which is exactly the
    /// state Solana was in before its own flag existed. Solana keeps its
    /// original key spelling so a device that already seeded it is not asked
    /// twice.
    private static let seeded: [(id: String, key: String)] = [
        ("solana-mainnet",      "wallet.chains.solanaSeeded.v1"),
        ("hyperliquid-mainnet", "wallet.chains.hyperevmSeeded.v1"),
        ("monad-mainnet",       "wallet.chains.monadSeeded.v1"),
    ]

    private init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([String].self, from: data), !saved.isEmpty {
            // Only ids still selectable survive (a chain retired from the list
            // shouldn't linger in the saved set).
            let known = Set(Self.allNetworkIDs)
            selected = saved.filter { known.contains($0) }
            if selected.isEmpty { selected = Self.defaultNetworkIDs }
            for seed in Self.seeded where !defaults.bool(forKey: seed.key) {
                defaults.set(true, forKey: seed.key)
                guard !selected.contains(seed.id) else { continue }
                selected = Self.allNetworkIDs.filter {
                    selected.contains($0) || $0 == seed.id
                }
            }
        } else {
            selected = Self.defaultNetworkIDs   // a fresh wallet reads the defaults
            for seed in Self.seeded { defaults.set(true, forKey: seed.key) }
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
