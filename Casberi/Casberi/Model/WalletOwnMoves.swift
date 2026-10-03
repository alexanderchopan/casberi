import Foundation

/// ONE MOVE BETWEEN YOUR OWN ACCOUNTS, ONE ROW (prd §1078, user: "do all the
/// changes you suggested"). The One Wallet reads every account you have, so
/// money moved from one of them to another landed twice: "Sent 0.5 ETH" on
/// the account it left and "Received 0.5 ETH" on the one it reached, with
/// opposite signs, as if two things had happened. Home now draws the pair as
/// one row ("Moved 0.5 ETH · main → Savings") with no sign and no colour,
/// because money that stayed yours nets to nothing (§83).
///
/// **Joined on evidence, never on a guess.** A sent leg and a received leg
/// pair only when they share a transaction link, or when the sent leg went to
/// the very address the received leg arrived at, carrying the same amount
/// within `window`. Every row in the Wallet room is one of the person's own
/// accounts, so an address that received is theirs by construction; nothing
/// here consults a watch list. A leg pairs at most once, and with the nearest
/// leg in time.
///
/// Display only: both rows stay in the store and in the history screen. This
/// decides what Home draws, nothing more.
///
/// Foundation-only and pure: `CasberiTests/WalletOwnMovesTests` composes it.
enum WalletOwnMoves {

    struct Leg: Equatable {
        let id: UUID
        let sent: Bool
        /// The account the leg belongs to (`Thing.walletAddress`).
        let address: String?
        /// The other side (`Thing.counterpartyAddress`).
        let counterparty: String?
        /// "0.5 ETH", as the title leads with it.
        let amount: String?
        /// The explorer link, which names the transaction.
        let link: String?
        let at: Date
    }

    struct Pair: Equatable {
        let sent: UUID
        let received: UUID
    }

    /// How far apart the two legs may land when they share no link: a
    /// withdrawal can confirm some minutes after it leaves.
    static let window: TimeInterval = 2 * 3600

    static func pairs(_ legs: [Leg]) -> [Pair] {
        let sent = legs.filter(\.sent)
        var open = legs.filter { !$0.sent }
        var out: [Pair] = []
        for leg in sent {
            let candidates = open.enumerated().filter { matches(sent: leg, received: $0.element) }
            guard let best = candidates.min(by: {
                abs($0.element.at.timeIntervalSince(leg.at)) < abs($1.element.at.timeIntervalSince(leg.at))
            }) else { continue }
            out.append(Pair(sent: leg.id, received: best.element.id))
            open.remove(at: best.offset)
        }
        return out
    }

    static func matches(sent: Leg, received: Leg) -> Bool {
        guard sent.id != received.id else { return false }
        if let a = sent.link, !a.isEmpty, a == received.link { return true }
        guard let to = sent.counterparty, let at = received.address, same(to, at),
              meaningful(sent.amount), sent.amount == received.amount,
              abs(sent.at.timeIntervalSince(received.at)) <= window
        else { return false }
        // The received leg names where it came from when it knows; it must
        // then be the account the sent leg left.
        if let from = received.counterparty, let origin = sent.address, !same(from, origin) { return false }
        return true
    }

    /// An amount with a nonzero digit: "ETH" alone, or "0.0000 ETH", proves
    /// nothing about two legs being one move.
    static func meaningful(_ amount: String?) -> Bool {
        amount?.contains(where: { ("1"..."9").contains($0) }) ?? false
    }

    static func same(_ a: String, _ b: String) -> Bool {
        a.caseInsensitiveCompare(b) == .orderedSame
    }
}
