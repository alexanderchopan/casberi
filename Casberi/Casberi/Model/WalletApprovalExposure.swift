import Foundation

/// WHAT SOMEONE ELSE CAN STILL MOVE (2026-08-03, prd §292).
///
/// The room has listed approvals since §196 — as rows, and as a tray notice
/// counting them. Neither answers the only question an approval actually
/// raises: **which one do I revoke first?** A count can't, because approvals
/// aren't equal; an unlimited USDC grant to a contract nobody can name is not
/// the same object as a capped grant to Aave made this morning, and a list
/// sorted by arrival puts them in whatever order the chain happened to emit.
///
/// So this ranks them by the one thing that orders them honestly: the value of
/// your own tokens each spender can move right now.
///
/// ## The number, and why it's this number
///
/// `min(allowance, balance) × price`, which in practice is two cases:
///
/// - **An unlimited grant reaches your whole balance of that token.** Not the
///   allowance — the allowance is a number past any real supply and pricing it
///   would print a figure in the trillions. What's at stake is what's there.
/// - **A capped grant reaches the smaller of the cap and the balance.** A
///   500 USDC cap on a wallet holding $6,200 exposes $500; the same cap on a
///   wallet holding $80 exposes $80.
///
/// It follows that the number MOVES with the balance, and that's correct
/// rather than unfortunate: spend the token and your exposure really does fall
/// to nothing while the grant stays live. The card says "can move", present
/// tense, for exactly this reason — it is not a record of what you approved,
/// it's a reading of what that approval currently reaches.
///
/// ## What is deliberately not counted
///
/// An operator grant (`setApprovalForAll` — "OpenSea can manage all your
/// Doodles") has no amount and this app prices no NFT, so it CANNOT join the
/// total. It is stated in its own line instead of being counted as zero,
/// because zero would sort the most dangerous grant in the list last. The same
/// holds for a token the holdings read didn't price, and for one it couldn't
/// reach at all: `nil` here means "we don't know", never "nothing".
///
/// That is `WalletFlow.minPricedShare`'s reasoning in a second place — the
/// flow band declines to draw rather than paint a confident picture of a tenth
/// of the window. Here the card still draws, because a partial exposure list
/// is still correctly ordered; what it must never do is silently drop the
/// unpriceable rows out of the story.
///
/// ## Foundation-only, on purpose
///
/// Every failure mode here is a WRONG NUMBER that renders perfectly — a capped
/// grant priced as if it were unlimited looks exactly like a large approval.
/// So this file holds no `Thing`, no book, and no network: it is compiled AS
/// SHIPPED by `scripts/wallet-viz-selftest.sh` and fed cases whose answers are
/// known. The reading half lives in `WalletApprovalExposureSource.swift`,
/// exactly as `WalletRiskScale` and `WalletRiskScaleSource` are split.
struct WalletApprovalExposure: Equatable, Sendable {

    /// One live grant, as the card states it.
    struct Grant: Equatable, Sendable, Identifiable {
        /// The approval thing this came from — the door to its prepare card.
        let thingID: UUID
        /// "Uniswap", or the short hex when nothing can name it. Never
        /// invented: `WalletApprovals.title` has always fallen back to hex
        /// rather than guess, and a wrong name on a revoke prompt sends you to
        /// revoke the wrong thing.
        let spender: String
        /// The spender's RAW address — what `spender` is a display of
        /// (2026-08-13, prd §372). Carried so a grant can be joined to the
        /// address book, which is what lets someone's own card say what that
        /// address can move right now.
        ///
        /// Raw, and NOT `AddressBook.key`, on purpose: this file is
        /// Foundation-only so the harness can compile it as shipped (see the
        /// type doc), and folding an address to its identity form is the
        /// book's own rule. Callers compare through `AddressBook.key`; keeping
        /// a second folding rule here is exactly the two-spellings-of-one-rule
        /// drift `WalletSafety.isFuzzyMatch` was collapsed to avoid.
        let spenderAddress: String
        /// Whether `spender` is a real name or a short hex — "a contract we
        /// can't name" is itself information.
        let named: Bool
        /// "USDC", or the token's short hex when its `symbol()` didn't answer.
        let symbol: String
        /// An `ApprovalForAll` operator grant — no amount, never priced.
        let forAll: Bool
        let unlimited: Bool
        /// What the spender can move right now, in dollars. nil when it can't
        /// be known (see the type's doc) — never 0 standing in for unknown.
        let usd: Double?
        /// The cap in token units, for a limited grant whose decimals we read.
        let capTokens: Double?
        /// When the grant was made — `Thing.grantedAt`, set only from a real
        /// block timestamp (§253), so nil stays silent rather than dating a
        /// years-old grant to today.
        let grantedAt: Date?

