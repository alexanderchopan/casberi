import Foundation

extension WalletPortfolio {
    /// The demo's own account for `demoFixture` (prd §1671): its tokens off
    /// its own table, on All and on its own pick, never under a Safe's (whose
    /// box adds this account itself, §1442l); nil outside the demo.
    static func demoAccountHeld(scopeTo address: String?, only: [String]?) -> DemoAccountHeld? {
        let account = YourAccountDemo.address
        guard YourAccountDemo.isOn, only == nil,
              address.map({ WalletWatch.sameAddress($0, account) }) ?? true else { return nil }
        let held = YourAccountOp.networks.flatMap { net -> [(symbol: String, usd: Double, key: String)] in
            guard let network = YourAccountOp.appName(net) else { return [] }
            return YourAccountDemo.held(on: net).compactMap { h in
                h.usd.map { (symbol: h.token.symbol, usd: $0,
                             key: HiddenTokens.contractKey(network: network, contract: h.token.contract)) }
            }
        }
        return DemoAccountHeld(address: account, label: String(localized: "Your account"), held: held)
    }
}
