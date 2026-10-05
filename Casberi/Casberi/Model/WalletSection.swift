import Foundation

/// The wallet room's SCOPE — which of its four readings is on screen (prd
/// §483, cut to four by §1107).
///
/// **FOUR TILES, ONE ROW (prd §1107, user: "i would challenge you perhaps to
/// give me a wallet that has 4 tiles").** The room had eight — Home · Coming
/// up · Holdings · Permissions · Positions · Risk · Subscriptions · Watch — and
/// each was a MODE: a tap swapped the box and the list, so you saw one reading
/// at a time and had to remember which tile held what. The eight fold into
/// four by what they are about, and nothing that mattered is dropped:
///
///   • **Subscriptions** (Coming up until prd §1111) tracks subscriptions
///     and nothing else: the renewals on its calendar, then every plan with
///     Add first. What waits on you and the dated rows moved to Home, the
///     activity: Needs you leads it, then what is ahead under its days (user:
///     "coming up moved to activity", "'needs you' becomes a section in home").
///   • **Holdings** takes Positions, and the loan risk with it: tokens first
///     (the biggest few, the rest one row away), then Positions, each loan
///     saying how far it can fall (Risk's own sentence, §1090).
///   • **Security** takes Permissions and what Risk called "Worth a look":
///     Safe signatures, delegations, approvals, and the three kinds of
///     flagged transfer — address poisoning, fake tokens, fake transfers. A
///     liquidation is not a security fact; it is a position's, so it went to
///     Holdings (user: "it's a security feature").
///   • **Watch** stops being a tile: watching a wallet is the first row of
///     the Accounts pill's list, where the accounts it adds will stand.
///
/// **ORDER is events → state → conditional**, the reason §483 gave: a scope
/// that can be empty sits at the tail, so the strip's head is the same on
/// every wallet. The tiles DRAW A–Z after Home (`DSScopeTiles.alphabetical`,
/// §995); this order is the publication's, and the self-test pins it.
///
/// **EVERY SCOPE IS PRESENT, ALWAYS (prd §611).** A scope with nothing in it
/// draws its empty state, which teaches what it would hold.
///
/// Foundation-only by design: `scripts/wallet-section-selftest.sh` compiles it
/// WHOLE and unmodified.
enum WalletSection: String, CaseIterable, Identifiable, Sendable {
    case home
    /// What you hold — tokens, then Positions (prd §1107).
    case holdings
    /// What renews, and what it costs (prd §1111): every subscription, the
    /// user's to build up. Was `comingUp` (§1041, §1107); a remembered
    /// "comingUp" resolves to Home.
    case subscriptions
    /// Who can act for you, and what is trying to fool you (prd §1107).
    case security

    var id: String { rawValue }

    /// The publication's order. `allCases` already declares it, but the order
    /// is a RULING (see the type's doc), stated where a self-test can assert it.
    static let order: [WalletSection] = [.home, .holdings, .subscriptions, .security]

    /// Which scopes can be EMPTY. They sit at the tail, and each must carry an
    /// `emptyBody`.
    var isConditional: Bool {
        switch self {
        case .home, .holdings: return false
        case .subscriptions, .security: return true
        }
    }

    /// `home` is the only scope that is always available — the room always
    /// has a crown, and an empty list is a real answer rather than an absence.
    var isAlwaysPresent: Bool { self == .home }

    var label: String {
        switch self {
        case .home:     return String(localized: "Home")
        case .holdings: return String(localized: "Holdings")
        // The word the app converges on for what keeps coming (prd §1111):
        // Day's mail tile says it too.
        case .subscriptions: return String(localized: "Subscriptions")
        // The word wallets use for approvals and scams (user, over "Safety").
        case .security: return String(localized: "Security")
        }
    }

    /// What a scope holds, for the accessibility label and the tooltip.
    var summary: String {
        switch self {
        case .home:     return String(localized: "The line, and what moved")
        case .holdings: return String(localized: "Your tokens, and money you've deployed")
        case .subscriptions: return String(localized: "What renews, and what it costs you")
        case .security: return String(localized: "Who can act for you, and what's trying to fool you")
        }
    }

    /// Which scopes the strip offers: **every one, on every wallet (prd §611).**
    static func present() -> [WalletSection] { order }

    /// **THE SHORT STATE, drawn where the scope's headline would go (prd §611).**
    var emptyHeadline: String? {
        switch self {
        // Home has words since prd §761: no total, no line and no recent row
        // drew nothing at all.
        case .home:     return String(localized: "No balance yet")
        case .holdings: return String(localized: "Nothing held")
        case .subscriptions: return String(localized: "No subscriptions yet")
        case .security: return String(localized: "Nothing to review")
        }
    }

    /// **THE CLAUSE THE HEADLINE AND THE DRAWING CANNOT SAY (prd §799).**
    /// VoiceOver's value: what the scope holds, with the bound on the read.
    var emptyBody: String? {
        switch self {
        case .home:
            // What was found, never why nothing was (§83): `total` is nil both
            // before the read lands and when nothing priced was found.
            return String(localized: "What these accounts are worth, and the line it traces.")
        case .holdings:
            return String(localized: "Tokens sized by worth, then money lent, pooled or held as a perp. Dust below the floor is left out.")
        case .subscriptions:
            return String(localized: "Plans that renew on a card or account, the bills that repeat, and the ones you add.")
        case .security:
            return String(localized: "A Safe signature, a delegate, a token approval, or a transfer made to fool you.")
        }
    }

    /// Resolve the scope actually shown from the one the person last picked.
    ///
    /// **Falls back to `.home`, never to "the first present scope."** A
    /// remembered scope the room no longer has — Positions, Risk and
    /// Permissions since §1107, Coming up since §1111 — resolves to Home rather than to an
    /// empty page claiming to be a section.
    static func resolve(_ wanted: WalletSection?, present: [WalletSection]) -> WalletSection {
        guard let wanted, present.contains(wanted) else { return .home }
        return wanted
    }

    /// Whether the strip is worth drawing at all: one scope is a label, not a
    /// control (§83).
    static func shows(present: [WalletSection]) -> Bool { present.count > 1 }
}
