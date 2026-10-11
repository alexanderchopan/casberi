import Foundation

/// GAS AT THE HEAD OF THE WATCHLIST (prd §1247): what a transaction costs to
/// send on Ethereum and on Base right now, in gwei, read with `eth_gasPrice`
/// on the hosts the Wallet's send preview already reads (`WalletApprovals`,
/// `WalletPrepare`), and a "below N gwei" alert per chain.
///
/// A gas price is a reading like a price (§1223): it carries when it was
/// read, is stamped past `stampAfter` and is not drawn past `dropAfter`.
/// Gas moves with every block, so its stamp comes sooner than a price's.
///
/// Foundation-only and pure: `scripts/markets-selftest.sh` compiles it whole.
/// The read lives in `MarketsGas`.
enum GasPrice {

    struct Chain: Equatable {
        /// `WalletApprovals`' network id, which `rpcRead` takes.
        let network: String
        let name: String
    }

    static let chains: [Chain] = [
        Chain(network: "eth-mainnet", name: "Ethereum"),
        Chain(network: "base-mainnet", name: "Base"),
    ]

    static func chain(_ network: String) -> Chain? { chains.first { $0.network == network } }

    /// A gas alert's ref: the chain's, since a gas alert watches no row.
    static let refPrefix = "gas:"

    static func ref(_ network: String) -> String { refPrefix + network }

    static func network(fromRef ref: String) -> String? {
        guard ref.hasPrefix(refPrefix) else { return nil }
        let network = String(ref.dropFirst(refPrefix.count))
        return chain(network) == nil ? nil : network
    }

    /// Past this a gas reading is stamped with its age.
    static let stampAfter: TimeInterval = 15 * 60
    /// Past this it is not drawn, and an alert does not fire on it.
    static let dropAfter: TimeInterval = 6 * 3600

    static func stamped(at: Date, now: Date) -> Bool { now.timeIntervalSince(at) > stampAfter }
    static func drawable(at: Date, now: Date) -> Bool { now.timeIntervalSince(at) < dropAfter }

    /// `eth_gasPrice`'s hex wei as gwei, or nil for anything that is not a
    /// positive hex number.
    static func gwei(hex: String) -> Double? {
        var digits = hex.lowercased()
        if digits.hasPrefix("0x") { digits.removeFirst(2) }
        guard !digits.isEmpty, digits.count <= 16, let wei = UInt64(digits, radix: 16), wei > 0
        else { return nil }
        return Double(wei) / 1e9
    }

    /// "12", "2.4", "0.42", "0.00512": as many places as the size needs to
    /// say something, never "0.00".
    static func number(_ gwei: Double) -> String {
        if gwei >= 10 { return String(format: "%.0f", gwei) }
        if gwei >= 1 { return String(format: "%.1f", gwei) }
        if gwei >= 0.01 { return String(format: "%.2f", gwei) }
        return String(format: "%.3g", gwei)
    }

    static func text(_ gwei: Double) -> String { "\(number(gwei)) gwei" }

    /// The levels the alert menu offers from the gas now: three quarters and
    /// half of it, each rounded to the places `number` draws, so the menu
    /// says the level the alert holds. Nothing for no reading.
    static func choices(now gwei: Double) -> [Double] {
        guard gwei > 0 else { return [] }
        let levels = [gwei * 0.75, gwei * 0.5].compactMap { Double(number($0)) }.filter { $0 > 0 }
        var seen = Set<Double>()
        return levels.filter { seen.insert($0).inserted }
    }
}
