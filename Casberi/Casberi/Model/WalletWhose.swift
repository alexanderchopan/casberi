import Foundation

/// **YOURS · FOLLOWING · ALL (prd §1526, §1536, user, 2026-10-25: "the underlying problem
/// is user doesn't have an easy way to toggle between the aggregated view or
/// just their own wallet"; "Yours means casberi").**
///
/// One switch, one state, drawn in the box of every tile but Markets. It is
/// the Wallet's account pick put where it can be seen: Yours narrows the
/// Wallet to this phone's Casberi account (`chrome.walletScope` = its
/// address), Following to every wallet you follow (`followingScope`), All
/// clears the pick. It is the ONLY whose-control: Home and Holdings draw no
/// rows that pick an account (§1536). One followed wallet, opened from
/// Following's list, lights Following, and the switch is the way back.
///
/// Foundation-only, so the rules below are one place: what is lit, whether
/// the switch draws, and where a launch starts.
enum WalletWhose: String, CaseIterable, Hashable, Sendable {
    // `everything` keeps its raw value: a launch remembers the last pick by it.
    case yours, following, everything

    static let defaultsKey = "wallet.whose.v1"

    /// **FOLLOWING IS A PICK OF ITS OWN (prd §1536, user: "i think yours
    /// following all switch is most sensible").** The scope that stands for
    /// every wallet you follow at once — not an address, not an app — so
    /// `selectedWallet` and `selectedSeat` both read it as nil.
    static let followingScope = "group:following"

    static func isFollowing(_ scope: String?) -> Bool { scope == followingScope }

    /// The word on the switch.
    var label: String {
        switch self {
        case .yours: return String(localized: "Yours")
        case .following: return String(localized: "Following")
        case .everything: return String(localized: "All")
        }
    }

    /// The words the switch offers: Yours when your Casberi account is in
    /// the Wallet, Following and All when you follow a wallet.
    ///
    /// **NO FOLLOWED WALLET, NO SWITCH (prd §1590, user: "Should the app even
    /// show 'all' if you arne't following a wallet? i don't think so").** With
    /// nothing followed, everything in the Wallet is yours: the Wallet stands
    /// on All, unlabelled, so a bank or an exchange still counts.
    static func offered(hasYours: Bool, hasFollowing: Bool) -> [WalletWhose] {
        guard hasFollowing else { return [.everything] }
        return allCases.filter { $0 != .yours || hasYours }
    }

    /// Which word is lit for the Wallet's pick: All for no pick, Yours for
    /// your account, Following for the group or any one wallet you follow,
    /// All for an app (its money is part of All).
    static func lit(scope: String?, yours: String?, same: (String, String) -> Bool) -> WalletWhose {
        guard let scope else { return .everything }
        if isFollowing(scope) { return .following }
        if scope.hasPrefix("seat:") { return .everything }
        if let yours, same(scope, yours) { return .yours }
        return .following
    }

    /// The scope a launch opens the Wallet on: yours unless you last chose
    /// another word; untouched when something already picked a scope.
    static func launchScope(current: String?, yours: String?, remembered: WalletWhose?,
                            hasFollowing: Bool) -> String? {
        guard current == nil else { return current }
        guard hasFollowing else { return nil }
        switch remembered {
        case .everything: return nil
        case .following: return followingScope
        case .yours, nil: return yours
        }
    }

    /// The scope a press on the switch sets.
    func scope(yours: String?) -> String? {
        switch self {
        case .yours: return yours
        case .following: return Self.followingScope
        case .everything: return nil
        }
    }

    /// **ONLY YOUR CASBERI ACCOUNT IS YOURS (prd §1526 item 4, user: "i don't
    /// think we should give people option to name a followed address 'yours'
    /// anymore b/c that'll get too confusing w/ the casberi account").** A
    /// name a followed wallet may not take.
    static func reservedName(_ name: String) -> Bool {
        let folded = name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return ["yours", "you", "your account", "my account", "me", "mine",
                String(localized: "Yours"), String(localized: "Your account")]
            .map { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
            .contains(folded)
    }
}
