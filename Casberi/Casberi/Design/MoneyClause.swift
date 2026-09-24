import Foundation

/// A title's trailing money clause — "Ada Lovelace · $49.00" — split into the
/// title and the figure (prd §900).
///
/// Payment, sale and payout bridges title their rows "<who or what> · <amount>",
/// so a column of rows put the dollars at a different x on every line and a
/// day's money could not be scanned. §764 already rules that money trails the
/// title in `price17`; `BandRow` only did it for a directional transfer, which
/// carries its amount in its own field. This finds the same fact in the title.
///
/// Deliberately narrow, because a wrong split moves a word out of a title:
/// - the clause is the LAST `" · "` or `" — "` part, and the only thing in
///   it is a figure;
/// - a figure is exactly one currency symbol, leading or trailing, around
///   digits and separators — so "$ETH", "€100 in bitcoin" and
///   "$49.00 — evidence due Oct 2" all stay in their titles;
/// - something must stand before it, or the row would have no title.
///
/// Foundation only: `feed-grammar-selftest.sh` compiles it whole.
enum MoneyClause {
    static func split(_ title: String) -> (title: String, amount: String)? {
        // The later of the two separators titles use: " · " (Stripe, Polar,
        // Dodo) and " — " (Acorns' "Checking — $191.40"). Only the LAST part
        // is ever the clause, so "Dispute opened · $49.00 — evidence due"
        // ends in words and stays whole.
        let dot = title.range(of: " · ", options: .backwards)
        let dash = title.range(of: " — ", options: .backwards)
        let later = [dot, dash].compactMap { $0 }.max { $0.lowerBound < $1.lowerBound }
        guard let sep = later else { return nil }
        let head = title[..<sep.lowerBound].trimmingCharacters(in: .whitespaces)
        let tail = title[sep.upperBound...].trimmingCharacters(in: .whitespaces)
        guard !head.isEmpty, isFigure(tail) else { return nil }
        return (head, tail)
    }

    /// The title with its money clause removed — a fold's name, which never
    /// shows money: a figure beside "+3 more" reads as the total of all four.
    static func stripped(_ title: String) -> String {
        split(title)?.title ?? title
    }

    private static let symbols: Set<Character> = ["$", "€", "£", "¥", "₩", "₹", "₿"]
    private static let separators: Set<Character> = [",", ".", " ", "\u{00A0}", "\u{202F}"]

    static func isFigure(_ text: String) -> Bool {
        var s = Substring(text)
        if let f = s.first, "+-−".contains(f) { s = s.dropFirst() }
        let leads = s.first.map { symbols.contains($0) } ?? false
        let trails = s.last.map { symbols.contains($0) } ?? false
        guard leads != trails else { return false }
        let body = (leads ? s.dropFirst() : s.dropLast())
            .trimmingCharacters(in: CharacterSet(charactersIn: " \u{00A0}\u{202F}"))
        guard let first = body.first, first.isASCII, first.isNumber,
              let last = body.last, last.isASCII, last.isNumber else { return false }
        return body.allSatisfy { ($0.isASCII && $0.isNumber) || separators.contains($0) }
    }
}
