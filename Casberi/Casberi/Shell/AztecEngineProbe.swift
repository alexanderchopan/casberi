#if DEBUG
import Foundation

/// `-aztecEngineProbe YES` — starts your Aztec account's engine (prd §1700)
/// headless: serve and load the page, start Aztec's wallet on mainnet, make or
/// find the root in iCloud Keychain, derive the account, and NSLog
/// `aztecEngine| probe | <step> | <ms> | <detail>` for each, private gas
/// (prd §1700aa) among them. Reads only.
enum AztecEngineProbe {
    @MainActor
    static func run(_ raw: String) {
        // `used`: also mark the account used and read its holdings, so the
        // Wallet's row and Holdings › Private › Aztec show (prd §1700a).
        // `recycle`: then fail one call as a dead store does, and read the
        // account and the chain again from the page that replaces it.
        guard raw == "YES" || raw == "1" || raw == "used" || raw == "recycle" else { return }
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
                // Private gas (prd §1700aa): whether the shared fee contract is
                // this rollup's, what the account keeps in it, and where a gas
                // deposit would go. Reads and a derivation; nothing is sent.
                let fees = try await AztecEngine.shared.call("privateFees") as? [String: Any]
                say("privateFees", fees?["on"] as? Bool == true
                    ? "on · \(AddressTail.short(fees?["address"] as? String ?? "")) · holds \(fees?["balance"] ?? "?")" : "off")
                let plan = try await AztecEngine.shared.call("feeJuicePlan", ["1"]) as? [String: Any]
                say("gasPlan", "\(plan?["kind"] ?? "?") · to \(AddressTail.short(plan?["to"] as? String ?? ""))")
                if raw == "recycle" {
                    AztecEngine.shared.failNextAsk = true
                    let again = try await AztecEngine.shared.accountAddress()
                    say("recycled", again == address ? "same account from a new page" : "A DIFFERENT ACCOUNT")
                    let after = try await AztecEngine.shared.call("chain") as? [String: Any]
                    say("chainAfter", "\(after?["chainId"] ?? "?") / \(after?["version"] ?? "?")")
                }
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

#if DEBUG
import SwiftUI
import UIKit

/// `-aztecBrowser <url>` — open an Aztec app in Casberi's browser at mount
/// (prd §1700 step 3), over everything, with a Close button; DEBUG's door
/// until Library and the account's page carry the real ones. `-autoApprove
/// YES` is not honoured here: every ask waits for a hand.
/// `-aztecBrowserEthereum <url>` opens the page with your account as its
/// Ethereum provider instead (Human Passport's door, prd §1700e).
/// `-aztecAppEthereum <url>` opens it as Apps on Aztec does, sending on
/// (prd §1700k); `-coSignerSample <0x…>` stands in for your co-signer there,
/// so Connect's quiet line shows on the simulator (prd §1700l);
/// `-connectRetrySample YES` makes the first Connect the retry after a
/// sign-in the app turned down, co-signer first.
enum AztecBrowserProbe {
    @MainActor
    static func open(_ raw: String, ethereum: Bool = false, sends: Bool = false) {
        guard let url = URL(string: raw), url.scheme == "https" || url.host == "localhost" || url.host == "127.0.0.1" else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard let root = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                .flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController else { return }
            var top = root
            while let next = top.presentedViewController { top = next }
            // Presented as the real doors present it (`SettingsHome`, a
            // thing's sheet): a sheet with its grabber, pulled down to
            // close. It was a full-screen cover under a navigation bar with
            // a Close button, so a walk on the simulator judged chrome the
            // phone never draws (2026-11-12).
            let host = UIHostingController(rootView:
                AztecBrowserView(url: url, aztec: !ethereum || sends, ethereum: ethereum, sends: sends))
            host.modalPresentationStyle = .pageSheet
            host.sheetPresentationController?.detents = [.large()]
            host.sheetPresentationController?.prefersGrabberVisible = true
            top.present(host, animated: true)
            NSLog("aztecEngine| probe | browser | %@", url.host ?? raw)
        }
    }
}
#endif
