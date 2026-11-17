import Foundation

/// **YOUR OWN NODE (prd §1509 item 5, Phase 5 of
/// `docs/specs/signing-safety-spec.md`).** Your account reads each network from
/// its two public nodes, through Tor (§1495). A network you give an address
/// reads from it instead, checked before it is used:
/// `eth_chainId` must be that network's, and `eth_blockNumber` must answer.
/// Then that network's reads go to your node and to nothing else (falling
/// back to the public nodes would send your address where you said not to), and
/// directly, not through Tor: a home node is on your own network, and Tor
/// does not hide your address from your own node. Bundlers stay public: a
/// node is not a bundler.
///
/// Pure (Foundation): the address rule, the check's verdict and its words,
/// held by `own-node-selftest.sh`. The store and the requests are the app's.
enum OwnNode {
    /// What is kept: each network's checked address. **No switch (prd
    /// §1833):** a network with an address reads from it, one without reads
    /// the public nodes. A setting kept with the old switch OFF forgets its
    /// addresses on decode, so turning it off still means off.
    struct Settings: Codable, Equatable, Sendable {
        /// Chain id → the address that answered its check.
        var nodes: [String: String] = [:]

        init(nodes: [String: String] = [:]) { self.nodes = nodes }

        func address(for chainId: Int) -> String? { nodes[String(chainId)] }

        private enum CodingKeys: String, CodingKey { case on, nodes }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let on = try c.decodeIfPresent(Bool.self, forKey: .on) ?? true
            nodes = on ? (try c.decodeIfPresent([String: String].self, forKey: .nodes) ?? [:]) : [:]
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(nodes, forKey: .nodes)
        }
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

    /// The words the tray, the page and the Security row share (prd §1833):
    /// "Public" is what a network without your node reads from, never
    /// "Casberi's list" (there is no list of ours, only each network's two
    /// public nodes); the field says what to paste.
    static var publicWord: String { String(localized: "Public") }
    static var fieldPrompt: String { String(localized: "Your node's address, https://…") }
    static var usePublic: String { String(localized: "Use public nodes") }

    /// A paste, not a keystroke: the text grew or changed by more than one
    /// character at once. A paste checks itself; typing waits for Return.
    static func isPaste(from old: String, to new: String) -> Bool {
        abs(new.count - old.count) > 1 && normalized(new) != nil
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
