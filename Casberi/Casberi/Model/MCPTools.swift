import Foundation
import SwiftData

/// The tool surface a Casberi MCP server exposes to outside clients (Claude,
/// Raycast, Claude Code) — the inverse of a bridge: a bridge pulls another app's
/// data IN; MCP hands the person's own things OUT to a client that asks. PRD §34.
///
/// This is the DURABLE core, built now while the transport is blocked. The
/// eventual server (Goal-3, after enrollment + M1 CloudKit sync) is a thin shell
/// over these functions — it reads the SYNCED copy of the corpus, not the phone
/// directly (strategy pivot 2026-07-06). No transport, pairing, or network lives
/// here yet; these are the three tools, operating on the local store, so the
/// logic is real and testable before the wire exists.
///
/// Honesty rails, same as the composer's Ask:
///   • READS (`searchThings`, `weekSynthesis`) return real things / real facts,
///     never invented — allowed whenever a connection is live.
///   • the WRITE (`saveThing`) never lands silently: it becomes an approval-thing
///     in Feed, and only the person's Approve tap commits it. This is the consent
///     rail the strategy pivot explicitly KEPT.
@MainActor
enum MCPTools {

    /// `sourceRef` marker on an approval-thing that carries a pending MCP save.
    /// Feed's Approve verb reads this to commit the real thing (FeedScreen).
    static let saveMarker = "mcp.save"

    // MARK: - Reads (no approval — reading your own things when a tool asks)

    /// `search_things(query, limit)` — the same scoring the composer's Ask uses
    /// (title 3× / tags 2× / content 1× + a freshness float). Returns real
    /// things, ranked; an empty query returns the most recent.
    static func searchThings(_ query: String, limit: Int = 10, context: ModelContext) -> [Thing] {
        var descriptor = FetchDescriptor<Thing>(sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        descriptor.fetchLimit = 500
        let all = (try? context.fetch(descriptor)) ?? []

        let stops: Set<String> = ["about", "my", "the", "a", "in", "from", "for", "of"]
        let terms = query.lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "? "))
            .split(separator: " ").map(String.init)
            .filter { !stops.contains($0) }
        guard !terms.isEmpty else { return Array(all.prefix(limit)) }

        return all.compactMap { thing -> (Thing, Double)? in
            let title = thing.title.lowercased()
            let tags = thing.tags.joined(separator: " ").lowercased()
            let content = thing.content.lowercased()
            var score = 0.0
            for term in terms {
                if title.contains(term) { score += 3 }
                if tags.contains(term) { score += 2 }
                if content.contains(term) { score += 1 }
            }
            guard score > 0 else { return nil }
            let age = Date.now.timeIntervalSince(thing.capturedAt)
            score += max(0, 1 - age / (7 * 86_400))
            return (thing, score)
        }
        .sorted { $0.1 > $1.1 }
        .prefix(limit)
        .map(\.0)
    }

    /// `week_synthesis()` — a plain-text summary of the week from the corpus.
    /// Deterministic and model-free on purpose: a tool must answer on any device,
    /// with or without Apple Intelligence, and never invent.
    static func weekSynthesis(context: ModelContext) -> String {
        var descriptor = FetchDescriptor<Thing>(sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        descriptor.fetchLimit = 1000
        let all = (try? context.fetch(descriptor)) ?? []
        let week = all.filter { $0.capturedAt > .now.addingTimeInterval(-7 * 86_400) }
        guard !week.isEmpty else { return "Nothing landed this week." }

        var parts = ["\(week.count) thing\(week.count == 1 ? "" : "s") this week"]
        if let top = HomeComposition.projectClusters(things: week).first {
            parts.append("\(top.name) led with \(top.things.count)")
        }
        let sources = Set(week.map(\.source))
        if sources.count > 1 { parts.append("across \(sources.count) apps") }
        return parts.joined(separator: "; ") + "."
    }

    // MARK: - Write (routes through consent — never silent)

    /// `save_thing(text, source, tags)` — does NOT commit. It creates an
    /// approval-thing carrying the payload and inserts it into the corpus, where
    /// it surfaces in Feed as "awaiting your call". The person's Approve tap is
    /// what commits the real thing (see FeedScreen `.approve`). Inline `#tags`
    /// ride in the stored text so the same capture path applies on commit.
    @discardableResult
    static func saveThing(text: String, from client: String, tags: [String] = [],
                          context: ModelContext) -> Thing {
        let payload = ([text] + tags.map { "#\($0)" }).joined(separator: " ")
        let preview = text.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? text
        let title = preview.count > 60 ? String(preview.prefix(60)) + "…" : preview

        let approval = Thing(
            kind: .approval,
            title: "Save: \(title)",
            content: payload,
            source: client,
            provenance: Provenance(app: client, agent: client),
            sourceRef: saveMarker
        )
        context.insert(approval)
        context.saveHonestly()
        return approval
    }
}
