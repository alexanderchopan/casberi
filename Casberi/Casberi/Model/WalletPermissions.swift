import Foundation

/// WHO CAN ACT FOR YOU, COUNTED BY WHAT THEY CAN DO (2026-08-26, prd §490).
///
/// The `Permissions` scope's lead drawing. Foundation-only BY DESIGN so
/// `scripts/wallet-permissions-selftest.sh` can compile it WHOLE and
/// unmodified — every read, every view and the mapping from the two source
/// types live elsewhere; this file is the arithmetic those depend on.
///
/// ## Why rungs and not a ranked list of dollars
///
/// §292 already ranks token approvals by `min(allowance, balance) × price`,
/// and that ranking is right for what it covers. It cannot cover this scope,
/// for two reasons that are properties of the data rather than of the design:
///
/// - **A whole class of holder has NO AMOUNT AT ALL.** A Safe module moves
///   funds with no signature, an EIP-7702 delegate runs as your wallet, an
///   Altana root credential signs as your wallet, and an operator grant
///   (`setApprovalForAll`) manages a whole collection this app prices at
///   nothing. None of them has a dollar figure, so a money-ranked card either
///   omits them — which hides the most dangerous things in the scope — or
///   sorts them as zero, which puts them last. §292 states that trap in its
///   own words and solves it with a separate line; at four kinds of holder a
///   line is no longer enough.
/// - **A COUNT of grants was already refused and still is.** §292 opens on
///   exactly that: *"a count can't, because approvals aren't equal"*. What is
///   counted here is not grants, it is CAPABILITY — the rungs are fixed and
///   ordered, and a rung's number says how many things have that power. Ten
///   grants collapse into the same four rows; forty do too.
///
/// ## The order, which is the whole claim
///
/// By REACH, unbounded first, and it is a statement about scope rather than a
/// grade: something that acts as your wallet reaches everything, a cap reaches
/// a stated amount. The one non-obvious rung is `scopedSigner`, which sits
/// ABOVE a capped grant even though a session key sounds smaller — §293's
/// ceiling rule, which this scope inherits: the registry publishes no way to
/// read a session key's scope, and a bound we cannot read must never be drawn
/// as a small one.
enum WalletPermissions {

    /// What one holder can do. The rungs, in their drawn order.
    ///
    /// A closed set on purpose: a new kind of holder must be given a rung and
    /// a position, not appended to a list where it would land last by
    /// accident. Swift's exhaustive switch is what forces that.
    enum Power: Int, CaseIterable, Comparable, Sendable {
        /// An EIP-7702 delegate, or an Altana root credential — it can do
        /// whatever you can.
        case actsAsWallet = 0
        /// A Safe module. Bounded to one Safe, unbounded inside it.
        case movesWithoutSignature = 1
        /// An unlimited ERC-20 allowance — all of one token.
        case unlimitedToken = 2
        /// `setApprovalForAll` — all of one collection, at no stated price.
        case wholeCollection = 3
        /// A session key. Scoped, and the scope is unreadable — see the type
        /// doc for why that puts it here rather than last.
        case scopedSigner = 4
        /// A capped allowance. The only rung whose limit is a number.
        case cappedAmount = 5

        static func < (a: Power, b: Power) -> Bool { a.rawValue < b.rawValue }

        /// The rung's sentence, always in the plural-agnostic form the view
        /// completes with a count ("2 can move a token with no limit").
        var phrase: String {
            switch self {
            case .actsAsWallet:          String(localized: "can act as your wallet")
            case .movesWithoutSignature: String(localized: "can spend without a signature")
            case .unlimitedToken:        String(localized: "can move a token with no limit")
            case .wholeCollection:       String(localized: "can manage a whole collection")
            case .scopedSigner:          String(localized: "can sign as your wallet")
            case .cappedAmount:          String(localized: "can move up to a cap")
            }
        }

        /// Whether this rung is one the room should draw in its alarm colour.
        ///
        /// The line is UNBOUNDEDNESS, never severity-as-opinion: the four
        /// above it reach everything of some kind, and the two below reach a
        /// stated amount or an unknown one. A capped grant you made on purpose
        /// is not an alarm (§292's own note about spelling the minus rather
        /// than colouring it, applied one scope over).
        var isUnbounded: Bool { self <= .wholeCollection }

        /// Whether a dollar figure could EXIST for this rung at all.
        ///
        /// False for the three whose holders have no amount by nature — a
        /// Safe module, a delegate and an operator grant are not unpriced,
        /// they are unpriceable — which is what lets the view stay silent
        /// there instead of printing "no amount to state" on rows where it
        /// reads as an apology for a fact. Where an amount SHOULD exist and
        /// didn't resolve, the view still says so: that one is a miss, and
        /// hiding it would let a failed price read look like a small grant.
        var canCarryAmount: Bool {
            self == .unlimitedToken || self == .cappedAmount
        }
    }

