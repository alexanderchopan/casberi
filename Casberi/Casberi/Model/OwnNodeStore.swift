import Foundation

/// Where your own node's addresses are kept, and the check an address must
/// pass before it is (prd §1509 item 5, §1517). `YourAccountChain.rpc` reads
/// `settings` on every request, so it is held in memory behind a lock and
/// written through `DefaultsWrite` (`defaults-lock-audit.py`).
enum OwnNodeStore {
    /// The service every request to your node names to `NetworkLedger`: the
    /// address is typed by you, so `NetworkReach` declares the family, not
    /// the host (the Logos node's rule, prd §989).
    static let service = "Your own node"
    private static let key = "yourAccount.ownNode"
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cached: OwnNode.Settings?

    static var settings: OwnNode.Settings {
        lock.lock(); defer { lock.unlock() }
        if let cached { return cached }
        let read = UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(OwnNode.Settings.self, from: $0) }
            ?? OwnNode.Settings()
        cached = read
        return read
    }

    static func save(_ s: OwnNode.Settings) {
        lock.lock(); cached = s; lock.unlock()
        if let data = try? JSONEncoder().encode(s) { DefaultsWrite.set(data, forKey: key) }
    }

    /// Ask an address the two questions: its chain id, and its newest block.
    /// Directly, never through Tor: the host is yours.
    static func check(_ text: String, chainId: Int) async -> (verdict: OwnNode.Verdict, url: String?) {
        guard let url = OwnNode.normalized(text) else { return (.notAnAddress, nil) }
        async let chain = ask(url, "eth_chainId")
        async let block = ask(url, "eth_blockNumber")
        return (OwnNode.verdict(expected: chainId, chainId: await chain, block: await block), url)
    }

    /// **AZTEC, ONE MORE NETWORK (prd §1700f item 3).** Kept under the
    /// rollup's version, Aztec mainnet's identity as a chain id is Ethereum's.
    static let aztecKey = 2_070_860_440
    static var aztecNode: String? { settings.address(for: aztecKey) }

    /// An Aztec node's two answers: its rollup version (mainnet's, or
    /// refused) and its newest block.
    static func checkAztec(_ text: String) async -> (verdict: OwnNode.Verdict, url: String?) {
        guard let url = OwnNode.normalized(text) else { return (.notAnAddress, nil) }
        let body: [String: Any] = ["jsonrpc": "2.0", "id": 1, "method": "node_getNodeInfo", "params": []]
        let (json, _) = await IngestSupport.postJSONBody(url, body: body, service: service)
        guard let info = (json as? [String: Any])?["result"] as? [String: Any] else { return (.noAnswer, url) }
        let version = (info["rollupVersion"] as? NSNumber)?.intValue ?? Int(info["rollupVersion"] as? String ?? "") ?? 0
        guard version == aztecKey else { return (.wrongChain(version), url) }
        let blockBody: [String: Any] = ["jsonrpc": "2.0", "id": 2, "method": "node_getBlockNumber", "params": []]
        let (blockJSON, _) = await IngestSupport.postJSONBody(url, body: blockBody, service: service)
        let block = ((blockJSON as? [String: Any])?["result"] as? NSNumber)?.intValue
        return (block.map { .answers(chainId: aztecKey, block: $0) } ?? .noAnswer, url)
    }

    private static func ask(_ url: String, _ method: String) async -> String? {
        let body: [String: Any] = ["jsonrpc": "2.0", "id": 1, "method": method, "params": []]
        let (json, _) = await IngestSupport.postJSONBody(url, body: body, service: service)
        return (json as? [String: Any])?["result"] as? String
    }
}
