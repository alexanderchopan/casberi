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
/// **EVERY SCOPE IS PRESENT, ALWAYS (prd §611, generalising §610).** The gate
/// used to drop `frames`, `coins`, `nonces` and `sponsors` for an address that
/// had none — most addresses — so the four readings this chain exists for
/// were invisible to anyone who had not already made one. Now the strip is
/// the same seven chips on every address, and a scope with nothing in it says
/// what it would hold (`emptyHeadline`/`emptyBody`). That obligation is what
/// keeps this on the right side of §83.
///
/// Foundation-only by design: `scripts/hegota-selftest.sh` compiles it WHOLE
/// and unmodified. Every failure it catches renders as a perfectly ordinary
/// room — a scope that never appears, a remembered scope resolving to one
/// nobody picked, or a strip drawn over a single chip.
enum HegotaSection: String, CaseIterable, Identifiable, Sendable {
    case home
    case activity
    /// What each watched address holds, as a treemap (prd §680) — the same
    /// tab the Privacy devnet gained the same day, and vibenet has had since
    /// §530. Distinct from `coins`, which is one address's UTXOs: this is
    /// balances ACROSS the addresses you watch.
    case holdings
    case accounts
    case frames
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
    /// **The conditional tail starts at `frames`, and that does NOT break
    /// Wallet's tail rule.** That rule is that no UNCONDITIONAL scope may sit
    /// after a conditional one, so the strip's stable head never reflows;
    /// `home`, `activity` and `accounts` are the only unconditional scopes here
    /// and all three precede `frames`. Within the conditional tail the ordering
    /// is editorial.
    ///
    /// **`frames` LEADS that tail, ahead of `coins` (2026-08-27).** Coins held
    /// the position on the grounds of being "the reading no other room in this
    /// app can draw", which is true of it and truer of this: frame
    /// transactions are the reason this chain exists and the reason it earned a
    /// seat. It also reads directly off `activity`, which precedes it — the
    /// list says what moved, this says what the transactions DID — so the two
    /// sit adjacent rather than with the vault between them.
    static let order: [HegotaSection] = [.home, .activity, .holdings, .accounts, .frames, .coins, .nonces, .sponsors]

    /// Which scopes can be EMPTY.
    ///
    /// **It no longer gates `present()` (prd §611)** — every scope is drawn
    /// always — and it is kept, with its family name, for the two jobs it
    /// still does: it fixes the ORDER (the scopes that can be empty sit at the
    /// tail, so the strip's head is the same three chips on every address),
    /// and it is what obliges a scope to carry an `emptyBody`.
    var isConditional: Bool {
        switch self {
        // `accounts` is unconditional once there is a room at all — a watched
        // address always has a roster row, even one that says the chain could
        // not be reached, which is itself the answer (vibenet's own rule).
        case .home, .activity, .holdings, .accounts: return false
        // `frames` is conditional for a reason worth stating: this chain has
        // TWO ERAS, and an address whose whole history predates frame
        // transactions has only type-`0x2` transfers. Its scope is absent
        // rather than empty, which is also how the strip says which era an
        // address lived in without a word of copy.
        case .frames, .coins, .nonces, .sponsors: return true
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
        case .holdings: return String(localized: "Holdings")
        case .accounts: return String(localized: "Accounts")
        // **"Frames", the literal term — the Nonces ruling, third application.**
        // EIP-8141 calls them frames, the receipt field is `frames`, and the
        // sheet has said "Step 2 of 4" since the seat shipped because a step is
        // what one frame IS. "Steps" was the friendly gloss and was refused for
        // `coins`' exact reason: it would leave one room using two words for
        // one thing, and the chip is where the word gets learned.
        case .frames:   return String(localized: "Frames")
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
        case .holdings: return String(localized: "What each account you follow holds")
        // **NOT "and what each holds" (prd §689).** That sentence is the
        // Holdings chip's, word for word, and this scope had been claiming it
        // since before Holdings existed here. What Accounts owns is identity
        // and relationship — the one question no other scope answers.
        case .accounts: return String(localized: "The accounts you follow, and the ones tied to them")
        case .frames:   return String(localized: "The steps your transactions ran")
        case .coins:    return String(localized: "The unspent outputs this address owns")
        case .nonces:   return String(localized: "Sends that don't wait for each other")
        case .sponsors: return String(localized: "Transactions somebody else paid for")
        }
    }

    /// Which scopes the strip offers: **every one, on every address (prd
    /// §611).** The four Bools this used to take are gone rather than ignored —
    /// an unused `frames:` at the call site is an invitation to re-gate on it
    /// by accident. Whether there is a ROOM at all is still `HegotaRoom.sections`'
    /// call: an unreached watch list offers no strip, since nothing below it
    /// would be current.
    static func present() -> [HegotaSection] { order }

    /// **THE SHORT STATE, drawn in the chassis' reserved headline row (prd
    /// §611).** Nil for `home`, which is never empty: the crown is its content.
    var emptyHeadline: String? {
        switch self {
        case .home:     return nil
        case .activity: return String(localized: "None yet")
        case .holdings: return String(localized: "Holds nothing")
        case .accounts: return String(localized: "No connections yet")
        case .frames:   return String(localized: "No steps")
        case .coins:    return String(localized: "No UTXOs")
        case .nonces:   return String(localized: "No keyed nonces")
        case .sponsors: return String(localized: "None sponsored")
        }
    }

    /// **WHAT THE SCOPE WOULD HOLD, and why this address has none.** No
    /// subject (the face rail above says which is scoped), no door (Top up and
    /// Send are Home's, §594), and nothing that states a chain-wide fact —
    /// "no transaction on this chain has ever been sponsored" was true when
    /// measured and becomes a lie the first time one is.
    var emptyBody: String? {
        switch self {
        case .home:
            return nil
        case .activity:
            return String(localized: "Every move of ETH on this chain is a log, so this list is exact. Nothing has moved to or from what you watch.")
        case .holdings:
            return String(localized: "Nothing you watch holds a balance here yet.")
        case .accounts:
            return String(localized: "How the accounts you follow relate — who they have both dealt with. None of them shares a counterparty yet, so there is nothing to draw between them.")
        case .frames:
            return String(localized: "A frame transaction runs in numbered steps, each carrying its own budget. Nothing here has run one — a plain transfer runs none.")
        case .coins:
            return String(localized: "This chain can hold a balance as unspent pieces, each spent whole and never in part. None of these addresses holds one.")
        case .nonces:
            return String(localized: "A transfer on a named key does not wait for the ordinary counter, so two can go out at once. Everything here went on the ordinary nonce.")
        case .sponsors:
            return String(localized: "A sponsored transaction is one somebody else covered the gas for. Nothing here was.")
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
    /// whole job is to say there is more than one place to be. Since §611
    /// `present()` is the full order whenever there is a room, so this is the
    /// rule the shell gates on rather than a case it expects to meet.
    static func shows(present: [HegotaSection]) -> Bool { present.count > 1 }
}
