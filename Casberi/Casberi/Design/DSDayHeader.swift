import SwiftUI

/// **A DAY OVER A DEVNET'S MOVES (prd §950).** The feed's own day divider —
/// the day in the brand ink (§740), in `FeedScreen.dayWord`'s words — for a
/// list that is not a `List` of its own (a devnet card's rows sit in a
/// `VStack`), so the Wallet's Activity (§942) and every devnet's read by the
/// same days. The row under it carries no age: the day says when.
struct DSDayHeader: View {
    let word: String
    var first = false

    var body: some View {
        Text(word)
            .dsText(.heading24)
            .foregroundStyle(DS.brandInk)
            .frame(maxWidth: .infinity, alignment: .leading)
            // The list's rows stand in the Wallet's row column; the day is
            // text, so it stands on the tiles' edge instead.
            .padding(.leading, DSRoomChassis.inset - DSRoomChassis.rowInset(forMark: DS.Face.list))
            .padding(.top, first ? DS.Space.s1 : DS.Space.s6)
            .padding(.bottom, DS.Space.s1)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Items in the order given, cut into runs of one day each — a day recurs
/// only if the caller's order does. An undated item joins "Earlier" rather
/// than being dated now.
enum DayRuns {
    struct Run<Item>: Identifiable {
        let id: String
        let items: [Item]
    }

    static func runs<Item>(_ items: [Item], date: (Item) -> Date?) -> [Run<Item>] {
        var out: [Run<Item>] = []
        var label: String?
        var current: [Item] = []
        for item in items {
            let word = date(item).map(FeedScreen.dayWord) ?? String(localized: "Earlier")
            if word != label, let open = label {
                out.append(Run(id: "\(open)#\(out.count)", items: current))
                current = []
            }
            label = word
            current.append(item)
        }
        if let open = label { out.append(Run(id: "\(open)#\(out.count)", items: current)) }
        return out
    }

    /// The day word a run's id carries.
    static func word<Item>(_ run: Run<Item>) -> String {
        String(run.id.split(separator: "#").first ?? "")
    }
}
