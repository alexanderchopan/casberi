import Foundation

/// WHERE THE CHANGES LANDED — the Activity scope's drawing (prd §491).
///
/// Foundation-only BY DESIGN so `scripts/vibenet-selftest.sh` can compile it
/// WHOLE; every read and every view lives elsewhere.
///
/// **A flow band, made honest.** The ask was for something sankey-shaped, and
/// the obvious pairing — key → account — is one this data cannot support: an
/// authorization records that a key BECAME able to act, not who granted it, so
/// a ribbon from a key to an account would draw a source the chain never
/// states. §83, on a security screen.
///
/// The pairing that IS in the data is EVENT KIND → THE ACCOUNT IT LANDED ON.
/// Every `VibenetKeyMoment` carries both halves, so every ribbon here is two
/// facts the chain actually published. What it says that a list of rows cannot
/// is WHICH ACCOUNT IS CHURNING — three revocations on one account and none on
/// the other two is the shape, and in a chronological list it is invisible.
///
/// **Wallet's flow band is NOT reused, and the reason is arithmetic.** That
/// band sizes its ribbons by dollars, so a lane's weight means magnitude. Here
/// the weight is a COUNT of events, and an authorization is not larger than a
/// revocation — they are different things that happened, not more and less of
/// one thing. Ribbons are weighted by count within their own kind and never
/// compared across kinds; the card states each kind's number in words beside
/// it rather than asking anyone to read one off a stroke.
enum VibenetChangeFlow {

    /// What happened. A closed set, in the order the drawing lists them —
    /// declared rather than sorted, so the rows are the same three on every
    /// account that has them and the shape is learnable.
    enum Kind: Int, CaseIterable, Comparable, Sendable {
        case authorized = 0
        case revoked = 1
        case locked = 2

        static func < (a: Kind, b: Kind) -> Bool { a.rawValue < b.rawValue }

        var label: String {
            switch self {
            case .authorized: String(localized: "Authorized")
            case .revoked:    String(localized: "Revoked")
            case .locked:     String(localized: "Locked")
            }
        }

        /// Whether this kind is drawn in the room's alarm colour.
        ///
        /// Only `locked`, and it is a STATE the account is in rather than a
        /// judgement we are making: a locked account cannot be acted for at
        /// all. An authorization is not an alarm — most of them are the
        /// account's owner adding a key on purpose — and colouring it would be
        /// this app grading somebody's own decisions.
        var isAlarming: Bool { self == .locked }
    }

    /// One ribbon: a kind, an account, and how many times it happened.
    struct Edge: Equatable, Identifiable, Sendable {
        let kind: Kind
        let address: String
        let count: Int
        var id: String { "\(kind.rawValue):\(address)" }
    }

    /// The whole drawing.
    struct Flow: Equatable, Sendable {
        let edges: [Edge]
        /// Accounts in first-appearance order, which is the room's own order —
        /// never re-sorted by volume, since a drawing whose rows reshuffle as
        /// events land reads as broken (§292's total-order rule).
        let addresses: [String]
        /// Per-kind totals, for the words beside each row.
        let totals: [Kind: Int]
        /// Every event counted, across kinds. Stated because the headline says
        /// it and a view recomputing it is how two numbers on one card come to
        /// disagree.
        let total: Int

        var isEmpty: Bool { edges.isEmpty }

        func total(_ kind: Kind) -> Int { totals[kind] ?? 0 }

        /// The heaviest edge WITHIN one kind — what that kind's ribbons are
        /// scaled against. Never the heaviest overall: scaling revocations
        /// against authorizations would draw one revocation as a hairline
        /// beside forty grants and say the account is quiet when it is not.
        func heaviest(_ kind: Kind) -> Int {
            edges.filter { $0.kind == kind }.map(\.count).max() ?? 0
        }
    }

    /// How many accounts the fixed slot draws before folding.
    static let addressesShown = 4

    /// Build the flow from each account's own moments plus its lock state.
    ///
    /// `locked` is passed separately and deliberately: a lock is a state read
    /// off the account right now, not an entry in its key history, so folding
    /// it into `moments` would mean inventing a moment with no block behind
    /// it. It contributes exactly one edge per locked account.
    static func flow(_ accounts: [(address: String, moments: [VibenetKeyMoment], locked: Bool)])
        -> Flow? {
        var edges: [Edge] = []
        var addresses: [String] = []
        var totals: [Kind: Int] = [:]

        for account in accounts {
            let authorized = account.moments.filter(\.authorized).count
            let revoked = account.moments.filter { !$0.authorized }.count
            let locked = account.locked ? 1 : 0
            guard authorized + revoked + locked > 0 else { continue }
            addresses.append(account.address)
            for (kind, n) in [(Kind.authorized, authorized),
                              (Kind.revoked, revoked),
                              (Kind.locked, locked)] where n > 0 {
                edges.append(Edge(kind: kind, address: account.address, count: n))
                totals[kind, default: 0] += n
            }
        }
        guard !edges.isEmpty else { return nil }
        return Flow(edges: edges.sorted { $0.kind == $1.kind ? $0.address < $1.address : $0.kind < $1.kind },
                    addresses: addresses,
                    totals: totals,
                    total: totals.values.reduce(0, +))
    }

    /// "10 changes" — the headline. A count of EVENTS, which is the one thing
    /// this card is counting; it never says "10 keys", because a key granted
    /// and later revoked is two changes and one key.
    static func headline(_ flow: Flow) -> String {
        flow.total == 1
            ? String(localized: "1 change")
            : String(localized: "\(flow.total) changes")
    }

    /// The drawing as one sentence (§299) — kinds in their declared order,
    /// each naming its accounts, because the ORDER is the claim.
    static func spoken(_ flow: Flow) -> String {
        guard !flow.isEmpty else { return String(localized: "Nothing has changed.") }
        let parts = Kind.allCases.compactMap { kind -> String? in
            let n = flow.total(kind)
            guard n > 0 else { return nil }
            return "\(kind.label): \(n)"
        }
        return String(localized: "Where the changes landed. \(parts.joined(separator: "; ")).")
    }
}
