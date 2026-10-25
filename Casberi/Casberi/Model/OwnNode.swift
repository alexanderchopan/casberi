import Foundation

/// **YOUR OWN NODE (prd §1509 item 5, Phase 5 of
/// `docs/signing-safety-spec.md`).** Your account reads each network from
/// Casberi's list of public nodes, through Tor (§1495). With your own node on,
/// a network takes an address you give it instead, checked before it is used:
/// `eth_chainId` must be that network's, and `eth_blockNumber` must answer.
/// Then that network's reads go to your node and to nothing else (falling
/// back to the list would send your address where you said not to), and
/// directly, not through Tor: a home node is on your own network, and Tor
/// does not hide your address from your own node. Bundlers stay the list: a
/// node is not a bundler.
///
/// Pure (Foundation): the address rule, the check's verdict and its words,
/// held by `own-node-selftest.sh`. The store and the requests are the app's.
enum OwnNode {
    /// What is kept: the switch, and each network's checked address.
    struct Settings: Codable, Equatable, Sendable {
        var on = false
        /// Chain id → the address that answered its check.
        var nodes: [String: String] = [:]

        func address(for chainId: Int) -> String? { on ? nodes[String(chainId)] : nil }
    }

    /// The address as typed, made a URL: `http` or `https` only (a home node
    /// on the local network is often plain `http`), a host, nothing else.
    /// A bare host gets `https://`.
    static func normalized(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(" ") else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let url = URL(string: withScheme), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", let host = url.host, !host.isEmpty else { return nil }
        return withScheme
    }

    /// What the address said to the two questions.
    enum Verdict: Equatable, Sendable {
        case answers(chainId: Int, block: Int)
        /// It answered for another chain: never used.
        case wrongChain(Int)
        case noAnswer
        case notAnAddress
    }

    /// A JSON-RPC quantity ("0x2105") as a number.
    static func quantity(_ hex: String?) -> Int? {
        guard let hex, hex.hasPrefix("0x"), hex.count > 2 else { return nil }
        return Int(hex.dropFirst(2), radix: 16)
    }

    static func verdict(expected: Int, chainId: String?, block: String?) -> Verdict {
        guard let got = quantity(chainId) else { return .noAnswer }
        guard got == expected else { return .wrongChain(got) }
        guard let height = quantity(block) else { return .noAnswer }
        return .answers(chainId: got, block: height)
    }

    /// The row's words, and whether they are the green ones: "Chain 8453 ·
    /// block 31,882,104", or the refusal.
    static func words(_ v: Verdict, network: String, expected: Int) -> (text: String, ok: Bool) {
        switch v {
        case .answers(let chain, let block):
            return (String(localized: "Chain \(String(chain)) · block \(block.formatted(.number.grouping(.automatic)))"), true)
        case .wrongChain(let got):
            return (String(localized: "Answers for chain \(String(got)), not \(network)'s \(String(expected))"), false)
        case .noAnswer:
            return (String(localized: "Did not answer as a node"), false)
        case .notAnAddress:
            return (String(localized: "Not an address"), false)
        }
    }
}
