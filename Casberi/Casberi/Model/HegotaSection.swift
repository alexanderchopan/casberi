import Foundation

/// The Ethrex Hegotá room's SCOPE — which of its five readings is on screen.
///
/// **Wallet's template, this chain's vocabulary.** `WalletSection` is the shape
/// (`order` as a ruling, `present(…)` over plain Bools, `resolve` falling back
/// to `.home`, `shows` refusing to draw a control over one scope) and
/// `DSSectionSwitcher` is the shared control. The WORDS are this room's own,
/// for the reason `VibenetSection` gives: borrowing a neighbour's scope name
/// for a thing this chain does not have is either a permanently empty chip or a
/// lie, and §83 bans both.
///
/// Four of Wallet's seven names are therefore absent, each for a stated reason:
///   • **Holdings** — this chain has ONE asset, so the crown on Home already
///     states the whole of it and a Holdings scope would restate it (vibenet's
///     own ruling). `coins` is this room's Holdings, and it says a thing a
///     total cannot: which unspent pieces the balance is made of.
///   • **Positions** — no lending, no perps, no pools. Nothing is deployed.
///   • **NFTs** — no collectibles exist on the chain.
///   • **Risk** — nothing can move against you. No leverage, and the asset is
///     test ETH with no price.
///   • **Permissions** — the nearest thing here is a sponsor paying your gas,
///     which is a TRANSACTION rather than a standing grant. It gets `sponsors`,
///     ranked last, and never the word "permissions": nobody holds authority
///     over a Hegotá address but its key. That is the sharp difference from
///     vibenet, where a keystore account really does have actors that can act
///     for it.
///
/// **`nonces`, not "Lanes" and not "Queues" (2026-08-27).** EIP-8250's own term
/// is *keyed nonces*, the RPC serves the fields as `nonceKeys`/`nonceSeq`, and
/// `SafeBridge` already speaks the word to users ("blocks any other transaction
/// at this nonce"), so it is not a new register for this app. The two
/// alternatives both cost more than they bought: "Lanes" collides twice in
/// wallet-adjacent copy — `WalletFlowBand` speaks its ribbons as lanes and the
/// x402 screen offers "Watch every lane" — and "Queues" reads as *things
/// pending* when what the scope lists is settled history. "Orders" was never in
/// the running: `TokenWatchOrder`, the exchange screens and `MoneyReceiptCard`
/// all spend that word on trades, in a room one chip away from Markets.
///
/// Foundation-only by design: `scripts/hegota-selftest.sh` compiles it WHOLE
/// and unmodified. Every failure it catches renders as a perfectly ordinary
/// room — a scope that never appears, a remembered scope resolving to one
/// nobody picked, or a strip drawn over a single chip.
enum HegotaSection: String, CaseIterable, Identifiable, Sendable {
    case home
    case activity
    case accounts
    case coins
    case nonces
    case sponsors

    var id: String { rawValue }

    /// The strip's order. `allCases` already declares it, but the order is a
    /// RULING rather than an accident of declaration (`WalletSection.order`'s
    /// own reasoning), so it is stated where a reader will look for it and
    /// where a self-test can assert it.
    ///
    /// **Home leads and is the fallback**, matching Wallet and vibenet: Home is
    /// the crown and its line, and opening anywhere else puts a tap between the
    /// crown and its own breakdown.
    ///
    /// **`coins` sits third, ahead of the two rarer conditionals, and that does
    /// NOT break Wallet's tail rule.** That rule is that no UNCONDITIONAL scope
    /// may sit after a conditional one, so the strip's stable head never
    /// reflows; `home` and `activity` are the only unconditional scopes here
    /// and both precede `coins`. Within the conditional tail the ordering is
    /// editorial, and Coins leads it because it is this room's headline — the
    /// one reading no other room in this app can draw.
    static let order: [HegotaSection] = [.home, .activity, .accounts, .coins, .nonces, .sponsors]

    /// Everything past `activity` is conditional on the address actually having
    /// the thing. Stated as data rather than left implicit in `present(…)`,
    /// because it is the whole reason the order ends the way it does.
    var isConditional: Bool {
        switch self {
        // `accounts` is unconditional once there is a room at all — a watched
        // address always has a roster row, even one that says the chain could
        // not be reached, which is itself the answer (vibenet's own rule).
        case .home, .activity, .accounts: return false
        case .coins, .nonces, .sponsors: return true
        }
    }

