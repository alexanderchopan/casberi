import Foundation

/// Aave asks (2026-07-20) — "how's my Aave loan", "what's my health factor".
/// Same shape as `WalletAsk`: the words name no corpus content to score, so
/// the answer is a live read (`WalletDeFi.positions`), never the retriever.
/// "aave"/"health factor"/"liquidation" are specific enough that a plain
/// substring match is safe — unlike "wallet", none of these collide with an
/// ordinary content search.
enum WalletDeFiAsk {
    static func matches(_ raw: String) -> Bool {
        let q = raw.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
        return q.contains("aave") || q.contains("health factor")
            || q.contains("liquidation") || q.contains("defi position")
            || q.contains("my loan") || q.contains("my loans")
    }

    /// nil ONLY when no EVM wallet is watched (the router points at
    /// Apps → Wallet then); an unreachable read or no open position still
    /// answers honestly.
    @MainActor
    static func answer() async -> String? {
        let watched = WalletStore.shared.addresses.map(\.address)
        let addresses = await WalletIngest.resolvedAddresses(watched).filter { ENS.isHexAddress($0) }
        guard !addresses.isEmpty else { return nil }
        let positions = await WalletDeFi.positions(addresses: addresses)
        guard !positions.isEmpty else {
            return String(localized: "No open Aave positions right now.")
        }
        // The worst health factor is the one worth leading with — a
        // position with no debt sorts last (`.infinity`), never first.
        guard let worst = positions.min(by: {
            ($0.healthFactor ?? .infinity) < ($1.healthFactor ?? .infinity)
        }), let hf = worst.healthFactor else {
            return positions.count == 1
                ? String(localized: "1 Aave position, no debt outstanding.")
                : String(localized: "\(positions.count) Aave positions, no debt outstanding.")
        }
        let chain = WalletIngest.displayName(forNetwork: worst.network) ?? worst.network
        let tail = positions.count > 1 ? String(localized: " (\(positions.count) positions)") : ""
        return String(localized: "Health factor \(WalletIngest.format(hf)) on \(chain)\(tail).")
    }
}
