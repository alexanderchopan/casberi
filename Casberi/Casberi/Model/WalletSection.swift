import Foundation

/// The wallet room's SCOPE — which of its six readings is on screen
/// (prd §483, 2026-08-26).
///
/// **Why this exists.** The room ran to ~2,900pt of standing cards before the
/// first ordinary transaction row, on a wallet that has everything — about
/// three and a half screens. Eight of its thirteen blocks were standing state
/// (things true today and true yesterday), only two were events, and one of
/// those two was the three-row patch added on 2026-08-18 *because* the feed was
/// too far down. Every card was individually justified; the arrangement was the
/// problem.
///
/// **This is a REGROUPING, not a redraw.** Five of the six scopes are the
/// room's own `walletGroupHeader` groups — "What you hold" / "What it's doing" /
/// "Who can reach it" / "Coming up", shipped 2026-08-20 (§475) — renamed to
/// short nouns (user ruling: *"we can't really have the sections we what you
/// hold etc b/c they are too long"*) and split twice, so the mapping from card
/// to scope is IDENTITY. No card is dropped and none is duplicated, which is
/// what makes content loss structurally impossible rather than merely unlikely.
///
/// The two splits, and why each is a split rather than a rename:
///   • `nfts` leaves "What you hold" — the only scope whose content is pictures.
///   • "What it's doing" becomes `positions` (money deployed) and `risk` (money
///     that could move against you). One word could not carry both honestly:
///     an approval you granted on purpose is not a hazard, and a health factor
///     is not a holding.
///
/// **ORDER is events → state → hazards, and the last part is structural rather
/// than taste.** `risk` and `permissions` are CONDITIONAL — most wallets have
/// no leverage and some have no live approval — so they sit at the end. A
/// conditional scope in the middle makes every scope after it shift the day it
/// appears or disappears, and a control that reflows under you is one you stop
/// trusting. At the end its absence changes nothing, and `risk` carries an
/// attention dot, so position was never how you find it.
///
/// **`home` leads and is the default** for the reason this whole direction
/// was chosen: every other room in this app opens on its feed, and making
/// Wallet the exception again is what put its transactions three screens down
/// in the first place. Named "Activity" rather than "Transactions" (long, and
/// §8 asks for Bob's words) or "Recent" — which is wrong by construction, since
/// the scope leads with forward-dated rows that are not recent.
///
/// **EVERY SCOPE IS PRESENT, ALWAYS (prd §611, generalising §610).** Until
/// 2026-09-05 `present(…)` dropped a scope the wallet had nothing for, so a
/// wallet with no leverage never saw a Risk chip and one with no approvals
/// never learned that Permissions existed — the strip taught the room's
/// vocabulary only to the wallets that already spoke it. Now the strip is the
/// same seven chips on every wallet, and a scope with nothing in it says what
/// it would hold (`emptyHeadline`/`emptyBody`). That is the obligation which
/// keeps this on the right side of §83: a chip onto nothing is a dead control,
/// a chip onto a sentence teaching the scope is the room explaining itself.
///
/// Foundation-only by design: `scripts/wallet-section-selftest.sh` compiles it
/// WHOLE and unmodified. Every failure this catches renders as a perfectly
/// ordinary room — a scope that never appears, a remembered scope that silently
/// resolves to the wrong one, or a strip whose order changes between opens.
enum WalletSection: String, CaseIterable, Identifiable, Sendable {
    case home
    case activity
    case holdings
    case positions
    case nfts
    case risk
    case permissions

    var id: String { rawValue }

    /// The strip's order. `allCases` already declares it, but the order is a
    /// RULING (see the type's doc) rather than an accident of declaration, so
    /// it is stated where a reader looking for it will find it and where a
    /// self-test can assert it.
    static let order: [WalletSection] = [
        .home, .activity, .holdings, .positions, .nfts, .risk, .permissions,
    ]

    /// Which scopes can be EMPTY.
    ///
    /// **It no longer gates `present()` (prd §611)** — every scope is drawn
    /// always — and it is kept, with its family name, for the two jobs it
    /// still does: it fixes the ORDER (the scopes that can be empty sit at the
    /// tail, so the strip's head is the same chips on every wallet), and it is
    /// what obliges a scope to carry an `emptyBody`.
    var isConditional: Bool {
        switch self {
        case .home, .activity, .holdings: return false
        case .positions, .nfts, .risk, .permissions: return true
        }
    }

    /// `activity` is the only scope that is always available — the room always
    /// has a crown, and an empty stream is a real answer rather than an absence.
    var isAlwaysPresent: Bool { self == .home || self == .activity }

