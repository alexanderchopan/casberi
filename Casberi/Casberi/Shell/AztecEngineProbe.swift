#if DEBUG
import Foundation

/// `-aztecEngineProbe YES` — starts your Aztec account's engine (prd §1700)
/// headless: serve and load the page, start Aztec's wallet on mainnet, make or
/// find the root in iCloud Keychain, derive the account, and NSLog
/// `aztecEngine| probe | <step> | <ms> | <detail>` for each. Reads only.
enum AztecEngineProbe {
    @MainActor
    static func run(_ raw: String) {
        // `used`: also mark the account used and read its holdings, so the
        // Wallet's row and Holdings › Private › Aztec show (prd §1700a).
        guard raw == "YES" || raw == "1" || raw == "used" else { return }
        Task { @MainActor in
            let start = Date()
            func say(_ step: String, _ detail: String) {
                NSLog("aztecEngine| probe | %@ | %d | %@", step, Int(Date().timeIntervalSince(start) * 1000), detail)
            }
            say("prover", AztecProver.isAvailable ? "native" : "none in this build")
            do {
                try await AztecEngine.shared.start()
                say("pageReady", AztecEngineServer.origin)
                let address = try await AztecEngine.shared.accountAddress()
                say("account", AddressTail.short(address))
                let chain = try await AztecEngine.shared.call("chain") as? [String: Any]
                say("chain", "\(chain?["chainId"] ?? "?") / \(chain?["version"] ?? "?")")
                if raw == "used" {
                    AztecAccountStore.shared.markUsed(address: address)
                    let read = await AztecAccountStore.shared.refresh()
                    let held = AztecAccountStore.shared.snapshot.holdings
                    say("holdings", "\(read ? "read" : "kept the last") · " + held.map { "\($0.name) \($0.privateUnits ?? "-")/\($0.publicUnits ?? "-")" }.joined(separator: ", "))
                }
            } catch {
                say("failed", error.localizedDescription)
            }
        }
    }
}
#endif
