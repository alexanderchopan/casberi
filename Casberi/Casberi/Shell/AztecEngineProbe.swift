#if DEBUG
import Foundation

/// `-aztecEngineProbe YES` — starts your Aztec account's engine (prd §1700)
/// headless: serve and load the page, start Aztec's wallet on mainnet, make or
/// find the root in iCloud Keychain, derive the account, and NSLog
/// `aztecEngine| probe | <step> | <ms> | <detail>` for each. Reads only.
enum AztecEngineProbe {
    @MainActor
    static func run(_ raw: String) {
        guard raw == "YES" || raw == "1" else { return }
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
            } catch {
                say("failed", error.localizedDescription)
            }
        }
    }
}
#endif
