import Foundation

/// Read-only JSON-RPC on Gnosis Chain (chain id 100), through two measured
/// public hosts — first that answers wins.
///
/// ONE caller: `SafeSigner`'s `getTransactionHash` cross-check on the `gno`
/// rail (2026-09-07, prd §425 amendment). That file's conduct guard requires
/// every host it names to be Safe's own, so a chain read it borrows lives
/// here, disclosed in `NetworkReach` under "Gnosis Chain".
///
/// The hosts were measured for the Gnosis Pay seat (2026-07-26, prd §222),
/// which owned this reader until prd §1318 removed the seat. What that
/// measurement found still holds for anyone adding a caller:
/// `gnosis-rpc.publicnode.com` 403s and `rpc.ankr.com/gnosis` demands auth,
/// hence this pair; both answered `eth_getLogs` and batched
/// `eth_getBlockByNumber`. UNMEASURED: `eth_call` and `eth_getCode`. If a host
/// refuses them the read is nil, `SafeSigner.prepare` answers
/// `.chainUnreadable`, and the app declines to sign — the safe failure.
///
/// READ ONLY, and that is structural rather than promised: `read` builds its
/// own body from a method and params, so no caller can turn it into a write
/// without editing this file.
enum GnosisChainRPC {

    private static let rpcs = ["https://rpc.gnosischain.com",
                               "https://rpc.gnosis.gateway.fm"]

    static func read(method: String, params: [Any]) async -> Any? {
        let body: [String: Any] = ["id": 1, "jsonrpc": "2.0",
                                   "method": method, "params": params]
        for rpc in rpcs {
            if let root = await IngestSupport.postJSON(rpc, body: body) as? [String: Any],
               let result = root["result"], !(result is NSNull) {
                return result
            }
        }
        return nil
    }
}
