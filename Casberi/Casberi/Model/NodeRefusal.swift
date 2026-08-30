import Foundation

/// WHAT A NODE SAID WHEN IT SAID NO (prd §530, 2026-08-30).
///
/// **Chain-neutral on purpose, and that is the point of it being its own
/// file.** Both devnets in this app broadcast, both threw the node's
/// `error.message` away, and both reported the identical dead sentence — "the
/// node refused the transaction" — for a stale sequence, an unfunded account,
/// a fee under the floor and a host that never answered. Fixing that twice
/// with two copies of this table is the §418 duplicate-parser mistake, and it
/// ends the same way: two chains eventually explaining the same refusal
/// differently. One table, both callers.
///
/// Foundation-only BY DESIGN so `scripts/hegota-tx-selftest.sh` compiles it
/// WHOLE. Neither devnet can be reached from a harness, so the classification
/// is the only part of either broadcast that can be proven at all.

/// A node's refusal, turned into something a person can act on.
///
/// **It never invents a reason and never hides one.** Where the message
/// matches a cause this app can explain, the explanation is given AND the
/// node's own words are kept — a devnet's phrasing is not stable enough to
/// paraphrase away, and the raw text is what makes a report actionable. Where
/// it matches nothing, the node's words stand alone; where there are no words
/// at all, it says that rather than asserting a refusal that may have been a
/// dead host.
enum NodeRefusal {

    /// Nil `raw` means the node said nothing we could read — which includes
    /// no node answering at all.
    static func sentence(_ raw: String?) -> String {
        let said = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !said.isEmpty else {
            return String(localized: "no answer from the chain")
        }
        guard let known = cause(said) else { return said }
        return "\(known) (\(said))"
    }

    /// The causes worth naming, matched on the substrings every Ethereum-shaped
    /// node uses for them. **Lowercased once**, because a node's casing is not
    /// a contract; matched as substrings because the surrounding phrasing is
    /// not one either.
    ///
    /// `nonce too low` leads: it is the one this app can produce by itself —
    /// two sends composed against one read sequence — and the only one whose
    /// remedy is simply to try again.
    static func cause(_ raw: String) -> String? {
        let s = raw.lowercased()
        if s.contains("nonce too low") || s.contains("nonce is too low") {
            return String(localized: "the sequence had already moved on")
        }
        if s.contains("already known") || s.contains("already imported") {
            return String(localized: "the chain already has this one")
        }
        if s.contains("insufficient funds") {
            return String(localized: "this account can't cover it")
        }
        if s.contains("underpriced") || s.contains("fee too low") || s.contains("gas price") {
            return String(localized: "the fee was under what the chain is taking")
        }
        if s.contains("intrinsic gas") || s.contains("gas limit") {
            return String(localized: "the gas allowance was too small")
        }
        if s.contains("transaction type") || s.contains("unsupported") || s.contains("invalid type") {
            return String(localized: "this node doesn't take this kind of transaction")
        }
        if s.contains("signature") || s.contains("invalid sender") || s.contains("recover") {
            return String(localized: "the signature didn't check out")
        }
        return nil
    }
}
