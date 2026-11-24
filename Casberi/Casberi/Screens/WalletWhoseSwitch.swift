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
        guard let own = YourAccountDemo.shownAddress else { return nil }
        // The demo's account is in the demo's holdings without a watch (§1671).
        if YourAccountDemo.isOn { return own }
        guard WalletStore.shared.addresses.contains(where: { WalletWatch.sameAddress($0.address, own) })
        else { return nil }
        return own
    }

    /// **YOURS IS ALWAYS A WORD (prd §1671, user: "this still needs to show
    /// Yours, Following, All").** With no account yet it is a door: the pick
    /// opens Move, where one is made, and the Wallet stays where it stood.
    static var noAccountYet: Bool { YourAccountDemo.shownAddress == nil }

    /// The wallets Following stands for: every watched address but yours.
    static var followed: [String] {
        let own = YourAccountDemo.shownAddress
        return WalletStore.shared.addresses.map(\.address)
            .filter { a in own.map { !WalletWatch.sameAddress(a, $0) } ?? true }
    }

    /// **NO SWITCH (prd §1969, retiring §1526, §1536 and §1590's words).**
    /// The Wallet is your money and nothing else; the wallets you follow
    /// stand in Following, each on its own page. Nothing is offered, so no
    /// surface draws the words.
    static var offered: [WalletWhose] { [] }

    var body: some View {
        let offered = Self.offered
        if offered.count > 1 {
            let lit = WalletWhose.lit(scope: chrome.walletScope, yours: Self.yours, same: WalletWatch.sameAddress)
            DSRangeChips(ranges: offered, range: lit, label: \.label, slim: true, repicks: true, reads: true) { picked in
                Self.pick(picked, chrome)
            }
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("Whose money"))
        }
    }

    /// One pick, from the switch or Home's one word (prd §1843).
    @MainActor static func pick(_ picked: WalletWhose, _ chrome: ShellChrome) {
        if picked == .yours, noAccountYet {
            chrome.moveTray = true
            return
        }
        DefaultsWrite.set(Data(picked.rawValue.utf8), forKey: WalletWhose.defaultsKey)
        withAnimation(DS.Motion.standard) { chrome.walletScope = picked.scope(yours: yours) }
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
        chrome.walletScope = rememberedScope(over: chrome.walletScope)
    }

    /// The scope the remembered choice names, unless `current` already
    /// holds a pick.
    /// With no switch (prd §1969) the Wallet opens on your money: a
    /// remembered Yours or Following is let go, an app's pick kept.
    @MainActor private static func rememberedScope(over current: String?) -> String? {
        guard let current else { return nil }
        if WalletWhose.isFollowing(current) { return nil }
        if let yours, WalletWatch.sameAddress(current, yours) { return nil }
        return current
    }

    /// **HOME SHOWS THE CHOICE YOU MADE ON HOLDINGS (prd §1843).** Back on
    /// the phone's Home from a Wallet page, the card reads the remembered
    /// Yours · Following · All, whatever the page left: a way back cleared
    /// the scope (seen: Home went from Yours to All by opening Account and
    /// swiping back), and one wallet's or one app's pick is that page's.
    @MainActor static func settleHome(_ chrome: ShellChrome) {
        let scope = rememberedScope(over: nil)
        if chrome.walletScope != scope { chrome.walletScope = scope }
    }
}
