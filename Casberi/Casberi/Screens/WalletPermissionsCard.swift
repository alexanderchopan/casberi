import SwiftUI

/// WHO CAN ACT FOR YOU — the `Permissions` scope's lead drawing (prd §490,
/// reshaped as COUNTS by §546, and MOVED ONTO THE SHARED FIGURE by §692).
///
/// Every judgement is `WalletPermissions`'; the SHAPE is now
/// `RoomPermissionsFigure`, which five rooms draw. What survives here is the
/// translation — a wallet's power rungs become the shared figure's kinds — and
/// the two facts only this room can state: the dollars in reach, and whether a
/// rung's total is complete enough to say out loud.
///
/// The rulings the shape carries, unchanged and now carried for everyone:
/// aggregate figures and NO names (§546 — the list below owns the names, this
/// owns the arithmetic); colour marks UNBOUNDEDNESS and nothing else; a rung
/// states its total only when every holder in it is priced; bare on the page
/// (§483: *"we don't do cards"*).
///
/// **The one visible change §692 makes here**: a cell is a well rather than a
/// bare numeral, and the numeral is `price17` rather than `price40` — vibenet's
/// census grammar, which is what lets a class with nothing in it draw a dash
/// instead of a "0" that reads as a measurement.
struct WalletPermissionsCard: View {
    let holders: [WalletPermissions.Holder]
    /// The scope's caption, the crown's own (prd §924).
    var caption: String? = nil

    private var rungs: [WalletPermissions.Rung] { WalletPermissions.rungs(holders) }

    var body: some View {
        RoomPermissionsFigure(kinds: WalletPermissionsCard.kinds(rungs, holders: holders),
                              lead: lead, caption: caption)
    }

    /// One kind per rung, in the rungs' own order (most reach first).
    /// One kind per rung, carrying its holders so a key can be pressed and
    /// named (prd §924) — the same holders the rows below list.
    static func kinds(_ rungs: [WalletPermissions.Rung],
                      holders: [WalletPermissions.Holder] = []) -> [RoomPermissions.Kind] {
        rungs.map { rung in
            RoomPermissions.Kind(label: rung.power.word,
                                 count: rung.count,
                                 phrase: rung.power.phrase,
                                 aside: aside(rung),
                                 unbounded: rung.power.isUnbounded,
                                 holders: holders.filter { $0.power == rung.power }.map {
                                     RoomPermissions.Holder(name: $0.name, usd: $0.usd, note: $0.note)
                                 })
        }
    }

    /// The total, which the rungs deliberately cannot carry: they answer
    /// "what can be done", this answers "to how much". Silent when nothing
    /// here has a figure at all — a wallet whose only holder is a Safe module
    /// has real exposure and no dollars to state, and "$0" there would be the
    /// most misleading thing on the card.
    private var lead: RoomPermissions.Lead {
        if let total = WalletPermissions.totalUSD(holders) {
            return RoomPermissions.Lead(figure: WalletApprovalExposure.money(total),
                                        caption: String(localized: "in reach"))
        }
        return RoomPermissions.Lead(figure: String(localized: "Who can act for you"))
    }

    /// The rung's total, beside its numeral — only when the rung is FULLY
    /// priced (§490's refusal: a partial sum looks complete, which is worse
    /// than no sum), and "no amount to state" only where a figure was
    /// EXPECTED (`Power.canCarryAmount`) — on a module or a collection grant
    /// it is an apology for a fact.
    ///
    /// No names, ever: the acting list and the approvals list directly below
    /// carry every holder, and a name here is the slot restating them (§546).
    static func aside(_ rung: WalletPermissions.Rung) -> String? {
        if let usd = rung.usd {
            return WalletApprovalExposure.money(usd)
        }
        if rung.hasUnpriced, rung.power.canCarryAmount {
            return String(localized: "no amount to state")
        }
        return nil
    }
}
