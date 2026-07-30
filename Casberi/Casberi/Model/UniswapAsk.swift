import Foundation

/// A Uniswap LP ask ("how's my uniswap position", "am I in range", "my lp") —
/// live read over `UniswapLiquidity.book`, no model. A SIBLING to
/// `WalletDeFiAsk`, not folded into it: that file's whole shape is borrowing
/// risk ("my loan", "health factor") — a liquidity position isn't a loan, and
/// the words don't collide (2026-07-30).
enum UniswapAsk {
    static func matches(_ raw: String) -> Bool {
        let q = raw.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
        return q.contains("uniswap") || q.contains("my lp") || q.contains("liquidity position")
            || q.contains("in range") || q.contains("out of range")
    }

    /// nil ONLY when no EVM wallet is watched (the router points at
    /// Apps → Wallet then); an unreachable read or no open position still
    /// answers honestly.
    @MainActor
    static func answer() async -> String? {
        let watched = WalletStore.shared.addresses.map(\.address)
        let addresses = await WalletIngest.resolvedAddresses(watched).filter { ENS.isHexAddress($0) }
        guard !addresses.isEmpty else { return nil }
        guard let book = await UniswapLiquidity.book(addresses: addresses), !book.isEmpty else {
            return String(localized: "No open Uniswap positions right now.")
        }
        let outOfRange = book.positions.filter { !$0.inRange }
        let totalFees = book.positions.compactMap(\.uncollectedFeeUSD).reduce(0, +)

        var parts: [String] = []
        if let worst = outOfRange.first {
            let pair = "\(worst.token0Symbol)/\(worst.token1Symbol)"
            let status = UniswapLiquidity.timeOutOfRange(address: worst.address, network: worst.network,
                                                         version: worst.version, tokenId: worst.tokenId)
                ?? String(localized: "out of range")
            let tail = outOfRange.count > 1
                ? String(localized: " (\(outOfRange.count) positions out of range)") : ""
            parts.append(String(localized: "\(pair) is \(status)\(tail)."))
        } else {
            let count = book.positions.count
            parts.append(count == 1
                ? String(localized: "Your position is in range.")
                : String(localized: "All \(count) positions are in range."))
        }
        if totalFees > 0 {
            parts.append(String(localized: "$\(WalletIngest.format(totalFees)) in uncollected fees."))
        }
        return parts.joined(separator: " ")
    }
}