    /// `home` and `activity` are the room's constants — a watched address
    /// always has a balance reading (even "couldn't be read", which is itself
    /// the answer) and an empty stream is a real answer rather than an absence.
    var isAlwaysPresent: Bool { self == .home || self == .activity || self == .accounts }

    var label: String {
        switch self {
        case .home:     return String(localized: "Home")
        case .activity: return String(localized: "Activity")
        case .accounts: return String(localized: "Accounts")
        // **"UTXOs", not "Coins" — the Nonces ruling, applied consistently.**
        // The chain's own word is UTXO: EIP-8312 names the frame, the predeploy
        // is the UTXO vault, and the RPC says so. "Coins" was the friendly
        // gloss, and keeping it here while the frame beside it read UTXO left
        // one room using two words for one thing. A second chip was considered
        // and refused outright: UTXOs and coins are not two readings, so two
        // chips over one set is the dead control §83 bans.
        case .coins:    return String(localized: "UTXOs")
        case .nonces:   return String(localized: "Nonces")
        case .sponsors: return String(localized: "Sponsors")
        }
    }

    /// What the scope holds — the accessibility label and the tooltip. The
    /// short nouns are learnable but not self-explaining, and two of these are
    /// words this app spends elsewhere on something else: "Coins" is not a
    /// token watchlist, and a "nonce" here keys an independent send sequence
    /// rather than counting one.
    var summary: String {
        switch self {
        case .home:     return String(localized: "The line, and the last few moves")
        case .activity: return String(localized: "What moved, and what each transaction did")
        case .accounts: return String(localized: "The addresses you watch, and what each holds")
        case .coins:    return String(localized: "The unspent outputs this address owns")
        case .nonces:   return String(localized: "Sends that don't wait for each other")
        case .sponsors: return String(localized: "Transactions somebody else paid for")
        }
    }

    /// Which scopes have anything to show.
    ///
    /// Deliberately takes plain Bools rather than the live chain state, for
    /// `WalletSection.present`'s reason: this file is Foundation-only so its
    /// rules can be compiled and mutation-tested with no `ModelContext` and no
    /// network. The call site does the reading; this does the deciding.
    ///
    /// **`sponsors` is expected to be false on every address today** — every
    /// frame transaction on this chain so far is self-paid — and that is the
    /// correct output rather than a gap. The scope declines silently and
    /// appears the first time somebody sponsors a transaction.
    static func present(coins: Bool, nonces: Bool, sponsors: Bool) -> [HegotaSection] {
        order.filter { section in
            switch section {
            case .home:     return true
            case .activity: return true
            case .accounts: return true
            case .coins:    return coins
            case .nonces:   return nonces
            case .sponsors: return sponsors
            }
        }
    }

    /// Which chips wear a dot.
    ///
    /// **None, ever.** Vibenet's `attention` returns an empty set because its
    /// dots were lit more often than not (prd §493); here the reason is one
    /// step stronger — nothing in this room is ever urgent. There is no
    /// deadline, no liquidation, no expiry and no grant to revoke, and the
    /// asset is test ETH with no price. A marker that can never honestly light
    /// is chrome.
    ///
    /// Returning an empty set rather than dropping the call keeps
    /// `DSSectionSwitcher`'s `attention` parameter honest for Wallet, which
    /// uses it for a genuinely rare state.
    static func attention() -> Set<HegotaSection> { [] }

    /// Resolve the scope actually shown from the one the person last picked.
    ///
    /// **Falls back to `.home`, never to "the first present scope."** The two
    /// differ only when `home` is somehow absent, which cannot happen — and
    /// that is the point: an unreachable branch that quietly picks `coins` is
    /// how a room starts opening somewhere nobody chose. A remembered scope
    /// whose content has since gone (the last coin spent) resolves to the crown
    /// rather than to an empty page claiming to be a section.
    static func resolve(_ wanted: HegotaSection?, present: [HegotaSection]) -> HegotaSection {
        guard let wanted, present.contains(wanted) else { return .home }
        return wanted
    }

    /// Whether the strip is worth drawing at all. One scope is not a control,
    /// it is a label — §83's dead-control ban, in the room where the control's
    /// whole job is to say there is more than one place to be. An address with
    /// no coins, no keyed nonces and no sponsor is a balance and a list of
    /// moves, and it should look like one.
    static func shows(present: [HegotaSection]) -> Bool { present.count > 1 }
}
