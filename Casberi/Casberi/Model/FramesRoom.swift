import Foundation

/// THE FRAMES DEVNET ROOM'S HEAD — what the room says before anything is
/// tapped (prd §548). Foundation-only BY DESIGN so
/// `scripts/frames-tx-selftest.sh` compiles it WHOLE.
///
/// ## THREE BLACK-SCREEN TRAPS, INHERITED RATHER THAN REDISCOVERED
///
/// This seat lands NO `Thing`, ever — its whole content is this head. Hegotá
/// is the same shape and reached a device with a black screen four times
/// before its three causes were written down. All three apply here unchanged,
/// so they are encoded rather than left to be found again:
///
/// 1. **A nil head is a BLACK SCREEN, not a quiet room.** `FeedScreen`'s
///    `if/else if` falls through both arms when a source has no rows and no
///    head, and renders nothing at all. So `head` returns nil only when there
///    is genuinely nothing to watch — never as a way of saying "not ready".
/// 2. **The demo installs accounts without watching anything**, so keying on
///    the watch list alone returns nil in a demo. `watching` takes the LARGER
///    of the watch list, the account count and a demo floor of 1 — which also
///    closes a chicken-and-egg, since the fixture is installed by the card's
///    own task and the card only mounts once this returns a head.
/// 3. **The head must not be memoised off the corpus revision.** Every other
///    room re-keys when a sweep lands the row that changed it; this one lands
///    no row, so its revision never moves and a head composed once while empty
///    would be kept forever. `FramesRoomSource.identity` is the key.
///
/// ## WHAT THIS ROOM LEADS WITH THAT NEITHER NEIGHBOUR CAN
///
/// `rolledBackCount` — frames whose value did NOT land. Measured on this chain
/// (§548, second follow-up): a frame inside an atomic batch reports
/// `status: 0x1` after being rolled back, and a transaction reporting
/// `status: 0x0` can still have moved money. So the count is read from
/// EFFECTS, never status, and it is the one number in this app that can only
/// be stated because the chain publishes every ETH movement as a log.
enum FramesRoom {

    /// What the head is ABOUT, which decides the headline. Ordered by
    /// precedence rather than by mood: the two states that mean "we cannot
    /// tell you anything yet" outrank the reading, because a balance drawn
    /// over an unreached chain is a confident zero.
    enum Lead: String, Equatable, Sendable {
        /// Nothing has been read yet on this device.
        case reading
        /// Addresses are watched and NOT ONE answered. Distinct from a zero
        /// balance, and the distinction is the whole of §515a.
        case unreached
        /// Money the sender meant to move and which was rolled back. Leads
        /// because it is the only thing here somebody might act on.
        case rolledBack
        /// The ordinary reading: what this account holds.
        case balance
    }

    struct Head: Equatable, Sendable {
        let lead: Lead
        let hasRead: Bool
        /// RAW HEX — a genesis account on this chain holds 99,999 ETH, which
        /// overflows `UInt64` as wei (see `FramesMoney`).
        let balanceWeiHex: String?
        let reached: Int
        let watched: Int
        let moveCount: Int
        /// Transactions that decompose into more than one frame — which is
        /// every frame transaction, and none of the ordinary transfers this
        /// chain also carries.
        let frameCount: Int
        let sponsoredCount: Int
        /// Read from EFFECTS, never status. See the type doc.
        let rolledBackCount: Int

        /// Some answered and some did not. The room says so rather than
        /// drawing a total that silently omits an address.
        var partial: Bool { reached < watched }
        var everythingUnreached: Bool { watched > 0 && reached == 0 }
    }

    /// Compose the head, or nil when there is genuinely nothing to watch.
    ///
    /// **Nil is not "not ready"** — see trap 1. A watched address that has not
    /// answered still gets a head, because "couldn't reach the chain" is
    /// itself the answer and a room that says it is better than one that is
    /// black.
    static func head(_ accounts: [FramesAccount],
                     hasRead: Bool = true,
                     watching: Int = 0) -> Head? {
        let watched = max(watching, accounts.count)
        guard watched > 0 else { return nil }

        let reached = accounts.filter(\.reached)
        let moves = reached.flatMap(\.moves)
        let rolled = reached.flatMap(\.rolledBack).count

        let lead: Lead
        if !hasRead {
            lead = .reading
        } else if reached.isEmpty {
            lead = .unreached
        } else if rolled > 0 {
            lead = .rolledBack
        } else {
            lead = .balance
        }

        return Head(
            lead: lead,
            hasRead: hasRead,
            // The FIRST reached account's balance — this room's crown is one
            // account, not a portfolio. Summing across addresses would state a
            // total nobody holds: these are separate accounts on a test chain,
            // not one person's holdings (Wallet's own combined-total rule does
            // not carry, because there the addresses are all yours by
            // construction and here a watched one is usually a stranger's).
            balanceWeiHex: reached.first?.balanceWeiHex,
            reached: reached.count,
            watched: watched,
            moveCount: moves.count,
            frameCount: moves.filter { $0.rows.count > 1 }.count,
            sponsoredCount: moves.filter(\.sponsored).count,
            rolledBackCount: rolled)
    }

    /// Which scopes this room actually has, so the switcher never offers a
    /// chip that opens nothing — derived from the composed room rather than
    /// from the watch list.
    static func sections(_ accounts: [FramesAccount]) -> [FramesSection] {
        let reached = accounts.filter(\.reached)
        let moves = reached.flatMap(\.moves)
        return FramesSection.present(
            frames: moves.contains { $0.rows.count > 1 },
            sponsors: moves.contains { $0.sponsored })
    }
}
