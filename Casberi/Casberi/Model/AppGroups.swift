import Foundation

/// The All feed under app headers (prd §1103, user: "it's gorgeous today but
/// kind of all blends together" → "do A" → "we want it consistent" → "the
/// whole point is just to show most recent thing").
///
/// Inside each section every app gets a header, even one that brought a single
/// thing, and stands as its NEWEST thing: the header is the door to the rest,
/// as a fold's row was (§377), and nothing under it counts what it holds back
/// (§902). The apps are ordered by that newest thing, so a section still reads
/// top-down in time.
///
/// Pure over values (a row's id and source are handed in), so
/// `scripts/feed-groups-selftest.sh` compiles this file whole. `FeedScreen`
/// runs it AFTER the away split (`momentSplit`), which cuts by date and needs
/// the rows still in time order.
enum AppGroups {
    /// How many of an app's things stand under its header (user: "cap at 3
    /// yes, but really we could just cap it at 1").
    static let rowCap = 1

    struct Result<Row> {
        /// The sections, each app's rows gathered under it, capped.
        var groups: [(String, [Row])]
        /// Row id → app, for the row that opens each app's group; the feed
        /// draws the header before it, the way it draws a day opener.
        var heads: [String: String]
        /// The away section's day openers (§879), re-pointed at the first row
        /// of each day's first app.
        var days: [String: String]
    }

    /// `groups` and the rows inside them arrive newest first. Inside "Since you
    /// left" each day it spans (`momentDays`, row id → day label) groups on its
    /// own, so an app's two days never merge under one header.
    static func group<Row>(_ groups: [(String, [Row])],
                           momentDays: [String: String] = [:],
                           cap: Int = rowCap,
                           id: (Row) -> String,
                           source: (Row) -> String) -> Result<Row> {
        var out: [(String, [Row])] = []
        var heads: [String: String] = [:]
        var days: [String: String] = [:]
        for (label, rows) in groups {
            var segments: [[Row]] = []
            for row in rows {
                if segments.isEmpty || momentDays[id(row)] != nil { segments.append([]) }
                segments[segments.count - 1].append(row)
            }
            var regrouped: [Row] = []
            for segment in segments {
                var order: [String] = []
                var bySource: [String: [Row]] = [:]
                for row in segment {
                    let app = source(row)
                    if bySource[app] == nil { order.append(app) }
                    bySource[app, default: []].append(row)
                }
                let opener = segment.first.flatMap { momentDays[id($0)] }
                for (i, app) in order.enumerated() {
                    guard let members = bySource[app], let first = members.first else { continue }
                    heads[id(first)] = app
                    if i == 0, let opener { days[id(first)] = opener }
                    regrouped.append(contentsOf: members.prefix(max(cap, 1)))
                }
            }
            out.append((label, regrouped))
        }
        return Result(groups: out, heads: heads, days: days)
    }
}
