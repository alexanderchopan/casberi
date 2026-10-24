import Foundation

/// The wallet room's SCOPE — which of its pages is on screen (prd §483).
///
/// **FOUR TILES, EVERY LIST BEHIND A DOOR (prd §1480, user: "i want to totally
/// refactor wallet. it has the right things, but has redundancy, shows too
/// much").** The tiles are Home · Activity · Holdings · Spending, and each
/// answers one question:
///
///   • **Home** is the overview: the balance and its line, then six doors —
///     Your account, Following, Needs you, Permissions, Threats, Markets.
///   • **Activity** is the stream: every transaction by day.
///   • **Holdings** is what the money is: Accounts, Tokens, Positions, Apps,
///     NFTs, each a door.
///   • **Spending** is a reading of Activity: Subscriptions, Places, Fees.
///
/// Security is deleted (user: "we will break those out into what they are"):
/// your account's controls are Your account's, approvals and delegations are
/// Permissions, the three kinds of flagged transfer are Threats, and a Safe
/// signature waiting on you is a Needs you row. Markets is a page off Home.
///
/// **A PAGE IS A SCOPE WITH NO TILE.** Subscriptions was the first (§1232);
/// every door opens one. A page names the page it opened from (`parent`), and
/// its title's category word goes back there (prd §1480 item 9).
///
/// **ORDER is the publication's**; the tiles DRAW A–Z after Home
/// (`DSScopeTiles.alphabetical`, §995), and the self-test pins it.
///
/// Foundation-only by design: `scripts/wallet-section-selftest.sh` compiles it
/// WHOLE and unmodified.
enum WalletSection: String, CaseIterable, Identifiable, Sendable {
    // ── The tiles ────────────────────────────────────────────────────────────
    case home
    /// Every transaction by day, pending first (prd §1480 item 3).
    case activity
    /// What the money is (prd §1480 item 4).
    case holdings
    /// A reading of Activity: subscriptions, places, fees (prd §1468, §1480).
    case spending

    // ── Home's doors ─────────────────────────────────────────────────────────
    /// The account the app made you, and its controls (prd §1480 item 6).
    case yourAccount
    /// Every other account the Wallet reads, where you add, rename and remove.
    case following
    /// Every ask, from every page.
    case needsYou
    /// Approvals and delegations: who can spend from you.
    case permissions
    /// Address poisoning, fake tokens, fake transfers.
    case threats
    /// What you watch, and the companies behind your apps (prd §1480 item 7).
    case markets

    // ── Holdings' doors ──────────────────────────────────────────────────────
    /// Each account's balance: the wallets and the accounts apps hold.
    case holdingAccounts
    /// Lending, perps, liquidity, stakes and orders (prd §1107).
    case positions
    /// The apps that made you a wallet (prd §1124).
    case apps
    case nfts

    // ── Spending's doors ─────────────────────────────────────────────────────
    /// What renews, and what it costs (prd §1111).
    case subscriptions
    case places
    case fees

    var id: String { rawValue }

    /// The tiles, in the publication's order: the ones that are never empty
    /// first (§483), so the strip's head is the same on every wallet. They
    /// DRAW A–Z after Home — Activity, Holdings, Spending (§995). `allCases`
    /// adds the pages.
    static let order: [WalletSection] = [.home, .holdings, .activity, .spending]

    /// Home's doors, in the row's order (prd §1480 item 2).
    static let homeDoors: [WalletSection] = [.yourAccount, .following, .needsYou,
                                             .permissions, .threats, .markets]
    /// Holdings' doors (prd §1480 item 4).
    static let holdingsDoors: [WalletSection] = [.holdingAccounts, .positions, .apps, .nfts]
    /// Spending's doors (prd §1480 item 5).
    static let spendingDoors: [WalletSection] = [.subscriptions, .places, .fees]

    /// The page a page was opened from, where its title goes back: nil for a
    /// tile.
    var parent: WalletSection? {
        if Self.order.contains(self) { return nil }
        if Self.holdingsDoors.contains(self) { return .holdings }
        if Self.spendingDoors.contains(self) { return .spending }
        return .home
    }

    var isTile: Bool { parent == nil }

    /// Which scopes can be EMPTY: each must carry an `emptyBody`.
    var isConditional: Bool {
        switch self {
        case .home, .holdings, .markets: return false
        default: return true
        }
    }

    /// `home` is the only scope that is always available.
    var isAlwaysPresent: Bool { self == .home }

    var label: String {
        switch self {
        case .home:            return String(localized: "Home")
        case .activity:        return String(localized: "Activity")
        case .holdings:        return String(localized: "Holdings")
        case .spending:        return String(localized: "Spending")
        case .yourAccount:     return String(localized: "Your account")
        case .following:       return String(localized: "Following")
        case .needsYou:        return String(localized: "Needs you")
        case .permissions:     return String(localized: "Permissions")
        case .threats:         return String(localized: "Threats")
        case .markets:         return String(localized: "Markets")
        // Where the money sits: a wallet, or an account an app holds (§1480).
        case .holdingAccounts: return String(localized: "Accounts")
        case .positions:       return String(localized: "Positions")
        case .apps:            return String(localized: "Apps")
        case .nfts:            return String(localized: "NFTs")
        case .subscriptions:   return String(localized: "Subscriptions")
        case .places:          return String(localized: "Places")
        case .fees:            return String(localized: "Fees")
        }
    }

