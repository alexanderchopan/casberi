import Foundation

/// ACCOUNTS YOU CAN ACT FOR — the Accounts scope's drawing (prd §491).
///
/// Foundation-only BY DESIGN so `scripts/vibenet-selftest.sh` can compile it
/// WHOLE; every read and every view lives elsewhere.
///
/// **The data was already here and nothing drew it.**
/// `VibenetBridge.subAccounts(delegate:keystore:)` has run in the account read
/// since the bridge shipped — one call per address, concurrent with the rest —
/// and its result landed on `VibenetAccountItem.subAccounts` where exactly one
/// card in one branch showed it. That branch was the single-account page the
/// chassis never reached, so in practice the reading was invisible.
///
/// **Why this and not the delegate spine** (user pick of three drawings): the
/// spine draws watched↔watched links, so it says nothing at all for somebody
/// watching one account — which is the ordinary case — and its own subject is
/// the same relationship this one covers more completely. A sub-account is an
/// account that authorized YOU: you can act for it. Here they are one drawing,
/// split by whether this device already watches the other side.
///
/// **The unwatched half is the point.** A watched sub-account is already on
/// screen elsewhere; an UNWATCHED one is an account you control and may not
/// know about, and it is the only row here that can offer to do something.
enum VibenetAccountWeb {

    /// One account you can act for.
    struct Node: Equatable, Identifiable, Sendable {
        let address: String
        /// Whether this device already watches it — see the type doc for why
        /// the FALSE case is the reason this drawing exists.
        let watched: Bool
        /// When the authorization landed, nil on a failed block-time lookup.
        /// Never defaulted to now: an undated authorization drawn as today's
        /// would claim you granted it this morning (`PeerRoom`'s rule).
        let authorizedAt: Date?
        var id: String { address }
    }

    /// What the drawing shows for one account.
    struct Web: Equatable, Sendable {
        /// The account everything here hangs off — the scoped one, or the
        /// only one watched.
        let owner: String
        let nodes: [Node]
        /// How many of `nodes` this device does not watch. Precomputed so the
        /// view and the accessibility sentence cannot disagree.
        let unwatched: Int

        var isEmpty: Bool { nodes.isEmpty }
    }

    /// How many nodes the fixed slot draws before folding the rest into a
    /// count. Four — the slot is 210pt and a node is a face plus two lines.
    static let nodesShown = 4

    /// The web for one account, or nil when it can act for nothing.
    ///
    /// **UNWATCHED FIRST, then oldest.** Not alphabetical and not the read's
    /// own order: the whole reading is "there is an account here you did not
    /// know about", so burying it under three you already watch is the one
    /// ordering that defeats the drawing. Within each half, oldest first —
    /// an authorization you have lived with for a year is the one you are
    /// least likely to remember granting.
    ///
    /// An undated node sorts LAST within its half rather than first: nil is
    /// "we could not read the block time", and treating it as the oldest
    /// would rank a failed read above a real fact.
    static func web(owner: String, subAccounts: [VibenetSubAccount]) -> Web? {
        guard !subAccounts.isEmpty else { return nil }
        let nodes = subAccounts
            .map { Node(address: $0.address, watched: $0.watched, authorizedAt: $0.authorizedAt) }
            .sorted { a, b in
                if a.watched != b.watched { return !a.watched }
                switch (a.authorizedAt, b.authorizedAt) {
                case let (x?, y?): return x < y
                case (nil, _?):    return false
                case (_?, nil):    return true
                default:           return a.address < b.address
                }
            }
        return Web(owner: owner,
                   nodes: nodes,
                   unwatched: nodes.filter { !$0.watched }.count)
    }

    /// "2 accounts · 1 unwatched" — the headline.
    ///
    /// The unwatched clause is DROPPED when there are none, rather than
    /// reading "0 unwatched": a healthy state that has to say a zero out loud
    /// is a card apologising for being fine.
    ///
    /// **The second clause is three words, not five** (user, 2026-08-26; it
    /// shipped as "1 you don't watch yet" and truncated to "1 you don't
    /// watch…" on a 402pt screen). The headline is `stat24` and shares its
    /// line with the room's settings gear, which is 44pt of reserved trailing
    /// corner — so the budget here is about 300pt, and a sentence-shaped
    /// clause cannot fit it at that size. The card carries a
    /// `minimumScaleFactor`, but shrinking a headline to fit is a worse answer
    /// than writing one that fits: it makes the room's largest type a
    /// different size on every scope.
    ///
    /// "Unwatched" over "you don't watch": the row it points at already says
    /// "Not watched" and now carries a Watch button, so the headline is
    /// naming a state, not making a request.
    static func headline(_ web: Web) -> String {
        let n = web.nodes.count
        let count = n == 1
            ? String(localized: "1 account")
            : String(localized: "\(n) accounts")
        guard web.unwatched > 0 else { return count }
        return String(localized: "\(count) · \(web.unwatched) unwatched")
    }

    /// The whole drawing as one sentence — §299's rule, since a web of faces
    /// and dashes reads as nothing to a screen reader.
    static func spoken(_ web: Web) -> String {
        guard !web.isEmpty else {
            return String(localized: "This account can act for no others.")
        }
        let listed = web.nodes.map { node in
            node.watched
                ? String(localized: "\(node.address), watched")
                : String(localized: "\(node.address), not watched")
        }.joined(separator: "; ")
        return String(localized: "Accounts you can act for: \(listed).")
    }
}
