import Foundation

/// Home under category and app headers (prd §1103, §1152, user: "it's
/// gorgeous today but kind of all blends together" → "do A" → "we want it
/// consistent" → "the whole point is just to show most recent thing", then
/// "it looks smarter to be by category and also helps them understand the
/// app. and their day" → "C is best").
///
/// Home is today (§1136 item 7). Its rows are first sorted into CATEGORY
/// sections (`byCategory`), in the person's own category order — the one the
/// tray and Settings › Feed order read, so rearranging it moves Home too —
/// and then, inside each section, every app gets a header (`group`), even one
/// that brought a single thing, and stands as its NEWEST thing: the header is
/// the door to the rest, as a fold's row was (§377), and nothing under it
/// counts what it holds back (§902). The apps are ordered by that newest
/// thing, so a section still reads top-down in time.
///
/// Pure over values (a row's id, source and category are handed in), so
/// `scripts/feed-groups-selftest.sh` compiles this file whole.
enum AppGroups {
    /// How many of an app's things stand under its header (user: "cap at 3
    /// yes, but really we could just cap it at 1").
    static let rowCap = 1

    struct Result<Row> {
        /// The sections, each app's rows gathered under it, capped.
        var groups: [(String, [Row])]
        /// Row id → app, for the row that opens each app's group; the feed
        /// draws the header before it.
        var heads: [String: String]
    }

    /// `rows` arrive newest first and leave in sections, one per category, in
    /// `order` (prd §1152). A category `order` has never heard of follows it
    /// A–Z; a row with no category at all (`category` answers nil: a note of
    /// yours) goes last under `rest`. Rows keep their order inside a section,
    /// and a section with nothing in it is not drawn.
    static func byCategory<Row>(_ rows: [Row],
                                order: [String],
                                rest: String,
                                category: (Row) -> String?) -> [(String, [Row])] {
        var buckets: [String: [Row]] = [:]
        var loose: [Row] = []
        for row in rows {
            if let name = category(row) { buckets[name, default: []].append(row) }
            else { loose.append(row) }
        }
        let known = order.filter { buckets[$0] != nil }
        let unknown = buckets.keys.filter { !order.contains($0) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        var out = (known + unknown).map { ($0, buckets[$0] ?? []) }
        if !loose.isEmpty { out.append((rest, loose)) }
        return out
    }

    /// `groups` and the rows inside them arrive newest first.
    static func group<Row>(_ groups: [(String, [Row])],
                           cap: Int = rowCap,
                           id: (Row) -> String,
                           source: (Row) -> String) -> Result<Row> {
        var out: [(String, [Row])] = []
        var heads: [String: String] = [:]
        for (label, rows) in groups {
            var order: [String] = []
            var bySource: [String: [Row]] = [:]
            for row in rows {
                let app = source(row)
                if bySource[app] == nil { order.append(app) }
                bySource[app, default: []].append(row)
            }
            var regrouped: [Row] = []
            for app in order {
                guard let members = bySource[app], let first = members.first else { continue }
                heads[id(first)] = app
                regrouped.append(contentsOf: members.prefix(max(cap, 1)))
            }
            out.append((label, regrouped))
        }
        return Result(groups: out, heads: heads)
    }
}
