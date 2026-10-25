import SwiftUI

/// The Yours · Everything switch (prd §1526), drawn at the foot of every
/// Wallet tile's box but Markets', in the range strip's slim grammar: the
/// lit word in primary ink, the other quiet. It draws nothing when
/// `WalletWhose.lit` says it has no honest state.
struct WalletWhoseSwitch: View {
    @Environment(ShellChrome.self) private var chrome

    /// Whether the switch draws for this pick — the box budgets its row on it.
    static func shows(_ chrome: ShellChrome) -> Bool { lit(chrome) != nil }

    private static func lit(_ chrome: ShellChrome) -> WalletWhose? {
        WalletWhose.lit(scope: chrome.walletScope, yours: yours, same: WalletWatch.sameAddress)
    }

    /// Your Casberi account, when the Wallet holds it: creating or recovering
    /// it watches it (`MoveScreen`), and Yours narrows to a watched account,
    /// so an unwatched one would be an empty box with nothing to say why.
    static var yours: String? {
        guard let own = YourAccountDemo.shownAddress,
              WalletStore.shared.addresses.contains(where: { WalletWatch.sameAddress($0.address, own) })
        else { return nil }
        return own
    }

    var body: some View {
        if let lit = Self.lit(chrome), let yours = Self.yours {
            DSRangeChips(ranges: WalletWhose.allCases, range: lit, label: \.label, slim: true) { picked in
                DefaultsWrite.set(Data(picked.rawValue.utf8), forKey: WalletWhose.defaultsKey)
                withAnimation(DS.Motion.standard) { chrome.walletScope = picked.scope(yours: yours) }
            }
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("Whose money"))
        }
    }

    /// Where a launch opens the Wallet (prd §1526 item 2): yours unless you
    /// last chose Everything. Once per launch, and never over a pick
    /// something else already made.
    @MainActor private static var applied = false
    @MainActor static func applyLaunchChoice(_ chrome: ShellChrome) {
        guard !applied else { return }
        applied = true
        let remembered = UserDefaults.standard.data(forKey: WalletWhose.defaultsKey)
            .flatMap { String(data: $0, encoding: .utf8) }.flatMap(WalletWhose.init(rawValue:))
        chrome.walletScope = WalletWhose.launchScope(current: chrome.walletScope,
                                                     yours: yours,
                                                     remembered: remembered)
    }
}
