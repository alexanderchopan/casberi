import Foundation

/// The one network call behind `SafeSimulation` (prd §1249): a pending Safe
/// transaction, simulated as the Safe's own call on Alchemy, read when the
/// sign block opens — in its `.task`, never in a body (§628).
///
/// Kept out of `SafeSigner.swift` on purpose: that file may reach Safe's own
/// hosts and nothing else (`safetx-selftest.sh`'s host guard), and the
/// simulation is not part of deciding whether a signature may happen. It is
/// information beside the decision, and a failure here never refuses or
/// allows anything — it only draws "not simulated" and why.
///
/// The host is the Alchemy per-chain host every wallet read already uses,
/// with the app's one shipped key (`IngestSupport.alchemyKey`); each of the
/// five is declared in `NetworkReach`, so this adds no reach.
///
/// UNMEASURED: no build host has sent `alchemy_simulateAssetChanges`. The
/// shapes are authored from Alchemy's reference; `SafeSimulation.parse` reads
/// them defensively and says "not simulated" on anything it does not know.
enum SafeSimulator {

    enum Outcome: Equatable {
        case simulated(SafeSimulation.Reading)
        case notSimulated(SafeSimulation.Skip)
    }

    static func simulate(chainId: Int, safe: String, tx: SafeTransaction,
                         reading: SafeCalldata) async -> Outcome {
        let plan = SafeSimulation.plan(chainId: chainId, safe: safe, tx: tx, reading: reading)
        if case .skip(let why) = plan { return .notSimulated(why) }
        guard let network = SafeSimulation.networks[chainId],
              let body = SafeSimulation.requestBody(plan)
        else { return .notSimulated(.chainNotServed) }
        let url = "https://\(network).g.alchemy.com/v2/\(IngestSupport.alchemyKey)"
        let (json, _) = await IngestSupport.postJSONStatus(url, body: body)
        let isBundle: Bool
        if case .bundle = plan { isBundle = true } else { isBundle = false }
        guard let answer = SafeSimulation.parse(json, safe: safe, bundle: isBundle)
        else { return .notSimulated(.failed) }
        return .simulated(answer)
    }
}
