import Foundation

/// The wallet room's SCOPE — which of its pages is on screen (prd §483).
///
/// **FIVE TILES, EVERY LIST BEHIND A DOOR (prd §1480, user: "i want to totally
/// refactor wallet. it has the right things, but has redundancy, shows too
/// much"; Markets a tile again by §1498).** The tiles are Home · Activity ·
/// Holdings · Markets · Spending, and each answers one question:
///
///   • **Home** is the overview: the balance and its line, then five doors —
///     Your account, Following, Needs you, Permissions, Threats.
///   • **Activity** is the stream: every transaction by day.
///   • **Holdings** is what the money is: Accounts, Tokens, Positions, Apps,
///     NFTs, each a door.
///   • **Markets** is what you watch, then the companies behind your apps
///     (§1498, user: "lets bring the tile back but keep watchlist on the with
///     the tile not on home"). It is yours, not an account's, so it stays
///     lit whatever account is picked (§1519, user: "markets should stay lit").
///   • **Spending** is a reading of Activity: Subscriptions, Places, Fees,
///     Round-ups (§1523).
///
/// Security is deleted (user: "we will break those out into what they are"):
/// your account's controls are Your account's, approvals and delegations are
/// Permissions, the three kinds of flagged transfer are Threats, and a Safe
/// signature waiting on you is a Needs you row.
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
    /// What you watch, and the companies behind your apps (prd §1480 item 7;
    /// a tile again by §1498, a door off Home before it).
    case markets

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

    // ── Your account's doors ─────────────────────────────────────────────────
    /// The monthly recovery check (prd §1509 item 4, §1515).
    case recoveryKey
    /// Your own node per network (prd §1509 item 5, §1517).
    case nodes

    // ── Holdings' doors ──────────────────────────────────────────────────────
    /// Each wallet you follow, and its balance (prd §1503).
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
    /// What your account's round-ups bought, never in the total (prd §1523).
    case roundUps

    var id: String { rawValue }

    /// The tiles, in the publication's order: the ones that are never empty
    /// first (§483), so the strip's head is the same on every wallet. They
    /// DRAW A–Z after Home — Activity, Holdings, Markets, Spending (§995).
    /// `allCases` adds the pages.
    static let order: [WalletSection] = [.home, .holdings, .markets, .activity, .spending]

    /// Home's doors, in the row's order (prd §1480 item 2; Markets left for
    /// its tile, §1498).
    static let homeDoors: [WalletSection] = [.yourAccount, .following, .needsYou,
                                             .permissions, .threats]
    /// Holdings' doors (prd §1480 item 4, §1503): whose, then what.
    static let holdingsDoors: [WalletSection] = [.holdingAccounts, .apps, .positions, .nfts]
    /// Spending's doors (prd §1480 item 5; Round-ups, §1523).
    static let spendingDoors: [WalletSection] = [.subscriptions, .places, .fees, .roundUps]
    /// Your account's doors (prd §1515): the recovery key's check.
    static let yourAccountDoors: [WalletSection] = [.recoveryKey, .nodes]

    /// The page a page was opened from, where its title goes back: nil for a
    /// tile.
    var parent: WalletSection? {
        if Self.order.contains(self) { return nil }
        if Self.holdingsDoors.contains(self) { return .holdings }
        if Self.spendingDoors.contains(self) { return .spending }
        if Self.yourAccountDoors.contains(self) { return .yourAccount }
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
        // The wallets you follow, by balance; Home's Following is where you
        // add and remove them (§1503).
        case .holdingAccounts: return String(localized: "Following")
        case .positions:       return String(localized: "Positions")
        case .apps:            return String(localized: "Apps")
        case .nfts:            return String(localized: "NFTs")
        case .subscriptions:   return String(localized: "Subscriptions")
        case .places:          return String(localized: "Places")
        case .fees:            return String(localized: "Fees")
        case .roundUps:        return String(localized: "Round-ups")
        case .recoveryKey:     return String(localized: "Recovery key")
        case .nodes:           return String(localized: "Nodes")
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
        case .holdingAccounts: return String(localized: "What each wallet you follow holds")
        case .positions:       return String(localized: "Money lent, pooled, staked or held as a perp")
        case .apps:            return String(localized: "What each app holds for you")
        case .nfts:            return String(localized: "Your collections")
        case .subscriptions:   return String(localized: "What renews, and what it costs you")
        case .places:          return String(localized: "Where your money went")
        case .fees:            return String(localized: "What your sends paid the network")
        case .roundUps:        return String(localized: "What your round-ups bought")
        case .recoveryKey:     return String(localized: "Whether your recovery key still works")
        case .nodes:           return String(localized: "Where your account reads each network")
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
        case .holdingAccounts: return String(localized: "No wallets you follow")
        case .positions:       return String(localized: "No positions")
        case .apps:            return String(localized: "No apps")
        case .nfts:            return String(localized: "No collections")
        case .subscriptions:   return String(localized: "No subscriptions yet")
        case .places:          return String(localized: "No places")
        case .fees:            return String(localized: "No fees")
        case .roundUps:        return String(localized: "No round-ups")
        case .recoveryKey:     return String(localized: "Not checked yet")
        case .nodes:           return String(localized: "Casberi's list")
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
            return String(localized: "Each wallet you follow, and what it holds.")
        case .positions:
            return String(localized: "Money lent, pooled, staked or held as a perp.")
        case .apps:
            return String(localized: "What each app holds for you, largest first.")
        case .nfts:
            return String(localized: "The collections you chose to show.")
        case .subscriptions:
            return String(localized: "Plans that renew on a card or account, the bills that repeat, and the ones you add.")
        case .places:
            return String(localized: "Every place you paid this window, largest first.")
        case .fees:
            return String(localized: "Gas on every transaction your wallets sent, by network.")
        case .roundUps:
            return String(localized: "The change your sends rounded up, and the token it bought; never part of the total.")
        case .recoveryKey:
            return String(localized: "Your recovery key, checked once a month with Face ID: no fee, nothing sent.")
        case .nodes:
            return String(localized: "Each network read from Casberi's list through Tor, or from a node of your own.")
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
