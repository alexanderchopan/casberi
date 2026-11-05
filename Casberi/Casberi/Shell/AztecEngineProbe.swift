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

#if DEBUG
import SwiftUI
import UIKit

/// `-aztecBrowser <url>` — open an Aztec app in Casberi's browser at mount
/// (prd §1700 step 3), over everything, with a Close button; DEBUG's door
/// until Library and the account's page carry the real ones. `-autoApprove
/// YES` is not honoured here: every ask waits for a hand.
/// `-aztecBrowserEthereum <url>` opens the page with your account as its
/// Ethereum provider instead (Human Passport's door, prd §1700e).
enum AztecBrowserProbe {
    @MainActor
    static func open(_ raw: String, ethereum: Bool = false) {
        guard let url = URL(string: raw), url.scheme == "https" || url.host == "localhost" || url.host == "127.0.0.1" else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard let root = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                .flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController else { return }
            var top = root
            while let next = top.presentedViewController { top = next }
            let host = UIHostingController(rootView: NavigationStack {
                AztecBrowserView(url: url, aztec: !ethereum, ethereum: ethereum).toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { top.presentedViewController?.dismiss(animated: true) }
                    }
                }
            })
            host.modalPresentationStyle = .fullScreen
            top.present(host, animated: true)
            NSLog("aztecEngine| probe | browser | %@", url.host ?? raw)
        }
    }
}
#endif
