import Foundation
import Observation

/// What the holdings check has found (prd §1825), and the runner that asks.
/// One wallet at a time, after the holdings read that named it, never more
/// than once a holdings window; a check that cannot run says nothing.
@MainActor
@Observable
final class HoldingsCheckStore {
    static let shared = HoldingsCheckStore()
    #if DEBUG
    private static let sample = UserDefaults.standard.string(forKey: "holdingsMismatchSample")?.uppercased()
    #endif

    private(set) var ledger = HoldingsCheck.Ledger()
    @ObservationIgnored private var lastRun: [String: Date] = [:]
    @ObservationIgnored private var waiting: [(owner: String, held: [HoldingsCheck.Held])] = []
    @ObservationIgnored private var running = false

    /// Whether any wallet's share of this position disagreed with Ethereum
    /// twice in a row.
    func mismatched(_ position: WalletPortfolio.Position) -> Bool {
        #if DEBUG
        // `-holdingsMismatchSample <SYMBOL>`: draw that row's amber line on a
        // simulator, where no real disagreement is ever seen (a reel's
        // capture, 2026-11-16). Read once, never in the store's ledger.
        if let sample = Self.sample, sample == position.symbol.uppercased() { return true }
        #endif
        guard !ledger.mismatched.isEmpty else { return false }
        return position.parts.contains { ledger.mismatched.contains("\($0.holder):\($0.key)".lowercased()) }
    }

    /// A live holdings read of `owner` just landed: check it when its turn
    /// comes. The demo's wallets are not anyone's, and are never asked.
    func consider(owner: String, held: [HoldingsCheck.Held]) {
        let owner = owner.lowercased()
        guard HoldingsCheck.isAddress(owner), !held.isEmpty, !DemoMode.isActive else { return }
        guard Date().timeIntervalSince(lastRun[owner] ?? .distantPast) > HoldingsCheck.every else { return }
        waiting.removeAll { $0.owner == owner }
        waiting.append((owner, held))
        guard !running else { return }
        running = true
        Task { await self.drain() }
    }

    private func drain() async {
        while !waiting.isEmpty {
            let next = waiting.removeFirst()
            lastRun[next.owner] = Date()
            await check(owner: next.owner, held: next.held)
        }
        running = false
    }

    private func check(owner: String, held: [HoldingsCheck.Held]) async {
        do {
            let read = try await PrivacyEngine.shared.verifyHoldings(owner: owner, tokens: held.map(\.contract))
            var checked: Set<String> = []
            var matched = 0, differ = 0, unknown = 0
            for token in read.tokens {
                let contract = token.contract?.lowercased()
                guard let mine = held.first(where: { $0.contract == contract }) else { continue }
                let key = HoldingsCheck.key(owner: owner, contract: contract)
                checked.insert(key)
                let verdict = HoldingsCheck.verdict(read: mine.amount, proven: token.amount)
                ledger.record(key, matched: verdict)
                switch verdict {
                case true?: matched += 1
                case false?: differ += 1
                case nil: unknown += 1
                }
            }
            ledger.finish(owner: owner, checked: checked)
            NSLog("holdingsCheck| %@ | %d match | %d differ | %d unproven | %d ms",
                  AddressTail.short(owner), matched, differ, unknown, read.ms)
        } catch {
            // Proves nothing either way; asked again a window later.
            lastRun[owner] = nil
            NSLog("holdingsCheck| %@ | unreachable | %@", AddressTail.short(owner), String(describing: error))
        }
    }
}
