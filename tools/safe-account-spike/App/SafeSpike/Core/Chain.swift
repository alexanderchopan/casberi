import Foundation

/// JSON-RPC to a node and to an ERC-4337 bundler — public, keyless,
/// interchangeable (measured 2026-10-19, `docs/safe-wallet-spec.md` §7).
enum Chain {
    struct Network: Sendable {
        let name: String
        let chainId: Int
        let rpc: String
        /// Tried in order; both answered EntryPoint v0.7 keyless.
        let bundlers: [String]
    }

    static let baseSepolia = Network(
        name: "Base Sepolia", chainId: 84532, rpc: "https://sepolia.base.org",
        bundlers: ["https://public.pimlico.io/v2/84532/rpc", "https://api.candide.dev/public/v3/84532"])

    struct RPCError: Error, CustomStringConvertible {
        let message: String
        var description: String { message }
    }

    /// One call; the `result` as JSON, or the node's error as a readable line.
    static func call(_ url: String, _ method: String, _ params: [Any]) async throws -> Any {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.timeoutInterval = 30
        request.httpBody = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 1, "method": method, "params": params])
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RPCError(message: "\(method): not JSON — \(String(decoding: data.prefix(200), as: UTF8.self))")
        }
        if let error = object["error"] as? [String: Any] {
            let detail = (error["data"].map { " · \($0)" }) ?? ""
            throw RPCError(message: "\(method): \(error["message"] ?? error)\(detail)")
        }
        return object["result"] ?? NSNull()
    }

    static func ethCall(_ net: Network, to: String, data: String) async throws -> String {
        let result = try await call(net.rpc, "eth_call", [["to": to, "data": data], "latest"])
        guard let hex = result as? String else { throw RPCError(message: "eth_call: no result") }
        return hex
    }

    static func balance(_ net: Network, _ address: String) async throws -> UInt64 {
        let hex = try await call(net.rpc, "eth_getBalance", [address, "latest"]) as? String ?? "0x0"
        return UInt64(hex.dropFirst(2), radix: 16) ?? 0
    }

    static func codeExists(_ net: Network, _ address: String) async throws -> Bool {
        let hex = try await call(net.rpc, "eth_getCode", [address, "latest"]) as? String ?? "0x"
        return hex.count > 2
    }

    /// The first bundler that answers; the error of the last if none does.
    static func bundler(_ net: Network, _ method: String, _ params: [Any]) async throws -> Any {
        var last: Error = RPCError(message: "no bundler")
        for url in net.bundlers {
            do { return try await call(url, method, params) } catch let error as RPCError {
                // A refusal of the operation itself is the answer, not an outage.
                if error.message.contains("AA") || error.message.lowercased().contains("signature") { throw error }
                last = error
            } catch { last = error }
        }
        throw last
    }
}