    /// One thing that can act on your behalf, flattened out of the two source
    /// types so this file needs neither.
    ///
    /// `usd` is Optional and nil means WE DON'T KNOW OR THERE IS NO AMOUNT —
    /// never zero. §292 makes the same distinction for the same reason: a
    /// zero sorts last and reads as harmless, and the holders with no amount
    /// are the ones at the top of this list.
    struct Holder: Equatable, Sendable {
        let power: Power
        /// What to call it. Already resolved by the caller — a wrong name on
        /// a permissions notice sends someone to revoke the wrong thing
        /// (§239's rule, which `Party.displayName` already keeps).
        let name: String
        let usd: Double?
        /// One short fact the rung can carry when it has room ("installed
        /// 14 Mar"). nil is ordinary.
        let note: String?

        init(power: Power, name: String, usd: Double? = nil, note: String? = nil) {
            self.power = power
            self.name = name
            self.usd = usd
            self.note = note
        }
    }

    /// One drawn row.
    struct Rung: Equatable, Identifiable, Sendable {
        let power: Power
        let count: Int
        /// Up to `namesShown`, in the order the caller supplied them. Never
        /// re-sorted here: the caller's order is the ranked one (§292 ranks
        /// its grants by dollars at stake), and re-sorting by name would
        /// throw that away for tidiness.
        let names: [String]
        /// The rung's total, or nil when the rung has no amount to state.
        ///
        /// A rung is priced only when EVERY holder in it carries a figure.
        /// A partial sum is the failure Railgun's all-or-nothing rule exists
        /// to prevent — a total quietly missing one grant is more wrong than
        /// no total, because it looks complete.
        let usd: Double?
        /// True when at least one holder in the rung had no figure, so the
        /// view can say the count is a floor rather than implying the rung
        /// is fully priced.
        let hasUnpriced: Bool
        let note: String?

        var id: Int { power.rawValue }
    }

    /// How many holders a rung names before it stops naming.
    ///
    /// Two, measured against the slot: a rung is one line of names under one
    /// line of sentence, and a third name pushes the row to two lines, which
    /// at four rungs costs the drawing its fourth. The remainder is not
    /// hidden — the list below carries every holder.
    static let namesShown = 2

    /// How many rungs the drawing shows. Four, for the same 210pt box: the
    /// fifth and sixth fold into a count so the shape never grows.
    static let rungsShown = 4

    /// The rungs, in `Power` order, skipping any with nothing in them.
    ///
    /// **The order is the type's, never the data's** — that is what makes the
    /// drawing stable. A room whose rows reshuffle between opens over
    /// identical data reads as broken (§292's total-order rule), and here the
    /// stability is stronger than sorted: the rungs are the SAME four rows on
    /// every wallet that has them, so the shape is learnable.
    static func rungs(_ holders: [Holder]) -> [Rung] {
        var byPower: [Power: [Holder]] = [:]
        for holder in holders {
            byPower[holder.power, default: []].append(holder)
        }
        return Power.allCases.compactMap { power in
            guard let group = byPower[power], !group.isEmpty else { return nil }
            let priced = group.compactMap(\.usd)
            let complete = priced.count == group.count
            return Rung(power: power,
                        count: group.count,
                        names: group.prefix(namesShown).map(\.name),
                        usd: complete && !priced.isEmpty ? priced.reduce(0, +) : nil,
                        hasUnpriced: priced.count < group.count,
                        note: group.count == 1 ? group[0].note : nil)
        }
    }

    /// Everything that can be priced, summed — the eyebrow's figure.
    ///
    /// Deliberately across ALL rungs rather than the drawn ones: the number
    /// answers "how much of my money is reachable", which does not change
    /// because a rung folded out of view.
    ///
    /// nil when nothing carries a figure at all, which is a real state — a
    /// wallet whose only holder is a Safe module has genuine exposure and no
    /// dollars to put on it, and printing $0 there would be the most
    /// misleading thing on the card.
    static func totalUSD(_ holders: [Holder]) -> Double? {
        let priced = holders.compactMap(\.usd).filter { $0.isFinite && $0 > 0 }
        return priced.isEmpty ? nil : priced.reduce(0, +)
    }

    /// Whether anything here reaches without a bound — what the eyebrow
    /// colours on, and the one judgement the card makes.
    static func hasUnbounded(_ holders: [Holder]) -> Bool {
        holders.contains { $0.power.isUnbounded }
    }

    /// "and 2 more" — what the folded rungs come to, or nil when nothing
    /// folded. A COUNT of holders, not of rungs: "2 more" meaning two more
    /// rows would be a fact about our layout rather than about the wallet.
    static func foldedCount(_ rungs: [Rung]) -> Int? {
        guard rungs.count > rungsShown else { return nil }
        let folded = rungs.dropFirst(rungsShown).reduce(0) { $0 + $1.count }
        return folded > 0 ? folded : nil
    }
}
