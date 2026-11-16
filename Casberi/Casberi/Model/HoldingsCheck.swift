import Foundation

/// **THE WALLET'S HOLDINGS, CHECKED AGAINST ETHEREUM ITSELF (prd §1825).**
///
/// Zerion and Alchemy say what a wallet holds; a provider can be wrong, stale
/// or lying, and Tor does nothing about that. After each live holdings read,
/// the wallet's biggest Ethereum holdings are read again through Kohaku's
/// verified provider (`PrivacyEngine.verifyHoldings`, Colibri in hybrid mode),
/// which checks every answer against the beacon chain's signatures. A holding
/// that disagrees on two checks in a row says so on its row.
///
/// The rules, Foundation-only so `holdings-check-selftest.sh` drives them.
enum HoldingsCheck {

    /// Colibri proves Ethereum (and Gnosis, which the Wallet does not check);
    /// Base and the other rollups are "upcoming" in the pinned package.
    static let network = "eth-mainnet"
    static let chainId = 1
    /// The node the Wallet already reads Ethereum through (`NetworkReach`'s
    /// Wallet entries); the prover is never sent an address in hybrid mode.
    static let rpcUrl = "https://rpc.mevblocker.io"
    /// About a second a token over Tor, measured: eight keeps a wallet's
    /// check under ten seconds.
    static let cap = 8
    static let floorUSD = 1.0
    /// One check a wallet per holdings window.
    static let every: TimeInterval = 10 * 60

    struct Held: Equatable, Sendable {
        /// nil is ETH itself.
        let contract: String?
        let amount: Double
        let usd: Double
    }

    /// What is worth checking: on Ethereum, a dollar or more, a real amount,
    /// biggest first, `cap` at most. A contract that is not an address (a
    /// venue's placeholder) is left out: it has no balance to prove.
    static func pick(network: [String], contract: [String?], amount: [Double?], usd: [Double]) -> [Held] {
        var out: [Held] = []
        for i in network.indices where network[i] == Self.network {
            guard let a = amount[i], a.isFinite, a > 0, usd[i] >= floorUSD else { continue }
            if let c = contract[i], !isAddress(c) { continue }
            out.append(Held(contract: contract[i]?.lowercased(), amount: a, usd: usd[i]))
        }
        return Array(out.sorted { $0.usd == $1.usd ? ($0.contract ?? "") < ($1.contract ?? "") : $0.usd > $1.usd }.prefix(cap))
    }

    static func isAddress(_ text: String) -> Bool {
        text.range(of: #"^0x[0-9a-fA-F]{40}$"#, options: .regularExpression) != nil
    }

    /// Whether the provider's amount is the chain's. A provider hands a
    /// decimal-adjusted Double, so a part in a million is rounding, not a
    /// different balance.
    static func matches(read: Double, proven: Double) -> Bool {
        let scale = max(abs(read), abs(proven))
        return abs(read - proven) <= max(1e-9, scale * 1e-6)
    }

    /// One holding's key: whose, then `HiddenTokens.contractKey`'s spelling,
    /// so a row's `Part` finds it.
    static func key(owner: String, contract: String?) -> String {
        "\(owner):\(network):\(contract ?? "native")".lowercased()
    }

    /// Two in a row. A balance can move between the provider's read and the
    /// proof (a transfer landing), so one disagreement is only a suspicion;
    /// the next check, a holdings window later, confirms or clears it. A
    /// token that could not be proven changes nothing.
    struct Ledger: Equatable {
        private(set) var suspect: Set<String> = []
        private(set) var mismatched: Set<String> = []

        mutating func record(_ key: String, matched: Bool?) {
            guard let matched else { return }
            if matched {
                suspect.remove(key)
                mismatched.remove(key)
            } else if suspect.contains(key) || mismatched.contains(key) {
                suspect.remove(key)
                mismatched.insert(key)
            } else {
                suspect.insert(key)
            }
        }

        /// After a wallet's pass: a holding it no longer checks (sold, or out
        /// of the biggest eight) says nothing any more.
        mutating func finish(owner: String, checked: Set<String>) {
            let prefix = owner.lowercased() + ":"
            suspect = suspect.filter { !$0.hasPrefix(prefix) || checked.contains($0) }
            mismatched = mismatched.filter { !$0.hasPrefix(prefix) || checked.contains($0) }
        }
    }

    /// One token's verdict: the proven amount against the read one, or nil
    /// when the proof did not come.
    static func verdict(read: Double, proven: String?) -> Bool? {
        guard let proven, let value = Double(proven), value.isFinite else { return nil }
        return matches(read: read, proven: value)
    }
}
