import Foundation
import SwiftData

/// The cross-source cluster derivations — what's left of the old Home board
/// composer after the Pinned board retired (2026-07-20, docs/agent-brief.md
/// rulings 11-12). The board's own composition (`compose`/`daily`,
/// `appendPinnedApps`, `appendWalletHoldings`, the cover, `awayLine`,
/// `boardSources`) is gone; the agent's `KeptAskComposers` reimplements the
/// away-window read independently now (the same parallel-reads pattern this
/// file and `RootShell` always used with each other, not a shared private
/// helper). What survives are the two derivations that outlived the board:
/// `projectClusters` (the tag-clustering the Themes treemap draws from,
/// `FeedScreen`'s own top-of-feed card since 2026-07-18) and `themesDocument`
/// itself, plus `MCPTools`'s week-synthesis tool, which reads
/// `projectClusters` directly.
enum HomeComposition {

    struct Cluster {
        let name: String
        let things: [Thing]
    }

    /// Until tags form, the map speaks in APPS: real things clustered by
    /// source (min 2, "You" included). Honest for a fresh corpus — bridge
    /// things arrive untagged, and a real user's Home earned no map at all.
    static func sourceClusters(things: [Thing]) -> [Cluster] {
        var buckets: [String: [Thing]] = [:]
        // `where thing.isLive` — this is called from a view body with a
        // caller-derived array, so a delete can land between the derive and
        // this loop. Guarding the SHARED helper covers every caller, which is
        // the half of corollary 2 that was written down and never enforced.
        for thing in things where thing.isLive {
            buckets[thing.source, default: []].append(thing)
        }
        return buckets
            .filter { $0.value.count >= 2 }
            .map { Cluster(name: $0.key, things: $0.value) }
            .sorted {
                $0.things.count != $1.things.count
                    ? $0.things.count > $1.things.count
                    : $0.name < $1.name
            }
    }

    /// A project is a computed cluster; membership rides a tag (brief §3).
    static func projectClusters(things: [Thing]) -> [Cluster] {
        let typeTags = Set(ThingKind.allCases.map { $0.typeTag.lowercased() })
        var buckets: [String: [Thing]] = [:]
        // `where thing.isLive` — build 177's crash site exactly: the themes
        // treemap's lede read `thing.tags` off the All room's stale snapshot.
        for thing in things where thing.isLive {
            for tag in thing.tags where !typeTags.contains(tag.lowercased()) {
                buckets[tag, default: []].append(thing)
            }
        }
        return buckets
            .filter { $0.value.count >= 2 }
            .map { Cluster(name: $0.key, things: $0.value) }
            .sorted {
                // Magnitude, then name — stable. (Project pins died 2026-07-07.)
                $0.things.count != $1.things.count
                    ? $0.things.count > $1.things.count
                    : $0.name < $1.name
            }
    }

    /// The Themes treemap document — the cross-source overview that moved OFF
    /// Home to the top of the "All" feed (2026-07-18, user: "should it go on
    /// all?"): a cross-source view belongs on the cross-source feed, same
    /// split that already sent the Wallet treemap to the Wallet feed. Same
    /// TagMap component/sizing the wallet treemap draws (no `genSpan` pin, so
    /// it takes the renderer's own unconstrained size — answering "is it too
    /// large / same as the wallet one?": identically sized, since it's the
    /// same component). Nil when no project has clustered yet — same standard
    /// `projectClusters` always held (min 2 things sharing a real tag).
    static func themesDocument(things: [Thing]) -> [String]? {
        themesDocument(clusters: projectClusters(things: things))
    }

    /// Same doc, from clusters already computed — for a caller (FeedScreen's
    /// Themes lede, 2026-07-21) that also needs the cluster list itself for
    /// its collapsed-row summary and would otherwise call `projectClusters`
    /// a second time over the same things just to get it.
    static func themesDocument(clusters: [Cluster]) -> [String]? {
        guard !clusters.isEmpty else { return nil }
        let items = clusters.prefix(6).map { "\($0.name) \($0.things.count)" }
        return ["root = TagMap(\(q(String(localized: "Themes"))), null, [\(items.joined(separator: ", "))])"]
    }

    /// Quotes a string for the document; strips embedded quotes rather than
    /// escaping (the line grammar has no escape sequence).
    private static func q(_ s: String) -> String {
        // GenParser splits the whole document on "\n" per line (brief §5) —
        // a raw newline inside a value (a multi-line social post, Goal 3)
        // would fracture one doc line into several malformed ones. Collapse
        // to spaces, same "no escape sequence" treatment as embedded quotes.
        let flat = s.replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        return "\"\(flat.replacingOccurrences(of: "\"", with: ""))\""
    }
}
