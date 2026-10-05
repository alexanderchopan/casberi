import Foundation

/// WHAT COMING UP ADDS UP TO (prd §1078, user: "do all the changes you
/// suggested"). Coming up's box led with the next item's title; it now says
/// what is due in the next thirty days and how many things wait on you.
///
/// **Only a bill is "due".** Coming up also holds money ARRIVING (a World ID
/// grant, a Peer sale settling) and deadlines with no money (an ENS expiry, a
/// card offer), so the figure adds only the sources whose dated rows are
/// payments you make: Apple Wallet's card payments. Rocket Money's next
/// charges moved to the Subscriptions tile with prd §1105 (they repeat), so
/// Coming up holds what happens once. A bill with no amount (Apple's payment row carries a date, not a
/// sum) is NAMED, never counted as zero. A currency with no rate is left out
/// and named the same way, as the Wallet total does (§1048).
///
/// Pure: `CasberiTests/WalletDueTests` composes it.
enum WalletDue {

    static let windowDays = 30

    /// Sources whose dated rows are payments the person makes.
    static let billSources: Set<String> = [AppleWalletBridge.sourceName]

    struct Bill: Equatable {
        let title: String
        let source: String
        let amount: Double?
        let currency: String?
        let due: Date
    }

    struct Reading: Equatable {
        /// Dollars due inside the window, over the bills with a usable amount.
        let total: Double
        /// How many bills `total` adds up.
        let counted: Int
        /// Bills inside the window the total could not count, by title.
        let uncounted: [String]
        /// Undated items that wait on the person now (a Safe signature, a
        /// deposit needing proof).
        let waiting: Int

        var hasFigure: Bool { counted > 0 }
    }

    static func compose(bills: [Bill], waiting: Int, rates: [String: Double],
                        now: Date = .now) -> Reading {
        let end = now.addingTimeInterval(TimeInterval(windowDays) * 86_400)
        var total = 0.0, counted = 0
        var uncounted: [String] = []
        for bill in bills.sorted(by: { $0.due < $1.due })
        where billSources.contains(bill.source) && bill.due > now && bill.due <= end {
            if let amount = bill.amount, let code = bill.currency,
               let usd = WalletCash.usd(amount, code, rates: rates) {
                total += usd
                counted += 1
            } else {
                uncounted.append(bill.title)
            }
        }
        return Reading(total: total, counted: counted, uncounted: uncounted, waiting: waiting)
    }

    /// "3 need you now" — the waiting count, in words.
    static func waitingLine(_ count: Int) -> String? {
        guard count > 0 else { return nil }
        return count == 1 ? String(localized: "1 needs you now")
                          : String(localized: "\(count) need you now")
    }

    /// "Not counted: Apple Card payment due" — the bills the total names
    /// instead of counting.
    static func uncountedLine(_ titles: [String]) -> String? {
        guard !titles.isEmpty else { return nil }
        let unique = titles.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        return String(localized: "Not counted: \(ListFormatter.localizedString(byJoining: unique))")
    }
}
