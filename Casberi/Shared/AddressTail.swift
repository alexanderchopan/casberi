import Foundation

/// A shortened address is its TAIL: `...e07a`, three ASCII dots and the last
/// four characters (user rule, 2026-10-26, prd §1553). Never cut at both ends
/// (`0x4b19…e07a` is banned), and never the `…` character.
///
/// The one shortener for every id the app draws short: EVM, Aztec, Solana,
/// Bitcoin and Logos addresses, Safes and contracts, transaction hashes. A
/// file that needs a short form calls this; `address-tail-audit.py` fails a
/// new head-and-tail shortener and a re-spelled tail anywhere else.
///
/// Display only. Nothing here touches what is stored, matched or sent, and a
/// name (the book's, ENS, "your account") still wins where a caller asks for
/// it first: this is the fallback half of `name ?? AddressTail.short(…)`.
enum AddressTail {
    /// The mark that says "this is a fragment".
    static let dots = "..."

    /// How many characters of the tail are shown.
    static let shown = 4

    /// `...e07a`. An id no longer than `wholeUpTo` is short enough to show
    /// whole, so it is returned unchanged.
    static func short(_ id: String, wholeUpTo: Int = 12) -> String {
        guard id.count > max(wholeUpTo, shown) else { return id }
        return dots + String(id.suffix(shown))
    }

    /// Does `text` READ as a shortened id rather than a name — this spelling,
    /// or the `…` one written before 2026-10-26 (placeholders stored in
    /// address books on people's devices keep it).
    static func isTail(_ text: String) -> Bool {
        text.hasPrefix(dots) || text.hasPrefix("…")
    }
}
