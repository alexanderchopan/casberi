import Foundation

/// **YOURS · EVERYTHING (prd §1526, user, 2026-10-25: "the underlying problem
/// is user doesn't have an easy way to toggle between the aggregated view or
/// just their own wallet"; "Yours means casberi").**
///
/// One switch, one state, drawn in the box of every tile but Markets. It is
/// the Wallet's account pick put where it can be seen: Yours narrows the
/// Wallet to this phone's Casberi account (`chrome.walletScope` = its
/// address), Everything clears the pick. Search still picks any one account;
/// while it has, the switch is not drawn, because the box then names that
/// account and neither word would be true.
///
/// Foundation-only, so the rules below are one place: what is lit, whether
/// the switch draws, and where a launch starts.
enum WalletWhose: String, CaseIterable, Hashable, Sendable {
    case yours, everything

    static let defaultsKey = "wallet.whose.v1"

    /// The word on the switch.
    var label: String {
        switch self {
        case .yours: return String(localized: "Yours")
        case .everything: return String(localized: "Everything")
        }
    }

    /// Which word is lit for the Wallet's current pick, or nil when the
    /// switch does not draw: no Casberi account (Yours would be empty), or a
    /// pick that is neither yours nor everything.
    static func lit(scope: String?, yours: String?, same: (String, String) -> Bool) -> WalletWhose? {
        guard let yours else { return nil }
        guard let scope else { return .everything }
        return same(scope, yours) ? .yours : nil
    }

    /// The scope a launch opens the Wallet on: yours unless you last chose
    /// Everything; untouched when you have no account, or when something
    /// already picked a scope (a deep link, a probe hook).
    static func launchScope(current: String?, yours: String?, remembered: WalletWhose?) -> String? {
        guard current == nil, let yours else { return current }
        return remembered == .everything ? nil : yours
    }

    /// The scope a press on the switch sets.
    func scope(yours: String) -> String? {
        self == .yours ? yours : nil
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
