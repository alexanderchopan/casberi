import Foundation

/// The Frames devnet room's SCOPE — which of its four readings is on screen
/// (prd §548).
///
/// **Wallet's template, this chain's vocabulary** — `WalletSection` is the
/// shape (`order` as a ruling, `present(…)` over plain Bools, `resolve`
/// falling back to `.home`, `shows` refusing to draw a control over one scope)
/// and `DSSectionSwitcher` is the shared control. The WORDS are this room's
/// own: borrowing a neighbour's scope name for a thing this chain does not
/// have is either a permanently empty chip or a lie, and §83 bans both.
///
/// **THREE OF HEGOTÁ'S SEVEN ARE ABSENT, and two of those are measurements
/// rather than choices.**
///   • **UTXOs** — this chain has no UTXO vault. Hegotá's `0x…8312` predeploy
///     is not deployed here and no transaction has ever named one. The seat
///     that made "the coins an address holds, not just a balance" Hegotá's
///     headline reading simply does not exist on this chain.
///   • **Nonces** — this chain implements no keyed nonces. EIP-8250's
///     `nonceKeys`/`nonceSeq` appear on none of its transactions (measured
///     2026-09-01, the whole type-`0x06` population), so the scope the user
///     personally named on Hegotá has nothing to list here. Absent because
///     the chain cannot fill it, not because it was not wanted.
///   • **Accounts** — this WAS a choice and §689 revisits it, on the condition
///     the original note itself named: *"revisit it if watching several here
///     ever becomes ordinary."* It is ordinary now — §688 seeded a second
///     watched address — and the scope does not draw the roster the old
///     reasoning was about. It draws the CONNECTIONS between what you watch,
///     which one account cannot have and which no other scope answers.
///
/// **HOLDINGS ARRIVES (prd §688, 2026-09-11), and §500's reason for its absence
/// was a measurement nobody had taken.** It read "one asset, so the crown
/// states the whole of it" — and this chain carries `YDS` and `DAI`, read off
/// it the day this changed. What was true is that the app only ever asked
/// `eth_getBalance`, so the room could not have seen a token if an address had
/// held one. It asks now (`DevnetTokens`), and the scope draws the split when
/// there is one and says "Test ETH only" when there is not — which is the
/// honest version of the sentence §500 wrote as a fact about the chain.
///
/// Wallet's other three stay absent for §500's reasons, all of which hold:
/// **Positions**
/// and **NFTs** (nothing to hold), **Risk** (nothing can move against you —
/// the asset is test ETH with no price), and **Permissions**.
///
/// **PERMISSIONS IS ABSENT BECAUSE THIS CHAIN HAS NO STANDING AUTHORITY, and
/// that is a fact about EIP-8141 rather than a gap in this room** (user,
/// 2026-09-01: *"won't we have permissions ... or no bc that is 'frames'"* —
/// right, and the reason is sharper than coverage). On vibenet a keystore
/// account really does have actors — keys, passkeys, a delegate — that can act
/// for it tomorrow, so a Permissions scope lists a durable grant somebody can
/// revoke. Here **authorization is PER-TRANSACTION**: a VERIFY frame's `flags`
/// carry the `APPROVE` scope for execution and payment, and that authority is
/// granted and spent inside the one transaction carrying it. Nothing survives
/// it, so there is nothing standing to list and nothing to revoke — which is
/// also why a transaction with no `APPROVE` is not under-permissioned but
/// INVALID: it has no payer at all.
///
/// The permission therefore genuinely IS a frame, and it is drawn where frames
/// are drawn. Two consequences worth keeping: the `frames` scope must always
/// say whether a VERIFY frame approved execution, payment or both — that is
/// the permission, not decoration — and a Permissions scope here would be a
/// page listing grants that cannot exist, the empty chip §83 bans.
///
/// **EVERY SCOPE IS PRESENT, ALWAYS (prd §611, generalising §610; user,
/// 2026-09-05: "it doesn't show all the scopes in the rail. I think it should
/// even if they are not present").** The gate used to drop `frames` and
/// `sponsors` for an address that had none, so the seat named for frame
/// transactions hid the Frames chip from anyone who had not already sent one.
/// Now the strip is the same four chips on every address, and a scope with
/// nothing in it says what it would hold (`emptyHeadline`/`emptyBody`). That
/// obligation is what keeps this on the right side of §83.
///
/// Foundation-only by design: `scripts/frames-tx-selftest.sh` compiles it
/// WHOLE and unmodified. Every failure it catches renders as a perfectly
/// ordinary room — a scope that never appears, a remembered scope resolving to
/// one nobody picked, or a strip drawn over a single chip.
enum FramesSection: String, CaseIterable, Identifiable, Sendable {
    case home
    case activity
    case holdings
    case accounts
    case frames
    case sponsors