    /// What a scope holds, for the accessibility label and the tooltip.
    var summary: String {
        switch self {
        case .home:            return String(localized: "The balance, and what needs you")
        case .activity:        return String(localized: "Every transaction, by day")
        case .holdings:        return String(localized: "What your money is")
        case .spending:        return String(localized: "What left your accounts, by place")
        case .yourAccount:     return String(localized: "Your account's keys, limit and round-ups")
        case .following:       return String(localized: "The accounts and apps you follow")
        case .needsYou:        return String(localized: "What is waiting on you")
        case .permissions:     return String(localized: "Who can spend from you")
        case .threats:         return String(localized: "What's trying to fool you")
        case .markets:         return String(localized: "What you watch")
        case .holdingAccounts: return String(localized: "What each account holds")
        case .positions:       return String(localized: "Money lent, pooled, staked or held as a perp")
        case .apps:            return String(localized: "The apps that made you a wallet")
        case .nfts:            return String(localized: "Your collections")
        case .subscriptions:   return String(localized: "What renews, and what it costs you")
        case .places:          return String(localized: "Where your money went")
        case .fees:            return String(localized: "What your sends paid the network")
        }
    }

    /// Which scopes the strip offers: **every tile, on every wallet (prd §611).**
    static func present() -> [WalletSection] { order }

    /// The pages a door may open: the tiles, and every page behind a door.
    static func pages(tiles: [WalletSection]) -> [WalletSection] {
        tiles + allCases.filter { !tiles.contains($0) && !$0.isTile }
    }

    /// **THE SHORT STATE, drawn where the scope's headline would go (prd §611).**
    var emptyHeadline: String? {
        switch self {
        case .home:            return String(localized: "No balance yet")
        case .activity:        return String(localized: "Nothing yet")
        case .holdings:        return String(localized: "Nothing held")
        case .spending:        return String(localized: "Nothing spent")
        case .yourAccount:     return String(localized: "No account yet")
        case .following:       return String(localized: "Nothing followed")
        case .needsYou:        return String(localized: "Nothing waiting")
        case .permissions:     return String(localized: "No permissions")
        case .threats:         return String(localized: "Nothing to fool you")
        case .markets:         return nil
        case .holdingAccounts: return String(localized: "No accounts")
        case .positions:       return String(localized: "No positions")
        case .apps:            return String(localized: "No apps")
        case .nfts:            return String(localized: "No collections")
        case .subscriptions:   return String(localized: "No subscriptions yet")
        case .places:          return String(localized: "No places")
        case .fees:            return String(localized: "No fees")
        }
    }

    /// **THE CLAUSE THE HEADLINE AND THE DRAWING CANNOT SAY (prd §799).**
    /// VoiceOver's value: what the scope holds, with the bound on the read.
    var emptyBody: String? {
        switch self {
        case .home:
            // What was found, never why nothing was (§83).
            return String(localized: "What these accounts are worth, and the line it traces.")
        case .activity:
            return String(localized: "Every send, receipt, swap and charge, by day.")
        case .holdings:
            return String(localized: "Tokens sized by worth, then money lent, pooled or held as a perp. Dust below the floor is left out.")
        case .spending:
            // What counts, and what is left out (§1201).
            return String(localized: "What your cards and wallets paid to places this week or month, against the last one; a move of your own or a swap never counts.")
        case .yourAccount:
            return String(localized: "The account Casberi makes you, its keys, its spend limit and its round-ups.")
        case .following:
            return String(localized: "Wallets you watch and apps you connected.")
        case .needsYou:
            return String(localized: "A signature, a transfer, a key, a renewal or a bill waiting on you.")
        case .permissions:
            return String(localized: "A delegate or a token approval that can spend from you.")
        case .threats:
            return String(localized: "An address made to look like yours, a fake token or a fake transfer.")
        case .markets:
            return nil
        case .holdingAccounts:
            return String(localized: "Each wallet's balance, and what an app holds for you.")
        case .positions:
            return String(localized: "Money lent, pooled, staked or held as a perp.")
        case .apps:
            return String(localized: "The apps that made you a wallet, with what each holds.")
        case .nfts:
            return String(localized: "The collections you chose to show.")
        case .subscriptions:
            return String(localized: "Plans that renew on a card or account, the bills that repeat, and the ones you add.")
        case .places:
            return String(localized: "Every place you paid this window, largest first.")
        case .fees:
            return String(localized: "Gas on every transaction your wallets sent, by network.")
        }
    }

    /// Resolve the scope actually shown from the one the person last picked.
    ///
    /// **Falls back to `.home`, never to "the first present scope."** A
    /// remembered scope the room no longer has — Security since §1480 — fails
    /// its raw value and resolves to Home rather than to an empty page.
    static func resolve(_ wanted: WalletSection?, present: [WalletSection]) -> WalletSection {
        guard let wanted, present.contains(wanted) else { return .home }
        return wanted
    }

    /// Whether the strip is worth drawing at all: one scope is a label, not a
    /// control (§83).
    static func shows(present: [WalletSection]) -> Bool { present.count > 1 }
}
