import Foundation
import Observation

/// Ethereum beacon-chain validators (2026-07-27) — the ETH half of the
/// rotki-comparison staking gap Solana's `SolanaStaking` already closed.
/// The two halves are solved differently on purpose: a Solana stake account
/// can be FOUND from a wallet address (the program's account set is
/// filterable by withdraw authority — see `SolanaStaking`'s doc header), but
/// Ethereum's beacon chain has no equivalent filter — the only free path
/// from "a wallet address" to "its validators" is a full scan of deposit
/// events since genesis, which is not something a rate-limited public RPC
/// can serve. What IS free and fast is looking a validator up by its own
/// INDEX — and a person running a validator already knows it (their staking
/// client shows it, or it's one lookup away on any explorer). So this bridge
/// asks for the index directly rather than trying to derive it — provenance,
/// not inference, the same rule address-book watching already keeps (prd
/// §169).
///
/// "The thing IS the watch" doesn't fit here the way it does for
/// Stocktwits/tokens (`StockWatch`) — this needs to be read from
/// `WalletIngest.portfolioRead`, a context-free static function with no
/// ModelContext to scan a corpus through. So it's a persisted store instead,
/// the same shape `WalletStore` already uses for wallet addresses.
@Observable
final class EthValidatorStore {
    static let shared = EthValidatorStore()
    private static let key = "eth.validators"

    struct Watched: Codable, Identifiable, Equatable {
        var id: Int { index }
        let index: Int
        /// A name the person gave it — optional, the index shows if empty.
        var label: String = ""
    }

    var watched: [Watched] {
        didSet { persist() }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([Watched].self, from: data) {
            watched = decoded
        } else {
            watched = []
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(watched) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }

    @discardableResult
    func add(index: Int, label: String = "") -> Bool {
        guard !watched.contains(where: { $0.index == index }) else { return false }
        watched.append(Watched(index: index, label: label))
        return true
    }

    func remove(index: Int) {
        watched.removeAll { $0.index == index }
    }
}

/// The live read — balance and status for watched validators, and the
/// combined-total fold-in. Keyless, via a public beacon-node REST API
/// (`ethereum-beacon-api.publicnode.com`, the standard Ethereum Beacon API
/// spec) — live-verified 2026-07-27: `/eth/v1/beacon/states/head/validators`
/// answers a comma-joined `id` list in one request (3 indices, ~0.2s), an
/// unknown index 404s honestly ("unknown validator: …"), and no rate-limit
/// headers showed across 5 back-to-back calls.
enum EthValidatorRead {

    private static let host = "https://ethereum-beacon-api.publicnode.com"

    enum Status: String { case active, activating, exiting, exited, unknown }

    struct Position: Identifiable {
        var id: Int { index }
        let index: Int
        /// Gwei, straight off the API — kept as the raw unit so a caller
        /// decides its own display precision; `eth` below is the ETH form.
        let balanceGwei: Int
        let status: Status
        var eth: Double { Double(balanceGwei) / 1e9 }
    }

    /// One request for every watched index — the batched shape the API
    /// itself offers (`?id=1,2,3`), matching `SolanaStaking`/`SolanaActivity`'s
    /// own "one call, not N" rule. nil only when the RPC couldn't be reached
    /// at all; a validator index that doesn't exist is simply absent from the
    /// result, not a failure of the whole read.
    static func positions(indices: [Int]) async -> [Position]? {
        guard !indices.isEmpty else { return [] }
        let ids = indices.map(String.init).joined(separator: ",")
        guard let url = URL(string: "\(host)/eth/v1/beacon/states/head/validators?id=\(ids)"),
              let root = await IngestSupport.getJSON(url) as? [String: Any],
              let rows = root["data"] as? [[String: Any]]
        else { return nil }
        return rows.compactMap { row in
            guard let indexStr = row["index"] as? String, let index = Int(indexStr),
                  let balanceStr = row["balance"] as? String, let balance = Int(balanceStr)
            else { return nil }
            let statusRaw = (row["status"] as? String) ?? ""
            let status: Status = statusRaw.hasPrefix("active") ? .active
                : statusRaw.hasPrefix("pending") ? .activating
                : statusRaw.hasPrefix("exited") ? .exited
                : statusRaw.contains("exit") ? .exiting
                : .unknown
            return Position(index: index, balanceGwei: balance, status: status)
        }
    }

    /// Total USD across every watched validator that hasn't fully exited —
    /// an exiting-but-not-yet-withdrawn validator still holds its balance, the
    /// same "still counted until it's actually gone" rule `SolanaStaking`
    /// applies to a cooling-down stake account. Priced off Kraken's keyless
    /// public book, the same source every exchange balance here already
    /// uses. nil only on an unreachable RPC; no watched validators is a real
    /// 0, not a failure.
    @MainActor
    static func totalUSD() async -> Double? {
        let indices = EthValidatorStore.shared.watched.map(\.index)
        guard !indices.isEmpty else { return 0 }
        guard let positions = await positions(indices: indices) else { return nil }
        let live = positions.filter { $0.status != .exited }
        guard !live.isEmpty else { return 0 }
        let prices = await ExchangeBridge.krakenPrices(symbols: ["ETH"])
        guard let ethPrice = prices["ETH"] else { return nil }
        return live.reduce(0) { $0 + $1.eth * ethPrice }
    }

    /// Registers (or clears) the ETH Validators seat with the live watched
    /// count — mirrors `StockWatch.registerBridge`.
    @MainActor
    static func registerBridge(store: BridgeStore) {
        let count = EthValidatorStore.shared.watched.count
        guard count > 0 else { store.remove("ethvalidators"); return }
        store.registerConnected(
            id: "ethvalidators", name: "ETH Validators",
            proof: "\(count) validator\(count == 1 ? "" : "s") watched",
            can: ["Reads the balance and status of the validator indices you name.",
                  "Read-only — never stakes, exits, or moves anything."])
    }

    /// `-ethValidatorProbe <index[,index]>` — NSLogs each watched-or-named
    /// index's balance and status, or the honest "unreachable" read.
    static func probe(indices: [Int]) async -> String {
        guard let positions = await positions(indices: indices) else { return "couldn't reach the beacon API" }
        guard !positions.isEmpty else { return "no matching validators" }
        return positions.map { p in
            "#\(p.index): \(String(format: "%.4f", p.eth)) ETH, \(p.status.rawValue)"
        }.joined(separator: " | ")
    }
}
