import Foundation

/// The Ethrex Privacy room's SCOPE — which of its seven readings is on screen
/// (prd §593).
///
/// **Hegotá's template, this chain's vocabulary and this chain's measurements.**
/// `HegotaSection` is the shape (`order` as a ruling, `present(…)` over plain
/// Bools, `resolve` falling back to `.home`, `shows` refusing a control over one
/// chip). Two names differ and one is absent, each because the CHAIN differs —
/// measured 2026-09-04 against `rpc1.privacy.ethrex.xyz`, not inferred from
/// ethrex's announcement.
///
/// **`coins` is ABSENT, not empty.** The UTXO vault predeploy `0x…8312` has no
/// code on chain 8141 — measured, against 76 bytes on Hegotá. So there are no
/// unspent outputs to list and never will be on this deployment. A permanently
/// empty chip is the dead control §83 bans, and this is the sharpest case of it
/// in the family: the scope would look identical to a wallet that merely holds
/// nothing. Hegotá keeps it and this room does not, which is also how the strip
/// says which chain you are in without a word of copy.
///
/// **`nullifiers`, not "Nonces" — and the divergence is a FACT about the chain
/// rather than a preference.** Hegotá names the scope after the mechanism
/// because that is all the mechanism does there: EIP-8250 keyed nonces let
/// sends run in parallel, and its own summary says so. Here the same field is
/// doing a different job. The pool contract emits every spent key as a log
/// topic BYTE-IDENTICAL to the transaction's own `nonceKeys` — block 13347's
/// two keys are that event's two topics — and every one carries `nonceSeq` 0,
/// spent once. That is a nullifier, not a queue. Calling it "Nonces" here would
/// name the mechanism while hiding what it is for, in the one room whose whole
/// subject is what it is for.
///
/// **`roots` has no counterpart anywhere in this app.** EIP-8272's predeploy
/// `0x…8272` carries 144 bytes here and NO CODE on Hegotá, so this is the only
/// chain where the reading exists at all. See `PrivacyRoots` for the window
/// arithmetic and for why the number it reports is a deadline rather than a
/// count.
///
/// Foundation-only by design: `scripts/privacy-selftest.sh` compiles it WHOLE
/// and unmodified. Every failure it catches renders as a perfectly ordinary
/// room — a scope that never appears, a remembered scope resolving to one
/// nobody picked, or a strip drawn over a single chip.
enum PrivacySection: String, CaseIterable, Identifiable, Sendable {
    case home
    case activity
    case accounts
    case frames
    case nullifiers
    case roots
    case sponsors

    var id: String { rawValue }

    /// The strip's order — a RULING, not an accident of declaration
    /// (`WalletSection.order`'s reasoning), so it is stated where a reader will
    /// look for it and where a self-test can assert it.
    ///
    /// **Home leads and is the fallback**, matching Wallet, vibenet and Hegotá.
    ///
    /// **The conditional tail starts at `frames`**, so Wallet's tail rule holds:
    /// no unconditional scope sits after a conditional one, and `home`,
    /// `activity` and `accounts` all precede it.
    ///
    /// **`nullifiers` and `roots` sit adjacent, in that order, and the pairing
    /// is the point.** They are the two halves of one mechanism — a nullifier
    /// says this spend cannot happen twice, a root says which set it was proved
    /// against — and a reader who meets them apart meets two unrelated pieces of
    /// jargon. Nullifiers leads because it is the half that concerns YOUR
    /// transaction; roots is the half that concerns the chain's state.
    static let order: [PrivacySection] = [.home, .activity, .accounts, .frames,
                                          .nullifiers, .roots, .sponsors]

    /// Everything past `accounts` is conditional on the address actually having
    /// the thing. Stated as data rather than left implicit in `present(…)`,
    /// because it is the whole reason the order ends the way it does.
    var isConditional: Bool {
        switch self {
        // A watched address always has a roster row — even one saying the chain
        // could not be reached, which is itself the answer (vibenet's rule).
        case .home, .activity, .accounts: return false
        case .frames, .nullifiers, .roots, .sponsors: return true
        }
    }

