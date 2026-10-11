import Foundation
import Observation

/// The gas the Watchlist's head draws and the gas alerts check (prd §1250):
/// `eth_gasPrice` on Ethereum and Base, through `WalletApprovals.rpcRead`, the
/// keyless hosts the Wallet's send preview reads its fee on
/// (`WalletPrepare`). Held a minute, so a room redrawn or an alert check in
/// the same pass asks once; a read that fails leaves the last reading with
/// its own time, which `GasPrice` stamps and then drops (§83).
@MainActor
@Observable
final class MarketsGas {
    static let shared = MarketsGas()

    struct Reading: Equatable {
        let gwei: Double
        let at: Date
    }

    private(set) var readings: [String: Reading] = [:]
    private var inFlight = false
    private static let freshFor: TimeInterval = 60

    private init() {}

    func reading(_ network: String) -> Reading? { readings[network] }

    /// Reads every chain whose reading is older than a minute.
    func load() async {
        // The demo reaches nothing (§217).
        guard !DemoMode.isActive, !inFlight else { return }
        let now = Date.now
        let stale = GasPrice.chains.map(\.network).filter { network in
            guard let last = readings[network] else { return true }
            return now.timeIntervalSince(last.at) > Self.freshFor
        }
        guard !stale.isEmpty else { return }
        inFlight = true
        defer { inFlight = false }
        let read = await IngestSupport.boundedGather(stale, maxConcurrent: 2) { network in
            (network, await WalletApprovals.rpcRead(network: network, method: "eth_gasPrice",
                                                    params: []) as? String)
        }
        let stamp = Date.now
        for (network, hex) in read {
            guard let hex, let gwei = GasPrice.gwei(hex: hex) else { continue }
            readings[network] = Reading(gwei: gwei, at: stamp)
        }
    }
}
