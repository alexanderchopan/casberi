import Foundation

/// DeFi asks (2026-07-20; Morpho joined 2026-07-21) — "how's my Aave loan",
/// "what's my health factor", "how are my Morpho vaults". Same shape as
/// `WalletAsk`: the words name no corpus content to score, so the answer is
/// a live read (`WalletDeFi.positions` + `MorphoDeFi.book`), never the
/// retriever. "aave"/"morpho"/"health factor" are specific enough that a
/// plain substring match is safe — unlike "wallet", none of these collide
/// with an ordinary content search.
enum WalletDeFiAsk {
    static func matches(_ raw: String) -> Bool {
        let q = raw.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
        return q.contains("aave") || q.contains("morpho") || q.contains("health factor")
            || q.contains("liquidation") || q.contains("defi position")
            || q.contains("my loan") || q.contains("my loans")
    }

    /// nil ONLY when no EVM wallet is watched (the router points at
    /// Apps → Wallet then); an unreachable read or no open position still
    /// answers honestly. Both protocols are read in parallel; the sentence
    /// leads with the worst health factor anywhere (the number that can
    /// lose money), then the earn side.
    @MainActor
    static func answer() async -> String? {
        let watched = WalletStore.shared.addresses.map(\.address)
        let addresses = await WalletIngest.resolvedAddresses(watched).filter { ENS.isHexAddress($0) }
        guard !addresses.isEmpty else { return nil }
        async let aaveRead = WalletDeFi.positions(addresses: addresses)
        async let morphoRead = MorphoDeFi.book(addresses: addresses)
        let aave = await aaveRead
        let morpho = await morphoRead ?? MorphoDeFi.Book()

        // Worst health factor across BOTH protocols, with its protocol and
        // chain named — a position with no debt sorts last, never first.
        struct Debt { let hf: Double; let protocolName: String; let network: String }
        var debts: [Debt] = aave.compactMap { p in
            p.healthFactor.map { Debt(hf: $0, protocolName: "Aave", network: p.network) }
        }
        debts += morpho.positions.compactMap { p in
            p.healthFactor.map { Debt(hf: $0, protocolName: "Morpho", network: p.network) }
        }
        let deposits = morpho.vaults.reduce(0) { $0 + $1.usd }
            + morpho.positions.reduce(0) { $0 + $1.supplyUSD }

        var parts: [String] = []
        if let worst = debts.min(by: { $0.hf < $1.hf }) {
            let chain = WalletIngest.displayName(forNetwork: worst.network) ?? worst.network
            let count = debts.count
            let tail = count > 1 ? String(localized: " (\(count) borrow positions)") : ""
            parts.append(String(localized:
                "Health factor \(WalletIngest.format(worst.hf)) on \(worst.protocolName) (\(chain))\(tail)."))
        } else if !aave.isEmpty || !morpho.positions.isEmpty {
            parts.append(String(localized: "No debt outstanding."))
        }
        if deposits > 0 {
            let vaults = morpho.vaults.count
            parts.append(vaults > 1
                ? String(localized: "$\(WalletIngest.format(deposits)) earning across \(vaults) Morpho vaults.")
                : String(localized: "$\(WalletIngest.format(deposits)) earning on Morpho."))
        }
        guard !parts.isEmpty else {
            return String(localized: "No open Aave or Morpho positions right now.")
        }
        return parts.joined(separator: " ")
    }
}
