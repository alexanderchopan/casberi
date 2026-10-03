import Foundation

/// THE COMPANIES BEHIND EVERY APP, AS AN INDEX (prd §1082).
///
/// Markets' category tiles were packs: the catalogue's companies for one
/// category, A to Z, rows that opened nothing. They are now an index you
/// read and search, on the deck's own promise — "invest in your apps":
///
/// - **From your apps** leads: the companies behind the apps you connected,
///   each naming those apps ("Microsoft — GitHub, npm").
/// - **Everything else** follows, so the index still shows the companies
///   behind apps you have not connected.
/// - **Not traded** closes it, once, instead of "n/a" on every row.
///
/// Search runs over the same index: a company's name, its ticker, or the name
/// of an app it makes ("slack" finds Salesforce).
///
/// Foundation-only: `scripts/markets-selftest.sh` compiles it whole.
enum MarketsIndex {
    struct Entry: Equatable {
        let name: String
        /// The ticker it trades under, or nil when it is not traded.
        let ticker: String?
        /// The catalogue apps it makes, in catalogue order.
        let apps: [String]
    }

    struct Sections: Equatable {
        var yours: [Entry] = []
        var rest: [Entry] = []
        var untraded: [Entry] = []
    }

    /// Splits a category's companies (`connected` is the apps you connected,
    /// by catalogue name). Each section reads A to Z. A company you connected
    /// any app of is yours; a company that is not traded closes the list
    /// whether or not it is yours, because it has nothing to watch.
    static func sections(_ entries: [Entry], connected: Set<String>) -> Sections {
        var out = Sections()
        for entry in entries.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) {
            if entry.ticker == nil {
                out.untraded.append(entry)
            } else if entry.apps.contains(where: connected.contains) {
                out.yours.append(entry)
            } else {
                out.rest.append(entry)
            }
        }
        return out
    }

    /// The apps a company row names: yours first, then the rest, each in
    /// catalogue order.
    static func appsLine(_ entry: Entry, connected: Set<String>) -> [String] {
        entry.apps.filter(connected.contains) + entry.apps.filter { !connected.contains($0) }
    }

    /// Every category's companies as one index, each company once with all
    /// its apps — the All tile.
    static func merged(_ categories: [[Entry]]) -> [Entry] {
        var order: [String] = []
        var byName: [String: Entry] = [:]
        for entry in categories.joined() {
            if let seen = byName[entry.name] {
                let apps = seen.apps + entry.apps.filter { !seen.apps.contains($0) }
                byName[entry.name] = Entry(name: entry.name, ticker: seen.ticker ?? entry.ticker, apps: apps)
            } else {
                order.append(entry.name)
                byName[entry.name] = entry
            }
        }
        return order.compactMap { byName[$0] }
    }

    /// Whether a typed query finds this company: its name or ticker begins
    /// with it, a word of its name does, or an app it makes contains it.
    /// Under two characters nothing matches — a single letter is every row.
    static func matches(_ query: String, _ entry: Entry) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "$")).lowercased()
        guard q.count >= 2 else { return false }
        if let ticker = entry.ticker?.lowercased(), ticker.hasPrefix(q) { return true }
        let name = entry.name.lowercased()
        if name.hasPrefix(q) { return true }
        if name.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains(where: { $0.hasPrefix(q) }) {
            return true
        }
        return entry.apps.contains { $0.lowercased().contains(q) }
    }

    /// The index's answer to a query, the companies whose own name or ticker
    /// matched before the ones found through an app.
    static func search(_ query: String, in entries: [Entry]) -> [Entry] {
        let found = entries.filter { matches(query, $0) }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        func direct(_ e: Entry) -> Bool {
            e.name.lowercased().hasPrefix(q) || (e.ticker?.lowercased().hasPrefix(q) ?? false)
        }
        return found.filter(direct) + found.filter { !direct($0) }
    }
}
