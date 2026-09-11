import Foundation

/// WHAT IS ALLOWED TO ACT ON YOUR ACCOUNTS — the Permissions scope's figure,
/// in every room that has one (prd §692).
///
/// **The scope is one scope now.** Wallet and vibenet each had a Permissions
/// chip; Hegotá UTXO kept the same reading under "Nonces" and "Sponsors",
/// Hegotá Privacy under "Spend keys" and "Sponsors", Hegotá Frames under
/// "Sponsors" alone. Five rooms, nine chips, one question — user, 2026-09-11:
/// *"they are just different kinds of permissions. actions permissable on the
/// account which have been granted."*
///
/// **Two TENSES under one roof, and the row is what tells them apart.** A
/// standing grant (a token approval, a vibenet key, a keyed nonce lane) is
/// authority that survives until somebody revokes it. An exercised one (a
/// spend key used once, a sponsor who paid) is authority that was granted and
/// spent. Both belong to the question "what is allowed on this account" and
/// neither may wear the other's words: a standing row says what it CAN do
/// ("Can move up to a cap", "Session · lapses in 3d"), an exercised one says
/// what it DID ("Spent once", "Paid for 3 transactions").
///
/// **The figure is counts by kind and never names a holder** (§546's ruling,
/// inherited whole): the list below owns the names, this owns the arithmetic,
/// and a slot that restates the list is the tally §292 refused.
///
/// **Colour marks UNBOUNDEDNESS and nothing else** — not severity, which would
/// be this app grading decisions somebody made on purpose.
///
/// Foundation-only, so every room's own harness can drive the rules it states
/// — `hegota-selftest.sh` compiles `HegotaPermissions` against it, and the
/// count a headline states must be the same count that decides whether the
/// scope is empty.
enum RoomPermissions {
    /// One class of permission, with how many of them there are.
    struct Kind: Identifiable, Equatable, Sendable {
        /// The room's own words for this class. Never a borrowed neighbour's
        /// noun: a keyed nonce lane is not a key and a sponsor is not a
        /// delegate.
        let label: String
        let count: Int
        /// A figure this class can state completely — a dollar total where
        /// every holder is priced, an expiry where there is one. Nil is the
        /// normal case and draws nothing.
        var aside: String? = nil
        /// Whether this class is unrestricted. The one thing colour says.
        var unbounded: Bool = false

        var id: String { label }
    }

    /// The line above the grid, where a room has one to state. Wallet's
    /// "$1,240 · in reach" is the only one today; the devnets' chassis draws
    /// `headline` instead, which is why this is optional rather than required.
    struct Lead: Equatable, Sendable {
        let figure: String
        var caption: String? = nil
    }

    /// **THREE COLUMNS ONLY WHEN TWO CANNOT HOLD IT.** Four cells fit two rows
    /// of two at a rung a number can be read at; the fifth is what forces the
    /// narrower cell. Vibenet's census (six classes) has been three-wide since
    /// 2026-09-02 for exactly this reason and keeps that shape; a devnet with
    /// two kinds gets one row of two.
    /// A LONE KIND TAKES THE WHOLE WIDTH rather than sitting in half of a
    /// two-column grid with nothing beside it — Hegotá Frames grants exactly
    /// one kind of permission, and a half-empty row is the "one number adrift"
    /// §551 spent a whole pass removing from vibenet.
    static func columns(_ kinds: [Kind]) -> Int {
        kinds.count > 4 ? 3 : min(2, max(1, kinds.count))
    }

    /// The grid is never taller than two rows — `DSRoomChassis.figureSlot` is
    /// a hard, clipped box, and a third row is what shears off a label.
    static func cellsShown(_ kinds: [Kind]) -> Int { columns(kinds) * 2 }

    /// How many permissions sit past the fold, as a COUNT OF PERMISSIONS
    /// rather than of classes: "and 3 more" under a grid of counts has to be
    /// the same unit as the numbers above it or the two cannot be added.
    static func folded(_ kinds: [Kind]) -> Int? {
        let shown = cellsShown(kinds)
        guard kinds.count > shown else { return nil }
        let rest = kinds.dropFirst(shown).reduce(0) { $0 + $1.count }
        return rest > 0 ? rest : nil
    }

    static func total(_ kinds: [Kind]) -> Int { kinds.reduce(0) { $0 + $1.count } }

    /// "N permissions" — the scope's headline in every room, and the reason
    /// the three devnets' old headlines go: two of them stated the address's
    /// ETH BALANCE over a list of sponsors, which is a fact about money in a
    /// slot asking about authority.
    ///
    /// Nil when there is nothing granted at all, so the caller falls back to
    /// its section's own `emptyHeadline` (§611's obligation).
    static func headline(count n: Int) -> String? {
        guard n > 0 else { return nil }
        return n == 1 ? String(localized: "1 permission")
                      : String(localized: "\(String(n)) permissions")
    }

    /// **THE COUNT IS NOT ALWAYS THE CELLS ADDED UP, which is why the headline
    /// takes it rather than deriving it.** Wallet's rungs and the devnets'
    /// kinds PARTITION their permissions — every grant is in exactly one cell,
    /// so the sum is the total. Vibenet's census does not: one key holding
    /// Send and Receive is counted in both cells, and adding them would report
    /// more permissions than the account has keys. A room whose kinds
    /// partition passes this; vibenet passes its key count.
    static func headline(_ kinds: [Kind]) -> String? { headline(count: total(kinds)) }

    /// What a whole figure says aloud, in one sentence rather than as N cells
    /// (§299, and `WalletPermissionsCard`'s own treatment before it moved
    /// here): the claim is the ORDER, and a reader hearing each cell alone has
    /// to hold that order themselves.
    static func spoken(_ kinds: [Kind], lead: Lead?) -> String {
        var parts: [String] = []
        if let lead {
            parts.append([lead.figure, lead.caption].compactMap { $0 }.joined(separator: " "))
        }
        for kind in kinds.prefix(cellsShown(kinds)) where kind.count > 0 {
            parts.append("\(kind.count) \(kind.label)")
        }
        if let folded = folded(kinds) {
            parts.append(String(localized: "and \(folded) more"))
        }
        return parts.joined(separator: ", ")
    }
}