    var id: String { rawValue }

    /// The strip's order. `allCases` already declares it, but the order is a
    /// RULING rather than an accident of declaration, so it is stated where a
    /// reader will look and where a self-test can assert it.
    ///
    /// **Home leads and is the fallback**, matching Wallet, vibenet and
    /// Hegotá: Home is the crown and its line, and opening anywhere else puts
    /// a tap between the crown and its own breakdown.
    ///
    /// **`frames` leads the conditional tail** for Hegotá's reason, one step
    /// stronger: frame transactions are not merely this room's rarest reading,
    /// they are the entire reason the chain and this seat exist. It also reads
    /// directly off `activity`, which precedes it — the list says what moved,
    /// this says what the transactions DID — so the two sit adjacent.
    static let order: [FramesSection] = [.home, .activity, .holdings, .accounts, .frames, .sponsors]

    /// Which scopes can be EMPTY.
    ///
    /// **It no longer gates `present()` (prd §611)** — every scope is drawn
    /// always — and it is kept, with its family name, for the two jobs it
    /// still does: it fixes the ORDER (the scopes that can be empty sit at the
    /// tail, so the strip's head is the same two chips on every address), and
    /// it is what obliges a scope to carry an `emptyBody`.
    var isConditional: Bool {
        switch self {
        case .home, .activity: return false
        case .holdings, .accounts, .frames, .sponsors: return true
        }
    }

    /// The room's constants. A watched address always has a balance reading
    /// (even "couldn't be read", which is itself the answer), and an empty
    /// stream is a real answer rather than an absence.
    var isAlwaysPresent: Bool { self == .home || self == .activity }

    var label: String {
        switch self {
        case .home:     return String(localized: "Home")
        case .activity: return String(localized: "Activity")
        case .holdings: return String(localized: "Holdings")
        case .accounts: return String(localized: "Accounts")
        // **"Frames", the literal term** — Hegotá's Nonces ruling, applied
        // again. EIP-8141 calls them frames, the RPC field is `frames`, the
        // chain is NAMED for them, and the seat is called Hegotá Frames.
        // A friendlier gloss would leave one room using two words for one
        // thing, and the chip is where the word gets learned.
        case .frames:   return String(localized: "Frames")
        case .sponsors: return String(localized: "Sponsors")
        }
    }

    /// What the scope holds — the accessibility label and the tooltip. The
    /// short nouns are learnable but not self-explaining.
    var summary: String {
        switch self {
        case .home:     return String(localized: "The balance, and the last few moves")
        case .activity: return String(localized: "What moved, and whether it worked")
        case .holdings: return String(localized: "The tokens this address holds")
        case .accounts: return String(localized: "The addresses you watch, and how they relate")
        case .frames:   return String(localized: "The steps each transaction ran")
        case .sponsors: return String(localized: "Transactions somebody else paid for")
        }
    }

    /// Which scopes the strip offers: **every one, on every address (prd
    /// §611).** The two Bools this used to take are gone rather than ignored —
    /// an unused `sponsors:` at the call site is an invitation to re-gate on
    /// it by accident.
    static func present() -> [FramesSection] { order }