    var isAlwaysPresent: Bool { !isConditional }

    var label: String {
        switch self {
        case .home:       return String(localized: "Home")
        case .activity:   return String(localized: "Activity")
        case .accounts:   return String(localized: "Accounts")
        case .frames:     return String(localized: "Frames")
        case .nullifiers: return String(localized: "Nullifiers")
        case .roots:      return String(localized: "Roots")
        case .sponsors:   return String(localized: "Sponsors")
        }
    }

    /// What the scope holds — the accessibility label and the tooltip.
    ///
    /// **`nullifiers` and `roots` are the two that must not overclaim.** Every
    /// transaction on this chain carries `sender` in the clear and EIP-8182's
    /// protocol-level pool is not deployed, so nothing here hides who
    /// transacted or how much. What is shielded is the LINK between a
    /// commitment and its spend, and these sentences say exactly that and no
    /// more — §83 in the domain where believing it is most expensive.
    var summary: String {
        switch self {
        case .home:       return String(localized: "The line, and the last few moves")
        case .activity:   return String(localized: "What moved, and what each transaction did")
        case .accounts:   return String(localized: "The addresses you watch, and what each holds")
        case .frames:     return String(localized: "The steps your transactions ran")
        case .nullifiers: return String(localized: "Spend keys used once, so a spend can't be repeated")
        case .roots:      return String(localized: "Which snapshot a proof was made against")
        case .sponsors:   return String(localized: "Transactions somebody else paid for")
        }
    }

    /// Which scopes have anything to show.
    ///
    /// Takes plain Bools rather than live chain state, for
    /// `WalletSection.present`'s reason: this file is Foundation-only so its
    /// rules compile and mutation-test with no `ModelContext` and no network.
    /// The call site does the reading; this does the deciding.
    ///
    /// **`sponsors` is expected false on every address today** — no measured
    /// transaction on this chain has a `payer` differing from its sender — and
    /// that is the correct output rather than a gap.
    ///
    /// **There is deliberately no `coins:` parameter.** Not "always false": the
    /// case does not exist, so a future caller cannot pass true and light a
    /// chip over a vault that has no code.
    static func present(frames: Bool, nullifiers: Bool, roots: Bool,
                        sponsors: Bool) -> [PrivacySection] {
        order.filter { section in
            switch section {
            case .home:       return true
            case .activity:   return true
            case .accounts:   return true
            case .frames:     return frames
            case .nullifiers: return nullifiers
            case .roots:      return roots
            case .sponsors:   return sponsors
            }
        }
    }

    /// Which chips wear a dot.
    ///
    /// **None, ever** — Hegotá's ruling, and it survives the one thing that
    /// might have overturned it. `roots` has a genuine CLOCK (a referenced root
    /// leaves the 8192-slot window ~27 hours after it is registered), and a
    /// clock is normally what earns a dot. It does not here, because the
    /// expiry is a fact about a proof somebody already made and landed: nothing
    /// is lost when the window closes, nothing can be done before it does, and
    /// a dot that lights on a deadline you cannot act on is chrome wearing
    /// urgency. See `PrivacyRoots.expiry` — it reports, it never alarms.
    static func attention() -> Set<PrivacySection> { [] }

    /// Resolve the scope actually shown from the one the person last picked.
    ///
    /// Falls back to `.home`, never to "the first present scope" — an
    /// unreachable branch that quietly picks `roots` is how a room starts
    /// opening somewhere nobody chose.
    static func resolve(_ wanted: PrivacySection?, present: [PrivacySection]) -> PrivacySection {
        guard let wanted, present.contains(wanted) else { return .home }
        return wanted
    }

    /// Whether the strip is worth drawing at all. One scope is a label, not a
    /// control — §83's dead-control ban.
    static func shows(present: [PrivacySection]) -> Bool { present.count > 1 }
}
