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
///   • **Accounts** — this one IS a choice. Hegotá gives the roster its own
///     unconditional scope; here `home` carries it, because the list is short
///     by construction (usually just the account you made) and a scope that
///     shows one row on nearly every install is the dead control §83 bans.
///     Revisit it if watching several here ever becomes ordinary.
///
/// Wallet's own four stay absent for §500's reasons, all of which hold:
/// **Holdings** (one asset, so the crown states the whole of it), **Positions**
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
/// Foundation-only by design: `scripts/frames-tx-selftest.sh` compiles it
/// WHOLE and unmodified. Every failure it catches renders as a perfectly
/// ordinary room — a scope that never appears, a remembered scope resolving to
/// one nobody picked, or a strip drawn over a single chip.
enum FramesSection: String, CaseIterable, Identifiable, Sendable {
    case home
    case activity
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
    static let order: [FramesSection] = [.home, .activity, .frames, .sponsors]

    /// Everything past `activity` is conditional on the address actually
    /// having the thing. Stated as data rather than left implicit in
    /// `present(…)`, because it is the whole reason the order ends this way:
    /// no UNCONDITIONAL scope may sit after a conditional one, so the strip's
    /// stable head never reflows.
    var isConditional: Bool {
        switch self {
        case .home, .activity: return false
        case .frames, .sponsors: return true
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
        // **"Frames", the literal term** — Hegotá's Nonces ruling, applied
        // again. EIP-8141 calls them frames, the RPC field is `frames`, the
        // chain is NAMED for them, and the seat is called Frames Devnet.
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
        case .frames:   return String(localized: "The steps each transaction ran")
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
    /// transaction measured on this chain is self-paid — and that is the
    /// correct output rather than a gap. The scope declines silently and
    /// appears the first time somebody sponsors one.
    static func present(frames: Bool, sponsors: Bool) -> [FramesSection] {
        order.filter { section in
            switch section {
            case .home:     return true
            case .activity: return true
            case .frames:   return frames
            case .sponsors: return sponsors
            }
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
