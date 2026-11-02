import Foundation

/// **NEEDS YOU'S BOX SAYS WHAT IS HELD UP (prd §1669, retiring "N waiting on
/// you").** The count repeated the list under it, so the box states the money
/// the asks hold: dollars where a price exists, else the quantity itself
/// ("0.001 ETH" — test money never takes a price, §83), over one bar split by
/// ask and a line per ask. An ask with no money in it (a key to back up, a
/// signature whose transaction we do not read yet) is never valued: it is
/// COUNTED in the line under the figure. No money at all and the box keeps the
/// count.
///
/// Foundation-only; `needs-you-held-selftest.sh` compiles it whole.
enum NeedsYouHeld {
    struct Part: Equatable, Identifiable {
        let id: String
        /// What it is waiting on, never the amount ("Waiting for approval").
        let label: String
        /// The quantity, as the row spells it ("0.001 ETH").
        let figure: String
        /// Nil for test money or a token with no price: the figure stands.
        let usd: Double?
        let since: Date
        /// Refused rather than waiting: the bar and dot take the alarm ink.
        let refused: Bool
    }

    struct Reading: Equatable {
        /// Priced first, largest first; then the rest, oldest first.
        let parts: [Part]
        /// Asks the box counts and does not value.
        let others: Int

        /// Dollars when anything is priced (the unpriced stand in the
        /// legend); else one figure, or two joined; else nil, and the box
        /// keeps the count.
        func headline(money: (Double) -> String) -> String? {
            let priced = parts.compactMap(\.usd)
            if !priced.isEmpty { return money(priced.reduce(0, +)) }
            switch parts.count {
            case 1: return parts[0].figure
            case 2: return parts.map(\.figure).joined(separator: " + ")
            default: return nil
            }
        }

        var oldest: Date? { parts.map(\.since).min() }

        /// Each part's share of the bar: by dollars when every part is
        /// priced, in equal parts when none is. A mix gives the unpriced the
        /// smallest priced share, so it shows and never claims a value.
        var weights: [Double] {
            let priced = parts.compactMap(\.usd)
            guard !priced.isEmpty else { return parts.map { _ in 1 } }
            let floor = max(priced.min() ?? 1, 0.000_001)
            return parts.map { $0.usd ?? floor }
        }
    }

    static func read(_ parts: [Part], others: Int) -> Reading {
        let priced = parts.filter { $0.usd != nil }.sorted { ($0.usd ?? 0) > ($1.usd ?? 0) }
        let rest = parts.filter { $0.usd == nil }.sorted { $0.since < $1.since }
        return Reading(parts: priced + rest, others: max(others, 0))
    }
}