        var id: String { thingID.uuidString }

        /// "Unlimited USDC" / "Capped at 500 USDC" / "Manages all Doodles".
        var stateLine: String {
            if forAll { return String(localized: "Manages all \(symbol)") }
            if unlimited { return String(localized: "Unlimited \(symbol)") }
            guard let capTokens else { return String(localized: "Limited \(symbol)") }
            return String(localized: "Capped at \(WalletApprovalExposure.number(capTokens)) \(symbol)")
        }
    }

    /// Grants with a known dollar figure, largest first.
    var priced: [Grant] = []
    /// Grants that exist and can't be priced — stated, never counted.
    var unpriced: [Grant] = []

    var isEmpty: Bool { priced.isEmpty && unpriced.isEmpty }

    /// The sum of what's reachable. Only ever the priced rows: adding a zero
    /// for each unpriceable grant would understate the total while looking
    /// complete, which is worse than a total that says what it covers.
    var total: Double { priced.compactMap(\.usd).reduce(0, +) }

    /// Every grant, priced first — the card's row order.
    var all: [Grant] { priced + unpriced }

    /// The count behind the headline — distinct spender identities among the
    /// priced rows. SPENDERS, not grants: one spender holding three approvals
    /// is one party who can move your money, and saying "3" would inflate the
    /// finding by counting the same trust three times.
    var spenderCount: Int { Set(priced.map(\.spender)).count }

    /// The button's target: the OLDEST unlimited grant, which is the one a
    /// revoke list exists for — a years-old blanket allowance to a contract
    /// you've forgotten. Falls back to the oldest grant of any kind, then to
    /// the first row, so the button is never dead while rows exist.
    ///
    /// Deliberately NOT the biggest number: the top row is already the biggest
    /// number, and a button pointing at what the eye is on says nothing.
    var oldestWorthReviewing: Grant? {
        let dated = all.filter { $0.grantedAt != nil }
        if let g = oldest(dated.filter(\.unlimited)) { return g }
        if let g = oldest(dated) { return g }
        return all.first
    }

    private func oldest(_ grants: [Grant]) -> Grant? {
        grants.min { ($0.grantedAt ?? .distantFuture) < ($1.grantedAt ?? .distantFuture) }
    }

    /// The footnote naming what the total leaves out. nil when nothing is
    /// unpriced, so the card grows the line only when it owes one.
    var unpricedNote: String? {
        guard !unpriced.isEmpty else { return nil }
        if unpriced.count == 1, let g = unpriced.first {
            return g.forAll
                ? String(localized: "\(g.spender) can move all your \(g.symbol). Not priced, so not counted.")
                : String(localized: "\(g.spender)'s \(g.symbol) grant couldn't be priced, so it isn't counted.")
        }
        return String(localized: "\(unpriced.count) more grants couldn't be priced, so they aren't counted.")
    }

    // MARK: - The arithmetic

