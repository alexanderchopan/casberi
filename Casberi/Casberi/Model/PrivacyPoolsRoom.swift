import Foundation

/// PRIVACY POOLS' VOCABULARY: the refs its rows land under, the state a
/// deposit wears, and the one rounding its set size takes.
///
/// This was the Privacy Pools room's head (prd §349, §397, §486): the split
/// bar, the holdings line, the cover line and their words. The head is
/// deleted with the pick that drew it (prd §1738) — Privacy Pools is no pick
/// in the Wallet's menu, its money is Holdings' Private section and a deposit
/// that needs you is Needs you's. What stays is what the bridge, Needs you
/// and the demo read: one table of prefixes and tags, so the half that lands
/// a row and the half that reads it cannot spell them differently. That drift
/// shipped once: §311's `retag` looked up `privacypools:deposit:` while
/// deposits land under `privacypools:dep:`, so no tag ever moved and every
/// deposit read `Pending` for life.
///
/// Foundation-only by design so `scripts/wallet-rooms-selftest.sh` can compile
/// it WHOLE and unmodified.
enum PrivacyPoolsRoom {

    /// Where a deposit stands with the screener.
    ///
    /// The raw values ARE the tag strings `PrivacyPoolsBridge.retag` writes.
    enum State: String, Equatable, CaseIterable {
        /// The ASP has not ruled yet. Also the state a deposit lands in.
        case pending      = "Pending"
        /// Approved — the deposit is in the withdrawal tree and can be spent
        /// privately.
        case cleared      = "Cleared"
        /// Refused. The money is not lost; it has to be reclaimed to the
        /// original depositor instead of withdrawn privately.
        case declined     = "Declined"
        /// 0xBow wants proof of innocence before it can rule. The one state
        /// that waits on the person (`WalletNeedsYou`).
        case needsProof   = "Needs proof"
        /// Taken back out to the original depositor (2026-08-17) — the only
        /// state that means the money is no longer in a pool at all.
        case reclaimed    = "Reclaimed"
    }

    /// The tag vocabulary, as strings — the set `retag` strips before writing a
    /// new state, so a row always carries exactly one.
    static let states: [String] = State.allCases.map(\.rawValue)

    /// The `sourceRef` prefixes `PrivacyPoolsBridge` lands: a deposit, the
    /// ragequit that takes one back out, and the alert about one.
    static let depositPrefix   = "privacypools:dep:"
    static let reclaimedPrefix = "privacypools:ragequit:"
    static let statusPrefix    = "privacypools:status:"

    /// The deposit's ASP label, off a deposit ref, its status alert, or its
    /// ragequit — `PrivacyPoolsBridge` lands all three under the SAME label
    /// suffix, which is what joins a ragequit to the deposit it undid. Nil for
    /// a ref shape no prefix names.
    static func label(ref: String?) -> String? {
        guard let ref else { return nil }
        for prefix in [depositPrefix, statusPrefix, reclaimedPrefix]
        where ref.hasPrefix(prefix) {
            return String(ref.dropFirst(prefix.count))
        }
        return nil
    }

    /// The one state tag on a row, or nil.
    ///
    /// Nil is a real answer, never defaulted to `.pending`: a deposit landed
    /// before §311 carries no state tag at all, and calling it pending would
    /// report a deposit that cleared months ago as still waiting.
    static func state(tags: [String]) -> State? {
        for tag in tags {
            if let found = State(rawValue: tag) { return found }
        }
        return nil
    }

    /// "3,900" from 3,947, "12" from 12 — two significant figures, grouped.
    ///
    /// The exact count is noise and the ORDER OF MAGNITUDE is the privacy
    /// fact. `PrivacyPoolsBridge` calls this for the per-deposit sentence it
    /// stores on `enrichedText` (prd §228).
    static func roundedSet(_ n: Int) -> String {
        guard n >= 100 else { return "\(n)" }
        let digits = String(n).count
        let unit = Int(pow(10.0, Double(digits - 2)))
        let rounded = (n / unit) * unit
        return setCount.string(from: NSNumber(value: rounded)) ?? "\(rounded)"
    }

    /// Its own formatter rather than `DSCount.grouped`: this file is compiled
    /// Foundation-only by `wallet-rooms-selftest.sh`, and a `Design/`
    /// dependency breaks that harness.
    private static let setCount: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f
    }()
}
