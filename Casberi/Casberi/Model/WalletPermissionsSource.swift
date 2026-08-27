import Foundation

/// The two real reads, flattened onto `WalletPermissions.Holder` (prd §490).
///
/// Separate from `WalletPermissions` because that file is Foundation-only so
/// a harness can compile its arithmetic WHOLE, and both source types here
/// reach the chain. Every judgement lives there; this is the mapping and
/// nothing else.
enum WalletPermissionsSource {

    /// One holder per token approval, and one per acting party.
    ///
    /// **`exposure.priced` FIRST, then `exposure.unpriced`, and the order
    /// inside each is preserved** — `WalletApprovalExposure` has already
    /// ranked its priced grants by dollars at stake, which is the whole point
    /// of that type, so a rung's two named holders are its two biggest. A
    /// re-sort here would silently throw §292's ranking away.
    static func holders(exposure: WalletApprovalExposure,
                        acting: [WalletActingParties.Account]) -> [WalletPermissions.Holder] {
        var out: [WalletPermissions.Holder] = []

        // The acting parties lead the array as well as the rung order. Not
        // decorative: `rungs` groups rather than sorts, so array position only
        // decides which names a rung shows — but a Safe module and a delegate
        // are each alone in their rung, so this is really about keeping the
        // read in one obvious order for anyone debugging the probe output.
        for account in acting {
            for party in account.parties {
                guard let power = power(for: party.kind) else { continue }
                out.append(.init(power: power,
                                 name: party.displayName,
                                 // NO amount, ever, for any of these — none of
                                 // them has one, and the whole reason this
                                 // card exists is that a money-ranked card
                                 // would have to invent a zero to place them.
                                 usd: nil,
                                 note: nil))
            }
        }

        for grant in exposure.priced + exposure.unpriced {
            out.append(.init(power: power(for: grant),
                             name: grant.spender,
                             // An operator grant carries no amount BY
                             // DEFINITION (§292: this app prices no NFT), so
                             // its `usd` is dropped even when one somehow
                             // arrived — a priced collection would put a
                             // figure on the one rung that must not have one.
                             usd: grant.forAll ? nil : grant.usd,
                             note: nil))
        }
        return out
    }

    /// A grant's rung. `forAll` is tested BEFORE `unlimited` because an
    /// operator grant may legitimately be flagged both — it is unlimited in
    /// the sense that matters — and filing it under `unlimitedToken` would
    /// put a collection in a rung whose sentence names a token and whose
    /// total is dollars.
    static func power(for grant: WalletApprovalExposure.Grant) -> WalletPermissions.Power {
        if grant.forAll { return .wholeCollection }
        if grant.unlimited { return .unlimitedToken }
        return .cappedAmount
    }

    /// An acting party's rung, or nil for one this card has no rung for.
    ///
    /// Exhaustive over `Party.Kind` on purpose: a new kind of holder should
    /// fail to compile here rather than silently vanish from a card whose
    /// entire job is to be complete.
    static func power(for kind: WalletActingParties.Party.Kind) -> WalletPermissions.Power? {
        switch kind {
        case .safeModule:            .movesWithoutSignature
        case .delegate:              .actsAsWallet
        // A ROOT credential holds permanent authority and belongs with the
        // delegate; a SESSION key is scoped and the registry publishes no way
        // to read that scope, which is exactly why `scopedSigner` sits above
        // a capped grant rather than below it (§293's ceiling rule).
        case .altanaKey(true, _):    .actsAsWallet
        case .altanaKey(false, _):   .scopedSigner
        }
    }
}