    var label: String {
        switch self {
        case .home:        return String(localized: "Home")
        case .activity:    return String(localized: "Activity")
        case .holdings:    return String(localized: "Holdings")
        case .positions:   return String(localized: "Positions")
        case .nfts:        return String(localized: "NFTs")
        case .risk:        return String(localized: "Risk")
        case .permissions: return String(localized: "Permissions")
        }
    }

    /// What a scope holds, for the accessibility label and the tooltip — the
    /// short nouns are learnable but not self-explaining, and "Permissions" in
    /// particular must not read as an app-settings screen when what sits behind
    /// it is ranked by the dollars somebody can take right now (§292).
    var summary: String {
        switch self {
        case .home:        return String(localized: "The line, and the last few moves")
        case .activity:    return String(localized: "What moved, and what's ahead")
        case .holdings:    return String(localized: "What your money is made of")
        case .positions:   return String(localized: "Money you've deployed")
        case .nfts:        return String(localized: "Collectibles you hold")
        case .risk:        return String(localized: "Positions that could move against you")
        case .permissions: return String(localized: "What you've granted reach to")
        }
    }

    /// Which scopes the strip offers: **every one, on every wallet (prd
    /// §611).** The five Bools this used to take are gone rather than ignored —
    /// an unused `risk:` at the call site is an invitation to re-gate on it by
    /// accident — and the same five readings now decide whether a scope draws
    /// its figure or its empty state (`FeedScreen.walletScopeIsEmpty`).
    static func present() -> [WalletSection] { order }

    /// **THE SHORT STATE, drawn where the scope's headline would go (prd
    /// §611).** Nil for `home`, which is never empty: the crown is its content.
    var emptyHeadline: String? {
        switch self {
        case .home:        return nil
        case .activity:    return String(localized: "Nothing yet")
        case .holdings:    return String(localized: "Nothing held")
        case .positions:   return String(localized: "Nothing deployed")
        case .nfts:        return String(localized: "No collectibles")
        case .risk:        return String(localized: "Nothing at risk")
        case .permissions: return String(localized: "No grants")
        }
    }

    /// **WHAT THE SCOPE WOULD HOLD, and why this wallet has none.** The return
    /// on making an empty chip reachable: each sentence teaches the reading the
    /// scope is about. No subject (the face rail above already says which
    /// wallets are scoped), no door (every verb lives on the card that draws
    /// it), and nothing that states a chain-wide fact and can go stale.
    var emptyBody: String? {
        switch self {
        case .home:
            return nil
        case .activity:
            return String(localized: "Transfers, approvals and what's ahead, as the chain reports them. Nothing from these wallets has been read yet.")
        case .holdings:
            return String(localized: "The tokens a wallet holds, sized by what each is worth. Nothing priced was found here — dust below the floor is left out.")
        case .positions:
            return String(localized: "Money at work in a protocol: lent, pooled, or held as a perp. Nothing here is deployed anywhere this app reads.")
        case .nfts:
            return String(localized: "The collections a wallet holds, as pictures. Nothing here holds one that survived the spam filter.")
        case .risk:
            return String(localized: "A position a price move could liquidate, and how close it stands. Nothing here carries leverage.")
        case .permissions:
            return String(localized: "What has been allowed to reach these wallets: a token approval, a Safe module, a delegate. Nothing here has granted any.")
        }
    }

    /// Resolve the scope actually shown from the one the person last picked.
    ///
    /// **Falls back to `.activity`, never to "the first present scope."** The
    /// two differ only when `activity` is somehow absent, which cannot happen —
    /// and that is the point: an unreachable branch that quietly picks
    /// `holdings` is how a room starts opening somewhere nobody chose. A
    /// remembered scope whose content has since gone (the last approval
    /// revoked, the last position closed) resolves to the feed rather than to
    /// an empty page claiming to be a section.
    static func resolve(_ wanted: WalletSection?, present: [WalletSection]) -> WalletSection {
        guard let wanted, present.contains(wanted) else { return .home }
        return wanted
    }

    /// Whether the strip is worth drawing at all.
    ///
    /// One scope is not a control, it is a label — the §83 dead-control ban, in
    /// the room where the control's whole job is to say there is more than one
    /// place to be. Since §611 `present()` is the full order whenever there is
    /// a room at all, so this is true for every wallet and stays as the rule
    /// the shell gates on rather than a case it expects to meet.
    static func shows(present: [WalletSection]) -> Bool { present.count > 1 }
}