    /// `min(allowance, balance) × price`, expressed against a holding already
    /// known in dollars.
    ///
    /// - `allowanceRaw`: the live allowance in the token's raw units.
    /// - `decimals`: the token's decimals. nil is not fatal for an unlimited
    ///   grant (the answer is the whole balance either way) and IS fatal for a
    ///   capped one — the share can't be computed, so it returns nil.
    /// - `heldUSD` / `heldTokens`: what the wallet holds. `heldTokens` nil
    ///   blocks only the capped case, for the same reason.
    /// - `unlimitedAt`: where "unlimited" starts, PASSED IN rather than
    ///   redeclared — it is owned by `WalletApprovals`, which uses the same
    ///   number to decide whether the row's own title says "unlimited". A
    ///   local copy could drift and make the card price a grant the row calls
    ///   unlimited as if it were capped (`WalletRiskScale`'s threshold rule,
    ///   and `DeFiRisk`'s lesson before it).
    ///
    /// Returns nil for "can't be known". Returns 0 only when the wallet
    /// genuinely holds nothing priced — a real and useful answer: a live
    /// unlimited grant on an emptied token reaches nothing today.
    static func atStake(allowanceRaw: Double, decimals: Int?,
                        heldUSD: Double?, heldTokens: Double?,
                        unlimitedAt: Double) -> Double? {
        guard let heldUSD, heldUSD.isFinite, heldUSD >= 0 else { return nil }
        // An untrusted allowance can arrive as inf/NaN off a malformed or
        // overlong reply — `holdingFloor`'s `.isFinite` lesson, one file over.
        // It resolves to nil ("we don't know"), NOT to 0: a value we couldn't
        // parse is not evidence that a live grant reaches nothing, and 0 would
        // print exactly that reassurance on the row that earned it least. A
        // negative is the same class — a uint256 cannot be negative, so it can
        // only be a parse failure.
        //
        // Caught by this harness on the day it was written: the first cut
        // folded both cases in with the genuine zero below and answered "$0"
        // for a grant it had failed to read.
        guard allowanceRaw.isFinite, allowanceRaw >= 0 else { return nil }
        // A real zero, though, is a real answer: the grant was revoked or
        // spent, and it reaches nothing.
        guard allowanceRaw > 0 else { return 0 }
        if allowanceRaw >= unlimitedAt { return heldUSD }
        guard let decimals, decimals >= 0, decimals <= 36,
              let heldTokens, heldTokens.isFinite, heldTokens > 0 else { return nil }
        let cap = allowanceRaw / pow(10, Double(decimals))
        guard cap.isFinite else { return nil }
        let usd = heldUSD * min(1, cap / heldTokens)
        return usd.isFinite ? usd : nil
    }

    /// The headline, as one sentence.
    static func headline(spenders: Int, total: Double) -> String {
        let amount = money(total)
        return spenders == 1
            ? String(localized: "1 spender can move \(amount)")
            : String(localized: "\(spenders) spenders can move \(amount)")
    }

    /// Dollars, EXACT — "$8,924", not the room's usual `TokenStats.compact`
    /// "$9K" (2026-08-03).
    ///
    /// The room compacts because a treemap cell and a deposit line are
    /// magnitudes you compare by area. This card's entire job is ORDERING
    /// numbers against each other, and compact rounds $6,200 and $2,140 to
    /// "$6K" and "$2K" — still ordered, but it throws away the resolution the
    /// ranking is made of. A card that ranks should show what it ranked on.
    static func money(_ v: Double) -> String {
        guard v.isFinite else { return "$0" }
        return "$" + number(v.rounded())
    }

    /// Grouped digits. Deliberately NOT `WalletIngest.format`: this file is
    /// Foundation-only so the harness can compile it as shipped (see the type
    /// doc), and that formatter shapes TOKEN amounts — sub-unit precision for
    /// fractions of an ETH — where this shapes whole dollars and a cap. Same
    /// grouping, different job, and the alternative is dragging the wallet
    /// stack into a file whose whole value is that it has no dependencies.
    static func number(_ v: Double) -> String {
        guard v.isFinite else { return "0" }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = abs(v) >= 1000 ? 0 : (abs(v) >= 1 ? 2 : 4)
        return f.string(from: v as NSNumber) ?? String(format: "%.0f", v)
    }
}
