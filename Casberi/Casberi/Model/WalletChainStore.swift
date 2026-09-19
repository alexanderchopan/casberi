import Foundation
import Observation

/// Which chains the wallet reads (2026-07-15) — a follow-a-list-of-chains
/// idiom, pointed at the wallet's Alchemy reads. Every watched wallet is read across the SELECTED chains only; turning
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
    ///
    /// **World Chain (prd §785, 2026-09-16) landed UNMEASURED and OFF, and
    /// was measured end to end the same evening (prd §788), which put it ON.**
    /// Zerion serves it as `world` (positions and transactions, one request
    /// per wallet like HyperEVM and Monad), Alchemy's Portfolio `by-address`
    /// call takes `worldchain-mainnet` beside `eth-mainnet` in one body,
    /// `getAssetTransfers` answers once it is not asked for `internal`
    /// transfers (`WalletIngest.Chain.internalTransfers`), and DeFiLlama
    /// prices WLD under `wc`. World App's wallets live here, so a watched
    /// World App address shows its WLD and USDC with nothing switched on.
    ///
    /// Note `WorldID` reads World Chain whether or not this row is on: that is
    /// one `eth_call` on a keyless public host, not this table's Alchemy
    /// pipeline, and it is a fact about an address rather than a chain you
    /// follow.
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
        ("worldchain-mainnet", "World Chain"),
        ("arc-mainnet",      "Arc"),
        ("tempo-mainnet",    "Tempo"),
    ]
    static var allNetworkIDs: [String] { selectable.map(\.id) }

    /// What a wallet reads by default. Solana costs an EVM-only person nothing —
    /// the holdings read routes each address to the chains its own SHAPE can
    /// live on (`WalletIngest.networks(for:)`), so a `0x…` wallet never spends a
    /// request on Solana and vice versa.
    ///
    /// HyperEVM, Monad, World Chain and Arc are free in the same way: all four
    /// are mapped in `ZerionAPI.networkFor`, and Zerion's positions and
    /// transactions calls ask for the chains the caller routes in ONE request
    /// per wallet, so switching them on spends nothing on the read that runs.
    ///
    /// **ROBINHOOD IS ON since 2026-09-18 (prd §826), and the reasoning that
    /// kept it off was measuring the wrong thing.** It was "a chain you turn on"
    /// because it has no Zerion mapping and so "costs a real extra chain in the
    /// Alchemy body" — but that body was only ever built when Zerion was
    /// UNREACHED, so while Zerion was up the chain could not be read at all and
    /// the toggle changed nothing. A picker row that cannot affect what you see
    /// is §83's dead control, and the person it was hiding money from was the
    /// one who reported it: ten dollars on Robinhood, three on Ethereum, and a
    /// crown that said six. `WalletIngest.collectCandidates` is a union now, so
    /// the row works — and a chain whose money the app cannot otherwise see
    /// belongs on, the same rule §788 and §808 applied to World Chain and Arc.
    /// The marginal cost is honest and small: ONE Alchemy Portfolio call per
    /// wallet per pass, for the unmapped chains only, and it is not made at all
    /// by anyone who turns this row back off.
    static let defaultNetworkIDs = ["eth-mainnet", "base-mainnet", "arb-mainnet",
                                    "opt-mainnet", "matic-mainnet",
                                    "hyperliquid-mainnet", "monad-mainnet",
                                    "solana-mainnet", "robinhood-mainnet",
                                    "worldchain-mainnet", "arc-mainnet", "tempo-mainnet"]

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
    /// **EVERY KEY IS `.v2`, AND THAT IS THE REPAIR (prd §827a).** The `.v1`
    /// flags are POISONED: the loop that wrote them ran `defaults.set(true,
    /// forKey:)` BEFORE the guard that adds the chain, and the assignment that
    /// would have added it could not persist from inside `init`. So a device can
    /// hold "this chain was seeded" beside a saved set that never contained it —
    /// and §827's rule, which correctly skips a RECORDED seed, would skip it
    /// forever. Build 626 wrote `robinhoodSeeded.v1` on every phone it reached,
    /// which is exactly how the third fix would have failed as the fourth.
    ///
    /// A fresh generation applies the seed once more, now that the mechanism
    /// works (`effectiveIDs` is the one rule, and `init` persists explicitly).
    /// The accepted cost is stated rather than hidden: somebody who
    /// DELIBERATELY switched one of these off before today gets it back once,
    /// and switching it off again now sticks. That is the trade `seeded` has
    /// always named — a saved set predating an option means "never asked" — paid
    /// a second time because the first payment never cleared. All six bump
    /// together: the written-with-add and written-without-add cases are
    /// indistinguishable on disk, so there is no per-chain judgement to get
    /// wrong.
    private static let seeded: [(id: String, key: String)] = [
        ("solana-mainnet",      "wallet.chains.solanaSeeded.v2"),
        ("hyperliquid-mainnet", "wallet.chains.hyperevmSeeded.v2"),
        ("monad-mainnet",       "wallet.chains.monadSeeded.v2"),
        ("worldchain-mainnet",  "wallet.chains.worldchainSeeded.v2"),
        // Arc (2026-09-17, user: "add Arc chain also to the app and have it on
        // by default") — free like World Chain: Zerion's one call per wallet
        // already carries it, and it rides no Alchemy request.
        ("arc-mainnet",         "wallet.chains.arcSeeded.v2"),
        // Robinhood (2026-09-18, prd §826) — it shipped OFF and its toggle
        // could not work, so every install that ever saw the picker has it
        // stored as off for a reason that was never true. The seed row is what
        // reaches those installs; without it this default would only ever
        // apply to phones set up after today, which is the exact state Solana
        // was in before its own flag existed.
        ("robinhood-mainnet",   "wallet.chains.robinhoodSeeded.v2"),
        // Tempo (2026-09-17, prd §810, user: "lets add tempo on by default") —
        // free the same way: Zerion only, no Alchemy request.
        ("tempo-mainnet",       "wallet.chains.tempoSeeded.v1"),
    ]

    /// **THE ONE RULE FOR "WHICH CHAINS ARE ON" (prd §827).** Pure: it reads
    /// `UserDefaults` and writes nothing, so the static read path every ingest
    /// uses can call it freely.
    ///
    /// **Why it exists, and it is the whole of §827.** This logic lived TWICE —
    /// once in `init`, applying the `seeded` list, and once in
    /// `activeNetworkIDs()`, which did not. Every read in the app goes through
    /// the static one (`WalletIngest`, `WalletApprovals`, `MorphoDeFi`,
    /// `SafeBridge`, `WalletSafety`, `WalletActingParties`,
    /// `WalletConnectBridge`), and the instance's `selected` reached only the
    /// picker. So `seeded` — the mechanism whose own doc says a saved set that
    /// predates an option "means never asked, not off" — **never affected a
    /// single read.** It was decorative from the day it was written, which
    /// silently cost World Chain (§788), Arc (§808) and Robinhood (§826) on
    /// every install that had ever saved a chain set: the chain was ON in the
    /// picker and never once asked for on the wire. Three passes at "Robinhood
    /// shows nothing" ended here.
    ///
    /// A seed is applied until its flag is RECORDED, which `init` does — so
    /// turning a seeded chain back off afterwards still sticks (the promise
    /// `seeded` has always made).
    static func effectiveIDs(_ d: UserDefaults = .standard) -> [String] {
        guard let data = d.data(forKey: key),
              let saved = try? JSONDecoder().decode([String].self, from: data)
        else { return defaultNetworkIDs }   // never chosen — the defaults ARE the answer
        // Only ids still selectable survive (a chain retired from the list
        // shouldn't linger in the saved set).
        let known = Set(allNetworkIDs)
        let kept = saved.filter { known.contains($0) }
        guard !kept.isEmpty else { return defaultNetworkIDs }
        let pending = Set(seeded.filter { !d.bool(forKey: $0.key) }.map(\.id))
            .subtracting(kept)
        guard !pending.isEmpty else { return kept }
        return allNetworkIDs.filter { kept.contains($0) || pending.contains($0) }
    }

    private init() {
        let defaults = UserDefaults.standard
        let hadSaved = defaults.data(forKey: Self.key) != nil
        selected = Self.effectiveIDs(defaults)
        // RECORD the seeds, and PERSIST the set they produced. Both halves were
        // missing: the flags were written from inside the seeding loop that the
        // static path never ran, and the assignment that added a seeded chain
        // could not persist it, because Swift does not call a property observer
        // for an assignment made inside the owning type's initializer — so
        // `didSet { persist() }` never fired here. Explicit, so neither rests
        // on a language subtlety again.
        for seed in Self.seeded where !defaults.bool(forKey: seed.key) {
            defaults.set(true, forKey: seed.key)
        }
        if hadSaved { persist() }
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
    static func activeNetworkIDs() -> [String] { effectiveIDs() }
}
