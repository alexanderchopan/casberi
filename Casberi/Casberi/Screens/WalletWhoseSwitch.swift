import SwiftUI

/// The Yours · Following · All switch (prd §1526, §1536), drawn at the foot
/// of every Wallet tile's box but Markets', in the range strip's slim
/// grammar: the lit word in primary ink, the others quiet.
struct WalletWhoseSwitch: View {
    @Environment(ShellChrome.self) private var chrome

    /// Whether the switch draws — the box budgets its row on it: two words
    /// or more to choose between.
    static func shows(_ chrome: ShellChrome) -> Bool { offered.count > 1 }

    /// Your Casberi account, when the Wallet holds it: creating or recovering
    /// it watches it (`MoveScreen`), and Yours narrows to a watched account,
    /// so an unwatched one would be an empty box with nothing to say why.
    static var yours: String? {
        guard let own = YourAccountDemo.shownAddress,
              WalletStore.shared.addresses.contains(where: { WalletWatch.sameAddress($0.address, own) })
        else { return nil }
        return own
    }

    /// The wallets Following stands for: every watched address but yours.
    static var followed: [String] {
        let own = YourAccountDemo.shownAddress
        return WalletStore.shared.addresses.map(\.address)
            .filter { a in own.map { !WalletWatch.sameAddress(a, $0) } ?? true }
    }

    static var offered: [WalletWhose] {
        WalletWhose.offered(hasYours: yours != nil, hasFollowing: !followed.isEmpty)
    }

    var body: some View {
        let offered = Self.offered
        if offered.count > 1 {
            let lit = WalletWhose.lit(scope: chrome.walletScope, yours: Self.yours, same: WalletWatch.sameAddress)
            DSRangeChips(ranges: offered, range: lit, label: \.label, slim: true, repicks: true) { picked in
                DefaultsWrite.set(Data(picked.rawValue.utf8), forKey: WalletWhose.defaultsKey)
                withAnimation(DS.Motion.standard) { chrome.walletScope = picked.scope(yours: Self.yours) }
            }
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("Whose money"))
        }
    }

    /// With nothing followed there is no switch, so a Yours or Following
    /// pick would strand the Wallet narrowed with no way back (prd §1590).
    /// An app's pick stays: its menu is its own way back.
    @MainActor static func settleUnfollowed(_ chrome: ShellChrome) {
        guard let scope = chrome.walletScope, !RoomAccounts.isSeat(scope) else { return }
        chrome.walletScope = nil
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
        // Following with nothing followed any more opens on All.
        let start = remembered == .following && followed.isEmpty ? .everything : remembered
        chrome.walletScope = WalletWhose.launchScope(current: chrome.walletScope,
                                                     yours: yours,
                                                     remembered: start,
                                                     hasFollowing: !followed.isEmpty)
    }
}
