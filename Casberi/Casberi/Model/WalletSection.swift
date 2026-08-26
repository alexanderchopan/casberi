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

    /// Everything past `.nfts` is conditional on the wallet actually having
    /// one. Stated as data rather than left implicit in `present(…)`, because
    /// it is the whole reason the order ends the way it does.
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

    /// Which scopes have anything to show.
    ///
    /// Deliberately takes plain Bools rather than the live wallet state: this
    /// file is Foundation-only so its rules can be compiled and mutation-tested
    /// without a `ModelContext`, a `WalletLiveState` or a `GenStream` — none of
    /// which any harness here can build. The call site does the reading; this
    /// does the deciding.
    static func present(holdings: Bool,
                        positions: Bool,
                        nfts: Bool,
                        risk: Bool,
                        permissions: Bool) -> [WalletSection] {
        order.filter { section in
            switch section {
            case .home:        return true
            case .activity:    return true
            case .holdings:    return holdings
            case .positions:   return positions
            case .nfts:        return nfts
            case .risk:        return risk
            case .permissions: return permissions
            }
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
    /// place to be. A wallet with no positions, no NFTs, no leverage and no
    /// approvals is just a list of transactions and a treemap, and it should
    /// look like one.
    static func shows(present: [WalletSection]) -> Bool { present.count > 1 }
}
