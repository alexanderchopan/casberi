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

    private static func ask(_ url: String, _ method: String) async -> String? {
        let body: [String: Any] = ["jsonrpc": "2.0", "id": 1, "method": method, "params": []]
        let (json, _) = await IngestSupport.postJSONBody(url, body: body, service: service)
        return (json as? [String: Any])?["result"] as? String
    }
}