    /// **THE SHORT STATE, drawn in the chassis' reserved headline row (prd
    /// §611).** Nil for `home`, which is never empty: the crown is its content.
    var emptyHeadline: String? {
        switch self {
        case .home:     return nil
        case .activity: return String(localized: "None yet")
        case .holdings: return String(localized: "Test ETH only")
        case .accounts: return String(localized: "No connections yet")
        case .frames:   return String(localized: "No steps")
        case .sponsors: return String(localized: "None sponsored")
        }
    }

    /// **WHAT THE SCOPE WOULD HOLD, and why this address has none.** No
    /// subject (the face rail above says which is scoped), no door (Top up and
    /// Send are Home's tiles, §553), and nothing that states a chain-wide fact
    /// — every transaction measured on this chain is self-paid, and a sentence
    /// saying so becomes a lie the first time one is not.
    var emptyBody: String? {
        switch self {
        case .home:
            return nil
        case .activity:
            return String(localized: "What moved, newest first, and whether the chain accepted it. Nothing from what you watch has landed on the stretch of chain this read covered.")
        case .holdings:
            return String(localized: "The tokens an address holds besides the chain's own coin. Nothing you watch holds one — the balance on Home is the whole of it.")
        case .accounts:
            return String(localized: "How the addresses you watch relate — who they have both dealt with. None of them shares a counterparty yet, so there is nothing to draw between them.")
        case .frames:
            return String(localized: "A framed transaction runs its work in numbered steps, each with a budget of its own. Nothing here has run any — a plain transfer runs none.")
        case .sponsors:
            return String(localized: "A sponsored transaction is one somebody else paid the gas for. Every transaction here paid its own.")
        }
    }

    /// Which chips wear a dot.
    ///
    /// **None, ever** — §500's ruling, and it holds here for the same reason
    /// one step stronger: nothing in this room is urgent. No deadline, no
    /// liquidation, no expiry, no grant to revoke, and the asset is test ETH
    /// on a chain that says it may be reset without notice. A marker that can
    /// never honestly light is chrome.
    ///
    /// Returning an empty set rather than dropping the call keeps
    /// `DSSectionSwitcher`'s `attention` parameter honest for Wallet, which
    /// uses it for a genuinely rare state.
    /// **NO DOT, EVER** (user, 2026-09-01: "get rid of this yellow dot too
    /// please").
    ///
    /// It was wired for one pass to mark `.frames` when a frame had been
    /// rolled back, as the pointer replacing the sentence Home lost to
    /// clipping. The ruling is that the pointer was not wanted: the Frames
    /// scope DRAWS those steps as dashed cells with their own caption, so the
    /// dot decorated a fact that was already visible one tap away, on a room
    /// the same session had just spent trimming.
    ///
    /// Keeping the function rather than deleting the parameter keeps
    /// `DSSectionSwitcher`'s `attention` honest for Wallet, which uses it for
    /// a genuinely rare state, and leaves one obvious place to put a dot back
    /// if this room ever earns one.
    static func attention() -> Set<FramesSection> { [] }

    /// Resolve the scope actually shown from the one the person last picked.
    ///
    /// **Falls back to `.home`, never to "the first present scope."** The two
    /// differ only when `home` is somehow absent, which cannot happen — and
    /// that is the point: an unreachable branch that quietly picks `frames` is
    /// how a room starts opening somewhere nobody chose. A remembered scope
    /// whose content has since gone resolves to the crown rather than to an
    /// empty page claiming to be a section.
    static func resolve(_ wanted: FramesSection?, present: [FramesSection]) -> FramesSection {
        guard let wanted, present.contains(wanted) else { return .home }
        return wanted
    }

    /// Whether the strip is worth drawing at all. One scope is not a control,
    /// it is a label — §83's dead-control ban, in the room where the control's
    /// whole job is to say there is more than one place to be.
    static func shows(present: [FramesSection]) -> Bool { present.count > 1 }
}
